---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/Data/GatherNodeInfo.lua
--
-- Build-order step 9f (2026-11-10): per-species name/icon/skill-level
-- reference data for the gathering-node field (MinimapEngine.lua's
-- RefreshGatherIcons/UpdateGatherIcons), replacing the one-generic-
-- icon-per-category placeholder with the real per-species icon the
-- user asked for (copper vein -> copper icon, silverleaf -> silverleaf
-- icon, etc.) plus a hover tooltip (name + required skill level,
-- colored relative to the player's own current skill).
--
-- Static reference data only - this is read like any other file in
-- Map/Data/, with ZERO runtime dependency on GatherMate2 or Carbonite
-- being installed/enabled (same stance as GatherHerb/Mining/Fish/
-- Treasure.lua). The icon/name pairs were ported from GatherMate2's
-- own Constants.lua (its node_textures + node_ids tables - read as
-- static reference data, not called into at runtime) since that's the
-- authoritative, already-correct source for "which texture goes with
-- which node ID" - re-deriving it from scratch would just reproduce
-- the same answer with more risk of typos. The icon files themselves
-- are bundled in this addon (Gfx\Gather\, copied from GatherMate2's
-- Artwork folder). They used to be loaded straight out of GatherMate2's
-- own folder, which broke the moment GatherMate2 was uninstalled from
-- the live client (2026-11-16): a missing texture file draws nothing,
-- so only the black backdrop square behind each icon showed.
--
-- Scoped to exactly the species IDs actually present in this server's
-- own zone data (Map/Data/Gather{Herb,Mining,Fish,Treasure}.lua) -
-- confirmed by grepping those files for their distinct node IDs. All
-- of it turned out to be vanilla-era content only (Herb 401-431, Mine
-- 201-219, no BC/Wrath+ IDs at all), which is what made hand-porting
-- this tractable in one pass.
--
-- Skill-level requirements (the `level` field, Herb/Mine only - see
-- below) are well-documented classic WoW Herbalism/Mining breakpoints,
-- not sourced from any addon (GatherMate2 doesn't track this at all -
-- it's a pure position tracker). The three Mining entries with real
-- quest/reputation gating on top of a skill floor (Dark Iron Deposit,
-- Lesser Bloodstone Deposit, Incendicite Mineral Vein - 217/218/219,
-- all Silithus-war-effort/Blackrock-Depths-questline resources) use a
-- best-effort approximate skill floor since this is a cosmetic tooltip
-- feature, not a hard gameplay gate - adjust if found wrong in practice.
--
-- Fish and Treasure have no `level` field at all: classic fishing has
-- no hard skill gate (Fishing skill affects catch chance/quality, not
-- whether you can click the pool), and Treasure nodes are plain world
-- loot, not tied to any profession - MinimapEngine.lua's tooltip code
-- treats a missing `level` as "gold, no level" rather than red/can't-
-- harvest, per the user's own explicit direction.
---------------------------------------------------------------------------------------

local ICON = "Interface\\AddOns\\AlchemyGPS\\Gfx\\Gather\\"

AlchemyGPSGatherNodeInfo = {

    Herb = {
        [401] = { name = "Peacebloom",           level = 1,   tex = ICON.."Herb\\peacebloom.tga" },
        [402] = { name = "Silverleaf",            level = 1,   tex = ICON.."Herb\\silverleaf.tga" },
        [403] = { name = "Earthroot",             level = 15,  tex = ICON.."Herb\\earthroot.tga" },
        [404] = { name = "Mageroyal",             level = 50,  tex = ICON.."Herb\\mageroyal.tga" },
        [405] = { name = "Briarthorn",            level = 70,  tex = ICON.."Herb\\briarthorn.tga" },
        [407] = { name = "Stranglekelp",          level = 85,  tex = ICON.."Herb\\stranglekelp.tga" },
        [408] = { name = "Bruiseweed",            level = 100, tex = ICON.."Herb\\bruiseweed.tga" },
        [409] = { name = "Wild Steelbloom",       level = 115, tex = ICON.."Herb\\wild_steelbloom.tga" },
        [410] = { name = "Grave Moss",            level = 120, tex = ICON.."Herb\\grave_moss.tga" },
        [411] = { name = "Kingsblood",            level = 125, tex = ICON.."Herb\\kingsblood.tga" },
        [412] = { name = "Liferoot",              level = 150, tex = ICON.."Herb\\liferoot.tga" },
        [413] = { name = "Fadeleaf",              level = 160, tex = ICON.."Herb\\fadeleaf.tga" },
        [414] = { name = "Goldthorn",             level = 170, tex = ICON.."Herb\\goldthorn.tga" },
        [415] = { name = "Khadgar's Whisker",     level = 185, tex = ICON.."Herb\\khadgars_whisker.tga" },
        [416] = { name = "Wintersbite",           level = 195, tex = ICON.."Herb\\wintersbite.tga" },
        [417] = { name = "Firebloom",             level = 205, tex = ICON.."Herb\\firebloom.tga" },
        [418] = { name = "Purple Lotus",          level = 210, tex = ICON.."Herb\\purple_lotus.tga" },
        [420] = { name = "Arthas' Tears",         level = 220, tex = ICON.."Herb\\arthas_tears.tga" },
        [421] = { name = "Sungrass",              level = 230, tex = ICON.."Herb\\sungrass.tga" },
        [422] = { name = "Blindweed",             level = 235, tex = ICON.."Herb\\blindweed.tga" },
        [423] = { name = "Ghost Mushroom",        level = 245, tex = ICON.."Herb\\ghost_mushroom.tga" },
        [424] = { name = "Gromsblood",            level = 250, tex = ICON.."Herb\\gromsblood.tga" },
        [425] = { name = "Golden Sansam",         level = 260, tex = ICON.."Herb\\golden_sansam.tga" },
        [426] = { name = "Dreamfoil",             level = 270, tex = ICON.."Herb\\dreamfoil.tga" },
        [427] = { name = "Mountain Silversage",   level = 280, tex = ICON.."Herb\\mountain_silversage.tga" },
        [428] = { name = "Plaguebloom",           level = 285, tex = ICON.."Herb\\plaguebloom.tga" },
        [429] = { name = "Icecap",                level = 290, tex = ICON.."Herb\\icecap.tga" },
        [431] = { name = "Black Lotus",           level = 300, tex = ICON.."Herb\\black_lotus.tga" },
    },

    Mine = {
        [201] = { name = "Copper Vein",                    level = 1,   tex = ICON.."Mine\\copper.tga" },
        [202] = { name = "Tin Vein",                        level = 65,  tex = ICON.."Mine\\tin.tga" },
        [203] = { name = "Iron Deposit",                    level = 125, tex = ICON.."Mine\\iron.tga" },
        [204] = { name = "Silver Vein",                     level = 75,  tex = ICON.."Mine\\silver.tga" },
        [205] = { name = "Gold Vein",                       level = 155, tex = ICON.."Mine\\gold.tga" },
        [206] = { name = "Mithril Deposit",                 level = 175, tex = ICON.."Mine\\mithril.tga" },
        [207] = { name = "Ooze Covered Mithril Deposit",    level = 175, tex = ICON.."Mine\\mithril.tga" },
        [208] = { name = "Truesilver Deposit",              level = 230, tex = ICON.."Mine\\truesilver.tga" },
        [209] = { name = "Ooze Covered Silver Vein",        level = 75,  tex = ICON.."Mine\\silver.tga" },
        [210] = { name = "Ooze Covered Gold Vein",          level = 155, tex = ICON.."Mine\\gold.tga" },
        [211] = { name = "Ooze Covered Truesilver Deposit", level = 230, tex = ICON.."Mine\\truesilver.tga" },
        [212] = { name = "Ooze Covered Rich Thorium Vein",  level = 275, tex = ICON.."Mine\\rich_thorium.tga" },
        [213] = { name = "Ooze Covered Thorium Vein",       level = 230, tex = ICON.."Mine\\thorium.tga" },
        [214] = { name = "Small Thorium Vein",              level = 230, tex = ICON.."Mine\\thorium.tga" },
        [215] = { name = "Rich Thorium Vein",               level = 275, tex = ICON.."Mine\\rich_thorium.tga" },
        -- Approximate skill floor (also quest/rep-gated in real content, see header).
        [217] = { name = "Dark Iron Deposit",               level = 230, tex = ICON.."Mine\\darkiron.tga" },
        [218] = { name = "Lesser Bloodstone Deposit",       level = 230, tex = ICON.."Mine\\blood_iron.tga" },
        [219] = { name = "Incendicite Mineral Vein",        level = 230, tex = ICON.."Mine\\darkiron.tga" },
    },

    -- No `level` field - see header (classic fishing has no hard skill gate).
    Fish = {
        [101] = { name = "Floating Wreckage",                    tex = ICON.."Fish\\treasure.tga" },
        [103] = { name = "Floating Debris",                      tex = ICON.."Fish\\debris.tga" },
        [105] = { name = "Firefin Snapper School",                tex = ICON.."Fish\\firefin.tga" },
        [106] = { name = "Greater Sagefish School",               tex = ICON.."Fish\\greater_sagefish.tga" },
        [107] = { name = "Oily Blackmouth School",                tex = ICON.."Fish\\oilyblackmouth.tga" },
        [108] = { name = "Sagefish School",                       tex = ICON.."Fish\\sagefish.tga" },
        [109] = { name = "School of Deviate Fish",                tex = ICON.."Fish\\firefin.tga" },
        [110] = { name = "Stonescale Eel Swarm",                  tex = ICON.."Fish\\eel.tga" },
        [112] = { name = "Highland Mixed School",                 tex = ICON.."Fish\\fish_hook.tga" },
        [113] = { name = "Pure Water",                            tex = ICON.."Fish\\purewater.tga" },
        [114] = { name = "Bluefish School",                       tex = ICON.."Fish\\bluefish.tga" },
        [115] = { name = "Feltail School",                        tex = ICON.."Fish\\feltail.tga" },
        [116] = { name = "Mudfish School",                        tex = ICON.."Fish\\mudfish.tga" },
        [117] = { name = "School of Darter",                      tex = ICON.."Fish\\darter.tga" },
        [118] = { name = "Sporefish School",                      tex = ICON.."Fish\\sporefish.tga" },
        [119] = { name = "Steam Pump Flotsam",                    tex = ICON.."Fish\\steampump.tga" },
        [120] = { name = "School of Tastyfish",                   tex = ICON.."Fish\\net.tga" },
        [121] = { name = "Borean Man O' War School",              tex = ICON.."Fish\\manowar.tga" },
        [122] = { name = "Deep Sea Monsterbelly School",          tex = ICON.."Fish\\net.tga" },
        [123] = { name = "Dragonfin Angelfish School",            tex = ICON.."Fish\\anglefish.tga" },
        [124] = { name = "Fangtooth Herring School",              tex = ICON.."Fish\\herring.tga" },
        [125] = { name = "Floating Wreckage Pool",                tex = ICON.."Fish\\treasure.tga" },
        [126] = { name = "Glacial Salmon School",                 tex = ICON.."Fish\\salmon.tga" },
        [127] = { name = "Glassfin Minnow School",                tex = ICON.."Fish\\minnow.tga" },
        [128] = { name = "Imperial Manta Ray School",             tex = ICON.."Fish\\manta.tga" },
        [129] = { name = "Moonglow Cuttlefish School",            tex = ICON.."Fish\\bonescale.tga" },
        [130] = { name = "Musselback Sculpin School",             tex = ICON.."Fish\\musselback.tga" },
        [131] = { name = "Nettlefish School",                     tex = ICON.."Fish\\nettlefish.tga" },
        [133] = { name = "Schooner Wreckage",                     tex = ICON.."Fish\\treasure.tga" },
        [134] = { name = "Waterlogged Wreckage Pool",             tex = ICON.."Fish\\treasure.tga" },
        [135] = { name = "Bloodsail Wreckage Pool",               tex = ICON.."Fish\\treasure.tga" },
        [136] = { name = "Mixed Ocean School",                    tex = ICON.."Fish\\fish_hook.tga" },
        [137] = { name = "Lesser Oily Blackmouth School",         tex = ICON.."Fish\\oilyblackmouth.tga" },
        [138] = { name = "Sparse Oily Blackmouth School",         tex = ICON.."Fish\\oilyblackmouth.tga" },
        [139] = { name = "Abundant Oily Blackmouth School",       tex = ICON.."Fish\\oilyblackmouth.tga" },
        [140] = { name = "Teeming Oily Blackmouth School",        tex = ICON.."Fish\\oilyblackmouth.tga" },
        [143] = { name = "Abundant Firefin Snapper School",       tex = ICON.."Fish\\firefin.tga" },
        [144] = { name = "Teeming Firefin Snapper School",        tex = ICON.."Fish\\firefin.tga" },
    },

    -- No `level` field - plain world loot, not tied to any profession.
    Treasure = {
        [501] = { name = "Giant Clam",                 tex = ICON.."Treasure\\clam.tga" },
        [502] = { name = "Battered Chest",              tex = ICON.."Treasure\\chest.tga" },
        [504] = { name = "Solid Chest",                 tex = ICON.."Treasure\\chest.tga" },
        [506] = { name = "Large Solid Chest",           tex = ICON.."Treasure\\chest.tga" },
        [508] = { name = "Buccaneer's Strongbox",       tex = ICON.."Treasure\\chest.tga" },
        [509] = { name = "Large Mithril Bound Chest",   tex = ICON.."Treasure\\chest.tga" },
        -- 511/513: no icon in GatherMate2's own table either - falls back to the generic bag icon.
        [511] = { name = "Un'Goro Dirt Pile" },
        [512] = { name = "Bloodpetal Sprout",           tex = ICON.."Treasure\\sprout.tga" },
        [513] = { name = "Blood of Heroes" },
        [514] = { name = "Practice Lockbox",            tex = ICON.."Treasure\\footlocker.tga" },
        [515] = { name = "Battered Footlocker",         tex = ICON.."Treasure\\footlocker.tga" },
        [516] = { name = "Waterlogged Footlocker",      tex = ICON.."Treasure\\footlocker.tga" },
        [517] = { name = "Dented Footlocker",           tex = ICON.."Treasure\\footlocker.tga" },
        [518] = { name = "Mossy Footlocker",            tex = ICON.."Treasure\\footlocker.tga" },
        [519] = { name = "Scarlet Footlocker",          tex = ICON.."Treasure\\footlocker.tga" },
    },

}
