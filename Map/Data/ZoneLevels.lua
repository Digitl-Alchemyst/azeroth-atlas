---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/Data/ZoneLevels.lua
--
-- 2026-11-17 (user request: "show zone levels"). Each zone's level
-- range and the fishing skill its waters need, shown when hovering a
-- zone on the big map. Taken from Leatrix Maps' own table (its "Show
-- zone levels" option, Leatrix_Maps.lua), which covers the classic
-- zones plus WoW Forever's Hyjal, Zephras Isle, Riverglades and
-- Shen'dralas. Cities have a fishing skill and no level range.
--   [uiMapID] = { minLevel, maxLevel, fishing }
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Map = AlchemyGPS.Map or {}

AlchemyGPS.Map.ZoneLevels = {
    -- Eastern Kingdoms
    [1416] = { 30, 40, "130" },        -- Alterac Mountains
    [1417] = { 30, 40, "130" },        -- Arathi Highlands
    [1418] = { 35, 45 },               -- Badlands
    [1419] = { 45, 55 },               -- Blasted Lands
    [1428] = { 50, 58, "330" },        -- Burning Steppes
    [1430] = { 55, 60, "330" },        -- Deadwind Pass
    [1426] = { 1, 10, "1" },           -- Dun Morogh
    [1431] = { 18, 30, "55" },         -- Duskwood
    [1423] = { 53, 60, "330" },        -- Eastern Plaguelands
    [1429] = { 1, 10, "1" },           -- Elwynn Forest
    [1424] = { 20, 30, "55" },         -- Hillsbrad Foothills
    [1455] = { nil, nil, "1" },        -- Ironforge
    [1432] = { 10, 20, "1" },          -- Loch Modan
    [1433] = { 15, 25, "55" },         -- Redridge Mountains
    [1427] = { 43, 50 },               -- Searing Gorge
    [1421] = { 10, 20, "1" },          -- Silverpine Forest
    [1453] = { nil, nil, "1" },        -- Stormwind City
    [1434] = { 30, 45, "130 (205)" },  -- Stranglethorn Vale
    [1435] = { 35, 45, "130" },        -- Swamp of Sorrows
    [1425] = { 40, 50, "205" },        -- The Hinterlands
    [1420] = { 1, 10, "1" },           -- Tirisfal Glades
    [1458] = { nil, nil, "1" },        -- Undercity
    [1436] = { 10, 20, "1" },          -- Westfall
    [1422] = { 51, 58, "205" },        -- Western Plaguelands
    [1437] = { 20, 30, "55" },         -- Wetlands

    -- Kalimdor
    [1440] = { 18, 30, "55" },         -- Ashenvale
    [1447] = { 45, 55, "205 (330)" },  -- Azshara
    [1439] = { 10, 20, "1" },          -- Darkshore
    [1457] = { nil, nil, "1" },        -- Darnassus
    [1443] = { 30, 40, "130" },        -- Desolace
    [1411] = { 1, 10, "1" },           -- Durotar
    [1445] = { 35, 45, "130" },        -- Dustwallow Marsh
    [1448] = { 48, 55, "205" },        -- Felwood
    [1444] = { 40, 50, "205 (330)" },  -- Feralas
    [1450] = { nil, nil, "205" },      -- Moonglade
    [1412] = { 1, 10, "1" },           -- Mulgore
    [1454] = { nil, nil, "1" },        -- Orgrimmar
    [1451] = { 55, 60, "330" },        -- Silithus
    [1442] = { 15, 27, "55" },         -- Stonetalon Mountains
    [1446] = { 40, 50, "205" },        -- Tanaris
    [1438] = { 1, 10, "1" },           -- Teldrassil
    [1413] = { 10, 25, "1" },          -- The Barrens
    [1441] = { 25, 35, "130" },        -- Thousand Needles
    [1456] = { nil, nil, "1" },        -- Thunder Bluff
    [1449] = { 48, 55, "205" },        -- Un'Goro Crater
    [1452] = { 55, 60, "330" },        -- Winterspring

    -- WoW Forever
    [2482] = { 60, 60 },               -- Hyjal
    [2521] = { 1, 12 },                -- Zephras Isle
    [2548] = { 35, 45 },               -- Riverglades
    [2652] = { 35, 45 },               -- Shen'dralas
}

-- "(30-40)" coloured for the player's level, the way Leatrix Maps
-- colours it: red/orange above you, yellow in range, green/grey below.
function AlchemyGPS.Map.ZoneLevelText(mapId)
    local t = AlchemyGPS.Map.ZoneLevels[mapId]
    if not t or not t[1] or not t[2] then return nil end
    local lo, hi = t[1], t[2]
    local level = UnitLevel("player") or 1
    local color
    if level < lo then
        color = GetQuestDifficultyColor(lo)
    elseif level > hi then
        color = GetQuestDifficultyColor(hi - 2)
    else
        color = QuestDifficultyColors and QuestDifficultyColors["difficult"]
    end
    local hex = color and ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) or "|cffffffff"
    local range = lo == hi and tostring(hi) or (lo .. "-" .. hi)
    return hex .. "(" .. range .. ")|r"
end

function AlchemyGPS.Map.ZoneFishing(mapId)
    local t = AlchemyGPS.Map.ZoneLevels[mapId]
    return t and t[3] or nil
end
