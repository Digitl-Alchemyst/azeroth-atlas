# Phase 13 — Art Map continent-level stitching: test plan

Build-order step 20, 2026-11-11. Full history in `CHANGELOG.md` — this
doc is the checklist only.

## Still needs confirming

Everything below is **NOT YET LIVE-TESTED** — deployed to the live
mirror and paren/brace-balance checked, but never opened in-game yet.

### Phase 1 — Normal zone view (baseline, should look unchanged)
- [ ] On Kalimdor, at a close/moderate zoom where the current zone's
      own art already fully covers the window, nothing looks different
      from before this change.
- [ ] Same check on Eastern Kingdoms.

### Phase 2 — Continent art fills in on Kalimdor
- [ ] Zoom out and/or enlarge the undocked window on a Kalimdor zone
      until the window needs to show more world-space than that one
      zone covers.
- [ ] Confirm the view switches to the CONTINENT's own art (all of
      Kalimdor's zones, pre-stitched into one image) instead of the
      old "one zone's art floating in blank space" — no visible seams,
      no stretching/misalignment between tiles.
- [ ] Zoom back in and confirm it switches back to the normal
      single-zone art cleanly.

### Phase 3 — Same check on Eastern Kingdoms
- [ ] Repeat Phase 2 on an Eastern Kingdoms zone.

### Phase 4 — Crossing a continent boundary while zoomed out
- [ ] While in continent view, travel/teleport from a Kalimdor zone to
      an Eastern Kingdoms zone (or vice versa) and confirm the
      continent art swaps cleanly to the new continent - no leftover
      tiles from the previous continent lingering underneath.

### Phase 5 — Zephras Isle fallback (no continent art available)
- [ ] On a Zephras Isle zone, zoom/resize out past that zone's own
      bounds and confirm it falls back to today's existing behavior
      (blank past the zone's edge) rather than erroring or showing a
      wrong/stale texture. This is an accepted, pre-existing gap for
      this one custom continent, not a regression to fix here.

### Phase 6 — Zone/continent hand-off
- [ ] Zoom slowly in and out right at the threshold where coverage
      need crosses the current zone's own extent, a few times in a
      row. Confirm no flicker, no stuck/duplicated tiles, no Lua error.

### Phase 7 — Regression: Terrain layer untouched
- [ ] Re-run Phase 12's spot-checks (full Kalimdor coverage at extreme
      zoom-out, Terrain Brightness slider still manual-only with no
      auto-fade) and confirm Terrain is pixel-for-pixel unaffected by
      this change at every zoom/pan tested above. This is the most
      important regression check in this doc - flag immediately if
      anything about Terrain looks different.

### Phase 8 — Regression: existing toggles unchanged
- [ ] `/gps hideart` cleanly hides BOTH zone-level and continent-level
      Art Map tiles, whichever is currently active, and restores
      correctly on toggle-back.
- [ ] `/gps hideterrain` and both title-bar checkboxes still behave as
      before.

## What to report back

For each phase above: pass/fail, and for any fail, the exact zoom
scale + window size + zone/continent + pan position where it happened.
