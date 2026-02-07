-- Player Frame Hider: Blizzard player frame hider addon (Retail)

local ADDON_NAME = ...
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- Shared namespace
PlayerFrameHider = PlayerFrameHider or {}
local PFH = PlayerFrameHider

PFH_DB = PFH_DB or {}

PFH.VERSION = VERSION
PFH.OPTION_PANEL_NAME = PFH.OPTION_PANEL_NAME or "Player Frame Hider"

-- ---------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------

PFH.DEFAULTS = {
  enabled = true,
  hidePlayerFrame = true,
  hideObjectiveTracker = false,
  objectiveHoverHideDelay = 3.0,
  showObjectiveUpdates = true,
  forceShowTrackerWhenSuperTracked = false,
  showInCombat = true,
  showIfTarget = true,
  showWhenHealthBelow100 = true,
  hoverRevealOutOfCombat = true,
  controlEssentialCooldowns = false,
  controlUtilityCooldowns = false,
  controlTrackedBuffs = false,
  cooldownDisplayMode = 0,
  alwaysShowInInstance = true,
  hiddenAlpha = 0,
}

-- =========================================================
-- Constants / State
-- =========================================================

local HURT_GRACE_SECONDS = 3

local function ClampHiddenAlpha(value)
  if type(value) ~= "number" then
    return 0
  elseif value < 0 then
    return 0
  elseif value > 1 then
    return 1
  end
  return value
end

PFH.state = PFH.state or {
  inCombat = false,

  -- grace window after health-related events
  hurtUntil = 0,
  hurtTicker = nil,

  -- init / hooks
  hooked = false,
  optionsCreated = false,
  optionsCategory = nil,
  optionsCategoryID = nil,
  loadMessageShown = false,
  didInit = false, -- guards double init between LOGIN / ENTERING_WORLD

  -- alpha-hidden tracking (combat-safe)
  playerFrameHidden = false,
  hoverOverride = false,

  -- hover hide delay
  hoverHideTimer = nil,

  -- objective tracker
  ObjectiveFrame = nil,
  objectiveHooked = false,
  objectiveHoverOverride = false,
  objectiveHoverHideTimer = nil,

  -- world map hooks
  worldMapHooked = false,

  -- widget frames
  EssentialCDFrame = nil,
  UtilityCDFrame = nil,
  TrackedBuffsFrame = nil,
}

local state = PFH.state

-- =========================================================
-- DB defaults / migration
-- =========================================================

-- Small helpers to keep ApplyDefaults readable
local function ApplyDefault(key, value)
  if PFH_DB[key] == nil then
    PFH_DB[key] = value
  end
end

local function ApplyNumberDefault(key, value, minValue)
  local v = PFH_DB[key]
  if type(v) ~= "number" then
    v = value
  end
  if minValue ~= nil and v < minValue then
    v = minValue
  end
  PFH_DB[key] = v
end

function PFH.ApplyDefaults()
  local D = PFH.DEFAULTS

  -- basic defaults
  ApplyDefault("enabled", D.enabled)
  ApplyDefault("showInCombat", D.showInCombat)
  ApplyDefault("showIfTarget", D.showIfTarget)
  ApplyDefault("showWhenHealthBelow100", D.showWhenHealthBelow100)
  ApplyDefault("hoverRevealOutOfCombat", D.hoverRevealOutOfCombat)
  ApplyDefault("hideObjectiveTracker", D.hideObjectiveTracker)
  ApplyDefault("showObjectiveUpdates", D.showObjectiveUpdates)
  ApplyDefault("forceShowTrackerWhenSuperTracked", D.forceShowTrackerWhenSuperTracked)
  ApplyDefault("alwaysShowInInstance", D.alwaysShowInInstance)

  ApplyNumberDefault("objectiveHoverHideDelay", D.objectiveHoverHideDelay, 0)
  ApplyNumberDefault("hiddenAlpha", D.hiddenAlpha, 0)
  PFH_DB.hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha)

  -- migrate old hideOutOfCombat -> hidePlayerFrame
  if PFH_DB.hidePlayerFrame == nil then
    if PFH_DB.hideOutOfCombat ~= nil then
      PFH_DB.hidePlayerFrame = PFH_DB.hideOutOfCombat and true or false
    else
      PFH_DB.hidePlayerFrame = D.hidePlayerFrame
    end
  end

  -- cooldown mode: seed once, then derive flags via SetCooldownMode
  if PFH_DB.cooldownDisplayMode == nil then
    PFH_DB.cooldownDisplayMode = D.cooldownDisplayMode or 0
  end
  PFH.SetCooldownMode(PFH_DB.cooldownDisplayMode)
end

-- =========================================================
-- Helpers
-- =========================================================

function PFH.SetCooldownMode(mode)
  local m = tonumber(mode) or 0
  if m < 0 then m = 0 elseif m > 3 then m = 3 end

  PFH_DB.cooldownDisplayMode = m

  -- keep the Settings mirror in sync too
  PFH_DB.PFH_cooldownDisplayMode = m

  -- derived flags (still used everywhere else)
  PFH_DB.controlEssentialCooldowns = (m >= 1)
  PFH_DB.controlUtilityCooldowns   = (m >= 2)
  PFH_DB.controlTrackedBuffs       = (m >= 3)
end

local function MarkHurt()
  state.hurtUntil = GetTime() + HURT_GRACE_SECONDS
end

local function IsRelevantInstance()
  local inInstance, instanceType = IsInInstance()
  if inInstance then
    if instanceType == "party"
      or instanceType == "raid"
      or instanceType == "pvp"
      or instanceType == "arena"
      or instanceType == "scenario"
      or instanceType == "delve" then
      return true
    end
  end

  if C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario() then
    return true
  end

  return false
end

local function IsAlwaysShowInstance()
  if not PFH_DB.alwaysShowInInstance then return false end
  return IsRelevantInstance()
end

local function IsInCombat()
  return state.inCombat or (UnitAffectingCombat("player") and true or false)
end

local function HasEnemyTarget()
  return UnitExists("target") and UnitCanAttack("player", "target")
end

local function ShouldShowPlayerFrame()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide anything
  end

  if IsAlwaysShowInstance() then return true end

  -- if not hiding at all, always show
  if not PFH_DB.hidePlayerFrame then return true end

  if PFH_DB.showInCombat and IsInCombat() then return true end
  if PFH_DB.showIfTarget and UnitExists("target") then return true end
  if PFH_DB.showWhenHealthBelow100 and GetTime() < state.hurtUntil then return true end

  if PFH_DB.hoverRevealOutOfCombat and state.hoverOverride and not IsInCombat() then
    return true
  end

  return false
end

local function ShouldShowWidgets()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide widgets
  end

  if IsAlwaysShowInstance() then return true end
  return IsInCombat() or HasEnemyTarget()
end

local function GetObjectiveHoverHideDelay()
  local v = PFH_DB.objectiveHoverHideDelay
  if type(v) ~= "number" then
    v = PFH.DEFAULTS.objectiveHoverHideDelay or 1.0
  end
  if v < 0 then v = 0 end
  return v
end

local function IsWorldMapOpen()
  local map = _G.WorldMapFrame
  if map and map.IsShown and map:IsShown() then
    return true
  end
  return false
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
-- Objective tracker visibility (hover reveal)
-- =========================================================

local function GetObjectiveFrame()
  if state.ObjectiveFrame and state.ObjectiveFrame.GetAlpha then
    return state.ObjectiveFrame
  end

  local frame = _G.ObjectiveTrackerFrame or _G.ObjectivesFrame or _G.QuestWatchFrame
  if frame and frame.GetAlpha then
    state.ObjectiveFrame = frame
    return frame
  end

  return nil
end

local function HasSuperTrackedQuest()
  if not C_SuperTrack or not C_SuperTrack.GetSuperTrackedQuestID then
    return false
  end

  local questID = C_SuperTrack.GetSuperTrackedQuestID()
  if not questID or questID == 0 then
    return false
  end

  return true
end

local function BaseShouldShowObjectiveTracker()
  if not PFH_DB.enabled then
    return true
  end

  if IsAlwaysShowInstance() then
    return true
  end

  -- Always show objectives when the world map is open so
  -- the quest list remains visible alongside the map.
  if IsWorldMapOpen() then
    return true
  end

  if not PFH_DB.hideObjectiveTracker then
    return true
  end

  if state.objectiveHoverOverride then
    return true
  end

  return false
end

local function ShouldShowObjectiveTracker()
  local show = BaseShouldShowObjectiveTracker()

  if show then
    return true
  end

  if PFH_DB.forceShowTrackerWhenSuperTracked and HasSuperTrackedQuest() then
    return true
  end

  return false
end

local function SetObjectiveTrackerVisible(wantVisible)
  local frame = GetObjectiveFrame()
  if not frame then return end

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha)

  if wantVisible then
    if frame:GetAlpha() ~= 1 then frame:SetAlpha(1) end
  else
    if frame:GetAlpha() ~= hiddenAlpha then frame:SetAlpha(hiddenAlpha) end
  end
end

local function OnObjectiveEnter()
  if not PFH_DB.enabled then return end
  if not PFH_DB.hideObjectiveTracker then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end

  if state.objectiveHoverHideTimer then
    state.objectiveHoverHideTimer:Cancel()
    state.objectiveHoverHideTimer = nil
  end

  state.objectiveHoverOverride = true
  Apply()
end

local function OnObjectiveLeave()
  if not PFH_DB.hideObjectiveTracker then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end

  if state.objectiveHoverHideTimer then
    state.objectiveHoverHideTimer:Cancel()
    state.objectiveHoverHideTimer = nil
  end

  local delay = GetObjectiveHoverHideDelay()

  state.objectiveHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.objectiveHoverHideTimer = nil
    if not PFH_DB.hideObjectiveTracker then return end
    state.objectiveHoverOverride = false
    Apply()
  end)
end

-- Triggered when the game updates objectives (quests, scenarios, etc.).
-- Briefly shows the objective tracker if it's being hidden by the addon.
local function OnObjectiveUpdated()
  if not PFH_DB.enabled then return end
  if not PFH_DB.hideObjectiveTracker then return end
  if not PFH_DB.showObjectiveUpdates then return end

  if state.objectiveHoverHideTimer then
    state.objectiveHoverHideTimer:Cancel()
    state.objectiveHoverHideTimer = nil
  end

  state.objectiveHoverOverride = true
  Apply()

  local delay = GetObjectiveHoverHideDelay()
  if delay <= 0 then return end

  state.objectiveHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.objectiveHoverHideTimer = nil
    if not PFH_DB.hideObjectiveTracker then return end
    state.objectiveHoverOverride = false
    Apply()
  end)
end

local function HookObjectiveOnce()
  if state.objectiveHooked then return end

  local frame = GetObjectiveFrame()
  if not frame then return end

  state.objectiveHooked = true
  state.ObjectiveFrame = frame

  if frame.SetHitRectInsets then
    local l, r, t, b = frame:GetHitRectInsets()
    l, r, t, b = l or 0, r or 0, t or 0, b or 0
    frame:SetHitRectInsets(l - 10, r + 10, t - 10, b + 10)
  end

  if frame.EnableMouse then
    frame:EnableMouse(true)
  end

  frame:HookScript("OnEnter", OnObjectiveEnter)
  frame:HookScript("OnLeave", OnObjectiveLeave)

  Apply()
end

local function InitObjectiveFrame()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.2, function()
    tries = tries + 1

    if GetObjectiveFrame() then
      HookObjectiveOnce()
      ticker:Cancel()
    elseif tries >= 50 then
      ticker:Cancel()
    end
  end)
end

-- =========================================================
-- World map hooks (keep objectives visible with map)
-- =========================================================

local function InitWorldMapHooks()
  if state.worldMapHooked then return end

  local map = _G.WorldMapFrame
  if not map or not map.HookScript then return end

  state.worldMapHooked = true

  map:HookScript("OnShow", function()
    Apply()
  end)

  map:HookScript("OnHide", function()
    Apply()
  end)
end

-- =========================================================
-- PlayerFrame visibility (combat-safe alpha)
-- =========================================================

local function SetPlayerFrameVisible(wantVisible)
  if not PlayerFrame then return end

  local inLockdown = InCombatLockdown()
  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha)

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
      if PFH_DB.hoverRevealOutOfCombat then
        PlayerFrame:EnableMouse(true)
      else
        PlayerFrame:EnableMouse(false)
      end
    end
  end
end

-- =========================================================
-- Hover reveal (out of combat)
-- =========================================================

local function OnPlayerFrameEnter()
  if not PFH_DB.enabled then return end
  if not PFH_DB.hidePlayerFrame then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end
  if IsInCombat() then return end
  if state.hoverHideTimer then
    state.hoverHideTimer:Cancel()
    state.hoverHideTimer = nil
  end
  state.hoverOverride = true
  Apply()
end

local function OnPlayerFrameLeave()
  if not PFH_DB.hoverRevealOutOfCombat then return end
  if state.hoverHideTimer then
    state.hoverHideTimer:Cancel()
    state.hoverHideTimer = nil
  end

  state.hoverHideTimer = C_Timer.NewTimer(3, function()
    state.hoverHideTimer = nil
    if not PFH_DB.hoverRevealOutOfCombat then return end
    if IsInCombat() then return end
    state.hoverOverride = false
    Apply()
  end)
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

  SetObjectiveTrackerVisible(ShouldShowObjectiveTracker())

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

  -- Slightly expand the clickable area so hovering over
  -- the health portion still counts as being over the frame.
  if PlayerFrame.SetHitRectInsets then
    local l, r, t, b = PlayerFrame:GetHitRectInsets()
    l, r, t, b = l or 0, r or 0, t or 0, b or 0
    PlayerFrame:SetHitRectInsets(l - 10, r - 10, t - 10, b - 10)
  end

  PlayerFrame:HookScript("OnEnter", OnPlayerFrameEnter)
  PlayerFrame:HookScript("OnLeave", OnPlayerFrameLeave)

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
-- API exposure for other modules
-- =========================================================

PFH.MarkHurt = MarkHurt
PFH.EnsureHurtTicker = EnsureHurtTicker
PFH.StopHurtTicker = StopHurtTicker

PFH.IsAlwaysShowInstance = IsAlwaysShowInstance
PFH.IsInCombat = IsInCombat
PFH.HasEnemyTarget = HasEnemyTarget
PFH.ShouldShowPlayerFrame = ShouldShowPlayerFrame
PFH.ShouldShowWidgets = ShouldShowWidgets

PFH.ResolveWidgetFramesOnce = ResolveWidgetFramesOnce
PFH.ResolveWidgetFramesWithRetries = ResolveWidgetFramesWithRetries
PFH.NeedWidgets = NeedWidgets
PFH.HaveRequiredWidgets = HaveRequiredWidgets

PFH.SetPlayerFrameVisible = SetPlayerFrameVisible
PFH.ApplyWidget = ApplyWidget
PFH.Apply = Apply

PFH.HookOnce = HookOnce
PFH.InitPlayerFrame = InitPlayerFrame
PFH.SetObjectiveTrackerVisible = SetObjectiveTrackerVisible
PFH.ShouldShowObjectiveTracker = ShouldShowObjectiveTracker
PFH.InitObjectiveFrame = InitObjectiveFrame
PFH.OnObjectiveUpdated = OnObjectiveUpdated
PFH.InitWorldMapHooks = InitWorldMapHooks
