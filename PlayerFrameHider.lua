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
  hideAllActionBars = false,
  hideActionBar1 = false,
  hidePetBar = false,
  hideStanceBar = false,
  showActionBar1WhenSkyriding = false,
  hideBuffFrame = false,
  hideObjectiveTracker = false,
  objectiveHoverHideDelay = 3.0,
  buffHoverHideDelay = 5.0,
  playerHoverHideDelay = 3.0,
  hurtGraceSeconds = 3.0,
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
  hiddenAlpha = 0, -- player frame hidden opacity
  actionHiddenAlpha = 0,
  cooldownHiddenAlpha = 0,
  objectiveHiddenAlpha = 0,
  buffHiddenAlpha = 0,
}

-- =========================================================
-- Constants / State
-- =========================================================

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

  -- action bars
  actionBarsHooked = false,
  actionBarFrames = nil, -- list of { frame = Frame, kind = "bar1"|"multi"|"pet"|"stance" }
  actionBarHoverOverride = false,
  actionBarHoverHideTimer = nil,

  ActionBar1Frame = nil,
  PetActionBarFrame = nil,
  StanceBarFrame = nil,

  -- buff frame
  BuffFrame = nil,
  buffHooked = false,
  buffHoverOverride = false,
  buffHoverHideTimer = nil,
  buffChangeOverride = false,
  buffChangeHideTimer = nil,

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

local Apply

-- Utility helpers (implemented in Core/Util.lua)
local ClampHiddenAlpha = PFH.ClampHiddenAlpha
local ApplyDefault = PFH.ApplyDefault
local ApplyNumberDefault = PFH.ApplyNumberDefault

-- =========================================================
-- DB defaults / migration
-- =========================================================

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
  ApplyDefault("hideAllActionBars", D.hideAllActionBars)
  ApplyDefault("hideActionBar1", D.hideActionBar1)
  ApplyDefault("hidePetBar", D.hidePetBar)
  ApplyDefault("hideStanceBar", D.hideStanceBar)
  ApplyDefault("showActionBar1WhenSkyriding", D.showActionBar1WhenSkyriding)
  ApplyDefault("hideBuffFrame", D.hideBuffFrame)
  ApplyDefault("hideObjectiveTracker", D.hideObjectiveTracker)
  ApplyDefault("showObjectiveUpdates", D.showObjectiveUpdates)
  ApplyDefault("forceShowTrackerWhenSuperTracked", D.forceShowTrackerWhenSuperTracked)
  ApplyDefault("showCooldownManagerWhenActive", D.showCooldownManagerWhenActive)
  ApplyDefault("alwaysShowInInstance", D.alwaysShowInInstance)

  ApplyNumberDefault("objectiveHoverHideDelay", D.objectiveHoverHideDelay, 0)
  ApplyNumberDefault("buffHoverHideDelay", D.buffHoverHideDelay, 0)
  ApplyNumberDefault("playerHoverHideDelay", D.playerHoverHideDelay, 0)
  ApplyNumberDefault("hurtGraceSeconds", D.hurtGraceSeconds or 0, 0)
  ApplyNumberDefault("hiddenAlpha", D.hiddenAlpha, 0)
  PFH_DB.hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha)

  local defaultActionAlpha = PFH_DB.hiddenAlpha or D.hiddenAlpha or 0
  ApplyNumberDefault("actionHiddenAlpha", defaultActionAlpha, 0)
  PFH_DB.actionHiddenAlpha = ClampHiddenAlpha(PFH_DB.actionHiddenAlpha)

  local defaultWidgetAlpha = PFH_DB.hiddenAlpha or D.hiddenAlpha or 0
  ApplyNumberDefault("cooldownHiddenAlpha", defaultWidgetAlpha, 0)
  PFH_DB.cooldownHiddenAlpha = ClampHiddenAlpha(PFH_DB.cooldownHiddenAlpha)

  local defaultObjectiveAlpha = PFH_DB.hiddenAlpha or D.hiddenAlpha or 0
  ApplyNumberDefault("objectiveHiddenAlpha", defaultObjectiveAlpha, 0)
  PFH_DB.objectiveHiddenAlpha = ClampHiddenAlpha(PFH_DB.objectiveHiddenAlpha)

  local defaultBuffAlpha = PFH_DB.hiddenAlpha or D.hiddenAlpha or 0
  ApplyNumberDefault("buffHiddenAlpha", defaultBuffAlpha, 0)
  PFH_DB.buffHiddenAlpha = ClampHiddenAlpha(PFH_DB.buffHiddenAlpha)

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
  local seconds = tonumber(PFH_DB.hurtGraceSeconds) or PFH.DEFAULTS.hurtGraceSeconds or 0
  if seconds < 0 then seconds = 0 end
  state.hurtUntil = GetTime() + seconds
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

local function GetBuffHoverHideDelay()
  local v = PFH_DB.buffHoverHideDelay
  if type(v) ~= "number" then
    v = PFH.DEFAULTS.buffHoverHideDelay or 5.0
  end
  if v < 0 then v = 0 end
  return v
end

local function GetPlayerHoverHideDelay()
  local v = PFH_DB.playerHoverHideDelay
  if type(v) ~= "number" then
    v = PFH.DEFAULTS.playerHoverHideDelay or 3.0
  end
  if v < 0 then v = 0 end
  return v
end

local function IsSkyRidingLike()
  if not IsMounted then return false end
  local okMounted, mounted = pcall(IsMounted)
  if not okMounted or not mounted then
    return false
  end

  -- Prefer the real "Skyriding/Dragonriding" signals when available
  if C_PlayerInfo then
    if C_PlayerInfo.IsPlayerInSkyriding then
      local ok, v = pcall(C_PlayerInfo.IsPlayerInSkyriding)
      if ok then return v and true or false end
    end
    if C_PlayerInfo.IsPlayerInDragonriding then
      local ok, v = pcall(C_PlayerInfo.IsPlayerInDragonriding)
      if ok then return v and true or false end
    end
  end

  -- Fallback: only count if you're actually flying (prevents ground mounts in flyable areas)
  if IsFlying then
    local okFlying, flying = pcall(IsFlying)
    if okFlying and flying then
      return true
    end
  end

  return false
end

-- =========================================================
-- Buff frame helpers
-- =========================================================

local function GetBuffFrame()
  if state.BuffFrame and state.BuffFrame.GetAlpha then
    return state.BuffFrame
  end

  local frame = _G.BuffFrame or _G.BuffFrameContainer or _G.PlayerBuffFrame
  if frame and frame.GetAlpha then
    state.BuffFrame = frame
    return frame
  end

  return nil
end

local function IsWorldMapOpen()
  local map = _G.WorldMapFrame
  if map and map.IsShown and map:IsShown() then
    return true
  end
  return false
end

-- =========================================================
-- Action bar frame helpers
-- =========================================================

local function AddActionBarFrame(list, frame, kind)
  if not frame or not frame.GetAlpha or not frame.SetAlpha then
    return
  end
  list[#list + 1] = { frame = frame, kind = kind }
end

local function ResolveActionBarFrames()
  if state.actionBarFrames then
    return state.actionBarFrames
  end

  local frames = {}

  -- Primary action bar (Bar 1)
  -- Prefer the modern ActionBar1 container, fall back to older names.
  local bar1 = _G.ActionBar1 or _G.MainMenuBar or _G.MainActionBar
  if bar1 and bar1.GetAlpha then
    state.ActionBar1Frame = bar1
    AddActionBarFrame(frames, bar1, "bar1")
  end

  -- Common multi-bars (treated as a single "multi" kind)
  local multiNames = {
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
  }
  for _, name in ipairs(multiNames) do
    local f = _G[name]
    if f and f.GetAlpha then
      AddActionBarFrame(frames, f, "multi")
    end
  end

  -- Pet bar
  local pet = _G.PetActionBarFrame or _G.PetActionBar
  if pet and pet.GetAlpha then
    state.PetActionBarFrame = pet
    AddActionBarFrame(frames, pet, "pet")
  end

  -- Stance bar
  local stance = _G.StanceBarFrame or _G.StanceBar
  if stance and stance.GetAlpha then
    state.StanceBarFrame = stance
    AddActionBarFrame(frames, stance, "stance")
  end

  -- Individual buttons for broader coverage (helps both alpha-hide and hover).

  -- Action Bar 1 buttons
  for i = 1, 12 do
    local btn = _G["ActionButton" .. i]
    if btn and btn.GetAlpha and btn.SetAlpha then
      AddActionBarFrame(frames, btn, "bar1")
    end
  end

  -- Multi-bar buttons
  local multiButtonPrefixes = {
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarLeftButton",
    "MultiBarRightButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
  }
  for _, prefix in ipairs(multiButtonPrefixes) do
    for i = 1, 12 do
      local btn = _G[prefix .. i]
      if btn and btn.GetAlpha and btn.SetAlpha then
        AddActionBarFrame(frames, btn, "multi")
      end
    end
  end

  -- Pet action buttons
  for i = 1, 10 do
    local btn = _G["PetActionButton" .. i]
    if btn and btn.GetAlpha and btn.SetAlpha then
      AddActionBarFrame(frames, btn, "pet")
    end
  end

  -- Stance buttons
  for i = 1, 10 do
    local btn = _G["StanceButton" .. i]
    if btn and btn.GetAlpha and btn.SetAlpha then
      AddActionBarFrame(frames, btn, "stance")
    end
  end

  if #frames == 0 then
    frames = nil
  end

  state.actionBarFrames = frames
  return frames
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
local function ResolveWidgetFramesWithRetries()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.5, function()
    tries = tries + 1
    if PFH.ResolveWidgetFramesOnce then
      PFH.ResolveWidgetFramesOnce()
    end

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

local function ShouldShowBuffFrame()
  if not PFH_DB.enabled then
    return true
  end

  if IsAlwaysShowInstance() then
    return true
  end

  if not PFH_DB.hideBuffFrame then
    return true
  end

  if state.buffHoverOverride then
    return true
  end

  if state.buffChangeOverride then
    return true
  end

  return false
end

local function AnyActionBarHideEnabled()
  return PFH_DB.hideAllActionBars
    or PFH_DB.hideActionBar1
    or PFH_DB.hidePetBar
    or PFH_DB.hideStanceBar
end

local function ShouldShowActionBar1()
  if not PFH_DB.enabled then
    return true
  end
  -- Base hide flag for Bar 1 (independent of global hideAllActionBars).
  local hideThis = PFH_DB.hideActionBar1 and true or false

  -- When skyriding and the option is enabled, temporarily treat Bar 1
  -- as not hidden so it behaves like a normal, always-visible bar.
  if hideThis and PFH_DB.showActionBar1WhenSkyriding and IsSkyRidingLike() then
    hideThis = false
  end

  -- If we're not hiding this bar via settings, always show it.
  if not hideThis then
    return true
  end

  -- When Bar 1 is configured as hidden, only show it while the
  -- action-bar hover override is active (mouse over bar/buttons).
  if PFH_DB.hoverRevealOutOfCombat and state.actionBarHoverOverride then
    return true
  end

  return false
end

local function ShouldShowPetBar()
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB.hidePetBar and true or false

  if not hideThis then
    return true
  end

  if PFH_DB.hoverRevealOutOfCombat and state.actionBarHoverOverride then
    return true
  end

  return false
end

local function ShouldShowStanceBar()
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB.hideStanceBar and true or false

  if not hideThis then
    return true
  end

  if PFH_DB.hoverRevealOutOfCombat and state.actionBarHoverOverride then
    return true
  end

  return false
end

local function ShouldShowMultiActionBars()
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB.hideAllActionBars and true or false

  if not hideThis then
    return true
  end

  if PFH_DB.hoverRevealOutOfCombat and state.actionBarHoverOverride then
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
-- Buff frame init & update hooks
-- =========================================================

local function OnBuffFrameEnter()
  if not PFH_DB.enabled then return end
  if not PFH_DB.hideBuffFrame then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end
  if IsInCombat() then return end

  if state.buffHoverHideTimer then
    state.buffHoverHideTimer:Cancel()
    state.buffHoverHideTimer = nil
  end

  state.buffHoverOverride = true
  Apply()
end

local function OnBuffFrameLeave()
  if not PFH_DB.hideBuffFrame then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end

  if state.buffHoverHideTimer then
    state.buffHoverHideTimer:Cancel()
    state.buffHoverHideTimer = nil
  end

  local delay = GetBuffHoverHideDelay()

  if delay <= 0 then
    state.buffHoverOverride = false
    Apply()
    return
  end

  state.buffHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.buffHoverHideTimer = nil
    if not PFH_DB.hoverRevealOutOfCombat then return end
    if IsInCombat() then return end
    state.buffHoverOverride = false
    Apply()
  end)
end

local function HookBuffFrameOnce()
  if state.buffHooked then return end

  local frame = GetBuffFrame()
  if not frame or not frame.HookScript then return end

  state.buffHooked = true
  state.BuffFrame = frame

  if frame.EnableMouse then
    frame:EnableMouse(true)
  end

  frame:HookScript("OnEnter", OnBuffFrameEnter)
  frame:HookScript("OnLeave", OnBuffFrameLeave)

  Apply()
end

local function OnBuffsUpdated()
  if not PFH_DB.enabled then return end
  if not PFH_DB.hideBuffFrame then return end

  if state.buffChangeHideTimer then
    state.buffChangeHideTimer:Cancel()
    state.buffChangeHideTimer = nil
  end

  state.buffChangeOverride = true
  Apply()

  local delay = GetBuffHoverHideDelay()
  if delay <= 0 then return end

  state.buffChangeHideTimer = C_Timer.NewTimer(delay, function()
    state.buffChangeHideTimer = nil
    if not PFH_DB.hideBuffFrame then return end
    state.buffChangeOverride = false
    Apply()
  end)
end

local function InitBuffFrame()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.2, function()
    tries = tries + 1

    if GetBuffFrame() then
      HookBuffFrameOnce()
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

local function SetBuffFrameVisible(wantVisible)
  local frame = GetBuffFrame()
  if not frame then return end

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.buffHiddenAlpha or PFH_DB.hiddenAlpha or 0)

  if wantVisible then
    if frame:GetAlpha() ~= 1 then frame:SetAlpha(1) end
  else
    if frame:GetAlpha() ~= hiddenAlpha then frame:SetAlpha(hiddenAlpha) end
  end
end

local function SetSimpleFrameVisible(frame, wantVisible)
  if not frame or not frame.GetAlpha or not frame.SetAlpha then return end

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.actionHiddenAlpha or PFH_DB.hiddenAlpha or 0)

  if wantVisible then
    if frame:GetAlpha() ~= 1 then
      frame:SetAlpha(1)
    end
  else
    if frame:GetAlpha() ~= hiddenAlpha then
      frame:SetAlpha(hiddenAlpha)
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

  local delay = GetPlayerHoverHideDelay()

  if delay <= 0 then
    state.hoverOverride = false
    Apply()
    return
  end

  state.hoverHideTimer = C_Timer.NewTimer(delay, function()
    state.hoverHideTimer = nil
    if not PFH_DB.hoverRevealOutOfCombat then return end
    if IsInCombat() then return end
    state.hoverOverride = false
    Apply()
  end)
end

local function OnActionBarEnter()
  if not PFH_DB.enabled then return end
  if not AnyActionBarHideEnabled() then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end

  if state.actionBarHoverHideTimer then
    state.actionBarHoverHideTimer:Cancel()
    state.actionBarHoverHideTimer = nil
  end

  state.actionBarHoverOverride = true
  Apply()
end

local function OnActionBarLeave()
  if not AnyActionBarHideEnabled() then return end
  if not PFH_DB.hoverRevealOutOfCombat then return end

  if state.actionBarHoverHideTimer then
    state.actionBarHoverHideTimer:Cancel()
    state.actionBarHoverHideTimer = nil
  end

  local delay = GetPlayerHoverHideDelay()

  if delay <= 0 then
    state.actionBarHoverOverride = false
    Apply()
    return
  end

  state.actionBarHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.actionBarHoverHideTimer = nil
    if not PFH_DB.hoverRevealOutOfCombat then return end
    state.actionBarHoverOverride = false
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

local function ApplyActionBars()
  local frames = ResolveActionBarFrames()
  if not frames then
    return
  end

  if not AnyActionBarHideEnabled() then
    -- Ensure all known action bars are fully visible.
    for _, info in ipairs(frames) do
      SetSimpleFrameVisible(info.frame, true)
    end
    return
  end

  for _, info in ipairs(frames) do
    local wantVisible = true
    if info.kind == "bar1" then
      wantVisible = ShouldShowActionBar1()
    elseif info.kind == "pet" then
      wantVisible = ShouldShowPetBar()
    elseif info.kind == "stance" then
      wantVisible = ShouldShowStanceBar()
    else
      wantVisible = ShouldShowMultiActionBars()
    end
    SetSimpleFrameVisible(info.frame, wantVisible)
  end
end

-- =========================================================
-- Core apply
-- =========================================================

Apply = function()
  if not PlayerFrame then return end

  SetPlayerFrameVisible(ShouldShowPlayerFrame())
  SetObjectiveTrackerVisible(ShouldShowObjectiveTracker())
  SetBuffFrameVisible(ShouldShowBuffFrame())
  ApplyActionBars()

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

  -- Hook hover for action bars, pet bar, and stance bar to support
  -- alpha-hide with hover reveal.
  local frames = ResolveActionBarFrames()
  if frames then
    for _, info in ipairs(frames) do
      local f = info.frame
      if f and f.HookScript and not f.PFH_ActionBarHooked then
        f.PFH_ActionBarHooked = true
        local objType = f.GetObjectType and f:GetObjectType() or nil

        -- For container/background frames, ensure they can see hover
        -- without interfering with button clicks. For actual buttons,
        -- leave mouse settings alone so Blizzard click handling works.
        if objType ~= "Button" and objType ~= "CheckButton" then
          if f.EnableMouse then
            f:EnableMouse(true)
          end
          if f.SetMouseMotionEnabled then
            f:SetMouseMotionEnabled(true)
          end
        end
        pcall(f.HookScript, f, "OnEnter", OnActionBarEnter)
        pcall(f.HookScript, f, "OnLeave", OnActionBarLeave)
      end
    end
  end

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
PFH.ShouldShowBuffFrame = ShouldShowBuffFrame
PFH.ShouldShowActionBar1 = ShouldShowActionBar1
PFH.ShouldShowPetBar = ShouldShowPetBar
PFH.ShouldShowStanceBar = ShouldShowStanceBar
PFH.ShouldShowMultiActionBars = ShouldShowMultiActionBars

PFH.ResolveWidgetFramesWithRetries = ResolveWidgetFramesWithRetries
PFH.NeedWidgets = NeedWidgets
PFH.HaveRequiredWidgets = HaveRequiredWidgets
PFH.ResolveActionBarFramesOnce = ResolveActionBarFrames

PFH.SetPlayerFrameVisible = SetPlayerFrameVisible
PFH.SetBuffFrameVisible = SetBuffFrameVisible
PFH.ApplyWidget = ApplyWidget
PFH.Apply = Apply

PFH.HookOnce = HookOnce
PFH.InitPlayerFrame = InitPlayerFrame
PFH.SetObjectiveTrackerVisible = SetObjectiveTrackerVisible
PFH.ShouldShowObjectiveTracker = ShouldShowObjectiveTracker
PFH.InitObjectiveFrame = InitObjectiveFrame
PFH.OnObjectiveUpdated = OnObjectiveUpdated
PFH.InitWorldMapHooks = InitWorldMapHooks
PFH.InitBuffFrame = InitBuffFrame
PFH.OnBuffsUpdated = OnBuffsUpdated

PFH.CancelHold = CancelHold
PFH.ScheduleHold = ScheduleHold
