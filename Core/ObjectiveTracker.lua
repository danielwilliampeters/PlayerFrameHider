-- Player Frame Hider objective tracker helpers

PlayerFrameHider = PlayerFrameHider or {}
local PFH = PlayerFrameHider
local state = PFH.state or {}

local ClampHiddenAlpha = PFH.ClampHiddenAlpha
local NormalizeSeconds = PFH.NormalizeSeconds

-- Startup flicker prevention: suppress auto-show for 3s after last quest event
local objectiveInitTime = 0
local lastQuestEventTime = 0
local startupGracePeriod = 3.0

local function GetObjectiveHoverHideDelay()
  local defaultSeconds = PFH.DEFAULTS and PFH.DEFAULTS.objectiveHoverHideDelay or 1.0
  return NormalizeSeconds(PFH_DB and PFH_DB.objectiveHoverHideDelay, defaultSeconds, 0)
end

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

local function BaseShouldShowObjectiveTracker()
  if not PFH_DB or not PFH_DB.enabled then
    return true
  end

  if PFH.IsAlwaysShowInstance and PFH.IsAlwaysShowInstance() then
    return true
  end

  if PFH.IsWorldMapOpen and PFH.IsWorldMapOpen() then
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

  if PFH_DB.forceShowTrackerWhenSuperTracked and PFH.HasSuperTrackedQuest and PFH.HasSuperTrackedQuest() then
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
  if not PFH_DB or not PFH_DB.enabled then return end
  if not PFH_DB.hideObjectiveTracker then return end
  if not PFH_DB.objectiveHoverReveal then return end

  if state.objectiveHoverHideTimer then
    state.objectiveHoverHideTimer:Cancel()
    state.objectiveHoverHideTimer = nil
  end

  state.objectiveHoverOverride = true
  if PFH.Apply then
    PFH.Apply()
  end
end

local function OnObjectiveLeave()
  if not PFH_DB or not PFH_DB.hideObjectiveTracker then return end
  if not PFH_DB.objectiveHoverReveal then return end

  if state.objectiveHoverHideTimer then
    state.objectiveHoverHideTimer:Cancel()
    state.objectiveHoverHideTimer = nil
  end

  local delay = GetObjectiveHoverHideDelay()

  state.objectiveHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.objectiveHoverHideTimer = nil
    if not PFH_DB or not PFH_DB.hideObjectiveTracker then return end
    state.objectiveHoverOverride = false
    if PFH.Apply then
      PFH.Apply()
    end
  end)
end

local function OnObjectiveUpdated()
  if not PFH_DB or not PFH_DB.enabled then return end
  if not PFH_DB.hideObjectiveTracker then return end
  if not PFH_DB.showObjectiveUpdates then return end

  local now = GetTime()
  local timeSinceInit = now - objectiveInitTime
  
  if timeSinceInit < 30.0 then
    lastQuestEventTime = now
  end
  
  -- Suppress auto-show during login quest spam (3s after last event, 30s max)
  if now - lastQuestEventTime < startupGracePeriod and timeSinceInit < 30.0 then
    return
  end

  if state.objectiveHoverHideTimer then
    state.objectiveHoverHideTimer:Cancel()
    state.objectiveHoverHideTimer = nil
  end

  state.objectiveHoverOverride = true
  if PFH.Apply then
    PFH.Apply()
  end

  local delay = GetObjectiveHoverHideDelay()
  if delay <= 0 then return end

  state.objectiveHoverHideTimer = C_Timer.NewTimer(delay, function()
    state.objectiveHoverHideTimer = nil
    if not PFH_DB or not PFH_DB.hideObjectiveTracker then return end
    state.objectiveHoverOverride = false
    if PFH.Apply then
      PFH.Apply()
    end
  end)
end

local function HookObjectiveOnce()
  if state.objectiveHooked then return end

  local frame = GetObjectiveFrame()
  if not frame then return end

  state.objectiveHooked = true
  state.ObjectiveFrame = frame

  local now = GetTime()
  objectiveInitTime = now
  lastQuestEventTime = now
  state.objectiveHoverOverride = false

  if PFH.Apply then PFH.Apply() end

  if frame.SetHitRectInsets then
    local l, r, t, b = frame:GetHitRectInsets()
    l, r, t, b = l or 0, r or 0, t or 0, b or 0
    frame:SetHitRectInsets(l - 10, r + 10, t - 10, b + 10)
  end

  if frame.EnableMouse then frame:EnableMouse(true) end

  if frame.HookScript then
    frame:HookScript("OnEnter", OnObjectiveEnter)
    frame:HookScript("OnLeave", OnObjectiveLeave)
  end

  if PFH.Apply then PFH.Apply() end
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

PFH.ShouldShowObjectiveTracker = ShouldShowObjectiveTracker
PFH.SetObjectiveTrackerVisible = SetObjectiveTrackerVisible
PFH.InitObjectiveFrame = InitObjectiveFrame
PFH.OnObjectiveUpdated = OnObjectiveUpdated
