# PlayerFrameHider

A World of Warcraft addon that automatically manages the visibility of the Player Frame and Edit Mode widgets, hiding them out of combat for a cleaner and less cluttered UI.

## Features

- **Alpha-based player frame hiding**: Fade the player frame to transparent instead of forcibly hiding it, keeping everything combat-safe
- **Configurable visibility rules**: Choose when the player frame should automatically fade back in
- **Show in combat**: Optionally restore the player frame whenever you enter combat
- **Show on target**: Optionally show the player frame when you have a target selected
- **Health awareness**: Optionally show the player frame when your health drops below a configurable threshold
- **Instance-aware**: Always show the player frame and widgets in dungeons, raids, battlegrounds, or delves
- **Edit Mode widget control**: Fade Essential Cooldowns, Utility Cooldowns, and Tracked Buffs while out of combat
- **Polished options UI**: Blizzard-style categorized settings with clear sections and helpful descriptions
- **Slash commands**: Quick access via `/pfh` or `/playerframehider`

## Installation

1. Download the addon
2. Extract the `PlayerFrameHider` folder to your `World of Warcraft\_retail_\Interface\AddOns\` directory
3. Restart World of Warcraft or reload your UI with `/reload`
