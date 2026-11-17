---------------------------------------------------------------------------------------
-- Alchemy GPS | Quest/Data/QuestDBManual.lua
--
-- HAND-MAINTAINED - unlike the other files in this folder, nothing
-- generates this one. It holds what the generated data can't know:
-- this server's newest content, where QuestieDB has the quests but not
-- where their objectives, givers or turn-ins are.
--
-- Read by QuestCatalog.lua (loaded after this file):
--   QuestDungeons  quest id -> instance ids (comma-separated) the quest's
--                  objectives are done inside. Routing and the quest
--                  pins then point at the dungeon's entrance - without
--                  this they fell back to the quest giver.
--   ManualStart /  Start / End in the rows' packed shape
--   ManualEnd      ("giverId|mapId|32|x|y", 0-100 zone percent). Only
--                  fill a row that has no position of its own.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.QuestData = AlchemyGPS.QuestData or {}
local QuestData = AlchemyGPS.QuestData

QuestData.Names = QuestData.Names or {}
QuestData.Names[252019] = QuestData.Names[252019] or "Abra Cadabra"

---------------------------------------------------------------------------------------
-- The Drowned City (instance 2970), new to WoW Forever. Entrance:
-- underwater in Sunken Hollow, Stranglethorn Vale, about 21.5, 27.8
-- (QuestData.Instances). QuestieDB names every objective (the four
-- Tablets of I'lalai, Var'Taka, Captain Dreadrise, the fetish and idol
-- droppers) but has no spawn for any of them. Quest list and givers:
-- ForeverDungeonJournal (Data/Dungeons.lua, Data/QuestUpdates.lua).
---------------------------------------------------------------------------------------

QuestData.QuestDungeons = {
    [95775] = "2970",   -- The Drowned City (Horde): rubbings of the four tablets
    [95776] = "2970",   -- The Only Good Brinescale...: kill Var'Taka
    [96774] = "2970",   -- Ancient Gurubashi Idol (Horde)
    [95787] = "2970",   -- Take Two With Water (Alliance): rubbings of the four tablets
    [95788] = "2970",   -- Magics of the Drowned City: 5 I'lalai Fetishes
    [97130] = "2970",   -- Ancient Gurubashi Secrets (Alliance)
    [95789] = "2970",   -- Shady Saltseers: 10 Voodoo-Infused Artifacts
    [95791] = "2970",   -- The Saltseer Captain: Captain Dreadrise + 3 Saltseer Coroners
}

-- Quest id -> the boss that drops what the quest needs, for objectives
-- whose text names the item, not the boss (Map/DungeonPins.lua marks
-- that boss on the dungeon map). Var'Taka and Captain Dreadrise are
-- named in their own objectives.
QuestData.DungeonQuestBosses = {
    [96774] = "Deathless Marrow",   -- Ancient Gurubashi Idol (Horde)
    [97130] = "Deathless Marrow",   -- Ancient Gurubashi Secrets (Alliance)
}

-- [instanceID] = objectives no database has a position for, tied to
-- the boss they are found near (Map/DungeonPins.lua: the boss pin turns
-- gold and its tooltip says so while the objective is unfinished).
-- `match` is lower-case text of the objective. Source: forg.gg's
-- Drowned City guide (2026-11-16) - approximate by its own account.
-- The first tablet: next to the first boss (user, in-game, 2026-11-16).
QuestData.DungeonObjectiveHints = {
    [2970] = {
        { match = "first tablet", boss = "Zul'Alai", text = "The First Tablet is next to Zul'Alai, the first boss" },
        { match = "second tablet", boss = "Var'Taka", text = "The Second Tablet is near Var'Taka (guide, approximate)" },
        { match = "third tablet", boss = "Captain Dreadrise", text = "The Third Tablet sits in a skull's mouth near Captain Dreadrise (guide)" },
        { match = "fourth tablet", boss = "Min'loth", text = "The Fourth Tablet is behind Min'loth (guide)" },
        { match = "saltseer coroner", boss = "Captain Dreadrise", text = "The Saltseer Coroners are with Captain Dreadrise (guide)" },
    },
}

local DIBBS = "2277|1424|32|50.6|57.1"      -- Loremaster Dibbs, Southshore

QuestData.ManualStart = {
    [96078] = "2519|1434|32|32.3|27.7",     -- Kin'weelay, Grom'gol
    [95787] = DIBBS,
    [95788] = DIBBS,
    [95799] = DIBBS,
    [95798] = DIBBS,
}

QuestData.ManualEnd = {
    [95787] = DIBBS,
    [95788] = DIBBS,
    [95799] = "2916|1455|32|77.5|11.8",     -- Historian Karnik, Hall of Explorers
    [95798] = "252019|1416|32|13.2|69.6",   -- Abra Cadabra, Dalaran
    [97130] = "31439|1416|32|15.4|74.0",    -- Archmage Timear, Dalaran
    [95789] = "773|1434|32|26.9|77.2",      -- Krazek, Booty Bay
}
