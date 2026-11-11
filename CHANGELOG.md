# Changelog

All notable changes to Alchemy GPS are logged here. Format is loose
(this is a solo/small-team addon project, not a public release train)
but entries are dated and grouped by area so the history stays
readable.

- **Build-order step 9e, 2026-11-10: gathering-node field (herb/mining/
  fish/treasure).** User's request: see gathering nodes on the tiled
  map, as far out as possible, accurate, AND able to tell a node that
  might actually be there right now from one that's just a known
  historical spot - explicitly not a plain GatherMate2-style static
  dot field.
  - **Data source found already on this server**: `GatherMate2` plus
    a Carbonite companion addon (`Carbonite.Gathermate2_Data`) ship a
    Wowhead-sourced static dump of every herb/ore/fish/treasure spawn
    for this exact "Camelot (Forever)" flavor. Confirmed its zone keys
    are this engine's own uiMapID (zone 1413 present = The Barrens,
    matching `NxMapData.lua` exactly) - no AreaID-style conversion
    problem like the quest-giver case (see `Docs/QuestieIntegration.md`).
    Since it's static data, not a live scan, it isn't bounded by the
    game engine's render distance at all - "as far out as possible" is
    just "the whole zone's static list," trivially satisfied.
  - Ported the four camelot data files (`HerbalismData.lua`,
    `MiningData.lua`, `FishData.lua`, `TreasureData.lua`) verbatim into
    this addon's own `Map/Data/` (`GatherHerb.lua`, `GatherMining.lua`,
    `GatherFish.lua`, `GatherTreasure.lua`), renaming their global
    table names (`AlchemyGPS*` instead of `GatherMateData2*`) so they
    can't collide with GatherMate2/Carbonite's own identically-shaped
    globals if those addons are also loaded. Coordinate decode is a
    direct port of GatherMate2's own `Collector.lua` `DecodeLoc` (a
    packed `x*1000000 + y*100` encoding, confirmed by reading its real
    source, not guessed).
  - **Profession gating** (user's call): herb nodes only show if the
    player knows Herbalism, mining only if Mining, fish only if the
    player has any Fishing skill. Treasure is unconditional - it's a
    plain world chest/loot spawn, not tied to any profession.
  - **"Active right now" investigated at length, not solved live**:
    checked Carbonite's own real node-map renderer
    (`Modules/Map/Pins/GatherPin.lua`) first - it only ever draws the
    static database, gated by zoom scale and gather-skill cap, no live
    presence check at all. Neither GatherMate2 nor Carbonite (both
    mature, long-iterated, purpose-built addons) do live detection -
    real evidence this isn't achievable the easy way. Live-tested two
    real candidate APIs with the user standing at an actual visible
    peacebloom node: `C_VignetteInfo.GetVignettes()` returned 0 (not
    how this server surfaces gathering nodes), and scanning
    `Minimap`'s own child region textures returned ~290 children, most
    clearly some other addon's minimap-skin decoration rather than
    blips - too noisy to isolate the real one without a much larger
    diff-based investigation (stand at a node / stand far from any
    node / diff the two child lists). Root cause isn't a missing
    technique so much as a hard constraint: a resource node is an
    ordinary game object, and the client only learns one exists once
    it's close enough to sync - there's no "list every active node in
    this zone" query for anyone, which is exactly why the native
    yellow blips only appear once you're near them either.
  - **Decision (user's own call after being told the above)**: ship a
    proximity APPROXIMATION instead of true live confirmation. A known
    point renders full-alpha/bright once the player is within
    `GATHER_NEARBY_RANGE` of it (a tuned-by-eye constant, not measured
    yards - needs live-test adjustment), dimmed otherwise. This is
    explicitly NOT a claim the node is actually there - it's "close
    enough that it's worth walking over and looking" - clearly
    different in kind from the quest/flight-master icons elsewhere in
    this file, which only ever show confirmed, API-backed state.
  - Icons use guaranteed-present Blizzard profession-spell textures
    (`Trade_Herbalism`/`Trade_Mining`/`Trade_Fishing`) plus a generic
    bag icon for treasure, rather than GatherMate2's own per-species
    `Artwork` files, so this doesn't carry a soft dependency on
    GatherMate2 staying installed for icons to render.
  - **Performance**: Barrens herb data alone is 857 entries; a player
    with multiple gather professions could have 1500+ points active
    in one zone. Reposition/clip pass (`UpdateGatherIcons`) runs on
    its own 0.1s throttle rather than every tick (unlike the player
    marker's 20Hz) - stationary points don't need that precision. Full
    rebuild (`RefreshGatherIcons`) only runs on zone change, same as
    the service-icon pattern, since none of this data changes
    mid-session (a newly learned profession picks up its node type on
    the next zone change or `/reload`, not instantly).
  - Completely untested in-game as of this writing - both the basic
    rendering and the `GATHER_NEARBY_RANGE` tuning need a live pass.
- **Step 9e REWRITTEN same day: direct GatherMate2 integration,
  dropped the self-ported data entirely.** First live test showed
  doubled-up markers at one node once the user copied their real
  GatherMate2 install + its own collected data into the dev tree - the
  real cause was two independent data sources (our ported Wowhead dump
  vs. their actual GatherMate2 database) disagreeing by a few feet on
  the same real node. User's explicit call: stop maintaining a local
  copy, integrate GatherMate2 directly, and use ITS real per-species
  icons ("so we see whats at the node") instead of one generic icon
  per category.
  - Deleted `Map/Data/GatherHerb.lua`, `GatherMining.lua`,
    `GatherFish.lua`, `GatherTreasure.lua` and their `Map.xml` entries
    entirely - no local gathering data lives in this addon anymore.
  - `RefreshGatherIcons` now reads GatherMate2's own public accessors
    directly (confirmed by reading its real source):
    `GatherMate:GetNodesForZone(zone, dbType)` (a stateless
    coord/nodeID iterator, zone = uiMapID per its HereBeDragons
    dependency), `GatherMate:DecodeLoc(coord)` (called directly, not
    reimplemented, so it can never drift from GatherMate2's own
    encoding), and `GatherMate.nodeTextures[fullDbName][nodeID]` (the
    real per-species icon path - confirmed public via
    `Constants.lua:1322`'s `GatherMate.nodeTextures = node_textures`).
  - `dbType` short keys ("Herb"/"Mine"/"Fish"/"Treasure") and
    `nodeTextures`' full-name keys ("Herb Gathering"/"Mining"/
    "Fishing"/"Treasure") are two different naming schemes GatherMate2
    itself never unifies - bridged with `GM_TYPE_TO_TEXKEY`. Kept a
    generic fallback icon (the same ones the first version used) for
    any nodeID missing from `nodeTextures`.
  - Added `## OptionalDeps: GatherMate2` to the `.toc` for load order.
    This is a real soft runtime dependency now - every call site
    guards with `if GatherMate then`, so no GatherMate2 installed/
    enabled just means no gathering icons, never an error.
  - Profession gating and the proximity-approximation "nearby"
    highlight (both from the first version) are unchanged -
    GatherMate2's own per-node filter is about toggled/deprecated node
    subtypes, not profession knowledge, so it doesn't replace either.
  - Still completely untested in-game as of this writing.
- **Fix, same day: no gathering icons appeared at all after the
  GatherMate2 rewrite above.** Root cause: `GatherMate2.lua:7` declares
  its addon object as `local GatherMate = LibStub("AceAddon-3.0"):
  NewAddon("GatherMate2", ...)` - a FILE-LOCAL variable. There is no
  bare `_G.GatherMate` global at all, despite GatherMate2's own code
  always referring to it that way internally - every `if GatherMate
  then` guard here was seeing a real `nil`, not a real absence of the
  addon. Fixed by resolving it the correct way instead of guessing a
  global name: `LibStub("AceAddon-3.0"):GetAddon("GatherMate2", true)`
  - AceAddon-3.0 keeps its own registry of every addon it creates
  regardless of how the creating file named its local, so this is the
  standard, intended way for one addon to reach another's AceAddon
  object. Resolved once and cached (`GetGatherMate()`).
- **Still no nodes after that fix - rewritten a third time, user's own
  call to "meet in the middle."** Root cause this time: the actual
  node data lives in `Carbonite.Gathermate2_Data`, which is `##
  LoadOnDemand: 1` in its own `.toc` - its raw tables simply don't
  exist in memory until something explicitly loads it. Carbonite's own
  `GatherStorage.lua` only does that when the user manually runs its
  GatherMate import UI action - nothing guarantees that's happened.
  Round 1 (the ported local copy) never hit this because it was our
  own file, always loaded with this addon regardless.
  - Fixed by force-loading the data pack ourselves
    (`EnsureGatherDataLoaded`, calling `C_AddOns.LoadAddOn(
    "Carbonite.Gathermate2_Data")` - the exact same technique
    Carbonite's own `GatherImportCarb` already uses) and reading its
    raw `GatherMateData2HerbDB`/`MineDB`/`FishDB`/`TreasureDB` tables
    LIVE as globals - no local copy of the data, same proven data path
    round 1 used, just pointed at the real installed addon instead of
    a ported duplicate.
  - GatherMate2 proper's live addon object (`GetGatherMate`, from the
    previous fix) is kept, but now strictly as an OPTIONAL upgrade:
    when that addon also happens to be enabled, its real per-species
    icons (`GatherMate.nodeTextures`) are used; otherwise the generic
    per-category fallback icon shows instead. Node POSITIONS no longer
    depend on GatherMate2 proper being enabled at all - only on the
    data pack, which this forces to load itself.
  - Still untested in-game as of this writing - this is the third
    attempt at this feature and needs a clean live pass before trusting
    it's actually fixed this time.
- **Fix, same day: the force-load above triggered a real Blizzard
  protection popup - "GatherMate2 has been blocked from an action only
  available to the Blizzard UI."** Root cause: `EnsureGatherDataLoaded`
  called `C_AddOns.LoadAddOn` every zone change from inside the
  `Update()` OnUpdate tick chain - not a direct hardware event - which
  tainted the execution context; when GatherMate2's own code ran next
  (reacting to `Carbonite.Gathermate2_Data`'s `ADDON_LOADED` firing) it
  inherited that taint and got blocked calling something Blizzard
  restricts to untainted/Blizzard-only code. Fixed two ways: (1) only
  ever attempt the load ONCE per session (`gatherDataLoadAttempted`
  guard), not every zone change; (2) defer the actual `LoadAddOn` call
  via `C_Timer.After(0, ...)`, which runs in a fresh, untainted
  execution context - the standard WoW addon-dev workaround for this
  exact class of taint-inheritance bug. Since the deferred load means
  data isn't ready yet for whichever `RefreshGatherIcons` call
  triggered it (always the first one each session), that same callback
  re-runs `self:RefreshGatherIcons()` once the load actually completes,
  so the player's starting zone doesn't need an extra real zone change
  to populate. Still untested in-game as of this writing.
- **Fix, same day: the taint-deferral fix above STILL tripped the same
  "GatherMate2 has been blocked" popup.** User confirmed via a clean
  isolating test - AlchemyGPS disabled entirely, GatherMate2 left
  enabled on its own: no error at all - that this addon's own code is
  the trigger, not a pre-existing GatherMate2-vs-server incompatibility.
  The only non-passive thing this addon did to GatherMate2 was the
  forced `LoadAddOn` call; since deferring it via `C_Timer.After`
  didn't help, the restriction apparently isn't a taint-inheritance
  issue at all - force-loading an on-demand addon programmatically
  seems to just be blocked outright on this server, regardless of
  calling context. **Dropped the LoadAddOn call entirely** - this addon
  never force-loads anything anymore. `CheckGatherDataPresent` just
  checks whether `Carbonite.Gathermate2_Data`'s raw globals already
  exist; if not, prints a one-time chat message telling the player to
  enable it themselves via the normal Blizzard AddOns list checkbox
  (a real "action available to the Blizzard UI" - exactly what the
  popup itself was steering toward) and `/reload`. Still untested
  in-game as of this writing - this is the fifth pass on this feature.
- **Still tainted even with LoadAddOn fully removed - and a scope
  correction, same day (round 3).** User re-tested: the same "blocked"
  popup still fired, and the "enable Carbonite.Gathermate2_Data"
  message printed too, prompting the user to point out their entire
  Carbonite suite is disabled - meaning `Carbonite.Gathermate2_Data`
  (which hard-requires `## Dependencies: Carbonite` in its own `.toc`)
  could never load for this setup regardless of any fix. More
  importantly, the user clarified the actual direction: **AlchemyGPS
  exists to phase Carbonite out** - depending on a Carbonite-only data
  bridge was backwards on principle, not just broken for this user.
  - Root cause of the taint, now actually understood instead of routed
    around: GatherMate2 ships its own first-party "Import
    GatherMate2Data" button (`/gathermate` -> Import tab ->
    GatherMate2Data section, `GatherMate2/Config.lua:1175-1199`) that
    calls `C_AddOns.LoadAddOn("GatherMate2_Data")` and
    `GatherMateData:PerformMerge(...)` from GatherMate2's own trusted
    code, fired by a direct hardware click - exactly why that's allowed
    and this addon's own programmatic `LoadAddOn` attempts (both
    versions) weren't.
  - **Rewritten back to GatherMate2's own live API as the sole data
    source** - `gm:GetNodesForZone(mapId, dbType)` /
    `gm:DecodeLoc(coord)` / `gm.nodeTextures`, via the already-correct
    `GetGatherMate()` resolution from the earlier AceAddon fix. This
    addon never calls `LoadAddOn` on anything, ever, now. No Carbonite
    dependency anywhere in the chain - `Carbonite.Gathermate2_Data` and
    its raw globals are gone from this code entirely.
  - Confirmed this needs no manual step at all per the user's explicit
    preference ("we dont want to have to do our own dataimport if we
    can just look at the gathermate data that is already there") -
    GatherMate2 records nodes automatically as the player gathers, with
    zero action required, and this addon just reads whatever's already
    in GatherMate2's live database. A one-time, clearly-optional chat
    tip (`ShowGatherImportTip`) mentions GatherMate2's own Import button
    only as a way to pre-seed an empty zone faster, not as a
    requirement.
  - Still untested in-game as of this writing - this is the sixth pass
    on this feature.
- **Still tainted, same day (round 7) - but with the decisive clue**:
  the round-6 rewrite was architecturally correct (no Carbonite, no
  LoadAddOn) but the SAME "GatherMate2 has been blocked" popup still
  fired. User reported the key new fact that finally pinned it down:
  the error ONLY ever appears at initial login/reload, never during
  normal play (walking, zoning, standing near nodes) - ruling out a
  theory floated this session that GatherMate2's own continuous pin-
  drawing was colliding with this addon's native-minimap-hide feature
  (that would show up during play, not specifically at load).
  - Real cause: this addon's very first `RefreshGatherIcons` call
    happens inside `TakeOwnership`'s initial `RefreshCurrentZone`,
    during addon load - before any hardware event (click/keypress) has
    happened yet this session. `GetGatherMate()` /
    `gm:GetNodesForZone()` / `gm:DecodeLoc()` were all being called
    eagerly, un-deferred, at exactly this moment through every round
    since round 3. Round 4's taint-deferral fix deferred a DIFFERENT
    call (`LoadAddOn`, since removed) and never touched this one - so
    it was never actually tested until now.
  - Fixed by deferring `RefreshGatherIcons`'s entire body one frame via
    `C_Timer.After(0, ...)` - the standard workaround for "called before
    any hardware event this session." A `MapId` re-check inside guards
    the rare case of zoning again before the deferred call fires.
  - Still untested in-game as of this writing - this is the seventh
    pass on this feature.
- **Round 7 confirmed NOT fixed - user re-tested, taint still fired.**
  User connected the dots himself: this addon has a "Mode: Live" vs
  "Mode: Tiles" toggle, and "mode live uses parts of the blizzard
  minimap so we cant even fully reassemble it" — directed removing
  "Mode: Live" entirely, returning all of it to Blizzard's own control,
  deleting the dead code, and fixing the "Hide Blizzard minimap"
  checkbox to remember its own state. Checkpoint commit `c8b8a84` made
  first per explicit request, before any of the work below.
  - **Root cause, finally pinned down**: `MinimapEngine.lua`'s
    `TakeOwnership` → `ApplyTakeOwnership` called `mm:SetParent(UIParent)`
    on the real global `Minimap` widget — reparenting it out of
    `MinimapCluster` into this addon's own window — automatically at
    login whenever the map window had been left open last session
    (`MinimapWindow.lua`'s `applyNativeHiddenOnceReady`), before any
    hardware event that session. That reparent call was already flagged
    in its own prior comment as "touches protected frame state." Every
    addon that parents pins/buttons directly to `Minimap` (GatherMate2's
    `Display.lua` confirmed to do exactly this) inherits taint from that
    reparent the next time it touches those pins — matching the user's
    own observation that the error only ever appeared at login/reload,
    never during play. Rounds 1-7 all chased the gathering-node call
    chain itself, which was never the actual cause.
  - **Removed entirely** (`MinimapEngine.lua`): `ApplyTakeOwnership`,
    `ReleaseOwnership`, `ClipMMW`, `PositionOwnedMinimap`,
    `MinimapSetScale`, `MinimapUpdateMask`,
    `MinimapShouldUseBlizzardPlayerArrow`, `MinimapSyncLayer`,
    `MinimapIsHostVisible`, `MinimapSyncVisibility`,
    `MinimapDetachFrms` — the whole live-widget-reparenting mechanism,
    ~500 lines. `TakeOwnership` trimmed to just its tile/marker/icon
    pool setup and mouse wheel/drag wiring; `Update()`'s live-widget
    blend tail and `MMOwn`/`MMApplyPending` guards removed;
    `UpdateDebugOverlay` simplified to drop the now-dead `MMFrm`
    diagnostics.
  - **Removed** (`MinimapWindow.lua`): `SetMode`/`self.Mode`/the
    "Mode: Live"/"Mode: Tiles" title-bar button; `ForceNativeHidden` and
    the `Open()`/close-handler dance that force-hid the native minimap
    while the window was open and restored `PrevNativeHidden` after —
    this was the actual cause of the "checkbox resets on reload"
    complaint, since it overrode the saved preference independently of
    the checkbox. Also removed the `/gps mapdebug` slash command (built
    entirely around the now-deleted `MMFrm`/`MMOwn` fields).
  - **Removed** (`ZoomController.lua`): the `MMFrm:SetZoom()` nudge in
    `ScrollSteps` that kept the real widget's zoom level in sync with
    the window's +/- buttons — nothing to sync now that the widget is
    never blended in.
  - **"Hide Blizzard minimap" now actually remembers its state**: with
    `Open()`/`Close()` no longer touching `NativeMinimapHidden`, the
    only writers left are the Settings checkbox and `/gps minimap
    hide|show`, both of which set the saved value directly — and the
    pre-existing login-time `applyNativeHiddenOnceReady` poll applies
    whatever was last saved, with nothing to override it anymore.
  - **MinimapDock.lua needed no functional changes** — confirmed its
    button-collection (`Scan()`) reads the global `_G["Minimap"]`
    directly rather than through `MinimapEngine`'s (now-removed)
    borrowed reference, so it keeps working unchanged. Its header
    comment was updated to explain why, and to note it's now the only
    way to reach those buttons at all while "Hide Blizzard minimap" is
    on.
  - Deployed and verified byte-identical against the live client path;
    not yet live-tested — pending the user's next `/reload`, both for
    whether this finally resolves the GatherMate2 taint popup and for a
    general regression check (zoom, pan, dock, icons) now that the live
    widget is out of the picture entirely.
- **"Mode: Live" removal confirmed NOT the fix either - user re-tested,
  popup still fires.** Both with the native minimap shown and hidden at
  reload (the "remember state" fix from the same round DID work
  correctly, confirmed separately).
- **Round 9 - systematic isolation, each test disproving the leading
  theory, culminating in dropping GatherMate2 entirely.**
  - `/console scriptErrors 1` and `/console taintLog 2`: neither
    surfaced a detailed stack trace or taint-propagation message on
    this server's client build - the generic one-line popup is all
    this client exposes, so no further diagnosis was possible that way.
  - User's own clean A/B test turned up a genuinely strange data point:
    enabling the (otherwise-unused) Carbonite suite alongside
    AlchemyGPS **suppressed** the popup, while AlchemyGPS alone (no
    Carbonite) still triggered it. More addons running reducing an
    error, rather than adding more addons increasing risk of one, broke
    every reparenting/taint theory tried so far.
  - Checked whether GatherMate2's LibDataBroker launcher object was
    being displayed as a minimap icon by Titan Panel (also installed)
    and swept up by `MinimapDock.lua`'s button-collector - ruled out by
    reading `Titan/TitanLDB.lua`: Titan's broker bridge parents its
    buttons to Titan's own bar, never to the real `Minimap`, so
    `MinimapDock` can't touch it either way.
  - **Decisive test**: temporarily stubbed `RefreshGatherIcons` to do
    nothing at all (zero calls into GatherMate2's code) - popup still
    fired. This conclusively exonerated the gathering-node feature's
    own code; all 8 prior rounds of fixes had been chasing the wrong
    subsystem the entire time.
  - **Second decisive test**: with the gathering code restored, instead
    temporarily stubbed out `NativeMinimapHide`'s login-time call AND
    `MinimapDock:Create()` together (the only two other places this
    addon touches the real `Minimap`/`MinimapCluster` at login) - popup
    still fired. This means literally every mechanism in this addon
    that touches the real minimap, the gathering-node feature, and the
    live-widget-reparenting mechanism (removed earlier this same day)
    had now each been individually ruled out, while disabling
    AlchemyGPS entirely still reliably fixed it - a real paradox that
    pointed at something structural (load order, addon count/timing)
    rather than any one line of this addon's own runtime code.
  - **User's call, given the above**: stop chasing an unreproducible-
    by-isolation bug and drop the GatherMate2 integration entirely,
    going back to this feature's own original static-Wowhead-data
    design (what build-order step 9e shipped with before the very
    first GatherMate2-related rewrite) - "before trying to copy
    carbonites gathermate 2 node system we had nodes showing on our own
    using our wow head data just get us back to that state." User is
    disabling GatherMate2 on their end as well.
  - **Reverted to static data, cleanly, not just restoring old files**:
    ported `GatherMate2_Data`'s own "Forever"-flavor pack (the
    standalone, non-Carbonite data addon already on this server,
    tailored specifically to this one server build) for herb/mining/
    treasure into `Map/Data/Gather{Herb,Mining,Treasure}.lua`, with the
    global table renamed (`AlchemyGPS*` instead of `GatherMateData2*`)
    so it can never collide with GatherMate2's own identically-shaped
    globals if that addon happens to be loaded anyway. The Forever
    pack's own `FishData.lua` is empty, so `Map/Data/GatherFish.lua`
    instead ports `Carbonite.Gathermate2_Data`'s broader "camelot" pack
    for fish only - same uiMapID zone-key convention, just not curated
    specifically for this one server. Coordinate decode is inlined from
    GatherMate2's own real `DecodeLoc` formula (confirmed via source
    read, not guessed) rather than reimplemented from scratch, since
    the data was generated in exactly that packed encoding. Icons are
    back to one guaranteed-present Blizzard profession-spell texture
    per category (`Trade_Herbalism`/`Trade_Mining`/`Trade_Fishing` +a
    generic bag icon for treasure), not per-species - this feature now
    carries zero runtime dependency on GatherMate2 or Carbonite at all.
  - Removed `## OptionalDeps: GatherMate2` from the `.toc` and all of
    `MinimapEngine.lua`'s now-dead GatherMate2-reading code
    (`GetGatherMate`/`ShowGatherImportTip`/the GatherMate2-calling
    version of `CollectGatherZoneNodes`/the `C_Timer.After` deferral in
    `RefreshGatherIcons`, which is no longer needed at all - reading
    this addon's own static Lua tables has no addon-interaction/taint
    concern to defer around).
  - Deployed and verified byte-identical. Not yet live-tested as of
    this writing.
  - **Open question, explicitly not resolved**: the actual root cause
    of the taint popup was never conclusively identified - every
    specific mechanism tested was ruled out, yet the popup was 100%
    reproducible whenever AlchemyGPS was enabled (with GatherMate2
    enabled) and 100% absent whenever AlchemyGPS was disabled. If this
    addon ever adds another GatherMate2 integration in the future,
    don't assume the cause is understood just because this round's
    specific theories were disproven - re-derive from scratch or re-
    read this entry's full isolation-test history first.
  - **New clue, live-tested after the revert above**: with GatherMate2
    disabled (per the user's own plan) and the gathering-node field
    fully reverted to static data with zero runtime calls into
    GatherMate2 at all, the SAME "has been blocked from an action only
    available to the Blizzard UI" popup now names **AlchemyGPS itself**
    instead of GatherMate2 - still fires, gathering nodes still render
    correctly despite it. This is a meaningful new data point for any
    future investigation: the popup was never really "about"
    GatherMate2 specifically - something in AlchemyGPS's own login-time
    code trips a Blizzard protected-action check regardless of which
    other addon happens to be next in the blamed chain when one is
    present. User's call was to accept this as a known cosmetic issue
    for now rather than open a round 10 investigation; worth revisiting
    if it starts causing real (not just cosmetic) problems.
- **Build-order step 9f, 2026-11-10: per-species gathering-node icons +
  hover tooltip.** Follow-up to step 9e's static-data revert, same day.
  User's request: real per-species icons (copper vein -> copper icon,
  silverleaf -> silverleaf icon, etc. - not the one generic icon per
  category step 9e shipped with), plus a hover tooltip showing the
  node's name and required skill level, colored relative to the
  player's own current profession skill (green/yellow/orange/red/gold).
  - **New file `Map/Data/GatherNodeInfo.lua`**: `[dbType][nodeID] = {
    name=, level=(Herb/Mine only), tex= }`, scoped to exactly the
    species IDs present in this server's own zone data (confirmed by
    grepping `Map/Data/Gather{Herb,Mining,Fish,Treasure}.lua` for their
    distinct node IDs - turned out to be vanilla-era content only, Herb
    401-431, Mine 201-219, which made hand-porting this tractable in
    one pass). Names/icon paths ported from GatherMate2's own
    `Constants.lua` (`node_textures` + `node_ids`, read as static
    reference data - zero runtime call into GatherMate2's code).
    Texture paths still point at GatherMate2's own `Artwork\*.tga`
    files on disk rather than copies bundled into this addon - WoW
    loads a texture by file path regardless of whether that addon's
    Lua is enabled, confirmed by checking the files are present at the
    deployed client path independent of GatherMate2's enabled state -
    this only degrades (falls back to the old generic per-category
    icon) if GatherMate2 is fully *uninstalled*, not just disabled.
  - **Skill-level data** (the `level` field) is NOT sourced from any
    addon - GatherMate2 doesn't track this at all (pure position
    tracker). Hand-entered from well-documented classic WoW Herbalism/
    Mining skill breakpoints. Three Mining entries with real quest/
    reputation gating on top of a skill floor (Dark Iron Deposit,
    Lesser Bloodstone Deposit, Incendicite Mineral Vein - Silithus war
    effort / Blackrock Depths questline resources) use a best-effort
    approximate floor, flagged in the data file's own comments, since
    this is a cosmetic tooltip, not a hard gameplay gate.
  - Fish/Treasure have no `level` field at all (classic fishing has no
    hard skill gate - Fishing skill affects catch chance/quality, not
    whether you can click the pool; Treasure is plain world loot, not
    tied to any profession) - the tooltip code treats a missing level
    as gold ("no level"), per explicit user direction, instead of
    WoW's usual gray for this case.
  - `MinimapEngine.lua`: `CollectGatherZoneNodes` now looks up each
    point's real icon by `nodeID` (falling back to the old generic
    per-category icon if a future/unrecognized ID has no entry) and
    carries `dbType`/`nodeID` on the point; `UpdateGatherIcons` wires
    `EnableMouse(true)` + `OnEnter`/`OnLeave` once per pooled frame
    (frames are reused across different species as zones change, so
    the per-frame `gatherDbType`/`gatherNodeID` fields are refreshed
    every reposition pass, not just at creation) and a new
    `GatherFrameOnEnter` builds the tooltip fresh on every hover
    (re-reads current Herbalism/Mining skill live via
    `GetProfessionInfo` rather than caching it from the last zone
    refresh, so a skill-up mid-session shows correctly without needing
    a `/reload`). New `GatherNodeColor` implements the standard WoW
    profession-difficulty color convention (orange = at/near the skill
    floor = best skill-up odds, climbing to yellow then green as
    current skill clears it by more; red + "(can't harvest)" appended
    to the level if current skill is below the floor).
  - Deployed and verified byte-identical. Not yet live-tested.
- **Build-order step 9g, 2026-11-10: gathering-icon opacity slider in
  the map's right-click menu.** Follow-up to step 9f, same day. User's
  request: a second slider in `MapContextMenu.lua` (alongside the
  existing tile-map-brightness one) that controls the gathering-node
  icons' overall opacity.
  - `MapContextMenu.lua`: added a second label+slider row ("Gathering
    Icon Opacity"), same `OptionsSliderTemplate`/0-100%/persisted
    pattern as row 1's brightness slider - persists to
    `AlchemyGPS.db.profile.GatherIconOpacity`, applied live to
    `MinimapEngine.GatherOpacity`. Menu frame resized taller (70px ->
    136px) to fit both rows.
  - `MinimapEngine.lua`: `TakeOwnership` seeds `self.GatherOpacity`
    from the saved profile value (mirrors the existing `BackgndAlpha`
    seeding right above it), so a chosen value survives `/reload`
    without needing the menu reopened first. `UpdateGatherIcons`
    multiplies it into the existing near/dimmed alpha calculation
    (`(near and 1 or GATHER_DIM_ALPHA) * (self.GatherOpacity or 1)`) -
    a plain 0-1 transparency multiplier on top of the existing
    proximity-based dim/bright logic, not a replacement for it.
  - Deployed and verified byte-identical. Not yet live-tested.
- **Build-order step 9h, 2026-11-10: gathering-icon visibility pass.**
  Same day, user-reported: "100 cannot be the best these get, can
  barely see them" after testing step 9g's opacity slider - plus a
  request for a size slider and "anything else you can think of to
  make these more visible."
  - **Root cause of the "100% still barely visible" report**:
    `GATHER_DIM_ALPHA` (the non-near/"dimmed" icon alpha) was 0.45,
    multiplied by the opacity slider - so even at the slider's max,
    any icon not within `GATHER_NEARBY_RANGE` (a small radius, so
    "dimmed" is the common case for anything visible at a normal zoom
    level, not the exception) topped out at 45% opacity. Raised to
    0.85 - now a subtle closer-is-brighter cue instead of the
    dominant factor in whether an icon is visible at all.
  - Bumped the base icon size 10 -> 12 (`GATHER_ICON_SIZE`,
    `MinimapEngine.lua`).
  - **New size slider** (row 3 in `MapContextMenu.lua`): 50%-300% of
    that base size, persisted as `AlchemyGPS.db.profile.
    GatherIconScale`, applied live to `MinimapEngine.GatherIconScale`
    and multiplied into the size passed to `ClipFrameW` in
    `UpdateGatherIcons`. Menu resized 136px -> 198px for the third row.
  - **New backdrop halo** (the "anything else" ask): each gather icon
    now has a plain dark square (`frm.backdrop`, a `BACKGROUND`-layer
    `SetColorTexture` - no new art asset needed) sized proportionally
    larger than the icon itself (`GATHER_BACKDROP_PAD_RATIO`, 20% per
    side, scales with the size slider rather than a fixed pixel
    border) for contrast against busy map art. Its alpha tracks the
    same near/dim/opacity calculation as the icon itself (at a reduced
    multiplier, `GATHER_BACKDROP_ALPHA_MULT` = 0.7) so it fades
    together with the icon rather than fighting the opacity slider.
  - Deployed and verified byte-identical. Not yet live-tested.
- **Build-order step 9i, 2026-11-10: backdrop halo refinement.**
  Same-day follow-up, user-reported after step 9h: the backdrop was "a
  little 2 big," wanted it to "hug tight with only a couple pixel
  padding," wanted the corners "a slight rounding," and wanted its
  opacity independently controllable (not fixed).
  - **Tight padding**: `GATHER_BACKDROP_PAD_RATIO` (20% of the icon's
    current size) replaced with a flat `GATHER_BACKDROP_PAD = 2`
    (pixels, every side) - no longer scales with the size slider.
  - **Rounded corners**: `frm.backdrop` is now a real `BackdropTemplate`
    frame (was a plain `SetColorTexture` square) using the exact same
    `UI-Tooltip-Background`/`UI-Tooltip-Border` combo
    `MapContextMenu.lua`'s own menu panel already uses, shrunk to icon
    scale (`edgeSize = 3`, 1px insets) - reuses an asset already in
    this addon rather than needing new art. Since BackdropTemplate
    frames don't layer the way `CreateMiniFrame`'s plain child textures
    do, it's a sibling frame (parented to `self.Frm`, not to the icon
    frame itself) kept behind it purely via frame level
    (`level - 1`, set every update pass).
  - **New backdrop-opacity slider** (row 4, `MapContextMenu.lua`): 0-
    100%, persisted as `AlchemyGPS.db.profile.GatherBackdropOpacity`,
    applied live to `MinimapEngine.GatherBackdropOpacity` - replaces
    the old fixed `GATHER_BACKDROP_ALPHA_MULT` (0.7) constant, which is
    now just that slider's default so today's look doesn't change
    until the user actually touches it. Menu resized 198px -> 260px.
  - Becoming a sibling frame instead of a child texture meant hiding
    the icon frame no longer auto-hides the backdrop - fixed in both
    `HideGatherFrames` and the end-of-list hide loop in
    `UpdateGatherIcons`, and the off-screen (`ClipFrameW` returns
    false) branch now explicitly hides it too rather than leaving a
    stale backdrop floating with no icon on top of it.
  - Deployed and verified byte-identical. Not yet live-tested.
- **Build-order step 9j, 2026-11-10: backdrop corners matched to the
  real map window's own chrome.** Same-day follow-up to step 9i - user
  asked for the backdrop's corner rounding to match the map module's
  own window corners specifically, rather than the ad-hoc small
  `edgeSize` picked in step 9i. `frm.backdrop`'s `SetBackdrop` call now
  reads `AlchemyGPS.Skin:GetBackdrop()` directly (the exact same table
  `UI/Window.lua`'s `CreateBorders` applies to the real window frame,
  defined in `UI/Skin.lua`) instead of a separate hardcoded recipe -
  same asset, same `edgeSize`/`tileSize`/`insets`, so it keeps matching
  automatically if that skin table is ever changed later, rather than
  two copies that could drift apart. Fill/border color stay plain black
  (not the skin's own blue-gray tint) - this is still "the black box"
  from the backdrop-opacity slider, not a themed panel.
  - Deployed and verified byte-identical. Not yet live-tested.
- **2026-11-10: zoom buttons restyled to match AlchemyNavigation's.**
  User's request: "steal the style" from the sibling AlchemyNavigation
  project's own undocked-minimap zoom buttons. `MinimapWindow.lua`'s
  zoomIn/zoomOut (build-order step 5) were `UIPanelButtonTemplate`
  (Blizzard's gray beveled button look); replaced with a plain 16x16
  `Button` + a black 50%-alpha `SetColorTexture` background + a
  centered +/- `GameFontNormalSmall` label - copied as-is from
  AlchemyNavigation's `Modules/Map/Minimap.lua` `makeButton` (no hover/
  pressed textures there either, so none added here). Kept this
  window's own bottom-right anchor rather than copying
  AlchemyNavigation's bottom-left placement too - the ask was the
  visual style, not the layout.
  - Deployed and verified byte-identical. Not yet live-tested.
- **Build-order step 9k, 2026-11-10: map filter button + menu.** User's
  request: a "Filter" button on the map window, opening a dropdown-
  style checklist "like the normal Blizzard one does only this is just
  for us, no borrowing from the Blizzard one" - first five items:
  gathering nodes (the profession ones, combined), a separate option
  for treasure, then flight masters/innkeepers/mailboxes.
  - New `Map/FilterMenu.lua`: a small bordered popup (same plain-
    Blizzard-frame-primitives pattern `MapContextMenu.lua` already
    established - explicitly not Blizzard's own `UIDropDownMenu`
    system, per the user's own direction) with one checkbox row per
    filter, using the same stock `UI-CheckBox-*` textures
    `MinimapWindow.lua`'s AutoFollow checkbox already uses. Opens
    anchored below a new title-bar "Filter" button (styled like the
    zoom buttons - flat dark background + text label, no icon texture
    to risk guessing wrong) instead of at the cursor, since this is a
    toolbar dropdown, not a right-click menu.
  - Persisted as `AlchemyGPS.db.profile.MapFilters[key]` - missing key
    means "on," same convention `AutoFollow` already uses, so adding a
    new filter later never needs a migration to default existing
    profiles to visible.
  - `MinimapEngine.lua`: `RefreshGatherIcons` now gates its `dbTypes`
    list on two filter keys - "Gathering" covers Herb/Mine/Fish
    together (the profession-gated ones, combined per the user's own
    request), "Treasure" is separate (not profession-gated at all).
    `RefreshServiceIcons` gates the Mailbox/Innkeeper loop per-kind
    (those keys already match the filter keys exactly) and the
    flight-master `C_TaxiMap` branch on its own "FlightMaster" key.
    Toggling a row calls straight into the relevant Refresh*/Update*
    pair immediately rather than waiting for the next zone change or
    tick, so the checkbox has instant visual effect. Quest-giver icons
    are NOT in this filter list - not asked for, future scope.
  - **Also corrected, same pass**: this file's own header comment
    claimed the "Mode: Live" removal (above) "turned out to be the
    real root cause" of the taint popup - stale, written before round
    9's later live re-test disproved it (see that section's own entry
    above). Corrected to describe what was actually confirmed (fixed
    checkbox persistence) versus what never panned out (the taint
    popup itself, still unresolved, now blaming AlchemyGPS directly
    with GatherMate2 disabled).
  - Deployed and verified byte-identical. Not yet live-tested.

- **Build-order step 9l, 2026-11-10: bankers, dungeon/raid entrances,
  zone transitions, and guard-direction flags.** User's request,
  verbatim: "the flag to mark locations given by guards," "bank
  icons," "dungeon and raid entrances," "zone transitions or bridges
  or w/entrances" - all four to show on the map AND get their own
  `FilterMenu.lua` row. Investigated data sourcing for all four before
  writing any code (same discipline as step 9b's Mailbox/Innkeeper and
  9e's gathering data), via a research subagent reading Carbonite's own
  source tree:
  - **Bankers**: `Carbonite/Data/camelot/Guides/Banker.lua` exists,
    same exact `Nx.GuideData[L["Banker"]]` shape (packed `fac,x,y`
    strings keyed by zone mapID) as the already-ported Mailbox/
    Innkeeper files. Ported verbatim as `Map/Data/GuideBanker.lua`,
    keyed by the plain string `"Banker"` - zero new parsing code, it's
    just another `SERVICE_ICON_TEX` entry and `RefreshServiceIcons`
    loop iteration. Icon: `Interface\MINIMAP\TRACKING\Banker`, same
    confirmed-working `TRACKING` family as Innkeeper.
  - **Dungeon/Raid Entrances**: no dedicated Carbonite Guides file for
    this - the real data lives in `Carbonite/Data/camelot/Zones.lua`'s
    `Nx.Zones`, keyed by INSTANCE mapID (not owner zone), one row per
    zone/instance as `name|minLvl|maxLvl|faction|typ|entryId|ex|ey|
    numPlayers` - `entryId/ex/ey` (the owner zone's mapID and the
    entrance's position in it) only populated for the 34 real
    dungeon/raid rows; plain zone and battleground rows leave them
    blank. Ported the 34 real rows as a local table in the new
    `Map/Data/GuideDungeonEntrance.lua`, which re-buckets them by owner
    zone into the same shared `fac,x,y` string shape at load time (one
    small loop, not exposed as a new global) under the single combined
    key `"DungeonEntrance"` - user asked for dungeons and raids as ONE
    filter, not two. Icon: `Interface\Icons\INV_Misc_Key_03` (no
    matching `TRACKING` category exists for this - that filter list
    has never had a "dungeon" entry - so this uses a plain, vanilla-
    safe item icon instead, not yet live-confirmed).
  - **Zone Transitions**: `Carbonite/Data/camelot/ZoneConnections.lua`'s
    `Nx.ZoneConnections`, a flat array of 76 pipe-delimited strings
    (`flags|contType|name1|mapId1|x1|y1|name2|mapId2|x2|y2`, confirmed
    against that file's own `Nx.Map:ConnectionUnpack`) covering plain
    walk-through zone borders plus named boats/zeppelins/trams/portals.
    Copied verbatim (byte-for-byte on every numeric field, to rule out
    a transcription mistake silently shifting a coordinate) into the
    new `Map/Data/GuideZoneTransition.lua`, which parses each string
    and writes BOTH endpoints into the shared `fac,x,y` shape under one
    combined key `"ZoneTransition"` (also one filter, not per-type, to
    match the user's own single line-item phrasing). Names are kept in
    the raw copied strings for faithfulness but not used (no tooltip
    for this category). `C_Map.GetMapLinksForMap` (the live Blizzard
    equivalent) was searched for across every installed addon and
    found nowhere - no evidence it works on this server build, so the
    static data above was used instead of guessing at a live API with
    zero precedent here. Icon: `Interface\Icons\INV_Misc_Map_01`, also
    not yet live-confirmed.
  - **Guard-given direction flags**: a real Blizzard mechanic (ask a
    guard for directions, get a temporary flag pointing at a city
    service) published through `C_GossipInfo.GetPoiForUiMapID`/
    `GetPoiInfo` - found by reading Carbonite's own `MapEngine.lua`,
    which defensively checks for `GetPoiForUiMapID`'s existence before
    using it (unlike `C_GossipInfo` itself, used unconditionally
    elsewhere in Carbonite, confirming the base table exists) rather
    than assuming every client build has it. No static data source
    makes sense here - it's inherently a live, temporary, one-per-zone
    state, not a fixed location list. New `RefreshServiceIcons` branch
    (existence-checked, `pcall`-wrapped, same defensive shape as the
    `C_TaxiMap` flight-master branch) under filter key `"GuardFlag"`,
    plus a small dedicated frame registering
    `DYNAMIC_GOSSIP_POI_UPDATED` so the flag can appear/change without
    needing a zone change to pick it up (registering an event name a
    client build doesn't have is a harmless no-op, not an error).
    Icon: `Interface\Icons\INV_BannerPVP_01` as a generic flag
    placeholder - **explicitly NOT confirmed to work at all**, unlike
    every other branch in `RefreshServiceIcons`. Carbonite's own code
    doesn't assert this API fires real data on this server build
    either; needs an in-game "ask a guard for directions" test before
    treating it as done, the same way flight masters needed a live
    round of debugging after the first pass.
  - `FilterMenu.lua`: four new rows ("Bankers," "Dungeon/Raid
    Entrances," "Zone Transitions," "Guard Directions"), menu widened
    170→190px (the longest new label was getting clipped). All four
    dispatch through the existing non-gather branch of `SetFilterOn`
    (`RefreshServiceIcons`/`UpdateServiceIcons`) with zero new dispatch
    logic needed - every one of these four keys already matches a
    `SERVICE_ICON_TEX`/filter key used inside that function.
  - Deployed and verified byte-identical. Bankers are high-confidence
    (reuses a confirmed-working icon family and identical data shape);
    dungeon entrances and zone transitions are new data shapes, built
    carefully but not yet live-tested; the guard-flag feature
    specifically is the least certain of the four and may need a
    follow-up round once tested in-game.

- **Build-order step 9m, 2026-11-10: debug overlay cleanup.** User
  reported the on-map debug overlay (`MinimapEngine.lua`'s
  `UpdateDebugOverlay`, shown via `/gps debug` or the Settings
  checkbox) was "jumbled" and asked for it to show everything the four
  `Docs/Testing/Phase5-8*.md` checklists (just rewritten the same
  session - see that work above) actually watch for. Every field those
  docs reference was already present - this was purely a presentation
  problem, not missing data:
  - Regrouped the overlay's single flat `Key=Value` dump into three
    labeled sections matching the testing docs: "Pan / Zoom (Phase 5,
    6, 7)" (`Scale`/`ScaleDraw`/`StepTime`/`MapPosX`/`MapPosY`/
    `MapPosXDraw`/`MapPosYDraw`/`Scrolling`/`Ttl` - merged into one
    section rather than three, since all three phases' tests read this
    same underlying animation state), "Window Size (Phase 7)"
    (`MapW`/`MapH`), and "World / Position (Phase 8)" (`MapId`/`Cont`/
    `Zone`/`CurWorldUpdateMapId`/`CurWorldTileCount`/`PlyrX`/`PlyrY`/
    `PlyrDir`). Headers colored gold (`|cffffd100`) for visual
    separation from data rows.
  - Numeric fields now format through a new `fmtNum(v, fmt)` helper
    (`%.2f`/`%.1f`/`%.3f` depending on field, falling back to plain
    `tostring` for non-numbers) instead of raw `tostring()` - the raw
    version could print a float out to a dozen-plus decimal digits,
    which was a real contributor to the "jumbled" look. `Cont`/`Zone`
    stay as plain `tostring` (no rounding) since `nil` is a meaningful,
    by-design value for instances (Phase 8's own test doc) and must
    print as literal `nil`, not error through a `%.2f` format spec.
  - Added one new derived field, `Animating` (`true` when `ScaleDraw`/
    `MapPosXDraw`/`MapPosYDraw` haven't caught up to `Scale`/`MapPosX`/
    `MapPosY` yet) - Phase5 Test 3 and Phase6 Test 2 both come down to
    "is a zoom animation still in flight," which previously meant
    eyeballing two raw floats for a difference; this is the one piece
    of new instrumentation added, not just reformatting.
  - Widened/tallened the overlay frame (520x260 -> 460x320) to fit the
    headered layout without word-wrap collapsing it back into a
    jumble.
  - Deployed and verified byte-identical; not yet visually confirmed
    in-game.

- **Build-order step 9n, 2026-11-10: Phase 5-7 confirmed passing
  live.** User walked `Docs/Testing/Phase5-Zoom.md`, `Phase6-PanDrag.md`,
  and `Phase7-Resize.md` and reported "100% pass" on all of it - the
  first formal pass/fail record either doc has had since the tile-canvas
  rewrite (`ROADMAP.md`'s Step A). One clarification folded into Phase
  6's own doc rather than left as a bare observation: reopening the map
  mid-drag re-triggers the Auto-follow re-center animation - confirmed
  this is the intended Auto-follow behavior (default on), not the
  "stuck scroll state" bug that test was actually checking for, so it's
  recorded as a pass with a note, not a caveat. Updated `STATUS.md`'s
  build-order table (rows 5-7 now "Confirmed passing" instead of
  "pass/fail not yet formally confirmed") and `ROADMAP.md`'s Step A
  (now just "close out Phase 8," 5-7 already done). Phase 8
  (`Phase8-WorldArtCanvas.md`) remains the only unconfirmed phase.
  - **2026-11-11, follow-up**: user deleted all three checklist docs
    (`Phase5-Zoom.md`/`Phase6-PanDrag.md`/`Phase7-Resize.md`) now that
    they're confirmed passing - no longer needed as open checklists,
    this entry is the permanent record instead. Every other doc's
    pointers to those three files (`STATUS.md`, `ROADMAP.md`) were
    redirected here rather than left dangling.

- **Build-order step 9o, 2026-11-11: `Docs/STATUS.md` deleted
  outright.** User's call, confirmed explicitly when asked (deleting a
  central project doc warranted a check first, unlike the three
  disposable checklists above). Its role as a "living audit/snapshot"
  doc is now fully absorbed by this file's own dated entries plus the
  per-phase `Docs/Testing/Phase*.md` docs - there's no separate
  "current state" doc anymore, by design. Every reference to
  `STATUS.md` elsewhere in the repo was found (`grep -rln` across
  `*.md`/`*.lua`/`*.xml`/`*.toc`) and redirected to the specific
  `CHANGELOG.md` section that covers the same fact, rather than left
  pointing at a deleted file:
  - `Docs/ROADMAP.md`: the companion-doc intro, the Mode:Live
    amendment, Step A's two references (build-order table -> this
    file's own dated entries, since there's no table to update
    anymore), Step B's two references (`### Map window` section, for
    both the detail-tile anchor note and the indoor-freeze-gate fix),
    Step C (`### Right-click brightness menu` section), and Step F's
    two references (now `ROADMAP.md`/`CHANGELOG.md` instead of
    `STATUS.md`/`ROADMAP.md`).
  - `Docs/Testing/Phase9-IconsAndUI.md`: one present-tense claim
    ("a gap `STATUS.md` has flagged since") rewritten to not cite a
    file that can no longer "flag" anything.
  - This entry and the one above it (step 9n's own 2026-11-11
    follow-up) are themselves exempt - `CHANGELOG.md` is explicitly a
    dated history, so a past-tense "updated `STATUS.md`'s build-order
    table" is accurate history, not a dangling live pointer.

## Unreleased — 2026-11-10

### Map window
- Removed a leftover solid dark placeholder texture on the window's
  content frame (`MinimapWindow.lua`). It was a stand-in for the real
  world-art canvas from before build-order step 8 landed, never
  removed once real tiles existed, and was painting over the tile art
  every tick regardless of brightness — the actual cause of "brightness
  slider does nothing, map stays black."
- Minimap mask switched from Blizzard's round mask to a square one
  (`MinimapEngine.lua`). The live-rendered accent patch was only
  filling the inscribed circle while the static world-art background
  already filled the whole square content area; the round mask was the
  only thing cropping the live patch down.
- Live widget sizing reworked from a 6-step fixed preset search (real
  Carbonite's `MMScales`) to directly solving for the one square size
  that fills the window's shorter side at the current scale. The
  preset search caused visible bounce when zoomed in (every preset
  failing at once) and stepped jumps when resizing the window; the new
  math grows smoothly in lockstep with the background tiles.
  - Added a 10% fit margin (`FIT_MARGIN`) after the live widget was
    found to disappear entirely inside Orgrimmar and reappear outside
    it — an exact-fill target has zero slack for the position drift
    city sub-zones apparently introduce, so a small margin keeps it
    fitting instead of failing outright.
- Minimap's own zoom level is now kept in sync with the window's +/-
  zoom buttons (`ZoomController.lua`). Previously only the background
  world-art reacted to zoom; Blizzard's own rendered terrain has a
  separate, discrete zoom level that was never being touched.
- Added an "Auto-follow player" checkbox to the map window's title bar,
  directly left of the Settings gear (`MinimapWindow.lua`, new saved
  flag `AutoFollow`, default on). Backs a continuous per-tick
  re-center-on-player call in `MinimapEngine.lua` that was previously
  always on — manually panning the view would get pulled back to
  center within about half a second of releasing the drag, with no way
  to turn it off. Unchecking the box now lets a manual pan stay put.
- Fixed the live-widget patch vanishing entirely when going indoors
  (`MinimapEngine.lua`). Root cause: `GetWorldZoneInfo` returns a
  fallback rectangle (`0,0,1002,668`, not `nil`) whenever the player's
  current map isn't in the static zone catalog — true for most building
  interiors, since Carbonite's real per-mapID catalog resolver
  (`NxMapData.lua`'s `GetZoneInfo`/`BuildMissingZoneInfo`) was
  deliberately left unported (needs Carbonite's full `Nx.Zones`
  database, confirmed this session to be a real hard dependency, not
  just an unverified assumption — out of scope for now). Because `0` is
  truthy in Lua, the per-tick update block ran anyway on that bogus
  fallback, computing a wildly-wrong player position and fighting the
  live widget's fit check until it failed outright. Now gated on
  `self.Cont` as well, so indoors the view simply freezes at the last
  good outdoor position instead of jumping to noise and disappearing.
  This is a mitigation, not true indoor tracking — real indoor
  movement still won't move the patch; that needs the full zone
  database port mentioned above.
- **Added the real-terrain "detail tile" layer** (new: `Map/Data/
  MinimapTiles.lua`, `MinimapBindings.lua`, `MinimapRuntime.lua`;
  `MinimapEngine.lua`'s new `UpdateMiniFrames`/`ClipFrameTL`/
  `CreateMiniFrame`/`HideMiniFrames`). Root cause of "the live view
  only fills a little box, not the whole window" (user screenshot
  comparison against real Carbonite, 2026-11-10): the live Blizzard
  widget is inherently square (one scalar drives both width and
  height in both our `MinimapSetScale` and real Carbonite's own), so
  on a non-square window it can only ever cover the shorter side —
  that part was never a bug. What actually fills Carbonite's whole
  window is a *third* layer we'd never ported: real per-256px client
  minimap textures (the same art the native minimap renders from,
  referenced by FileDataID), tiled as plain static frames that follow
  the view's pan position rather than the player's live position.
  Ported near-verbatim from Carbonite's `UpdateMiniFrames`/
  `ClipFrameTL` (flat 2D math only — View3D is still an explicit
  non-goal), gated the same way real Carbonite's `UpdateZones` does:
  this layer replaces the zone-overview tiles once zoomed in past a
  scale threshold (`DETAIL_SCALE = 4`, matching Carbonite's own
  `NXDetailScale` default), zone-overview tiles return once zoomed
  back out.
  - The `MapWorldInfo[13]`/`[14]` anchor-index concern noted when this
    first landed turned out to be fine — confirmed live, position
    matches.
  - **Found and fixed live, 2026-11-10**: the detail tiles weren't
    appearing at all once zoomed past the threshold (background went
    blank, only the live-widget patch remained; panning rendered
    nothing new) — all three symptoms traced to one cause.
    `GetMiniInfo` (`MinimapRuntime.lua`) needs a per-zone `.Cont` field
    to know which continent's tile table to use, but that field is
    only ever written by the dead `BuildMissingZoneInfo` resolver
    (needs the real `Nx.Zones` database this addon doesn't have), so
    it's nil on every ordinary outdoor zone — `GetMiniInfo` silently
    returned nil every time. Fixed by falling back to
    `MinimapEngine.Cont`, the engine's own already-reliable current-
    continent number (the same one `MoveZoneTiles` already uses
    correctly), since `GetMiniInfo` is only ever called here with the
    current zone anyway.
  - **Found and fixed live, 2026-11-10 (second round)**: after the fix
    above, detail tiles appeared and were correctly positioned, but
    only ever as one frozen square that didn't change while
    panning/zooming. Root cause: the zoom-threshold gate was wrongly
    written as an either/or switch between the zone-overview layer and
    the detail-tile layer. Re-reading real Carbonite's `UpdateZones`
    (`MapEngine.lua:9831-9900`) shows `UpdateMiniFrames()` is called
    unconditionally on *every* tick at *every* zoom level in every
    branch — the threshold only ever decides whether the coarse
    zone-overview art is *also* drawn on top of it (zoomed out) or
    cleared (zoomed in). Gating `UpdateMiniFrames` itself behind the
    threshold meant detail tiles only ever turned on once already
    zoomed in far enough that a single ~107-world-unit tile exceeded
    the whole window — so only one tile was ever visible, and panning
    within it looked like nothing was happening. Fixed by calling
    `UpdateMiniFrames()` unconditionally every tick, matching real
    Carbonite exactly; only the zone-overview draw/clear choice stays
    behind the threshold.
- **Added a canvas-drawn player-position marker** (new:
  `MinimapEngine.lua`'s `ClipFrameW`/`UpdatePlayerMarker`, `PlyrFrm`).
  Root cause of "I see no icons, I have no idea where I am" and of
  markers visibly disagreeing after zooming: the live Blizzard-widget
  blend was the *only* thing in this addon showing player position,
  and it can legitimately clip out of view entirely (same "pan far
  enough and lose the square" behavior disclosed since this project's
  very first session) or visibly diverge from the tile layers whenever
  the view's pan target differs from the player's raw live position
  (mid-animation after a zoom/recenter, or panned away with auto-follow
  off). Investigated how real Carbonite actually solves this: it has
  no separate "draw the player" mechanism at all — the player marker
  is just one more icon (a "Player" Pin) drawn by the same generic
  per-frame icon renderer as every other world icon (mailbox, inn,
  quest giver), through the identical world-to-screen math this
  addon's own tile code already uses, with one dedicated frame instead
  of the generic icon pool since there's always exactly one. Ported
  that same mechanism at the same scope: one dedicated frame, the real
  `ClipFrameW` point-clip math (fixed pixel size, not scaled by zoom —
  unlike tiles), repositioned every tick, independent of both tile
  layers and the live widget. Includes facing-direction rotation;
  corrected a real degrees-vs-radians unit mismatch found along the
  way in Carbonite's own legacy source (its `PlyrDir` is computed in
  degrees but fed straight into `cos()`/`sin()`, which expect radians)
  rather than porting that mismatch faithfully.
- **Decision, 2026-11-10**: user chose to reopen the full mailbox/
  inn/quest-giver icon system (Carbonite's real Pin/Layer/Renderer
  architecture) as real scope, previously an explicit non-goal.
- **Added static service-location icons** (mailbox, innkeeper, flight
  master; new `Map/Data/GuideMailbox.lua`/`GuideInnkeeper.lua`,
  `MinimapEngine.lua`'s `RefreshServiceIcons`/`UpdateServiceIcons`).
  First concrete slice of the scope decision above. Investigated how
  real Carbonite actually sources these: unlike quest-giver/trainer/
  gather icons (live game state, the generic Pin/Layer/Renderer
  system), static service icons come from a hand-curated per-flavor
  coordinate database keyed by mapID
  (`Carbonite/Data/camelot/Guides/<Kind>.lua`) — ported Mailbox/
  Innkeeper verbatim. Flight Master's own camelot data file ships
  empty for this flavor (no coordinates, just a mode flag) — sourced
  from Blizzard's live `C_TaxiMap` API instead, which is arguably more
  robust anyway (always accurate to what's actually been discovered).
  World positions resolve once per zone change; screen position still
  updates every tick (pan/zoom), reusing step 9a's `ClipFrameW`
  directly rather than new clip math.
  - **Found and fixed live, 2026-11-10**: while wiring this up,
    discovered `GetWorldPos` — referenced by name in several existing
    comments across this file (`RefreshCurrentZone`, `NxMapData.lua`'s
    dead zone-resolver) as if it already existed — was never actually
    implemented. It would have errored on first real call. Added it
    using the exact same per-zone anchor/scale data
    `GetWorldZoneInfo` already relies on successfully, just in its
    general "convert an arbitrary 0-100 zone-relative position"
    form instead of that function's fixed "top-left + full span"
    return.
  - Icon textures are standard Blizzard minimap-tracking-filter
    paths, not Carbonite's own icon atlas, and not yet confirmed to
    exist on this server build — this server has already shown one
    default Blizzard texture path missing entirely this same session
    (the native mail-icon fix). Needs live verification.
  - Completely untested in-game as of this writing.
- **First live test results, 2026-11-10, and fixes from them**:
  - Player marker appeared but never rotated (always pointed up) and
    was reported too small. Bumped `PLAYER_MARKER_SIZE` 20→28. For
    rotation: the hand-rolled UV-corner-rotation math ported from
    Carbonite's legacy `ClipFrameW` couldn't be cross-checked against
    a working reference (the newer Pin-system rewrite's own
    `PlayerPin.lua` doesn't carry facing/rotation over at all - it
    only tracks x/y) and evidently had a bug somewhere. Replaced with
    the texture's native `:SetRotation()` instead - the standard WoW
    API for exactly this, simpler and not dependent on hand-rolled
    trig. Dropped the now-unneeded degrees/radians sign correction on
    `PlyrDir` that only made sense for the old UV-math formula. If
    this turns out mirrored (rotates backwards) rather than not
    rotating, the fix is a one-line sign flip, not another rewrite.
  - Only one of three innkeeper entries in The Barrens (mapID 1413)
    showed, and it was the wrong one for a Horde player (a neutral
    entry near Ratchet, not Crossroads). Root cause: this addon's own
    `ServiceIconFactionOk` had Carbonite's real faction convention
    backwards. Real `hideFaction()` (`GuideLocations.lua`) returns the
    code to HIDE (1 for Horde, 2 for Alliance), and its call site shows
    an entry when `fac ~= hide` - so fac==1 is Alliance-only and
    fac==2 is Horde-only. This addon's port had it exactly reversed,
    silently hiding every Horde-only entry from Horde players (and
    vice versa for Alliance). Fixed - same bug affected Mailbox
    identically, same fix applies to both.
  - No mail icon appeared at all. Root cause: `Interface\Minimap\
    TrackingIcons\Mailbox` is in the exact same `Interface\Minimap\...`
    texture family already confirmed broken on this server build this
    same session (`MinimapDock.lua`'s native mail-icon fix -
    `MiniMap-MailIcon` renders nothing here). Switched to
    `Interface\Icons\INV_Letter_15`, that same earlier fix's own
    already-verified-visible replacement, rather than guessing a third
    path blind. Innkeeper's own path
    (`Interface\MINIMAP\TRACKING\Innkeeper`) is a different, modern
    texture family and is now confirmed working (visible once the
    faction bug above was fixed) - left unchanged.
  - No flight-master icon appeared at a Crossroads landing. **Not yet
    root-caused** - unlike the three fixes above, this one is still
    open. Flight Master's own texture path is in the same now-
    confirmed-working family as Innkeeper, so a texture problem is
    unlikely; more likely `C_TaxiMap.GetTaxiNodesForMap` isn't
    returning what's expected for this mapID on this server build, or
    there's a reachable/current state-filtering mismatch. See
    `RefreshServiceIcons`'s own header comment for the open question.
  - Quest-giver icons still don't appear - **expected, not a bug**:
    the dynamic Pin/Layer/Renderer system quest-givers would need is
    explicitly out of scope so far (see the "reopen full icon/pin
    system" decision above) - only the static service-icon slice
    (mailbox/innkeeper/flight-master) has been built.
- **Flight-master icon, root-caused and fixed, 2026-11-10**: the
  original reachability check (`node.state == Enum.FlightPathState...`)
  never matched anything on this server build. Found an already-
  installed, already-working addon on this exact server
  (`ForeverDungeonJournal/Systems/MapMarkers.lua`) that also calls
  `C_TaxiMap.GetTaxiNodesForMap` and does NOT trust the node's own
  state/type field for reachability either - it tracks "discovered"
  itself, specifically because the live field isn't reliable here. It
  also reads `node.position` defensively (plain `{x,y}` table on some
  builds, a Vector2D needing `:GetXY()` on others). Matched both of
  those: dropped the reachability filter entirely (shows every node
  the API returns for the zone - "shows an undiscovered one too" beats
  "shows none"), fixed position reading, added the same faction filter
  the mailbox/innkeeper fix above uses (`node.faction`, same
  1=Horde-only/2=Alliance-only convention, confirmed against that same
  addon's own filter).
- **Added quest turn-in markers** (user asked to "get... quest
  working" after testing the above). Investigated a large, real,
  already-working quest-map-icon implementation on this same server
  first (`Carbonite.Quests/MapIcons.lua`, 2000+ lines) before writing
  anything. Two findings shaped the scope:
  - A "new available quest, NPC not yet talked to" marker needs a
    static NPC-to-quest database. The one already installed
    (QuestieDB) has exactly this data via its public `LibQuestieDB`
    contract, but stores spawn positions by legacy AreaID, not this
    engine's uiMapID - converting between the two turns out to need
    Questie's own PRIVATE, undocumented `ZoneDB` module (confirmed:
    even Questie's own `QuestiePlayer:GetCurrentZoneId` depends on it
    for exactly this). Not a stable contract to build on - **deferred,
    not built**, real future scope.
  - A "where do I turn in a quest already in my log" marker needs none
    of that - `C_QuestLog.GetQuestsOnMap(mapID)` is a live, standard,
    external-database-free Blizzard API, confirmed current by
    Carbonite.Quests' own use of it as its primary feed. Built this
    half only: `RefreshQuestIcons`/`UpdateQuestIcons` show the
    standard quest-turn-in texture (`Interface\GossipFrame\
    ActiveQuestIcon`, same one Carbonite's own `QuestPin.lua` names)
    at every map point whose quest is flagged complete
    (`C_QuestLog.IsComplete`). Refreshes on zone change plus a plain
    2-second throttle (quest state can change without a zone change,
    unlike the static service-icon data). In-progress objective
    markers (not yet complete) are deliberately left out of this first
    pass - simpler scope, avoids ambiguity about what a mid-quest
    marker would even mean positionally.
  - Completely untested in-game as of this writing.
- **Live test, 2026-11-10 (Camp Taurajo, The Barrens)**: user reported
  neither quest nor flight-master icons appeared. Diagnosed with two
  one-line `/run` checks rather than guessing a third time:
  - Quest icons: confirmed working as designed, not broken - zero
    complete quests in the log at the time, so correctly nothing to
    show. Only a turn-in-ready quest produces a marker.
  - Flight master: genuinely broken. `GetTaxiNodesForMap(1413)`
    returned 38 nodes - the whole continent's flight network (the
    same thing a flight master's own map shows when you talk to one),
    not just nodes physically in The Barrens. Their positions, read as
    percent-through-this-zone, land far outside it once converted to
    world space - not necessarily safely off-screen, since that wrong
    position could coincidentally overlap something else on the
    canvas. Added an explicit 0-1 bounds check on the node's position
    before converting, rejecting every node that doesn't actually
    belong to the current zone.
- **Live test round 2, 2026-11-10 (Camp Taurajo)**: user moved away
  and zoomed in - still no flight-master icon. Ruled out the obvious
  theory first (player marker drawn on a higher frame level than
  service icons, and the node's position is almost exactly the
  player's own coordinate) by asking the user to step away; icon still
  didn't appear, so that wasn't it. One more `/run` check
  (`d.faction, d.type, d.state` for the Taurajo node) found the real
  cause: `print` returned `1  nil  nil` - `C_TaxiMap`'s own
  `node.faction` does NOT use `GuideData`'s hide-code convention
  (1=Alliance-only/2=Horde-only, confirmed against Carbonite's
  `hideFaction()`). It's direct identity instead (1=Horde, 2=Alliance)
  - Camp Taurajo (a real Horde-only flight point) reporting `faction=1`
  proves it. Reusing `ServiceIconFactionOk` for taxi nodes was
  rejecting every node of the player's own faction outright, which is
  why none ever rendered even after the whole-continent bounds-check
  fix. Added a separate `TaxiFactionOk` with the opposite convention -
  deliberately NOT merged into `ServiceIconFactionOk`, since the two
  data sources disagree on what the numbers mean and conflating them
  would silently reintroduce this exact bug later.

### Right-click brightness menu (new: `MapContextMenu.lua`)
- Added a small right-click popup on the map window with a tile-map
  brightness slider, built on plain frame primitives rather than
  porting Carbonite's full menu system.
- Brightness range is 0–100% (plain alpha-style multiplier on the tile
  art's color channels) — an earlier 0–250% "overbrightening" version
  was tried and explicitly reverted.
- Closes on any click outside the menu, via an `OnUpdate` mouse-button
  poll rather than an invisible full-screen catcher frame — the
  catcher approach tripped Blizzard's protected-action taint warning
  by sitting on top of the action bars.
- Right-click again on the map toggles the menu closed (same action
  that opens it).
- **Fixed, 2026-11-10**: the long-deferred "Your AddOns are
  experiencing a large number of errors" popup, finally reproduced
  with an exact error — `MapContextMenu.lua:93: attempt to call a nil
  value`, firing every single `OnUpdate` tick while this menu was
  open. Root cause: the global `MouseIsOver()` function doesn't exist
  on this server's client build — same pattern as the native mail-icon
  texture also being missing. Switched the outside-click-dismiss check
  to the frame's own `:IsMouseOver()` method, which doesn't depend on
  that global.

### Minimap icon dock (`MinimapDock.lua`)
- Fixed real addon/Blizzard minimap buttons being swept up as fake
  icons, or missed entirely:
  - The generic "anything anchored to Minimap" scan matched real
    Carbonite's own filter (exclude only `Model`-type objects) too
    loosely for this server — `MinimapBackdrop` (a decorative frame
    carrying the coordinate text) was getting grabbed and rendered as
    a stray sliver of tiny text in the bar. Narrowed to
    `IsObjectType("Button")` in both the one-time scan and the
    repeating child scan.
  - Blizzard's native minimap zoom buttons are real Button-type
    widgets anchored the same way a genuine addon launcher is; added
    to the name-exclude list.
  - A button whose width hadn't resolved yet was retried forever and
    never actually docked — real addon icons simply never appeared.
    Now falls back to Blizzard's standard 32px button size instead of
    waiting indefinitely.
- Added a mail icon to the dock. This server's client uses the modern
  (post-Shadowlands) minimap structure —
  `MinimapCluster.IndicatorFrame.MailFrame` — not the old flat
  `MiniMapMailFrame` global real Carbonite and this addon's own
  `KNOWN_NAMES` list both assumed. The dock forwards that real native
  button (keeping its working hover/tooltip) rather than building a
  fully standalone one:
  - The native button's own texture region is a numeric FileDataID
    that renders as nothing on this server; a separate, non-mouse-
    interactive overlay texture is layered on top instead so it can
    never block the hover.
  - Blizzard's `Interface\Minimap\MiniMap-MailIcon` art also does not
    exist on this client build at all (confirmed with an isolated
    on-screen test) — using `Interface\Icons\INV_Letter_15` instead
    (the same icon real Carbonite's own guide data uses for mailbox
    markers).
  - Visibility is driven by polling `HasNewMail()` every tick rather
    than trusting the native frame's own show/hide, matching real
    Carbonite's own `MailboxNotice` module, which doesn't trust it
    either.
  - Icon creation/acquisition is safe to retry every tick rather than
    once at startup — the native mail frame, like
    `GameTimeFrame`/`TimeManagerClockButton`, can be one of this
    server's lazily-created elements not yet present at addon load.

### Known open item
- A "large number of AddOn errors" popup was seen once with this
  menu open on screen; cause not yet confirmed. Deferred at the time —
  revisit with `/console scriptErrors 1` set and the exact error text
  next time it reproduces.

- **Build-order step 10, 2026-11-11: right-click goto waypoint + ant-
  trail.** User's request: "carbonite has a feature where you can
  right click set a goto at that spot then get ant trails from you to
  the location... a little number above [the dot] that is the yards
  away... updates as you move... use the flowing arrows like
  carbonite, snag their art if need be." Confirmed the UX against real
  Carbonite's own source (`Carbonite\Modules\Map\MapEngine.lua`) rather
  than guessing: right-click opens a menu (matches this addon's own
  `MapContextMenu.lua` exactly), with "Set Goto"/"Clear Goto" as two of
  that menu's real items.
  - `MapContextMenu.lua`: two new button rows, "Set Goto Here" and
    "Clear Goto" (menu resized 220×260 → 220×320 to fit them), wired to
    two new `MinimapEngine` methods of the same name/intent.
  - `MinimapEngine.lua`'s `OnMouseUp` RightButton branch now also
    captures the click's frame-local pixel position (`ClickFrmX/Y`)
    *before* the menu opens — ported from real Carbonite's own
    `CalcClick` (sampled once, at click time, not resampled when the
    menu item is later clicked). New `FramePosToWorldPos(fx, fy)`
    converts that back into this engine's own world-coordinate space —
    the algebraic inverse of `ClipFrameW`'s forward formula, reusing
    the exact same inversion `MouseWheel`'s zoom-at-cursor code already
    proven working, rather than deriving a new one.
  - Goto storage is a single in-memory point (`GotoWX/GotoWY/GotoCont`)
    — not saved to `AlchemyGPS.db`, matching real Carbonite's own
    `Nx.Map.Targets` (a plain runtime table, confirmed never written to
    its SavedVariables either). Cleared on arrival (within 7 yards —
    real Carbonite's own default `Target.Radius`) with a
    `UIErrorsFrame` message and `PlaySoundFile(567455)`, both real
    calls confirmed in Carbonite's own arrival-check code.
  - Ant trail: pooled arrow frames spaced every 15 world-units (capped
    at 40), straight line from player to goto, textured with real
    Carbonite's own art (`Carbonite\Gfx\Map\IconArrowGrad.tga` for the
    arrows, `IconWayTarget.tga` for the destination dot — both
    confirmed present on disk, per the user's own "snag their art if
    need be"). The "flowing" look is mostly the player's own live
    position advancing every tick; a small extra creep
    (`self.ArrowScroll`) keeps the ants moving while standing still,
    gated on `self.PlyrSpeed == 0` exactly like real Carbonite's own
    `DrawTracking`, reusing this engine's own already-existing
    `PlyrSpeed` field rather than adding a new speed check.
  - Yardage label: a new `#yd` `FontString` anchored above the dot,
    text = `ceil(dist * 4.575)` — the same constant/formula this
    engine's own `PlyrSpeed` calc already uses, confirmed against real
    Carbonite's canonical formula and NOT its dead-code `YardsBetween`
    variant (zero callers anywhere in real Carbonite; it re-multiplies
    by zone `Scale` a second time and would double-apply it). This
    specific `#yd`-above-the-dot display does not exist in real
    Carbonite at all (confirmed — its only live distance readouts are
    a hover tooltip and a separate HUD arrow window, neither anchored
    to the map canvas) — built fresh for this addon, not ported.
  - **Unconfirmed, flagged the same way as the player marker's own
    rotation**: the ant-trail arrows' pointing direction
    (`math.atan2(-dx, -dy)`, feeding this engine's own
    `ClipFrameW`/`:SetRotation`) is derived fresh rather than ported —
    real Carbonite's own rotation formula answers a different question
    (its own legacy degree-based UV-rotation system, which this addon
    doesn't use). If the arrows render pointing backwards or sideways
    rather than along the trail, that one `atan2` call is the fix, not
    a rewrite. Everything else in this entry is either a direct port
    of confirmed-real Carbonite logic or a small, clearly-marked new
    addition — not yet live-tested as a whole.

### Build-order step 10 follow-up, 2026-11-11: live-tested working + menu restyle.

- **Live-tested, confirmed correct** — the goto/ant-trail feature above
  works as built: trail arrows point the right way (the unconfirmed
  `atan2(-dx, -dy)` guess turned out correct, no fix needed), the addon
  detects arrival and clears the goto, the chat message and sound both
  fire.
- **"Set Goto Here"/"Clear Goto" moved to the top of the menu and
  restyled**, per explicit user request to render first and look like
  "a small line like the carbonite addon" rather than full buttons.
  Read real Carbonite's own menu-rendering code
  (`Nx.Menu:AddItem`/`Nx.Menu:Update`, `Modules/UI/UIEngine.lua:5483-
  5871`) rather than guessing at the look: each of its rows is a plain
  frame spanning the menu width minus margins, ~12px tall, no button
  border/texture at all, with a tinted highlight that fades in on
  hover (manual alpha animation in `Item_OnEnter`/`Item_OnUpdate`) and
  a left-justified `FontString`. `MapContextMenu.lua`'s new
  `createMenuRow` helper reproduces that same look — same borderless,
  width-spanning, left-justified-text shape — but as a plain `Button`
  frame using a WoW `HIGHLIGHT`-layer texture (`SetHighlightTexture`)
  instead of hand-rolling Carbonite's own `OnEnter`/`OnLeave`/`OnUpdate`
  alpha-fade trio, since Blizzard's highlight layer already does the
  identical show-on-hover/hide-on-leave job for free — same visual
  result, no new animation code needed. The two rows now sit at the
  very top of the menu (`-10` and `-10 - (16+2)` from the menu's own
  `TOP`), with every slider/label below them shifted down by a flat 40
  so none of their existing relative spacing needed touching; menu
  height grew from 220×320 to 220×310 to re-fit (shorter overall once
  the old 22px-tall buttons were replaced by 16px-tall rows).
