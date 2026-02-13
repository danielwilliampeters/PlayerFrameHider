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

-- Scan the global table for a frame whose global name contains a hint.
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
