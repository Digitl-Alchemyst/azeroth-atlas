-- Alchemy GPS | Quest / QuestRouting
-- Answers one question for everything else in the Quest module: where
-- should the player go next? No UI of its own - the arrow (HUDArrow.lua),
-- the tracker's distance column and sort order (QuestTracker.lua) and the
-- map window's route trail (Map/MinimapEngine.lua) all read from here.
--
--   Routing.Target      the current destination, or nil:
--                       { kind="quest"|"point", questID, objIndex,
--                         x, y (world), mId, cont, name, detail,
--                         inside, entrance, source, auto }
--   Routing.QuestInfo   [questID] = { res=, objIndex=, dist=, yards=, far= }
--                       for every tracked quest, refreshed about once a second
--   "QUEST_ROUTE_CHANGED" on the EventBus when the destination itself
--                       changes (not on every small position update)
--
-- Ported from Carbonite.Quests/Tracking.lua:
--   ResolveTrackTarget (:424)   the catalog-objective -> live -> catalog-
--                               endpoint fallback chain, and the swap to a
--                               dungeon's entrance for objectives inside an
--                               instance the player isn't in
--   LiveQuestPos (:278)         Blizzard's own waypoint/POI for a quest
--   CalcAutoTrack (:468)        "closest tracked objective wins"
-- and from Nx.Map:Update's player-speed sampling (MapEngine.lua:6553-6569).
--
-- Not ported, on purpose:
--   - Carbonite's Map:SetTarget pipeline and its zone-to-zone path
--     planner. This addon has neither; a destination here is one world
--     point, and one on another continent is reported as "far" rather
--     than routed through boats and zeppelins.
--   - RefineLiveMapId / the phased-map projection: both exist to feed
--     that path planner the right map id.
--   - The quest-area "blob" drawing (UpdateQuestBlob) - a Carbonite map
--     overlay with no counterpart here.
--
-- Positions are in the map engine's own world space (Map:GetWorldPos),
-- shared across a whole continent; one world unit is 4.575 yards.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest
local Map = AlchemyGPS.Map
local Api = Q.Api
local Catalog = Q.Catalog

local Routing = {}
Q.Routing = Routing

Routing.QuestInfo = {}
Routing.PlyrSpeed = 0

local YARDS_PER_WORLDUNIT = 4.575
Routing.YARDS_PER_WORLDUNIT = YARDS_PER_WORLDUNIT

local POS_TTL = 0.04            -- player position is re-read at most this often
local MAP_TTL = 0.5             -- ... and the player's map id this often
local LIVE_CACHE_TTL = 0.5      -- Carbonite's own value for LiveQuestPos
local TICK = 0.25               -- active target refresh
local FULL_EVERY = 4            -- every Nth tick re-resolves all tracked quests
local POINT_ARRIVAL_YARDS = 7   -- same radius the map's own goto uses

-- An auto-tracked quest keeps the arrow until another is closer by
-- this factor, so two objectives at similar distances don't trade the
-- arrow back and forth as the player moves.
local AUTO_SWITCH_FACTOR = 0.85

local huge = math.huge

---------------------------------------------------------------------------------------
-- Player position
---------------------------------------------------------------------------------------

-- worldX, worldY, continent, mapId - or nil when the player is somewhere
-- the map engine can't place (inside an instance, mostly). Independent
-- of the map window: that engine only tracks the player while its
-- window is open, and the arrow has to work with it closed.
function Routing:GetPlayerPos()
    local now = GetTime()
    if self._posAt and now - self._posAt < POS_TTL then
        return self.PlyrX, self.PlyrY, self.PlyrCont, self.PlyrMapId
    end
    self._posAt = now

    if not self._mapAt or now - self._mapAt > MAP_TTL then
        self._mapAt = now
        local mapId = Map:GetDisplayableMapForPlayer()
        if mapId == 0 then mapId = nil end
        self.PlyrMapId = mapId
        self.PlyrCont = Catalog:GetContinent(mapId)
    end

    local x, y
    local mapId, cont = self.PlyrMapId, self.PlyrCont
    if cont and C_Map and C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
        if ok and pos then
            local px, py = pos:GetXY()
            if px and py and (px ~= 0 or py ~= 0) then
                x, y = Map:GetWorldPos(mapId, px * 100, py * 100)
            end
        end
    end

    if x then
        if x == self.PlyrX and y == self.PlyrY then
            self.PlyrSpeed = 0
            self._speedAt, self._speedX, self._speedY = now, x, y
        elseif self._speedAt then
            local dt = now - self._speedAt
            if dt > .5 then
                self.PlyrSpeed = ((x - self._speedX) ^ 2 + (y - self._speedY) ^ 2) ^ .5
                    * YARDS_PER_WORLDUNIT / dt
                self._speedAt, self._speedX, self._speedY = now, x, y
            end
        else
            self._speedAt, self._speedX, self._speedY = now, x, y
        end
    else
        self.PlyrSpeed = 0
        self._speedAt = nil
        cont = nil
    end

    self.PlyrX, self.PlyrY = x, y
    if not x then return nil end
    return x, y, cont, mapId
end

---------------------------------------------------------------------------------------
-- Resolving a quest to a destination
---------------------------------------------------------------------------------------

local liveCache = {}

local function LiveQuestPos(questID, playerMapId)
    local now = GetTime()
    local hit = liveCache[questID]
    if hit and now - hit.t < LIVE_CACHE_TTL then
        return hit.mapID, hit.x, hit.y
    end

    local mapID, x, y = Api:GetNextWaypoint(questID)
    if not mapID and playerMapId then
        local list = Api:GetQuestsOnMap(playerMapId)
        if list then
            for _, e in ipairs(list) do
                if e.questID == questID and type(e.x) == "number" and type(e.y) == "number" then
                    mapID, x, y = playerMapId, e.x, e.y
                    break
                end
            end
        end
    end

    if not hit then
        hit = {}
        liveCache[questID] = hit
    end
    hit.t, hit.mapID, hit.x, hit.y = now, mapID, x, y
    return mapID, x, y
end

local function LiveTarget(questID, playerMapId)
    local mapID, lx, ly = LiveQuestPos(questID, playerMapId)
    if not mapID then return nil end
    mapID = Map:CanonicalizeMapID(mapID)
    local cont = Catalog:GetContinent(mapID)
    if not cont then return nil end
    local wx, wy = Map:GetWorldPos(mapID, lx * 100, ly * 100)
    if not wx or (wx == 0 and wy == 0) then return nil end
    return { mId = mapID, cont = cont, x = wx, y = wy, source = "live" }
end

-- The entrance to head for, out of a list of instances something is
-- found inside: the nearest on the player's continent, otherwise the
-- first one the map can place. Returns res, squared distance (huge
-- when it is on another continent).
local function EntranceTarget(dungeons, px, py, cont)
    if not dungeons then return nil end
    -- Already inside one of them: the destination is "here", not the
    -- entrance on the outdoor continent the player just left.
    local here = Catalog:CurrentInstance()
    if here then
        for i = 1, #dungeons do
            if dungeons[i] == here then
                local name = Catalog:GetInstanceEntrance(here) or "the dungeon"
                return {
                    mId = Routing.PlyrMapId, cont = cont, x = px, y = py,
                    inside = true, name = name, instance = here, source = "here",
                }, 0
            end
        end
    end
    local res, bestD
    for i = 1, #dungeons do
        local name, owner, wx, wy = Catalog:GetInstanceEntrance(dungeons[i])
        if wx then
            local ownerCont = Catalog:GetContinent(owner)
            local d = (ownerCont == cont) and ((wx - px) ^ 2 + (wy - py) ^ 2) or huge
            if not bestD or d < bestD then
                bestD = d
                res = res or { entrance = true, source = "db-instance" }
                res.mId, res.cont, res.x, res.y = owner, ownerCont, wx, wy
                res.name, res.instance = name, dungeons[i]
            end
        end
    end
    return res, bestD
end

-- A quest's pickup (useEnd false) or turn-in (useEnd true) point: the
-- nearest of its listed positions on the player's continent, otherwise
-- the first usable one. Second return is the list of instances it
-- happens inside, when it happens inside a dungeon.
local function EndpointTarget(questID, useEnd, px, py, cont)
    local inside = Catalog:GetEndpointDungeons(questID, useEnd)
    local list = Catalog:GetEndpoints(questID, useEnd)
    if not list then return nil, inside end

    local bestD, bx, by, bZone, bCont, bName
    local fx, fy, fZone, fCont, fName
    for i = 1, #list do
        local name, zone, x, y = Catalog:UnpackSE(list[i])
        local zoneCont = Catalog:GetContinent(zone)
        if zoneCont and (x > 0 or y > 0) then
            local wx, wy = Map:GetWorldPos(zone, x, y)
            if wx then
                if not fx then fx, fy, fZone, fCont, fName = wx, wy, zone, zoneCont, name end
                if zoneCont == cont then
                    local d = (wx - px) ^ 2 + (wy - py) ^ 2
                    if not bestD or d < bestD then
                        bestD, bx, by, bZone, bCont, bName = d, wx, wy, zone, zoneCont, name
                    end
                end
            end
        end
    end

    if bx then
        return { mId = bZone, cont = bCont, x = bx, y = by, name = bName, source = "db-se" }, inside
    elseif fx then
        return { mId = fZone, cont = fCont, x = fx, y = fy, name = fName, source = "db-se" }, inside
    end
    return nil, inside
end

-- Second return: the instances the objective is found inside, if any.
local function ObjectiveTarget(questID, objIndex, px, py, cont)
    local geo = Catalog:GetObjectiveGeo(questID, objIndex)
    if not geo then return nil end
    if geo.n == 0 then return nil, geo.dungeons end
    local x, y, zone, inside = Catalog:ClosestPoint(geo, px, py, cont)
    if not x then return nil, geo.dungeons end
    return {
        mId = zone, cont = Catalog:GetContinent(zone), x = x, y = y,
        name = geo.name, inside = inside or nil, source = "db",
    }, geo.dungeons
end

-- Where to go for one quest in the log, given where the player is.
-- Returns res, objIndex (0 = the quest as a whole), or nil.
--
-- Ready to turn in: the turn-in point; else, when that is inside a
-- dungeon, the dungeon's entrance; else Blizzard's own POI.
-- In progress: the nearest unfinished objective the database can
-- place; else - when the database says an objective is inside a
-- dungeon - that dungeon's entrance; else Blizzard's POI; else the
-- turn-in point, which is Carbonite's own last resort for a quest it
-- has no objective data for.
--
-- An objective can be found in several dungeons, and a quest's
-- objectives can be spread over several; the entrance chosen is the
-- nearest of all of them, so it changes as the player travels and as
-- objectives are finished.
--
-- What the database knows comes before Blizzard's POI throughout, as
-- in ResolveTrackTarget: there a position inside an instance counts as
-- a catalog hit, beats the live POI, and is then swapped for the
-- entrance.
local function ResolveQuest(q, px, py, cont, playerMapId)
    local questID = q.questID

    if q.ready then
        local res, inside = EndpointTarget(questID, true, px, py, cont)
        if not res then res = EntranceTarget(inside, px, py, cont) end
        res = res or LiveTarget(questID, playerMapId)
        if res then res.turnin = true end
        return res, 0
    end

    local best, bestD, bestIndex
    local entrance, entranceD
    for i, o in ipairs(q.objectives) do
        if not o.finished then
            local res, inside = ObjectiveTarget(questID, i, px, py, cont)
            if not res and inside then
                local e, d = EntranceTarget(inside, px, py, cont)
                if e and (not entranceD or d < entranceD) then entrance, entranceD = e, d end
            end
            if res then
                local d
                if res.inside then
                    d = 0
                elseif res.cont == cont then
                    d = (res.x - px) ^ 2 + (res.y - py) ^ 2
                else
                    d = huge
                end
                if not bestD or d < bestD then best, bestD, bestIndex = res, d, i end
            end
        end
    end
    if best then return best, bestIndex end

    if entrance then return entrance, 0 end

    local res = LiveTarget(questID, playerMapId)
    if res then return res, 0 end

    local inside
    res, inside = EndpointTarget(questID, true, px, py, cont)
    if not res then res = EntranceTarget(inside, px, py, cont) end
    return res, 0
end

-- The two caption lines for a quest destination: the quest's title,
-- and what to do there.
local function Describe(q, res, objIndex)
    local detail
    if res.entrance and res.turnin then
        detail = "Turn in inside " .. tostring(res.name)
    elseif res.entrance then
        detail = "Dungeon entrance: " .. tostring(res.name)
    elseif objIndex > 0 then
        local o = q.objectives[objIndex]
        detail = (o and o.text ~= "" and o.text) or res.name
    elseif q.ready then
        detail = (res.name and res.name ~= "?") and ("Turn in: " .. res.name) or "Turn in"
    else
        for _, o in ipairs(q.objectives) do
            if not o.finished and o.text ~= "" then
                detail = o.text
                break
            end
        end
    end
    return q.title, detail
end

---------------------------------------------------------------------------------------
-- Choosing the destination
---------------------------------------------------------------------------------------

local function targetKey(t)
    if not t then return "" end
    return table.concat({
        t.kind, tostring(t.questID), tostring(t.objIndex), tostring(t.source),
        tostring(t.name), tostring(t.detail), tostring(t.entrance), tostring(t.mId),
    }, "|")
end

function Routing:SetTarget(target)
    local oldKey = targetKey(self.Target)
    self.Target = target
    if targetKey(target) ~= oldKey then
        EventBus:Fire("QUEST_ROUTE_CHANGED", target)
    end
end

local function questTarget(q, entry, auto)
    local res = entry.res
    local name, detail = Describe(q, res, entry.objIndex)
    return {
        kind = "quest", questID = q.questID, objIndex = entry.objIndex,
        x = res.x, y = res.y, mId = res.mId, cont = res.cont,
        name = name, detail = detail,
        inside = res.inside, entrance = res.entrance, turnin = res.turnin,
        source = res.source, auto = auto or nil,
    }
end

-- Re-resolves every tracked quest and picks the destination:
-- a point the player set by hand, else the quest they pinned, else
-- (with auto-track on) whichever tracked quest is closest.
function Routing:Recalc()
    local State = Q.State
    local px, py, cont, mapId = self:GetPlayerPos()
    local info = {}
    local closest, closestD

    if px and State then
        for _, q in ipairs(State:GetWatchedQuests()) do
            local res, objIndex = ResolveQuest(q, px, py, cont, mapId)
            local entry = { res = res, objIndex = objIndex or 0 }
            if res then
                if res.cont == cont then
                    local d = res.inside and 0 or ((res.x - px) ^ 2 + (res.y - py) ^ 2) ^ .5
                    entry.dist = d
                    entry.yards = d * YARDS_PER_WORLDUNIT
                    if not closestD or d < closestD then closest, closestD = q, d end
                else
                    entry.far = true
                end
            end
            info[q.questID] = entry
        end
    end
    self.QuestInfo = info

    local target

    local point = self.ManualPoint
    if point then
        if px and point.cont == cont then
            local yards = ((point.x - px) ^ 2 + (point.y - py) ^ 2) ^ .5 * YARDS_PER_WORLDUNIT
            if yards < POINT_ARRIVAL_YARDS then
                self.ManualPoint = nil
                point = nil
                if UIErrorsFrame then
                    UIErrorsFrame:AddMessage("Arrived", 1, 1, 1, 1)
                end
            end
        end
        if point then
            target = {
                kind = "point", x = point.x, y = point.y, mId = point.mId, cont = point.cont,
                name = point.name, detail = point.detail, source = "manual",
            }
        end
    end

    if not target and px and State then
        local questID = self.ManualQuestID
        if questID and not State:IsInLog(questID) then
            -- Turned in or abandoned: the pin goes with it.
            self.ManualQuestID = nil
            questID = nil
        end

        local auto = false
        if not questID and closest and Q.Core:Opt("AutoTrack") then
            questID = closest.questID
            auto = true
            local cur = self.Target
            if cur and cur.kind == "quest" and cur.auto and cur.questID ~= questID then
                local curEntry = info[cur.questID]
                if curEntry and curEntry.dist and closestD > curEntry.dist * AUTO_SWITCH_FACTOR then
                    questID = cur.questID
                end
            end
        end

        if questID then
            local q = State:GetQuest(questID)
            local entry = info[questID]
            if q and not entry then
                -- A pinned quest that isn't on the tracker.
                local res, objIndex = ResolveQuest(q, px, py, cont, mapId)
                entry = { res = res, objIndex = objIndex or 0 }
            end
            if q and entry and entry.res then
                target = questTarget(q, entry, auto)
            end
        end
    end

    self:SetTarget(target)
end

-- Between full passes, keep just the active quest destination fresh:
-- the nearest point of an objective area moves as the player does.
function Routing:RefreshActive()
    local t = self.Target
    if not t or t.kind ~= "quest" then return end
    local q = Q.State and Q.State:GetQuest(t.questID)
    local px, py, cont, mapId = self:GetPlayerPos()
    if not q or not px then
        self:Recalc()
        return
    end
    local res, objIndex = ResolveQuest(q, px, py, cont, mapId)
    if not res or (objIndex or 0) ~= t.objIndex or res.source ~= t.source or res.mId ~= t.mId then
        self:Recalc()
        return
    end
    t.x, t.y, t.cont, t.inside = res.x, res.y, res.cont, res.inside
end

---------------------------------------------------------------------------------------
-- Manual control
---------------------------------------------------------------------------------------

function Routing:RequestRecalc()
    self._tick = FULL_EVERY
    self._elapsed = TICK
end

function Routing:SetManualQuest(questID)
    self.ManualPoint = nil
    self.ManualQuestID = questID
    self:Recalc()
end

function Routing:ClearManual()
    self.ManualPoint = nil
    self.ManualQuestID = nil
    self:Recalc()
end

function Routing:IsManualQuest(questID)
    return self.ManualQuestID == questID and not self.ManualPoint
end

-- Click behaviour for a quest (tracker row, map pin): pin it; clicking
-- the pinned quest again unpins it and hands the arrow back to
-- auto-track (or to nothing, with auto-track off).
function Routing:ToggleManualQuest(questID)
    if self:IsManualQuest(questID) then
        self:ClearManual()
    else
        self:SetManualQuest(questID)
    end
end

-- point: { x, y (world), mId, name, detail }
function Routing:SetManualPoint(point)
    self.ManualPoint = {
        x = point.x, y = point.y, mId = point.mId,
        cont = Catalog:GetContinent(point.mId),
        name = point.name, detail = point.detail,
    }
    self:Recalc()
end

function Routing:ToggleManualPoint(point)
    local cur = self.ManualPoint
    if cur and cur.x == point.x and cur.y == point.y then
        self.ManualPoint = nil
        self:Recalc()
    else
        self:SetManualPoint(point)
    end
end

---------------------------------------------------------------------------------------
-- Driving it
---------------------------------------------------------------------------------------

-- Nothing reads routing state with the tracker and arrow both off and
-- the map window closed, so nothing needs computing either.
local function hasConsumers()
    if Q.Core:Opt("TrackerShown") or Q.Core:Opt("ArrowShown") then return true end
    local frm = Map.Frm
    return frm ~= nil and frm:IsVisible()
end

function Routing:Start()
    if self.Frame then return end
    local frame = CreateFrame("Frame")
    self.Frame = frame
    self._elapsed, self._tick = 0, FULL_EVERY

    frame:SetScript("OnUpdate", function(_, elapsed)
        self._elapsed = self._elapsed + elapsed
        if self._elapsed < TICK then return end
        self._elapsed = 0
        if not hasConsumers() then
            if self.Target then self:SetTarget(nil) end
            return
        end
        self._tick = self._tick + 1
        if self._tick >= FULL_EVERY then
            self._tick = 0
            self:Recalc()
        else
            self:RefreshActive()
        end
    end)

    local function soon() self:RequestRecalc() end
    EventBus:Subscribe("QUEST_STATE_CHANGED", soon)
    EventBus:Subscribe("QUEST_CATALOG_READY", soon)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", soon)
end
