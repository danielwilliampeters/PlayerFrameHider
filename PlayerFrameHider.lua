-- PlayerFrameHider

local ADDON_NAME = ...
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local eventFrame = CreateFrame("Frame")

PFH_DB = PFH_DB or {}

-- =========================================================
-- Constants / State
-- =========================================================
local OPTION_PANEL_NAME = "PlayerFrameHider"
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
  -- migrate old hideOutOfCombat -> hidePlayerFrame
  if PFH_DB.hidePlayerFrame == nil then
    if PFH_DB.hideOutOfCombat ~= nil then
      PFH_DB.hidePlayerFrame = PFH_DB.hideOutOfCombat and true or false
    else
      PFH_DB.hidePlayerFrame = true
    end
  end

  if PFH_DB.showInCombat == nil then PFH_DB.showInCombat = true end
  if PFH_DB.showIfTarget == nil then PFH_DB.showIfTarget = true end
  if PFH_DB.showWhenHealthBelow100 == nil then PFH_DB.showWhenHealthBelow100 = true end

  if PFH_DB.controlEssentialCooldowns == nil then PFH_DB.controlEssentialCooldowns = false end
  if PFH_DB.controlUtilityCooldowns == nil then PFH_DB.controlUtilityCooldowns = false end
  if PFH_DB.controlTrackedBuffs == nil then PFH_DB.controlTrackedBuffs = false end

  if PFH_DB.alwaysShowInInstance == nil then PFH_DB.alwaysShowInInstance = true end
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
  if IsAlwaysShowInstance() then return true end

  -- if not hiding at all, always show
  if not PFH_DB.hidePlayerFrame then return true end

  if PFH_DB.showInCombat and IsInCombat() then return true end
  if PFH_DB.showIfTarget and UnitExists("target") then return true end
  if PFH_DB.showWhenHealthBelow100 and GetTime() < state.hurtUntil then return true end

  return false
end

local function ShouldShowWidgets()
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

  if wantVisible then
    if state.playerFrameHidden then
      state.playerFrameHidden = false
    end
    if PlayerFrame:GetAlpha() ~= 1 then PlayerFrame:SetAlpha(1) end
    PlayerFrame:EnableMouse(true)
  else
    if not state.playerFrameHidden then
      state.playerFrameHidden = true
    end
    if PlayerFrame:GetAlpha() ~= 0 then PlayerFrame:SetAlpha(0) end
    PlayerFrame:EnableMouse(false)
  end
end

-- =========================================================
-- Widget visibility
-- =========================================================
local function ApplyWidget(frame, enabled)
  if not enabled or not frame then return end

  local want = ShouldShowWidgets()

  -- in combat: avoid Hide() calls; allow Show() if needed
  if InCombatLockdown() then
    if want and not frame:IsShown() then pcall(frame.Show, frame) end
    return
  end

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
-- Options UI
-- =========================================================
local function OpenOptions()
  if Settings and Settings.OpenToCategory and state.optionsCategory then
    Settings.OpenToCategory(state.optionsCategory.ID)
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

  local function BuildPanel(panel)
    panel.name = OPTION_PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("PlayerFrameHider")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Control visibility of player frame and Edit Mode widgets")

    local function CreateSectionHeader(anchor, text, yOffset)
      local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
      header:SetText(text)
      header:SetTextColor(1, 0.82, 0)
      return header
    end

    local function CreateDescription(anchor, text, yOffset)
      local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      desc:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
      desc:SetText(text)
      desc:SetTextColor(0.7, 0.7, 0.7)
      desc:SetJustifyH("LEFT")
      desc:SetWidth(550)
      return desc
    end

    local function CreateCheckbox(anchor, label, key, yOffset)
      local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
      cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
      cb.Text:SetText(label)
      cb:SetChecked(PFH_DB[key])

      cb:SetScript("OnClick", function(self)
        PFH_DB[key] = self:GetChecked() and true or false
        ResolveWidgetFramesOnce()
        Apply()
      end)

      return cb
    end

    -- General
    local generalHeader = CreateSectionHeader(subtitle, "General Settings", -20)
    local generalDesc = CreateDescription(generalHeader, "Global behavior that applies in all views", -4)
    local cbInstance = CreateCheckbox(generalDesc, "Always show in dungeons/raids/battlegrounds/delves", "alwaysShowInInstance", -8)

    -- Player frame
    local pfHeader = CreateSectionHeader(cbInstance, "Player Frame Settings", -20)
    local pfDesc = CreateDescription(pfHeader, "Configure when the player frame should be visible", -4)

    local cbHide = CreateCheckbox(pfDesc, "Hide player frame", "hidePlayerFrame", -8)
    local cbCombat = CreateCheckbox(cbHide, "Show player frame in combat", "showInCombat", -4)
    local cbTarget = CreateCheckbox(cbCombat, "Show player frame if target", "showIfTarget", -4)
    local cbHealth = CreateCheckbox(cbTarget, "Show player frame when health below 100%", "showWhenHealthBelow100", -4)

    -- Widgets
    local wHeader = CreateSectionHeader(cbHealth, "Cooldowns settings", -20)
    local wDesc = CreateDescription(wHeader, "Hide cooldowns out of combat (they will show in combat or when you have a target)", -4)

    local cbE = CreateCheckbox(wDesc, "Control Essential Cooldowns visibility", "controlEssentialCooldowns", -8)
    local cbU = CreateCheckbox(cbE, "Control Utility Cooldowns visibility", "controlUtilityCooldowns", -4)
    local cbT = CreateCheckbox(cbU, "Control Tracked Buffs visibility", "controlTrackedBuffs", -4)

    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", cbT, "BOTTOMLEFT", -16, -16)
    separator:SetSize(560, 1)
    separator:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    local reloadNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reloadNote:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 16, -12)
    reloadNote:SetText("Note: Some changes may require a UI reload to take full effect")
    reloadNote:SetTextColor(1, 0.5, 0.25)

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(140, 22)
    btn:SetPoint("TOPLEFT", reloadNote, "BOTTOMLEFT", 0, -12)
    btn:SetText("Reload UI")
    btn:SetScript("OnClick", ReloadUI)

    panel:SetScript("OnShow", function()
      cbHide:SetChecked(PFH_DB.hidePlayerFrame)
      cbCombat:SetChecked(PFH_DB.showInCombat)
      cbTarget:SetChecked(PFH_DB.showIfTarget)
      cbHealth:SetChecked(PFH_DB.showWhenHealthBelow100)
      cbInstance:SetChecked(PFH_DB.alwaysShowInInstance)

      cbE:SetChecked(PFH_DB.controlEssentialCooldowns)
      cbU:SetChecked(PFH_DB.controlUtilityCooldowns)
      cbT:SetChecked(PFH_DB.controlTrackedBuffs)
    end)
  end

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local panel = CreateFrame("Frame")
    BuildPanel(panel)
    state.optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, OPTION_PANEL_NAME)
    Settings.RegisterAddOnCategory(state.optionsCategory)
    return
  end

  if InterfaceOptions_AddCategory then
    local panel = CreateFrame("Frame")
    BuildPanel(panel)
    InterfaceOptions_AddCategory(panel)
  end
end

-- =========================================================
-- Events
-- =========================================================
local function OnLogin()
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
