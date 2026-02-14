-- Player Frame Hider utility helpers

-- Ensure shared namespace exists
PlayerFrameHider = PlayerFrameHider or {}
local PFH = PlayerFrameHider

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

-- Return true if the player is in a Skyriding/Dragonriding-like
-- state, based primarily on the Vigor (AlternateMount) power bar.
function PFH.IsSkyRidingLike()
  -- Skyriding Vigor power bar (AlternateMount).
  if Enum and Enum.PowerType and Enum.PowerType.AlternateMount and UnitPowerMax then
    local okVigor, maxVigor = pcall(UnitPowerMax, "player", Enum.PowerType.AlternateMount)
    if okVigor and type(maxVigor) == "number" and maxVigor > 0 then
      return true
    end
  end

  -- Fallback: mounted and actually flying (pre-Dragonflight clients or edge cases).
  if not IsMounted then
    return false
  end

  local okMounted, mounted = pcall(IsMounted)
  if not okMounted or not mounted then
    return false
  end

  if IsFlying then
    local okFlying, flying = pcall(IsFlying)
    if okFlying and flying then
      return true
    end
  end

  return false
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
