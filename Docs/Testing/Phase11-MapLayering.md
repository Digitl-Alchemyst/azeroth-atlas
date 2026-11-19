# Phase 11 — Map layering fix: test plan

Build-order step 18, 2026-11-11. Full history in `CHANGELOG.md` — this
doc is the checklist only.

## Still needs confirming

Everything below is **NOT YET LIVE-TESTED** — deployed to the live
mirror and paren/brace-balance checked, but never opened in-game yet.

### Phase 1 — Terrain-above-Art stacking fix
- [ ] **Terrain Texture layer (close-zoom real minimap tiles) now
      consistently renders ABOVE the Art Map layer (continent/zone
      overview art)** everywhere both are visible — reproduce the three
      original reference screenshots' zoom/pan positions and confirm
      the stacking looks the same every time, not different per
      zoom/pan like before.
- [ ] **No hand-off glitch crossing the DETAIL_SCALE threshold**
      (~scale 4) — zoom slowly in and out through it a few times.
- Fail condition: either layer still visibly swaps which one wins at
  the *same* zoom/pan on repeated tries — if this happens even with
  the new explicit level offsets, report the exact zoom/pan, since it
  would mean a second bug beyond the original shared-level collision.

### Phase 1b — title-bar checkboxes + chrome-level regression (new)
- [ ] The two new title-bar checkboxes (left of the Filter button) show
      up, with tooltips "Terrain Texture layer" / "Art Map layer", and
      toggling either immediately shows/hides that layer live.
- [ ] Clicking a checkbox and then running the matching slash command
      (`/aatlas hideart` / `/aatlas hideterrain`) keeps the checkbox and the
      slash command in sync with each other either direction.
- [ ] **Zoom +/- buttons, the Settings gear, Auto-follow checkbox, and
      Filter button are all visible and clickable again** at every
      zoom/pan level — this was a real live regression (reported:
      "zoom in zoom out buttons are gone") from Phase 1's level change
      colliding with this row's own old `+1` offset, now fixed via
      `CHROME_LEVEL_OFFSET = 50`. Re-check this specifically, not just
      the two new checkboxes.

### Phase 2 — Terrain layer isolation
- [ ] `/aatlas hideterrain` (or the title-bar Terrain checkbox) cleanly
      hides only the Terrain layer (Art Map and all icons unaffected);
      toggling again restores Terrain.
- [ ] With Terrain isolated (both toggled off), the earlier
      screenshots' dark-wedge/missing-tile artifact — is it present
      with Terrain alone? Note the exact zoom scale and pan position if
      so (not fixed yet, this phase only characterizes it).

### Phase 3 — Art Map layer isolation
- [ ] `/aatlas hideart` (or the title-bar Art Map checkbox) cleanly hides
      only the Art Map layer (Terrain and icons unaffected); toggling
      again restores it.
- [ ] With Art isolated, pan/zoom across the DETAIL_SCALE threshold —
      confirm Art's own tile grid has no gaps or misaligned tiles of
      its own (e.g. the black wedge visible in the fully-zoomed-out
      reference screenshot).
- [ ] Turn both debug toggles back off (`/aatlas hideart` / `/aatlas
      hideterrain` again if still on) and re-confirm Phase 1's stacking
      once more with both layers back on.

### Phase 4 — Icon layer regression check (should be unchanged)
- [ ] Service icons (mailbox/banker/auctioneer/etc.), quest turn-in
      icons, gather-node icons, and the player marker still render
      above both Art and Terrain at every zoom/pan tested above, with
      no change in appearance, click, or hover behavior from before
      this fix.
- [ ] Goto and corpse-recovery ant-trail arrows/dots still render
      correctly above Art/Terrain.

### Phase 5 — Gathering radar layer regression check (should be unchanged)
- [ ] With gathering tracking active (Find Herbs/Minerals/Fish) and the
      map window open, the live Blizzard widget patch and its radar
      sweep still reparent/position/strata-sync correctly across the
      same zoom/pan range.
- [ ] Player/gather/service/quest icons still raise above the live
      patch while it's shown, and drop back to normal when tracking
      ends.
- [ ] **Observe only, don't worry about fixing it here:** if a goto or
      corpse trail happens to be active at the same time as the live
      radar patch, note whether it renders underneath the sweep (a
      known, pre-existing gap — see CHANGELOG).

## What to report back

For each phase above: pass/fail, and for any fail, the exact zoom
scale + pan position (or in-game location) where it happened. Phase
6 (an intentional Terrain↔Art blend) is explicitly not part of this
doc — it's a separate follow-up once everything above is confirmed
solid.
