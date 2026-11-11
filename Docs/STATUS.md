# Alchemy GPS — Project Status

**Snapshot date: 2026-11-10.** This is a living audit document, not a
changelog (see `../CHANGELOG.md` for the dated history of individual
fixes) — update it whenever the roadmap below advances a step.

## TL;DR

The addon boots clean, the ported minimap window works (chrome, zoom,
pan, resize, real world-art background, player marker, service/quest/
gather icons), and three features beyond the original build plan's
scope have also been built and are working in-game: a right-click
tile-brightness menu, a minimap icon dock (addon/Blizzard button
collector), and a native-mail-button forward with a working icon.
What's left to reach "done": confirm Phase 5-8 testing formally, add
the Ctrl+Shift+M keybind, and run one real deploy+regression pass. See
`ROADMAP.md` for the ordered plan.

**2026-11-10, same-day amendment**: the "live Blizzard widget blend"
row below (step 4) describes a mechanism that no longer exists.
Removed entirely — the window never reparents or blends in the real
Minimap widget anymore; it's a self-contained tile canvas only. This
was removed on strong, specific evidence it was the cause of a
recurring GatherMate2 taint popup (`mm:SetParent(UIParent)`, a
protected-frame call, touching the same widget GatherMate2 parents its
own pins to) — **confirmed by live re-test NOT to have fixed it**,
along with 8 further rounds of fixes and isolation tests (see
`CHANGELOG.md`'s round-9 entry). The actual root cause was never
conclusively found. GatherMate2 integration was dropped entirely as a
result — see item 10 further down and `CHANGELOG.md` for the full
history. The live-widget removal itself stands regardless (it was also
the direct, confirmed cause of a separate bug: the "Hide Blizzard
minimap" checkbox not remembering its state across reload).

## Build-order status against the original plan (`../../AlchemyGPS-Plan.md`)

| # | Step | Status |
|---|------|--------|
| 1 | Addon skeleton boots cleanly | **Done.** `/gps` slash, SavedVariables, zero-error login — never regressed since. |
| 2 | Native-hide toggle in isolation | **Done**, now exposed via the Settings window checkbox, not just a temp slash command. |
| 3 | Window chrome only (`Nx.Window` port + Settings window) | **Done.** `UI/Window.lua` (2029 lines, the real ported chrome), `Settings/SettingsWindow.lua`. |
| 4 | Live Blizzard widget blend (`ClipMMW` etc.) | **Removed, 2026-11-10** (see TL;DR amendment above) — the real Minimap widget is never reparented/blended in anymore; suspected (not confirmed) as the GatherMate2 taint popup's cause, fixed a separate real bug either way ("Hide Blizzard minimap" not persisting). |
| 5 | Zoom (wheel + buttons) | **Built; test doc exists (`Docs/Testing/Phase5-Zoom.md`), pass/fail not yet formally confirmed back in writing.** |
| 6 | Pan-drag | **Built; test doc exists (`Phase6-PanDrag.md`), same confirmation gap as Phase 5.** |
| 7 | Resize correctness | **Built; test doc exists (`Phase7-Resize.md`), same confirmation gap.** |
| 8 | Real world-art canvas | **Built; test doc exists (`Phase8-WorldArtCanvas.md`), same confirmation gap.** Also received a significant post-build fix pass this session (see below), plus a brand-new third visual layer (the real-terrain "detail tile" system, step 8b) - neither covered by the original Phase 8 doc. |
| 9 | Keybind + polish (Ctrl+Shift+M, `Bindings.xml`) | **Not started.** Window/anchor size *is* already persisted across `/reload` via `AlchemyGPS.db.profile.WindowLayouts` (`UI/Window.lua`) — that half of "polish" is done; the keybind itself is not. |
| 10 | Deploy + real in-game test pass | **Ongoing in practice** (every change this session was deployed and live-tested individually) **but never run as one dedicated final pass** across the whole feature set at once. |

**Bottom line on 5-8**: all four are implemented and have been
live-tested piecemeal while chasing specific bugs (see `CHANGELOG.md`),
but nobody has walked the four `Docs/Testing/Phase*.md` checklists
test-by-test and recorded a clean pass. That walk-through is the
immediate next step — see `ROADMAP.md`.

## Built beyond the original plan's scope

The original plan's non-goals list explicitly excluded one thing that
ended up getting built anyway, plus two features the plan never
anticipated at all. All three are real, working, user-facing parts of
the addon now — this status doc (and the roadmap) treats them as
permanent scope, not as scope creep to be walked back.

- **Minimap icon dock** (`Map/MinimapDock.lua`, 516 lines). The
  original plan named this an explicit non-goal ("the minimap button
  dock (`Nx.Map.Dock`) — unrelated to the map window despite the
  similar name"). Built anyway once real use made clear the user
  wanted other addons' (and Blizzard's own) minimap buttons collected
  somewhere after the native minimap gets hidden. Went through several
  real bug rounds (stray `MinimapBackdrop` coordinate-text sliver,
  native zoom buttons mistaken for addon icons, real addon icons stuck
  in an infinite retry and never appearing) — all fixed and confirmed
  live, see `CHANGELOG.md`'s "Minimap icon dock" section. Orientation
  (row/column) is user-configurable from the Settings window.
- **Native mail-button forwarding + icon** (also `MinimapDock.lua`).
  Not in the original plan at all. Forwards
  `MinimapCluster.IndicatorFrame.MailFrame` (this client's modern
  button location, not the old `MiniMapMailFrame` global) into the
  dock, keeping its working hover/tooltip, with a custom overlay icon
  (`Interface\Icons\INV_Letter_15` — Blizzard's own
  `Interface\Minimap\MiniMap-MailIcon` art was confirmed live not to
  exist on this client build at all) and `HasNewMail()`-driven
  show/hide, matching real Carbonite's own `MailboxNotice` module's
  philosophy of not trusting the native frame's own visibility.
  **Confirmed working live, 2026-11-10** (this session's final fix).
- **Right-click tile-brightness menu** (`Map/MapContextMenu.lua`, new
  file, not in the original plan). A small popup on the map window
  with four sliders now (2026-11-10): tile-map brightness (0-100%),
  and three more added the same day for the gathering-node icons -
  opacity, size (50%-300%), and a separate backdrop-halo opacity (the
  halo's corner rounding matches the real map window's own chrome,
  `AlchemyGPS.Skin:GetBackdrop()`). Dismissed by clicking anywhere
  outside it (a polling approach, not an overlapping catcher frame,
  after the catcher tripped a Blizzard taint warning) or by
  right-clicking the map again.
- **Map filter button + menu** (`Map/FilterMenu.lua`, new file,
  2026-11-10, not in the original plan). A "Filter" title-bar button
  opens a small checklist popup - same plain-frame pattern as the
  brightness menu above, explicitly not Blizzard's own dropdown
  system (user's own direction) - with one checkbox per icon category:
  Gathering Nodes (Herb/Mine/Fish combined), Treasure (separate,
  not profession-gated), Flight Masters, Innkeepers, Mailboxes.
  Persisted per-key (`AlchemyGPS.db.profile.MapFilters`), missing key
  means visible. Toggling calls straight into `MinimapEngine.lua`'s own
  `RefreshGatherIcons`/`RefreshServiceIcons` for instant effect, not
  just at the next zone change.

## Fixes layered on top of the original Phase 5-8 implementation

Live testing this session surfaced and fixed several bugs in already
"built" phases that the original Phase 5-8 test docs don't describe,
because they predate this fix pass:

- A leftover placeholder texture (pre-dating the real Phase 8 canvas)
  was still painting a solid dark color over the real world-art tiles
  every tick, regardless of brightness — this, not the brightness
  slider itself, was the actual cause of "brightness does nothing, map
  stays black."
- The live-widget-fill math was rewritten from a 6-step fixed preset
  search (real Carbonite's own `MMScales`) to a direct
  fill-the-window calculation, fixing visible bounce when zoomed in
  and stepped jumps when resizing. A 10% fit margin was added after
  the live widget was found to disappear entirely inside Orgrimmar
  (city sub-zones apparently drift slightly off the open-world
  position convention this engine assumes) and reappear outside it.
- The minimap mask was switched from Blizzard's round mask to a square
  one, since the round mask was cropping the live-rendered patch down
  from the same square footprint the background art already filled.
- Blizzard's own minimap zoom level is now kept in sync with the
  window's zoom buttons/wheel — previously only the background
  world-art reacted to zoom.

None of these are covered by the existing Phase 5/7/8 test docs as
written. See `ROADMAP.md` for the recommendation to re-run those
checklists now that these fixes are in, rather than treating the
original docs' pass/fail as still valid against today's code.

## Known open issues

1. **Resolved, 2026-11-10.** Reproduced with the exact error —
   `MapContextMenu.lua:93: attempt to call a nil value`, firing every
   `OnUpdate` tick (Count: 1628) while the brightness menu was open —
   confirming the leading suspect from earlier this session. Root
   cause: the global `MouseIsOver()` function doesn't exist on this
   server's client build (same pattern as this session's other
   missing-default-Blizzard-asset finds — the native mail icon
   texture). Fixed by switching to the frame's own `:IsMouseOver()`
   method instead, which doesn't depend on that global.
2. **No formal Phase 5-8 pass/fail record.** See build-order table
   above — functionally working, never walked as a checklist.
3. **Phases 1-4 and the three beyond-scope features have no dedicated
   test docs at all** (`Docs/Testing/` only covers 5-8). Not urgent —
   none of the four has an open bug right now — but worth closing
   before calling the module "done," since every other phase has one.
4. **No real indoor/instance zone support.** Building interiors
   (confirmed with the Freewind Post inn, 2026-11-10) mostly aren't in
   Carbonite's static camelot-flavor zone catalog, so the background
   world-art correctly goes blank there (by design — see
   `RefreshCurrentZone`'s own comment) and the view *freezes* at the
   last good outdoor position instead of jumping to noise (see
   `CHANGELOG.md`). It still doesn't track real indoor movement. (The
   live-widget patch this was originally written against no longer
   exists at all — see this file's TL;DR amendment, 2026-11-10 — but
   the same freeze-gate still applies to the tile canvas/player marker.)
   Carbonite's real fix for this is its full `Nx.Zones` zone-metadata
   database feeding `NxMapData.lua`'s `GetZoneInfo`/
   `BuildMissingZoneInfo` resolver — confirmed this session (by reading
   `ResolveZoneMapAnchor`) that this dependency is real, not just an
   unverified assumption from the original port: without real zone
   data the resolver can't tell which continent an interior belongs to
   and would anchor it to an arbitrary wrong zone. Porting that
   database is its own project, not a quick fix — tracked here as a
   known limitation, not an open bug to patch blindly.
5. **New this session**: an "Auto-follow player" checkbox now lives on
   the map window's title bar (left of the Settings gear). It gates the
   continuous re-center-on-player call that was previously always on
   and fought manual panning back to center within ~30 ticks of
   releasing a drag. See `CHANGELOG.md` for the full root-cause
   writeup. Not yet walked as a formal test case — add to Step B's
   retroactive-coverage list in `ROADMAP.md` next time that's picked up.
6. **New this session, not yet live-tested at all**: a third visual
   layer (`MinimapEngine.lua`'s `UpdateMiniFrames`, new `Map/Data/
   MinimapTiles.lua`/`MinimapBindings.lua`/`MinimapRuntime.lua`) that
   tiles in real per-256px client minimap art once zoomed in past
   `DETAIL_SCALE = 4`, replacing the zone-overview tiles - this is what
   actually produces Carbonite's "fills the whole window" look, not a
   stretched live widget (see `CHANGELOG.md` for the full writeup).
   **Known unresolved risk, check first**: the anchor formula
   (`MinimapBindings.lua`) indexes `MapWorldInfo[13]`/`[14]` for
   Kalimdor/Eastern Kingdoms, but those aren't actually either
   continent's root entry in this same data (`[12]`/`[13]` are) - this
   mismatch is present in Carbonite's own shipped source too, not
   introduced here, so it wasn't corrected blindly. First test: zoom in
   past the threshold in Kalimdor and in Eastern Kingdoms and confirm
   the detail tiles that appear actually match where you're standing,
   not some offset/wrong location.
   - **Resolved, 2026-11-10**: the anchor indices were fine (position
     confirmed live). The real bug was `UpdateMiniFrames` itself being
     wrongly gated behind the zoom threshold as an either/or switch
     with the zone-overview layer - fixed to match real Carbonite's
     `UpdateZones`, which calls it unconditionally every tick. See
     `CHANGELOG.md` for the full writeup.
7. **New this session, not yet live-tested at all**: a canvas-drawn
   player-position marker (`MinimapEngine.lua`'s `ClipFrameW`/
   `UpdatePlayerMarker`) and static service-location icons for
   mailbox/innkeeper/flight master (`RefreshServiceIcons`/
   `UpdateServiceIcons`, new `Map/Data/GuideMailbox.lua`/
   `GuideInnkeeper.lua`) - the "reopen full icon/pin system" scope
   decision, same session. Both reuse the same new `ClipFrameW`
   point-clip primitive. Along the way, found and fixed a real gap:
   `GetWorldPos` was referenced in several existing comments as if
   already implemented but never actually was - see `CHANGELOG.md`.
   **First live test, 2026-11-10, found and fixed three real bugs**:
   the player marker never rotated (fixed - switched to native
   `:SetRotation()`) and was too small (bumped 20→28); the faction
   filter (`ServiceIconFactionOk`) had Carbonite's real Horde/Alliance
   convention backwards, hiding every Horde-only mailbox/innkeeper
   entry from Horde players (fixed); the Mailbox texture path was in
   the same family already confirmed broken on this server this
   session (swapped for the native mail-icon fix's own confirmed-
   working replacement). **Flight-master icon now also fixed** - three
   rounds, all live-diagnosed via `/run` checks rather than guessed.
   First, an unreliable reachability field on this server build.
   Second, `GetTaxiNodesForMap` for a zone returns the WHOLE
   CONTINENT's flight network, not just local nodes - added a 0-1
   bounds check on each node's position before converting. Third (the
   actual final blocker): `C_TaxiMap`'s own `node.faction` uses the
   OPPOSITE numbering from `GuideData`'s hide-code convention (direct
   identity: 1=Horde, 2=Alliance, not 1=Alliance-only/2=Horde-only) -
   reusing the mailbox/innkeeper faction filter was silently rejecting
   every node of the player's own faction. Now uses a separate
   `TaxiFactionOk` function with the correct convention. See
   `CHANGELOG.md` for the full sequence.
9. **New this session**: quest turn-in markers
   (`RefreshQuestIcons`/`UpdateQuestIcons`) - shows the standard quest-
   turn-in icon at any map point for a quest already in your log and
   flagged complete, via the live `C_QuestLog.GetQuestsOnMap` API, no
   external database. **Confirmed working as designed** - a live test
   with zero complete quests in the log correctly showed zero
   markers. Deliberately does NOT show "new available quest" markers
   for NPCs not yet talked to - that needs a static NPC database and
   a zone-ID conversion this
   session found no clean public path for (see `CHANGELOG.md`'s
   step-9c entry) - real future scope, not a bug.
10. **New this session**: gathering-node field (herb/mining/fish/
    treasure), `RefreshGatherIcons`/`UpdateGatherIcons`. Went through
    six rewrites same day before landing on the current design - full
    blow-by-blow in `CHANGELOG.md`'s step-9e entries, compressed here:
    v1 ported a static Wowhead dump into this addon's own data files
    (doubled-up markers once the user's real GatherMate2 install was
    also present); v2-v8 progressively integrated GatherMate2's own
    live database directly instead, chasing a recurring Blizzard
    "blocked from an action only available to the Blizzard UI" taint
    popup through 8 rounds of fixes - including removing this addon's
    entire live-Blizzard-widget-reparenting mechanism ("Mode: Live") on
    strong, specific evidence it was the cause. **None of it worked.**
    Round 9's systematic isolation (stub the gathering feature's own
    GatherMate2 calls entirely - popup still fired; stub
    `NativeMinimapHide` and `MinimapDock` together, the only other two
    places this addon touches the real Minimap - popup still fired)
    ruled out literally every mechanism in this addon individually,
    while disabling the whole addon still reliably fixed it every time
    - a paradox pointing at something structural (addon load order/
    count/timing) rather than any one line of code. One data point that
    broke every theory tried: enabling the otherwise-unused Carbonite
    suite alongside AlchemyGPS *suppressed* the popup entirely. See
    `CHANGELOG.md`'s full round-9 entry for the complete isolation-test
    history - **the actual root cause was never conclusively found.**
    **User's call, given that**: stop chasing an unreproducible-by-
    isolation bug and drop the GatherMate2 integration entirely,
    reverting to this feature's own original static-data design (user
    is also disabling GatherMate2 on their end). **Current design**:
    static Wowhead data again, but a cleaner port than v1 - herb/
    mining/treasure from the standalone `GatherMate2_Data` addon's own
    "Forever"-flavor pack (tailored to this exact server), fish from
    `Carbonite.Gathermate2_Data`'s broader "camelot" pack instead (the
    Forever pack's own fish data is empty) - `Map/Data/Gather{Herb,
    Mining,Fish,Treasure}.lua`, global tables renamed `AlchemyGPS*` to
    avoid any collision if GatherMate2/Carbonite are also present.
    Coordinate decode inlined from GatherMate2's own real `DecodeLoc`
    formula (confirmed via source read). Icons are one guaranteed-
    present Blizzard profession-spell texture per category, not per-
    species - zero runtime dependency on GatherMate2 or Carbonite at
    all now. Profession-gated (herb/mining/fish only show if the player
    knows that profession; treasure always shows) - unchanged from
    every prior version. True live "is this node active right now"
    detection was investigated and hit a real wall - neither GatherMate2
    nor Carbonite's own node-pin renderer do it either, and two live API
    checks (`C_VignetteInfo.GetVignettes`, minimap child-texture
    scanning) both came back unusable on this server. Ships a proximity
    approximation instead (bright when near a known point, dimmed
    otherwise) - not a confirmed-active claim, unchanged from every
    prior version. Deployed and verified byte-identical.
    **Live-tested, same day**: gathering nodes render correctly with
    GatherMate2 disabled - but the SAME "blocked from an action only
    available to the Blizzard UI" popup now names **AlchemyGPS itself**
    instead of GatherMate2, cosmetic-only (nodes still work), accepted
    by the user as a known open issue rather than opening a round 10 -
    see `CHANGELOG.md`'s step-9e entry for why this is actually a
    useful new clue, not just a shrug.
    **Build-order step 9f, same day, follow-up**: real per-species icons
    (copper vein -> copper icon, silverleaf -> silverleaf icon, etc.,
    not one generic icon per category) plus a hover tooltip (node name
    + required skill level, colored green/yellow/orange/red/gold
    relative to the player's own current Herbalism/Mining skill - gold
    for Fish/Treasure, which have no skill-level concept at all). New
    `Map/Data/GatherNodeInfo.lua` (name/icon/level per node ID, scoped
    to exactly the species this server's own zone data uses - all
    vanilla-era, confirmed by grep). Icon textures still point at
    GatherMate2's own `Artwork\*.tga` files on disk (loads fine with
    GatherMate2 disabled, not just enabled - WoW loads a texture by
    path regardless of addon enable state; only breaks if GatherMate2
    is fully uninstalled). Skill-level numbers are hand-entered classic
    WoW data, not sourced from any addon (GatherMate2 doesn't track
    this). Deployed and verified byte-identical; **not yet live-tested.**

## Current file tree (non-library files)

```
AlchemyGPS.toc           CHANGELOG.md
Compat/   Expansion.lua
Core/     Bootstrap, EventBus, Logger, Module, SavedVariables, SlashCommands
Locales/  enUS.lua
Util/     ColorParse.lua, UiHelpers.lua
UI/       Window.lua (real ported Nx.Window chrome), SmallWindow.lua,
          Button.lua, Fonts.lua, Skin.lua, Widget.lua,
          Mixins/Draggable.lua, Mixins/Resizable.lua
Map/      MinimapEngine.lua, MinimapWindow.lua,
          MinimapDock.lua, MapContextMenu.lua, FilterMenu.lua,
          ZoomController.lua, ScrollScale.lua, NativeMinimapHide.lua,
          Data/NxMapData.lua,
          Data/GuideMailbox.lua, Data/GuideInnkeeper.lua,
          Data/Gather{Herb,Mining,Fish,Treasure}.lua (static node
          position data), Data/GatherNodeInfo.lua (per-species name/
          icon/skill-level data - see STATUS item 10)
Settings/ SettingsWindow.lua
Gfx/      Skin/*.tga, Map/32Transparent.blp
Docs/     STATUS.md (this file), ROADMAP.md, Testing/Phase5-8*.md
```

Note vs. the original plan's file manifest: `Map/MiniMap.lua`,
`Coords.lua`, and `FrameToWorld.lua` were never split out as separate
files — their logic was folded directly into `MinimapEngine.lua`
instead. This is an implementation detail, not a scope gap; nothing
the plan asked for is missing.
