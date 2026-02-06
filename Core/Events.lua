-- Player Frame Hider event handling

local PFH = PlayerFrameHider
local state = PFH.state
local eventFrame = CreateFrame("Frame")

local function OnLogin()
  if state.didInit then
    -- Still refresh combat flag and apply, but don't re-run init/setup.
    state.inCombat = UnitAffectingCombat("player") and true or false
    PFH.Apply()
    return
  end
  state.didInit = true

  PFH.ApplyDefaults()
  state.inCombat = UnitAffectingCombat("player") and true or false

  if PFH.CreateSettingsPanel then
    PFH.CreateSettingsPanel()
  end
  PFH.InitPlayerFrame()
  PFH.InitObjectiveFrame()
  PFH.ResolveWidgetFramesWithRetries()

  if not state.loadMessageShown then
    local version = PFH.VERSION or "dev"
    print("|cFF00FF00PlayerFrameHider:|r v" .. version .. " Loaded. Use |cFFFFA500/pfh|r to open options.")
    state.loadMessageShown = true
  end

  PFH.Apply()
end

local function OnRegenDisabled()
  state.inCombat = true
  PFH.Apply()
end

local function OnRegenEnabled()
  state.inCombat = false
  PFH.Apply()
end

local function OnTargetOrZoneChanged()
  PFH.Apply()
end

local function OnPlayerHealthChanged(unit)
  if unit ~= "player" then return end
  if PFH_DB.showWhenHealthBelow100 then
    PFH.MarkHurt()
    PFH.EnsureHurtTicker()
  end
  PFH.Apply()
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")

eventFrame:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    OnLogin()
    return
  end

  PFH.HookOnce()

  if event == "PLAYER_REGEN_DISABLED" then
    OnRegenDisabled()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    OnRegenEnabled()
    return
  end

  if event == "PLAYER_TARGET_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
    OnTargetOrZoneChanged()
    return
  end

  if event == "UNIT_HEALTH"
    or event == "UNIT_MAXHEALTH"
    or event == "UNIT_ABSORB_AMOUNT_CHANGED"
    or event == "UNIT_HEAL_PREDICTION"
  then
    OnPlayerHealthChanged(unit)
  end
end)
