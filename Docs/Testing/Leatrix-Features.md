# Alchemy GPS — Leatrix Features Test Plan

Nov 18, 2026 · @Digital Alchemyst

## Before you start

This plan covers the Leatrix Maps features added on Nov 18 (the ✅ rows in `Docs/Compare-Leatrix.md`), plus the earlier Leatrix ports that `BigMapPhaseTestPlan.md` doesn't cover. That plan already covers the Leatrix-style big map, its 15 themes, the coordinates and zone-level label, and the faction flight master icons, so they aren't repeated here.

- **Restart the game fully once** before testing. After that, `/reload` is enough between fixes.
- **Show Lua errors**: type `/console scriptErrors 1`, or use BugSack. Any red error box counts as a fail for the step you were on.
- **You'll need**: a character who can reach a capital city (Stormwind or Orgrimmar), a harbour with a boat or zeppelin, and a zone with a dungeon entrance. Ideally also Blackrock Mountain (Searing Gorge / Burning Steppes).
- **Recording results**: set each step's Result to Pass, Fail or Not tested. For a fail, add a comment saying what you saw, with a screenshot if you can.
- **"Big map"** means the map window maximised with M (or dragged wide). Clicking icons to open maps works on the big map only. The small map always follows you.

## 1. Portal icons (Leatrix 1.1)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.1 | Open the map's Filters menu | A **Portals** row is there, ticked. |  |
| 1.2 | Look at a city or zone with a portal, such as the Dark Portal area or a capital's portal room | Portals have their own icon, not the boat or zone-exit icon. |  |
| 1.3 | Hover a portal icon | The tooltip names the portal and where it goes. |  |
| 1.4 | Untick **Portals** | Portal icons disappear and nothing else does. Tick it again and they come back. |  |

## 2. Tram icons (Leatrix 1.2)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.1 | Open Stormwind or Ironforge | The Deeprun Tram station has a tram icon. |  |
| 2.2 | View Eastern Kingdoms (continent view) | The tram icons show with the boats and zeppelins. |  |
| 2.3 | Untick **Trams** in Filters | The tram icons disappear. Tick it again and they come back. |  |

## 3. Boats and zeppelins told apart

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 3.1 | Look at a zeppelin tower (Grom'gol, Orgrimmar, Undercity) | It shows the **zeppelin** icon, not the boat icon. |  |
| 3.2 | Look at a dock (Booty Bay, Menethil Harbor, Ratchet) | It shows the **boat** icon. |  |
| 3.3 | Untick **Boats**, then **Zeppelins** | Each filter hides only its own kind. |  |

## 4. The other faction's travel (Leatrix 1.3)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 4.1 | Open Filters | **Other faction's travel** is there and **off** to start with. |  |
| 4.2 | With it off, look at a port the other faction uses (an Alliance character at a Horde zeppelin tower, or the other way round) | The other faction's boats, zeppelins, portals and trams don't show. Neutral ones (Booty Bay–Ratchet) do. |  |
| 4.3 | Tick **Other faction's travel** | The other faction's boats, zeppelins, portals and trams appear. Their tooltip has a red "Alliance only" or "Horde only" line. |  |
| 4.4 | Check flight masters with it ticked | Flight masters stay your own faction and neutral only. This switch is for travel icons. |  |
| 4.5 | `/reload` | The setting is kept. |  |

## 5. Click a travel icon to open where it goes (Leatrix 1.4)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 5.1 | Big map: hover a zone-exit arrow | The tooltip has a line "Click to open (zone name)". |  |
| 5.2 | Click it | The map opens the zone it leads to. My Map turns bronze (you're browsing). |  |
| 5.3 | Do the same with a boat, a zeppelin, a portal and a tram | Each opens the map at the other end of the trip. |  |
| 5.4 | Click **My Map** | You're back on your own map. |  |
| 5.5 | Small map: click a travel icon | Nothing changes. The small map keeps following you, and the tooltip has no "Click to open" line. |  |
| 5.6 | Big map: click an icon whose destination is the map already on show | Nothing happens and there's no error. |  |

## 6. Click a dungeon entrance to open its map (Leatrix 1.5)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 6.1 | Big map: hover a dungeon entrance (e.g. The Deadmines in Westfall) | The tooltip has a line "Click to open its map". |  |
| 6.2 | Click it | The dungeon's floor map opens, with the floor bar. |  |
| 6.3 | Go to Blackrock Mountain on the big map (Searing Gorge / Burning Steppes border) | **One** entrance icon stands for all the dungeons inside it. Its tooltip names them and says "Click to pick a map". |  |
| 6.4 | Click that icon | A small list pops up (Blackrock Depths, Lower / Upper Blackrock Spire, Molten Core, Blackwing Lair). Picking one opens its map. |  |
| 6.5 | Try Ahn'Qiraj in Silithus | The same: one icon, a list of both raids. |  |
| 6.6 | Open the pop-up list near the bottom of the screen | It opens **upward** so it doesn't run off the screen. |  |
| 6.7 | Hover and click an entrance whose dungeon has no map | Its tooltip has no "Click to…" line, and clicking does nothing. No errors. |  |

## 7. Unexplored areas (partly Leatrix 1.7 / 1.8)

Leatrix has a show/hide switch and a tint colour for unexplored areas. We now have a brightness slider for them, without a tint colour.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 7.1 | Go to a zone you haven't fully explored. Right-click the map | The menu has an **Unexplored areas** slider under Map layers, at 35%. |  |
| 7.2 | Drag it to 0% | Unexplored parts go black. |  |
| 7.3 | Drag it to 100% | Unexplored parts look the same as explored ones (revealed). |  |
| 7.4 | Settings > Map > Brightness and opacity | The same slider is there, with the same value. |  |
| 7.5 | `/reload` | The value is kept. |  |

## 8. Dungeon maps with Leatrix pins (ported Nov 16–17)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 8.1 | Open a classic dungeon's map (Dungeons v > Razorfen Downs, The Deadmines…) | The entrance shows Leatrix's dungeon pin, and level-change spots show the upgrade-arrow icon. |  |
| 8.2 | Look at the bosses | Each boss shows its **portrait**, not a skull. |  |
| 8.3 | Have a quest that needs a boss (e.g. Amnennar the Coldbringer in Razorfen Downs) | That boss's pin is gold and larger. |  |
| 8.4 | Click a level arrow | The map moves to that level. |  |
| 8.5 | Look for quest NPCs inside (Belnistrasz in Razorfen Downs) | Their pickup / turn-in pin shows inside the dungeon. |  |
| 8.6 | Open a WoW Forever dungeon | It falls back to the Forever Dungeon Journal's pins, with no errors. |  |

## 9. Zone-exit arrows point the right way (ported Nov 17)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 9.1 | Look at the zone-exit arrows around Elwynn Forest | Each arrow points **out of the zone** toward where it leads (Westfall west, Redridge east, Stormwind north…). |  |
| 9.2 | Check a few more zones, including a WoW Forever one | The arrows point sensibly. Note any that point the wrong way, with the zone and roughly where. |  |

## 10. Risks and regression checks

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 10.1 | Press Alt+M (Blizzard's map) | It opens and works as before. Other addons' icons still show on it. |  |
| 10.2 | Toggle every travel filter off and back on | No icons are left stuck on the map, and there are no errors. |  |
| 10.3 | Switch between continent, zone and dungeon views a few times, clicking travel icons on the way | No errors, and My Map always brings you home. |  |
