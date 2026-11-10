# Phase 7 — Resize correctness: test plan

Scope note first, since this phase's plan wording ("confirm the resize-grip
correctly drives `ZoomController:CenterMap` so the revealed area matches
the new window size") turned out to describe a feature that needs
Phase 8's real per-zone coordinate database (`Coords`/`mapID`) to exist at
all - `CenterMap` fits a *known zone's* bounds to the window, which we
can't do until there's a real zone to fit. Reading the actual chrome code
(`UI/Window.lua`, already ported in step 3) confirmed something simpler
and already true without any new code: `Window:Adjust()` already resizes
our content frame continuously during a live resize-drag (it's called
every tick the mouse is over the window, via the window's own `OnUpdate`),
and `MinimapEngine:Update()` already recomputes `MapW`/`MapH` from that
content frame's live size every tick. So "resize correctness" for this
phase means: confirm that already-live recomputation behaves correctly
with no extra glue code, not that a re-center-to-zone feature exists yet
(that lands in Phase 8/9 once there's a real zone to center on).

## Setup

1. `/reload`.
2. `/gps showmap` to open the window.
3. Keep the debug panel in view.

## Test 1 — smooth live resize, no lag

1. Grab any edge or corner of the window (cursor near the border - the
   real ported hit-test, `Window:IsOnWinUI`, is what decides this) and
   drag to make the window substantially bigger.
2. Drag it back down substantially smaller.
3. Try a corner drag (resizes both dimensions at once) as well as a pure
   edge drag (one dimension only).

**Expected**: the live-widget-blend patch and its ring mask track the
window's new size continuously *while dragging*, not just once you let
go. No visible lag, no "snaps to correct size a moment after release."

**Debug panel fields to watch**: `MapW`/`MapH` should track the window's
actual content size in real time as you drag.

## Test 2 — zoomType tier transitions cleanly across a resize

The engine picks the biggest of 6 preset sizes that fits the window
(`zoomType` 1-6, see `MMScales` in `MinimapEngine.lua`). Resizing across
one of those size thresholds forces a different preset.

1. Start with the window fairly small (so `zoomType` is low, e.g. 1-2 -
   check the debug panel).
2. Slowly drag a corner to grow the window past a few thresholds, pausing
   for a second at a few points along the way.

**Expected**: no stale/crescent terrain at any point you pause (same
check as Phase 5's Test 3, now triggered by a *size* change instead of a
*scale* change - this exercises the same `MMZoomType ~= zoomType or
MMScale ~= ScaleDraw` re-kick condition from a different angle, so it's
worth checking separately). `MMScale(lastKick)` should update to match
`ScaleDraw` every time `zoomType` changes.

## Test 3 — too small to show anything, and recovering

1. Shrink the window below the smallest preset (until the live widget
   disappears - `zoomType` should read `0` in the debug panel).
2. Grow it back past that threshold.

**Expected**: the widget cleanly hides when too small (no leftover
textures/artifacts) and cleanly reappears, correctly sized, once the
window is big enough again.

## Test 4 — resize doesn't disturb an independent pan/zoom

1. Pan the view somewhere off-center (Phase 6) and/or zoom in a few steps
   (Phase 5).
2. Resize the window (bigger or smaller).

**Expected**: the resize changes how much of the view you can see, but
doesn't itself snap `Scale`/`MapPosX`/`MapPosY` back to any default - your
pan/zoom position should persist through the resize. (A "recenter on
resize" feature is explicitly out of scope until Phase 8, per the note at
the top of this doc - don't report "it doesn't recenter" as a bug.)

## What to report back

Pass/fail per test, with a screenshot (debug panel visible) for anything
that looks like lag, a stale/crescent render, or a leftover artifact after
shrinking past the hide threshold.
