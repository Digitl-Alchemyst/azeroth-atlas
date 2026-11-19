# Phase 9 — Icons, dock, sliders, filter menu: test plan

Everything built after Phase 8 that never had a test doc at all. Full
history in `CHANGELOG.md` — this doc is the checklist only.

## Still needs confirming

Roughly in priority order — top items are things that may not render at
all; bottom items are tuning/feel questions on things known to render.

- [ ] **NOT YET LIVE-TESTED, HIGH CAUTION** — Native resource-node
      blips via a revived live-widget patch, 2026-11-11 (build-order
      step 17, `CHANGELOG.md`). A scoped-down revival of this addon's
      own previously-removed "Mode: Live" mechanism (real `Minimap`
      widget reparented so its native terrain+blip rendering becomes
      visible inside this window) - this time gated behind the
      player's gathering-tracking buff (Find Herbs/Find Minerals/Find
      Fish) instead of being on whenever the map window is open.
      **Test in this exact order, do not skip to step 2:**
      1. Toggle tracking on/off a few times with the map window open
         (buff bar, or the minimap's own Tracking dropdown), open/close
         the map window while tracking is active, and go in and out of
         combat while it's active. Watch specifically for the "AzerothAtlas
         has been blocked from an action only available to the Blizzard
         UI" popup reappearing - this exact mechanism was removed once
         before on suspicion of causing that popup (though removing it
         didn't actually fix it at the time). If it reappears, STOP,
         click "Ignore" not "Disable", and report exactly what sequence
         reproduced it (this addon's own bug, not a fresh guess needed).
      2. Only if step 1 is clean: with tracking active and standing
         near a node you can see is active, confirm native resource
         blips actually show up inside the patch on the custom map
         window, confirm the patch's position/size tracks correctly as
         you move and as the window is panned/zoomed, and confirm your
         on-screen native minimap (if you don't have "Hide Blizzard
         minimap" on) goes back to normal once tracking turns off.
- [ ] **NOT YET LIVE-TESTED** — Radar sweep overlay on the live-blip
      patch, 2026-11-11 (build-order step 17, `CHANGELOG.md`). A very
      light green tint plus a sweeping line with a fading trail
      (14 discrete segments, not a true gradient), on top of the live
      widget whenever it's shown. Confirm: the tint/sweep actually
      appears and looks intentional (not like a bug), the sweep line's
      pivot stays centered as the patch resizes with zoom, it hides
      cleanly when tracking turns off or the map window closes, and it
      doesn't get caught and hidden by the passenger-hiding pass (it
      shouldn't - it's parented to `UIParent`, not `mm` - but this is
      exactly the kind of thing worth a second look given how many
      follow-ups this general area has already needed).
- [x] **CONCLUDED - confirmed dead end, 2026-11-11.** "Is this
      gathering node actually active right now" - user cited FarmHud as
      an example; its source was read and it does no independent
      detection of its own (see `CHANGELOG.md`'s build-order step 16).
      Live-tested from three independent angles, all empty:
      `C_VignetteInfo.GetVignettes()` (earlier research) returned 0;
      `/aatlas scanblips` found 0 Texture regions on the real Minimap;
      `/aatlas diffblips`, run as a controlled test with every other addon
      disabled, standing directly on a confirmed-visible node, found 0
      added/0 removed (only 4 total Minimap children exist at all with
      nothing else enabled - pure zoom/tracking button chrome). An
      earlier non-zero diffblips result (16-19 "added" frames) turned
      out to be a Questie/Platynator movement trail, not a node signal
      - all same size/texture, offsets tracing a line to the player's
      own position, captured while the player was mid-movement.
      **Conclusion**: this client renders resource-node blips as part
      of the native minimap's own internal compositing, unreachable to
      addon Lua code - not a scanning failure, a real architectural
      limit. Do not re-attempt a Minimap-scanning approach to this in a
      future session. A different, adjacent feature (detecting "was
      this specific node just harvested" via a gather event, then
      dimming it for an estimated respawn window) was offered and the
      user declined it - keeping the existing proximity-dimming
      approximation as-is. Closed, not paused.
- [ ] **NOT YET LIVE-TESTED** — Duplicate gathering-node dedup,
      2026-11-11. User reported some nodes rendering twice -
      `MinimapEngine.lua`'s `CollectGatherZoneNodes` now collapses any
      two same-species nodes within 7 yards of each other down to one
      (the static data is a port of Carbonite's own crowd-sourced
      Wowhead spawn dump, which occasionally has two slightly-offset
      entries for what's physically one node). Check: previously-
      doubled nodes now show as a single icon; un-doubled/normal nodes
      are unaffected; nothing that used to render is now missing
      entirely (if two icons more than ~7 yards apart both vanish, or
      more than one of three+ clustered icons survives oddly, report
      the species/zone so the 7-yard threshold can be adjusted).
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
- [ ] **NEEDS DIAGNOSIS** — "AzerothAtlas has been blocked from an action
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

- [ ] **NOT YET LIVE-TESTED** — Mailbox icon switched, 2026-11-11, from
      the flat `Interface\Icons\INV_Letter_15` item icon (user reported
      it rendered as "a black box and background with a border" - a
      real property of raw Blizzard inventory art, which has no alpha
      transparency at all) to `Interface\Minimap\TRACKING\Mailbox`, the
      same confirmed-working tracking-pin family Innkeeper/Banker
      already use. Check: mailbox pins now look like a proper
      free-floating pin icon, not a solid square with a dark
      background - if it's STILL boxy/wrong, something about this
      specific icon name in the TRACKING family may differ from
      Innkeeper/Banker, report exactly what it looks like.
- [ ] **NOT YET LIVE-TESTED** — Auctioneer icons, 2026-11-11, brand new
      (there was never a SERVICE_ICON_TEX/GuideData entry for this kind
      before - user noticed they were missing from the map entirely).
      Ported from `Carbonite/Data/camelot/Guides/Auctioneer.lua`
      (`Map/Data/GuideAuctioneer.lua`), same shape/texture family as
      Banker. Toggle via the Filter menu's new "Auctioneers" row.
      Check: icons appear at real auction-house locations in a few
      different zones, icon isn't blank/boxy, hover tooltip says
      "Auctioneer", toggling the filter row instantly hides/shows them.

## Confirmed (icon rendering only — exact tuning above may still be off)

- [x] **2026-11-10** — Mailbox/Innkeeper icons render, correct per-faction
      filtering (`ServiceIconFactionOk`) — position/filtering only;
      Mailbox's own ICON ART was wrong until the 2026-11-11 fix above,
      see that entry.
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
