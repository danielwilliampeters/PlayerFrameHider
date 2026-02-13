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
