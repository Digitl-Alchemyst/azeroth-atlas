-- Alchemy GPS | Map / MinimapEngine
-- Blends the live Blizzard Minimap widget into our undocked window as
-- a small, low-alpha patch near the player - Carbonite's real
-- mechanism (reparent the widget to UIParent, clip/scale/position it
-- against a world-space viewport, never just stretch it to fill a
-- box). Ported from Carbonite/Modules/Map/MapEngine.lua.
--
-- Build-order step 4 turned out much deeper than the plan's own
-- anchors assumed. ClipMMW/MinimapUpdate/MinimapDetachFrms aren't a
-- small isolated slice of Carbonite's map engine - they're wired
-- into:
--   - self.MinimapOnMouseDown/Up/Wheel + MinimapSetInputMode: input
--     routing that only matters once Carbonite's own zoom/pan replace
--     native minimap clicks - that's steps 5/6, not this one. Not
--     ported here; the widget keeps its native Blizzard clicks/wheel-
--     zoom for now, which is harmless, not broken, and the correct
--     "no zoom/pan yet" interim behavior.
--   - Nx.Map.Dock (the button-dock system) - explicitly a non-goal
--     per the plan ("unrelated to the map window despite the similar
--     name"). MinimapDetachFrms's real job is handing off addon
--     buttons/pins attached to the minimap to that dock; without it,
--     this file's MinimapDetachFrms just hides anything unrecognized
--     instead, so the small patch stays clean.
--   - A whole Nx.db.profile.MiniMap options schema (dock position,
--     dock-on-max, per-zone alpha, icon scale, instance/BG/garrison
--     auto-docking, indoor/bugged auto-full-size) this project's
--     feature list never asked for. Dropped; fixed sensible defaults
--     stand in (see Update() below).
--   - A real world-art canvas (self.MapPosXDraw/Y, self.ScaleDraw,
--     self.MapW/H as a drawn map surface) that doesn't exist until
--     build-order step 8. Standing in for it here: the player is
--     always treated as sitting at the canvas center (no pan yet -
--     that's step 6) at a fixed 1-world-unit-per-pixel scale (no zoom
--     yet - step 5), with "canvas size" just being our window's
--     content frame size. Once steps 5/6/8 land, PlyrX/Y, ScaleDraw
--     and MapW/H get driven by the real systems instead of these
--     fixed stand-ins - ClipMMW/PositionOwnedMinimap/MinimapSetScale
--     themselves are already the real, verbatim math and need no
--     changes when that happens.
--
-- ClipMMW/PositionOwnedMinimap/MinimapSetScale/MinimapSyncLayer/
-- MinimapSyncVisibility/MinimapIsHostVisible/
-- MinimapShouldUseBlizzardPlayerArrow are kept verbatim (the real
-- positioning/clipping/layering math - this is "the single most
-- important function for the map that sits inside it to actually
-- look like Carbonite", per the plan). TakeOwnership is a trimmed
-- MinimapOwnInit (one-time setup only; this addon has no "own
-- minimap" checkbox - it's just how the window works). Update is a
-- new, much-trimmed replacement for MinimapUpdate/MinimapUpdateEnd
-- combined, keeping only the "try each preset size, biggest first,
-- blend if it fits" loop and the alpha/mask/layer/detach calls that
-- loop needs - every dock-position/instance/BG/garrison/indoor-auto-
-- toggle/menu-checkbox branch is dropped, not approximated.

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

    self.MMOwn = true
    local mm = _G["Minimap"]
    assert(mm, "Minimap widget not found")
    self.MMFrm = mm

    self.MMScales = {}
    for n = 1, 6 do
        self.MMScales[n] = (8 - n) * 66.6666666666666 / 5.0
    end

    -- Build-order step 8: the zone-art tile frame pool. Created once
    -- (persists across close/reopen, same as the pan/zoom state below -
    -- recreating it would just leak the old 150 frames).
    if not self.TileFrms then
        self:InitTileFrames()
    end

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
    self.Scale = self.Scale or 1
    self.MapPosX, self.MapPosY = self.MapPosX or 0, self.MapPosY or 0
    self.StepTime = self.StepTime or 0
    self.ScaleDraw = self.ScaleDraw or 1
    self.MapPosXDraw, self.MapPosYDraw = self.MapPosXDraw or 0, self.MapPosYDraw or 0
    self.MMZoomType = nil

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

    if not self.MMOriginalParent then
        self.MMOriginalParent = mm:GetParent()
        self.MMOriginalStrata = mm:GetFrameStrata()
        self.MMOriginalLevel = mm:GetFrameLevel()
        self.MMOriginalShown = mm:IsShown()
        self.MMOriginalAlpha = mm:GetAlpha()
        self.MMOriginalWidth = mm:GetWidth()
        self.MMOriginalHeight = mm:GetHeight()
        self.MMOriginalScale = mm:GetScale()
        self.MMOriginalPoints = {}
        for index = 1, mm:GetNumPoints() do
            self.MMOriginalPoints[index] = { mm:GetPoint(index) }
        end
    end

    -- Every call below (SetParent above all) touches protected frame
    -- state - every other mutator in this file (ReleaseOwnership,
    -- PositionOwnedMinimap, MinimapSetScale) already guards against
    -- combat lockdown, but this one didn't, and it's the one that
    -- actually reparents the widget. Confirmed live: closing/reopening
    -- our window while in combat left TakeOwnership erroring out
    -- partway through, which silently aborted MinimapWindow:Open()
    -- before it reached win:Show(true) - the window just never
    -- reappeared. Deferred the same way Carbonite defers its own
    -- combat-unsafe minimap work (MMChkDelay-style retry): Update()
    -- re-attempts this every tick until it succeeds.
    if InCombatLockdown() then
        self.MMApplyPending = true
        return
    end
    self:ApplyTakeOwnership(mm)
end

function MinimapEngine:ApplyTakeOwnership(mm)
    self.MMApplyPending = nil

    -- Carbonite normally picks between a Retail round mask
    -- ("Interface\\CharacterFrame\\TempPortraitAlphaMask") and a
    -- Classic one ("textures\\MinimapMask") here (Nx.isRetail,
    -- MapEngine.lua:3748). The Classic mask is confirmed dead on this
    -- client (blank terrain once the widget's resized, regardless of
    -- the zoom-kick below) - but WoW Forever may behave more like a
    -- modern client under the hood despite its Classic-range TOC, so
    -- trying Carbonite's OTHER real mask path here instead of jumping
    -- straight to the square fallback.
    mm:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mm:SetClampedToScreen(true)
    mm:SetWidth(140)
    mm:SetHeight(140)

    -- Keep Blizzard's hierarchy out of the movable window: a managed
    -- descendant of a StartMoving/StartSizing frame can invalidate
    -- the drag/resize on current clients (the exact reason Carbonite
    -- itself positions this in screen coordinates instead).
    mm:SetParent(UIParent)

    local transparentPOITexture = "Interface\\Addons\\AlchemyGPS\\Gfx\\Map\\32Transparent"
    if type(mm.SetPOIArrowTexture) == "function" then
        mm:SetPOIArrowTexture(transparentPOITexture)
    end
    if type(mm.SetStaticPOIArrowTexture) == "function" then
        mm:SetStaticPOIArrowTexture(transparentPOITexture)
    end

    -- Kept verbatim from this same real function (MapEngine.lua:2541-
    -- 2544). The "ring" that kept showing regardless of the mask/
    -- region fiddling above was never one of mm's own regions or
    -- children at all (confirmed live: the always-on debug overlay's
    -- own regions=0 count) - it's a SEPARATE global frame,
    -- `MinimapBackdrop`, this client's Classic/Wrath-era FrameXML
    -- ships as the minimap's round border backdrop (a sibling of
    -- Minimap under MinimapCluster, not a descendant of it) - so
    -- nothing about reparenting mm itself ever touched it. Confirmed
    -- live 2026-11-09.
    local backdrop = _G["MinimapBackdrop"]
    if backdrop then
        backdrop:Hide()
        local mmc = _G["MinimapCluster"]
        if mmc then backdrop:SetParent(mmc) end
    end
end

-- Give the live widget back to Blizzard when our window closes, so a
-- still-visible native MinimapCluster (the user has "Hide Blizzard
-- minimap" off) doesn't end up an empty shell missing its Minimap
-- child. Re-opening calls TakeOwnership again.
function MinimapEngine:ReleaseOwnership()
    local mm = self.MMFrm
    if not mm or not self.MMOwn then return end

    self.MMOwn = false
    self.MMZoomType = nil
    mm:Hide()

    if not InCombatLockdown() and self.MMOriginalParent then
        mm:SetParent(self.MMOriginalParent)
        mm:ClearAllPoints()
        for _, point in ipairs(self.MMOriginalPoints or {}) do
            mm:SetPoint(unpack(point))
        end
        if self.MMOriginalStrata then mm:SetFrameStrata(self.MMOriginalStrata) end
        if self.MMOriginalLevel then mm:SetFrameLevel(self.MMOriginalLevel) end
        if self.MMOriginalAlpha then mm:SetAlpha(self.MMOriginalAlpha) end
        if self.MMOriginalWidth then mm:SetWidth(self.MMOriginalWidth) end
        if self.MMOriginalHeight then mm:SetHeight(self.MMOriginalHeight) end
        if self.MMOriginalScale then mm:SetScale(self.MMOriginalScale) end

        -- Same "force icon update" nudge as the zoom-kick in Update()
        -- (see ApplyTakeOwnership's header comment) - a size change
        -- alone doesn't make Blizzard re-render the content to fill
        -- it. Without this, confirmed live: the restored widget comes
        -- back at its correct native size, but the terrain inside
        -- stays rendered at whatever smaller size it last was while
        -- we owned it, pinned in one corner instead of filling the
        -- now-bigger frame.
        if mm.GetZoom and mm.SetZoom then
            local ok, err = pcall(function()
                local zoom = mm:GetZoom() or 0
                local altZoom = zoom == 0 and 1 or 0
                mm:SetZoom(altZoom)
                mm:SetZoom(zoom)
            end)
            if not ok then
                AlchemyGPS.Core.Logger:warn("release zoom-kick failed: %s", tostring(err))
            end
        end

        -- Same retail round mask ApplyTakeOwnership now uses (see its
        -- comment) instead of the Classic one confirmed dead on this
        -- client - restores the native minimap to its real round look
        -- instead of a square (or square-inset-to-fit) substitute.
        if type(mm.SetMaskTexture) == "function" then
            mm:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end
        if self.MMOriginalShown then mm:Show() else mm:Hide() end
    end

    if type(mm.SetPlayerTexture) == "function" then
        mm:SetPlayerTexture("Interface\\Minimap\\MinimapArrow")
    end
    self.MMArrowName = nil
    self.MMMaskName = nil
end

---------------------------------------------------------------------------------------
-- Clip minimap frame to the map and set position, size and texture coords.
-- XY is center. Width and height are not scaled.
-- Kept verbatim from Nx.Map:ClipMMW (UIEngine.lua:10988) - the real
-- positioning math, unchanged by this file's simplifications.
---------------------------------------------------------------------------------------

function MinimapEngine:ClipMMW(frm, bx, by, w, h)

    local scale = self.ScaleDraw

    local bw = w * scale
    local bh = h * scale
    local clipW = self.MapW
    local clipH = self.MapH
    local x = (bx - self.MapPosXDraw) * scale + clipW * .5
    local y = (by - self.MapPosYDraw) * scale + clipH * .5

    local vx0 = x - bw * .5
    local vx1 = vx0
    local vx2 = vx0 + bw

    if vx1 < 0 or vx2 > clipW then
        return false
    end

    w = vx2 - vx1

    if w <= 0 then
        return false
    end

    local vy0 = y - bh * .5
    local vy1 = vy0
    local vy2 = vy0 + bh

    if vy1 < 0 or vy2 > clipH then
        return false
    end

    h = vy2 - vy1

    if h <= 0 then
        return false
    end

    local sc = w / 140
    self.MMFScale = sc

    local isc = 1
    self:MinimapSetScale(sc, isc)

    if not self:PositionOwnedMinimap(vx1, -vy1 - self.TitleH) then
        frm:Hide()
        return false
    end

    frm:Show()

    return true
end

---------------------------------------------------------------------------------------
-- Position Blizzard's owned minimap without anchoring or parenting it to the
-- movable Carbonite window. localX/localY are offsets from the map content
-- frame's TOPLEFT, in that frame's unscaled coordinates.
-- Kept verbatim from Nx.Map:PositionOwnedMinimap (MapEngine.lua:3696).
---------------------------------------------------------------------------------------

function MinimapEngine:PositionOwnedMinimap(localX, localY)
    if InCombatLockdown() then
        return false
    end

    local mm = self.MMFrm
    local mapFrame = self.Frm
    if not mm or not mapFrame then
        return false
    end

    local mapLeft = mapFrame:GetLeft()
    local mapTop = mapFrame:GetTop()
    local mapScale = mapFrame:GetEffectiveScale()
    local minimapScale = mm:GetEffectiveScale()
    if type(mapLeft) ~= "number" or type(mapTop) ~= "number"
        or type(mapScale) ~= "number" or mapScale <= 0
        or type(minimapScale) ~= "number" or minimapScale <= 0 then
        return false
    end

    local left = (mapLeft + localX) * mapScale / minimapScale
    local top = (mapTop + localY) * mapScale / minimapScale

    mm:ClearAllPoints()
    mm:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

    return true
end

-- Kept verbatim from Nx.Map:MinimapSetScale (MapEngine.lua:3734).
function MinimapEngine:MinimapSetScale(scale, iconScale)
    if InCombatLockdown() then
        return
    end
    local mm = self.MMFrm
    local sz = 140 * scale / iconScale
    mm:SetWidth(sz)
    mm:SetHeight(sz)
    mm:SetScale(iconScale)
end

-- Trimmed from Nx.Map:MinimapUpdateMask (MapEngine.lua:3746): no
-- per-zone Square/round options table - always the retail round mask
-- (see ApplyTakeOwnership's comment for why) - and no
-- Nx.NXMiniMapBut:Move() call (the button-dock launcher icon isn't
-- ported - non-goal).
function MinimapEngine:MinimapUpdateMask()

    local roundMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

    if self.MMMaskName ~= roundMask then
        self.MMMaskName = roundMask
        self.MMFrm:SetMaskTexture(roundMask)
    end

    local useBlizzardPlayerArrow = self:MinimapShouldUseBlizzardPlayerArrow()
    local name = useBlizzardPlayerArrow
        and "Interface\\Minimap\\MinimapArrow"
        or "Interface\\Addons\\AlchemyGPS\\Gfx\\Map\\32Transparent"
    if self.MMArrowName ~= name then
        self.MMArrowName = name
        if name ~= "" and type(self.MMFrm.SetPlayerTexture) == "function" then
            self.MMFrm:SetPlayerTexture(name)
        end
    end

end

-- Kept verbatim from Nx.Map:MinimapShouldUseBlizzardPlayerArrow (MapEngine.lua:3080).
function MinimapEngine:MinimapShouldUseBlizzardPlayerArrow()
    return self.MMOwn and self.MMFrm ~= nil
end

-- Kept verbatim from Nx.Map:MinimapSyncLayer (MapEngine.lua:2977).
function MinimapEngine:MinimapSyncLayer(preferredLevel, hostOffset, aboveHost)
    local mm = self.MMFrm
    if not mm then
        return preferredLevel or 1
    end

    local level = type(preferredLevel) == "number" and preferredLevel or 1
    local offset = type(hostOffset) == "number" and hostOffset or 1
    local winFrame = self.Win and self.Win.Frm
    local mapFrame = self.Frm

    if not InCombatLockdown() and mm.SetFrameStrata then
        local targetStrata = winFrame and winFrame.GetFrameStrata
            and winFrame:GetFrameStrata()
        local targetRank = targetStrata
            and MINIMAP_STRATA_RANK[targetStrata] or -1
        local mapStrata = mapFrame and mapFrame.GetFrameStrata
            and mapFrame:GetFrameStrata()
        local mapRank = mapStrata and MINIMAP_STRATA_RANK[mapStrata] or -1

        if mapStrata and mapRank > targetRank then
            targetStrata = mapStrata
        end

        if aboveHost and targetStrata then
            targetStrata = MINIMAP_STRATA_ABOVE[targetStrata] or targetStrata
        end

        if targetStrata and mm:GetFrameStrata() ~= targetStrata then
            mm:SetFrameStrata(targetStrata)
        end
    end

    if winFrame then
        if winFrame.GetFrameLevel then
            local winLevel = winFrame:GetFrameLevel()
            if type(winLevel) == "number" then
                level = max(level, winLevel + offset)
            end
        end
    end

    if mapFrame and mapFrame.GetFrameLevel then
        local mapLevel = mapFrame:GetFrameLevel()
        if type(mapLevel) == "number" then
            level = max(level, mapLevel + offset)
        end
    end

    mm:SetFrameLevel(level)
    return level
end

-- Kept verbatim from Nx.Map:MinimapIsHostVisible (MapEngine.lua:3032).
function MinimapEngine:MinimapIsHostVisible()
    return self.Win and self.Win.Frm:IsVisible()
        and self.Frm and self.Frm:IsVisible() or false
end

-- Kept verbatim from Nx.Map:MinimapSyncVisibility (MapEngine.lua:3037).
function MinimapEngine:MinimapSyncVisibility()
    local mm = self.MMFrm
    if not self.MMOwn or not mm then return true end
    local visible = self:MinimapIsHostVisible()
    if visible and not self.MMHiddenByMap then return true end

    self.MMHiddenByMap = true
    local inCombat = InCombatLockdown()
    if inCombat and mm.IsProtected and mm:IsProtected() then
        mm:SetAlpha(0)
    elseif mm:IsShown() then
        mm:Hide()
    end
    return visible and not inCombat
end

-- Not ported (no-op stub, same reasoning as UI/Window.lua's
-- OpenMenu): the real Nx.Map:MinimapDetachFrms (MapEngine.lua:3803)
-- hands addon buttons/pins parented to the minimap off to Nx.Map.Dock
-- (a non-goal) or a recognized-addon-name table (self.
-- AddonMinimapNames) this project doesn't have either. A blanket
-- "hide every child" in its place was considered and rejected - the
-- real source only ever redirects recognized frames, it never hides
-- arbitrary unrecognized ones, and this widget's own player-arrow
-- rendering is an internal texture layer (SetPlayerTexture, set by
-- MinimapUpdateMask above), not a discoverable child frame, but
-- *other* legitimate Blizzard children (e.g. the click-ping effect)
-- might be, and blanket-hiding risked breaking one of those instead
-- of just leaving addon-pin clutter unaddressed. Revisit once there's
-- a real recognized-names list or dock to redirect to.
function MinimapEngine:MinimapDetachFrms()
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
-- battlegrounds, micro-dungeons) - this addon has no close-zoom
-- "detail relief" tile system to defer to when zoomed in anyway (an
-- explicit non-goal), so there's nothing for an ordinary zone's
-- overview art to ever need to yield to - always drawing whichever
-- known zone we're in, at any zoom level, is the correct
-- simplification for this engine, not an approximation of a real gate
-- we're skipping.
function MinimapEngine:MoveCurZoneTiles()
    if not self.Cont then
        self:HideZoneTileFrames(self.TileFrms)
        return
    end
    self:MoveZoneTiles(self.Cont, self.Zone, self.TileFrms, self.BackgndAlpha or 1,
        self.Frm:GetFrameLevel() or 1)
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
    if button ~= "LeftButton" then return end
    self.Scrolling = false
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

    local mm = self.MMFrm
    if not mm then
        debugText:SetText("MinimapEngine: no MMFrm yet")
        return
    end

    local lines = {}
    local parent = mm:GetParent()
    tinsert(lines, ("parent=%s shown=%s visible=%s alpha=%.2f"):format(
        tostring(parent and parent.GetName and parent:GetName() or parent),
        tostring(mm:IsShown()), tostring(mm:IsVisible()), mm:GetAlpha() or -1))
    tinsert(lines, ("w=%.1f h=%.1f scale=%.2f strata=%s level=%s"):format(
        mm:GetWidth() or -1, mm:GetHeight() or -1, mm:GetScale() or -1,
        tostring(mm:GetFrameStrata()), tostring(mm:GetFrameLevel())))
    tinsert(lines, ("MapW=%s MapH=%s MMFScale=%s zoomType(prev)=%s"):format(
        tostring(self.MapW), tostring(self.MapH), tostring(self.MMFScale), tostring(self.MMZoomType)))
    tinsert(lines, ("Scale=%s ScaleDraw=%s StepTime=%s MMScale(lastKick)=%s"):format(
        tostring(self.Scale), tostring(self.ScaleDraw), tostring(self.StepTime), tostring(self.MMScale)))
    tinsert(lines, ("MapPosX=%s MapPosY=%s MapPosXDraw=%s MapPosYDraw=%s"):format(
        tostring(self.MapPosX), tostring(self.MapPosY), tostring(self.MapPosXDraw), tostring(self.MapPosYDraw)))
    tinsert(lines, ("Scrolling=%s Ttl=%s"):format(tostring(self.Scrolling), tostring(self.Ttl)))
    tinsert(lines, ("MapId=%s Cont=%s Zone=%s CurWorldUpdateMapId=%s tiles=%s"):format(
        tostring(self.MapId), tostring(self.Cont), tostring(self.Zone),
        tostring(self.CurWorldUpdateMapId), tostring(self.CurWorldTileCount)))
    tinsert(lines, ("PlyrX=%s PlyrY=%s"):format(tostring(self.PlyrX), tostring(self.PlyrY)))
    tinsert(lines, ("GetZoom=%s MaskName=%s ArrowName=%s"):format(
        tostring(mm.GetZoom and mm:GetZoom()), tostring(self.MMMaskName), tostring(self.MMArrowName)))

    local regions = { mm:GetRegions() }
    tinsert(lines, ("regions=%d"):format(#regions))
    for i, r in ipairs(regions) do
        local objType = r.GetObjectType and r:GetObjectType() or "?"
        if objType == "Texture" then
            local texPath = r.GetTexture and r:GetTexture()
            tinsert(lines, ("  [%d] Texture tex=%s shown=%s a=%.2f layer=%s"):format(
                i, tostring(texPath), tostring(r:IsShown()), r:GetAlpha() or -1,
                tostring(r.GetDrawLayer and r:GetDrawLayer())))
        else
            tinsert(lines, ("  [%d] %s shown=%s"):format(i, tostring(objType), tostring(r:IsShown())))
        end
    end

    debugText:SetText(table.concat(lines, "\n"))
end

function MinimapEngine:Update(elapsed)
    if not self.MMOwn or not self.Frm then return end

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

    if self.MMApplyPending and not InCombatLockdown() then
        self:ApplyTakeOwnership(self.MMFrm)
    end
    if self.MMApplyPending then return end

    if not self:MinimapSyncVisibility() then
        self:UpdateDebugOverlay()
        return
    end

    -- Resetting this latch was MinimapUpdateEnd's job in the real
    -- source (not ported - see file header); without it,
    -- MinimapSyncVisibility would re-hide defensively every single
    -- tick after the first hide, even once genuinely visible again.
    -- Harmless (ClipMMW re-shows it moments later in the same call
    -- when a preset fits) but needless.
    self.MMHiddenByMap = nil

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
        if zx then
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
                local ZoomController = AlchemyGPS.Modules.Map.ZoomController
                if ZoomController and not self.Scrolling then
                    ZoomController:Move(self.PlyrX, self.PlyrY, nil, 30)
                end
            end
        end
    end
    self:MoveCurZoneTiles()

    local mm = self.MMFrm
    local zoomType = 0

    -- "Tiles" mode (the window's Mode button, MinimapWindow.lua's
    -- SetMode) means background-canvas-only - no small live-widget
    -- accent/ring at all, regardless of zoom level. Gated here (not by
    -- skipping ApplyTakeOwnership/MinimapUpdateMask outright) so
    -- switching back to "Live" just resumes the normal per-zoom-level
    -- ClipMMW candidate search below with no extra reinitialization.
    local MinimapWindow = AlchemyGPS.Modules.Map.MinimapWindow
    local tilesOnly = MinimapWindow and MinimapWindow.Mode == "Tiles"

    if not tilesOnly and not InCombatLockdown() then
        for n = 1, 6 do
            local sz = self.MMScales[n]
            if self:ClipMMW(mm, self.PlyrX, self.PlyrY, sz, sz) then
                zoomType = n
                break
            end
        end
    end

    if zoomType > 0 then
        local al = 0.65
        if IsControlKeyDown() then
            al = IsAltKeyDown() and 1 or .8
        end
        mm:SetAlpha(al)

        self:MinimapUpdateMask()
        self:MinimapSyncLayer(self.Win.Frm:GetFrameLevel() or 1, 1)
        self:MinimapDetachFrms()

        -- MinimapUpdateEnd's "force icon update" (MapEngine.lua:3669-
        -- 3671), ported here since it turned out load-bearing on its
        -- own: without a SetZoom nudge after a resize/reparent,
        -- Blizzard's Minimap widget keeps its round mask and position
        -- but never redraws its terrain tiles - confirmed live (the
        -- mask ring showed, the map inside it stayed blank) before
        -- this was added.
        --
        -- Build-order step 5 bug fix: this used to re-kick only when
        -- zoomType (which of the 6 discrete MMScales candidates)
        -- changed. Real Carbonite's own trigger (MapEngine.lua:3480)
        -- is "zoomType changed OR (zoomType > 0 AND self.MMScale ~=
        -- self.ScaleDraw)" - it ALSO re-kicks on every continuous
        -- scale change within the same candidate, via a second field
        -- (self.MMScale, distinct from self.Scale/ScaleDraw - it's
        -- just "the ScaleDraw value as of the last kick"). Without
        -- that half, confirmed live: once a zoom animation settled on
        -- the same zoomType it started on, further continuous zoom
        -- widened the widget's own bounds but never re-kicked, so
        -- Blizzard's terrain stayed rendered at its last-kicked size -
        -- same stale-render bug as the original fill-lag, just gated
        -- on the wrong variable now that zoom is continuous.
        if self.MMZoomType ~= zoomType or self.MMScale ~= self.ScaleDraw then
            self.MMZoomType = zoomType
            self.MMScale = self.ScaleDraw
            local ok, err = pcall(function()
                local zoom = mm:GetZoom() or 0
                local altZoom = zoom == 0 and 1 or 0
                mm:SetZoom(altZoom)
                mm:SetZoom(zoom)
            end)
            if not ok then
                AlchemyGPS.Core.Logger:warn("zoom-kick failed: %s", tostring(err))
            end
        end
    else
        -- Window too small for even the smallest preset. The real
        -- dock-to-corner fallback isn't ported (tied to dock-position
        -- options this project doesn't have) - just hide until the
        -- window is large enough again.
        mm:Hide()
    end

    self:UpdateDebugOverlay()
end
