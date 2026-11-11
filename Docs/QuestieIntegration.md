# Questie integration notes — for GitHub issue #1 ("available quest" markers)

Everything learned investigating this during the step 9c (quest icons)
build-out, 2026-11-10, so the next pass doesn't have to re-derive it
from scratch. This is reference material, not a plan — see the GitHub
issue itself for the three options and the decision still to be made.

## What this addon already has (no Questie needed)

Turn-in markers (`RefreshQuestIcons`/`UpdateQuestIcons` in
`Map/MinimapEngine.lua`, step 9c) use only live, standard Blizzard
APIs, confirmed current by reading `Carbonite.Quests/MapIcons.lua`
(an already-installed, already-working, 2000+-line quest-map-icon
addon on this same server):

- `C_QuestLog.GetQuestsOnMap(uiMapId)` — returns quest POIs
  (questID, x, y normalized 0-1) directly in this engine's own
  uiMapID. No external database, no ID conversion. Per Carbonite's own
  comment, this is "shared by all clients" — a genuine stable API.
- `C_QuestLog.IsComplete(questID)` — turn-in-ready check.
- `C_QuestLog.GetNextWaypointForMap(uiMapId)` — retail-only, for the
  currently super-tracked/focused quest. Not used by this addon yet.

None of this needs Questie, QuestieDB, or any AreaID conversion. This
is why the turn-in half was buildable in one session and the pickup
half isn't.

## Why "available quest" markers are hard

Blizzard has no live API for "this NPC offers a quest you haven't
picked up yet." That's not something you can query from the quest log
(you don't have the quest yet) — it requires a static NPC → quest
database, matched against what's already in your log/completed log to
know what's still available.

## QuestieDB — the public, usable half

`g:\World of Warcraft\_forever_\Interface\AddOns\QuestieDB\src\api.lua`
exposes a genuine, versioned, public contract: `LibQuestieDB`, with
`RequireContract` for version-checking. Entity types: `NpcDB`,
`QuestDB`, `ItemDB`, `ObjectDB`.

`NpcDB` schema (confirmed via
`QuestieDB\src\meta\npcMeta.lua`):
- `name`
- `spawns` — per-zone x,y spawn coordinates, **keyed by legacy AreaID**
- `questStarts` / `questEnds` — arrays of quest IDs
- `zoneID`
- `friendlyToFaction`

Access mechanics (confirmed via `QuestieDB\src\read\shared.lua`):
`GetAllIds`, `Get`, standard entity-table accessors — straightforward
to use once you have an AreaID to query by.

**This part is safe to depend on.** It's public, versioned, and has a
real compatibility contract.

## The blocker — AreaID vs. uiMapID

`NpcDB.spawns` keys positions by legacy **AreaID** (the old
pre-Dragonflight zone-ID system). This addon's own map system
(`Map/Data/NxMapData.lua`, `MinimapEngine.lua`) uses modern
**uiMapID** everywhere, same as every live Blizzard API this addon
calls elsewhere (`C_Map.*`, `C_QuestLog.*`, `C_TaxiMap.*`).

Converting between the two requires Questie's own **private,
undocumented** `ZoneDB` module:

`g:\World of Warcraft\_forever_\Interface\AddOns\Questie\Database\Zones\zoneDB.lua`
- Exposes `ZoneDB:GetUiMapIdByAreaId` / `ZoneDB:GetAreaIdByUiMapId`.
- The canonical `areaIdToUiMapId` table is **assembled at runtime from
  an internally-encoded/decoded blob**, not a plain static Lua table
  you could safely copy out and vendor. Not part of `LibQuestieDB`'s
  public contract at all.

Confirmed this is a real, load-bearing dependency even for Questie's
own code, not just a theoretical risk: read
`g:\World of Warcraft\_forever_\Interface\AddOns\Questie\Modules\QuestiePlayer.lua`'s
`GetCurrentZoneId()` — even Questie's own mature, in-production
zone-resolution logic depends on this private `ZoneDB` module for
this exact conversion, with a documented fallback to **name matching**
(`C_Map.GetAreaInfo` / `GetRealZoneText()`) when no static entry
exists. If Questie's own code needs a fallback, the static table isn't
even 100% complete.

### Two other files checked, ruled out as shortcuts

- `QuestieDB\src\support\eraToForever.lua` — a narrow **coordinate
  scale-correction** table (adjusts x/y for continent-scale
  differences between client flavors), not a general AreaID↔uiMapID
  converter. Doesn't help here.
- `QuestieDB\support\Forever\Zones\uiMapIdToAreaId.lua` — a small
  "override"/handoff supplement (~117 lines, confirmed via `wc -l`),
  not the comprehensive canonical table. Covers edge cases Questie's
  own main table gets wrong on this specific server flavor — useless
  without the main table it's patching.

## Options going into the next pass (see GitHub issue #1 for details)

1. **Depend on QuestieDB + Questie's private `ZoneDB` anyway.** Fast,
   but genuinely fragile — `ZoneDB` could change shape or vanish on a
   Questie update with zero warning, and we'd have no contract to rely
   on. If chosen: wrap every call through it in `pcall`, and have a
   graceful "pickup markers just don't show" fallback rather than
   erroring, since this addon doesn't control Questie's release cycle.
2. **Build an independent static NPC/quest database** scoped to this
   addon, using uiMapID from the start. No fragile dependency, but a
   real separate data-sourcing effort (hand-authored or scraped from
   somewhere), likely significant in scope — comparable to how
   Carbonite's own `GuideLocations.lua` mailbox/innkeeper/flight data
   was hand-curated.
3. **Skip permanently**, treat turn-in-only as sufficient v1 scope.

No recommendation is locked in — this still needs a real decision, not
a default. Whoever picks this issue back up should re-confirm Questie
is still installed on the server and `ZoneDB`'s shape hasn't changed
before building on option 1, since none of this was re-verified after
2026-11-10.

## Full file reference list (all read in full or in large part, 2026-11-10)

- `QuestieDB\src\api.lua` — public contract shape.
- `QuestieDB\src\meta\npcMeta.lua` — `NpcDB` schema.
- `QuestieDB\src\read\shared.lua` — entity-access mechanics.
- `QuestieDB\src\support\eraToForever.lua` — coordinate-scale table, not an ID converter.
- `QuestieDB\support\Forever\Zones\uiMapIdToAreaId.lua` — small override supplement.
- `Questie\Database\Zones\zoneDB.lua` — private `ZoneDB`, ~500 lines read.
- `Questie\Modules\QuestiePlayer.lua` — `GetCurrentZoneId()`, proof `ZoneDB` is load-bearing even for Questie itself.
- `Carbonite.Quests\MapIcons.lua` — confirmed `C_QuestLog.GetQuestsOnMap`/`IsComplete`/`GetNextWaypointForMap` as the live, no-database path (this is what step 9c's turn-in markers are built on).

All paths above are under
`g:\World of Warcraft\_forever_\Interface\AddOns\`.
