-- Azeroth Atlas | Core / Bootstrap
-- Owns the very first lines of code that run for the addon. Creates
-- the AceAddon-3.0 instance and exposes a single namespace on which
-- every subsequent file hangs its public API.
--
-- Adapted from AlchemyNavigation/Core/Bootstrap.lua (rename only),
-- itself adapted from Carbonite/Core/Bootstrap.lua.

local ADDON_NAME = "AzerothAtlas"

local AceAddon = LibStub("AceAddon-3.0")

local AzerothAtlas = AceAddon:NewAddon(ADDON_NAME,
    "AceConsole-3.0",
    "AceTimer-3.0",
    "AceEvent-3.0",
    "AceComm-3.0",
    "AceHook-3.0",
    "AceBucket-3.0",
    "AceSerializer-3.0")

_G.AzerothAtlas = AzerothAtlas

AzerothAtlas.Core    = AzerothAtlas.Core    or {}
AzerothAtlas.Util    = AzerothAtlas.Util    or {}
AzerothAtlas.UI      = AzerothAtlas.UI      or {}
AzerothAtlas.Compat  = AzerothAtlas.Compat  or {}
AzerothAtlas.Modules = AzerothAtlas.Modules or {}

function AzerothAtlas:L()
    return LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
end

AzerothAtlas.VERSION_STRING = "0.1.0-dev"

-- Lifecycle hookup via a private event frame, mirroring Carbonite's
-- pattern so Core/SavedVariables.lua has a well-defined moment to
-- bind AceDB. Fires on the EventBus so any module can react without
-- holding a direct reference to Bootstrap.
local lifecycle = CreateFrame("Frame", "AzerothAtlasLifecycle")
lifecycle:RegisterEvent("ADDON_LOADED")
lifecycle:RegisterEvent("PLAYER_LOGIN")
lifecycle:RegisterEvent("PLAYER_ENTERING_WORLD")
lifecycle:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        if AzerothAtlas.Core.EventBus then
            AzerothAtlas.Core.EventBus:Fire("AZEROTHATLAS_LOADED", AzerothAtlas)
        end
    elseif event == "PLAYER_LOGIN" then
        if AzerothAtlas.Core.EventBus then
            AzerothAtlas.Core.EventBus:Fire("AZEROTHATLAS_INITIALIZE", AzerothAtlas)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if AzerothAtlas.Core.EventBus then
            AzerothAtlas.Core.EventBus:Fire("AZEROTHATLAS_ENABLE", AzerothAtlas)
        end
    end
end)
AzerothAtlas._lifecycleFrame = lifecycle
