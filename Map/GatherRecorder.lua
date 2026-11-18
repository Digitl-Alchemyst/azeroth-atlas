-- Alchemy GPS | Map/GatherRecorder.lua
---------------------------------------------------------------------------------------
-- Recording the nodes you gather (2026-11-18, user request, from
-- Carbonite: "Saves every herb, ore or other node you pick, building
-- your own database alongside the shipped one. You can delete each
-- type separately").
--
-- How a gather is seen (the way GatherMate2 does it): casting Herb
-- Gathering, Mining or Opening fires UNIT_SPELLCAST_SENT with the
-- node's name as the target ("Peacebloom", "Copper Vein", "Battered
-- Chest"); when that same cast succeeds, the node is stored where you
-- stand. Fishing pools aren't recorded - a fishing cast names no target.
-- Opening is also cast on doors and quest objects, so a treasure is
-- only kept when its name is one GatherNodeInfo knows.
--
-- Stored account-wide (every character adds to the same map), in the
-- shipped data's own shape and coordinate encoding:
--   db.global.GatheredNodes[kind][mapId][coord] = nodeID
-- kind "Herb" / "Mine" / "Treasure", nodeID from GatherNodeInfo by name
-- (or the name itself when the shipped list doesn't know it). A node
-- within 10 yards of one you already recorded of the same kind
-- replaces it rather than adding another. MinimapEngine's
-- CollectGatherZoneNodes draws these alongside the shipped ones, with
-- "You gathered here" in the tooltip.
-- Settings > Map, "Gathered nodes": record on / off (profile.
-- RecordGathering) and a clear button per kind.
--
-- Importing from GatherMate2_Data (2026-11-18, user request, from
-- Carbonite): GatherMate2_Data is a load-on-demand addon that only
-- loads alongside GatherMate2 - the addon we stopped depending on
-- because of its taint popup. So the import is one-off: with both
-- enabled, Settings > Map > "Import from GatherMate2_Data" loads it and
-- copies its herb / mining / fishing / treasure tables into
-- db.global.GatherImport (same shape as the shipped Map/Data/Gather*
-- files, which came from it). From then on those replace the shipped
-- tables - GatherMate2 can be disabled again, and a newer
-- GatherMate2_Data is picked up by importing again. "Remove" goes back
-- to the shipped data.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local Recorder = {}
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}
AlchemyGPS.Modules.Map.GatherRecorder = Recorder

local SAME_NODE_YARDS = 10
-- The gathering spells' base IDs; their names (any rank) are compared.
local SPELL_KIND = { [2366] = "Herb", [2575] = "Mine", [3365] = "Treasure" }
Recorder.KINDS = { "Herb", "Mine", "Treasure" }
Recorder.KIND_LABEL = { Herb = "herbs", Mine = "mining nodes", Treasure = "treasure" }

local kindBySpellName

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function kindFor(spellID)
    if not kindBySpellName then
        kindBySpellName = {}
        for id, kind in pairs(SPELL_KIND) do
            local n = spellName(id)
            if n then kindBySpellName[n] = kind end
        end
    end
    local n = spellID and spellName(spellID)
    return n and kindBySpellName[n]
end

function Recorder:Store()
    local db = AlchemyGPS.db
    if not db then return nil end
    db.global.GatheredNodes = db.global.GatheredNodes or {}
    return db.global.GatheredNodes
end

-- The recorded nodes of one kind on one map (nil when none).
function Recorder:Nodes(kind, mapId)
    local db = AlchemyGPS.db
    local all = db and db.global.GatheredNodes
    return all and all[kind] and all[kind][mapId]
end

function Recorder:Count(kind)
    local db = AlchemyGPS.db
    local t = db and db.global.GatheredNodes and db.global.GatheredNodes[kind]
    local n = 0
    for _, nodes in pairs(t or {}) do
        for _ in pairs(nodes) do n = n + 1 end
    end
    return n
end

function Recorder:Clear(kind)
    local all = self:Store()
    if all then all[kind] = nil end
    self:Changed()
end

function Recorder:Changed()
    local E = AlchemyGPS.Modules.Map.MinimapEngine
    if E and E.RefreshGatherIcons then E:RefreshGatherIcons() end
end

local function encode(x, y)
    return math.floor(x * 10000 + .5) * 1000000 + math.floor(y * 10000 + .5) * 100
end

local function decode(coord)
    return math.floor(coord / 1000000) / 10000, math.floor(coord % 1000000 / 100) / 10000
end

local nameToID

local function nodeIDFor(kind, name)
    if not nameToID then
        nameToID = {}
        for k, list in pairs(_G.AlchemyGPSGatherNodeInfo or {}) do
            nameToID[k] = {}
            for id, info in pairs(list) do
                if info.name then nameToID[k][info.name:lower()] = id end
            end
        end
    end
    return (nameToID[kind] and nameToID[kind][name:lower()]) or name
end

function Recorder:Record(kind, name)
    local db = AlchemyGPS.db
    if not db or db.profile.RecordGathering == false then return end
    local E = AlchemyGPS.Modules.Map.MinimapEngine
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map or not E then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    map = E:CanonicalizeMapID(map) or map
    local id = nodeIDFor(kind, name)
    -- "Opening" is also cast on doors, quest objects and lockboxes: a
    -- treasure is only kept when it's one the shipped list knows.
    if kind == "Treasure" and type(id) ~= "number" then return end

    local all = self:Store()
    all[kind] = all[kind] or {}
    local nodes = all[kind][map] or {}
    all[kind][map] = nodes

    -- The same node gathered again (it respawns in about the same spot):
    -- move it rather than add a second.
    local wx, wy = E:GetWorldPos(map, x * 100, y * 100)
    if wx then
        local range = (SAME_NODE_YARDS / 4.575) ^ 2
        for coord in pairs(nodes) do
            local ox, oy = decode(coord)
            local ax, ay = E:GetWorldPos(map, ox * 100, oy * 100)
            if ax and (ax - wx) ^ 2 + (ay - wy) ^ 2 <= range then
                nodes[coord] = nil
            end
        end
    end
    nodes[encode(x, y)] = id
    if E.MapId == map then self:Changed() end
end

---------------------------------------------------------------------------------------
-- Import from GatherMate2_Data
---------------------------------------------------------------------------------------

local IMPORT_TABLES = {
    Herb = "GatherMateData2HerbDB",
    Mine = "GatherMateData2MineDB",
    Fish = "GatherMateData2FishDB",
    Treasure = "GatherMateData2TreasureDB",
}

-- The imported table for one kind (nil = use the shipped data).
function Recorder:Imported(kind)
    local db = AlchemyGPS.db
    local imp = db and db.global.GatherImport
    return imp and imp.nodes and imp.nodes[kind]
end

function Recorder:ImportInfo()
    local db = AlchemyGPS.db
    return db and db.global.GatherImport
end

local function addonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function loadAddon(name)
    if C_AddOns and C_AddOns.LoadAddOn then return C_AddOns.LoadAddOn(name) end
    return LoadAddOn(name)
end

-- Returns true, or false and a message to show.
function Recorder:Import()
    if not addonLoaded("GatherMate2") then
        return false, "GatherMate2 isn't running. Enable GatherMate2 and GatherMate2_Data in the AddOns list, "
            .. "reload, and import again - afterwards you can disable them."
    end
    if not addonLoaded("GatherMate2_Data") then
        local ok, reason = loadAddon("GatherMate2_Data")
        if not ok then
            return false, "GatherMate2_Data couldn't be loaded (" .. tostring(reason or "not installed")
                .. "). Make sure it's installed and enabled in the AddOns list."
        end
    end

    local nodes, counts, total = {}, {}, 0
    for kind, global in pairs(IMPORT_TABLES) do
        local src = _G[global]
        local n = 0
        if type(src) == "table" then
            local copy = {}
            for mapId, list in pairs(src) do
                local t = {}
                for coord, nodeID in pairs(list) do
                    t[coord] = nodeID
                    n = n + 1
                end
                copy[mapId] = t
            end
            -- A kind it has nothing for (its fishing list is empty) keeps
            -- the shipped data.
            if n > 0 then nodes[kind] = copy end
        end
        counts[kind] = n
        total = total + n
    end
    if total == 0 then
        return false, "GatherMate2_Data loaded but had no nodes in it."
    end

    local version
    local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local data = AceAddon and AceAddon:GetAddon("GatherMate2_Data", true)
    version = data and data.generatedVersion
    AlchemyGPS.db.global.GatherImport = {
        nodes = nodes, counts = counts, version = version, when = time(),
    }
    self:Changed()
    return true, ("Imported %d herbs, %d mining nodes, %d fishing pools and %d treasures from GatherMate2_Data. "
        .. "You can disable GatherMate2 now."):format(counts.Herb or 0, counts.Mine or 0, counts.Fish or 0, counts.Treasure or 0)
end

function Recorder:RemoveImport()
    local db = AlchemyGPS.db
    if db then db.global.GatherImport = nil end
    self:Changed()
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local pending = {}   -- [castGUID] = { kind, name }

local events = CreateFrame("Frame")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, target, castGUID, spellID)
        local kind = kindFor(a4)
        if kind and type(a2) == "string" and a2 ~= "" and a3 then
            pending[a3] = { kind = kind, name = a2 }
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, castGUID, spellID)
        local p = a2 and pending[a2]
        if p then
            pending[a2] = nil
            local ok, err = pcall(Recorder.Record, Recorder, p.kind, p.name)
            if not ok then AlchemyGPS.Core.Logger:Get("Map"):error("recording a node failed: %s", tostring(err)) end
        end
    elseif a2 then
        pending[a2] = nil
    end
end)
