-- Azeroth Atlas | Map/Travel.lua
---------------------------------------------------------------------------------------
-- Travel routing (2026-11-18, user request, from Carbonite: "Travel
-- routing with flight paths"). When the quickest way to where the arrow
-- is going is not a straight walk, the arrow and the map's ant trail
-- point at the next step instead - the flight master to fly from, or
-- the boat / zeppelin / portal / tram to take - and the arrow's caption
-- says what to do there ("Fly to Orgrimmar, then Zeppelin to Undercity").
--
-- Carbonite's idea (Modules/Travel/TravelEngine.lua: Travel:MakePath,
-- FindFlight, FindClosest, FindCrossContinent), built differently: one
-- shortest-time search (Dijkstra) over
--   * you and the destination
--   * every flight master you know - learned whenever a flight map opens
--     (TAXIMAP_OPENED, like Carbonite's CaptureTaxi), per character
--   * both ends of every boat / zeppelin / portal / tram
--     (Map/Data/GuideZoneTransition.lua's Map.TravelLinks)
-- with three kinds of step: walk / ride between any two points on the
-- same continent, fly between two known flight masters on the same
-- continent, and take a transport from one end to the other (one-way
-- portals only one way). So it also finds two-transport trips Carbonite
-- only does as "indirect" special cases.
--
-- Times, in seconds:
--   walk  straight distance x 1.15 (roads bend) at 7 yd/s, or 11.2 yd/s
--         once this character has been seen mounted
--   fly   straight distance x 1.25 (flight paths bend) at 31.5 yd/s,
--         plus 15 s to take off and land
--   boat / zeppelin 150 s (wait + crossing), tram 80 s, portal 10 s
-- On the same continent the route only replaces the straight walk when
-- it is clearly quicker (15% and at least 30 s), so the arrow doesn't
-- flick between "walk" and "fly" for a destination that's close either
-- way. Nothing is routed for the corpse run (a ghost can't fly), while
-- on a flight, or when there is no known faster way.
--
-- On / off: Settings > Map, Navigation, "Travel routes" (profile.TravelRoute).
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
local Map = AzerothAtlas.Map

local Travel = {}
AzerothAtlas.Modules.Map = AzerothAtlas.Modules.Map or {}
AzerothAtlas.Modules.Map.Travel = Travel

local YARDS_PER_WORLDUNIT = 4.575
local WALK_YPS, MOUNT_FACTOR, WALK_DETOUR = 7, 1.6, 1.15
local FLY_YPS, FLY_DETOUR, FLY_OVERHEAD = 31.5, 1.25, 15
local TRANSPORT_TIME = { Boat = 150, Zeppelin = 150, Tram = 80, Portal = 10 }
local TRANSPORT_VERB = { Boat = "boat", Zeppelin = "zeppelin", Tram = "tram", Portal = "portal" }
local MIN_SAVING_FRAC, MIN_SAVING_SECS = 0.15, 30
local RECALC_SECS = 2

local huge, sqrt = math.huge, math.sqrt

local taxiByCont = {}     -- continent -> flight masters (taxiNodes below)

local function charDB()
    local db = AzerothAtlas.db
    return db and db.char
end

local function routeOn()
    local db = AzerothAtlas.db
    return db and db.profile.TravelRoute ~= false
end

---------------------------------------------------------------------------------------
-- Known flight masters
---------------------------------------------------------------------------------------

-- Called when a flight master's map opens: every node it shows as where
-- you are or somewhere you can fly to is known; one it shows as not
-- (yet) reachable isn't. Nodes this map doesn't list keep what they had.
function Travel:CaptureTaxi()
    local c = charDB()
    if not c then return end
    c.KnownTaxi = c.KnownTaxi or {}
    c.KnownTaxiIds = c.KnownTaxiIds or {}
    -- Also kept for the flight you're about to take (OnTakeTaxi): the
    -- slots' names, which is "CURRENT", and their node IDs.
    local slots = {}
    self.TaxiSlots = slots
    if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
        for i = 1, NumTaxiNodes() do
            local name, typ = TaxiNodeName(i), TaxiNodeGetType(i)
            if name and name ~= "" then
                c.KnownTaxi[name] = (typ == "CURRENT" or typ == "REACHABLE") or nil
            end
            slots[i] = { name = name, current = typ == "CURRENT" }
        end
    end
    -- The newer API too, by node ID, in case its names differ.
    local taxiMap = GetTaxiMapID and GetTaxiMapID()
    if taxiMap and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, taxiMap)
        if ok and type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                if node.nodeID and node.state ~= nil then
                    c.KnownTaxiIds[node.nodeID] = (node.state == 0 or node.state == 1) or nil
                end
                local slot = node.slotIndex and slots[node.slotIndex]
                if slot then slot.id = node.nodeID end
            end
        end
    end
    -- A new continent's network may only answer once a flight map has
    -- been opened there: ask again.
    taxiByCont = {}
    self.CacheKey = nil
end

local function isKnown(node)
    local c = charDB()
    if not c then return false end
    return (c.KnownTaxi and c.KnownTaxi[node.name]) or (c.KnownTaxiIds and c.KnownTaxiIds[node.id]) or false
end

-- Every flight master on a continent, in world coordinates: asked zone
-- by zone (GetTaxiNodesForMap answers with the whole continent's network,
-- placed relative to the zone asked about - see MinimapEngine's own
-- flight-master icons), keeping each node from the first zone it lies
-- inside. Built once per continent per session.
taxiByCont = {}

local function taxiNodes(cont)
    local list = taxiByCont[cont]
    if list then return list end
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return {} end
    local zones = Map.MapZones and Map.MapZones[cont]
    if not zones or #zones == 0 then return {} end
    list = {}
    local seen = {}
    for _, zoneId in ipairs(zones) do
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, zoneId)
        if ok and type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                local key = node.nodeID or node.name
                local pos = node.position
                local nx, ny = pos and pos.x, pos and pos.y
                if pos and (nx == nil or ny == nil) and pos.GetXY then nx, ny = pos:GetXY() end
                if key and not seen[key] and nx and ny and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                    local wx, wy = Map:GetWorldPos(zoneId, nx * 100, ny * 100)
                    if wx then
                        seen[key] = true
                        list[#list + 1] = { x = wx, y = wy, cont = cont, name = node.name or "",
                            id = node.nodeID, taxi = true }
                    end
                end
            end
        end
    end
    taxiByCont[cont] = list
    return list
end

---------------------------------------------------------------------------------------
-- Transport ends
---------------------------------------------------------------------------------------

local function factionOk(fac)
    if fac == 0 then return true end
    local mine = UnitFactionGroup("player")
    return (fac == 1 and mine == "Alliance") or (fac == 2 and mine == "Horde")
end

local transportEnds

local function buildTransports()
    if transportEnds then return transportEnds end
    local ends = {}
    for _, l in ipairs(Map.TravelLinks or {}) do
        local kind = l[1]
        if TRANSPORT_TIME[kind] and factionOk(l[2]) then
            local x1, y1 = Map:GetWorldPos(l[3], l[4], l[5])
            local x2, y2 = Map:GetWorldPos(l[7], l[8], l[9])
            local c1, c2 = Map:FindContinent(l[3]), Map:FindContinent(l[7])
            if x1 and x2 and c1 and c2 then
                local a = { x = x1, y = y1, cont = c1, name = l[6], links = {} }
                local b = { x = x2, y = y2, cont = c2, name = l[10], links = {} }
                local t = TRANSPORT_TIME[kind]
                a.links[#a.links + 1] = { node = b, cost = t, kind = kind, label = l[6] }
                if l[11] then
                    b.links[#b.links + 1] = { node = a, cost = t, kind = kind, label = l[10] }
                end
                ends[#ends + 1] = a
                ends[#ends + 1] = b
            end
        end
    end
    -- Only kept once the map data is in (FindContinent needs it).
    if #ends > 0 then transportEnds = ends end
    return ends
end

---------------------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------------------

local function walkTime(a, b, yps)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy) * YARDS_PER_WORLDUNIT * WALK_DETOUR / yps
end

local function flyTime(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy) * YARDS_PER_WORLDUNIT * FLY_DETOUR / FLY_YPS + FLY_OVERHEAD
end

local function shortName(name)
    return (name or ""):match("^([^,]+)") or name or ""
end

local function stepText(step)
    if step.how == "fly" then
        return "Fly to " .. shortName(step.to.name)
    elseif step.how == "link" then
        return step.label
    end
end

-- The route from (px, py) on continent pcont to dest, as a list of
-- steps { how = "walk" | "fly" | "link", to = node, label, kind }, and
-- its time and the straight walk's time (nil when there isn't one).
local function search(px, py, pcont, dest)
    local c = charDB()
    if c and IsMounted and IsMounted() then c.TravelMounted = true end
    local yps = WALK_YPS * ((c and c.TravelMounted) and MOUNT_FACTOR or 1)

    local S = { x = px, y = py, cont = pcont }
    local D = { x = dest.x, y = dest.y, cont = dest.cont }
    local nodes = { S, D }
    for cont = 1, Map.ContCnt or 0 do
        for _, n in ipairs(taxiNodes(cont)) do
            if isKnown(n) then nodes[#nodes + 1] = n end
        end
    end
    for _, n in ipairs(buildTransports()) do nodes[#nodes + 1] = n end

    local count = #nodes
    local best, via, done = {}, {}, {}
    for i = 1, count do best[i] = huge; nodes[i].idx = i end
    best[1] = 0

    while true do
        local u, ub = nil, huge
        for i = 1, count do
            if not done[i] and best[i] < ub then u, ub = i, best[i] end
        end
        if not u or u == 2 then break end
        done[u] = true
        local a = nodes[u]
        for i = 2, count do
            if not done[i] then
                local b = nodes[i]
                if a.cont == b.cont then
                    local t, how = walkTime(a, b, yps), "walk"
                    if a.taxi and b.taxi then
                        local ft = flyTime(a, b)
                        if ft < t then t, how = ft, "fly" end
                    end
                    if ub + t < best[i] then
                        best[i] = ub + t
                        via[i] = { from = u, how = how, to = b }
                    end
                end
            end
        end
        for _, l in ipairs(a.links or {}) do
            local i = l.node.idx
            if i and not done[i] and ub + l.cost < best[i] then
                best[i] = ub + l.cost
                via[i] = { from = u, how = "link", to = l.node, label = l.label, kind = l.kind }
            end
        end
    end
    for i = 1, count do nodes[i].idx = nil end

    if best[2] == huge then return nil end
    local steps, i = {}, 2
    while i ~= 1 do
        local v = via[i]
        table.insert(steps, 1, v)
        i = v.from
    end
    local direct = pcont == dest.cont and walkTime(S, D, yps) or nil
    return steps, best[2], direct
end

---------------------------------------------------------------------------------------
-- What the arrow and the map follow
---------------------------------------------------------------------------------------

-- dest: { x, y, cont, name } (world coordinates, like QuestRouting's
-- targets). Returns the next step as a target of the same shape (plus
-- kind = "travel") when the route goes by flight or transport, else nil
-- - follow dest itself. Worked out at most every 2 seconds per
-- destination.
function Travel:NextLeg(dest)
    if not dest or not dest.x or not dest.cont or dest.kind == "corpse" or not routeOn() then return nil end
    -- On a flight: where it lands (Travel:FlightTarget), if known.
    if UnitOnTaxi and UnitOnTaxi("player") then return self:FlightTarget() end
    local Q = AzerothAtlas.Modules.Quest
    local Routing = Q and Q.Routing
    if not Routing then return nil end
    local px, py, pcont = Routing:GetPlayerPos()
    if not px or not pcont then return nil end

    local key = ("%.1f|%.1f|%s"):format(dest.x, dest.y, tostring(dest.cont))
    local now = GetTime()
    if key == self.CacheKey and now - (self.CacheAt or 0) < RECALC_SECS then
        return self.Leg
    end
    self.CacheKey, self.CacheAt = key, now
    self.Leg = nil

    local steps, time, direct = search(px, py, pcont, dest)
    if not steps or #steps < 2 then return nil end
    if direct and (direct - time < MIN_SAVING_SECS or time > direct * (1 - MIN_SAVING_FRAC)) then
        return nil
    end

    -- The first step is the walk to where the trip proper starts.
    local first, act = steps[1], steps[2]
    if first.how ~= "walk" or act.how == "walk" then return nil end
    local at = first.to
    local leg = self.LegTable or {}
    self.LegTable = leg
    leg.kind, leg.x, leg.y, leg.cont, leg.inside = "travel", at.x, at.y, at.cont, nil
    if act.how == "fly" then
        leg.name = "Flight master: " .. shortName(at.name)
    else
        leg.name = act.label
    end
    -- "Fly to Orgrimmar, then Zeppelin to Undercity for <quest>": what
    -- to do here, then up to two more steps.
    local first_text = act.how == "fly" and stepText(act)
        or ("Take the " .. (TRANSPORT_VERB[act.kind] or "transport"))
    local parts = { first_text }
    for n = 3, #steps do
        local text = stepText(steps[n])
        if text then parts[#parts + 1] = text end
        if #parts >= 3 then break end
    end
    local detail = table.concat(parts, ", then ")
    if dest.name and dest.name ~= "" then detail = detail .. " - for " .. dest.name end
    leg.detail = detail
    leg.time = time
    self.Leg = leg
    return leg
end

-- After the map data changes (new flight masters, continent catalog).
function Travel:Reset()
    taxiByCont = {}
    transportEnds = nil
    self.CacheKey = nil
end

---------------------------------------------------------------------------------------
-- Following your flight (2026-11-18, user request, from Carbonite: "When
-- you take a flight, the arrow switches to where you're flying").
-- Carbonite wraps TakeTaxiNode (Travel.TakeTaxiNode) to read the
-- destination's name and look up where it is; here a hooksecurefunc
-- reads the same from the flight map as it was when it opened
-- (CaptureTaxi's TaxiSlots - the map may already be closing by the time
-- the hook runs), and finds the landing spot among the continent's
-- flight masters by node ID, else by name.
-- While the flight lasts (UnitOnTaxi), the arrow points at the landing
-- spot - "Flying to Orgrimmar" - and counts down to landing once this
-- character has flown that route before: Carbonite keeps flight times
-- per hop (TaxiSaveTime); here per whole flight, start -> destination,
-- saved on landing (profile-wide, db.global.FlightTimes - the same
-- route takes the same time for every character).
-- On / off: Settings > Map, Navigation, "Follow your flight"
-- (profile.TrackFlight).
---------------------------------------------------------------------------------------

local FLIGHT_START_GRACE = 10   -- seconds for the flight to begin after you pick it

local function flightTimes()
    local db = AzerothAtlas.db
    if not db then return nil end
    db.global.FlightTimes = db.global.FlightTimes or {}
    return db.global.FlightTimes
end

function Travel:OnTakeTaxi(slotIndex)
    local db = AzerothAtlas.db
    if db and db.profile.TrackFlight == false then return end
    local slots = self.TaxiSlots or {}
    local slot = slots[slotIndex]
    local name = (slot and slot.name) or (TaxiNodeName and TaxiNodeName(slotIndex))
    if not name or name == "" then return end
    local from
    for _, s in pairs(slots) do
        if s.current then from = s.name end
    end

    -- Where it lands: the player's continent first, then the rest.
    local Q = AzerothAtlas.Modules.Quest
    local _, _, pcont = Q and Q.Routing and Q.Routing:GetPlayerPos()
    local found
    local function look(cont)
        for _, n in ipairs(taxiNodes(cont)) do
            if (slot and slot.id and n.id == slot.id) or n.name == name then
                found = n
                return true
            end
        end
    end
    if not (pcont and look(pcont)) then
        for cont = 1, Map.ContCnt or 0 do
            if cont ~= pcont and look(cont) then break end
        end
    end

    self.Flight = {
        name = name, from = from, takenAt = GetTime(),
        x = found and found.x, y = found and found.y, cont = found and found.cont,
    }
    self.CacheKey = nil
end

-- Watches the flight: started (UnitOnTaxi), landed (saves its time), or
-- never started (picked, then cancelled / not enough money).
function Travel:WatchFlight()
    local f = self.Flight
    if not f then return end
    local now = GetTime()
    if UnitOnTaxi and UnitOnTaxi("player") then
        f.startedAt = f.startedAt or now
    elseif f.startedAt then
        local times = flightTimes()
        if times and f.from then
            times[f.from .. "|" .. f.name] = math.floor(now - f.startedAt + .5)
        end
        self.Flight = nil
        self.CacheKey = nil
    elseif now - f.takenAt > FLIGHT_START_GRACE then
        self.Flight = nil
    end
end

local flightTarget = {}

-- The landing spot as an arrow target (QuestRouting's target shape,
-- kind = "flight"), or nil when not flying somewhere known.
function Travel:FlightTarget()
    local f = self.Flight
    if not f or not f.x then return nil end
    local t = flightTarget
    t.kind, t.x, t.y, t.cont, t.inside = "flight", f.x, f.y, f.cont, nil
    t.name = "Flying to " .. shortName(f.name)
    local times = flightTimes()
    local total = times and f.from and times[f.from .. "|" .. f.name]
    if total and f.startedAt then
        local left = math.max(0, total - (GetTime() - f.startedAt))
        t.detail = ("Lands in %d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
    elseif total then
        t.detail = ("About %d:%02d in the air"):format(math.floor(total / 60), total % 60)
    else
        t.detail = "First time on this flight - timing it for next time"
    end
    return t
end

local events = CreateFrame("Frame")
events:RegisterEvent("TAXIMAP_OPENED")
events:SetScript("OnEvent", function()
    Travel:CaptureTaxi()
end)

if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(slotIndex)
        Travel:OnTakeTaxi(slotIndex)
    end)
end

local watchAt = 0
events:SetScript("OnUpdate", function(_, elapsed)
    watchAt = watchAt + elapsed
    if watchAt < .5 then return end
    watchAt = 0
    Travel:WatchFlight()
end)
