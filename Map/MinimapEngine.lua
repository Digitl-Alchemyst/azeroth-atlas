-- Azeroth Atlas | Map / MinimapEngine
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
-- off). Removed on explicit direction, on strong (but, confirmed by a
-- later live re-test, ultimately NOT correct) evidence that this was
-- the root cause of a recurring "GatherMate2 has been blocked from an
-- action only available to the Blizzard UI" taint popup: the theory
-- was that ApplyTakeOwnership's `mm:SetParent(UIParent)` - explicitly
-- noted in its own prior comment as "touches protected frame state" -
-- ripped the real Minimap widget out of MinimapCluster automatically
-- on login, tainting GatherMate2's own pin code (parented to that same
-- widget) the next time it ran. Removing this mechanism did NOT fix
-- the popup (confirmed live, same day) - round 9's later systematic
-- isolation (CHANGELOG.md) ruled out every mechanism in this addon
-- individually without ever finding the real cause, and the popup
-- still occurs today (now blaming AzerothAtlas itself instead of
-- GatherMate2, once GatherMate2 was disabled - see CHANGELOG.md). What
-- this removal DID actually, confirmably fix: the "Hide Blizzard
-- minimap" checkbox not persisting its state across reload (Open()/
-- Close() were force-overriding the saved preference). The real
-- Blizzard minimap now stays fully under Blizzard's own control
-- always - shown or hidden per that saved preference, persisted
-- directly with no override tied to this window's own open/close state
-- (see MinimapWindow.lua). Kept removed regardless of the taint
-- popup's real cause being unresolved - it's dead weight either way
-- now that the gathering-node field no longer needs GatherMate2's own
-- live database (see this file's gathering-node section further down).
--
-- TakeOwnership is kept as a name (one-time per-window setup: tile/
-- marker/icon frame pools, mouse wheel/drag wiring) even though it no
-- longer "owns" anything external - renaming it was considered and
-- rejected to keep this diff reviewable; a future cleanup pass can
-- rename it along with MinimapWindow.lua's own call site.

local AzerothAtlas = _G.AzerothAtlas
local Nx = AzerothAtlas
AzerothAtlas.Modules.Map = AzerothAtlas.Modules.Map or {}

-- Build-order step 8: Map\Data\NxMapData.lua (Carbonite's real
-- Camelot-flavor zone/continent database) assigns onto `AzerothAtlas.Map`
-- (its own `local Map = Nx.Map` alias) - whichever of the two files
-- loads first (see Map.xml), inherit/share that same table instead of
-- creating a fresh one, so NxMapData.lua's MapInfo/MapWorldInfo/
-- MapZones/ContCnt/ContBlks fields and this file's own methods end up
-- on one table, exactly mirroring how real Carbonite's `Nx.Map` is
-- simultaneously the map class AND the static data holder.
local MinimapEngine = AzerothAtlas.Map or {}
AzerothAtlas.Map = MinimapEngine
AzerothAtlas.Modules.Map.MinimapEngine = MinimapEngine

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
    self.BackgndAlpha = (AzerothAtlas.db and AzerothAtlas.db.profile
        and AzerothAtlas.db.profile.BackgndBrightness) or 1

    -- Same pattern as BackgndAlpha just above, for the gathering-node
    -- icons' own opacity and size sliders (MapContextMenu.lua, build-
    -- order steps 9g/9h) - seeded here so a value chosen via the
    -- right-click menu survives /reload without needing the menu
    -- reopened first.
    self.GatherOpacity = (AzerothAtlas.db and AzerothAtlas.db.profile
        and AzerothAtlas.db.profile.GatherIconOpacity) or 1
    self.GatherIconScale = (AzerothAtlas.db and AzerothAtlas.db.profile
        and AzerothAtlas.db.profile.GatherIconScale) or 1
    -- Literal fallback (not the DEFAULT_GATHER_BACKDROP_OPACITY named
    -- constant below) - same reason BackgndAlpha/GatherOpacity/
    -- GatherIconScale just above use literals too: this runs before
    -- that constant's own `local` declaration further down the file
    -- is in scope.
    self.GatherBackdropOpacity = (AzerothAtlas.db and AzerothAtlas.db.profile
        and AzerothAtlas.db.profile.GatherBackdropOpacity) or 0.7

    -- Same pattern again, for the Terrain Texture layer's own
    -- brightness slider (MapContextMenu.lua, build-order step 19
    -- follow-up) - independent of BackgndAlpha above (that one is Art
    -- Map's own), seeded here so a value chosen via the right-click
    -- menu survives /reload.
    self.TerrainBrightness = (AzerothAtlas.db and AzerothAtlas.db.profile
        and AzerothAtlas.db.profile.TerrainBrightness) or 1

    -- 2026-11-18 (user request, from Carbonite): the rest of the per-
    -- layer sliders (city / dungeon maps, unexplored areas, map icons,
    -- quest icons, quest areas) - one list, MapContextMenu.SLIDERS.
    local MapContextMenu = AzerothAtlas.Modules.Map.MapContextMenu
    if MapContextMenu and MapContextMenu.ApplyAll then MapContextMenu.ApplyAll() end

    -- 2026-11-16: layer on/off switches now live in Settings > Map and
    -- persist (they used to be session-only title-bar debug toggles).
    self:LoadLayerSettings()

    -- Build-order step 8: the zone-art tile frame pool. Created once
    -- (persists across close/reopen, same as the pan/zoom state below -
    -- recreating it would just leak the old 150 frames).
    if not self.TileFrms then
        self:InitTileFrames()
    end
    -- Build-order step 20: the continent-art frame pool (one static,
    -- never-retextured set per continent that has re-exported art) -
    -- see InitContinentFrames' own header. Same create-once treatment.
    if not self.ContFrms then
        self:InitContinentFrames()
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

    -- Build-order step 10 (2026-11-11): right-click goto waypoint +
    -- ant-trail pool (see SetGotoAtClick/UpdateGoto). Only the pool
    -- array persists here, same treatment as the pools above - the
    -- single dot frame is lazily created inside UpdateGoto instead
    -- (its texture constant is declared further down the file, after
    -- this function, so it isn't in scope yet here). GotoWX/GotoWY/
    -- GotoCont are deliberately NOT initialized/persisted anywhere -
    -- matches real Carbonite's own Nx.Map.Targets, a plain in-memory
    -- table never written to Nx.db (confirmed by reading its real
    -- source - SetTargetAtClick/ClearTargets, MapEngine.lua) - a goto
    -- is session-only, cleared on /reload, same as upstream.
    self.GotoTrailFrms = self.GotoTrailFrms or {}
    self.ArrowScroll = self.ArrowScroll or 0

    -- Build-order step 10 follow-up (2026-11-11): corpse-recovery
    -- trail pool - real Carbonite's own corpse-tracking (MapEngine.lua
    -- :7667-7712) is a second, independent tracking system next to
    -- Goto (its own icon, its own DrawTracking call), not a variant of
    -- it, so it gets its own pool/dot rather than sharing Goto's -
    -- both can be visible at once, same as upstream. See
    -- UpdateCorpseTrack's own header for the rest.
    self.CorpseTrailFrms = self.CorpseTrailFrms or {}

    -- Quest companion (2026-11-15): a third trail pool, for the routed
    -- quest destination (see UpdateQuestRoute) - independent of the
    -- two above for the same reason they are independent of each other.
    self.QuestTrailFrms = self.QuestTrailFrms or {}

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
-- Build-order step 17 (2026-11-11): a scoped-down revival of the
-- removed "Mode: Live" live-widget reparenting mechanism (see this
-- file's own top header comment, and CHANGELOG.md's build-order step
-- 16/17 for the full history) - not to blend the real Minimap into
-- the window cosmetically like before, but because it's the only way
-- to surface Blizzard's own native resource-node blips: this same
-- session's research (CHANGELOG.md step 16) confirmed those blips are
-- otherwise unreachable from Lua on this client - no region, no
-- child frame, nothing, even standing directly on a visible node with
-- every other addon disabled. They're baked into the Minimap widget's
-- own internal rendering, so the only way to see them through this
-- addon's own window is to put the real widget there.
--
-- That removed mechanism was blamed for a recurring "blocked from an
-- action only available to the Blizzard UI" taint popup, but the
-- commit that removed it (`4076ed8`) says plainly that removing it was
-- live-tested and did NOT fix the popup - so it's not confirmed to be
-- the cause, just a prior suspect. Reviving it with fresh, isolated
-- testing is reasonable; if the popup reappears THIS time, that's
-- real, clean evidence (a single-variable test, unlike the original
-- multi-cause investigation) and this section should come back out.
--
-- Scoped down from the original per explicit user direction: only
-- takes over the real Minimap widget while the player's gathering-
-- tracking buff (Find Herbs/Find Minerals/Find Fish) is active, not
-- for the whole time the map window is open - smaller exposure window
-- for the protected-frame work below, and it's only useful while
-- actually gathering anyway. Detection confirmed via a real, already-
-- installed, already-working addon on this exact server
-- (GatherMate2/Constants.lua:806-810, Display.lua:325-335) -
-- C_Minimap.GetNumTrackingTypes()/GetTrackingInfo(id) (.name/.active),
-- matched against C_Spell.GetSpellName(id) for the known tracking-
-- spell IDs below - not a guess, the same mechanism that addon already
-- uses successfully here. Checked on a cheap 1s poll from Update()
-- (see the gather-tracking block further down) rather than a new
-- MINIMAP_UPDATE_TRACKING event-frame registration - this file has no
-- event plumbing of its own, it's driven entirely by Update()'s own
-- throttle, same pattern as the quest-icon 2s/gather-icon 0.1s polls
-- already in Update() below.
--
-- Most of what follows (ShowLiveBlips/HideLiveBlips/ClipMMW/
-- PositionOwnedMinimap/MinimapSetScale/MinimapUpdateMask/
-- MinimapSyncLayer/MinimapIsHostVisible/MinimapSyncVisibility) is
-- lifted near-verbatim from the archived ApplyTakeOwnership/
-- ReleaseOwnership/etc. (`git show 4076ed8^:Map/MinimapEngine.lua`),
-- already real Carbonite math/logic, already combat-lockdown-guarded,
-- already confirmed live before removal - not rewritten from scratch.
-- Two things deliberately dropped as dead weight, not ported back:
-- the custom transparent POI-arrow texture (`Gfx/Map/32Transparent`,
-- deleted along with the rest of Mode:Live and not worth restoring -
-- the branch that used it was provably unreachable anyway, see
-- MinimapUpdateMask below), and the archive's Ctrl/Alt-modified
-- "see-through" alpha levels (that was for a cosmetic background
-- blend - this revival's whole point is seeing blips clearly, so it's
-- always full alpha instead). `MinimapDetachFrms` stays the same
-- no-op stub it already was in the archive.
---------------------------------------------------------------------------------------

local GATHER_TRACKING_SPELL_IDS = { 2383, 2580, 43308 } -- Find Herbs, Find Minerals, Find Fish
local gatherTrackingSpellNames -- lazily resolved by name, see IsGatherTrackingActive

local function IsGatherTrackingActive()
    if not gatherTrackingSpellNames then
        gatherTrackingSpellNames = {}
        for _, spellID in ipairs(GATHER_TRACKING_SPELL_IDS) do
            local name = C_Spell.GetSpellName(spellID)
            if name then gatherTrackingSpellNames[name] = true end
        end
    end
    for id = 1, (C_Minimap.GetNumTrackingTypes() or 0) do
        local info = C_Minimap.GetTrackingInfo(id)
        if info and info.active and gatherTrackingSpellNames[info.name] then
            return true
        end
    end
    return false
end

-- Build-order step 17, live-tested follow-up: recursively hides every
-- shown descendant of frm (not just direct children - confirmed live
-- a first, direct-children-only pass still missed a passenger, most
-- likely nested one level deeper inside its own button frame), storing
-- each one in `hidden` so HideLiveBlips can restore exactly what was
-- touched. Safe to walk unconditionally: this session's own earlier,
-- fully-isolated testing (every other addon disabled) already
-- confirmed Blizzard's native Minimap has zero Lua-visible children of
-- its own, so anything found here with other addons enabled is a
-- third-party addon's own unprotected frame, never Blizzard's.
-- Live-tested follow-up: the addon-button icon itself stopped
-- appearing once this walked frames, but a faint dark square stayed
-- behind - its own background is most likely a bare Texture region
-- (GetChildren() only returns Frame-type children; a plain decorative
-- texture parented straight onto a frame, with no frame of its own
-- wrapping it, is invisible to that call and needs GetRegions()
-- instead). Hiding regions at every level this walks, not just
-- frames, for the same reason frames are safe to hide here - nothing
-- Blizzard's own native Minimap draws survives in isolation (confirmed
-- earlier this session), so anything found with other addons enabled
-- is third-party.
-- Build-order step 17, sixth follow-up, same day: /aatlas mmpassengers
-- found one specific passenger that was STILL shown despite being a
-- key in `hidden` (so we HAD hidden it) - it re-shows itself faster
-- than the 0.5s re-scan throttle in UpdateLiveBlips can catch (some
-- addon's own OnUpdate/OnShow-driven redisplay, same category as the
-- icon/texture passengers before it, just quicker about it). A
-- throttled poll can only ever catch up after the fact; hooking
-- OnShow reacts the instant it tries, regardless of how fast that is.
-- Kept separate from `hidden` (a per-ownership-cycle restore record)
-- since the hook itself needs to persist and keep applying across
-- cycles once attached, but must only actually suppress the Show()
-- while live blips are presently active - gated on `engine.MMOwn`,
-- checked fresh every time it fires, not captured at hook time, so a
-- hook attached during one gathering-tracking session doesn't silence
-- this addon's button forever once tracking turns back off.
-- HookScript only exists on Frame-type objects, not plain texture/
-- fontstring Regions - the region loop below stays throttle-only,
-- which is fine since it was the Frame path that showed this symptom.
local HookedPassengers = setmetatable({}, { __mode = "k" })

local function HideMinimapPassengers(frm, hidden, engine)
    for _, region in ipairs({ frm:GetRegions() }) do
        if region:IsShown() and not hidden[region] then
            hidden[region] = true
            region:Hide()
        end
    end
    for _, child in ipairs({ frm:GetChildren() }) do
        if child:IsShown() and not hidden[child] then
            hidden[child] = true
            child:Hide()
        end
        if not HookedPassengers[child] then
            HookedPassengers[child] = true
            child:HookScript("OnShow", function(frame)
                if engine.MMOwn then
                    frame:Hide()
                end
            end)
        end
        HideMinimapPassengers(child, hidden, engine)
    end
end

-- Takes over the real Minimap widget. Adapted from the archived
-- ApplyTakeOwnership - same InCombatLockdown deferral (retried from
-- Update(), see MMApplyPending below), same "SetParent(UIParent) and
-- position purely by anchor math (PositionOwnedMinimap) rather than
-- true reparenting into this window's own frame tree" approach - the
-- archive's own comment explains this avoids drag/resize conflicts
-- with a movable window.
function MinimapEngine:ShowLiveBlips()
    if self.MMOwn then return end
    if InCombatLockdown() then
        self.MMApplyPending = true
        return
    end
    self.MMApplyPending = nil

    local mm = _G["Minimap"]
    if not mm then return end
    self.MMFrm = mm
    self.MMOwn = true

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

    -- The real widget is a single object - moving it would leave the
    -- on-screen MinimapCluster an empty shell if the user currently
    -- has it shown. Force it hidden for the duration (same as the
    -- archived Mode:Live did), restoring whatever it was in
    -- HideLiveBlips below.
    local NativeMinimapHide = AzerothAtlas.Modules.Map.NativeMinimapHide
    if NativeMinimapHide then
        if self.MMPrevNativeHidden == nil then
            self.MMPrevNativeHidden = NativeMinimapHide:IsNativeHidden()
        end
        NativeMinimapHide:SetNativeHidden(true)
    end

    -- Carbonite picks between a Retail round mask and a Classic one
    -- here (Nx.isRetail) - the archive found the Classic one dead on
    -- this client and used the Retail path unconditionally; kept the
    -- same way. This round mask is what actually crops the widget's
    -- content for the rest of this feature's life - MinimapUpdateMask
    -- no longer touches the mask at all (a square-mask override was
    -- tried and reverted - see CHANGELOG's step 17 follow-ups).
    mm:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mm:SetClampedToScreen(true)
    mm:SetWidth(140)
    mm:SetHeight(140)

    -- Keep Blizzard's hierarchy out of the movable window - see this
    -- section's own header.
    mm:SetParent(UIParent)

    -- Kept verbatim from the archive (MapEngine.lua:2541-2544): a
    -- separate global sibling frame under MinimapCluster, not a
    -- descendant of mm, confirmed live before - nothing about
    -- reparenting mm itself needs to touch it, just keep it out of the
    -- way.
    local backdrop = _G["MinimapBackdrop"]
    if backdrop then
        backdrop:Hide()
        local mmc = _G["MinimapCluster"]
        if mmc then backdrop:SetParent(mmc) end
    end

    -- Build-order step 17, live-tested follow-up: a third-party
    -- addon's own minimap button (a LibDBIcon-style icon; several
    -- addons already running this session announce themselves as
    -- exactly this kind - Titan Panel, Dungeon Journal, Lore Forever)
    -- parents itself as a descendant of the real Minimap and
    -- recalculates its own position from Minimap's current size/
    -- shape - resizing/repositioning mm for the live-blip patch
    -- dragged one along, showing up (icon and backdrop both) inside
    -- this window's patch. See HideMinimapPassengers above for why
    -- recursing into every descendant, not just direct children, is
    -- safe here.
    self.MMHiddenChildren = {}
    HideMinimapPassengers(mm, self.MMHiddenChildren, self)
end

-- Gives the live widget back to Blizzard. Adapted from the archived
-- ReleaseOwnership - same combat-lockdown-safe restore, same zoom-kick
-- nudge (without it, confirmed live before: the restored widget comes
-- back at its correct native size, but the terrain inside stays
-- rendered at whatever smaller size it last was).
function MinimapEngine:HideLiveBlips()
    local mm = self.MMFrm
    if not mm or not self.MMOwn then return end

    self.MMOwn = false
    self.MMZoomType = nil
    self.MMPassengerCheckAt = nil
    mm:Hide()
    self:UpdateLiveBlipRadar(false)

    -- Restore whatever third-party addon buttons ShowLiveBlips hid
    -- (see its own header) - plain unprotected frames, no combat-
    -- lockdown concern, safe to do unconditionally.
    if self.MMHiddenChildren then
        for child in pairs(self.MMHiddenChildren) do
            child:Show()
        end
        self.MMHiddenChildren = nil
    end

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

        if mm.GetZoom and mm.SetZoom then
            local ok, err = pcall(function()
                local zoom = mm:GetZoom() or 0
                local altZoom = zoom == 0 and 1 or 0
                mm:SetZoom(altZoom)
                mm:SetZoom(zoom)
            end)
            if not ok then
                AzerothAtlas.Core.Logger:warn("release zoom-kick failed: %s", tostring(err))
            end
        end

        if type(mm.SetMaskTexture) == "function" then
            mm:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end
        if self.MMOriginalShown then mm:Show() else mm:Hide() end
    end

    if type(mm.SetPlayerTexture) == "function" then
        mm:SetPlayerTexture("Interface\\Minimap\\MinimapArrow")
    end
    self.MMArrowName = nil

    local NativeMinimapHide = AzerothAtlas.Modules.Map.NativeMinimapHide
    if NativeMinimapHide and self.MMPrevNativeHidden ~= nil then
        NativeMinimapHide:SetNativeHidden(self.MMPrevNativeHidden)
        self.MMPrevNativeHidden = nil
    end
end

---------------------------------------------------------------------------------------
-- Clip minimap frame to the map and set position, size and texture coords.
-- XY is center. Width and height are not scaled.
-- Kept verbatim from Nx.Map:ClipMMW (UIEngine.lua:10988) via the
-- archived port - the real positioning math, unchanged.
--
-- Build-order step 17: hides the widget outright whenever its aligned
-- size exceeds the window (vx1<0 or vx2>clipW) - confirmed live as a
-- real ceiling, not a bug: Blizzard's own most-zoomed-in native level
-- still has a fixed minimum real-world radius, and past that this
-- engine's own zoom can't be matched by any native level at all, no
-- matter the widget's pixel size. (A SetClipsChildren-based oversize-
-- and-crop workaround was tried for this and reverted - confirmed
-- live that the API exists on this client but doesn't actually clip -
-- see CHANGELOG's "oversize+clip REVERTED" entry.)
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
-- movable window. localX/localY are offsets from the map content
-- frame's TOPLEFT, in that frame's unscaled coordinates.
-- Kept verbatim from Nx.Map:PositionOwnedMinimap (MapEngine.lua:3696)
-- via the archived port.
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

-- Kept verbatim from Nx.Map:MinimapSetScale (MapEngine.lua:3734) via
-- the archived port.
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

-- Adapted from the archived MinimapUpdateMask (MapEngine.lua:3746-
-- 3759) - simplified from the archive: that version's custom
-- transparent-arrow fallback branch is gone (its texture asset,
-- Gfx/Map/32Transparent, was deleted along with the rest of Mode:Live
-- and isn't worth restoring - the branch only ran when MMOwn was
-- false, which can't be true inside this function, so it was
-- provably unreachable anyway). Always blanks Blizzard's own arrow.
--
-- Doesn't touch the mask at all - a square mask was tried here (fill
-- this window's own square content area edge to edge) and reverted:
-- Blizzard's native minimap source texture is square internally and
-- normally cropped to a circle, and a fully-uncropped mask revealed
-- whatever's baked into the corners outside that circle, never meant
-- to be seen (confirmed via /aatlas mmpassengers coming back with zero
-- Lua-visible passengers while the artifact was still there - not a
-- Lua object, native rendering). ShowLiveBlips's own initial
-- SetMaskTexture("...TempPortraitAlphaMask") is what actually crops
-- the widget now, round, same as normal gameplay - see its own
-- comment and CHANGELOG's step 17 follow-ups for the full history.
function MinimapEngine:MinimapUpdateMask()
    -- Build-order step 17, live-tested follow-up: this used to restore
    -- Blizzard's own player-facing arrow here. Confirmed live this own
    -- addon's doing - this engine already draws its own player marker
    -- (UpdatePlayerMarker) at the same spot, so the native one was
    -- pure redundant clutter sitting on top of it (and easy to mistake
    -- for something else, like a quest-direction pointer, since it's a
    -- gray arrow rotating with facing). Blanked out instead of set -
    -- "" is the standard trick other minimap-replacement addons use to
    -- suppress Blizzard's own player icon without hiding the rest of
    -- the widget.
    local arrow = ""
    if self.MMArrowName ~= arrow then
        self.MMArrowName = arrow
        if type(self.MMFrm.SetPlayerTexture) == "function" then
            local ok, err = pcall(self.MMFrm.SetPlayerTexture, self.MMFrm, arrow)
            if not ok then
                AzerothAtlas.Core.Logger:warn("SetPlayerTexture blank failed: %s", tostring(err))
            end
        end
    end
end

-- Kept verbatim from Nx.Map:MinimapSyncLayer (MapEngine.lua:2977) via
-- the archived port.
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

-- Kept verbatim from Nx.Map:MinimapIsHostVisible (MapEngine.lua:3032)
-- via the archived port.
function MinimapEngine:MinimapIsHostVisible()
    return self.Win and self.Win.Frm:IsVisible()
        and self.Frm and self.Frm:IsVisible() or false
end

-- Kept verbatim from Nx.Map:MinimapSyncVisibility (MapEngine.lua:3037)
-- via the archived port.
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

-- Not ported (no-op stub, same as the archive) - the real
-- Nx.Map:MinimapDetachFrms hands addon buttons/pins parented to the
-- minimap off to a dock/recognized-addon-name system this project
-- doesn't have.
function MinimapEngine:MinimapDetachFrms()
end

local LIVE_BLIP_FIT_MARGIN = 0.9 -- see ResolveLiveBlipFit's own header

-- Build-order step 17, live-tested follow-up: user asked to "remove
-- the blizz texture" once alignment was confirmed working - full
-- removal isn't possible (same confirmed-this-session fact that made
-- blips themselves unreadable: terrain and blips are one baked
-- render, there's no known way to fade one without the other), so
-- this dims the whole widget instead of hiding it outright - enough
-- that the native terrain reads as a faint backdrop instead of a
-- competing image, while the blip (small, bright) still shows through.
-- A first-guess tunable, not a measured constant - raise it if blips
-- end up too faint to see, lower it if the terrain is still too loud.
local LIVE_BLIP_ALPHA = 0.55

-- Build-order step 17 follow-up, same day: live-tested - the real
-- widget DOES show native blips once reparented (confirmed, yellow
-- dot visible), but didn't line up with this engine's own background/
-- icons, and zoomed oddly on top of our own canvas. Root cause: the
-- widget's own zoom LEVEL (an index, SetZoom(0..GetZoomLevels()-1))
-- determines how many real-world yards its content spans - that's
-- independent of pixel size, so resizing the frame to "fill the
-- window" (this function's first pass) changes how big the content
-- LOOKS without changing what real-world distance it represents,
-- which is exactly why the blip didn't land where our own drawn node
-- icon says it should.
--
-- Fix: read the widget's actual current view radius in yards
-- (C_Minimap.GetViewRadius() - confirmed available on this client the
-- same way C_Minimap.GetTrackingInfo/C_VignetteInfo etc. were already
-- confirmed this session) and pick whichever of the widget's real
-- discrete zoom levels makes its yards-per-pixel match this engine's
-- own background scale (self.ScaleDraw px-per-worldunit, divided by
-- the same YARDS_PER_WORLDUNIT conversion the Goto/gather-dedupe
-- sections already use) while still fitting the window. This is a
-- principled version of the exact thing this file's own header
-- explains Carbonite's real preset-search did (MapEngine.lua:3384-
-- 3391) and this project deliberately replaced for the old cosmetic-
-- blend use case (continuous smooth fill mattered more than exact
-- scale there) - here exact scale IS the point, so searching real
-- zoom levels is the correct trade this time, not a regression.
local GATHER_YARDS_PER_WORLDUNIT = 4.575

-- Fallback constants for a client (or moment) without
-- C_Minimap.GetViewRadius - ported from GatherMate2's own bundled
-- HereBeDragons-Pins-2.0.lua:66-83 (real, maintained library
-- constants also used to place that addon's own minimap pins, not
-- guessed here).
local MINIMAP_VIEW_RADIUS_FALLBACK = {
    [false] = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 3, [4] = 200, [5] = 133 + 1 / 3 },
    [true]  = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
}

local function GetMinimapViewRadius(zoom)
    if C_Minimap and C_Minimap.GetViewRadius then
        return C_Minimap.GetViewRadius()
    end
    local byIndoor = MINIMAP_VIEW_RADIUS_FALLBACK[IsIndoors() and true or false]
    return byIndoor and byIndoor[zoom]
end

-- Searches the widget's real zoom levels (visited most-zoomed-out
-- first, since view radius shrinks monotonically as the level index
-- rises - confirmed against the fallback table above) for the
-- largest one whose resulting size still fits the window, so the
-- patch shows as much real-world context as it can while staying
-- aligned. Sets the widget's real zoom to the chosen level as a side
-- effect (calling SetZoom per candidate costs nothing visible -
-- these all happen within one tick, before any frame renders).
-- Returns a fit width/height in this engine's own world-pos units
-- (same units ClipMMW already expects), or nil if not even the most-
-- zoomed-in level has a usable radius.
function MinimapEngine:ResolveLiveBlipFit()
    local mm = self.MMFrm
    local scale = self.ScaleDraw
    if not scale or scale <= 0 then return nil end

    local fitBound = LIVE_BLIP_FIT_MARGIN * min(self.MapW or 0, self.MapH or 0)
    local levels = (mm.GetZoomLevels and mm:GetZoomLevels()) or 1

    local bestFit, bestLevel
    for level = 0, levels - 1 do
        mm:SetZoom(level)
        local radius = GetMinimapViewRadius(level)
        if radius and radius > 0 then
            local fit = (2 * radius) / GATHER_YARDS_PER_WORLDUNIT
            if fit * scale <= fitBound then
                bestFit, bestLevel = fit, level
                break
            end
            if not bestFit or fit < bestFit then
                bestFit, bestLevel = fit, level
            end
        end
    end

    if bestLevel then
        mm:SetZoom(bestLevel)
    end
    return bestFit
end

-- Build-order step 17, ninth follow-up, same day: the faint ring
-- artifact at the round mask's edge (accepted as a cosmetic limit a
-- few follow-ups back - no further lever on Blizzard's own rendering,
-- see ClipMMW's header) gets reframed instead of fought again - a
-- deliberate radar look (soft green tint + a sweeping line with a
-- fading trail) gives the window its own visual identity, so the
-- edge reads as "part of the design" rather than a leftover artifact.
-- User's own explicit design, including the fade-via-discrete-
-- segments approach (no custom art asset exists or is available to
-- generate here, so the "trail" is several thin lines at shrinking
-- angular offsets behind the leading edge, each a bit more
-- transparent than the last, rather than a single continuously-
-- gradiented wedge texture).
--
-- All of it lives in its own frame (self.MMRadar), parented to
-- UIParent like the widget itself, NOT to mm - mm's own descendants
-- are what HideMinimapPassengers recursively hides every tick, which
-- would eat this too if it lived there (same trap the reverted edge-
-- cover border hit). Anchored CENTER-to-CENTER on mm (tracks its
-- position with no extra per-tick math), resized to match mm's own
-- current width each tick since that varies with zoom/fit. The tint
-- is masked to the same round shape as the widget itself (a
-- CreateMaskTexture using the identical TempPortraitAlphaMask path -
-- texture masking is long-standing, stable WoW API, unlike the
-- confirmed-broken SetClipsChildren from the earlier reverted
-- attempt, so no fallback-capability concern here). Each sweep
-- segment pivots at its own left-center point (SetRotation's
-- normalized rotation-center args), anchored by that same point to
-- the circle's center, so it reads as a clock hand swinging around a
-- fixed pivot rather than a line translating across the window.
local LIVE_BLIP_RADAR_DEGREES_PER_SEC = 55
-- Live-tested same day, second follow-up: even at 42 segments it still
-- read as "a bunch of lines," not a trail - the real cause is
-- geometric, not a segment-count/alpha-curve problem: these are thin
-- SPOKES fanning out from a shared center, and spokes necessarily
-- spread apart as they near the outer edge (the same way a wheel's
-- spokes are close at the hub and far apart at the rim) - at the old
-- 42/1px settings the gap between adjacent spokes at a typical patch
-- radius exceeded their own width, leaving visible slivers of
-- background between every one of them. Fixed by making the spokes
-- wide enough, and dense enough, that neighboring ones overlap at the
-- OUTER edge instead of gapping (see the per-tick loop's angleRad
-- math - unchanged - this is purely a density/width tuning fix).
-- User also asked for "the 1 line and a fading gradient behind it one
-- solid object" - WoW's plain Texture API has no true conic/angular
-- gradient primitive to draw that as literally one object, so this
-- keeps the proven multi-segment approach but gives the FIRST segment
-- (the sweep's current leading edge) its own distinct full-alpha,
-- thicker treatment so it reads as "the line," with the remaining
-- segments forming the fading trail behind it - same visual intent,
-- built from primitives already confirmed working on this client.
local LIVE_BLIP_RADAR_SEGMENTS = 90
local LIVE_BLIP_RADAR_TRAIL_SPAN_DEGREES = 75
local LIVE_BLIP_RADAR_LINE_THICKNESS = 2
local LIVE_BLIP_RADAR_LEAD_LINE_THICKNESS = 3
local LIVE_BLIP_RADAR_LEAD_ALPHA = 0.6
local LIVE_BLIP_RADAR_TINT_ALPHA = 0.10
local LIVE_BLIP_RADAR_R, LIVE_BLIP_RADAR_G, LIVE_BLIP_RADAR_B = 0.3, 1.0, 0.4

-- Live-tested same day: the sweep wasn't visibly moving. UpdateLiveBlips
-- (and this function in turn) only actually RUNS roughly every 0.05s -
-- Update()'s own Ttl accumulator gates the whole body - but the
-- `elapsed` it was passed down was the raw single-OnUpdate-frame delta
-- (~0.007-0.02s depending on framerate), not the ~0.05s that actually
-- passed since this function last ran. The angle was advancing at a
-- small fraction of LIVE_BLIP_RADAR_DEGREES_PER_SEC's real intent -
-- technically moving, just slow enough (a full revolution could take
-- a minute or more at a high framerate) to look static over a short
-- glance. Tracks its own wall-clock delta via GetTime() now, fully
-- decoupled from Update()'s own throttle/elapsed semantics - correct
-- regardless of framerate or how often this actually gets called.
function MinimapEngine:UpdateLiveBlipRadar(shown)
    if not shown then
        if self.MMRadar then
            self.MMRadar:Hide()
        end
        self.MMRadarLastTime = nil
        return
    end

    local mm = self.MMFrm
    local now = GetTime()
    if not self.MMRadar then
        local radar = CreateFrame("Frame", nil, UIParent)
        radar:SetPoint("CENTER", mm, "CENTER")

        local mask = radar:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        mask:SetAllPoints(radar)

        local tint = radar:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints(radar)
        tint:SetColorTexture(LIVE_BLIP_RADAR_R, LIVE_BLIP_RADAR_G, LIVE_BLIP_RADAR_B, LIVE_BLIP_RADAR_TINT_ALPHA)
        tint:AddMaskTexture(mask)

        radar.segments = {}
        for i = 1, LIVE_BLIP_RADAR_SEGMENTS do
            local seg = radar:CreateTexture(nil, "OVERLAY")
            seg:SetColorTexture(LIVE_BLIP_RADAR_R, LIVE_BLIP_RADAR_G, LIVE_BLIP_RADAR_B, 1)
            radar.segments[i] = seg
        end

        self.MMRadar = radar
        self.MMRadarAngle = 0
        self.MMRadarLastTime = now
    end

    local radar = self.MMRadar
    local dt = now - (self.MMRadarLastTime or now)
    self.MMRadarLastTime = now
    self.MMRadarAngle = (self.MMRadarAngle + dt * LIVE_BLIP_RADAR_DEGREES_PER_SEC) % 360

    local size = mm:GetWidth()
    radar:SetSize(size, size)

    local strata, level = mm:GetFrameStrata(), mm:GetFrameLevel()
    radar:SetFrameStrata(strata)
    radar:SetFrameLevel(level + 1)

    -- Live-tested same day: SetRotation on this client only takes
    -- (radians) - the 3-arg (radians, normalizedX, normalizedY) custom-
    -- pivot form this was written against errored ("bad argument #2")
    -- and spammed the error log every tick. Rotation always pivots
    -- around a texture's own center here, so a true one-sided "hand
    -- pinned at the circle's center" needs the PIVOT to BE that center
    -- - done by positioning each segment's own CENTER at the midpoint
    -- of where it should visually span (half the segment's length out
    -- from the circle's center, toward its current angle) via plain
    -- trig, then rotating it (default center pivot) by that same
    -- angle. The segment's inner end lands exactly on the circle's
    -- center and its outer end exactly on the circle's edge, with no
    -- pivot-point API involved at all.
    local radius = size / 2
    local stepDeg = LIVE_BLIP_RADAR_TRAIL_SPAN_DEGREES / LIVE_BLIP_RADAR_SEGMENTS
    for i, seg in ipairs(radar.segments) do
        local angleRad = math.rad(self.MMRadarAngle - (i - 1) * stepDeg)
        local offsetX = (radius / 2) * math.cos(angleRad)
        local offsetY = (radius / 2) * math.sin(angleRad)
        seg:SetPoint("CENTER", radar, "CENTER", offsetX, offsetY)
        seg:SetRotation(angleRad)
        if i == 1 then
            seg:SetSize(radius, LIVE_BLIP_RADAR_LEAD_LINE_THICKNESS)
            seg:SetAlpha(1)
        else
            seg:SetSize(radius, LIVE_BLIP_RADAR_LINE_THICKNESS)
            local t = (i - 1) / LIVE_BLIP_RADAR_SEGMENTS
            seg:SetAlpha(LIVE_BLIP_RADAR_LEAD_ALPHA * (1 - t) * (1 - t))
        end
    end

    radar:Show()
end

-- Per-tick positioning/sizing of the owned widget while gathering-
-- tracking is active - adapted from the archived Mode:Live's own
-- inline Update() block, now sized/zoomed via ResolveLiveBlipFit
-- above instead of a plain "fill the window" calculation (see that
-- function's own header for why). The zoom-level search only re-runs
-- when self.ScaleDraw actually changes (cached otherwise) - re-
-- probing every one of the widget's zoom levels every single tick
-- regardless of whether anything changed would be needless churn.
--
-- Simplified from the archive for this new purpose: no "Tiles" mode
-- gate (tied to a Mode button this revival doesn't use - this
-- function is only ever called while self.MMOwn is true, which
-- already serves as the gate), and always full alpha (the archive's
-- Ctrl/Alt "see-through" alpha was for a cosmetic background blend -
-- this revival's whole point is seeing native blips clearly, not
-- blending them in).
-- Build-order step 17, radar-layering follow-up (2026-11-11): this
-- engine's own markers (player dot, gather/service/quest icons) used
-- to get raised to a strata ABOVE mm/MMRadar whenever the live patch
-- was shown, via RaiseIconsAboveLivePatch/RestoreIconsFromLivePatch
-- below - confirmed live, user-reported at the time: the radar's
-- opaque sweep made icons disappearing underneath it newly obvious
-- ("get all of that under the yellow dots those seem to be on the
-- bottom"). That mechanism established the key technical fact this
-- follow-up still relies on: frame STRATA is a hard global sort key
-- that ignores parent/level entirely (unlike frame level, which only
-- compares directly within shared-parent siblings) - confirmed the
-- hard way, since a first attempt at reparenting each icon to
-- UIParent (mm/MMRadar's own parent) so a plain frame-level bump would
-- be an unambiguous sibling comparison was live-tested BROKEN:
-- ClipFrameW positions every one of these icons via a 3-arg
-- `frm:SetPoint("TOPLEFT", vx1, ...)` with no explicit relativeTo
-- frame, which WoW resolves against the icon's OWN PARENT implicitly -
-- reparenting to UIParent silently changed what that anchor was
-- relative to, landing most icons outside ClipFrameW's own bounds
-- check and hiding them.
--
-- Build-order step 21 same-day seventh follow-up (2026-11-11, 5-layer
-- rework): this ordering is now deliberately REVERSED. Direct request/
-- confirmation: Radar Layer (the live-blip patch below) is layer 5 of
-- the user's 5-layer spec, above Service Layer (layer 4, this engine's
-- own icons) - explicitly confirmed even knowing it undoes the step-17
-- fix above, because Radar Layer's whole purpose is seeing the native
-- minimap's own live blips clearly, and the always-on Service icons
-- sitting on top of them defeated that. So: RaiseIconsAboveLivePatch/
-- RestoreIconsFromLivePatch and their two small helpers are removed
-- outright - Service icons no longer get touched here at all, they
-- just stay at their normal strata. Instead, UpdateLiveBlips' own
-- MinimapSyncLayer call below now passes aboveHost=true, bumping mm
-- (and MMRadar, which derives its own strata directly from mm's) one
-- strata tier above the window's own baseline - the exact same proven
-- mechanism, just pointed the other direction. See MinimapWindow.lua's
-- chrome-strata fix (same follow-up) for why the title-bar buttons
-- needed an explicit strata of their own once mm could out-rank the
-- window's default strata this way.
function MinimapEngine:UpdateLiveBlips()
    local mm = self.MMFrm
    if not mm then return end

    if not self:MinimapSyncVisibility() then
        return
    end
    self.MMHiddenByMap = nil

    -- Build-order step 17, live-tested follow-up: the one-time hide in
    -- ShowLiveBlips wasn't enough - confirmed live, a passenger button
    -- was still appearing. Several addon minimap-button libraries keep
    -- re-showing/repositioning their own button from an ongoing OnUpdate
    -- (that's how they support being dragged around the minimap edge),
    -- which would undo a one-time Hide() almost immediately. Re-scanning
    -- on a cheap throttle (not every tick) catches that without the
    -- cost of a full recursive walk 20x/sec.
    local now = GetTime()
    if not self.MMPassengerCheckAt or now >= self.MMPassengerCheckAt then
        self.MMPassengerCheckAt = now + 0.5
        self.MMHiddenChildren = self.MMHiddenChildren or {}
        HideMinimapPassengers(mm, self.MMHiddenChildren, self)
    end

    local shown = false
    if not InCombatLockdown() then
        if self.MMScale ~= self.ScaleDraw or not self.MMLiveFit then
            self.MMLiveFit = self:ResolveLiveBlipFit()
        end
        local fit = self.MMLiveFit
        if fit and fit > 0 and self:ClipMMW(mm, self.PlyrX, self.PlyrY, fit, fit) then
            shown = true
        end
    end

    if shown then
        mm:SetAlpha(LIVE_BLIP_ALPHA)
        self:MinimapUpdateMask()
        self:MinimapSyncLayer(self.Win.Frm:GetFrameLevel() or 1, 1, true)
        self:MinimapDetachFrms()

        if self.MMZoomType ~= 1 or self.MMScale ~= self.ScaleDraw then
            self.MMZoomType = 1
            self.MMScale = self.ScaleDraw
            local ok, err = pcall(function()
                local zoom = mm:GetZoom() or 0
                local altZoom = zoom == 0 and 1 or 0
                mm:SetZoom(altZoom)
                mm:SetZoom(zoom)
            end)
            if not ok then
                AzerothAtlas.Core.Logger:warn("zoom-kick failed: %s", tostring(err))
            end
        end
        self:UpdateLiveBlipRadar(true)
    else
        self.MMZoomType = 0
        mm:Hide()
        self:UpdateLiveBlipRadar(false)
    end
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
--     surrounding machinery for. UpdateWorldArt (removed build-order
--     step 21 same-day sixth follow-up - see its own removal comment)
--     used to be a fresh, much smaller trigger calling the exact same
--     real API primitives (GetArtSourceMapID/GetArtLayerTextures)
--     UpdateWorld itself calls for the texture-fetch step; those two
--     primitives are still here and still load-bearing (MoveZoneTiles'
--     own continent/zone sizing math, Overlay's GetCachedLayerInfo),
--     just no longer feeding a dedicated flat zone-tile backdrop.
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
-- function serves the zone==0 continent-overview render path. That
-- path used to be dead here (nothing ever set self.Zone = 0 - see
-- RefreshCurrentZone), so this used to be left out rather than built
-- unused. Build-order step 20 revives it below as InitContinentFrames
-- - see that function's own header for why it's a SEPARATE function
-- rather than extending this one.
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

-- Build-order step 20: real Carbonite's own ContFrms half of InitFrames
-- (MapEngine.lua:2300-2334), adapted rather than ported verbatim. Real
-- Carbonite keeps ALL continents' frame pools alive simultaneously
-- because its MoveContinents can show every continent at once (the
-- "World of Azeroth" selector screen, gated on NXWorldShow - a mode
-- this addon doesn't implement, see MoveContinents' own research notes
-- in CHANGELOG.md). This addon only ever shows ONE continent's art at
-- a time (see MoveCurZoneTiles below), so there's no need for that
-- screen's own machinery - just a small static pool per continent,
-- built once and never re-textured.
--
-- Unlike TileFrms (never textured now - see UpdateWorldArt's own
-- removal comment, build-order step 21 same-day sixth follow-up),
-- continent art never changes at runtime, so the texture is set ONCE,
-- right here, and MoveZoneTiles' existing zone==0 branch only ever
-- positions/crops these frames afterward - confirmed by reading that
-- branch in both sources: it has no SetTexture call of its own.
--
-- Real Carbonite's own gate for which texture source to use
-- (`Nx.isRetail or (Nx.isCamelot and rootMapID > 1000)`) is false for
-- both Kalimdor (12) and Eastern Kingdoms (13) - low, non-retail
-- mapIDs - so it never even tries the modern C_Map API for these and
-- goes straight to the static per-tile file path built from
-- MapInfo[cont].FileName. This addon does the same unconditionally
-- (no modern-API attempt at all) since MapInfo[cont].FileName is only
-- ever set for continents that actually have the re-exported static
-- art (see NxMapData.lua's own comment on why Forever needed to
-- re-export it) - a continent without FileName (Zephras Isle, index 3)
-- simply gets no ContFrms pool and MoveCurZoneTiles' coverage check
-- below never selects it.
--
-- ContBlks[cont][i] == 0 means that tile index is part of the
-- deliberately-cropped outer columns (NxMapData.lua's own comment) -
-- skipped entirely, not just hidden, same as real Carbonite. frms[i]
-- stays nil for those indices; MoveZoneTiles' per-tile loop already
-- null-checks frm before touching it, so a sparse pool here needs no
-- extra handling there.
function MinimapEngine:InitContinentFrames()
    self.ContFrms = {}
    local f = self.Frm
    for cont = 1, self.ContCnt or 0 do
        local info = self.MapInfo and self.MapInfo[cont]
        local fileName = info and info.FileName
        if fileName then
            local mask = self.ContBlks and self.ContBlks[cont]
            local tilex = info.TileX or 4
            local tiley = info.TileY or 3
            self.ContFrms[cont] = {}
            for i = 1, tilex * tiley do
                if not mask or mask[i] ~= 0 then
                    local cf = CreateFrame("Frame", nil, f)
                    self.ContFrms[cont][i] = cf
                    local t = cf:CreateTexture()
                    t:SetAllPoints(cf)
                    t:SetSnapToPixelGrid(false)
                    t:SetTexelSnappingBias(0)
                    cf.texture = t
                    t:SetTexture("Interface\\WorldMap\\" .. fileName .. "\\" .. fileName .. i)
                end
            end
        end
    end
end

-- Hides every continent's ContFrms pool except exceptCont (pass nil to
-- hide all of them). Called from MoveCurZoneTiles/Update's DETAIL_SCALE
-- gate whenever Art Map is about to show zone-level art, close-zoomed
-- art, or is debug-hidden entirely - any of those states must not leave
-- a previous tick's continent tiles showing underneath.
function MinimapEngine:HideContinentFrames(exceptCont)
    if not self.ContFrms then return end
    for cont, pool in pairs(self.ContFrms) do
        if cont ~= exceptCont then
            self:HideZoneTileFrames(pool)
        end
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

-- Build-order step 18 (2026-11-11, map-layering fix): explicit, non-
-- colliding frame-level offsets for the Art Map layer (TileFrms,
-- MoveZoneTiles/MoveCurZoneTiles below) and the Terrain Texture layer
-- (MiniFrms, UpdateMiniFrames further down) - previously both drew at
-- the exact same `self.Frm:GetFrameLevel()` with no relative offset,
-- so WoW's implementation-defined same-level sibling draw order
-- decided which one won in the one zoom band where both show (zoomed
-- out past DETAIL_SCALE) - confirmed as the root cause of "different
-- results at different zooms/pans" reported live via screenshot
-- comparison. Declared here, ahead of MoveZoneTiles/MoveCurZoneTiles,
-- rather than down near DETAIL_SCALE where UpdateMiniFrames' own
-- section starts - Lua locals aren't visible to code written earlier
-- in the same chunk, and MoveCurZoneTiles (below) needed this before
-- UpdateMiniFrames' section does; this project has hit that exact
-- forward-reference trap once before (see CHANGELOG.md, build-order
-- step 9h-9k's "nil constant" note).
--
-- Verified against real Carbonite (Carbonite/Modules/Map/MapEngine.lua
-- :9886-9894): for an ORDINARY zone (the only zone type this
-- simplified port implements - no City-map special-casing), the real
-- per-tick order is MoveCurZoneTiles() then UpdateMiniFrames(), and
-- both draw through a shared, incrementing self.Level counter - so
-- Terrain (drawn second) ends up one level ABOVE Art there. (Real
-- Carbonite only reverses this for City maps specifically, a branch
-- this port never reaches.) This port's own header comment used to
-- assert the opposite ("Art ALSO drawn on top of it") - that was
-- written without checking the real call order; corrected at
-- UpdateMiniFrames' own header to match the order actually implemented
-- here. User confirmed Terrain-above-Art as the intended look (detail
-- peeking through over the broad backdrop), matching the real source.
--
-- Build-order step 21 same-day sixth follow-up (2026-11-11, "Art Map"
-- redefined as the Overlay layer): the user's own mental model of
-- "Art Map" was never the flat zone-tile backdrop this offset
-- originally drew (self.TileFrms, fed by UpdateWorldArt) - it's the
-- zone "revealed" overlay art (what this file's code calls Overlay).
-- That follow-up put Overlay on the exact same literal level as Base's
-- continent backdrop and flagged (rather than fixed) the resulting
-- same-level sibling-order risk - live screenshots the same day
-- confirmed it: part of Hillsbrad Foothills' Overlay art (the
-- Durnholde Keep region) rendered BEHIND Base instead of in front of
-- it, visible as a flat, undetailed patch where Base's own texture
-- showed through.
--
-- Build-order step 21 same-day SEVENTH follow-up (2026-11-11, full
-- 5-layer rework): rather than patch that one collision, the user
-- redefined the whole stack. Direct request: *"there should be 5
-- parent layers ... 1 The base -> the flat continent backdrop / 2 Art
-- Map -> Every zone's hand-catalogued 'revealed' sub-region art,
-- stitched across the whole continent / 3 Terrain Texture -> Real
-- close-zoom minimap detail tiles / 4 Service Layer -> ... the service
-- icons quest markers goto and corpse trail corpse dot and the player
-- marker all live here the gathernodes and their backdrop / 5 Radar
-- Layer -> the sweeping radar green overlay and our yellow dots for
-- active gathering nodes ... this is the layer order to get the proper
-- functionality moving forward from here not that each layer works on
-- its own."* Confirmed via follow-up: gather-node icons stay in
-- Service Layer exactly as written (layer 5's "yellow dots" are the
-- NATIVE Blizzard minimap's own harvest-node blips, picked up through
-- the Live Blip Radar patch - not this addon's own custom icons,
-- which are always-visible and separate). Also confirmed: Radar Layer
-- must render ABOVE Service Layer - see UpdateLiveBlips' own header
-- comment below for that reversal (it lives outside this file's
-- self.Frm level stack entirely; it's a frame-strata change, not a
-- level one).
--
-- New scheme: Base, Art Map, and Terrain each now get their OWN
-- guaranteed-distinct level (BASE_LEVEL_OFFSET/ART_MAP_LEVEL_OFFSET/
-- TERRAIN_TILE_LEVEL_OFFSET below) - this fully RESOLVES the Base-vs-
-- Overlay collision above as a side effect, not just mitigates it:
-- different literal FrameLevels are a deterministic WoW ordering rule,
-- unlike same-level siblings. Service Layer deliberately collapses
-- every icon type (previously 7 distinct offsets: gather +5, service
-- +6, quest +7, goto/corpse trail +8, goto/corpse dot +10, player
-- marker +11) onto ONE shared SERVICE_LEVEL_OFFSET, per the explicit
-- "not that each layer works on its own" instruction - same honest
-- flagging as before: inter-item order WITHIN Service Layer (e.g.
-- whether the player marker always wins over a quest marker at the
-- same pixel) is now implementation-defined, accepted rather than
-- fixed, because the user asked for the simplification knowing that.
-- Level 4 is deliberately left unnamed/reserved rather than given its
-- own constant - GatherFrms' own backdrop (:~3722) derives its level
-- as "icon level - 1" and nothing else uses it; it's an internal
-- detail of one icon pair, not a user-facing layer, so
-- SERVICE_LEVEL_OFFSET starts at 5 specifically to leave 4 free for it
-- (if it instead collapsed straight onto Terrain's level 3, the
-- backdrop would visually collide with every Terrain tile).
local BASE_LEVEL_OFFSET = 1
local ART_MAP_LEVEL_OFFSET = 2
local TERRAIN_TILE_LEVEL_OFFSET = 3
-- 2026-11-16: City / Dungeon map layer (UpdateAreaMap) - a city's or
-- dungeon's own art map, above Terrain and below the Service layer
-- (explicit user request). Everything from here up moved one level.
local CITY_LEVEL_OFFSET = 4
-- level 5 reserved: GatherFrms backdrop only (derived as icon level - 1)
local SERVICE_LEVEL_OFFSET = 6
-- 2026-11-16: the player marker sits above everything the map draws -
-- in the overlay strata (MinimapWindow.OVERLAY_STRATA, the same tier
-- the live-blip radar reaches) and well above it on level. Chrome is
-- at +50 in that same strata, so buttons still win.
local PLAYER_LEVEL_OFFSET = 30
MinimapEngine.SERVICE_LEVEL_OFFSET = SERVICE_LEVEL_OFFSET

-- `/aatlas hideart` / `/aatlas hideterrain` - toggle self.DebugHideArt/
-- self.DebugHideTerrain (read in Update()'s zoom-gate block further
-- down this file), letting a live tester force-isolate one of these
-- two layers at a time to characterize an artifact without the other
-- layer's own tiles in the way. Same "keep it, don't delete it after
-- use" treatment as scanblips/diffblips/mmpassengers below.
--
-- Build-order step 18 follow-up (2026-11-11): MinimapWindow.lua now
-- has two title-bar checkboxes (TerrainCB/ArtMapCB) backed by these
-- exact same two fields, for live testers who'd rather click than
-- type. Keep both in sync here, same pattern as MinimapWindow.lua's
-- own `/aatlas minimap hide|show` refreshing the Settings window's
-- checkbox - the window may not be open (self.Win nil) or the
-- checkbox may not exist yet (created in Open(), not at module
-- enable), so both are nil-guarded rather than assumed present.
-- 2026-11-16: those title-bar checkboxes moved to Settings > Map and
-- the switches persist now - a slash-command toggle saves the new state
-- (SetLayerShown) and refreshes the Settings window's checkboxes.
local LAYER_KEY_FOR_FIELD = { DebugHideArt = "Art", DebugHideBase = "Base", DebugHideTerrain = "Terrain" }
local function syncLayerCheckbox(_, debugHideField)
    local key = LAYER_KEY_FOR_FIELD[debugHideField]
    if key then
        MinimapEngine:SetLayerShown(key, not MinimapEngine[debugHideField])
    end
    local SettingsWindow = AzerothAtlas.Modules.Settings and AzerothAtlas.Modules.Settings.SettingsWindow
    if SettingsWindow and SettingsWindow.Refresh then SettingsWindow:Refresh() end
end

AzerothAtlas.Core.SlashCommands:Register("hideart", function()
    local Logger = AzerothAtlas.Core.Logger:Get("Map")
    MinimapEngine.DebugHideArt = not MinimapEngine.DebugHideArt
    Logger:info("hideart: Art Map layer is now %s",
        MinimapEngine.DebugHideArt and "FORCED HIDDEN" or "normal")
    local win = AzerothAtlas.Modules.Map.MinimapWindow
    syncLayerCheckbox(win and win.ArtMapCB, "DebugHideArt")
end, "toggle forcing the Art Map (zone revealed overlay art) layer hidden - map-layering diagnostic")

-- Build-order step 20 follow-up (2026-11-11): split out of Art Map
-- into its own independently-togglable layer, direct user request
-- ("move the continent to its own layer call it base give it a toggle
-- box too") - see MoveCurZoneTiles' own header comment for how the two
-- flags now apply independently to their own half of that function.
AzerothAtlas.Core.SlashCommands:Register("hidebase", function()
    local Logger = AzerothAtlas.Core.Logger:Get("Map")
    MinimapEngine.DebugHideBase = not MinimapEngine.DebugHideBase
    Logger:info("hidebase: Base (continent backdrop) layer is now %s",
        MinimapEngine.DebugHideBase and "FORCED HIDDEN" or "normal")
    local win = AzerothAtlas.Modules.Map.MinimapWindow
    syncLayerCheckbox(win and win.BaseCB, "DebugHideBase")
end, "toggle forcing the Base (continent backdrop) layer hidden - map-layering diagnostic")

AzerothAtlas.Core.SlashCommands:Register("hideterrain", function()
    local Logger = AzerothAtlas.Core.Logger:Get("Map")
    MinimapEngine.DebugHideTerrain = not MinimapEngine.DebugHideTerrain
    Logger:info("hideterrain: Terrain Texture layer is now %s",
        MinimapEngine.DebugHideTerrain and "FORCED HIDDEN" or "normal")
    local win = AzerothAtlas.Modules.Map.MinimapWindow
    syncLayerCheckbox(win and win.TerrainCB, "DebugHideTerrain")
end, "toggle forcing the Terrain Texture (close-zoom detail tile) layer hidden - map-layering diagnostic")

-- Build-order step 21 follow-up (2026-11-11, temporary diagnostic):
-- live-tested, overlay art still looked "100% unexplored" even after
-- SHOW_UNEXPLORED was flipped to disable the dimming pass entirely -
-- meaning either that fix didn't land, or (more likely per a closer
-- read of real Carbonite) UpdateOverlay is returning early somewhere
-- BEFORE it ever reaches that logic - GetCachedLayerInfo in
-- particular depends on the same modern C_Map.GetMapArtLayers API
-- build-order step 20 already found unreliable enough to avoid for
-- continent root art. `/aatlas dbgoverlay` prints (throttled to once per
-- ~3s per mapId, so it stays readable) exactly which early-return (if
-- any) UpdateOverlay is hitting for the current/recently-drawn zones.
-- Meant to be removed once the real cause is confirmed and fixed -
-- not a permanent feature like hideart/hideterrain above.
local DebugOverlayLastLog = {}
local function DebugOverlayLog(mapId, fmt, ...)
    if not MinimapEngine.DebugOverlay then return end
    local now = GetTime()
    if (DebugOverlayLastLog[mapId] or 0) + 3 > now then return end
    DebugOverlayLastLog[mapId] = now
    AzerothAtlas.Core.Logger:Get("Map"):info("dbgoverlay[%s]: " .. fmt, mapId, ...)
end

AzerothAtlas.Core.SlashCommands:Register("dbgoverlay", function()
    MinimapEngine.DebugOverlay = not MinimapEngine.DebugOverlay
    AzerothAtlas.Core.Logger:Get("Map"):info("dbgoverlay: %s",
        MinimapEngine.DebugOverlay and "ON (throttled ~3s/zone)" or "off")
end, "toggle temporary diagnostic logging for UpdateOverlay's early-return points - build-order step 21 bug hunt")

-- Kept verbatim from Nx.Map:MoveZoneTiles (MapEngine.lua:9533-9690) -
-- the real tile-grid crop/position/texcoord math. Not approximated;
-- every branch is unchanged. The zone==0 continent-overview path used
-- to be dead code here (see InitTileFrames' header above) - build-
-- order step 20 wires it up via InitContinentFrames/MoveCurZoneTiles,
-- with one deliberate deviation from "kept verbatim" in that branch's
-- own tilex/tiley setup (see its comment there for why).
--
-- Build-order step 21 same-day sixth follow-up (2026-11-11): the
-- `zone ~= 0` branch below and the `frms == self.TileFrms` check
-- further down are now dead code in practice - MoveCurZoneTiles no
-- longer calls this with zone ~= 0/frms == self.TileFrms at all, since
-- the flat zone-tile backdrop that call used to draw was removed
-- outright (see UpdateWorldArt's own removal comment). Left in place
-- rather than surgically cut, same reasoning as other "kept verbatim"
-- ported functions in this file: this one is explicitly a direct port
-- with every branch unchanged, and the zone==0 (continent) branch this
-- function's real callers now exclusively use is interleaved with the
-- dead one throughout, not cleanly separable without risking the part
-- that's still load-bearing.
function MinimapEngine:MoveZoneTiles(cont, zone, frms, alpha, level)
    local zname, zx, zy, zw, zh = self:GetWorldZoneInfo(cont, zone)
    if not zx then
        self:HideZoneTileFrames(frms)
        return
    end

    local scale = self.ScaleDraw
    local tilex, tiley, layerInfo
    if zone == 0 then
        -- Build-order step 20: real Carbonite only even TRIES the modern
        -- C_Map layer API here when `Nx.isRetail or (Nx.isCamelot and
        -- rootMapID > 1000)` (MapEngine.lua:2310-2311) - for Kalimdor
        -- (12) / Eastern Kingdoms (13) on this non-retail, low-mapID
        -- flavor that's always false, so it goes straight to the static
        -- MapInfo[cont].FileName tiling InitContinentFrames already
        -- baked into ContFrms. Skipping the attempt here too (not just
        -- falling back after it returns nothing) avoids a real risk:
        -- if GetArtLayers(rootMapID) ever returned SOME layer info with
        -- different dimensions than the 4x3 grid ContFrms was actually
        -- built with, tilex/tiley below would mismatch the frame pool's
        -- real shape.
        layerInfo = nil
        tilex = self.MapInfo[cont].TileX or 4
        tiley = self.MapInfo[cont].TileY or 3

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
--
-- Build-order step 20: added the zone-vs-continent choice below. A
-- single zone's own art only covers that zone's own world-space extent
-- (zw/zh here) - once the window/zoom combo needs to see MORE world-
-- space than that on its longer axis, there is nothing past the
-- zone's edge to draw, which is exactly the "only one zone loads and
-- it's blank beyond that" symptom this addresses. This is deliberately
-- its OWN geometric check, not a reuse of UpdateMiniFrames' dynamic-
-- radius formula below - that one is locked in as Terrain-only and
-- must not be touched or shared (see this file's TerrainBrightness
-- comments / CHANGELOG build-order step 19).
--
-- Build-order step 20 follow-up (2026-11-11, "Base" layer split):
-- the continent backdrop got its own independent toggle
-- (self.DebugHideBase, title-bar BaseCB) separate from Art Map's
-- self.DebugHideArt - direct user request ("move the continent to its
-- own layer call it base give it a toggle box too"). Previously
-- DebugHideArt being true meant MoveCurZoneTiles never even ran
-- (Update()'s own gate used it as a top-level branch), which forced
-- continent hidden too whenever Art Map was off - not actually
-- independent.
--
-- Build-order step 21 same-day sixth follow-up (2026-11-11, "Art Map"
-- redefined as Overlay): this function's OTHER branch - drawing the
-- current zone's own flat tile backdrop into self.TileFrms, fed by
-- UpdateWorldArt - is gone as of this follow-up. The user's own "Art
-- Map" was always meant to be the zone "revealed" overlay art (see
-- BASE_LEVEL_OFFSET's own header comment above for the full 5-layer
-- request), not this flat backdrop, so there's nothing left for
-- DebugHideArt to gate here - this function is now Base-only (the
-- continent backdrop decision, now its own BASE_LEVEL_OFFSET as of the
-- same-day seventh follow-up), despite its name still describing the
-- removed mechanism. Left unrenamed since every caller/comment already
-- refers to it by this name and a rename wasn't asked for.
function MinimapEngine:MoveCurZoneTiles()
    -- (TileFrms now belongs to the City / Dungeon map layer -
    -- UpdateAreaMap - and is no longer cleared here.)

    if not self.Cont then
        self:HideContinentFrames()
        return
    end

    -- 2026-11-17: the Azeroth view draws every continent.
    if self.ShowAllConts and self.ContFrms then
        local lvl = (self.Frm:GetFrameLevel() or 1) + BASE_LEVEL_OFFSET
        for cont, pool in pairs(self.ContFrms) do
            if self.DebugHideBase then
                self:HideZoneTileFrames(pool)
            else
                self:MoveZoneTiles(cont, 0, pool, self.BackgndAlpha or 1, lvl)
            end
        end
        return
    end

    local level = (self.Frm:GetFrameLevel() or 1) + BASE_LEVEL_OFFSET
    local info = self.MapInfo and self.MapInfo[self.Cont]
    local fileName = info and info.FileName
    local contPool = fileName and self.ContFrms and self.ContFrms[self.Cont]

    if contPool then
        local _, _, _, zw, zh = self:GetWorldZoneInfo(self.Cont, self.Zone)
        local scaleDraw = self.ScaleDraw
        if not scaleDraw or scaleDraw <= 0 then scaleDraw = 1 end
        local neededSpan = max(self.MapW or 0, self.MapH or 0) / scaleDraw

        if zw and zh and neededSpan > max(zw, zh) then
            if self.DebugHideBase then
                self:HideContinentFrames()
            else
                self:HideContinentFrames(self.Cont)
                self:MoveZoneTiles(self.Cont, 0, contPool, self.BackgndAlpha or 1, level)
            end
            return
        end
    end

    self:HideContinentFrames()
end

---------------------------------------------------------------------------------------
-- 2026-11-16: persisted layer switches (Settings > Map). The engine
-- still reads its long-standing DebugHide* fields every tick; these
-- functions just load them from / save them to
-- AzerothAtlas.db.profile.MapLayers. Missing key = shown, same
-- "absent means on" convention as MapFilters.
---------------------------------------------------------------------------------------

local LAYER_FIELDS = {
    Base    = "DebugHideBase",
    Art     = "DebugHideArt",
    Terrain = "DebugHideTerrain",
    City    = "HideCityArt",
    Dungeon = "HideDungeonArt",
}

function MinimapEngine:LoadLayerSettings()
    local layers = AzerothAtlas.db and AzerothAtlas.db.profile and AzerothAtlas.db.profile.MapLayers or {}
    for key, field in pairs(LAYER_FIELDS) do
        self[field] = layers[key] == false
    end
end

function MinimapEngine:IsLayerShown(key)
    local layers = AzerothAtlas.db and AzerothAtlas.db.profile and AzerothAtlas.db.profile.MapLayers
    return not layers or layers[key] ~= false
end

function MinimapEngine:SetLayerShown(key, on)
    local field = LAYER_FIELDS[key]
    if not field then return end
    if AzerothAtlas.db and AzerothAtlas.db.profile then
        AzerothAtlas.db.profile.MapLayers = AzerothAtlas.db.profile.MapLayers or {}
        AzerothAtlas.db.profile.MapLayers[key] = on and true or false
    end
    self[field] = not on
end

---------------------------------------------------------------------------------------
-- 2026-11-16: dungeon maps. Instances aren't in Carbonite's static zone
-- catalog (NxMapData.lua), so the engine used to draw nothing inside
-- one. Each dungeon floor the player enters is now registered as a
-- zone of its own on a made-up continent (DUNGEON_CONT), placed far
-- away from the real continents' world coordinates. After that, every
-- existing piece - zoom, pan, auto-follow, the player marker, gotos -
-- works on it unchanged, and UpdateAreaMap draws the floor's own map
-- art (the same Blizzard map art the dungeon's world map uses, read
-- with C_Map.GetMapArtLayerTextures - the approach
-- ForeverDungeonJournal's MapArtFinder already proves works on this
-- client).
--
-- Size: if the client reports the floor's size in yards
-- (C_Map.GetMapWorldSize) it is converted to this engine's world units
-- (4.575 yards each, the constant used throughout this file);
-- otherwise a typical dungeon size is assumed. That only affects the
-- zoom level the floor opens at and the yard readouts, not where
-- anything is drawn on the floor's map.
---------------------------------------------------------------------------------------

local DUNGEON_CONT = 99
MinimapEngine.DUNGEON_CONT = DUNGEON_CONT
local DUNGEON_DEFAULT_SCALE = 1.5   -- ~690 yards across

function MinimapEngine:RegisterInstanceMap(mapId)
    if not mapId or mapId == 0 then return nil end
    local inInstance, instType = IsInInstance()
    if not inInstance or (instType ~= "party" and instType ~= "raid") then
        return nil
    end

    local scale = DUNGEON_DEFAULT_SCALE
    if C_Map and C_Map.GetMapWorldSize then
        local ok, w = pcall(C_Map.GetMapWorldSize, mapId)
        if ok and type(w) == "number" and w > 10 then
            scale = w / 4.575 / 100
        end
    end

    self.MapInfo[DUNGEON_CONT] = self.MapInfo[DUNGEON_CONT]
        or { X = 100000, Y = 100000, Name = "Instance" }
    local winfo = self.MapWorldInfo[mapId] or {}
    winfo.Scale = scale
    winfo.X = 0
    winfo.Y = 0
    winfo.Dungeon = true
    if not winfo.Name then
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
        winfo.Name = info and info.name
    end
    self.MapWorldInfo[mapId] = winfo

    self.MapZones[DUNGEON_CONT] = self.MapZones[DUNGEON_CONT] or {}
    local list = self.MapZones[DUNGEON_CONT]
    for _, id in ipairs(list) do
        if id == mapId then return DUNGEON_CONT end
    end
    list[#list + 1] = mapId
    return DUNGEON_CONT
end

---------------------------------------------------------------------------------------
-- 2026-11-16: dungeon floors (levels) and WoW Forever's own dungeons.
--
-- A dungeon is a list of floors, built once per instance/floor change
-- by ResolveDungeonMap and kept in self.DungeonFloors:
--   { mapId, name, spec, posMap }
-- Every floor is registered as its own zone on DUNGEON_CONT at the
-- same origin, so whichever floor is being looked at is drawn in the
-- same space.
--
-- Two sources of floors:
--   1. The client's own dungeon maps - the floor the player is on and
--      its siblings from C_Map's map group (Blizzard's own world-map
--      floor dropdown reads the same list). Art and positions come
--      from the client.
--   2. WoW Forever's new dungeons (The Drowned City, Krol'dok
--      Stronghold, ...), which have no map art in the client. Leatrix
--      Maps ships art for them; when that addon is installed, its art
--      file is drawn here (read from its folder, not copied - the art
--      is third-party work Leatrix uses with permission). CUSTOM_ART
--      below is Leatrix_Maps.lua's own dungeonArt rows for them. These
--      floors get made-up map ids (CUSTOM_FLOOR_BASE + instance * 10 +
--      floor). The player is placed on one only when the client
--      reports a map of its own for that dungeon (posMap).
--
-- The floor shown is the player's (PlayerFloor) unless the user picked
-- another with the level bar on the map (ViewFloor; MinimapWindow's
-- UpdateLevelBar). The player marker and party dots only show on the
-- floor they are on.
---------------------------------------------------------------------------------------

local CUSTOM_FLOOR_BASE = 900000
local LEATRIX_ART = "Interface\\AddOns\\Leatrix_Maps\\Leatrix_Maps_Dungeon_Art"
local LEATRIX_ATLAS_W, LEATRIX_ATLAS_H = 2048, 4096
-- [instance id] = { { x, y, h (default 683), file suffix, name }, ... }
local CUSTOM_ART = {
    [2959] = { { x = 0, y = 1368, name = "City of Dalaran (1)" },
               { x = 1024, y = 1368, name = "City of Dalaran (2)" } },
    [2998] = { { x = 0, y = 2060 } },                  -- Excavation Site: Wetlands
    [2999] = { { x = 1024, y = 2060 } },               -- Ruins of Lordaeron
    [3065] = { { x = 0, y = 2752 } },                  -- The Hall of Thanes
    [2970] = { { x = 0, y = 0, file = "8" } },         -- The Drowned City
    [3039] = { { x = 1024, y = 0, file = "8" } },      -- Krol'dok Stronghold
    [2994] = { { x = 0, y = 684, file = "8" } },       -- Alcaz Prison
    [3001] = { { x = 1024, y = 2736, file = "7" } },   -- The Shaper's Terrace
}
local NO_FLOORS = {}

local leatrixState
local function leatrixInstalled()
    if leatrixState == nil then
        leatrixState = false
        local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
        if getInfo then
            local ok, name, _, _, _, reason = pcall(getInfo, "Leatrix_Maps")
            leatrixState = ok and name ~= nil and reason ~= "MISSING" or false
        end
        if _G.LeaMapsDB ~= nil or _G.LeaMapsLC ~= nil then leatrixState = true end
    end
    return leatrixState
end

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Forever Dungeon Journal (2026-11-16, user pointed at it): its
-- FDJ.DUNGEON_MAPS holds every Forever dungeon's level art (with more
-- levels than Leatrix - The Drowned City's Atal'Byzal, Blackmaw Hold's
-- six) plus boss, entrance and level-exit positions on that art
-- (DungeonPins.lua draws those). Read live from the addon, so its
-- updates arrive here without copying anything. Only dungeons whose
-- every level is its own texture are taken; the classic ones FDJ draws
-- from the client's own tiles come from the client here too.
function MinimapEngine:GetFDJDungeon(instanceID)
    local fdj = _G.FDJ or _G.ForeverDungeonJournal_NS
    if type(fdj) ~= "table" or type(fdj.DUNGEON_MAPS) ~= "table" then return nil end
    local name = instanceID and type(fdj.INSTANCE_ID_TO_DUNGEON) == "table"
        and fdj.INSTANCE_ID_TO_DUNGEON[instanceID]
    if type(name) ~= "string" then return nil end
    local data = fdj.DUNGEON_MAPS[name]
    if not data then
        local alt = name:match("^The (.+)$") or ("The " .. name)
        data, name = fdj.DUNGEON_MAPS[alt], alt
    end
    if type(data) ~= "table" or type(data.floors) ~= "table" or not data.floors[1] then return nil end
    for _, f in ipairs(data.floors) do
        if type(f) ~= "table" or type(f.texture) ~= "string" then return nil end
    end
    return data, name
end

-- FDJ's entry and level for one of the game's dungeon maps (the classic
-- dungeons, whose levels FDJ keys by uiMapID; wings such as "Scarlet
-- Monastery: Library" are entries of their own): data, level, entry name.
local fdjByClientMap = {}
function MinimapEngine:GetFDJForClientMap(mapId)
    local fdj = _G.FDJ or _G.ForeverDungeonJournal_NS
    if type(fdj) ~= "table" or type(fdj.DUNGEON_MAPS) ~= "table" or not mapId then return nil end
    local hit = fdjByClientMap[mapId]
    if hit == nil then
        hit = false
        for name, data in pairs(fdj.DUNGEON_MAPS) do
            local floors = type(data) == "table" and type(data.floors) == "table" and data.floors or {}
            for i, f in ipairs(floors) do
                if type(f) == "table" and f.uiMapID == mapId then
                    hit = { data, i, name }
                    break
                end
            end
            if hit then break end
        end
        fdjByClientMap[mapId] = hit
    end
    if hit then return hit[1], hit[2], hit[3] end
    return nil
end

-- The game's world map tiles of a dungeon map (12 of them, 4 across 3
-- down), by its legacy map file (NxMapData's migration table, e.g.
-- WailingCaverns floor 1 -> Interface\WorldMap\WailingCaverns\
-- WailingCaverns1_1..12). This client returns no art for dungeon maps
-- through C_Map (2026-11-16, Wailing Caverns), but the files are there -
-- Forever Dungeon Journal draws from the same paths.
local function legacyTiles(mapId)
    local Map = AzerothAtlas.Map
    if not Map or not Map.GetLegacyMapInfo then return nil end
    local ok, _, floorNum, mapFile = pcall(Map.GetLegacyMapInfo, Map, mapId)
    if not ok or type(mapFile) ~= "string" then return nil end
    local base = "Interface\\WorldMap\\" .. mapFile .. "\\" .. mapFile
        .. ((floorNum and floorNum > 0) and floorNum or "") .. "_"
    local tiles = {}
    for n = 1, 12 do tiles[n] = base .. n end
    return tiles
end

-- Art specs: which file, and which rectangle of it (0-1 texcoords) is
-- the level's map.
local function fdjSpec(name, i, f)
    return { path = f.texture, u1 = 0, u2 = f.texRight or 1, v1 = 0, v2 = f.texBottom or 1,
        fdjName = name, fdjFloor = i }
end

local function leatrixSpec(s)
    local h = s.h or 683
    return {
        path = LEATRIX_ART .. (s.file or ""),
        u1 = (s.x + .5) / LEATRIX_ATLAS_W, u2 = (s.x + 1024 - .5) / LEATRIX_ATLAS_W,
        v1 = (s.y + .5) / LEATRIX_ATLAS_H, v2 = (s.y + h - .5) / LEATRIX_ATLAS_H,
    }
end

-- An outdoor zone in the static catalog (as opposed to a dungeon floor).
function MinimapEngine:IsOutdoorMap(mapId)
    local cont = mapId and self:FindContinent(mapId)
    return cont ~= nil and cont ~= DUNGEON_CONT
end

local function registerFloor(self, mapId, name, spec, posMap, blank)
    local scale = DUNGEON_DEFAULT_SCALE
    local sizeMap = posMap or (not spec and mapId)
    if sizeMap and C_Map and C_Map.GetMapWorldSize then
        local ok, w = pcall(C_Map.GetMapWorldSize, sizeMap)
        if ok and type(w) == "number" and w > 10 then scale = w / 4.575 / 100 end
    end
    self.MapInfo[DUNGEON_CONT] = self.MapInfo[DUNGEON_CONT]
        or { X = 100000, Y = 100000, Name = "Instance" }
    local winfo = self.MapWorldInfo[mapId] or {}
    winfo.Scale, winfo.X, winfo.Y, winfo.Dungeon = scale, 0, 0, true
    winfo.CustomArt, winfo.PosMap, winfo.Blank = spec, posMap, blank
    if name and name ~= "" then
        winfo.Name = name
    elseif not winfo.Name and not spec then
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
        winfo.Name = info and info.name
    end
    self.MapWorldInfo[mapId] = winfo
    self.MapZones[DUNGEON_CONT] = self.MapZones[DUNGEON_CONT] or {}
    local list = self.MapZones[DUNGEON_CONT]
    for _, id in ipairs(list) do
        if id == mapId then return end
    end
    list[#list + 1] = mapId
end

-- A client map that is a dungeon floor: Blizzard's map types Dungeon
-- (4), Micro (5) and Orphan (6). Not the world, a continent or a zone -
-- inside The Drowned City the client reports no map for the player and
-- falls back to 947, the whole world (first live test, 2026-11-16).
local function isDungeonMapType(mapId)
    if not mapId or mapId == 0 or not C_Map.GetMapInfo then return false end
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    local t = ok and info and info.mapType
    return type(t) == "number" and t >= 4
end

function MinimapEngine:BuildDungeonFloors(instanceID, playerMap)
    local dungeonMap = playerMap and playerMap ~= 0 and not self:IsOutdoorMap(playerMap)
        and isDungeonMapType(playerMap) and playerMap or nil
    local floors
    if dungeonMap then
        floors = {}
        local members
        if C_Map.GetMapGroupID and C_Map.GetMapGroupMembersInfo then
            local ok, group = pcall(C_Map.GetMapGroupID, dungeonMap)
            if ok and readable(group) and group then
                local ok2, list = pcall(C_Map.GetMapGroupMembersInfo, group)
                if ok2 and type(list) == "table" and #list > 0 then members = list end
            end
        end
        if members then
            for _, m in ipairs(members) do
                if m.mapID then floors[#floors + 1] = { mapId = m.mapID, name = m.name } end
            end
        end
        if #floors == 0 then floors[1] = { mapId = dungeonMap } end
        local art = self:GetArtLayerTextures(dungeonMap, 1)
        if art and art[1] then return floors end
    end
    -- 2026-11-16: the game names no map inside the instance - a classic
    -- one's own maps, from the room data's list (DungeonRooms.lua).
    local listed = not dungeonMap and self.GetInstanceClientFloors and self:GetInstanceClientFloors(instanceID)
    if listed and listed[1] then
        local art = self:GetArtLayerTextures(listed[1], 1)
        floors = {}
        for i, id in ipairs(listed) do
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
            local name = info and info.name
            if art and art[1] then
                floors[i] = { mapId = id, name = name }
            elseif i <= 9 then
                -- No art from C_Map: FDJ's own picture of this level if it
                -- has one (Wailing Caverns' full original cave), else the
                -- game's tiles. clientMap: the room data and FDJ's bosses
                -- know the level by this id.
                local data, level, fdjName = self:GetFDJForClientMap(id)
                local f = data and data.floors[level]
                local spec
                if f and type(f.texture) == "string" then
                    spec = fdjSpec(fdjName, level, f)
                else
                    local tiles = legacyTiles(id)
                    spec = tiles and { tiles = tiles, fdjName = fdjName, fdjFloor = level }
                end
                if spec then
                    spec.clientMap = id
                    local wing = fdjName and fdjName:match(": (.+)$")
                    floors[#floors + 1] = { mapId = CUSTOM_FLOOR_BASE + instanceID * 10 + i,
                        name = wing or (f and f.label) or name, spec = spec }
                end
            end
        end
        if floors[1] then return floors end
        floors = nil
    end
    local fdjData, fdjName = self:GetFDJDungeon(instanceID)
    if fdjData then
        local custom = {}
        for i, f in ipairs(fdjData.floors) do
            custom[i] = {
                mapId = CUSTOM_FLOOR_BASE + instanceID * 10 + i,
                name = f.label or (#fdjData.floors > 1 and ("Level " .. i)) or fdjName,
                spec = fdjSpec(fdjName, i, f),
                posMap = (#fdjData.floors == 1) and dungeonMap or nil,
            }
        end
        return custom
    end
    local spec = instanceID and CUSTOM_ART[instanceID]
    if spec and leatrixInstalled() then
        local custom = {}
        for i, s in ipairs(spec) do
            custom[i] = {
                mapId = CUSTOM_FLOOR_BASE + instanceID * 10 + i, name = s.name, spec = leatrixSpec(s),
                posMap = (#spec == 1) and dungeonMap or nil,
            }
        end
        return custom
    end
    if not floors and instanceID and (spec or (AzerothAtlas.QuestData and AzerothAtlas.QuestData.Instances
            and AzerothAtlas.QuestData.Instances[instanceID])) then
        floors = { { mapId = CUSTOM_FLOOR_BASE + instanceID * 10 + 1, blank = true,
            name = select(1, GetInstanceInfo()), posMap = dungeonMap } }
    end
    return floors
end

-- Called from RefreshCurrentZone every tick. Inside a dungeon: the map
-- id of the floor to treat as the player's zone. Otherwise nil.
function MinimapEngine:ResolveDungeonMap(rawMap)
    local inInstance, instType = IsInInstance()
    local instanceID = tonumber((select(8, GetInstanceInfo())))
    -- 2026-11-17: a dungeon picked from the big map's menu, from outside.
    local browsing = self.BrowseInstance
    if browsing then inInstance, instType, instanceID = true, "party", browsing end
    local known = instanceID and (CUSTOM_ART[instanceID]
        or (AzerothAtlas.QuestData and AzerothAtlas.QuestData.Instances
            and AzerothAtlas.QuestData.Instances[instanceID]))
    if not known and (not inInstance or (instType ~= "party" and instType ~= "raid")) then
        if self.DungeonFloors or self.DungeonKey then
            self.DungeonFloors, self.DungeonKey, self.DungeonInstance = nil, nil, nil
            self.ViewFloor, self.PlayerFloor, self.RoomFloorKnown = nil, nil, nil
            self.MapFloorKnown = nil
        end
        return nil
    end
    local best = not browsing and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    if not readable(best) then best = nil end
    local playerMap = (best and isDungeonMapType(best)) and best or nil
    local key = tostring(instanceID) .. ":" .. tostring(playerMap)
        .. ((_G.FDJ or _G.ForeverDungeonJournal_NS) and ":fdj" or "")
    if key ~= self.DungeonKey then
        local oldFloor, oldInstance = self.PlayerFloor, self.DungeonInstance
        self.DungeonKey, self.DungeonInstance = key, instanceID
        local floors = self:BuildDungeonFloors(instanceID, playerMap)
        -- 2026-11-16: levels the game has no map for, drawn from its old
        -- map tiles (Upper Blackrock Spire - DungeonRooms.lua).
        local tiles = self.GetInstanceTileFloors and self:GetInstanceTileFloors(instanceID)
        if tiles then
            if not floors or (#floors == 1 and floors[1].blank) then floors = {} end
            local n = #floors
            for k, t in ipairs(tiles) do
                floors[n + k] = { mapId = CUSTOM_FLOOR_BASE + instanceID * 10 + math.min(9, n + k), name = t.name,
                    spec = { tiles = t.tiles, fdrFloor = t.id } }
            end
        end
        self.DungeonFloors = floors
        self.PlayerFloor = nil
        for i, f in ipairs(floors or NO_FLOORS) do
            registerFloor(self, f.mapId, f.name, f.spec, f.posMap, f.blank)
            if f.mapId == playerMap or (f.posMap and f.posMap == playerMap) then
                self.PlayerFloor = i
            end
        end
        -- 2026-11-19: whether the game's map told us the level. A Forever
        -- dungeon drawn from FDJ's pictures (The Drowned City: the city
        -- and Atal'Byzal) can have a game map that matches none of its
        -- levels; the room then has to say (user: "auto detect when we
        -- enter and exit ... the boss room for Primeval Elemental").
        self.MapFloorKnown = self.PlayerFloor ~= nil
        -- A new dungeon, or the player changed floor: show where they are.
        if oldInstance ~= instanceID or oldFloor ~= self.PlayerFloor then
            self.ViewFloor = nil
        end
    end
    -- No map from the game, or one that isn't any of the levels: the
    -- room it names tells the level (DungeonRooms.lua). Kept while
    -- between named rooms.
    local useRoom = not browsing and not (playerMap and self.MapFloorKnown)
    local roomLevel = useRoom and self.GetRoomLevel and self:GetRoomLevel(self.DungeonFloors)
    if roomLevel then
        self.RoomFloorKnown = true
        if roomLevel ~= self.PlayerFloor then
            self.PlayerFloor, self.ViewFloor = roomLevel, nil
        end
    elseif playerMap and self.MapFloorKnown then
        self.RoomFloorKnown = nil
    end
    local floors = self.DungeonFloors
    if not floors or not floors[1] then return nil end
    return floors[self.PlayerFloor or 1].mapId
end

-- Index of the floor being looked at, or nil outside a dungeon.
function MinimapEngine:GetViewFloorIndex()
    local floors = self.DungeonFloors
    if not floors or not floors[1] or self.Cont ~= DUNGEON_CONT then return nil end
    local i = self.ViewFloor or self.PlayerFloor or 1
    if i > #floors then i = #floors end
    return i
end

-- Map id of the floor being looked at (the player's zone outside a dungeon).
function MinimapEngine:GetViewMapId()
    local i = self:GetViewFloorIndex()
    return i and self.DungeonFloors[i].mapId or self.MapId
end

function MinimapEngine:IsViewingPlayerFloor()
    return self.ViewFloor == nil or not self:GetViewFloorIndex()
end

-- Shows floor i (nil: back to the player's own floor), fitted to the window.
function MinimapEngine:SetViewFloor(i)
    local floors = self.DungeonFloors
    if not floors or not floors[1] then return end
    if i then i = max(1, min(#floors, i)) end
    if i and i == (self.PlayerFloor or 1) then i = nil end
    if i == self.ViewFloor then return end
    self.ViewFloor = i
    local mapId = self:GetViewMapId()
    local _, x, y, zw, zh = self:GetWorldZoneInfo(DUNGEON_CONT, mapId)
    local ZoomController = AzerothAtlas.Modules.Map.ZoomController
    if ZoomController and x and zw > 0 and self.MapW and self.MapH then
        if i or self.PlyrPosUnknown then
            ZoomController:Move(x + zw / 2, y + zh / 2, min(self.MapW / zw, self.MapH / zh) * .9, 10)
        elseif self.PlyrX then
            ZoomController:Move(self.PlyrX, self.PlyrY, nil, 10)
        end
    end
end

function MinimapEngine:StepViewFloor(delta)
    local i = self:GetViewFloorIndex()
    if i then self:SetViewFloor(i + delta) end
end

-- The map id to ask C_Map for the player's position on a floor: the
-- floor itself, or for a Forever dungeon's art floor the client map it
-- matches (nil when there is none).
function MinimapEngine:GetPositionMap(mapId)
    local winfo = mapId and self.MapWorldInfo[mapId]
    if winfo and (winfo.CustomArt or winfo.Blank) then return winfo.PosMap end
    return mapId
end

-- A unit's own map id -> the floor it is on, or nil.
function MinimapEngine:FloorForMap(map)
    for _, f in ipairs(self.DungeonFloors or NO_FLOORS) do
        if f.mapId == map or (f.posMap and f.posMap == map) then return f.mapId end
    end
    return nil
end

-- One Forever-dungeon floor: a single frame showing its part of
-- Leatrix's art sheet, clipped to the map window like a terrain tile.
-- A level drawn from the game's world map tiles: 12 tiles of 256 px,
-- 4 across 3 down, the map being their top-left 1002x668 (the layout
-- Forever Dungeon Routes' MapView.lua uses for the same files).
local TILE_PX, TILE_MAP_W, TILE_MAP_H = 256, 1002, 668
function MinimapEngine:DrawTileFloor(mapId, s)
    local frms = self.CustomTileFrms or {}
    self.CustomTileFrms = frms
    local _, zx, zy, zw, zh = self:GetWorldZoneInfo(DUNGEON_CONT, mapId)
    if not zx then return end
    local lvl = (self.Frm:GetFrameLevel() or 1) + CITY_LEVEL_OFFSET
    for i = 1, 12 do
        local frm = frms[i]
        if not frm then
            frm = self:CreateMiniFrame()
            frms[i] = frm
        end
        local id = s.tiles[i]
        if id then
            local row, col = math.floor((i - 1) / 4), (i - 1) % 4
            local w = math.min(TILE_PX, TILE_MAP_W - col * TILE_PX)
            local h = math.min(TILE_PX, TILE_MAP_H - row * TILE_PX)
            if frm.tileId ~= id then
                frm.texture:SetTexture(id)
                frm.tileId = id
            end
            frm:SetFrameLevel(lvl)
            local db = self.DungeonBrightness or 1
            frm.texture:SetVertexColor(db, db, db, 1)
            if self:ClipFrameTL(frm, zx + col * TILE_PX / TILE_MAP_W * zw, zy + row * TILE_PX / TILE_MAP_H * zh,
                    w / TILE_MAP_W * zw, h / TILE_MAP_H * zh) then
                -- 0-1 over the visible part of the used w x h corner.
                local ulx, uly, _, lly, urx = frm.texture:GetTexCoord()
                local su, sv = w / TILE_PX, h / TILE_PX
                frm.texture:SetTexCoord(ulx * su, urx * su, uly * sv, lly * sv)
            end
        else
            frm:Hide()
        end
    end
end

local function hideTileFloor(self)
    for _, f in ipairs(self.CustomTileFrms or {}) do f:Hide() end
end

function MinimapEngine:DrawCustomFloor(mapId, winfo)
    if winfo.CustomArt and winfo.CustomArt.tiles then
        if self.CustomArtFrm then self.CustomArtFrm:Hide() end
        return self:DrawTileFloor(mapId, winfo.CustomArt)
    end
    hideTileFloor(self)
    local frm = self.CustomArtFrm
    if not frm then
        frm = self:CreateMiniFrame()
        self.CustomArtFrm = frm
    end
    local s = winfo.CustomArt
    local path = s.path
    if frm.path ~= path then
        frm.texture:SetTexture(path)
        frm.path = path
    end
    frm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + CITY_LEVEL_OFFSET)
    local db = self.DungeonBrightness or 1
    frm.texture:SetVertexColor(db, db, db, 1)
    local _, zx, zy, zw, zh = self:GetWorldZoneInfo(DUNGEON_CONT, mapId)
    if not zx or not self:ClipFrameTL(frm, zx, zy, zw, zh) then return end
    -- ClipFrameTL left 0-1 coords for the visible part of the floor;
    -- map them into the floor's rectangle on the art sheet.
    local ulx, uly, _, lly, urx = frm.texture:GetTexCoord()
    local u1, u2, v1, v2 = s.u1, s.u2, s.v1, s.v2
    frm.texture:SetTexCoord(u1 + ulx * (u2 - u1), u1 + urx * (u2 - u1),
        v1 + uly * (v2 - v1), v1 + lly * (v2 - v1))
end

function MinimapEngine:HideCustomFloor()
    if self.CustomArtFrm then self.CustomArtFrm:Hide() end
    hideTileFloor(self)
end

---------------------------------------------------------------------------------------
-- 2026-11-16: City / Dungeon map layer (user request). Inside one of
-- the main cities (MapWorldInfo rows flagged City - Stormwind,
-- Orgrimmar, Ironforge, Thunder Bluff, Darnassus, Undercity) or a
-- dungeon, that place's own art map is drawn over the Terrain layer
-- and under the Service layer, so it's the dominant map; each can be
-- switched off in Settings > Map to fall back to Terrain alone.
--
-- This is real Carbonite's city handling: its UpdateWorld fills the
-- TileFrms pool from GetArtLayerTextures(mapId, 1) and MoveCurZoneTiles
-- places it with MoveZoneTiles whenever the zone is flagged City
-- (MapEngine.lua:6083-6118 / 9419). TileFrms had been sitting unused
-- in this port since the Art Map layer was redefined (build-order step
-- 21), so it becomes this layer's pool.
---------------------------------------------------------------------------------------

function MinimapEngine:GetAreaMapKind(mapId)
    local winfo = mapId and self.MapWorldInfo and self.MapWorldInfo[mapId]
    if not winfo then return nil end
    if winfo.City then return "City" end
    if winfo.Dungeon then return "Dungeon" end
    return nil
end

function MinimapEngine:UpdateAreaMap()
    local mapId = self:GetViewMapId()
    local kind = self.Cont and self:GetAreaMapKind(mapId)
    if not kind or (kind == "City" and self.HideCityArt)
        or (kind == "Dungeon" and self.HideDungeonArt) then
        self:HideZoneTileFrames(self.TileFrms)
        self:HideCustomFloor()
        return
    end

    local winfo = self.MapWorldInfo[mapId]
    if winfo and winfo.Blank then
        self:HideZoneTileFrames(self.TileFrms)
        self:HideCustomFloor()
        return
    end
    if winfo and winfo.CustomArt then
        self:HideZoneTileFrames(self.TileFrms)
        self:DrawCustomFloor(mapId, winfo)
        return
    end
    self:HideCustomFloor()

    if self.AreaArtMapId ~= mapId then
        local now = GetTime()
        if self.AreaArtRetryMapId == mapId and now < (self.AreaArtRetryAt or 0) then
            self:HideZoneTileFrames(self.TileFrms)
            return
        end
        local textures = self:GetArtLayerTextures(self:GetArtSourceMapID(mapId), 1)
        if not textures or not textures[1] then
            -- Map art can arrive a moment after a loading screen - try
            -- again in a second rather than giving up on this map.
            self.AreaArtRetryMapId, self.AreaArtRetryAt = mapId, now + 1
            self:HideZoneTileFrames(self.TileFrms, true)
            return
        end
        local n = min(#textures, 150)
        for i = 1, 150 do
            local frm = self.TileFrms[i]
            if frm then
                frm.texture:SetTexture(i <= n and textures[i] or nil)
            end
        end
        self.CurWorldTileCount = n
        self.AreaArtMapId = mapId
        self.AreaArtRetryMapId = nil
    end

    -- 2026-11-18: city and dungeon maps' own brightness sliders.
    local bright = (kind == "City" and self.CityBrightness) or (kind == "Dungeon" and self.DungeonBrightness) or 1
    self:MoveZoneTiles(self.Cont, mapId, self.TileFrms, bright,
        (self.Frm:GetFrameLevel() or 1) + CITY_LEVEL_OFFSET)
end

---------------------------------------------------------------------------------------
-- 2026-11-16: window title = location, written like Titan Panel's
-- Location button ("Zone - Subzone"), then the player's coordinates.
-- Movement speed moved out of the title to the bottom-left corner of
-- the map (MinimapWindow.SpeedText).
---------------------------------------------------------------------------------------

function MinimapEngine:UpdateTitle()
    local win = self.Win
    if not win then return end

    local zone = GetRealZoneText and GetRealZoneText() or ""
    if zone == "" then zone = GetZoneText and GetZoneText() or "" end
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local title = zone
    if sub ~= "" and sub ~= zone then
        title = (zone ~= "" and (zone .. " - ") or "") .. sub
    end
    if not self.PlyrPosUnknown and self.PlyrRZX and self.PlyrRZY then
        title = ("%s  |cffa0a0a0%.1f, %.1f|r"):format(title, self.PlyrRZX, self.PlyrRZY)
    end
    if self:IsBrowsing() then
        title = ("|cffffd100%s|r  |cffa0a0a0(you: %s)|r"):format(self.BrowseName or "?", title)
    end
    if title ~= self._LastTitle then
        self._LastTitle = title
        win:SetTitle(title)
    end

    local MinimapWindow = AzerothAtlas.Modules.Map.MinimapWindow
    local speedText = MinimapWindow and MinimapWindow.SpeedText
    if speedText then
        local text = "Speed: stopped"
        if self.PlyrSpeed and self.PlyrSpeed > 0 then
            local pct = self.PlyrSpeed / 6.4 * 100 - 100
            if math.abs(pct) < .5 then pct = 0 end
            text = ("Speed %+.0f%%"):format(pct)
        end
        if text ~= self._LastSpeed then
            self._LastSpeed = text
            speedText:SetText(text)
        end
    end
end

---------------------------------------------------------------------------------------
-- 2026-11-16: auto-scale, ported from Nx.Map:Update's NXAutoScaleOn
-- block (Carbonite MapEngine.lua:6631-6720). While there is somewhere
-- to go, the view centers between the player and that place and zooms
-- so both stay on screen, re-fitting as the player closes in; once the
-- destination is gone the zoom from before goes back (ClearTargets,
-- :15281-15287). Carbonite tracks one destination at a time; here all
-- three trails can run together, so the one it fits is picked by the
-- user's priority: goto, then corpse, then quest.
--
-- Same math as the real source: the player-to-target distance spans
-- half the window on its tighter axis, each step is limited to
-- halving/doubling the current zoom (smooths big jumps), and the result
-- is clamped to the Auto Scale Min/Max settings.
---------------------------------------------------------------------------------------

function MinimapEngine:GetAutoScaleTarget()
    if self.GotoWX and self.GotoCont == self.Cont then
        return self.GotoWX, self.GotoWY
    end
    if self.CorpseWX and self.CorpseCont == self.Cont then
        return self.CorpseWX, self.CorpseWY
    end
    local Quest = AzerothAtlas.Modules.Quest
    local t = Quest and Quest.Routing and Quest.Routing.Target
    if t and t.x and t.cont == self.Cont and not t.inside
        and not (Quest.Core and Quest.Core:Opt("RouteTrail") == false) then
        return t.x, t.y
    end
    return nil
end

local AUTOSCALE_MIN_DISTANCE = .1

function MinimapEngine:AutoScaleTarget()
    local ZoomController = AzerothAtlas.Modules.Map.ZoomController
    local MinimapWindow = AzerothAtlas.Modules.Map.MinimapWindow
    if not ZoomController or not MinimapWindow then return false end
    local opts = MinimapWindow:DB().profile

    local tx, ty
    if opts.AutoScale ~= false then
        tx, ty = self:GetAutoScaleTarget()
    end

    if not tx then
        if self.ScaleBeforeTarget then
            ZoomController:Move(self.PlyrX, self.PlyrY, self.ScaleBeforeTarget, 30)
            self.ScaleBeforeTarget = nil
            return true
        end
        return false
    end

    if not self.ScaleBeforeTarget then
        self.ScaleBeforeTarget = self.Scale
    end

    local mX = (tx + self.PlyrX) * .5
    local mY = (ty + self.PlyrY) * .5
    local dx = max(math.abs(tx - self.PlyrX), AUTOSCALE_MIN_DISTANCE)
    local dy = max(math.abs(ty - self.PlyrY), AUTOSCALE_MIN_DISTANCE)
    local scale = min(self.MapW / dx, self.MapH / dy) * .5

    local cur = self.Scale or 1
    scale = max(min(scale, cur * 2), cur / 2)
    scale = max(min(scale, opts.AutoScaleMax or 4), opts.AutoScaleMin or .05)

    ZoomController:Move(mX, mY, scale, 30)
    return true
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
-- drawn (zoomed out) or cleared (zoomed in); this engine's Update()
-- mirrors exactly that, not an either/or swap between the two layers
-- (an earlier version of this code wrongly treated it as one, gating
-- UpdateMiniFrames itself behind the same threshold - confirmed wrong
-- live, 2026-11-10: it meant detail tiles only ever turned on once
-- already zoomed in far enough that a single ~107-world-unit tile
-- exceeded the whole window, i.e. "stuck showing one square, no update
-- on pan").
--
-- CORRECTED 2026-11-11 (map-layering fix): this comment used to say
-- the zone-overview layer draws "on top of" this one. That was never
-- actually checked against real Carbonite's own per-tick call order,
-- and both layers used to share one literal frame level with no
-- relative offset anyway (the real root cause of a separately-reported
-- "inconsistent at different zooms/pans" bug - see
-- ART_MAP_LEVEL_OFFSET/TERRAIN_TILE_LEVEL_OFFSET above MoveZoneTiles).
-- Checking the real source (MapEngine.lua:9886-9894) shows the
-- opposite for an ordinary zone (the only kind this port implements):
-- UpdateMiniFrames (this layer) is called AFTER MoveCurZoneTiles and
-- both draw through a shared incrementing level counter, so TERRAIN
-- ends up the TOP layer where both show, not Art - now implemented
-- that way below via TERRAIN_TILE_LEVEL_OFFSET > ART_MAP_LEVEL_OFFSET,
-- confirmed with the user as the intended look.
--
-- View3D (Carbonite's tilted 3D relief mode) is an explicit non-goal
-- throughout this addon (ZoomController.lua's own header) - both
-- functions below drop that entire branch, keeping only the flat 2D
-- tiling math (same shape as MoveZoneTiles' own per-tile clip code
-- above).
---------------------------------------------------------------------------------------

-- Maximum tile-grid side length (in scale-sized world tiles) the
-- Terrain layer will ever build in one direction, no matter how
-- large the window or how far zoomed out - caps worst-case tile
-- count at MAX_DETAIL_RADIUS^2. Reuses real Carbonite's own shipped
-- Nx.db.profile.Map.DetailSize slider's real MAX (OptionsEngine.lua:
-- 925-964) - an already-battle-tested ceiling, not a guess - and its
-- MIN as a floor so a very-zoomed-in tick never collapses to an
-- unusably small grid.
--
-- UNLIKE the old fixed DETAIL_RADIUS this replaces (and unlike real
-- Carbonite's own self.MiniBlks, which is also fixed, read once from
-- that same slider - see UpdateMiniFrames' own header for why that
-- never mattered for Carbonite's fixed-size window but does here),
-- the actual grid side length used each tick is computed dynamically
-- in UpdateMiniFrames from the window's current size and zoom - this
-- is only the ceiling on that computation.
local MAX_DETAIL_RADIUS = 40
local MIN_DETAIL_RADIUS = 2

-- Extra tiles added on each axis beyond the exact math, to absorb
-- UpdateMiniFrames' own miniX/miniY floor(...+.5) centering rounding -
-- without this, a hairline gap could appear at the window's edge on
-- whichever side that rounding happened to shrink.
local DETAIL_SAFETY_MARGIN = 2

-- Zoom-scale threshold controlling ONLY the zone-overview layer above
-- (MoveCurZoneTiles vs. HideZoneTileFrames in Update(), below) - real
-- Carbonite's NXDetailScale, hardcoded here at its real default 4,
-- same reasoning as MAX_DETAIL_RADIUS above. Unrelated to
-- UpdateMiniFrames below - that one no longer fades on this or any
-- other zoom value (see that function's header).
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
--
-- Build-order step 21: added the real source's two optional trailing
-- params (texMaxX, texMaxY, MapEngine.lua:11655-11662) - scales the
-- computed texcoords for overlay art files that aren't clean powers-
-- of-two (UpdateOverlay, below). Existing callers (Terrain tiles, Art
-- Map backdrop) never pass these, so they're unaffected.
function MinimapEngine:ClipFrameTL(frm, bx, by, w, h, texMaxX, texMaxY)
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
    if texMaxX and texMaxY then
        texX1 = texX1 * texMaxX
        texX2 = texX2 * texMaxX
        texY1 = texY1 * texMaxY
        texY2 = texY2 * texMaxY
    end
    frm.texture:SetTexCoord(texX1, texX2, texY1, texY2)
    frm:Show()
    return true
end

-- Build-order step 21: generic, auto-growing, reset-every-tick frame
-- pool for zone "revealed" overlay art (UpdateOverlay, below) - ported
-- from real Carbonite's GetIconNI/HideExtraIcons (MapEngine.lua:12327/
-- :12047), this port's own slice of it (that function serves five
-- different icon pools there; this port only needs the one). Unlike
-- this file's other icon pools (QuestFrms/GatherFrms/etc, zone-scoped,
-- rebuilt on zone change) this one is reset every tick because the
-- number of overlay regions drawn varies by zone and by how many
-- recently-visited zones are currently being drawn at once.
local MAX_OVERLAY_FRAMES = 1500 -- real Carbonite's own tested ceiling

function MinimapEngine:GetOverlayFrame(levelAdd)
    self.OverlayFrms = self.OverlayFrms or {}
    local frms = self.OverlayFrms
    local pos = frms.Next or 1
    if pos > MAX_OVERLAY_FRAMES then pos = MAX_OVERLAY_FRAMES end
    local f = frms[pos]
    if not f then
        f = self:CreateMiniFrame()
        frms[pos] = f
    end
    f:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + ART_MAP_LEVEL_OFFSET + (levelAdd or 0))
    f.texture:SetVertexColor(1, 1, 1, 1)
    f.texture:SetTexCoord(0, 1, 0, 1)
    frms.Next = pos + 1
    return f
end

function MinimapEngine:HideExtraOverlayFrames()
    local frms = self.OverlayFrms
    if not frms then return end
    for n = (frms.Next or 1), (frms.Used or 0) do
        if frms[n] then frms[n]:Hide() end
    end
end

-- Build-order step 21 same-day eighth follow-up (2026-11-11): live-
-- tested broken - toggling the Art Map checkbox off neither hid the
-- stitched Overlay art nor let it keep panning ("does not turn on and
-- off with the art map toggle box... when i do turn it off i can no
-- longer pan the zone stiched map"). Root cause: both gate branches in
-- Update() below that need to hide Overlay ENTIRELY (DebugHideArt, and
-- zoomed in past DETAIL_SCALE) were calling HideExtraOverlayFrames
-- instead - that function only trims the TRAILING EXCESS left over
-- from UpdateZoneOverlays' own last real draw (frames from its fresh
-- `Next` up to the PREVIOUS tick's stale `Used` count), not the
-- currently-drawn set itself. Skipping UpdateZoneOverlays entirely (as
-- both branches correctly do, to stop redrawing/repositioning) left
-- `Next` frozen at "last real draw count + 1" and `Used` frozen at an
-- even older, usually smaller count - so the trim loop's own range
-- (Next..Used) was empty or near-empty every single tick, hiding
-- nothing, while the frames themselves never got repositioned again
-- either (that only happens inside UpdateOverlay, called from
-- UpdateZoneOverlays) - exactly "stuck visible, stuck in place."
function MinimapEngine:HideAllOverlayFrames()
    local frms = self.OverlayFrms
    if not frms then return end
    local count = (frms.Next or 1) - 1
    for n = 1, count do
        if frms[n] then frms[n]:Hide() end
    end
    frms.Used = 0
    frms.Next = 1
end

-- Kept verbatim from Nx.Map:GetWorldZoneScale (MapEngine.lua:15035-
--15045) - the BaseMap redirect is dead for this port's own data (no
-- entry currently sets MapWorldInfo[x].BaseMap) but harmless to keep,
-- matching GetWorldPos' own already-ported handling of the same field.
function MinimapEngine:GetWorldZoneScale(mapId)
    local winfo = self.MapWorldInfo[mapId]
    if winfo and winfo.BaseMap then
        winfo = self.MapWorldInfo[winfo.BaseMap]
    end
    if winfo and winfo.Scale then
        return winfo.Scale
    end
    return 10.02
end

-- Build-order step 21: zone "revealed" overlay art (UpdateOverlay,
-- below) - caches ported verbatim from the real source
-- (MapEngine.lua:9740-9826). Genuine perf optimizations (avoid
-- Nx.Split/API calls every frame for a loop that can run for up to
-- ZONE_DRAW_CNT+1 zones' worth of regions every tick), not incidental
-- complexity - kept rather than dropped, unlike the dead branches
-- UpdateOverlay itself drops below.
local OverlayCache = {
    layerInfo = {},
    exploredTextures = {},
    parsedOverlays = {},
    lastExploredCheck = {},
}

local function GetParsedOverlay(txFolder, txName, whxyStr)
    local cacheKey = txFolder .. txName
    local cached = OverlayCache.parsedOverlays[cacheKey]
    if cached then
        return cached
    end

    local oX, oY, txW, txH = Nx.Split(",", whxyStr)
    local arTx
    if string.find(txName, ",") then
        arTx = { Nx.Split(",", txName) }
    elseif tonumber(txName) then
        arTx = { txName }
    end

    cached = {
        oX = tonumber(oX),
        oY = tonumber(oY),
        txW = tonumber(txW),
        txH = tonumber(txH),
        arTx = arTx,
        whxyKey = oX .. "," .. oY .. "," .. txW .. "," .. txH,
    }
    OverlayCache.parsedOverlays[cacheKey] = cached
    return cached
end

function MinimapEngine:GetCachedLayerInfo(mapId)
    local artMapID = self:GetArtSourceMapID(mapId)
    local artID = C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(artMapID) or artMapID
    local cached = OverlayCache.layerInfo[mapId]
    if cached and cached.artID == artID then
        return cached.info
    end

    local layers = self:GetArtLayers(artMapID)
    if not layers or not layers[1] then
        return nil
    end

    local layerInfo = layers[1]
    OverlayCache.layerInfo[mapId] = { artID = artID, info = layerInfo }
    return layerInfo
end

function MinimapEngine:GetCachedExploredTextures(mapId, forceRefresh)
    local now = GetTime()
    local lastCheck = OverlayCache.lastExploredCheck[mapId] or 0

    if not forceRefresh and (now - lastCheck) < 2 and OverlayCache.exploredTextures[mapId] then
        return OverlayCache.exploredTextures[mapId]
    end

    local exploredWHXY = {}
    local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
        and C_MapExplorationInfo.GetExploredMapTextures(mapId)
    if explored then
        for i, ex in ipairs(explored) do
            local key = ex.offsetX .. "," .. ex.offsetY .. "," .. ex.textureWidth .. "," .. ex.textureHeight
            exploredWHXY[key] = true
        end
    end

    OverlayCache.exploredTextures[mapId] = exploredWHXY
    OverlayCache.lastExploredCheck[mapId] = now
    return exploredWHXY
end

-- Build-order step 21 follow-up (live-tested same day): real
-- Carbonite's own default here is NXShowUnexplored = false (per-region
-- dimming against real C_MapExplorationInfo.GetExploredMapTextures
-- data, matching Classic exploration state). Live-tested on this
-- server with that default and every region rendered permanently
-- dimmed/"undiscovered," even for zones long since fully explored -
-- most likely this Forever-flavor server's own exploration tracking
-- doesn't line up with Carbonite's hand-authored Classic-client
-- overlay catalog closely enough for GetCachedExploredTextures' key
-- match to ever succeed. Flipped to true: this short-circuits `unex`
-- to always stay nil (see UpdateOverlay below), so every region always
-- renders at its full requested brightness - no exploration lookup,
-- no oX-shift, no per-region dimming at all. Matches the user's own
-- stated goal ("all revealed") better than a dimming pass that was
-- never actually discriminating explored from unexplored, only
-- failing to find anything explored.
local SHOW_UNEXPLORED = true
local UNEXPLORED_ALPHA = .35

-- Trimmed port of Nx.Map:UpdateOverlay (MapEngine.lua:10045-10236) -
-- the zone "revealed" overlay art, now THE Art Map layer itself (see
-- ART_MAP_LEVEL_OFFSET's own header), drawn on top of Base's continent
-- backdrop for the current zone (bright=1) and every other zone on the
-- same continent (bright=.8, via UpdateZoneOverlays below). Dropped
-- (confirmed dead/inapplicable for this single-flavor, no-instance/no-battleground
-- port, same convention as this file's other "explicit non-goal"
-- branches): the modern-instance-canvas early return,
-- ShouldHideQuelThalasZone, IsBattleGroundMap/IsMicroDungeon/
-- IsInstanceMap guards, wzone.Phase (MoP-phasing, not reachable on
-- this server), and the underscore-combined-region branch +
-- GetCompressedTexturePath (confirmed zero occurrences in
-- ExplorationOverlays.lua). KEPT, unlike an earlier pass through this
-- plan assumed: the arTx/multi-texture-ID branch - confirmed NOT dead,
-- Eastern Plaguelands' 21 regions are keyed by plain numeric or
-- comma-separated Blizzard fileIDs instead of named file paths (e.g.
-- ["271518,271527,2212703,2212704"]), and that branch is what renders
-- them.
function MinimapEngine:UpdateOverlay(mapId, bright, noUnexplored)
    if mapId == nil or mapId == 0 or mapId == -1 then
        return
    end

    local wzone = self.MapWorldInfo[mapId]
    if wzone and wzone.City then
        DebugOverlayLog(mapId, "wzone.City set, skipping")
        return
    end
    local txFolder = (wzone and wzone.Overlay) or ""
    local overlays = self.ZoneOverlays and self.ZoneOverlays[txFolder]
    if not overlays then
        DebugOverlayLog(mapId, "no overlays (wzone=%s txFolder=%q ZoneOverlays=%s)",
            tostring(wzone ~= nil), txFolder, tostring(self.ZoneOverlays ~= nil))
        return
    end

    local unex
    if not noUnexplored and (not overlays or not SHOW_UNEXPLORED) then
        if not (wzone and wzone.Explored) then
            unex = true
        end
    end

    local path = "Interface\\Worldmap\\" .. txFolder .. "\\"
    local alpha = self.BackgndAlpha or 1
    local unExAl = self.UnexploredBrightness or UNEXPLORED_ALPHA     -- 2026-11-18: a slider
    local exploredWHXY = unex and self:GetCachedExploredTextures(mapId) or {}

    local layerInfo = self:GetCachedLayerInfo(mapId)
    if not layerInfo then
        local artMapID = self:GetArtSourceMapID(mapId)
        DebugOverlayLog(mapId, "no layerInfo (overlays found, txFolder=%q, artMapID=%s, C_Map.GetMapArtLayers=%s)",
            txFolder, tostring(artMapID),
            tostring(C_Map and C_Map.GetMapArtLayers ~= nil))
        return
    end
    DebugOverlayLog(mapId, "OK txFolder=%q regions=%d tileW=%s tileH=%s layerW=%s layerH=%s",
        txFolder, (function() local n=0 for _ in pairs(overlays) do n=n+1 end return n end)(),
        tostring(layerInfo.tileWidth), tostring(layerInfo.tileHeight),
        tostring(layerInfo.layerWidth), tostring(layerInfo.layerHeight))
    local TILE_SIZE_WIDTH = layerInfo.tileWidth
    local TILE_SIZE_HEIGHT = layerInfo.tileHeight
    local layerWidth = layerInfo.layerWidth
    local layerHeight = layerInfo.layerHeight
    local zoneScale = self:GetWorldZoneScale(mapId)
    local worldPerPixelX = zoneScale * 100 / layerWidth
    local worldPerPixelY = zoneScale * 100 / (1.5 * layerHeight)

    local scale = self.ScaleDraw or 1
    local minVisibleSize = scale < 0.15 and 128 or (scale < 0.3 and 64 or 0)

    local dbgDrawn, dbgClipped, dbgDimmed, dbgBright = 0, 0, 0, 0

    for oName, whxyStr in pairs(overlays) do
        if oName ~= "dynamic" then
            local parsed = GetParsedOverlay(txFolder, oName, whxyStr)
            local oX, oY = parsed.oX, parsed.oY
            local txW, txH = parsed.txW, parsed.txH
            local arTx = parsed.arTx
            local whxyKey = parsed.whxyKey

            if not (txW < minVisibleSize and txH < minVisibleSize) then
                local lev = 0
                local brt = bright
                local txName = path .. oName

                if exploredWHXY[whxyKey] then
                    oX = oX - 10000
                end

                if unex then
                    if oX < 0 then
                        oX = oX + 10000
                    else
                        brt = unExAl
                        lev = 1
                    end
                end

                if brt == unExAl then dbgDimmed = dbgDimmed + 1 else dbgBright = dbgBright + 1 end

                local bW = ceil(txW / TILE_SIZE_WIDTH)
                local bH = ceil(txH / TILE_SIZE_HEIGHT)
                local txIndex = 1

                for bY = 0, bH - 1 do
                    local txPixelH, txFileH
                    if bY < bH - 1 then
                        txPixelH, txFileH = TILE_SIZE_HEIGHT, TILE_SIZE_HEIGHT
                    else
                        txPixelH = txH % TILE_SIZE_HEIGHT
                        if txPixelH == 0 then txPixelH = TILE_SIZE_HEIGHT end
                        txFileH = 16
                        while txFileH < txPixelH do txFileH = txFileH * 2 end
                    end

                    for bX = 0, bW - 1 do
                        local txPixelW, txFileW
                        if bX < bW - 1 then
                            txPixelW, txFileW = TILE_SIZE_WIDTH, TILE_SIZE_WIDTH
                        else
                            txPixelW = txW % TILE_SIZE_WIDTH
                            if txPixelW == 0 then txPixelW = TILE_SIZE_WIDTH end
                            txFileW = 16
                            while txFileW < txPixelW do txFileW = txFileW * 2 end
                        end

                        local f = self:GetOverlayFrame(lev)
                        local wx, wy = self:GetWorldPos(mapId,
                            (oX + bX * TILE_SIZE_WIDTH) / layerWidth * 100,
                            (oY + bY * TILE_SIZE_HEIGHT) / layerHeight * 100)

                        if wx and self:ClipFrameTL(f, wx, wy,
                                txPixelW * worldPerPixelX,
                                txPixelH * worldPerPixelY,
                                txPixelW / txFileW,
                                txPixelH / txFileH) then

                            f.texture:SetColorTexture(1, 0, 0, 0)

                            if arTx then
                                local textureID = arTx[txIndex]
                                f.texture:SetTexture(tonumber(textureID) or textureID)
                            else
                                f.texture:SetTexture(txName .. txIndex)
                            end
                            f.texture:SetVertexColor(brt, brt, brt, alpha)
                            dbgDrawn = dbgDrawn + 1
                        else
                            dbgClipped = dbgClipped + 1
                        end

                        txIndex = txIndex + 1
                    end
                end
            end
        end
    end

    DebugOverlayLog(mapId, "done bright=%s unex=%s dimmedRegions=%d brightRegions=%d drawnTiles=%d clippedTiles=%d",
        tostring(bright), tostring(unex), dbgDimmed, dbgBright, dbgDrawn, dbgClipped)
end

-- Build-order step 21 same-day follow-up: user's actual goal was never
-- real Carbonite's default ("current zone + a FIFO of the last few
-- visited, matching real exploration") - it's "all revealed," same
-- philosophy as SHOW_UNEXPLORED above (no per-region fog of war) but
-- at the zone-stitching level too (no per-zone visit history either).
-- Dropped the self.MapsDrawnOrder/AddOldMap FIFO entirely (confirmed
-- unused anywhere else first) in favor of iterating EVERY zone on the
-- current continent - self.MapZones[self.Cont], the same static
-- continent->zones list FindContinent already walks, and the same one
-- MoveZoneTiles' own tiling relies on existing and being accurate.
-- No real-source equivalent by this name (real Carbonite inlines its
-- own narrower version of this loop directly in UpdateZones,
-- MapEngine.lua:9880-9893).
function MinimapEngine:UpdateZoneOverlays()
    self.OverlayFrms = self.OverlayFrms or {}
    self.OverlayFrms.Used = (self.OverlayFrms.Next or 1) - 1
    self.OverlayFrms.Next = 1

    local zones = self.Cont and self.MapZones and self.MapZones[self.Cont]
    if zones then
        for _, zoneId in ipairs(zones) do
            if zoneId ~= self.MapId then
                self:UpdateOverlay(zoneId, .8, true)
            end
        end
    end
    -- 2026-11-17: and every other continent's zones in the Azeroth view.
    if self.ShowAllConts then
        for cont = 1, self.ContCnt or 0 do
            if cont ~= self.Cont then
                for _, zoneId in ipairs(self.MapZones[cont] or {}) do
                    self:UpdateOverlay(zoneId, .8, true)
                end
            end
        end
    end
    if self.MapId then
        self:UpdateOverlay(self.MapId, 1)
    end

    self:HideExtraOverlayFrames()
end

-- Kept verbatim (flat-view math only) from Nx.Map:UpdateMiniFrames
-- (MapEngine.lua:10296-10535+). miniT/basex/basey come from
-- GetMiniInfo (Map/Data/MinimapRuntime.lua). Called every tick,
-- unconditionally, at every zoom level (see Update()'s call site and
-- the DETAIL_SCALE comment above for why this is NOT zoom-gated).
--
-- Build-order step 19 (2026-11-11, terrain coverage fix): the tile
-- grid's side length (`blks`) is now computed fresh every tick from
-- the window's ACTUAL visible world-space extent (self.MapW/MapH /
-- self.ScaleDraw), not a fixed constant.
--
-- Previously this used a fixed blks (the old DETAIL_RADIUS = 6, real
-- Carbonite's own fixed self.MiniBlks equivalent), giving a FIXED
-- ~640x640-world-unit coverage square regardless of window size or
-- zoom. Confirmed live (user screenshots, zoomed/panned around
-- Thousand Needles at varying window sizes): whenever the window's
-- visible world extent (MapW or MapH / ScaleDraw) exceeded that fixed
-- square - any sufficiently zoomed-out and/or large undocked window,
-- both explicitly supported by this addon (ScrollScale.lua's
-- MIN_SCALE=0.015 floor, live window/map resize) - the fixed square
-- stopped reaching the window's edges, producing a sharp visible gap
-- wherever coverage ran out. Which tiles happened to fall inside vs.
-- outside that fixed square as pan/zoom/window size changed is
-- exactly the "tiles cut in and out" symptom reported.
--
-- Build-order step 19 follow-up, same day: that fix's first version
-- also added an automatic scale-based alpha FADE once the window/zoom
-- combination's needed coverage exceeded MAX_DETAIL_RADIUS (mirroring
-- real Carbonite's own internal NXDetailScale-pivoted fade,
-- MapEngine.lua:10334-10343,10480) - confirmed live (whole-Kalimdor
-- screenshot, then one more zoom-out step) that this auto-fade is NOT
-- wanted here: explicit user instruction, "no fading, always bright
-- by default." Removed entirely - this layer never auto-dims itself
-- for any reason now, matching the pre-fade behavior, just with the
-- window-size-aware `blks` from the fix above kept. Brightness is
-- instead a plain user-controlled value (self.TerrainBrightness,
-- default 1 = fully bright), exposed as its own "Terrain Brightness"
-- slider in MapContextMenu.lua - same persisted-value/live-apply
-- pattern as that file's existing "Tile Map Brightness" row for the
-- Art Map layer (BackgndBrightness/BackgndAlpha), just a separate,
-- independent control rather than sharing that one - the user asked
-- for control over "that variable" specifically "moving forward with
-- future steps," which calls for Terrain's own dial, not reuse of
-- Art's.
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

    local scaleDraw = self.ScaleDraw
    if not scaleDraw or scaleDraw <= 0 then scaleDraw = 1 end
    local mapExtent = max(self.MapW or 0, self.MapH or 0)

    -- Exact tile count (no margin yet) needed to span the window's
    -- LARGER dimension at the current zoom.
    local neededRaw = mapExtent / scaleDraw / scale

    local blks = min(MAX_DETAIL_RADIUS,
        max(MIN_DETAIL_RADIUS, ceil(neededRaw) + DETAIL_SAFETY_MARGIN))

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

    local al = self.TerrainBrightness or 1
    local level = (self.Frm:GetFrameLevel() or 1) + TERRAIN_TILE_LEVEL_OFFSET
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

---------------------------------------------------------------------------------------
-- Subzone names (2026-11-18, user request, from Carbonite: "Draws area
-- names like Goldshire or Stormwind Harbor on the map once you zoom in
-- far enough"). Ported from Nx.Map:UpdateAreaLabels (Carbonite
-- MapEngine.lua:13540-13650), flat view only:
--   * the labels are Carbonite's own list (Map/Data/AreaLabels.lua):
--     {areaID, x%, y%, w%, h%} per map, the names from C_Map.GetAreaInfo
--     so they follow the client's language
--   * a label shows once its area is 70 pixels wide on screen and fades
--     in up to 140 - zoomed out, only the big areas are named
--   * the map you're on plus every zone of the continent on show (all
--     continents in the Azeroth view); none inside a dungeon
-- Not Carbonite's: labels sit one level under the icons (so pins stay on
-- top), a label that would hang over the map's edge is skipped, and the
-- whole pass only runs when the view moved (pan, zoom, resize, new map).
-- On / off: Settings > Map, "Subzone names" (profile.ShowAreaNames).
---------------------------------------------------------------------------------------

local AREA_LABEL_MIN_PX = 70
local areaNameCache = {}

local function AreaName(areaID)
    local name = areaNameCache[areaID]
    if name == nil then
        local ok, n = false, nil
        if C_Map and C_Map.GetAreaInfo then ok, n = pcall(C_Map.GetAreaInfo, areaID) end
        name = (ok and type(n) == "string" and n ~= "") and n or false
        areaNameCache[areaID] = name
    end
    return name or nil
end

function MinimapEngine:HideAreaLabels()
    for _, fs in ipairs(self.AreaLabelFStrs or {}) do fs:Hide() end
    self.AreaLabelKey = nil
end

function MinimapEngine:UpdateAreaLabels()
    local labels = AzerothAtlas.Map.AreaLabels
    local show = AzerothAtlas.db and AzerothAtlas.db.profile.ShowAreaNames ~= false
    if not show or not labels or not self.Frm or not self.Cont or self.Cont == DUNGEON_CONT
            or not self.MapW or not self.ScaleDraw or not self.MapPosXDraw then
        if self.AreaLabelKey ~= false then
            self:HideAreaLabels()
            self.AreaLabelKey = false
        end
        return
    end
    local key = ("%s|%s|%.1f|%.1f|%.5f|%d|%d"):format(tostring(self.MapId), tostring(self.ShowAllConts),
        self.MapPosXDraw, self.MapPosYDraw, self.ScaleDraw, self.MapW, self.MapH)
    if key == self.AreaLabelKey then return end
    self.AreaLabelKey = key

    local host = self.AreaLabelHost
    if not host then
        host = CreateFrame("Frame", nil, self.Frm)
        host:SetAllPoints(self.Frm)
        host:EnableMouse(false)
        self.AreaLabelHost = host
        self.AreaLabelFStrs = {}
    end
    host:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET - 1)
    local pool = self.AreaLabelFStrs

    local scale, cw, ch = self.ScaleDraw, self.MapW, self.MapH
    local used, seen = 0, {}
    local function drawMap(mapId)
        if not mapId or seen[mapId] then return end
        seen[mapId] = true
        local list = labels[mapId]
        local winfo = list and self.MapWorldInfo[mapId]
        if not winfo or not winfo.Scale then return end
        for i = 1, #list do
            local e = list[i]
            local wpx = e[4] * winfo.Scale * scale
            if wpx >= AREA_LABEL_MIN_PX then
                local name = AreaName(e[1])
                -- Not "name and GetWorldPos(...)": "and" keeps only the
                -- first of the two values, leaving my nil.
                local mx, my
                if name then mx, my = self:GetWorldPos(mapId, e[2], e[3]) end
                if mx then
                    local sx = (mx - self.MapPosXDraw) * scale + cw * .5
                    local sy = (my - self.MapPosYDraw) * scale + ch * .5
                    if sx > 0 and sx < cw and sy > 8 and sy < ch - 8 then
                        used = used + 1
                        local fs = pool[used]
                        if not fs then
                            fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            fs:SetJustifyH("CENTER")
                            fs:SetShadowColor(0, 0, 0, .9)
                            fs:SetShadowOffset(1, -1)
                            fs:SetTextColor(1, .95, .8, 1)
                            fs:SetWordWrap(false)
                            pool[used] = fs
                        end
                        fs:SetText(name)
                        local half = (fs:GetStringWidth() or 0) / 2
                        if sx - half < 2 or sx + half > cw - 2 then
                            fs:Hide()
                            used = used - 1
                        else
                            fs:ClearAllPoints()
                            fs:SetPoint("CENTER", host, "TOPLEFT", sx, -sy - (self.TitleH or 0))
                            local a = (wpx - AREA_LABEL_MIN_PX) / AREA_LABEL_MIN_PX
                            fs:SetAlpha(a > 1 and 1 or a)
                            fs:Show()
                        end
                    end
                end
            end
        end
    end

    drawMap(self.MapId)
    local conts = self.ShowAllConts and {} or { self.Cont }
    if self.ShowAllConts then
        for c = 1, self.ContCnt or 0 do conts[#conts + 1] = c end
    end
    for _, c in ipairs(conts) do
        for _, id in ipairs(self.MapZones and self.MapZones[c] or {}) do drawMap(id) end
    end
    for n = used + 1, #pool do pool[n]:Hide() end
end

---------------------------------------------------------------------------------------
-- Movement trail (2026-11-18, user request, from Carbonite: "A
-- breadcrumb trail of dots showing where you've walked. You set the
-- spacing, the number of dots and how long they last" - "be able to
-- turn on and off"). Ported from Nx.Map:UpdatePlyrHistory
-- (MapEngine.lua:8785) and its ring buffer (Map:Init, :273-287): a dot
-- is dropped each time you've moved the spacing from the last one, the
-- oldest is reused once there are as many as allowed, and each fades
-- out over its lifetime. Carbonite's spacing is in map units; here it's
-- yards. Dots remember their continent, so another continent's trail
-- isn't drawn on this one. Recorded while the map window is open (the
-- small map, normally).
-- Settings > Map, "Movement trail": on / off (profile.ShowTrail),
-- spacing (TrailYards, 10), dots (TrailCount, 100), lifetime
-- (TrailSeconds, 90).
---------------------------------------------------------------------------------------

local TRAIL_TEX = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\IconCircleFade"

local TRAIL_YARDS_PER_UNIT = 4.575    -- YARDS_PER_WORLDUNIT, declared further down

local function trailOpt(key, default)
    local db = AzerothAtlas.db
    local v = db and db.profile[key]
    if v == nil then return default end
    return v
end

function MinimapEngine:HideTrail()
    for _, f in ipairs(self.TrailFrms or {}) do f:Hide() end
end

function MinimapEngine:UpdateTrail()
    if not trailOpt("ShowTrail", true) or not self.PlyrX or self.PlyrPosUnknown or not self.Cont then
        self:HideTrail()
        return
    end
    local count = math.max(1, math.floor(trailOpt("TrailCount", 100)))
    local hist = self.TrailHist
    if not hist or hist.cnt ~= count then
        hist = { cnt = count, nextI = 1, lastX = nil, lastY = nil }
        self.TrailHist = hist
    end
    local now = GetTime()

    -- Drop a dot once you've moved the spacing from the last one.
    local spacing = trailOpt("TrailYards", 10) / TRAIL_YARDS_PER_UNIT
    local moved = not hist.lastX or hist.lastCont ~= self.Cont
        or ((self.PlyrX - hist.lastX) ^ 2 + (self.PlyrY - hist.lastY) ^ 2) ^ .5 > spacing
    if moved then
        hist.lastX, hist.lastY, hist.lastCont = self.PlyrX, self.PlyrY, self.Cont
        local i = hist.nextI
        local d = hist[i] or {}
        hist[i] = d
        d.t, d.x, d.y, d.cont = now, self.PlyrX, self.PlyrY, self.Cont
        hist.nextI = i >= count and 1 or i + 1
    end

    local frms = self.TrailFrms
    if not frms then
        frms = {}
        self.TrailFrms = frms
    end
    local life = math.max(1, trailOpt("TrailSeconds", 90))
    local size = math.min(math.max(3 + (self.ScaleDraw or 1) * .8, 4), 12)
    local level = (self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET - 1
    local used = 0
    for i = 1, count do
        local d = hist[i]
        local age = d and now - d.t
        if age and age < life and d.cont == self.Cont then
            used = used + 1
            local f = frms[used]
            if not f then
                f = self:CreateMiniFrame()
                f.texture:SetTexture(TRAIL_TEX)
                frms[used] = f
            end
            if self:ClipFrameW(f, d.x, d.y, size, size, 0) then
                f.texture:SetVertexColor(1, .25, .15, (life - age) / life * .9)
                f:SetFrameLevel(level)
            end
        end
    end
    for n = used + 1, #frms do frms[n]:Hide() end
end

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
    -- 2026-11-17: an icon that is part of a bigger file keeps to its part
    -- (UI/StyleOptions.lua ApplyIconSpec marks it): a sheet crop is
    -- clipped within its crop; an atlas keeps its own coordinates.
    local tex = frm.texture
    local tc = tex.azaTC
    if tex.azaAtlas then
        -- left as the atlas set it
    elseif tc then
        local cw, ch = tc[2] - tc[1], tc[4] - tc[3]
        tex:SetTexCoord(tc[1] + texX1 * cw, tc[1] + texX2 * cw, tc[3] + texY1 * ch, tc[3] + texY2 * ch)
    else
        tex:SetTexCoord(texX1, texX2, texY1, texY2)
    end

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
    -- Build-order step 14, 2026-11-11: now Style-tab swappable (see
    -- UI/StyleOptions.lua's PlayerMarker category) - same one-time-set
    -- pattern as before ("Arrow" is still the default), just resolved
    -- through the registry instead of a hardcoded path. GetTexture()
    -- still correctly detects "already set" even if the live choice is
    -- an atlas (SetAtlas populates the same underlying texture file,
    -- so GetTexture() returns non-nil either way) - no change needed
    -- to this guard itself. ApplyStyleChange("PlayerMarker") handles
    -- forcing a live-picked change onto this same frame.texture.
    if not frm.texture:GetTexture() then
        AzerothAtlas.UI.StyleOptions:ApplyIcon(frm.texture, "PlayerMarker")
    end
    -- 2026-11-16: inside a dungeon whose map doesn't report the
    -- player's position there is nothing honest to draw.
    if self.PlyrPosUnknown or not self:IsViewingPlayerFloor() then
        frm:Hide()
        return
    end
    -- 2026-11-16: always on top (user request) - overlay strata plus
    -- its own level, above every icon, trail and the radar patch.
    local MinimapWindow = AzerothAtlas.Modules.Map.MinimapWindow
    local overlay = MinimapWindow and MinimapWindow.OVERLAY_STRATA or "FULLSCREEN"
    if frm:GetFrameStrata() ~= overlay then frm:SetFrameStrata(overlay) end
    frm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + PLAYER_LEVEL_OFFSET)
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

-- Build-order step 9k, 2026-11-10: the Filter button/menu
-- (FilterMenu.lua) - shared by this section and the gathering-node
-- section further down, so it's declared here, before both. Missing
-- key = on, same "absent means default" convention as MinimapWindow.
-- lua's own AutoFollow checkbox, so a brand new filter key never
-- needs a migration to default everyone's existing saved profile to
-- visible.
local function IsMapFilterOn(key)
    -- 2026-11-18: FilterMenu knows which rows start off ("Other
    -- faction's travel"); ask it when it's loaded.
    local FilterMenu = AzerothAtlas.Modules.Map.FilterMenu
    if FilterMenu and FilterMenu.IsFilterOn then return FilterMenu.IsFilterOn(key) end
    local filters = AzerothAtlas.db and AzerothAtlas.db.profile and AzerothAtlas.db.profile.MapFilters
    return not filters or filters[key] ~= false
end

local SERVICE_ICON_SIZE = 16
-- 2026-11-16: boats and zeppelins a size up - the way off a continent.
-- 2026-11-18: portals and trams join them.
local SERVICE_ICON_SIZE_BY_KIND = { Boat = 22, Zeppelin = 22, Portal = 22, Tram = 22 }
-- Kinds shown on a continent / Azeroth view (2026-11-17).
local WIDE_VIEW_KINDS = { DungeonEntrance = true, Boat = true, Zeppelin = true, Portal = true, Tram = true }
-- Kinds the "Other faction's travel" filter can bring back (2026-11-18,
-- user request, from Leatrix Maps' "Show opposing faction points of
-- interest": flight points, boats, zeppelins, trams and portals).
local OPPOSING_KINDS = { Boat = true, Zeppelin = true, Portal = true, Tram = true }

-- Standard Blizzard minimap-tracking-filter textures (not Carbonite's
-- own icon atlas) - long-standing paths, present since Classic.
-- Innkeeper confirmed rendering live, 2026-11-10 (visible once the
-- faction-filter bug above was found and fixed). Mailbox switched the
-- same day to Interface\Icons\INV_Letter_15 - the user reported no
-- mail icon at all, and Interface\Minimap\TrackingIcons\Mailbox was
-- diagnosed (wrongly, see below) as being in the exact same
-- Interface\Minimap\... texture family confirmed BROKEN on this
-- server build (MinimapDock.lua's native mail-icon fix, same session -
-- MiniMap-MailIcon renders nothing here).
--
-- 2026-11-11 follow-up, user reported the live result directly: a flat
-- item icon like INV_Letter_15 has no transparency at all (Blizzard
-- inventory art is always a painted opaque square, no alpha) - raw on
-- the map it reads as "a black box and background with a border," not
-- a free-floating pin. Re-examined the original diagnosis: the path
-- actually tried was Interface\Minimap\TrackingIcons\Mailbox (the
-- "TrackingIcons" folder - an older/different asset family), which got
-- conflated with the separately-broken MiniMap-MailIcon (Blizzard's
-- unrelated "you have new mail" notification icon, not a map-tracking
-- pin at all, just sharing the word "mail"). The real, modern tracking-
-- pin family - Interface\Minimap\TRACKING\<Name> - was never actually
-- tried for Mailbox, even though Innkeeper/Banker below already
-- confirm it works fine on this server for sibling categories. Fixed
-- by switching to that same family. Not yet live-confirmed for Mailbox
-- specifically - tell me if it still looks wrong.
local SERVICE_ICON_TEX = {
    Mailbox         = "Interface\\MINIMAP\\TRACKING\\Mailbox",
    Innkeeper       = "Interface\\MINIMAP\\TRACKING\\Innkeeper",
    -- 2026-11-11: explicit user request after noticing auctioneers
    -- missing from the map entirely - no SERVICE_ICON_TEX entry had
    -- ever existed for this kind. Same confirmed-working TRACKING
    -- family as Innkeeper/Banker; data ported the same way (see
    -- Map/Data/GuideAuctioneer.lua).
    Auctioneer      = "Interface\\MINIMAP\\TRACKING\\Auctioneer",
    -- Build-order step 9l, 2026-11-10: bank/dungeon/zone-transition
    -- icons, explicit user request. Banker is the same confirmed-
    -- working Interface\MINIMAP\TRACKING\... family as Innkeeper above
    -- (high confidence); DungeonEntrance/ZoneTransition have no
    -- matching TRACKING icon at all (that filter list has never had a
    -- "dungeon" or "zone border" category), so these use plain
    -- Interface\Icons\... item-icon paths instead - a different family
    -- than Mailbox's own fix needed, but the same "pick something
    -- guaranteed to exist since vanilla" reasoning. Not yet confirmed
    -- live for any of these three - same caveat FlightMaster/Banker
    -- itself carries below, tell me if any renders blank. (Both now
    -- have real Leatrix_Maps atlas alternatives in the Style tab if
    -- they turn out to have the same "flat black box" look Mailbox
    -- just did - see UI/StyleOptions.lua's build-order step 14.)
    Banker          = "Interface\\MINIMAP\\TRACKING\\Banker",
    DungeonEntrance = "Interface\\Icons\\INV_Misc_Key_03",
    ZoneTransition  = "Interface\\Icons\\INV_Misc_Map_01",
    -- Build-order step 11, 2026-11-11: spirit healer icons, explicit
    -- user request. No native Blizzard tracking icon or Carbonite data
    -- exists for this (see Map/Data/GuideSpiritHealer.lua's own header
    -- for the full citation) - same "guaranteed since vanilla" plain
    -- Interface\Icons\... reasoning as DungeonEntrance/ZoneTransition
    -- above, picked for thematic fit (the resurrection-spell icon)
    -- rather than Leatrix_Maps' own atlas choice, to avoid adding
    -- atlas-vs-texture branching to UpdateServiceIcons below.
    SpiritHealer    = "Interface\\Icons\\Spell_Holy_Resurrection",
    -- 2026-11-16: boats and zeppelins, split out of ZoneTransition
    -- (GuideZoneTransition.lua) with icons of their own, drawn for this
    -- addon by Tools/make_transport_icons.py.
    Boat            = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\IconBoat",
    Zeppelin        = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\IconZeppelin",
    -- 2026-11-18: portals and trams, split out of ZoneTransition the
    -- same way, drawn by the same tool.
    Portal          = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\IconPortal",
    Tram            = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\IconTram",
    -- 2026-11-18 (user request, from Carbonite): trainers, data from
    -- Carbonite's camelot guides (Map/Data/GuideTrainer.lua). The game's
    -- own "find trainers" tracking icons, same family as Innkeeper.
    ClassTrainer      = "Interface\\MINIMAP\\TRACKING\\Class",
    ProfessionTrainer = "Interface\\MINIMAP\\TRACKING\\Profession",
}

-- Build-order step 14, 2026-11-11: these three (plus FlightMaster's
-- own separate branch below) now also have real Leatrix_Maps atlas/
-- texcoord alternatives, swappable from the Style tab - everything
-- else in SERVICE_ICON_TEX above has no Leatrix equivalent and keeps
-- reading that fixed table unchanged.
local STYLE_BACKED_KINDS = {
    DungeonEntrance = true,
    ZoneTransition  = true,
    SpiritHealer    = true,
}

-- Build-order step 12, 2026-11-11: hover tooltips on every service
-- icon, explicit user request ("hovering the icon to tell what it
-- is, same as how the gather points work"). Gather icons identify
-- themselves via per-node data (species name/level); these icons have
-- no such per-node database, just a fixed category - so this is the
-- generic fallback label shown whenever a point has no more specific
-- name of its own (every Mailbox/Innkeeper/Banker/SpiritHealer point,
-- plus any DungeonEntrance/ZoneTransition/FlightMaster/GuardFlag point
-- whose real source data happens to have no name either).
local SERVICE_ICON_LABEL = {
    Mailbox         = "Mailbox",
    Innkeeper       = "Innkeeper",
    Auctioneer      = "Auctioneer",
    Banker          = "Banker",
    DungeonEntrance = "Dungeon/Raid Entrance",
    ZoneTransition  = "Zone Transition",
    SpiritHealer    = "Spirit Healer",
    FlightMaster    = "Flight Master",
    GuardFlag       = "Guard Directions",
    Boat            = "Boat",
    Zeppelin        = "Zeppelin",
    Portal          = "Portal",
    Tram            = "Tram",
    ClassTrainer      = "Class Trainer",
    ProfessionTrainer = "Profession Trainer",
}

---------------------------------------------------------------------------------------
-- Click a travel or dungeon icon to open where it goes (2026-11-18, user
-- request, from Leatrix Maps). On the big map only - the small map is
-- the "where am I" view and always follows you.
--   zone exit, boat, zeppelin, portal, tram   opens the map it leads to
--   dungeon / raid entrance                   opens the dungeon's map; when
--                                             several share one entrance
--                                             (Blackrock Mountain, Ahn'Qiraj)
--                                             a small list picks one
-- Leatrix does the same on the world map (a "click catcher" over the
-- hovered pin, then C_Map.OpenWorldMap); here it's BrowseTo, the same
-- call the big map's Zones and Dungeons menus make.
---------------------------------------------------------------------------------------

local function BigMapShown()
    local BigMap = AzerothAtlas.Modules.Map.BigMap
    return BigMap and BigMap.IsBig and BigMap:IsBig() or false
end

local function NormDungeonName(n)
    return ((n or ""):lower():gsub("^the ", ""):gsub("[^%w]", ""))
end

-- The big map's browsable dungeons whose name matches an entrance's.
local function DungeonsNamed(names)
    local found = {}
    local list = MinimapEngine:GetBrowseDungeons()
    for _, want in ipairs(names or {}) do
        local w = NormDungeonName(want)
        for _, d in ipairs(list) do
            if NormDungeonName(d.name) == w then found[#found + 1] = d end
        end
    end
    return found
end

-- What clicking the point would open, as a tooltip line, or nil.
local function ServiceClickHint(pt)
    if not pt or not BigMapShown() then return nil end
    if pt.dest and pt.dest ~= MinimapEngine.MapId then
        return "Click to open " .. MinimapEngine:MapName(pt.dest)
    end
    if pt.dungeons then
        local n = #DungeonsNamed(pt.dungeons)
        if n == 1 then return "Click to open its map" end
        if n > 1 then return "Click to pick a map" end
    end
    return nil
end

local function ServiceFrameOnClick(frm)
    local pt = frm.svcPt
    if not pt or not BigMapShown() then return end
    local E = MinimapEngine
    if pt.dest and pt.dest ~= E.MapId then
        GameTooltip:Hide()
        E:BrowseTo("map", pt.dest)
        return
    end
    if pt.dungeons then
        local found = DungeonsNamed(pt.dungeons)
        if #found == 1 then
            GameTooltip:Hide()
            E:BrowseTo("dungeon", found[1].id, found[1].name)
        elseif #found > 1 then
            local BigMap = AzerothAtlas.Modules.Map.BigMap
            local items = {}
            for _, d in ipairs(found) do
                items[#items + 1] = { d.name, function() E:BrowseTo("dungeon", d.id, d.name) end }
            end
            if BigMap and BigMap.OpenMenu then BigMap.OpenMenu(frm, items) end
        end
    end
end

local function ServiceFrameOnEnter(frm)
    GameTooltip:SetOwner(frm, "ANCHOR_CURSOR")
    GameTooltip:SetText(frm.svcLabel or "?")
    local pt = frm.svcPt
    if pt and pt.factionNote then
        GameTooltip:AddLine(pt.factionNote, 1, 0.45, 0.45)
    end
    local hint = ServiceClickHint(pt)
    if hint then GameTooltip:AddLine(hint, 0.5, 0.85, 1) end
    GameTooltip:Show()
end

local function ServiceFrameOnLeave()
    GameTooltip:Hide()
end

local function ServiceFrameOnMouseUp(frm, button)
    if button == "LeftButton" then
        ServiceFrameOnClick(frm)
    elseif button == "RightButton" then
        -- The map's own right-click menu, as if the icon weren't there.
        MinimapEngine:OnMouseUp("RightButton")
    end
end

-- Not yet confirmed either way - same TRACKING family as the now-
-- confirmed-working Innkeeper path above, so likely fine; flight-
-- master's own absence in the user's 2026-11-10 report is more likely
-- a C_TaxiMap data/mapID question than a texture one. See
-- RefreshServiceIcons' own header comment for the open question.
--
-- Build-order step 14, 2026-11-11: this is now style-backed (see
-- STYLE_BACKED_KINDS/RefreshServiceIcons below) - its default value
-- moved to UI/StyleOptions.lua's FlightMaster category ("Tracking"
-- option) instead of living here as a lone constant.

-- Build-order step 9l, 2026-11-10: "the flag to mark locations given
-- by guards" - a real Blizzard mechanic (talk to a guard, pick the
-- "directions" gossip option, get a temporary flag pointing at a city
-- service) published through C_GossipInfo.GetPoiForUiMapID/GetPoiInfo.
-- Found by reading Carbonite's own MapEngine.lua (it defensively
-- checks for GetPoiForUiMapID's existence before using it rather than
-- assuming every client has it) - NOT yet confirmed to actually return
-- data on this server build, unlike FlightMaster's C_TaxiMap branch
-- which was live-verified. Built the same defensive way regardless
-- (existence-checked, pcall-wrapped); tell me if this one simply never
-- shows anything after asking a guard for directions and it needs a
-- live round the way flight masters did.
local GUARDFLAG_TEX = "Interface\\Icons\\INV_BannerPVP_01"
-- No Leatrix alternative exists for this one (not style-backed) - a
-- single static spec table, same shape StyleOptions:GetOption returns,
-- so UpdateServiceIcons' reference-identity diff-cache treats every
-- point uniformly regardless of which branch produced it.
local GUARDFLAG_SPEC = { tex = GUARDFLAG_TEX }

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

    local StyleOptions = AzerothAtlas.UI.StyleOptions
    for kind, tex in pairs(SERVICE_ICON_TEX) do
        -- FilterMenu.lua's "Innkeepers"/"Mailboxes" rows - kind here
        -- is literally "Mailbox"/"Innkeeper", the same keys those rows
        -- use, so no translation table needed.
        if IsMapFilterOn(kind) then
            -- Build-order step 14: style-backed kinds resolve through
            -- the Style tab's current choice instead of the fixed
            -- table above; the option TABLE itself (not just its
            -- texture/atlas string) is what gets cached onto each
            -- point, so UpdateServiceIcons below can diff-cache by
            -- reference the same way for every kind.
            local iconSpec = STYLE_BACKED_KINDS[kind]
                and StyleOptions:GetOption(kind)
                or { tex = tex }
            local data = self.GuideData and self.GuideData[kind]
            -- 2026-11-17: a continent or Azeroth view shows the points of
            -- interest of every zone on it (dungeons, boats, zeppelins).
            local zoneList = { self.MapId }
            if self.WideView then
                zoneList = {}
                if WIDE_VIEW_KINDS[kind] then
                    local conts = self.ShowAllConts and { 1, 2, 3 } or { self.Cont }
                    for _, c in ipairs(conts) do
                        for _, id in ipairs(self.MapZones[c] or {}) do zoneList[#zoneList + 1] = id end
                    end
                end
            end
            for _, zoneId in ipairs(zoneList) do
            local entry = data and data[zoneId]
            if entry then
                -- Build-order step 12, 2026-11-11: trailing ",name" is
                -- optional (the `,?` before it) - every pre-existing
                -- Mailbox/Innkeeper/Banker/SpiritHealer entry has no
                -- 4th field at all and still matches cleanly, name
                -- just comes back "". Only GuideDungeonEntrance.lua/
                -- GuideZoneTransition.lua's own conversion loops were
                -- changed to actually populate it.
                for fac, x, y, name in entry:gmatch("(%d+),([%d%.]+),([%d%.]+),?([^|]*)") do
                    fac = tonumber(fac)
                    -- 2026-11-18: "Boat to Darkshore#1439" - the map the
                    -- point leads to (GuideZoneTransition.lua).
                    local dest
                    local base, d = name:match("^(.-)#(%d+)$")
                    if base then name, dest = base, tonumber(d) end
                    local own = ServiceIconFactionOk(fac)
                    local shown = own or (OPPOSING_KINDS[kind] and IsMapFilterOn("OpposingFaction"))
                    -- 2026-11-18: class trainers - your own class's only,
                    -- like Carbonite's "Show Class Trainer".
                    if shown and kind == "ClassTrainer" then
                        local _, token = UnitClass("player")
                        shown = token ~= nil and name:upper() == token .. " TRAINER"
                    end
                    local wx, wy
                    if shown then wx, wy = self:GetWorldPos(zoneId, tonumber(x), tonumber(y)) end
                    -- 2026-11-18: dungeons sharing one entrance (Blackrock
                    -- Mountain, Ahn'Qiraj) become one icon listing them all.
                    local merged
                    if wx and kind == "DungeonEntrance" then
                        for _, other in ipairs(pts) do
                            if other.dungeons and other.zone == zoneId and other.px == x and other.py == y then
                                other.dungeons[#other.dungeons + 1] = name
                                other.label = other.label .. " / " .. name
                                merged = true
                                break
                            end
                        end
                    end
                    if wx and not merged then
                            -- Build-order step 12, fourth follow-up,
                            -- 2026-11-11: reverted the third follow-
                            -- up's Innkeeper-shows-zone-name special
                            -- case - explicit user request ("just call
                            -- the innkeeper innkeeper... we will just
                            -- have the name of the place be on the
                            -- flight master"). Innkeeper is back to
                            -- the plain generic label, same as Mailbox
                            -- /Banker/SpiritHealer; only FlightMaster's
                            -- own node.name carries a location now.
                            local label = (name ~= "" and name) or SERVICE_ICON_LABEL[kind]
                            local pt = { x = wx, y = wy, iconSpec = iconSpec, label = label,
                                size = SERVICE_ICON_SIZE_BY_KIND[kind], dest = dest }
                            if not own then
                                pt.factionNote = (fac == 1 and "Alliance only") or "Horde only"
                            end
                            if kind == "DungeonEntrance" and name ~= "" then
                                pt.dungeons, pt.zone, pt.px, pt.py = { name }, zoneId, x, y
                            end
                            -- 2026-11-18 (user request): the exit arrow points
                            -- into the zone it leads to, like Leatrix's
                            -- (Map/Data/ZoneArrowAngles.lua, made by
                            -- Tools/gen_zone_arrow_angles.py). Only the arrow
                            -- style turns - the map-scroll icon stays upright.
                            if kind == "ZoneTransition" and iconSpec.atlas == "Garr_LevelUpgradeArrow" then
                                local angles = AzerothAtlas.Map.ZoneArrowAngles
                                pt.rot = angles and angles[zoneId .. ":" .. x .. ":" .. y]
                            end
                            pts[#pts + 1] = pt
                    end
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
    -- FilterMenu.lua's "Flight Masters" row.
    if IsMapFilterOn("FlightMaster") and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, self.MapId)
        if ok and type(nodes) == "table" then
            local showOther = IsMapFilterOn("OpposingFaction")
            for _, node in ipairs(nodes) do
                local own = TaxiFactionOk(tonumber(node.faction))
                if own or showOther then
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
                            -- Build-order step 12, 2026-11-11: node.name
                            -- is a real TaxiNodeInfo field (the flight
                            -- point's own name, e.g. "Orgrimmar") -
                            -- falls back to the generic label only if
                            -- it's ever missing/blank.
                            local label = (node.name and node.name ~= "" and node.name)
                                or SERVICE_ICON_LABEL.FlightMaster
                            -- Build-order step 14: style-backed, same as
                            -- DungeonEntrance/ZoneTransition/SpiritHealer above.
                            -- 2026-11-17: a "by faction" set gives each node
                            -- its own faction's icon.
                            local spec = StyleOptions:ForFaction(StyleOptions:GetOption("FlightMaster"),
                                tonumber(node.faction) or 0)
                            pts[#pts + 1] = { x = wx, y = wy, iconSpec = spec, label = label,
                                -- C_TaxiMap: 1 = Horde, 2 = Alliance.
                                factionNote = not own and ((tonumber(node.faction) == 1 and "Horde only")
                                    or "Alliance only") or nil }
                        end
                    end
                end
            end
        end
    end

    -- FilterMenu.lua's "Guard Directions" row. Only one active flag
    -- per map at a time (that's the real mechanic - asking a second
    -- guard replaces the first), so at most one point gets added here.
    if IsMapFilterOn("GuardFlag") and C_GossipInfo and C_GossipInfo.GetPoiForUiMapID and C_GossipInfo.GetPoiInfo then
        local ok, poiID = pcall(C_GossipInfo.GetPoiForUiMapID, self.MapId)
        if ok and poiID then
            local infoOk, info = pcall(C_GossipInfo.GetPoiInfo, self.MapId, poiID)
            if infoOk and type(info) == "table" and info.position then
                local pos = info.position
                local nx, ny = pos.x, pos.y
                if (nx == nil or ny == nil) and pos.GetXY then
                    nx, ny = pos:GetXY()
                end
                if nx and ny then
                    local wx, wy = self:GetWorldPos(self.MapId, nx * 100, ny * 100)
                    if wx then
                        -- Build-order step 12, 2026-11-11: WorldMapPOIInfo's
                        -- exact field for the service name isn't
                        -- confirmed on this client - tries .name then
                        -- .description before falling back to the
                        -- generic label, same defensive posture as the
                        -- rest of this branch already has.
                        local label = (info.name and info.name ~= "" and info.name)
                            or (info.description and info.description ~= "" and info.description)
                            or SERVICE_ICON_LABEL.GuardFlag
                        pts[#pts + 1] = { x = wx, y = wy, iconSpec = GUARDFLAG_SPEC, label = label }
                    end
                end
            end
        end
    end
end

-- DYNAMIC_GOSSIP_POI_UPDATED fires the moment a guard's directions
-- flag appears/changes - without this, the guard-flag branch above
-- would only ever refresh on the next zone change, missing the common
-- case of asking a guard while already standing in the zone the flag
-- belongs to. Registering an event name that doesn't exist on this
-- client is harmless (RegisterEvent silently no-ops), so this is safe
-- to leave in even if the event itself turns out not to fire here.
local guardFlagWatcher = CreateFrame("Frame")
guardFlagWatcher:RegisterEvent("DYNAMIC_GOSSIP_POI_UPDATED")
guardFlagWatcher:SetScript("OnEvent", function()
    if MinimapEngine.RefreshServiceIcons then
        MinimapEngine:RefreshServiceIcons()
    end
end)

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
            local frm = self:CreateMiniFrame()
            -- Build-order step 12, 2026-11-11: hover tooltips, explicit
            -- user request ("same as how the gather points work") -
            -- same EnableMouse/OnEnter/OnLeave wiring GatherFrms already
            -- uses, just reading frm.svcLabel (set fresh every pass
            -- below) instead of a dbType/nodeID database lookup.
            frm:EnableMouse(true)
            frm:SetScript("OnEnter", ServiceFrameOnEnter)
            frm:SetScript("OnLeave", ServiceFrameOnLeave)
            frm:SetScript("OnMouseUp", ServiceFrameOnMouseUp)
            self.SvcFrms[n] = frm
        end
    end

    local StyleOptions = AzerothAtlas.UI.StyleOptions
    local level = (self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET
    for i, pt in ipairs(pts) do
        local frm = self.SvcFrms[i]
        if frm.svcIconSpec ~= pt.iconSpec then
            StyleOptions:ApplyIconSpec(frm.texture, pt.iconSpec)
            frm.svcIconSpec = pt.iconSpec
        end
        frm.svcLabel = pt.label
        frm.svcPt = pt
        local size = pt.size or SERVICE_ICON_SIZE
        if self:ClipFrameW(frm, pt.x, pt.y, size, size, pt.rot) then
            frm:SetFrameLevel(level)
            frm:SetAlpha(self.PoiOpacity or 1)      -- 2026-11-18: a slider
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
-- Build-order step 13, 2026-11-11: was a fixed local
-- ("Interface\GossipFrame\ActiveQuestIcon", Carbonite's own
-- QuestPin.lua ICONS.turnin value) - now one of three Style-tab
-- swappable categories (see UI/StyleOptions.lua). Resolved fresh each
-- RefreshQuestIcons() call (not hot-loop - that only runs on zone
-- change + a time throttle), so a changed choice reaches QuestPts
-- without any extra plumbing; UpdateQuestIcons' own existing
-- svcIconSpec-diff check then naturally re-applies it to each live frame.

function MinimapEngine:HideQuestFrames()
    for i = 1, #self.QuestFrms do
        self.QuestFrms[i]:Hide()
    end
end

local function QuestFrameOnEnter(frm)
    local pt = frm.questPt
    local QuestPins = AzerothAtlas.Modules.Quest and AzerothAtlas.Modules.Quest.Pins
    if pt and pt.label and QuestPins then
        QuestPins:ShowTooltip(frm, pt)
    end
end

local function QuestFrameOnLeave()
    GameTooltip:Hide()
end

local function QuestFrameOnMouseUp(frm, button)
    local pt = frm.questPt
    local QuestPins = AzerothAtlas.Modules.Quest and AzerothAtlas.Modules.Quest.Pins
    if button == "LeftButton" and pt and QuestPins then
        QuestPins:OnClick(pt)
    elseif button == "RightButton" and pt and QuestPins and QuestPins.OnRightClick then
        QuestPins:OnRightClick(frm, pt)
    end
end

-- Quest companion (2026-11-15): this section grew from turn-in markers
-- only to the three roles Carbonite's own QuestPin.lua defines -
-- turn-in, objective, and giver ("a quest I could pick up here"). The
-- second finding in this section's header no longer blocks the giver
-- role: Carbonite.Quests' bundled data turned out to carry every
-- giver's map id and coordinates in this client's own uiMapID scheme,
-- already merged from Questie's database, so nothing needs Questie's
-- private ZoneDB after all (ported as Quest/Data/*.lua).
--
-- What goes on the map is decided in Quest/QuestPins.lua - it knows
-- about the quest log, the bundled database and the current route.
-- This file still owns the frames and draws them exactly as before:
-- the same CreateMiniFrame pool, the same fixed-size ClipFrameW point
-- clip. A point may now also carry a size, a tint, tooltip lines and a
-- click target; a point with none of those draws as the old turn-in
-- marker did.
--
-- Called on zone change (RefreshCurrentZone) and on a time throttle
-- from Update() below, since quest state (unlike the static mailbox/
-- innkeeper data) can change without a zone change at all. QuestPins
-- also zeroes QuestRefreshAt when quest state or the route changes, so
-- the map doesn't wait out that throttle after a turn-in.
function MinimapEngine:RefreshQuestIcons()
    local pts = {}
    self.QuestPts = pts
    local mapId = self.MapId
    if not mapId then return end

    local QuestPins = AzerothAtlas.Modules.Quest and AzerothAtlas.Modules.Quest.Pins
    if QuestPins and QuestPins.Collect then
        local ok, err = pcall(QuestPins.Collect, QuestPins, self, pts)
        if not ok and self.QuestPinError ~= err then
            -- Report a failure once, not on every refresh tick.
            self.QuestPinError = err
            AzerothAtlas.Core.Logger:Get("Map"):error("quest pins failed: %s", tostring(err))
        end
        return
    end

    -- The Quest module didn't load: fall back to the original turn-in-
    -- only markers, straight from Blizzard's live POI list, so a problem
    -- over there can't take away what this map already had.
    if not C_QuestLog or not C_QuestLog.GetQuestsOnMap then return end

    local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapId)
    if not ok or type(quests) ~= "table" then return end

    local iconSpec = AzerothAtlas.UI.StyleOptions:GetOption("QuestIcon")
    for _, info in ipairs(quests) do
        local questID = info and info.questID
        if questID and type(info.x) == "number" and type(info.y) == "number" then
            local completeOk, complete = pcall(C_QuestLog.IsComplete, questID)
            if completeOk and complete then
                local wx, wy = self:GetWorldPos(mapId, info.x * 100, info.y * 100)
                if wx then
                    pts[#pts + 1] = { x = wx, y = wy, iconSpec = iconSpec }
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
            local frm = self:CreateMiniFrame()
            -- Same hover/click wiring as the service and gather pools;
            -- what the tooltip says and what a click does is QuestPins'
            -- business, read from frm.questPt (set fresh every pass).
            frm:EnableMouse(true)
            frm:SetScript("OnEnter", QuestFrameOnEnter)
            frm:SetScript("OnLeave", QuestFrameOnLeave)
            frm:SetScript("OnMouseUp", QuestFrameOnMouseUp)
            self.QuestFrms[n] = frm
        end
    end

    local level = (self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET
    for i, pt in ipairs(pts) do
        local frm = self.QuestFrms[i]
        if frm.svcIconSpec ~= pt.iconSpec then
            AzerothAtlas.UI.StyleOptions:ApplyIconSpec(frm.texture, pt.iconSpec)
            frm.svcIconSpec = pt.iconSpec
        end
        frm.questPt = pt
        local size = pt.size or QUEST_ICON_SIZE
        if self:ClipFrameW(frm, pt.x, pt.y, size, size) then
            -- 2026-11-17: a quest hovered in the quest list (Quest/QuestPins
            -- .lua Pins:SetFocus): its pins on top with a glow, the rest faded.
            frm:SetFrameLevel(level + (pt.focus and 2 or 0))
            -- Frames are pooled across roles: always set the tint, so
            -- an untinted pin never inherits the last quest's colour.
            frm.texture:SetVertexColor(pt.r or 1, pt.g or 1, pt.b or 1,
                (pt.dim and 0.22 or 1) * (self.QuestIconOpacity or 1))     -- 2026-11-18: a slider
            -- Same reason: a low-level pickup pin is drawn gray, and
            -- the next pin to use this frame must not stay that way.
            frm.texture:SetDesaturated(pt.desat and true or false)
            if pt.focus then
                local glow = frm.focusGlow
                if not glow then
                    glow = frm:CreateTexture(nil, "BACKGROUND")
                    glow:SetTexture("Interface\\Cooldown\\star4")
                    glow:SetBlendMode("ADD")
                    glow:SetPoint("CENTER")
                    frm.focusGlow = glow
                end
                glow:SetSize(size * 2.6, size * 2.6)
                if pt.r then
                    glow:SetVertexColor(pt.r, pt.g, pt.b, 1)
                else
                    glow:SetVertexColor(1, 0.82, 0.2, 1)
                end
                glow:Show()
            elseif frm.focusGlow then
                frm.focusGlow:Hide()
            end
        end
    end
    for n = #pts + 1, #self.QuestFrms do
        self.QuestFrms[n]:Hide()
    end
end

-- Build-order step 13, 2026-11-11: called by UI/StyleOptions.lua's
-- SetChoice when the user picks a different option in the Style tab.
-- QuestIcon/DungeonEntrance/ZoneTransition/FlightMaster/SpiritHealer
-- need no per-frame handling here - each one's Refresh*() resolves
-- GetOption() fresh every call, and the matching Update*()'s own
-- svcIconSpec-diff check already re-applies a changed value to every
-- live frame on its own next tick, so a cheap Refresh+Update re-run is
-- all that's needed to force it immediately rather than waiting on
-- that tick. TrailArrow, GotoMarker, and PlayerMarker have no such
-- per-tick re-check (their SetTexture/SetAtlas calls only fire once,
-- when a pooled frame - or the one player marker frame - is first
-- created - see each one's own call site comment) so already-existing
-- frames need to be force-updated directly here instead.
function MinimapEngine:ApplyStyleChange(key)
    local StyleOptions = AzerothAtlas.UI.StyleOptions

    if key == "TrailArrow" then
        local spec = StyleOptions:GetOption("TrailArrow")
        -- A plain numeric loop, not ipairs over a table literal: a pool
        -- that doesn't exist yet would be a nil hole and end ipairs
        -- early, skipping the pools after it.
        local pools = { self.GotoTrailFrms, self.CorpseTrailFrms, self.QuestTrailFrms }
        for n = 1, 3 do
            local pool = pools[n]
            if pool then
                for _, f in ipairs(pool) do
                    StyleOptions:ApplyIconSpec(f.texture, spec)
                end
            end
        end
    elseif key == "GotoMarker" then
        if self.GotoFrm then
            StyleOptions:ApplyIcon(self.GotoFrm.texture, "GotoMarker")
        end
        if self.QuestRouteFrm then
            StyleOptions:ApplyIcon(self.QuestRouteFrm.texture, "GotoMarker")
        end
    elseif key == "PlayerMarker" then
        if self.PlyrFrm then
            StyleOptions:ApplyIcon(self.PlyrFrm.texture, "PlayerMarker")
        end
    elseif key == "QuestIcon" or key == "QuestGiverIcon" or key == "QuestObjectiveIcon" then
        -- self.Frm: the Style tab can be used before the map window has
        -- ever been opened, when there are no icon pools to update yet.
        if self.Frm then
            self:RefreshQuestIcons()
            self:UpdateQuestIcons()
        end
    elseif key == "HUDArrow" then
        -- Not a map icon at all - the Quest module's floating arrow -
        -- but StyleOptions:SetChoice has this one notification hook.
        local HUD = AzerothAtlas.Modules.Quest and AzerothAtlas.Modules.Quest.HUD
        if HUD then HUD:ApplyStyle() end
    elseif key == "DungeonEntrance" or key == "ZoneTransition"
        or key == "FlightMaster" or key == "SpiritHealer" then
        self:RefreshServiceIcons()
        self:UpdateServiceIcons()
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
-- popup go away either, while disabling AzerothAtlas entirely did -
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
-- the global table renamed (AzerothAtlas* instead of GatherMateData2*,
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
-- Node glow (1.27) is parked: see UpdateGatherIcons.
local GATHER_GLOW_ENABLED = false
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
local GATHER_NODE_INFO = _G.AzerothAtlasGatherNodeInfo

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
    -- 2026-11-18: a recorded node the shipped list doesn't know keeps
    -- its name as its ID (Map/GatherRecorder.lua).
    local name = (info and info.name) or (type(nodeID) == "string" and nodeID) or dbType
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
    if frm.gatherMine then
        GameTooltip:AddLine("You gathered here", 0.6, 0.8, 1)
    end
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
    Herb     = _G.AzerothAtlasHerbDB,
    Mine     = _G.AzerothAtlasMineDB,
    Fish     = _G.AzerothAtlasFishDB,
    Treasure = _G.AzerothAtlasTreasureDB,
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

-- Build-order step 16 (2026-11-11): user-reported duplicate nodes -
-- "some nodes are rendering twice... I am guessing there are 2 node
-- entries from wowhead that are slightly off of each other." Plausible
-- and confirmed by this file's own earlier header (see the "Data
-- source" comment above `GATHER_DB`): this static data is a port of
-- Carbonite's own Gathermate2_Data "camelot" pack, itself built from
-- crowd-sourced Wowhead spawn reports that don't always land on the
-- exact same coordinate for what's physically one node. Fixed here at
-- render time (not by hand-editing/removing rows from the static
-- Gather*.lua tables) so it stays correct automatically if that data
-- is ever re-ported/updated later, and so it's trivially reversible if
-- the threshold needs tuning.
--
-- Any two points of the SAME SPECIES (nodeID) within
-- GATHER_DEDUPE_YARDS of each other collapse to just one. User's own
-- suggested range was "5-10 yards" - 7 picked as the middle (also
-- happens to match GOTO_ARRIVAL_YARDS elsewhere in this file, a
-- coincidence, not derived from it). Grouped by nodeID first (not a
-- flat O(n^2) scan over the whole zone) since a zone can carry 800+
-- entries total but any one species' own count within it is far
-- smaller - two different species can never be "the same node", so
-- there's no reason to ever compare across groups.
--
-- Which of a close pair survives is whichever pairs() visits first -
-- NOT guaranteed stable across sessions/reloads. Accepted: anything
-- this close is visually indistinguishable on the map anyway: the bug
-- being fixed is "two icons where there should be one", not which
-- exact one of two near-identical coordinates wins.
local GATHER_DEDUPE_YARDS = 7
-- Fresh local, same 4.575 constant/formula as Update()'s own PlyrSpeed
-- block and UpdateGoto's own YARDS_PER_WORLDUNIT local further down -
-- see that section's header comment for the citation. Not shared
-- across sections by design, same reasoning as TRAIL_ARROW_TEX/
-- YARDS_PER_WORLDUNIT elsewhere in this file (a fresh local per
-- section beats threading one constant through unrelated code).
local GATHER_DEDUPE_RANGE_SQ = (GATHER_DEDUPE_YARDS / 4.575) ^ 2

-- Pcall-wrapped per dbType so one bad zone/type combo in the static
-- data can't abort the other three categories.
local function CollectGatherZoneNodes(engine, mapId, dbType, pts)
    -- 2026-11-18: data imported from GatherMate2_Data replaces the
    -- shipped tables (Map/GatherRecorder.lua's Import).
    local Recorder = AzerothAtlas.Modules.Map.GatherRecorder
    local db = (Recorder and Recorder:Imported(dbType)) or GATHER_DB[dbType]
    local zoneNodes = db and db[mapId]
    -- 2026-11-18: and the nodes you've gathered yourself
    -- (Map/GatherRecorder.lua) - listed first, so a shipped node in the
    -- same spot is the duplicate that's dropped.
    local mine = Recorder and Recorder:Nodes(dbType, mapId)
    if not zoneNodes and not mine then return end

    local infoByID = GATHER_NODE_INFO and GATHER_NODE_INFO[dbType]
    local fallbackTex = GATHER_ICON_TEX[dbType]

    -- Pass 1: decode + world-position everything, bucketed by species
    -- (nodeID) so the dedupe pass below only ever compares points that
    -- could possibly be the same physical spawn.
    local bySpecies = {}
    local function add(nodes, isMine)
        for coord, nodeID in pairs(nodes) do
            local gx, gy = DecodeGatherCoord(coord)
            local wx, wy = engine:GetWorldPos(mapId, gx * 100, gy * 100)
            if wx then
                local bucket = bySpecies[nodeID]
                if not bucket then
                    bucket = {}
                    bySpecies[nodeID] = bucket
                end
                bucket[#bucket + 1] = { x = wx, y = wy, mine = isMine }
            end
        end
    end
    if mine then add(mine, true) end
    if zoneNodes then add(zoneNodes, false) end

    -- Pass 2: within each species bucket, drop any point landing
    -- within range of one already kept.
    for nodeID, bucket in pairs(bySpecies) do
        local info = infoByID and infoByID[nodeID]
        local tex = (info and info.tex) or fallbackTex
        local kept = {}
        for _, p in ipairs(bucket) do
            local dup = false
            for _, k in ipairs(kept) do
                local dx, dy = p.x - k.x, p.y - k.y
                if dx * dx + dy * dy <= GATHER_DEDUPE_RANGE_SQ then
                    dup = true
                    break
                end
            end
            if not dup then
                kept[#kept + 1] = p
                pts[#pts + 1] = { x = p.x, y = p.y, tex = tex, dbType = dbType, nodeID = nodeID, mine = p.mine }
            end
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

    local dbTypes = {}
    -- FilterMenu.lua's "Gathering Nodes" row covers all three
    -- profession-gated categories at once (user's own request to
    -- combine them); "Treasure" is its own separate row since it
    -- isn't profession-gated at all.
    if IsMapFilterOn("Gathering") then
        local known = GetKnownGatherProfessions()
        if known.Herb then dbTypes[#dbTypes + 1] = "Herb" end
        if known.Mine then dbTypes[#dbTypes + 1] = "Mine" end
        if known.Fish then dbTypes[#dbTypes + 1] = "Fish" end
    end
    if IsMapFilterOn("Treasure") then
        dbTypes[#dbTypes + 1] = "Treasure"
    end

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
            -- the real map window's own chrome (AzerothAtlas.Skin:
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
            -- is what keeps it behind frm instead. Build-order step 21
            -- same-day seventh follow-up (5-layer rework): this stays
            -- derived as "icon level - 1" rather than its own named
            -- constant - SERVICE_LEVEL_OFFSET was deliberately set to 5
            -- (not 4) specifically so this lands on the reserved,
            -- otherwise-unused level 4, clear of Terrain's level 3 -
            -- see SERVICE_LEVEL_OFFSET's own header comment.
            -- 2026-11-17: a plain solid square. It used the window skin's
            -- backdrop, whose border is sized for windows: on a box this
            -- small the edge pieces overlapped and drew a "#".
            frm.backdrop = CreateFrame("Frame", nil, self.Frm, "BackdropTemplate")
            frm.backdrop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            frm.backdrop:SetBackdropColor(0, 0, 0, 1)
            -- 2026-11-18 (user request, from Carbonite): node glow - the
            -- quest pins' focus glow, pulsing behind the icon.
            frm.glow = frm:CreateTexture(nil, "BACKGROUND")
            frm.glow:SetTexture("Interface\\Cooldown\\star4")
            frm.glow:SetBlendMode("ADD")
            frm.glow:SetPoint("CENTER")
            frm.glow:SetVertexColor(1, 0.82, 0.3, 1)
            frm.glow:Hide()
            self.GatherFrms[n] = frm
        end
    end

    local level = (self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET
    local px, py = self.PlyrX, self.PlyrY
    local size = GATHER_ICON_SIZE * (self.GatherIconScale or 1)
    -- Node glow (Settings > Map > Gathered nodes): one pulse value for
    -- every node this tick, GatherGlowSpeed pulses a second.
    local prof = AzerothAtlas.db and AzerothAtlas.db.profile
    -- 2026-11-18: switched off (user: "ALL the gathering nodes are
    -- glowing it should only be the ones that are active"). The data
    -- only says where a node CAN spawn, not whether one is up now, so
    -- every spot pulsed. Parked until we can tell live nodes apart -
    -- see GitHub issue #2. GATHER_GLOW_ENABLED turns it back on.
    local glowOn = GATHER_GLOW_ENABLED and (not prof or prof.GatherGlow ~= false)
    local glowNearOnly = prof and prof.GatherGlowNearOnly
    local pulse = 0
    if glowOn then
        local speed = (prof and prof.GatherGlowSpeed) or 1
        pulse = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(GetTime() * speed * 2 * math.pi))
    end
    for i, pt in ipairs(pts) do
        local frm = self.GatherFrms[i]
        if frm.svcTex ~= pt.tex then
            frm.texture:SetTexture(pt.tex)
            frm.svcTex = pt.tex
        end
        frm.gatherDbType, frm.gatherNodeID, frm.gatherMine = pt.dbType, pt.nodeID, pt.mine
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
            if glowOn and (near or not glowNearOnly) then
                frm.glow:SetSize(size * 2.4, size * 2.4)
                frm.glow:SetAlpha(pulse * (self.GatherOpacity or 1))
                frm.glow:Show()
            else
                frm.glow:Hide()
            end
        else
            frm.backdrop:Hide()
        end
    end
    for n = #pts + 1, #self.GatherFrms do
        self.GatherFrms[n]:Hide()
        self.GatherFrms[n].backdrop:Hide()
    end
end

-- Build-order step 16 (2026-11-11), diagnostic only - not the "active
-- node" feature itself, groundwork for it. User's second request:
-- show on the map whether a gathering node is actually there right
-- now, citing FarmHud (`R:\addons\FarmHud\`) as a known-good example.
--
-- Read FarmHud's own source first rather than guessing: it does NOT
-- do any independent live-node detection at all - it's a minimap
-- reskin (reparents/enlarges the REAL native Blizzard Minimap frame to
-- fill its own HUD, per `FarmHud.toc`'s own description: "Turns your
-- minimap into a hud for gathering resources!"). Its "active" accuracy
-- is just a free side effect of still being the real native Minimap -
-- Blizzard itself only ever draws a resource blip there when a node is
-- actually present and in range. That's the same ground-truth signal
-- this file's own header already went looking for and failed to
-- isolate (`C_VignetteInfo.GetVignettes()` returned 0; a raw scan of
-- `Minimap:GetRegions()` returned ~290 entries, declared "too noisy"
-- and dropped without filtering by anything).
--
-- This addon can't just become the native Minimap the way FarmHud does
-- - it draws its own separate custom window from a static database.
-- But the real native Minimap frame still exists in memory even when
-- hidden (`MinimapDock.lua`'s own "Hide Blizzard minimap" preference
-- doesn't destroy it) and still appears to receive blip updates, so
-- scanning IT for the real resource-blip texture - this time grouped
-- by texture path/atlas instead of dumped one-by-one - is worth a
-- second, more targeted look before building anything on top of it.
-- Classic/Wrath-era clients (this server's interface version matches
-- that family, per GatherMate2_Data's own `## Interface: 16001`) draw
-- minimap blips as plain Texture regions cropped from one shared sheet
-- (`Interface\Minimap\ObjectIconsAtlas`) via SetTexCoord, not individual
-- files - if that path shows up here with a small, stable count, it's
-- the real signal; this command exists to find out, not to assume it.
--
-- `/aatlas scanblips` - read-only, chat-only, no map/rendering changes.
-- Dumps every distinct texture/atlas path currently on the real
-- Minimap, grouped with a count, loudest first. Ask the user to run it
-- once while standing right on a visibly-active node and once well
-- away from any node, and compare the two lists - whatever path's
-- count changes between the two is the real blip texture.
local function ScanMinimapBlipTextures()
    local counts, order = {}, {}
    for _, region in ipairs({ Minimap:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            local path = region:GetTexture()
            local key = path and tostring(path) or "<no texture>"
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas and atlas ~= "" then
                key = key .. " (atlas: " .. atlas .. ")"
            end
            if not counts[key] then
                counts[key] = 0
                order[#order + 1] = key
            end
            counts[key] = counts[key] + 1
        end
    end
    table.sort(order, function(a, b) return counts[a] > counts[b] end)
    return order, counts
end

-- 2026-11-11 follow-up: first live run came back "0 distinct paths"
-- both on and off a node - that's not noise, it's a real result that
-- needs its OWN explanation before trying a different texture-name
-- filter. Most likely cause, found by reading this addon's own
-- `NativeMinimapHide.lua`: the "Hide Blizzard minimap" preference
-- (default ON) calls `MinimapCluster:Hide()`, and `Minimap` is a
-- descendant of `MinimapCluster` - a hidden ancestor plausibly means
-- the client never bothers creating/updating blip textures on it at
-- all, not just that they're invisible. This file's own OLDER "~290
-- children" finding (cited in RefreshGatherIcons's header) almost
-- certainly predates this addon hiding the native minimap by default.
-- Reporting IsVisible/IsShown + raw region/child counts (regardless of
-- type) alongside the grouped-by-texture list below, so the NEXT run
-- confirms or rules this out in one pass instead of another blind
-- round-trip.
AzerothAtlas.Core.SlashCommands:Register("scanblips", function()
    local Logger = AzerothAtlas.Core.Logger:Get("Map")
    local numRegions = select("#", Minimap:GetRegions())
    local numChildren = select("#", Minimap:GetChildren())
    Logger:info("Minimap:IsShown()=%s IsVisible()=%s regions=%d children=%d",
        tostring(Minimap:IsShown()), tostring(Minimap:IsVisible()), numRegions, numChildren)
    local order, counts = ScanMinimapBlipTextures()
    Logger:info("Minimap texture regions: %d distinct path(s)", #order)
    for _, key in ipairs(order) do
        Logger:info("  x%d  %s", counts[key], key)
    end
end, "dump real Minimap texture regions, grouped by path (gathering-node active-detection research)")

-- 2026-11-11, second follow-up: live result was `regions=0,
-- children=493` (then 499) both on and off a node, `IsShown()=true,
-- IsVisible()=false`. This fully explains the "0 distinct paths"
-- result above WITHOUT needing the hide theory at all - it's simpler
-- than that: `GetRegions()` only returns direct Texture/FontString/
-- Line children, and on this client, minimap blips are plainly NOT
-- raw Texture regions at all (that would've shown up as >0 regions
-- regardless of visibility) - they're child FRAMES (hence 493-499
-- `GetChildren()`). This file's own much-older "~290 children" finding
-- (RefreshGatherIcons's header) was actually the right call all along,
-- just abandoned one step too early - it needs a GROUPED or DIFFED
-- scan of children, not regions, to cut through the noise.
--
-- A plain count/texture dump of ~500 children would still be mostly
-- noise (quest POIs, group member dots, any leftover vignette pins,
-- every other installed addon's own minimap decoration). Diffing
-- against a snapshot cancels all of that out automatically, since
-- none of it changes just because the player walked up to one
-- specific spot - whatever children appear/disappear between a
-- snapshot taken away from any node and a second check taken standing
-- on one are the real candidates.
--
-- `/aatlas diffblips start` - snapshot current Minimap children (run this
-- FIRST, standing away from any node). `/aatlas diffblips` (no argument)
-- - compare right now against that snapshot and report exactly which
-- children were added/removed since, each described by its own name
-- (if any) plus any texture/atlas found on ITS children (one level
-- down, since a blip frame's actual icon is typically a texture nested
-- inside it, not on the blip frame itself). Snapshot is kept by object
-- identity (the frame itself as a table key), not by name or index,
-- since most of these are anonymous pooled frames with no `GetName()`
-- at all.
local blipSnapshot

-- 2026-11-11, second live round: first real non-empty diff (19 added,
-- 2 removed - the 2 removed were plainly just the minimap's own zoom
-- in/out buttons churning, named by their own atlases, unrelated
-- noise). All 19 added came back as bare `table: 0x...` with no
-- texture/atlas found - `DescribeMinimapChild` only ever looked at the
-- added frame's OWN immediate regions, one level. A pin frame's actual
-- icon is commonly nested a level or two further in (frame -> a child
-- frame -> ITS regions), so this now recurses a few levels down
-- looking for any Texture region anywhere inside, and also reports
-- each candidate's pixel size and its offset from Minimap's own center
-- - real blips should be small (icon-sized, not a layout frame) and
-- positioned somewhere other than dead center.
local function DescribeMinimapChild(child)
    local parts = {}
    local name = child.GetName and child:GetName()
    parts[#parts + 1] = name or tostring(child)

    if child.GetSize then
        local w, h = child:GetSize()
        parts[#parts + 1] = ("size:%.0fx%.0f"):format(w or 0, h or 0)
    end
    if child.GetCenter and Minimap.GetCenter then
        local cx, cy = child:GetCenter()
        local mx, my = Minimap:GetCenter()
        if cx and mx then
            parts[#parts + 1] = ("offset:%.0f,%.0f"):format(cx - mx, cy - my)
        end
    end

    local seen = {}
    local function scanRegions(frame, remaining)
        if seen[frame] then return end
        seen[frame] = true
        if frame.GetRegions then
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "Texture" then
                    local atlas = r.GetAtlas and r:GetAtlas()
                    local tex = r.GetTexture and r:GetTexture()
                    if atlas and atlas ~= "" then
                        parts[#parts + 1] = "atlas:" .. atlas
                    elseif tex then
                        parts[#parts + 1] = "tex:" .. tostring(tex)
                    end
                end
            end
        end
        if remaining > 0 and frame.GetChildren then
            for _, sub in ipairs({ frame:GetChildren() }) do
                scanRegions(sub, remaining - 1)
            end
        end
    end
    scanRegions(child, 3)

    return table.concat(parts, "  ")
end

AzerothAtlas.Core.SlashCommands:Register("diffblips", function(rest)
    local Logger = AzerothAtlas.Core.Logger:Get("Map")

    if rest == "start" then
        blipSnapshot = {}
        local n = 0
        for _, child in ipairs({ Minimap:GetChildren() }) do
            blipSnapshot[child] = true
            n = n + 1
        end
        Logger:info("diffblips: snapshot taken (%d children) - now walk to a node and run '/aatlas diffblips'", n)
        return
    end

    if not blipSnapshot then
        Logger:warn("diffblips: no snapshot yet - run '/aatlas diffblips start' first, away from any node")
        return
    end

    local current, added, removed = {}, {}, {}
    for _, child in ipairs({ Minimap:GetChildren() }) do
        current[child] = true
        if not blipSnapshot[child] then
            added[#added + 1] = child
        end
    end
    for child in pairs(blipSnapshot) do
        if not current[child] then
            removed[#removed + 1] = child
        end
    end

    Logger:info("diffblips: %d added, %d removed since snapshot", #added, #removed)
    for _, child in ipairs(added) do
        Logger:info("  + %s", DescribeMinimapChild(child))
    end
    for _, child in ipairs(removed) do
        Logger:info("  - %s", DescribeMinimapChild(child))
    end
end, "diff Minimap's child frames vs. a snapshot ('/aatlas diffblips start' first) - gathering-node active-detection research")

-- Build-order step 17, live-tested follow-up: after two rounds of
-- blind HideMinimapPassengers fixes (frames, then regions) the user
-- still reported a faint dark square - rather than guess a third time,
-- this dumps ground truth: every descendant of Minimap right now
-- (frames AND regions, same recursion HideMinimapPassengers itself
-- uses), each one's own description (reusing DescribeMinimapChild -
-- works on regions too, GetSize/GetCenter aren't frame-only), whether
-- it's currently shown, and whether this engine's own hide pass has
-- already caught it. Only useful while the live patch is actually
-- shown (self.MMOwn) - run it then.
AzerothAtlas.Core.SlashCommands:Register("mmpassengers", function()
    local Logger = AzerothAtlas.Core.Logger:Get("Map")
    local MinimapEngine = AzerothAtlas.Modules.Map.MinimapEngine
    if not MinimapEngine.MMOwn or not MinimapEngine.MMFrm then
        Logger:warn("mmpassengers: live patch isn't shown right now (MMOwn=%s) - turn on gathering tracking first",
            tostring(MinimapEngine.MMOwn))
        return
    end

    -- 2026-11-11, same-day follow-up: the first version logged every
    -- descendant unconditionally - 2045 of them on a live character
    -- with Questie installed, which blew straight past WoW's own chat
    -- scrollback before the user could find the one that mattered.
    -- Only shown:true entries get logged now - that's the entire
    -- point of the dump (find what's actually visibly riding along),
    -- so filtering to just those loses nothing and makes the output
    -- usable instead of a wall of noise.
    local hidden = MinimapEngine.MMHiddenChildren or {}
    local n, shownCount = 0, 0
    local function walk(frm, depth)
        for _, region in ipairs({ frm:GetRegions() }) do
            n = n + 1
            if region:IsShown() then
                shownCount = shownCount + 1
                Logger:info("  [region]%s shown:true hidden-by-us:%s  %s",
                    ("  "):rep(depth), tostring(hidden[region] == true),
                    DescribeMinimapChild(region))
            end
        end
        for _, child in ipairs({ frm:GetChildren() }) do
            n = n + 1
            if child:IsShown() then
                shownCount = shownCount + 1
                Logger:info("  [frame] %s shown:true hidden-by-us:%s  %s",
                    ("  "):rep(depth), tostring(hidden[child] == true),
                    DescribeMinimapChild(child))
            end
            walk(child, depth + 1)
        end
    end
    Logger:info("mmpassengers: walking Minimap's full descendant tree (shown-only)...")
    walk(MinimapEngine.MMFrm, 0)
    Logger:info("mmpassengers: %d shown out of %d total descendant(s)", shownCount, n)
end, "dump only the SHOWN frames/regions under the live Minimap patch, hidden-by-us state (build-order step 17 diagnostic)")

-- Build-order step 21 same-day sixth follow-up (2026-11-11): removed
-- outright, not just stopped calling - this function's entire purpose
-- was fetching/assigning the current zone's flat tile backdrop into
-- self.TileFrms (Nx.Map:UpdateWorld, MapEngine.lua:5945-6147, trimmed),
-- and nothing draws from TileFrms anymore now that "Art Map" means the
-- Overlay layer instead (see ART_MAP_LEVEL_OFFSET's own header comment
-- and MoveCurZoneTiles' above). Direct user request: "get rid of
-- whatever lives there now." self.CurWorldUpdateMapId/CurWorldUpdateArtID/
-- CurWorldTileCount/WorldArtRetryMapId/WorldArtRetryTime (this
-- function's own cache-state fields) are now unused too, left as
-- harmless unset table fields rather than hunted down individually -
-- none of them are read anywhere except inside this now-deleted
-- function and MoveZoneTiles' own `frms == self.TileFrms` special case
-- (dead in practice since nothing calls MoveZoneTiles with TileFrms
-- anymore - see MoveZoneTiles' own header for why that one branch was
-- left in place rather than surgically cut out of a verbatim port).

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
    -- 2026-11-16: dungeon floors registered by RegisterInstanceMap.
    local inst = self.MapZones and self.MapZones[self.DUNGEON_CONT]
    if inst then
        for _, zoneId in ipairs(inst) do
            if zoneId == mapId then return self.DUNGEON_CONT end
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
    -- 2026-11-17: the big map can browse Azeroth, a continent, a zone or a
    -- dungeon (BrowseTo). The viewed map is MapId/Cont/Zone as before;
    -- the player's own map is PlyrMapId/PlyrCont/PlyrZone.
    local browsing = self:IsBrowsing()
    local mapId
    if browsing then
        local raw = self:GetDisplayableMapForPlayer()
        if raw ~= self.PlyrMapId then
            self.PlyrMapId = raw
            self.PlyrCont = raw and raw ~= 0 and self:FindContinent(raw) or nil
            self.PlyrZone = self.PlyrCont and raw or nil
        end
        if self.BrowseInstance then
            mapId = self:ResolveDungeonMap(nil)
            if not mapId then
                -- Nothing to draw for that dungeon: back to the player.
                self.BrowseFailed = self.BrowseName
                self:StopBrowse()
                return
            end
        else
            mapId = self.BrowseMapId
        end
    else
        mapId = self:GetDisplayableMapForPlayer()
        -- 2026-11-16: inside a dungeon, the floor the player is on (which
        -- for a WoW Forever dungeon can be one of ResolveDungeonMap's made-
        -- up art floors - the client may report no map, or an outdoor one).
        mapId = self:ResolveDungeonMap(mapId) or mapId
    end
    if not mapId or mapId == 0 or mapId == self.MapId then
        if not browsing then
            self.PlyrMapId, self.PlyrCont, self.PlyrZone = self.MapId, self.Cont, self.Zone
        end
        return
    end

    local cont, zone, wide, allConts
    if browsing and mapId == self.AZEROTH_MAP then
        cont = (self.PlyrCont and self.PlyrCont >= 1 and self.PlyrCont <= 2) and self.PlyrCont or 2
        zone = self.MapZones[0][cont]
        wide, allConts = true, true
    elseif browsing and self:ContinentForRoot(mapId) then
        cont = self:ContinentForRoot(mapId)
        zone = mapId
        wide = true
    else
        cont = self:FindContinent(mapId) or self:RegisterInstanceMap(mapId)
        zone = cont and mapId or nil
    end
    self.MapId = mapId
    self.Cont = cont
    self.PlyrPosUnknown = nil
    self.Zone = zone
    self.WideView, self.ShowAllConts = wide, allConts
    if not browsing then
        self.PlyrMapId, self.PlyrCont, self.PlyrZone = mapId, cont, self.Zone
    end

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
        self.AreaArtMapId = nil     -- textures just cleared; reload on return
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
    if allConts then x, y, zw, zh = self:GetAzerothRect() end
    local ZoomController = AzerothAtlas.Modules.Map.ZoomController
    if ZoomController and x and browsing and self.MapW and self.MapH and zw > 0 then
        -- Browsing: fit what was picked into the window.
        ZoomController:Move(x + zw / 2, y + zh / 2, min(self.MapW / zw, self.MapH / zh) * .9, 15)
    elseif ZoomController and x then
        -- 2026-11-16: a dungeon floor opens zoomed to fit the window
        -- (it's far smaller than a zone, so the outdoor zoom would show
        -- it as a speck); the outdoor zoom comes back on leaving.
        local scale
        if cont == self.DUNGEON_CONT and self.MapW and self.MapH and zw > 0 then
            if not self.ScaleBeforeDungeon then self.ScaleBeforeDungeon = self.Scale end
            scale = min(self.MapW / zw, self.MapH / zh) * .9
        elseif self.ScaleBeforeDungeon then
            scale = self.ScaleBeforeDungeon
            self.ScaleBeforeDungeon = nil
        end
        ZoomController:Move(x + zw / 2, y + zh / 2, scale, 15)
    end
    -- Back from browsing ("My Map"): land on the player, not the zone's
    -- middle, even with Center off.
    if self.ReturnToPlayer and not browsing then
        self.ReturnToPlayer = nil
        if ZoomController and self.PlyrX and not self.PlyrPosUnknown then
            ZoomController:Move(self.PlyrX, self.PlyrY, nil, 15)
        end
    end
end

---------------------------------------------------------------------------------------
-- Browsing (2026-11-17, user request: big map buttons that "shift focus
-- to each continent or Azeroth or go into zone or go into dungeon or
-- city maps", and one to get back to our own map).
--   BrowseTo("azeroth")            every continent at once
--   BrowseTo("map", mapId)         a continent root (12 / 13) or a zone
--   BrowseTo("dungeon", instanceID) a dungeon's floors, from outside
--   StopBrowse()                   back to the player's own map
-- While browsing the map doesn't follow the player; the player marker
-- still draws wherever the player is.
---------------------------------------------------------------------------------------

MinimapEngine.AZEROTH_MAP = 947

function MinimapEngine:IsBrowsing()
    return (self.BrowseMapId or self.BrowseInstance) and true or false
end

-- Continent index for a continent root map (MapZones[0]: 12, 13), or nil.
function MinimapEngine:ContinentForRoot(mapId)
    local roots = self.MapZones and self.MapZones[0]
    for cont = 1, self.ContCnt or 0 do
        if roots and roots[cont] == mapId and self.MapInfo[cont] and self.MapInfo[cont].FileName then
            return cont
        end
    end
    return nil
end

-- World rectangle (x, y, w, h) holding every continent's drawn art.
function MinimapEngine:GetAzerothRect()
    local x1, y1, x2, y2
    for cont = 1, self.ContCnt or 0 do
        local info = self.MapInfo[cont]
        local _, x, y, w, h = self:GetWorldZoneInfo(cont, 0)
        if info and info.FileName and x then
            -- Only the middle columns of a continent image are drawn
            -- (ContBlks), so only they count.
            local mask = self.ContBlks and self.ContBlks[cont]
            local c1, c2 = 4, 1
            for col = 1, 4 do
                if not mask or mask[col] ~= 0 then
                    c1, c2 = min(c1, col), max(c2, col)
                end
            end
            local lx, rx = x + w * (c1 - 1) / 4, x + w * c2 / 4
            x1 = x1 and min(x1, lx) or lx
            x2 = x2 and max(x2, rx) or rx
            y1 = y1 and min(y1, y) or y
            y2 = y2 and max(y2, y + h) or (y + h)
        end
    end
    if not x1 then return nil end
    return x1, y1, x2 - x1, y2 - y1
end

function MinimapEngine:MapName(mapId)
    if mapId == self.AZEROTH_MAP then return "Azeroth" end
    local cont = self:ContinentForRoot(mapId)
    if cont then return self.MapInfo[cont].Name end
    local winfo = self.MapWorldInfo and self.MapWorldInfo[mapId]
    if winfo and winfo.Name then return winfo.Name end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    return info and info.name or ("Map " .. tostring(mapId))
end

function MinimapEngine:BrowseTo(kind, id, name)
    if kind == "azeroth" then
        self.BrowseMapId, self.BrowseInstance = self.AZEROTH_MAP, nil
    elseif kind == "dungeon" then
        self.BrowseMapId, self.BrowseInstance = nil, id
    else
        self.BrowseMapId, self.BrowseInstance = id, nil
    end
    self.BrowseName = name or (kind == "azeroth" and "Azeroth") or (id and self:MapName(id))
    self.BrowseFailed = nil
    if not self.BrowseSavedScale then self.BrowseSavedScale = self.Scale end
    self.MapId = nil            -- RefreshCurrentZone redraws on the next tick
    self.ViewFloor = nil
end

function MinimapEngine:StopBrowse()
    if not self:IsBrowsing() then return end
    self.BrowseMapId, self.BrowseInstance, self.BrowseName = nil, nil, nil
    self.WideView, self.ShowAllConts = nil, nil
    self.MapId = nil
    self.ViewFloor = nil
    local scale = self.BrowseSavedScale
    self.BrowseSavedScale = nil
    self.ReturnToPlayer = true
    local ZoomController = AzerothAtlas.Modules.Map.ZoomController
    if ZoomController and self.PlyrX then
        ZoomController:Move(self.PlyrX, self.PlyrY, scale, 15)
    end
end

-- Back to the player: stop browsing, and re-centre even when not
-- browsing (after a manual pan).
function MinimapEngine:ShowPlayer()
    if self:IsBrowsing() then
        self:StopBrowse()
        return
    end
    self:SetViewFloor(nil)
    local ZoomController = AzerothAtlas.Modules.Map.ZoomController
    if ZoomController and self.PlyrX and not self.PlyrPosUnknown then
        ZoomController:Move(self.PlyrX, self.PlyrY, nil, 10)
    end
end

-- Zones to list for a continent: { {id, name, city}, ... } sorted by name.
local CITY_MAPS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
MinimapEngine.CITY_MAPS = CITY_MAPS
function MinimapEngine:GetContinentZones(cont)
    local list = {}
    for _, id in ipairs(self.MapZones and self.MapZones[cont] or {}) do
        local winfo = self.MapWorldInfo[id]
        if winfo and winfo.X and winfo.Scale then
            list[#list + 1] = { id = id, name = self:MapName(id), city = CITY_MAPS[id] }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Dungeons and raids that have something to draw: { {id, name}, ... }.
function MinimapEngine:GetBrowseDungeons()
    local seen, list = {}, {}
    local Instances = AzerothAtlas.QuestData and AzerothAtlas.QuestData.Instances or {}
    local Catalog = AzerothAtlas.Modules.Quest and AzerothAtlas.Modules.Quest.Catalog
    local rooms = AzerothAtlas.DungeonRoomData or {}
    local fdjNames = _G.FDJ and _G.FDJ.INSTANCE_ID_TO_DUNGEON or {}
    local function nameOf(id)
        local key = Catalog and Catalog.InstanceKey and Catalog:InstanceKey(id)
        local packed = key and Instances[key]
        local n = packed and packed:match("^([^|]+)")
        if n then return n end
        if type(fdjNames[id]) == "string" then return fdjNames[id] end
        local first = rooms.ClientFloors and rooms.ClientFloors[id] and rooms.ClientFloors[id][1]
        local info = first and C_Map.GetMapInfo and C_Map.GetMapInfo(first)
        return info and info.name or nil
    end
    local function add(id)
        id = tonumber(id)
        if not id or seen[id] then return end
        seen[id] = true
        local n = nameOf(id)
        if n then list[#list + 1] = { id = id, name = n } end
    end
    for id in pairs(rooms.ClientFloors or {}) do add(id) end
    for id in pairs(rooms.TileFloors or {}) do add(id) end
    for id in pairs(fdjNames) do add(id) end
    for id in pairs(Instances) do if id > 2000 then add(id) end end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

---------------------------------------------------------------------------------------
-- Coordinates (2026-11-17, user request: player and cursor coordinates)
---------------------------------------------------------------------------------------

-- Zone percent (0-100) of a world point on mapId's map, or nil.
function MinimapEngine:WorldToZone(mapId, wx, wy)
    if not mapId or not wx then return nil end
    local cont = self:FindContinent(mapId)
    local info = cont and self.MapInfo[cont]
    local winfo = self.MapWorldInfo[mapId]
    if not info or not winfo or not winfo.X or not winfo.Scale or winfo.Scale == 0 then return nil end
    return (wx - info.X - winfo.X) / winfo.Scale, (wy - info.Y - winfo.Y) * 1.5 / winfo.Scale
end

-- The zone under a world point (the smallest one, so a city wins over
-- the zone around it) and its percent coordinates.
function MinimapEngine:ZoneAtWorld(wx, wy)
    local best, bx, by, bscale
    local conts = self.ShowAllConts and { 1, 2, 3 } or { self.Cont }
    for _, cont in ipairs(conts) do
        for _, id in ipairs(cont and self.MapZones[cont] or {}) do
            local zx, zy = self:WorldToZone(id, wx, wy)
            if zx and zx >= 0 and zx <= 100 and zy >= 0 and zy <= 100 then
                local sc = self.MapWorldInfo[id].Scale
                if not bscale or sc < bscale then best, bx, by, bscale = id, zx, zy, sc end
            end
        end
    end
    return best, bx, by
end

-- World position under the cursor, or nil when it's off the map.
function MinimapEngine:CursorWorldPos()
    local f = self.Frm
    if not f or not f:IsVisible() or not f:IsMouseOver() then return nil end
    local cx, cy = GetCursorPosition()
    local es = f:GetEffectiveScale()
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return nil end
    local fx, fy = cx / es - left, top - cy / es
    if fy < (self.TitleH or 0) then return nil end
    local wx = self.MapPosXDraw + (fx - self.MapW / 2) / self.ScaleDraw
    local wy = self.MapPosYDraw + (fy - (self.TitleH or 0) - self.MapH / 2) / self.ScaleDraw
    return wx, wy
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

    local ScrollScale = AzerothAtlas.Modules.Map.ScrollScale
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

-- 2026-11-18: where on the map the last click was (frame-local pixels),
-- for actions that work "here" (SetGotoAtClick). Factored out of
-- OnMouseUp's right-button branch below.
function MinimapEngine:CaptureClick()
    local frm = self.Frm
    if frm and self.MapW and self.MapH then
        local cx, cy = GetCursorPosition()
        local effScale = frm:GetEffectiveScale()
        cx, cy = cx / effScale, cy / effScale
        local left, top = frm:GetLeft(), frm:GetTop()
        if left and top then
            self.ClickFrmX, self.ClickFrmY = cx - left, top - cy
        end
    end
end

-- 2026-11-18 (user request): a click with a job you gave it in
-- Settings > Map (Map/MouseActions.lua) does that instead.
local function RunMouseAction(engine, button)
    local MouseActions = AzerothAtlas.Modules.Map.MouseActions
    return MouseActions and MouseActions:Run(engine, button)
end

function MinimapEngine:OnMouseDown(button)
    if button ~= "LeftButton" then return end
    if RunMouseAction(self, button) then
        self.MouseActionDown = true
        return
    end

    -- Deterministic close on top of MapContextMenu's own outside-
    -- click poll: a left-click on the map window itself starts a pan-
    -- drag below, which should always dismiss the menu first rather
    -- than drag underneath it.
    local MapContextMenu = AzerothAtlas.Modules.Map.MapContextMenu
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
        self.MouseActionDown = nil
    elseif button ~= "RightButton" then
        RunMouseAction(self, button)     -- middle, 4, 5: only what you set
    elseif RunMouseAction(self, button) then
        return
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

        -- Build-order step 10 (2026-11-11): capture the click's frame-
        -- local position now, before the menu opens, so "Set Goto
        -- Here" can use it later without resampling the cursor (which
        -- would read the menu's own position instead) - ported from
        -- Nx.Map:CalcClick (MapEngine.lua:5089-5098), called the same
        -- way (right on mouse-up, before dispatching the button
        -- action). Reuses MouseWheel's own already-working cursor-to-
        -- frame-local-pixels math just above in this file rather than
        -- re-deriving it.
        local frm = self.Frm
        if frm and self.MapW and self.MapH then
            local cx, cy = GetCursorPosition()
            local effScale = frm:GetEffectiveScale()
            cx, cy = cx / effScale, cy / effScale
            local left, top = frm:GetLeft(), frm:GetTop()
            if left and top then
                self.ClickFrmX, self.ClickFrmY = cx - left, top - cy
            end
        end

        local MapContextMenu = AzerothAtlas.Modules.Map.MapContextMenu
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
-- Build-order step 10 (2026-11-11): right-click goto waypoint + ant-
-- trail. User request: "carbonite has a feature where you can right
-- click set a goto at that spot then get ant trails from you to the
-- location... a little number above #yd that is the yards away...
-- updates as you move... use the flowing arrows like carbonite snag
-- their art if need be." Investigated Carbonite's real implementation
-- before writing any of this (MapEngine.lua) rather than guessing:
--
-- - Right-click dispatch: real Carbonite's default right-click action
--   IS a menu (Nx.db.profile.Map.ButR defaults to "Menu", MapEngine.lua
--   :614-624 / Defaults.lua:371), with "Goto"/"Clear Goto" as two of
--   that menu's items (Menu_OnGoto/Menu_OnClearGoto, :3968-3975) -
--   matches this addon's own MapContextMenu.lua exactly, confirmed
--   against real source rather than assumed. The click position is
--   sampled once, at mouse-down/up time (CalcClick, :5089-5098),
--   *before* the menu even opens - "Goto" just consumes the already-
--   captured position, it doesn't resample the cursor. See OnMouseUp's
--   RightButton branch above for this addon's equivalent capture.
-- - Reverse screen-to-world conversion: real Carbonite's own
--   FramePosToWorldPos (:15159-15167) is the algebraic inverse of
--   ClipFrameW's forward formula, using the LOGICAL (non-animated)
--   Scale/MapPosX/Y fields, not the ScaleDraw/MapPosXDraw/Y ones -
--   this addon's own MouseWheel function (above) already does the
--   exact same inversion for zoom-at-cursor, so FramePosToWorldPos
--   below just reuses that proven formula rather than deriving a new
--   one.
-- - Storage: a single in-memory point (self.GotoWX/WY/GotoCont), not
--   saved to AzerothAtlas.db - matches real Carbonite's own Nx.Map.
--   Targets, a plain runtime table (SetTarget/ClearTargets, :15183-
--   15394) never written to Nx.db either. Dropped real Carbonite's
--   multi-point Shift+click route queue (Pathing.lua) - out of scope,
--   the user asked for one goto, not a route planner.
-- - Ant trail: real Carbonite's own DrawTracking (:9007-9205) spaces
--   pooled arrow frames every 15 world-units (capped at 40) along a
--   STRAIGHT line from player to target, each stamped with Carbonite's
--   own art (IconArrowGrad.tga, confirmed to exist on disk at
--   Carbonite\Gfx\Map\IconArrowGrad.tga - "snag their art" per the
--   user's own request) and rotated to point along that line. The
--   "flowing" look is mostly just the player's own live position
--   advancing every tick (the trail's source end moves); a small
--   extra creep (self.ArrowScroll, 0->1 in .01 steps) keeps the ants
--   flowing even while standing still, but ONLY then (gated on
--   self.PlyrSpeed == 0, :9145 vs. this engine's own already-existing
--   PlyrSpeed field - see Update()'s own player-speed block) - ported
--   verbatim rather than left always-on, which would double up with
--   real movement and look too fast.
-- - Rotation: real Carbonite computes degrees (atan2+90) for its own
--   legacy UV-corner rotation system - NOT reusable here, since this
--   engine's ClipFrameW instead calls the texture's native
--   :SetRotation(radians) (see ClipFrameW's own header comment on why,
--   and its own "unverified, may need a sign flip" caveat for the
--   player marker). This section's own rotation formula is derived
--   fresh for that same :SetRotation convention (see UpdateGoto's own
--   comment at the atan2 call) under the same two assumptions the
--   player marker already relies on - texture points "up" unrotated,
--   SetRotation is counterclockwise-positive - rather than porting
--   Carbonite's degree formula, which answers a question (which way
--   does ITS OWN UV-rotation turn) this engine doesn't ask.
--   **UNCONFIRMED, same as the player marker**: if the arrows point
--   backwards/sideways rather than along the trail, that's this one
--   atan2 call to fix, not a rewrite.
-- - Yardage: dist * 4.575, the exact same constant and formula this
--   engine's own Update() already uses for PlyrSpeed (see that
--   block's own header comment) - confirmed against real Carbonite's
--   canonical formula (Coords.lua's own comment, DrawTracking :9013,
--   UpdateTargets :8854) and NOT Coords:YardsBetween's dead-code
--   variant, which re-multiplies by zone Scale a second time and
--   would double-apply it (confirmed zero callers anywhere in real
--   Carbonite - don't copy that one).
-- - Arrival: real Carbonite auto-clears + announces once within its
--   own default Radius (7 yards, UpdateTargets :8841-8897) - ported
--   the same way (UIErrorsFrame message + PlaySoundFile(567455), both
--   confirmed real calls in that same function) since a goto you can
--   never complete isn't really this feature, just a crippled piece
--   of it.
---------------------------------------------------------------------------------------

local GOTO_ICON_SIZE = 16
-- Build-order step 13, 2026-11-11: both GOTO_DOT_TEX and
-- TRAIL_ARROW_TEX used to be fixed locals pointing at Carbonite's own
-- LIVE install path (Interface\AddOns\Carbonite\Gfx\Map\...) - that
-- dependency was accepted at the time (same shape as the gathering-
-- icon textures), but the Style tab's "add them to our addon" request
-- was the natural moment to fix it: both are now Style-tab swappable
-- categories (UI/StyleOptions.lua) backed by this addon's own local
-- copies under Gfx/Map/, so neither needs Carbonite installed at all
-- any more, default-swapped or not. Resolved via GetTex() at each
-- SetTexture call site below (DrawAntTrail/UpdateGoto) rather than a
-- fixed constant, so a freshly-created pooled frame always gets
-- whatever's currently chosen; MinimapEngine:ApplyStyleChange (below)
-- handles the already-existing-frame case for a live change.
local TRAIL_ARROW_SIZE = 16
-- World-units per arrow and the arrow-count cap - real Carbonite's own
-- /15/self.IconNavScale and min(,40) (MapEngine.lua:9134/9138). This
-- addon has no IconNavScale slider, so that factor is just dropped
-- (equivalent to it always being 1), same as other absent sliders
-- elsewhere in this file.
local TRAIL_ARROW_SPACING = 15
local TRAIL_ARROW_MAX = 40
-- Real Carbonite's own default Target.Radius (MapEngine.lua:8866).
local GOTO_ARRIVAL_YARDS = 7
MinimapEngine.GOTO_ARRIVAL_YARDS = GOTO_ARRIVAL_YARDS     -- Quest/HUDArrow.lua
-- Same constant as Update()'s own PlyrSpeed block above - see this
-- section's header comment for why it's a fresh local here rather
-- than touching that already-working line. Shared by UpdateCorpseTrack
-- below too (its own #yd label) - named without the GOTO_ prefix for
-- the same reason TRAIL_ARROW_* above lost theirs.
local YARDS_PER_WORLDUNIT = 4.575

-- Shared by UpdateGoto and UpdateCorpseTrack below - the pooled-arrow
-- spacing/cap/rotation math is identical for both, matching real
-- Carbonite's own single DrawTracking primitive serving multiple
-- tracking types rather than each having its own copy (see
-- TRAIL_ARROW_TEX's own comment above for the citation). Takes a
-- caller-owned pool array (so Goto's and Corpse's trails never share
-- frames and can both be visible at once, same as upstream's
-- independent systems), the already-resolved dx/dy/dist from the
-- caller (both callers need those themselves anyway), and an optional
-- vertex-color tint - real Carbonite's own DrawTracking tints its
-- shared arrow texture per tracking type via SetVertexColor rather
-- than using separate art (:9183-9189: "B" faded-blue, "F" yellow for
-- taxi, "D" red for corpse recovery) - UpdateCorpseTrack below passes
-- red (1,0,0,1) for exactly that reason; UpdateGoto passes nothing,
-- same as real Carbonite's own untinted plain-route-target case.
-- self.ArrowScroll itself is advanced once per tick in Update(), NOT
-- in here - see that call site's own comment for why.
function MinimapEngine:DrawAntTrail(pool, dx, dy, dist, r, g, b, a)
    local cnt = dist / TRAIL_ARROW_SPACING
    if cnt < 5 then cnt = cnt + .5 end
    cnt = math.min(math.floor(cnt), TRAIL_ARROW_MAX)

    if cnt < 1 then
        for n = 1, #pool do
            pool[n]:Hide()
        end
        return
    end

    if #pool < cnt then
        for n = #pool + 1, cnt do
            local f = self:CreateMiniFrame()
            AzerothAtlas.UI.StyleOptions:ApplyIcon(f.texture, "TrailArrow")
            pool[n] = f
        end
    end

    -- Derived for this engine's own ClipFrameW/:SetRotation convention,
    -- not ported from Carbonite's degree formula - see UpdateGoto's own
    -- comment (where this was originally written) for the full
    -- reasoning and the "unconfirmed, may need a sign flip" caveat.
    -- Confirmed correct live, 2026-11-11 (goto trail direction tested
    -- in-game) - no longer unconfirmed.
    local dir = math.atan2(-dx, -dy)
    local stepX, stepY = dx / cnt, dy / cnt
    local scroll = self.ArrowScroll or 0
    local ox, oy = stepX * scroll, stepY * scroll
    local level = (self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET
    for n = 1, cnt do
        local f = pool[n]
        local wx, wy = self.PlyrX + ox, self.PlyrY + oy
        if self:ClipFrameW(f, wx, wy, TRAIL_ARROW_SIZE, TRAIL_ARROW_SIZE, dir) then
            f.texture:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
            f:SetFrameLevel(level)
        end
        ox, oy = ox + stepX, oy + stepY
    end
    for n = cnt + 1, #pool do
        pool[n]:Hide()
    end
end

function MinimapEngine:FramePosToWorldPos(fx, fy)
    local wx = self.MapPosX + (fx - self.MapW / 2) / self.Scale
    local wy = self.MapPosY + (fy - self.TitleH - self.MapH / 2) / self.Scale
    return wx, wy
end

-- Wired from MapContextMenu.lua's "Set Goto Here" row - consumes the
-- position OnMouseUp's RightButton branch already captured into
-- self.ClickFrmX/Y at right-click time (see that branch's own
-- comment), exactly matching real Carbonite's own deferred-use pattern
-- (SetTargetAtClick, MapEngine.lua:15379-15394) rather than resampling
-- the cursor now, which would read wherever the mouse is when the menu
-- item is clicked instead.
function MinimapEngine:SetGotoAtClick()
    if not self.ClickFrmX or not self.ClickFrmY then return end
    local wx, wy = self:FramePosToWorldPos(self.ClickFrmX, self.ClickFrmY)
    self.GotoWX, self.GotoWY = wx, wy
    self.GotoCont = self.Cont
    self.GotoName, self.GotoUid = nil, nil
    self.ArrowScroll = 0
end

-- Wired from MapContextMenu.lua's "Clear Goto" row, and called
-- automatically on arrival by UpdateGoto below.
function MinimapEngine:ClearGoto()
    local uid = self.GotoUid
    self.GotoWX, self.GotoWY, self.GotoCont = nil, nil, nil
    self.GotoName, self.GotoUid = nil, nil
    -- 2026-11-18: a waypoint (/way, TomTom - Map/Waypoints.lua) is done
    -- with, and the closest of the rest becomes the goto.
    local Waypoints = AzerothAtlas.Modules.Map.Waypoints
    if Waypoints then Waypoints:OnGotoCleared(uid) end
end

-- 2026-11-18: the waypoints that aren't the goto (Map/Waypoints.lua), as
-- dimmer goto markers.
function MinimapEngine:UpdateWaypointPins()
    local Waypoints = AzerothAtlas.Modules.Map.Waypoints
    local pool = self.WaypointPinFrms
    if not pool then
        pool = {}
        self.WaypointPinFrms = pool
    end
    local used = 0
    if Waypoints and self.Cont then
        local level = (self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET
        for _, uid in ipairs(Waypoints.List) do
            if uid ~= self.GotoUid and Waypoints:Resolve(uid) and uid.cont == self.Cont then
                used = used + 1
                local f = pool[used]
                if not f then
                    f = self:CreateMiniFrame()
                    AzerothAtlas.UI.StyleOptions:ApplyIcon(f.texture, "GotoMarker")
                    pool[used] = f
                end
                if self:ClipFrameW(f, uid.wx, uid.wy, GOTO_ICON_SIZE * .8, GOTO_ICON_SIZE * .8, 0) then
                    f.texture:SetVertexColor(1, 1, 1, .55)
                    f:SetFrameLevel(level)
                end
            end
        end
    end
    for n = used + 1, #pool do pool[n]:Hide() end
end

-- 2026-11-18: the next step of a travel route (Map/Travel.lua) for a
-- destination, or nil to head straight there.
local function TravelLeg(dest)
    local Travel = AzerothAtlas.Modules.Map.Travel
    return Travel and Travel:NextLeg(dest)
end

-- UpdateGoto with a travel leg: the goto dot (if it's on this map) and
-- the trail to the leg (if that is) - no arrival check, that is the
-- goto's own.
function MinimapEngine:UpdateGotoLeg(leg)
    if self.GotoFrm and self.Cont == self.GotoCont
            and self:ClipFrameW(self.GotoFrm, self.GotoWX, self.GotoWY, GOTO_ICON_SIZE, GOTO_ICON_SIZE, 0) then
        self.GotoFrm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET)
        if self.GotoYdLabel then self.GotoYdLabel:Hide() end
    else
        if self.GotoFrm then self.GotoFrm:Hide() end
        if self.GotoYdLabel then self.GotoYdLabel:Hide() end
    end
    if self.Cont ~= leg.cont then
        for i = 1, #self.GotoTrailFrms do self.GotoTrailFrms[i]:Hide() end
        return
    end
    local dx, dy = leg.x - self.PlyrX, leg.y - self.PlyrY
    self:DrawAntTrail(self.GotoTrailFrms, dx, dy, (dx * dx + dy * dy) ^ .5)
end

function MinimapEngine:HideGotoFrames()
    if self.GotoFrm then self.GotoFrm:Hide() end
    if self.GotoYdLabel then self.GotoYdLabel:Hide() end
    for i = 1, #self.GotoTrailFrms do
        self.GotoTrailFrms[i]:Hide()
    end
end

-- Called every tick from Update() (see that function's own call site)
-- - repositions the dot/label/trail for the current pan/zoom/player
-- position, same "every tick, cheap" treatment as UpdatePlayerMarker/
-- UpdateServiceIcons above. Gated on self.Cont == self.GotoCont so a
-- goto set before crossing a zone border (but staying on the SAME
-- continent - this engine's world-coordinate space is shared across
-- an entire continent, same as real Carbonite's) keeps working
-- correctly, but one left behind on a continent change (or an
-- instance, where Cont is nil) just hides rather than pointing
-- somewhere meaningless.
function MinimapEngine:UpdateGoto()
    self:UpdateWaypointPins()
    -- 2026-11-18: travel routing (Map/Travel.lua) - when a flight or a
    -- boat is quicker, the trail leads to where it starts; the goto dot
    -- stays where it is.
    if self.GotoWX then
        local dest = self.GotoDest or {}
        self.GotoDest = dest
        dest.x, dest.y, dest.cont, dest.kind = self.GotoWX, self.GotoWY, self.GotoCont, "goto"
        dest.name = self.GotoName or "Goto marker"
        local leg = TravelLeg(dest)
        if leg then
            self:UpdateGotoLeg(leg)
            return
        end
    end
    if not self.GotoWX or self.Cont ~= self.GotoCont then
        self:HideGotoFrames()
        return
    end

    local dx = self.GotoWX - self.PlyrX
    local dy = self.GotoWY - self.PlyrY
    local dist = (dx * dx + dy * dy) ^ .5
    local yards = dist * YARDS_PER_WORLDUNIT

    -- Arrived - see this section's header comment for why this auto-
    -- clears rather than leaving the dot/trail sitting on the player.
    if yards < GOTO_ARRIVAL_YARDS then
        self:ClearGoto()
        self:HideGotoFrames()
        UIErrorsFrame:AddMessage("Goto reached", 1, 1, 1, 1)
        PlaySoundFile(567455)
        return
    end

    -- Destination dot + yardage label. Lazily created here (not in
    -- TakeOwnership, unlike PlyrFrm - see TakeOwnership's own comment
    -- for why) - the label is a child of the dot frame so it rides
    -- along with ClipFrameW's own repositioning below for free.
    if not self.GotoFrm then
        self.GotoFrm = self:CreateMiniFrame()
        AzerothAtlas.UI.StyleOptions:ApplyIcon(self.GotoFrm.texture, "GotoMarker")
        local lbl = self.GotoFrm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("BOTTOM", self.GotoFrm, "TOP", 0, 2)
        self.GotoYdLabel = lbl
    end
    local dotShown = self:ClipFrameW(self.GotoFrm, self.GotoWX, self.GotoWY, GOTO_ICON_SIZE, GOTO_ICON_SIZE, 0)
    if dotShown then
        self.GotoFrm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET)
        self.GotoYdLabel:SetText(("%dyd"):format(math.ceil(yards)))
        self.GotoYdLabel:Show()
    else
        self.GotoYdLabel:Hide()
    end

    -- Ant trail - see DrawAntTrail's own header for the spacing/cap/
    -- scroll/tint formulas' real-source citations (untinted here,
    -- same as real Carbonite's own plain-route-target case).
    self:DrawAntTrail(self.GotoTrailFrms, dx, dy, dist)
end

---------------------------------------------------------------------------------------
-- Build-order step 10 follow-up (2026-11-11): corpse recovery - "when
-- the user is dead, the ant trails should also lead to the player's
-- body and put the grave icon on their body" (explicit user request).
-- Investigated real Carbonite's own corpse-tracking first
-- (MapEngine.lua:6645-6650, :7667-7712) rather than guessing:
-- - Detection: UnitIsDeadOrGhost("player"), gated the same way real
--   Carbonite gates it ("Only check corpse if player is actually
--   dead").
-- - Position: C_DeathInfo.GetCorpseMapPosition(mapId) - a live
--   Blizzard API returning a 0-1 normalized {x,y} on the given map,
--   confirmed by reading the real call site rather than guessed. Fed
--   into this engine's own GetWorldPos(mapId, pctX, pctY) (defined
--   above, already the direct equivalent of real Carbonite's own
--   Nx.Map:GetWorldPos - see that function's header) after the *100
--   scaling real Carbonite's own call site also does (GetWorldPos
--   expects 0-100, not 0-1).
-- - Battleground guard: real Carbonite also skips this inside a
--   battleground (its own IsBattleGroundMap check, MapEngine.lua
--   :6281) - that needs Carbonite's full zone-ID database, a much
--   bigger port this file has deliberately avoided elsewhere too (see
--   GetArtSourceMapID's own header). GetInstanceInfo()'s native
--   instanceType == "pvp" is the lightweight equivalent - no database
--   needed, same practical effect.
-- - Icon: Interface\Minimap\POIIcons, a standard BLIZZARD atlas sheet
--   (not a Carbonite art dependency, unlike the goto dot/arrows above).
--   **CORRECTED TWICE, 2026-11-11** - full history, in order:
--   1) Originally carried over real Carbonite's own corpse-icon
--      texcoord (MapEngine.lua:7706-7709) verbatim. User reported live
--      it rendered squished with the Arathi Basin Lumber Mill flag
--      icon bleeding in underneath.
--   2) Replaced with Cartographer3's own `CorpsePOI.lua` fix (WowAce
--      issue #218, 2008-10-24). User reported live this was ALSO
--      wrong - now a captured-objective flag plus an uncaptured
--      Lumber Mill icon, still two icons, still wrong.
--   3) Went to the source instead of a third addon-code guess: fetched
--      Blizzard's OWN current live-client FrameXML (the public mirror
--      at github.com/Gethe/wow-ui-source,
--      Blizzard_SharedMapDataProviders/DeathMapDataProvider.xml,
--      CorpsePinTemplate) - the literal file defining this literal
--      pin. Its `<TexCoords left="0.56640625" right="0.6328125"
--      top="0.001953125" bottom="0.03515625"/>` has the SAME left/
--      right as attempt #1 (Carbonite's own U-range was right all
--      along) but a top/bottom HALF AS TALL - "squished with another
--      icon bleeding in underneath" is exactly what carving a cell
--      twice the correct height would look like. Attempt #2's value
--      was a different, unrelated cell (shifted left) and never had
--      anything to do with the real fix - a wrong detour, not a step
--      toward this answer.
--   These values (CORPSE_TEX_U1/U2/V1/V2 below) are now sourced
--   directly from Blizzard's own shipped template rather than from
--   another addon's possibly-stale copy of it - the strongest source
--   available short of this server's own client files. Still not
--   independently re-confirmed live on THIS server as of this
--   writing, since its exact client build is still an unknown
--   variable - if it's wrong a fourth time, these two constants below
--   are the one spot to fix, not this function.
--   ClipFrameW's own SetTexCoord stomps this right after it's set (it
--   assumes a plain 0-1 square icon) - same "override clipping" quirk
--   real Carbonite's own corpse code has (its own "FIX maybe?" comment
--   at :7708) - set AFTER ClipFrameW below, ported with the same known
--   imperfection rather than solved better than the original.
-- - Trail: DrawAntTrail above, same shared primitive as Goto's own
--   trail, tinted RED (1,0,0,1) - real Carbonite's own DrawTracking
--   tints its shared arrow texture red specifically for its "D"
--   (death) tracking mode (:9189), so the corpse trail reads
--   differently from a plain goto trail at a glance, exactly like
--   upstream.
-- - No arrival-radius auto-clear (unlike Goto): real Carbonite's own
--   corpse-tracking has no such check either - it just keeps pointing
--   at the corpse every tick for as long as UnitIsDeadOrGhost is true
--   and GetCorpseMapPosition keeps returning a position; it stops on
--   its own once you resurrect (dot/trail just hide via the early
--   return below).
-- - #yd label (2026-11-11 follow-up, explicit user request): same
--   treatment as the goto dot's own GotoYdLabel above - NOT a port
--   (real Carbonite's corpse-tracking has no such label either, same
--   as the goto dot didn't originally), added for consistency between
--   the two trail types.
---------------------------------------------------------------------------------------

local CORPSE_ICON_SIZE = 16
local CORPSE_TEX = "Interface\\Minimap\\POIIcons"
-- Blizzard's own live-client CorpsePinTemplate (DeathMapDataProvider
-- .xml) - see this section's header comment above for the full,
-- two-wrong-attempts-before-this history.
local CORPSE_TEX_U1, CORPSE_TEX_U2 = 0.56640625, 0.6328125
local CORPSE_TEX_V1, CORPSE_TEX_V2 = 0.001953125, 0.03515625

function MinimapEngine:HideCorpseFrames()
    self.CorpseWX, self.CorpseWY, self.CorpseCont = nil, nil, nil
    if self.CorpseFrm then self.CorpseFrm:Hide() end
    if self.CorpseYdLabel then self.CorpseYdLabel:Hide() end
    for i = 1, #self.CorpseTrailFrms do
        self.CorpseTrailFrms[i]:Hide()
    end
end

-- Called every tick from Update(), alongside UpdateGoto - see this
-- section's header comment above for the full citation trail.
-- 2026-11-16 (user request: "when im dead in a dungeon it needs to
-- trace me back to the dungeon entrance"). Dying inside an instance
-- leaves the corpse where no outdoor map can show it, and the game
-- gives no corpse position once you release to the graveyard outside.
-- So the instance you died in is remembered (per character, so it
-- survives a relog as a ghost) and, while you're a ghost outside it,
-- the corpse marker and red trail lead to its entrance instead
-- (QuestData.Instances via Catalog:GetInstanceEntrance). Forgotten
-- once you're alive again.
local function deathStore()
    local Quest = AzerothAtlas.Modules.Quest
    local ok, t = pcall(function() return Quest.Core:Char("DeathInstance") end)
    return ok and t or nil
end

local function noteDeathInstance()
    if not IsInInstance() then return end
    local name, instanceType, _, _, _, _, _, id = GetInstanceInfo()
    id = tonumber(id)
    if not id or instanceType == "pvp" or instanceType == "arena" then return end
    local t = deathStore()
    if t then t.id, t.name = id, name end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_DEAD")
    f:RegisterEvent("PLAYER_ALIVE")
    f:RegisterEvent("PLAYER_UNGHOST")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_DEAD" then
            pcall(noteDeathInstance)
        elseif not UnitIsDeadOrGhost("player") then
            -- Alive again (resurrected or back in your body): forget it.
            local t = deathStore()
            if t then t.id, t.name = nil, nil end
        end
    end)
end

-- Entrance of the instance you died in, while you're a ghost outside
-- it: worldX, worldY, label - or nil.
function MinimapEngine:GetDeathEntrance()
    local t = deathStore()
    if not t or not t.id then return nil end
    if IsInInstance() then
        local id = tonumber((select(8, GetInstanceInfo())))
        if id == t.id then return nil end   -- back inside: the run is over
    end
    local Quest = AzerothAtlas.Modules.Quest
    local Catalog = Quest and Quest.Catalog
    if not Catalog or not Catalog.GetInstanceEntrance then return nil end
    local key = Catalog.InstanceKey and Catalog:InstanceKey(t.id) or t.id
    local name, owner, wx, wy = Catalog:GetInstanceEntrance(key)
    if not wx or self:FindContinent(owner) ~= self.Cont then return nil end
    return wx, wy, (name or t.name or "Dungeon") .. " entrance"
end

-- Fallback (2026-11-16, first live test: dead ~20yd from The Drowned
-- City's entrance, no trail - the death came before this code loaded,
-- so no instance was remembered, and the game had no corpse position).
-- A ghost outdoors whose corpse the game can't place has it inside an
-- instance: lead to the nearest entrance on this continent.
-- Entrances per continent are built once.
function MinimapEngine:GetNearestEntrance()
    if IsInInstance() or not self.PlyrX then return nil end
    local Quest = AzerothAtlas.Modules.Quest
    local Catalog = Quest and Quest.Catalog
    local all = AzerothAtlas.QuestData and AzerothAtlas.QuestData.Instances
    if not Catalog or not Catalog.GetInstanceEntrance or not all then return nil end
    self.EntranceCache = self.EntranceCache or {}
    local list = self.EntranceCache[self.Cont]
    if not list then
        list = {}
        for id in pairs(all) do
            local name, owner, wx, wy = Catalog:GetInstanceEntrance(id)
            if wx and self:FindContinent(owner) == self.Cont then
                list[#list + 1] = { wx = wx, wy = wy, name = name }
            end
        end
        self.EntranceCache[self.Cont] = list
    end
    local best, bestD
    for _, e in ipairs(list) do
        local dx, dy = e.wx - self.PlyrX, e.wy - self.PlyrY
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = e, d end
    end
    if not best then return nil end
    return best.wx, best.wy, (best.name or "Dungeon") .. " entrance"
end

function MinimapEngine:UpdateCorpseTrack()
    -- 2026-11-17: the navigation arrow (Quest/HUDArrow.lua) reads the
    -- corpse spot, so it only stands while there is one to show.
    self.CorpseWX, self.CorpseWY, self.CorpseCont, self.CorpseLabel = nil, nil, nil, nil
    if not UnitIsDeadOrGhost("player") then
        local t = deathStore()
        if t and t.id then t.id, t.name = nil, nil end
        self:HideCorpseFrames()
        return
    end

    local _, instanceType = GetInstanceInfo()
    if instanceType == "pvp" then
        self:HideCorpseFrames()
        return
    end
    -- Dead inside an instance without a PLAYER_DEAD seen (reload while
    -- dead): remember it now.
    if IsInInstance() then
        local t = deathStore()
        if t and not t.id then pcall(noteDeathInstance) end
    end

    local wx, wy, label = self:GetDeathEntrance()
    if not wx then
        local mapId = C_Map.GetBestMapForUnit("player")
        local info = mapId and C_DeathInfo.GetCorpseMapPosition(mapId)
        if info then
            wx, wy = self:GetWorldPos(mapId, info.x * 100, info.y * 100)
        end
        if not wx and UnitIsGhost and UnitIsGhost("player") then
            wx, wy, label = self:GetNearestEntrance()
        end
        if not wx then
            self:HideCorpseFrames()
            return
        end
    end

    if not self.CorpseFrm then
        self.CorpseFrm = self:CreateMiniFrame()
        self.CorpseFrm.texture:SetTexture(CORPSE_TEX)
        -- Same "#yd" treatment as the goto dot's own label (GotoYdLabel,
        -- UpdateGoto above) - not a port, real Carbonite's corpse-
        -- tracking has no such label either (same as the goto dot
        -- didn't), but kept consistent with it per explicit user
        -- request. A child of the dot frame so it rides along with
        -- ClipFrameW's own repositioning below for free.
        local lbl = self.CorpseFrm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("BOTTOM", self.CorpseFrm, "TOP", 0, 2)
        self.CorpseYdLabel = lbl
    end

    -- Remembered for auto-scale (AutoScaleTarget), cleared in
    -- HideCorpseFrames.
    -- The player's continent, not the one on show (the big map can be
    -- browsing another).
    self.CorpseWX, self.CorpseWY, self.CorpseCont = wx, wy, self.PlyrCont or self.Cont
    self.CorpseLabel = label

    local dx = wx - self.PlyrX
    local dy = wy - self.PlyrY
    local dist = (dx * dx + dy * dy) ^ .5

    local dotShown = self:ClipFrameW(self.CorpseFrm, wx, wy, CORPSE_ICON_SIZE, CORPSE_ICON_SIZE, 0)
    if dotShown then
        self.CorpseFrm.texture:SetTexCoord(CORPSE_TEX_U1, CORPSE_TEX_U2, CORPSE_TEX_V1, CORPSE_TEX_V2)
        self.CorpseFrm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET)
        local yd = ("%dyd"):format(math.ceil(dist * YARDS_PER_WORLDUNIT))
        self.CorpseYdLabel:SetText(label and (label .. "  " .. yd) or yd)
        self.CorpseYdLabel:Show()
    else
        self.CorpseYdLabel:Hide()
    end

    self:DrawAntTrail(self.CorpseTrailFrms, dx, dy, dist, 1, 0, 0, 1)
end

---------------------------------------------------------------------------------------
-- Quest companion (2026-11-15): the routed quest destination on the
-- map - a marker where the Quest module's arrow is leading, and an ant
-- trail to it. Real Carbonite draws its quest target through the same
-- DrawTracking primitive as a plain goto (MapEngine.lua:9007); this is
-- that, as a third independent consumer of DrawAntTrail beside Goto and
-- Corpse - its own pool, so all three can show at once.
--
-- The destination itself comes from Quest/QuestRouting.lua
-- (Routing.Target, already in this engine's world space). Tinted gold
-- so it reads apart from a manual goto's untinted trail and the corpse
-- trail's red. Nothing is drawn while the player is standing inside the
-- objective's own area (Target.inside) - there is no "there" to lead
-- to - or when the destination is on another continent, where this
-- engine's shared world space doesn't reach.
---------------------------------------------------------------------------------------

local QUEST_ROUTE_ICON_SIZE = 18
local QUEST_ROUTE_R, QUEST_ROUTE_G, QUEST_ROUTE_B = 1, 0.82, 0.2

function MinimapEngine:HideQuestRouteFrames()
    if self.QuestRouteFrm then self.QuestRouteFrm:Hide() end
    if self.QuestRouteYdLabel then self.QuestRouteYdLabel:Hide() end
    for i = 1, #self.QuestTrailFrms do
        self.QuestTrailFrms[i]:Hide()
    end
end

-- Called every tick from Update(), alongside UpdateGoto/UpdateCorpseTrack.
function MinimapEngine:UpdateQuestRoute()
    local Quest = AzerothAtlas.Modules.Quest
    local t = Quest and Quest.Routing and Quest.Routing.Target
    -- 2026-11-18: travel routing - the trail leads to the flight master
    -- or boat first (Map/Travel.lua).
    t = (t and TravelLeg(t)) or t
    if not t or not self.Cont or t.cont ~= self.Cont or t.inside
        or (Quest.Core and Quest.Core:Opt("RouteTrail") == false) then
        self:HideQuestRouteFrames()
        return
    end

    local dx = t.x - self.PlyrX
    local dy = t.y - self.PlyrY
    local dist = (dx * dx + dy * dy) ^ .5

    if not self.QuestRouteFrm then
        self.QuestRouteFrm = self:CreateMiniFrame()
        AzerothAtlas.UI.StyleOptions:ApplyIcon(self.QuestRouteFrm.texture, "GotoMarker")
        local lbl = self.QuestRouteFrm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("BOTTOM", self.QuestRouteFrm, "TOP", 0, 2)
        self.QuestRouteYdLabel = lbl
    end

    if self:ClipFrameW(self.QuestRouteFrm, t.x, t.y, QUEST_ROUTE_ICON_SIZE, QUEST_ROUTE_ICON_SIZE, 0) then
        self.QuestRouteFrm.texture:SetVertexColor(QUEST_ROUTE_R, QUEST_ROUTE_G, QUEST_ROUTE_B, 1)
        self.QuestRouteFrm:SetFrameLevel((self.Frm:GetFrameLevel() or 1) + SERVICE_LEVEL_OFFSET)
        self.QuestRouteYdLabel:SetText(("%dyd"):format(math.ceil(dist * YARDS_PER_WORLDUNIT)))
        self.QuestRouteYdLabel:Show()
    else
        self.QuestRouteYdLabel:Hide()
    end

    self:DrawAntTrail(self.QuestTrailFrms, dx, dy, dist, QUEST_ROUTE_R, QUEST_ROUTE_G, QUEST_ROUTE_B, 1)
end

---------------------------------------------------------------------------------------
-- Diagnostic overlay, originally built for the build-order step 4
-- live-widget-blend bug (mask renders, terrain stays blank). Kept as
-- a permanent debug aid rather than torn out - shown/hidden by the
-- Settings window's "Debug mode" checkbox (Core/Logger.lua's
-- Logger.minLevel), not always-on.
---------------------------------------------------------------------------------------

local debugFrm, debugText

-- Where the user last dragged this to, saved across /reload. Lives on
-- the root AceDB profile table (AzerothAtlas.db.profile) rather than a
-- module's own DB, since this overlay isn't a registered Module - see
-- Core/SavedVariables.lua's bind() for what that table is. Always
-- available by the time this overlay is first created (lazily, on the
-- first debug-overlay update after the map window has been opened at
-- least once), well after the PLAYER_LOGIN that creates it.
local function saveDebugOverlayPosition()
    if not (AzerothAtlas.db and AzerothAtlas.db.profile) then return end
    local point, _, relPoint, x, y = debugFrm:GetPoint()
    if not point then return end
    AzerothAtlas.db.profile.DebugOverlay = { point = point, relPoint = relPoint, x = x, y = y }
end

local function ensureDebugOverlay()
    if debugFrm then return end
    debugFrm = CreateFrame("Frame", "AzerothAtlasMapDebug", UIParent, "BackdropTemplate")
    -- Widened/tallened (build-order step 9m, 2026-11-10) to fit the
    -- grouped/headered layout below without word-wrap collapsing it
    -- back into a jumble - see UpdateDebugOverlay's own header comment.
    debugFrm:SetSize(460, 320)

    local saved = AzerothAtlas.db and AzerothAtlas.db.profile and AzerothAtlas.db.profile.DebugOverlay
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

-- Formats a possibly-nil/non-number field safely - several of these
-- (Cont/Zone especially) are nil by DESIGN for instances (see Phase8's
-- own test doc), not a bug, so this must print "nil" cleanly rather
-- than erroring %.2f on a nil argument.
local function fmtNum(v, fmt)
    if type(v) ~= "number" then return tostring(v) end
    return (fmt or "%.2f"):format(v)
end

local DEBUG_HEADER_COLOR = "|cffffd100%s|r"

-- Build-order step 9m (2026-11-10): regrouped from one flat dump into
-- labeled sections, one per `Docs/Testing/Phase5-8*.md` doc (Pan/Zoom
-- covers Phase 5+6+7, since all three tests read the same underlying
-- animation state - see those docs' own "Setup" sections for exactly
-- which fields each test watches). Explicit user request, after the
-- flat version was reported "jumbled" - every value already existed,
-- this is a formatting/grouping pass, not new instrumentation (the one
-- exception: `Animating`, a derived field added because Phase5 Test 3
-- and Phase6 Test 2 both boil down to "is Scale still catching up to
-- ScaleDraw" and forcing the tester to compare two raw floats by eye
-- was exactly the kind of jumble this pass is fixing).
function MinimapEngine:UpdateDebugOverlay()
    -- Tied to the same Debug mode flag the Settings window's checkbox
    -- and the `/aatlas debug` slash command both already drive
    -- (Core/Logger.lua's Logger.minLevel) - whichever one last
    -- toggled it, this just reads the same place, so there's nothing
    -- extra to keep in sync. Off hides (and stops updating) the
    -- overlay entirely instead of just dimming it, matching "off
    -- turns them both off."
    local Logger = AzerothAtlas.Core.Logger
    if Logger.minLevel ~= Logger.LEVEL.DEBUG then
        if debugFrm then debugFrm:Hide() end
        return
    end

    ensureDebugOverlay()
    debugFrm:Show()

    local animating = math.abs((self.ScaleDraw or 0) - (self.Scale or 0)) > 0.001
        or (self.MapPosXDraw or 0) ~= (self.MapPosX or 0)
        or (self.MapPosYDraw or 0) ~= (self.MapPosY or 0)

    local lines = {}

    tinsert(lines, DEBUG_HEADER_COLOR:format("Pan / Zoom  (Phase 5, 6, 7)"))
    tinsert(lines, ("Scale: %s   ScaleDraw: %s   Animating: %s"):format(
        fmtNum(self.Scale), fmtNum(self.ScaleDraw), tostring(animating)))
    tinsert(lines, ("StepTime: %s"):format(fmtNum(self.StepTime, "%.3f")))
    tinsert(lines, ("MapPosX: %s   MapPosY: %s"):format(fmtNum(self.MapPosX, "%.1f"), fmtNum(self.MapPosY, "%.1f")))
    tinsert(lines, ("MapPosXDraw: %s   MapPosYDraw: %s"):format(
        fmtNum(self.MapPosXDraw, "%.1f"), fmtNum(self.MapPosYDraw, "%.1f")))
    tinsert(lines, ("Scrolling: %s   Ttl: %s"):format(tostring(self.Scrolling), fmtNum(self.Ttl, "%.2f")))

    tinsert(lines, "")
    tinsert(lines, DEBUG_HEADER_COLOR:format("Window Size  (Phase 7)"))
    tinsert(lines, ("MapW: %s   MapH: %s"):format(tostring(self.MapW), tostring(self.MapH)))

    tinsert(lines, "")
    tinsert(lines, DEBUG_HEADER_COLOR:format("World / Position  (Phase 8)"))
    tinsert(lines, ("MapId: %s   Cont: %s   Zone: %s"):format(
        tostring(self.MapId), tostring(self.Cont), tostring(self.Zone)))
    tinsert(lines, ("CurWorldUpdateMapId: %s   Tiles: %s"):format(
        tostring(self.CurWorldUpdateMapId), tostring(self.CurWorldTileCount)))
    tinsert(lines, ("PlyrX: %s   PlyrY: %s   PlyrDir: %s"):format(
        fmtNum(self.PlyrX, "%.1f"), fmtNum(self.PlyrY, "%.1f"), fmtNum(self.PlyrDir, "%.2f")))

    tinsert(lines, "")
    tinsert(lines, DEBUG_HEADER_COLOR:format("Goto  (Build-order step 10)"))
    if self.GotoWX then
        local dx = self.GotoWX - (self.PlyrX or 0)
        local dy = self.GotoWY - (self.PlyrY or 0)
        local yd = ((dx * dx + dy * dy) ^ .5) * 4.575
        tinsert(lines, ("GotoWX: %s   GotoWY: %s   Dist: %dyd"):format(
            fmtNum(self.GotoWX, "%.1f"), fmtNum(self.GotoWY, "%.1f"), math.ceil(yd)))
    else
        tinsert(lines, "GotoWX: nil   (no goto set)")
    end

    tinsert(lines, "")
    tinsert(lines, DEBUG_HEADER_COLOR:format("Corpse Track  (Build-order step 10 follow-up)"))
    local dead = UnitIsDeadOrGhost("player")
    if not dead then
        tinsert(lines, "UnitIsDeadOrGhost: false   (alive)")
    elseif self.CorpseFrm and self.CorpseFrm:IsShown() then
        tinsert(lines, "UnitIsDeadOrGhost: true   Corpse: tracked")
    else
        tinsert(lines, "UnitIsDeadOrGhost: true   Corpse: not tracked (pvp map, or no corpse info yet)")
    end

    tinsert(lines, "")
    tinsert(lines, DEBUG_HEADER_COLOR:format("Live Blips  (Build-order step 17)"))
    if self.MMOwn then
        local mm = self.MMFrm
        tinsert(lines, ("MMOwn: true   Zoom: %s/%s"):format(
            tostring(mm and mm:GetZoom()), tostring(mm and mm.GetZoomLevels and mm:GetZoomLevels())))
        tinsert(lines, ("LiveFit (worldunits): %s   MMScale: %s"):format(
            fmtNum(self.MMLiveFit, "%.2f"), fmtNum(self.MMScale, "%.3f")))
        tinsert(lines, ("MM px size: %s   ZoomType: %s"):format(
            tostring(mm and mm:GetWidth()), tostring(self.MMZoomType)))
    else
        tinsert(lines, ("MMOwn: false   (tracking %s)"):format(
            tostring(self.Frm and IsGatherTrackingActive())))
    end

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

    -- Build-order step 17: retry a deferred ShowLiveBlips (see its own
    -- header - every call it makes touches protected frame state, so
    -- it bails out and sets this flag instead of erroring mid-combat).
    if self.MMApplyPending and not InCombatLockdown() then
        self:ShowLiveBlips()
    end

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
    -- This call is a cheap no-op once the zone hasn't changed - see
    -- RefreshCurrentZone's own comments. (UpdateWorldArt used to be
    -- called here too, feeding the now-removed flat zone-tile backdrop
    -- - see its own removal comment, build-order step 21 same-day
    -- sixth follow-up.)
    self:RefreshCurrentZone()
    -- 2026-11-17 (big map browsing): the player's position always comes
    -- from the player's own map (PlyrMapId/PlyrCont/PlyrZone), which is
    -- the viewed map too unless the map is browsing somewhere else.
    if self.PlyrCont then
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
        local _, zx, zy, zw, zh = self:GetWorldZoneInfo(self.PlyrCont, self.PlyrZone)
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
        if self.PlyrCont and zx then
            -- 2026-11-16: a Forever art floor reads the client map it
            -- matches, if any (GetPositionMap); pcall since a dungeon
            -- map can refuse the call.
            local posMap = self:GetPositionMap(self.PlyrMapId)
            local pos
            if posMap and C_Map and C_Map.GetPlayerMapPosition then
                local ok, p = pcall(C_Map.GetPlayerMapPosition, posMap, "player")
                if ok then pos = p end
            end
            local px, py
            if pos then px, py = pos:GetXY() end
            if px and py and (px ~= 0 or py ~= 0) then
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

                -- (Window title and speed readout: UpdateTitle, called
                -- every tick from Update below - 2026-11-16.)

                local ZoomController = AzerothAtlas.Modules.Map.ZoomController
                local followWin = AzerothAtlas.Modules.Map.MinimapWindow
                local autoFollow = not (followWin and followWin:DB().profile.AutoFollow == false)
                -- 2026-11-16: two independent header switches. "Follow"
                -- (saved as AutoScale) is Carbonite's auto-scale - while
                -- there's somewhere to go it owns the view. Otherwise
                -- "Center" (saved as AutoFollow) keeps the player in the
                -- middle of the map.
                if ZoomController and not self.Scrolling and self:IsViewingPlayerFloor()
                        and not self:IsBrowsing() then
                    if not self:AutoScaleTarget() and autoFollow then
                        ZoomController:Move(self.PlyrX, self.PlyrY, nil, 30)
                    end
                end
                self.PlyrPosUnknown = nil
            elseif self.PlyrCont == self.DUNGEON_CONT then
                -- This dungeon's map doesn't report where the player is
                -- (some instances don't) - show the map, hide the marker.
                self.PlyrPosUnknown = true
            end
        end
    end
    self:UpdateTitle()
    -- Build-order step 8b, corrected 2026-11-10 after live testing
    -- showed only ever one detail tile at a time, frozen on pan: a
    -- re-read of real Carbonite's UpdateZones (MapEngine.lua:9831-9900)
    -- shows UpdateMiniFrames() is called EVERY tick, UNCONDITIONALLY,
    -- in every branch (city, ordinary zone, zoomed in or out) - the
    -- detail-tile layer is always live, following pan/zoom
    -- continuously from the very first tick. ScaleDraw <= DETAIL_SCALE
    -- only ever decides whether the COARSE zone-overview art is ALSO
    -- drawn (zoomed out: self:MoveCurZoneTiles()) or cleared (zoomed
    -- in: real source's "MoveCurZoneTiles(true)" - this engine's own
    -- equivalent is HideZoneTileFrames). The previous version of this
    -- block treated the two layers as a mutually-exclusive switch and
    -- only ever turned detail tiles on once already zoomed in far
    -- enough that a single ~107-world-unit tile exceeds the whole
    -- window - exactly the "one frozen square" symptom reported live.
    -- (Which one draws on top where both show is now an explicit
    -- frame-level offset, not an artifact of draw order here - see
    -- ART_MAP_LEVEL_OFFSET/TERRAIN_TILE_LEVEL_OFFSET above
    -- MoveZoneTiles.)
    --
    -- Build-order step 18 (2026-11-11, map-layering fix): debug flags
    -- let a live tester isolate a layer via /aatlas hideart /
    -- /aatlas hideterrain / /aatlas hidebase (Core/SlashCommands.lua
    -- registrations further down this file) - short-circuit straight
    -- to the same hide calls the zoom gate already uses, so an
    -- isolated layer looks exactly like "zoomed past the point this
    -- layer would show" rather than a new code path.
    --
    -- Build-order step 20 follow-up (2026-11-11, "Base" layer split):
    -- DebugHideArt and DebugHideBase used to share one top-level
    -- branch here, which meant hiding Art Map always hid the continent
    -- backdrop too - not actually independent toggles. MoveCurZoneTiles
    -- now handles only the Base/continent decision internally (gated on
    -- DebugHideBase), so it always runs whenever continent art could
    -- show at the current zoom; Art Map itself - now defined as the
    -- Overlay layer, see ART_MAP_LEVEL_OFFSET's own header comment for
    -- the full "Art Map redefined" story - is gated directly here on
    -- DebugHideArt instead, independent of Base's own decision.
    if self.ScaleDraw <= DETAIL_SCALE then
        self:MoveCurZoneTiles()
        if self.DebugHideArt then
            self:HideAllOverlayFrames()
        else
            self:UpdateZoneOverlays()
        end
    else
        self:HideContinentFrames()
        self:HideAllOverlayFrames()
    end
    if self.DebugHideTerrain then
        self:HideMiniFrames()
    else
        self:UpdateMiniFrames()
    end

    -- 2026-11-16: City / Dungeon map layer, above Terrain - see
    -- UpdateAreaMap. Not zoom-gated: inside a city or dungeon its art
    -- is the main map at every zoom.
    self:UpdateAreaMap()
    -- 2026-11-18: subzone names (UpdateAreaLabels).
    self:UpdateAreaLabels()

    -- Build-order step 9a: independent of both tile layers - see
    -- UpdatePlayerMarker's own header.
    self:UpdatePlayerMarker()
    -- 2026-11-18: where you've walked (UpdateTrail).
    self:UpdateTrail()

    -- Build-order step 10: independent of the tile/icon layers above -
    -- see UpdateGoto's own header for why this runs every tick.
    --
    -- ArrowScroll is advanced exactly ONCE here, shared by whichever
    -- of UpdateGoto/UpdateCorpseTrack draw a trail this tick (both
    -- read it via DrawAntTrail, neither mutates it) - advancing it
    -- from two call sites in the same tick would double its speed
    -- whenever both a goto AND a corpse trail are showing at once.
    -- Matches real Carbonite's own structure, a single shared advance
    -- before any of its own several tracking consumers draw
    -- (MapEngine.lua:7661-7664).
    if not self.PlyrSpeed or self.PlyrSpeed == 0 then
        local scroll = (self.ArrowScroll or 0) + .01
        self.ArrowScroll = scroll > 1 and 0 or scroll
    end
    self:UpdateGoto()
    self:UpdateCorpseTrack()
    -- Quest companion: marker + trail to the routed quest destination.
    self:UpdateQuestRoute()

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

    -- Shaded quest areas and patrol lines, under the pins. What to draw
    -- and how is Quest/QuestOverlay.lua's business; it reads this
    -- engine's pan/zoom and skips the work when neither has changed.
    local QuestOverlay = AzerothAtlas.Modules.Quest and AzerothAtlas.Modules.Quest.Overlay
    if QuestOverlay and QuestOverlay.Draw then
        local ok, err = pcall(QuestOverlay.Draw, QuestOverlay, self)
        if not ok and self.QuestOverlayError ~= err then
            self.QuestOverlayError = err
            AzerothAtlas.Core.Logger:Get("Map"):error("quest overlay failed: %s", tostring(err))
        end
    end

    -- Build-order step 9e: gathering-node field. Repositioned on its
    -- own 0.1s throttle, not every tick - see UpdateGatherIcons'
    -- header for why (hundreds of stationary points, 20Hz precision
    -- is wasted on something that never moves).
    if not self.GatherUpdateAt or now >= self.GatherUpdateAt then
        self.GatherUpdateAt = now + 0.1
        self:UpdateGatherIcons()
    end

    -- Build-order step 17: gathering-tracking gate for the live-widget
    -- blip patch (see ShowLiveBlips' own header for why) - cheap 1s
    -- poll, same reasoning as the quest/gather throttles above. Only
    -- takes over the real widget if this window has actually been
    -- opened at least once this session (self.Frm is set once by
    -- TakeOwnership and persists across close/reopen) - no point
    -- owning it with nothing yet to position it against.
    if not self.GatherTrackingCheckAt or now >= self.GatherTrackingCheckAt then
        self.GatherTrackingCheckAt = now + 1
        local active = self.Frm and IsGatherTrackingActive()
        if active and not self.MMOwn then
            self:ShowLiveBlips()
        elseif not active and self.MMOwn then
            self:HideLiveBlips()
        end
    end
    if self.MMOwn then
        self:UpdateLiveBlips()
    end

    -- 2026-11-16: bosses, level exits, entrance and quest targets on a
    -- Forever dungeon's map (DungeonPins.lua).
    if self.UpdateDungeonPins then
        local ok, err = pcall(self.UpdateDungeonPins, self)
        if not ok and self.DungeonPinError ~= err then
            self.DungeonPinError = err
            AzerothAtlas.Core.Logger:Get("Map"):error("dungeon pins failed: %s", tostring(err))
        end
    end

    -- 2026-11-18: other addons' world map pins (AddonPins.lua).
    if self.UpdateAddonPins then
        local ok, err = pcall(self.UpdateAddonPins, self)
        if not ok and self.AddonPinError ~= err then
            self.AddonPinError = err
            AzerothAtlas.Core.Logger:Get("Map"):error("addon pins failed: %s", tostring(err))
        end
    end

    -- 2026-11-16: party / raid / guild / enemy players (PlayerBlips.lua).
    if self.UpdatePlayerBlips then
        local ok, err = pcall(self.UpdatePlayerBlips, self)
        if not ok and self.PlayerBlipError ~= err then
            self.PlayerBlipError = err
            AzerothAtlas.Core.Logger:Get("Map"):error("player blips failed: %s", tostring(err))
        end
    end

    -- 2026-11-16: keep the map above other addons (see MinimapWindow's
    -- SyncStrata) - re-asserted every tick, it's only string compares.
    local MinimapWindow = AzerothAtlas.Modules.Map.MinimapWindow
    if MinimapWindow and MinimapWindow.SyncStrata then MinimapWindow:SyncStrata() end
    if MinimapWindow and MinimapWindow.UpdateLevelBar then MinimapWindow:UpdateLevelBar() end
    local BigMap = AzerothAtlas.Modules.Map.BigMap
    if BigMap and BigMap.Win then
        local ok, err = pcall(BigMap.Update, BigMap)
        if not ok and self.BigMapError ~= err then
            self.BigMapError = err
            AzerothAtlas.Core.Logger:Get("Map"):error("big map failed: %s", tostring(err))
        end
    end

    self:UpdateDebugOverlay()
end

---------------------------------------------------------------------------------------
-- /aatlas where - what the client reports about where the player is.
-- Inside a dungeon this is what decides whether a position marker can
-- be drawn at all, and it differs per dungeon (WoW Forever's own ones
-- especially), so it is printed rather than guessed.
---------------------------------------------------------------------------------------

AzerothAtlas.Core.SlashCommands:Register("where", function()
    local function say(...) DEFAULT_CHAT_FRAME:AddMessage(string.format(...)) end
    local function pos(map, unit)
        if not map then return "no map" end
        local ok, p = pcall(C_Map.GetPlayerMapPosition, map, unit or "player")
        if not ok then return "error" end
        if not p then return "nil" end
        local x, y = p:GetXY()
        return ("%.1f, %.1f"):format((x or 0) * 100, (y or 0) * 100)
    end
    local E = MinimapEngine
    local inInstance, instType = IsInInstance()
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    say("|cffffd100Azeroth Atlas - where am I|r")
    say("  instance: %s (%s) id %s, type %s", tostring(inInstance), tostring(name),
        tostring(instanceID), tostring(instType))
    local best = C_Map.GetBestMapForUnit("player")
    local info = best and C_Map.GetMapInfo(best)
    say("  best map: %s %s - position %s", tostring(best), tostring(info and info.name), pos(best))
    say("  displayable map: %s", tostring(E:GetDisplayableMapForPlayer()))
    local okU, ux, uy, _, uc = pcall(UnitPosition, "player")
    say("  UnitPosition: %s", okU and ux and ("%.1f, %.1f (instance %s)"):format(ux, uy, tostring(uc)) or "nil")
    say("  Leatrix Maps art: %s", leatrixInstalled() and "found" or "not found")
    local f1 = E.DungeonFloors and E.DungeonFloors[1]
    if E.DescribeRoom then say("  room: %s", E:DescribeRoom()) end
    do
        local Quest = AzerothAtlas.Modules.Quest
        local ok, t = pcall(function() return Quest.Core:Char("DeathInstance") end)
        local bm = C_Map.GetBestMapForUnit("player")
        local cp = bm and C_DeathInfo.GetCorpseMapPosition(bm)
        local ex, _, elabel = E:GetDeathEntrance()
        local nx, _, nlabel = E:GetNearestEntrance()
        say("  death: dead %s, ghost %s, died in %s, corpse from game %s, died-in entrance %s, nearest entrance %s",
            tostring(UnitIsDeadOrGhost("player")), tostring(UnitIsGhost and UnitIsGhost("player")),
            ok and t and t.id and (tostring(t.name) .. " " .. t.id) or "none",
            cp and ("%.1f, %.1f"):format(cp.x * 100, cp.y * 100) or "none",
            ex and elabel or "none", nx and nlabel or "none")
    end
    say("  dungeon floors: %s", not f1 and "none"
        or (f1.spec and f1.spec.fdjName and "Forever Dungeon Journal art")
        or (f1.spec and "Leatrix art") or (f1.blank and "blank (no art)") or "client maps")
    say("  map: zone %s, continent %s, floor %s of %s (showing %s)%s",
        tostring(E.MapId), tostring(E.Cont), tostring(E.PlayerFloor),
        tostring(E.DungeonFloors and #E.DungeonFloors), tostring(E:GetViewFloorIndex()),
        E.PlyrPosUnknown and " - position unknown" or "")
    if C_Map.GetMapArtLayerTextures and best then
        local ok, t = pcall(C_Map.GetMapArtLayerTextures, best, 1)
        say("  client map art for %s: %s", tostring(best), (ok and t and #t > 0) and (#t .. " tiles") or "none")
    end
end, "print what the game reports about your position (for dungeon maps)")
