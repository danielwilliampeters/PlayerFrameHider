-- Player Frame Hider frame resolution helpers

PlayerFrameHider = PlayerFrameHider or {}
local PFH = PlayerFrameHider

-- Debounced wrapper used specifically for widget HookScript callbacks.
-- This avoids spamming full Apply() calls when Edit Mode widgets are
-- rapidly shown/hidden or otherwise updated in quick succession.
local widgetApplyScheduled = false

local function ApplyFromWidget()
  if widgetApplyScheduled then
    return
  end

  widgetApplyScheduled = true

  C_Timer.After(0, function()
    widgetApplyScheduled = false

    -- Use the core Apply routine if it has been wired.
    if PFH.Apply then
      PFH.Apply()
    end
  end)
end

local function TryGetMethod(target, methodName)
  if not target then
    return nil
  end

  if type(target) == "table" then
    local method = rawget(target, methodName)
    if type(method) == "function" then
      return method
    end
  end

  local ok, method = pcall(function()
    return target[methodName]
  end)

  if ok and type(method) == "function" then
    return method
  end

  return nil
end

-- Scan the global table for a frame whose global name contains a hint.
local function FindFrameByNameHint(hint)
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "table" and k:find(hint, 1, true) then
      local getObjectType = TryGetMethod(v, "GetObjectType")
      local isShown = TryGetMethod(v, "IsShown")
      if getObjectType and isShown then
        return v
      end
    end
  end
  return nil
end

-- Locate and cache the Blizzard Edit Mode cooldown/buff widget frames,
-- and hook them so visibility changes trigger a debounced Apply().
function PFH.ResolveWidgetFramesOnce()
  local state = PFH.state
  if not state then
    state = {}
    PFH.state = state
  end

  state.EssentialCDFrame = state.EssentialCDFrame or _G.EssentialCooldownsFrame or FindFrameByNameHint("EssentialCooldown")
  state.UtilityCDFrame = state.UtilityCDFrame or _G.UtilityCooldownsFrame or _G.UtilityCooldownFrame or _G.UtilityCooldowns or FindFrameByNameHint("UtilityCooldown")
  state.TrackedBuffsFrame = state.TrackedBuffsFrame or _G.TrackedBuffsFrame or _G.TrackedBuffFrame or _G.TrackedBuffs or FindFrameByNameHint("BuffIconCooldownViewer")

  if not state.widgetFramesHooked then
    local function HookWidgetFrame(frame)
      if not frame or frame.PFH_WidgetHooked then return end

      frame.PFH_WidgetHooked = true

      if type(frame.HasScript) == "function" then
        if frame:HasScript("OnShow") and frame.HookScript then
          pcall(frame.HookScript, frame, "OnShow", ApplyFromWidget)
        end
        if frame:HasScript("OnHide") and frame.HookScript then
          pcall(frame.HookScript, frame, "OnHide", ApplyFromWidget)
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

-- Expose the name-hint finder for other modules that need to
-- discover Blizzard UI frames introduced in newer patches.
PFH.FindFrameByNameHint = FindFrameByNameHint
