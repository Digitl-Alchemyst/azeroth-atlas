-- Azeroth Atlas | Core / Module
-- Base class for every Azeroth Atlas module. Wraps AceAddon-3.0's
-- NewModule with a consistent lifecycle, and per-module logger.
--
-- Usage:
--   local MapModule = AzerothAtlas.Core.Module:New("Map", {
--     defaults = { ... AceDB defaults ... },
--   })
--   function MapModule:OnEnable() ... end
--
-- Every Module is also an AceAddon module, so AceEvent / AceTimer /
-- AceHook mixins are available via `self:RegisterEvent`.
--
-- Adapted from AlchemyNavigation/Core/Module.lua (rename only).

local AzerothAtlas = _G.AzerothAtlas
local Logger = AzerothAtlas.Core.Logger

local Module = {}
AzerothAtlas.Core.Module = Module

-- Registry of every module created via `Module:New`, in declaration
-- order. Other Core files (SavedVariables) read this list.
Module.registry = {}

local DEFAULT_MIXINS = {
    "AceEvent-3.0",
    "AceTimer-3.0",
    "AceHook-3.0",
}

-- Creates and returns a new AceAddon module with extra Azeroth Atlas
-- behavior attached. `spec` is a plain table of options:
--   defaults  table  AceDB defaults forwarded by the SavedVariables module.
--   mixins    table  Extra Ace mixin library names appended to DEFAULT_MIXINS.
function Module:New(name, spec)
    spec = spec or {}

    local mixins = { unpack(DEFAULT_MIXINS) }
    if spec.mixins then
        for _, m in ipairs(spec.mixins) do mixins[#mixins + 1] = m end
    end

    local mod = AzerothAtlas:NewModule(name, unpack(mixins))
    mod.spec = spec
    mod.log = Logger:Get(name)

    -- AceDB defaults: copy out so the SavedVariables module can collect
    -- them and merge into the global defaults table before AceDB:New.
    if spec.defaults then
        mod.dbDefaults = spec.defaults
    end

    -- Lifecycle wrappers fire EventBus events so other modules can
    -- react to a module enabling without holding references.
    local origEnable  = mod.OnEnable
    local origDisable = mod.OnDisable
    function mod:OnEnable()
        if origEnable then origEnable(self) end
        AzerothAtlas.Core.EventBus:Fire("MODULE_ENABLED", self:GetName())
    end
    function mod:OnDisable()
        if origDisable then origDisable(self) end
        AzerothAtlas.Core.EventBus:Fire("MODULE_DISABLED", self:GetName())
    end

    -- Pull a saved-variable subtable scoped to this module so each
    -- module does not have to know the global DB layout. Lazy: if the
    -- SavedVariables binder has not yet run (e.g. we are inside an
    -- early OnEnable), fall back to a transient empty table backed by
    -- the dbDefaults so callers do not have to nil-check.
    function mod:DB()
        local sv = AzerothAtlas.Core.SavedVariables
        local view = sv and sv:GetModuleDB(self:GetName())
        if view then return view end

        local fallback = self._fallbackDB
        if not fallback then
            fallback = { profile = {}, char = {}, global = {} }
            local name = self:GetName()
            if self.dbDefaults then
                for scope, t in pairs(self.dbDefaults) do
                    local sub = t[name]
                    if type(sub) == "table" then
                        fallback[scope] = fallback[scope] or {}
                        for k, v in pairs(sub) do fallback[scope][k] = v end
                    end
                end
            end
            self._fallbackDB = fallback
        end
        return fallback
    end

    Module.registry[#Module.registry + 1] = mod
    return mod
end

-- Convenience accessor used by code that doesn't want to import the
-- AceAddon API directly.
function Module:Get(name)
    return AzerothAtlas:GetModule(name, true)
end
