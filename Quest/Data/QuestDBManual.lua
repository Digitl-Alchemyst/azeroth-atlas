---------------------------------------------------------------------------------------
-- Azeroth Atlas | Quest/Data/QuestDBManual.lua
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
--   ManualRequiredClasses  quest id -> class bit mask (WARRIOR=1 PALADIN=2
--                  HUNTER=4 ROGUE=8 PRIEST=16 SHAMAN=64 MAGE=128
--                  WARLOCK=256 DRUID=1024), for class quests no source
--                  marks as one. Added to QuestDBExtras' RequiredClasses:
--                  the pickup is hidden from other classes, and a shared
--                  copy in another class's log is flagged.
--   ManualObjectives  quest id -> { [objective index] = { "name|mapId|32|x|y", ... } }.
--                  REPLACES that objective's generated locations - for
--                  rows the source data places wrongly (checked in game).
--   ManualProvidedItems  quest id -> "itemId:vendor:name,..." - items the
--                  player crafts, buys or brings, for quests the generated
--                  ProvidedItems (QuestDBRules.lua) misses.
--   ManualRows     quest id -> a whole row, for quests no source has.
--   ManualRules    quest id -> pickup rule, replacing QuestDBRules' one.
--   ManualSide     quest id -> 0 both / 1 Alliance / 2 Horde, replacing
--                  a row's wrong faction.
--   ObjectiveNotes  quest id -> notes on objectives no data places; with
--                  `hold`, routing won't send you back to the giver
--                  while that objective is unfinished.
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
AzerothAtlas.QuestData = AzerothAtlas.QuestData or {}
local QuestData = AzerothAtlas.QuestData

QuestData.Names = QuestData.Names or {}
QuestData.Names[252019] = QuestData.Names[252019] or "Abra Cadabra"
-- Riverglades dock, 79.45, 52.71: turn-in for Twice Misplaced Trust (97332)
-- and giver of the Riverglades coast quests (95118-95123).
QuestData.Names[259961] = QuestData.Names[259961] or "Wharfmaster Whizzbuzz"

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

    -- Krol'dok Stronghold (instance 3039), new to WoW Forever. Entrance:
    -- Riverglades, 37.5, 37.4 (QuestData.Instances). Quest list from
    -- ForeverDungeonJournal (Data/Dungeons.lua, "Wowhead Forever's list for
    -- the dungeon"). QuestieDB names the items but places none of them.
    [94968] = "3039",   -- Eye of Mugg (Horde): Overlord Mugg, last boss
    [94982] = "3039",   -- Eye of Mugg (Alliance)
    [94972] = "3039",   -- Tome of Twilight (Horde): from Nar'gurk
    [94984] = "3039",   -- Tome of Twilight (Alliance): kill Nar'gurk
    [94975] = "3039",   -- A Token of Vengeance (Horde): 15 Cultist Ears
    [94983] = "3039",   -- Twilight Mementos (Alliance): 8 Twilight Bangles
    [96771] = "3039",   -- Vengeance of the Highborne (Alliance): Zalfan Moonshadow
}

-- Quest id -> the boss that drops what the quest needs, for objectives
-- whose text names the item, not the boss (Map/DungeonPins.lua marks
-- that boss on the dungeon map). Var'Taka and Captain Dreadrise are
-- named in their own objectives.
QuestData.DungeonQuestBosses = {
    [96774] = "Deathless Marrow",   -- Ancient Gurubashi Idol (Horde)
    [97130] = "Deathless Marrow",   -- Ancient Gurubashi Secrets (Alliance)
    [94968] = "Overlord Mugg",      -- Eye of Mugg (Horde): "their leader"
    [94982] = "Overlord Mugg",      -- Eye of Mugg (Alliance)
    [94972] = "Nar'gurk",           -- Tome of Twilight (Horde): the item, not the boss
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

-- [instanceID] = objectives found in a room rather than on a boss: the
-- room (Map/Data/DungeonRoomData.lua's name for it) is shaded in the
-- quest's colour on the dungeon map while the objective is unfinished
-- (Map/DungeonRooms.lua GetQuestRoomPins). `match` is lower-case text
-- of the objective.
QuestData.DungeonObjectiveRooms = {
    [2970] = {
        -- Shady Saltseers (95789): the Voodoo-Infused Artifacts drop from
        -- the Saltseer mobs in the Altar of the Serpent, Captain
        -- Dreadrise's room on the north side (user, in game, 2026-11-19).
        { match = "infused artifact", room = "Altar of the Serpent",
          text = "Drop from the Saltseers in the Altar of the Serpent" },
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

QuestData.ManualRequiredClasses = {
    -- Ground to Keep, Arathi Highlands: a rogue quest that can be shared
    -- with other classes (user, 2026-11-18). QuestieDB and Carbonite have
    -- no class requirement on it.
    [92867] = 8,        -- ROGUE
}

-- 2026-11-18 (user, the Magram / Gelkis centaur quests in Desolace).
-- Quest id -> "itemId:vendor:name,...", the same shape as QuestDBRules'
-- generated ProvidedItems, for quests QuestieDB lists no objectives for.
-- The clans' profession quests (items and counts: Wowhead Forever,
-- 2026-11-18); Gizmo for Warug (1371) is in the generated data.
QuestData.ManualProvidedItems = {
    [92754] = "13459:0:Greater Shadow Protection Potion",   -- A New Need for Shadow Protection (Magram, Mirda): alchemy, 3
    [92755] = "11135:0:Greater Mystic Essence",             -- Mysterious Mysticism (Gelkis, Halea): enchanting, 3
    [92814] = "10008:0:White Bandit Mask",                  -- I Need a Tailor (Gelkis, Molkar): tailoring
    [92817] = "5739:0:Barbaric Harness",                    -- Leather Technique (Gelkis, Talra): leatherworking
    [92818] = "3855:0:Massive Iron Axe",                    -- Big, No, MASSIVE Iron Axes (Magram, Grolkar): blacksmithing, 2
}

-- Quest id -> the faction that can take it (0 both, 1 Alliance, 2 Horde),
-- REPLACING the row's own side, for rows that have it wrong (checked in game).
QuestData.ManualSide = {
    -- Not My Circus, Riverglades (Jasper Geartoggle, goblin, 75.9, 52.7):
    -- Carbonite marks it Alliance; the game offers it to Horde too (user,
    -- 2026-11-19), and QuestieDB has no race limit on it.
    [95982] = 0,
}

-- Quest id -> a pickup rule in QuestDBRules' Rules format ("s=a,b;n=c";
-- see the key list there), REPLACING the generated one.
QuestData.ManualRules = {
    -- Smuggler's Paradise, Riverglades (Friz Frazzlespark): only offered
    -- after a lead-in - The Goblin Trader (93976, Horde) or A Few Furs for
    -- Friz (94928, Alliance), both of which name it as their next quest.
    -- QuestieDB lists no prerequisite, so the map showed it at once (user,
    -- 2026-11-19: "map shows ... but i cant pick it up").
    [95288] = "s=93976,94928;n=95293",
}

-- Whole rows, in the generated rows' shape, for quests no source has a
-- row for. Added only when the quest has no row.
QuestData.ManualRows = {
    -- QuestieDB has the giver (Mirda, 70.47, 70.39) but no turn-in, so the
    -- import skipped it; Wowhead Forever: turned in to Mirda (2026-11-18).
    [92754] = {
        Quest = "A New Need for Shadow Protection|3|35|30|0|0|0",
        Start = "253097|1443|32|70.47|70.39",
        End = "253097|1443|32|70.47|70.39",
    },
}

-- Quest id -> { { match = lower-case objective text, note = short tag,
-- tip = longer line, hold = true: don't route back to the giver while
-- it's unfinished }, ... } for objectives no data places.
QuestData.ObjectiveNotes = {
    -- A Conqueror's Crown (Magram): the Conqueror's Helm comes out of a
    -- "Conqueror's Helm" object (580100) in a crypt in the Badlands
    -- (user; Wowhead Forever: object in Badlands, no coordinates).
    [92743] = {
        { match = "conqueror", note = "crypt, Badlands", hold = true,
          tip = "Loot it from the Conqueror's Helm in a crypt in the Badlands" },
    },
}

QuestData.ManualObjectives = {
    -- Sunken Treasure (665), Arathi Highlands: the escort ends in the cave
    -- at 35.7, 79.7 (user, in game, 2026-11-18). Carbonite's area sits at
    -- 33.5, 80.0, outside it.
    [665] = { [1] = { "Defend Professor Phizzlethorpe|1417|32|35.7|79.7" } },
}
