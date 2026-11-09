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

local MinimapEngine = {}
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

    -- No real world canvas yet (build-order step 8) - the player is
    -- always at the canvas center, and there's no pan (step 6) to
    -- move away from it, so PlyrX/Y and MapPosXDraw/Y just stay
    -- together at a fixed point. ScaleDraw (1 world unit = 1 pixel)
    -- stands in for real zoom (step 5).
    self.PlyrX, self.PlyrY = 0, 0
    self.MapPosXDraw, self.MapPosYDraw = 0, 0
    self.ScaleDraw = 1
    self.MMZoomType = nil

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
-- New, much-trimmed replacement for Nx.Map:MinimapUpdate +
-- MinimapUpdateEnd combined. Keeps only: try each preset size
-- (biggest first), blend the widget if one fits, otherwise hide it.
-- No dock-position/instance/BG/garrison/indoor-auto-toggle/menu-
-- checkbox logic - none of that is part of this project's feature
-- list, and none of it is approximated here, just not ported.
---------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------
-- TEMPORARY diagnostic overlay for the live-widget-blend bug (build-
-- order step 4: mask renders, terrain stays blank). Always-on instead
-- of a slash command so there's nothing to remember to run before
-- screenshotting. Remove once that bug is confirmed fixed.
---------------------------------------------------------------------------------------

local debugFrm, debugText

local function ensureDebugOverlay()
    if debugFrm then return end
    debugFrm = CreateFrame("Frame", "AlchemyGPSMapDebug", UIParent, "BackdropTemplate")
    debugFrm:SetSize(520, 260)
    debugFrm:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
    debugFrm:SetFrameStrata("TOOLTIP")
    debugFrm:SetBackdrop({
        bgFile = "Interface\\Buttons\\White8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 9, edgeSize = 9,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    debugFrm:SetBackdropColor(0, 0, 0, 0.85)

    debugText = debugFrm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debugText:SetPoint("TOPLEFT", 6, -6)
    debugText:SetPoint("BOTTOMRIGHT", -6, 6)
    debugText:SetJustifyH("LEFT")
    debugText:SetJustifyV("TOP")
    debugText:SetWordWrap(true)
end

function MinimapEngine:UpdateDebugOverlay()
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

function MinimapEngine:Update()
    if not self.MMOwn or not self.Frm then return end

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

    self.MapW = self.Frm:GetWidth()
    self.MapH = self.Frm:GetHeight()

    local mm = self.MMFrm
    local zoomType = 0

    if not InCombatLockdown() then
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
        -- this was added. Only kicked once per zoomType change, not
        -- every tick - same as the real source's MMZoomChanged guard.
        if self.MMZoomType ~= zoomType then
            self.MMZoomType = zoomType
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
