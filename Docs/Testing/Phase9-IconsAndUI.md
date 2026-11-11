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
- [ ] **NOT YET LIVE-TESTED** — Goto menu rows restyled, 2026-11-11 (moved
      "Set Goto Here"/"Clear Goto" to the top of the right-click menu as
      thin Carbonite-style highlight rows instead of full buttons — the
      underlying goto/ant-trail/arrival behavior itself is already
      confirmed working, see below, this is just the new row look/order).
- [ ] **UNCONFIRMED GUESS, may still be wrong - 3rd attempt** — Corpse
      recovery grave icon (die in a non-PvP area, go ghost, open the
      map): should show a proper tombstone sprite from Blizzard's own
      `Interface\Minimap\POIIcons`. Two prior attempts were both
      confirmed wrong live (2026-11-11): first a squished icon with
      the Arathi Basin Lumber Mill flag bleeding in underneath, then a
      captured-objective flag plus an uncaptured Lumber Mill icon.
      This 3rd attempt uses the texcoord straight from Blizzard's own
      live-client source (`CorpsePinTemplate`,
      `DeathMapDataProvider.xml`) rather than another addon's copy of
      it - the strongest source used so far, but this exact server's
      client build relative to that source is still unconfirmed. If
      it's STILL wrong, say exactly what icon/shape shows (same level
      of detail as both previous reports - that's what's let each one
      get diagnosed precisely).
      A `#yd` label above it (same live-updating label as the goto
      dot's) and a RED ant trail leading from you to it should also
      show, independent of (and simultaneous with, if you have one)
      any active goto trail/dot - these two parts are already expected
      to work correctly, only the icon itself was wrong. Should
      disappear on resurrecting. Also check: no grave/trail appears
      while inside a battleground.
- [ ] **NEEDS DIAGNOSIS** — "AlchemyGPS has been blocked from an action
      only available to the Blizzard UI" popup, reported live
      2026-11-11 while dead with the corpse-tracking feature active.
      Root cause not yet identified - exact error text/stack trace
      (e.g. from a bug-catching addon like BugSack) still needed to
      diagnose which call is tainted. Click "Ignore," not "Disable,"
      if it recurs, so the rest of the addon keeps working while this
      gets tracked down.
- [ ] **NOT YET LIVE-TESTED** — Spirit Healer icons, 2026-11-11 (new
      `Interface\Icons\Spell_Holy_Resurrection` icon, one per graveyard,
      89 locations ported from Leatrix_Maps' own data since neither
      Carbonite nor Blizzard has any). Toggle via the Filter menu's new
      "Spirit Healers" row. Check: icons appear in the right spot in a
      few different zones (not just one), icon isn't blank, toggling
      the filter row instantly hides/shows them.
- [ ] **NOT YET LIVE-TESTED** — Hover tooltips on every service icon,
      2026-11-11 (Mailbox/Innkeeper/Banker/DungeonEntrance/
      ZoneTransition/FlightMaster/GuardFlag/SpiritHealer - hover each
      and a tooltip should appear, same mechanism as gather nodes).
      Check per category: Mailbox/Innkeeper/Banker/SpiritHealer should
      say exactly that ("Mailbox"/"Innkeeper"/"Banker"/"Spirit
      Healer") - Innkeeper's tooltip briefly showed the current zone's
      name instead, but that was reverted same-day per explicit user
      request ("just call the innkeeper innkeeper... we will just have
      the name of the place be on the flight master"); DungeonEntrance
      should say the real
      dungeon/raid name (e.g. "Ragefire Chasm"); **ZoneTransition
      should say the DESTINATION zone's name** (e.g. "Mulgore,"
      "Undercity," "Duskwood") for a plain walk-through border, or the
      real boat/zeppelin/tram/portal destination where one exists
      (e.g. "Boat to Menethil Harbor") - no entry should ever show the
      old generic "Zone Transition" label anymore; FlightMaster should
      say the real flight point name (kept as location-only, not an
      individual NPC name - see CHANGELOG's QuestieDB/ZoneDB entry for
      why); GuardFlag's label is an unconfirmed-API guess (tries
      `info.name` then `info.description`) - if it ever shows and says
      something wrong/blank, report exactly what it says.

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
- [x] **2026-11-11** — Right-click goto waypoint + ant-trail: confirmed
      live — trail arrows point the correct way, arrival detection fires
      (chat message + sound) when reaching the goto

## What to report back

For each "still needs confirming" item: does it render at all, does it
look right, and (for Guard Directions specifically) does asking a guard
for directions produce anything on the map whatsoever. Screenshots for
anything blank or wrong, with the zone/NPC used.
