# Phase 8 — Real world-art canvas: test plan

Covers: the zone-overview background art (`C_Map.GetMapArtLayers`/
`GetMapArtLayerTextures`, still the current mechanism — not removed by the
later Mode:Live purge, which only removed the separate live-widget blend)
and the player-position marker. Full history in `CHANGELOG.md`.

Where older notes say "the live-widget patch," read "the player marker"
instead — that's the thing actually tracking position now.

## Still needs confirming

- [ ] **NOT YET CONFIRMED** — background art appears for a normal outdoor
      zone (watch for `Cont=nil`, which means the zone isn't in the
      static catalog — expected for instances, a real gap for an outdoor
      zone)
- [ ] **NOT YET CONFIRMED** — background art pans/zooms in lockstep with
      the player marker, no drift
- [ ] **NOT YET CONFIRMED** — crossing a zone boundary swaps the canvas
      and re-centers correctly
- [ ] **FIXED 2026-11-09, not reconfirmed since** — player marker
      direction/position (was mis-anchored and Y-flipped; both corrected
      against real Carbonite's own formula, but the fix itself was never
      walked live afterward)
- [ ] **NOT YET CONFIRMED** — no flicker/texture-pop standing still for
      15-20s

None of the above has a recorded pass since this doc was written.

## Setup

1. **Full client restart** (not just `/reload`) if this hasn't been
   tested since `Map\Data\NxMapData.lua` was added to the `.toc`.
2. Log in standing in a normal outdoor zone. `/gps showmap`, debug overlay
   on (`MapId`/`Cont`/`Zone`/`CurWorldUpdateMapId`/`tiles`, `PlyrX`/`PlyrY`/
   `PlyrDir`).
3. Check chat for a red Lua error naming `NxMapData.lua` or
   `MinimapEngine.lua` before testing anything else.

## Test 1 — background art appears

**Expected**: real zone terrain fills the window. `MapId` non-nil, `Cont`
is `1`/`2`/`3` (not `nil` for an outdoor zone), `tiles` is a small
positive number.

## Test 2 — art tracks pan/zoom

Zoom and pan. **Expected**: background terrain and player marker never
visibly drift apart.

## Test 3 — zone crossing updates the canvas

Walk/fly across a real zone border. **Expected**: background art swaps to
the new zone shortly after the game's own "zone changed" toast, and
re-centers on the new zone.

## Test 4 — player marker direction

Note a landmark, compare the marker's position to your actual position,
then walk a fixed compass direction for 30-60s. **Expected**: walking
north moves the marker north on the art (not south/mirrored). If it's
still backwards on any axis, that's a real bug — the formula was
corrected from source but never re-walked live.

## Test 5 — stability standing still

Stand still 15-20s. **Expected**: no flicker, no re-fetch flashing.

## Known non-goals (don't report as bugs)

Instances/dungeons/raids/battlegrounds (`Cont=nil`, no art — separate,
explicitly out of scope), continent-wide zoomed-out view, fog-of-war,
zone-name label overlay.

## What to report back

Pass/fail per test, screenshot (debug overlay visible), and which exact
zone(s) tested — especially for Test 1's `Cont=nil` case and Test 4's
direction check.
