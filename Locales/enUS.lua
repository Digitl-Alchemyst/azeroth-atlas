-- Azeroth Atlas | Locales / enUS
-- Only the keys the ported Nx.Window/Nx.Button chrome actually
-- references (grepped from the ported files, per the build plan's
-- "port only locale keys actually referenced" instruction). English
-- text copied verbatim from Carbonite/Locales/enUS/Main.lua.

local L = LibStub("AceLocale-3.0"):NewLocale("AzerothAtlas", "enUS", true, true)
if not L then return end

L["Close/Menu"] = true
L["Close/Unlock"] = true
L["Unlock"] = true
L["Maximize"] = true
L["Restore"] = true
L["Detach %s"] = true
L["Detach found %s"] = true
