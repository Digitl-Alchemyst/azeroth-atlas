# Azeroth Atlas — Big Map Phase Test Plan

Nov 17, 2026 · @Digital Alchemyst

## Before you start

This plan covers everything built since the last test plan: the Leatrix-style big map, its themes, the quest hover highlight, the Twice Misplaced Trust fix and the faction flight master icons. All of it is in the live AddOns folder; none of it is committed yet.

- **Restart the game fully once** before testing. After that, `/reload` is enough between fixes.
- **Show Lua errors**: type `/console scriptErrors 1`, or use BugSack if you have it. Any red error box counts as a fail for the step you were on.
- **You'll need**: a character who can reach Booty Bay and the Riverglades, a quest log with several quests (at least one untracked), and flight masters of your own faction and a neutral one nearby.
- **Recording results**: set each step's Result to Pass, Fail or Not tested. For a fail, add a comment saying what you saw, with a screenshot if you can.
- **Quest problems**: type `/aatlas quest dump <questID>` and paste the lines into your comment.

## 1. Big map basics

The big map is the map window when it's maximised with M, or dragged at least 480 pixels wide.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.1 | Open the map and press M | The window grows big. A toolbar sits under the title: My Map, Continents v, Zones v, Dungeons v, Filters, Quests. Your coordinates and the cursor's show at the bottom. The frame has the game's gold border. |  |
| 1.2 | Press M again | The window goes back to small. The toolbar, coordinates and zone label disappear and the small map has your normal window skin. |  |
| 1.3 | Drag the small map until it's wide (about half the screen) | The toolbar, coordinates and theme appear without maximising. Shrink it again and they go. |  |
| 1.4 | Hover each toolbar button | A tooltip explains what the button does. |  |
| 1.5 | Open the Continents menu, then click on the map or press Escape | The menu closes. |  |
| 1.6 | With the big map open, use the window's close button | The map closes with no Lua error. Pressing M opens it again. |  |

## 2. Browsing other maps

The toolbar menus let you look at any continent, zone or dungeon while your own position keeps updating. My Map brings you back.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.1 | Continents v > Azeroth | Every continent is drawn at once and fits the window. The title reads Azeroth in gold, with "(you: your zone)" after it. My Map turns bronze. |  |
| 2.2 | Continents v > Kalimdor, then Eastern Kingdoms, then Zephras Isle | Each continent fills the window with its zones drawn. Nothing from the previous one is left behind. |  |
| 2.3 | Open Zones v while looking at Eastern Kingdoms | It lists that continent's zones, in columns if long. Cities say (city). Each zone has a coloured level range. The zone on show has a green > in front. |  |
| 2.4 | Pick a zone and a city from the Zones menu | The map shows that zone or city, fitted to the window. |  |
| 2.5 | Dungeons v > a dungeon with a map (for example The Deadmines) | Its floor map is drawn with the floor bar under the toolbar. Switching floors works. |  |
| 2.6 | Try several dungeons in the list, including WoW Forever ones | Each either draws or shows "No map to show for ..." and returns to your own map. Note any that do neither. |  |
| 2.7 | While looking at another zone, move your character | The map stays where you put it and doesn't jump back to you. The Player coordinates still change. |  |
| 2.8 | Click My Map | The map returns to your position at the zoom you had before browsing and follows you again. My Map loses its bronze colour. |  |

## 3. Coordinates and zone label

The footer shows your coordinates and the cursor's. The label at the top names the zone under the cursor with its level range, using Leatrix's colour rule: red above your level, orange in your range, green or grey below.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 3.1 | Stand still on the big map and read the footer | It reads Player x, y and Cursor x, y. Your numbers match the game's world map or another coordinate addon to within 0.1. |  |
| 3.2 | Point at a spot you know, such as Whizzbuzz's dock in the Riverglades (79.4, 52.7) | The Cursor numbers match that spot. |  |
| 3.3 | Move the cursor off the map | Cursor shows --. |  |
| 3.4 | On a continent or Azeroth view, point at different zones | The Cursor numbers are for the zone under the cursor and switch as you cross a border. |  |
| 3.5 | Point at zones above, at and below your level | The label shows the zone name and its level range, red above you, orange in range, green or grey below. |  |
| 3.6 | Point at a zone with fishing, such as Stranglethorn Vale | A second line shows the fishing skill needed. |  |
| 3.7 | View a dungeon map | No zone label shows, because the floor bar names the floor. |  |
| 3.8 | Settings > Map > Big map (M): untick the coordinates option, then the zone label option, then tick both again | Each part disappears when unticked and comes back when ticked. |  |

## 4. Points of interest on continent and Azeroth views

On a continent or Azeroth view, only dungeon entrances, boats and zeppelins are shown, gathered from every zone. Mailboxes, innkeepers and bankers are left out on purpose, because there would be too many.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 4.1 | View Eastern Kingdoms | Dungeon entrance icons show across all its zones, in the right places (for example The Deadmines in Westfall, Scarlet Monastery in Tirisfal Glades). |  |
| 4.2 | Look at the harbours on the same view | Boats and zeppelins show at their docks and towers, such as Menethil Harbor, Booty Bay and Grom'gol. |  |
| 4.3 | View Azeroth | The same icons show on every continent. |  |
| 4.4 | Hover one of these icons | A tooltip names it. |  |
| 4.5 | Compare a continent view with a zone view | Mailboxes, innkeepers and bankers show in the zone view only. |  |
| 4.6 | Filters: turn off dungeon entrances, then turn them back on | They disappear from the continent view and come back. |  |
| 4.7 | Look for flight masters on a continent view | Not specifically built for wide views. Note whether they show and whether they're in the right places. |  |

## 5. Filters and the docked quest list

Quests pops the quest list out beside the big map. The docked list now closes whenever the big map does, including when M shrinks it.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 5.1 | Click Filters | The map's filter menu opens under the button, lined up with its left edge. Toggling a filter changes the map. Clicking Filters again closes it. |  |
| 5.2 | Click Quests with room on the right of the map | The quest list opens against the map's right edge, as tall as the map. |  |
| 5.3 | Make the map fill the screen, then click Quests | The list opens inside the map's top right corner instead. |  |
| 5.4 | Click Quests again | The list closes. |  |
| 5.5 | Dock the list, then press M | The map shrinks and the list closes with it; nothing is left floating. |  |
| 5.6 | Dock the list, then close the map with its close button | Both close. |  |
| 5.7 | Dock the list, then drag the map | The list moves with the map. |  |
| 5.8 | After 5.5, open the quest list the normal way (its key or button) | It opens at its own saved place and size, not docked. |  |

## 6. Big map themes

Settings > Style > Big Map Theme offers 16 choices: Leatrix's 15 map themes plus the plain Azeroth Atlas window skin. A theme only shows while the map is big.

### General

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 6.1 | Open Settings > Style | A row titled "Big Map Theme (when the map is big)" has 16 swatches. Hovering one shows its name. Blizzard is selected unless you had turned the old Blizzard frame checkbox off. |  |
| 6.2 | With the big map open, click a different swatch | The map changes straight away, with no reload. |  |
| 6.3 | Press M to shrink the map, then again to grow it | The small map has your normal window skin; the theme comes back when big. |  |
| 6.4 | Pick a theme and `/reload` | The same theme is still chosen and shown. |  |
| 6.5 | Open Continents, Zones and Dungeons under a few themes | The menus take the theme's colours. Under Azeroth Atlas they look like a normal tooltip. |  |
| 6.6 | Browse to another zone under a few themes | My Map's bronze tint is visible over every theme. |  |
| 6.7 | Open Settings > Map | The old "Blizzard-style frame" checkbox is gone; the coordinates and zone label options remain. |  |
| 6.8 | With a theme on, change Window Skin, then pick the Azeroth Atlas theme | The big map shows the new window skin, not the old one. |  |

### Each theme

| Theme | What to look for | Result |
| --- | --- | --- |
| Azeroth Atlas (window skin) | No theming: your window skin's frame, dark toolbar buttons with gold text. |  |
| Classic | Near-black title bar and footer, muted gold button edges, black frame edge. |  |
| Warm | Dark brown bars, bronze edges. |  |
| Charcoal | Cool slate-grey bars, blue-grey edges. |  |
| Class colour | A dark wash of your class colour; edges and button text in the colour. Try two classes. |  |
| Pink | Dark pink wash, pink edges and text. |  |
| Alliance | Dark blue wash, blue edges and text. |  |
| Horde | Dark red wash, red edges and text. |  |
| Purple | Dark purple wash, purple edges and text. |  |
| Teal | Dark teal wash, teal edges and text. |  |
| Green | Dark green wash, green edges and text. |  |
| Rainbow | A dark rainbow across the title bar and the coordinates bar. It still spans the full width after resizing the window. |  |
| Blizzard | The game's gold frame border, sitting on the window's edges; rock texture in the title bar and footer. |  |
| Glass | See-through frame background, a thin bright rim, a faint sheen across the top. |  |
| Handheld | A charcoal games console round the map: D-pad on the left, A and B on the right, red power light, speaker holes, "AZEROTH ATLAS · POCKET MAP" under the screen. Its buttons are only drawn. |  |
| Retro TV | Wood casing with a dark bezel; side panel on the right with two knobs, a grille and a power light; scanlines, darkened edges and glare over the map. Pins under the screen effects can still be hovered and clicked. |  |

## 7. Quest hover highlight

Hovering a quest in the quest list lights it up on the map: its pins grow, sit on top and glow, its areas are shaded strongly, and everything else fades back. It works with the list docked or not.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 7.1 | Hover a tracked quest with objectives in this zone | Its pins grow, sit above every other icon and glow in the quest's colour. Its areas are shaded strongly and drawn over other quests' areas. |  |
| 7.2 | Look at the rest of the map during 7.1 | Other quests' pins and areas, quest givers and dotted step lines are faded but still faintly visible. |  |
| 7.3 | Move the mouse off the list | The map goes back to normal straight away. |  |
| 7.4 | Hover a quest that's ready to turn in | Its turn-in pin grows with a gold glow. |  |
| 7.5 | Hover an untracked quest | Its pins and areas appear while hovered and go away afterwards. |  |
| 7.6 | Turn off quest objective pins in Filters, or quest areas in Settings, then hover a quest | The hovered quest still shows; the others stay hidden. |  |
| 7.7 | Hover a quest from another continent | The tooltip ends with "Not on the map on show". |  |
| 7.8 | Hover a quest with objectives in several places | Its numbered badges and dotted line stay bright; other quests' dotted lines are faint. |  |
| 7.9 | Hover a quest's tick box, then a zone header row | The tick box lights the quest up; the zone header doesn't. |  |
| 7.10 | On a crowded map (many quests, gathering nodes, services), dock the list and hover quests | The hovered quest is easy to pick out every time. |  |
| 7.11 | Run the mouse quickly up and down the list | No stutter and no Lua errors; the map settles on the last quest hovered or back to normal. |  |
| 7.12 | While hovering a quest, close the list with its key | The map goes back to normal. |  |

## 8. Twice Misplaced Trust turn-in (quest 97332)

The quest is picked up from Wharfmaster Lozgil in Booty Bay (26.4, 73.6) and handed in to Wharfmaster Whizzbuzz in the Riverglades (79.4, 52.7). The map used to show the turn-in back at Lozgil.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 8.1 | Pick up Twice Misplaced Trust from Lozgil | It's in your log and counts as ready to turn in straight away. |  |
| 8.2 | Look at the map in Booty Bay | No turn-in pin for this quest at Lozgil. |  |
| 8.3 | Route to the quest (click it in the list or tracker) | The caption reads "Turn in: Wharfmaster Whizzbuzz" and the arrow points towards the Riverglades. |  |
| 8.4 | View the Riverglades with the Zones menu | A turn-in pin sits at 79.4, 52.7. Hovering it shows "Turn in: Wharfmaster Whizzbuzz". |  |
| 8.5 | Type `/aatlas quest dump 97332` | The End line shows map 2548 at 79.45, 52.71. "resolved" names Wharfmaster Whizzbuzz via db-se. |  |
| 8.6 | Hand the quest in to Whizzbuzz | It leaves the log and its pins go. His own quests (Saltwater Savages and others) show his name, not "?". |  |
| 8.7 | Check a different quest that's ready to turn in | It still shows a turn-in pin. A quest our database has no turn-in for still uses the game's own marker. |  |

## 9. Flight master icons by faction

Settings > Style > Flight Master Icon now has two choices: the Tracking icon on every flight master, or Leatrix's taxi nodes by faction. The map only shows your own faction's flight masters and neutral ones.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 9.1 | Open Settings > Style > Flight Master Icon | Two swatches: Tracking Icon and "Taxi Nodes by faction (Leatrix)". |  |
| 9.2 | Pick Taxi Nodes by faction and look at a zone with your faction's flight master | It shows your faction's node: blue for Alliance, red for Horde. |  |
| 9.3 | Look at a neutral flight master (for example Booty Bay or Gadgetzan) | It shows the yellow neutral node. |  |
| 9.4 | Pick Tracking Icon | Every flight master goes back to the tracking icon. |  |
| 9.5 | On a profile that had Alliance, Horde or Neutral picked before this change, `/reload` | Taxi Nodes by faction is selected and the map shows per-faction icons. |  |
| 9.6 | Hover a flight master icon | The tooltip shows the flight point's name. |  |

## 10. Theme parts bin

The theme assets gathered for the final theming stage are data and image files only. Apart from the big map themes, they change nothing you can see, so these are file checks.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 10.1 | Open `Interface\AddOns\AzerothAtlas\Gfx\Themes\Leatrix\` | 12 images: ButtonBar, ButtonBarGlow, Close, Maximize, Minimize, TravelAlliance, TravelHorde, TravelNeutral, DungeonRaid, DragonGold, DragonSilver, DragonGrey. |  |
| 10.2 | Log in after a full restart | No Lua error mentions ThemeLibrary.lua. |  |
| 10.3 | Read `R:\addons\AzerothAtlas\Docs\Themes.md` (project folder only, not copied to the game) | It lists the 15 themes and the sliced icons. |  |

## 11. Risks and regression checks

These check that the new work didn't break the map you already had, and cover two behaviours nobody has decided yet.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 11.1 | Play normally with the small map for a while | It follows you, zooms and shows icons as before, with no toolbar or theme. |  |
| 11.2 | Enter and leave a dungeon with the map open, small and big | Dungeon floors draw as before. Leaving returns to the outdoor map. |  |
| 11.3 | Browse to another zone, then press M to shrink the map | Undecided: the small map may stay on the browsed zone. Note what happens and whether you'd want it to snap back to you. |  |
| 11.4 | Browse to another zone, then fly or hearth to a new zone | Undecided: note whether the map stays on the browsed zone or follows you. |  |
| 11.5 | Leave the big map on the Azeroth view for a few minutes | No noticeable frame-rate drop compared with a zone view. |  |
| 11.6 | `/reload` with the big map open and the list docked | No Lua errors. The map comes back working. |  |

Tests still open from the earlier [In-Game Test Plan](https://claude.ai/artifact/KcJ5gVfVbrXxePDbCH7SYT): dungeon tiles, portraits, boats and zeppelins, party badges and the quest right-click menu.
