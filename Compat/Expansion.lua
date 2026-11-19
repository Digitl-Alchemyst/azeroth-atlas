-- Azeroth Atlas | Compat / Expansion
-- Azeroth Atlas targets WoW Forever only, so this is a deliberately
-- small version of the multi-flavor detection pattern Carbonite uses
-- (see Carbonite/Compat/Expansion.lua for the original, which also
-- handles Classic Era/TBC/Wrath/Cata/MoP/Retail).
--
--   if AzerothAtlas.Compat.Expansion:HasFeature("MAP_C_MAP_API") then ... end

local AzerothAtlas = _G.AzerothAtlas

local Expansion = {}
AzerothAtlas.Compat.Expansion = Expansion

-- WoW Forever identifies itself by TOC version, not WOW_PROJECT_ID
-- (Carbonite's code calls this flavor "Camelot" internally).
local function isForeverToc()
    local _, _, _, toc = GetBuildInfo()
    toc = toc or 0
    return toc >= 16000 and toc < 19999
end

Expansion.isForever = isForeverToc()

local _, _, _, tocVersion = GetBuildInfo()
Expansion.tocVersion = tocVersion or 0

-- Feature flags: ask "does this client support X?" instead of
-- hardcoding assumptions, since Forever's own TOC version climbs as
-- its developers ship updates.
local F = {}
Expansion.features = F

F.MAP_C_MAP_API       = type(_G.C_Map) == "table" and type(_G.C_Map.GetMapInfo) == "function"
F.MAP_EXPLORATION_API = type(_G.C_MapExplorationInfo) == "table"

function Expansion:HasFeature(name)
    return F[name] == true
end

AzerothAtlas.isForever = Expansion.isForever
