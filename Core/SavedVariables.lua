-- Azeroth Atlas | Core / SavedVariables
-- Wraps AceDB-3.0. This module creates the AceDB instance and merges
-- each Core.Module's `dbDefaults` into it afterward.
--
-- Adapted from AlchemyNavigation/Core/SavedVariables.lua (rename only).

local AzerothAtlas = _G.AzerothAtlas
local Logger = AzerothAtlas.Core.Logger:Get("SavedVariables")

local SavedVariables = {}
AzerothAtlas.Core.SavedVariables = SavedVariables

local moduleDB = {}

function SavedVariables:GetModuleDB(name)
    return moduleDB[name]
end

-- Deep-copy a default value so user mutations don't mutate our
-- shared defaults table.
local function copyValue(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = copyValue(vv) end
    return out
end

local function ensureDB()
    if AzerothAtlas.db then return true end
    local AceDB = LibStub("AceDB-3.0", true)
    if not AceDB then
        Logger:debug("AceDB-3.0 not available yet, deferring")
        return false
    end
    AzerothAtlas.db = AceDB:New("AzerothAtlasDB", { profile = {}, char = {}, global = {} }, true)
    return true
end

local function bind()
    if not ensureDB() then return false end
    local db = AzerothAtlas.db

    -- Poke each module's defaults directly into the live db scope
    -- tables. Only writes when the destination key is nil so we
    -- never overwrite the user's saved values.
    for _, mod in ipairs(AzerothAtlas.Core.Module.registry or {}) do
        if mod.dbDefaults then
            for scope, subTable in pairs(mod.dbDefaults) do
                local destScope = db[scope]
                if destScope then
                    for k, v in pairs(subTable) do
                        if destScope[k] == nil then
                            destScope[k] = copyValue(v)
                        end
                    end
                end
            end
        end
    end

    -- Build per-module DB views over the now-populated db.
    for _, mod in ipairs(AzerothAtlas.Core.Module.registry or {}) do
        local name = mod:GetName()
        db.profile[name] = db.profile[name] or {}
        db.char[name]    = db.char[name]    or {}
        db.global[name]  = db.global[name]  or {}
        moduleDB[name] = {
            profile = db.profile[name],
            char    = db.char[name],
            global  = db.global[name],
        }
    end

    Logger:debug("AceDB bound; %d modules registered", #(AzerothAtlas.Core.Module.registry or {}))
    return true
end

-- Retry-poll briefly if the DB isn't ready the first time.
AzerothAtlas.Core.EventBus:Subscribe("AZEROTHATLAS_INITIALIZE", function()
    if bind() then return end
    local tries = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        tries = tries + 1
        if bind() or tries > 200 then self:SetScript("OnUpdate", nil) end
    end)
end)
