# Alchemy GPS vs Carbonite — what Carbonite has that we don't (map and quests)

*Written 2026-11-18. Covers the map (`Carbonite`, plus the map-notes module `Carbonite.Notes`) and quests (`Carbonite.Quests`). Leaves out Carbonite's other modules (Info, Warehouse, combat graph, auction help).*

**How this was made.** I went through Carbonite's option pages, map menus and code in `R:\addons\Carbonite*`, then searched our code for each feature. Anything we already do is left out. Each item was checked by searching our code, so a few could be wrong. If you spot one we already have, strike it.

Our map engine is ported from Carbonite's, so the core map is shared: the seamless zone map, zoom and pan, goto with the ant trail, corpse tracking, group dots and gathering nodes. This list is everything around that core.

## Where we stand (updated 2026-11-18)

**Fully done items are removed from this list.** 24 of the original 70 are done: built and deployed, but not yet tested in game. Their checklist is `Docs/Testing/Carbonite-Features.md`. The numbers below keep their original values, so the gaps are those done items.

| | Partly ◐ | Still missing | Left |
|---|---|---|---|
| Part 1 — Map | 2 | 20 | 22 |
| Part 2 — Quests | 1 | 23 | 24 |
| **All** | **3** | **43** | **46** |

1.27 Node glow is **parked** (⏸): it's built but switched off, so it counts as missing ([issue #2](https://github.com/Digitl-Alchemyst/alchemy-gps/issues/2)).

- **Partly** rows: 1.7 (waypoint queue, no loop planning), 1.36 (other addons' pins, for addons that use HereBeDragons), 2.29 (quest-area opacity, no colours).
- What's left, grouped:
  - **Map:** the Guide window and vendor memory; multi-stop loops; click-through and Alt mode; health bar, second title line, saved zoom; icon sizes by type, fonts, tooltip placement, profiles; other users in the zone, level-ups, battleground tools, update check; minimap button bar and our own button; map notes; guide-addon arrows.
  - **Quests:** History and Database tabs; go to quest giver; auto-accept and auto turn-in; Blizzard auto-tracking; every tracker option (2.16–2.28); quest-area colours, giver level range, locked givers; objective capture; partial database loading.

---

## Part 1 — Map

### 1A. Finding places

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.1 | **Guide window** | A searchable panel beside the map that lists places by type. Click any entry to show it on the map or set a goto. Types: every class trainer, every profession trainer, stable masters, flight masters, innkeepers, bankers, auctioneers, mailboxes, anvils and forges, barbers, portals, boats, zeppelins, trams, dungeons and raids, gathering spots, and vendors you've visited. |
| 1.3 | **Visited-vendor memory** | Remembers every vendor you open and what they sell (the count is a setting), so you can find them again from the Guide. |
| 1.5 | **Kill icons** | Marks where you killed things. |

### 1B. Getting there

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.7 | ◐ *Partly, 2026-11-18.* **Multi-stop routes** | Builds the shortest loop through many points: all current gathering spots, a queue of goto targets, or unexplored spots. Options can reverse the loop, recycle reached stops, and set the gathering radius. *Ours now queues waypoints (`/way`, the map menu) and moves to the closest one left when you reach one. There's no planned loop, gathering loop or unexplored loop.* |

### 1C. Map window and behaviour

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.13 | **Ignore the mouse unless Alt is held** | Lets clicks go through the map to the game world. There are separate switches for the small and full-size map. |
| 1.16 | **Player health bar on the map** | A thin health bar on the map, with a thickness setting. |
| 1.17 | **Second title line** | Shows PvP status (contested, sanctuary, etc.) and the subzone under the zone name. |
| 1.18 | **Save / restore map zoom** | Remember a zoom level and jump back to it. It can also restore the zoom automatically when a track is cleared. |
| 1.20 | **Icon sizes by type and zoom** | Separate size sliders for party, raid, friend and zone dots, map icons, navigation icons and the player arrow. Each icon group (details, gathering, POI) also gets a zoom level where it appears. Ours has a gathering-icon size and the arrow scale only. |
| 1.22 | **Fonts** | Choose the font, size, spacing, outline and shadow for map text, map tooltips, menus and small text. |
| 1.23 | **Tooltip placement** | Choose where map tooltips anchor, and keep them above the map. |
| 1.24 | **Profiles** | Named settings profiles: create, copy between characters, reset, delete. |

### 1D. Gathering

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.27 | ⏸ *Parked 2026-11-18: built, but every possible node spot glowed (we can't tell which nodes are actually up), so it's switched off and its settings hidden. Tracked in [issue #2](https://github.com/Digitl-Alchemyst/alchemy-gps/issues/2).* **Node glow** | Gathering nodes on the minimap pulse; the pulse speed is a setting. |

### 1E. Other players and battlegrounds

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.29 | **Other users in your zone** | A zone channel shows other Carbonite users near you. |
| 1.30 | **Level-up notices** | Tells you in chat when a friend or guildmate levels. |
| 1.31 | **Battleground tools** | Your kills, deaths and honour per match. Auto-track friends in battlegrounds. Quick reports to chat (Incoming, Attack, Guard, Status). Capture and conflict bars under the map. |
| 1.32 | **Update check** | A global channel that tells you when a newer version is around. |

### 1F. Minimap buttons

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.33 | **Button-bar layout options** | Number of columns, button spacing, which corner the first button sits in, lock, and hide. It also lets you pick which Blizzard buttons go in (calendar, clock, world map, dungeon finder). Ours has the dock with a row or column switch. |
| 1.34 | **Own minimap button** | A Carbonite button. Left-click opens the map, Shift-click minimises it, middle-click opens the Guide, right-click opens a menu. |

### 1G. Map notes (the `Carbonite.Notes` module)

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.35 | **Your own map notes** | Put a note with an icon anywhere on the map. Notes go into folders, can be renamed, cut, copied and pasted, and there's a Find Note search. |
| 1.36 | ◐ *Partly, 2026-11-18 (through 1.19: addons that draw with HereBeDragons, such as Questie, HandyNotes and GatherMate2).* **Other addons' pins on the map** | Shows HandyNotes, RareScanner, Questie (objectives and available quests), RXPGuides and GatherLite icons on the Carbonite map, each with its own size. |
| 1.37 | **Guide arrows through the HUD** | RXPGuides' and Zygor's navigation arrows are replaced with Carbonite's arrow. |

---

## Part 2 — Quests

### 2A. Quest window

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.1 | **History tab** | Every quest you've finished, with a button to fetch your completed quests from the server and a way to mark a quest as done by hand. |
| 2.2 | **Database tab** | Browse every quest in the database, not just your log. Filters: low or high level, all zones, finished, this zone or continent only, nearer than a distance, hide 5-player group quests. Sort by distance, completion or level. |
| 2.8 | **Go to quest giver** | Set the arrow on the quest's giver from the list. |

### 2B. Automation

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.9 | **Auto-accept quests** | Accepts quests as soon as they're offered. |
| 2.10 | **Auto turn-in** | Hands quests in automatically, with a separate switch for quests that complete themselves. |
| 2.14 | **Turn off Blizzard's auto-tracking** | Stops Blizzard adding every new quest to its tracker. |

### 2D. Tracker (watch list)

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.16 | **Priority quests** | Pin a quest to the top of the tracker ("high watch priority"). |
| 2.17 | **Sort modes** | Sort by distance, by completion or by level. Ours sorts by distance. |
| 2.18 | **Hide in raids** | Hides the tracker in a raid. |
| 2.19 | **Grow upward** | New lines are added above instead of below. |
| 2.20 | **Fixed size** | The tracker can move but not resize. |
| 2.21 | **Objective layout options** | Hide finished objectives; show "4/10" before the text; choose the line-wrap length. |
| 2.22 | **Progress bars** | A percentage bar instead of "4/10". |
| 2.23 | **Colours** | Background, complete and incomplete quest colours, objective colours, and objectives coloured by how far along they are. |
| 2.24 | **Fonts** | Tracker font, size, spacing, outline and shadow. |
| 2.25 | **Item button settings** | Size (0 turns them off) and transparency for the usable-item buttons. |
| 2.26 | **Blizzard-style look** | Blizzard's tracker header and quest state icons. |
| 2.27 | **Close button and whole-window fade** | A close button on the tracker. When it fades, the text fades too, not just the background. |
| 2.28 | **Separate positions** | The full and minimised tracker can each keep their own spot on screen. |

### 2E. Quests on the map

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.29 | ◐ *Partly, 2026-11-18 (opacity slider only).* **Quest-area colours** | Up to 12 colours, one per quest, with a hover colour, opacity and a choice of fill graphic. *Ours now has an opacity slider (1.21). Colours and fill graphics are still fixed.* |
| 2.30 | **Quest giver level range** | Set how many levels below and above you to show quest givers for. Ours has a single "show low-level" switch. |
| 2.31 | **Locked quest givers: dim or hide** | Carbonite dims givers whose quests need an unfinished earlier quest and marks them "locked", or hides them if you choose. Ours always hides them. |

### 2F. Quest data

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.32 | **Objective capture** | Records where you kill or loot things for quests the database has no location for, to fill the gaps. |
| 2.33 | **Load the database by level range** | Load only part of the quest data to save memory. |

---

## Part 3 — Left out on purpose or not on WoW Forever

| Feature | Why it's not on the list above |
|---|---|
| 3D tilted map view | We decided not to build it. It's a non-goal in our map engine notes. |
| Docking the Blizzard minimap into the map, square minimap, minimap above icons | We replace Blizzard's minimap entirely, so there's nothing to dock. |
| World quests, bonus objectives, scenarios, achievements, challenge modes, archaeology, timber, artifacts | Not part of WoW Forever's game. |
| GatherMate2 live data | Removed on purpose because of the taint popup (see the TOC notes). The one-off import (1.26) covers it instead. |

---

## Biggest gaps left, in my view (updated 2026-11-18)

What I'd do next:

1. **Auto-accept and auto turn-in (2.9, 2.10).** Small to build, and people expect them.
2. **Go to quest giver (2.8).** Small, and it fits the arrow work just done.
3. **Quest window History and Database tabs (2.1, 2.2).**
4. **Guide window (1.1).** A searchable list of every place we already draw.
5. **Tracker options (2.16–2.22),** above all priority quests, sort modes and hiding finished objectives.
6. **Your own map notes (1.35).**
