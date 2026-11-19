-- Azeroth Atlas | UI / StyleOptions
-- Build-order step 13 (2026-11-11): swappable single-texture icon
-- choices, explicit user request ("control what icons and art assets
-- are used for what"). Separate from UI/Skin.lua (which is a full
-- backdrop+color THEME, not a single icon) - these categories are
-- plain "pick one icon" swaps, each consumed by exactly one
-- MinimapEngine.lua icon.
--
-- Build-order step 14 (2026-11-11), same-day follow-up: "scrape all
-- of the leatrix icons... be able to swap those out, lets get some
-- alt icons for our player cursor too." Leatrix_Maps' real icon table
-- (POIIcons, Leatrix_Maps.lua:4055-4070) is mostly Blizzard ATLAS
-- strings (zero asset cost) plus 4 confirmed texcoord rectangles into
-- the one real sprite sheet it ships (Leatrix_Maps.blp, now promoted
-- from Gfx/Staged/ to Gfx/Map/ since it has a real consumer). An
-- option can now be one of three kinds:
--   { tex = "path" }                        -- plain texture (original)
--   { atlas = "AtlasName" }                 -- Blizzard atlas
--   { tex = "path", coords = {l,r,t,b} }     -- texcoord crop of a sheet
-- `GetOption`/`ApplyIconSpec`/`ApplyIcon` replace the old `GetTex` (it
-- only ever returned a plain string, which an atlas/crop option has
-- none of) - every MinimapEngine.lua call site, including the three
-- pre-existing categories, now goes through these instead, for one
-- consistent pattern addon-wide.

local AzerothAtlas = _G.AzerothAtlas
AzerothAtlas.UI = AzerothAtlas.UI or {}

local StyleOptions = {}
AzerothAtlas.UI.StyleOptions = StyleOptions

local MAP_GFX = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\"
local LEATRIX_SHEET = MAP_GFX .. "Leatrix_Maps"

-- Ordered list (not a map) - both for GetOption's lookup and so the
-- Style tab can render categories/options in a fixed, predictable
-- order (Lua's pairs() has none).
StyleOptions.Categories = {
    {
        key = "TrailArrow", label = "Trail Arrow",
        options = {
            { id = "Carbonite", label = "Gradient",   tex = MAP_GFX .. "IconArrowGrad" },
            { id = "HUDArrow",  label = "HUD",         tex = MAP_GFX .. "HUDArrow" },
            { id = "HUDChip",   label = "HUD Chip",    tex = MAP_GFX .. "HUDArrowChip" },
            { id = "HUDGloss",  label = "HUD Gloss",   tex = MAP_GFX .. "HUDArrowGloss" },
            { id = "HUDGlow",   label = "HUD Glow",    tex = MAP_GFX .. "HUDArrowGlow" },
            { id = "HUDNeon",   label = "HUD Neon",    tex = MAP_GFX .. "HUDArrowNeon" },
        },
    },
    {
        key = "GotoMarker", label = "Goto Marker",
        options = {
            { id = "Carbonite",  label = "Way Target", tex = MAP_GFX .. "IconWayTarget" },
            { id = "Circle",     label = "Circle",      tex = MAP_GFX .. "IconCircle" },
            { id = "CircleFade", label = "Circle Fade", tex = MAP_GFX .. "IconCircleFade" },
            { id = "CirclePlus", label = "Circle Plus", tex = MAP_GFX .. "IconCirclePlus" },
            { id = "Ring",       label = "Ring",        tex = MAP_GFX .. "IconRing" },
            { id = "QTarget",    label = "Q-Target",    tex = MAP_GFX .. "IconQTarget" },
        },
    },
    {
        key = "QuestIcon", label = "Quest Turn-In Icon",
        options = {
            { id = "Blizzard", label = "Blizzard", tex = "Interface\\GossipFrame\\ActiveQuestIcon" },
            { id = "Exclaim",  label = "Exclaim",   tex = MAP_GFX .. "IconExclaim" },
            { id = "ExclaimB", label = "Exclaim B", tex = MAP_GFX .. "IconExclaimB" },
            { id = "Question", label = "Question",  tex = MAP_GFX .. "IconQuestion" },
        },
    },
    -- Quest companion (2026-11-15): the two pin roles added alongside
    -- the turn-in icon above, and the routing arrow. Defaults are this
    -- addon's own bundled art rather than a Blizzard path - guessed
    -- Blizzard texture paths have been this project's most repeated bug,
    -- and these files are already proven to load (the goto marker and
    -- trail arrows come from the same folder). The objective options are
    -- all greyscale art, so they take the per-quest tint QuestPins.lua
    -- applies; the lighter ones (Circle, Ring) show it most vividly.
    {
        key = "QuestGiverIcon", label = "Quest Giver Icon",
        options = {
            { id = "Exclaim",  label = "Exclaim (default)", tex = MAP_GFX .. "IconExclaim" },
            { id = "ExclaimB", label = "Exclaim B",         tex = MAP_GFX .. "IconExclaimB" },
            { id = "Blizzard", label = "Blizzard",          tex = "Interface\\GossipFrame\\AvailableQuestIcon" },
        },
    },
    {
        key = "QuestObjectiveIcon", label = "Quest Objective Icon",
        options = {
            { id = "QTarget",    label = "Q-Target (default)", tex = MAP_GFX .. "IconQTarget" },
            { id = "Circle",     label = "Circle",             tex = MAP_GFX .. "IconCircle" },
            { id = "CircleFade", label = "Circle Fade",        tex = MAP_GFX .. "IconCircleFade" },
            { id = "Ring",       label = "Ring",               tex = MAP_GFX .. "IconRing" },
        },
    },
    -- Carbonite's own five arrow styles (HUDEngine.lua's HUD.TexNames:
    -- "", "Chip", "Gloss", "Glow", "Neon").
    {
        key = "HUDArrow", label = "Quest Arrow",
        options = {
            { id = "Plain", label = "Plain (default)", tex = MAP_GFX .. "HUDArrow" },
            { id = "Chip",  label = "Chip",            tex = MAP_GFX .. "HUDArrowChip" },
            { id = "Gloss", label = "Gloss",           tex = MAP_GFX .. "HUDArrowGloss" },
            { id = "Glow",  label = "Glow",            tex = MAP_GFX .. "HUDArrowGlow" },
            { id = "Neon",  label = "Neon",            tex = MAP_GFX .. "HUDArrowNeon" },
        },
    },
    -- Build-order step 14: real citations below are all from
    -- Leatrix_Maps.lua's own POIIcons table (:4055-4070) and the real
    -- texcoord rectangles its SetupIcon (:4112-4126) crops from
    -- Leatrix_Maps.blp - confirmed this session, not guessed.
    {
        key = "DungeonEntrance", label = "Dungeon Entrance Icon",
        options = {
            { id = "Key",      label = "Key (default)",       tex = "Interface\\Icons\\INV_Misc_Key_03" },
            { id = "Dungeon",  label = "Dungeon (Leatrix)",    atlas = "Dungeon" },
            { id = "Raid",     label = "Raid (Leatrix)",       atlas = "Raid" },
            { id = "Dunraid",  label = "Dungeon/Raid (Leatrix)", tex = LEATRIX_SHEET, coords = { 0.375, 0.5, 0.375, 0.5 } },
        },
    },
    {
        key = "ZoneTransition", label = "Zone Transition Icon",
        options = {
            { id = "Map",      label = "Map (default)",         tex = "Interface\\Icons\\INV_Misc_Map_01" },
            { id = "Arrow",    label = "Exit Arrow (Leatrix)",   atlas = "Garr_LevelUpgradeArrow" },
            { id = "BoatA",    label = "Boat - Alliance (Leatrix)", tex = LEATRIX_SHEET, coords = { 0, 0.125, 0.375, 0.5 } },
            { id = "BoatH",    label = "Boat - Horde (Leatrix)",    tex = LEATRIX_SHEET, coords = { 0.125, 0.25, 0.375, 0.5 } },
            { id = "Travel",   label = "Travel (Leatrix)",          tex = LEATRIX_SHEET, coords = { 0.25, 0.375, 0.375, 0.5 } },
            { id = "PortalA",  label = "Portal - Alliance (Leatrix)", atlas = "MagePortalAlliance" },
            { id = "PortalH",  label = "Portal - Horde (Leatrix)",    atlas = "MagePortalHorde" },
        },
    },
    {
        key = "FlightMaster", label = "Flight Master Icon",
        options = {
            { id = "Tracking", label = "Tracking Icon (default)", tex = "Interface\\MINIMAP\\TRACKING\\FlightMaster" },
            -- 2026-11-17 (user request): one set instead of three single
            -- icons - each flight master shows its own faction's node
            -- (TaxiNodeInfo.faction: 0 neutral, 1 Horde, 2 Alliance).
            -- See StyleOptions:ForFaction.
            { id = "Faction", label = "Taxi Nodes by faction (Leatrix)", atlas = "TaxiNode_Neutral",
              variants = {
                  [0] = { atlas = "TaxiNode_Neutral" },
                  [1] = { atlas = "TaxiNode_Horde" },
                  [2] = { atlas = "TaxiNode_Alliance" },
              } },
        },
        -- The three single-faction choices this set replaced.
        renamed = { Alliance = "Faction", Horde = "Faction", Neutral = "Faction" },
    },
    {
        key = "SpiritHealer", label = "Spirit Healer Icon",
        options = {
            { id = "Resurrection", label = "Resurrection (default)", tex = "Interface\\Icons\\Spell_Holy_Resurrection" },
            { id = "GreenBall",    label = "Green Ball (Leatrix)",    atlas = "Vehicle-TempleofKotmogu-GreenBall" },
        },
    },
    -- Carbonite's IconPlyr{P,F,G,Z}.tga were built for its OTHER-
    -- player social/Spy tracking feature (plain/marked-foe/marked-pal/
    -- generic zone-presence) - reused here purely as alternate dot
    -- shapes for the LOCAL player's own marker, so labeled by their
    -- Carbonite origin rather than a claimed color (the swatch preview
    -- shows the real look). Combat-tinted "C" siblings deliberately
    -- left out - that's a dynamic state tint, not a static style pick.
    {
        key = "PlayerMarker", label = "Player Marker",
        options = {
            { id = "Arrow",    label = "Arrow (default)",   tex = "Interface\\Minimap\\MinimapArrow" },
            { id = "DotPlain", label = "Dot (Plain)",       tex = MAP_GFX .. "IconPlyrP" },
            { id = "DotFoe",   label = "Dot (Foe style)",   tex = MAP_GFX .. "IconPlyrF" },
            { id = "DotPal",   label = "Dot (Pal style)",   tex = MAP_GFX .. "IconPlyrG" },
            { id = "DotZone",  label = "Dot (Zone style)",  tex = MAP_GFX .. "IconPlyrZ" },
        },
    },
}

local byKey = {}
for _, cat in ipairs(StyleOptions.Categories) do
    byKey[cat.key] = cat
end

-- Resolves the currently-saved choice for `key` to its full option
-- table (not just a texture string, since an atlas/crop option has
-- no plain `tex` of its own) - falls back to that category's first
-- (default) option if the saved id is missing or stale (e.g. from a
-- removed option in a future version). Callers can compare the
-- returned table by REFERENCE as a diff-cache key, since each
-- category's option tables are static and reused, never recreated.
function StyleOptions:GetOption(key)
    local cat = byKey[key]
    if not cat then return nil end

    local sv = AzerothAtlas.db and AzerothAtlas.db.profile.Style
    local chosenId = sv and sv[key]
    if cat.renamed and cat.renamed[chosenId] then chosenId = cat.renamed[chosenId] end

    for _, opt in ipairs(cat.options) do
        if opt.id == chosenId then return opt end
    end
    return cat.options[1]
end

-- The one place that knows how to realize an option spec onto a
-- Texture object - every consumer (MinimapEngine.lua's live icons,
-- SettingsWindow.lua's swatch previews) goes through this so the
-- atlas-vs-texcoord-vs-plain branching exists exactly once.
local FALLBACK_TC = { 0.08, 0.92, 0.08, 0.92 }   -- an icon's border trimmed off

function StyleOptions:ApplyIconSpec(tex, spec)
    if not spec then return end

    -- 2026-11-17: an atlas this client doesn't have falls back to the
    -- spec's own `fallback` texture (Leatrix's recipe), else a question
    -- mark - never a blank icon.
    if spec.atlas and C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(spec.atlas) then
        tex:SetTexture(spec.fallback or "Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex.azaAtlas, tex.azaTC = nil, FALLBACK_TC
    elseif spec.atlas then
        -- Explicit `false`: keep the icon's own fixed on-screen size
        -- (SERVICE_ICON_SIZE etc.) rather than the atlas's native one.
        tex:SetAtlas(spec.atlas, false)
        -- 2026-11-17: no SetTexCoord after SetAtlas - the atlas sets its
        -- own coordinates within its file, and a reset to 0-1 would show
        -- the whole file. azaAtlas / azaTC tell MinimapEngine:ClipFrameW
        -- the same thing.
        tex.azaAtlas, tex.azaTC = spec.atlas, nil
    elseif spec.coords then
        tex:SetTexture(spec.tex)
        tex:SetTexCoord(spec.coords[1], spec.coords[2], spec.coords[3], spec.coords[4])
        tex.azaAtlas, tex.azaTC = nil, spec.coords
    else
        tex:SetTexture(spec.tex)
        -- Reset in case this texture object last held a cropped icon.
        tex:SetTexCoord(0, 1, 0, 1)
        tex.azaAtlas, tex.azaTC = nil, nil
    end
end

-- Convenience wrapper for the simple single-value call sites (Trail
-- Arrow, Goto Marker, Player Marker) that just want "the current
-- choice for this key, applied."
function StyleOptions:ApplyIcon(tex, key)
    self:ApplyIconSpec(tex, self:GetOption(key))
end

function StyleOptions:GetChoice(key)
    local sv = AzerothAtlas.db and AzerothAtlas.db.profile.Style
    local cat = byKey[key]
    local id = sv and sv[key]
    if cat and cat.renamed and cat.renamed[id] then id = cat.renamed[id] end
    return id or (cat and cat.options[1].id)
end

-- The spec for one faction out of an option that is a set (`variants`,
-- keyed 0 neutral / 1 Horde / 2 Alliance); a plain option is returned
-- as it is. The variant tables are static, so reference compares still
-- work as a diff-cache key.
function StyleOptions:ForFaction(spec, faction)
    if spec and spec.variants then
        return spec.variants[faction] or spec.variants[0] or spec
    end
    return spec
end

function StyleOptions:SetChoice(key, id)
    if not byKey[key] then return end
    AzerothAtlas.db.profile.Style = AzerothAtlas.db.profile.Style or {}
    AzerothAtlas.db.profile.Style[key] = id

    local MinimapEngine = AzerothAtlas.Modules.Map and AzerothAtlas.Modules.Map.MinimapEngine
    if MinimapEngine and MinimapEngine.ApplyStyleChange then
        MinimapEngine:ApplyStyleChange(key)
    end
end
