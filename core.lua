local eventFrame = CreateFrame("Frame")

PFH_DB = PFH_DB or {}

local VERSION = "1.1.5"
local HURT_GRACE_SECONDS = 3
local OPTION_PANEL_NAME = "PlayerFrameHider"

local hurtUntil = 0
local hurtTicking = false
local hurtTicker
local hooked = false
local suppress = false
local loadMessageShown = false
local optionsCreated = false
local optionsCategory

local EssentialCDFrame
local UtilityCDFrame
local TrackedBuffsFrame

local function ApplyDefaults()
  if PFH_DB.hideOutOfCombat == nil then PFH_DB.hideOutOfCombat = true end
  if PFH_DB.showWhenHealthBelow100 == nil then PFH_DB.showWhenHealthBelow100 = true end
  if PFH_DB.controlEssentialCooldowns == nil then PFH_DB.controlEssentialCooldowns = false end
  if PFH_DB.controlUtilityCooldowns == nil then PFH_DB.controlUtilityCooldowns = false end
  if PFH_DB.controlTrackedBuffs == nil then PFH_DB.controlTrackedBuffs = false end
  if PFH_DB.alwaysShowInInstance == nil then PFH_DB.alwaysShowInInstance = true end
end

local function OpenOptions()
  if Settings and Settings.OpenToCategory and optionsCategory then
    Settings.OpenToCategory(optionsCategory.ID)
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
  EssentialCDFrame = EssentialCDFrame or _G.EssentialCooldownsFrame or FindFrameByNameHint("EssentialCooldown")
  UtilityCDFrame = UtilityCDFrame or _G.UtilityCooldownsFrame or _G.UtilityCooldownFrame or _G.UtilityCooldowns or FindFrameByNameHint("UtilityCooldown")
  TrackedBuffsFrame = TrackedBuffsFrame or _G.TrackedBuffsFrame or _G.TrackedBuffFrame or _G.TrackedBuffs or FindFrameByNameHint("BuffIconCooldownViewer")
end

local function ResolveWidgetFramesWithRetries()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.5, function()
    tries = tries + 1
    ResolveWidgetFramesOnce()

    local needAny = PFH_DB.controlEssentialCooldowns or PFH_DB.controlUtilityCooldowns or PFH_DB.controlTrackedBuffs
    local haveEnough = not needAny or 
      ((not PFH_DB.controlEssentialCooldowns or EssentialCDFrame) and
       (not PFH_DB.controlUtilityCooldowns or UtilityCDFrame) and
       (not PFH_DB.controlTrackedBuffs or TrackedBuffsFrame))

    Apply()

    if haveEnough or tries >= 10 then
      ticker:Cancel()
    end
  end)
end


local function CreateOptionsPanel()
  if optionsCreated then return end
  optionsCreated = true

  local function BuildPanel(panel)
    panel.name = OPTION_PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("PlayerFrameHider")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Control visibility of player frame and Edit Mode widgets")

    local function CreateSectionHeader(parent, text, yOffset)
      local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      header:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, yOffset)
      header:SetText(text)
      header:SetTextColor(1, 0.82, 0)
      return header
    end

    local function CreateDescription(parent, text, yOffset)
      local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      desc:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, yOffset)
      desc:SetText(text)
      desc:SetTextColor(0.7, 0.7, 0.7)
      desc:SetJustifyH("LEFT")
      desc:SetWidth(550)
      return desc
    end

    local function CreateCheckbox(parent, label, configKey, yOffset)
      local checkbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
      checkbox:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, yOffset)
      checkbox.Text:SetText(label)
      checkbox:SetChecked(PFH_DB[configKey])
      checkbox:SetScript("OnClick", function(self)
        PFH_DB[configKey] = self:GetChecked() and true or false
        ResolveWidgetFramesOnce()
        Apply()
      end)
      return checkbox
    end

    -- General settings
    local generalHeader = CreateSectionHeader(subtitle, "General Settings", -20)
    local generalDesc = CreateDescription(generalHeader, "Global behavior that applies in all views", -4)
    local cbInstance = CreateCheckbox(generalDesc, "Always show in dungeons/raids/battlegrounds/delves", "alwaysShowInInstance", -8)

    -- Player frame settings
    local playerFrameHeader = CreateSectionHeader(cbInstance, "Player Frame Settings", -20)
    local playerFrameDesc = CreateDescription(playerFrameHeader, "Configure when the player frame should be visible", -4)

    local cb1 = CreateCheckbox(playerFrameDesc, "Hide player frame out of combat", "hideOutOfCombat", -8)
    local cb2 = CreateCheckbox(cb1, "Show player frame when health below 100%", "showWhenHealthBelow100", -4)

    -- Cooldowns widgets
    local widgetsHeader = CreateSectionHeader(cb2, "Cooldowns settings", -20)
    local widgetsDesc = CreateDescription(widgetsHeader, "Hide cooldowns out of combat (they will show in combat or when you have a target)", -4)

    local cb3 = CreateCheckbox(widgetsDesc, "Control Essential Cooldowns visibility", "controlEssentialCooldowns", -8)
    local cb4 = CreateCheckbox(cb3, "Control Utility Cooldowns visibility", "controlUtilityCooldowns", -4)
    local cb5 = CreateCheckbox(cb4, "Control Tracked Buffs visibility", "controlTrackedBuffs", -4)

    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", cb5, "BOTTOMLEFT", -16, -16)
    separator:SetSize(560, 1)
    separator:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    local reloadNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reloadNote:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 16, -12)
    reloadNote:SetText("Note: Some changes may require a UI reload to take full effect")
    reloadNote:SetTextColor(1, 0.5, 0.25)

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(140, 28)
    btn:SetPoint("TOPLEFT", reloadNote, "BOTTOMLEFT", 0, -12)
    btn:SetText("Reload UI")
    btn:SetScript("OnClick", ReloadUI)

    panel:SetScript("OnShow", function()
      cb1:SetChecked(PFH_DB.hideOutOfCombat)
      cb2:SetChecked(PFH_DB.showWhenHealthBelow100)
      cbInstance:SetChecked(PFH_DB.alwaysShowInInstance)
      cb3:SetChecked(PFH_DB.controlEssentialCooldowns)
      cb4:SetChecked(PFH_DB.controlUtilityCooldowns)
      cb5:SetChecked(PFH_DB.controlTrackedBuffs)
    end)
  end

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local panel = CreateFrame("Frame")
    BuildPanel(panel)
    optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, OPTION_PANEL_NAME)
    Settings.RegisterAddOnCategory(optionsCategory)
    return
  end

  if InterfaceOptions_AddCategory then
    local panel = CreateFrame("Frame")
    BuildPanel(panel)
    InterfaceOptions_AddCategory(panel)
  end
end


local function MarkHurt()
  hurtUntil = GetTime() + HURT_GRACE_SECONDS
end

local function ShouldShowPlayerFrame()
  if PFH_DB.alwaysShowInInstance then
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" or instanceType == "scenario") then
      return true
    end
  end

  if InCombatLockdown() then return true end
  if not PFH_DB.hideOutOfCombat then return true end
  if UnitExists("target") then return true end
  if PFH_DB.showWhenHealthBelow100 and GetTime() < hurtUntil then return true end
  return false
end

local function ShouldShowWidgets()
  if PFH_DB.alwaysShowInInstance then
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" or instanceType == "scenario") then
      return true
    end
  end

  return InCombatLockdown() or (UnitExists("target") and UnitCanAttack("player", "target"))
end

local function ApplyWidget(frame, enabled)
  if not enabled or not frame then return end

  local want = ShouldShowWidgets()

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

function Apply()
  if not PlayerFrame then return end

  local showPlayer = ShouldShowPlayerFrame()
  if showPlayer then
    if not PlayerFrame:IsShown() then PlayerFrame:Show() end
  else
    if not InCombatLockdown() and PlayerFrame:IsShown() then PlayerFrame:Hide() end
  end

  ApplyWidget(EssentialCDFrame, PFH_DB.controlEssentialCooldowns)
  ApplyWidget(UtilityCDFrame, PFH_DB.controlUtilityCooldowns)
  ApplyWidget(TrackedBuffsFrame, PFH_DB.controlTrackedBuffs)
end

local function EnsureHurtTicker()
  if hurtTicking then return end
  hurtTicking = true

  hurtTicker = C_Timer.NewTicker(0.2, function()
    Apply()
    if GetTime() >= hurtUntil or not PFH_DB.showWhenHealthBelow100 then
      hurtTicker:Cancel()
      hurtTicking = false
    end
  end)
end

local function VetoIfNeeded()
  if suppress or not PlayerFrame then return end

  if not ShouldShowPlayerFrame() and not InCombatLockdown() then
    suppress = true
    PlayerFrame:Hide()
    suppress = false
  end
end

local function HookOnce()
  if hooked or not PlayerFrame then return end
  hooked = true

  PlayerFrame:HookScript("OnShow", VetoIfNeeded)
  hooksecurefunc(PlayerFrame, "Show", VetoIfNeeded)
  hooksecurefunc(PlayerFrame, "SetShown", function(_, shown)
    if shown then VetoIfNeeded() end
  end)

  Apply()
end

local function Init()
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
    ApplyDefaults()
    CreateOptionsPanel()
    Init()
    ResolveWidgetFramesWithRetries()

    if not loadMessageShown then
      print("|cFF00FF00PlayerFrameHider:|r v" .. VERSION .. " Loaded. Use |cFFFFA500/pfh|r to open options.")
      loadMessageShown = true
    end

    Apply()
    return
  end

  HookOnce()

  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
    Apply()
    return
  end

  if (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_PREDICTION") and unit == "player" then
    if PFH_DB.showWhenHealthBelow100 then
      MarkHurt()
      EnsureHurtTicker()
    end
    Apply()
  end
end)
