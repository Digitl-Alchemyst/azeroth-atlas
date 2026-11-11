# Phase 9 — Icons, dock, sliders, filter menu: test plan

Everything built after Phase 8 that never had a test doc at all. Full
history in `CHANGELOG.md` — this doc is the checklist only.

## Still needs confirming

Roughly in priority order — top items are things that may not render at
all; bottom items are tuning/feel questions on things known to render.

- [ ] **UNCONFIRMED GUESS, may render nothing** — Guard Directions flag
      (`C_GossipInfo` API; ask a guard for directions, watch for a flag
      icon). Not just untested — the API itself isn't confirmed to return
      data on this server build.
- [ ] **UNCONFIRMED GUESS, icon may be blank** — Dungeon/Raid Entrance
      icons (`Interface\Icons\INV_Misc_Key_03`)
- [ ] **UNCONFIRMED GUESS, icon may be blank** — Zone Transition icons
      (`Interface\Icons\INV_Misc_Map_01`)
- [ ] **UNCONFIRMED GUESS, icon may be blank** — Flight Master icon
      (`Interface\MINIMAP\TRACKING\FlightMaster`) — separately, whether
      `C_TaxiMap` returns any node at all for a given zone is itself
      unconfirmed on this server build
- [ ] **NOT YET LIVE-TESTED** — Banker icons/positions (high confidence —
      same data shape and icon family as the already-working Innkeeper —
      but never actually looked at in-game)
- [ ] **NOT YET LIVE-TESTED** — Filter button + menu (opens/closes,
      checkboxes persist across `/reload`, each toggle instantly
      hides/shows its category)
- [ ] **NOT YET LIVE-TESTED** — Zoom button restyle (visual only — does it
      look right, does it still work)
- [ ] **TUNING NOT RE-CONFIRMED** — gathering-icon opacity/size/backdrop
      sliders. The original "100% still barely visible" bug is fixed
      (dim-alpha ceiling raised 0.45→0.85), but the resulting look at the
      new default was never confirmed good — same for backdrop padding/
      corner-rounding/opacity.
- [ ] **NOT YET FORMALLY WALKED** — Auto-follow checkbox (root cause of
      the original "fights manual panning" bug is fixed, but no recorded
      pass since)

## Confirmed (icon rendering only — exact tuning above may still be off)

- [x] **2026-11-10** — Mailbox/Innkeeper icons render, correct per-faction
      filtering (`ServiceIconFactionOk`)
- [x] **2026-11-10** — Per-species gathering-node icons render with
      correct species texture; hover tooltip shows name + skill-colored
      level
- [x] **2026-11-10** — Detail-tile zoom layer (close-zoom real client art)
      appears at the right position and continent
- [x] **2026-11-10** — Minimap icon dock collects real addon/Blizzard
      buttons without stray/duplicate entries
- [x] **2026-11-10** — Native mail button forwards into the dock with a
      working icon and click-through
- [x] **2026-11-10** — Right-click menu's taint-popup bug fixed
      (`:IsMouseOver()` switch)

## What to report back

For each "still needs confirming" item: does it render at all, does it
look right, and (for Guard Directions specifically) does asking a guard
for directions produce anything on the map whatsoever. Screenshots for
anything blank or wrong, with the zone/NPC used.
