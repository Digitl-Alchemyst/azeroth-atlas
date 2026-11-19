# Phase 12 — Terrain layer dynamic coverage + fade: test plan

Build-order step 19, 2026-11-11. Full history in `CHANGELOG.md` — this
doc is the checklist only.

## Still needs confirming

Everything below is **NOT YET LIVE-TESTED** — deployed to the live
mirror and paren/brace-balance checked, but never opened in-game yet.

### Phase 1 — Small window / zoomed in (baseline, should look unchanged)
- [ ] At a small/default undocked window size and a close zoom (the
      kind of zoom this addon always rendered correctly before), the
      Terrain layer still fully covers the window edge-to-edge at full
      alpha, same as before this change.
- [ ] No visible change in tile alignment, texture choice, or
      frame-level stacking versus Phase 11's own baseline.

### Phase 2 — Large window / zoomed out, but still within the cap
- [ ] Resize the undocked window larger and/or zoom out moderately
      (still comfortably under where the needed tile count would
      exceed 40 tiles across).
- [ ] Terrain now fully covers the window edge-to-edge at FULL alpha —
      confirm this is NEW/IMPROVED behavior versus before the fix
      (previously this exact case showed a visible gap at the fixed
      6x6 grid's edge).
- [ ] Resize the window larger while zoomed steady and confirm
      coverage keeps reaching the new edges live, with no pop-in/flash
      as the tile pool grows.

### Phase 3 — Zoomed out far enough to exceed the cap (no auto-fade)
- [ ] Zoom out (and/or enlarge the window) until the needed tile count
      exceeds the 40-tile cap — at default window size this requires a
      fairly extreme zoom-out, close to the addon's "world view" floor.
- [ ] Confirm Terrain does NOT auto-fade or auto-hide here — it should
      stay at full (or whatever the Terrain Brightness slider is set
      to) brightness right up to the capped grid's own edge. A hard
      edge/visible square at this extreme zoom is EXPECTED now (by
      design, per explicit user instruction) — this phase is only
      checking that no automatic dimming happens, not that the edge is
      gone.
- [ ] Zoom back in and confirm there's no leftover dimming/fade state
      from a previous tick (brightness should be instantly back to the
      slider's set value, not animate back up).

### Phase 3b — Terrain Brightness slider (new)
- [ ] Right-click the map, confirm a "Terrain Brightness" row appears
      below "Gathering Icon Backdrop Opacity," independent of the
      existing "Tile Map Brightness" row (Art Map layer).
- [ ] Dragging it live-updates the Terrain layer's brightness at any
      zoom, including fully zoomed out past the coverage cap.
- [ ] Set it to something other than 100%, `/reload`, and confirm the
      value persisted (menu reopens at the saved value, and Terrain
      renders at that brightness immediately without reopening the
      menu).

### Phase 4 — Live resize at large window / far zoom
- [ ] With the window at or beyond the Phase 3 cap, slowly drag-resize
      the undocked window larger/smaller and confirm the dynamic
      coverage radius keeps tracking smoothly (no stutter/flash,
      no unexpected dimming) as it grows/shrinks the tile grid.

### Phase 5 — Regression: existing toggles/layers unchanged
- [ ] `/aatlas hideart` / `/aatlas hideterrain` and the title-bar
      Terrain/Art checkboxes still isolate each layer correctly and
      stay in sync with each other, same as Phase 11's own checks.
- [ ] Icon layer, gathering radar/live widget, goto/corpse trails all
      unchanged in appearance and behavior.
- [ ] No frame-rate complaints at the most extreme zoomed-out/largest-
      window combination tested (watch specifically here — the
      40-tile/1600-frame ceiling is inherited from Carbonite's own
      shipped slider max, not independently profiled in this port
      yet).

## What to report back

For each phase above: pass/fail, and for any fail, the exact zoom
scale + window size + pan position where it happened.
