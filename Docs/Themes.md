# Map themes: parts bin

Collected 2026-11-17 from Leatrix Maps' map themes, for the final theming stage. The data lives in `UI/ThemeLibrary.lua`, and Leatrix's sliced icons are in `Gfx/Themes/Leatrix/`. Leatrix art is used with its author's permission.

| # | Theme | Look |
| --- | --- | --- |
| 1 | Classic | Neutral black bars, muted gold accent |
| 2 | Warm | Dark brown, bronze accent |
| 3 | Charcoal | Cool slate |
| 4 | Class Tint (Leatrix: "Class colour") | Dark wash of your class colour |
| 5–10 | Pink, Alliance, Horde, Purple, Teal, Green | Same wash recipe, one colour each |
| 11 | Rainbow | Dark rainbow across the title bar, violet accent |
| 12 | Blizzard | The game's own gold frame border and rock title bar (the big map's default) |
| 13 | Frosted Glass (Leatrix: "Glass") | See-through frosted bars, bright 1-pixel rim, light sheen |
| 14 | Handheld | Map as the screen of a sideways games handheld |
| 15 | Retro TV | Map as an old wooden TV with knobs, scanlines and glare |

All 15 can be picked for the big map in Settings > Style > Big Map Theme (`Map/BigMapThemes.lua`). Handheld and Retro TV are drawn without Leatrix's power-switch animations and the handheld's gem game.

Only Leatrix's icon sheet and its dungeon art are files of its own. Alchemy GPS already reads the dungeon art from the Leatrix folder at runtime. Every other texture, atlas and font the themes use is built into the game client and is listed by path under `Art` and `Fonts`.

Leatrix's sliced icons:

| File | Size (px) | What it is |
| --- | --- | --- |
| Close, Maximize, Minimize | 32 | Flat title bar buttons |
| TravelAlliance, TravelHorde, TravelNeutral | 32 | Boat, zeppelin and tram pins |
| DungeonRaid | 32 | Dungeon pin |
| ButtonBar, ButtonBarGlow | 128×32 | Button background and its hover glow |
| DragonGold, DragonSilver, DragonGrey | 128 | Elite-style dragon frames for pins |

To regenerate the icons, run `python -E Tools/slice_leatrix_sheet.py`.
