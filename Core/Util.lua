-- Player Frame Hider utility helpers

-- Ensure shared namespace exists
PlayerFrameHider = PlayerFrameHider or {}
local PFH = PlayerFrameHider

-- =========================================================
-- SavedVariables helpers
-- =========================================================

-- Remove legacy PFH_* keys from the SavedVariables table.
function PFH.CleanupLegacySavedVariables()
  if not PFH_DB or type(PFH_DB) ~= "table" then return end

  local toClear = {}
  for k in pairs(PFH_DB) do
    if type(k) == "string" and k:match("^PFH_") then
      toClear[#toClear + 1] = k
    end
  end

  for _, key in ipairs(toClear) do
    PFH_DB[key] = nil
  end
end

-- Clamp an alpha/opacity value into [0, 1].
function PFH.ClampHiddenAlpha(value)
  if type(value) ~= "number" then
    return 0
  elseif value < 0 then
    return 0
  elseif value > 1 then
    return 1
  end
  return value
end

-- Apply a default value for a DB key if it is currently nil.
function PFH.ApplyDefault(key, value)
  if PFH_DB and PFH_DB[key] == nil then
    PFH_DB[key] = value
  end
end

-- Apply a numeric default for a DB key, enforcing an optional minimum.
function PFH.ApplyNumberDefault(key, value, minValue)
  if not PFH_DB then return end

  local v = PFH_DB[key]
  if type(v) ~= "number" then
    v = value
  end
  if minValue ~= nil and v < minValue then
    v = minValue
  end
  PFH_DB[key] = v
end

-- Normalize a duration in seconds using an optional default and minimum.
-- Returns a non-negative number (or the provided minimum) suitable for
-- use with timers and delay settings.
function PFH.NormalizeSeconds(value, defaultValue, minValue)
  local v = tonumber(value)

  if v == nil then
    v = defaultValue
  end

  if type(v) ~= "number" then
    v = 0
  end

  if minValue == nil then
    minValue = 0
  end

  if v < minValue then
    v = minValue
  end

  return v
end

-- =========================================================
-- Cooldown manager helpers
-- =========================================================

-- Set the numeric cooldown display mode and derive the
-- underlying boolean flags used elsewhere in the addon.
function PFH.SetCooldownMode(mode)
  local m = tonumber(mode) or 0
  if m < 0 then
    m = 0
  elseif m > 3 then
    m = 3
  end

  PFH_DB.cooldownDisplayMode = m

  PFH_DB.controlEssentialCooldowns = (m >= 1)
  PFH_DB.controlUtilityCooldowns   = (m >= 2)
  PFH_DB.controlTrackedBuffs       = (m >= 3)
end

-- Return true if the player is in combat.
function PFH.IsInCombat()
  return (PFH.state and PFH.state.inCombat)
    or (UnitAffectingCombat and UnitAffectingCombat("player") and true or false)
end

-- Return true if the player currently has an enemy target.
function PFH.HasEnemyTarget()
  return UnitExists and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target")
end

-- Return true if there is any "target-like" unit, based on showTargetMode.
function PFH.HasTargetLike()
  if not PFH_DB then return false end

  local mode = tonumber(PFH_DB.showTargetMode) or 0

  if (mode == 1 or mode == 3) and UnitExists and UnitExists("target") then
    return true
  end

  if (mode == 2 or mode == 3) and UnitExists and UnitExists("softenemy") then
    return true
  end

  return false
end

-- Return true if the current instance/zone is one where the
-- addon should treat "always show in instance" as relevant.
function PFH.IsRelevantInstance()
  if not IsInInstance then
    return false
  end

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

-- Return true if "alwaysShowInInstance" is enabled and the
-- player is currently in a relevant instance.
function PFH.IsAlwaysShowInstance()
  if not PFH_DB or not PFH_DB.alwaysShowInInstance then
    return false
  end
  return PFH.IsRelevantInstance()
end

-- Return true if the player is mounted
function PFH.IsSkyRidingLike()
  if not IsMounted then
    return false
  end

  local okMounted, mounted = pcall(IsMounted)
  return okMounted and mounted
end

-- Return true if a vehicle-style action bar is currently active.
function PFH.IsVehicleActionBarActive()
  -- Prefer the dedicated vehicle APIs when available.
  if HasVehicleActionBar and HasVehicleActionBar() then
    return true
  end

  if UnitHasVehicleUI and UnitHasVehicleUI("player") then
    return true
  end

  return false
end

-- =========================================================
-- Cooldown widget helpers
-- =========================================================

-- Internal: locate a cooldown frame on an item/widget.
local function GetItemCooldownFrame(item)
  if type(item) ~= "table" then return nil end

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

-- Internal: check whether any active objects in a pool have a visible cooldown.
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

    local cd = GetItemCooldownFrame(item)
    if cd and cd.IsShown and cd:IsShown() then
      return true
    end

    return false
  end)
end

-- Check whether a cooldown viewer has any active cooldowns.
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

-- Return true if any of the configured cooldown widgets currently have
-- active cooldowns that should keep the manager visible.
function PFH.AreWidgetsActive()
  if not PFH_DB or not PFH_DB.enabled then return false end
  if not PFH_DB.showCooldownManagerWhenActive then return false end
  if not (PFH_DB.controlEssentialCooldowns or PFH_DB.controlUtilityCooldowns or PFH_DB.controlTrackedBuffs) then
    return false
  end

  local state = PFH.state or {}

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

-- =========================================================
-- Action bar/helpers
-- =========================================================

-- Return true if any hide-action-bar option is enabled.
function PFH.AnyActionBarHideEnabled()
  if not PFH_DB then return false end

  return PFH_DB.hideActionBar1
    or PFH_DB.hideActionBar2
    or PFH_DB.hideActionBar3
    or PFH_DB.hideActionBar4
    or PFH_DB.hideActionBar5
    or PFH_DB.hideActionBar6
    or PFH_DB.hideActionBar7
    or PFH_DB.hideActionBar8
    or PFH_DB.hidePetBar
    or PFH_DB.hideStanceBar
    or PFH_DB.hideBagsBar
    or PFH_DB.hideMicroMenu
end

-- =========================================================
-- Cooldown widget presence helpers
-- =========================================================

function PFH.NeedWidgets()
  if not PFH_DB then return false end
  return PFH_DB.controlEssentialCooldowns or PFH_DB.controlUtilityCooldowns or PFH_DB.controlTrackedBuffs
end

function PFH.HaveRequiredWidgets()
  if not PFH.NeedWidgets() then return true end

  local state = PFH.state or {}

  return ((not PFH_DB.controlEssentialCooldowns or state.EssentialCDFrame) and
          (not PFH_DB.controlUtilityCooldowns or state.UtilityCDFrame) and
          (not PFH_DB.controlTrackedBuffs or state.TrackedBuffsFrame))
end

-- =========================================================
-- Objective tracker helpers
-- =========================================================

function PFH.HasSuperTrackedQuest()
  if not C_SuperTrack or not C_SuperTrack.GetSuperTrackedQuestID then
    return false
  end

  local questID = C_SuperTrack.GetSuperTrackedQuestID()
  if not questID or questID == 0 then
    return false
  end

  return true
end

function PFH.IsWorldMapOpen()
  local map = _G.WorldMapFrame
  if map and map.IsShown and map:IsShown() then
    return true
  end
  return false
end

