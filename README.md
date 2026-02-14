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
- **Action bar hiding**: Optionally hide Action Bars 1–8 individually, plus the Pet Bar and the Stance Bar, with hover-to-reveal
- **Skyriding support for Action Bar 1**: When "Show While Skyriding" is enabled, Action Bar 1 is kept visible while Skyriding/Dragonriding (based on the Vigor power bar), even if it is normally hidden
- **Cooldown Manager integration**: Hide or fade the Blizzard Cooldown Manager (Essential/Utility/Tracked Buffs) using the same out-of-combat rules as the player frame
- **Show When Active (Cooldown Manager)**: Optionally force the Cooldown Manager to show whenever it has active cooldowns, even if you're out of combat with no target
- **Objective tracker integration**: Optionally hide the Objective Tracker and show it again on mouseover; by default, objective/quest updates briefly reveal it so you can see what changed
- **Polished options UI**: Blizzard-style categorized settings with clear sections and helpful descriptions
- **Slash commands**: Quick access via `/pfh` or `/playerframehider`

## Usage

- Open the options panel via `/pfh`, `/playerframehider`, or through the in-game Settings under AddOns → Player Frame Hider.
- Use the **Hidden alpha** slider to control how transparent the player frame becomes when hidden.
- Toggle visibility rules, such as **Show in combat**, **Combat hold (seconds)**, **Show with target**, **Show on health change**, **Hover to reveal (out of combat)**, and **Always show in instances**.
- In the **Action Bars** section, you can:
  - Enable **Hide Action Bar 1** (with optional **Show While Skyriding** so Bar 1 remains visible whenever the Skyriding/Vigor bar is active)
  - Enable **Hide Action Bar 2–8** individually, plus **Hide Pet Bar** and **Hide Stance Bar**, with optional **Hover to Reveal Action Bars**
  - Adjust **Hidden Opacity** for action bars independently of the player frame
- Configure the **Cooldown Manager** section to choose which parts to hide and whether to **Show When Active** so it appears whenever it has cooldowns to display.
- Optionally let the addon control Edit Mode widgets (**Essential Cooldowns**, **Utility Cooldowns**, and **Tracked Buffs**) so they follow the same "out of combat" visibility logic.

## Installation

1. Download the addon
2. Extract the `PlayerFrameHider` folder to your `World of Warcraft\_retail_\Interface\AddOns\` directory
3. Restart World of Warcraft or reload your UI with `/reload`
