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

  AddCheckbox(
    "enabled",
    "Enable Player Frame Hider",
    "Turns Player Frame Hider on or off.\n\nRequires a UI reload."
  )

  AddHeader("Visibility")

  AddCheckbox(
    "hidePlayerFrame",
    "Hide player frame",
    "Hide the Blizzard Player Frame by default. The options below control when it becomes visible."
  )

  AddSlider(
    "hiddenAlpha",
    "Hidden alpha",
    "Opacity used when the player frame is hidden.\n\n0% = fully hidden, 100% = fully visible.",
    0, 1, 0.05, DEFAULTS.hiddenAlpha
  )

  AddCheckbox(
    "showInCombat",
    "Show in combat",
    "Always show the Player Frame while you are in combat."
  )

  AddCheckbox(
    "showIfTarget",
    "Show with target",
    "Show the Player Frame when you have a target selected."
  )

  AddCheckbox(
    "showWhenHealthBelow100",
    "Show on health change",
    "Temporarily show the Player Frame when your health changes."
  )

  AddCheckbox(
    "hoverRevealOutOfCombat",
    "Hover to reveal (out of combat)",
    "When hidden out of combat, hovering over the Player Frame area temporarily reveals it."
  )

  AddCheckbox(
    "alwaysShowInInstance",
    "Always show in instances",
    "Always show the Player Frame and related widgets in dungeons, raids, PvP, scenarios, and delves."
  )

  AddHeader("Cooldowns and buffs")

  AddCheckbox(
    "controlEssentialCooldowns",
    "Essential Cooldowns",
    "Control visibility. Hidden out of combat; shown in combat or when targeting an attackable enemy.\n\nRequires a UI reload."
  )

  AddCheckbox(
    "controlUtilityCooldowns",
    "Utility Cooldowns",
    "Control visibility. Hidden out of combat; shown in combat or when targeting an attackable enemy.\n\nRequires a UI reload."
  )

  AddCheckbox(
    "controlTrackedBuffs",
    "Tracked Buffs",
    "Control visibility. Hidden out of combat; shown in combat or when targeting an attackable enemy.\n\nRequires a UI reload."
  )

  AddHeader("Objective Tracker")

  AddCheckbox(
    "hideObjectiveTracker",
    "Hide objective tracker",
    "Automatically hides the Objective Tracker when idle. It reappears when objectives update or when you move the mouse over it."
  )

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