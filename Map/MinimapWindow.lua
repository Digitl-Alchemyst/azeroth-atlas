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
                -- 2026-11-16: M / L key overrides (see ApplyKeys) and
                -- Carbonite's auto-scale (MinimapEngine:AutoScaleTarget).
                OverrideMLKeys = true,
                AutoScale = true,
                AutoScaleMin = 0.05,
                AutoScaleMax = 4,
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

-- 2026-11-16: the map renders above other addons' frames (see Open()'s
-- strata comment). DIALOG beats the MEDIUM/HIGH strata action bars,
-- raid frames and unit frames use; FULLSCREEN is the overlay tier for
-- the map's own chrome and player marker. Popups that must open over
-- the map (Settings, the quest list, menus) use FULLSCREEN_DIALOG or
-- TOOLTIP.
local MAP_STRATA = "DIALOG"
local OVERLAY_STRATA = "FULLSCREEN"
MinimapWindow.MAP_STRATA = MAP_STRATA
MinimapWindow.OVERLAY_STRATA = OVERLAY_STRATA

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

        self:ApplyKeys()

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
    -- Pinned above other addons (see MAP_STRATA) - set before the first
    -- SetLayoutMode below so the saved layout's own layer never applies.
    win.ForceStrata = MAP_STRATA
    win.OnStrataChanged = function() self:SyncStrata() end

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

    -- Header checkboxes, right to left (2026-11-16, user request: no
    -- text labels, hover tooltips only):
    --   Center (right, next to the gear) - saved flag AutoFollow. The
    --     original 2026-11-10 checkbox: keeps the player in the middle
    --     of the map at every zoom/size. Unchecking it is what lets a
    --     manual pan stay where you left it.
    --   Follow (left of Center) - saved flag AutoScale. Carbonite's
    --     auto-scale (MinimapEngine:AutoScaleTarget): with a goto,
    --     corpse or routed quest active, zooms in and out so both the
    --     player and that point stay in the frame.
    -- The saved flag names predate the user's names for them and are
    -- kept so existing saved settings carry over.
    local function makeHeaderCB(anchor, field, title, text)
        local cb = CreateFrame("CheckButton", nil, win.Frm)
        cb:SetSize(14, 14)
        cb:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        cb:SetChecked(self:DB().profile[field] ~= false)
        cb:SetScript("OnClick", function(b)
            self:DB().profile[field] = b:GetChecked() and true or false
            local SettingsWindow = AlchemyGPS.Modules.Settings and AlchemyGPS.Modules.Settings.SettingsWindow
            if SettingsWindow and SettingsWindow.Refresh then SettingsWindow:Refresh() end
        end)
        cb:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            GameTooltip:SetText(title)
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return cb
    end

    local centerCB = makeHeaderCB(settingsBut, "AutoFollow", "Center",
        "Keeps you in the middle of the map at any zoom or window size. "
        .. "Uncheck to pan freely without the map snapping back to you.")
    self.CenterCB = centerCB

    local followCB = makeHeaderCB(centerCB, "AutoScale", "Follow",
        "With a goto, corpse or quest route active, zooms the map in and out so "
        .. "both you and that point stay in the frame. Picks the goto first, then "
        .. "your corpse, then the quest.")
    self.FollowCB = followCB

    -- The title text used to run the full width of the bar, under these
    -- controls - stop it just left of the leftmost one.
    local titleFS = win.TitleFStr and win.TitleFStr[1]
    if titleFS then
        local _, _, _, _, ty = titleFS:GetPoint(1)
        titleFS:ClearAllPoints()
        titleFS:SetPoint("TOPLEFT", win.Frm, "TOPLEFT", win.BorderW, ty or -win.BorderH)
        titleFS:SetPoint("RIGHT", followCB, "LEFT", -6, 0)
        titleFS:SetWordWrap(false)
    end

    -- 2026-11-16: the Filter button and the Base/Art Map/Terrain layer
    -- checkboxes that used to continue this row leftward moved into the
    -- Settings window's "Map" tab (explicit user request - keep the
    -- header to the location name). The title bar now carries only
    -- the location text, Follow, Center, the Settings gear and
    -- Close/Max.

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
    -- explicit level offsets of their own (now, as of build-order step
    -- 21's 5-layer rework: Base +1, Art Map +2, Terrain Texture +3,
    -- Service Layer +5 - see MinimapEngine.lua's own BASE_LEVEL_OFFSET
    -- header comment for the full stack) - Terrain and Art/Base are
    -- full-window background layers (unlike the small, sparse icon
    -- frames, which rarely land on the exact pixels a button occupies),
    -- so once one of them's level reached this row's own `+1`, it
    -- visibly painted over every title-bar/zoom button at once -
    -- reported live as "my zoom in zoom out buttons are gone." Fixed by
    -- giving this row a big, deliberately round margin well above
    -- MinimapEngine's own current ceiling (+5), so a future addition to
    -- that internal stack can't silently repeat this same collision -
    -- chrome should always just win.
    --
    -- 2026-11-16 (map above other addons): the whole stack moved up a
    -- tier. The window itself is pinned to MAP_STRATA ("DIALOG", see
    -- the top of this file) so Bartender bars, VuhDo panels and Frames
    -- Forever unit frames - all MEDIUM/HIGH - can no longer show
    -- through it. Chrome and the player marker go one tier higher
    -- still (OVERLAY_STRATA, "FULLSCREEN"), the same tier the live-blip
    -- radar patch reaches (MinimapEngine's MinimapSyncLayer puts it one
    -- strata above the window), and win there on frame level. All of
    -- this is re-asserted every tick by SyncStrata below, because
    -- changing a parent's strata drags its children along with it.
    self.Chrome = { zoomIn, zoomOut, settingsBut, self.CenterCB, self.FollowCB }

    -- Movement speed, bottom-left corner (2026-11-16, moved out of the
    -- title per user request). Text is set by MinimapEngine:Update.
    local speedFrm = CreateFrame("Frame", nil, win.Frm)
    speedFrm:SetSize(110, 16)
    speedFrm:SetPoint("BOTTOMLEFT", win.Frm, "BOTTOMLEFT", 8, 4)
    local speedBg = speedFrm:CreateTexture(nil, "BACKGROUND")
    speedBg:SetAllPoints()
    speedBg:SetColorTexture(0, 0, 0, 0.5)
    local speedText = speedFrm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    speedText:SetPoint("LEFT", 4, 0)
    speedText:SetJustifyH("LEFT")
    speedText:SetTextColor(0.85, 0.85, 0.85)
    self.SpeedFrm, self.SpeedText = speedFrm, speedText
    self.Chrome[#self.Chrome + 1] = speedFrm

    -- Dungeon level bar (2026-11-16, user request): top-centre of the
    -- map, inside any dungeon (UpdateLevelBar). Arrows flip
    -- through the floors; clicking the name goes back to your own.
    -- Filled in every tick by UpdateLevelBar.
    local levelBar = CreateFrame("Frame", nil, win.Frm)
    levelBar:SetSize(240, 20)
    levelBar:SetPoint("TOP", win.Frm, "TOP", 0, -((win.TopH or 20) + 4))
    local levelBg = levelBar:CreateTexture(nil, "BACKGROUND")
    levelBg:SetAllPoints()
    levelBg:SetColorTexture(0, 0, 0, 0.6)
    local function arrow(dir, point, x)
        local b = CreateFrame("Button", nil, levelBar)
        b:SetSize(20, 20)
        b:SetPoint(point, x, 0)
        local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir < 0 and "Prev" or "Next") .. "Page-"
        b:SetNormalTexture(base .. "Up")
        b:SetPushedTexture(base .. "Down")
        b:SetDisabledTexture(base .. "Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function() MinimapEngine:StepViewFloor(dir) end)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
            GameTooltip:SetText(dir < 0 and "Previous level" or "Next level")
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local prevBut = arrow(-1, "LEFT", 0)
    local nextBut = arrow(1, "RIGHT", 0)
    local nameBut = CreateFrame("Button", nil, levelBar)
    nameBut:SetPoint("LEFT", prevBut, "RIGHT", 2, 0)
    nameBut:SetPoint("RIGHT", nextBut, "LEFT", -2, 0)
    nameBut:SetHeight(20)
    local levelText = nameBut:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetAllPoints()
    levelText:SetWordWrap(false)
    nameBut:SetScript("OnClick", function() MinimapEngine:SetViewFloor(nil) end)
    nameBut:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Dungeon level")
        GameTooltip:AddLine("Arrows: look at the other levels. Click here: back to the level you're on.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    nameBut:SetScript("OnLeave", function() GameTooltip:Hide() end)
    levelBar:Hide()
    self.LevelBar, self.LevelText = levelBar, levelText
    self.LevelPrev, self.LevelNext = prevBut, nextBut
    self.Chrome[#self.Chrome + 1] = levelBar

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
    win.Frm:SetFrameStrata(MAP_STRATA)
    self:SyncStrata()
end

-- Re-applies the strata stack described in Open() - window at
-- MAP_STRATA, its own close/max buttons with it, chrome and the player
-- marker at OVERLAY_STRATA above everything the map draws. Cheap
-- (string compares) and called every engine tick, since setting a
-- parent's strata resets its children's.
-- The dungeon level bar (see Open): shown in every dungeon (with its
-- arrows greyed out when there is only one level, so it's clear there
-- is nothing to flip to - user feedback 2026-11-16), hidden elsewhere.
-- "Level name  2/3", with a green > on the level you are on.
function MinimapWindow:UpdateLevelBar()
    local bar = self.LevelBar
    if not bar then return end
    local E = AlchemyGPS.Modules.Map.MinimapEngine
    if not E or not E.GetViewFloorIndex then return end
    local i = E:GetViewFloorIndex()
    local floors = E.DungeonFloors
    if not i or not floors or #floors < 1 then
        if bar:IsShown() then bar:Hide() end
        return
    end
    local f = floors[i]
    local winfo = E.MapWorldInfo and E.MapWorldInfo[f.mapId]
    local name = (winfo and winfo.Name) or f.name or ("Level " .. i)
    local here = E.PlayerFloor == i and (not E.PlyrPosUnknown or E.RoomFloorKnown)
    local text = ("%s%s  |cffa0a0a0%d/%d|r"):format(here and "|cff40ff40>|r " or "", name, i, #floors)
    if text ~= self._LevelText then
        self._LevelText = text
        self.LevelText:SetText(text)
        self.LevelPrev:SetEnabled(i > 1)
        self.LevelNext:SetEnabled(i < #floors)
    end
    if not bar:IsShown() then bar:Show() end
end

local CHROME_LEVEL_OFFSET = 50
function MinimapWindow:SyncStrata()
    local win = self.Win
    if not win or not win.Frm then return end
    local f = win.Frm
    if f:GetFrameStrata() ~= MAP_STRATA then f:SetFrameStrata(MAP_STRATA) end

    local base = self.Content and self.Content:GetFrameLevel() or f:GetFrameLevel()
    for _, b in ipairs({ win.ButClose, win.ButMaxer }) do
        local bf = b and b.Frm
        if bf then
            if bf:GetFrameStrata() ~= MAP_STRATA then bf:SetFrameStrata(MAP_STRATA) end
            if bf:GetFrameLevel() < base + CHROME_LEVEL_OFFSET then
                bf:SetFrameLevel(base + CHROME_LEVEL_OFFSET)
            end
        end
    end
    for _, c in ipairs(self.Chrome or {}) do
        if c:GetFrameStrata() ~= OVERLAY_STRATA then c:SetFrameStrata(OVERLAY_STRATA) end
        if c:GetFrameLevel() ~= base + CHROME_LEVEL_OFFSET then
            c:SetFrameLevel(base + CHROME_LEVEL_OFFSET)
        end
    end
end

---------------------------------------------------------------------------------------
-- M / L keys (2026-11-16, user request): M flips the map window between
-- its normal size and its maximized ("big map") size, opening it first
-- if it's closed; L toggles the quest list. Done with override
-- bindings, which sit on top of the player's own key bindings without
-- ever changing or saving them - turn the "M / L keys" option off in
-- Settings > Map and the game's own M (world map) / L (quest log) come
-- straight back. Override bindings can't change during combat, so a
-- change made in combat is applied when combat ends.
---------------------------------------------------------------------------------------

function MinimapWindow:ToggleMapSize()
    if not self.Win or not self.Win:IsShown() then
        self:Open()
        return
    end
    self.Win:ToggleSize()
end

function MinimapWindow:ToggleQuestList()
    local List = AlchemyGPS.Modules.Quest and AlchemyGPS.Modules.Quest.List
    if List then List:Toggle() end
end

-- Global entry points for Bindings.xml.
_G.AlchemyGPS_ToggleMapSize = function() MinimapWindow:ToggleMapSize() end
_G.AlchemyGPS_ToggleQuestList = function() MinimapWindow:ToggleQuestList() end
_G.BINDING_HEADER_ALCHEMYGPS = _G.BINDING_HEADER_ALCHEMYGPS or "Alchemy GPS"
_G.BINDING_NAME_ALCHEMYGPS_TOGGLEMAP = "Toggle map size (small / big)"
_G.BINDING_NAME_ALCHEMYGPS_QUESTLIST = "Toggle quest list"

local keyOwner = CreateFrame("Frame", "AlchemyGPSKeyOwner", UIParent)
keyOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
keyOwner:SetScript("OnEvent", function()
    if keyOwner.pending then MinimapWindow:ApplyKeys() end
end)

function MinimapWindow:ApplyKeys()
    if InCombatLockdown() then
        keyOwner.pending = true
        return
    end
    keyOwner.pending = nil
    ClearOverrideBindings(keyOwner)
    if self:DB().profile.OverrideMLKeys ~= false then
        SetOverrideBinding(keyOwner, false, "M", "ALCHEMYGPS_TOGGLEMAP")
        SetOverrideBinding(keyOwner, false, "L", "ALCHEMYGPS_QUESTLIST")
        -- Alt+M / Alt+L keep the game's own world map and quest log
        -- reachable while M and L belong to Alchemy GPS.
        SetOverrideBinding(keyOwner, false, "ALT-M", "TOGGLEWORLDMAP")
        SetOverrideBinding(keyOwner, false, "ALT-L", "TOGGLEQUESTLOG")
    end
end
