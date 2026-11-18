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
-- Quest companion (2026-11-15): a third tab, "Quests", between the two
-- - on/off switches for the tracker window, the routing arrow, hiding
-- Blizzard's tracker, and what the map's pickup pins include. See
-- buildQuests below and Quest/Quest.lua's DEFAULTS.
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

-- 2026-11-18: a labelled slider ("Arrow size: 1.2"), refreshed with the
-- checkboxes. Takes 46 pixels of height; fmt formats the value.
local sliders = {}
local nextSliderID = 0

local function addSlider(parent, y, label, minV, maxV, step, get, set, fmt)
    nextSliderID = nextSliderID + 1
    local name = "AlchemyGPSSettingsSlider" .. nextSliderID
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 14, y - 16)
    s:SetWidth(296)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    fmt = fmt or "%g"
    -- fmt: a format string, or a function (value -> text).
    local function fmtv(v)
        if type(fmt) == "function" then return fmt(v) end
        return fmt:format(v)
    end
    local text, low, high = _G[name .. "Text"], _G[name .. "Low"], _G[name .. "High"]
    if low then low:SetText(fmtv(minV)) end
    if high then high:SetText(fmtv(maxV)) end
    local function show(v)
        if text then text:SetText(label .. ": " .. fmtv(v)) end
    end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + .5) * step
        show(v)
        if not self.refreshing then set(v) end
    end)
    local entry = { get = get }
    function entry.refresh()
        local v = get() or minV
        s.refreshing = true
        s:SetValue(v)
        s.refreshing = false
        show(v)
    end
    entry.refresh()
    tinsert(sliders, entry)
    return s
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
-- Map tab (2026-11-16, user request): everything that used to crowd the
-- map's title bar - the layer checkboxes and the Filter menu - plus the
-- new player icons, auto-scale and M / L key options. Scrolls, like the
-- Quests tab.
---------------------------------------------------------------------------------------

local MAP_LAYERS = {
    { key = "Base",    label = "Base - continent backdrop when zoomed far out" },
    { key = "Art",     label = "Art Map - zones' revealed overlay art" },
    { key = "Terrain", label = "Terrain - close-zoom ground texture" },
    { key = "City",    label = "City maps - inside the main cities" },
    { key = "Dungeon", label = "Dungeon maps - inside dungeons and raids" },
}

local PLAYER_FILTERS = {
    { key = "Party", label = "Party members (blue)" },
    { key = "Raid",  label = "Raid members (orange)" },
    { key = "Guild", label = "Guildmates (green) - those running Alchemy GPS" },
    { key = "Friend", label = "Friends (yellow) - those running Alchemy GPS" },
    { key = "Enemy", label = "Enemy players (red) - where you last saw them" },
}

local function mapFilterOn(key)
    local filters = AlchemyGPS.db.profile.MapFilters
    return not filters or filters[key] ~= false
end

local function setMapFilter(key, on)
    AlchemyGPS.db.profile.MapFilters = AlchemyGPS.db.profile.MapFilters or {}
    AlchemyGPS.db.profile.MapFilters[key] = on
end

local function addHeader(parent, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 6, y)
    fs:SetText(text)
    return y - 20
end

local function buildMap(panel)
    local scroll = Widget.CreateScrollFrame(panel, "AlchemyGPSMapOptionsScroll")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local content = scroll.ScrollChild
    content:SetWidth(340)

    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    local FilterMenu = AlchemyGPS.Modules.Map.FilterMenu
    local y = -6

    y = addHeader(content, y, "Map layers")
    for _, layer in ipairs(MAP_LAYERS) do
        local key = layer.key
        addCheckbox(content, y, layer.label,
            function() return MinimapEngine:IsLayerShown(key) end,
            function(value) MinimapEngine:SetLayerShown(key, value) end)
        y = y - 26
    end
    -- 2026-11-18 (user request, from Carbonite): subzone names.
    addCheckbox(content, y, "Subzone names (Goldshire...) as you zoom in",
        function() return AlchemyGPS.db.profile.ShowAreaNames ~= false end,
        function(value)
            AlchemyGPS.db.profile.ShowAreaNames = value
            MinimapEngine.AreaLabelKey = nil
        end)
    y = y - 26

    y = y - 8
    y = addHeader(content, y, "Map icons")
    if FilterMenu and FilterMenu.FILTERS then
        for _, f in ipairs(FilterMenu.FILTERS) do
            local key = f.key
            addCheckbox(content, y, f.label,
                function() return FilterMenu.IsFilterOn(key) end,
                function(value) FilterMenu.SetFilterOn(key, value) end)
            y = y - 26
        end
    end

    y = y - 8
    y = addHeader(content, y, "Players")
    for _, f in ipairs(PLAYER_FILTERS) do
        local key = f.key
        addCheckbox(content, y, f.label,
            function() return mapFilterOn(key) end,
            function(value) setMapFilter(key, value) end)
        y = y - 26
    end
    addCheckbox(content, y, "Show enemies as their faction's emblem",
        function() return AlchemyGPS.db.profile.EnemyFactionIcons == true end,
        function(value) AlchemyGPS.db.profile.EnemyFactionIcons = value end)
    y = y - 26
    addCheckbox(content, y, "Share my position with my guild",
        function() return AlchemyGPS.db.profile.ShareGuildPosition ~= false end,
        function(value) AlchemyGPS.db.profile.ShareGuildPosition = value end)
    y = y - 26
    addCheckbox(content, y, "Share my position with online friends",
        function() return AlchemyGPS.db.profile.ShareFriendPosition ~= false end,
        function(value) AlchemyGPS.db.profile.ShareFriendPosition = value end)
    y = y - 26

    -- 2026-11-18 (user request, from Carbonite): Map/MouseActions.lua.
    -- A button per click; clicking it lists the jobs it can have.
    local MouseActions = AlchemyGPS.Modules.Map.MouseActions
    if MouseActions then
        y = y - 8
        y = addHeader(content, y, "Mouse clicks on the map")
        local note = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", 6, y)
        note:SetWidth(320)
        note:SetJustifyH("LEFT")
        note:SetText("Each of these does nothing until you give it a job. Plain left-drag "
            .. "still moves the map and plain right-click still opens its menu.")
        y = y - 30
        for _, slot in ipairs(MouseActions.SLOTS) do
            local key = slot.key
            local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", 8, y - 4)
            label:SetText(slot.label)
            local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            btn:SetSize(190, 20)
            btn:SetPoint("TOPLEFT", 140, y)
            local function refresh() btn:SetText(MouseActions:Label(MouseActions:Get(key))) end
            refresh()
            btn:SetScript("OnShow", refresh)
            btn:SetScript("OnClick", function(self)
                local BigMap = AlchemyGPS.Modules.Map.BigMap
                if not (BigMap and BigMap.OpenMenu) then return end
                local items = {}
                local current = MouseActions:Get(key)
                for _, a in ipairs(MouseActions.ACTIONS) do
                    items[#items + 1] = { a.label, function()
                        MouseActions:Set(key, a.id)
                        refresh()
                    end, a.id == current }
                end
                BigMap.OpenMenu(self, items)
            end)
            y = y - 24
        end
    end

    -- 2026-11-18 (user request, from Carbonite: transparency by layer):
    -- the same sliders as the map's right-click menu (one list,
    -- MapContextMenu.SLIDERS).
    local MapContextMenu = AlchemyGPS.Modules.Map.MapContextMenu
    if MapContextMenu and MapContextMenu.SLIDERS then
        y = y - 8
        y = addHeader(content, y, "Brightness and opacity")
        local tip = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tip:SetPoint("TOPLEFT", 6, y + 2)
        tip:SetText("Also on the map's right-click menu.")
        y = y - 14
        for _, def in ipairs(MapContextMenu.SLIDERS) do
            addSlider(content, y, def.label, def.min, def.max, def.step,
                function() return MapContextMenu.SliderValue(def) end,
                function(v) MapContextMenu.SetSliderValue(def, v) end,
                MapContextMenu.Pct)
            y = y - 46
        end
    end

    -- 2026-11-18 (user request, from Carbonite): Map/GatherRecorder.lua.
    local Recorder = AlchemyGPS.Modules.Map.GatherRecorder
    if Recorder then
        y = y - 8
        y = addHeader(content, y, "Gathered nodes")
        -- Node glow's settings (on, near-only, speed) are hidden while
        -- the feature is parked (MinimapEngine.lua, GATHER_GLOW_ENABLED).
        addCheckbox(content, y, "Record the herbs, ore and treasure you gather",
            function() return AlchemyGPS.db.profile.RecordGathering ~= false end,
            function(value) AlchemyGPS.db.profile.RecordGathering = value end)
        y = y - 28
        local x = 4
        for _, kind in ipairs(Recorder.KINDS) do
            local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            btn:SetSize(108, 22)
            btn:SetPoint("TOPLEFT", x, y)
            local function label()
                local n = Recorder:Count(kind)
                btn:SetText(("Clear %s (%d)"):format(kind == "Mine" and "mining" or kind:lower(), n))
                btn:SetEnabled(n > 0)
            end
            btn:SetScript("OnShow", label)
            btn:SetScript("OnClick", function()
                Recorder:Clear(kind)
                label()
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Forget every " .. Recorder.KIND_LABEL[kind]:gsub("s$", "") .. " you recorded")
                GameTooltip:AddLine("Every character's - the map's own nodes stay.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            label()
            x = x + 112
        end
        y = y - 30

        -- 2026-11-18 (user request, from Carbonite): one-off import.
        local imp = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        imp:SetSize(220, 22)
        imp:SetPoint("TOPLEFT", 4, y)
        imp:SetText("Import from GatherMate2_Data")
        local rem = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        rem:SetSize(120, 22)
        rem:SetPoint("LEFT", imp, "RIGHT", 4, 0)
        rem:SetText("Remove import")
        local status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("TOPLEFT", 8, y - 26)
        status:SetWidth(440)
        status:SetJustifyH("LEFT")
        local function showStatus(msg)
            local info = Recorder:ImportInfo()
            rem:SetEnabled(info ~= nil)
            if msg then
                status:SetText(msg)
            elseif info then
                local c = info.counts or {}
                status:SetText(("Using imported data (%s): %d herbs, %d mining, %d treasure.")
                    :format(info.when and date("%Y-%m-%d", info.when) or "?", c.Herb or 0, c.Mine or 0, c.Treasure or 0))
            else
                status:SetText("Using the map's built-in gathering data.")
            end
        end
        imp:SetScript("OnClick", function()
            local _, msg = Recorder:Import()
            showStatus(msg)
        end)
        rem:SetScript("OnClick", function()
            Recorder:RemoveImport()
            showStatus()
        end)
        imp:SetScript("OnShow", function() showStatus() end)
        showStatus()
        y = y - 56
    end

    -- 2026-11-18 (user request, from Carbonite): MinimapEngine:UpdateTrail.
    y = y - 8
    y = addHeader(content, y, "Movement trail")
    addCheckbox(content, y, "Show a trail of dots where you've walked",
        function() return AlchemyGPS.db.profile.ShowTrail ~= false end,
        function(value) AlchemyGPS.db.profile.ShowTrail = value end)
    y = y - 26
    addSlider(content, y, "Yards between dots", 2, 50, 1,
        function() return AlchemyGPS.db.profile.TrailYards or 10 end,
        function(v) AlchemyGPS.db.profile.TrailYards = v end, "%d")
    y = y - 46
    addSlider(content, y, "Most dots", 10, 300, 10,
        function() return AlchemyGPS.db.profile.TrailCount or 100 end,
        function(v) AlchemyGPS.db.profile.TrailCount = v end, "%d")
    y = y - 46
    addSlider(content, y, "Seconds a dot lasts", 10, 600, 10,
        function() return AlchemyGPS.db.profile.TrailSeconds or 90 end,
        function(v) AlchemyGPS.db.profile.TrailSeconds = v end, "%d")
    y = y - 46

    -- 2026-11-18 (user request, from Carbonite): Map/CombatState.lua.
    y = y - 8
    y = addHeader(content, y, "In combat")
    for _, o in ipairs({
        { key = "CombatShrinkMap",      label = "Big map drops to the small map when combat starts" },
        { key = "CombatCloseQuestList", label = "Quest list closes when combat starts" },
        { key = "CombatRestore",        label = "Put them back the way they were when combat ends" },
    }) do
        local key = o.key
        addCheckbox(content, y, o.label,
            function() return AlchemyGPS.db.profile[key] ~= false end,
            function(value) AlchemyGPS.db.profile[key] = value end)
        y = y - 26
    end

    -- 2026-11-17: the big map (M) - Map/BigMap.lua.
    y = y - 8
    y = addHeader(content, y, "Big map (M)")
    addCheckbox(content, y, "Player and cursor coordinates",
        function() return minimapDB().BigMapCoords ~= false end,
        function(value) minimapDB().BigMapCoords = value end)
    y = y - 26
    addCheckbox(content, y, "Zone name and level range under the cursor",
        function() return minimapDB().BigMapZoneLevels ~= false end,
        function(value) minimapDB().BigMapZoneLevels = value end)
    y = y - 26

    y = y - 8
    y = addHeader(content, y, "Navigation")
    -- 2026-11-18 (user request, from Carbonite): Map/Travel.lua.
    addCheckbox(content, y, "Travel routes: use flight paths, boats and portals",
        function() return AlchemyGPS.db.profile.TravelRoute ~= false end,
        function(value)
            AlchemyGPS.db.profile.TravelRoute = value
            local Travel = AlchemyGPS.Modules.Map.Travel
            if Travel then Travel.CacheKey = nil end
        end)
    y = y - 26
    addCheckbox(content, y, "Follow your flight: the arrow points where it lands",
        function() return AlchemyGPS.db.profile.TrackFlight ~= false end,
        function(value) AlchemyGPS.db.profile.TrackFlight = value end)
    y = y - 26
    -- 2026-11-18 (user request, from Carbonite): Map/Waypoints.lua.
    addCheckbox(content, y, "Act as TomTom: /way, and waypoints from other addons (/reload)",
        function() return AlchemyGPS.db.profile.EmulateTomTom ~= false end,
        function(value) AlchemyGPS.db.profile.EmulateTomTom = value end)
    y = y - 26
    addCheckbox(content, y, "Center: keep you in the middle of the map",
        function() return minimapDB().AutoFollow ~= false end,
        function(value)
            minimapDB().AutoFollow = value
            local MinimapWindow = AlchemyGPS.Modules.Map.MinimapWindow
            if MinimapWindow and MinimapWindow.CenterCB then MinimapWindow.CenterCB:SetChecked(value) end
        end)
    y = y - 26
    addCheckbox(content, y, "Follow: zoom to keep you and your destination in view",
        function() return minimapDB().AutoScale ~= false end,
        function(value)
            minimapDB().AutoScale = value
            local MinimapWindow = AlchemyGPS.Modules.Map.MinimapWindow
            if MinimapWindow and MinimapWindow.FollowCB then MinimapWindow.FollowCB:SetChecked(value) end
        end)
    y = y - 26
    addCheckbox(content, y, "M: map size, L: quest list (Alt+M / Alt+L: Blizzard's)",
        function() return minimapDB().OverrideMLKeys ~= false end,
        function(value)
            minimapDB().OverrideMLKeys = value
            local MinimapWindow = AlchemyGPS.Modules.Map.MinimapWindow
            if MinimapWindow then MinimapWindow:ApplyKeys() end
        end)
    y = y - 26

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 4, y - 6)
    hint:SetWidth(330)
    hint:SetJustifyH("LEFT")
    hint:SetText("Follow fits one destination at a time, in this order: "
        .. "your goto point, then your corpse, then the quest you're routed to. "
        .. "Center and Follow are also the two checkboxes on the map's header.\n\n"
        .. "With the M / L option on, Alt+M and Alt+L open the game's own world map and "
        .. "quest log. Unticking it gives plain M and L back to them.")

    content:SetHeight(-y + 90)
end

---------------------------------------------------------------------------------------
-- Quests tab (quest companion, 2026-11-15)
---------------------------------------------------------------------------------------

-- Every option here is a plain on/off stored through the Quest
-- module's own Core:Opt/SetOpt (see Quest/Quest.lua) - SetOpt fires
-- the EventBus message each piece listens for, so a click takes
-- effect at once with no per-option wiring in this file.
local QUEST_OPTIONS = {
    { key = "TrackerShown",     label = "Show quest tracker" },
    { key = "TrackerLocked",    label = "Lock quest tracker (no drag or resize)" },
    { key = "HideBlizzTracker", label = "Hide Blizzard's quest tracker" },
    { gap = true },
    { key = "ArrowShown",       label = "Show quest arrow" },
    { key = "ArrowLocked",      label = "Lock quest arrow (click-through)" },
    { key = "AutoTrack",        label = "Auto-track the closest quest" },
    { key = "RouteTrail",       label = "Show the route trail on the map" },
    { gap = true },
    { key = "TrackerGroupByZone", label = "Tracker: group quests by zone / dungeon" },
    { key = "TrackerCollapsed",   label = "Tracker: rolled up to its title bar" },
    { key = "TrackerItemButtons", label = "Tracker: buttons for usable quest items" },
    { gap = true },
    { key = "ShowQuestAreas",   label = "Map: shade the areas where quests are done" },
    { key = "ShowPatrolPaths",  label = "Map: draw the path a wandering quest NPC walks" },
    { key = "ShowLowLevel",     label = "Map: show low-level (gray) quests to pick up" },
    { key = "ShowEventQuests",  label = "Map: show holiday/event quests to pick up" },
    { gap = true },
    { key = "SuperTrackSync",   label = "Keep Blizzard's tracked quest in step" },
}

local function buildQuests(panel)
    -- Scrolls, like the Style tab: there are more options than fit.
    local scroll = Widget.CreateScrollFrame(panel, "AlchemyGPSQuestOptionsScroll")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local content = scroll.ScrollChild
    content:SetWidth(340)       -- window 380, less its insets and the scroll bar

    local Core = AlchemyGPS.Modules.Quest and AlchemyGPS.Modules.Quest.Core
    if not Core then
        local msg = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        msg:SetPoint("TOPLEFT", 8, -10)
        msg:SetText("The quest module failed to load.")
        content:SetHeight(40)
        return
    end

    local y = -6
    for _, opt in ipairs(QUEST_OPTIONS) do
        if opt.gap then
            y = y - 10
        else
            local key = opt.key
            addCheckbox(content, y, opt.label,
                function() return Core:Opt(key) end,
                function(value) Core:SetOpt(key, value) end)
            y = y - 26
        end
    end

    -- 2026-11-18 (user request, from Carbonite's HUD options): the arrow.
    -- Its look is on the Style tab ("Quest Arrow").
    y = y - 10
    y = addHeader(content, y, "Arrow")
    for _, opt in ipairs({
        { key = "ArrowDirText",      label = "Show how many degrees you're off course" },
        { key = "ArrowTargetButton", label = "Click the arrow to target who you're heading to" },
        { key = "ArrowHideInBG",     label = "Hide the arrow in battlegrounds" },
    }) do
        local key = opt.key
        addCheckbox(content, y, opt.label,
            function() return Core:Opt(key) end,
            function(value) Core:SetOpt(key, value) end)
        y = y - 26
    end
    addSlider(content, y, "Arrow size", 0.5, 2, 0.05,
        function() return Core:Opt("ArrowScale") or 1 end,
        function(v) Core:SetOpt("ArrowScale", v) end, "%.2f")
    y = y - 46
    -- X / Y: where the arrow's middle sits, from the middle of the screen.
    -- Dragging the arrow moves these too.
    local function arrowOffset(axis)
        local HUD = AlchemyGPS.Modules.Quest.HUD
        local f = HUD and HUD.Frm
        local cx, cy
        if f then cx, cy = f:GetCenter() end
        if cx then
            local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local ux, uy = UIParent:GetCenter()
            return math.floor((axis == "x" and (cx - ux / k) or (cy - uy / k)) + .5)
        end
        local a = Core:ProfileTable("ArrowAnchor")
        return (a.point == "CENTER" and a[axis]) or 0
    end
    local function setArrowOffset(axis, v)
        local a = Core:ProfileTable("ArrowAnchor")
        local ox, oy = arrowOffset("x"), arrowOffset("y")
        a.point, a.relPoint = "CENTER", "CENTER"
        a.x, a.y = ox, oy
        a[axis] = v
        AlchemyGPS.Core.EventBus:Fire("QUEST_OPTION_CHANGED", "ArrowAnchor")
    end
    addSlider(content, y, "Arrow X offset", -800, 800, 1,
        function() return arrowOffset("x") end,
        function(v) setArrowOffset("x", v) end, "%d")
    y = y - 46
    addSlider(content, y, "Arrow Y offset", -500, 500, 1,
        function() return arrowOffset("y") end,
        function(v) setArrowOffset("y", v) end, "%d")
    y = y - 46

    -- 2026-11-18 (user request, from Carbonite): quest IDs, chain parts.
    y = y - 10
    y = addHeader(content, y, "Quest list and tracker")
    addCheckbox(content, y, "Show which part of a chain a quest is (part 2/4)",
        function() return Core:Opt("ListShowChain") ~= false end,
        function(value) Core:SetOpt("ListShowChain", value) end)
    y = y - 26
    addCheckbox(content, y, "Show quest IDs",
        function() return Core:Opt("ListShowIDs") == true end,
        function(value) Core:SetOpt("ListShowIDs", value) end)
    y = y - 26
    addCheckbox(content, y, "Quest links in chat say the level and chain part",
        function() return Core:Opt("QuestLinkExtras") ~= false end,
        function(value) Core:SetOpt("QuestLinkExtras", value) end)
    y = y - 26

    -- 2026-11-18 (user request, from Carbonite): Quest/QuestNotify.lua.
    local Notify = AlchemyGPS.Modules.Quest.Notify
    if Notify then
        y = y - 10
        y = addHeader(content, y, "Quest progress")
        local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 8, y - 4)
        label:SetText("Sound")
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetSize(190, 20)
        btn:SetPoint("TOPLEFT", 70, y)
        local function refresh() btn:SetText(Notify:SoundLabel(Notify:SoundChoice())) end
        refresh()
        btn:SetScript("OnShow", refresh)
        btn:SetScript("OnClick", function(self)
            local BigMap = AlchemyGPS.Modules.Map.BigMap
            if not (BigMap and BigMap.OpenMenu) then return end
            local cur = Notify:SoundChoice()
            local items = {}
            local function add(choice)
                items[#items + 1] = { Notify:SoundLabel(choice), function()
                    Core:SetOpt("CompleteSound", choice)
                    refresh()
                    Notify:PlaySound(choice)
                end, choice == cur }
            end
            add(0)
            for i = 1, #Notify.SOUNDS do add(i) end
            add("random")
            BigMap.OpenMenu(self, items)
        end)
        local play = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        play:SetSize(60, 20)
        play:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        play:SetText("Play")
        play:SetScript("OnClick", function() Notify:PlaySound() end)
        y = y - 28
        -- 2026-11-18 (user request, from Carbonite): progress to the group.
        addCheckbox(content, y, "Tell my party / raid in chat as my objectives progress",
            function() return Core:Opt("GroupProgressMsg") == true end,
            function(value) Core:SetOpt("GroupProgressMsg", value) end)
        y = y - 30
        addSlider(content, y, "Say it every this many kills / items", 1, 10, 1,
            function() return Core:Opt("GroupProgressEvery") or 1 end,
            function(v) Core:SetOpt("GroupProgressEvery", v) end, "%d")
        y = y - 46
        -- 2026-11-18 (user request, from Carbonite): auto-watch.
        -- 2026-11-18 (user request, from Carbonite): Quest/QuestTooltips.lua.
        addCheckbox(content, y, "Quest progress on mob and item tooltips",
            function() return Core:Opt("QuestTooltips") ~= false end,
            function(value) Core:SetOpt("QuestTooltips", value) end)
        y = y - 26
        addCheckbox(content, y, "Track a quest again when it progresses",
            function() return Core:Opt("AutoWatchProgress") ~= false end,
            function(value) Core:SetOpt("AutoWatchProgress", value) end)
        y = y - 26
        addCheckbox(content, y, "Stop tracking a quest once it's ready to hand in",
            function() return Core:Opt("AutoUnwatchDone") == true end,
            function(value) Core:SetOpt("AutoUnwatchDone", value) end)
        y = y - 26
    end

    -- 2026-11-18 (user request, from Carbonite): Quest/QuestDetails.lua.
    y = y - 10
    y = addHeader(content, y, "Quest text")
    addCheckbox(content, y, "Show quest text in a panel beside the list",
        function() return Core:Opt("ListTextSide") ~= false end,
        function(value) Core:SetOpt("ListTextSide", value) end)
    y = y - 26
    addCheckbox(content, y, "Parchment background",
        function() return Core:Opt("DetailsParchment") ~= false end,
        function(value) Core:SetOpt("DetailsParchment", value) end)
    y = y - 28
    do
        local Details = AlchemyGPS.Modules.Quest.Details
        local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 8, y - 4)
        label:SetText("Text colour")
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetSize(210, 20)
        btn:SetPoint("TOPLEFT", 110, y)
        local function refresh()
            local cur = Core:Opt("DetailsColor") or "auto"
            for _, c in ipairs(Details and Details.COLOR_CHOICES or {}) do
                if c.id == cur then btn:SetText(c.label) end
            end
        end
        refresh()
        btn:SetScript("OnShow", refresh)
        btn:SetScript("OnClick", function(self)
            local BigMap = AlchemyGPS.Modules.Map.BigMap
            if not (BigMap and BigMap.OpenMenu and Details) then return end
            local cur = Core:Opt("DetailsColor") or "auto"
            local items = {}
            for _, c in ipairs(Details.COLOR_CHOICES) do
                items[#items + 1] = { c.label, function()
                    Core:SetOpt("DetailsColor", c.id)
                    refresh()
                end, c.id == cur }
            end
            BigMap.OpenMenu(self, items)
        end)
        y = y - 30
    end
    addSlider(content, y, "Quest text size", 0.7, 1.5, 0.05,
        function() return Core:Opt("DetailsScale") or 1 end,
        function(v) Core:SetOpt("DetailsScale", v) end, "%.2f")
    y = y - 46

    y = y - 8
    local trackAll = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    trackAll:SetSize(150, 22)
    trackAll:SetPoint("TOPLEFT", 4, y)
    trackAll:SetText("Track all quests")
    trackAll:SetScript("OnClick", function()
        local State = AlchemyGPS.Modules.Quest.State
        if State then State:WatchAll() end
    end)

    local list = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    list:SetSize(150, 22)
    list:SetPoint("TOPLEFT", 162, y)
    list:SetText("Open the quest list")
    list:SetScript("OnClick", function()
        local List = AlchemyGPS.Modules.Quest.List
        if List then List:Toggle() end
    end)

    local unhide = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    unhide:SetSize(308, 22)
    unhide:SetPoint("TOPLEFT", 4, y - 26)
    local function unhideLabel()
        local Pins = AlchemyGPS.Modules.Quest.Pins
        local n = Pins and Pins:NumHidden() or 0
        unhide:SetText(n > 0 and ("Show the %d hidden quest%s on the map again"):format(n, n == 1 and "" or "s")
            or "No quests hidden from the map")
        unhide:SetEnabled(n > 0)
    end
    unhide:SetScript("OnClick", function()
        local Pins = AlchemyGPS.Modules.Quest.Pins
        if Pins then Pins:UnhideAll() end
        unhideLabel()
    end)
    unhide:SetScript("OnShow", unhideLabel)
    unhideLabel()
    y = y - 26

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 4, y - 30)
    hint:SetWidth(330)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tracker: click a quest to route to it, right-click to collapse, "
        .. "Shift-click to untrack. Click a zone heading to fold it, Shift-click it to "
        .. "untrack the whole zone. Right-click a quest pin on the map to hide one of its quests.\n\n"
        .. "Quest item hotkey: Key Bindings > Alchemy GPS > \"Use the nearest quest's item\", "
        .. "or type /gps quest key F.\n\n"
        .. "Quest map pins are toggled from the map's Filter button.")

    content:SetHeight(-y + 30 + 130)
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

    local function setWindowSkin(id)
        AlchemyGPS.Skin:Set(id)
        if win then win:ApplySkin() end
        -- The quest tracker is built on the same small-window
        -- chrome as this window, so Skin:ResetWindows can't reach
        -- it either.
        local Tracker = AlchemyGPS.Modules.Quest and AlchemyGPS.Modules.Quest.Tracker
        if Tracker and Tracker.Win then Tracker.Win:ApplySkin() end
    end

    -- 2026-11-18 (user request: every theme on either map): one list -
    -- the window skins and the map themes (Map/BigMapThemes.lua) - in
    -- both rows. A skin picked for the minimap is the window skin, worn
    -- by every window, as the old "Window Skin" row did.
    local Themes = AlchemyGPS.Modules.Map and AlchemyGPS.Modules.Map.BigMapThemes
    local BigMap = AlchemyGPS.Modules.Map and AlchemyGPS.Modules.Map.BigMap
    if Themes and BigMap then
        local function items(forBig)
            local list = {}
            for _, t in ipairs(Themes:GetList(forBig)) do
                local bg, accent = Themes:Preview(t.id)
                list[#list + 1] = { id = t.id, label = t.name, bg = bg, accent = accent }
            end
            return list
        end
        y = buildCategoryRow(child, y, "Minimap Theme (a window skin here styles every window)", items(false),
            function() return BigMap:MiniThemeChoice() end,
            function(id)
                if type(id) == "string" then
                    BigMap:SetMiniThemeId(nil)
                    setWindowSkin(id)
                else
                    BigMap:SetMiniThemeId(id)
                end
            end)
        y = buildCategoryRow(child, y, "Big Map Theme (when the map is big)", items(true),
            function() return BigMap:ThemeId() end,
            function(id) BigMap:SetThemeId(id) end)
    else
        y = buildCategoryRow(child, y, "Window Skin", buildWindowSkinItems(),
            function() return AlchemyGPS.db.profile.Skin and AlchemyGPS.db.profile.Skin.Name end,
            setWindowSkin)
    end

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
        -- 2026-11-16: above the map, which now sits in DIALOG strata.
        strata = "FULLSCREEN_DIALOG",
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

    local questsPanel = CreateFrame("Frame", nil, win.content)
    questsPanel:SetPoint("TOPLEFT", 0, -30)
    questsPanel:SetPoint("BOTTOMRIGHT", 0, 0)

    local mapPanel = CreateFrame("Frame", nil, win.content)
    mapPanel:SetPoint("TOPLEFT", 0, -30)
    mapPanel:SetPoint("BOTTOMRIGHT", 0, 0)

    local panels = { general = generalPanel, map = mapPanel, quests = questsPanel, style = stylePanel }

    local tabBar = AlchemyGPS.UI.TabBar:New{
        parent = win.content,
        name = "AlchemyGPSSettingsTabs",
        width = 364,
        anchor = { point = "TOPLEFT", x = 0, y = 0 },
        tabs = {
            { id = "general", label = "General" },
            { id = "map",     label = "Map" },
            { id = "quests",  label = "Quests" },
            { id = "style",   label = "Style" },
        },
        selected = "general",
        onSelect = function(_, id)
            for panelId, panel in pairs(panels) do
                if panelId == id then panel:Show() else panel:Hide() end
            end
        end,
    }
    stylePanel:Hide()
    questsPanel:Hide()
    mapPanel:Hide()

    buildGeneral(generalPanel)
    buildMap(mapPanel)
    buildQuests(questsPanel)
    buildStyle(stylePanel)

    AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(win, UIParent, { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })

    return win
end

function SettingsWindow:Refresh()
    for _, entry in ipairs(checkboxes) do
        entry.cb:SetChecked(entry.get() and true or false)
    end
    for _, entry in ipairs(sliders) do entry.refresh() end
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

-- Quest options also change from outside this window (the tracker's
-- own close and Auto buttons, /gps quest ...); keep the Quests tab's
-- checkboxes honest when they do.
AlchemyGPS.Core.EventBus:Subscribe("QUEST_OPTION_CHANGED", function()
    if win then SettingsWindow:Refresh() end
end)
