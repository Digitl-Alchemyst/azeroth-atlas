---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/BigMap.lua
--
-- 2026-11-17 (user request, "Feature from Leatrix"): what the map window
-- gets when it's big (M maximises it, or it's dragged wide):
--
--   Toolbar, top left:
--     My Map       back to where you are (stops browsing, re-centres)
--     Continents   Azeroth, Kalimdor, Eastern Kingdoms, Zephras Isle
--     Zones        the zones and cities of the continent on show
--     Dungeons     any dungeon or raid with a map, viewed from outside
--     Filters      the map's icon filters (Map/FilterMenu.lua)
--     Quests       pops the quest list out, docked to the map's side
--   Footer, bottom centre: your coordinates and the cursor's.
--   Hover label, top centre: the zone under the cursor with its level
--     range and fishing skill (Map/Data/ZoneLevels.lua, Leatrix's data).
--   Theme: one of Leatrix Maps' 15 map themes, or the plain window skin
--     (Settings > Style > Big Map Theme; Map/BigMapThemes.lua). Blizzard,
--     the game's own frame border art, is the default.
--
-- Browsing itself (what the map shows) is MinimapEngine:BrowseTo /
-- StopBrowse / ShowPlayer.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local BigMap = {}
AlchemyGPS.Modules.Map.BigMap = BigMap

local MIN_BIG_WIDTH = 480     -- a window at least this wide counts as big
local BAR_H = 20
local MENU_ROWS = 22           -- rows per column before a menu wraps

local function engine() return AlchemyGPS.Modules.Map.MinimapEngine end
local function themes() return AlchemyGPS.Modules.Map.BigMapThemes end
local function opts() return AlchemyGPS.Modules.Map.MinimapWindow:DB().profile end

---------------------------------------------------------------------------------------
-- Popup menu (one at a time, same look as the map's right-click menu)
---------------------------------------------------------------------------------------

local menu

local function closeMenu()
    if menu then menu:Hide() end
end
BigMap.CloseMenu = closeMenu

local function createMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "AlchemyGPSBigMapMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.rows = {}
    menu:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
            closeMenu()
        end
    end)
    tinsert(UISpecialFrames, "AlchemyGPSBigMapMenu")
    menu:Hide()
    return menu
end

-- items: { { text, onClick, current, header }, ... }
local function openMenu(owner, items)
    local m = createMenu()
    if m:IsShown() and m.owner == owner then closeMenu() return end
    m.owner = owner
    -- The big map theme's list colours, else the tooltip look.
    local T = themes()
    local bg, border, hlc
    if T then bg, border, hlc = T:MenuColors(BigMap) end
    if bg then
        m:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        m:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        m:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    else
        m:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        m:SetBackdropColor(0, 0, 0, 0.92)
        m:SetBackdropBorderColor(1, 1, 1, 1)
        hlc = { 0.4, 0.4, 0.8, 0.35 }
    end
    local ROW_H, COL_W, PAD = 16, 170, 8
    local cols = math.max(1, math.ceil(#items / MENU_ROWS))
    local rows = math.min(#items, MENU_ROWS)
    for i, it in ipairs(items) do
        local row = m.rows[i]
        if not row then
            row = CreateFrame("Button", nil, m)
            row:SetSize(COL_W - 4, ROW_H)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            row:SetHighlightTexture(hl)
            row.hl = hl
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetPoint("RIGHT", -2, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row:SetScript("OnClick", function(self)
                closeMenu()
                if self.onClick then self.onClick() end
            end)
            m.rows[i] = row
        end
        local col, r = math.floor((i - 1) / MENU_ROWS), (i - 1) % MENU_ROWS
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", m, "TOPLEFT", PAD + col * COL_W, -PAD - r * ROW_H)
        row.hl:SetColorTexture(hlc[1], hlc[2], hlc[3], hlc[4])
        row.onClick = it[2]
        row:SetEnabled(it[2] ~= nil)
        if it[4] then
            row.text:SetText(it[1])
            row.text:SetTextColor(0.6, 0.6, 0.6)
        elseif it[3] then
            row.text:SetText("|cff40ff40>|r " .. it[1])
            row.text:SetTextColor(1, 1, 1)
        else
            row.text:SetText(it[1])
            row.text:SetTextColor(1, 0.82, 0)
        end
        row:Show()
    end
    for i = #items + 1, #m.rows do m.rows[i]:Hide() end
    m:SetSize(PAD * 2 + cols * COL_W - 4, PAD * 2 + rows * ROW_H)
    m:ClearAllPoints()
    -- 2026-11-18 (user request): opens upward when there isn't room
    -- below the owner, so it never runs off the bottom of the screen.
    local bottom = owner:GetBottom()
    local ratio = owner:GetEffectiveScale() / m:GetEffectiveScale()
    if bottom and bottom * ratio - m:GetHeight() - 2 < 0 then
        m:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    else
        m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
    m:Show()
end
-- 2026-11-18: also used by the map's dungeon entrance icons (a list
-- when several dungeons share one entrance - MinimapEngine.lua).
BigMap.OpenMenu = openMenu

---------------------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------------------

local CONTINENTS = {
    { kind = "azeroth", name = "Azeroth" },
    { kind = "map", id = 12, name = "Kalimdor" },
    { kind = "map", id = 13, name = "Eastern Kingdoms" },
    { kind = "map", id = 2521, name = "Zephras Isle" },
}

local function continentMenu(owner)
    local E = engine()
    local items = {}
    for _, c in ipairs(CONTINENTS) do
        local current = (c.kind == "azeroth" and E.BrowseMapId == E.AZEROTH_MAP)
            or (c.id and E.BrowseMapId == c.id)
        items[#items + 1] = { c.name, function() E:BrowseTo(c.kind, c.id, c.name) end, current }
    end
    openMenu(owner, items)
end

-- The continent whose zones the Zones menu lists: the one on show, else yours.
local function zoneMenuContinent(E)
    local c = E.Cont
    if c and c >= 1 and c <= (E.ContCnt or 0) then return c end
    c = E.PlyrCont
    if c and c >= 1 and c <= (E.ContCnt or 0) then return c end
    return 2
end

local function zoneMenu(owner)
    local E = engine()
    local cont = zoneMenuContinent(E)
    local items = { { E.MapInfo[cont] and E.MapInfo[cont].Name or "Zones", nil, nil, true } }
    for _, z in ipairs(E:GetContinentZones(cont)) do
        local label = z.city and (z.name .. " |cffa0a0a0(city)|r") or z.name
        local lv = AlchemyGPS.Map.ZoneLevelText and AlchemyGPS.Map.ZoneLevelText(z.id)
        if lv then label = label .. " " .. lv end
        items[#items + 1] = { label, function() E:BrowseTo("map", z.id, z.name) end, E.MapId == z.id }
    end
    openMenu(owner, items)
end

local function dungeonMenu(owner)
    local E = engine()
    local items = {}
    for _, d in ipairs(E:GetBrowseDungeons()) do
        items[#items + 1] = { d.name, function() E:BrowseTo("dungeon", d.id, d.name) end, E.BrowseInstance == d.id }
    end
    if #items == 0 then items[1] = { "No dungeon maps found", nil, nil, true } end
    openMenu(owner, items)
end

---------------------------------------------------------------------------------------
-- Quest list, docked to the map
---------------------------------------------------------------------------------------

-- The docked quest list closes with the big map (2026-11-17, user
-- request: "we want both to close together"). Shrinking the map back to
-- small (M again) counts as closing the big map, not only hiding it.
function BigMap:CloseDockedList()
    local List = AlchemyGPS.Modules.Quest and AlchemyGPS.Modules.Quest.List
    if List and List.IsDocked and List:IsDocked() then
        List:Dock(nil)
        if List.Win then List.Win:Hide() end
    end
    -- A quest lit up from the list goes back to normal with it.
    local Pins = AlchemyGPS.Modules.Quest and AlchemyGPS.Modules.Quest.Pins
    if Pins and Pins.SetFocus then Pins:SetFocus(nil) end
end

function BigMap:ToggleQuests()
    local List = AlchemyGPS.Modules.Quest and AlchemyGPS.Modules.Quest.List
    if not List or not List.Dock then return end
    if List:IsDocked() and List.Win and List.Win:IsShown() then
        List:Dock(nil)
        List.Win:Hide()
    else
        List:Dock(self.Win.Frm)
    end
end

---------------------------------------------------------------------------------------
-- Toolbar, footer, hover label
---------------------------------------------------------------------------------------

local function barButton(parent, label, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(BAR_H)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    b.bg = bg
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    b.text = text
    b.hl = hl
    b:SetWidth(math.max(44, text:GetStringWidth() + 16))
    b:SetScript("OnClick", onClick)
    local tipTitle = label:gsub(" v$", "")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(tipTitle)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function BigMap:Attach(window, win, content)
    if self.Win then return end
    self.Window, self.Win, self.Content = window, win, content
    local f = win.Frm

    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(BAR_H)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", (win.BorderW or 4) + 4, -((win.TopH or 20) + 4))
    self.Bar = bar
    local prev
    self.Buttons = {}
    local function add(label, tip, onClick)
        local b = barButton(bar, label, tip, onClick)
        self.Buttons[#self.Buttons + 1] = b
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("LEFT", bar, "LEFT", 0, 0) end
        prev = b
        return b
    end
    self.HomeBut = add("My Map", "Back to where you are: stops browsing and puts you in the middle.",
        function() engine():ShowPlayer() end)
    -- Bronze while you're looking somewhere else (over any theme).
    local tint = self.HomeBut:CreateTexture(nil, "ARTWORK")
    tint:SetAllPoints()
    tint:SetColorTexture(0.6, 0.4, 0, 0.6)
    tint:Hide()
    self.HomeTint = tint
    add("Continents v", "Look at all of Azeroth or one continent.", function(b) continentMenu(b) end)
    add("Zones v", "Look at a zone or city on the continent on show.", function(b) zoneMenu(b) end)
    add("Dungeons v", "Look at a dungeon or raid map from outside.", function(b) dungeonMenu(b) end)
    add("Filters", "Choose which icons the map shows.", function(b)
        local FilterMenu = AlchemyGPS.Modules.Map.FilterMenu
        if FilterMenu then FilterMenu:Toggle(b, true) end
    end)
    self.QuestBut = add("Quests", "Pop the quest list out beside the map. Click again to put it away.",
        function() self:ToggleQuests() end)
    local w = 0
    for _, child in ipairs({ bar:GetChildren() }) do w = w + child:GetWidth() + 3 end
    bar:SetWidth(w)

    -- Footer: coordinates.
    local foot = CreateFrame("Frame", nil, f)
    foot:SetSize(300, 16)
    foot:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    local fbg = foot:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    fbg:SetColorTexture(0, 0, 0, 0.6)
    local ftext = foot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ftext:SetPoint("CENTER")
    ftext:SetTextColor(0.9, 0.9, 0.9)
    self.Foot, self.FootText, self.FootBg = foot, ftext, fbg

    -- Hover label: zone under the cursor and its levels.
    local hover = CreateFrame("Frame", nil, f)
    hover:SetSize(320, 34)
    hover:SetPoint("TOP", f, "TOP", 0, -((win.TopH or 20) + 4 + BAR_H + 6))
    local hname = hover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hname:SetPoint("TOP")
    hname:SetShadowOffset(1, -1)
    local hsub = hover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hsub:SetPoint("TOP", hname, "BOTTOM", 0, -2)
    hsub:SetShadowOffset(1, -1)
    hover:EnableMouse(false)
    self.Hover, self.HoverName, self.HoverSub = hover, hname, hsub

    local chrome = window.Chrome
    chrome[#chrome + 1] = bar
    chrome[#chrome + 1] = foot
    chrome[#chrome + 1] = hover
    bar:Hide() foot:Hide() hover:Hide()
end

function BigMap:IsBig()
    local win = self.Win
    if not win or not win.Frm:IsShown() then return false end
    return win:IsSizeMax() or (win.Frm:GetWidth() or 0) >= MIN_BIG_WIDTH
end

---------------------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------------------

-- The chosen theme id (0 = the window skin). Before themes existed the only
-- choice was the Blizzard frame on / off, so that answer carries over.
function BigMap:ThemeId()
    local o = opts()
    if o.BigMapTheme ~= nil then return o.BigMapTheme end
    if o.BlizzardBigMap == false then return 0 end
    local T = themes()
    return T and T.DEFAULT or 0
end

function BigMap:SetThemeId(id)
    opts().BigMapTheme = id
    self.AppliedTheme = nil     -- next tick repaints
end

-- 2026-11-18: the minimap's theme - a map theme's number, or 0 = the
-- window skin (which a skin picked for the minimap sets).
function BigMap:MiniThemeId()
    local id = opts().MinimapTheme
    return type(id) == "number" and id or 0
end

-- What the Minimap Theme row shows as picked.
function BigMap:MiniThemeChoice()
    local id = self:MiniThemeId()
    if id ~= 0 then return id end
    local sv = AlchemyGPS.db and AlchemyGPS.db.profile.Skin
    return (sv and sv.Name) or "Modern Dark"
end

function BigMap:SetMiniThemeId(id)
    opts().MinimapTheme = (type(id) == "number" and id ~= 0) and id or nil
    self.AppliedTheme = nil
end

-- The theme to wear now: the big one while big ("Same as the minimap" =
-- the minimap's), else the minimap's.
function BigMap:CurrentThemeId(big)
    local id = big and self:ThemeId() or 0
    if id == 0 then id = self:MiniThemeId() end
    return id
end

---------------------------------------------------------------------------------------
-- Every map tick (MinimapEngine:Update)
---------------------------------------------------------------------------------------

local function fmt(x, y)
    if not x or not y then return "--" end
    return ("%.1f, %.1f"):format(x, y)
end

function BigMap:Update()
    local win = self.Win
    if not win then return end
    local E = engine()
    local o = opts()
    local big = self:IsBig()

    -- Theme: the big map's while big, the minimap's while small
    -- (2026-11-18: any theme on either). Repainted when the theme, the
    -- size or the window skin under it changes.
    local T = themes()
    if T then
        local id = self:CurrentThemeId(big)
        local Skin = AlchemyGPS.Skin
        local sig = tostring(id) .. "|" .. tostring(Skin and Skin.Data)
        if sig ~= self.AppliedTheme then
            self.AppliedTheme = sig
            closeMenu()
            local ok, err = pcall(T.Apply, T, self, id)
            if not ok then print("|cffff6060Alchemy GPS|r map theme: " .. tostring(err)) end
        end
        if id ~= 0 then T:Tick(self) end
    end

    self.Bar:SetShown(big)
    if not big then closeMenu() end
    if self.WasBig and not big then
        self:CloseDockedList()
        -- 2026-11-17 (user request): back to the minimap is always back
        -- to "My Map" - wherever the big map was looking (another zone or
        -- continent, another dungeon level, a pan), it returns to you.
        local E2 = engine()
        if E2 then E2:ShowPlayer() end
    end
    self.WasBig = big
    if self.HomeTint then self.HomeTint:SetShown(E:IsBrowsing()) end

    -- Dungeon level bar sits under the toolbar while it's showing.
    local window = self.Window
    if window.LevelBar then
        local y = -((win.TopH or 20) + 4 + (big and (BAR_H + 4) or 0))
        if self._levelY ~= y then
            self._levelY = y
            window.LevelBar:ClearAllPoints()
            window.LevelBar:SetPoint("TOP", win.Frm, "TOP", 0, y)
        end
    end

    -- Cursor position (also needed for the hover label).
    local cwx, cwy = E:CursorWorldPos()
    local czone, czx, czy
    if cwx then
        if E.Cont == E.DUNGEON_CONT then
            local floorMap = E:GetViewMapId()
            czone = floorMap
            czx, czy = E:WorldToZone(floorMap, cwx, cwy)
        elseif E.WideView then
            czone, czx, czy = E:ZoneAtWorld(cwx, cwy)
        else
            czone = E.MapId
            czx, czy = E:WorldToZone(E.MapId, cwx, cwy)
            if czx and (czx < 0 or czx > 100 or czy < 0 or czy > 100) then
                czone, czx, czy = E:ZoneAtWorld(cwx, cwy)
            end
        end
    end

    local showCoords = big and o.BigMapCoords ~= false
    self.Foot:SetShown(showCoords)
    if showCoords then
        local player = (not E.PlyrPosUnknown and E.PlyrRZX) and fmt(E.PlyrRZX, E.PlyrRZY) or "--"
        local cursor = czx and fmt(czx, czy) or "--"
        local text = ("|cffffd100Player|r %s     |cffffd100Cursor|r %s"):format(player, cursor)
        if text ~= self._footText then
            self._footText = text
            self.FootText:SetText(text)
            self.Foot:SetWidth(self.FootText:GetStringWidth() + 20)
        end
    end

    -- Hover label: not in dungeons (the level bar names the floor there).
    local showHover = big and o.BigMapZoneLevels ~= false and czone and E.Cont ~= E.DUNGEON_CONT
    if showHover then
        local name = E:MapName(czone)
        local lv = AlchemyGPS.Map.ZoneLevelText and AlchemyGPS.Map.ZoneLevelText(czone)
        local fish = AlchemyGPS.Map.ZoneFishing and AlchemyGPS.Map.ZoneFishing(czone)
        local key = czone .. (lv or "")
        if key ~= self._hoverKey then
            self._hoverKey = key
            self.HoverName:SetText(lv and (name .. " " .. lv) or name)
            self.HoverSub:SetText(fish and ("Fishing: " .. fish) or "")
        end
    end
    self.Hover:SetShown(showHover and true or false)

    -- A dungeon picked from the menu with nothing to draw.
    if E.BrowseFailed then
        UIErrorsFrame:AddMessage(("No map to show for %s."):format(E.BrowseFailed), 1, 0.82, 0)
        E.BrowseFailed = nil
    end
end

-- The docked quest list goes with the map.
function BigMap:OnMapHidden()
    closeMenu()
    self:CloseDockedList()
    -- Closed while big: it opens again on you (same as shrinking).
    if self.WasBig then
        local E = engine()
        if E then E:ShowPlayer() end
    end
    self.WasBig = false
end
