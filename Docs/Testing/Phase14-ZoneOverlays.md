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
      every zone's lookup silently failed). Confirmed via `/aatlas
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
- [ ] `/aatlas hideart` cleanly hides Art Map tiles/continent backdrop
      AND the overlay art together, restores correctly on toggle-back.
- [ ] `/aatlas hideterrain` and both title-bar checkboxes still behave as
      before.

### Phase 9 — Frame-rate sanity
- [ ] Worst case (3 recently-visited zones + current, each with many
      named regions, zoomed out) doesn't introduce a noticeable
      stutter.

### Phase 10 — "Art Map redefined": Overlay now occupies the Art Map slot (added 2026-11-11, sixth follow-up)
- [ ] Zoom out to single-zone view (not continent) and confirm the
      current zone's own revealed overlay art still renders correctly
      - it now shares Art Map's own frame level instead of its
      previous separate one, with the old flat zone-tile backdrop that
      used to live there removed entirely.
- [ ] Toggle the Art Map title-bar checkbox (or `/aatlas hideart`) off and
      on - confirm Overlay (not a flat backdrop) is what shows/hides.
- [x] **Resolved structurally, 2026-11-11 (seventh follow-up)**: at
      continent zoom, confirm Overlay's "revealed" zone art renders ON
      TOP of Base's flat backdrop, not hidden behind it. This WAS the
      one risk flagged in this phase's own previous version (Base and
      Overlay sharing one frame level) - confirmed live-broken exactly
      as flagged (Hillsbrad's Durnholde Keep region rendering behind
      Base, screenshots `WoWScrnShot_111126_231058/102/110/112.jpg`).
      Base and Art Map/Overlay now sit on separate, guaranteed-distinct
      frame levels (`CHANGELOG.md`'s "full 5-layer rework" entry), which
      structurally fixes this rather than relying on creation-order
      luck - still worth one pass confirming no flat/wrong-colored
      patches anywhere on a zoomed-out continent view, including
      Hillsbrad specifically.

### Phase 11 — 5-layer rework: Service Layer collapse + Radar Layer reversal (added 2026-11-11, seventh follow-up)
- [ ] With a full set of icons visible at once (quest markers, service
      icons, gather nodes, goto or corpse trail+dot, player marker),
      confirm every type still renders correctly - they now all share
      one frame level (Service Layer) instead of each having its own,
      so order between DIFFERENT icon types at the exact same pixel is
      no longer guaranteed. Not expected to be visually obvious in
      normal play (icon types rarely occupy the identical pixel), but
      worth a specific look if several icons cluster at one spot.
- [ ] Confirm each gather node's black backdrop still renders correctly
      BEHIND its own icon (not covering it) - this pairing's own
      internal ordering is unchanged, just double-check it since
      Service Layer's overall level moved.
- [ ] Start tracking a gathering skill (e.g. Find Herbs) near some
      native minimap blips and confirm the green radar sweep (Radar
      Layer) now renders ON TOP of this addon's own Service Layer icons
      (player dot, quest markers, etc.), not hidden beneath them. This
      is a deliberate reversal of build-order step 17's fix - the
      opposite of what step 17 fixed is now the INTENDED behavior, not
      a regression.
- [ ] With the radar sweep active (same gathering-skill state as
      above), confirm the title-bar row - zoom in/out, settings, follow,
      filter, Terrain/Art Map/Base checkboxes - all stay fully visible
      and clickable. This is the specific regression the chrome-strata
      fix in the same follow-up exists to prevent; if any chrome control
      visibly disappears or stops responding to clicks while the sweep
      is active, report that exactly along with which control(s).

## What to report back

For each phase above: pass/fail, and for any fail, the exact zoom
scale + window size + zone/continent + pan position where it happened.
