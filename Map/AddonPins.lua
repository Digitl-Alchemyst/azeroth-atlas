-- Alchemy GPS | Map/AddonPins.lua
---------------------------------------------------------------------------------------
-- Other addons' world map pins on the big map (2026-11-18, user
-- request, from Carbonite: "Bring Blizzard's map pins in - moves
-- anything other addons draw on Blizzard's world map onto the big
-- Carbonite map").
--
-- Most addons put their pins on Blizzard's world map through the
-- HereBeDragons-Pins library (Questie, GatherMate2, HandyNotes and its
-- plugins, TomTom, FarmHud...). The library keeps every pin in one
-- table - pins.worldmapPins[iconFrame] = { x, y (world yards),
-- instanceID, uiMapID, worldMapShowFlag } - and, while Blizzard's map
-- is open, parents each icon frame to a pin of its own on that map.
-- While the big map is open (and Blizzard's isn't), this borrows the
-- same icon frames onto it, so they keep their own look, tooltips and
-- clicks; closing the big map hands them back (and Blizzard's map takes
-- them again whenever it opens).
--
-- Which pins show, following the library's show flags: a pin made for
-- one zone only (flag 0 or less) while that zone is the map's current
-- one; the rest anywhere on their continent.
-- Pins drawn some other way (an addon's own Blizzard map data provider)
-- can't be read back, and stay on Blizzard's map.
-- On / off: the map's Filter menu (and Settings > Map), "Other addons'
-- pins (big map)".
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local MinimapEngine = AlchemyGPS.Map

local REFRESH = 0.25     -- seconds between full passes while the view is still
local held = {}          -- [icon] = true while it's on our map
local placeCache = setmetatable({}, { __mode = "k" })   -- [data] = { key, wx, wy, cont, mapId }

local function libs()
    local LS = _G.LibStub
    if not LS then return nil end
    local pins = LS("HereBeDragons-Pins-2.0", true)
    local hbd = LS("HereBeDragons-2.0", true)
    if not pins or not hbd or type(pins.worldmapPins) ~= "table" then return nil end
    return pins, hbd
end

local function filterOn()
    local FilterMenu = AlchemyGPS.Modules.Map.FilterMenu
    return not FilterMenu or FilterMenu.IsFilterOn("AddonPins")
end

local function bigShown()
    local BigMap = AlchemyGPS.Modules.Map.BigMap
    return BigMap and BigMap.IsBig and BigMap:IsBig() or false
end

local function blizzardMapShown()
    return _G.WorldMapFrame and _G.WorldMapFrame:IsShown() or false
end

-- Hand every borrowed icon back: hidden and unparented, as the library
-- leaves them when its own pin lets go (worldmapProviderPin:OnReleased).
function MinimapEngine:ReleaseAddonPins()
    local any = false
    local host = self.AddonPinHost
    for icon in pairs(held) do
        -- One Blizzard's map has taken back meanwhile is left alone.
        if icon:GetParent() == host then
            icon:Hide()
            icon:SetParent(UIParent)
            icon:ClearAllPoints()
            any = true
        end
        held[icon] = nil
    end
    self.AddonPinKey = nil
    if any and blizzardMapShown() then
        local pins = libs()
        if pins and pins.worldmapProvider and pins.worldmapProvider.RefreshAllData then
            pcall(pins.worldmapProvider.RefreshAllData, pins.worldmapProvider)
        end
    end
end

-- World position on our map for one pin, cached while it doesn't move.
local function place(engine, hbd, data)
    local key = ("%s|%s|%s|%s"):format(tostring(data.x), tostring(data.y), tostring(data.uiMapID), tostring(data.instanceID))
    local c = placeCache[data]
    if c and c.key == key then return c end
    c = { key = key }
    placeCache[data] = c
    local mapId, zx, zy = data.uiMapID, nil, nil
    if mapId then
        zx, zy = hbd:GetZoneCoordinatesFromWorld(data.x, data.y, mapId)
    else
        -- A pin given in world coordinates only: the zone it falls in.
        for cont = 1, engine.ContCnt or 0 do
            for _, id in ipairs(engine.MapZones[cont] or {}) do
                local ax, ay = hbd:GetZoneCoordinatesFromWorld(data.x, data.y, id)
                if ax and ax >= 0 and ax <= 1 and ay >= 0 and ay <= 1 then
                    mapId, zx, zy = id, ax, ay
                    break
                end
            end
            if zx then break end
        end
    end
    if not zx or not mapId then return c end
    mapId = engine:CanonicalizeMapID(mapId) or mapId
    local wx, wy = engine:GetWorldPos(mapId, zx * 100, zy * 100)
    if wx then
        c.wx, c.wy, c.cont, c.mapId = wx, wy, engine:FindContinent(mapId), mapId
    end
    return c
end

function MinimapEngine:UpdateAddonPins()
    if not self.Frm or not self.Cont or not filterOn() or not bigShown() or blizzardMapShown() then
        if next(held) then self:ReleaseAddonPins() end
        return
    end
    local pins, hbd = libs()
    if not pins then return end

    local now = GetTime()
    local key = ("%s|%.1f|%.1f|%.5f|%d|%d"):format(tostring(self.MapId), self.MapPosXDraw or 0,
        self.MapPosYDraw or 0, self.ScaleDraw or 0, self.MapW or 0, self.MapH or 0)
    if key == self.AddonPinKey and now < (self.AddonPinAt or 0) then return end
    self.AddonPinKey, self.AddonPinAt = key, now + REFRESH

    local host = self.AddonPinHost
    if not host then
        host = CreateFrame("Frame", nil, self.Frm)
        host:SetAllPoints(self.Frm)
        host:EnableMouse(false)
        self.AddonPinHost = host
    end
    host:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + (self.SERVICE_LEVEL_OFFSET or 6) + 2)

    local scale, cw, ch = self.ScaleDraw, self.MapW, self.MapH
    local seen = {}
    for icon, data in pairs(pins.worldmapPins) do
        local c = type(data) == "table" and data.x and place(self, hbd, data)
        local show = c and c.wx and c.cont == self.Cont
        if show and (data.worldMapShowFlag or 0) <= 0 then
            show = c.mapId == self.MapId
        end
        local sx, sy
        if show then
            sx = (c.wx - self.MapPosXDraw) * scale + cw * .5
            sy = (c.wy - self.MapPosYDraw) * scale + ch * .5
            show = sx > 0 and sx < cw and sy > 0 and sy < ch
        end
        if show then
            seen[icon] = true
            if not held[icon] or icon:GetParent() ~= host then
                icon:SetParent(host)
                held[icon] = true
            end
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", host, "TOPLEFT", sx, -sy - (self.TitleH or 0))
            icon:Show()
        end
    end
    -- Gone from view, or removed by their addon: hand back.
    for icon in pairs(held) do
        if icon:GetParent() ~= host then
            held[icon] = nil
        elseif not seen[icon] then
            icon:Hide()
            if not pins.worldmapPins[icon] then
                icon:SetParent(UIParent)
                icon:ClearAllPoints()
                held[icon] = nil
            end
        end
    end
end
