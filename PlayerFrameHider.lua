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
  combatHoldSeconds = 3,
  showTargetMode = 1,
  showWhenHealthBelow100 = true,
  hoverRevealOutOfCombat = true,
  controlEssentialCooldowns = false,
  controlUtilityCooldowns = false,
  controlTrackedBuffs = false,
  cooldownDisplayMode = 0,
  showCooldownManagerWhenActive = false,
  alwaysShowInInstance = true,
  hiddenAlpha = 0,              -- player frame hidden opacity
  cooldownHiddenAlpha = 0,      -- cooldown manager hidden opacity
  objectiveHiddenAlpha = 0,     -- objective tracker hidden opacity
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
 
  -- combat hold
  combatHoldPlayer = false,
  combatHoldWidgets = false,
  justLeftCombat = false,

  -- cooldown manager watcher
  cooldownWatcherTicker = nil,
  lastWidgetsShouldShow = nil,
}

local state = PFH.state

PFH.timers = PFH.timers or {}

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

  -- migrate legacy showIfTarget into showTargetMode before any defaults
  if PFH_DB.showTargetMode == nil then
    PFH_DB.showTargetMode = (PFH_DB.showIfTarget == true) and 1 or 0
  end

  -- basic defaults
  ApplyDefault("enabled", D.enabled)
  ApplyDefault("showInCombat", D.showInCombat)
  ApplyDefault("showTargetMode", D.showTargetMode)
  ApplyDefault("showWhenHealthBelow100", D.showWhenHealthBelow100)
  ApplyDefault("hoverRevealOutOfCombat", D.hoverRevealOutOfCombat)
  ApplyDefault("hideObjectiveTracker", D.hideObjectiveTracker)
  ApplyDefault("showObjectiveUpdates", D.showObjectiveUpdates)
  ApplyDefault("forceShowTrackerWhenSuperTracked", D.forceShowTrackerWhenSuperTracked)
  ApplyDefault("showCooldownManagerWhenActive", D.showCooldownManagerWhenActive)
  ApplyDefault("alwaysShowInInstance", D.alwaysShowInInstance)

  ApplyNumberDefault("objectiveHoverHideDelay", D.objectiveHoverHideDelay, 0)
  ApplyNumberDefault("hiddenAlpha", D.hiddenAlpha, 0)
  PFH_DB.hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha)

  local defaultWidgetAlpha = PFH_DB.hiddenAlpha or D.hiddenAlpha or 0
  ApplyNumberDefault("cooldownHiddenAlpha", defaultWidgetAlpha, 0)
  PFH_DB.cooldownHiddenAlpha = ClampHiddenAlpha(PFH_DB.cooldownHiddenAlpha)

  local defaultObjectiveAlpha = PFH_DB.hiddenAlpha or D.hiddenAlpha or 0
  ApplyNumberDefault("objectiveHiddenAlpha", defaultObjectiveAlpha, 0)
  PFH_DB.objectiveHiddenAlpha = ClampHiddenAlpha(PFH_DB.objectiveHiddenAlpha)

  ApplyNumberDefault("combatHoldSeconds", D.combatHoldSeconds or 0, 0)

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

local function HasTargetLike()
  local mode = tonumber(PFH_DB.showTargetMode) or 0

  if (mode == 1 or mode == 3) and UnitExists("target") then
    return true
  end

  if (mode == 2 or mode == 3) and UnitExists("softenemy") then
    return true
  end

  return false
end

local function ShouldShowPlayerFrame()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide anything
  end

  if IsAlwaysShowInstance() then return true end

  -- if not hiding at all, always show
  if not PFH_DB.hidePlayerFrame then return true end

  if PFH_DB.showInCombat and IsInCombat() then return true end
  if HasTargetLike() then return true end
  if PFH_DB.showWhenHealthBelow100 and GetTime() < state.hurtUntil then return true end

  if PFH_DB.hoverRevealOutOfCombat and state.hoverOverride and not IsInCombat() then
    return true
  end

  -- During a combat-hold window, keep the frame visible
  if state.combatHoldPlayer then
    return true
  end

  return false
end

local function GetItemCooldownFrame(item)
  if type(item) ~= "table" then return nil end

  -- Commonly-used cooldown frame fields
  local candidates = {
    item.cooldown,
    item.Cooldown,
    item.CooldownWidget,
    item.CooldownFrame,
  }

  for i = 1, #candidates do
    local cd = candidates[i]
    if cd and cd.GetCooldownTimes then
      return cd
    end
  end

  -- Fallback: scan children for a cooldown frame
  if item.GetChildren then
    local numChildren = select("#", item:GetChildren())
    for i = 1, numChildren do
      local child = select(i, item:GetChildren())
      if child and child.GetCooldownTimes then
        return child
      end
    end
  end

  return nil
end

local function PoolHasActiveCooldown(pool)
  if not pool or type(pool) ~= "table" then
    return false
  end

  local function ForEachActive(callback)
    if type(pool.EnumerateActive) == "function" then
      for item in pool:EnumerateActive() do
        if callback(item) then return true end
      end
    elseif type(pool.activeObjects) == "table" then
      for item in pairs(pool.activeObjects) do
        if callback(item) then return true end
      end
    end
    return false
  end

  return ForEachActive(function(item)
    if type(item) ~= "table" then
      return false
    end

    -- If we have a cooldown widget and it is currently shown,
    -- treat it as active without inspecting any secret/secure fields.
    local cd = GetItemCooldownFrame(item)
    if cd and cd.IsShown and cd:IsShown() then
      return true
    end

    return false
  end)
end

local function ViewerHasActiveCooldown(viewer)
  if not viewer or type(viewer) ~= "table" then return false end

  if PoolHasActiveCooldown(viewer.itemFramePool) then
    return true
  end

  if PoolHasActiveCooldown(viewer.pandemicIconPool) then
    return true
  end

  return false
end

local function AreWidgetsActive()
  if not PFH_DB.enabled then return false end
  if not PFH_DB.showCooldownManagerWhenActive then return false end
  if not (PFH_DB.controlEssentialCooldowns or PFH_DB.controlUtilityCooldowns or PFH_DB.controlTrackedBuffs) then
    return false
  end

  if PFH_DB.controlEssentialCooldowns and ViewerHasActiveCooldown(state.EssentialCDFrame) then
    return true
  end

  if PFH_DB.controlUtilityCooldowns and ViewerHasActiveCooldown(state.UtilityCDFrame) then
    return true
  end

  if PFH_DB.controlTrackedBuffs and ViewerHasActiveCooldown(state.TrackedBuffsFrame) then
    return true
  end

  return false
end

local function ShouldShowWidgets()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide widgets
  end

  if IsAlwaysShowInstance() then return true end

  if state.combatHoldWidgets then
    return true
  end

  -- Mirror player frame rules for target/soft-target visibility so that
  -- the "Show with Target" setting is respected for widgets as well.
  if IsInCombat() or HasTargetLike() then
    return true
  end

  -- Optionally show widgets whenever the Blizzard Cooldown Manager
  -- considers them active (e.g. when it has cooldowns to display)
  if AreWidgetsActive() then
    return true
  end

  return false
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
    if type(k) == "string" and type(v) == "table" then
      local ok, isMatch = pcall(function()
        -- Some global tables are forbidden/restricted and will error
        -- when indexed; wrap access in pcall so we can safely skip them.
        if v.GetObjectType and v.IsShown and k:find(hint, 1, true) then
          return true
        end
        return false
      end)

      if ok and isMatch then
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

  if not state.widgetFramesHooked then
    local function HookWidgetFrame(frame)
      if not frame or frame.PFH_WidgetHooked then return end

      frame.PFH_WidgetHooked = true

      if type(frame.HasScript) == "function" then
        if frame:HasScript("OnShow") and frame.HookScript then
          pcall(frame.HookScript, frame, "OnShow", Apply)
        end
        if frame:HasScript("OnHide") and frame.HookScript then
          pcall(frame.HookScript, frame, "OnHide", Apply)
        end
      end
    end

    HookWidgetFrame(state.EssentialCDFrame)
    HookWidgetFrame(state.UtilityCDFrame)
    HookWidgetFrame(state.TrackedBuffsFrame)

    if (state.EssentialCDFrame or state.UtilityCDFrame or state.TrackedBuffsFrame) then
      state.widgetFramesHooked = true
    end
  end
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

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.objectiveHiddenAlpha or PFH_DB.hiddenAlpha or 0)

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
  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha or 0)

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

local function SetViewerMouseEnabled(viewer, enabled)
  if not viewer or type(viewer) ~= "table" then return end

  local function ForEachActiveInPool(pool, callback)
    if not pool or type(pool) ~= "table" then return end

    if type(pool.EnumerateActive) == "function" then
      for item in pool:EnumerateActive() do
        callback(item)
      end
    elseif type(pool.activeObjects) == "table" then
      for item in pairs(pool.activeObjects) do
        callback(item)
      end
    end
  end

  local function SetMouseOnItem(item)
    if not item then return end
    if item.EnableMouse then
      item:EnableMouse(enabled)
    end
    if item.SetMouseClickEnabled then
      item:SetMouseClickEnabled(enabled)
    end
    if item.SetMouseMotionEnabled then
      item:SetMouseMotionEnabled(enabled)
    end
  end

  ForEachActiveInPool(viewer.itemFramePool, SetMouseOnItem)
  ForEachActiveInPool(viewer.pandemicIconPool, SetMouseOnItem)

  if viewer.EnableMouse then
    viewer:EnableMouse(enabled)
  end
end

local function SetWidgetVisible(frame, wantVisible)
  if not frame or not frame.SetAlpha then return end

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.cooldownHiddenAlpha or PFH_DB.hiddenAlpha or 0)

  if wantVisible then
    if frame:GetAlpha() ~= 1 then frame:SetAlpha(1) end
    if not InCombatLockdown() then
      SetViewerMouseEnabled(frame, true)
    end
  else
    if frame:GetAlpha() ~= hiddenAlpha then frame:SetAlpha(hiddenAlpha) end
    if hiddenAlpha < 0.99 and not InCombatLockdown() then
      SetViewerMouseEnabled(frame, false)
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

  local want = ShouldShowWidgets()
  SetWidgetVisible(frame, want)
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
-- Combat hold helpers
-- =========================================================

local timers = PFH.timers

local function CancelHold(which)
  if not timers then return end

  local t = timers[which]
  if t then
    t:Cancel()
    timers[which] = nil
  end

  if which == "player" then
    state.combatHoldPlayer = false
  elseif which == "widgets" then
    state.combatHoldWidgets = false
  end
end

local function ScheduleHold(which, seconds)
  local duration = tonumber(seconds) or 0
  if duration <= 0 then
    CancelHold(which)
    return
  end

  CancelHold(which)

  if which == "player" then
    state.combatHoldPlayer = true
  elseif which == "widgets" then
    state.combatHoldWidgets = true
  end

  if not timers then
    timers = {}
    PFH.timers = timers
  end

  timers[which] = C_Timer.NewTimer(duration, function()
    timers[which] = nil

    if which == "player" then
      state.combatHoldPlayer = false
    elseif which == "widgets" then
      state.combatHoldWidgets = false
    end

    Apply()
  end)
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
-- Cooldown manager watcher (polls for active cooldowns)
-- =========================================================

local function StopCooldownWatcher()
  if state.cooldownWatcherTicker then
    state.cooldownWatcherTicker:Cancel()
    state.cooldownWatcherTicker = nil
  end
end

local function EnsureCooldownWatcher()
  if state.cooldownWatcherTicker then return end
  if not PFH_DB.showCooldownManagerWhenActive then return end

  state.cooldownWatcherTicker = C_Timer.NewTicker(0.5, function()
    if not PFH_DB.showCooldownManagerWhenActive then
      StopCooldownWatcher()
      return
    end

    local shouldShow = ShouldShowWidgets()
    if state.lastWidgetsShouldShow == nil or state.lastWidgetsShouldShow ~= shouldShow then
      state.lastWidgetsShouldShow = shouldShow
      Apply()
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
    PlayerFrame:SetHitRectInsets(l - 10, r + 10, t - 10, b + 10)
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

PFH.EnsureCooldownWatcher = EnsureCooldownWatcher
PFH.StopCooldownWatcher = StopCooldownWatcher

PFH.IsAlwaysShowInstance = IsAlwaysShowInstance
PFH.IsInCombat = IsInCombat
PFH.HasEnemyTarget = HasEnemyTarget
PFH.HasTargetLike = HasTargetLike
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

PFH.CancelHold = CancelHold
PFH.ScheduleHold = ScheduleHold
