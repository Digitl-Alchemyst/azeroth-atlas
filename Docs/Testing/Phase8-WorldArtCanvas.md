# Phase 8 — Real world-art canvas: test plan

Covers: the big, new piece — the window now draws the player's actual
continent/zone as Blizzard's real map art (fetched live via
`C_Map.GetMapArtLayers`/`GetMapArtLayerTextures`), positioned/scaled by the
same pan/zoom state Phase 5/6 already animate, plus a live player-position
dot replacing the fixed-at-center stand-in from build-order step 4. This is
also the first phase to add a new file to the `.toc`/load order
(`Map\Data\NxMapData.lua`, Carbonite's own real Camelot-flavor zone/
continent database, copied nearly byte-for-byte) — **a full client restart
is required**, not just `/reload`, the first time you test this phase.

## Setup

1. **Fully exit and relaunch the WoW client** (not just `/reload` — a new
   file was added to the addon's load manifest).
2. Log in on a character standing in a normal outdoor zone (not a
   dungeon/raid/battleground — those are explicitly out of scope for this
   phase, see "Known non-goals" below).
3. `/gps showmap` to open the window.
4. Keep the debug panel in view — it now has three new lines:
   - `MapId=... Cont=... Zone=... CurWorldUpdateMapId=... tiles=...`
   - `PlyrX=... PlyrY=...`
5. **First check before anything else**: look at the chat frame for a red
   Lua error right after the client finishes loading. If there's an error
   naming `NxMapData.lua` or `MinimapEngine.lua`, stop and report it
   verbatim (file/line/message) before testing anything below — that means
   something in the ported data file didn't load cleanly.

## Test 1 — the background art actually appears

1. With the window open and no error in Test setup, look at the content
   area.

**Expected**: instead of the plain dark background from earlier phases,
you should now see real Blizzard world-map art — the terrain/texture of
whatever zone you're standing in — filling the window behind the live
minimap widget patch.

**Debug panel fields to watch**: `MapId` should show a real map ID
(non-zero, non-nil). `Cont` should show `1`, `2`, or `3` (not `nil` — `nil`
means your current zone isn't in Carbonite's static catalog for this
flavor, see "Known non-goals"). `CurWorldUpdateMapId` should match `MapId`
once the art has loaded. `tiles` should show a small positive number
(typically 6-20 depending on the zone's art-layer tile grid).

**If you see `Cont=nil` for a normal outdoor zone** (not an instance): this
is the one open risk from this phase's implementation — the player's
current zone isn't being found in the ported `MapZones` membership lists.
Report exactly which zone you were in, plus a screenshot of the debug
panel, so the zone-lookup logic can be checked against that specific zone.

## Test 2 — background art pans/zooms in lockstep with the live widget

1. Zoom in/out with the mouse wheel (Phase 5).
2. Pan by dragging (Phase 6).

**Expected**: the background terrain moves and scales together with the
live-widget patch and its ring mask — they should never visibly drift
apart or desync, since both are driven by the same `Scale`/`ScaleDraw`/
`MapPosX*Draw` state. If the background terrain seems to move at a
different rate or in a different direction than the widget patch inside
it, that's a bug — screenshot it.

## Test 3 — crossing a zone boundary updates the canvas

1. Walk/fly across a real zone boundary (e.g. from Durotar into the
   Barrens, or any adjacent zone transition).
2. Watch the window while crossing.

**Expected**: shortly after the game itself recognizes you've entered the
new zone (watch for the normal "Zone changed" toast/sound), the window's
background art should swap to the new zone's terrain, and the view should
re-pan to center roughly on the new zone (not stay centered on the old
zone's now-irrelevant coordinates).

**Debug panel fields to watch**: `MapId`/`Zone` should update to the new
zone's ID. `CurWorldUpdateMapId` should catch up to match within a tick or
two (the new zone's art fetch is a one-tick cache-miss, not continuously
re-fetched).

## Test 4 — the live player-position dot is in roughly the right place

**Updated 2026-11-09**: a live screenshot caught the background art badly
mispositioned (most of the window blank, only a sliver of real terrain in
one corner) — tracing that bug back through the real Carbonite source also
turned up a second, related bug in this exact player-position formula (it
was both mis-anchored and Y-flipped relative to the real
`Nx.Map:GetWorldPos`/`GetPlayerMapPosition` convention). Both are now fixed
in `MinimapEngine.lua` (pan-to-zone-center in `RefreshCurrentZone`, and
`PlyrX = zx + px * zw` / `PlyrY = zy + py * zh` with no recentering or flip
in `Update`), re-derived directly from the real source rather than
guessed. This test is still worth running since the fix hasn't been
confirmed live yet — it's just no longer a "pick a sign, any sign" check.

1. Note a landmark you're near in-game that you can also roughly place on
   the window's background art (a coastline, a lake, a distinctly-shaped
   zone border).
2. Compare where the live-widget patch (which tracks `self.PlyrX`/
   `self.PlyrY`) sits over the background art to where you actually are
   relative to that landmark.
3. Walk a good distance in a single compass direction (e.g. due north for
   30-60 seconds) and watch which way the widget patch moves over the
   background art.

**Expected**: walking north should move the patch's position over the
background art northward (up, toward the top of the zone's terrain image)
— not southward/mirrored. Likewise for east/west.

**If the dot still moves opposite to your actual movement on any axis**:
report it exactly that way (e.g. "walked north, dot moved down/south on
the terrain") with a screenshot — that would mean this flavor's world-Y
convention genuinely differs from retail's (unlikely given the source
trace, but only a live test can rule it out).

## Test 5 — standing still in a zone with no art hiccups

1. Just stand still in one zone for 15-20 seconds with the window open.

**Expected**: no flicker, no texture popping in and out, no repeated
"loading" gap in the terrain. The art should fetch once and stay stable.

**Debug panel field to watch**: `CurWorldUpdateMapId`/`tiles` should hold
steady (not reset/flicker) the whole time you're not changing zones.

## Known non-goals for this phase (don't report these as bugs)

- **Instances, dungeons, raids, battlegrounds**: `Cont` will read `nil` and
  no background art will draw. This is intentional — Carbonite's real
  instance-art system is a large, separate, explicitly-skipped subsystem
  (see `MinimapEngine.lua`'s Phase 8 header comment). Test in a normal
  outdoor zone.
- **Continent-wide zoomed-out view** (seeing the whole continent at once,
  multiple zones' art simultaneously): not built. Zooming out just shows
  more of the *current* zone's own art tiles, cropped at the zone's art
  boundary — it won't show the neighboring zone's terrain past that edge.
- **Fog-of-war / unexplored-area darkening**: not ported (explicit
  non-goal).
- **Zone name label overlay on the map**: not ported (explicit non-goal).
- **Garrison/Classic-era old-MapID special cases**: not applicable to WoW
  Forever, not ported.

## What to report back

Pass/fail per test, with a screenshot (debug panel visible) for anything
that looks wrong — especially Test 1's `Cont=nil`-in-a-normal-zone case
and Test 4's dot-direction check, since those are the two places this
phase's new, non-ported glue code (`FindContinent`/`RefreshCurrentZone`,
and the `PlyrY` sign) could realistically be wrong. Also note which exact
zone(s) you tested in, so a reported bug can be reproduced against the
same real data rows.
