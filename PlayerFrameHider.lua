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
  playerFrameMode = 2, -- 0 = always show, 1 = hide, 2 = hide + health
  hideActionBar1 = false,
  hideActionBar2 = false,
  hideActionBar3 = false,
  hideActionBar4 = false,
  hideActionBar5 = false,
  hideActionBar6 = false,
  hideActionBar7 = false,
  hideActionBar8 = false,
  hidePetBar = false,
  hideStanceBar = false,
  hideBagsBar = false,
  hideMicroMenu = false,
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
  petFrameMode = 2, -- 0 = always show, 1 = hide, 2 = auto (health)
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
  objectiveHoverReveal = true,
  buffHoverReveal = true,
  actionBarHoverReveal = true,
  hideDamageMeter = false,
  showDamageMeterInCombat = false,
}

-- =========================================================
-- Constants / State
-- =========================================================

PFH.state = PFH.state or {
  inCombat = false,

  -- grace window after health-related events
  hurtUntil = 0,
  hurtPlayerUntil = 0,
  hurtPetUntil = 0,
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

  -- independent hover overrides for bags bar and micro menu
  bagsHoverOverride = false,
  bagsHoverHideTimer = nil,
  microHoverOverride = false,
  microHoverHideTimer = nil,

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

  -- damage meter
  DamageMeterFrame = nil,
  damageMeterHooked = false,
  damageMeterHoverOverride = false,
  damageMeterHoverHideTimer = nil,

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
local NormalizeSeconds = PFH.NormalizeSeconds

-- =========================================================
-- DB defaults / migration
-- =========================================================

function PFH.ApplyDefaults()
  local D = PFH.DEFAULTS

  -- migrate legacy showIfTarget into showTargetMode before any defaults
  if PFH_DB.showTargetMode == nil then
    if PFH_DB.showIfTarget ~= nil then
      PFH_DB.showTargetMode = (PFH_DB.showIfTarget == true) and 1 or 0
    else
      PFH_DB.showTargetMode = D.showTargetMode
    end
  end

  -- migrate legacy showCooldownManagerWhenActive: always force it off if it
  -- was previously enabled. This keeps the feature effectively disabled in
  -- newer versions, even for older profiles.
  if PFH_DB.showCooldownManagerWhenActive == true then
    PFH_DB.showCooldownManagerWhenActive = false
  end

  -- basic defaults
  ApplyDefault("enabled", D.enabled)
  ApplyDefault("showInCombat", D.showInCombat)
  ApplyDefault("showTargetMode", D.showTargetMode)
  ApplyDefault("petFrameMode", D.petFrameMode)
  ApplyDefault("hoverRevealOutOfCombat", D.hoverRevealOutOfCombat)
  ApplyDefault("objectiveHoverReveal", D.objectiveHoverReveal)
  ApplyDefault("buffHoverReveal", D.buffHoverReveal)
  ApplyDefault("actionBarHoverReveal", D.actionBarHoverReveal)
  ApplyDefault("hideActionBar1", D.hideActionBar1)
  ApplyDefault("hideActionBar2", D.hideActionBar2)
  ApplyDefault("hideActionBar3", D.hideActionBar3)
  ApplyDefault("hideActionBar4", D.hideActionBar4)
  ApplyDefault("hideActionBar5", D.hideActionBar5)
  ApplyDefault("hideActionBar6", D.hideActionBar6)
  ApplyDefault("hideActionBar7", D.hideActionBar7)
  ApplyDefault("hideActionBar8", D.hideActionBar8)
  ApplyDefault("hidePetBar", D.hidePetBar)
  ApplyDefault("hideStanceBar", D.hideStanceBar)
  ApplyDefault("hideBagsBar", D.hideBagsBar)
  ApplyDefault("hideMicroMenu", D.hideMicroMenu)
  ApplyDefault("showActionBar1WhenSkyriding", D.showActionBar1WhenSkyriding)
  ApplyDefault("hideBuffFrame", D.hideBuffFrame)
  ApplyDefault("hideObjectiveTracker", D.hideObjectiveTracker)
  ApplyDefault("showObjectiveUpdates", D.showObjectiveUpdates)
  ApplyDefault("forceShowTrackerWhenSuperTracked", D.forceShowTrackerWhenSuperTracked)
  ApplyDefault("showCooldownManagerWhenActive", D.showCooldownManagerWhenActive)
  ApplyDefault("alwaysShowInInstance", D.alwaysShowInInstance)
  ApplyDefault("hideDamageMeter", D.hideDamageMeter)
  ApplyDefault("showDamageMeterInCombat", D.showDamageMeterInCombat)

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

  -- Seed playerFrameMode if missing, falling back to defaults.
  local mode = tonumber(PFH_DB.playerFrameMode)
  if mode == nil then
    mode = tonumber(D.playerFrameMode) or 2
  end

  if mode < 0 then mode = 0 elseif mode > 2 then mode = 2 end
  PFH_DB.playerFrameMode = mode

  -- cooldown mode: seed once, then derive flags via SetCooldownMode
  if PFH_DB.cooldownDisplayMode == nil then
    PFH_DB.cooldownDisplayMode = D.cooldownDisplayMode or 0
  end
  PFH.SetCooldownMode(PFH_DB.cooldownDisplayMode)
  -- ensure legacy hideAllActionBars flag is cleared from saved variables
  PFH_DB.hideAllActionBars = nil
end

-- =========================================================
-- SavedVariables cleanup (remove legacy PFH_* fields)
-- =========================================================

local function MarkHurt(which)
  local defaultSeconds = PFH.DEFAULTS.hurtGraceSeconds or 0
  local seconds = NormalizeSeconds(PFH_DB.hurtGraceSeconds, defaultSeconds, 0)
  local untilTime = GetTime() + seconds

  if which == "pet" then
    state.hurtPetUntil = untilTime
  else
    state.hurtUntil = untilTime
    state.hurtPlayerUntil = untilTime
  end
end

local function ShouldShowPlayerFrame()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide anything
  end

  if PFH.IsAlwaysShowInstance() then return true end

  local mode = tonumber(PFH_DB.playerFrameMode) or tonumber(PFH.DEFAULTS.playerFrameMode) or 2

  -- Mode 0: always show the player frame.
  if mode == 0 then
    return true
  end

  if PFH_DB.showInCombat and PFH.IsInCombat() then return true end
  if PFH.HasTargetLike() then return true end
  local hurtUntil = state.hurtPlayerUntil or state.hurtUntil or 0
  if mode == 2 and GetTime() < hurtUntil then return true end

  if PFH_DB.hoverRevealOutOfCombat and state.hoverOverride and not PFH.IsInCombat() then
    return true
  end

  -- During a combat-hold window, keep the frame visible
  if state.combatHoldPlayer then
    return true
  end

  return false
end

local function ShouldShowPetFrame()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide anything
  end

  local mode = tonumber(PFH_DB.petFrameMode) or PFH.DEFAULTS.petFrameMode or 0

  if PFH.IsAlwaysShowInstance() then return true end

  -- Mode 0: always show the pet frame.
  if mode == 0 then
    return true
  end

  -- Modes 1 and 2 hide the frame by default, with different rules
  -- for health-based auto-show in mode 2.
  if PFH_DB.showInCombat and PFH.IsInCombat() then return true end
  if PFH.HasTargetLike() then return true end

  if mode == 2 then
    local hurtUntil = state.hurtPetUntil or 0
    if GetTime() < hurtUntil then return true end
  end

  -- During a combat-hold window for unit frames, keep the frame visible
  if state.combatHoldPlayer then
    return true
  end

  return false
end

local function ShouldShowWidgets()
  if not PFH_DB.enabled then
    return true -- addon disabled => do not hide widgets
  end

  -- In instances where "Always Show in Instances" is enabled, keep
  -- widgets visible unconditionally, even if a transient vehicle
  --/override bar appears (e.g. during certain delve or dungeon
  -- interactions).
  local inAlwaysShowInstance = PFH.IsAlwaysShowInstance and PFH.IsAlwaysShowInstance()

  if not inAlwaysShowInstance then
    -- Outside of "always show" instances, never show the cooldown
    -- manager while the vehicle action bar is active.
    if PFH.IsVehicleActionBarActive and PFH.IsVehicleActionBarActive() then
      return false
    end
  end

  if inAlwaysShowInstance then return true end

  if state.combatHoldWidgets then
    return true
  end

  -- Mirror player frame rules for target/soft-target visibility so that
  -- the "Show with Target" setting is respected for widgets as well.
  if PFH.IsInCombat() or PFH.HasTargetLike() then
    return true
  end

  -- Optionally show widgets whenever the Blizzard Cooldown Manager
  -- considers them active (e.g. when it has cooldowns to display)
  if PFH.AreWidgetsActive and PFH.AreWidgetsActive() then
    return true
  end

  return false
end

local function GetObjectiveHoverHideDelay()
  local defaultSeconds = PFH.DEFAULTS.objectiveHoverHideDelay or 1.0
  return NormalizeSeconds(PFH_DB.objectiveHoverHideDelay, defaultSeconds, 0)
end

local function GetBuffHoverHideDelay()
  local defaultSeconds = PFH.DEFAULTS.buffHoverHideDelay or 5.0
  return NormalizeSeconds(PFH_DB.buffHoverHideDelay, defaultSeconds, 0)
end

local function GetPlayerHoverHideDelay()
  local defaultSeconds = PFH.DEFAULTS.playerHoverHideDelay or 3.0
  return NormalizeSeconds(PFH_DB.playerHoverHideDelay, defaultSeconds, 0)
end

-- Skyriding detection is implemented in Core/Util.lua as PFH.IsSkyRidingLike.

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

-- =========================================================
-- Action bar frame helpers
-- =========================================================

local function AddActionBarFrame(list, frame, kind, alphaTarget)
  if not frame or not frame.GetAlpha or not frame.SetAlpha then
    return
  end
  -- alphaTarget controls whether SetSimpleFrameVisible() should be
  -- applied to this entry. Defaults to true when omitted.
  local doAlpha = (alphaTarget ~= false)
  list[#list + 1] = { frame = frame, kind = kind, alphaTarget = doAlpha }
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

  -- Individual multi-bars mapped to Edit Mode action bar numbers
  local multiBars = {
    { name = "MultiBarBottomLeft", kind = "bar2" },
    { name = "MultiBarBottomRight", kind = "bar3" },
    { name = "MultiBarRight", kind = "bar4" },
    { name = "MultiBarLeft", kind = "bar5" },
    { name = "MultiBar5", kind = "bar6" },
    { name = "MultiBar6", kind = "bar7" },
    { name = "MultiBar7", kind = "bar8" },
  }
  for _, info in ipairs(multiBars) do
    local f = _G[info.name]
    if f and f.GetAlpha then
      AddActionBarFrame(frames, f, info.kind)
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

  -- Action Bar 1 buttons
  for i = 1, 12 do
    local btn = _G["ActionButton" .. i]
    if btn and btn.GetAlpha and btn.SetAlpha then
      AddActionBarFrame(frames, btn, "bar1")
    end
  end

  -- Multi-bar buttons mapped to the corresponding action bar number
  local multiButtonPrefixes = {
    { prefix = "MultiBarBottomLeftButton", kind = "bar2" },
    { prefix = "MultiBarBottomRightButton", kind = "bar3" },
    { prefix = "MultiBarRightButton", kind = "bar4" },
    { prefix = "MultiBarLeftButton", kind = "bar5" },
    { prefix = "MultiBar5Button", kind = "bar6" },
    { prefix = "MultiBar6Button", kind = "bar7" },
    { prefix = "MultiBar7Button", kind = "bar8" },
  }
  for _, info in ipairs(multiButtonPrefixes) do
    for i = 1, 12 do
      local btn = _G[info.prefix .. i]
      if btn and btn.GetAlpha and btn.SetAlpha then
        AddActionBarFrame(frames, btn, info.kind)
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

-- Resolve non-action-bar button groups (bags bar and micro menu).
-- These are kept separate from ResolveActionBarFrames so that
-- true action bars remain distinct from UI utility bars.
local function ResolveExtraBarFrames()
  if state.extraBarFrames then
    return state.extraBarFrames
  end

  local frames = {}

  -- Bags bar (Dragonflight+ Edit Mode "Bag Bar" or legacy backpack buttons)
  local bagsContainers = {
    "BagsBar",
    "MicroButtonAndBagsBar", -- older combined container
  }
  for _, name in ipairs(bagsContainers) do
    local f = _G[name]
    if f and f.GetAlpha and f.SetAlpha then
      -- Container is the alpha target for show/hide
      AddActionBarFrame(frames, f, "bags", true)
    end
  end

  -- Common bags bar buttons (only added if they exist on this client)
  local bagButtons = {
    "BagsBarBackpack",
    "BagsBarBag0",
    "BagsBarBag1",
    "BagsBarBag2",
    "BagsBarBag3",
    "MainMenuBarBackpackButton", -- pre-Dragonflight backpack
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
  }
  for _, name in ipairs(bagButtons) do
    local btn = _G[name]
    if btn and btn.GetAlpha and btn.SetAlpha then
      -- Buttons participate in hover, but not alpha hiding
      AddActionBarFrame(frames, btn, "bags", false)
    end
  end

  -- Micro menu (Dragonflight+ "Micro Menu" bar and legacy micro buttons)
  local microContainers = {
    "MicroMenu",
    "MicroButtonAndBagsBar", -- combined container also holds micro buttons
  }
  for _, name in ipairs(microContainers) do
    local f = _G[name]
    if f and f.GetAlpha and f.SetAlpha then
      -- Container is the alpha target for show/hide
      AddActionBarFrame(frames, f, "micro", true)
    end
  end

  local microButtons = {
    "CharacterMicroButton",
    "SpellbookMicroButton",
    "TalentMicroButton",
    "AchievementMicroButton",
    "QuestLogMicroButton",
    "GuildMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "StoreMicroButton",
    "MainMenuMicroButton",
    "AdventureGuideMicroButton",
  }
  for _, name in ipairs(microButtons) do
    local btn = _G[name]
    if btn and btn.GetAlpha and btn.SetAlpha then
      -- Buttons participate in hover, but not alpha hiding
      AddActionBarFrame(frames, btn, "micro", false)
    end
  end

  if #frames == 0 then
    frames = nil
  end

  state.extraBarFrames = frames
  return frames
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

    if PFH.HaveRequiredWidgets and PFH.HaveRequiredWidgets() or tries >= 10 then
      ticker:Cancel()
    end
  end)
end

local function ShouldShowBuffFrame()
  if not PFH_DB.enabled then
    return true
  end

  if PFH.IsAlwaysShowInstance() then
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

local function ShouldShowActionBar1()
  if not PFH_DB.enabled then
    return true
  end
  -- Base hide flag for Bar 1.
  local hideThis = PFH_DB.hideActionBar1 and true or false

  -- When skyriding and the option is enabled, temporarily treat Bar 1
  -- as not hidden so it behaves like a normal, always-visible bar.
  if hideThis and PFH_DB.showActionBar1WhenSkyriding and PFH.IsSkyRidingLike() then
    hideThis = false
  end

  -- If we're not hiding this bar via settings, always show it.
  if not hideThis then
    return true
  end

  -- When Bar 1 is configured as hidden, only show it while the
  -- action-bar hover override is active (mouse over bar/buttons),
  -- if hover reveal for action bars is enabled.
  if PFH_DB.actionBarHoverReveal and state.actionBarHoverOverride then
    return true
  end

  return false
end

local function ShouldShowGenericActionBar(hideKey)
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB[hideKey] and true or false

  if not hideThis then
    return true
  end

  if PFH_DB.actionBarHoverReveal and state.actionBarHoverOverride then
    return true
  end

  return false
end

local function ShouldShowActionBar2()
  return ShouldShowGenericActionBar("hideActionBar2")
end

local function ShouldShowActionBar3()
  return ShouldShowGenericActionBar("hideActionBar3")
end

local function ShouldShowActionBar4()
  return ShouldShowGenericActionBar("hideActionBar4")
end

local function ShouldShowActionBar5()
  return ShouldShowGenericActionBar("hideActionBar5")
end

local function ShouldShowActionBar6()
  return ShouldShowGenericActionBar("hideActionBar6")
end

local function ShouldShowActionBar7()
  return ShouldShowGenericActionBar("hideActionBar7")
end

local function ShouldShowActionBar8()
  return ShouldShowGenericActionBar("hideActionBar8")
end

local function ShouldShowPetBar()
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB.hidePetBar and true or false

  if not hideThis then
    return true
  end

  if PFH_DB.actionBarHoverReveal and state.actionBarHoverOverride then
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

  if PFH_DB.actionBarHoverReveal and state.actionBarHoverOverride then
    return true
  end

  return false
end

local function ShouldShowBagsBar()
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB.hideBagsBar and true or false

  if not hideThis then
    return true
  end

  if state.bagsHoverOverride then
    return true
  end

  return false
end

local function ShouldShowMicroMenu()
  if not PFH_DB.enabled then
    return true
  end

  local hideThis = PFH_DB.hideMicroMenu and true or false

  if not hideThis then
    return true
  end

  if state.microHoverOverride then
    return true
  end

  return false
end

-- =========================================================
-- Buff frame init & update hooks
-- =========================================================

local function OnBuffFrameEnter()
  if not PFH_DB.enabled then return end
  if not PFH_DB.hideBuffFrame then return end
  if not PFH_DB.buffHoverReveal then return end
  if PFH.IsInCombat() then return end

  if state.buffHoverHideTimer then
    state.buffHoverHideTimer:Cancel()
    state.buffHoverHideTimer = nil
  end

  state.buffHoverOverride = true
  Apply()
end

local function OnBuffFrameLeave()
  if not PFH_DB.hideBuffFrame then return end
  if not PFH_DB.buffHoverReveal then return end

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
    if not PFH_DB.buffHoverReveal then return end
    if PFH.IsInCombat() then return end
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

local function SetPetFrameVisible(wantVisible)
  local frame = _G.PetFrame
  if not frame or not frame.GetAlpha or not frame.SetAlpha then return end

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.hiddenAlpha or 0)

  if wantVisible then
    if frame:GetAlpha() ~= 1 then frame:SetAlpha(1) end
  else
    if frame:GetAlpha() ~= hiddenAlpha then frame:SetAlpha(hiddenAlpha) end
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
  local mode = tonumber(PFH_DB.playerFrameMode) or tonumber(PFH.DEFAULTS.playerFrameMode) or 2
  if mode == 0 then return end -- "Always show" mode disables hover reveal
  if not PFH_DB.hoverRevealOutOfCombat then return end
  if PFH.IsInCombat() then return end
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
    if PFH.IsInCombat() then return end
    state.hoverOverride = false
    Apply()
  end)
end

local function OnActionBarEnter(kind)
  if not PFH_DB.enabled then return end

  if kind == "bags" then
    if not PFH_DB.hideBagsBar then return end

    if state.bagsHoverHideTimer then
      state.bagsHoverHideTimer:Cancel()
      state.bagsHoverHideTimer = nil
    end

    state.bagsHoverOverride = true
    Apply()
    return
  elseif kind == "micro" then
    if not PFH_DB.hideMicroMenu then return end

    if state.microHoverHideTimer then
      state.microHoverHideTimer:Cancel()
      state.microHoverHideTimer = nil
    end

    state.microHoverOverride = true
    Apply()
    return
  end

  if not PFH.AnyActionBarHideEnabled or not PFH.AnyActionBarHideEnabled() then return end
  if not PFH_DB.actionBarHoverReveal then return end

  if state.actionBarHoverHideTimer then
    state.actionBarHoverHideTimer:Cancel()
    state.actionBarHoverHideTimer = nil
  end

  state.actionBarHoverOverride = true
  Apply()
end

local function OnActionBarLeave(kind)
  if kind == "bags" then
    if not PFH_DB.hideBagsBar then return end

    if state.bagsHoverHideTimer then
      state.bagsHoverHideTimer:Cancel()
      state.bagsHoverHideTimer = nil
    end

    local delay = GetPlayerHoverHideDelay()

    if delay <= 0 then
      state.bagsHoverOverride = false
      Apply()
      return
    end

    state.bagsHoverHideTimer = C_Timer.NewTimer(delay, function()
      state.bagsHoverHideTimer = nil
      if not PFH_DB.hideBagsBar then return end
      state.bagsHoverOverride = false
      Apply()
    end)
    return
  elseif kind == "micro" then
    if not PFH_DB.hideMicroMenu then return end

    if state.microHoverHideTimer then
      state.microHoverHideTimer:Cancel()
      state.microHoverHideTimer = nil
    end

    local delay = GetPlayerHoverHideDelay()

    if delay <= 0 then
      state.microHoverOverride = false
      Apply()
      return
    end

    state.microHoverHideTimer = C_Timer.NewTimer(delay, function()
      state.microHoverHideTimer = nil
      if not PFH_DB.hideMicroMenu then return end
      state.microHoverOverride = false
      Apply()
    end)
    return
  end

  if not PFH.AnyActionBarHideEnabled or not PFH.AnyActionBarHideEnabled() then return end
  if not PFH_DB.actionBarHoverReveal then return end

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
    if not PFH_DB.actionBarHoverReveal then return end
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
  if not PFH.AnyActionBarHideEnabled or not PFH.AnyActionBarHideEnabled() then
    return
  end

  local frames = ResolveActionBarFrames()
  if frames then
    for _, info in ipairs(frames) do
      local wantVisible = true
      if info.kind == "bar1" then
        wantVisible = ShouldShowActionBar1()
      elseif info.kind == "bar2" then
        wantVisible = ShouldShowActionBar2()
      elseif info.kind == "bar3" then
        wantVisible = ShouldShowActionBar3()
      elseif info.kind == "bar4" then
        wantVisible = ShouldShowActionBar4()
      elseif info.kind == "bar5" then
        wantVisible = ShouldShowActionBar5()
      elseif info.kind == "bar6" then
        wantVisible = ShouldShowActionBar6()
      elseif info.kind == "bar7" then
        wantVisible = ShouldShowActionBar7()
      elseif info.kind == "bar8" then
        wantVisible = ShouldShowActionBar8()
      elseif info.kind == "pet" then
        wantVisible = ShouldShowPetBar()
      elseif info.kind == "stance" then
        wantVisible = ShouldShowStanceBar()
      end
      if info.alphaTarget ~= false then
        SetSimpleFrameVisible(info.frame, wantVisible)
      end
    end
  end

  local extraFrames = ResolveExtraBarFrames()
  if not extraFrames then
    return
  end

  for _, info in ipairs(extraFrames) do
    local wantVisible = true
    if info.kind == "bags" then
      wantVisible = ShouldShowBagsBar()
    elseif info.kind == "micro" then
      wantVisible = ShouldShowMicroMenu()
    end
    if info.alphaTarget ~= false then
      SetSimpleFrameVisible(info.frame, wantVisible)
    end
  end
end

-- =========================================================
-- Core apply
-- =========================================================

Apply = function()
  if not PlayerFrame then return end

  SetPlayerFrameVisible(ShouldShowPlayerFrame())
  SetPetFrameVisible(ShouldShowPetFrame())
  if PFH.SetObjectiveTrackerVisible and PFH.ShouldShowObjectiveTracker then
    PFH.SetObjectiveTrackerVisible(PFH.ShouldShowObjectiveTracker())
  end
  SetBuffFrameVisible(ShouldShowBuffFrame())
  if PFH.SetDamageMeterVisible and PFH.ShouldShowDamageMeter then
    PFH.SetDamageMeterVisible(PFH.ShouldShowDamageMeter())
  end
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
  local duration = NormalizeSeconds(seconds, 0, 0)
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

    local now = GetTime()

    local playerEnabled = PFH_DB.showWhenHealthBelow100 and true or false
    local petEnabled = (tonumber(PFH_DB.petFrameMode) == 2)

    local playerExpired = (not playerEnabled) or (now >= (state.hurtPlayerUntil or state.hurtUntil or 0))
    local petExpired = (not petEnabled) or (now >= (state.hurtPetUntil or 0))

    if playerExpired and petExpired then
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
  local function HookHoverForFrames(list)
    if not list then return end
    for _, info in ipairs(list) do
      local f = info.frame
      local kind = info.kind
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
        pcall(f.HookScript, f, "OnEnter", function()
          OnActionBarEnter(kind)
        end)
        pcall(f.HookScript, f, "OnLeave", function()
          OnActionBarLeave(kind)
        end)
      end
    end
  end

  HookHoverForFrames(frames)
  HookHoverForFrames(ResolveExtraBarFrames())

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

PFH.ShouldShowPlayerFrame = ShouldShowPlayerFrame
PFH.ShouldShowPetFrame = ShouldShowPetFrame
PFH.ShouldShowWidgets = ShouldShowWidgets
PFH.ShouldShowBuffFrame = ShouldShowBuffFrame
PFH.ShouldShowActionBar1 = ShouldShowActionBar1
PFH.ShouldShowPetBar = ShouldShowPetBar
PFH.ShouldShowStanceBar = ShouldShowStanceBar
PFH.ShouldShowBagsBar = ShouldShowBagsBar
PFH.ShouldShowMicroMenu = ShouldShowMicroMenu

PFH.ResolveWidgetFramesWithRetries = ResolveWidgetFramesWithRetries
PFH.ResolveActionBarFramesOnce = ResolveActionBarFrames

PFH.SetPlayerFrameVisible = SetPlayerFrameVisible
PFH.SetBuffFrameVisible = SetBuffFrameVisible
PFH.ApplyWidget = ApplyWidget
PFH.Apply = Apply

PFH.HookOnce = HookOnce
PFH.InitPlayerFrame = InitPlayerFrame
PFH.InitWorldMapHooks = InitWorldMapHooks
PFH.InitBuffFrame = InitBuffFrame
PFH.OnBuffsUpdated = OnBuffsUpdated

PFH.CancelHold = CancelHold
PFH.ScheduleHold = ScheduleHold
