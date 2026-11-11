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
-- First (and currently only) row: a brightness slider for the static
-- world-art tile background (MinimapEngine:MoveZoneTiles's own
-- texture:SetVertexColor call - see that function's header comment
-- for why this is "brightness," allowed above 1, rather than plain
-- 0-1 alpha transparency). Persisted as
-- AlchemyGPS.db.profile.BackgndBrightness, applied live to
-- MinimapEngine.BackgndAlpha on every slider move.

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local MapContextMenu = {}
AlchemyGPS.Modules.Map.MapContextMenu = MapContextMenu

local DEFAULT_BRIGHTNESS = 1
-- 0-100% only, not an over-brightening range past the tile art's own
-- natural color - explicit user instruction, 2026-11-10 ("i want the
-- working range to be 0-100"), reverting the earlier 0-250% attempt.
local MIN_BRIGHTNESS, MAX_BRIGHTNESS = 0, 1

local menu

local function applyBrightness(value)
    if AlchemyGPS.db and AlchemyGPS.db.profile then
        AlchemyGPS.db.profile.BackgndBrightness = value
    end
    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    if MinimapEngine then
        MinimapEngine.BackgndAlpha = value
    end
end

local function create()
    if menu then return menu end

    menu = CreateFrame("Frame", "AlchemyGPSMapContextMenu", UIParent, "BackdropTemplate")
    menu:SetSize(220, 70)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:Hide()

    local label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Anchored to the menu's own top-center, not the slider below it -
    -- a left-anchored label's "BOTTOM" point sits at the horizontal
    -- center of its own rendered text width, not the menu's center,
    -- which is what was actually dragging the slider left (it was
    -- anchored off this label, not off the menu).
    label:SetPoint("TOP", menu, "TOP", 0, -12)
    label:SetText("Tile Map Brightness")

    local slider = CreateFrame("Slider", "AlchemyGPSMapBrightnessSlider", menu, "OptionsSliderTemplate")
    slider:SetPoint("TOP", menu, "TOP", 0, -36)
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
