-- Alchemy GPS | Settings / SettingsWindow
-- The settings window: /gps settings. Built on the simplified
-- UI/SmallWindow.lua chrome (AlchemyGPS.UI.Window), not the heavy
-- ported Nx.Window used by the minimap itself - this is a small
-- utility panel, not something that needs free-edge resize.
--
-- Build-order step 13 (2026-11-11): split into two tabs via the new
-- UI/TabBar.lua, explicit user request ("give me a tab in the
-- settings menu... just make the tab in settings called style").
--   - "General": the three checkboxes + Show Minimap button this
--     window always had - unchanged, just moved into their own panel.
--   - "Style": new. Window Skin (the 12-theme AlchemyGPS.Skin
--     registry) plus every UI/StyleOptions.lua category - one row per
--     category, a clickable preview swatch per option, selected one
--     highlighted gold. Window grew from 270x180 to 380x440 to fit a
--     scrollable list - there's no content here that existed at the
--     old size. The row loop itself (buildStyle, below) is fully
--     generic over StyleOptions.Categories - new categories need no
--     new code here at all, they just appear as another row.
--
-- Build-order step 14 (2026-11-11), same-day follow-up: StyleOptions'
-- option shape grew to cover Blizzard atlases and texcoord-cropped
-- sheet regions (Leatrix_Maps' real icon set), not just plain
-- textures - buildCategoryRow's swatch preview below renders all
-- three the same way the live icons do, via StyleOptions:ApplyIconSpec
-- (see that function's own comment in UI/StyleOptions.lua).
--
-- Adapted from AlchemyNavigation/Modules/Settings/SettingsWindow.lua
-- (same General-tab structure; the per-cluster button toggles that
-- file already tried and cut don't apply here - this addon never had
-- them).

local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS
AlchemyGPS.Modules.Settings = AlchemyGPS.Modules.Settings or {}

local Widget = AlchemyGPS.UI.Widget

local SettingsWindow = {}
AlchemyGPS.Modules.Settings.SettingsWindow = SettingsWindow

local function minimapDB()
    local MinimapWindow = AlchemyGPS:GetModule("MinimapWindow", true)
    return MinimapWindow and MinimapWindow:DB().profile or {}
end

local win
local nextCBID = 0
-- Tracked so Refresh() can re-sync checked-state against the DB -
-- needed because `/gps minimap hide|show` can flip NativeMinimapHidden
-- from outside this window, and a checkbox only reads get() once, at
-- creation, otherwise.
local checkboxes = {}

local function addCheckbox(parent, y, label, get, set)
    nextCBID = nextCBID + 1
    local cb = CreateFrame("CheckButton", "AlchemyGPSSettingsCB" .. nextCBID, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 4, y)
    cb:SetSize(24, 24)

    local text = _G[cb:GetName() .. "Text"]
    if text then text:SetText(label) end

    cb:SetChecked(get() and true or false)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)

    tinsert(checkboxes, { cb = cb, get = get })
    return cb
end

local function buildGeneral(content)
    local y = -6

    addCheckbox(content, y, "Hide Blizzard minimap",
        function() return minimapDB().NativeMinimapHidden == true end,
        function(value)
            minimapDB().NativeMinimapHidden = value
            local NativeMinimapHide = AlchemyGPS.Modules.Map.NativeMinimapHide
            if NativeMinimapHide then NativeMinimapHide:SetNativeHidden(value) end
        end)
    y = y - 26

    local Logger = AlchemyGPS.Core.Logger
    addCheckbox(content, y, "Debug mode",
        function() return Logger.minLevel == Logger.LEVEL.DEBUG end,
        function(value) Logger:SetLevel(value and "DEBUG" or "INFO") end)
    y = y - 26

    -- Icon bar (the MinimapDock window) orientation - a single line of
    -- icons, either a row or a column, never wrapping (see
    -- Map/MinimapDock.lua's Layout/IsVertical), so it can be docked
    -- flush against another window's edge.
    addCheckbox(content, y, "Icon bar: vertical column",
        function()
            local MinimapDock = AlchemyGPS.Modules.Map.MinimapDock
            return MinimapDock and MinimapDock:IsVertical() or false
        end,
        function(value)
            AlchemyGPS.db.profile.DockOrientation = value and "Column" or "Row"
            local MinimapDock = AlchemyGPS.Modules.Map.MinimapDock
            if MinimapDock and MinimapDock.Win then MinimapDock:Layout() end
        end)
    y = y - 34

    local showBut = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    showBut:SetSize(120, 22)
    showBut:SetPoint("TOPLEFT", 4, y)
    showBut:SetText("Show Minimap")
    showBut:SetScript("OnClick", function()
        local MinimapWindow = AlchemyGPS:GetModule("MinimapWindow", true)
        if MinimapWindow then MinimapWindow:Open() end
    end)
end

---------------------------------------------------------------------------------------
-- Style tab
---------------------------------------------------------------------------------------

local SWATCH_SIZE = 28
local SWATCH_GAP = 6
-- Numeric, not queried via GetWidth() - the scroll child's width is
-- set explicitly below (see buildStyle), and GetWidth() on a frame
-- sized purely by anchors isn't reliably resolved yet on the same
-- frame it's built in.
local SCROLL_CHILD_WIDTH = 380 - 8 - 8 - 24

-- Re-run after every swatch click (any category) so the one just
-- picked lights up and every other swatch in that same row goes back
-- to its normal border - simplest correct approach given how few
-- swatches this tab ever has (at most 12, Window Skin).
local swatchRefreshers = {}

local function highlightSwatch(btn, selected)
    if selected then
        btn:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
        btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
end

-- Same BackdropTemplate client-compat check as UI/Widget.lua's own
-- CreateFrame (only present/needed on Retail-era clients; older
-- clients already have SetBackdrop on every frame).
local function makeSwatchButton(parent)
    local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local btn = CreateFrame("Button", nil, parent, template)
    btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\White8x8",
        edgeFile = "Interface\\Buttons\\White8x8",
        edgeSize = 2,
    })
    return btn
end

-- `items` is a list of { id, label, tex=<path> } / { id, label,
-- atlas=<name> } / { id, label, tex=<path>, coords={l,r,t,b} } (icon
-- preview - a StyleOptions option table, rendered via its own
-- ApplyIconSpec) or { id, label, bg={r,g,b,a}, accent={r,g,b,a} }
-- (Window Skin's two-tone color preview - no texture). `getSelectedId()` and
-- `onSelect(id)` close over whichever system (Skin or StyleOptions)
-- actually owns that category's persisted choice.
local function buildCategoryRow(parent, yPos, label, items, getSelectedId, onSelect)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 4, yPos)
    lbl:SetText(label)
    yPos = yPos - 18

    local rowX = 4
    local rowY = yPos

    for _, item in ipairs(items) do
        if rowX + SWATCH_SIZE > SCROLL_CHILD_WIDTH then
            rowX = 4
            rowY = rowY - (SWATCH_SIZE + SWATCH_GAP)
        end

        local btn = makeSwatchButton(parent)
        btn:SetPoint("TOPLEFT", rowX, rowY)

        if item.tex or item.atlas then
            btn:SetBackdropColor(0.05, 0.05, 0.05, 1)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("CENTER")
            icon:SetSize(SWATCH_SIZE - 8, SWATCH_SIZE - 8)
            -- Build-order step 14, 2026-11-11: `item` is already shaped
            -- exactly like a StyleOptions spec table (tex/atlas/coords),
            -- since buildTextureItems below just passes those fields
            -- straight through - so the same ApplyIconSpec that renders
            -- the live icon also renders its preview here, instead of
            -- re-deriving the atlas-vs-texcoord-vs-plain branching a
            -- second time in this file.
            AlchemyGPS.UI.StyleOptions:ApplyIconSpec(icon, item)
        else
            btn:SetBackdropColor(item.bg[1], item.bg[2], item.bg[3], item.bg[4] or 1)
            if item.accent then
                local inner = btn:CreateTexture(nil, "ARTWORK")
                inner:SetPoint("CENTER")
                inner:SetSize(SWATCH_SIZE - 14, SWATCH_SIZE - 14)
                inner:SetColorTexture(item.accent[1], item.accent[2], item.accent[3], item.accent[4] or 1)
            end
        end

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(item.label)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local function refresh()
            highlightSwatch(btn, getSelectedId() == item.id)
        end
        refresh()
        tinsert(swatchRefreshers, refresh)

        btn:SetScript("OnClick", function()
            onSelect(item.id)
            for _, fn in ipairs(swatchRefreshers) do fn() end
        end)

        rowX = rowX + SWATCH_SIZE + SWATCH_GAP
    end

    return rowY - (SWATCH_SIZE + SWATCH_GAP + 12)
end

local function buildWindowSkinItems()
    local items = {}
    for _, name in ipairs(AlchemyGPS.Skin.Names) do
        local data = AlchemyGPS.Skin.Skins[name]
        local br, bg, bb, ba = Nx.Util_str2rgba(data["BgCol"])

        local accentStr = data["BdCol"]
        if type(data["BdColResolve"]) == "function" then
            local ok, val = pcall(data.BdColResolve)
            if ok and val then accentStr = val end
        end
        local ar, ag, ab, aa = Nx.Util_str2rgba(accentStr)

        items[#items + 1] = {
            id = name, label = name,
            bg = { br, bg, bb, ba },
            accent = { ar, ag, ab, aa },
        }
    end
    return items
end

local function buildTextureItems(categoryKey)
    local items = {}
    for _, cat in ipairs(AlchemyGPS.UI.StyleOptions.Categories) do
        if cat.key == categoryKey then
            for _, opt in ipairs(cat.options) do
                items[#items + 1] = {
                    id = opt.id, label = opt.label,
                    tex = opt.tex, atlas = opt.atlas, coords = opt.coords,
                }
            end
        end
    end
    return items
end

local function buildStyle(panel)
    local scroll = Widget.CreateScrollFrame(panel, "AlchemyGPSStyleScroll")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)

    local child = scroll.ScrollChild
    child:SetWidth(SCROLL_CHILD_WIDTH)

    local y = -4
    swatchRefreshers = {}

    y = buildCategoryRow(child, y, "Window Skin", buildWindowSkinItems(),
        function() return AlchemyGPS.db.profile.Skin and AlchemyGPS.db.profile.Skin.Name end,
        function(id)
            AlchemyGPS.Skin:Set(id)
            if win then win:ApplySkin() end
        end)

    for _, cat in ipairs(AlchemyGPS.UI.StyleOptions.Categories) do
        y = buildCategoryRow(child, y, cat.label, buildTextureItems(cat.key),
            function() return AlchemyGPS.UI.StyleOptions:GetChoice(cat.key) end,
            function(id) AlchemyGPS.UI.StyleOptions:SetChoice(cat.key, id) end)
    end

    child:SetHeight(math.max(-y, 1))
end

---------------------------------------------------------------------------------------

local function create()
    if win then return win end

    win = AlchemyGPS.UI.Window:Create{
        name   = "AlchemyGPSSettingsWindow",
        title  = "Alchemy GPS Settings",
        width  = 380,
        height = 440,
    }

    -- Both panels sit below the 30px-tall tab bar (anchored at the top
    -- of win.content, see below) - same insets, so switching tabs
    -- never shifts anything.
    local generalPanel = CreateFrame("Frame", nil, win.content)
    generalPanel:SetPoint("TOPLEFT", 0, -30)
    generalPanel:SetPoint("BOTTOMRIGHT", 0, 0)

    local stylePanel = CreateFrame("Frame", nil, win.content)
    stylePanel:SetPoint("TOPLEFT", 0, -30)
    stylePanel:SetPoint("BOTTOMRIGHT", 0, 0)

    local tabBar = AlchemyGPS.UI.TabBar:New{
        parent = win.content,
        name = "AlchemyGPSSettingsTabs",
        width = 364,
        anchor = { point = "TOPLEFT", x = 0, y = 0 },
        tabs = {
            { id = "general", label = "General" },
            { id = "style",   label = "Style" },
        },
        selected = "general",
        onSelect = function(_, id)
            if id == "style" then
                generalPanel:Hide()
                stylePanel:Show()
            else
                stylePanel:Hide()
                generalPanel:Show()
            end
        end,
    }
    stylePanel:Hide()

    buildGeneral(generalPanel)
    buildStyle(stylePanel)

    AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(win, UIParent, { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })

    return win
end

function SettingsWindow:Refresh()
    for _, entry in ipairs(checkboxes) do
        entry.cb:SetChecked(entry.get() and true or false)
    end
    for _, fn in ipairs(swatchRefreshers) do fn() end
end

function SettingsWindow:IsShown()
    return win ~= nil and win:IsShown()
end

function SettingsWindow:Open()
    create():Show()
end

function SettingsWindow:Close()
    if win then win:Hide() end
end

function SettingsWindow:Toggle()
    if self:IsShown() then self:Close() else self:Open() end
end

AlchemyGPS.Core.SlashCommands:Register("settings", function()
    SettingsWindow:Toggle()
end, "open the settings window")
