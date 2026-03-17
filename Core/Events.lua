-- Player Frame Hider event handling

local PFH = PlayerFrameHider
local state = PFH.state
local eventFrame = CreateFrame("Frame")

local function OnLogin()
  if state.didInit then
    -- Still refresh combat flag and apply, but don't re-run init/setup.
    state.inCombat = UnitAffectingCombat("player")
    PFH.Apply()
    return
  end
  state.didInit = true

  PFH.ApplyDefaults()
  if PFH.CleanupLegacySavedVariables then
    PFH.CleanupLegacySavedVariables()
  end
  state.inCombat = UnitAffectingCombat("player")

  if PFH.CreateSettingsPanel then
    PFH.CreateSettingsPanel()
  end
  PFH.InitPlayerFrame()
  PFH.InitObjectiveFrame()
  if PFH.InitBuffFrame then
    PFH.InitBuffFrame()
  end
  if PFH.InitDamageMeterFrame then
    PFH.InitDamageMeterFrame()
  end
  if PFH.ResolveActionBarFramesOnce then
    PFH.ResolveActionBarFramesOnce()
  end
  if PFH.InitWorldMapHooks then
    PFH.InitWorldMapHooks()
  end
  if PFH.NeedWidgets and PFH.NeedWidgets() then
    PFH.ResolveWidgetFramesWithRetries()
  end

  if PFH.EnsureCooldownWatcher then
    PFH.EnsureCooldownWatcher()
  end

  if not state.loadMessageShown then
    local version = PFH.VERSION or "dev"
    print("|cFF00FF00PlayerFrameHider:|r v" .. version .. " Loaded. Use |cFFFFA500/pfh|r to open options.")
    state.loadMessageShown = true
  end

  PFH.Apply()
end

local function OnRegenDisabled()
  state.inCombat = true
  state.justLeftCombat = false
  if PFH.CancelHold then
    PFH.CancelHold("player")
    PFH.CancelHold("widgets")
  end
  PFH.Apply()
end

local function OnRegenEnabled()
  -- Leaving combat: if elements were visible in combat and a combat
  -- hold is configured, keep them visible for the configured duration.

  local holdSeconds = tonumber(PFH_DB and PFH_DB.combatHoldSeconds) or 0

  -- Ensure combat-hold flags are cleared while we sample baselines.
  state.combatHoldPlayer = false
  state.combatHoldWidgets = false

  -- Treat as in-combat for the "before" snapshot.
  state.inCombat = true
  local prevShowPlayer = PFH.ShouldShowPlayerFrame()
  local prevShowPet = PFH.ShouldShowPetFrame and PFH.ShouldShowPetFrame() or false
  local prevShowWidgets = PFH.ShouldShowWidgets()

  -- Now mark as out of combat and clear any existing holds.
  state.inCombat = false
  state.justLeftCombat = true

  if PFH.CancelHold then
    PFH.CancelHold("player")
    PFH.CancelHold("widgets")
  end

  if PFH.ScheduleHold and holdSeconds > 0 then
    if prevShowPlayer or prevShowPet then
      PFH.ScheduleHold("player", holdSeconds)
    end
    if prevShowWidgets then
      PFH.ScheduleHold("widgets", holdSeconds)
    end
  end

  PFH.Apply()

  state.justLeftCombat = false
end

local function OnTargetOrZoneChanged()
  PFH.Apply()
end

local function OnUnitHealthChanged(event, unit)
  if event ~= "UNIT_HEALTH" then
    return
  end

  if unit == "player" then
    if PFH_DB.playerFrameMode ~= 2 then return end
    PFH.MarkHurt("player")
  elseif unit == "pet" then
    if PFH_DB.petFrameMode ~= 2 then return end
    PFH.MarkHurt("pet")
  else
    return
  end

  PFH.EnsureHurtTicker()
  PFH.Apply()
end

local function OnObjectiveTrackerChanged()
  if PFH.OnObjectiveUpdated then
    PFH.OnObjectiveUpdated()
  end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
eventFrame:RegisterEvent("SCENARIO_UPDATE")
eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")

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

  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_SOFT_ENEMY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
    OnTargetOrZoneChanged()
    return
  end

  if event == "UNIT_HEALTH"
    or event == "UNIT_MAXHEALTH"
    or event == "UNIT_ABSORB_AMOUNT_CHANGED"
    or event == "UNIT_HEAL_PREDICTION"
  then
    OnUnitHealthChanged(event, unit)
    return
  end

  if event == "QUEST_LOG_UPDATE"
    or event == "QUEST_WATCH_LIST_CHANGED"
    or event == "SCENARIO_UPDATE"
    or event == "SCENARIO_CRITERIA_UPDATE"
    or event == "SUPER_TRACKING_CHANGED"
  then
    OnObjectiveTrackerChanged()
    return
  end

  if event == "UNIT_AURA" then
    if unit == "player" and PFH.OnBuffsUpdated then
      PFH.OnBuffsUpdated()
    end
  end
end)
