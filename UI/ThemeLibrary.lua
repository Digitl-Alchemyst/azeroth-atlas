---------------------------------------------------------------------------------------
-- Azeroth Atlas | UI/ThemeLibrary.lua
--
-- 2026-11-17 (user request: "I like all the map themes, let's gather up
-- all the assets for themes ... we can use later on to build out the
-- visual theming of our addon (final stage)").
--
-- A parts bin for that final stage. Map/BigMapThemes.lua already uses
-- the Palettes for the big map's theme picker. Everything
-- here comes from Leatrix Maps' map themes as shipped on WoW Forever
-- (Leatrix_Maps.lua, "Map theme" section of the simple map frame):
--
--   Palettes   the 15 themes' colour recipes, by Leatrix's own numbers
--   Builds     how the art-based themes (Blizzard, Glass, Handheld,
--              Retro TV) are put together, in words, for re-creating them
--   Art        the game's own textures and atlases those themes and its
--              icons use - in every client, nothing copied
--   Icons      Leatrix's own icon sheet, sliced into named files in
--              Gfx/Themes/Leatrix/ (Tools/slice_leatrix_sheet.py)
--   Fonts      Leatrix ships no font files; its text uses the game's
--              font objects at the sizes listed
--
-- Leatrix Maps' art is used with its author's permission (as with the
-- dungeon art and Gfx/Map/Leatrix_Maps.blp). Docs/Themes.md describes
-- each theme for picking between them.
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
AzerothAtlas.UI = AzerothAtlas.UI or {}

local THEMES = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Themes\\Leatrix\\"

AzerothAtlas.UI.ThemeLibrary = {

    -- Colours are 0-1 RGB(A). bgBottom / bgTop: the title bar and footer
    -- gradient. accent: title bar buttons and list borders. hover: menu
    -- row highlight (RGBA). A theme with `color` only uses Leatrix's
    -- "wash" recipe: title bar = a dark wash of the colour, accents =
    -- the colour itself, so every colour theme matches the others.
    Palettes = {
        { id = 1,  name = "Classic",  bgBottom = { 0.04, 0.04, 0.04 }, bgTop = { 0.09, 0.09, 0.09 },
          accent = { 0.45, 0.37, 0.20 }, hover = { 1, 1, 1, 0.12 } },
        { id = 2,  name = "Warm",     bgBottom = { 0.06, 0.04, 0.02 }, bgTop = { 0.12, 0.08, 0.045 },
          accent = { 0.55, 0.42, 0.22 }, hover = { 1, 0.85, 0.6, 0.14 } },
        { id = 3,  name = "Charcoal", bgBottom = { 0.05, 0.05, 0.06 }, bgTop = { 0.13, 0.13, 0.15 },
          accent = { 0.32, 0.36, 0.42 }, hover = { 0.75, 0.85, 1, 0.14 } },
        -- 2026-11-18: renamed from Leatrix's "Class colour" / "Glass" -
        -- the window skins already have a "Class Color" and a "Glass", and
        -- every theme can now go on either map (Map/BigMapThemes.lua).
        { id = 4,  name = "Class Tint", classColor = true },
        { id = 5,  name = "Pink",     color = { 1, 0.35, 0.70 } },
        { id = 6,  name = "Alliance", color = { 0.25, 0.50, 1 } },
        { id = 7,  name = "Horde",    color = { 0.90, 0.15, 0.10 } },
        { id = 8,  name = "Purple",   color = { 0.60, 0.30, 1 } },
        { id = 9,  name = "Teal",     color = { 0.10, 0.80, 0.75 } },
        { id = 10, name = "Green",    color = { 0.30, 0.85, 0.25 } },
        { id = 11, name = "Rainbow",  rainbow = true, bgBottom = { 0.04, 0.04, 0.04 }, bgTop = { 0.09, 0.09, 0.09 },
          accent = { 0.65, 0.40, 1 }, hover = { 1, 1, 1, 0.15 },
          -- left to right across the bar, drawn at 30% brightness
          rainbowColors = { { 1, 0.15, 0.15 }, { 1, 0.55, 0.10 }, { 1, 0.90, 0.15 },
                            { 0.25, 0.90, 0.30 }, { 0.20, 0.50, 1 }, { 0.65, 0.35, 1 } },
          rainbowShade = 0.30 },
        { id = 12, name = "Blizzard", blizzard = true, bgBottom = { 0, 0, 0 }, bgTop = { 0.08, 0.08, 0.08 },
          accent = { 1, 0.82, 0 }, hover = { 1, 1, 1, 0.15 } },
        { id = 13, name = "Frosted Glass", glass = true, bgBottom = { 0.10, 0.12, 0.16, 0.50 },
          bgTop = { 0.32, 0.37, 0.45, 0.40 }, accent = { 0.85, 0.90, 1 }, hover = { 1, 1, 1, 0.18 },
          icon = { 0.90, 0.94, 1 }, box = { 1, 1, 1, 0.22 },
          list = { 0.08, 0.10, 0.14, 0.75, 0.82, 0.92, 0.82 },          -- bg rgb, border rgb, bg alpha
          search = { { 0, 0, 0, 0.35 }, { 0, 0, 0, 0.55 } } },         -- normal, typing
        { id = 14, name = "Handheld", handheld = true, pads = { 96, 96, 18, 30 },   -- left, right, top, bottom
          bgBottom = { 0.07, 0.07, 0.09 }, bgTop = { 0.12, 0.115, 0.15 }, accent = { 0.80, 0.45, 0.70 },
          hover = { 0.90, 0.55, 0.80, 0.20 }, icon = { 0.88, 0.85, 0.94 },
          list = { 0.12, 0.11, 0.15, 0.62, 0.58, 0.72, 0.97 } },
        { id = 15, name = "Retro TV", tv = true, pads = { 12, 62, 12, 16 },
          bgBottom = { 0.04, 0.04, 0.04 }, bgTop = { 0.08, 0.08, 0.08 }, accent = { 0.80, 0.62, 0.30 },
          hover = { 1, 0.85, 0.55, 0.15 }, list = { 0.16, 0.10, 0.05, 0.80, 0.62, 0.30, 0.97 } },
    },

    -- How the art themes are built (all drawn from WHITE8X8 + the Art below).
    Builds = {
        Blizzard = "NineSliceUtil layout ButtonFrameTemplateNoPortrait around the map, centre piece hidden, "
            .. "bottom 4px drop shadow cropped; title bar and footer filled with UI-Background-Rock (tiled); "
            .. "lists filled with UI-Background-Rock tinted 0.63, 0.40, 0.23; title buttons 26px using the "
            .. "game's own button art. Fallback: DialogBox-Gold-Border backdrop, edge 32. "
            .. "Drawn for the big map in Map/BigMapThemes.lua.",
        Glass = "No frame background; 1-pixel white rim (alpha 0.55) round the frame; an 11px white sheen "
            .. "on top of the title bar (vertical gradient alpha 0 -> 0.12); see-through bars.",
        Rainbow = "Title bar split into 5 horizontal gradient segments through rainbowColors at "
            .. "rainbowShade brightness, plus a black vertical shade (alpha 0.45 -> 0) over it; list rows "
            .. "run through the rainbow top to bottom.",
        Handheld = "Map as a sideways games handheld: rounded charcoal plastic body (pads), dark screen "
            .. "surround with a red power light, D-pad left, A and B buttons and speaker holes right.",
        RetroTV = "Map as an old wooden TV: wood casing (pads) with a dark bezel; side panel with two knobs "
            .. "(ring 36px, metal face 30px gradient 0.28 -> 0.68, cap 10px, made round with "
            .. "TempPortraitAlphaMask), speaker grille and power light; scanlines every 3px (black, alpha "
            .. "0.13), dark vignette and glass glare over the screen; the power knob plays an off/on "
            .. "squeeze-to-a-dot animation.",
    },

    -- The game's own art the themes and Leatrix's icons use.
    Art = {
        White          = "Interface\\Buttons\\WHITE8X8",
        RoundMask      = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        Rock           = "Interface\\FrameGeneral\\UI-Background-Rock",
        GoldBorder     = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        Parchment      = "Interface\\ACHIEVEMENTFRAME\\UI-GuildAchievement-Parchment-Horizontal-Desaturated.png",
        Star           = "Interface\\Cooldown\\star4",
        Starburst      = "Interface\\Cooldown\\starburst",
        SwordGradient  = "Interface\\GLUES\\Models\\UI_MainMenu\\swordgradient2",
        Gear           = "Interface\\WorldMap\\Gear_64.png",
        HelpInfo       = "Interface\\COMMON\\help-i.blp",
        HelpBug        = "Interface\\HELPFRAME\\HelpIcon-Bug",
        TrackingBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
        PartyBlips     = "Interface\\MINIMAP\\partyraidblipsv2",
        Skull          = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
        ExpandArrow    = "Interface\\ChatFrame\\ChatFrameExpandArrow",
        ChatBackground = "Interface\\ChatFrame\\ChatFrameBackground",
        TitleHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
        MouseHilight   = "Interface\\Buttons\\UI-Common-MouseHilight",
        PageButtons    = "Interface\\Buttons\\UI-SpellbookIcon-",          -- ..PrevPage-Up etc.
        MinimizeButton = "Interface\\Buttons\\UI-Panel-MinimizeButton-",   -- ..Up/Down/Highlight/Disabled
        NineSliceLayout = "ButtonFrameTemplateNoPortrait",
        Atlases = {
            "Dungeon", "Raid", "TaxiNode_Alliance", "TaxiNode_Horde", "TaxiNode_Neutral",
            "MagePortalAlliance", "MagePortalHorde", "Vehicle-TempleofKotmogu-GreenBall",
            "Vehicle-TempleofKotmogu-CyanBall", "Garr_LevelUpgradeArrow", "UI-WorldMapArrow",
            "common-dropdown-a-button",
        },
        Icons = {
            "INV_Misc_Map_01", "INV_Misc_Bone_Skull_02", "INV_Misc_QuestionMark", "INV_Enchant_ShardBrilliantLarge",
            "Spell_Holy_HolyBolt", "Spell_Fire_Fireball02", "INV_Misc_Gem_Topaz_02", "INV_Misc_Gem_Sapphire_02",
            "INV_Misc_Gem_Ruby_02", "INV_Misc_Gem_Emerald_02", "INV_Misc_Gem_Diamond_02", "INV_Misc_Gem_Amethyst_02",
        },
    },

    -- Leatrix's own icon sheet, one file per piece (sizes in pixels).
    Icons = {
        Close          = THEMES .. "Close",            -- 32
        Maximize       = THEMES .. "Maximize",         -- 32
        Minimize       = THEMES .. "Minimize",         -- 32
        TravelAlliance = THEMES .. "TravelAlliance",   -- 32, blue
        TravelHorde    = THEMES .. "TravelHorde",      -- 32, red
        TravelNeutral  = THEMES .. "TravelNeutral",    -- 32, yellow
        DungeonRaid    = THEMES .. "DungeonRaid",      -- 32, green swirl
        ButtonBar      = THEMES .. "ButtonBar",        -- 128x32
        ButtonBarGlow  = THEMES .. "ButtonBarGlow",    -- 128x32
        DragonGold     = THEMES .. "DragonGold",       -- 128, elite-style pin frame
        DragonSilver   = THEMES .. "DragonSilver",     -- 128
        DragonGrey     = THEMES .. "DragonGrey",       -- 128
    },

    -- Font objects and sizes Leatrix's frames use (no font files shipped).
    Fonts = {
        Coordinates = { object = "GameFontNormalSmall", size = 8 },
        Labels      = { object = "GameFontNormal", size = 8 },
        Bar         = { object = "GameFontNormal", size = 13, flags = "OUTLINE" },
        Banner      = { object = "GameFontNormalHuge", size = 36, flags = "THICKOUTLINE" },
        Title       = { object = "GameFontNormalHuge", size = 52, flags = "THICKOUTLINE" },
        PageHead    = { object = "GameFontNormalLarge", size = 26 },
        PageText    = { object = "GameFontHighlight", size = 17 },
    },
}
