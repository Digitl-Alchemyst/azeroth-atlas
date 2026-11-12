# Phase 14 — Zone "revealed" overlay art: test plan

Build-order step 21, 2026-11-11. Full history in `CHANGELOG.md` — this
doc is the checklist only.

## Still needs confirming

Everything below is **NOT YET LIVE-TESTED** — deployed to the live
mirror and paren/brace-balance checked, but never opened in-game yet.

### Phase 1 — Current zone overlay art, full brightness
- [ ] Zoom/resize out past `DETAIL_SCALE` on a zone with `Overlay`
      data populated (e.g. Hillsbrad Foothills, Elwynn Forest,
      Durotar) and confirm that zone's own named sub-regions
      (Tarren Mill, Southshore, etc.) appear at full brightness,
      correctly positioned on top of the Art Map backdrop (zone-level
      or continent-level, whichever build-order step 20 is showing).
- [ ] Zoom back in and confirm the overlay art hides cleanly.

### Phase 2 — ALL zones on the continent show, not just visited ones (updated 2026-11-11, fourth follow-up)
- [ ] **Superseded**: this phase originally tested the
      recently-visited FIFO (`self.MapsDrawnOrder`/`AddOldMap`) -
      removed entirely same day, in favor of always drawing every zone
      on the current continent. Confirmed working for the current zone
      alone (screenshot `WoWScrnShot_111126_221032.jpg`); next test is
      whether OTHER, never-visited zones on the same continent also
      render their own revealed art (dimmer, `.8`) simultaneously,
      stitched together on the continent backdrop - the actual original
      ask ("all revealed liek carbonit does... now stitch and show all
      zones like that").
- [ ] Zoom out to continent level and confirm every zone belonging to
      that continent shows its own overlay art at once, not just the
      current zone and not just previously-visited ones.
- [ ] Cross to the other continent (Kalimdor <-> Eastern Kingdoms) and
      confirm the full new set of zones appears, with no stale frames
      left over from the old continent (`HideExtraOverlayFrames`).

### Phase 3 — No per-region dimming (updated after first live test)
- [ ] First live test (2026-11-11) showed every region permanently
      dimmed/"undiscovered" regardless of actual exploration -
      `SHOW_UNEXPLORED` flipped to `true` to disable that lookup
      entirely (see CHANGELOG's same-day follow-up). Confirm every
      region - current zone and recently-visited ones alike - now
      renders at its full requested brightness (1 / .8) with no dim
      regions anywhere, matching "all revealed."
- [ ] **Updated after real root cause found (2026-11-11, third
      follow-up)**: the actual bug was never the dimming logic at all
      - it was `ExplorationOverlays.lua` shipping the wrong, obsolete
      data file entirely (legacy named-region keys that never matched
      this server's real `<zone>_c60`-suffixed `Overlay` fields, so
      every zone's lookup silently failed). Confirmed via `/gps
      dbgoverlay` chat log, now fixed by porting the real
      `NxMapData.lua`-inlined dataset instead. This phase's original
      checklist item above still stands as the thing to confirm, now
      actually reachable in code.

### Phase 4 — Numeric-fileID regions (now the *only* convention — not an Eastern Plaguelands exception)
- [ ] Zoom out on Hillsbrad Foothills (the zone from the diagnostic
      log) and confirm its 12 regions — keyed by Blizzard fileIDs, same
      as every other zone in the corrected data — render correctly,
      positioned and sized right.
- [ ] Spot-check a second zone (e.g. Elwynn Forest or Durotar) for the
      same. Earlier testing notes assumed this numeric-fileID
      convention (`arTx`) was a one-zone exception limited to Eastern
      Plaguelands — the real, now-ported dataset uses it for every one
      of its ~44 zones, so this is the normal path, not an edge case.

### Phase 5 — Zone with no overlay data
- [ ] Zoom out on a zone NOT in the ~53 populated `.Overlay` entries
      and confirm it simply shows no overlay art (no error, no
      placeholder) — the continent/zone Art Map backdrop alone.

### Phase 6 — Continent-boundary crossing
- [ ] Cross from Kalimdor to Eastern Kingdoms (or back) while zoomed
      out and confirm no stale overlay frames from the old continent's
      zones linger on screen.

### Phase 7 — Regression: Terrain layer untouched
- [ ] Re-run Phase 12's spot-checks (full coverage at extreme
      zoom-out, Terrain Brightness slider still manual-only, no
      auto-fade) and confirm Terrain is pixel-for-pixel unaffected.
      This touches the same per-tick `Update()` function again - flag
      immediately if anything about Terrain looks different.
- [ ] Also confirm every icon layer (gather nodes, service icons,
      quest markers, goto/corpse trail+dot, player marker) still
      renders at the correct relative stacking order - their frame
      level offsets all shifted by +1 this step to make room for the
      new Overlay layer (gather backdrop/icon, service, quest,
      goto+corpse trail, goto/corpse dot, player marker), though their
      order RELATIVE TO EACH OTHER is unchanged.

### Phase 8 — Regression: existing toggles unchanged
- [ ] `/gps hideart` cleanly hides Art Map tiles/continent backdrop
      AND the overlay art together, restores correctly on toggle-back.
- [ ] `/gps hideterrain` and both title-bar checkboxes still behave as
      before.

### Phase 9 — Frame-rate sanity
- [ ] Worst case (3 recently-visited zones + current, each with many
      named regions, zoomed out) doesn't introduce a noticeable
      stutter.

## What to report back

For each phase above: pass/fail, and for any fail, the exact zoom
scale + window size + zone/continent + pan position where it happened.
