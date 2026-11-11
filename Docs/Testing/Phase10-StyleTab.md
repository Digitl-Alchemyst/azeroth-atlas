# Phase 10 — Style settings tab: test plan

Build-order steps 13 and 14, 2026-11-11. Full history in
`CHANGELOG.md` — this doc is the checklist only.

## Still needs confirming

Everything below is **NOT YET LIVE-TESTED** — deployed to the live
mirror and brace-balance checked, but never opened in-game yet.

- [ ] **Settings window opens at the new size** (`/gps settings`,
      380x440, was 270x180) with a "General"/"Style" tab strip at the
      top. Clicking each tab swaps the body without moving/resizing
      the window.
- [ ] **General tab** still has all three original checkboxes ("Hide
      Blizzard minimap", "Debug mode", "Icon bar: vertical column")
      plus the "Show Minimap" button, and they still work exactly as
      before (this tab's content/logic is unchanged, only moved into
      its own panel).
- [ ] **Style tab renders nine rows**: Window Skin (12 swatches,
      wrapping to 2 lines), Trail Arrow (6), Goto Marker (6), Quest
      Turn-In Icon (4), Dungeon Entrance Icon (4), Zone Transition Icon
      (7), Flight Master Icon (4), Spirit Healer Icon (2), Player
      Marker (5). The list should scroll if anything is cut off at the
      bottom - it's considerably taller now than step 13 alone.
- [ ] **Window Skin swatches show real color previews** (not blank
      squares) and clicking one re-skins the Settings window's own
      backdrop/border AND the minimap window live, with no `/reload`
      needed. Check a few spread across the list, not just one -
      Blackout, Dialog Gold, Glass, Class Color (should tint the
      border to your own class color), Faction (Alliance = blue,
      Horde = red border).
- [ ] **Trail Arrow swatches show the real icon art** (not blank) and
      clicking one changes the ant-trail arrow on an active goto or
      corpse-recovery trail immediately, without needing to re-trigger
      the trail.
- [ ] **Goto Marker swatches** likewise show real icon art, and
      clicking one changes the "set goto here" dot's look immediately
      if a goto is currently active.
- [ ] **Quest Turn-In Icon swatches** show real icon art; clicking one
      changes already-visible quest-turnin pins within a few seconds
      (next throttled update, not instant - that's expected, see
      CHANGELOG).
- [ ] **Build-order step 14 - the five new rows' swatches all show
      real icon art, not blank squares**, including the ATLAS-based
      options (Dungeon/Raid, all three Taxi-Node variants, both
      Portal variants, Spirit Healer's green ball, the zone-exit
      arrow) and the TEXCOORD-CROPPED ones (Dungeon/Raid combined,
      both Boat variants, Travel) - these two kinds were never
      exercised by step 13 at all, so this is the real first test of
      `ApplyIconSpec`'s atlas/texcoord branches, not just a repeat of
      the already-working plain-texture path.
- [ ] **Dungeon Entrance / Zone Transition / Flight Master / Spirit
      Healer**: picking a non-default option changes the live map
      icon within a few seconds at a zone/city that actually has one
      of each (a dungeon entrance, a zone-border crossing, a flight
      point, a spirit healer near a graveyard). Also worth explicitly
      re-checking whether the CURRENT DEFAULT for each of these four
      ever renders blank in-game, same as their own original build
      step asked - if so, the fix is just switching the Style tab to
      one of the new confirmed-working Leatrix alternatives, not more
      guessing.
- [ ] **Player Marker**: picking a Dot option replaces the rotating
      arrow with a static dot immediately (rotation still applies
      underneath - harmless on a symmetric dot, confirm it doesn't
      look visibly wrong). Switching back to Arrow restores rotation
      behavior.
- [ ] **Selected swatch per category is visibly highlighted** (gold
      border) and only one per category stays highlighted after a
      click - clicking a new one in the same row should un-highlight
      the previous one.
- [ ] **Persistence**: pick a non-default option in each of the nine
      categories, `/reload`, re-open Settings → Style tab. Every
      choice should still be selected (gold-highlighted) and the
      minimap/trails/icons/player marker should still reflect them
      without re-clicking anything.
- [ ] **Fresh-profile default look is unchanged**: on a character that
      has never opened the Style tab, the minimap window, trail arrow,
      goto dot, quest-turnin icon, dungeon/zone/flight/spirit-healer
      icons, and the player's own marker should all look EXACTLY as
      they did before build-order step 14 (every new category's
      default is the pre-existing hardcoded icon, byte-for-byte) —
      confirms the new system didn't silently change anyone's existing
      look.
