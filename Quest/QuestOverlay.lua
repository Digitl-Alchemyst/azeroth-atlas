-- Alchemy GPS | Quest / QuestOverlay
-- What the map shows under the quest pins:
--
--   areas    where a tracked quest's unfinished objectives are found,
--            shaded in that quest's colour - the pins stay, this fills
--            in the ground between them. Drawn at the data's own
--            resolution: Carbonite.Quests stores each objective's spawn
--            area as strips half a percent of the zone tall (its "35"
--            rows), which is what Carbonite draws too. Neighbouring
--            strips are joined, and lone spawn points (its "32" rows)
--            get a small round patch.
--   steps    a quest whose objectives - or one objective - are found in
--            separate places (Kodo Roundup: tame a kodo in one spot,
--            lead it to another) gets a numbered badge on each area,
--            "1", "2" per objective and "1a", "1b" for one objective in
--            several places, and a dotted line in the quest's colour
--            joining its areas, so they read as one quest.
--   drops    the same shading, in orange, over the places an item that
--            starts a quest drops (QuestPins.lua's "dropped item" pins).
--   patrols  a bright line along the path a wandering quest giver or
--            turn-in NPC walks (Quest/Data/QuestDBRules.lua's Patrols).
--
-- Where areas overlap, the smaller one is drawn over the larger, so a
-- small area inside a big one stays visible. Everything here is drawn
-- below the map's icons (one frame level under them), so no area ever
-- covers a pin. Hovering anywhere over an area shows what it is for -
-- every quest whose area is under the cursor, smallest first.
--
-- New code, not a port. The map engine calls Draw every tick
-- (Map/MinimapEngine.lua's Update); shapes are rebuilt only when quest
-- state, the zone shown or an option changes, and re-placed only when
-- the map has actually panned or zoomed.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest
local Catalog = Q.Catalog

local Overlay = {}
Q.Overlay = Overlay

local MAX_RECTS = 6000      -- area strips considered at once (only those in view get a texture)
local MAX_SEGMENTS = 600    -- patrol line pieces drawn at once
local AREA_ALPHA = 0.26
local DROP_COLOR = { 1, 0.6, 0.2 }
local PATROL_COLOR = { 0.2, 1, 1 }
local REBUILD_EVERY = 2     -- seconds; pickup pins can change without an event
local HOVER_EVERY = 0.05

-- In percent of the zone's width.
local POINT_RADIUS = 0.9    -- patch around a lone spawn point
local DROP_RADIUS = 1.2     -- patch around an item drop position
local CLUSTER_GAP = 2.5     -- strips closer than this belong to one area

local DASH, DASH_GAP = 7, 5 -- dotted step line, screen pixels

-- Draw slots, bottom to top: biggest area lowest.
local LAYERS = { "BACKGROUND", "BORDER", "ARTWORK" }
local SLOTS = #LAYERS * 16

local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt
local GEO_STRIDE = 6        -- QuestCatalog.lua's geo layout: zone, isPoint, x1, y1, x2, y2

local function isFilterOn(key)
    local filters = AlchemyGPS.db and AlchemyGPS.db.profile and AlchemyGPS.db.profile.MapFilters
    return not filters or filters[key] ~= false
end

---------------------------------------------------------------------------------------
-- Building shapes (world coordinates)
--
-- A shape is one area: { rects = {x1, y1, x2, y2, ...}, n = rect count,
-- bx1, by1, bx2, by2 = bounds, size = covered area, ax, ay = a point
-- inside it for the badge }.
---------------------------------------------------------------------------------------

-- World units per percent of a zone's width.
local unitCache = {}
local function zoneUnit(zone)
    local u = unitCache[zone]
    if u == nil then
        local Map = AlchemyGPS.Map
        local x1 = Map:GetWorldPos(zone, 0, 0)
        local x2 = Map:GetWorldPos(zone, 100, 0)
        u = (x1 and x2 and x2 > x1) and (x2 - x1) / 100 or false
        unitCache[zone] = u
    end
    return u or nil
end

-- A round-ish patch of radius r: three strips.
local function addDisc(list, cx, cy, r)
    local n = #list
    list[n + 1], list[n + 2], list[n + 3], list[n + 4] = cx - r, cy - r * 0.4, cx + r, cy + r * 0.4
    list[n + 5], list[n + 6], list[n + 7], list[n + 8] = cx - r * 0.7, cy - r * 0.75, cx + r * 0.7, cy - r * 0.4
    list[n + 9], list[n + 10], list[n + 11], list[n + 12] = cx - r * 0.7, cy + r * 0.4, cx + r * 0.7, cy + r * 0.75
end

-- Joins strips stacked exactly on top of each other with the same
-- width into one taller strip: same picture, far fewer textures.
local function mergeColumns(flat)
    local list = {}
    for i = 1, #flat, 4 do
        list[#list + 1] = { flat[i], flat[i + 1], flat[i + 2], flat[i + 3] }
    end
    table.sort(list, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        if a[3] ~= b[3] then return a[3] < b[3] end
        return a[2] < b[2]
    end)
    local out, cur = {}, nil
    local eps = 1e-6
    for _, r in ipairs(list) do
        if cur and math.abs(cur[1] - r[1]) < eps and math.abs(cur[3] - r[3]) < eps and r[2] <= cur[4] + eps then
            if r[4] > cur[4] then cur[4] = r[4] end
        else
            cur = { r[1], r[2], r[3], r[4] }
            out[#out + 1] = cur
        end
    end
    return out
end

-- Strips -> separate areas (strips within `gap` of each other share one).
local function cluster(list, gap)
    local n = #list
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for i = 1, n do
        local a = list[i]
        for j = i + 1, n do
            local b = list[j]
            if a[1] <= b[3] + gap and b[1] <= a[3] + gap and a[2] <= b[4] + gap and b[2] <= a[4] + gap then
                local ri, rj = find(i), find(j)
                if ri ~= rj then parent[ri] = rj end
            end
        end
    end

    local shapes, byRoot = {}, {}
    for i = 1, n do
        local root = find(i)
        local shape = byRoot[root]
        if not shape then
            shape = { rects = {}, n = 0, size = 0, bx1 = math.huge, by1 = math.huge, bx2 = -math.huge, by2 = -math.huge }
            byRoot[root] = shape
            shapes[#shapes + 1] = shape
        end
        local r = list[i]
        local k = shape.n * 4
        shape.rects[k + 1], shape.rects[k + 2], shape.rects[k + 3], shape.rects[k + 4] = r[1], r[2], r[3], r[4]
        shape.n = shape.n + 1
        shape.size = shape.size + (r[3] - r[1]) * (r[4] - r[2])
        shape.bx1, shape.by1 = min(shape.bx1, r[1]), min(shape.by1, r[2])
        shape.bx2, shape.by2 = max(shape.bx2, r[3]), max(shape.by2, r[4])
    end

    -- Badge point: the middle of the strip nearest the area's centre of
    -- mass, so it always lands on the area itself.
    for _, shape in ipairs(shapes) do
        local sx, sy, w = 0, 0, 0
        local rects = shape.rects
        for i = 0, shape.n - 1 do
            local k = i * 4
            local a = (rects[k + 3] - rects[k + 1]) * (rects[k + 4] - rects[k + 2])
            sx = sx + (rects[k + 1] + rects[k + 3]) * 0.5 * a
            sy = sy + (rects[k + 2] + rects[k + 4]) * 0.5 * a
            w = w + a
        end
        local mx, my = sx / max(w, 1e-9), sy / max(w, 1e-9)
        local best
        for i = 0, shape.n - 1 do
            local k = i * 4
            local px = min(max(mx, rects[k + 1]), rects[k + 3])
            local py = min(max(my, rects[k + 2]), rects[k + 4])
            local d = (px - mx) ^ 2 + (py - my) ^ 2
            if not best or d < best then best, shape.ax, shape.ay = d, px, py end
        end
    end
    table.sort(shapes, function(a, b) return a.size > b.size end)
    return shapes
end

-- The areas of one objective on one continent, cached on its geo table.
local function objectiveShapes(geo, cont)
    geo.shapes = geo.shapes or {}
    local shapes = geo.shapes[cont]
    if shapes then return shapes end

    local flat, unit = {}, nil
    for i = 0, geo.n - 1 do
        local b = i * GEO_STRIDE
        local zone = geo[b + 1]
        if Catalog:GetContinent(zone) == cont then
            local u = zoneUnit(zone)
            unit = unit or u
            if geo[b + 2] == 1 then
                if u then addDisc(flat, geo[b + 3], geo[b + 4], POINT_RADIUS * u) end
            else
                local n = #flat
                flat[n + 1], flat[n + 2], flat[n + 3], flat[n + 4] = geo[b + 3], geo[b + 4], geo[b + 5], geo[b + 6]
            end
        end
    end
    shapes = (#flat > 0 and unit) and cluster(mergeColumns(flat), CLUSTER_GAP * unit) or {}
    geo.shapes[cont] = shapes
    return shapes
end

-- The areas an item drops in (zone-percent positions), cached on the list.
local function dropShapes(area)
    if area.shapes then return area.shapes end
    local Map = AlchemyGPS.Map
    local unit = zoneUnit(area.mapId)
    local flat = {}
    if unit then
        for i = 0, area.n - 1 do
            local wx, wy = Map:GetWorldPos(area.mapId, area[i * 2 + 1], area[i * 2 + 2])
            if wx then addDisc(flat, wx, wy, DROP_RADIUS * unit) end
        end
    end
    area.shapes = (#flat > 0) and cluster(mergeColumns(flat), CLUSTER_GAP * unit) or {}
    return area.shapes
end

-- A patrol path as world coordinates { wx, wy, wx, wy, ... }, cached.
local function pathWorld(path)
    if path.world then return path.world end
    local Map = AlchemyGPS.Map
    local world = {}
    for i = 0, path.n - 1 do
        local wx, wy = Map:GetWorldPos(path.mapId, path[i * 2 + 1], path[i * 2 + 2])
        if wx then
            world[#world + 1] = wx
            world[#world + 1] = wy
        end
    end
    path.world = world
    return world
end

---------------------------------------------------------------------------------------
-- What to show
---------------------------------------------------------------------------------------

-- self.Areas: { {shape=, r=, g=, b=, questID=, objIndex=, badge=, drop=, slot=}, ... }
-- self.Links: { {x1, y1, x2, y2, r, g, b}, ... }   dotted step lines
-- self.Lines: { {x1, y1, x2, y2}, ... }            patrol paths
function Overlay:Rebuild(engine)
    local areas, links, lines = {}, {}, {}
    self.Areas, self.Links, self.Lines = areas, links, lines
    self.Version = (self.Version or 0) + 1

    local State, Core, Pins, Rules = Q.State, Q.Core, Q.Pins, Q.Rules
    local mapId, cont = engine.MapId, engine.Cont
    if not State or not State.Scanned or not mapId or not cont or not Catalog.Ready then return end

    local budget = MAX_RECTS
    local showAreas = Core:Opt("ShowQuestAreas")
    if showAreas and isFilterOn("QuestObjective") then
        -- The quest the arrow is on first, so it is never the one cut
        -- off by MAX_RECTS.
        local target = Q.Routing and Q.Routing.Target
        local activeQuest = target and target.kind == "quest" and target.questID or nil
        local quests = State:GetWatchedQuests()
        table.sort(quests, function(a, b)
            if (a.questID == activeQuest) ~= (b.questID == activeQuest) then
                return a.questID == activeQuest
            end
            return a.questID < b.questID
        end)
        for _, q in ipairs(quests) do
            if not q.ready and budget > 0 then
                local r, g, b = Pins:QuestColor(q.questID)
                local mine = {}
                for i, o in ipairs(q.objectives) do
                    if not o.finished then
                        local geo = Catalog:GetObjectiveGeo(q.questID, i)
                        local shapes = (geo and geo.n > 0) and objectiveShapes(geo, cont) or nil
                        for n, shape in ipairs(shapes or {}) do
                            if budget <= 0 then break end
                            budget = budget - shape.n
                            local a = {
                                shape = shape, r = r, g = g, b = b, questID = q.questID, objIndex = i,
                                part = (#shapes > 1) and n or nil,
                            }
                            areas[#areas + 1] = a
                            mine[#mine + 1] = a
                        end
                    end
                end
                -- Badges and joining lines only where there is more than
                -- one area to tell apart.
                if #mine > 1 then
                    for _, a in ipairs(mine) do
                        a.badge = tostring(a.objIndex) .. (a.part and string.char(96 + min(a.part, 26)) or "")
                    end
                    -- Join each area to the nearest one already joined.
                    local joined = { mine[1] }
                    for k = 2, #mine do
                        local a, best, bestD = mine[k], nil, nil
                        for _, o in ipairs(joined) do
                            local d = (a.shape.ax - o.shape.ax) ^ 2 + (a.shape.ay - o.shape.ay) ^ 2
                            if not bestD or d < bestD then best, bestD = o, d end
                        end
                        links[#links + 1] = { best.shape.ax, best.shape.ay, a.shape.ax, a.shape.ay, r, g, b }
                        joined[#joined + 1] = a
                    end
                end
            end
        end
    end

    local givers = isFilterOn("QuestGiver") and Pins and Pins:GetGivers(mapId) or nil
    if givers and showAreas then
        for _, g in ipairs(givers) do
            if g.area and budget > 0 then
                for _, shape in ipairs(dropShapes(g.area)) do
                    if budget <= 0 then break end
                    budget = budget - shape.n
                    areas[#areas + 1] = {
                        shape = shape, r = DROP_COLOR[1], g = DROP_COLOR[2], b = DROP_COLOR[3],
                        drop = g.drop, quests = g.quests,
                    }
                end
            end
        end
    end

    -- Bigger areas lower, smaller ones over them.
    table.sort(areas, function(a, b) return a.shape.size > b.shape.size end)
    local count = #areas
    for rank, a in ipairs(areas) do
        a.slot = (count <= SLOTS) and (rank - 1) or floor((rank - 1) * SLOTS / count)
    end

    if Core:Opt("ShowPatrolPaths") and Rules then
        local seen = {}
        local function addPatrol(npcId)
            if not npcId or seen[npcId] then return end
            seen[npcId] = true
            local paths = Rules:GetPatrol(npcId)
            if not paths then return end
            for _, path in ipairs(paths) do
                if Catalog:GetContinent(path.mapId) == cont then
                    local w = pathWorld(path)
                    for i = 1, #w - 3, 2 do
                        if #lines >= MAX_SEGMENTS then return end
                        lines[#lines + 1] = { w[i], w[i + 1], w[i + 2], w[i + 3] }
                    end
                end
            end
        end
        for _, g in ipairs(givers or {}) do
            if g.patrol then addPatrol(g.id) end
        end
        -- Turn-ins wander too: a quest ready to hand in to a walker.
        if isFilterOn("QuestTurnIn") then
            for _, q in ipairs(State.Quests) do
                if q.ready then
                    local ends = Catalog:GetEndpoints(q.questID, true)
                    for i = 1, ends and #ends or 0 do
                        local _, _, _, _, npcId = Catalog:UnpackSE(ends[i])
                        addPatrol(npcId)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- Drawing (canvas pixels)
---------------------------------------------------------------------------------------

function Overlay:GetFrame(engine)
    local f = self.Frame
    if not f or f:GetParent() ~= engine.Frm then
        f = CreateFrame("Frame", nil, engine.Frm)
        f.rects, f.cores, f.glows, f.dashes, f.badges = {}, {}, {}, {}, {}
        self.Frame = f
        self.Drawn = nil
    end
    return f
end

-- Clips the segment (x1,y1)-(x2,y2) to the w-by-h canvas (Liang-Barsky).
-- Returns the clipped ends, or nil when it lies wholly outside.
local function clipSegment(x1, y1, x2, y2, w, h)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    local function edge(p, q)
        if p == 0 then return q >= 0 end
        local t = q / p
        if p < 0 then
            if t > t1 then return false end
            if t > t0 then t0 = t end
        else
            if t < t0 then return false end
            if t < t1 then t1 = t end
        end
        return true
    end
    if edge(-dx, x1) and edge(dx, w - x1) and edge(-dy, y1) and edge(dy, h - y1) then
        return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
    end
    return nil
end

local function newLine(f, layer, sub, thickness)
    local line = f:CreateLine(nil, layer, nil, sub)
    line:SetThickness(thickness)
    return line
end

function Overlay:Draw(engine)
    if not engine.Frm or not engine.ScaleDraw or not engine.MapW then return end

    local now = GetTime()
    if self.Dirty or self.MapId ~= engine.MapId or not self.RebuildAt or now >= self.RebuildAt then
        self.Dirty, self.MapId, self.RebuildAt = false, engine.MapId, now + REBUILD_EVERY
        self:Rebuild(engine)
    end

    local f = self:GetFrame(engine)
    -- One level under the map's icons (MinimapEngine.lua's
    -- SERVICE_LEVEL_OFFSET, 5) and above its terrain (3) - re-checked
    -- every tick, so no area can ever end up over a pin.
    local want = (engine.Frm:GetFrameLevel() or 1) + 4
    if f:GetFrameLevel() ~= want then f:SetFrameLevel(want) end

    self:UpdateHover(engine, now)

    local scale, mapW, mapH = engine.ScaleDraw, engine.MapW, engine.MapH
    local posX, posY = engine.MapPosXDraw, engine.MapPosYDraw
    local last = self.Drawn
    if last and last[1] == self.Version and last[2] == scale and last[3] == mapW and last[4] == mapH
        and last[5] == posX and last[6] == posY and last[7] == f then
        return
    end
    self.Drawn = { self.Version, scale, mapW, mapH, posX, posY, f }

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", engine.Frm, "TOPLEFT", 0, -(engine.TitleH or 0))
    f:SetSize(mapW, mapH)

    local halfW, halfH = mapW * .5, mapH * .5
    local function sx(wx) return (wx - posX) * scale + halfW end
    local function sy(wy) return (wy - posY) * scale + halfH end

    -- Areas.
    local used = 0
    for _, a in ipairs(self.Areas or {}) do
        local shape = a.shape
        if sx(shape.bx2) > 0 and sy(shape.by2) > 0 and sx(shape.bx1) < mapW and sy(shape.by1) < mapH then
            local layer = LAYERS[floor(a.slot / 16) + 1] or "ARTWORK"
            local sub = a.slot % 16 - 8
            local rects = shape.rects
            for i = 0, shape.n - 1 do
                local k = i * 4
                local x1, y1, x2, y2 = sx(rects[k + 1]), sy(rects[k + 2]), sx(rects[k + 3]), sy(rects[k + 4])
                if x2 > 0 and y2 > 0 and x1 < mapW and y1 < mapH then
                    x1, y1, x2, y2 = max(x1, 0), max(y1, 0), min(x2, mapW), min(y2, mapH)
                    if x2 - x1 >= 0.5 and y2 - y1 >= 0.5 then
                        used = used + 1
                        local t = f.rects[used]
                        if not t then
                            t = f:CreateTexture(nil, "BACKGROUND")
                            f.rects[used] = t
                        end
                        t:SetDrawLayer(layer, sub)
                        t:SetColorTexture(a.r, a.g, a.b, AREA_ALPHA)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", f, "TOPLEFT", x1, -y1)
                        t:SetSize(x2 - x1, y2 - y1)
                        t:Show()
                    end
                end
            end
        end
    end
    for i = used + 1, #f.rects do f.rects[i]:Hide() end

    local canLine = f.CreateLine ~= nil

    -- Dotted lines joining one quest's areas.
    used = 0
    if canLine then
        for _, l in ipairs(self.Links or {}) do
            local x1, y1, x2, y2 = clipSegment(sx(l[1]), sy(l[2]), sx(l[3]), sy(l[4]), mapW, mapH)
            if x1 then
                local dx, dy = x2 - x1, y2 - y1
                local len = sqrt(dx * dx + dy * dy)
                if len > 1 then
                    local ux, uy = dx / len, dy / len
                    local d = 0
                    while d < len and used < 400 do
                        local e = min(d + DASH, len)
                        used = used + 1
                        local dash = f.dashes[used]
                        if not dash then
                            dash = newLine(f, "OVERLAY", 1, 2)
                            f.dashes[used] = dash
                        end
                        dash:SetColorTexture(l[5], l[6], l[7], 0.9)
                        dash:SetStartPoint("TOPLEFT", f, x1 + ux * d, -(y1 + uy * d))
                        dash:SetEndPoint("TOPLEFT", f, x1 + ux * e, -(y1 + uy * e))
                        dash:Show()
                        d = e + DASH_GAP
                    end
                end
            end
        end
    end
    for i = used + 1, #f.dashes do f.dashes[i]:Hide() end

    -- Step badges.
    used = 0
    for _, a in ipairs(self.Areas or {}) do
        if a.badge then
            local x, y = sx(a.shape.ax), sy(a.shape.ay)
            if x > 4 and y > 4 and x < mapW - 4 and y < mapH - 4 then
                used = used + 1
                local fs = f.badges[used]
                if not fs then
                    fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    fs:SetDrawLayer("OVERLAY", 7)
                    local font, size = fs:GetFont()
                    if font then fs:SetFont(font, size or 10, "OUTLINE") end
                    f.badges[used] = fs
                end
                fs:SetText(a.badge)
                fs:SetTextColor(a.r, a.g, a.b)
                fs:ClearAllPoints()
                fs:SetPoint("CENTER", f, "TOPLEFT", x, -y)
                fs:Show()
            end
        end
    end
    for i = used + 1, #f.badges do f.badges[i]:Hide() end

    -- Patrol paths.
    used = 0
    local cr, cg, cb = PATROL_COLOR[1], PATROL_COLOR[2], PATROL_COLOR[3]
    for _, l in ipairs(self.Lines or {}) do
        local x1, y1, x2, y2 = clipSegment(sx(l[1]), sy(l[2]), sx(l[3]), sy(l[4]), mapW, mapH)
        if x1 and ((x2 - x1) ^ 2 + (y2 - y1) ^ 2) > 0.25 then
            used = used + 1
            local core, glow = f.cores[used], f.glows[used]
            if not core then
                if canLine then
                    -- A wide faint line under a thin bright one: neon.
                    glow = newLine(f, "OVERLAY", 2, 6)
                    glow:SetColorTexture(cr, cg, cb, 0.22)
                    core = newLine(f, "OVERLAY", 3, 2)
                    core:SetColorTexture(cr, cg, cb, 0.95)
                else
                    -- No line objects on this client: a dot per waypoint.
                    core = f:CreateTexture(nil, "OVERLAY")
                    core:SetColorTexture(cr, cg, cb, 0.95)
                    core:SetSize(3, 3)
                end
                f.cores[used], f.glows[used] = core, glow
            end
            if canLine then
                glow:SetStartPoint("TOPLEFT", f, x1, -y1)
                glow:SetEndPoint("TOPLEFT", f, x2, -y2)
                glow:Show()
                core:SetStartPoint("TOPLEFT", f, x1, -y1)
                core:SetEndPoint("TOPLEFT", f, x2, -y2)
            else
                core:ClearAllPoints()
                core:SetPoint("CENTER", f, "TOPLEFT", x1, -y1)
            end
            core:Show()
        end
    end
    for i = used + 1, #f.cores do
        f.cores[i]:Hide()
        if f.glows[i] then f.glows[i]:Hide() end
    end
end

---------------------------------------------------------------------------------------
-- Hover
---------------------------------------------------------------------------------------

local function contains(shape, wx, wy)
    if wx < shape.bx1 or wx > shape.bx2 or wy < shape.by1 or wy > shape.by2 then return false end
    local rects = shape.rects
    for i = 0, shape.n - 1 do
        local k = i * 4
        if wx >= rects[k + 1] and wx <= rects[k + 3] and wy >= rects[k + 2] and wy <= rects[k + 4] then
            return true
        end
    end
    return false
end

-- Areas under the cursor, smallest first, or nil when the cursor isn't
-- over the map.
function Overlay:AreasAt(engine)
    local f = self.Frame
    if not f or not f:IsVisible() or not engine.Frm:IsMouseOver() or engine.Scrolling then return nil end
    local cx, cy = GetCursorPosition()
    local eff = f:GetEffectiveScale()
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top or not eff or eff == 0 then return nil end
    local lx, ly = cx / eff - left, top - cy / eff
    if lx < 0 or ly < 0 or lx > engine.MapW or ly > engine.MapH then return nil end
    local wx = engine.MapPosXDraw + (lx - engine.MapW * .5) / engine.ScaleDraw
    local wy = engine.MapPosYDraw + (ly - engine.MapH * .5) / engine.ScaleDraw

    local hits
    for _, a in ipairs(self.Areas or {}) do
        if contains(a.shape, wx, wy) then
            hits = hits or {}
            hits[#hits + 1] = a
        end
    end
    if hits then table.sort(hits, function(a, b) return a.shape.size < b.shape.size end) end
    return hits
end

local function hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + .5), floor(g * 255 + .5), floor(b * 255 + .5))
end

function Overlay:UpdateHover(engine, now)
    if (self.HoverAt or 0) > now then return end
    self.HoverAt = now + HOVER_EVERY

    local f = self.Frame
    local owned = GameTooltip:IsShown() and GameTooltip:GetOwner() == f
    -- A pin (or anything else) already has the tooltip: leave it be.
    if GameTooltip:IsShown() and not owned then
        self.HoverKey = nil
        return
    end

    local hits = self:AreasAt(engine)
    if not hits then
        if owned then GameTooltip:Hide() end
        self.HoverKey = nil
        return
    end

    -- Only rebuild the tooltip when what's under the cursor changes.
    local parts = {}
    for _, a in ipairs(hits) do
        parts[#parts + 1] = tostring(a.questID or (a.drop and a.drop.itemId)) .. ":" .. tostring(a.objIndex)
    end
    local key = table.concat(parts, ",") .. ":" .. (Q.State.Serial or 0)
    if owned and key == self.HoverKey then return end
    self.HoverKey = key

    GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
    local first, seen = true, {}
    local function head(text, r, g, b)
        if first then GameTooltip:SetText(text, r, g, b) else GameTooltip:AddLine(text, r, g, b) end
        first = false
    end
    for _, a in ipairs(hits) do
        if a.drop then
            local id = "drop:" .. a.drop.itemId
            if not seen[id] then
                seen[id] = true
                head("Drop area: " .. a.drop.name, DROP_COLOR[1], DROP_COLOR[2], DROP_COLOR[3])
                for _, quest in ipairs(a.quests or {}) do
                    GameTooltip:AddLine("  starts " .. quest.title, 1, 1, 1)
                end
                if a.drop.droppers then GameTooltip:AddLine("  from " .. a.drop.droppers, 0.7, 0.7, 0.7, true) end
            end
        else
            local q = Q.State:GetQuest(a.questID)
            if q then
                if not seen[a.questID] then
                    seen[a.questID] = true
                    head(hex(a.r, a.g, a.b) .. q.title .. "|r", 1, 1, 1)
                end
                local o = q.objectives[a.objIndex]
                local text = (o and o.text ~= "" and o.text) or ("Objective " .. a.objIndex)
                if a.badge then text = "[" .. a.badge .. "] " .. text end
                GameTooltip:AddLine("  " .. text, 1, 1, 1, true)
            end
        end
    end
    GameTooltip:Show()
end

function Overlay:Start()
    local function dirty() self.Dirty = true end
    EventBus:Subscribe("QUEST_STATE_CHANGED", dirty)
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", dirty)
    EventBus:Subscribe("QUEST_CATALOG_READY", dirty)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", dirty)
end
