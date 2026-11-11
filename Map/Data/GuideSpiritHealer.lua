---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/Data/GuideSpiritHealer.lua
--
-- Build-order step 11 (2026-11-11): spirit healer icons, explicit user
-- request ("add icons for the spirit healers too, leatrix has this so
-- you can see how they get the data"). Checked Carbonite's own source
-- first, per this project's standing convention - it has NO spirit-
-- healer data anywhere (confirmed: no "Spirit"/"SpiritHealer" hits in
-- any Data/*/MapData file, and NxMapGuide.lua's one "Spirit" string is
-- the unrelated old character-stat name, not a location). Unlike
-- Corpse (a live Blizzard API, C_DeathInfo.GetCorpseMapPosition) or
-- Dungeon/Zone data (Carbonite's own real Zones.lua table), spirit
-- healer locations have no live API AND no Carbonite source at all -
-- Blizzard draws no map pin for them and tracks no "nearest spirit
-- healer" data either. They're simply fixed, hand-surveyed points, the
-- same way every other addon that shows them (including Leatrix_Maps,
-- confirmed installed on this exact server) has to hardcode them.
--
-- Source: Leatrix_Maps_Icons.lua's own Leatrix_Maps["Icons"] table
-- (this addon collection's only available real source for this
-- specific data, since Carbonite has none) - every row tagged
-- {"Spirit", x, y, ...} across its whole-world zone tables, extracted
-- programmatically (not hand-retyped, to avoid transcription error on
-- 89 rows) and cross-checked against two commented-out duplicate rows
-- in Leatrix's own source (Eastern Plaguelands, mapID 1423) which were
-- correctly excluded - Leatrix's own data disables those two as
-- redundant, so this port matches its ACTIVE data, not its dead code.
-- Map IDs are the same uiMapID scheme this addon's own Gather*.lua
-- files already key by (confirmed: 1417/1418/1437/etc. already appear
-- in GatherHerb.lua/GatherMining.lua/GatherTreasure.lua), so these
-- transfer directly into GetWorldPos with no translation needed.
--
-- Every entry already in Leatrix's table omits a faction field
-- entirely (no row ever restricts a spirit healer to one side) - built
-- with faction 0 (show to both) for all of them, same treatment
-- GuideDungeonEntrance.lua gives its own no-real-faction-field source
-- data.
--
-- Icon: NOT Leatrix's own choice (an atlas, "Vehicle-TempleofKotmogu-
-- GreenBall" - a Temple of Kotmogu battleground ball icon repurposed
-- as a convenient round green dot, not real "spirit healer" art
-- either, since none exists). Rather than add atlas-vs-texture
-- branching to the shared UpdateServiceIcons pool (used by seven
-- categories already, all plain Interface\Icons\... paths), used
-- Interface\Icons\Spell_Holy_Resurrection instead - a real, plain
-- icon path confirmed present since vanilla, and literally the
-- resurrection-spell icon, which is thematically the closest fit
-- available in that same reliable family (same "pick something
-- guaranteed to exist since vanilla" reasoning as DungeonEntrance/
-- ZoneTransition/GuardFlag above it).
--
-- Same conversion-loop/shape as every other Guide data file - turns
-- this into "[ownerMapId] = 'fac,x,y|fac,x,y'", so RefreshServiceIcons
-- needs zero new parsing code, just a new SERVICE_ICON_TEX entry and a
-- new FilterMenu.lua row.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local Map = AlchemyGPS.Map

-- { zoneName, mapId, x, y } - zoneName is kept only for human
-- readability of this file, not stored/used further (every row's real
-- title, same as Leatrix's own, is just "Spirit Healer").
local RAW_SPIRIT_HEALERS = {
    { "Arathi Highlands",           1417,   48.7,   55.5 },
    { "Badlands",                   1418,    8.2,   55.5 },
    { "Badlands",                   1418,   56.9,   24.5 },
    { "Blasted Lands",              1419,   51.0,   12.2 },
    { "Tirisfal Glades",            1420,   31.2,   64.8 },
    { "Tirisfal Glades",            1420,   56.2,   49.4 },
    { "Tirisfal Glades",            1420,   79.0,   40.8 },
    { "Tirisfal Glades",            1420,   82.0,   69.5 },
    { "Silverpine Forest",          1421,   44.2,   41.5 },
    { "Western Plaguelands",        1422,   45.5,   85.5 },
    { "Western Plaguelands",        1422,   65.5,   74.6 },
    { "Eastern Plaguelands",        1423,   38.2,   70.5 },
    { "Eastern Plaguelands",        1423,   39.0,   92.5 },
    { "Eastern Plaguelands",        1423,   47.2,   44.4 },
    { "Eastern Plaguelands",        1423,   80.0,   64.5 },
    { "Eastern Plaguelands",        1423,   96.5,   91.5 },
    { "Hillsbrad Foothills",        1424,   51.6,   52.5 },
    { "Hillsbrad Foothills",        1424,   63.5,   19.5 },
    { "The Hinterlands",            1425,   16.8,   44.6 },
    { "The Hinterlands",            1425,   60.5,   38.6 },
    { "The Hinterlands",            1425,   62.0,   26.8 },
    { "The Hinterlands",            1425,   72.6,   68.0 },
    { "Dun Morogh",                 1426,   29.5,   69.8 },
    { "Dun Morogh",                 1426,   47.0,   55.0 },
    { "Dun Morogh",                 1426,   54.2,   39.0 },
    { "Searing Gorge",              1427,   35.5,   22.6 },
    { "Burning Steppes",            1428,   63.2,   23.5 },
    { "Elwynn Forest",              1429,   39.5,   60.5 },
    { "Elwynn Forest",              1429,   49.5,   43.4 },
    { "Elwynn Forest",              1429,   83.5,   69.5 },
    { "Deadwind Pass",              1430,   40.0,   75.3 },
    { "Duskwood",                   1431,   20.0,   49.4 },
    { "Duskwood",                   1431,   44.8,   67.2 },
    { "Duskwood",                   1431,   47.8,   45.6 },
    { "Duskwood",                   1431,   75.0,   59.0 },
    { "Loch Modan",                 1432,   32.5,   46.7 },
    { "Redridge Mountains",         1433,   20.8,   56.5 },
    { "Stranglethorn Vale",         1434,   30.0,   73.0 },
    { "Stranglethorn Vale",         1434,   38.4,    8.8 },
    { "Swamp of Sorrows",           1435,   50.2,   62.2 },
    { "Westfall",                   1436,   51.6,   49.6 },
    { "Wetlands",                   1437,   11.5,   43.4 },
    { "Wetlands",                   1437,   49.5,   41.5 },
    { "Undercity",                  1458,   67.7,   14.2 },
    { "Durotar",                    1411,   44.2,   69.4 },
    { "Durotar",                    1411,   47.0,   17.5 },
    { "Durotar",                    1411,   53.5,   44.5 },
    { "Durotar",                    1411,   57.5,   73.2 },
    { "Mulgore",                    1412,   42.6,   78.0 },
    { "Mulgore",                    1412,   46.5,   55.5 },
    { "The Barrens",                1413,   45.2,   61.0 },
    { "The Barrens",                1413,   50.7,   32.5 },
    { "The Barrens",                1413,   60.2,   39.8 },
    { "Teldrassil",                 1438,   56.2,   63.2 },
    { "Teldrassil",                 1438,   58.7,   42.5 },
    { "Darkshore",                  1439,   41.8,   36.5 },
    { "Darkshore",                  1439,   43.5,   92.3 },
    { "Ashenvale",                  1440,   17.8,   11.0 },
    { "Ashenvale",                  1440,   22.2,   28.2 },
    { "Ashenvale",                  1440,   40.2,   53.0 },
    { "Ashenvale",                  1440,   51.5,   63.2 },
    { "Ashenvale",                  1440,   80.6,   58.0 },
    { "Ashenvale",                  1440,   84.2,   56.8 },
    { "Ashenvale",                  1440,   93.2,   42.2 },
    { "Thousand Needles",           1441,   30.5,   23.5 },
    { "Thousand Needles",           1441,   69.1,   53.5 },
    { "Stonetalon Mountains",       1442,   57.5,   62.0 },
    { "Desolace",                   1443,   50.2,   62.8 },
    { "Feralas",                    1444,   31.5,   48.0 },
    { "Feralas",                    1444,   44.0,    7.4 },
    { "Feralas",                    1444,   50.4,   13.4 },
    { "Feralas",                    1444,   54.8,   47.6 },
    { "Feralas",                    1444,   73.0,   44.8 },
    { "Dustwallow Marsh",           1445,   39.6,   30.8 },
    { "Dustwallow Marsh",           1445,   63.5,   43.0 },
    { "Tanaris",                    1446,   54.0,   28.6 },
    { "Azshara",                    1447,   14.5,   78.5 },
    { "Azshara",                    1447,   54.2,   71.4 },
    { "Azshara",                    1447,   70.4,   15.6 },
    { "Felwood",                    1448,   49.5,   30.6 },
    { "Felwood",                    1448,   56.2,   86.6 },
    { "Un'Goro Crater",             1449,   80.0,   49.8 },
    { "Moonglade",                  1450,   62.0,   69.5 },
    { "Silithus",                   1451,   28.0,   87.5 },
    { "Silithus",                   1451,   47.0,   38.5 },
    { "Silithus",                   1451,   80.6,   19.8 },
    { "Winterspring",               1452,   61.2,   34.8 },
    { "Thunder Bluff",              1456,   56.5,   17.9 },
    { "Darnassus",                  1457,   77.2,   26.7 },
}

local byZone = {}
for _, sh in ipairs(RAW_SPIRIT_HEALERS) do
    local _, mapId, x, y = sh[1], sh[2], sh[3], sh[4]
    local entry = ("0,%g,%g"):format(x, y)
    byZone[mapId] = byZone[mapId] and (byZone[mapId] .. "|" .. entry) or entry
end

Map.GuideData = Map.GuideData or {}
Map.GuideData["SpiritHealer"] = byZone
