-- Azeroth Atlas | UI / Fonts
-- Minimal port of Carbonite's Nx.Font:Init (Modules/UI/UIEngine.lua:
-- 1055). The real version is a live-customizable font picker across
-- 5 named slots, backed by SavedVariables and LibSharedMedia
-- (Font:Update/FontScan/ModuleAdd) - not a feature this project asked
-- for. The ported Nx.Window/Nx.Button chrome only ever references two
-- fixed font objects by name ("NxFontS" for title/button text,
-- "NxFontM" for the medium size no window here actually uses yet),
-- so just create those two, copying Blizzard's own stock fonts - no
-- SavedVariables or font-file management needed.

local f = CreateFont("NxFontS")
f:SetFontObject("GameFontNormalSmall")

local m = CreateFont("NxFontM")
m:SetFontObject("GameFontNormal")
