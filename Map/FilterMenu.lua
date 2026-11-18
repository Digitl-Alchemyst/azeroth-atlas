-- Alchemy GPS | Map / FilterMenu
-- Build-order step 9k (2026-11-10): a "Filter" button on the map
-- window's title bar that opens a checklist menu - explicit user
-- request, modeled on "the normal Blizzard one" (a button that opens
-- a dropdown-style list of checkable icon categories) but NOT built
-- from Blizzard's own dropdown system (UIDropDownMenu etc.) at all -
-- same reasoning MapContextMenu.lua already gave for not porting
-- Carbonite's own Nx.Menu: a large, deeply-coupled system for what
-- this addon actually needs (a handful of checkbox rows). Built on the
-- exact same plain-Blizzard-frame-primitives pattern MapContextMenu.lua
-- already established (a bordered popup frame, OnUpdate-based outside-
-- click dismiss, one row per item) - just checkboxes instead of
-- sliders, and anchored to the button that opened it instead of the
-- cursor position (this is a toolbar dropdown, not a right-click menu).
--
-- First five filters, exactly as requested: the gathering-node field's
-- profession-gated categories (herb/mining/fish) as ONE combined
-- toggle ("Gathering Nodes"), Treasure as its OWN separate toggle (not
-- profession-gated, explicit user ask to split it out), then the three
-- static service-icon categories (Flight Masters/Innkeepers/
-- Mailboxes) each as their own toggle. Quest-giver icons are NOT in
-- this list - not asked for, future scope if wanted later.
--
-- Build-order step 9l (2026-11-10): four more rows, explicit user
-- request - Bankers (same shape as Innkeeper/Mailbox), Dungeon/Raid
-- Entrances (one combined toggle, user asked for them as a single
-- line item, not two), Zone Transitions (boats/zeppelins/trams/
-- portals/plain borders, also one combined toggle), and Guard
-- Directions (the live C_GossipInfo flag - see MinimapEngine.lua's own
-- header comment on GUARDFLAG_TEX for why this one specifically isn't
-- confirmed to render anything yet).
--
-- Build-order step 11 (2026-11-11): Spirit Healers, explicit user
-- request - same shape as Mailbox/Innkeeper/Banker (a static
-- GuideData category), so it falls into SetFilterOn's existing
-- RefreshServiceIcons/UpdateServiceIcons branch below with no new
-- code there.
--
-- 2026-11-11, same-day follow-up: Auctioneers - user noticed they
-- were missing from the map entirely (there had never been a
-- SERVICE_ICON_TEX/GuideData entry for this kind at all, unlike every
-- other row here). Same shape as Banker, same "no new code needed
-- below" situation as Spirit Healer above.
--
-- Persisted as AlchemyGPS.db.profile.MapFilters[key] (true/false/nil -
-- nil/missing means "on", same "absent means default" convention
-- MinimapWindow.lua's AutoFollow checkbox already uses, so a brand
-- new filter key added later doesn't need a migration to default
-- everyone's existing saved profile to visible). Toggling a row calls
-- straight into MinimapEngine's own Refresh*/Update* pairs immediately
-- (gathering/treasure share RefreshGatherIcons; the three service
-- kinds share RefreshServiceIcons) rather than waiting for the next
-- zone change or tick, so the checkbox has instant visual effect.

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local FilterMenu = {}
AlchemyGPS.Modules.Map.FilterMenu = FilterMenu

-- Order matches the user's own request order.
local FILTERS = {
    { key = "Gathering",       label = "Gathering Nodes" },
    { key = "Treasure",        label = "Treasure" },
    { key = "FlightMaster",    label = "Flight Masters" },
    { key = "Innkeeper",       label = "Innkeepers" },
    { key = "Mailbox",         label = "Mailboxes" },
    { key = "Auctioneer",      label = "Auctioneers" },
    { key = "Banker",          label = "Bankers" },
    { key = "DungeonEntrance", label = "Dungeon/Raid Entrances" },
    { key = "ZoneTransition",  label = "Zone Transitions" },
    { key = "Boat",            label = "Boats" },
    { key = "Zeppelin",        label = "Zeppelins" },
    -- 2026-11-18 (user request, from Leatrix Maps): portals and trams
    -- out of Zone Transitions into rows of their own, and a switch for
    -- the other faction's flight masters, boats, zeppelins, portals and
    -- trams - off unless turned on (default = false).
    { key = "Portal",          label = "Portals" },
    { key = "Tram",            label = "Trams" },
    { key = "OpposingFaction", label = "Other faction's travel", default = false },
    { key = "GuardFlag",       label = "Guard Directions" },
    { key = "SpiritHealer",    label = "Spirit Healers" },
    -- Quest companion (2026-11-15): the three quest pin roles
    -- (Quest/QuestPins.lua). Turn-in markers existed before this but
    -- had no filter row of their own.
    { key = "QuestGiver",      label = "Quest Givers" },
    { key = "QuestObjective",  label = "Quest Objectives" },
    { key = "QuestTurnIn",     label = "Quest Turn-ins" },
}

local QUEST_FILTERS = { QuestGiver = true, QuestObjective = true, QuestTurnIn = true }

local ROW_HEIGHT = 22
-- Widened from 170 (build-order step 9l) - "Dungeon/Raid Entrances" is
-- longer than any of the first five labels and was getting clipped.
local MENU_WIDTH = 190

local menu

-- A row's state when it was never changed: on, unless the row says
-- default = false.
local DEFAULT_OFF = {}
for _, f in ipairs(FILTERS) do
    if f.default == false then DEFAULT_OFF[f.key] = true end
end

local function IsFilterOn(key)
    local filters = AlchemyGPS.db and AlchemyGPS.db.profile and AlchemyGPS.db.profile.MapFilters
    local v = filters and filters[key]
    if v == nil then return not DEFAULT_OFF[key] end
    return v ~= false
end

local function SetFilterOn(key, on)
    if not (AlchemyGPS.db and AlchemyGPS.db.profile) then return end
    AlchemyGPS.db.profile.MapFilters = AlchemyGPS.db.profile.MapFilters or {}
    AlchemyGPS.db.profile.MapFilters[key] = on

    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    -- .Frm: Settings > Map can change a filter before the map window
    -- has ever been opened, when there are no icon pools yet - the
    -- first open reads the saved filters anyway.
    if not MinimapEngine or not MinimapEngine.Frm then return end
    if key == "Gathering" or key == "Treasure" then
        MinimapEngine:RefreshGatherIcons()
        MinimapEngine:UpdateGatherIcons()
    elseif QUEST_FILTERS[key] then
        MinimapEngine:RefreshQuestIcons()
        MinimapEngine:UpdateQuestIcons()
    else
        MinimapEngine:RefreshServiceIcons()
        MinimapEngine:UpdateServiceIcons()
    end
end

-- 2026-11-16: the map's title-bar Filter button is gone - these same
-- rows now live in Settings > Map, which reads them from here so the
-- list and its refresh behavior stay in one place.
FilterMenu.FILTERS = FILTERS
FilterMenu.IsFilterOn = IsFilterOn
FilterMenu.SetFilterOn = SetFilterOn

local function create()
    if menu then return menu end

    local height = 16 + #FILTERS * ROW_HEIGHT
    menu = CreateFrame("Frame", "AlchemyGPSFilterMenu", UIParent, "BackdropTemplate")
    menu:SetSize(MENU_WIDTH, height)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:Hide()

    menu.rows = {}
    for i, f in ipairs(FILTERS) do
        local y = -10 - (i - 1) * ROW_HEIGHT

        -- Same stock Blizzard checkbox textures MinimapWindow.lua's
        -- own AutoFollow checkbox already uses - an established
        -- convention in this project, not a new asset.
        local cb = CreateFrame("CheckButton", nil, menu)
        cb:SetSize(14, 14)
        cb:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

        local label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        label:SetText(f.label)

        local key = f.key
        cb:SetScript("OnClick", function(btn)
            SetFilterOn(key, btn:GetChecked() and true or false)
        end)

        menu.rows[key] = cb
    end

    -- Same outside-click dismiss pattern as MapContextMenu.lua (no
    -- intercepting frame - see that file's own header comment for why
    -- a full-screen clickable overlay tripped a taint warning there).
    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() then
            FilterMenu:Close()
        end
    end)

    return menu
end

-- leftAlign (2026-11-17): open down and to the right of the anchor (the
-- big map's toolbar button sits at the map's left edge).
function FilterMenu:Open(anchorFrame, leftAlign)
    local m = create()

    for _, f in ipairs(FILTERS) do
        m.rows[f.key]:SetChecked(IsFilterOn(f.key))
    end

    m:ClearAllPoints()
    if leftAlign then
        m:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    else
        m:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -4)
    end
    m:Show()
end

function FilterMenu:Close()
    if not menu then return end
    menu:Hide()
end

function FilterMenu:IsShown()
    return menu ~= nil and menu:IsShown()
end

function FilterMenu:Toggle(anchorFrame, leftAlign)
    if self:IsShown() then
        self:Close()
    else
        self:Open(anchorFrame, leftAlign)
    end
end
