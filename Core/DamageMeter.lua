-- Player Frame Hider damage meter helpers

PlayerFrameHider = PlayerFrameHider or {}
local PFH = PlayerFrameHider
local state = PFH.state or {}

local ClampHiddenAlpha = PFH.ClampHiddenAlpha
local NormalizeSeconds = PFH.NormalizeSeconds

-- Locate the Blizzard damage meter host frame.
local function GetDamageMeterFrame()
  if state.DamageMeterFrame and state.DamageMeterFrame.GetAlpha then
    return state.DamageMeterFrame
  end

  local candidates = {
    _G.HUDDamageMeterFrame,
    _G.HudDamageMeterFrame,
    _G.DamageMeterFrame,
    _G.TimerTracker,
    _G.TimerTrackerFrame,
  }

  for i = 1, #candidates do
    local frame = candidates[i]
    if frame and frame.GetAlpha then
      state.DamageMeterFrame = frame
      return frame
    end
  end

  if PFH.FindFrameByNameHint then
    local frame =
      PFH.FindFrameByNameHint("DamageMeter") or
      PFH.FindFrameByNameHint("TimerTracker")
    if frame and frame.GetAlpha then
      state.DamageMeterFrame = frame
      return frame
    end
  end

  return nil
end

local function GetDamageMeterHoverHideDelay()
  local defaultSeconds = PFH.DEFAULTS and PFH.DEFAULTS.playerHoverHideDelay or 3.0
  return NormalizeSeconds(PFH_DB and PFH_DB.playerHoverHideDelay, defaultSeconds, 0)
end

local function ShouldShowDamageMeter()
  if not PFH_DB or not PFH_DB.enabled then
    return true
  end

  if PFH.IsAlwaysShowInstance and PFH.IsAlwaysShowInstance() then
    return true
  end

  if not PFH_DB.hideDamageMeter then
    return true
  end

  if PFH_DB.showDamageMeterInCombat and PFH.IsInCombat and PFH.IsInCombat() then
    return true
  end

  if state.damageMeterHoverOverride then
    return true
  end

  return false
end

local function SetDamageMeterVisible(wantVisible)
  local frame = GetDamageMeterFrame()
  if not frame then return end

  local hiddenAlpha = ClampHiddenAlpha(PFH_DB.buffHiddenAlpha or PFH_DB.hiddenAlpha or 0)

  if wantVisible then
    if frame:GetAlpha() ~= 1 then frame:SetAlpha(1) end
  else
    if frame:GetAlpha() ~= hiddenAlpha then frame:SetAlpha(hiddenAlpha) end
  end
end

local function OnDamageMeterEnter()
  if not PFH_DB or not PFH_DB.enabled then return end
  if not PFH_DB.hideDamageMeter then return end

  if state.damageMeterHoverHideTimer then
    state.damageMeterHoverHideTimer:Cancel()
    state.damageMeterHoverHideTimer = nil
  end

  state.damageMeterHoverOverride = true
  if PFH.Apply then
    PFH.Apply()
  end
end

local function OnDamageMeterLeave()
  if not PFH_DB or not PFH_DB.hideDamageMeter then return end

  if state.damageMeterHoverHideTimer then
    state.damageMeterHoverHideTimer:Cancel()
    state.damageMeterHoverHideTimer = nil
  end

  local delay = GetDamageMeterHoverHideDelay()

  if delay <= 0 then
    state.damageMeterHoverOverride = false
    if PFH.Apply then
      PFH.Apply()
    end
    return
  end

  state.damageMeterHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.damageMeterHoverHideTimer = nil
    if not PFH_DB or not PFH_DB.hideDamageMeter then return end
    state.damageMeterHoverOverride = false
    if PFH.Apply then
      PFH.Apply()
    end
  end)
end

local function HookDamageMeterOnce()
  if state.damageMeterHooked then return end

  local frame = GetDamageMeterFrame()
  if not frame then return end

  state.damageMeterHooked = true
  state.DamageMeterFrame = frame

  local function HookHover(target)
    if not target or target.PFH_DamageMeterHoverHooked then
      return
    end

    target.PFH_DamageMeterHoverHooked = true

    local objType = target.GetObjectType and target:GetObjectType() or nil

    if objType ~= "Button" and objType ~= "CheckButton" then
      if target.EnableMouse then
        target:EnableMouse(true)
      end
      if target.SetMouseMotionEnabled then
        target:SetMouseMotionEnabled(true)
      end
    end

    if type(target.HookScript) == "function" then
      pcall(target.HookScript, target, "OnEnter", OnDamageMeterEnter)
      pcall(target.HookScript, target, "OnLeave", OnDamageMeterLeave)
    end
  end

  local function HookChildrenRecursive(parent)
    if not parent or not parent.GetChildren then
      return
    end

    local children = { parent:GetChildren() }
    for _, child in ipairs(children) do
      HookHover(child)
      HookChildrenRecursive(child)
    end
  end

  HookHover(frame)
  HookChildrenRecursive(frame)

  if PFH.Apply then
    PFH.Apply()
  end
end

local function InitDamageMeterFrame()
  local tries = 0
  local ticker
  ticker = C_Timer.NewTicker(0.2, function()
    tries = tries + 1

    if GetDamageMeterFrame() then
      HookDamageMeterOnce()
      ticker:Cancel()
    elseif tries >= 50 then
      ticker:Cancel()
    end
  end)
end

PFH.ShouldShowDamageMeter = ShouldShowDamageMeter
PFH.SetDamageMeterVisible = SetDamageMeterVisible
PFH.InitDamageMeterFrame = InitDamageMeterFrame
