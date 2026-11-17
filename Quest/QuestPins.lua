-- Alchemy GPS | Quest / QuestPins
-- Decides which quest pins belong on the map window. The map engine
-- (Map/MinimapEngine.lua's RefreshQuestIcons/UpdateQuestIcons) owns the
-- frames and draws them through the same CreateMiniFrame/ClipFrameW
-- pool every other icon category uses; this file only fills its point
-- list. Three roles, the same three Carbonite's own generic quest pin
-- defines (Carbonite/Modules/Map/Pins/QuestPin.lua):
--
--   turnin     a quest ready to hand in. Blizzard's live POI where it
--              publishes one for the zone being shown, otherwise the
--              turn-in point from the bundled database.
--   objective  something still to do for a tracked quest. One pin per
--              cluster of the database's locations for each unfinished
--              objective, anywhere on the continent; the dungeon's
--              entrance for objectives found only inside one; Blizzard's
--              live POI for a quest the database knows no place for.
--   giver      a quest this character could pick up, in the zone being
--              shown. One pin per giver, listing every quest they offer;
--              quests picked up inside a dungeon are listed on one pin
--              at that dungeon's entrance.
--              A quest begun by an item that drops gets pins showing
--              that item's icon where it drops, instead. Only quests
--              this character could take right now are listed
--              (Quest/QuestRules.lua); a pin offering nothing but
--              low-level quests is drawn gray.
--
-- The giver role is new logic, not a port. Carbonite defines the role
-- and its icon but never draws it at a distance - its "what does this
-- NPC offer" is a tooltip on an NPC you are already looking at
-- (Tooltips.lua:524). What makes it possible here is Carbonite's data:
-- every row's Start string carries the giver's map and coordinates.
-- Availability is judged from that data - faction, class, level, event
-- category - plus Quest/QuestRules.lua's prerequisites, exclusives,
-- race, profession and reputation checks and the live "already done /
-- already in the log" ones.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest
local Api = Q.Api
local Catalog = Q.Catalog

local Pins = {}
Q.Pins = Pins

-- Pin sizes are fixed on screen (not zoom-scaled), like every other
-- icon the map draws. Icons themselves are Style-tab categories
-- (UI/StyleOptions.lua: QuestIcon, QuestObjectiveIcon, QuestGiverIcon).
local OBJECTIVE_SIZE = 14
local ACTIVE_SCALE = 1.35       -- pins of the quest the arrow is on

-- A colour per quest, so its objective pins and map areas read as one
-- set and match the swatch on its tracker row.
--
-- The log holds up to 40 quests, so there are 40 colours: 20 hues round
-- the whole wheel, each in a light and a slightly deeper pastel. They
-- are handed out in an order that keeps the quests you pick up close
-- together far apart on the wheel (hue steps of 7/20 of a turn,
-- alternating light and deep), and every quest in the log holds its
-- own until it leaves the log - no two quests share one, and a quest
-- doesn't change colour when another is turned in.
local PALETTE_SIZE = 40
local PALETTE = {}
do
    local function hsv(h, s, v)
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
        i = i % 6
        if i == 0 then return v, t, p elseif i == 1 then return q, v, p
        elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
        elseif i == 4 then return t, p, v end
        return v, p, q
    end
    for n = 0, PALETTE_SIZE - 1 do
        local hue = ((n * 7) % 20) / 20
        -- Light and deep alternate, and the second pass round the 20
        -- hues takes the other one of each pair: 40 different colours.
        local deep = ((n + math.floor(n / 20)) % 2 == 1)
        local r, g, b
        if deep then
            r, g, b = hsv(hue, 0.62, 0.90)
        else
            r, g, b = hsv(hue, 0.42, 1.00)
        end
        PALETTE[n + 1] = { r, g, b }
    end
end
Pins.PALETTE = PALETTE

-- Slot of a quest in the log, assigned on first use: the lowest one no
-- other quest in the log holds. Kept per character, so colours survive
-- a reload; QuestState.lua drops slots of quests that left the log.
local function colorSlot(questID)
    local State = Q.State
    if not State or not State:IsInLog(questID) then return nil end
    local slots = Q.Core:Char("ColorSlots")
    local slot = slots[questID]
    if slot and slot >= 1 and slot <= PALETTE_SIZE then return slot end
    local taken = {}
    for id, n in pairs(slots) do
        if id ~= questID and State:IsInLog(id) then taken[n] = true end
    end
    for n = 1, PALETTE_SIZE do
        if not taken[n] then
            slots[questID] = n
            return n
        end
    end
    return nil
end

function Pins:QuestColor(questID)
    local slot = colorSlot(questID) or (questID % PALETTE_SIZE + 1)
    local c = PALETTE[slot]
    return c[1], c[2], c[3]
end

local function isFilterOn(key)
    local filters = AlchemyGPS.db and AlchemyGPS.db.profile and AlchemyGPS.db.profile.MapFilters
    return not filters or filters[key] ~= false
end

local function hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(
        math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

---------------------------------------------------------------------------------------
-- Quest givers
---------------------------------------------------------------------------------------

-- Positions (zone percent, flat x,y list with .n) grouped into at most
-- `max` clusters: { {x=, y=, count=}, ... }, largest first. Each sits on
-- the member nearest its centre, so it is always on a real position.
local DROP_LINK = 7     -- zone percent
local function clusterPoints(area, max)
    local clusters = {}
    for i = 0, area.n - 1 do
        local x, y = area[i * 2 + 1], area[i * 2 + 2]
        local home
        for _, c in ipairs(clusters) do
            if math.abs(c.sx / c.count - x) <= DROP_LINK and math.abs(c.sy / c.count - y) <= DROP_LINK then
                home = c
                break
            end
        end
        if not home then
            home = { sx = 0, sy = 0, count = 0 }
            clusters[#clusters + 1] = home
        end
        home.sx, home.sy, home.count = home.sx + x, home.sy + y, home.count + 1
        home[home.count * 2 - 1], home[home.count * 2] = x, y
    end
    table.sort(clusters, function(c1, c2) return c1.count > c2.count end)
    for i = #clusters, max + 1, -1 do clusters[i] = nil end
    for _, c in ipairs(clusters) do
        local mx, my, bestD = c.sx / c.count, c.sy / c.count, nil
        for i = 1, c.count do
            local d = (c[i * 2 - 1] - mx) ^ 2 + (c[i * 2] - my) ^ 2
            if not bestD or d < bestD then bestD, c.x, c.y = d, c[i * 2 - 1], c[i * 2] end
        end
    end
    return clusters
end

-- The pin for an item that starts a quest shows the item's own icon.
local dropSpecs = {}
local function dropSpec(itemId)
    local spec = dropSpecs[itemId]
    if not spec then
        local icon
        local getIcon = (_G.C_Item and _G.C_Item.GetItemIconByID) or _G.GetItemIcon
        if getIcon then
            local ok, v = pcall(getIcon, itemId)
            if ok then icon = v end
        end
        spec = { tex = icon or "Interface\\Icons\\INV_Misc_Bag_08", coords = { 0.07, 0.93, 0.07, 0.93 } }
        dropSpecs[itemId] = spec
    end
    return spec
end

-- Pickup pins for one zone:
--   { {x=, y=, mId=, name=, quests={ {id=, title=, level=, trivial=}, ... },
--      id=       giver id (for its patrol path), on an ordinary giver
--      inside=   true on the one pin listing quests picked up in a dungeon
--      drop=     the Rules start-item record, on a "this item drops here" pin
--      area=     that item's drop positions in this zone (first pin only)
--   }, ... }
-- A quest is listed only if this character could take it right now
-- (Quest/QuestRules.lua). Depends only on the zone, the log, the
-- character's level and a few options, so it is rebuilt when one of
-- those changes rather than on the map's own refresh timer.
function Pins:GetGivers(mapId)
    local State, Core, Rules = Q.State, Q.Core, Q.Rules
    local key = table.concat({
        mapId, State.Serial, UnitLevel("player") or 0, Catalog.Count, Catalog.Version or 0,
        tostring(Core:Opt("ShowLowLevel")), tostring(Core:Opt("ShowEventQuests")),
        Rules and Rules.Serial or 0, Core.HiddenSerial or 0,
        -- "Already turned in" is asked of the client, which can still be
        -- filling that in just after login: don't trust one answer forever.
        math.floor(GetTime() / 30),
    }, ":")
    if self._giverKey == key then return self._givers end

    local givers, byGiver = {}, {}
    local list = Catalog.GiversByMap[mapId]
    local dungeons = Catalog.DungeonsByOwner[mapId]
    local dropQuests = Rules and Rules:GetStartItemQuests(mapId)
    if list or dungeons or dropQuests then
        local _, classToken = UnitClass("player")
        local opts = {
            faction = UnitFactionGroup("player"),
            class = classToken,
            level = UnitLevel("player") or 1,
            showLowLevel = Core:Opt("ShowLowLevel"),
            showEvents = Core:Opt("ShowEventQuests"),
        }
        local Map = AlchemyGPS.Map

        local hidden = Core:ProfileTable("HiddenQuests")

        -- ok, trivial: could this character pick the quest up right now?
        local function available(questID)
            if hidden[questID] or Catalog:IsBlacklisted(questID) then return false end
            local ok, trivial = Catalog:IsEligible(questID, opts)
            if not ok or State:IsInLog(questID) or Api:IsFlaggedCompleted(questID) then
                return false
            end
            if Rules then
                if not Rules:Check(questID, opts.level) then return false end
            else
                local prereq = Catalog:GetPrerequisite(questID)
                if prereq and not Api:IsFlaggedCompleted(prereq) then return false end
            end
            return true, trivial
        end

        local function addQuest(g, questID, trivial)
            g.has = g.has or {}
            if g.has[questID] then return end
            g.has[questID] = true
            local h = Catalog:GetHeader(questID)
            g.quests[#g.quests + 1] = {
                id = questID, title = h.name, level = h.level, trivial = trivial,
            }
        end

        for i = 1, list and #list or 0, 2 do
            local questID, se = list[i], list[i + 1]
            local ok, trivial = available(questID)
            local item = ok and Rules and Rules:GetStartItem(questID)
            -- An item-started quest whose drop positions are known is
            -- drawn from those below, not from the row's single point;
            -- one whose item drops all over the world isn't drawn at all
            -- (the row's point is just one of hundreds of creatures).
            if ok and not (item and (item.world or #item.areas > 0)) then
                local name, zone, x, y, giverId = Catalog:UnpackSE(se)
                if x > 0 or y > 0 then
                    local slot = (giverId or name) .. ":" .. x .. ":" .. y
                    local g = byGiver[slot]
                    if not g then
                        local wx, wy = Map:GetWorldPos(zone, x, y)
                        if wx then
                            g = { x = wx, y = wy, mId = zone, name = name, id = giverId, quests = {} }
                            byGiver[slot] = g
                            givers[#givers + 1] = g
                        end
                    end
                    if g then
                        if item then g.itemName = item.name end
                        addQuest(g, questID, trivial)
                    end
                end
            end
        end

        -- Quests begun by an item that drops: a pin on each cluster of
        -- places the things that drop it are found, and the whole spread
        -- handed to QuestOverlay.lua to shade.
        for _, questID in ipairs(dropQuests or {}) do
            local ok, trivial = available(questID)
            local item = ok and Rules:GetStartItem(questID)
            if item then
                for _, area in ipairs(item.areas) do
                    if area.mapId == mapId then
                        for n, c in ipairs(clusterPoints(area, 3)) do
                            local slot = "drop:" .. item.itemId .. ":" .. n
                            local g = byGiver[slot]
                            if not g then
                                local wx, wy = Map:GetWorldPos(mapId, c.x, c.y)
                                if wx then
                                    g = {
                                        x = wx, y = wy, mId = mapId, name = item.name, quests = {},
                                        drop = item, area = (n == 1) and area or nil,
                                    }
                                    byGiver[slot] = g
                                    givers[#givers + 1] = g
                                end
                            end
                            if g then addQuest(g, questID, trivial) end
                        end
                    end
                end
            end
        end

        -- Quests picked up inside a dungeon entered from this zone: one
        -- pin at the entrance - where the map's own entrance flag is -
        -- listing them. Instances that share an entrance (the two
        -- Ahn'Qiraj raids) share the pin.
        for _, instanceId in ipairs(dungeons or {}) do
            local quests = Catalog.GiversByDungeon[instanceId]
            local name, owner, wx, wy
            if quests then name, owner, wx, wy = Catalog:GetInstanceEntrance(instanceId) end
            if wx then
                local slot = "dungeon:" .. wx .. ":" .. wy
                for _, questID in ipairs(quests) do
                    local ok, trivial = available(questID)
                    if ok then
                        local g = byGiver[slot]
                        if not g then
                            g = {
                                x = wx, y = wy, mId = owner, name = name, quests = {},
                                inside = true, names = { [name] = true },
                            }
                            byGiver[slot] = g
                            givers[#givers + 1] = g
                        elseif not g.names[name] then
                            g.names[name] = true
                            g.name = g.name .. " / " .. name
                        end
                        addQuest(g, questID, trivial)
                    end
                end
            end
        end

        for _, g in ipairs(givers) do
            table.sort(g.quests, function(q1, q2)
                if q1.level ~= q2.level then return q1.level < q2.level end
                return q1.id < q2.id
            end)
            -- Gray pin only when everything on it is a low-level quest.
            g.trivial = true
            for _, quest in ipairs(g.quests) do
                if not quest.trivial then g.trivial = false; break end
            end
            g.patrol = (g.id and Rules and Rules:GetPatrol(g.id)) and true or nil
        end
    end

    self._giverKey, self._givers = key, givers
    return givers
end

---------------------------------------------------------------------------------------
-- Collecting everything for the map
---------------------------------------------------------------------------------------

local function questLines(q, onlyIndex)
    local lines = {}
    for i, o in ipairs(q.objectives) do
        if (not onlyIndex or onlyIndex == i) and o.text ~= "" then
            if o.finished then
                lines[#lines + 1] = { o.text, 0.5, 0.75, 0.5 }
            else
                lines[#lines + 1] = { o.text, 1, 1, 1 }
            end
        end
    end
    return lines
end

-- Appends quest points for the engine's current zone/continent to pts.
-- Point: { x, y (world), role, iconSpec, size, r, g, b, label, lines,
--          questID, giver }
function Pins:Collect(engine, pts)
    local State = Q.State
    if not State or not State.Scanned then return end

    local StyleOptions = AlchemyGPS.UI.StyleOptions
    local Map = AlchemyGPS.Map
    local mapId, cont = engine.MapId, engine.Cont
    local target = Q.Routing and Q.Routing.Target
    local activeQuest = target and target.kind == "quest" and target.questID or nil

    local live = Api:GetQuestsOnMap(mapId)
    local liveById
    if live then
        liveById = {}
        for _, e in ipairs(live) do
            if e.questID and type(e.x) == "number" and type(e.y) == "number" then
                liveById[e.questID] = e
            end
        end
    end

    local showTurnIn = isFilterOn("QuestTurnIn")
    local showObjective = isFilterOn("QuestObjective")
    local turnInSpec = StyleOptions:GetOption("QuestIcon")
    local objectiveSpec = StyleOptions:GetOption("QuestObjectiveIcon")

    for _, q in ipairs(State.Quests) do
        local questID = q.questID
        local scale = (questID == activeQuest) and ACTIVE_SCALE or 1

        if q.ready then
            if showTurnIn then
                local lines = { { "Ready to turn in", 0.4, 1, 0.4 } }
                local placed = false
                local e = liveById and liveById[questID]
                if e then
                    local wx, wy = Map:GetWorldPos(mapId, e.x * 100, e.y * 100)
                    if wx then
                        pts[#pts + 1] = {
                            x = wx, y = wy, role = "turnin", iconSpec = turnInSpec,
                            size = 16 * scale, label = q.title, lines = lines, questID = questID,
                        }
                        placed = true
                    end
                end
                local endpoints = Catalog:GetEndpoints(questID, true)
                if endpoints then
                    for i = 1, #endpoints do
                        local name, zone, x, y = Catalog:UnpackSE(endpoints[i])
                        -- The row's own turn-in point anywhere on this
                        -- continent; an alternate only in the zone shown.
                        -- Skipped in this zone when Blizzard already
                        -- placed the quest here.
                        local wanted = (i == 1 or zone == mapId) and not (placed and zone == mapId)
                        if wanted and (x > 0 or y > 0) and Catalog:GetContinent(zone) == cont then
                            local wx, wy = Map:GetWorldPos(zone, x, y)
                            if wx then
                                pts[#pts + 1] = {
                                    x = wx, y = wy, role = "turnin", iconSpec = turnInSpec,
                                    size = 16 * scale, label = q.title, questID = questID,
                                    lines = { { "Turn in: " .. name, 0.4, 1, 0.4 } },
                                }
                            end
                        end
                    end
                end
                -- Turned in inside a dungeon: a pin at its entrance.
                local inside = Catalog:GetEndpointDungeons(questID, true)
                if inside then
                    for i = 1, #inside do
                        local name, owner, wx, wy = Catalog:GetInstanceEntrance(inside[i])
                        if wx and Catalog:GetContinent(owner) == cont
                            and not (placed and owner == mapId) then
                            pts[#pts + 1] = {
                                x = wx, y = wy, role = "turnin", iconSpec = turnInSpec,
                                size = 16 * scale, label = q.title, questID = questID,
                                lines = { { "Turn in inside " .. name, 0.4, 1, 0.4 } },
                            }
                        end
                    end
                end
            end
        elseif showObjective and State:IsWatched(questID) then
            local r, g, b = self:QuestColor(questID)
            local placed = false
            local dungeons    -- [instanceId] = tooltip lines of the objectives inside it
            for i, o in ipairs(q.objectives) do
                if not o.finished then
                    local clusters = Catalog:GetObjectiveClusters(questID, i)
                    if clusters then
                        local lines = questLines(q, i)
                        for _, c in ipairs(clusters) do
                            if Catalog:GetContinent(c.zone) == cont then
                                pts[#pts + 1] = {
                                    x = c.x, y = c.y, role = "objective", iconSpec = objectiveSpec,
                                    size = OBJECTIVE_SIZE * scale, r = r, g = g, b = b,
                                    label = q.title, lines = lines, questID = questID,
                                }
                                placed = true
                            end
                        end
                    end
                    local geo = Catalog:GetObjectiveGeo(questID, i)
                    if geo and geo.n == 0 and geo.dungeons then
                        dungeons = dungeons or {}
                        for _, id in ipairs(geo.dungeons) do
                            local lines = dungeons[id]
                            if not lines then
                                lines = {}
                                dungeons[id] = lines
                            end
                            if o.text ~= "" then lines[#lines + 1] = { o.text, 1, 1, 1 } end
                        end
                    end
                end
            end
            -- Objectives that are only found inside a dungeon: one pin at
            -- the entrance of each dungeon they can be done in. Knowing
            -- that much also rules out Blizzard's POI below, the same
            -- order QuestRouting.lua resolves in.
            if dungeons then
                placed = true
                for id, lines in pairs(dungeons) do
                    local name, owner, wx, wy = Catalog:GetInstanceEntrance(id)
                    if wx and Catalog:GetContinent(owner) == cont then
                        table.insert(lines, 1, { "Inside " .. name, 0.5, 0.75, 1 })
                        pts[#pts + 1] = {
                            x = wx, y = wy, role = "objective", iconSpec = objectiveSpec,
                            size = OBJECTIVE_SIZE * scale, r = r, g = g, b = b,
                            label = q.title, lines = lines, questID = questID,
                        }
                    end
                end
            end
            local e = not placed and liveById and liveById[questID]
            if e then
                local wx, wy = Map:GetWorldPos(mapId, e.x * 100, e.y * 100)
                if wx then
                    pts[#pts + 1] = {
                        x = wx, y = wy, role = "objective", iconSpec = objectiveSpec,
                        size = OBJECTIVE_SIZE * scale, r = r, g = g, b = b,
                        label = q.title, lines = questLines(q), questID = questID,
                    }
                end
            end
        end
    end

    if cont and Catalog.Ready and isFilterOn("QuestGiver") then
        local giverSpec = StyleOptions:GetOption("QuestGiverIcon")
        local core = Q.Core
        local showPatrols = core:Opt("ShowPatrolPaths")
        for _, g in ipairs(self:GetGivers(mapId)) do
            local lines = {}
            if g.inside then
                lines[1] = { "Picked up inside the dungeon", 0.5, 0.75, 1 }
            elseif g.drop then
                lines[1] = { "Dropped item - starts a quest", 1, 0.6, 0.2 }
                if g.drop.droppers then
                    lines[2] = { "Drops from: " .. g.drop.droppers, 0.8, 0.8, 0.8, true }
                end
            elseif g.itemName then
                lines[1] = { "Starts from the item: " .. g.itemName, 1, 0.6, 0.2 }
            end
            if g.patrol then
                lines[#lines + 1] = {
                    showPatrols and "Wanders - the line is the route walked"
                        or "Wanders (patrol paths are switched off)", 0.3, 1, 1,
                }
            end
            for _, quest in ipairs(g.quests) do
                local r, gg, b = core:Difficulty(quest.level, quest.id)
                lines[#lines + 1] = { ("[%d] %s"):format(quest.level, quest.title), r, gg, b }
            end
            local pt = {
                x = g.x, y = g.y, role = "giver", size = 16,
                iconSpec = g.drop and dropSpec(g.drop.itemId) or giverSpec,
                label = g.drop and ("Item: " .. g.name) or g.name, lines = lines, giver = g,
            }
            if g.trivial then
                -- Low-level quests only: a gray marker, so it reads as
                -- optional at a glance.
                pt.desat, pt.r, pt.g, pt.b = true, 0.7, 0.7, 0.7
            end
            pts[#pts + 1] = pt
        end
    end
end

---------------------------------------------------------------------------------------
-- Interaction (called by the map engine's pin frames)
---------------------------------------------------------------------------------------

function Pins:ShowTooltip(frame, pt)
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    GameTooltip:SetText(pt.label or "?")
    if pt.lines then
        for _, line in ipairs(pt.lines) do
            GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
        end
    end
    if pt.role == "giver" then
        GameTooltip:AddLine("Click: point the arrow here", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: hide a quest from the map", 0.6, 0.6, 0.6)
    elseif pt.questID then
        GameTooltip:AddLine("Click: route to this quest", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function Pins:OnClick(pt)
    local Routing = Q.Routing
    if not Routing then return end
    if pt.role == "giver" then
        local g = pt.giver
        local n = #g.quests
        Routing:ToggleManualPoint({
            x = g.x, y = g.y, mId = g.mId, name = g.name,
            detail = (n == 1) and g.quests[1].title or (n .. " quests available"),
        })
    elseif pt.questID then
        Routing:ToggleManualQuest(pt.questID)
    end
end

---------------------------------------------------------------------------------------
-- Hiding quests
--
-- A quest the player never wants offered on the map (one that is bugged
-- on the server, or that they will never do) can be hidden: right-click
-- a pickup pin and pick it. Hidden quests are per profile, brought back
-- from the Settings window or /gps quest unhide.
---------------------------------------------------------------------------------------

function Pins:SetHidden(questID, hide)
    local Core = Q.Core
    Core:ProfileTable("HiddenQuests")[questID] = hide and true or nil
    Core.HiddenSerial = (Core.HiddenSerial or 0) + 1
    -- Through the option message, so the map and overlay refresh.
    EventBus:Fire("QUEST_OPTION_CHANGED", "HiddenQuests")
end

function Pins:UnhideAll()
    local hidden = Q.Core:ProfileTable("HiddenQuests")
    for id in pairs(hidden) do hidden[id] = nil end
    self:SetHidden(0, false)
end

function Pins:NumHidden()
    local n = 0
    for _ in pairs(Q.Core:ProfileTable("HiddenQuests")) do n = n + 1 end
    return n
end

-- A small menu at the cursor: one row per quest on the pin; click one
-- to hide it.
function Pins:OnRightClick(frm, pt)
    if pt.role ~= "giver" or not pt.giver or #pt.giver.quests == 0 then return end
    local menu = self.HideMenu
    if not menu then
        menu = CreateFrame("Frame", "AlchemyGPSQuestHideMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        if menu.SetBackdrop then
            menu:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            menu:SetBackdropColor(0, 0, 0, 0.92)
        end
        menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menu.title:SetPoint("TOPLEFT", 10, -8)
        menu.title:SetText("Hide from the map:")
        menu.rows = {}
        -- Closes on a click elsewhere, or when the cursor wanders off.
        menu:SetScript("OnUpdate", function(m, elapsed)
            if m:IsMouseOver(8, -8, -8, 8) then
                m.away = 0
            else
                m.away = (m.away or 0) + elapsed
                if m.away > 1.5 or IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                    m:Hide()
                end
            end
        end)
        tinsert(UISpecialFrames, "AlchemyGPSQuestHideMenu")
        self.HideMenu = menu
    end

    local quests = pt.giver.quests
    local width = 160
    for i, quest in ipairs(quests) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(16)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.12)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetJustifyH("LEFT")
            menu.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -8 - 14 - (i - 1) * 16)
        row.text:SetText(self:ColoredTitle(quest.level, quest.title, quest.id))
        width = math.max(width, (row.text:GetStringWidth() or 100) + 20)
        row:SetScript("OnClick", function()
            menu:Hide()
            self:SetHidden(quest.id, true)
            Q.Core.Say("hidden from the map: %s (quest %d). /gps quest unhide %d brings it back.",
                quest.title, quest.id, quest.id)
        end)
        row:Show()
    end
    for i = #quests + 1, #menu.rows do menu.rows[i]:Hide() end
    for i = 1, #quests do menu.rows[i]:SetWidth(width - 12) end
    menu:SetSize(width, 14 + 14 + #quests * 16)

    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale - 6, cy / scale + 6)
    menu.away = 0
    menu:Show()
end

-- Coloured "[level] title" for a quest, shared with the tracker and the
-- quest list. Give the quest id where there is one: the client grades
-- quests individually, and that is what its own log colours by.
function Pins:ColoredTitle(level, title, questID)
    local r, g, b = Q.Core:Difficulty(level, questID)
    if level and level > 0 then
        return ("%s[%d] %s|r"):format(hex(r, g, b), level, title)
    end
    return ("%s%s|r"):format(hex(r, g, b), title)
end

function Pins:Start()
    -- Quest state, the route, and the database finishing its load all
    -- change what should be on the map; ask the engine for a refresh on
    -- its next tick rather than waiting out its two-second timer.
    local function refreshSoon()
        local engine = AlchemyGPS.Map
        if engine then engine.QuestRefreshAt = 0 end
    end
    EventBus:Subscribe("QUEST_STATE_CHANGED", refreshSoon)
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", refreshSoon)
    EventBus:Subscribe("QUEST_CATALOG_READY", refreshSoon)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", refreshSoon)
end
