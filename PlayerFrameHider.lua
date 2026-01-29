-- PlayerFrameHider

local ADDON_NAME = ...
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local eventFrame = CreateFrame("Frame")

PFH_DB = PFH_DB or {}

-- ---------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------

local DEFAULTS = {
  enabled = true,
  hidePlayerFrame = true,
  showInCombat = true,
  showIfTarget = true,
  showWhenHealthBelow100 = true,
  controlEssentialCooldowns = false,
  controlUtilityCooldowns = false,
  controlTrackedBuffs = false,
  alwaysShowInInstance = true,
  hiddenAlpha = 0,
}

-- =========================================================
-- Constants / State
-- =========================================================
local OPTION_PANEL_NAME = "Player Frame Hider"
local HURT_GRACE_SECONDS = 3

local state = {
  inCombat = false,

  -- grace window after health-related events
  hurtUntil = 0,
  hurtTicker = nil,

  -- init / hooks
  hooked = false,
  optionsCreated = false,
  optionsCategory = nil,
  loadMessageShown = false,
  didInit = false, -- guards double init between LOGIN / ENTERING_WORLD

  -- alpha-hidden tracking (combat-safe)
  playerFrameHidden = false,

  -- widget frames
  EssentialCDFrame = nil,
  UtilityCDFrame = nil,
  TrackedBuffsFrame = nil,
}

-- =========================================================
-- DB defaults / migration
-- =========================================================
local function ApplyDefaults()
  -- master enable
  if PFH_DB.enabled == nil then
    PFH_DB.enabled = DEFAULTS.enabled
  end

  -- migrate old hideOutOfCombat -> hidePlayerFrame
  if PFH_DB.hidePlayerFrame == nil then
    if PFH_DB.hideOutOfCombat ~= nil then
      PFH_DB.hidePlayerFrame = PFH_DB.hideOutOfCombat and true or false
    else
      PFH_DB.hidePlayerFrame = DEFAULTS.hidePlayerFrame
    end
  end

  if PFH_DB.showInCombat == nil then PFH_DB.showInCombat = DEFAULTS.showInCombat end
  if PFH_DB.showIfTarget == nil then PFH_DB.showIfTarget = DEFAULTS.showIfTarget end
  if PFH_DB.showWhenHealthBelow100 == nil then PFH_DB.showWhenHealthBelow100 = DEFAULTS.showWhenHealthBelow100 end

  if PFH_DB.controlEssentialCooldowns == nil then PFH_DB.controlEssentialCooldowns = DEFAULTS.controlEssentialCooldowns end
  if PFH_DB.controlUtilityCooldowns == nil then PFH_DB.controlUtilityCooldowns = DEFAULTS.controlUtilityCooldowns end
  if PFH_DB.controlTrackedBuffs == nil then PFH_DB.controlTrackedBuffs = DEFAULTS.controlTrackedBuffs end

  if PFH_DB.alwaysShowInInstance == nil then PFH_DB.alwaysShowInInstance = DEFAULTS.alwaysShowInInstance end

  if PFH_DB.hiddenAlpha == nil then PFH_DB.hiddenAlpha = DEFAULTS.hiddenAlpha end

  -- sanity-clamp alpha
  if type(PFH_DB.hiddenAlpha) ~= "number" then
    PFH_DB.hiddenAlpha = 0
  elseif PFH_DB.hiddenAlpha < 0 then
    PFH_DB.hiddenAlpha = 0
  elseif PFH_DB.hiddenAlpha > 1 then
    PFH_DB.hiddenAlpha = 1
  end
end

-- =========================================================
-- Helpers
-- =========================================================
local function MarkHurt()
  state.hurtUntil = GetTime() + HURT_GRACE_SECONDS
end

local function IsAlwaysShowInstance()
  if not PFH_DB.alwaysShowInInstance then return false end
  local inInstance, instanceType = IsInInstance()
  if not inInstance then return false end

  return instanceType == "party"
    or instanceType == "raid"
    or instanceType == "pvp"
    or instanceType == "arena"
    or instanceType == "scenario"
    or instanceType == "delve"
end

local function IsInCombat()
  return state.inCombat or (UnitAffectingCombat("player") and true or false)
end

local function HasEnemyTarget()
  return UnitExists("target") and UnitCanAttack("player", "target")
end

local function ShouldShowPlayerFrame()
  if PFH_DB.enabled == false then
    return true -- addon disabled => do not hide anything
  end

  if IsAlwaysShowInstance() then return true end

  -- if not hiding at all, always show
  if not PFH_DB.hidePlayerFrame then return true end

  if PFH_DB.showInCombat and IsInCombat() then return true end
  if PFH_DB.showIfTarget and UnitExists("target") then return true end
  if PFH_DB.showWhenHealthBelow100 and GetTime() < state.hurtUntil then return true end

  return false
end

local function ShouldShowWidgets()
  if PFH_DB.enabled == false then
    return true -- addon disabled => do not hide widgets
  end

  if IsAlwaysShowInstance() then return true end
  return IsInCombat() or HasEnemyTarget()
end

-- =========================================================
-- Frame resolution (Edit Mode widgets)
-- =========================================================
local function FindFrameByNameHint(hint)
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "table" and v.GetObjectType and v.IsShown then
      if k:find(hint, 1, true) then
        return v
      end
    end
  end
  return nil
end

local function ResolveWidgetFramesOnce()
  state.EssentialCDFrame = state.EssentialCDFrame or _G.EssentialCooldownsFrame or FindFrameByNameHint("EssentialCooldown")
  state.UtilityCDFrame = state.UtilityCDFrame or _G.UtilityCooldownsFrame or _G.UtilityCooldownFrame or _G.UtilityCooldowns or FindFrameByNameHint("UtilityCooldown")
  state.TrackedBuffsFrame = state.TrackedBuffsFrame or _G.TrackedBuffsFrame or _G.TrackedBuffFrame or _G.TrackedBuffs or FindFrameByNameHint("BuffIconCooldownViewer")
end

local function NeedWidgets()
  return PFH_DB.controlEssentialCooldowns or PFH_DB.controlUtilityCooldowns or PFH_DB.controlTrackedBuffs
end

local function HaveRequiredWidgets()
  if not NeedWidgets() then return true end
  return ((not PFH_DB.controlEssentialCooldowns or state.EssentialCDFrame) and
          (not PFH_DB.controlUtilityCooldowns or state.UtilityCDFrame) and
          (not PFH_DB.controlTrackedBuffs or state.TrackedBuffsFrame))
end

-- forward declare
local Apply

local function ResolveWidgetFramesWithRetries()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.5, function()
    tries = tries + 1
    ResolveWidgetFramesOnce()

    Apply()

    if HaveRequiredWidgets() or tries >= 10 then
      ticker:Cancel()
    end
  end)
end

-- =========================================================
-- PlayerFrame visibility (combat-safe alpha)
-- =========================================================
local function SetPlayerFrameVisible(wantVisible)
  if not PlayerFrame then return end

  local inLockdown = InCombatLockdown()
  local hiddenAlpha = PFH_DB.hiddenAlpha

  if type(hiddenAlpha) ~= "number" then
    hiddenAlpha = 0
  elseif hiddenAlpha < 0 then
    hiddenAlpha = 0
  elseif hiddenAlpha > 1 then
    hiddenAlpha = 1
  end

  if wantVisible then
    state.playerFrameHidden = false
    if PlayerFrame:GetAlpha() ~= 1 then PlayerFrame:SetAlpha(1) end
    if not inLockdown then
      PlayerFrame:EnableMouse(true)
    end
  else
    state.playerFrameHidden = true
    if PlayerFrame:GetAlpha() ~= hiddenAlpha then PlayerFrame:SetAlpha(hiddenAlpha) end
    if not inLockdown then
      PlayerFrame:EnableMouse(false)
    end
  end
end

-- =========================================================
-- Widget visibility
-- =========================================================
local function ApplyWidget(frame, enabled)
  if not enabled or not frame then return end

  -- Never try to show/hide protected frames during combat.
  if InCombatLockdown() then return end

  local want = ShouldShowWidgets()

  if want then
    if not frame:IsShown() then pcall(frame.Show, frame) end
  else
    if frame:IsShown() then pcall(frame.Hide, frame) end
  end
end

-- =========================================================
-- Core apply
-- =========================================================
function Apply()
  if not PlayerFrame then return end

  SetPlayerFrameVisible(ShouldShowPlayerFrame())

  ApplyWidget(state.EssentialCDFrame, PFH_DB.controlEssentialCooldowns)
  ApplyWidget(state.UtilityCDFrame, PFH_DB.controlUtilityCooldowns)
  ApplyWidget(state.TrackedBuffsFrame, PFH_DB.controlTrackedBuffs)
end

-- =========================================================
-- Hurt ticker
-- =========================================================
local function StopHurtTicker()
  if state.hurtTicker then
    state.hurtTicker:Cancel()
    state.hurtTicker = nil
  end
end

local function EnsureHurtTicker()
  if state.hurtTicker then return end

  state.hurtTicker = C_Timer.NewTicker(0.2, function()
    Apply()

    local expired = GetTime() >= state.hurtUntil
    local disabled = not PFH_DB.showWhenHealthBelow100
    if expired or disabled then
      StopHurtTicker()
    end
  end)
end

-- =========================================================
-- Show veto hooks (prevents other UI code forcing Show())
-- =========================================================
local function VetoIfNeeded()
  if not PlayerFrame then return end
  if InCombatLockdown() then return end
  if ShouldShowPlayerFrame() then return end

  -- alpha-hide again if anything tried to show it
  SetPlayerFrameVisible(false)
end

local function HookOnce()
  if state.hooked or not PlayerFrame then return end
  state.hooked = true

  PlayerFrame:HookScript("OnShow", VetoIfNeeded)
  hooksecurefunc(PlayerFrame, "Show", VetoIfNeeded)
  hooksecurefunc(PlayerFrame, "SetShown", function(_, shown)
    if shown then VetoIfNeeded() end
  end)

  Apply()
end

local function InitPlayerFrame()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.2, function()
    tries = tries + 1
    if PlayerFrame then
      HookOnce()
      ticker:Cancel()
    elseif tries >= 50 then
      ticker:Cancel()
    end
  end)
end

-- =========================================================
-- Options UI (Blizzard-native vertical Settings layout)
-- =========================================================
local function OpenOptions()
  if Settings and Settings.OpenToCategory and state.optionsCategoryID then
    Settings.OpenToCategory(state.optionsCategoryID)
    return
  end

  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(OPTION_PANEL_NAME)
    InterfaceOptionsFrame_OpenToCategory(OPTION_PANEL_NAME)
  end
end

SLASH_PlayerFrameHider1 = "/pfh"
SLASH_PlayerFrameHider2 = "/playerframehider"
SlashCmdList["PlayerFrameHider"] = OpenOptions

local function CreateOptionsPanel()
  if state.optionsCreated then return end
  state.optionsCreated = true

  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end

  ApplyDefaults()

  local category, layout = Settings.RegisterVerticalLayoutCategory(OPTION_PANEL_NAME)
  state.optionsCategory = category
  Settings.RegisterAddOnCategory(category)

  local function VarTypeFor(v)
    if Settings.VarType then
      if type(v) == "boolean" then return Settings.VarType.Boolean end
      if type(v) == "number" then return Settings.VarType.Number end
    end
    return type(v) -- fallback
  end

  -- 12.0 signature (works on 120000):
  -- Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
  local function RegisterSetting(key, name, defaultValue)
    local ok, setting = pcall(Settings.RegisterAddOnSetting,
      category,
      key,         -- variable
      key,         -- variableKey
      PFH_DB,      -- variableTbl  (MUST be table)
      VarTypeFor(defaultValue),
      name,
      defaultValue
    )
    if ok and setting then return setting end

    -- If Blizzard changes it again, fail loudly with context
    error(("PlayerFrameHider: RegisterAddOnSetting failed for %s: %s"):format(key, tostring(setting)))
  end

  local function OnChangedFor(key, setting)
    if not (Settings.SetOnValueChangedCallback and setting and setting.GetValue) then return end
    Settings.SetOnValueChangedCallback(key, function()
      PFH_DB[key] = setting:GetValue()

      if key == "showWhenHealthBelow100" and not PFH_DB.showWhenHealthBelow100 then
        StopHurtTicker()
        state.hurtUntil = 0
      end

      ResolveWidgetFramesOnce()
      Apply()
    end)
  end

  local function CreateCheckboxControl(setting, tooltip)
    -- 120000: CreateCheckbox (NOT CreateCheckBox)
    if Settings.CreateCheckbox then
      return Settings.CreateCheckbox(category, setting, tooltip)
    end
    -- fallback name just in case
    if Settings.CreateCheckBox then
      return Settings.CreateCheckBox(category, setting, tooltip)
    end
  end

  local function AddCheckbox(key, name, tooltip)
    local defaultValue = DEFAULTS[key] and true or false
    local setting = RegisterSetting(key, name, defaultValue)
    OnChangedFor(key, setting)
    CreateCheckboxControl(setting, tooltip)
    return setting
  end

  local function AddSlider(key, name, tooltip, minValue, maxValue, step, defaultValue)
    local current = PFH_DB[key]
    if type(current) ~= "number" then current = 0 end
    if current < minValue then current = minValue end
    if current > maxValue then current = maxValue end
    PFH_DB[key] = current

    local default = defaultValue
    if type(default) ~= "number" then
      default = current
    end
    if default < minValue then default = minValue end
    if default > maxValue then default = maxValue end

    local setting = RegisterSetting(key, name, default)
    OnChangedFor(key, setting)

    if Settings.CreateSliderOptions and Settings.CreateSlider then
      local opts = Settings.CreateSliderOptions(minValue, maxValue, step)

      -- Show percentage on the right, even though the
      -- stored value is a 0-1 alpha.
      if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and MinimalSliderWithSteppersMixin.Label.Right and opts.SetLabelFormatter then
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
          if FormatPercentage then
            return FormatPercentage(value, true)
          else
            return string.format("%d%%", math.floor((value * 100) + 0.5))
          end
        end)
      end

      Settings.CreateSlider(category, setting, opts, tooltip)
    elseif Settings.CreateSlider then
      -- older signature fallback
      Settings.CreateSlider(category, setting, minValue, maxValue, step, tooltip)
    end

    return setting
  end

  local function AddHeader(text)
    if layout and type(layout.AddInitializer) == "function"
      and type(CreateSettingsListSectionHeaderInitializer) == "function" then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
  end

  AddCheckbox(
    "enabled",
    "Enable PlayerFrameHider",
    "Master toggle for all PlayerFrameHider behaviour."
  )

  AddCheckbox(
    "hidePlayerFrame",
    "Hide player frame",
    "Hide the Blizzard Player Frame by default. The options below control when it is shown again."
  )

  AddSlider(
    "hiddenAlpha",
    "Hidden alpha",
    "Opacity when hidden (0% = fully hidden, 100% = fully visible).",
    0, 1, 0.05, DEFAULTS.hiddenAlpha
  )

  AddCheckbox(
    "showInCombat",
    "Show in combat",
    "Show the Player Frame while you are in combat."
  )

  AddCheckbox(
    "showIfTarget",
    "Show with target",
    "Show the Player Frame when you have a target selected."
  )

  AddCheckbox(
    "showWhenHealthBelow100",
    "Show on health change",
    "Temporarily show the Player Frame after your health changes."
  )

  AddCheckbox(
    "alwaysShowInInstance",
    "Always show in instances",
    "Always show the player frame and widgets in dungeons, raids, PvP, scenarios, and delves."
  )

  AddHeader("Cooldowns and buffs")

  AddCheckbox(
    "controlEssentialCooldowns",
    "Manage Essential Cooldowns",
    "Hide out of combat. Shows in combat or with an attackable target.\n\nChanges require a UI reload."
  )

  AddCheckbox(
    "controlUtilityCooldowns",
    "Manage Utility Cooldowns",
    "Hide out of combat. Shows in combat or with an attackable target.\n\nChanges require a UI reload."
  )

  AddCheckbox(
    "controlTrackedBuffs",
    "Manage Tracked Buffs",
    "Hide out of combat. Shows in combat or with an attackable target.\n\nChanges require a UI reload."
  )

end

-- =========================================================
-- Events
-- =========================================================
local function OnLogin()
  if state.didInit then
    -- Still refresh combat flag and apply, but don't re-run init/setup.
    state.inCombat = UnitAffectingCombat("player") and true or false
    Apply()
    return
  end
  state.didInit = true

  ApplyDefaults()
  state.inCombat = UnitAffectingCombat("player") and true or false

  CreateOptionsPanel()
  InitPlayerFrame()
  ResolveWidgetFramesWithRetries()

  if not state.loadMessageShown then
    print("|cFF00FF00PlayerFrameHider:|r v" .. VERSION .. " Loaded. Use |cFFFFA500/pfh|r to open options.")
    state.loadMessageShown = true
  end

  Apply()
end

local function OnRegenDisabled()
  state.inCombat = true
  Apply()
end

local function OnRegenEnabled()
  state.inCombat = false
  Apply()
end

local function OnTargetOrZoneChanged()
  Apply()
end

local function OnPlayerHealthChanged(unit)
  if unit ~= "player" then return end
  if PFH_DB.showWhenHealthBelow100 then
    MarkHurt()
    EnsureHurtTicker()
  end
  Apply()
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")

eventFrame:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    OnLogin()
    return
  end

  HookOnce()

  if event == "PLAYER_REGEN_DISABLED" then
    OnRegenDisabled()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    OnRegenEnabled()
    return
  end

  if event == "PLAYER_TARGET_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
    OnTargetOrZoneChanged()
    return
  end

  if event == "UNIT_HEALTH"
    or event == "UNIT_MAXHEALTH"
    or event == "UNIT_ABSORB_AMOUNT_CHANGED"
    or event == "UNIT_HEAL_PREDICTION"
  then
    OnPlayerHealthChanged(unit)
  end
end)
