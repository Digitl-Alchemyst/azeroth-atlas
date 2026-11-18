-- Alchemy GPS | Map / MapContextMenu
-- Right-click popup menu for the map window (wired from
-- MinimapEngine:OnMouseUp's RightButton branch). Not a port -
-- Carbonite's own menu system (Nx.Menu, Modules/UI/UIEngine.lua) is
-- thousands of lines deeply coupled to its own options schema; porting
-- it for one slider would be a large, disproportionate undertaking.
-- Built instead on plain Blizzard frame primitives, the same way
-- Settings/SettingsWindow.lua already does for this addon's other
-- small UI - structured as a list of rows so later items are just
-- another row, not a rewrite.
--
-- Row 1: a brightness slider for the static world-art tile background
-- (MinimapEngine:MoveZoneTiles's own texture:SetVertexColor call - see
-- that function's header comment for why this is "brightness," allowed
-- above 1, rather than plain 0-1 alpha transparency). Persisted as
-- AlchemyGPS.db.profile.BackgndBrightness, applied live to
-- MinimapEngine.BackgndAlpha on every slider move.
--
-- Row 2 (build-order step 9g, 2026-11-10): an opacity slider for the
-- gathering-node icons (MinimapEngine:UpdateGatherIcons's own
-- texture:SetAlpha call) - plain 0-1 transparency multiplied on top of
-- the existing near/dimmed distinction, not a brightness overlay like
-- row 1, so it stays capped at 100%. Persisted as
-- AlchemyGPS.db.profile.GatherIconOpacity, applied live to
-- MinimapEngine.GatherOpacity on every slider move.
--
-- Row 3 (build-order step 9h, 2026-11-10, same "can barely see them"
-- visibility pass as row 2's dim-ratio/backdrop fixes): a size slider
-- for the same icons, 50%-300% of their base size
-- (MinimapEngine.lua's GATHER_ICON_SIZE). Allowed above 100% - unlike
-- row 1/2, making these bigger than their natural size is exactly the
-- point. Persisted as AlchemyGPS.db.profile.GatherIconScale, applied
-- live to MinimapEngine.GatherIconScale on every slider move.
--
-- Row 4 (build-order step 9i, 2026-11-10, follow-up to row 3's own
-- backdrop halo): a separate opacity slider just for that backdrop
-- (MinimapEngine:UpdateGatherIcons's frm.backdrop, a BackdropTemplate
-- frame, not the icon itself) - user wanted it independently
-- controllable rather than fixed. 0-100%, same capped-at-100% reasoning
-- as row 2. Persisted as AlchemyGPS.db.profile.GatherBackdropOpacity,
-- applied live to MinimapEngine.GatherBackdropOpacity on every slider
-- move.
--
-- Row 7 (build-order step 19 follow-up, 2026-11-11): a brightness
-- slider for the Terrain Texture layer (MinimapEngine:UpdateMiniFrames'
-- own texture:SetVertexColor call) - added after the dynamic-coverage
-- fix's first version auto-faded this layer out once its coverage cap
-- was exceeded, and the user explicitly didn't want that ("no fading,
-- always bright by default... expose that variable as a slider... so
-- i have control of it"). Same persisted-value/live-apply shape as
-- row 1's Tile Map Brightness (0-100%, same "no over-brightening past
-- natural color" range), but a SEPARATE, independent control rather
-- than sharing row 1's value - Terrain and Art Map are different
-- layers the user may want to balance differently, and row 1 already
-- existed and worked a certain way before this request. Persisted as
-- AlchemyGPS.db.profile.TerrainBrightness, applied live to
-- MinimapEngine.TerrainBrightness on every slider move.
--
-- Rows 5/6 (build-order step 10, 2026-11-11): "Set Goto Here" and
-- "Clear Goto" - real Carbonite's own right-click menu has these same
-- two items (Menu_OnGoto/Menu_OnClearGoto, MapEngine.lua:3968-3975),
-- confirmed by reading its source rather than assumed, so this isn't a
-- new idea bolted onto an unrelated menu - it's the same feature's own
-- real UI. See MinimapEngine.lua's own "Build-order step 10" section
-- header for the position-capture/world-math/ant-trail details behind
-- what these two rows actually do.
--
-- Live-tested working 2026-11-11 (goto, ant-trail direction, arrival
-- detection/sound all confirmed correct) - then moved to the TOP of
-- the menu and restyled as thin highlight rows (createMenuRow, below)
-- instead of UIPanelButtonTemplate buttons, per explicit user request
-- to match Carbonite's own menu look. Real Carbonite's row style
-- (Nx.Menu:Update, UIEngine.lua:5740-5862) is a plain Button-ish
-- frame spanning the menu width, ~12px tall, no border/button
-- texture, with a tinted highlight that fades in on hover and a
-- left-justified label - createMenuRow below is that same look (a
-- WoW HIGHLIGHT-layer texture standing in for Carbonite's own manual
-- alpha-fade-on-OnUpdate, since Blizzard's highlight layer already
-- does the show/hide-on-hover part for free).

-- 2026-11-18 (user request, from Carbonite's "Transparency by layer":
-- "do this but make it work how the ones we already have do, put in
-- both settings menu and the right click menu on map make the right
-- click menu more tidy, make it open up or down depending on where on
-- screen it is so it never flows off screen"): every slider is now one
-- row of MapContextMenu.SLIDERS - the five above plus city maps,
-- dungeon maps, unexplored areas, map icons, quest icons and quest
-- areas - each a profile value applied live to a MinimapEngine field,
-- exactly like the first five. Settings > Map builds the same list.
-- The menu itself: the goto rows on top, then two columns ("Map
-- layers", "Icons") of compact sliders each showing its value, and it
-- opens down and right from the cursor, or up / left when that would
-- run off the screen.

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local MapContextMenu = {}
AlchemyGPS.Modules.Map.MapContextMenu = MapContextMenu

-- One row per slider: profile key, engine field (read by the drawing
-- code), label, range, step, default, and an optional extra on change.
local function questOverlayChanged()
    local Q = AlchemyGPS.Modules.Quest
    if Q and Q.Overlay then Q.Overlay.Drawn = nil end
end

MapContextMenu.SLIDERS = {
    -- Map layers
    { col = 1, key = "BackgndBrightness", field = "BackgndAlpha", label = "Zone art",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 1, key = "TerrainBrightness", field = "TerrainBrightness", label = "Terrain",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 1, key = "CityBrightness", field = "CityBrightness", label = "City maps",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 1, key = "DungeonBrightness", field = "DungeonBrightness", label = "Dungeon maps",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 1, key = "UnexploredBrightness", field = "UnexploredBrightness", label = "Unexplored areas",
      min = 0, max = 1, step = 0.05, default = 0.35 },
    { col = 1, key = "QuestAreaOpacity", field = "QuestAreaOpacity", label = "Quest areas",
      min = 0, max = 3, step = 0.1, default = 1, changed = questOverlayChanged },
    -- Icons
    { col = 2, key = "PoiOpacity", field = "PoiOpacity", label = "Map icons",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 2, key = "QuestIconOpacity", field = "QuestIconOpacity", label = "Quest icons",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 2, key = "GatherIconOpacity", field = "GatherOpacity", label = "Gathering icons",
      min = 0, max = 1, step = 0.05, default = 1 },
    { col = 2, key = "GatherIconScale", field = "GatherIconScale", label = "Gathering icon size",
      min = 0.5, max = 3, step = 0.1, default = 1 },
    { col = 2, key = "GatherBackdropOpacity", field = "GatherBackdropOpacity", label = "Gathering backdrop",
      min = 0, max = 1, step = 0.05, default = 0.7 },
}

function MapContextMenu.SliderValue(def)
    local p = AlchemyGPS.db and AlchemyGPS.db.profile
    local v = p and p[def.key]
    if v == nil then return def.default end
    return v
end

function MapContextMenu.SetSliderValue(def, value)
    if AlchemyGPS.db and AlchemyGPS.db.profile then
        AlchemyGPS.db.profile[def.key] = value
    end
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if MinimapEngine then MinimapEngine[def.field] = value end
    if def.changed then def.changed() end
end

-- Puts every slider's saved value on the engine (at login).
function MapContextMenu.ApplyAll()
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if not MinimapEngine or not (AlchemyGPS.db and AlchemyGPS.db.profile) then return end
    for _, def in ipairs(MapContextMenu.SLIDERS) do
        MinimapEngine[def.field] = MapContextMenu.SliderValue(def)
    end
end

local menu

local ROW_H = 16
local ROW_GAP = 2
local COL_W = 200
local PAD = 12
local SLIDER_H = 38
local HEADER_H = 18

-- Thin, borderless highlight row matching real Carbonite's own menu
-- item look (see header comment above) - a Button (for OnClick/hover)
-- rather than UIPanelButtonTemplate, spanning the menu width minus
-- margins, with a HIGHLIGHT-layer texture WoW already shows/hides on
-- hover for free instead of Carbonite's own manual alpha-fade.
local function createMenuRow(parent, text, yOffset, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, yOffset)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(0.4, 0.4, 0.8, 0.35)
    row:SetHighlightTexture(hl)

    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)

    row:SetScript("OnClick", onClick)
    return row
end

local function pct(v) return ("%d%%"):format(math.floor(v * 100 + .5)) end
MapContextMenu.Pct = pct

-- A compact slider: "Label .......... 80%" over a thin bar.
local sliderCount = 0
local function createSlider(parent, def, x, y)
    sliderCount = sliderCount + 1
    local name = "AlchemyGPSMapMenuSlider" .. sliderCount
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y)
    label:SetText(def.label)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + COL_W - 8, y)

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 14)
    slider:SetWidth(COL_W - 12)
    slider:SetHeight(14)
    slider:SetMinMaxValues(def.min, def.max)
    slider:SetValueStep(def.step)
    slider:SetObeyStepOnDrag(true)
    for _, part in ipairs({ "Low", "High", "Text" }) do
        local fs = _G[name .. part]
        if fs then fs:SetText("") end
    end
    slider:SetScript("OnValueChanged", function(self, v)
        value:SetText(pct(v))
        if not self.refreshing then MapContextMenu.SetSliderValue(def, v) end
    end)
    slider.def = def
    slider.valueText = value
    return slider
end

local function create()
    if menu then return menu end

    menu = CreateFrame("Frame", "AlchemyGPSMapContextMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:Hide()

    local y = -10
    local function row(text, fn)
        local r = createMenuRow(menu, text, y, function()
            local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
            if MinimapEngine then fn(MinimapEngine) end
            MapContextMenu:Close()
        end)
        y = y - (ROW_H + ROW_GAP)
        return r
    end
    menu.gotoRow = row("Set goto here", function(E) E:SetGotoAtClick() end)
    -- 2026-11-18: a waypoint here, queued behind the goto (Map/Waypoints.lua).
    menu.waypointRow = row("Add a waypoint here", function(E)
        if not E.ClickFrmX then return end
        local wx, wy = E:FramePosToWorldPos(E.ClickFrmX, E.ClickFrmY)
        local zone, zx, zy
        if wx then zone, zx, zy = E:ZoneAtWorld(wx, wy) end
        local W = AlchemyGPS.Modules.Map.Waypoints
        if zone and W then
            W:Add(zone, zx / 100, zy / 100, { title = "Map waypoint", crazy = false, from = "map" })
        end
    end)
    menu.clearGotoRow = row("Clear goto", function(E) E:ClearGoto() end)

    -- A thin divider, then the two columns.
    y = y - 4
    local line = menu:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, y)
    line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, y)
    y = y - 6

    local heads = { "Map layers", "Icons" }
    local colY = {}
    for col = 1, 2 do
        local x = PAD + (col - 1) * COL_W
        local h = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", menu, "TOPLEFT", x + 4, y)
        h:SetText(heads[col])
        colY[col] = y - HEADER_H
    end
    menu.sliders = {}
    for _, def in ipairs(MapContextMenu.SLIDERS) do
        local col = def.col
        local x = PAD + (col - 1) * COL_W
        menu.sliders[#menu.sliders + 1] = createSlider(menu, def, x, colY[col])
        colY[col] = colY[col] - SLIDER_H
    end
    local bottom = math.min(colY[1], colY[2])
    menu:SetSize(PAD * 2 + COL_W * 2, -bottom + 8)

    -- Dismiss on an outside click WITHOUT an intercepting frame: a
    -- full-screen clickable Button over UIParent sat above Blizzard's
    -- own protected action bars and tripped "AlchemyGPS has been
    -- blocked from an action only available to the Blizzard UI" -
    -- confirmed live, 2026-11-10. This polls instead (an OnUpdate
    -- never touches or blocks a click meant for something else, so it
    -- can't taint a secure frame's click the way an overlapping
    -- mouse-enabled frame can).
    --
    -- Found and fixed live, 2026-11-10: the global MouseIsOver()
    -- function doesn't exist on this server's client build - the
    -- frame's own :IsMouseOver() method is used instead.
    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() then
            MapContextMenu:Close()
        end
    end)

    return menu
end

function MapContextMenu:Open()
    local m = create()

    for _, slider in ipairs(m.sliders) do
        local v = MapContextMenu.SliderValue(slider.def)
        slider.refreshing = true
        slider:SetValue(v)
        slider.refreshing = false
        slider.valueText:SetText(pct(v))
    end

    -- Down and right from the cursor, or up / left when that would run
    -- off the screen.
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local w, h = m:GetWidth(), m:GetHeight()
    local up = y - h < 0
    local left = x + w > UIParent:GetWidth()
    local point = (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
    m:ClearAllPoints()
    m:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)

    m:Show()
end

function MapContextMenu:Close()
    if not menu then return end
    menu:Hide()
end

function MapContextMenu:IsShown()
    return menu ~= nil and menu:IsShown()
end

-- Saved values onto the engine once the saved settings are in.
AlchemyGPS.Core.EventBus:Subscribe("ALCHEMYGPS_ENABLE", function()
    MapContextMenu.ApplyAll()
end)
