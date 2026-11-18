# Alchemy GPS vs Carbonite — what Carbonite has that we don't (map and quests)

*Written 2026-11-18. Covers the map (`Carbonite`, plus the map-notes module `Carbonite.Notes`) and quests (`Carbonite.Quests`). Leaves out Carbonite's other modules (Info, Warehouse, combat graph, auction help).*

**How this was made.** I went through Carbonite's option pages, map menus and code in `R:\addons\Carbonite*`, then searched our code for each feature. Anything we already do is left out. Each item was checked by searching our code, so a few could be wrong. If you spot one we already have, strike it.

Our map engine is ported from Carbonite's, so the core map is shared: the seamless zone map, zoom and pan, goto with the ant trail, corpse tracking, group dots and gathering nodes. This list is everything around that core.

---

## Part 1 — Map

### 1A. Finding places

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.1 | **Guide window** | A searchable panel beside the map that lists places by type. Click any entry to show it on the map or set a goto. Types: every class trainer, every profession trainer, stable masters, flight masters, innkeepers, bankers, auctioneers, mailboxes, anvils and forges, barbers, portals, boats, zeppelins, trams, dungeons and raids, gathering spots, and vendors you've visited. |
| 1.2 | **Trainer icons** | Class trainers and profession trainers drawn on the map, each with an on/off switch. |
| 1.3 | **Visited-vendor memory** | Remembers every vendor you open and what they sell (the count is a setting), so you can find them again from the Guide. |
| 1.4 | **Subzone names on the map** | Draws area names like Goldshire or Stormwind Harbor on the map once you zoom in far enough. |
| 1.5 | **Kill icons** | Marks where you killed things. |

### 1B. Getting there

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.6 | **Travel routing with flight paths** | For a goto in another zone, Carbonite plans the trip: fly from this flight master to that one, take this boat or portal, then walk. It learns which flight masters you know by reading the taxi window. Ours points straight at the target. |
| 1.7 | **Multi-stop routes** | Builds the shortest loop through many points: all current gathering spots, a queue of goto targets, or unexplored spots. Options can reverse the loop, recycle reached stops, and set the gathering radius. Ours handles one goto at a time. |
| 1.8 | **Auto-track your flight destination** | When you take a flight, the arrow switches to where you're flying. |
| 1.9 | **TomTom emulation** | Pretends to be TomTom, so `/way` and other addons (Questie, guides) can send waypoints to Carbonite's arrow. Ours has no `/way` and doesn't accept waypoints from other addons. |
| 1.10 | **Track a player** | Right-click a party, raid or friend dot to set the arrow on them. The same menu offers Whisper, Invite and Report AFK. |
| 1.11 | **HUD arrow extras** | A choice of arrow art, X/Y offset, a direction-text line, a click-to-target button that targets the NPC you're heading to, and hiding the arrow in battlegrounds. Ours has show, lock, size, distance, time and an arrival sound. |

### 1C. Map window and behaviour

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.12 | **Mouse-button actions you set yourself** | Choose what Alt/Ctrl plus left, middle, right or button-4 clicks do on the map (goto, menu, zoom, show your zone, and so on). |
| 1.13 | **Ignore the mouse unless Alt is held** | Lets clicks go through the map to the game world. There are separate switches for the small and full-size map. |
| 1.14 | **Hide the map in combat** | Closes the big map when you enter combat. |
| 1.15 | **Movement trail** | A breadcrumb trail of dots showing where you've walked. You set the spacing, the number of dots and how long they last. |
| 1.16 | **Player health bar on the map** | A thin health bar on the map, with a thickness setting. |
| 1.17 | **Second title line** | Shows PvP status (contested, sanctuary, etc.) and the subzone under the zone name. |
| 1.18 | **Save / restore map zoom** | Remember a zoom level and jump back to it. It can also restore the zoom automatically when a track is cleared. |
| 1.19 | **Bring Blizzard's map pins in** | Moves anything other addons draw on Blizzard's world map onto the big Carbonite map. |
| 1.20 | **Icon sizes by type and zoom** | Separate size sliders for party, raid, friend and zone dots, map icons, navigation icons and the player arrow. Each icon group (details, gathering, POI) also gets a zoom level where it appears. Ours has a gathering-icon size and the arrow scale only. |
| 1.21 | **Transparency by layer** | Sliders for detail tiles, fade-in/out, POI icons, unexplored areas and quest areas. Ours has brightness per layer and gathering-icon opacity. |
| 1.22 | **Fonts** | Choose the font, size, spacing, outline and shadow for map text, map tooltips, menus and small text. |
| 1.23 | **Tooltip placement** | Choose where map tooltips anchor, and keep them above the map. |
| 1.24 | **Profiles** | Named settings profiles: create, copy between characters, reset, delete. |

### 1D. Gathering

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.25 | **Record the nodes you gather** | Saves every herb, ore or other node you pick, building your own database alongside the shipped one. You can delete each type separately. |
| 1.26 | **Import from GatherMate2_Data** | Pulls herb, mining and misc nodes from the GatherMate2_Data addon. *We chose static Wowhead data on purpose because of the taint popup, so this one stays a deliberate gap.* |
| 1.27 | **Node glow** | Gathering nodes on the minimap pulse; the pulse speed is a setting. |

### 1E. Other players and battlegrounds

| # | Feature | What it does in Carbonite |
|---|---|---|
| 1.28 | **Friends on the map** | Shows friends-list players running Carbonite, as well as guildmates. Ours shares with guild and group only. |
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
| 1.36 | **Other addons' pins on the map** | Shows HandyNotes, RareScanner, Questie (objectives and available quests), RXPGuides and GatherLite icons on the Carbonite map, each with its own size. |
| 1.37 | **Guide arrows through the HUD** | RXPGuides' and Zygor's navigation arrows are replaced with Carbonite's arrow. |

---

## Part 2 — Quests

### 2A. Quest window

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.1 | **History tab** | Every quest you've finished, with a button to fetch your completed quests from the server and a way to mark a quest as done by hand. |
| 2.2 | **Database tab** | Browse every quest in the database, not just your log. Filters: low or high level, all zones, finished, this zone or continent only, nearer than a distance, hide 5-player group quests. Sort by distance, completion or level. |
| 2.3 | **Party tab** | See your party members' quest logs, or only the quests you share. Ours shows party progress in tooltips only. |
| 2.4 | **Search box** | Type to filter the quest list. |
| 2.5 | **Details beside the list** | Quest text in a side panel, with a parchment background, and colour and scale settings. Ours opens the text under the quest. |
| 2.6 | **Quest IDs, chain parts, dailies** | Shows the quest ID and "Part 2 of 4" for chains. Also counts dailies done and the time to the daily reset. |
| 2.7 | **Links** | Shift-right-click puts a quest link in chat. Quest links can carry level and part number. You can also copy a Wowhead link. |
| 2.8 | **Go to quest giver** | Set the arrow on the quest's giver from the list. |

### 2B. Automation

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.9 | **Auto-accept quests** | Accepts quests as soon as they're offered. |
| 2.10 | **Auto turn-in** | Hands quests in automatically, with a separate switch for quests that complete themselves. |


| 2.12 | **Progress messages to the group** | Says in party or raid chat when you finish objectives, after a set number of changes. Ours shares progress silently between our users. |
| 2.13 | **Quest-complete sound** | Plays a sound when a quest completes, chosen from 8 (peon "work complete", dwarf "well done", and so on). |
| 2.14 | **Turn off Blizzard's auto-tracking** | Stops Blizzard adding every new quest to its tracker. |

### 2C. Tooltips

| # | Feature | What it does in Carbonite |
|---|---|---|
| 2.15 | **Quest info on mob and item tooltips** | Hovering a mob or item shows which quest needs it and your progress (for example "Kobold Vermin: 4/10"). Ours adds nothing to the game's tooltips. |

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
| 2.29 | **Quest-area colours** | Up to 12 colours, one per quest, with a hover colour, opacity and a choice of fill graphic. Ours shades areas in one fixed style. |
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
| GatherMate2 live data | Removed on purpose because of the taint popup (see the TOC notes). Import (1.26) is listed above for completeness. |

---

## Biggest gaps, in my view

1. **Quest info on mob and item tooltips (2.15).** Players notice it every few seconds.
2. **Travel routing with flight paths (1.6)** and **TomTom / `/way` support (1.9).** These make the arrow far more useful.
3. **Guide window and trainer icons (1.1, 1.2).**
4. **Quest window History and Database tabs, plus search (2.1, 2.2, 2.4).**
5. **Auto-accept and auto turn-in (2.9, 2.10).** Small to build, and people expect them.
