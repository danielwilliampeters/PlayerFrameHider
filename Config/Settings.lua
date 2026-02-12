-- Player Frame Hider settings & options UI

local PFH = PlayerFrameHider
local state = PFH.state

local DEFAULTS = PFH.DEFAULTS

-- Guard to prevent re-entrant Settings callbacks when values
-- are updated programmatically.
local inCallback = false

-- =========================================================
-- Settings panel (Blizzard-native vertical Settings layout)
-- =========================================================

-- Create (and cache) the Retail Settings panel. Uses PFH_*-prefixed
-- Settings variables backed by PFH_DB["PFH_..."] while keeping the
-- legacy PFH_DB[key] values in sync for the rest of the addon.
function PFH.CreateSettingsPanel()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
    return nil
  end

  if PFH.settingsCategory then
    return PFH.settingsCategory
  end

  -- Ensure DB is initialised before wiring settings
  PFH.ApplyDefaults()

  local category, layout = Settings.RegisterVerticalLayoutCategory(PFH.OPTION_PANEL_NAME or "Player Frame Hider")
  PFH.settingsCategory = category
  state.optionsCategory = category
  if category and category.GetID then
    state.optionsCategoryID = category:GetID()
  end
  Settings.RegisterAddOnCategory(category)

  local function VarTypeFor(v)
    if Settings.VarType then
      if type(v) == "boolean" then return Settings.VarType.Boolean end
      if type(v) == "number" then return Settings.VarType.Number end
    end
    return type(v) -- fallback
  end

  -- Namespaced Settings variable name for this addon.
  local function VarNameFor(key)
    return "PFH_" .. key
  end

  -- Seed PFH_DB["PFH_"..key] from PFH_DB[key] (or defaults) so that
  -- Blizzard Settings sees the current saved value, then keep both in sync.
  local function SeedVariable(key)
    local varName = VarNameFor(key)

    if PFH_DB[varName] == nil then
      if PFH_DB[key] ~= nil then
        PFH_DB[varName] = PFH_DB[key]
      else
        PFH_DB[varName] = DEFAULTS[key]
      end
    end

    if PFH_DB[key] == nil then
      PFH_DB[key] = PFH_DB[varName]
    end
  end

  -- 12.0 signature (works on 120000):
  -- Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
  local function RegisterSetting(key, name, defaultValue)
    SeedVariable(key)
    local varName = VarNameFor(key)

    local ok, setting = pcall(Settings.RegisterAddOnSetting,
      category,
      varName,     -- variable (PFH_-prefixed)
      varName,     -- variableKey
      PFH_DB,      -- variableTbl  (MUST be table)
      VarTypeFor(defaultValue),
      name,
      defaultValue
    )
    if ok and setting then return setting, varName end

    -- If Blizzard changes it again, fail loudly with context
    error(("PlayerFrameHider: RegisterAddOnSetting failed for %s (%s): %s"):format(key, tostring(varName), tostring(setting)))
  end

  local function OnChangedFor(key, varName, setting)
    if not (Settings.SetOnValueChangedCallback and setting and setting.GetValue) then return end

    Settings.SetOnValueChangedCallback(varName, function()
      if inCallback then return end
      inCallback = true

      local value = setting:GetValue()

      -- Keep Settings storage and legacy addon DB keys in sync.
      PFH_DB[varName] = value
      PFH_DB[key] = value

      if key == "showWhenHealthBelow100" and not PFH_DB.showWhenHealthBelow100 then
        PFH.StopHurtTicker()
        state.hurtUntil = 0
      end

      if key == "hoverRevealOutOfCombat" and not PFH_DB.hoverRevealOutOfCombat then
        -- Turning off hover reveal should immediately clear any
        -- hover overrides/timers for both the player frame and
        -- the objective tracker.
        if state.hoverHideTimer then
          state.hoverHideTimer:Cancel()
          state.hoverHideTimer = nil
        end
        state.hoverOverride = false
        if state.objectiveHoverHideTimer then
          state.objectiveHoverHideTimer:Cancel()
          state.objectiveHoverHideTimer = nil
        end
        state.objectiveHoverOverride = false
        if state.buffHoverHideTimer then
          state.buffHoverHideTimer:Cancel()
          state.buffHoverHideTimer = nil
        end
        state.buffHoverOverride = false
      end

      if key == "combatHoldSeconds" then
        if PFH.CancelHold then
          PFH.CancelHold("player")
          PFH.CancelHold("widgets")
        end
      end

      if key == "showCooldownManagerWhenActive" then
        if PFH.EnsureCooldownWatcher and PFH.StopCooldownWatcher then
          if PFH_DB.showCooldownManagerWhenActive then
            PFH.EnsureCooldownWatcher()
          else
            PFH.StopCooldownWatcher()
          end
        end
      end

      PFH.ResolveWidgetFramesOnce()
      PFH.Apply()

      inCallback = false
    end)
  end

  local function CreateCheckboxControl(setting, tooltip)
    -- 120000: CreateCheckbox (NOT CreateCheckBox)
    if Settings.CreateCheckbox then
      return Settings.CreateCheckbox(category, setting, tooltip)
    end
    -- fallback name just in case
    if Settings.CreateCheckBox then
      return Settings.CreateCheckBox(category, setting, tooltip)
    end
  end

  local function AddCheckbox(key, name, tooltip)
    local defaultValue = DEFAULTS[key] and true or false
    local setting, varName = RegisterSetting(key, name, defaultValue)
    OnChangedFor(key, varName, setting)
    CreateCheckboxControl(setting, tooltip)
    return setting
  end

  local function AddSlider(key, name, tooltip, minValue, maxValue, step, defaultValue)
    SeedVariable(key)
    local varName = VarNameFor(key)

    local current = PFH_DB[varName]
    if type(current) ~= "number" then current = 0 end
    if current < minValue then current = minValue end
    if current > maxValue then current = maxValue end
    PFH_DB[varName] = current
    PFH_DB[key] = current

    local default = defaultValue
    if type(default) ~= "number" then
      default = current
    end
    if default < minValue then default = minValue end
    if default > maxValue then default = maxValue end

    local setting, registeredVarName = RegisterSetting(key, name, default)
    OnChangedFor(key, registeredVarName, setting)

    if Settings.CreateSliderOptions and Settings.CreateSlider then
      local opts = Settings.CreateSliderOptions(minValue, maxValue, step)

      -- Show percentage on the right, even though the
      -- stored value is a 0-1 alpha.
      if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and MinimalSliderWithSteppersMixin.Label.Right and opts.SetLabelFormatter then
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
          if FormatPercentage then
            return FormatPercentage(value, true)
          else
            return string.format("%d%%", math.floor((value * 100) + 0.5))
          end
        end)
      end

      Settings.CreateSlider(category, setting, opts, tooltip)
    elseif Settings.CreateSlider then
      -- older signature fallback
      Settings.CreateSlider(category, setting, minValue, maxValue, step, tooltip)
    end

    return setting
  end

  local function AddHeader(text)
    if layout and type(layout.AddInitializer) == "function"
      and type(CreateSettingsListSectionHeaderInitializer) == "function" then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
  end

  local function AddTargetModeDropdown()
    local key = "showTargetMode"
    local varName = VarNameFor(key)

    -- Ensure base mode exists
    if PFH_DB[key] == nil then
      PFH_DB[key] = DEFAULTS.showTargetMode or 0
    end

    -- Always seed the Settings variable from the base mode
    PFH_DB[varName] = tonumber(PFH_DB[key]) or 0
    if PFH_DB[varName] < 0 then PFH_DB[varName] = 0 end
    if PFH_DB[varName] > 3 then PFH_DB[varName] = 3 end

    local defaultValue = DEFAULTS.showTargetMode or 0

    local ok, setting = pcall(Settings.RegisterAddOnSetting,
      category,
      varName,
      varName,
      PFH_DB,
      (Settings.VarType and Settings.VarType.Number) or "number",
      "Show With Target",
      defaultValue
    )
    if not (ok and setting) then
      error(("PlayerFrameHider: RegisterAddOnSetting failed for %s (%s): %s"):format(key, tostring(varName), tostring(setting)))
    end

    local function GetTargetModeOptions()
      local container = Settings.CreateControlTextContainer()
      container:Add(0, "Off")
      container:Add(1, "Target")
      container:Add(3, "Target + Soft Target")
      return container:GetData()
    end

    local tooltip = "Shows the Player Frame and Cooldown Manager when a target is available.\n\nSoft Target requires Action Targeting enabled in Game Settings."

    if Settings.CreateDropdown and Settings.CreateControlTextContainer then
      Settings.CreateDropdown(category, setting, GetTargetModeOptions, tooltip)
    end

    if Settings.SetOnValueChangedCallback then
      Settings.SetOnValueChangedCallback(varName, function()
        if inCallback then return end
        inCallback = true

        local value = tonumber(setting:GetValue()) or 0
        if value < 0 then value = 0 end
        if value > 3 then value = 3 end

        PFH_DB[varName] = value
        PFH_DB[key] = value

        PFH.ResolveWidgetFramesOnce()
        PFH.Apply()

        inCallback = false
      end)
    end
  end

  local function AddCooldownDropdown()
    local key = "cooldownDisplayMode"
    local varName = VarNameFor(key)

    -- Ensure base mode exists
    if PFH_DB[key] == nil then
      PFH_DB[key] = DEFAULTS.cooldownDisplayMode or 0
    end

    -- Always seed the Settings variable from the base mode
    PFH_DB[varName] = tonumber(PFH_DB[key]) or 0
    if PFH_DB[varName] < 0 then PFH_DB[varName] = 0 end
    if PFH_DB[varName] > 3 then PFH_DB[varName] = 3 end

    local defaultValue = DEFAULTS.cooldownDisplayMode or 0

    local ok, setting = pcall(Settings.RegisterAddOnSetting,
      category,
      varName,
      varName,
      PFH_DB,
      (Settings.VarType and Settings.VarType.Number) or "number",
      "Hide Cooldown Manager",
      defaultValue
    )
    if not (ok and setting) then
      error(("PlayerFrameHider: RegisterAddOnSetting failed for %s (%s): %s"):format(key, tostring(varName), tostring(setting)))
    end

    local function GetCooldownOptions()
      local container = Settings.CreateControlTextContainer()
      container:Add(0, "Off")
      container:Add(1, "Essential")
      container:Add(2, "Essential + Utility")
      container:Add(3, "All")
      return container:GetData()
    end

    local tooltip = "Choose which parts of the Blizzard Cooldown Manager are shown or hidden automatically.\n\nVisibility rules control when it is shown.\n\nMay require a UI reload."

    if Settings.CreateDropdown and Settings.CreateControlTextContainer then
      Settings.CreateDropdown(category, setting, GetCooldownOptions, tooltip)
    end

    if Settings.SetOnValueChangedCallback then
      Settings.SetOnValueChangedCallback(varName, function()
        if inCallback then return end
        inCallback = true

        local value = tonumber(setting:GetValue()) or 0
        if value < 0 then value = 0 end
        if value > 3 then value = 3 end

        PFH.SetCooldownMode(value)

        PFH.ResolveWidgetFramesOnce()
        PFH.Apply()

        inCallback = false
      end)
    end
  end

  local function AddCombatHoldDropdown()
    local key = "combatHoldSeconds"
    local defaultValue = DEFAULTS[key] or 0

    local setting, varName = RegisterSetting(key, "Post-Combat Hide Delay", defaultValue)
    OnChangedFor(key, varName, setting)

    local function GetHoldOptions()
      local container = Settings.CreateControlTextContainer()
      container:Add(0, "Off")
      container:Add(1, "Short")
      container:Add(3, "Medium")
      container:Add(5, "Long")
      return container:GetData()
    end

    local tooltip = "Keeps the Player Frame and Cooldown Manager visible briefly after combat ends.\n\nThis only applies when \"Show in Combat\" is enabled."

    if Settings.CreateDropdown and Settings.CreateControlTextContainer then
      Settings.CreateDropdown(category, setting, GetHoldOptions, tooltip)
    end
  end

  AddCheckbox(
    "enabled",
    "Enable Player Frame Hider",
    "Turns Player Frame Hider on or off.\n\nRequires a UI reload."
  )

  AddCheckbox(
    "hoverRevealOutOfCombat",
    "Hover to Reveal",
    "When the Player Frame or Objective Tracker is hidden, hovering over it temporarily reveals it."
  )

  AddCheckbox(
    "showInCombat",
    "Show in Combat",
    "Always show the Player Frame and Cooldown Manager while you are in combat."
  )

  AddCombatHoldDropdown()

  AddTargetModeDropdown()

  AddCheckbox(
    "alwaysShowInInstance",
    "Always Show in Instances",
    "Forces the Player Frame, Cooldown Manager, and Objective Tracker to stay visible in instances."
  )

  AddHeader("Player Frame")

  AddCheckbox(
    "hidePlayerFrame",
    "Hide Player Frame",
    "Hides the Blizzard Player Frame by default.\n\nVisibility rules control when it is shown."
  )

  AddCheckbox(
    "showWhenHealthBelow100",
    "Show Player Frame on Health Change",
    "Temporarily show the Player Frame when your health changes."
  )

  AddSlider(
    "hiddenAlpha",
    "Hidden Opacity",
    "Opacity used when the Player Frame is hidden.\n\n0% = fully hidden, 100% = fully visible.",
    0, 1, 0.05, DEFAULTS.hiddenAlpha
  )

  AddHeader("Buff Frame")

  AddCheckbox(
    "hideBuffFrame",
    "Hide Buff Frame",
    "Hides the player buff frame by default. It briefly appears when your buffs change or when you hover over it."
  )

  AddSlider(
    "buffHiddenAlpha",
    "Hidden Opacity",
    "Opacity used when the Buff Frame is hidden.\n\n0% = fully hidden, 100% = fully visible.",
    0, 1, 0.05, DEFAULTS.buffHiddenAlpha or DEFAULTS.hiddenAlpha
  )

  AddHeader("Cooldown Manager")

  AddCooldownDropdown()

  AddCheckbox(
    "showCooldownManagerWhenActive",
    "Show When Active",
    "Automatically shows the Cooldown Manager when it has active cooldowns, even if you are out of combat and have no target."
  )

  -- AddSlider(
  --   "cooldownHiddenAlpha",
  --   "Hidden Opacity",
  --   "Opacity used when the Cooldown Manager is hidden.\n\n0% = fully hidden, 100% = fully visible.",
  --   0, 1, 0.05, DEFAULTS.cooldownHiddenAlpha or DEFAULTS.hiddenAlpha
  -- )

  AddHeader("Objective Tracker")

  AddCheckbox(
    "hideObjectiveTracker",
    "Hide Objective Tracker",
    "Automatically hides the Objective Tracker when idle and shows it again when objectives update.\n\nTip: Enable \"Hover to Reveal\" to temporarily show it on mouseover."
  )

  AddCheckbox(
    "forceShowTrackerWhenSuperTracked",
    "Show for Active Waypoint",
    "Shows the Objective Tracker when a quest is set as your active waypoint."
  )

  -- AddSlider(
  --   "objectiveHiddenAlpha",
  --   "Hidden Opacity",
  --   "Opacity used when the Objective Tracker is hidden.\n\n0% = fully hidden, 100% = fully visible.",
  --   0, 1, 0.05, DEFAULTS.objectiveHiddenAlpha or DEFAULTS.hiddenAlpha
  -- )

  return category
end

-- Backwards-compatible alias; routes to the single settings
-- creation path above so there is only one implementation.
function PFH.CreateOptionsPanel()
  return PFH.CreateSettingsPanel()
end

function PFH.OpenOptions()
  -- Prefer modern Settings UI when available.
  if Settings and Settings.OpenToCategory and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory then
    local category = PFH.CreateSettingsPanel and PFH.CreateSettingsPanel() or PFH.settingsCategory
    local cat = category or PFH.settingsCategory
    if cat then
      Settings.OpenToCategory(cat.GetID and cat:GetID() or cat)
      return
    end
  end

  -- Legacy fallback for very old clients.
  if InterfaceOptionsFrame_OpenToCategory then
    local name = PFH.OPTION_PANEL_NAME or "Player Frame Hider"
    InterfaceOptionsFrame_OpenToCategory(name)
    InterfaceOptionsFrame_OpenToCategory(name)
  end
end

SLASH_PlayerFrameHider1 = "/pfh"
SLASH_PlayerFrameHider2 = "/playerframehider"
SlashCmdList["PlayerFrameHider"] = function()
  PFH.OpenOptions()
end

-- Global handler for the AddOn Compartment button. Kept
-- for TOC AddonCompartmentFunc usage.
function PlayerFrameHider_OpenSettings(addonName, buttonName)
  if not PlayerFrameHider or not PlayerFrameHider.OpenOptions then return end
  PlayerFrameHider.OpenOptions()
end