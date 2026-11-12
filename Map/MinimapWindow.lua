-- Alchemy GPS | Map / MinimapWindow
-- Orchestration for the minimap module: owns the module's saved
-- settings, applies them on login, and exposes them via slash
-- commands. Open() (the real ported undocked map window) and the
-- Ctrl+Shift+M keybind are added here in later build-order phases
-- once the window itself exists - this phase only wires the
-- native-hide toggle end to end, with a temporary slash command
-- standing in for the Settings window checkbox until that exists.
--
-- Adapted from AlchemyNavigation/Modules/Map/Map.lua's OnEnable /
-- slash-command wiring pattern (rename only; Pin/Undock-anchor
-- defaults and the regions/scan debug subcommands aren't ported -
-- out of scope for this addon).

local AlchemyGPS = _G.AlchemyGPS
local Module = AlchemyGPS.Core.Module

-- NOTE: Core/SavedVariables.lua's bind() pokes dbDefaults.profile's
-- own keys directly onto the ROOT db.profile table (keyed by
-- whatever name each key happens to have), then separately builds
-- this module's own self:DB().profile as db.profile.MinimapWindow.
-- So the actual per-module fields must be nested one level deeper,
-- under this module's own name, or they land on the wrong table and
-- self:DB() never sees them (see AlchemyNavigation/Modules/Map/
-- Map.lua's defaults for the same pattern: `profile = { Map = {...} }`).
-- The sibling `Map` entry isn't this module's own data - it's seeding
-- the ROOT db.profile.Map table (see the note above on how bind()
-- merges dbDefaults), which is where the ported Nx.Window code (see
-- UI/Window.lua's Adjust/SetLayoutMode) reads Nx.db.profile.Map.
-- Compatibility, Carbonite's own combat-lockdown safety flag. Reusing
-- this mechanism to seed it means UI/Window.lua needs zero edits.
local MinimapWindow = Module:New("MinimapWindow", {
    defaults = {
        profile = {
            MinimapWindow = {
                NativeMinimapHidden = true,
                AutoFollow = true,
            },
            Map = {
                Compatibility = true,
            },
        },
    },
})

-- Self-register alongside the rest of the Map module family (same
-- pattern as ZoomController.lua/NativeMinimapHide.lua/etc.).
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}
AlchemyGPS.Modules.Map.MinimapWindow = MinimapWindow

function MinimapWindow:OnEnable()
    -- AceAddon's automatic module-enable fires on ADDON_LOADED, but
    -- Core/SavedVariables.lua's bind() only runs on the later
    -- PLAYER_LOGIN (ALCHEMYGPS_INITIALIZE). Calling self:DB() before
    -- bind() has run returns Module.lua's transient defaults-only
    -- fallback table, not the real saved value - applying native-hide
    -- from that silently diverges from whatever's actually on disk
    -- (confirmed live, 2026-11-08: native minimap stayed hidden at
    -- login even with the Settings checkbox correctly showing
    -- unchecked, because this ran before the real saved "false" was
    -- available and never re-ran once it was). Poll until the real
    -- per-module view exists before applying, instead of trusting
    -- whatever self:DB() happens to return on the first call.
    local function applyNativeHiddenOnceReady()
        if not AlchemyGPS.Core.SavedVariables:GetModuleDB(self:GetName()) then
            AlchemyGPS:ScheduleTimer(applyNativeHiddenOnceReady, 0.1)
            return
        end
        local NativeMinimapHide = AlchemyGPS.Modules.Map.NativeMinimapHide
        if NativeMinimapHide then
            NativeMinimapHide:SetNativeHidden(self:DB().profile.NativeMinimapHidden == true)
        end

        -- Remember whether the map window itself was open or closed,
        -- same way UI/Window.lua's Window:Show already persists it
        -- (SaveData["Hide"], now backed by AlchemyGPS.db.profile.
        -- WindowLayouts - see that file's Create()). That table only
        -- exists once the window has actually been created/opened at
        -- least once this addon's lifetime - a truly first-ever login
        -- (nothing saved yet) must NOT auto-open a window the player
        -- has never asked to see.
        local layouts = AlchemyGPS.db and AlchemyGPS.db.profile
            and AlchemyGPS.db.profile.WindowLayouts
        local saved = layouts and layouts["AlchemyGPSMinimapWindow"]
        if saved and not saved["Hide"] then
            self:Open()
        end
    end
    applyNativeHiddenOnceReady()

    AlchemyGPS.Core.SlashCommands:Register("minimap", function(rest)
        rest = (rest or ""):lower()
        local NativeMinimapHide_ = AlchemyGPS.Modules.Map.NativeMinimapHide
        if not NativeMinimapHide_ then return end
        -- Persists the choice, not just applying it live, so it
        -- survives to the next login and agrees with the Settings
        -- window checkbox this same value backs once that exists.
        if rest == "hide" then
            self:DB().profile.NativeMinimapHidden = true
            NativeMinimapHide_:SetNativeHidden(true)
        elseif rest == "show" then
            self:DB().profile.NativeMinimapHidden = false
            NativeMinimapHide_:SetNativeHidden(false)
        else
            self.log:info("usage: /gps minimap hide|show")
            return
        end
        -- Keep the Settings window's checkbox in sync if it's open -
        -- it only reads get() once, at creation, otherwise (see that
        -- file's own `checkboxes` comment).
        local SettingsWindow = AlchemyGPS.Modules.Settings and AlchemyGPS.Modules.Settings.SettingsWindow
        if SettingsWindow and SettingsWindow.Refresh then SettingsWindow:Refresh() end
    end, "hide|show the native Blizzard minimap")

    AlchemyGPS.Core.SlashCommands:Register("showmap", function()
        self:Open()
    end, "open the (placeholder) minimap window")
end

-- Build-order step 4: the window content is now the real live-widget
-- blend (Map/MinimapEngine.lua), not the step-3 solid-color
-- placeholder. Chrome itself (title bar, resize, drag, close X,
-- middle-click maximize) is unchanged from step 3. A one-way open,
-- same as the plan's "Show Minimap" button: the window only closes
-- via its own X.
-- REMOVED same day (2026-11-10, "Mode: Live" removal): this window
-- used to reparent the real Blizzard Minimap widget into itself
-- (Map/MinimapEngine.lua's TakeOwnership/ApplyTakeOwnership) and blend
-- it in as a small accent on top of the tile canvas - Open() force-hid
-- the native minimap for the duration, regardless of the user's own
-- "Hide Blizzard minimap" preference, and restored it on close. That
-- reparenting turned out to be the real cause of a recurring
-- GatherMate2 taint popup (see MinimapEngine.lua's own header comment)
-- - removed entirely, along with the "Mode: Live"/"Mode: Tiles" toggle
-- this comment used to explain (there's only ever one render mode
-- now, the tile canvas). The native minimap's visibility is now driven
-- ONLY by the user's own saved preference, applied once at login and
-- on toggle - this window's own open/close state no longer touches it
-- at all.

function MinimapWindow:Open()

    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine

    if self.Win then
        self.Win:Show(true)
        return
    end

    local Nx = AlchemyGPS

    -- (name, minResizeW, minResizeH, secure, titleLines, borderType, hide, noButs)
    -- secure=false: no protected children, so the combat-lockdown
    -- mouse-down guard in UI/Window.lua's OnMouseDown never applies
    -- here. borderType/hide/noButs left nil: sizeable + bordered +
    -- shown + with buttons (Create's own defaults).
    local win = Nx.Window:Create("AlchemyGPSMinimapWindow", 120, 120, false, 1)
    self.Win = win

    -- One no-zone-key call per the plan: seed the "" (normal) layout
    -- mode's default position/size. Nx.FixWin's deferred post-login
    -- batch isn't ported (see UI/Window.lua's header), so apply the
    -- layout ourselves right after, instead of relying on self.LoginDone.
    -- A literal 300,150 top-left offset (the original default) landed
    -- right under the always-on debug overlay (also top-left-anchored)
    -- on first open. Negative fractions in (-1, 0) are
    -- Window:SetLayoutMode's own "% of screen width/height" convention
    -- (x/y = sw/sh * -x/-y - see UI/Window.lua) - set here to roughly
    -- where the user placed the window by hand (just above the action
    -- bars, left of center), eyeballed from a live screenshot
    -- (2026-11-09) rather than read back from SavedVariables, since
    -- this window's dragged position isn't persisted (Nx.FixWin's
    -- deferred post-login save/restore batch isn't ported - see this
    -- function's header comment above) - nudge these two numbers if
    -- the default lands off from where you actually want it.
    win:InitLayoutData(nil, -0.43, -0.81, 220, 220, 2, nil)
    win:SetLayoutMode(1)

    win:CreateButtons(true, true, false)    -- closer + maxer, no miner
    win:SetTitle("Alchemy GPS")

    -- Settings-gear button, title-bar row next to Close/Max. No real
    -- Carbonite analog (Nx.Button's TypeData - UI/Button.lua - only
    -- ever defined Close/CloseLock/Lock/Max/MaxOn; the real window
    -- chrome never had its own settings button), so this is a plain
    -- icon button rather than a ported Nx.Button skin. Placed one more
    -- slot left of the Maxer button, same TOPRIGHT row/anchor math
    -- CreateButtons uses for Close/Max (UI/Window.lua:297,306).
    local settingsBut = CreateFrame("Button", nil, win.Frm)
    settingsBut:SetSize(12, 12)
    settingsBut:SetPoint("TOPRIGHT", win.Frm, "TOPRIGHT",
        win.BorderW - 26.5 - 20, win.Sizeable and -win.BorderH or -3)
    settingsBut:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsBut:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsBut:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
    settingsBut:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsBut:GetHighlightTexture():SetBlendMode("ADD")
    settingsBut:SetScript("OnClick", function()
        local SettingsWindow = AlchemyGPS.Modules.Settings and AlchemyGPS.Modules.Settings.SettingsWindow
        if SettingsWindow then SettingsWindow:Open() end
    end)
    self.SettingsBut = settingsBut

    -- Auto-follow checkbox, title-bar row directly left of the
    -- Settings gear (user-requested quick toggle, 2026-11-10). Backs
    -- MinimapEngine.lua's continuous per-tick re-center-on-player call
    -- (ZoomController:Move, gated on this same saved flag) - unchecking
    -- it is what lets a manual pan-drag stay where you left it instead
    -- of snapping back to center the instant you release the mouse.
    -- Real checkbox textures (Blizzard's stock UI-CheckBox set, shrunk
    -- to match the tight title-bar row), not a plain icon button like
    -- settingsBut above - this one needs to show a persistent
    -- checked/unchecked state, not just fire once on click.
    local followCB = CreateFrame("CheckButton", nil, win.Frm)
    followCB:SetSize(14, 14)
    followCB:SetPoint("RIGHT", settingsBut, "LEFT", -6, 0)
    followCB:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    followCB:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    followCB:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    followCB:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    followCB:SetChecked(self:DB().profile.AutoFollow ~= false)
    followCB:SetScript("OnClick", function(cb)
        self:DB().profile.AutoFollow = cb:GetChecked() and true or false
    end)
    followCB:SetScript("OnEnter", function(cb)
        GameTooltip:SetOwner(cb, "ANCHOR_LEFT")
        GameTooltip:SetText("Auto-follow player")
        GameTooltip:AddLine(
            "Recenters the view on you once you stop panning. Uncheck to pan freely without it snapping back.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    followCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.FollowCB = followCB

    -- Filter button, title-bar row directly left of the auto-follow
    -- checkbox (build-order step 9k, 2026-11-10, explicit user
    -- request). Opens FilterMenu.lua's own checklist popup - see that
    -- file's header for why it's not built from Blizzard's dropdown
    -- system. Styled like the zoom buttons just below (flat dark
    -- background + text label, not an icon) rather than a bare icon
    -- button like settingsBut - this project has had more than one
    -- wrong-guessed icon-texture-path bug this session, and a text
    -- label carries zero texture-path risk at all.
    local filterBut = CreateFrame("Button", nil, win.Frm)
    filterBut:SetSize(40, 14)
    filterBut:SetPoint("RIGHT", followCB, "LEFT", -6, 0)
    local filterBg = filterBut:CreateTexture(nil, "BACKGROUND")
    filterBg:SetAllPoints()
    filterBg:SetColorTexture(0, 0, 0, 0.5)
    local filterText = filterBut:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterText:SetPoint("CENTER")
    filterText:SetText("Filter")
    filterBut:SetScript("OnClick", function()
        local FilterMenu = AlchemyGPS.Modules.Map.FilterMenu
        if FilterMenu then FilterMenu:Toggle(filterBut) end
    end)
    self.FilterBut = filterBut

    -- Terrain/Art Map layer toggles (build-order step 18 follow-up,
    -- 2026-11-11, direct user request for clickable buttons instead of
    -- typing the `/gps hideart`/`/gps hideterrain` diagnostic slash
    -- commands those same two flags already backed - see
    -- MinimapEngine.lua's own header comment above
    -- ART_MAP_LEVEL_OFFSET/TERRAIN_TILE_LEVEL_OFFSET). Same bare-
    -- checkbox-plus-tooltip style as followCB above (no text label -
    -- title bar is already tight), reading/writing
    -- MinimapEngine.DebugHideArt/DebugHideTerrain directly rather than
    -- a new SavedVariables field - these are still the Phase 2/3
    -- isolation-testing toggles from the map-layering fix, not a new
    -- persisted user preference, so they intentionally reset to both-
    -- on (unchecked = "hidden") at next login/reload, same as the
    -- slash commands already did. Checked = layer shown, matching the
    -- Filter menu's own checkbox-means-visible convention. Reuses the
    -- `MinimapEngine` local already declared at the top of this
    -- function (line 143) rather than redeclaring it.

    local terrainCB = CreateFrame("CheckButton", nil, win.Frm)
    terrainCB:SetSize(14, 14)
    terrainCB:SetPoint("RIGHT", filterBut, "LEFT", -6, 0)
    terrainCB:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    terrainCB:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    terrainCB:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    terrainCB:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    terrainCB:SetChecked(not MinimapEngine.DebugHideTerrain)
    terrainCB:SetScript("OnClick", function(cb)
        MinimapEngine.DebugHideTerrain = not cb:GetChecked()
    end)
    terrainCB:SetScript("OnEnter", function(cb)
        GameTooltip:SetOwner(cb, "ANCHOR_LEFT")
        GameTooltip:SetText("Terrain Texture layer")
        GameTooltip:AddLine(
            "Close-zoom real minimap tiles. Uncheck to hide it and see the Art Map layer alone.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    terrainCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.TerrainCB = terrainCB

    local artCB = CreateFrame("CheckButton", nil, win.Frm)
    artCB:SetSize(14, 14)
    artCB:SetPoint("RIGHT", terrainCB, "LEFT", -6, 0)
    artCB:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    artCB:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    artCB:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    artCB:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    artCB:SetChecked(not MinimapEngine.DebugHideArt)
    artCB:SetScript("OnClick", function(cb)
        MinimapEngine.DebugHideArt = not cb:GetChecked()
    end)
    artCB:SetScript("OnEnter", function(cb)
        GameTooltip:SetOwner(cb, "ANCHOR_LEFT")
        GameTooltip:SetText("Art Map layer")
        GameTooltip:AddLine(
            "Coarse continent/zone overview art. Uncheck to hide it and see the Terrain Texture layer alone.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    artCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.ArtMapCB = artCB

    -- Zoom buttons, build-order step 5. Carbonite's own +/- zoom
    -- buttons are Blizzard's native MinimapZoomIn/MinimapZoomOut,
    -- which only make sense for a docked (small, native-replacing)
    -- minimap - this window is the undocked case, so it gets its own
    -- pair instead, matching MiniMap:ZoomIn/ZoomOut's delta of +-2.
    --
    -- Styled 2026-11-10 to match AlchemyNavigation's own undocked-
    -- minimap zoom buttons (Modules/Map/Minimap.lua's makeButton) per
    -- explicit user request ("steal the style") - a plain flat 16x16
    -- button (not UIPanelButtonTemplate's gray beveled look) with a
    -- black 50%-alpha background and a centered +/- label, no
    -- hover/pressed textures (that sibling project's version doesn't
    -- have any either - copied as-is, not embellished). Position kept
    -- at this window's own bottom-right anchor rather than
    -- AlchemyNavigation's bottom-left, since "style" was the ask, not
    -- layout.
    local ZoomController = AlchemyGPS.Modules.Map.ZoomController

    local function makeZoomButton(label)
        local b = CreateFrame("Button", nil, win.Frm)
        b:SetSize(16, 16)

        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)

        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(label)

        return b
    end

    local zoomIn = makeZoomButton("+")
    zoomIn:SetPoint("BOTTOMRIGHT", win.Frm, "BOTTOMRIGHT", -6, 4)
    zoomIn:SetScript("OnClick", function() ZoomController:ScrollSteps(2) end)

    local zoomOut = makeZoomButton("-")
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -2, 0)
    zoomOut:SetScript("OnClick", function() ZoomController:ScrollSteps(-2) end)

    -- content is the clip area the live minimap patch and the world-
    -- art tile frames (both parented to it - MinimapEngine:TakeOwnership/
    -- InitTileFrames) are positioned against. Used to carry its own
    -- plain dark texture here as a stand-in for the real world-art
    -- canvas, back when build-order step 8 hadn't landed yet. That
    -- texture was never removed once real tiles existed - confirmed
    -- live, 2026-11-10: at 0.9 alpha, directly on this same frame the
    -- tile frames are parented to, it was painting over the real tile
    -- art every tick regardless of the tiles' own brightness (Tile Map
    -- Brightness maxed at 250% and still solid black). No replacement
    -- background needed here - win.Frm already has its own backdrop
    -- (UI/Window.lua's CreateBorders) showing through wherever tiles
    -- don't cover (no known zone, or past the zone's own art edge).
    local content = CreateFrame("Frame", nil, win.Frm)
    win:Attach(content)
    self.Content = content

    -- content (just attached) fills the whole window 0-1 fractionally
    -- and would otherwise draw over zoomIn/zoomOut/settingsBut - WoW
    -- compares frame LEVEL as a flat, global sort key within a shared
    -- frame STRATA, regardless of which frame is whose actual parent
    -- (confirmed live, 2026-11-11: this is exactly why these chrome
    -- buttons, siblings of `content` under `win.Frm`, could still be
    -- drawn over by `content`'s own CHILDREN - MinimapEngine's internal
    -- layer stack - once one of those children's level reached or
    -- passed this row's own level).
    --
    -- CHROME_LEVEL_OFFSET was a bare `+1` until build-order step 18's
    -- map-layering fix gave MinimapEngine's own internal layers
    -- explicit level offsets of their own (Art Map +1, Terrain Texture
    -- +2, up through Player Marker +10 - see MinimapEngine.lua's own
    -- ART_MAP_LEVEL_OFFSET header comment for the full stack) - Terrain
    -- and Art are full-window background layers (unlike the small,
    -- sparse icon frames, which rarely land on the exact pixels a
    -- button occupies), so once either one's level reached this row's
    -- own `+1`, it visibly painted over every title-bar/zoom button at
    -- once - reported live as "my zoom in zoom out buttons are gone."
    -- Fixed by giving this row a big, deliberately round margin well
    -- above MinimapEngine's own current ceiling (+10), so a future
    -- addition to that internal stack can't silently repeat this same
    -- collision - chrome should always just win.
    local CHROME_LEVEL_OFFSET = 50
    zoomIn:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)
    zoomOut:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)
    settingsBut:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)
    followCB:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)
    filterBut:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)
    terrainCB:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)
    artCB:SetFrameLevel(content:GetFrameLevel() + CHROME_LEVEL_OFFSET)

    MinimapEngine:TakeOwnership(win, content)

    -- Real source creates its button dock right alongside the map
    -- window itself, same first-open-only lifecycle (MapEngine.lua
    -- :456-457, `self.Maps[1] = self:Create(1); self.Dock:Create()`).
    local MinimapDock = AlchemyGPS.Modules.Map.MinimapDock
    if MinimapDock then MinimapDock:Create() end

    -- Build-order step 6/7 smoothness fix: drive Update() from a real
    -- per-frame OnUpdate script on the content frame instead of a
    -- 0.1s AceTimer, matching Carbonite's own Nx.Map.OnUpdate wiring
    -- (MapEngine.lua:1709, f:SetScript("OnUpdate", self.OnUpdate)).
    -- Update()'s own internal Ttl throttle (MinimapEngine.lua) still
    -- caps the real work at the same ~20fps (.05s) the real source
    -- uses - this just gets accurate per-frame `elapsed` instead of a
    -- timer's coarser interval, and - same as the real source -
    -- naturally stops ticking while the window/content frame is
    -- hidden, no manual cancel needed on close. This only runs once,
    -- here at content-frame creation (the fast reopen path above
    -- returns before reaching this line), so no "already registered"
    -- guard is needed.
    content:SetScript("OnUpdate", function(_, elapsed)
        MinimapEngine:Update(elapsed)
    end)

    win:Show(true)
end
