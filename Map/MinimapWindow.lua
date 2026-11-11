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
-- pattern as ZoomController.lua/NativeMinimapHide.lua/etc.) - needed
-- so MinimapEngine.lua's Update() can read the current Mode
-- (AlchemyGPS.Modules.Map.MinimapWindow.Mode) to decide whether to
-- show the small live-widget accent.
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
        end
    end, "hide|show the native Blizzard minimap")

    AlchemyGPS.Core.SlashCommands:Register("showmap", function()
        self:Open()
    end, "open the (placeholder) minimap window")

    -- Temporary diagnostic for the live-widget blend (build-order
    -- step 4) not showing up visually in testing. Remove once that's
    -- confirmed working.
    AlchemyGPS.Core.SlashCommands:Register("mapdebug", function()
        local E = AlchemyGPS.Modules.Map.MinimapEngine
        local log = AlchemyGPS.Core.Logger
        local mm = E and E.MMFrm
        if not mm then
            log:info("MinimapEngine not initialized - open the minimap window first")
            return
        end
        local parent = mm:GetParent()
        log:info("MMFrm parent=%s shown=%s alpha=%.2f w=%.1f h=%.1f scale=%.2f strata=%s level=%d",
            tostring(parent and parent.GetName and parent:GetName() or parent),
            tostring(mm:IsShown()), mm:GetAlpha() or -1, mm:GetWidth() or -1, mm:GetHeight() or -1,
            mm:GetScale() or -1, tostring(mm:GetFrameStrata()), mm:GetFrameLevel() or -1)
        log:info("content Frm w=%.1f h=%.1f shown=%s | win strata=%s level=%d",
            E.Frm and E.Frm:GetWidth() or -1, E.Frm and E.Frm:GetHeight() or -1,
            tostring(E.Frm and E.Frm:IsShown()),
            tostring(E.Win and E.Win.Frm:GetFrameStrata()), E.Win and E.Win.Frm:GetFrameLevel() or -1)
        log:info("MMFScale=%s MapW=%s MapH=%s MMOwn=%s",
            tostring(E.MMFScale), tostring(E.MapW), tostring(E.MapH), tostring(E.MMOwn))
        local pt, rel, relpt, x, y = mm:GetPoint()
        log:info("MMFrm point=%s relPt=%s x=%s y=%s",
            tostring(pt), tostring(relpt), tostring(x), tostring(y))
        log:info("IsVisible=%s GetZoom=%s MMZoomType=%s",
            tostring(mm:IsVisible()), tostring(mm.GetZoom and mm:GetZoom()), tostring(E.MMZoomType))

        -- Dump every visual region Minimap itself owns, so we can see
        -- directly whether a terrain texture region exists at all,
        -- and if so, what file it points at / whether it's shown.
        local regions = { mm:GetRegions() }
        log:info("MMFrm region count=%d", #regions)
        for i, r in ipairs(regions) do
            local objType = r.GetObjectType and r:GetObjectType() or "?"
            if objType == "Texture" then
                local texPath = r.GetTexture and r:GetTexture()
                log:info("  [%d] Texture tex=%s shown=%s alpha=%.2f layer=%s",
                    i, tostring(texPath), tostring(r:IsShown()), r:GetAlpha() or -1,
                    tostring(r.GetDrawLayer and r:GetDrawLayer()))
            else
                log:info("  [%d] %s shown=%s", i, tostring(objType), tostring(r:IsShown()))
            end
        end
    end, "dump minimap-blend diagnostic info")
end

-- Build-order step 4: the window content is now the real live-widget
-- blend (Map/MinimapEngine.lua), not the step-3 solid-color
-- placeholder. Chrome itself (title bar, resize, drag, close X,
-- middle-click maximize) is unchanged from step 3. A one-way open,
-- same as the plan's "Show Minimap" button: the window only closes
-- via its own X.
-- The live Blizzard Minimap widget is a single client-provided
-- resource - it can only have one parent/location at a time, so our
-- window and the native minimap can never both show real terrain from
-- it simultaneously (confirmed live, 2026-11-08: opening our window
-- while the native one was also visible left the native minimap an
-- empty shell, since the widget had moved into ours). This is why
-- Open() always force-hides the native minimap regardless of Mode -
-- the window always owns the one live widget while open, it just
-- doesn't always draw it (see below).
--
-- Build-order step 8 added the real background canvas (the static
-- zone-art tiles, Map/MinimapEngine.lua's UpdateWorldArt/
-- MoveCurZoneTiles), matching real Carbonite's own split: a static
-- zone-tile canvas with the live widget blended in as a small accent
-- on top (MapEngine.lua's Nx.Map:GetMap(1)). "Mode" picks whether that
-- accent shows: "Live" shows it (auto-hidden by MinimapEngine.lua's
-- Update() when zoomed too far out for any of its size presets to
-- fit), "Tiles" hides it unconditionally so only the background canvas
-- + its drawn player-position marker show.
function MinimapWindow:SetMode(mode)
    self.Mode = (mode == "Tiles") and "Tiles" or "Live"
end

function MinimapWindow:ForceNativeHidden(hidden)
    local NativeMinimapHide = AlchemyGPS.Modules.Map.NativeMinimapHide
    if not NativeMinimapHide then return end
    self:DB().profile.NativeMinimapHidden = hidden
    NativeMinimapHide:SetNativeHidden(hidden)
    local SettingsWindow = AlchemyGPS.Modules.Settings and AlchemyGPS.Modules.Settings.SettingsWindow
    if SettingsWindow and SettingsWindow.Refresh then SettingsWindow:Refresh() end
end

function MinimapWindow:Open()

    local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine
    self.Mode = self.Mode or "Live"

    -- Capture whatever the user's own native-hide preference was
    -- before WE force it on below, once per open/close cycle, so
    -- closing can hand it back instead of permanently overwriting a
    -- preference the user set for reasons unrelated to our window.
    if self.PrevNativeHidden == nil then
        self.PrevNativeHidden = self:DB().profile.NativeMinimapHidden == true
    end
    self:ForceNativeHidden(true)

    if self.Win then
        -- Close fires MinimapEngine:ReleaseOwnership() (below), handing
        -- the live widget back to Blizzard. Without re-taking it here,
        -- reopening just re-shows the window with its empty dark
        -- backdrop and no live widget in it - confirmed live: Update()
        -- was bailing out every tick on MMOwn being false, frozen since
        -- the moment the window had first closed.
        MinimapEngine:TakeOwnership(self.Win, self.Content)
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

    -- Mode toggle, same idea as Carbonite's own 2D/3D map-mode button.
    -- See SetMode above for what "Live" vs "Tiles" actually changes.
    local modeBut = CreateFrame("Button", nil, win.Frm, "UIPanelButtonTemplate")
    modeBut:SetSize(90, 20)
    modeBut:SetPoint("BOTTOMLEFT", win.Frm, "BOTTOMLEFT", 6, 4)
    modeBut:SetText("Mode: " .. self.Mode)
    modeBut:SetScript("OnClick", function()
        self:SetMode(self.Mode == "Live" and "Tiles" or "Live")
        modeBut:SetText("Mode: " .. self.Mode)
    end)
    self.ModeBut = modeBut

    -- Zoom buttons, build-order step 5. Carbonite's own +/- zoom
    -- buttons are Blizzard's native MinimapZoomIn/MinimapZoomOut,
    -- which only make sense for a docked (small, native-replacing)
    -- minimap - this window is the undocked case, so it gets its own
    -- pair instead, matching MiniMap:ZoomIn/ZoomOut's delta of +-2.
    local ZoomController = AlchemyGPS.Modules.Map.ZoomController
    local zoomIn = CreateFrame("Button", nil, win.Frm, "UIPanelButtonTemplate")
    zoomIn:SetSize(24, 20)
    zoomIn:SetPoint("BOTTOMRIGHT", win.Frm, "BOTTOMRIGHT", -6, 4)
    zoomIn:SetText("+")
    zoomIn:SetScript("OnClick", function() ZoomController:ScrollSteps(2) end)

    local zoomOut = CreateFrame("Button", nil, win.Frm, "UIPanelButtonTemplate")
    zoomOut:SetSize(24, 20)
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -2, 0)
    zoomOut:SetText("-")
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
    -- and would otherwise draw over modeBut/zoomIn/zoomOut/settingsBut
    -- at the same sibling frame level, since it was created after -
    -- keep them clickable.
    modeBut:SetFrameLevel(content:GetFrameLevel() + 1)
    zoomIn:SetFrameLevel(content:GetFrameLevel() + 1)
    zoomOut:SetFrameLevel(content:GetFrameLevel() + 1)
    settingsBut:SetFrameLevel(content:GetFrameLevel() + 1)
    followCB:SetFrameLevel(content:GetFrameLevel() + 1)

    MinimapEngine:TakeOwnership(win, content)

    -- Real source creates its button dock right alongside the map
    -- window itself, same first-open-only lifecycle (MapEngine.lua
    -- :456-457, `self.Maps[1] = self:Create(1); self.Dock:Create()`).
    local MinimapDock = AlchemyGPS.Modules.Map.MinimapDock
    if MinimapDock then MinimapDock:Create() end

    -- Give the live widget back to Blizzard when this window closes,
    -- so a still-visible native MinimapCluster doesn't end up an
    -- empty shell missing its Minimap child. See MinimapEngine.lua's
    -- ReleaseOwnership header comment.
    win:SetUser(self, function(_, event)
        if event == "Close" then
            MinimapEngine:ReleaseOwnership()
            -- Hand the native-hide preference back to whatever it was
            -- before Open() forced it on, instead of permanently
            -- leaving the native minimap hidden just because our
            -- window happened to have been open once this session.
            if self.PrevNativeHidden ~= nil then
                self:ForceNativeHidden(self.PrevNativeHidden)
                self.PrevNativeHidden = nil
            end
        end
    end)

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
