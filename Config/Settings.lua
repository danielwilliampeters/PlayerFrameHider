-- Player Frame Hider settings & options UI

local PFH = PlayerFrameHider
local state = PFH.state

-- =========================================================
-- Options UI (Blizzard-native vertical Settings layout)
-- =========================================================

function PFH.OpenOptions()
  if Settings and Settings.OpenToCategory and state.optionsCategoryID then
    Settings.OpenToCategory(state.optionsCategoryID)
    return
  end

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

function PFH.CreateOptionsPanel()
  if state.optionsCreated then return end
  state.optionsCreated = true

  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end

  -- Ensure DB is initialised before wiring settings
  PFH.ApplyDefaults()

  local category, layout = Settings.RegisterVerticalLayoutCategory(PFH.OPTION_PANEL_NAME or "Player Frame Hider")
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

  -- 12.0 signature (works on 120000):
  -- Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
  local function RegisterSetting(key, name, defaultValue)
    local ok, setting = pcall(Settings.RegisterAddOnSetting,
      category,
      key,         -- variable
      key,         -- variableKey
      PFH_DB,      -- variableTbl  (MUST be table)
      VarTypeFor(defaultValue),
      name,
      defaultValue
    )
    if ok and setting then return setting end

    -- If Blizzard changes it again, fail loudly with context
    error(("PlayerFrameHider: RegisterAddOnSetting failed for %s: %s"):format(key, tostring(setting)))
  end

  local function OnChangedFor(key, setting)
    if not (Settings.SetOnValueChangedCallback and setting and setting.GetValue) then return end
    Settings.SetOnValueChangedCallback(key, function()
      PFH_DB[key] = setting:GetValue()

      if key == "showWhenHealthBelow100" and not PFH_DB.showWhenHealthBelow100 then
        PFH.StopHurtTicker()
        state.hurtUntil = 0
      end

      PFH.ResolveWidgetFramesOnce()
      PFH.Apply()
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
    local defaultValue = PFH.DEFAULTS[key] and true or false
    local setting = RegisterSetting(key, name, defaultValue)
    OnChangedFor(key, setting)
    CreateCheckboxControl(setting, tooltip)
    return setting
  end

  local function AddSlider(key, name, tooltip, minValue, maxValue, step, defaultValue)
    local current = PFH_DB[key]
    if type(current) ~= "number" then current = 0 end
    if current < minValue then current = minValue end
    if current > maxValue then current = maxValue end
    PFH_DB[key] = current

    local default = defaultValue
    if type(default) ~= "number" then
      default = current
    end
    if default < minValue then default = minValue end
    if default > maxValue then default = maxValue end

    local setting = RegisterSetting(key, name, default)
    OnChangedFor(key, setting)

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
    0, 1, 0.05, PFH.DEFAULTS.hiddenAlpha
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
end
