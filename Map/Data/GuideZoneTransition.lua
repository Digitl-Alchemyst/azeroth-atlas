---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/Data/GuideZoneTransition.lua
--
-- Build-order step 9l (2026-11-10): zone transition/border-crossing
-- icons (boats, zeppelins, trams, portals, and plain walk-through
-- zone borders), explicit user request. Source is Carbonite/Data/
-- camelot/ZoneConnections.lua's Nx.ZoneConnections, a flat array of
-- pipe-delimited strings: "flags|contType|name1|mapId1|x1|y1|name2|
-- mapId2|x2|y2" (confirmed against that file's own Nx.Map:
-- ConnectionUnpack). Each entry describes ONE connection with TWO
-- endpoints (one per connected zone) - unlike every other Guide data
-- file here, which is already bucketed by a single owner zone.
--
-- Copied verbatim below (byte-for-byte on the numeric fields, so a
-- transcription mistake can't silently shift a coordinate) except for
-- the name fields, which use real Carbonite's AceLocale lookup
-- (L["..."]) - inlined as plain strings instead, same "no locale
-- layer here" convention every other ported Guide file already uses.
--
-- Build-order step 12, 2026-11-11: names ARE used now - hover-tooltip
-- support (explicit user request) reads them as each point's label,
-- falling back to the generic "Zone Transition" label only for the
-- majority of entries (plain walk-through zone borders) whose real
-- Carbonite source leaves both names blank. Checked: none of the real
-- names below ("Boat to ...", "Zeppelin to ...", "Portal to ...",
-- "Tram to ...") contain "," or "|", the two characters this format
-- can't carry safely.
--
-- RAW_CONNECTIONS is parsed once at load time (ParseConnection below)
-- and both endpoints are written into the same "[ownerMapId] =
-- 'fac,x,y|fac,x,y'" shape every other Guide data file already uses -
-- RefreshServiceIcons needs zero new parsing code for this category.
-- Faction: was always 0 (shown to both) until 2026-11-18; now read
-- from each connection's flags - see addPoint's header below.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local Map = AlchemyGPS.Map

local RAW_CONNECTIONS = {
    "7|1||1417|20.34|29.73||1424|81.96|56.91",
    "7|1||1417|45.45|89.06||1437|51.06|11.95",
    "7|1||1439|43.69|94.7||1440|29.16|14.99",
    "7|1||1440|42.34|70.96||1442|78.21|42.94",
    "7|1||1440|55.85|31.7||1448|54.91|92.71",
    "7|1||1440|94.56|47.6||1447|10.72|75.27",
    "7|1||1440|68.63|86.25||1413|48.44|11.33",
    "7|1||1448|64.97|8.36||1450|35.77|72.2",
    "7|1||1448|64.97|8.36||1452|27.96|34.56",
    "7|1||1411|45.54|12.28||1454|52.49|84.4",
    "7|1||1411|37.2|43||1413|60.8|19.8",
    "7|1||1434|40.81|4.19||1431|44.5|87.51",
    "7|1||1431|10.6|63.8||1436|68.9|63",
    "7|1||1436|60.9|19||1429|22.3|78.2",
    "7|1||1429|32.33|49.86||1453|76.42|94.63",
    "7|1||1429|93.21|72.27||1433|3.86|71.9",
    "7|1||1431|93.75|11.43||1433|2.01|89.26",
    "7|1||1431|89.88|41.25||1430|33.05|35.96",
    "7|1||1430|58.29|41.44||1435|5.84|60.78",
    "7|1||1419|52.03|5.6||1435|33.83|66.07",
    "7|1||1433|41.42|6.56||1428|78.85|82.5",
    "7|1||1433|45.22|8.11||2548|16.1|68.1",
    "7|1||1433|66.62|18.71||2548|25.5|73.0",
    "6|1||2548|28.2|39.3||1428|98.0|36.2",
    "7|1||1433|96.62|68.81||1435|67.0|0.41",
    "7|1||1427|34.81|83.74||1428|31.83|50.44",
    "7|1||1427|76.63|56.67||1418|1.09|62.92",
    "7|1||1432|47.19|80.82||1418|49.36|7.97",
    "7|1||1432|19.61|62.81||1426|86.13|51.16",
    "7|1||1432|19.23|17.21||1426|84.37|31.09",
    "7|1||1455|21.62|77.79||1426|53.4|35.01",
    "7|1||1432|25.57|10.47||1437|53.97|70.33",
    "7|1||1416|51.2|65.6||1424|55.5|16.6",
    "7|1||1416|23.6|87.2||1424|30.4|27.9",
    "7|1||1418|54.7|90.5||2548|32.1|30.4",
    "7|1||1425|9.66|55.77||1424|85.06|31.27",
    "7|1||1425|24.94|45.71||1422|65.48|88.64",
    "7|1||1416|80.66|36.42||1422|44.05|86.19",
    "7|1||1420|84.09|70.49||1422|28.62|57.46",
    "7|1||1423|6.29|55.80||1422|69.67|50.24",
    "7|1||1421|66.36|79.8||1424|14.35|46.2",
    "7|1||1421|67.56|5.45||1420|54.14|75.77",
    "7|1||1458|66.01|36.85||1420|61.86|64.95",
    "7|1||1454|18|60.43||1413|63.88|0",
    "7|1||1413|39.42|29.68||1442|82.78|96.94",
    "7|1||1443|53.4|5.52||1442|30.21|75.61",
    "7|1||1442|73.0|99.1||1412|40.7|12.9",
    "7|1||1443|80.7|37.4||1412|32.0|22.5",
    "7|1||1443|40.91|90.72||1444|45.45|2.82",
    "7|1||1444|89.1|41.14||1441|7.98|10.93",
    "7|1||1413|44.15|91.23||1441|31.92|24.22",
    "7|1||1446|50.68|24.29||1441|74.24|93.62",
    "7|1||1446|27.08|57.2||1449|71.44|77.23",
    "7|1||1449|29.43|22.42||1451|83.68|14.26",
    "7|1||1445|30.02|47.11||1413|49.53|78.41",
    "7|1||1413|41.87|58.62||1412|64.27|63.73",
    "7|1||1450|35.77|72.2||1452|27.96|34.56",
    "3|0|Portal to Darnassus|1438|55.94|89.84|Portal to Teldrassil|1457|30.75|41.39",
    "7|1||1438|36.32|54.38||1457|85.73|35.93",
    "7|1||1412|38.39|40.73||1456|35.69|63.08",
    "7|1||1412|35.88|36.45||1456|35.69|63.08",
    "7|1||1412|39.54|29.09||1456|51.17|31.54",
    "7|1||1412|42.18|30.01||1456|51.17|31.54",
    "3|2|Boat to Menethil Harbor|1445|71.54|56.37|Boat to Dustwallow Marsh|1437|5.03|63.46",
    "3|2|Boat to Stormwind City|1439|30.69|41.12|Boat to Darkshore|1453|22.42|55.95",
    "3|2|Tram to Stormwind City|1455|72.78|50.24|Tram to Ironforge|1453|69.04|30.85",
    "3|2|Boat to Menethil Harbor|1439|32.39|43.82|Boat to Darkshore|1437|4.5|57.7",
    "3|2|Boat to Teldrassil|1439|33.18|40.1|Boat to Darkshore|1438|54.87|96.8",
    "5|2|Zeppelin to Stranglethorn Vale|1420|61.87|59.07|Zeppelin to Undercity|1434|31.56|29.13",
    "5|2|Zeppelin to Undercity|1411|50.88|13.87|Zeppelin to Orgrimmar|1420|60.7|58.78",
    "5|2|Zeppelin to Stranglethorn Vale|1411|50.57|12.64|Zeppelin to Orgrimmar|1434|31.37|30.15",
    "7|2|Boat to Stranglethorn Vale|1413|63.68|38.63|Boat to The Barrens|1434|26.04|73.24",
    "7|2|Boat to Tanaris|2548|80.1|54.4|Boat to Riverglades|1446|68.3|23.0",
    "2|0|Portal to Stormwind|1416|12.0|56.2|Portal to Dalaran|1453|50.0|87.0",
    "3|2|Boat to Dalaran|2521|65.8|83.4|Boat to Zephras Isle|1416|12.7|52.0",
    -- 2026-11-18: a zeppelin, not a boat (Leatrix Maps: "Zeppelin to
    -- Thunder Bluff" / "Zeppelin to Zephras Isle").
    "5|2|Zeppelin to Mulgore|2521|57.9|80.7|Zeppelin to Zephras Isle|1412|34.3|25.7",
    -- 2026-11-18: the Feathermoon Stronghold boat, missing from
    -- Carbonite's list - Leatrix Maps' two Feralas "Boat to" pins.
    "3|2|Boat to Feathermoon|1444|43.1|42.8|Boat to Feralas|1444|31.0|39.5",
}

local function ParseConnection(s)
    local parts = {}
    for p in (s .. "|"):gmatch("([^|]*)|") do
        parts[#parts + 1] = p
    end
    -- flags, contType, name1, mapId1, x1, y1, name2, mapId2, x2, y2
    return parts[3], tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6]),
        parts[7], tonumber(parts[8]), tonumber(parts[9]), tonumber(parts[10])
end

-- Build-order step 12, second follow-up, 2026-11-11: a plain
-- walk-through border's own name1/name2 are blank in Carbonite's real
-- data (confirmed - unlike the boat/zeppelin/tram/portal entries,
-- which already carry a real "Boat to X"-style name) - resolved to
-- the OTHER endpoint's zone name instead of falling through to the
-- generic "Zone Transition" label, matching Leatrix_Maps' own real
-- behavior for its equivalent "Arrow" pins (confirmed: its tooltip
-- renderer shows that pin's title field verbatim, and its own data
-- stores the plain destination zone name there, no "to" prefix - see
-- Map/Data/ZoneNames.lua's own header for the full citation).
-- 2026-11-16 (user request: "special icons for zeppelins and boats
-- moving between continents"): boats and zeppelins go to categories of
-- their own (GuideData.Boat / .Zeppelin - own icon, own filter row);
-- plain borders stay Zone Transitions. Told apart by the name every
-- boat / zeppelin / portal / tram row carries ("Boat to ...").
--
-- 2026-11-18 (user request, from Leatrix Maps): portals and trams get
-- kinds of their own too (GuideData.Portal / .Tram), and every point
-- now carries:
--   * its faction, from the connection's flags - Carbonite's own
--     reading (MapEngine.lua's transport branch): bit 2 = Alliance,
--     bit 4 = Horde, both or neither = everyone. Written in the
--     Guide data's hide-code convention (1 = Alliance only, 2 = Horde
--     only, 0 = both - see ServiceIconFactionOk in MinimapEngine.lua),
--     so the other faction's boats are hidden unless the map's "Other
--     faction's travel" filter is on.
--   * the map it leads to, after a "#" at the end of the name
--     ("Boat to Darkshore#1439"), so clicking the icon on the big map
--     can open that map.
local KINDS = { Boat = true, Zeppelin = true, Portal = true, Tram = true }
local byZone, byKind = {}, { Boat = {}, Zeppelin = {}, Portal = {}, Tram = {} }

local function factionOf(flags)
    local bits = flags and (flags % 8 - flags % 2) or 0     -- flags & 6
    if bits == 2 then return 1 end
    if bits == 4 then return 2 end
    return 0
end

local function addPoint(mapId, x, y, name, otherMapId, fac)
    if not mapId or not x or not y then return end
    if not name or name == "" then
        name = Map.ZoneNames and Map.ZoneNames[otherMapId] or ""
    end
    local kind = name:match("^(%a+) to ")
    if not KINDS[kind] then kind = nil end
    local bucket = kind and byKind[kind] or byZone
    local entry = ("%d,%g,%g,%s"):format(fac, x, y, name)
    if otherMapId then entry = entry .. "#" .. otherMapId end
    bucket[mapId] = bucket[mapId] and (bucket[mapId] .. "|" .. entry) or entry
end

for _, raw in ipairs(RAW_CONNECTIONS) do
    local flags = tonumber(raw:match("^(%d+)|"))
    local name1, mapId1, x1, y1, name2, mapId2, x2, y2 = ParseConnection(raw)
    local fac = factionOf(flags)
    addPoint(mapId1, x1, y1, name1, mapId2, fac)
    addPoint(mapId2, x2, y2, name2, mapId1, fac)
end

Map.GuideData = Map.GuideData or {}
Map.GuideData["ZoneTransition"] = byZone
Map.GuideData["ZoneTransition"].Mode = 32
Map.GuideData["Boat"] = byKind.Boat
Map.GuideData["Boat"].Mode = 32
Map.GuideData["Zeppelin"] = byKind.Zeppelin
Map.GuideData["Zeppelin"].Mode = 32
Map.GuideData["Portal"] = byKind.Portal
Map.GuideData["Portal"].Mode = 32
Map.GuideData["Tram"] = byKind.Tram
Map.GuideData["Tram"].Mode = 32
