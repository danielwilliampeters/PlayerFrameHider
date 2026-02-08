# Player Frame Hider

A World of Warcraft addon that automatically manages the visibility of the Player Frame and Edit Mode widgets, hiding them out of combat for a cleaner and less cluttered UI.

## Features

- **Alpha-based player frame hiding**: Fade the player frame to transparent instead of forcibly hiding it, keeping everything combat-safe
- **Configurable visibility rules**: Choose when the player frame should automatically fade back in
- **Show in combat**: Optionally restore the player frame whenever you enter combat
- **Combat hold (seconds)**: Keep the player frame and cooldown widgets visible for a short, configurable delay after combat ends before hiding them again
- **Show on target**: Optionally show the player frame when you have a target selected
- **Health awareness**: Optionally show the player frame for a short time whenever your health changes
- **Hover reveal (out of combat)**: When hidden out of combat, hovering over the player frame area temporarily reveals it
- **Instance-aware**: Always show the player frame and widgets in dungeons, raids, raids, PvP, scenarios, and delves
- **Edit Mode widget control**: Fade Essential Cooldowns, Utility Cooldowns, and Tracked Buffs while out of combat
- **Objective tracker integration**: Optionally hide the Objective Tracker and show it again on mouseover; by default, objective/quest updates briefly reveal it so you can see what changed
- **Polished options UI**: Blizzard-style categorized settings with clear sections and helpful descriptions
- **Slash commands**: Quick access via `/pfh` or `/playerframehider`

## Usage

- Open the options panel via `/pfh`, `/playerframehider`, or through the in-game Settings under AddOns → Player Frame Hider.
- Use the **Hidden alpha** slider to control how transparent the player frame becomes when hidden.
- Toggle visibility rules, such as **Show in combat**, **Combat hold (seconds)**, **Show with target**, **Show on health change**, **Hover to reveal (out of combat)**, and **Always show in instances**.
- Optionally let the addon control Edit Mode widgets (**Essential Cooldowns**, **Utility Cooldowns**, and **Tracked Buffs**) so they follow the same "out of combat" visibility logic.

## Installation

1. Download the addon
2. Extract the `PlayerFrameHider` folder to your `World of Warcraft\_retail_\Interface\AddOns\` directory
3. Restart World of Warcraft or reload your UI with `/reload`
