---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/Data/GuideDungeonEntrance.lua
--
-- Build-order step 9l (2026-11-10): dungeon/raid entrance icons,
-- explicit user request. Carbonite's Guides/ folder has no dedicated
-- file for these (unlike Mailbox/Innkeeper/Banker) - the real source
-- is Carbonite/Data/camelot/Zones.lua's Nx.Zones table, keyed by
-- INSTANCE mapID (not the owner zone), one row per zone/instance with
-- fields "name|minLvl|maxLvl|faction|typ|entryId|ex|ey|numPlayers" -
-- entryId/ex/ey (the owner zone's mapID and the entrance's position in
-- it, 0-100 percent, same convention as every other Guide data file)
-- are only populated for actual instance rows; plain zone/battleground
-- rows leave them blank and are skipped below entirely.
--
-- Ported here as a LOCAL table (not exposing Nx.Zones globally at
-- all - nothing else needs the raw per-instance shape, and this
-- avoids any collision risk with Carbonite's own real Nx.Zones if
-- that addon is also loaded) containing only the rows that actually
-- have entrance data: every dungeon and raid from Carbonite's own
-- camelot-flavor table, both the vanilla ones and the "WoW Forever"-
-- specific additions lower in that same file. Faction in the source
-- table is always 3 ("instance") for every one of these rows - not a
-- real per-faction restriction the way Mailbox/Banker/Innkeeper's own
-- faction field is, so every entry here is built with faction 0 (show
-- to both) once converted to the shared Guide data format below.
--
-- The one-time conversion loop at the bottom turns this into the
-- exact same "[ownerMapId] = 'fac,x,y|fac,x,y'" shape every other
-- Guide data file already uses, so RefreshServiceIcons/MinimapEngine.
-- lua needs zero new parsing code for this category - it's just
-- another entry in SERVICE_ICON_TEX/the Mailbox-style loop.
--
-- User asked for "dungeon and raid entrances" as one category, not
-- two - both share this same single "DungeonEntrance" filter/icon key.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local Map = AlchemyGPS.Map

-- { instanceName, ownerMapId, ex, ey } - instanceName now also feeds
-- the hover-tooltip label (build-order step 12), not just readability.
local RAW_INSTANCES = {
    { "Ragefire Chasm",               1454, 51.9,  58.4 },
    { "Zul'Farrak",                   1446, 39.2,  21.4 },
    { "The Temple of Atal'Hakkar",    1435, 69.83, 54.14 },
    { "The Stockade",                 1453, 51.4,  68.3 },
    { "Gnomeregan",                   1426, 24.38, 39.8 },
    { "Blackfathom Deeps",            1440, 14.15, 13.9 },
    { "Uldaman",                      1418, 44.44, 12.19 },
    { "Dire Maul",                    1444, 59.1,  45.4 },
    { "Blackrock Depths",             1428, 15.70, 28.33 },
    { "Blackrock Spire",              1428, 15.70, 33.33 },
    { "Maraudon",                     1443, 29.48, 62.53 },
    { "The Deadmines",                1436, 42.56, 71.72 },
    { "Wailing Caverns",              1413, 39,    69.4 },
    { "Razorfen Downs",               1413, 45.43, 89.48 },
    { "Razorfen Kraul",               1413, 43.59, 90.16 },
    { "Scholomance",                  1422, 69.77, 73.51 },
    { "Shadowfang Keep",              1421, 44.86, 67.86 },
    { "Stratholme",                   1423, 27.09, 12.6 },
    { "Scarlet Monastery",            1420, 85.57, 36.04 },
    { "Naxxramas",                    1423, 40.0,  25.8 },
    { "Molten Core",                  1428, 20.70, 33.33 },
    { "Ruins of Ahn'Qiraj",           1451, 29.1,  93.8 },
    { "Onyxia's Lair",                70,   52.41, 76.39 },
    { "Blackwing Lair",               1428, 20.70, 35.33 },
    { "Temple of Ahn'Qiraj",          1451, 29.1,  93.8 },
    { "Zul'Gurub",                    1434, 67.2,  32.8 },
    { "City of Dalaran",              1416, 9.8,   60.6 },
    { "Excavation Site: Wetlands",    1437, 52.3,  66.4 },
    { "Ruins of Lordaeron",           1458, 72.9,  11.3 },
    { "The Hall of Thanes",           1455, 46.8,  52.3 },
    { "The Drowned City",             1434, 20.9,  28.1 },
    { "Blackmaw Hold",                1447, 39.6,  32.7 },
    { "Alcaz Prison",                 1445, 77.5,  17.2 },
    { "The Shaper's Terrace",         1449, 49.1,  1.0 },
    { "Krol'dok Stronghold",          2548, 37.5,  37.4 },
}

-- Build-order step 12, 2026-11-11: instanceName is no longer discarded
-- - hover-tooltip support (explicit user request) needs a real per-
-- point name, and this table already had one. None of these names
-- contain "," or "|" (checked), the two characters this format can't
-- carry safely.
local byZone = {}
for _, inst in ipairs(RAW_INSTANCES) do
    local name, ownerMapId, ex, ey = inst[1], inst[2], inst[3], inst[4]
    local entry = ("0,%g,%g,%s"):format(ex, ey, name)
    byZone[ownerMapId] = byZone[ownerMapId] and (byZone[ownerMapId] .. "|" .. entry) or entry
end

Map.GuideData = Map.GuideData or {}
Map.GuideData["DungeonEntrance"] = byZone
Map.GuideData["DungeonEntrance"].Mode = 32
