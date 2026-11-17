# AlchemyGPS — Quest Tracking, Map Overlay & Routing Companion

Deep-dive research + build plan for the next major AlchemyGPS feature: a full
questing companion (on-screen tracker, map pin overlays, auto-routing arrow),
built by leaning hard on Carbonite's own code, with Questie and TomTom used
for UX inspiration/comparison rather than code ports.

## Decisions locked in (user confirmed)

1. **Replace Blizzard's native quest tracker** with our own ported/styled
   tracker (not run alongside it).
2. **Build all three pieces — tracker window, map pins, routing arrow — as
   one coordinated phase**, not sequenced one-at-a-time. (Still broken into
   small independently-testable steps _within_ that phase — see Build Order.)
3. **Include pickup ("available quest") map pins in v1 scope.** The earlier
   blocker (Questie's private `ZoneDB` dependency) is resolved — see Finding
   3 below — but read the caveat under Feature 3; the _data_ is a direct
   port, the _pin-placement logic_ is new code, not a Carbonite port.
4. **Scope stays on AlchemyGPS's own map/minimap window.** No Blizzard
   `WorldMapFrame` integration in this plan.

---

## Source survey — what's actually where

### AlchemyGPS today (the integration surface this plan builds onto)

- `Map/MinimapEngine.lua` is a single 252KB file holding every icon
  category (terrain tiles, player marker, service icons, gathering nodes,
  **and already** turn-in-only quest icons) as hand-rolled per-category
  `Refresh*`/`Update*` function pairs — no generic Pin/Layer/Renderer
  framework was ported (deliberate prior choice, each category was simple
  enough to hand-roll).
- **Turn-in markers already exist**: `RefreshQuestIcons` (`MinimapEngine.lua:3210`)
  calls `C_QuestLog.GetQuestsOnMap(mapId)` + `C_QuestLog.IsComplete(questID)`,
  gated by a Style-tab icon choice, refreshed on a 2s throttle +
  zone-change (`:5240-5244`) and once at login (`:4122`). `UpdateQuestIcons`
  (`:3234`) renders them through the same `CreateMiniFrame()` pool and
  `ClipFrameW` point-clip math every other icon category already uses
  (fixed-size, **not** zoom-scaled).
- `Map/FilterMenu.lua` has an established per-category checkbox pattern
  (`IsMapFilterOn(key)`, "missing key = on" convention) that gates
  gathering/service icons today — new quest-pin categories should plug into
  this same list, not invent a new one.
- `Map/MapContextMenu.lua` has the established pattern for per-layer
  sliders (brightness/opacity/scale) if quest-pin opacity controls are
  wanted.
- **No quest log/tracker window exists at all.** Would be new, built on
  `AlchemyGPS.UI.Window` (the same chrome `MinimapWindow.lua`/the Settings
  window already use).
- **No routing/waypoint arrow exists at all.** Entirely new HUD module.
- `Docs/QuestieIntegration.md` (written 2026-11-10) already explored and
  shelved the pickup-marker problem — its blocker is resolved below.

### Carbonite — the hard lean for code

Two separate, GPL-3.0-licensed addon folders (confirmed by reading each
`LICENSE` file directly):

**`Carbonite.Quests`** (own TOC family, own LICENSE) — the real quest
engine. It's mid-refactor by its own maintainers: a legacy `Nx.Quest` engine
(`NxQuest.lua`, `Init.lua`) plus a newer layer of small, cleanly-documented
public-API wrapper classes (`QuestRouting.lua`, `QuestWatchSurface.lua`,
`Plugin.lua`) sitting on top of it. **That wrapper-over-legacy-engine
pattern is itself a good template** for how AlchemyGPS should port this —
clean accessor functions over whatever internals we actually need, not a
wholesale line-for-line port of everything.

Key files, read directly, with real file:line citations:

- **`QuestCatalog.lua`** (~2000 lines) — a modern cache/reconciliation layer.
  Explicit design principle in its own header: _"Blizzard is the authority
  for mutable runtime quest state. Carbonite's bundled quest database
  remains versioned fallback knowledge... The two stores are intentionally
  separate and are never merged in-place."_ Has delta-signature change
  tracking (`BeginDelta`/`TrackRecordDelta`/`CommitDelta`, `:1195-1381`) so
  consumers only redraw what changed instead of rebuilding every tick —
  directly relevant since this plan bolts a tracker + 3 pin roles + an
  arrow all onto the same live quest state.
- **`Tracking.lua`** — the actual routing/target-resolution engine.
  `ResolveTrackTarget` (`:424`) is the core function: for an objective
  index, try `CatalogObjective` (bundled-DB coordinate, resolves "closest"
  copy for multi-spawn objectives) → fall back to `LiveTarget` (live
  Blizzard quest-POI position) → fall back to `CatalogEndpoint` (quest
  start/end NPC coordinate from the bundled DB). For a whole-quest route
  (no objective index): `CatalogEndpoint` OR `LiveTarget` (`:437`). Also
  resolves dungeon-entrance fallback when an objective is inside an
  instance you're not in (`resolveDungeonEntrance`, `:207`). `CalcAutoTrack`
  (`:468`) picks which watched quest gets the single "closest" auto-track
  slot by scanning every watched quest's nearest incomplete objective
  distance.
- **`SuperTrack.lua`** — bridges Carbonite's tracking state to Blizzard's
  _native_ `C_SuperTrack` API (`OnSuperTrackChanged`, `:702`), meaning
  Carbonite's blob/arrow rendering rides the same native system Blizzard's
  own tracker highlight and native waypoint arrow read. **Hard
  requirement, not optional**: both `QuestRouting.lua:51-58` and
  `QuestWatchSurface.lua:44-51/56-59` independently flag the same
  combat-taint hazard — an insecure `C_SuperTrack.SetSuperTrackedQuestID`
  call fires `SUPER_TRACKING_CHANGED` into taint and trips Blizzard's
  protected `SetPassThroughButtons` in `QuestDataProvider`. Both wrap every
  mutation through a `SuperTrackSafe`/`SetSuperTrackedQuestIDSafe` deferral.
  Port this wrapper verbatim; don't call the native API directly.
- **`MapIcons.lua`** (~2000 lines) — the live map-pin placement engine.
  `Nx.Quest:UpdateIcons(map)` (`:1039`, ~1000 lines) is confirmed built
  entirely on **live** Blizzard POI/quest-log data (`GetLiveQuestsOnMap`,
  `GetLiveTrackedQuestPOI`, `BuildLiveQuestPOIContext`) — matches what
  AlchemyGPS already built for turn-in icons. The bundled DB is **not**
  used here; it's only used by `Tracking.lua`'s routing fallback.
- **`Carbonite/Modules/Map/Pins/QuestPin.lua`** (modern Pin/Layer/Renderer
  rewrite, separate from the legacy `MapIcons.lua`) — a small, clean
  generic quest pin with exactly three roles and icons:
  ```
  giver     = "Interface\GossipFrame\AvailableQuestIcon"
  turnin    = "Interface\GossipFrame\ActiveQuestIcon"
  objective = "Interface\AddOns\Carbonite\Gfx\MMBut.tga"
  ```
  `drawMode = "WP"` (world-point) with `clipKind = "chop"` — confirmed via
  `Pin.lua:39` (`DEFAULT_CLIP_KIND`) this is a **fixed-size, non-zoom-scaled**
  point clip, i.e. **exactly** AlchemyGPS's existing `ClipFrameW` mechanism
  already used for the player marker and service icons. No new clipping
  math needed — this is a direct conceptual match, just feed it a third
  role.
  **Important finding**: `Plugin.lua:112-136`'s `MAP_REFRESH` subscriber
  only ever feeds this pin role `"objective"`, sourced from
  `Nx.Quest.Watched` (tracked quests only). **The "giver" role is defined
  in the icon table but nothing in the live codebase currently populates
  it as a map pin.** Confirms the correction below.
- **Pickup ("available quest") markers are _not_ a live map-pin feature in
  Carbonite today.** The actual mechanism for "what quests does this NPC
  offer" is a **tooltip**, not a pin: `Tooltips.lua:524`
  (`AddUnitQuestLines`) reads the mouseover/target unit's GUID → NPC ID →
  looks it up in `Nx.Units2Quests[npcID]`. That only works for an NPC
  you're already near enough to target/mouseover — there is no "a quest
  giver is somewhere in this zone" at-a-distance dot anywhere in the
  current Carbonite codebase.
- **However, the raw data needed to build real at-a-distance pickup pins
  does exist**, confirmed by reading an actual row:
  `Carbonite.Quests/Data/camelot/Quests1-10.lua:12-14`:
  ```lua
  [7] = {
      Quest = [=[Kobold Camp Cleanup|1|2|1|15|0|0]=],
      Start = "197|1429|32|48.92|41.61",   -- npcID|mapID|?|x|y
      End   = "197|1429|32|48.92|41.61",
      Objectives = { ... },
  }
  ```
  The file header reads _"Carbonite - Quest Data Level 1-10 (CLASSIC,
  Questie-merged)"_ — **Carbonite's own maintainers have already merged
  Questie's quest/NPC database into these plain static Lua tables**, GPL
  licensed, no live Questie/ZoneDB dependency. This is the single biggest
  finding of this research pass: the exact blocker that stalled pickup
  markers in `QuestieIntegration.md` is already solved upstream. **Caveat
  to verify empirically before trusting it**: it's not yet confirmed
  whether the `mapID` field in these packed strings (`1429` above) is
  Blizzard's modern uiMapID (what AlchemyGPS's own `GetWorldPos` expects)
  or Carbonite's own legacy internal zone ID — see Risks.
- Supporting static tables, all in `Data/camelot/`, all GPL, all plain Lua
  (no runtime dependency on Questie or GatherMate2-style live reads):
  `Units2Quests.lua` (NPC→quest-list, Questie-merged, 5667 entries),
  `QuestStartEndNPC.lua` (ID→display name, "Source: Questie database (with
  corrections) for NPC"), `QuestNPC.lua` (confusingly actually populates
  `Nx.QuestStartEnd` — kill-target/lootable-object name lookup, **not**
  coordinates — flag this naming mismatch so a future session doesn't
  re-trip on it), `QuestStartEndObject.lua`, `QuestStartEndItem.lua`,
  `QuestStartAlts.lua`/`QuestEndAlts.lua`, `QuestRequiredClasses.lua`, and
  `Data/Shared/{QuestCats,QuestDataLoader,QuestFreq,QuestPrev,QuestReward}.lua`
  (not yet read in depth — read `QuestDataLoader.lua` first thing in Build
  Step 1, since it's almost certainly the glue that unpacks all the above).
- **`TrackerHider.lua`** (~21KB) — already solves "hide Blizzard's native
  tracker cleanly" including Edit Mode compatibility and state capture for
  restore (`TrackerHider_Init/_SetRetailVisible/_ShouldHide/_BindEditMode/
_CaptureOriginal/_SetVisible/_HookFrame/_Apply`). This is a real, already
  -solved problem (Edit Mode interaction is genuinely fiddly) — port close
  to verbatim rather than reinvent, given this project's own hard-won
  lesson about re-deriving Carbonite behavior from scratch instead of
  porting it (the original reason this whole addon restarted from scratch
  — see `[[project_alchemy_gps]]`).
- **`WatchWindow.lua`** (153KB) — the actual tracker UI. **Too entangled to
  port line-by-line**: it's built on Carbonite's own decade-old
  `Button.TypeData` skin-table system (seen populated at length in
  `Init.lua:58-349` — dozens of custom button type definitions for header
  collapse/expand, watch-priority, auto-track, turn-in glow states, etc.)
  which AlchemyGPS has no equivalent of and shouldn't port wholesale just
  for this. **Recommendation: treat as a UX/behavior reference, not a code
  port** — build AlchemyGPS's own tracker on its existing `UI.Window`/
  `UI.Button` chrome, borrowing _behaviors_ (collapsible per-quest headers,
  priority sort, "+N more" cap instead of overflowing, click-to-track) from
  both `WatchWindow.lua` and Questie's cleaner modern equivalent below.

**Carbonite core HUD arrow** (`Carbonite/Modules/HUD/`):

- `HUDArrow.lua` — clean modern public accessor (`GetDirectionDegrees`,
  `GetDistanceYards`, `GetTargetName`, `GetETA`, `SetTexture`, `Show/Hide`).
  Good template for AlchemyGPS's own accessor shape.
- `HUD.lua` — module shell: saved-variable defaults (Enabled, ArrowStyle,
  Scale, ShowDistance, ShowETA, anchor, Locked), `/hud` slash, options page.
- `HUDEngine.lua:206-295` (`HUD:Update`) — the actual per-tick math.
  Rotation is screen-space, not 3D: `dir = (map.TrackDir - map.PlyrDir) %
360` (`:226`). Distance/ETA formatting, caption layout for multi-line
  objective names, a "within 5° = highlight color" cue (`:242`). This is a
  compact, well-isolated, directly portable module — moderate size, no
  entanglement with the legacy button-skin system `WatchWindow.lua` has.
  `map.TrackDir`/`PlyrDir`/`TrackDistYd`/`TrackETA`/`PlyrSpeed` are fields
  on Carbonite's per-tick map state object — AlchemyGPS already has
  `PlyrDir` (used for the player-marker rotation, per prior project
  history); `TrackDir`/`TrackDistYd`/`TrackETA` would be new fields derived
  from "current routed target's world position" vs. the player's own
  already-computed world position — ordinary bearing/distance trig, not a
  new technique for this codebase.

**TomTom integration layer** (`Carbonite/Modules/Integrations/TomTom.lua` +
`TomTomWaypoints.lua`) — Carbonite's own emulation of the real TomTom
public API (`_G.TomTom` with `AddWaypoint`/`SetCrazyArrow`/etc.), active
only when the real TomTom isn't loaded. Thin shim over Carbonite's own
routing/target primitives. **Not core to this plan** (flagged as an
optional fast-follow below) but documents TomTom's real public API surface
accurately, which is useful if we ever want third-party-addon compat.

### Questie — UX/behavior reference only (not a code-port target)

Modern, clean, module-based architecture (`QuestieLoader:CreateModule`,
confirmed via `Modules/Tracker/TrackerQuestieBehavior.lua`). Notably
separates "baseline tracker display record" from "Questie-specific
enrichment" (`TrackerQuestieBehavior.Apply`) — a cleaner separation of
concerns than Carbonite's legacy engine. Its `Modules/Tracker/` folder
(`TrackerLayout.lua`, `TrackerQuestFrame.lua`, `TrackerSuperTrack.lua`,
`Sorter/`) is worth a UX look when building AlchemyGPS's own tracker window
in Build Step 4, purely for layout/behavior ideas — not for code. Also
GPL-3.0 licensed (`gpl-3.0.md`/`LICENSE.md` present), so a direct port
would be license-compatible if ever wanted, but Carbonite's own
Questie-merged static data (above) already gives us the data half for
free without touching Questie's own (much more complex, QuestieLoader
-coupled) runtime code at all.

### TomTom standalone — UX reference only

`modules/crazy_arrow/crazy_arrow.lua` is the canonical "crazy arrow"
reference implementation (`OnUpdate:353`, rotation via live
`GetPlayerFacing()` each tick rather than Carbonite's `PlyrDir` field
abstraction). Comparative note only — Carbonite's `HUDEngine.lua` is the
better port target since it already matches AlchemyGPS's existing
per-tick-state-object convention. **License note**: prior project memory
flagged TomTom as "All Rights Reserved" in its TOC (not re-verified this
session) — irrelevant to this plan since we're only taking the UX concept,
not copying TomTom code, but don't copy any TomTom code verbatim without
re-checking that.

---

## Feature plan

### Feature 1 — Native tracker replacement

Port `TrackerHider.lua`'s approach for hiding Blizzard's tracker cleanly
(Edit Mode aware, state captured for restore). New `AlchemyGPS.db.profile`
toggle, same "missing key = on" convention as `MapFilters`.

### Feature 2 — Quest tracker window

New UI, not a port: a quest list window on `AlchemyGPS.UI.Window` chrome.
Behavior borrowed from both Carbonite's `WatchWindow.lua` (collapsible
headers, priority sort, "+N more" cap, click-to-track) and Questie's
`Modules/Tracker/` (cleaner modern layout ideas). Needs a quest-state cache
(new, lightweight — see Build Step 2) reading live `C_QuestLog`/
`C_QuestInfoSystem` state; does **not** need Carbonite's full
delta-signature perf machinery at v1 scale (that's a documented fast-follow
if frame-time issues actually show up).

### Feature 3 — Map pins: turn-in, objective, pickup

Extend the **existing** `RefreshQuestIcons`/`UpdateQuestIcons`
(`MinimapEngine.lua:3210/3234`) from turn-in-only to three roles, mirroring
`QuestPin.lua`'s `giver`/`turnin`/`objective` icon table, through the
**same** `CreateMiniFrame`/`ClipFrameW` pool every other icon category
already uses — no new rendering mechanism.

- **Turn-in + objective**: live-API driven (same pattern Carbonite's
  `MapIcons.lua` already proved), with the ported `CatalogObjective`/
  `CatalogEndpoint` fallback logic (from `Tracking.lua`) for cross-zone
  cases where the live POI isn't visible on the current map.
- **Pickup (giver)**: genuinely new logic (confirmed above — not a
  Carbonite port), using the ported static Questie-merged DB: for each
  catalog quest whose start-NPC zone matches the current map, is
  level-appropriate, and isn't already completed/in-log, plot a pin at its
  `Start` coordinate. Budget this as new code, not a port.

### Feature 4 — Routing / auto-track resolution

Port `ResolveTrackTarget`/`CalcAutoTrack` logic (`Tracking.lua:424/468`) —
catalog-objective → live → catalog-endpoint fallback chain, plus
dungeon-entrance resolution. No UI; a pure "what is my current routed
target's world position" resolver other features consume.

### Feature 5 — Native SuperTrack bridge

Wire Feature 4's resolved target to `C_SuperTrack.SetSuperTrackedQuestID`,
**combat-safe-deferred** exactly like `SuperTrackSafe` — this is the piece
that makes Blizzard's own native tracker-highlight/quest-blob follow our
chosen target instead of fighting it. Treat the taint wrapper as a hard
requirement per the Risks section, not best-effort.

### Feature 6 — HUD routing arrow

Port `HUDArrow.lua` (accessor shape) + `HUDEngine.lua:206-295` (rotation/
distance/ETA math) as a new floating frame on AlchemyGPS's own chrome, fed
by Feature 4's resolver and AlchemyGPS's own already-ported player
position/facing math.

### Feature 7 (fast-follow, not in this plan's core scope)

Manual waypoint set (right-click map → "set waypoint", modeled on
`NxQuest.lua:612-693`'s `TrackUserWaypoint`/`SeedUserWaypoint` dedupe
pattern) so the arrow isn't quest-only. TomTom public-API emulation
(`_G.TomTom` shim) for third-party addon compatibility, relevant given the
project's explicit goal of eventually letting the user drop Carbonite
entirely. Carbonite's full delta-signature cache if perf ever demands it.
World Quest tracker (`WorldQuestWindow.lua`) — likely irrelevant to WoW
Forever's content era, skip unless asked.

---

## Build order (one coordinated phase, small testable steps within it)

1. **Quest data foundation** — port the static DB files into
   `Quest/Data/*.lua` (renamed globals, e.g. `AlchemyGPSQuestDB`, to avoid
   any future collision the way the gathering-node saga already taught
   this project to avoid) + a thin accessor `Quest/QuestCatalog.lua`
   (`GetQuestStart/End/Objective(questID, ...)`). Read
   `Data/Shared/QuestDataLoader.lua` first to understand the real unpacking
   format before porting. No UI — testable via `/gps` debug dump.
   **First thing to verify here**: dump a few known quests' `Start` coords
   and confirm the packed `mapID` field is a real uiMapID AlchemyGPS's own
   `GetWorldPos` resolves correctly (see Risks) before building anything on
   top of it.
2. **Live quest-state cache** — new `Quest/QuestState.lua`, event-driven
   (`QUEST_LOG_UPDATE` etc.), exposing `GetWatchedQuests()`/
   `GetObjectiveProgress(questID)`/`IsComplete(questID)`.
3. **Native tracker hider** — port `TrackerHider.lua`'s approach. Smallest
   standalone risk-reduction step; testable alone.
4. **Quest tracker window v1** — new `Quest/QuestTracker.lua` + window on
   existing `UI.Window` chrome, reading Step 2's cache.
5. **Turn-in + objective map pins** — extend the existing
   `RefreshQuestIcons`/`UpdateQuestIcons` to all three roles.
6. **Pickup map pins** — new logic consuming Step 1's catalog.
7. **Filter menu + style integration** — new pin categories into
   `FilterMenu.lua`'s existing pattern; opacity/scale sliders into
   `MapContextMenu.lua` if wanted.
8. **Routing resolver** — port `ResolveTrackTarget`/`CalcAutoTrack`.
   Testable via debug print of resolved target vs. manual expectation.
9. **Native SuperTrack bridge** — combat-safe-deferred wiring. Testable by
   confirming Blizzard's own tracker highlight/quest blob follows our pick,
   and nothing taints in combat.
10. **HUD routing arrow** — new frame fed by Step 8.
11. **Full regression pass** — same Step-E discipline as the minimap build:
    fresh client restart, zero Lua errors through login/zone-change/every
    window, byte-identical source↔deployed tree check, walk every new
    surface back to back in one sitting.

---

## Risks / things to verify live, not guess

- **MapID format in the bundled DB**: `Nx.Map:GetWorldPos(zone, x, y)` in
  Carbonite's own `CatalogEndpoint` may expect Carbonite's own legacy
  internal zone ID, not Blizzard's modern uiMapID — unconfirmed. A silent
  mismatch here would misplace pins the same way the detail-tile anchor-
  index bug once did. Verify with real data before trusting it (Build Step 1).
- **Combat taint around SuperTrack** is independently flagged twice in
  Carbonite's own source — treat the safe-deferral wrapper as mandatory,
  first-class code, not an afterthought.
- **Performance**: a full quest log can have 20-35 active quests with
  multiple objectives each. Don't build a new per-frame `OnUpdate` loop for
  this — reuse the event-driven + throttle pattern already proven for
  turn-in icons (2s throttle + zone-change + login).
- **Tracker UI will not look pixel-identical to Carbonite's** — that's a
  deliberate choice (its UI is entangled with a legacy button-skin system
  not worth porting), not an oversight. Set that expectation now so it's
  not a surprise during a later live-test round.
- **Pickup pins are new code**, not a port — don't budget them like the
  gathering-node data port (which was close to a direct lift); the
  placement _logic_ has no existing Carbonite implementation to copy.

## Licensing

Both Carbonite and Carbonite.Quests ship GPL-3.0 (confirmed by reading
each `LICENSE` file directly this session). Questie is also GPL-3.0.
Consistent with this project's existing practice of porting Carbonite code
directly. If AlchemyGPS is ever published/redistributed, GPL requires
source availability for the whole addon — a reminder, not a blocker for
personal use (same note already on file from the original Carbonite-port
work).
