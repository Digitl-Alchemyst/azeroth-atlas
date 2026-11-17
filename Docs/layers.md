# Map layers

Updated 2026-11-16. Levels are offsets above the map's content frame
(`MinimapEngine.lua`'s `*_LEVEL_OFFSET` constants). Strata is the frame
strata tier: the whole map window sits in **DIALOG** so other addons'
action bars, raid frames and unit frames (MEDIUM/HIGH) can't show through
it. The overlay tier is **FULLSCREEN**.

| # | Layer | What it shows | When it's visible | Toggle |
|---|-------|---------------|-------------------|--------|
| 1 | Base | Flat continent backdrop art | Zoomed out past the current zone's own bounds | Settings > Map > Map layers |
| 2 | Art Map | Zones' revealed overlay art, stitched across the continent | Zoomed out (scale at or below 4) | Settings > Map > Map layers |
| 3 | Terrain | Close-zoom minimap ground tiles | Always | Settings > Map > Map layers |
| 4 | City / Dungeon map | The city's or dungeon floor's own art map | Inside a main city or a dungeon/raid | Settings > Map > Map layers (City and Dungeon separately) |
| 5 | Gather backdrop | Dark rounded square behind each gathering icon | With its gathering icon | Follows the gathering filters |
| 6 | Service | Gathering nodes, mailbox/inn/bank/AH/flight/spirit healer, entrances, zone transitions, quest pins, goto/corpse/quest trails and markers | Always, per filter | Settings > Map > Map icons |
| 7 | Players | Party (blue), raid (orange), guildmates (green), enemies (red or faction emblem) | Always, per filter | Settings > Map > Players |
| overlay +1 | Radar | Live Blizzard minimap patch (native gathering blips) | While a Find Herbs/Minerals/Fish tracking is active | Automatic |
| overlay +30 | Player marker | You | Always (hidden only in a dungeon that doesn't report your position) | None |
| overlay +50 | Chrome | Zoom buttons, Auto-follow, Settings gear, speed readout | Always | None |

Popups that open over the map: Settings window and Quest List
(FULLSCREEN_DIALOG), right-click menus and tooltips (TOOLTIP).
