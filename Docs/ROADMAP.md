# Alchemy GPS — Roadmap

Companion to `../CHANGELOG.md` (dated history - the permanent record
of what's confirmed/fixed/why). This is the ordered plan from here to
"the minimap module is done" — read `CHANGELOG.md`'s most recent
entries first if picking this up cold.

**2026-11-11 note**: `Docs/STATUS.md` (a living audit/snapshot doc)
was deleted once its content was fully superseded by `CHANGELOG.md`'s
dated entries and the per-phase testing docs - there is no separate
"current state" doc anymore, by design. Every reference below that
used to point at `STATUS.md` now points at the specific `CHANGELOG.md`
entry that covers the same fact instead.

**2026-11-10 amendment**: "Mode: Live"/the live Blizzard-widget blend
(build-order step 4, `ClipMMW` etc.) was removed entirely this same
day — see `CHANGELOG.md`'s GatherMate2-taint-popup entries (rounds
5-9) for the removal's own history. `Docs/Testing/Phase4-*.md` (if it
exists) and anything in Phase5-7's docs that specifically tests the
live-widget patch (zoomType tiers, widget show/hide at fit boundaries)
now tests a mechanism that no longer exists — read each doc against
today's code before running it, same as Step A item 3 below already
flags for the preset-search rewrite.

## Step A — Close out Phase 8 testing formally

**Phases 5 (Zoom), 6 (Pan-drag), and 7 (Resize) confirmed passing live
by the user, 2026-11-10** — see `CHANGELOG.md`'s step 9n entry (their
own `Docs/Testing/Phase*.md` checklists were deleted once confirmed -
no longer needed as open checklists). The old Phase 7 Test 2
(zoomType tier transitions) no longer exists as a test at all — that
preset system was removed along with the live-widget mechanism, and
the doc itself was already updated to drop it rather than test a
mechanism that's gone. Phase 8 is the only one left:

1. Walk `Docs/Testing/Phase8-WorldArtCanvas.md` top to bottom, record
   pass/fail per test — particular attention to Test 1 (background art
   appears) and Test 4 (position dot direction), the two places the
   doc itself flags as most likely to still be wrong.
2. Any failure found: fix it, redeploy, re-test that one item, *then*
   continue the walk rather than batching fixes — same one-change-at-
   a-time discipline the original plan was built around.
3. Once it passes clean: record it in a new `CHANGELOG.md` entry,
   matching step 9n's own pattern for Phase 5-7 (no build-order table
   to update anymore - `CHANGELOG.md`'s dated entries are the
   permanent record now).

## Step B — Retroactive test coverage for the beyond-scope features

**Superseded, 2026-11-10**: these got ONE consolidated doc instead of
one each — `Docs/Testing/Phase9-IconsAndUI.md` now covers icon dock,
mail forwarding, the brightness/gathering-icon sliders, service/
gathering/filter-menu icons, and more. The specific test ideas below
are kept as reference detail in case that consolidated doc needs
expanding, not as a still-open task list.

Icon dock, mail-button forwarding, and the brightness menu are real
shipped features with their own real bug histories (several rounds
each — see `CHANGELOG.md`) but no test doc of their own, unlike every
numbered phase. Write one short doc per feature, same format as the
existing Phase5-8 docs (setup → numbered tests → expected result →
what to report back), and run each once:

- `Docs/Testing/IconDock.md` — real addon buttons get collected and
  stay docked after `/reload` and after a loading-screen transition
  (the original infinite-retry and lazy-init bugs both specifically
  showed up around those two moments); row vs. column orientation
  toggle actually re-lays-out live; a button that disappears (addon
  disabled mid-session) doesn't leave a gap/crash.
- `Docs/Testing/MailIcon.md` — icon appears when mail is pending and
  disappears once collected; hover/tooltip still names the sender;
  survives `/reload` and a zone change (both previously broke it at
  different points in this session's fix history).
- `Docs/Testing/BrightnessMenu.md` — slider range is 0-100% and
  persists across `/reload`; menu closes on any outside click without
  tripping a taint warning (the specific prior bug); right-click
  toggles open/closed correctly.
- `Docs/Testing/DetailTiles.md` (new, 2026-11-10, highest priority of
  this list - genuinely untested, not just undocumented) — zoom in
  past the threshold (~5 zoom-in clicks from default) in both Kalimdor
  and Eastern Kingdoms and confirm the detail tiles that appear match
  where you actually are (see `CHANGELOG.md`'s `### Map window` section
  - the `MapWorldInfo[13]`/`[14]` anchor-index note - for why this
  specifically needs checking); confirm zoning between the
  two continents swaps tile sets correctly; confirm zooming back out
  cleanly restores the zone-overview tiles with no leftover detail
  tiles; confirm panning while zoomed in scrolls new tiles in smoothly
  at the edges.
- `Docs/Testing/PlayerMarkerAndServiceIcons.md` (new, 2026-11-10,
  highest priority — genuinely untested, not just undocumented) —
  the player-arrow marker stays visible and correctly placed even when
  the live-widget patch itself clips out of view (panned away, or
  auto-follow off); it rotates to match facing; mailbox/innkeeper/
  flight-master icons appear with a real texture (not blank) at
  roughly the right real-world spots in at least two different zones;
  icons disappear/reappear correctly on zone change; faction filtering
  hides the opposite faction's innkeeper/mailbox entries where the
  data marks one.
- `Docs/Testing/GatherNodes.md` (new, 2026-11-10, highest priority —
  genuinely untested, not just undocumented) — **reverted to static
  Wowhead data, 2026-11-10 (see `CHANGELOG.md`'s round-9 entry); no
  GatherMate2 dependency at all now, test with it disabled** — herb/
  mining/fish/treasure icons appear using one generic profession-icon
  texture per category (`Trade_Herbalism`/`Trade_Mining`/
  `Trade_Fishing`/a bag icon for treasure); gated correctly by which
  professions the character actually knows; icons dim/brighten
  correctly as the player walks toward and away from a known point
  (confirms `GATHER_NEARBY_RANGE` is in the right ballpark — adjust
  the constant in `MinimapEngine.lua` if it triggers obviously too
  early or too late); no visible frame-rate stutter in a dense zone
  (confirms the 0.1s reposition throttle is enough); icons disappear/
  reappear correctly on zone change.
- `Docs/Testing/AutoFollow.md` (new, 2026-11-10) — unchecking the
  title-bar checkbox lets a manual pan stay put instead of snapping
  back to center within ~30 ticks of releasing the drag; re-checking
  it resumes continuous follow immediately; the checked state persists
  across `/reload`; going indoors (see `CHANGELOG.md`'s `### Map
  window` section, the indoor-freeze-gate fix) freezes the view rather
  than disappearing, with or without auto-follow on.

## Step C — Resolve the deferred error popup

**Done, 2026-11-10** — reproduced and fixed. See `CHANGELOG.md`'s
`### Right-click brightness menu` section for the root cause
(`MouseIsOver()` missing on this server's client build) and
fix (`:IsMouseOver()` instead).

## Step D — Phase 9: keybind + remaining polish

The original plan's Phase 9, minus the anchor/size persistence half
(already done via `WindowLayouts`):

1. Force-bind `Ctrl+Shift+M` every login via `SetBinding` (not saved
   via `SaveBindings` — see the plan's reasoning: override the chord
   for the session without permanently touching the user's real
   keybind profile).
2. Add `Bindings.xml` with the `BINDING_HEADER_ALCHEMYGPS` /
   `BINDING_NAME_...` declaration so the chord is visible/rebindable
   in Blizzard's own Key Bindings UI. Remember: **do not** list
   `Bindings.xml` in the `.toc` — Blizzard auto-detects it by filename,
   and explicitly listing it breaks XML loading (the exact mistake
   `AlchemyNavigation` already hit once).
3. Wire the binding to the same `MinimapWindow:Open()` the Settings
   window's "Show Minimap" button already calls.

## Step E — Phase 10: one dedicated full regression pass

Every change so far has been deployed and tested individually (correct
discipline, keep doing it for anything new) but the *whole* feature
set together has never been walked in one sitting. Before calling the
module done:

1. Full client restart (not `/reload`) on a clean login.
2. Zero Lua errors through login, zone change, and opening every
   window this addon has (`/gps showmap`, `/gps settings`, the
   right-click brightness menu).
3. Re-run Step A/B's checklists once more, back to back, as a single
   pass rather than individually — this is what would have caught a
   regression like the Phase 8 fixes interacting badly with Phase 5's
   zoom math, if one existed.
4. Confirm the live `R:\addons\AlchemyGPS\` tree and the deployed
   `G:\...\AddOns\AlchemyGPS\` tree are byte-identical file-by-file
   (not just the files touched in the most recent change) — the
   standing per-change diff check has only ever verified files touched
   in that change.

## Step F — Reconcile the written plan with reality

`../../AlchemyGPS-Plan.md` (outside this repo, at the addons root)
still lists the icon dock as a non-goal and doesn't mention the
brightness menu or mail-button forwarding at all, since all three
postdate it. Once Steps A-E are done, either:

- add a short "amendments" section at the top of that plan file
  pointing here and to `../CHANGELOG.md`, or
- treat `ROADMAP.md`/`CHANGELOG.md` as having fully superseded it for
  anything past Phase 8, and leave the original file as historical
  record of the Phase 1-8 design decisions (which are all still
  accurate) without editing it further.

Either is fine — just pick one rather than leaving two docs silently
disagreeing about current scope.

## After that: is the module "done"?

Once Steps A-F are complete, the minimap module matches (and exceeds)
everything the original plan set out to build. Anything past that
point — a new module (world map, quest log, etc.), the optional
`Nx.Window:OpenMenu` right-click-on-the-*window*-chrome context menu
the original plan explicitly called "polish, not required for v1," or
further icon-dock features (per-button hide list, drag-to-reorder) —
is new scope, not completion of this plan, and should get its own
planning pass rather than being folded in here.
