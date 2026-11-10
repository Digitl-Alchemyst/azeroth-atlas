# Phase 6 — Pan-drag: test plan

Covers: click-and-drag inside the window's content area to pan the view.
Ported from Carbonite's real `Nx.Map:OnMouseDown`/`OnMouseUp`/the
`Scrolling` block in `Nx.Map:OnUpdate` - not reimplemented by hand.

## Setup

1. `/reload`.
2. `/gps showmap` to open the window.
3. Keep the debug panel in view.

## Test 1 — basic drag pans the view

1. Left-click and hold anywhere inside the window's dark content area
   (not on the title bar - that drags the whole *window*, not the map
   inside it).
2. While holding, move the mouse in a small circle or back and forth.
3. Release.

**Expected**: the live-widget patch (and the ring mask around it) slides
opposite to your drag direction, same as dragging a map you're holding
from underneath - drag right, the view pans left (the world content
appears to move with your cursor, like grabbing and sliding a piece of
paper). Motion should track the cursor closely and smoothly, not lag or
stutter.

**Debug panel field to watch**: `Scrolling` should read `true` for the
whole duration you're holding the button down, and flip back to `false`
immediately on release. `MapPosX`/`MapPosY` should change continuously
while `Scrolling=true`.

## Test 2 — drag doesn't fight an in-flight zoom

1. Click "+" to start a zoom animation.
2. *Immediately* (while `StepTime` in the debug panel is still non-zero)
   start a drag.

**Expected**: the drag takes over cleanly - no visible snap-back or fight
between the zoom animation and the drag. `Scale`/`ScaleDraw` should stop
changing on their own the moment you start dragging (the drag freezes
them at whatever they'd reached) and only your drag moves the view from
that point on.

## Test 3 — releasing outside the window doesn't get stuck

1. Start a drag inside the window.
2. While holding, move the cursor completely outside the window's bounds
   (e.g. off the edge of the screen or over the native UI elsewhere),
   then release the mouse button there.
3. Move the mouse back over the window without clicking.

**Expected**: the view stops panning the moment you released, even though
the release happened outside the window. `Scrolling` in the debug panel
should read `false` once you've released, and moving the mouse afterward
(with no button held) should not move the view.

## Test 4 — close/reopen while a drag was active doesn't carry over

1. Start a drag, and *while still holding the left button down*, click
   the window's close (X) button... if that's not physically possible
   with one hand, instead: start a drag, release, then immediately close
   and reopen the window (`/gps showmap` again) and try a fresh drag.

**Expected**: the reopened window's drag behaves normally from a clean
state - no "stuck scrolling" or a view that drifts on its own without
you touching anything.

## What to report back

Pass/fail for each test, with a note on *feel* (does it track the cursor
tightly, or does it feel laggy/rubber-bandy) since that's the main thing
the per-frame `OnUpdate` fix (see Phase 5's doc) was meant to improve.
