-- Alchemy GPS | Map / MinimapEngine
-- Renders the undocked map window as a self-contained tile canvas
-- (Blizzard's own continent/zone art, C_Map.GetMapArtLayerTextures) -
-- this engine's own PlyrX/Y/Scale/pan state, our own drawn player
-- marker, and our own service/quest/gather icon layers. No dependency
-- on the real Blizzard Minimap widget anywhere in this file.
--
-- REMOVED same day (2026-11-10, "Mode: Live" removal): earlier
-- versions of this file also reparented the real Minimap widget
-- (TakeOwnership/ApplyTakeOwnership/ReleaseOwnership/ClipMMW/
-- PositionOwnedMinimap/MinimapSetScale/MinimapUpdateMask/
-- MinimapSyncLayer/MinimapIsHostVisible/MinimapSyncVisibility/
-- MinimapDetachFrms - ~500 lines, ported from Carbonite/Modules/Map/
-- MapEngine.lua) and blended it into the window as a small low-alpha
-- "Live" accent on top of the tile canvas ("Mode: Tiles" toggled this
-- off). Removed entirely, on explicit direction, after this turned
-- out to be the real root cause of a recurring "GatherMate2 has been
-- blocked from an action only available to the Blizzard UI" taint
-- popup: GatherMate2 (and presumably other addons) parent their own
-- minimap pins directly to the real Minimap widget, and
-- ApplyTakeOwnership's `mm:SetParent(UIParent)` - explicitly noted in
-- its own prior comment as "touches protected frame state" - rips that
-- widget out of MinimapCluster and into this addon's own window,
-- automatically, on login if the map window was left open, before any
-- hardware event that session. GatherMate2's own pin code then
-- inherited taint from that reparent the next time it touched its
-- pins. The real Blizzard minimap now stays fully under Blizzard's own
-- control always - shown or hidden per the user's own "Hide Blizzard
-- minimap" preference, persisted directly with no override tied to
-- this window's own open/close state (see MinimapWindow.lua).
--
-- TakeOwnership is kept as a name (one-time per-window setup: tile/
-- marker/icon frame pools, mouse wheel/drag wiring) even though it no
-- longer "owns" anything external - renaming it was considered and
-- rejected to keep this diff reviewable; a future cleanup pass can
-- rename it along with MinimapWindow.lua's own call site.

local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

-- Build-order step 8: Map\Data\NxMapData.lua (Carbonite's real
-- Camelot-flavor zone/continent database) assigns onto `AlchemyGPS.Map`
-- (its own `local Map = Nx.Map` alias) - whichever of the two files
-- loads first (see Map.xml), inherit/share that same table instead of
-- creating a fresh one, so NxMapData.lua's MapInfo/MapWorldInfo/
-- MapZones/ContCnt/ContBlks fields and this file's own methods end up
-- on one table, exactly mirroring how real Carbonite's `Nx.Map` is
-- simultaneously the map class AND the static data holder.
local MinimapEngine = AlchemyGPS.Map or {}
AlchemyGPS.Map = MinimapEngine
AlchemyGPS.Modules.Map.MinimapEngine = MinimapEngine

local MINIMAP_STRATA_RANK = {
    WORLD = 0,
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    DIALOG = 5,
    FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8,
}

local MINIMAP_STRATA_ABOVE = {
    WORLD = "BACKGROUND",
    BACKGROUND = "LOW",
    LOW = "MEDIUM",
    MEDIUM = "HIGH",
    HIGH = "DIALOG",
    DIALOG = "FULLSCREEN",
    FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "FULLSCREEN_DIALOG",
    TOOLTIP = "TOOLTIP",
}

---------------------------------------------------------------------------------------
-- One-time setup: take ownership of the live Blizzard Minimap widget.
-- Trimmed from Nx.Map:MinimapOwnInit - this addon always owns it once
-- the window is first opened (no "own minimap" checkbox), so only the
-- unconditional "take ownership" half of that function is ported.
---------------------------------------------------------------------------------------

function MinimapEngine:TakeOwnership(win, contentFrm)

    self.Win = win
    self.Frm = contentFrm

    -- Our content frame (from Window:Attach) already sits below the
    -- window's own title bar - unlike Carbonite's self.Frm, which is
    -- the whole window and needs this offset to skip past its title
    -- bar. Zero here avoids double-subtracting it in ClipMMW.
    self.TitleH = 0

    -- Carbonite's own tile-rendering (MoveZoneTiles) writes this same
    -- field through self.BackgndAlpha but never actually applies it
    -- (see this file's MoveZoneTiles for the real source's own
    -- disabled line) - seeded from the saved profile value here so a
    -- brightness chosen via the map's right-click menu
    -- (MapContextMenu.lua) survives /reload without needing the menu
    -- reopened first.
    self.BackgndAlpha = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.BackgndBrightness) or 1

    -- Same pattern as BackgndAlpha just above, for the gathering-node
    -- icons' own opacity and size sliders (MapContextMenu.lua, build-
    -- order steps 9g/9h) - seeded here so a value chosen via the
    -- right-click menu survives /reload without needing the menu
    -- reopened first.
    self.GatherOpacity = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.GatherIconOpacity) or 1
    self.GatherIconScale = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.GatherIconScale) or 1
    -- Literal fallback (not the DEFAULT_GATHER_BACKDROP_OPACITY named
    -- constant below) - same reason BackgndAlpha/GatherOpacity/
    -- GatherIconScale just above use literals too: this runs before
    -- that constant's own `local` declaration further down the file
    -- is in scope.
    self.GatherBackdropOpacity = (AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.GatherBackdropOpacity) or 0.7

    -- Build-order step 8: the zone-art tile frame pool. Created once
    -- (persists across close/reopen, same as the pan/zoom state below -
    -- recreating it would just leak the old 150 frames).
    if not self.TileFrms then
        self:InitTileFrames()
    end
    -- Build-order step 8b's detail-tile pool (see UpdateMiniFrames) -
    -- same "create once, grow on demand, persist across close/reopen"
    -- treatment as TileFrms above.
    self.MiniFrms = self.MiniFrms or {}

    -- Build-order step 9a (2026-11-10): the canvas-drawn player marker
    -- (see UpdatePlayerMarker below) - created once, same persistence
    -- treatment as TileFrms/MiniFrms above.
    if not self.PlyrFrm then
        self.PlyrFrm = self:CreateMiniFrame()
    end

    -- Build-order step 9b's static service-icon pool (see
    -- RefreshServiceIcons/UpdateServiceIcons) - same persistence
    -- treatment as the pools above.
    self.SvcFrms = self.SvcFrms or {}
    self.SvcPts = self.SvcPts or {}

    -- Build-order step 9c's quest turn-in marker pool (see
    -- RefreshQuestIcons/UpdateQuestIcons) - same persistence
    -- treatment as the pools above.
    self.QuestFrms = self.QuestFrms or {}
    self.QuestPts = self.QuestPts or {}

    -- Build-order step 9e's gathering-node pool (see
    -- RefreshGatherIcons/UpdateGatherIcons) - same persistence
    -- treatment as the pools above.
    self.GatherFrms = self.GatherFrms or {}
    self.GatherPts = self.GatherPts or {}

    -- PlyrX/Y are overwritten every tick once Update() resolves a real
    -- zone (build-order step 8's RefreshCurrentZone/live-position
    -- block) - this is just a safe fallback for the handful of ticks
    -- before that first resolves, and for the Cont==nil case (no
    -- known zone, e.g. an instance) where Update() otherwise leaves
    -- them untouched. Scale/MapPosX/Y (the zoom/pan TARGET, step 5's
    -- ZoomController.lua mutates these) and ScaleDraw/MapPosXDraw/Y/
    -- StepTime (the ANIMATED values Update() steps toward that target,
    -- per MapEngine.lua's own "Adjust draw scale and position" block)
    -- default-init with `or`, not an unconditional reset, so closing
    -- and reopening the window resumes at whatever zoom/pan the user
    -- left it on instead of snapping back to defaults - resetting
    -- ScaleDraw alone while Scale persisted would leave them
    -- permanently mismatched, since the animation block below only
    -- runs while StepTime ~= 0.
    self.PlyrX, self.PlyrY = self.PlyrX or 0, self.PlyrY or 0
    self.PlyrDir = self.PlyrDir or 0
    self.Scale = self.Scale or 1
    self.MapPosX, self.MapPosY = self.MapPosX or 0, self.MapPosY or 0
    self.StepTime = self.StepTime or 0
    self.ScaleDraw = self.ScaleDraw or 1
    self.MapPosXDraw, self.MapPosYDraw = self.MapPosXDraw or 0, self.MapPosYDraw or 0

    -- Drag-to-pan state (build-order step 6) is transient, unlike the
    -- zoom/pan target fields above - always reset on (re)open instead
    -- of persisting, so a window closed mid-drag (e.g. via the X while
    -- the left button happens to still be down) never reopens stuck
    -- mid-scroll.
    self.Scrolling = false
    self.ScrollingX, self.ScrollingY = nil, nil

    -- Carbonite wires this at Nx.Map:Create time (MapEngine.lua:976) -
    -- our equivalent "map frame created" moment is here, since
    -- contentFrm is freshly supplied once per window (TakeOwnership
    -- is a no-op re-wire on the fast-path reopen, which is harmless).
    contentFrm:EnableMouseWheel(true)
    contentFrm:SetScript("OnMouseWheel", function(_, value)
        self:MouseWheel(value)
    end)

    -- Build-order step 6: drag-to-pan. Ported from Nx.Map:OnMouseDown/
    -- OnMouseUp's left-button branch (MapEngine.lua:4997-5046/5129-
    -- 5139) - only the Scrolling state-machine half. Dropped, not
    -- approximated: double-click-centers-map (map:CenterMap(), needs
    -- a real mapID/Coords - step 8 territory, see ZoomController.lua's
    -- own header), Shift-click-ping, Ctrl/Alt-modified-click
    -- (CallFunc-bound actions tied to a config system this addon
    -- doesn't have), and the Ctrl+Alt rectangle-draw edit mode - all
    -- non-goals per the plan.
    contentFrm:EnableMouse(true)
    contentFrm:SetScript("OnMouseDown", function(_, button)
        self:OnMouseDown(button)
    end)
    contentFrm:SetScript("OnMouseUp", function(_, button)
        self:OnMouseUp(button)
    end)
end

---------------------------------------------------------------------------------------
-- Build-order step 8: real world-art canvas. The player's actual
-- continent/zone, drawn as a tile grid of Blizzard's own live map art
-- (C_Map.GetMapArtLayers/GetMapArtLayerTextures) positioned/scaled by
-- the SAME Scale/ScaleDraw/MapPosX*Draw state steps 5/6 already
-- animate - so panning/zooming the live-widget patch pans/zooms this
-- background in lockstep, with no new coordination code needed.
--
-- Ported near-verbatim from real Carbonite (file:line noted per
-- function below) against Map\Data\NxMapData.lua - Carbonite's own
-- real Camelot-flavor zone/continent database, copied wholesale (see
-- that file's own header for what's intentionally left unported/dead
-- inside it). What's deliberately NOT ported from the same cluster,
-- and why:
--   - Nx.Map:UpdateWorld (MapEngine.lua:5945-6147) itself - the real
--     orchestration entangles garrison-tier texture paths, dungeon-
--     level suffixes, fog-of-war "explored overlay" diffing, Classic
--     old-MapID translation, and Blizzard-WorldMapFrame mouse-vs-
--     player disambiguation, none of which this addon has any of the
--     surrounding machinery for. UpdateWorldArt below is a fresh,
--     much smaller trigger that calls the exact same real API
--     primitives (GetArtSourceMapID/GetArtLayerTextures) UpdateWorld
--     itself calls for the texture-fetch step - the part that's
--     actually hard to get right (the C_Map shape-guards, the per-
--     flavor art-ID resolution) is still the real code, just without
--     the entangled orchestration around it.
--   - Nx.Map:SetToCurrentZone/SetMapByID/GetCurrentMapId (depend on
--     self.RMapId, legacy render-pass state tied to the above) - not
--     ported; RefreshCurrentZone below drives "what to show" from
--     MapIDs:GetDisplayableMapForPlayer-equivalent logic instead,
--     which is self-contained and live-API-driven.
--   - The classic-minimap-tile "detail relief" close-zoom layer
--     (UpdateMiniFrames/GetMiniInfo/GetMiniBlkName/CreateMiniFrame) -
--     tangled with the explicit 3D-view non-goal and old zone special-
--     casing; deeper zoom instead just uses GetArtLayers' own further
--     layer indices (Blizzard's own art already has multiple zoom
--     tiers per map).
--   - IsBattleGroundMap/IsMicroDungeon/the wzone City/ModernZoneArt/
--     StartZone gate in the real MoveCurZoneTiles - that gate decides
--     whether the old tile system should defer to a competing "modern
--     instance canvas" overlay; this addon has no such overlay (non-
--     goal), so there's nothing to defer to and always drawing
--     whichever zone we're in is the correct simplification.
---------------------------------------------------------------------------------------

-- Kept verbatim from Nx.Map:InitFrames (MapEngine.lua:2275-2296) - only
-- the TileFrms pool half; the sibling ContFrms init in the same real
-- function serves the zone==0 continent-overview render path, which is
-- never reached in this addon (nothing here ever sets self.Zone = 0 -
-- see RefreshCurrentZone), so it's left out rather than built unused.
function MinimapEngine:InitTileFrames()
    self.TileFrms = {}
    local f = self.Frm
    for i = 1, 150 do
        local tf = CreateFrame("Frame", nil, f)
        self.TileFrms[i] = tf
        local t = tf:CreateTexture()
        t:SetAllPoints(tf)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tf.texture = t
    end
end

-- Kept verbatim from Nx.Map:GetArtSourceMapID/GetArtLayers/
-- GetArtLayerTextures (MapEngine.lua:9454-9490) - the real C_Map
-- shape-guards (their own comment: a 12.0.5-era hotfix wrapped both
-- map-art APIs one extra level deeper on some clients; these normalize
-- back to the flat shape so the draw math below never has to care).
function MinimapEngine:GetArtSourceMapID(id)
    local info = id and self.MapWorldInfo and self.MapWorldInfo[id]
    if not info then return id end
    return info.ArtMapID or info.RBaseMap or id
end

function MinimapEngine:GetArtLayers(id)
    local layers = id and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(id)
    if layers and layers[1] and layers[1].layerWidth == nil and type(layers[1][1]) == "table" then
        layers = layers[1]
    end
    return layers
end

function MinimapEngine:GetArtLayerTextures(id, layer)
    local textures = id and C_Map and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(id, layer)
    if textures and type(textures[1]) == "table" then
        textures = textures[1]
    end
    return textures
end

-- Kept verbatim from Nx.Map:HideZoneTileFrames (MapEngine.lua:9460-9474).
function MinimapEngine:HideZoneTileFrames(frms, clearTextures)
    if not frms then return end
    for i = 1, 150 do
        local frm = frms[i]
        if frm then
            frm:Hide()
            if clearTextures and frm.texture then
                frm.texture:SetTexture(nil)
            end
        end
    end
    if clearTextures and frms == self.TileFrms then
        self.CurWorldTileCount = 0
    end
end

-- Trimmed from Nx.Map:GetWorldZoneInfo (MapEngine.lua:14959-14993) -
-- drops the GetMapNameByID lookup for the human-readable `name` return
-- value (MoveZoneTiles below never reads it either - it's cosmetic
-- title text this addon's window doesn't show), the dead, already-
-- commented-out DebugPXOff branch, and the `ParentMapCache` fallback
-- for a mapID with no MapWorldInfo row at all (used for Blizzard
-- city/sub-zone maps missing from Carbonite's static catalog - a
-- non-goal here since RefreshCurrentZone's own FindContinent already
-- requires zone-catalog membership before ever calling this, so that
-- fallback would never be reached anyway). Everything that actually
-- produces the zone's world-space anchor/span (the whole reason this
-- function exists) is unchanged.
function MinimapEngine:GetWorldZoneInfo(cont, zone)
    if not cont or not zone then
        return nil, 0, 0, 1002, 668
    end
    local info = self.MapInfo[cont]
    if not info then
        return nil, 0, 0, 1002, 668
    end
    if zone == 0 then
        zone = self.MapZones[0] and self.MapZones[0][cont]
    end
    local winfo = self.MapWorldInfo[zone]
    if not winfo or not winfo.X then
        return nil, 0, 0, 1002, 668
    end
    local x = info.X + winfo.X
    local y = info.Y + winfo.Y
    local scale = winfo.Scale * 100
    return nil, x, y, scale, scale / 1.5
end

-- Nx.Map:GetWorldPos (MapEngine.lua:15047-15068) - referenced by name
-- in several comments elsewhere in this file (RefreshCurrentZone,
-- the step 9b service-icon section) but never actually implemented
-- until now (found live, 2026-11-10, while wiring RefreshServiceIcons
-- - it would have errored on first call). Converts a 0-100
-- zone-relative percent position to world coordinates, using the
-- exact same per-zone anchor/scale data GetWorldZoneInfo above already
-- relies on successfully (info.X/Y, winfo.X/Y/Scale) - just the
-- general-position form instead of GetWorldZoneInfo's own fixed "top-
-- left + full span" return. x/y default to 50/50 (zone center),
-- matching the real source's own default and RefreshCurrentZone's
-- "pans to the zone's center" comment above.
function MinimapEngine:GetWorldPos(mapId, x, y)
    local cont = self:FindContinent(mapId)
    if not cont then return nil end
    local info = self.MapInfo[cont]
    local winfo = self.MapWorldInfo[mapId]
    if not info or not winfo or not winfo.X or not winfo.Scale then return nil end
    local anchorX = info.X + winfo.X
    local anchorY = info.Y + winfo.Y
    return anchorX + (x or 50) * winfo.Scale, anchorY + (y or 50) * winfo.Scale / 1.5
end

-- Kept verbatim from Nx.Map:MoveZoneTiles (MapEngine.lua:9533-9690) -
-- the real tile-grid crop/position/texcoord math. Not approximated;
-- every branch (including the zone==0 continent-overview path, dead
-- code for now per InitTileFrames' comment above) is unchanged.
function MinimapEngine:MoveZoneTiles(cont, zone, frms, alpha, level)
    local zname, zx, zy, zw, zh = self:GetWorldZoneInfo(cont, zone)
    if not zx then
        self:HideZoneTileFrames(frms)
        return
    end

    local scale = self.ScaleDraw
    local tilex, tiley, layerInfo
    if zone == 0 then
        local rootMapID = self.MapZones[0] and self.MapZones[0][cont]
        local layers = rootMapID and self:GetArtLayers(rootMapID)
        layerInfo = layers and layers[1]
        tilex = layerInfo and ceil(layerInfo.layerWidth / layerInfo.tileWidth)
            or self.MapInfo[cont].TileX or 4
        tiley = layerInfo and ceil(layerInfo.layerHeight / layerInfo.tileHeight)
            or self.MapInfo[cont].TileY or 3

        if self.MapInfo[cont].ZXOff and self.MapInfo[cont].ZYOff then
            zx = zx + self.MapInfo[cont].ZXOff
            zy = zy + self.MapInfo[cont].ZYOff
        end

        if self.MapInfo[cont].ZWOff and self.MapInfo[cont].ZHOff then
            zw = zw + self.MapInfo[cont].ZWOff
            zh = zh + self.MapInfo[cont].ZHOff
        end
    else
        local layers = self:GetArtLayers(self:GetArtSourceMapID(zone))
        if layers and layers[1] then
            layerInfo = layers[1]
            tilex = ceil(layerInfo.layerWidth / layerInfo.tileWidth)
            tiley = ceil(layerInfo.layerHeight / layerInfo.tileHeight)
        else
            tilex = self.MapWorldInfo[zone].TileX or 4
            tiley = self.MapWorldInfo[zone].TileY or 3
        end

        if self.MapWorldInfo[zone].ZXOff and self.MapWorldInfo[zone].ZYOff then
            zx = zx + self.MapWorldInfo[zone].ZXOff
            zy = zy + self.MapWorldInfo[zone].ZYOff
        end

        if self.MapWorldInfo[zone].ZWOff and self.MapWorldInfo[zone].ZHOff then
            zw = zw + self.MapWorldInfo[zone].ZWOff
            zh = zh + self.MapWorldInfo[zone].ZHOff
        end
    end

    local clipW = self.MapW
    local clipH = self.MapH
    local x = (zx - self.MapPosXDraw) * scale + clipW / 2
    local y = (zy - self.MapPosYDraw) * scale + clipH / 2
    local bx = 0
    local by = 0
    local bw, bh
    if layerInfo then
        bw = zw * layerInfo.tileWidth / layerInfo.layerWidth * scale
        bh = zh * layerInfo.tileHeight / layerInfo.layerHeight * scale
    else
        bw = zw * (tilex == 15 and 1 or 1024 / 1002) / tilex * scale
        bh = zh * (tiley == 10 and 1 or 768 / 668) / tiley * scale
    end

    local w, h
    local texX1, texX2
    local texY1, texY2
    local numtiles = tilex * tiley
    if frms == self.TileFrms and self.CurWorldTileCount then
        numtiles = min(numtiles, self.CurWorldTileCount)
    end

    for i = 1, numtiles do
        local frm = frms[i]
        if frm then
            texX1 = 0
            texY1 = 0
            texX2 = layerInfo
                and min(layerInfo.tileWidth, layerInfo.layerWidth - bx * layerInfo.tileWidth)
                    / layerInfo.tileWidth
                or 1
            texY2 = layerInfo
                and min(layerInfo.tileHeight, layerInfo.layerHeight - by * layerInfo.tileHeight)
                    / layerInfo.tileHeight
                or 1

            local vx0 = bx * bw + x
            local vx1 = vx0
            local vx2 = vx0 + bw * texX2

            if vx1 < 0 then
                vx1 = 0
                texX1 = (vx1 - vx0) / bw
            end

            if vx2 > clipW then
                vx2 = clipW
                texX2 = (vx2 - vx0) / bw
            end

            local vy0 = by * bh + y
            local vy1 = vy0
            local vy2 = vy0 + bh * texY2

            if vy1 < 0 then
                vy1 = 0
                texY1 = (vy1 - vy0) / bh
            end

            if vy2 > clipH then
                vy2 = clipH
                texY2 = (vy2 - vy0) / bh
            end

            w = vx2 - vx1
            h = vy2 - vy1

            if w <= 0 or h <= 0 then
                frm:Hide()
            else
                frm:SetPoint("TOPLEFT", vx1, -vy1 - self.TitleH)
                frm:SetWidth(w)
                frm:SetHeight(h)
                frm:SetFrameLevel(level)

                frm.texture:SetTexCoord(texX1, texX2, texY1, texY2)

                -- Real Carbonite writes this same call out but leaves
                -- it commented (MapEngine.lua:9670,
                -- `--frm.texture:SetVertexColor(1,1,1,self.BackgndAlpha)`)
                -- - alpha is accepted as a parameter here and nowhere
                -- ever applied to the tile, in both the real source
                -- and (until now) this port. Applied as a brightness
                -- multiplier across all 3 color channels rather than
                -- the alpha channel (MapContextMenu.lua's own slider -
                -- 0-100% only, confirmed working range per explicit
                -- instruction, 2026-11-10).
                frm.texture:SetVertexColor(alpha, alpha, alpha, 1)

                frm:Show()
            end
        end

        bx = bx + 1

        if bx >= tilex then
            bx = 0
            by = by + 1
        end
    end

    for i = numtiles + 1, 150 do
        local frm = frms[i]
        if frm then frm:Hide() end
    end
end

-- Trimmed from Nx.Map:MoveCurZoneTiles (MapEngine.lua:9404-9431) -
-- drops its own inner wzone.City/.ModernZoneArt/.StartZone/BG/
-- MicroDungeon gate. Verified against source this isn't the gate that
-- decides whether an ORDINARY zone's overview art shows at all - that
-- decision is made one level up, by the real caller Nx.Map:UpdateZones
-- (MapEngine.lua:9837, `freeOrScale = self.ScaleDraw <= NXDetailScale`,
-- default threshold 4): when zoomed out past that threshold (the
-- normal case for an overview-style window like this one), it calls
-- bare MoveCurZoneTiles() for ANY zone, ordinary or not. The inner
-- gate this function drops only matters for the camelot flavor's own
-- narrower cases (city sub-maps, the very-first-login start zone,
-- battlegrounds, micro-dungeons) - not applicable to this engine's
-- simpler zone model, so always drawing whichever known zone we're in
-- is the correct simplification here, not an approximation of a real
-- gate we're skipping. The OTHER half of UpdateZones' own gate - what
-- happens when zoomed IN past that threshold - used to be dismissed
-- in this same comment as "an explicit non-goal"; that was wrong (see
-- UpdateMiniFrames below, added 2026-11-10 once a live screenshot
-- comparison against real Carbonite revealed what it actually is).
function MinimapEngine:MoveCurZoneTiles()
    if not self.Cont then
        self:HideZoneTileFrames(self.TileFrms)
        return
    end
    self:MoveZoneTiles(self.Cont, self.Zone, self.TileFrms, self.BackgndAlpha or 1,
        self.Frm:GetFrameLevel() or 1)
end

---------------------------------------------------------------------------------------
-- Build-order step 8b (2026-11-10): the real-terrain "detail tile"
-- system - a THIRD visual layer, distinct from both the zone-overview
-- tiles above (MoveZoneTiles) and the live Blizzard-widget blend
-- (ClipMMW). Ported from Nx.Map:UpdateMiniFrames/CreateMiniFrame/
-- HideMiniFrames/ClipFrameTL (MapEngine.lua:10296-10535+/11552),
-- discovered by reading the real source after a live screenshot
-- comparison showed Carbonite's own undocked map filling its whole
-- window with rich, continuously-pannable detail that the live widget
-- alone can't produce (it only ever renders a small patch near the
-- player - see ClipMMW's own header). The real mechanism: plain
-- static frames tiled with real per-256px client minimap textures
-- (Map/Data/MinimapTiles.lua's FileDataIDs - the same art the native
-- minimap itself renders from), positioned from MapPosXDraw/Y like any
-- other tile layer, so panning scrolls them smoothly and they aren't
-- tied to the player's live position the way the small widget patch
-- is. Unlike the zone-overview layer, this one is NOT scale-gated:
-- real Carbonite's UpdateZones (MapEngine.lua:9831-9900) calls
-- UpdateMiniFrames() unconditionally on every single tick, at every
-- zoom level, in every branch - it's always live from the moment the
-- window opens. The NXDetailScale threshold only ever decides whether
-- the COARSE zone-overview layer (MoveCurZoneTiles, above) is ALSO
-- drawn on top of it (zoomed out) or cleared (zoomed in); this
-- engine's Update() mirrors exactly that, not an either/or swap
-- between the two layers (an earlier version of this code wrongly
-- treated it as one, gating UpdateMiniFrames itself behind the same
-- threshold - confirmed wrong live, 2026-11-10: it meant detail tiles
-- only ever turned on once already zoomed in far enough that a single
-- ~107-world-unit tile exceeded the whole window, i.e. "stuck showing
-- one square, no update on pan").
--
-- View3D (Carbonite's tilted 3D relief mode) is an explicit non-goal
-- throughout this addon (ZoomController.lua's own header) - both
-- functions below drop that entire branch, keeping only the flat 2D
-- tiling math (same shape as MoveZoneTiles' own per-tile clip code
-- above).
---------------------------------------------------------------------------------------

-- How far out (in 256px tile blocks) to tile in each direction from
-- the current view center. Real Carbonite exposes this as a user
-- slider (Nx.db.profile.Map.DetailSize, default 6) this addon has no
-- settings UI for - hardcoded at that same default instead, same
-- "disclosed trim" pattern as FIT_MARGIN elsewhere in this file.
local DETAIL_RADIUS = 6

-- Zoom-scale threshold controlling ONLY the zone-overview layer above
-- (MoveCurZoneTiles vs. HideZoneTileFrames in Update(), below) - real
-- Carbonite's NXDetailScale, hardcoded here at its real default 4,
-- same reasoning as DETAIL_RADIUS above. Does NOT gate UpdateMiniFrames
-- itself (see that function's own header comment - it's unconditional,
-- every tick, every zoom level). Real Carbonite's UpdateMiniFrames
-- does take its own optional alphaPer fade-in parameter, but traced
-- through every one of UpdateZones' real call sites and confirmed
-- it's always invoked with zero arguments there - the fade parameter
-- exists for a different, unported caller (the View3D/tilted-relief
-- branch's own transition), not for this one - so UpdateMiniFrames
-- below skips that parameter entirely and always draws at full
-- BackgndAlpha, matching every reachable real call site exactly.
local DETAIL_SCALE = 4

function MinimapEngine:CreateMiniFrame()
    local tf = CreateFrame("Frame", nil, self.Frm)
    local t = tf:CreateTexture()
    tf.texture = t
    t:SetAllPoints(tf)
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
    return tf
end

function MinimapEngine:HideMiniFrames()
    for i = 1, #self.MiniFrms do
        self.MiniFrms[i]:Hide()
    end
end

-- Kept verbatim from Nx.Map:ClipFrameTL (MapEngine.lua:11552) - the
-- flat (non-View3D) half only; also drops the real source's w<.3/
-- ScrollingFrm micro-tile-width special case (that guard exists for
-- Carbonite's own click-drag-to-scroll frame identity, self.ScrollingFrm,
-- which this engine's own pan-drag - MinimapEngine:OnMouseDown/Up's
-- Scrolling flag - doesn't track per-frame; a tile narrower than .3px
-- just hiding outright is harmless here).
function MinimapEngine:ClipFrameTL(frm, bx, by, w, h)
    local scale = self.ScaleDraw

    local bw = w * scale
    local clipW = self.MapW
    local x = (bx - self.MapPosXDraw) * scale + clipW * .5

    local texX1, texX2 = 0, 1
    local vx1 = x
    local vx2 = x + bw

    if vx1 < 0 then
        vx1 = 0
        texX1 = (vx1 - x) / bw
    end
    if vx2 > clipW then
        vx2 = clipW
        texX2 = (vx2 - x) / bw
    end

    w = vx2 - vx1
    if w <= 0 then
        frm:Hide()
        return false
    end

    local bh = h * scale
    local clipH = self.MapH
    local y = (by - self.MapPosYDraw) * scale + clipH * .5

    local texY1, texY2 = 0, 1
    local vy1 = y
    local vy2 = y + bh

    if vy1 < 0 then
        vy1 = 0
        texY1 = (vy1 - y) / bh
    end
    if vy2 > clipH then
        vy2 = clipH
        texY2 = (vy2 - y) / bh
    end

    h = vy2 - vy1
    if h <= 0 then
        frm:Hide()
        return false
    end

    frm:SetPoint("TOPLEFT", vx1, -vy1 - self.TitleH)
    frm:SetWidth(w)
    frm:SetHeight(h)
    frm.texture:SetTexCoord(texX1, texX2, texY1, texY2)
    frm:Show()
    return true
end

-- Kept verbatim (flat-view math only) from Nx.Map:UpdateMiniFrames
-- (MapEngine.lua:10296-10535+). miniT/basex/basey come from
-- GetMiniInfo (Map/Data/MinimapRuntime.lua). Called every tick,
-- unconditionally, at every zoom level (see Update()'s call site and
-- the DETAIL_SCALE comment above for why this is NOT zoom-gated) -
-- full BackgndAlpha, no fade-in parameter needed for the reason
-- explained there.
function MinimapEngine:UpdateMiniFrames()
    local miniT, basex, basey = self:GetMiniInfo(self.MapId)
    if not miniT then
        self:HideMiniFrames()
        return
    end

    -- Each real minimap tile texture covers this many world units -
    -- kept verbatim (256 * the real source's own magic constant,
    -- MapEngine.lua:10387).
    local scale = 256 * 0.416767770014
    local blks = DETAIL_RADIUS
    local miniX = floor((self.MapPosXDraw - basex) / scale - blks / 2 + .5)
    local miniY = floor((self.MapPosYDraw - basey) / scale - blks / 2 + .5)

    local need = blks * blks
    if #self.MiniFrms < need then
        for n = #self.MiniFrms + 1, need do
            self.MiniFrms[n] = self:CreateMiniFrame()
        end
    end

    basex = basex + miniX * scale
    basey = basey + miniY * scale

    local al = self.BackgndAlpha or 1
    local level = self.Frm:GetFrameLevel() or 1
    local frmNum = 1
    local wy = basey

    for y = miniY, miniY + blks - 1 do
        local wx = basex
        for x = miniX, miniX + blks - 1 do
            local frm = self.MiniFrms[frmNum]
            local key = (x + miniT[3]) * 100 + (y + miniT[4])
            local txname = miniT[1][key]

            if txname and txname ~= "" then
                if self:ClipFrameTL(frm, wx, wy, scale, scale) then
                    frm:SetFrameLevel(level)
                    frm.texture:SetVertexColor(1, 1, 1, al)
                    frm.texture:SetTexture(txname)
                end
            else
                frm:Hide()
            end

            wx = wx + scale
            frmNum = frmNum + 1
        end
        wy = wy + scale
    end

    for n = frmNum, #self.MiniFrms do
        self.MiniFrms[n]:Hide()
    end
end

---------------------------------------------------------------------------------------
-- Build-order step 9a (2026-11-10): a player-position marker drawn
-- directly on the canvas, independent of the live Blizzard-widget
-- blend (ClipMMW above). Added after live testing showed the live
-- widget - the only thing in this addon showing where the player is -
-- can legitimately clip out of view (same "pan far enough and lose
-- the square" behavior disclosed since this project's first session)
-- or visibly disagree with the tile layers whenever the view's pan
-- target (MapPosXDraw/Y) differs from the player's raw live position
-- (PlyrX/Y) - e.g. mid-animation after a zoom/recenter, or while
-- panned away with auto-follow off.
--
-- Investigated how real Carbonite actually solves this (not guessed):
-- it doesn't have a separate "draw the player" mechanism at all. The
-- player marker is just one more icon - a "Player" Pin (Pin.lua,
-- Pins/PlayerPin.lua) drawn by the same generic per-frame icon
-- renderer (Renderer.lua) as every other world icon (mailbox, inn,
-- quest giver, etc.), all going through the identical world-to-screen
-- math this file's own ClipFrameTL/ClipMMW already use. The one
-- real difference: it keeps a dedicated self.PlyrFrm reference
-- (MapEngine.lua:1585) rather than going through the generic
-- pool/mixin plumbing every other icon kind uses, since there's
-- always exactly one.
--
-- This ports that same real mechanism at the same scope: one
-- dedicated frame, the real ClipFrameW point-clip math (MapEngine.lua
-- :10668-10786 - the "WP"/world-point draw mode every Pin kind
-- defaults to), continuously repositioned from PlyrX/Y every tick.
-- It does NOT pull in Pin.lua/Layer.lua/Renderer.lua's generic
-- class/pool machinery - that's only worth its complexity once
-- multiple icon kinds exist (mailbox/inn/quest-giver icons, tracked
-- as a separate, larger follow-on scope decision, not part of this
-- step).
---------------------------------------------------------------------------------------

-- Fixed pixel size (not scaled by ScaleDraw - same "icons stay a
-- constant on-screen size, only their position moves with zoom/pan"
-- rule real Carbonite's own Pin system documents, Pin.lua's own header
-- comment: "w, h  pixel size at scale 1"). Real Carbonite exposes this
-- as a user slider (Nx.db.profile.Map.PlyrArrowSize) this addon has no
-- settings UI for - started at the real PlayerPin class's own default
-- size (Pins/PlayerPin.lua: w=20, h=20), bumped up per user feedback
-- 2026-11-10 ("needs to be a touch bigger").
local PLAYER_MARKER_SIZE = 28

-- Kept verbatim (core W-clip math only) from Nx.Map:ClipFrameW
-- (MapEngine.lua:10681-10786). Drops the real source's View3D branch
-- (explicit non-goal, same as every other function in this file) and
-- its ClipFrameByMapType instance-map wrapper (ClipFrameMF branch -
-- this addon has no instance-map canvas; UpdatePlayerMarker below
-- calls this directly instead of through that wrapper). Unlike
-- ClipFrameTL (used for tiles), w/h here are NOT multiplied by scale -
-- see PLAYER_MARKER_SIZE's own comment above for why - only the
-- center position moves with zoom/pan, matching real Carbonite's own
-- icon-vs-tile distinction exactly.
function MinimapEngine:ClipFrameW(frm, bx, by, w, h, dir)
    local scale = self.ScaleDraw
    local clipW = self.MapW
    local clipH = self.MapH

    local x = (bx - self.MapPosXDraw) * scale + clipW * .5
    local y = (by - self.MapPosYDraw) * scale + clipH * .5

    -- hideOutside: real Carbonite's own icon call sites always pass
    -- true here (that's what makes an icon vanish once panned off the
    -- visible canvas, same behavior as ClipFrameTL's own tiles) - this
    -- marker has exactly one use site, so it's hardcoded true rather
    -- than threaded through as a parameter nothing else would set
    -- differently.
    if x < 0 or x > clipW or y < 0 or y > clipH then
        frm:Hide()
        return false
    end

    local bw, bh = w, h
    local texX1, texX2 = 0, 1
    local texY1, texY2 = 0, 1

    local vx1 = x - bw * .5
    local vx2 = vx1 + bw
    if vx1 < 0 then
        vx1 = 0
        texX1 = (vx1 - (x - bw * .5)) / bw
    end
    if vx2 > clipW then
        vx2 = clipW
        texX2 = (vx2 - (x - bw * .5)) / bw
    end
    local fw = vx2 - vx1
    if fw < .3 then
        frm:Hide()
        return false
    end

    local vy1 = y - bh * .5
    local vy2 = vy1 + bh
    if vy1 < 0 then
        vy1 = 0
        texY1 = (vy1 - (y - bh * .5)) / bh
    end
    if vy2 > clipH then
        vy2 = clipH
        texY2 = (vy2 - (y - bh * .5)) / bh
    end
    local fh = vy2 - vy1
    if fh < .3 then
        frm:Hide()
        return false
    end

    frm:SetPoint("TOPLEFT", vx1, -vy1 - self.TitleH)
    frm:SetWidth(fw)
    frm:SetHeight(fh)
    frm.texture:SetTexCoord(texX1, texX2, texY1, texY2)

    -- Facing rotation, for the player marker. Real Carbonite's own
    -- ClipFrameW (MapEngine.lua:10792-10805+) does this via UV-space
    -- corner rotation (rotating the four texcoords around .5,.5) -
    -- first ported that way verbatim here, but user-reported live
    -- 2026-11-10 that the marker never visibly rotated at all, and
    -- that hand-rolled corner math couldn't be cross-checked against
    -- a working reference (PlayerPin.lua, the newer Pin-system
    -- rewrite of this same addon, doesn't carry facing/rotation over
    -- at all - it only tracks x/y). Switched to the texture's own
    -- native :SetRotation(), the standard WoW API built for exactly
    -- this (rotates in place around the texture's center, composes
    -- fine with the texcoord cropping above) - simpler and doesn't
    -- depend on hand-rolled trig being right. If this turns out
    -- mirrored (rotates the wrong way) rather than not rotating at
    -- all, the fix is a one-line sign flip on PlyrDir below, not
    -- another rewrite here.
    frm.texture:SetRotation(dir or 0)

    frm:Show()
    return true
end

-- Repositions the dedicated canvas player marker every tick from the
-- engine's own already-tracked PlyrX/Y/PlyrDir (see Update()'s own
-- position-resolution block and this section's header comment above
-- for why this exists independently of the live-widget blend).
function MinimapEngine:UpdatePlayerMarker()
    local frm = self.PlyrFrm
    if not frm then return end
    if not frm.texture:GetTexture() then
        frm.texture:SetTexture("Interface\\Minimap\\MinimapArrow")
    end
    frm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + 10)
    self:ClipFrameW(frm, self.PlyrX, self.PlyrY,
        PLAYER_MARKER_SIZE, PLAYER_MARKER_SIZE, self.PlyrDir)
end

---------------------------------------------------------------------------------------
-- Build-order step 9b (2026-11-10): static service-location icons
-- (mailbox, innkeeper, flight master) - the "reopen full icon/pin
-- system" scope decision, same session as step 9a's player marker.
--
-- Investigated how real Carbonite actually sources these (not
-- guessed): unlike quest-giver/trainer/gather icons - which track
-- live game state and go through the generic Pin/Layer/Renderer
-- system (Pin.lua/Renderer.lua) - static service icons come from a
-- hand-curated per-flavor coordinate database shipped as plain data
-- files (Carbonite/Data/camelot/Guides/<Kind>.lua), looked up by the
-- current mapID. Ported Mailbox/Innkeeper verbatim (Map/Data/
-- GuideMailbox.lua/GuideInnkeeper.lua). Flight Master's own camelot
-- data file ships empty for this flavor (no coordinates, just a Mode
-- flag) - sourced from Blizzard's own live C_TaxiMap API instead,
-- which is arguably the more robust choice anyway (always accurate to
-- what the player has actually discovered, no hand-curated data to go
-- stale or miss this server's custom geography).
--
-- These are STATIC positions (a mailbox doesn't move), so unlike the
-- player marker this only needs to resolve world positions on zone
-- change (RefreshServiceIcons, called from RefreshCurrentZone) rather
-- than every tick - but still needs to REPOSITION on screen every
-- tick (UpdateServiceIcons, called from Update()), since pan/zoom
-- moves the screen position even though the world position hasn't
-- changed. Reuses step 9a's ClipFrameW directly - these are icons like
-- the player marker, not scaled tiles, so no new clip math is needed.
---------------------------------------------------------------------------------------

local SERVICE_ICON_SIZE = 16

-- Standard Blizzard minimap-tracking-filter textures (not Carbonite's
-- own icon atlas) - long-standing paths, present since Classic.
-- Innkeeper confirmed rendering live, 2026-11-10 (visible once the
-- faction-filter bug above was found and fixed). Mailbox switched the
-- same day to Interface\Icons\INV_Letter_15 - the user reported no
-- mail icon at all, and Interface\Minimap\TrackingIcons\Mailbox is in
-- the exact same Interface\Minimap\... texture family already
-- confirmed BROKEN on this server build (MinimapDock.lua's native
-- mail-icon fix, same session - MiniMap-MailIcon renders nothing
-- here). Reusing that fix's own already-verified-visible replacement
-- rather than guessing a third path blind.
local SERVICE_ICON_TEX = {
    Mailbox   = "Interface\\Icons\\INV_Letter_15",
    Innkeeper = "Interface\\MINIMAP\\TRACKING\\Innkeeper",
}
-- Not yet confirmed either way - same TRACKING family as the now-
-- confirmed-working Innkeeper path above, so likely fine; flight-
-- master's own absence in the user's 2026-11-10 report is more likely
-- a C_TaxiMap data/mapID question than a texture one. See
-- RefreshServiceIcons' own header comment for the open question.
local FLIGHTMASTER_TEX = "Interface\\MINIMAP\\TRACKING\\FlightMaster"

-- Carbonite's real faction filter (GuideLocations.lua's hideFaction),
-- ported inline since this addon doesn't have that whole module.
-- Found and fixed live, 2026-11-10: this addon's own first pass at
-- this had the two conditions backwards. Real Carbonite's
-- hideFaction() returns the faction CODE TO HIDE for the current
-- player (1 for a Horde player, 2 for an Alliance player), and its one
-- call site (FindNPC) shows an entry whenever `fac ~= hide` - so
-- fac==1 is actually hidden FROM Horde (Alliance-only), and fac==2 is
-- hidden FROM Alliance (Horde-only). The original version here did
-- the opposite (showed fac==1 to Horde, fac==2 to Alliance), which
-- silently hid every Horde-only entry from a Horde player - exactly
-- matching the reported symptom (only one of three innkeeper entries
-- in a zone visible, and not the one actually nearby).
local function ServiceIconFactionOk(fac)
    if fac == 0 then return true end
    local faction = UnitFactionGroup("player")
    if faction == "Horde" then return fac == 2 end
    if faction == "Alliance" then return fac == 1 end
    return true
end

-- Confirmed live, 2026-11-10: C_TaxiMap's own node.faction does NOT use
-- GuideData's hide-code convention above (1=Alliance-only/2=Horde-only).
-- The Camp Taurajo node (a real Horde-only flight point) reported
-- faction=1 - direct identity (1=Horde, 2=Alliance), the opposite
-- scheme. Reusing ServiceIconFactionOk for taxi nodes was rejecting
-- every same-faction node outright - this is why none ever appeared
-- even once the whole-continent/bounds-check fix landed. Separate
-- function, do not merge back with ServiceIconFactionOk - the two data
-- sources disagree on what the numbers mean.
local function TaxiFactionOk(fac)
    if not fac or fac == 0 then return true end
    local faction = UnitFactionGroup("player")
    if faction == "Horde" then return fac == 1 end
    if faction == "Alliance" then return fac == 2 end
    return true
end

function MinimapEngine:HideServiceFrames()
    for i = 1, #self.SvcFrms do
        self.SvcFrms[i]:Hide()
    end
end

-- Rebuilds the resolved service-icon world-position list for the
-- current zone. Call only on zone change (RefreshCurrentZone) - these
-- are static positions, recomputing every tick would be wasted work.
--
-- Open question, 2026-11-10: user reported no flight-master icon
-- visible at a Crossroads (The Barrens, mapID 1413) landing, right
-- after flying in. Camelot's own FlightMaster.lua data file ships
-- empty for this flavor (confirmed earlier this session), so this
-- only ever has anything to show via the C_TaxiMap branch below - if
-- that reports no reachable/current node for this exact mapID, or
-- GetTaxiNodesForMap itself isn't returning what's expected on this
-- server build, nothing renders. Not yet root-caused; the faction-
-- filter bug and the Mailbox texture swap above were both confirmed,
-- concrete fixes, this one still needs a live check (does
-- C_TaxiMap.GetTaxiNodesForMap(1413) return anything at all from
-- Crossroads once landed) before guessing further.
function MinimapEngine:RefreshServiceIcons()
    local pts = {}
    self.SvcPts = pts
    if not self.MapId then return end

    for kind, tex in pairs(SERVICE_ICON_TEX) do
        local data = self.GuideData and self.GuideData[kind]
        local entry = data and data[self.MapId]
        if entry then
            for fac, x, y in entry:gmatch("(%d+),([%d%.]+),([%d%.]+)") do
                if ServiceIconFactionOk(tonumber(fac)) then
                    local wx, wy = self:GetWorldPos(self.MapId, tonumber(x), tonumber(y))
                    if wx then
                        pts[#pts + 1] = { x = wx, y = wy, tex = tex }
                    end
                end
            end
        end
    end

    -- Found and fixed live, 2026-11-10: the original check here
    -- (`node.state == Enum.FlightPathState.Reachable/.Current`) never
    -- matched anything on this server build - no flight-master icon
    -- ever appeared. Re-derived against ForeverDungeonJournal's own
    -- Systems/MapMarkers.lua, an already-installed, already-working
    -- addon on this exact server that also calls GetTaxiNodesForMap:
    -- it doesn't trust the node's own state/type field for
    -- reachability either - it tracks "discovered" itself from the
    -- flight map being opened, specifically because the live field
    -- isn't reliable here. It also reads node.position defensively
    -- (some builds hand back a plain {x,y} table, others a Vector2D
    -- needing :GetXY()) rather than assuming `.x`/`.y` are always
    -- present. Matched both of those here, and dropped the
    -- reachability filter entirely in favor of showing every node
    -- this call returns for the zone - we're not building a discovery
    -- log, just flight-master icons, and "shows an undiscovered one
    -- too" beats "shows none at all". Faction filtering reuses
    -- ServiceIconFactionOk above - node.faction is the same 1=Horde-
    -- only/2=Alliance-only convention (confirmed against that same
    -- addon's own OurSide()), not a separate scheme.
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, self.MapId)
        if ok and type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                if TaxiFactionOk(tonumber(node.faction)) then
                    local pos = node.position
                    local nx, ny = pos and pos.x, pos and pos.y
                    if pos and (nx == nil or ny == nil) and pos.GetXY then
                        nx, ny = pos:GetXY()
                    end
                    -- Confirmed live, 2026-11-10: GetTaxiNodesForMap(1413)
                    -- returned 38 nodes standing in The Barrens - the
                    -- whole continent's flight network (the same thing a
                    -- flight master's own map shows when you talk to one),
                    -- not just nodes physically in this zone. Positions
                    -- for a node elsewhere on the continent aren't
                    -- meaningful as a percent-through-THIS-zone and land
                    -- miles outside it once run through GetWorldPos -
                    -- this bounds check rejects those before that
                    -- conversion rather than relying on ClipFrameW's
                    -- downstream screen-space clip to hide them (their
                    -- resulting world position could coincidentally
                    -- overlap something on-screen, not just land safely
                    -- off it).
                    if nx and ny and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                        local wx, wy = self:GetWorldPos(self.MapId, nx * 100, ny * 100)
                        if wx then
                            pts[#pts + 1] = { x = wx, y = wy, tex = FLIGHTMASTER_TEX }
                        end
                    end
                end
            end
        end
    end
end

-- Repositions every resolved service-icon point every tick - world
-- positions are static (see RefreshServiceIcons above), but screen
-- position still moves with pan/zoom, same reasoning as the player
-- marker.
function MinimapEngine:UpdateServiceIcons()
    local pts = self.SvcPts
    if not pts or #pts == 0 then
        self:HideServiceFrames()
        return
    end

    if #self.SvcFrms < #pts then
        for n = #self.SvcFrms + 1, #pts do
            self.SvcFrms[n] = self:CreateMiniFrame()
        end
    end

    local level = (self.Frm:GetFrameLevel() or 1) + 5
    for i, pt in ipairs(pts) do
        local frm = self.SvcFrms[i]
        if frm.svcTex ~= pt.tex then
            frm.texture:SetTexture(pt.tex)
            frm.svcTex = pt.tex
        end
        if self:ClipFrameW(frm, pt.x, pt.y, SERVICE_ICON_SIZE, SERVICE_ICON_SIZE) then
            frm:SetFrameLevel(level)
        end
    end
    for n = #pts + 1, #self.SvcFrms do
        self.SvcFrms[n]:Hide()
    end
end

---------------------------------------------------------------------------------------
-- Build-order step 9c (2026-11-10): quest turn-in markers. User asked
-- for "quest [icons] working" after step 9b landed - investigated
-- Carbonite.Quests' own MapIcons.lua (a separate, already-installed
-- addon on this same server) before writing anything, since it's a
-- large, real, already-working implementation of exactly this problem
-- for Carbonite's own map. Two real findings shaped what's below:
--
-- 1. A "brand new available quest at an NPC I haven't talked to yet"
--    marker (the yellow ! Carbonite's own QuestPin.lua/ICONS.giver
--    represents) needs a static NPC-to-quest database - this addon
--    has none, and the one already installed on this server
--    (QuestieDB, via its public LibQuestieDB contract) stores spawn
--    zones by legacy AreaID, not the uiMapID this engine uses
--    everywhere else. Converting between the two turned out to
--    require Questie's own PRIVATE, undocumented ZoneDB module (confirmed
--    by reading Questie's own QuestiePlayer:GetCurrentZoneId, which
--    depends on it too) - not a stable public contract, and a real
--    scope step up from anything built this session. Deliberately NOT
--    built - deferred, not forgotten.
-- 2. A "where do I turn in/continue the quests already in my log"
--    marker needs none of that: C_QuestLog.GetQuestsOnMap(mapID) is a
--    live, standard Blizzard API with no external database at all
--    (confirmed real and current via Carbonite.Quests' own
--    MapIcons.lua, which uses this exact call as its primary feed).
--    That's what this section builds - the smaller, immediately
--    achievable half of "quest icons," not the full system.
--
-- Position convention matches the flight-master branch above:
-- GetQuestsOnMap's x/y are 0-1 normalized (same family as
-- C_TaxiMap/C_Map.GetPlayerMapPosition), so *100 for GetWorldPos's
-- 0-100 convention.
---------------------------------------------------------------------------------------

local QUEST_ICON_SIZE = 16
-- Same texture Carbonite's own QuestPin.lua (ICONS.turnin) uses for a
-- quest ready to hand in - a real, long-standing Blizzard path (the
-- GossipFrame's own quest-icon art), not guessed.
local QUEST_TURNIN_TEX = "Interface\\GossipFrame\\ActiveQuestIcon"

function MinimapEngine:HideQuestFrames()
    for i = 1, #self.QuestFrms do
        self.QuestFrms[i]:Hide()
    end
end

-- Only shows quests already in the player's log that are flagged
-- complete (ready to turn in) - see this section's header for why an
-- in-progress objective marker isn't included in this first pass.
-- Called on zone change (RefreshCurrentZone) and on a time throttle
-- from Update() below, since quest state (unlike the static mailbox/
-- innkeeper data) can change without a zone change at all.
function MinimapEngine:RefreshQuestIcons()
    local pts = {}
    self.QuestPts = pts
    local mapId = self.MapId
    if not mapId or not C_QuestLog or not C_QuestLog.GetQuestsOnMap then return end

    local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapId)
    if not ok or type(quests) ~= "table" then return end

    for _, info in ipairs(quests) do
        local questID = info and info.questID
        if questID and type(info.x) == "number" and type(info.y) == "number" then
            local completeOk, complete = pcall(C_QuestLog.IsComplete, questID)
            if completeOk and complete then
                local wx, wy = self:GetWorldPos(mapId, info.x * 100, info.y * 100)
                if wx then
                    pts[#pts + 1] = { x = wx, y = wy, tex = QUEST_TURNIN_TEX }
                end
            end
        end
    end
end

function MinimapEngine:UpdateQuestIcons()
    local pts = self.QuestPts
    if not pts or #pts == 0 then
        self:HideQuestFrames()
        return
    end

    if #self.QuestFrms < #pts then
        for n = #self.QuestFrms + 1, #pts do
            self.QuestFrms[n] = self:CreateMiniFrame()
        end
    end

    local level = (self.Frm:GetFrameLevel() or 1) + 6
    for i, pt in ipairs(pts) do
        local frm = self.QuestFrms[i]
        if frm.svcTex ~= pt.tex then
            frm.texture:SetTexture(pt.tex)
            frm.svcTex = pt.tex
        end
        if self:ClipFrameW(frm, pt.x, pt.y, QUEST_ICON_SIZE, QUEST_ICON_SIZE) then
            frm:SetFrameLevel(level)
        end
    end
    for n = #pts + 1, #self.QuestFrms do
        self.QuestFrms[n]:Hide()
    end
end

---------------------------------------------------------------------------------------
-- Build-order step 9e (2026-11-10, REWRITTEN AGAIN same day): gathering
-- nodes (herb/mining/fish/treasure) - direct user request after the
-- quest/flight-master work above.
--
-- First version (this one) ported a static Wowhead data dump into this
-- addon's own files. Rewritten to read GatherMate2's own live database
-- directly instead, after the user copied their real GatherMate2
-- install + its own collected data into the dev tree and saw doubled-
-- up markers at one node (two independent sources disagreeing by a few
-- feet on the same real spot). That GatherMate2 integration went
-- through 8 rounds chasing a recurring "GatherMate2 has been blocked
-- from an action only available to the Blizzard UI" taint popup -
-- including removing this addon's entire live-Blizzard-widget-blend
-- mechanism ("Mode: Live") on the strong, evidence-backed suspicion it
-- was the cause - which did NOT resolve it. Further isolating tests
-- (stubbing this feature's own GatherMate2 calls entirely; stubbing
-- NativeMinimapHide; stubbing MinimapDock) each failed to make the
-- popup go away either, while disabling AlchemyGPS entirely did -
-- meaning something about this addon's mere presence in the addon list
-- triggers a pre-existing GatherMate2 bug on this server build, not
-- anything traced to a specific line of our own code. Rather than keep
-- chasing an unreproducible-by-isolation bug, user's call: drop the
-- GatherMate2 integration entirely and go back to this static-data
-- approach - doubled-up markers are a non-issue once GatherMate2 isn't
-- also running its own pins at the same time.
--
-- Data source: GatherMate2_Data's own "Forever"-flavor pack (the
-- standalone, non-Carbonite data addon already on this server -
-- confirmed via its own .toc, `## Interface: 16001`, tailored
-- specifically to this server) for Herb/Mining/Treasure, ported
-- verbatim into Map/Data/Gather{Herb,Mining,Treasure}.lua with just
-- the global table renamed (AlchemyGPS* instead of GatherMateData2*,
-- so it can never collide with GatherMate2's own identically-shaped
-- globals if that addon is also loaded). The Forever pack's own
-- FishData.lua is empty, so Map/Data/GatherFish.lua instead ports
-- Carbonite.Gathermate2_Data's broader "camelot" pack's FishData.lua -
-- same zone-key convention (uiMapID, already confirmed project-wide),
-- just not curated specifically for this one server.
--
-- Coordinate decode is inlined from GatherMate2's own real
-- `GatherMate:DecodeLoc` (GatherMate2.lua:685, `floor(id/1000000)/10000,
-- floor(id % 1000000 / 100)/10000`) - not reimplemented from scratch,
-- since this data was generated in exactly that packed encoding to be
-- importable into GatherMate2's own database.
--
-- Icons are the same guaranteed-present Blizzard profession-spell
-- textures used throughout this addon's history for this feature
-- (Trade_Herbalism/Trade_Mining/Trade_Fishing + a generic bag icon for
-- treasure) - one per category, not per-species, so this carries zero
-- dependency on GatherMate2 (or anything else) for icons to render.
--
-- "Active right now" investigated and NOT solved live, same day:
-- checked Carbonite's own real GatherPin.lua (Modules/Map/Pins/
-- GatherPin.lua) - it only ever draws the static database, gated by
-- zoom scale and gather-skill cap, no live presence check at all.
-- Live-tested two real candidate APIs with the user standing at an
-- actual visible node: C_VignetteInfo.GetVignettes() returned 0 (not
-- how this server surfaces gathering nodes), and scanning Minimap's
-- own child region textures returned ~290 children, most of which are
-- clearly some other addon's minimap-skin decoration, not blips - too
-- noisy to isolate the real one without a much larger diff-based
-- investigation. Neither GatherMate2 nor Carbonite's own mature,
-- long-iterated addons do live detection either - real evidence no
-- clean client API exists for "is a resource node here right now"
-- beyond normal engine visibility range (the same reason the native
-- yellow blips only show once you're close).
--
-- Decision (user's own call after being told the above): ship a
-- proximity APPROXIMATION instead of true live confirmation - a
-- known point renders brighter/full-alpha once the player is within
-- GATHER_NEARBY_RANGE of it, dimmed otherwise. This is NOT a claim
-- the node is actually there - it's "close enough that it's worth
-- walking over and looking", clearly distinct from the quest/flight-
-- master icons elsewhere in this file which only ever show confirmed,
-- API-backed state.
--
-- Profession gating (user's own call): herb nodes only show if the
-- player knows Herbalism, mining only if Mining, fishing pools only if
-- the player has any Fishing skill. Treasure is NOT gated - it's a
-- plain world chest/loot spawn, not tied to any profession.
---------------------------------------------------------------------------------------

-- Base size before the right-click menu's size slider (self.
-- GatherIconScale) multiplies it - bumped 10 -> 12 same day as the
-- visibility pass below, user-reported "can barely see them" even at
-- max opacity.
local GATHER_ICON_SIZE = 12
-- World-position units (the same space GetWorldPos/ClipFrameW already
-- work in, not real yards) - tuned by eye, not measured. Adjust after
-- live testing if "nearby" triggers too early or too late.
local GATHER_NEARBY_RANGE = 3
local GATHER_NEARBY_RANGE_SQ = GATHER_NEARBY_RANGE * GATHER_NEARBY_RANGE
-- Was 0.45 - raised 2026-11-10 (same "can barely see them" report).
-- 0.45 meant a non-near icon was still only ~45% opaque even with the
-- opacity slider (MapContextMenu.lua) maxed at 100%, which is most of
-- what's actually on screen at once (GATHER_NEARBY_RANGE above is
-- small, so "near" is the exception, not the rule, for anything
-- visible at a normal zoom level). This is now just a subtle
-- closer-is-brighter cue, not the dominant factor in whether an icon
-- is visible at all.
local GATHER_DIM_ALPHA = 0.85
-- Backdrop halo behind each icon for contrast against busy map art
-- (same "anything else to make these more visible" ask). Tightened
-- 2026-11-10 (user: "a little 2 big... make it hug tight with only a
-- couple pixel padding") from a proportional 20%-of-size pad to a flat
-- 2px on every side, regardless of the size slider.
local GATHER_BACKDROP_PAD = 2
-- Default for the new backdrop-opacity slider (MapContextMenu.lua row
-- 4) - same value the old hardcoded GATHER_BACKDROP_ALPHA_MULT used,
-- so today's look doesn't change until the user actually touches the
-- new slider.
local DEFAULT_GATHER_BACKDROP_OPACITY = 0.7

-- Fallback only now (build-order step 9f replaced the per-category
-- generic icon with the real per-species one from GatherNodeInfo.lua
-- below) - used when a node ID has no entry there at all, so an
-- unrecognized/future node type degrades to "some icon" instead of
-- rendering blank.
local GATHER_ICON_TEX = {
    Herb     = "Interface\\Icons\\Trade_Herbalism",
    Mine     = "Interface\\Icons\\Trade_Mining",
    Fish     = "Interface\\Icons\\Trade_Fishing",
    Treasure = "Interface\\Icons\\INV_Misc_Bag_10",
}

-- Build-order step 9f: per-species name/icon/required-skill-level
-- data (Map/Data/GatherNodeInfo.lua) - see that file's own header for
-- sourcing/scope. [dbType][nodeID] = { name=, level=(Herb/Mine only), tex= }.
local GATHER_NODE_INFO = _G.AlchemyGPSGatherNodeInfo

-- Standard WoW profession-difficulty coloring (orange = at/near the
-- skill floor, best skill-up odds; yellow/green = easier as current
-- skill climbs further past it; red = below the floor, can't harvest
-- at all). Gold replaces WoW's usual gray for Fish/Treasure, which
-- have no `level` at all (see GatherNodeInfo.lua's header) - explicit
-- user direction, not a WoW convention.
-- Returns r, g, b, cantHarvest (boolean, only true for red).
local function GatherNodeColor(info, curSkill)
    if not info or not info.level then
        return 1, 0.82, 0, false
    end
    if not curSkill or curSkill < info.level then
        return 1, 0.1, 0.1, true
    end
    local over = curSkill - info.level
    if over <= 25 then
        return 1, 0.5, 0.25, false
    elseif over <= 75 then
        return 1, 1, 0, false
    else
        return 0.1, 1, 0.1, false
    end
end

-- Hover-time only (cheap, infrequent) rather than threaded through
-- RefreshGatherIcons's point list, so a profession skill-up between
-- zone changes still shows correctly without needing a re-scan.
local function GetCurrentGatherSkill(dbType)
    if dbType ~= "Herb" and dbType ~= "Mine" then return nil end
    local wantName = (dbType == "Herb") and "Herbalism" or "Mining"
    local p1, p2 = GetProfessions()
    for _, idx in ipairs({ p1, p2 }) do
        if idx then
            local name, _, skillLevel = GetProfessionInfo(idx)
            if name == wantName then return skillLevel end
        end
    end
    return nil
end

local function GatherFrameOnEnter(frm)
    local dbType, nodeID = frm.gatherDbType, frm.gatherNodeID
    if not dbType then return end
    local info = GATHER_NODE_INFO and GATHER_NODE_INFO[dbType] and GATHER_NODE_INFO[dbType][nodeID]
    local name = (info and info.name) or dbType
    local r, g, b, cantHarvest = GatherNodeColor(info, GetCurrentGatherSkill(dbType))

    local label
    if info and info.level then
        if cantHarvest then
            label = string.format("%s (%d - can't harvest)", name, info.level)
        else
            label = string.format("%s (%d)", name, info.level)
        end
    else
        label = name
    end

    GameTooltip:SetOwner(frm, "ANCHOR_CURSOR")
    GameTooltip:SetText(label, r, g, b)
    GameTooltip:Show()
end

local function GatherFrameOnLeave()
    GameTooltip:Hide()
end

-- This feature's own static data tables (Map/Data/Gather*.lua),
-- keyed by this engine's own dbType short names. Each table is
-- [uiMapID] = { [packedCoord] = nodeID }, GatherMate2's own encoding
-- (see this section's header) - nodeID now also feeds the per-species
-- icon/name/level lookup above.
local GATHER_DB = {
    Herb     = _G.AlchemyGPSHerbDB,
    Mine     = _G.AlchemyGPSMineDB,
    Fish     = _G.AlchemyGPSFishDB,
    Treasure = _G.AlchemyGPSTreasureDB,
}

-- Inlined from GatherMate2's own GatherMate:DecodeLoc (GatherMate2.lua
-- :685) - see this section's header comment.
local function DecodeGatherCoord(coord)
    return math.floor(coord / 1000000) / 10000, math.floor(coord % 1000000 / 100) / 10000
end

local function GetKnownGatherProfessions()
    local known = {}
    local p1, p2, _, fishing = GetProfessions()
    for _, idx in ipairs({ p1, p2 }) do
        if idx then
            local name = GetProfessionInfo(idx)
            if name == "Herbalism" then known.Herb = true end
            if name == "Mining" then known.Mine = true end
        end
    end
    if fishing then known.Fish = true end
    return known
end

function MinimapEngine:HideGatherFrames()
    for i = 1, #self.GatherFrms do
        self.GatherFrms[i]:Hide()
        -- backdrop (build-order step 9h) is a sibling frame, not a
        -- child texture of GatherFrms[i] - hiding the icon frame no
        -- longer hides it automatically, so this needs its own call.
        self.GatherFrms[i].backdrop:Hide()
    end
end

-- Pcall-wrapped per dbType so one bad zone/type combo in the static
-- data can't abort the other three categories.
local function CollectGatherZoneNodes(engine, mapId, dbType, pts)
    local db = GATHER_DB[dbType]
    local zoneNodes = db and db[mapId]
    if not zoneNodes then return end

    local infoByID = GATHER_NODE_INFO and GATHER_NODE_INFO[dbType]
    local fallbackTex = GATHER_ICON_TEX[dbType]
    for coord, nodeID in pairs(zoneNodes) do
        local gx, gy = DecodeGatherCoord(coord)
        local wx, wy = engine:GetWorldPos(mapId, gx * 100, gy * 100)
        if wx then
            local info = infoByID and infoByID[nodeID]
            local tex = (info and info.tex) or fallbackTex
            pts[#pts + 1] = { x = wx, y = wy, tex = tex, dbType = dbType, nodeID = nodeID }
        end
    end
end

-- Rebuilds the full point list for the current zone - only needs to
-- run on zone change (and once at login via TakeOwnership's first
-- RefreshCurrentZone), not every tick, since this is static data. A
-- newly learned profession picks up its node type on the next zone
-- change or /reload, not instantly - acceptable, professions aren't
-- learned often.
function MinimapEngine:RefreshGatherIcons()
    local mapId = self.MapId
    local pts = {}
    self.GatherPts = pts
    if not mapId then return end

    local known = GetKnownGatherProfessions()
    local dbTypes = {}
    if known.Herb then dbTypes[#dbTypes + 1] = "Herb" end
    if known.Mine then dbTypes[#dbTypes + 1] = "Mine" end
    if known.Fish then dbTypes[#dbTypes + 1] = "Fish" end
    dbTypes[#dbTypes + 1] = "Treasure"

    for _, dbType in ipairs(dbTypes) do
        pcall(CollectGatherZoneNodes, self, mapId, dbType, pts)
    end
end

-- Repositioned on its own 0.1s throttle from Update() below, not
-- every tick - these are stationary world points, and a single zone
-- can carry 800+ of them (confirmed: Barrens herb data alone is 857
-- entries), so a 20Hz reposition pass the way the player marker gets
-- is needless cost. 10Hz is still visually smooth for something that
-- never moves.
function MinimapEngine:UpdateGatherIcons()
    local pts = self.GatherPts
    if not pts or #pts == 0 then
        self:HideGatherFrames()
        return
    end

    if #self.GatherFrms < #pts then
        for n = #self.GatherFrms + 1, #pts do
            local frm = self:CreateMiniFrame()
            frm:EnableMouse(true)
            frm:SetScript("OnEnter", GatherFrameOnEnter)
            frm:SetScript("OnLeave", GatherFrameOnLeave)
            -- Backdrop halo, a real frame (not a plain SetColorTexture
            -- square) so it can use BackdropTemplate's edge art for
            -- corner rounding. Uses the exact same backdrop recipe as
            -- the real map window's own chrome (AlchemyGPS.Skin:
            -- GetBackdrop(), UI/Skin.lua/UI/Window.lua:CreateBorders) -
            -- user asked for the rounding to match the map module's
            -- own corners, and reading the live table (not a hardcoded
            -- copy) means it keeps matching automatically if that skin
            -- ever changes. Fill/border stay plain black here (not the
            -- skin's own blue-gray tint) since this is still "the black
            -- box" from the opacity-slider request, not a themed panel.
            -- A sibling of frm (parented to self.Frm, not to frm)
            -- rather than a child texture, since BackdropTemplate
            -- frames don't layer the way CreateMiniFrame's plain
            -- textures do - its own frame LEVEL (set below, each pass)
            -- is what keeps it behind frm instead.
            frm.backdrop = CreateFrame("Frame", nil, self.Frm, "BackdropTemplate")
            frm.backdrop:SetBackdrop(AlchemyGPS.Skin:GetBackdrop())
            frm.backdrop:SetBackdropColor(0, 0, 0, 1)
            frm.backdrop:SetBackdropBorderColor(0, 0, 0, 1)
            self.GatherFrms[n] = frm
        end
    end

    local level = (self.Frm:GetFrameLevel() or 1) + 4
    local px, py = self.PlyrX, self.PlyrY
    local size = GATHER_ICON_SIZE * (self.GatherIconScale or 1)
    for i, pt in ipairs(pts) do
        local frm = self.GatherFrms[i]
        if frm.svcTex ~= pt.tex then
            frm.texture:SetTexture(pt.tex)
            frm.svcTex = pt.tex
        end
        frm.gatherDbType, frm.gatherNodeID = pt.dbType, pt.nodeID
        if self:ClipFrameW(frm, pt.x, pt.y, size, size) then
            frm:SetFrameLevel(level)
            local near = px and py
                and ((pt.x - px) ^ 2 + (pt.y - py) ^ 2) <= GATHER_NEARBY_RANGE_SQ
            local alpha = (near and 1 or GATHER_DIM_ALPHA) * (self.GatherOpacity or 1)
            frm.texture:SetAlpha(alpha)
            frm.backdrop:ClearAllPoints()
            frm.backdrop:SetPoint("TOPLEFT", frm, "TOPLEFT", -GATHER_BACKDROP_PAD, GATHER_BACKDROP_PAD)
            frm.backdrop:SetPoint("BOTTOMRIGHT", frm, "BOTTOMRIGHT", GATHER_BACKDROP_PAD, -GATHER_BACKDROP_PAD)
            frm.backdrop:SetFrameLevel(math.max(1, level - 1))
            frm.backdrop:SetAlpha(alpha * (self.GatherBackdropOpacity or DEFAULT_GATHER_BACKDROP_OPACITY))
            frm.backdrop:Show()
        else
            frm.backdrop:Hide()
        end
    end
    for n = #pts + 1, #self.GatherFrms do
        self.GatherFrms[n]:Hide()
        self.GatherFrms[n].backdrop:Hide()
    end
end

-- Trimmed from Nx.Map:UpdateWorld (MapEngine.lua:5945-6147) - see this
-- section's header for what's dropped and why. What's kept is the
-- real texture-fetch/assign core: resolve the art source mapID, fetch
-- its tile textures (with Carbonite's own real MoP-city-map legacy-art
-- fallback preserved), assign them into the TileFrms pool, and cache
-- the result so repeat calls (every Update() tick) are cheap once the
-- zone hasn't actually changed.
function MinimapEngine:UpdateWorldArt(mapId)
    if not mapId or mapId == 9000 then return end

    local winfo = self.MapWorldInfo[mapId]
    if winfo and winfo.BaseMap then
        winfo = self.MapWorldInfo[winfo.BaseMap]
    end
    winfo = winfo or {}

    local artMapID = self:GetArtSourceMapID(mapId)
    local mapArtID = (C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(artMapID)) or artMapID

    if self.CurWorldUpdateMapId == mapId and mapArtID == self.CurWorldUpdateArtID then
        return
    end

    if self.WorldArtRetryMapId == mapId and self.WorldArtRetryTime
        and GetTime() < self.WorldArtRetryTime then
        return
    end

    local texturesIDs = self:GetArtLayerTextures(artMapID, 1)

    -- Some MoP city maps are valid player maps but intentionally have no
    -- C_Map art assignment. Carbonite still ships the original 4x3 world-map
    -- textures for those cities - use them instead of leaving the previous
    -- zone's tile IDs in this shared frame pool.
    if (not texturesIDs or not texturesIDs[1]) and winfo.LegacyMapArt then
        local layers = self:GetArtLayers(artMapID)
        local layerInfo = layers and layers[1]
        local tilex = layerInfo and ceil(layerInfo.layerWidth / layerInfo.tileWidth) or winfo.TileX or 4
        local tiley = layerInfo and ceil(layerInfo.layerHeight / layerInfo.tileHeight) or winfo.TileY or 3
        local legacyBase = "Interface\\WorldMap\\" .. winfo.LegacyMapArt .. "\\" .. winfo.LegacyMapArt
        texturesIDs = {}
        for tileIndex = 1, tilex * tiley do
            texturesIDs[tileIndex] = legacyBase .. tileIndex
        end
    end

    if not texturesIDs or not texturesIDs[1] then
        self:HideZoneTileFrames(self.TileFrms, true)
        -- Do not cache a failed art request - Blizzard can populate map art
        -- after loading/phase changes, and the next update must retry it.
        self.CurWorldUpdateMapId = nil
        self.CurWorldUpdateArtID = nil
        self.WorldArtRetryMapId = mapId
        self.WorldArtRetryTime = GetTime() + 1
        return
    end

    local numtiles = min(#texturesIDs, 150)
    for i = 1, numtiles do
        if self.TileFrms[i] and self.TileFrms[i].texture then
            self.TileFrms[i].texture:SetTexture(texturesIDs[i])
            if self.TileFrms[i].texture.SetSnapToPixelGrid then
                self.TileFrms[i].texture:SetSnapToPixelGrid(false)
                self.TileFrms[i].texture:SetTexelSnappingBias(0)
            end
        end
    end
    for tileIndex = numtiles + 1, 150 do
        local frm = self.TileFrms[tileIndex]
        if frm then
            frm:Hide()
            if frm.texture then frm.texture:SetTexture(nil) end
        end
    end

    -- Commit the cache only after the requested art was installed - caching
    -- a nil texture response is what previously made a random old zone
    -- persist (same reasoning as the real source's own comment).
    self.CurWorldUpdateMapId = mapId
    self.CurWorldUpdateArtID = mapArtID
    self.CurWorldTileCount = numtiles
    self.WorldArtRetryMapId = nil
    self.WorldArtRetryTime = nil
end

---------------------------------------------------------------------------------------
-- "What map should we show" - new glue, not a direct port (see this
-- section's header on why Nx.Map:UpdateWorld's own orchestration isn't
-- ported). Built from the same real, live primitives Carbonite's own
-- MapIDs.lua exposes.
---------------------------------------------------------------------------------------

-- Trimmed from Carbonite/Modules/Map/MapIDs.lua's CanonicalizeMapID
-- (:34-63) - drops the per-mapID alias result cache (a table that
-- never shrinks across a whole session; this addon's MapWorldInfo is
-- far smaller than real Carbonite's full multi-flavor catalog, so the
-- lookup below is cheap enough uncached).
function MinimapEngine:CanonicalizeMapID(mapID)
    if not mapID or mapID == 0 then return mapID end
    local worldInfo = self.MapWorldInfo
    if not worldInfo then return mapID end
    for canonicalID, info in pairs(worldInfo) do
        local aliases = info and info.PlayerMapID
        if aliases == mapID then
            return canonicalID
        elseif type(aliases) == "table" then
            for _, aliasID in pairs(aliases) do
                if aliasID == mapID then return canonicalID end
            end
        end
    end
    return mapID
end

-- Trimmed from Carbonite/Modules/Map/MapIDs.lua's
-- GetDisplayableMapForPlayer (:218-233) - drops GetPlayerInstanceMapID's
-- instance-floor disambiguation (instances/dungeons are an explicit
-- non-goal per the plan) and the Classic old-MapID 1414/1415
-- translation (Nx.OldMapIDs, not applicable to this client).
function MinimapEngine:GetDisplayableMapForPlayer()
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local displayableMapID = rawMapID or 0
    if MapUtil and MapUtil.GetDisplayableMapForPlayer then
        local ok, mapID = pcall(MapUtil.GetDisplayableMapForPlayer)
        if ok and mapID then displayableMapID = mapID end
    end
    return self:CanonicalizeMapID(displayableMapID) or 0
end

-- New: the real Nx.Map:IsNormalMap's own membership-search pattern
-- (MapEngine.lua:14676-14685), repurposed to answer "which continent"
-- instead of "is this map in the catalog at all" - MapWorldInfo rows
-- don't carry a `.Cont` field of their own (see Map\Data\NxMapData.lua's
-- header); continent membership lives in MapZones[1..ContCnt] instead.
function MinimapEngine:FindContinent(mapId)
    for cont = 1, self.ContCnt or 0 do
        local list = self.MapZones and self.MapZones[cont]
        if list then
            for _, zoneId in ipairs(list) do
                if zoneId == mapId then return cont end
            end
        end
    end
    return nil
end

-- New: detects a zone change and reacts - recompute Cont/Zone, and pan
-- (not snap) to the new zone's anchor so the view starts somewhere
-- sane instead of wherever the OLD zone's coordinates would leave it.
-- Cheap to call every Update() tick (the mapId == self.MapId check
-- below is the only work done once nothing has actually changed).
function MinimapEngine:RefreshCurrentZone()
    local mapId = self:GetDisplayableMapForPlayer()
    if not mapId or mapId == 0 or mapId == self.MapId then return end

    local cont = self:FindContinent(mapId)
    self.MapId = mapId
    self.Cont = cont
    self.Zone = cont and mapId or nil

    -- Build-order step 9b: static service icons (mailbox/innkeeper/
    -- flight master) are per-mapID, so they only need resolving here,
    -- not every tick - see RefreshServiceIcons' own header comment.
    self:RefreshServiceIcons()

    -- Build-order step 9c: quest turn-in markers get their own
    -- immediate refresh on zone entry too (a stale list from the
    -- PREVIOUS zone would otherwise linger up to the throttle
    -- interval below) - see RefreshQuestIcons' own header comment.
    self:RefreshQuestIcons()

    -- Build-order step 9e: the gathering-node field is per-mapID
    -- static data (same as service icons above), so it only needs
    -- rebuilding here, not every tick - see RefreshGatherIcons' own
    -- header comment.
    self:RefreshGatherIcons()

    if not cont then
        -- Not in Carbonite's static catalog for this flavor (an
        -- instance/dungeon, or Forever-custom content) - nothing to
        -- draw; leave the tile pool clean rather than showing stale
        -- art from whatever zone we were in before.
        self:HideZoneTileFrames(self.TileFrms, true)
        self.CurWorldUpdateMapId = nil
        return
    end

    -- Pans to the zone's CENTER, not GetWorldZoneInfo's own x,y (its
    -- zone's top-left world anchor, used as MoveZoneTiles' tile(0,0)
    -- origin - see that function). Confirmed 2026-11-09 against a live
    -- screenshot showing most of the window blank with only a sliver
    -- of real terrain art in the bottom-right corner: panning to the
    -- raw anchor put that corner at screen-center instead of the
    -- zone's middle, pushing ~3/4 of the tile grid off-window. Fixed
    -- by re-deriving from the real source's own "center on zone"
    -- function, Nx.Map:CenterMap (MapEngine.lua:14576-14607), which
    -- calls `self:GetWorldPos(mapId, 50, 50)` - GetWorldPos
    -- (:15047-15068) resolves 50/50 (the 0-100 percentage-of-zone
    -- convention) to `anchorX + 50*winfo.Scale, anchorY + 50*winfo.Scale/1.5`,
    -- i.e. exactly `x + zw/2, y + zh/2` in this function's own
    -- GetWorldZoneInfo return values.
    local _, x, y, zw, zh = self:GetWorldZoneInfo(cont, mapId)
    local ZoomController = AlchemyGPS.Modules.Map.ZoomController
    if ZoomController and x then
        ZoomController:Move(x + zw / 2, y + zh / 2, nil, 15)
    end
end

---------------------------------------------------------------------------------------
-- Build-order step 5: mouse-wheel zoom, centered on the cursor.
-- Ported from Nx.Map:MouseWheel (MapEngine.lua:5172) via its frame-
-- script wrapper Nx.Map:OnMouseWheel (:5163), wired directly to our
-- content frame's OnMouseWheel script in TakeOwnership instead of
-- going through that indirection (we have one map instance, not a
-- frame->self.NxMap lookup). Dropped, not approximated:
--   - the instance/BG-map NXInstanceMaps skip (no instance-canvas
--     concept until step 8)
--   - the "hovering the docked minimap" branch that adjusts
--     Nx.db.profile.MiniMap.DockZoom (this project has no docked-vs-
--     undocked distinction - our window IS the undocked map)
--   - the View3D/Unproject3D branch (3D view is an explicit non-goal)
-- PadX doesn't exist here (our content frame has no padding, unlike
-- Carbonite's legacy Frm - same reasoning as TitleH=0 in TakeOwnership).
---------------------------------------------------------------------------------------

function MinimapEngine:MouseWheel(value)
    local frm = self.Frm
    -- MapW/H are only populated once Update()'s own timer has ticked
    -- at least once; guard the narrow window-just-opened race instead
    -- of risking a nil-arithmetic error on an immediate scroll.
    if not frm or not self.MapW or not self.MapH then return end

    local x, y = GetCursorPosition()
    x = x / frm:GetEffectiveScale()
    y = y / frm:GetEffectiveScale()

    local left = frm:GetLeft()
    local top = frm:GetTop()
    if not left or not top then return end

    -- World position under the cursor before zoom.
    local fx, fy = x - left, top - y
    local ox = self.MapPosX + (fx - self.MapW / 2) / self.Scale
    local oy = self.MapPosY + (fy - self.TitleH - self.MapH / 2) / self.Scale

    local ScrollScale = AlchemyGPS.Modules.Map.ScrollScale
    if not ScrollScale then return end
    self.Scale = ScrollScale:Compute(self.Scale, value)
    self.StepTime = 10

    -- World position under the cursor after zoom.
    local nx = self.MapPosX + (fx - self.MapW / 2) / self.Scale
    local ny = self.MapPosY + (fy - self.TitleH - self.MapH / 2) / self.Scale

    -- Keep the world point under the cursor fixed on screen.
    self.MapPosX = self.MapPosX + ox - nx
    self.MapPosY = self.MapPosY + oy - ny
end

---------------------------------------------------------------------------------------
-- Build-order step 6: pan-drag. Ported from Nx.Map:OnMouseDown
-- (MapEngine.lua:4982) and Nx.Map:OnMouseUp (:5129) - left-button-
-- drag half only. See TakeOwnership's wiring comment for what's
-- dropped and why.
---------------------------------------------------------------------------------------

function MinimapEngine:OnMouseDown(button)
    if button ~= "LeftButton" then return end

    -- Deterministic close on top of MapContextMenu's own outside-
    -- click poll: a left-click on the map window itself starts a pan-
    -- drag below, which should always dismiss the menu first rather
    -- than drag underneath it.
    local MapContextMenu = AlchemyGPS.Modules.Map.MapContextMenu
    if MapContextMenu and MapContextMenu:IsShown() then
        MapContextMenu:Close()
    end

    local frm = self.Frm
    if not frm then return end

    local x, y = GetCursorPosition()
    x = x / frm:GetEffectiveScale()
    y = y / frm:GetEffectiveScale()

    self.LClickTime = GetTime()
    self.Scrolling = true
    self.ScrollingX = x
    self.ScrollingY = y
end

function MinimapEngine:OnMouseUp(button)
    if button == "LeftButton" then
        self.Scrolling = false
    elseif button == "RightButton" then
        -- New, not a port - Carbonite's own right-click menu
        -- (Nx.Menu, Modules/UI/UIEngine.lua) is thousands of lines
        -- tied to its full options schema; see MapContextMenu.lua's
        -- header for why this addon builds its own small popup
        -- instead of porting that. Toggle, not unconditional open -
        -- right-clicking the map again to dismiss (the same action
        -- that opened it) is the natural way to close it, same as
        -- the left-click/outside-click close MapContextMenu's own
        -- OnUpdate handles.
        local MapContextMenu = AlchemyGPS.Modules.Map.MapContextMenu
        if MapContextMenu then
            if MapContextMenu:IsShown() then
                MapContextMenu:Close()
            else
                MapContextMenu:Open()
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- New, much-trimmed replacement for Nx.Map:MinimapUpdate +
-- MinimapUpdateEnd combined. Keeps only: try each preset size
-- (biggest first), blend the widget if one fits, otherwise hide it.
-- No dock-position/instance/BG/garrison/indoor-auto-toggle/menu-
-- checkbox logic - none of that is part of this project's feature
-- list, and none of it is approximated here, just not ported.
---------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------
-- Diagnostic overlay, originally built for the build-order step 4
-- live-widget-blend bug (mask renders, terrain stays blank). Kept as
-- a permanent debug aid rather than torn out - shown/hidden by the
-- Settings window's "Debug mode" checkbox (Core/Logger.lua's
-- Logger.minLevel), not always-on.
---------------------------------------------------------------------------------------

local debugFrm, debugText

-- Where the user last dragged this to, saved across /reload. Lives on
-- the root AceDB profile table (AlchemyGPS.db.profile) rather than a
-- module's own DB, since this overlay isn't a registered Module - see
-- Core/SavedVariables.lua's bind() for what that table is. Always
-- available by the time this overlay is first created (lazily, on the
-- first debug-overlay update after the map window has been opened at
-- least once), well after the PLAYER_LOGIN that creates it.
local function saveDebugOverlayPosition()
    if not (AlchemyGPS.db and AlchemyGPS.db.profile) then return end
    local point, _, relPoint, x, y = debugFrm:GetPoint()
    if not point then return end
    AlchemyGPS.db.profile.DebugOverlay = { point = point, relPoint = relPoint, x = x, y = y }
end

local function ensureDebugOverlay()
    if debugFrm then return end
    debugFrm = CreateFrame("Frame", "AlchemyGPSMapDebug", UIParent, "BackdropTemplate")
    debugFrm:SetSize(520, 260)

    local saved = AlchemyGPS.db and AlchemyGPS.db.profile and AlchemyGPS.db.profile.DebugOverlay
    if saved and saved.point and saved.x and saved.y then
        debugFrm:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x, saved.y)
    else
        debugFrm:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
    end

    debugFrm:SetFrameStrata("TOOLTIP")
    debugFrm:SetBackdrop({
        bgFile = "Interface\\Buttons\\White8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 9, edgeSize = 9,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    debugFrm:SetBackdropColor(0, 0, 0, 0.85)

    -- Movable so it can be dragged off whatever it's overlapping
    -- (e.g. the minimap window's own default top-left spawn point).
    -- Position is saved back to the profile on every drag stop so it
    -- comes back in the same spot after a /reload instead of
    -- snapping back to the top-left default every time.
    debugFrm:SetMovable(true)
    debugFrm:EnableMouse(true)
    debugFrm:RegisterForDrag("LeftButton")
    debugFrm:SetScript("OnDragStart", debugFrm.StartMoving)
    debugFrm:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveDebugOverlayPosition()
    end)

    debugText = debugFrm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debugText:SetPoint("TOPLEFT", 6, -6)
    debugText:SetPoint("BOTTOMRIGHT", -6, 6)
    debugText:SetJustifyH("LEFT")
    debugText:SetJustifyV("TOP")
    debugText:SetWordWrap(true)
end

function MinimapEngine:UpdateDebugOverlay()
    -- Tied to the same Debug mode flag the Settings window's checkbox
    -- and the `/gps debug` slash command both already drive
    -- (Core/Logger.lua's Logger.minLevel) - whichever one last
    -- toggled it, this just reads the same place, so there's nothing
    -- extra to keep in sync. Off hides (and stops updating) the
    -- overlay entirely instead of just dimming it, matching "off
    -- turns them both off."
    local Logger = AlchemyGPS.Core.Logger
    if Logger.minLevel ~= Logger.LEVEL.DEBUG then
        if debugFrm then debugFrm:Hide() end
        return
    end

    ensureDebugOverlay()
    debugFrm:Show()

    -- MMFrm-specific diagnostics (live-widget parent/mask/zoom state)
    -- dropped along with the whole live-widget-ownership mechanism this
    -- addon used to carry - see MinimapWindow.lua's SetMode removal,
    -- same day. Everything below is tile-mode-only state.
    local lines = {}
    tinsert(lines, ("MapW=%s MapH=%s"):format(tostring(self.MapW), tostring(self.MapH)))
    tinsert(lines, ("Scale=%s ScaleDraw=%s StepTime=%s"):format(
        tostring(self.Scale), tostring(self.ScaleDraw), tostring(self.StepTime)))
    tinsert(lines, ("MapPosX=%s MapPosY=%s MapPosXDraw=%s MapPosYDraw=%s"):format(
        tostring(self.MapPosX), tostring(self.MapPosY), tostring(self.MapPosXDraw), tostring(self.MapPosYDraw)))
    tinsert(lines, ("Scrolling=%s Ttl=%s"):format(tostring(self.Scrolling), tostring(self.Ttl)))
    tinsert(lines, ("MapId=%s Cont=%s Zone=%s CurWorldUpdateMapId=%s tiles=%s"):format(
        tostring(self.MapId), tostring(self.Cont), tostring(self.Zone),
        tostring(self.CurWorldUpdateMapId), tostring(self.CurWorldTileCount)))
    tinsert(lines, ("PlyrX=%s PlyrY=%s PlyrDir=%s"):format(
        tostring(self.PlyrX), tostring(self.PlyrY), tostring(self.PlyrDir)))

    debugText:SetText(table.concat(lines, "\n"))
end

function MinimapEngine:Update(elapsed)
    if not self.Frm then return end

    -- Throttle update rate - ported from Nx.Map.OnUpdate's own ttl
    -- accumulator (MapEngine.lua:5503-5509: "ttl = ttl + elapsed; if
    -- ttl < (Nx.db.profile.Map.mapUpdate or .05) then return end").
    -- This project has no mapUpdate option, so just the fixed .05
    -- default. Build-order step 5 drove this from a 0.1s AceTimer
    -- (MinimapWindow.lua) instead of a real per-frame OnUpdate script
    -- - half the real cadence, plus a timer's own scheduling jitter on
    -- top - and is the most likely cause of zoom/pan reading "buggy,
    -- not smooth" in that step's live testing. MinimapWindow.lua now
    -- drives Update() from the content frame's own OnUpdate script
    -- (matching MapEngine.lua:1709's f:SetScript("OnUpdate", ...)), so
    -- `elapsed` here is accurate per-frame time, and this throttle is
    -- the only thing capping the real work, exactly like the original.
    self.Ttl = (self.Ttl or 0) + (elapsed or 0)
    if self.Ttl < 0.05 then return end
    self.Ttl = 0

    -- Build-order step 6: apply an active drag. Ported verbatim from
    -- Nx.Map:OnUpdate's own "Scroll map with mouse" block
    -- (MapEngine.lua:5589-5623) - runs before the zoom/pan animation
    -- block below, same ordering as the real source, so a drag always
    -- wins over any in-flight zoom animation that tick: it forces
    -- MapPosX/Y AND Scale to immediately match the dragged
    -- ScaleDraw/MapPos*Draw, leaving the interpolation block below
    -- nothing to do (diff already 0) while actively dragging.
    if self.Scrolling then
        local cx, cy = GetCursorPosition()
        cx = cx / self.Frm:GetEffectiveScale()
        cy = cy / self.Frm:GetEffectiveScale()
        local dx = cx - self.ScrollingX
        local dy = cy - self.ScrollingY

        if dx ~= 0 or dy ~= 0 then
            self.LClickTime = 0
        end

        self.ScrollingX = cx
        self.ScrollingY = cy

        local mx = dx / self.ScaleDraw
        local my = dy / self.ScaleDraw
        self.MapPosXDraw = self.MapPosXDraw - mx
        self.MapPosYDraw = self.MapPosYDraw + my

        self.MapPosX = self.MapPosXDraw
        self.MapPosY = self.MapPosYDraw
        self.Scale = self.ScaleDraw
    end

    -- Build-order step 5: animate ScaleDraw/MapPosXDraw/Y toward
    -- Scale/MapPosX/Y. Ported verbatim from Nx.Map:Update's own
    -- "Adjust draw scale and position" block (MapEngine.lua:6734) -
    -- the exact per-tick stepping ZoomController's Move/ScrollSteps
    -- rely on to produce a smooth zoom instead of an instant snap.
    -- Works in inverse-scale space (ScaleDrawW/ScaleW) because that's
    -- what makes the snap threshold below (inverse-scale gap < 0.01)
    -- meaningful - zoomed-in scale differences of 1.0 feel huge while
    -- zoomed-out differences of 1.0 are imperceptible, and 1/scale
    -- flattens that disparity.
    local scaleDiff = math.abs(self.ScaleDraw - self.Scale)
    local xDiff = self.MapPosXDraw - self.MapPosX
    local yDiff = self.MapPosYDraw - self.MapPosY

    if self.StepTime ~= 0 and (scaleDiff > 0 or xDiff ~= 0 or yDiff ~= 0) then
        if self.StepTime > 0 then
            self.StepTime = -self.StepTime
            self.ScaleDrawW = 1 / self.ScaleDraw
            self.ScaleW = 1 / self.Scale
        end

        local st = -self.StepTime

        self.MapPosXDraw = Nx.Util_StepValue(self.MapPosXDraw, self.MapPosX, math.abs(xDiff) / st)
        self.MapPosYDraw = Nx.Util_StepValue(self.MapPosYDraw, self.MapPosY, math.abs(yDiff) / st)
        self.ScaleDrawW = Nx.Util_StepValue(self.ScaleDrawW, self.ScaleW, math.abs(self.ScaleDrawW - self.ScaleW) / st)
        self.ScaleDraw = 1 / self.ScaleDrawW

        self.StepTime = self.StepTime + 1
    end

    self.MapW = self.Frm:GetWidth()
    self.MapH = self.Frm:GetHeight()

    -- Build-order step 8: resolve/refresh the real world-art canvas.
    -- Both calls are cheap no-ops once the zone hasn't changed and its
    -- art is already fetched - see RefreshCurrentZone/UpdateWorldArt's
    -- own comments.
    self:RefreshCurrentZone()
    if self.Cont then
        self:UpdateWorldArt(self.MapId)

        -- Live player world position, replacing build-order step 4's
        -- fixed-at-canvas-center stand-in. Formula corrected 2026-11-09
        -- after a live screenshot showed the rendered art badly
        -- misplaced (see MoveCurZoneTiles/RefreshCurrentZone's fix the
        -- same day) - re-derived directly from the real source instead
        -- of guessing: Nx.Map's own per-frame player-position update
        -- (MapEngine.lua:6474-6476) calls
        -- self:GetWorldPos(mapId, plZX*100, plZY*100), and GetWorldPos
        -- (:15047-15068) resolves that to `winfo[4] + mapX*winfo.Scale,
        -- winfo[5] + mapY*winfo.Scale/1.5` - i.e. exactly
        -- `zx + px*zw, zy + py*zh` using this function's own zx/zy/zw/zh
        -- (winfo[4]/[5] are a cached copy of the same info.X+winfo.X
        -- anchor GetWorldZoneInfo computes live, confirmed via the real
        -- source's one-time fill at MapEngine.lua:14046-14047). No
        -- 0.5-recentering and no Y-flip in the real source - both were
        -- wrong guesses here (zx/zy are the zone's top-left world
        -- anchor, not its center, so subtracting 0.5 anchored the
        -- fractional position to the wrong corner; and
        -- GetPlayerMapPosition's 0..1 top-to-bottom Y already matches
        -- Carbonite's own world-Y-increases-south convention, so
        -- flipping it was backwards).
        local _, zx, zy, zw, zh = self:GetWorldZoneInfo(self.Cont, self.Zone)
        -- self.Cont guard added 2026-11-10: GetWorldZoneInfo's own
        -- "invalid cont/zone" fallback returns 0 for zx (not nil, see
        -- that function above) - 0 is truthy in Lua, so without this
        -- extra check this block was running anyway whenever the
        -- player stood somewhere not in the static zone catalog (a
        -- building interior, since indoor sub-zone IDs mostly aren't
        -- in Carbonite's camelot-flavor catalog - see NxMapData.lua's
        -- header on why its real GetZoneInfo/BuildMissingZoneInfo
        -- resolver is dead/unported here), computing PlyrX/PlyrY from
        -- that meaningless (0,0,1002,668) fallback rectangle instead
        -- of leaving them alone. The bogus result was wildly far from
        -- the last real outdoor position, so ZoomController:Move's own
        -- auto-follow (below) tried to animate the view there, and the
        -- live widget patch's ClipMMW fit check failed outright at
        -- that distance - confirmed live, 2026-11-10: walking into the
        -- Freewind Post inn made the live-widget patch disappear
        -- entirely instead of just freezing in place. Requiring
        -- self.Cont (nil whenever RefreshCurrentZone couldn't find the
        -- current map in the catalog) skips this whole block indoors,
        -- so PlyrX/PlyrY/the title/the live patch all simply freeze at
        -- their last good outdoor values instead of jumping to noise.
        -- This does NOT make the live widget track real indoor
        -- movement (that needs Carbonite's full zone/instance database
        -- - a separate, much bigger port, not attempted here) - it only
        -- stops the existing patch from vanishing while indoors.
        if self.Cont and zx then
            local pos = C_Map and C_Map.GetPlayerMapPosition
                and C_Map.GetPlayerMapPosition(self.MapId, "player")
            if pos then
                local px, py = pos:GetXY()
                local newX = zx + px * zw
                local newY = zy + py * zh
                self.PlyrRZX = px * 100
                self.PlyrRZY = py * 100

                -- Run speed %, ported from Nx.Map:Update (MapEngine.
                -- lua:6553-6569) - sampled on a real-time >0.5s gate
                -- (frame-to-frame position deltas are too noisy for a
                -- usable number) using the same 4.575 world-pixel-to-
                -- yard constant the real source's own cursor-distance
                -- tooltip uses (:5698) - this addon's PlyrX/PlyrY are
                -- in the identical GetWorldPos-derived scale (see this
                -- function's header comment above), so the constant
                -- carries over unchanged. Must run BEFORE self.PlyrX/Y
                -- below are overwritten - the real source's own
                -- "not moving?" check compares the freshly-resolved
                -- position against the PREVIOUS tick's self.PlyrX/Y.
                if newX == self.PlyrX and newY == self.PlyrY then
                    self.PlyrSpeed = 0
                    self.PlyrSpeedCalcTime = GetTime()
                    self.PlyrSpeedX, self.PlyrSpeedY = newX, newY
                elseif self.PlyrSpeedCalcTime then
                    local tmDif = GetTime() - self.PlyrSpeedCalcTime
                    if tmDif > .5 then
                        self.PlyrSpeed = ((newX - self.PlyrSpeedX) ^ 2 + (newY - self.PlyrSpeedY) ^ 2) ^ .5 * 4.575 / tmDif
                        self.PlyrSpeedCalcTime = GetTime()
                        self.PlyrSpeedX, self.PlyrSpeedY = newX, newY
                    end
                else
                    self.PlyrSpeedCalcTime = GetTime()
                    self.PlyrSpeedX, self.PlyrSpeedY = newX, newY
                end

                self.PlyrX = newX
                self.PlyrY = newY

                -- Build-order step 9a: facing, for the canvas player
                -- marker's rotation (UpdatePlayerMarker/ClipFrameW's
                -- :SetRotation call below). GetPlayerFacing() already
                -- returns radians, 0 = north - fed straight in, no
                -- sign correction (that was only needed for Carbonite's
                -- own legacy degrees-then-cos/sin formula, abandoned in
                -- favor of SetRotation - see ClipFrameW's own comment).
                -- Unverified as of 2026-11-10: if the marker turns out
                -- to rotate mirrored (backwards) rather than not at
                -- all, negate this one line rather than touching
                -- ClipFrameW again.
                self.PlyrDir = GetPlayerFacing() or 0

                -- Window title: zone name + live coordinates + run
                -- speed, same three pieces Nx.Map:OnUpdate's title
                -- line 1 shows (MapEngine.lua:5632-5671) - not the
                -- real source's own zone-database name lookup
                -- (map:IdToName, NxMapData.lua) or its subzone/cursor-
                -- position second title line (no mouse-hover tracking
                -- ported here), just the live Blizzard API's own zone
                -- name plus this function's own RZX/RZY/PlyrSpeed.
                if self.MapId ~= self._TitleMapId then
                    self._TitleMapId = self.MapId
                    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(self.MapId)
                    self._TitleZoneName = info and info.name or ""
                end

                local title = ("%s %4.1f, %4.1f"):format(
                    self._TitleZoneName or "", self.PlyrRZX, self.PlyrRZY)

                if self.PlyrSpeed and self.PlyrSpeed > 0 then
                    local speedPct = self.PlyrSpeed / 6.4 * 100 - 100
                    if math.abs(speedPct) < .5 then speedPct = 0 end
                    title = title .. (" |cffa0a0a0Speed%+.0f%%"):format(speedPct)
                end

                self.Win:SetTitle(title)

                -- Trimmed from Nx.Map:Update's own continuous auto-
                -- follow (MapEngine.lua:6625-6634,
                -- `if not self.Scrolling and not self.MouseIsOver then
                -- if self.CurOpts.NXPlyrFollow then ...
                -- self:Move(plX, plY, nil, 30) end end`). Missing
                -- entirely until now - confirmed live 2026-11-09 (big
                -- background canvas correctly appears and tracks the
                -- right zone, but never re-centers on the player as
                -- they walk around; only the small live-widget patch
                -- tracked PlyrX/PlyrY, since RefreshCurrentZone only
                -- pans once, on zone entry, to the zone's center).
                -- Drops the NXPlyrFollow user toggle (no settings UI
                -- for it yet - always-on follow, which is this addon's
                -- whole point) and the MouseIsOver pause-while-hovering
                -- nicety (not ported - this addon's window isn't used
                -- for click-to-travel the way Carbonite's full map is),
                -- keeping only the self.Scrolling guard so an active
                -- manual drag (ScrollScale.lua) is never fought.
                --
                -- 2026-11-10: gated on the new AutoFollow saved
                -- setting (MinimapWindow.lua's title-bar checkbox,
                -- next to the Settings gear) so this continuous
                -- re-center can be turned off - without it, any manual
                -- pan got fought back to center within ~30 ticks of
                -- releasing the drag, which is what the checkbox is
                -- for.
                local ZoomController = AlchemyGPS.Modules.Map.ZoomController
                local followWin = AlchemyGPS.Modules.Map.MinimapWindow
                local autoFollow = not (followWin and followWin:DB().profile.AutoFollow == false)
                if ZoomController and not self.Scrolling and autoFollow then
                    ZoomController:Move(self.PlyrX, self.PlyrY, nil, 30)
                end
            end
        end
    end
    -- Build-order step 8b, corrected 2026-11-10 after live testing
    -- showed only ever one detail tile at a time, frozen on pan: a
    -- re-read of real Carbonite's UpdateZones (MapEngine.lua:9831-9900)
    -- shows UpdateMiniFrames() is called EVERY tick, UNCONDITIONALLY,
    -- in every branch (city, ordinary zone, zoomed in or out) - the
    -- detail-tile layer is always live, following pan/zoom
    -- continuously from the very first tick. ScaleDraw <= DETAIL_SCALE
    -- only ever decides whether the COARSE zone-overview art is ALSO
    -- drawn on top of it (zoomed out: self:MoveCurZoneTiles()) or
    -- cleared (zoomed in: real source's "MoveCurZoneTiles(true)" -
    -- this engine's own equivalent is HideZoneTileFrames). The
    -- previous version of this block treated the two layers as a
    -- mutually-exclusive switch and only ever turned detail tiles on
    -- once already zoomed in far enough that a single ~107-world-unit
    -- tile exceeds the whole window - exactly the "one frozen square"
    -- symptom reported live.
    if self.ScaleDraw <= DETAIL_SCALE then
        self:MoveCurZoneTiles()
    else
        self:HideZoneTileFrames(self.TileFrms)
    end
    self:UpdateMiniFrames()

    -- Build-order step 9a: independent of both tile layers - see
    -- UpdatePlayerMarker's own header.
    self:UpdatePlayerMarker()

    -- Build-order step 9b: repositions already-resolved static service
    -- icons for the current pan/zoom - see UpdateServiceIcons' own
    -- header comment for why this runs every tick while
    -- RefreshServiceIcons only runs on zone change.
    self:UpdateServiceIcons()

    -- Build-order step 9c: quest turn-in state can change without a
    -- zone change (turning a quest in while standing still), unlike
    -- the static service-icon data above - re-resolve on a plain
    -- 2-second real-time throttle (GetTime(), not an elapsed-time
    -- accumulator - simpler and immune to drift) rather than every
    -- tick. A couple of seconds' lag before a turned-in quest's
    -- marker disappears is an acceptable tradeoff, not a correctness
    -- problem.
    local now = GetTime()
    if not self.QuestRefreshAt or now >= self.QuestRefreshAt then
        self.QuestRefreshAt = now + 2
        self:RefreshQuestIcons()
    end
    self:UpdateQuestIcons()

    -- Build-order step 9e: gathering-node field. Repositioned on its
    -- own 0.1s throttle, not every tick - see UpdateGatherIcons'
    -- header for why (hundreds of stationary points, 20Hz precision
    -- is wasted on something that never moves).
    if not self.GatherUpdateAt or now >= self.GatherUpdateAt then
        self.GatherUpdateAt = now + 0.1
        self:UpdateGatherIcons()
    end

    self:UpdateDebugOverlay()
end
