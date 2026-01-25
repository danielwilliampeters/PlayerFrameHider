# PlayerFrameHider

A World of Warcraft addon that automatically manages the visibility of the Player Frame and Edit Mode widgets, hiding them out of combat for a cleaner and less cluttered UI.

## Features

- **Auto-hide out of combat**: Automatically hides the player frame when you're not in combat
- **Show on target**: Player frame appears when you have a target selected
- **Health awareness**: Optionally shows the player frame when your health drops below 100%
- **Instance-aware**: Option to always show the player frame and widgets while in dungeons, raids, battlegrounds, or delves
- **Edit Mode widget control**: Hide Essential Cooldowns, Utility Cooldowns, and Tracked Buffs out of combat
- **Improved UI**: Categorized options panel with clear sections and helpful descriptions
- **Configurable**: Easy-to-use options panel with organized settings
- **Slash commands**: Quick access to settings via `/pfh` or `/playerframehider`

## Installation

1. Download the addon
2. Extract the `PlayerFrameHider` folder to your `World of Warcraft\_retail_\Interface\AddOns\` directory
3. Restart World of Warcraft or reload your UI with `/reload`

## Usage

### Slash Commands

- `/pfh` - Opens the addon options panel
- `/playerframehider` - Opens the addon options panel

### Options

Access the options panel via:

- Slash command: `/pfh`
- ESC menu → Options → AddOns → PlayerFrameHider

**General Settings:**

- **Always show in dungeons/raids/battlegrounds/delves** - Keeps the player frame and supported widgets visible in group instances, delves, and PvP battlegrounds regardless of combat/target state.

**Player Frame Settings:**

- **Hide player frame out of combat** - Automatically hides the player frame when not in combat.
- **Show player frame when health below 100%** - Shows the frame when you take damage (with a 3-second grace period).

**Cooldowns Settings:**

- **Control Essential Cooldowns visibility** - Hide Essential Cooldowns out of combat (shows in combat or with target).
- **Control Utility Cooldowns visibility** - Hide Utility Cooldowns out of combat (shows in combat or with target).
- **Control Tracked Buffs visibility** - Hide Tracked Buffs out of combat (shows in combat or with target).

## How It Works

The addon intelligently manages the player frame visibility based on your combat state, target, and health:

1. **Always shows** the player frame when in combat
2. **Always shows** the player frame when you have a target
3. **Optionally shows** the player frame when your health is below 100% (configurable)
4. **Hides** the player frame when out of combat and no target exists

## License

Free to use and modify.
