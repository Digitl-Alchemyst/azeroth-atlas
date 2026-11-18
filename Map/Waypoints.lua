-- Alchemy GPS | Map/Waypoints.lua
---------------------------------------------------------------------------------------
-- Waypoints and TomTom emulation (2026-11-18, user request, from
-- Carbonite: "Pretends to be TomTom, so /way and other addons (Questie,
-- guides) can send waypoints to Carbonite's arrow").
--
-- A list of waypoints, one of which is the map's goto marker (and so
-- what the arrow, the ant trail and travel routing follow). When that
-- one is reached or cleared, the closest of the rest takes over - like
-- TomTom's "autoqueue". The others show on the map as dimmer pins.
--
-- Carbonite's version: Modules/Integrations/TomTom.lua and
-- TomTomWaypoints.lua - a global TomTom table carrying TomTom's API, and
-- TomTom's slash commands. The same here, unless the real TomTom is
-- installed and enabled (then it stays in charge, and /gps way still
-- works). TomTom's API as other addons call it:
--   TomTom:AddWaypoint(mapId, x, y, opts)  x, y 0-1; opts.title,
--     opts.crazy (false: don't make it the arrow's), opts.silent
--     -> uid (a table: uid[1] mapId, uid[2] x, uid[3] y, uid.title)
--   TomTom:AddZWaypoint(c, z, x, y, desc)  (old: z is a map ID, x, y 0-100)
--   TomTom:AddWaypointToCurrentZone(x, y, desc)  x, y 0-100
--   TomTom:RemoveWaypoint(uid), :ClearAllWaypoints(), :SetCrazyArrow(uid),
--   :SetClosestWaypoint(), :GetClosestWaypoint(), :WaypointExists(m, x,
--   y, desc), :IsValidWaypoint(uid), :GetKey(uid), :GetKeyArgs(m, x, y,
--   title), :GetCurrentPlayerPosition(), :GetCurrentCoords(),
--   :DefaultCallbacks(), :UIDIsSaved(uid)
-- Callbacks (opts.callbacks: tooltips, distance alerts) are accepted and
-- ignored, as Carbonite's are when nothing maps onto them.
-- Slash commands (TomTom's):
--   /way [zone | #mapId] x y [description]   (also /tway, /gps way ...)
--   /way list         every waypoint
--   /way reset all    clear them all   (/way reset <zone>: that zone's)
--   /cway             make the closest one the arrow's
--   /wayb             a waypoint where you stand now ("Wayback")
-- On / off: Settings > Map, Navigation, "Act as TomTom"
-- (profile.EmulateTomTom) - a /reload applies it.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local W = {}
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}
AlchemyGPS.Modules.Map.Waypoints = W

local list = {}
W.List = list

local function engine() return AlchemyGPS.Modules.Map.MinimapEngine end

local function say(fmt, ...)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAlchemy GPS|r: " .. fmt:format(...))
    end
end

local function zoneName(mapId)
    local E = engine()
    if E and E.MapName then
        local ok, n = pcall(E.MapName, E, mapId)
        if ok and n then return n end
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    return info and info.name or ("Map " .. tostring(mapId))
end

local function describe(uid)
    return ("%s (%s %.1f, %.1f)"):format(uid.title or "Waypoint", zoneName(uid[1]), uid[2] * 100, uid[3] * 100)
end

-- World position (engine coordinates) for a waypoint, once the map's
-- catalog is in.
local function resolve(uid)
    if uid.wx then return true end
    local E = engine()
    if not E or not E.MapZones then return false end
    local wx, wy = E:GetWorldPos(uid[1], uid[2] * 100, uid[3] * 100)
    local cont = wx and E:FindContinent(uid[1])
    if not cont then return false end
    uid.wx, uid.wy, uid.cont = wx, wy, cont
    return true
end

function W:Resolve(uid) return resolve(uid) end

local function indexOf(uid)
    for i, u in ipairs(list) do
        if u == uid then return i end
    end
end

---------------------------------------------------------------------------------------
-- The arrow's waypoint
---------------------------------------------------------------------------------------

-- Make uid the map's goto (what the arrow follows). Until the map is
-- ready it waits (the ticker at the bottom tries again).
function W:SetActive(uid)
    if not uid or not indexOf(uid) then return end
    local E = engine()
    if not E or not resolve(uid) then
        self.Pending = uid
        return
    end
    self.Pending = nil
    E.GotoWX, E.GotoWY, E.GotoCont = uid.wx, uid.wy, uid.cont
    E.GotoName, E.GotoUid = uid.title or "Waypoint", uid
    E.ArrowScroll = 0
end

local function playerPos()
    local Q = AlchemyGPS.Modules.Quest
    if Q and Q.Routing then return Q.Routing:GetPlayerPos() end
end

function W:GetClosest()
    local px, py, pcont = playerPos()
    local best, bestD
    for _, uid in ipairs(list) do
        if resolve(uid) then
            local d = math.huge / 2
            if px and uid.cont == pcont then
                d = (uid.wx - px) ^ 2 + (uid.wy - py) ^ 2
            end
            if not bestD or d < bestD then best, bestD = uid, d end
        end
    end
    return best or list[1]
end

-- MinimapEngine:ClearGoto calls this with the waypoint that was the goto
-- (nil for a goto set from the map): it's done with, and the closest of
-- the rest takes over.
function W:OnGotoCleared(uid)
    if self.Clearing then return end
    local i = uid and indexOf(uid)
    if i then table.remove(list, i) end
    if #list > 0 then self:SetActive(self:GetClosest()) end
end

---------------------------------------------------------------------------------------
-- Adding and removing
---------------------------------------------------------------------------------------

function W:Find(m, x, y, title)
    for _, u in ipairs(list) do
        if u[1] == m and math.abs(u[2] - x) < 1e-4 and math.abs(u[3] - y) < 1e-4
                and (title == nil or u.title == title) then
            return u
        end
    end
end

-- mapId, x and y 0-1. Returns the uid.
function W:Add(m, x, y, opts)
    m, x, y = tonumber(m), tonumber(x), tonumber(y)
    if not m or not x or not y then return nil end
    opts = type(opts) == "table" and opts or {}
    local title = opts.title or opts.desc
    local uid = self:Find(m, x, y, title)
    if not uid then
        uid = { m, x, y, title = title, from = opts.from, opts = opts }
        list[#list + 1] = uid
        if not opts.silent then say("waypoint added: %s", describe(uid)) end
    end
    local E = engine()
    if opts.crazy ~= false or not (E and E.GotoWX) then self:SetActive(uid) end
    return uid
end

function W:Remove(uid)
    local i = uid and indexOf(uid)
    if not i then return end
    local E = engine()
    if E and E.GotoUid == uid then
        E:ClearGoto()        -- removes it, and the next one takes over
    else
        table.remove(list, i)
    end
end

function W:ClearAll()
    local E = engine()
    for i = #list, 1, -1 do list[i] = nil end
    self.Pending = nil
    if E and E.GotoUid then
        self.Clearing = true
        E:ClearGoto()
        self.Clearing = nil
    end
end

---------------------------------------------------------------------------------------
-- /way
---------------------------------------------------------------------------------------

local function norm(s)
    return (s or ""):lower():gsub("^the ", ""):gsub("[^%w]", "")
end

-- A zone by name: exact, then starts-with, then contains.
local function findZone(text)
    local want = norm(text)
    if want == "" then return nil end
    local E = engine()
    local ids = {}
    for cont = 1, E and E.ContCnt or 0 do
        for _, id in ipairs(E.MapZones[cont] or {}) do ids[#ids + 1] = id end
    end
    for pass = 1, 3 do
        for _, id in ipairs(ids) do
            local n = norm(zoneName(id))
            if (pass == 1 and n == want) or (pass == 2 and n:sub(1, #want) == want)
                    or (pass == 3 and n:find(want, 1, true)) then
                return id
            end
        end
    end
end

local function currentMap()
    local E = engine()
    local m = E and E.GetDisplayableMapForPlayer and E:GetDisplayableMapForPlayer()
    if (not m or m == 0) and C_Map and C_Map.GetBestMapForUnit then m = C_Map.GetBestMapForUnit("player") end
    return m ~= 0 and m or nil
end

local function playerMapPos()
    local m = currentMap()
    if not m or not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return m, x, y
end

local function wayHelp()
    say("/way [zone or #mapID] x y [description] - set a waypoint")
    say("/way list - list them; /way reset all - clear them; /way reset <zone> - clear a zone's")
    say("/cway - point the arrow at the closest; /wayb - a waypoint where you stand")
end

function W:HandleWay(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = msg:lower()
    if msg == "" or lower == "help" then return wayHelp() end

    if lower == "list" then
        if #list == 0 then return say("no waypoints") end
        local E = engine()
        for i, uid in ipairs(list) do
            say("%d. %s%s", i, describe(uid), (E and E.GotoUid == uid) and " |cff66ff66(arrow)|r" or "")
        end
        return
    end

    local resetArg = lower:match("^reset%s*(.*)$")
    if resetArg then
        if resetArg == "" or resetArg == "all" then
            local n = #list
            self:ClearAll()
            return say("cleared %d waypoint%s", n, n == 1 and "" or "s")
        end
        local zone = resetArg:match("^#(%d+)$") and tonumber(resetArg:match("^#(%d+)$")) or findZone(resetArg)
        if not zone then return say("no zone called %q", resetArg) end
        local n = 0
        for i = #list, 1, -1 do
            if list[i][1] == zone then self:Remove(list[i]); n = n + 1 end
        end
        return say("cleared %d waypoint%s in %s", n, n == 1 and "" or "s", zoneName(zone))
    end

    -- "45.2, 67.8" and "45.2,67.8" read the same as "45.2 67.8".
    local tokens = {}
    for tok in msg:gsub(",", " "):gmatch("%S+") do tokens[#tokens + 1] = tok end
    local at
    for i = 1, #tokens - 1 do
        if tonumber(tokens[i]) and tonumber(tokens[i + 1]) then at = i; break end
    end
    if not at then return wayHelp() end
    local x, y = tonumber(tokens[at]), tonumber(tokens[at + 1])
    local zoneText = table.concat(tokens, " ", 1, at - 1)
    local desc = table.concat(tokens, " ", at + 2)

    local m
    if zoneText == "" then
        m = currentMap()
        if not m then return say("can't tell which zone you're in - name it: /way <zone> x y") end
    elseif zoneText:match("^#%d+$") then
        m = tonumber(zoneText:sub(2))
    else
        m = findZone(zoneText)
        if not m then return say("no zone called %q", zoneText) end
    end
    if x < 0 or x > 100 or y < 0 or y > 100 then return say("coordinates go from 0 to 100") end
    self:Add(m, x / 100, y / 100, { title = desc ~= "" and desc or nil, from = "/way" })
end

function W:WayBack()
    local m, x, y = playerMapPos()
    if not m then return say("can't place you on the map here") end
    self:Add(m, x, y, { title = "Wayback", from = "/wayb" })
end

---------------------------------------------------------------------------------------
-- TomTom
---------------------------------------------------------------------------------------

local function realTomTom()
    local enabled = false
    pcall(function()
        local me = UnitName("player")
        local state
        if C_AddOns and C_AddOns.GetAddOnEnableState then
            state = C_AddOns.GetAddOnEnableState("TomTom", me)
        elseif GetAddOnEnableState then
            state = GetAddOnEnableState(me, "TomTom")
        end
        enabled = (tonumber(state) or 0) > 0
    end)
    return enabled
end

local fakeTomTom

local function buildTomTom()
    local T = { version = "v40200-AlchemyGPS", waypoints = {}, AlchemyGPS = true }
    T.profile = {
        general     = { announce = false },
        minimap     = { enable = true },
        worldmap    = { enable = true },
        arrow       = { autoqueue = true, arrival = 15, enablePing = false },
        persistence = { savewaypoints = false, cleardistance = 0 },
    }
    -- T.waypoints[mapId][key] = uid, as the real one keeps it.
    local function track(uid)
        if not uid then return end
        T.waypoints[uid[1]] = T.waypoints[uid[1]] or {}
        T.waypoints[uid[1]][T:GetKey(uid)] = uid
    end
    local function untrack(uid)
        local z = uid and T.waypoints[uid[1]]
        if z then z[T:GetKey(uid)] = nil end
    end

    function T:AddWaypoint(m, x, y, opts)
        local uid = W:Add(m, x, y, opts)
        track(uid)
        return uid
    end
    function T:AddMFWaypoint(m, _, x, y, opts) return self:AddWaypoint(m, x, y, opts) end
    T.SetCustomMFWaypoint = T.AddMFWaypoint
    function T:AddZWaypoint(_, z, x, y, desc, _, _, _, callbacks)
        return self:AddWaypoint(z, (tonumber(x) or 0) / 100, (tonumber(y) or 0) / 100,
            { title = desc, callbacks = callbacks })
    end
    function T:SetCustomWaypoint(c, z, x, y, callbacks)
        return self:AddZWaypoint(c, z, x, y, nil, nil, nil, nil, callbacks)
    end
    function T:AddWaypointToCurrentZone(x, y, desc)
        local m = currentMap()
        if not m then return nil end
        return self:AddWaypoint(m, (tonumber(x) or 0) / 100, (tonumber(y) or 0) / 100, { title = desc })
    end
    function T:RemoveWaypoint(uid)
        untrack(uid)
        W:Remove(uid)
    end
    function T:ClearAllWaypoints()
        T.waypoints = {}
        W:ClearAll()
    end
    function T:SetCrazyArrow(uid) W:SetActive(uid) end
    function T:SetClosestWaypoint()
        local uid = W:GetClosest()
        if uid then W:SetActive(uid) end
        return uid
    end
    function T:GetClosestWaypoint() return W:GetClosest() end
    function T:IsValidWaypoint(uid) return indexOf(uid) ~= nil end
    T.UIDIsSaved = function() return false end
    function T:GetKey(uid) return self:GetKeyArgs(uid[1], uid[2], uid[3], uid.title) end
    function T:GetKeyArgs(m, x, y, title)
        return ("%s:%d:%d:%s"):format(tostring(m), math.floor((x or 0) * 10000 + .5),
            math.floor((y or 0) * 10000 + .5), tostring(title))
    end
    function T:WaypointExists(m, x, y, desc) return W:Find(tonumber(m), tonumber(x), tonumber(y), desc) ~= nil end
    function T:GetCurrentPlayerPosition() return playerMapPos() end
    function T:GetCurrentCoords()
        local _, x, y = playerMapPos()
        return x, y
    end
    function T:DefaultCallbacks() return {} end
    return T
end

local function bindSlash()
    _G.SLASH_ALCHEMYGPS_WAY1 = "/way"
    _G.SLASH_ALCHEMYGPS_WAY2 = "/tway"
    _G.SLASH_ALCHEMYGPS_WAY3 = "/tomtomway"
    _G.SlashCmdList["ALCHEMYGPS_WAY"] = function(msg) W:HandleWay(msg) end
    _G.SLASH_ALCHEMYGPS_CWAY1 = "/cway"
    _G.SLASH_ALCHEMYGPS_CWAY2 = "/closestway"
    _G.SlashCmdList["ALCHEMYGPS_CWAY"] = function()
        local uid = W:GetClosest()
        if uid then W:SetActive(uid); say("arrow: %s", describe(uid)) else say("no waypoints") end
    end
    _G.SLASH_ALCHEMYGPS_WAYB1 = "/wayb"
    _G.SLASH_ALCHEMYGPS_WAYB2 = "/wayback"
    _G.SlashCmdList["ALCHEMYGPS_WAYB"] = function() W:WayBack() end
end

-- Installed as this file loads - so addons loading after this one find
-- TomTom when they look - unless the real one is on. The setting is
-- only readable once the saved settings are in: switched off, the
-- emulation is taken down again at login.
if not realTomTom() and not _G.TomTom then
    fakeTomTom = buildTomTom()
    _G.TomTom = fakeTomTom
    bindSlash()
    W.Emulating = true
end

local SlashCommands = AlchemyGPS.Core.SlashCommands
if SlashCommands and SlashCommands.Register then
    SlashCommands:Register("way", function(rest) W:HandleWay(rest) end,
        "set a waypoint: /gps way [zone] x y [description] (also list, reset all)")
end

local ticker = CreateFrame("Frame")
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
    local db = AlchemyGPS.db
    if W.Emulating and db and db.profile.EmulateTomTom == false and _G.TomTom == fakeTomTom then
        _G.TomTom = nil
        _G.SlashCmdList["ALCHEMYGPS_WAY"] = nil
        _G.SlashCmdList["ALCHEMYGPS_CWAY"] = nil
        _G.SlashCmdList["ALCHEMYGPS_WAYB"] = nil
        _G.SLASH_ALCHEMYGPS_WAY1, _G.SLASH_ALCHEMYGPS_WAY2, _G.SLASH_ALCHEMYGPS_WAY3 = nil, nil, nil
        _G.SLASH_ALCHEMYGPS_CWAY1, _G.SLASH_ALCHEMYGPS_CWAY2 = nil, nil
        _G.SLASH_ALCHEMYGPS_WAYB1, _G.SLASH_ALCHEMYGPS_WAYB2 = nil, nil
        W.Emulating = false
    end
end)
-- A waypoint added before the map was ready becomes the goto once it is.
local waitAt = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    waitAt = waitAt + elapsed
    if waitAt < 1 then return end
    waitAt = 0
    if W.Pending then W:SetActive(W.Pending) end
end)
