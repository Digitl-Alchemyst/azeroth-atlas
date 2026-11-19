-- Azeroth Atlas | Quest / QuestCatalog
-- Accessors over the bundled quest database (Quest/Data/*.lua - a
-- generated port of Carbonite.Quests' own Questie-merged "camelot"
-- data, see Tools/gen_quest_data.py). This is static knowledge: where
-- a quest starts and ends, where its objectives are found, what it
-- requires. Live state - what is in the log, what is finished - is
-- QuestState.lua's job, and the two are never merged; that split is
-- Carbonite's own (QuestCatalog.lua's header: "Blizzard is the
-- authority for mutable runtime quest state... the two stores are
-- intentionally separate").
--
-- Row shape, exactly as Carbonite ships it:
--   Quest      = "name|side|level|minLevel|nextId|category|xp"
--   Start, End = "giverId|mapId|32|x|y"         (x/y: 0-100 zone percent)
--   Objectives = { [n] = { "name|mapId|typ|x|y|w|h", ... } }
--                typ 32 = a point; typ 35 = a rectangle whose w/h are in
--                1002x668 zone-pixel units.
-- mapId is this client's own uiMapID - the same ids Map/Data/
-- NxMapData.lua's MapWorldInfo is keyed by - so Map:GetWorldPos
-- converts these positions with no id translation.
--
-- Ported from Carbonite.Quests/DataAndComm.lua: Unpack (:39),
-- _pickAltSE/ResolveStart/ResolveEnd (:168-208), UnpackSE (:210),
-- IsUsableLocation (:513), GetClosestObjectivePos' table branch
-- (:583-644). What differs, and why:
--   - Objective lists are parsed once into flat world-space arrays
--     (GetObjectiveGeo) instead of being re-split on every distance
--     check. Same numbers, without the per-tick string garbage.
--   - GetClosestObjectivePos' single-string branch isn't ported: every
--     objective in this data set is a list.
--   - Instance maps have no world position here (Map:GetWorldPos only
--     knows continent zones), so an objective inside a dungeon is
--     reported in geo.dungeons and resolved to an entrance by
--     QuestRouting.lua, from QuestData.Instances - the same instances,
--     at the same places, as the map's own entrance flags
--     (Map/Data/GuideDungeonEntrance.lua).
--   - The data writes a dungeon objective a second way that Carbonite
--     itself ignores: the outdoor zone the dungeon is entered from,
--     with the coordinates zeroed ("Garrett Family Treasure|1418|32|0|0"
--     - Uldaman, by way of the Badlands). Carbonite's IsUsableLocation
--     rejects those rows and its tracking falls through to the turn-in
--     NPC, which sends the player back to the quest giver. Such a row
--     doesn't say which dungeon either, and a zone can lead to several.
--     QuestData.ObjectiveDungeons carries the answer for each of them,
--     worked out per objective when the data is generated; the rows
--     themselves are skipped here just as Carbonite skips them.
--   - An objective can be found in more than one dungeon (an item
--     several bosses drop), so geo.dungeons is a list.
--   - GetObjectiveClusters and the giver index are new; Carbonite has
--     no at-a-distance giver pins and draws objective areas a
--     different way.

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Q = AzerothAtlas.Modules.Quest
local Map = AzerothAtlas.Map

local Catalog = {}
Q.Catalog = Catalog

local QuestData = AzerothAtlas.QuestData or {}
local Names = QuestData.Names or {}
local Prev = QuestData.Prev or {}
local RequiredClasses = QuestData.RequiredClasses or {}
local StartAlts = QuestData.StartAlts or {}
local EndAlts = QuestData.EndAlts or {}
local Instances = QuestData.Instances or {}
local ObjectiveDungeons = QuestData.ObjectiveDungeons or {}
local EndpointDungeons = QuestData.EndpointDungeons or {}
-- Hand-maintained (Quest/Data/QuestDBManual.lua): quests whose work is
-- done inside a dungeon that no generated table can say, and Start /
-- End positions the generated rows lack.
local QuestDungeons = QuestData.QuestDungeons or {}
local ManualStart = QuestData.ManualStart or {}
local ManualEnd = QuestData.ManualEnd or {}
local ManualObjectives = QuestData.ManualObjectives or {}
-- 2026-11-18: class quests no source marks (Ground to Keep, rogue).
for questID, mask in pairs(QuestData.ManualRequiredClasses or {}) do
    RequiredClasses[questID] = mask
end
-- 2026-11-18: items the player brings (QuestDBRules' ProvidedItems, plus
-- QuestDBManual's ManualProvidedItems) and hand-written objective notes.
local ProvidedItems = QuestData.ProvidedItems or {}
for questID, packed in pairs(QuestData.ManualProvidedItems or {}) do
    ProvidedItems[questID] = packed
end
local ManualObjectiveNotes = QuestData.ObjectiveNotes or {}
local EMPTY = {}

Catalog.Quests = {}
Catalog.Count = 0
Catalog.Ready = false
Catalog.GiversByMap = {}
Catalog.GiversByDungeon = {}    -- [instanceId] = { questID, ... } picked up inside it
Catalog.DungeonsByOwner = {}    -- [outdoor mapId] = { instanceId, ... } entered from it

local strsplit = strsplit
local tonumber = tonumber
local floor = math.floor
local huge = math.huge

-- Carbonite's own list of event categories (Data/Shared/QuestCats.lua,
-- Nx.QuestCategoryHoliday): Children's Week, Darkmoon Faire, Lunar
-- Festival, Midsummer, Love is in the Air, Hallow's End, Harvest
-- Festival, Winter Veil and the rest. These quests exist only while
-- their event runs, which this addon can't tell, so pickup pins leave
-- them out unless asked.
local HOLIDAY_CATEGORY = {
    [3] = true, [15] = true, [24] = true, [29] = true, [32] = true, [33] = true,
    [37] = true, [39] = true, [40] = true, [41] = true, [89] = true, [118] = true,
    [131] = true, [169] = true, [185] = true, [186] = true,
}

-- Questie's requiredClasses bit for each class token.
local CLASS_BIT = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256,
    MONK = 512, DRUID = 1024,
}

---------------------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------------------

-- The data files only define builder functions; the rows are created
-- here, one file's worth per timer tick, so login doesn't pay for all
-- of it in one frame (Carbonite staggers its own load the same way,
-- SuperTrack.lua's LoadQuestDB). Each builder is dropped once run so
-- its compiled body can be collected.
function Catalog:Start()
    self:StartLearning()
    if self.Ready or self.Loading then return end
    local chunks = QuestData.Chunks
    if type(chunks) ~= "table" or #chunks == 0 then
        self:FinishLoad()
        return
    end

    self.Loading = true
    local index = 0
    local function step()
        index = index + 1
        local build = chunks[index]
        if not build then
            QuestData.Chunks = nil
            self:FinishLoad()
            return
        end
        chunks[index] = false
        local ok, rows = pcall(build)
        if ok and type(rows) == "table" then
            local quests, count = self.Quests, self.Count
            for id, row in pairs(rows) do
                quests[id] = row
                count = count + 1
            end
            self.Count = count
        else
            Q.Core.log:error("quest data file %d failed to load: %s", index, tostring(rows))
        end
        Q.Core:After(0.15, step)
    end
    Q.Core:After(0.5, step)
end

function Catalog:FinishLoad()
    self:ApplyManual()
    self:ApplyLearned()
    self:BuildGiverIndex()
    self.Loading = false
    self.Ready = true
    EventBus:Fire("QUEST_CATALOG_READY")
end

---------------------------------------------------------------------------------------
-- The quest blacklist
---------------------------------------------------------------------------------------

-- Questie's blacklist as it applies on this server (generated into
-- Quest/Data/QuestDBImported.lua): duplicates, quests not in the game,
-- quests from another expansion. Never offered on the map.
local blacklist
function Catalog:IsBlacklisted(questID)
    if not blacklist then
        blacklist = {}
        for id in tostring(QuestData.Blacklist or ""):gmatch("%d+") do blacklist[tonumber(id)] = true end
    end
    return blacklist[questID] == true
end

---------------------------------------------------------------------------------------
-- Learned positions
--
-- Some quests have no giver or turn-in position in any data the addon
-- ships (this server's own quests especially: QuestieDB knows "Big, No,
-- MASSIVE Iron Axes" and its giver Grolkar, but not where Grolkar
-- stands). When the player is offered such a quest, or hands one in,
-- the NPC they're talking to is right there: its id and the player's
-- position are saved (per profile, so every character benefits) and
-- used as the quest's Start / End from then on.
---------------------------------------------------------------------------------------

local function hasPosition(se)
    if type(se) ~= "string" then return false end
    local _, zone, _, x, y = strsplit("|", se)
    return (tonumber(zone) or 0) ~= 0 and ((tonumber(x) or 0) > 0 or (tonumber(y) or 0) > 0)
end

-- Fills the rows' missing Start / End from Quest/Data/QuestDBManual.lua.
-- Runs before ApplyLearned, which only fills what is still missing.
function Catalog:ApplyManual()
    -- 2026-11-18: whole rows no source has (A New Need for Shadow Protection).
    for questID, row in pairs(QuestData.ManualRows or EMPTY) do
        if not self.Quests[questID] then
            self.Quests[questID] = row
            self.Count = self.Count + 1
        end
    end
    -- 2026-11-19: a row's faction, when its source has it wrong (Not My
    -- Circus). The side is the header's second field.
    for questID, side in pairs(QuestData.ManualSide or EMPTY) do
        local row = self.Quests[questID]
        if row and type(row.Quest) == "string" then
            row.Quest = row.Quest:gsub("^([^|]*)|[^|]*", "%1|" .. side, 1)
        end
    end
    for questID, se in pairs(ManualStart) do
        local row = self.Quests[questID]
        if row and not hasPosition(row.Start) then row.Start = se end
    end
    for questID, se in pairs(ManualEnd) do
        local row = self.Quests[questID]
        if row and not hasPosition(row.End) then row.End = se end
    end
    -- 2026-11-18: unlike Start / End, these replace what the row has.
    for questID, objs in pairs(ManualObjectives) do
        local row = self.Quests[questID]
        if row then
            row.Objectives = row.Objectives or {}
            for index, list in pairs(objs) do row.Objectives[index] = list end
            row._geo = nil
        end
    end
end

-- Fills the rows' missing Start / End from the saved positions.
function Catalog:ApplyLearned()
    local learned = Q.Core:ProfileTable("Learned")
    for questID, entry in pairs(learned) do
        local row = self.Quests[questID]
        if row and type(entry) == "table" then
            if entry.s and not hasPosition(row.Start) then row.Start = entry.s end
            if entry.e and not hasPosition(row.End) then row.End = entry.e end
        end
    end
end

-- The NPC the player is talking to: id, name (nil for an object, an
-- item or no one).
local function talkingTo()
    local guid = UnitGUID("npc")
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    return tonumber(id), UnitName("npc")
end

function Catalog:LearnPosition(questID, useEnd)
    local row = questID and self.Quests[questID]
    if not row then return end
    local learned = Q.Core:ProfileTable("Learned")
    local entry = learned[questID] or {}
    -- A guessed giver (see below) gives way to the real one.
    local guessed = not useEnd and entry.guess
    if hasPosition(useEnd and row.End or row.Start) and not guessed then return end
    local npcId, name = talkingTo()
    if not npcId then return end
    local mapId = Map:GetDisplayableMapForPlayer()
    if not mapId or mapId == 0 or not C_Map or not C_Map.GetPlayerMapPosition then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
    local px, py
    if ok and pos then px, py = pos:GetXY() end
    if not px or (px == 0 and py == 0) then return end

    local se = ("%d|%d|32|%.2f|%.2f"):format(npcId, mapId, px * 100, py * 100)
    if name and not Names[npcId] then Names[npcId] = name end
    learned[questID] = entry
    if useEnd then
        entry.e = se
        row.End = se
        -- Nothing anywhere says who gives this quest: the one who takes
        -- it back is the best guess (it usually is the same NPC, and is
        -- for the repeatable reputation quests these mostly are). Kept
        -- only until the quest is seen being offered.
        if not hasPosition(row.Start) and not (Q.Rules and Q.Rules:GetStartItem(questID)) then
            entry.s, entry.guess = se, true
            row.Start = se
        end
    else
        entry.s, entry.guess = se, nil
        row.Start = se
    end
    if name then entry.n = name end
    self.Version = (self.Version or 0) + 1
    row._startDungeons, row._endDungeons = nil, nil
    self:BuildGiverIndex()
    Q.Core.log:info("learned where %s %s quest %d", name or "?", useEnd and "takes" or "gives", questID)
    EventBus:Fire("QUEST_CATALOG_READY")
end

function Catalog:StartLearning()
    if self.LearnFrame then return end
    local frame = CreateFrame("Frame")
    self.LearnFrame = frame
    for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
        Q.Core:SafeRegisterEvent(frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if not self.Ready or not GetQuestID then return end
        local questID = GetQuestID()
        if not questID or questID == 0 then return end
        self:LearnPosition(questID, event ~= "QUEST_DETAIL")
    end)
end

---------------------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------------------

local contCache = {}

-- Continent index for a map id, or nil if Map:GetWorldPos can't place
-- it (an instance, a battleground, an id this client's catalog lacks).
function Catalog:GetContinent(zone)
    if not zone or zone == 0 then return nil end
    local cont = contCache[zone]
    if cont == nil then
        cont = Map:FindContinent(zone)
        -- Only hits are cached: a dungeon floor joins the map's catalog
        -- when the player first enters it (MinimapEngine
        -- :ResolveDungeonMap), after it may already have been asked about.
        if cont then contCache[zone] = cont end
    end
    return cont
end

-- The instance id the player is inside right now (GetInstanceInfo's
-- eighth return - the same ids QuestData.Instances is keyed by), or nil.
function Catalog:CurrentInstance()
    if not IsInInstance or not IsInInstance() then return nil end
    local id = GetInstanceInfo and select(8, GetInstanceInfo())
    return self:InstanceKey(tonumber(id))
end

-- QuestData.Instances key for an instance id. WoW Forever's own dungeons
-- are keyed by instance id; the classic ones by their first map's
-- uiMapID (Wailing Caverns: instance 43, key 279) - found through the
-- room data's map list (Map/Data/DungeonRoomData.lua). 2026-11-16.
function Catalog:InstanceKey(id)
    if not id then return nil end
    if Instances[id] then return id end
    local data = AzerothAtlas.DungeonRoomData
    local maps = data and data.ClientFloors and data.ClientFloors[id]
    for _, mapId in ipairs(maps or {}) do
        if Instances[mapId] then return mapId end
    end
    return nil
end

function Catalog:IsInstanceZone(zone)
    return zone ~= nil and Instances[zone] ~= nil
end

-- Where an instance's entrance sits outdoors:
-- name, ownerMapId, worldX, worldY (nil if unknown or unplaceable).
function Catalog:GetInstanceEntrance(zone)
    local packed = zone and Instances[zone]
    if not packed then return nil end
    local name, owner, x, y = strsplit("|", packed)
    owner = tonumber(owner)
    local wx, wy = Map:GetWorldPos(owner, tonumber(x), tonumber(y))
    if not wx then return nil end
    return name, owner, wx, wy
end

---------------------------------------------------------------------------------------
-- Row unpacking
---------------------------------------------------------------------------------------

-- { name, side, level, minLevel, nextId, category } for a quest, parsed
-- once and cached on the row. side: 1 = Alliance only, 2 = Horde only,
-- anything else = both (ProcessQuestDB's own reading of it).
function Catalog:GetHeader(questID)
    local row = self.Quests[questID]
    if not row then return nil end
    local h = row._h
    if not h then
        local name, side, level, minLevel, nextId, category, xp = strsplit("|", row.Quest or "")
        h = {
            name = name or "?",
            side = tonumber(side) or 0,
            level = tonumber(level) or 0,
            minLevel = tonumber(minLevel) or 0,
            nextId = tonumber(nextId) or 0,
            category = tonumber(category) or 0,
            xp = tonumber(xp) or 0,     -- 2026-11-18: QuestieDB's XP, the details panel's fallback
        }
        row._h = h
    end
    return h
end

function Catalog:GetName(questID)
    local h = self:GetHeader(questID)
    return h and h.name or nil
end

-- name, mapId, x, y, giverId for a Start/End string. A non-numeric
-- first field is the name itself (Carbonite writes those for rows it
-- synthesizes from live data).
function Catalog:UnpackSE(str)
    if type(str) ~= "string" then return nil end
    local first, zone, _, x, y = strsplit("|", str)
    local id = tonumber(first)
    local name
    if id then
        name = Names[id]
    elseif first and first ~= "" then
        name = first
    end
    return name or "?", tonumber(zone) or 0, tonumber(x) or 0, tonumber(y) or 0, id
end

-- Every place a quest can be picked up (useEnd false) or turned in
-- (useEnd true): the row's own string first, then its alternates.
function Catalog:GetEndpoints(questID, useEnd)
    local row = self.Quests[questID]
    if not row then return nil end
    local primary = useEnd and row.End or row.Start
    local alts = (useEnd and EndAlts or StartAlts)[questID]
    if not alts then
        return primary and { primary } or nil
    end
    local list = {}
    if primary then list[1] = primary end
    for entry in alts:gmatch("[^;]+") do
        if entry ~= primary then list[#list + 1] = entry end
    end
    return #list > 0 and list or nil
end

-- Appends id to list unless it is already there; creates the list.
local function addUnique(list, id)
    if not list then return { id } end
    for i = 1, #list do
        if list[i] == id then return list end
    end
    list[#list + 1] = id
    return list
end

-- The instances a quest is picked up inside (useEnd false) or turned in
-- inside (useEnd true): { instanceId, ... } or nil, cached on the row.
-- Two sources - a Start/End string that names an instance's own map id,
-- and QuestData.EndpointDungeons for the rows that have no Start/End
-- at all (most of Blackrock Depths).
function Catalog:GetEndpointDungeons(questID, useEnd)
    local row = self.Quests[questID]
    if not row then return nil end
    local key = useEnd and "_endDungeons" or "_startDungeons"
    local list = row[key]
    if list == nil then
        local found
        local endpoints = self:GetEndpoints(questID, useEnd)
        if endpoints then
            for i = 1, #endpoints do
                local _, zone = strsplit("|", endpoints[i])
                zone = tonumber(zone)
                if zone and Instances[zone] then found = addUnique(found, zone) end
            end
        end
        local packed = EndpointDungeons[questID]
        if packed then
            local starts, ends = strsplit("|", packed)
            for id in ((useEnd and ends or starts) or ""):gmatch("%d+") do
                id = tonumber(id)
                if Instances[id] then found = addUnique(found, id) end
            end
        end
        list = found or false
        row[key] = list
    end
    return list or nil
end

-- A Start/End position is usable when it names a continent zone and
-- isn't the 0,0 "no coordinates" placeholder.
local function usableWorldPoint(zone, x, y)
    return Catalog:GetContinent(zone) ~= nil and (x > 0 or y > 0)
end

---------------------------------------------------------------------------------------
-- Objective geometry
---------------------------------------------------------------------------------------

local GEO_STRIDE = 6    -- zone, isPoint(1/0), wx1, wy1, wx2, wy2

-- { [objIndex] = { instanceId, ... } } out of a quest's
-- ObjectiveDungeons string ("1=230;2=242,250"), parsed once and cached
-- on the row. false when the quest has none.
local function objectiveDungeons(questID, row)
    local parsed = row._dungeons
    if parsed == nil then
        parsed = false
        local packed = ObjectiveDungeons[questID]
        if packed then
            parsed = {}
            for index, ids in packed:gmatch("(%d+)=([%d,]+)") do
                local list = {}
                for id in ids:gmatch("%d+") do list[#list + 1] = tonumber(id) end
                parsed[tonumber(index)] = list
            end
        end
        row._dungeons = parsed
    end
    return parsed
end

-- World-space locations for one objective of a quest, parsed once and
-- cached on the row:
--   geo.name      what the objective is ("Kobold Vermin")
--   geo.n         number of placeable locations
--   geo[...]      n * GEO_STRIDE numbers (see GEO_STRIDE)
--   geo.dungeons  { instanceId, ... } when it is found inside dungeons;
--                 each id is one GetInstanceEntrance knows
function Catalog:GetObjectiveGeo(questID, objIndex)
    local row = self.Quests[questID]
    local list = row and row.Objectives and row.Objectives[objIndex]
    -- A quest QuestDBManual.lua says is done inside a dungeon gets a
    -- location-less geo naming that dungeon, so routing and the pins
    -- send the player to its entrance instead of back to the giver.
    local inside = row and QuestDungeons[questID]
    if type(list) ~= "table" then
        if not inside then return nil end
        list = EMPTY
    end

    local cache = row._geo
    if not cache then
        cache = {}
        row._geo = cache
    end
    local geo = cache[objIndex]
    if geo then return geo end

    geo = { n = 0 }
    local n = 0
    for i = 1, #list do
        local name, zone, typ, x, y, w, h = strsplit("|", list[i])
        zone = tonumber(zone) or 0
        x, y = tonumber(x), tonumber(y)
        if not geo.name and name and name ~= "" then geo.name = name end
        if x and y and zone ~= 0 then
            if usableWorldPoint(zone, x, y) then
                local isPoint = (tonumber(typ) or 35) <= 33
                local wx1, wy1 = Map:GetWorldPos(zone, x, y)
                local wx2, wy2 = wx1, wy1
                if not isPoint then
                    w = (tonumber(w) or 0) / 1002 * 100
                    h = (tonumber(h) or 0) / 668 * 100
                    wx2, wy2 = Map:GetWorldPos(zone, x + w, y + h)
                end
                local b = n * GEO_STRIDE
                geo[b + 1] = zone
                geo[b + 2] = isPoint and 1 or 0
                geo[b + 3] = wx1
                geo[b + 4] = wy1
                geo[b + 5] = wx2
                geo[b + 6] = wy2
                n = n + 1
            elseif Instances[zone] then
                geo.dungeons = addUnique(geo.dungeons, zone)
            end
        end
    end
    -- The dungeons meant by this objective's zeroed rows on outdoor zones.
    local extra = objectiveDungeons(questID, row)
    extra = extra and extra[objIndex]
    if extra then
        for i = 1, #extra do
            if Instances[extra[i]] then geo.dungeons = addUnique(geo.dungeons, extra[i]) end
        end
    end
    if inside then
        for id in tostring(inside):gmatch("%d+") do
            id = tonumber(id)
            if Instances[id] then geo.dungeons = addUnique(geo.dungeons, id) end
        end
    end
    geo.n = n
    cache[objIndex] = geo
    return geo
end

-- Number of objective slots the database has for a quest.
function Catalog:GetNumObjectives(questID)
    local row = self.Quests[questID]
    local objs = row and row.Objectives
    if not objs then return 0 end
    local n = 0
    while objs[n + 1] do n = n + 1 end
    return n
end

-- The point of an objective nearest the player: x, y, mapId, inside.
-- A rectangle contributes its nearest edge point, or the player's own
-- position with inside=true when the player is standing in it.
-- Locations on the player's continent always win over ones elsewhere;
-- a distance across continents means nothing.
function Catalog:ClosestPoint(geo, px, py, cont)
    local bestD, bestX, bestY, bestZone = huge, nil, nil, nil
    local farX, farY, farZone
    for i = 0, geo.n - 1 do
        local b = i * GEO_STRIDE
        local zone = geo[b + 1]
        if cont and self:GetContinent(zone) ~= cont then
            if not farX then
                farX = (geo[b + 3] + geo[b + 5]) * .5
                farY = (geo[b + 4] + geo[b + 6]) * .5
                farZone = zone
            end
        else
            local x, y = geo[b + 3], geo[b + 4]
            if geo[b + 2] == 0 then
                local wx2, wy2 = geo[b + 5], geo[b + 6]
                local insideX = px >= x and px <= wx2
                local insideY = py >= y and py <= wy2
                if insideX and insideY then
                    return px, py, zone, true
                end
                if insideX then x = px elseif px > wx2 then x = wx2 end
                if insideY then y = py elseif py > wy2 then y = wy2 end
            end
            local d = (x - px) ^ 2 + (y - py) ^ 2
            if d < bestD then
                bestD, bestX, bestY, bestZone = d, x, y, zone
            end
        end
    end
    if bestX then return bestX, bestY, bestZone, false end
    return farX, farY, farZone, false
end

-- Locations within this many world units of each other (about 180
-- yards) are drawn as one map pin.
local CLUSTER_LINK = 40
local CLUSTER_LINK_SQ = CLUSTER_LINK * CLUSTER_LINK
local MAX_CLUSTERS = 6

-- An objective's locations grouped into pin-sized clusters:
-- { {x=, y=, zone=, count=}, ... }, largest first, at most
-- MAX_CLUSTERS. A "kill 10 kobolds" objective is typically dozens of
-- small spawn rectangles; one pin per camp reads far better than one
-- per rectangle, or one in the empty middle of them all. Each pin sits
-- on the member location nearest its cluster's centre, so it is always
-- on a real spawn. Cached on the geo table.
function Catalog:GetObjectiveClusters(questID, objIndex)
    local geo = self:GetObjectiveGeo(questID, objIndex)
    if not geo then return nil end
    if geo.clusters then return geo.clusters end

    local n = geo.n
    local cx, cy, parent = {}, {}, {}
    for i = 1, n do
        local b = (i - 1) * GEO_STRIDE
        cx[i] = (geo[b + 3] + geo[b + 5]) * .5
        cy[i] = (geo[b + 4] + geo[b + 6]) * .5
        parent[i] = i
    end

    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end

    -- Bucket by a grid of CLUSTER_LINK cells: anything within link
    -- range of a point is in its cell or one of the eight around it.
    local cells = {}
    for i = 1, n do
        local gx, gy = floor(cx[i] / CLUSTER_LINK), floor(cy[i] / CLUSTER_LINK)
        for ox = -1, 1 do
            for oy = -1, 1 do
                local cell = cells[(gx + ox) * 100000 + (gy + oy)]
                if cell then
                    for k = 1, #cell do
                        local j = cell[k]
                        if (cx[i] - cx[j]) ^ 2 + (cy[i] - cy[j]) ^ 2 <= CLUSTER_LINK_SQ then
                            local ri, rj = find(i), find(j)
                            if ri ~= rj then parent[ri] = rj end
                        end
                    end
                end
            end
        end
        local key = gx * 100000 + gy
        local own = cells[key]
        if not own then
            own = {}
            cells[key] = own
        end
        own[#own + 1] = i
    end

    local groups, order = {}, {}
    for i = 1, n do
        local r = find(i)
        local g = groups[r]
        if not g then
            g = { sx = 0, sy = 0, count = 0, members = {} }
            groups[r] = g
            order[#order + 1] = g
        end
        g.sx, g.sy, g.count = g.sx + cx[i], g.sy + cy[i], g.count + 1
        g.members[g.count] = i
    end

    local clusters = {}
    for _, g in ipairs(order) do
        local mx, my = g.sx / g.count, g.sy / g.count
        local best, bestD = g.members[1], huge
        for _, i in ipairs(g.members) do
            local d = (cx[i] - mx) ^ 2 + (cy[i] - my) ^ 2
            if d < bestD then best, bestD = i, d end
        end
        clusters[#clusters + 1] = {
            x = cx[best], y = cy[best],
            zone = geo[(best - 1) * GEO_STRIDE + 1],
            count = g.count,
        }
    end
    table.sort(clusters, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    for i = #clusters, MAX_CLUSTERS + 1, -1 do clusters[i] = nil end

    geo.clusters = clusters
    return clusters
end

---------------------------------------------------------------------------------------
-- Quest givers
---------------------------------------------------------------------------------------

-- GiversByMap[mapId] = { questID, startString, questID, startString, ... }
-- for every giver position (a row's own Start plus its alternates).
function Catalog:BuildGiverIndex()
    local byMap = {}
    local function add(questID, se)
        local _, zone = strsplit("|", se)
        zone = tonumber(zone)
        if zone and zone ~= 0 then
            local list = byMap[zone]
            if not list then
                list = {}
                byMap[zone] = list
            end
            list[#list + 1] = questID
            list[#list + 1] = se
        end
    end
    for questID, row in pairs(self.Quests) do
        local start = row.Start
        if start then add(questID, start) end
        local alts = StartAlts[questID]
        if alts then
            for entry in alts:gmatch("[^;]+") do
                if entry ~= start then add(questID, entry) end
            end
        end
    end
    self.GiversByMap = byMap

    -- Quests picked up inside a dungeon, by instance, and which instances
    -- each outdoor zone leads to - so QuestPins.lua can list them at the
    -- entrance. Sorted so the pins come out the same every time.
    local byDungeon = {}
    for questID in pairs(self.Quests) do
        local inside = self:GetEndpointDungeons(questID, false)
        if inside then
            for i = 1, #inside do
                local list = byDungeon[inside[i]]
                if not list then
                    list = {}
                    byDungeon[inside[i]] = list
                end
                list[#list + 1] = questID
            end
        end
    end
    for _, list in pairs(byDungeon) do table.sort(list) end
    self.GiversByDungeon = byDungeon

    local byOwner = {}
    for id, packed in pairs(Instances) do
        local _, owner = strsplit("|", packed)
        owner = tonumber(owner)
        if owner then
            byOwner[owner] = byOwner[owner] or {}
            byOwner[owner][#byOwner[owner] + 1] = id
        end
    end
    for _, list in pairs(byOwner) do table.sort(list) end
    self.DungeonsByOwner = byOwner
end

-- Static eligibility: can this character ever be offered this quest at
-- its current level? (Faction, class, level, event category. Whether
-- it is already done or in the log is live state - QuestPins.lua.)
-- Returns ok, trivial.
function Catalog:IsEligible(questID, opts)
    local h = self:GetHeader(questID)
    if not h then return false end

    local faction = opts.faction
    if (h.side == 1 and faction == "Horde") or (h.side == 2 and faction == "Alliance") then
        return false
    end

    local mask = RequiredClasses[questID]
    if mask then
        local bit = CLASS_BIT[opts.class or ""]
        -- No bit library call needed: a single-bit test by arithmetic.
        if not bit or floor(mask / bit) % 2 == 0 then return false end
    end

    -- QuestieDB's level requirement where it differs from the row's.
    local minLevel = (Q.Rules and Q.Rules:GetMinLevel(questID)) or h.minLevel
    if minLevel > opts.level then return false end
    if HOLIDAY_CATEGORY[h.category] and not opts.showEvents then return false end

    local _, _, _, trivial = Q.Core:Difficulty(h.level, questID)
    if trivial and not opts.showLowLevel then return false, true end
    return true, trivial
end

-- 2026-11-18 (user: the Magram / Gelkis quests - "highlight those items
-- as player provided not a drop" and "not route back to the quest giver
-- until we have them"). What to say about one of a quest's objectives,
-- matched by name in the objective's text ("Advanced Target Dummy: 0/1"):
--   note     short text for the tracker / list ("craft or AH", "vendor",
--            or a hand-written hint from QuestDBManual's ObjectiveNotes)
--   hold     true: while it's unfinished, routing doesn't fall back to
--            the quest giver - there's nothing there to go back for
-- nil when nothing is known about it.
local notesCache = {}
local function objectiveNotes(questID)
    local list = notesCache[questID]
    if list then return list end
    list = {}
    local packed = ProvidedItems[questID]
    if packed then
        for entry in packed:gmatch("[^,]+") do
            local id, vendor, name = entry:match("^(%d+):(%d):(.+)$")
            if name then
                list[#list + 1] = {
                    match = name:lower(), itemID = tonumber(id), hold = true,
                    note = vendor == "1" and "vendor" or "craft or AH",
                    tip = vendor == "1" and "Bought from a vendor - not a drop"
                        or "Player provided - crafted or bought (Auction House), not a drop",
                }
            end
        end
    end
    for _, n in ipairs(ManualObjectiveNotes[questID] or EMPTY) do list[#list + 1] = n end
    notesCache[questID] = list
    return list
end

-- The objective's text has to START with the name (after any "0/1 "
-- count, which newer clients put first): "Craftsman's Writ: Azure Silk
-- Hood" is not the Azure Silk Hood.
function Catalog:ObjectiveNote(questID, text)
    if not questID or type(text) ~= "string" or text == "" then return nil end
    local lower = text:lower():gsub("^%d+%s*/%s*%d+%s+", "")
    for _, n in ipairs(objectiveNotes(questID)) do
        if lower:sub(1, #n.match) == n.match then return n end
    end
    return nil
end

-- " (craft or AH)" for an objective line, or "".
function Catalog:ObjectiveTag(questID, text)
    local n = self:ObjectiveNote(questID, text)
    return n and (" |cff66ccff(%s)|r"):format(n.note) or ""
end

-- 2026-11-18: the class a quest is meant for, when that isn't the
-- player's - a class quest someone shared with you (Ground to Keep, a
-- rogue quest). "Rogue", "Warrior or Paladin", ...; nil when the quest
-- is for every class or includes yours.
local CLASS_LABEL = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage",
    WARLOCK = "Warlock", MONK = "Monk", DRUID = "Druid",
}
function Catalog:OtherClassQuest(questID)
    local mask = RequiredClasses[questID]
    if not mask then return nil end
    local _, class = UnitClass("player")
    local mine = CLASS_BIT[class or ""]
    if mine and floor(mask / mine) % 2 == 1 then return nil end
    local names = {}
    for token, bit in pairs(CLASS_BIT) do
        if floor(mask / bit) % 2 == 1 then names[#names + 1] = CLASS_LABEL[token] or token end
    end
    if #names == 0 then return nil end
    table.sort(names)
    return table.concat(names, " or ")
end

-- The quest that must be turned in before this one is offered, if any,
-- as Carbonite's QuestPrev has it. Quest/QuestRules.lua is what decides
-- availability; it falls back to this for quests it has no rule for.
function Catalog:GetPrerequisite(questID)
    return Prev[questID]
end

-- 2026-11-18 (user request, from Carbonite: "Part 2 of 4" for chains).
-- part, total for a quest in a chain of two or more, else nil. Back
-- through the prerequisites (Prev), forward through the header's next
-- quest. Cached; a loop in the data can't run away (50 steps at most).
local chainCache = {}
function Catalog:GetChainPart(questID)
    local hit = chainCache[questID]
    if hit ~= nil then
        if hit == false then return nil end
        return hit[1], hit[2]
    end
    local before, id, seen = 0, questID, { [questID] = true }
    while Prev[id] and not seen[Prev[id]] and before < 50 do
        id = Prev[id]
        seen[id] = true
        before = before + 1
    end
    local after = 0
    id = questID
    while after < 50 do
        local h = self:GetHeader(id)
        local nextId = h and h.nextId
        if not nextId or nextId == 0 or seen[nextId] or not self.Quests[nextId] then break end
        id = nextId
        seen[id] = true
        after = after + 1
    end
    local total = before + 1 + after
    if total < 2 then
        chainCache[questID] = false
        return nil
    end
    chainCache[questID] = { before + 1, total }
    return before + 1, total
end
