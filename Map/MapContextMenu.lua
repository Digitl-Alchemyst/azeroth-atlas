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

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local MapContextMenu = {}
AlchemyGPS.Modules.Map.MapContextMenu = MapContextMenu

local DEFAULT_BRIGHTNESS = 1
-- 0-100% only, not an over-brightening range past the tile art's own
-- natural color - explicit user instruction, 2026-11-10 ("i want the
-- working range to be 0-100"), reverting the earlier 0-250% attempt.
local MIN_BRIGHTNESS, MAX_BRIGHTNESS = 0, 1

local DEFAULT_GATHER_OPACITY = 1
local MIN_GATHER_OPACITY, MAX_GATHER_OPACITY = 0, 1

local DEFAULT_GATHER_SCALE = 1
local MIN_GATHER_SCALE, MAX_GATHER_SCALE = 0.5, 3

local DEFAULT_GATHER_BACKDROP_OPACITY = 0.7
local MIN_GATHER_BACKDROP_OPACITY, MAX_GATHER_BACKDROP_OPACITY = 0, 1

local menu

local GOTO_ROW_H = 16
local GOTO_ROW_GAP = 2

-- Thin, borderless highlight row matching real Carbonite's own menu
-- item look (see header comment above) - a Button (for OnClick/hover)
-- rather than UIPanelButtonTemplate, spanning the menu width minus
-- margins, with a HIGHLIGHT-layer texture WoW already shows/hides on
-- hover for free instead of Carbonite's own manual alpha-fade.
local function createMenuRow(parent, text, yOffset, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(GOTO_ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, yOffset)

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

local function applyBrightness(value)
    if AlchemyGPS.db and AlchemyGPS.db.profile then
        AlchemyGPS.db.profile.BackgndBrightness = value
    end
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if MinimapEngine then
        MinimapEngine.BackgndAlpha = value
    end
end

local function applyGatherOpacity(value)
    if AlchemyGPS.db and AlchemyGPS.db.profile then
        AlchemyGPS.db.profile.GatherIconOpacity = value
    end
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if MinimapEngine then
        MinimapEngine.GatherOpacity = value
    end
end

local function applyGatherScale(value)
    if AlchemyGPS.db and AlchemyGPS.db.profile then
        AlchemyGPS.db.profile.GatherIconScale = value
    end
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if MinimapEngine then
        MinimapEngine.GatherIconScale = value
    end
end

local function applyGatherBackdropOpacity(value)
    if AlchemyGPS.db and AlchemyGPS.db.profile then
        AlchemyGPS.db.profile.GatherBackdropOpacity = value
    end
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if MinimapEngine then
        MinimapEngine.GatherBackdropOpacity = value
    end
end

local function create()
    if menu then return menu end

    menu = CreateFrame("Frame", "AlchemyGPSMapContextMenu", UIParent, "BackdropTemplate")
    menu:SetSize(220, 310)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:Hide()

    local gotoRow = createMenuRow(menu, "Set Goto Here", -10, function()
        local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
        if MinimapEngine then MinimapEngine:SetGotoAtClick() end
        MapContextMenu:Close()
    end)
    menu.gotoRow = gotoRow

    local clearGotoRow = createMenuRow(menu, "Clear Goto", -10 - (GOTO_ROW_H + GOTO_ROW_GAP), function()
        local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
        if MinimapEngine then MinimapEngine:ClearGoto() end
        MapContextMenu:Close()
    end)
    menu.clearGotoRow = clearGotoRow

    local label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Anchored to the menu's own top-center, not the slider below it -
    -- a left-anchored label's "BOTTOM" point sits at the horizontal
    -- center of its own rendered text width, not the menu's center,
    -- which is what was actually dragging the slider left (it was
    -- anchored off this label, not off the menu).
    label:SetPoint("TOP", menu, "TOP", 0, -52)
    label:SetText("Tile Map Brightness")

    local slider = CreateFrame("Slider", "AlchemyGPSMapBrightnessSlider", menu, "OptionsSliderTemplate")
    slider:SetPoint("TOP", menu, "TOP", 0, -76)
    slider:SetWidth(180)
    slider:SetMinMaxValues(MIN_BRIGHTNESS, MAX_BRIGHTNESS)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("0%")
    _G[slider:GetName() .. "High"]:SetText(("%d%%"):format(MAX_BRIGHTNESS * 100))
    _G[slider:GetName() .. "Text"]:SetText("")
    slider:SetScript("OnValueChanged", function(_, value)
        applyBrightness(value)
    end)
    menu.slider = slider

    local gatherLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gatherLabel:SetPoint("TOP", menu, "TOP", 0, -114)
    gatherLabel:SetText("Gathering Icon Opacity")

    local gatherSlider = CreateFrame("Slider", "AlchemyGPSGatherOpacitySlider", menu, "OptionsSliderTemplate")
    gatherSlider:SetPoint("TOP", menu, "TOP", 0, -138)
    gatherSlider:SetWidth(180)
    gatherSlider:SetMinMaxValues(MIN_GATHER_OPACITY, MAX_GATHER_OPACITY)
    gatherSlider:SetValueStep(0.05)
    gatherSlider:SetObeyStepOnDrag(true)
    _G[gatherSlider:GetName() .. "Low"]:SetText("0%")
    _G[gatherSlider:GetName() .. "High"]:SetText(("%d%%"):format(MAX_GATHER_OPACITY * 100))
    _G[gatherSlider:GetName() .. "Text"]:SetText("")
    gatherSlider:SetScript("OnValueChanged", function(_, value)
        applyGatherOpacity(value)
    end)
    menu.gatherSlider = gatherSlider

    local sizeLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("TOP", menu, "TOP", 0, -176)
    sizeLabel:SetText("Gathering Icon Size")

    local sizeSlider = CreateFrame("Slider", "AlchemyGPSGatherSizeSlider", menu, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOP", menu, "TOP", 0, -200)
    sizeSlider:SetWidth(180)
    sizeSlider:SetMinMaxValues(MIN_GATHER_SCALE, MAX_GATHER_SCALE)
    sizeSlider:SetValueStep(0.1)
    sizeSlider:SetObeyStepOnDrag(true)
    _G[sizeSlider:GetName() .. "Low"]:SetText(("%d%%"):format(MIN_GATHER_SCALE * 100))
    _G[sizeSlider:GetName() .. "High"]:SetText(("%d%%"):format(MAX_GATHER_SCALE * 100))
    _G[sizeSlider:GetName() .. "Text"]:SetText("")
    sizeSlider:SetScript("OnValueChanged", function(_, value)
        applyGatherScale(value)
    end)
    menu.sizeSlider = sizeSlider

    local backdropLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    backdropLabel:SetPoint("TOP", menu, "TOP", 0, -238)
    backdropLabel:SetText("Gathering Icon Backdrop Opacity")

    local backdropSlider = CreateFrame("Slider", "AlchemyGPSGatherBackdropOpacitySlider", menu, "OptionsSliderTemplate")
    backdropSlider:SetPoint("TOP", menu, "TOP", 0, -262)
    backdropSlider:SetWidth(180)
    backdropSlider:SetMinMaxValues(MIN_GATHER_BACKDROP_OPACITY, MAX_GATHER_BACKDROP_OPACITY)
    backdropSlider:SetValueStep(0.05)
    backdropSlider:SetObeyStepOnDrag(true)
    _G[backdropSlider:GetName() .. "Low"]:SetText("0%")
    _G[backdropSlider:GetName() .. "High"]:SetText(("%d%%"):format(MAX_GATHER_BACKDROP_OPACITY * 100))
    _G[backdropSlider:GetName() .. "Text"]:SetText("")
    backdropSlider:SetScript("OnValueChanged", function(_, value)
        applyGatherBackdropOpacity(value)
    end)
    menu.backdropSlider = backdropSlider

    -- Dismiss on an outside click WITHOUT an intercepting frame: a
    -- full-screen clickable Button over UIParent sat above Blizzard's
    -- own protected action bars and tripped "AlchemyGPS has been
    -- blocked from an action only available to the Blizzard UI" -
    -- confirmed live, 2026-11-10. This polls instead (an OnUpdate
    -- never touches or blocks a click meant for something else, so it
    -- can't taint a secure frame's click the way an overlapping
    -- mouse-enabled frame can).
    --
    -- Found and fixed live, 2026-11-10 (the deferred "large number of
    -- AddOn errors" bug from earlier this session, finally reproduced
    -- with an exact error): the global MouseIsOver() function doesn't
    -- exist on this server's client build - "attempt to call a nil
    -- value" on every single OnUpdate tick while this menu was open,
    -- which is exactly what "large number of errors" looks like. Same
    -- pattern as this session's other missing-default-Blizzard-asset
    -- finds (the native mail icon texture). Switched to the frame's
    -- own :IsMouseOver() method instead, which doesn't depend on that
    -- global and is the more modern, idiomatic equivalent anyway.
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

    local brightness = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.BackgndBrightness) or DEFAULT_BRIGHTNESS
    m.slider:SetValue(brightness)

    local gatherOpacity = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.GatherIconOpacity) or DEFAULT_GATHER_OPACITY
    m.gatherSlider:SetValue(gatherOpacity)

    local gatherScale = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.GatherIconScale) or DEFAULT_GATHER_SCALE
    m.sizeSlider:SetValue(gatherScale)

    local gatherBackdropOpacity = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.GatherBackdropOpacity) or DEFAULT_GATHER_BACKDROP_OPACITY
    m.backdropSlider:SetValue(gatherBackdropOpacity)

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)

    m:Show()
end

function MapContextMenu:Close()
    if not menu then return end
    menu:Hide()
end

function MapContextMenu:IsShown()
    return menu ~= nil and menu:IsShown()
end
