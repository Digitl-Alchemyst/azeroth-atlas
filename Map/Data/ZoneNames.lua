---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/Data/ZoneNames.lua
--
-- Build-order step 12, follow-up (2026-11-11): a small mapID->zone
-- name lookup, explicit user request - zone-transition icons should
-- say what zone they lead TO (e.g. "Mulgore", "Undercity", "Duskwood"
-- - confirmed via both Leatrix_Maps' own rendering, which shows the
-- destination zone's plain name with no "to" prefix for its "Arrow"
-- zone-crossing pins, and Carbonite's own real data, both cited
-- below), and innkeeper icons should say which zone they're in
-- (explicit follow-up: "give the location like how you are [doing it]
-- from the FP master" - FlightMaster's own tooltip is already just a
-- plain location name with no prefix, node.name from the live
-- C_TaxiMap API - this is the same treatment for Innkeeper, which has
-- no live per-point name of its own to read).
--
-- Source: Carbonite/Data/camelot/Zones.lua's real Nx.Zones table - a
-- full mapID->"name|minLvl|maxLvl|faction|cont|entryId|ex|ey" pipe
-- string keyed by every zone in the game, localized via AceLocale
-- (L["..."]). Only the NAME portion is needed here, and only for the
-- zones actually referenced by GuideZoneTransition.lua/
-- GuideInnkeeper.lua's own mapID keys (confirmed: ZoneTransition's 48
-- distinct mapIDs are a strict superset of Innkeeper's own 37) - a
-- small, targeted subset of Nx.Zones rather than the whole table,
-- same "don't expose the whole real module, just the rows this addon
-- actually needs" convention GuideDungeonEntrance.lua's own header
-- already established for Nx.Zones. Names inlined as plain strings
-- (no locale layer in this addon, same convention every other ported
-- Guide file already uses) - this server has no non-English Nx.Zones
-- localization installed to diverge from anyway.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local Map = AlchemyGPS.Map

Map.ZoneNames = {
    [1411] = "Durotar",
    [1412] = "Mulgore",
    [1413] = "Northern Barrens",
    [1416] = "Alterac Mountains",
    [1417] = "Arathi Highlands",
    [1418] = "Badlands",
    [1419] = "Blasted Lands",
    [1420] = "Tirisfal Glades",
    [1421] = "Silverpine Forest",
    [1422] = "Western Plaguelands",
    [1423] = "Eastern Plaguelands",
    [1424] = "Hillsbrad Foothills",
    [1425] = "The Hinterlands",
    [1426] = "Dun Morogh",
    [1427] = "Searing Gorge",
    [1428] = "Burning Steppes",
    [1429] = "Elwynn Forest",
    [1430] = "Deadwind Pass",
    [1431] = "Duskwood",
    [1432] = "Loch Modan",
    [1433] = "Redridge Mountains",
    [1434] = "Stranglethorn Vale",
    [1435] = "Swamp of Sorrows",
    [1436] = "Westfall",
    [1437] = "Wetlands",
    [1438] = "Teldrassil",
    [1439] = "Darkshore",
    [1440] = "Ashenvale",
    [1441] = "Thousand Needles",
    [1442] = "Stonetalon Mountains",
    [1443] = "Desolace",
    [1444] = "Feralas",
    [1445] = "Dustwallow Marsh",
    [1446] = "Tanaris",
    [1447] = "Azshara",
    [1448] = "Felwood",
    [1449] = "Un'Goro Crater",
    [1450] = "Moonglade",
    [1451] = "Silithus",
    [1452] = "Winterspring",
    [1453] = "Stormwind City",
    [1454] = "Orgrimmar",
    [1455] = "Ironforge",
    [1456] = "Thunder Bluff",
    [1457] = "Darnassus",
    [1458] = "Undercity",
    [2521] = "Zephras Isle",
    [2548] = "Riverglades",
}
