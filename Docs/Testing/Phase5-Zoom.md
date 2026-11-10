# Phase 5 — Zoom: test plan

Covers: mouse-wheel zoom (cursor-centered), the window's own "+"/"-" buttons,
and the stale-terrain-render fix. Also covers a cross-cutting fix made
while chasing this phase's bugs: the engine now ticks on a real per-frame
`OnUpdate` script (throttled to 0.05s, matching Carbonite's own cadence)
instead of a 0.1s `AceTimer`, which should make all motion in this window
(zoom, and the drag/resize covered in Phase 6/7) noticeably smoother than
earlier screenshots showed.

## Setup

1. `/reload` (a full client restart isn't required for this phase — no new
   files were added to the `.toc`).
2. `/gps showmap` (or your bound key, once Phase 9 adds it) to open the
   window.
3. Watch the always-on debug panel in the top-left corner of the screen
   (`AlchemyGPSMapDebug`) while testing — it has the fields referenced
   below.

## Test 1 — mouse wheel zooms in/out, centered on the cursor

1. Move the mouse to a spot inside the window that is **not** the exact
   center (e.g. near a corner).
2. Scroll the wheel up (zoom in) a few notches, pausing between each.
3. Scroll down (zoom out) back to roughly where you started.

**Expected**: the point under the cursor stays visually fixed while
everything around it grows/shrinks — i.e. zooming feels like it's zooming
*into where the mouse is*, not into the window's center. Motion should
look continuous/smooth tick-to-tick, not jumpy.

**Debug panel fields to watch**: `Scale`/`ScaleDraw` should both climb
smoothly in the same direction as your scroll (no reversals), and
`MapPosX`/`MapPosY` should shift together with `Scale` while you're
actively scrolling off-center.

## Test 2 — the window's own +/- buttons

1. Click the **"+"** button (bottom-right of the window) 3-4 times, a
   second or two apart.
2. Click **"-"** the same number of times.

**Expected**: same smooth growth/shrink behavior as the wheel (centered on
the window, since there's no cursor-position concept for a button click).
`Scale` should return close to its starting value after an equal number of
+/- clicks (not exact, due to the asymmetric zoom-out damping Carbonite
itself uses — small drift is correct, not a bug).

## Test 3 — no stale/crescent terrain (the step-5 bug we fixed)

This is the specific bug chased across several screenshot rounds: the
mask/ring would resize correctly but the terrain *inside* it stayed
rendered at the old size, looking like a crescent or like the terrain
wasn't filling the ring.

1. Zoom in several steps with the wheel or buttons, then stop and let the
   animation settle (watch `StepTime` in the debug panel — wait until it
   reads `0`).
2. Take a screenshot. Confirm the terrain fills the ring edge-to-edge with
   no dark crescent/gap and no visible seam where old/new content meet.
3. Zoom in a few *more* steps from there (continuing past the first
   settle point) and repeat the check.

**Expected**: filled, centered terrain at every step, including the
*second* round of zooming (this is the part that was broken before: it
only failed once an animation had already settled once).

**Debug panel field to watch**: `MMScale(lastKick)` should update to
match `ScaleDraw` every time `ScaleDraw` changes meaningfully — if you see
`ScaleDraw` moving but `MMScale(lastKick)` stuck on an old value for more
than a tick or two, the fix regressed.

## What to report back

For each test: pass/fail, plus a screenshot if anything looks off (ideally
with the debug panel visible in frame, same as earlier rounds). Call out
specifically whether the "not smooth" feeling from the earlier screenshot
series is gone now that the engine ticks every frame instead of every
0.1s.
