---------------------------------------------------------------------------------------
-- Carbonite - classic minimap tileset bindings and coordinate anchors
-- Copyright 2007-2012 Carbon Based Creations, LLC
-- Distributed under the GNU General Public License, version 3 or later.
---------------------------------------------------------------------------------------

-- Alchemy GPS port note (build-order step 8b, 2026-11-10): copied
-- verbatim, including its MapWorldInfo[13]/[14] anchor indices - left
-- unchanged even though [13]/[14] don't match this same file's own
-- Kalimdor/Eastern-Kingdoms *root* entries at a glance (our/real
-- Carbonite's MapWorldInfo[12] is Kalimdor's root per the "-- [1414]
-- Kalimdor" comment at NxMapData.lua, cross-confirmed by
-- NormalizeZoneMapID's 1414->12/1415->13 mapping; [13]/[14] land on
-- Eastern Kingdoms' root and "Arathi Highlands" instead). This exact
-- mismatch is present in Carbonite's own shipped source too (checked
-- both the per-flavor data.xml-loaded copy and this standalone one -
-- identical indices in both), so it reads as intentional/historical
-- rather than a transcription error introduced here - possibly a
-- different, older internal zone-ID convention this specific table
-- was written against. Not "corrected" blindly: verify live whether
-- Kalimdor/EK detail tiles land in the right real-world position
-- before trusting or further debugging this formula.
local AlchemyGPS = _G.AlchemyGPS
local Map = AlchemyGPS.Map

Map.MiniMapBlks = {
    [1] = {
        Map.CamelotKalMapBlks,
        1908,
        19, 8,
        Map.MapWorldInfo[13].X + Map.MapInfo[1].X + 1600 + 212.52, Map.MapWorldInfo[13].Y + Map.MapInfo[1].Y + -800 + -266.42,
        "World\\Minimaps\\Kalimdor"
    },
    [2] = {
        Map.CamelotEkMapBlks,
        2420,
        24, 20,
        Map.MapWorldInfo[14].X + Map.MapInfo[2].X -1080, Map.MapWorldInfo[14].Y + Map.MapInfo[2].Y - 1308,
        "World\\Minimaps\\Azeroth"
    }
}

--------
