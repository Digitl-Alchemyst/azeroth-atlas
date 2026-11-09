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
            },
            Map = {
                Compatibility = true,
            },
        },
    },
})

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
-- empty shell, since the widget had moved into ours). Carbonite itself
-- never hits this because its big map is a separate static zone-tile
-- canvas (Modules/Map/MapEngine.lua's Nx.Map:GetMap(1)) with the live
-- widget only ever blended in as a small accent - that canvas is a
-- planned future mode (build-order step 8) this addon doesn't have
-- yet. Until then, "Live" (this window borrowing the real widget) is
-- the only working mode, so opening it force-hides the native minimap
-- instead of leaving both fighting over the one widget.
function MinimapWindow:SetMode(mode)
    if mode == "Tiles" then
        self.log:info("Tiles mode (Carbonite-style zone canvas) isn't built yet - staying on Live")
        return
    end
    self.Mode = "Live"
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
    win:InitLayoutData(nil, 300, 150, 220, 220, 2, nil)
    win:SetLayoutMode(1)

    win:CreateButtons(true, true, false)    -- closer + maxer, no miner
    win:SetTitle("Alchemy GPS")

    -- Mode toggle, same idea as Carbonite's own 2D/3D map-mode button.
    -- "Tiles" isn't built yet (SetMode above just logs and stays on
    -- Live), but the control lives here now so it's ready once it is.
    local modeBut = CreateFrame("Button", nil, win.Frm, "UIPanelButtonTemplate")
    modeBut:SetSize(90, 20)
    modeBut:SetPoint("BOTTOMLEFT", win.Frm, "BOTTOMLEFT", 6, 4)
    modeBut:SetText("Mode: " .. self.Mode)
    modeBut:SetScript("OnClick", function()
        self:SetMode(self.Mode == "Live" and "Tiles" or "Live")
        modeBut:SetText("Mode: " .. self.Mode)
    end)
    self.ModeBut = modeBut

    -- Stand-in for the real world-art canvas (build-order step 8) -
    -- just a plain dark backdrop so the clip area against which the
    -- live minimap patch is positioned has a visible boundary.
    local content = CreateFrame("Frame", nil, win.Frm)
    local tex = content:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(0.08, 0.08, 0.10, 0.9)
    tex:SetAllPoints(content)
    win:Attach(content)
    self.Content = content

    -- content (just attached) fills the whole window 0-1 fractionally
    -- and would otherwise draw over modeBut at the same sibling frame
    -- level, since it was created after - keep the button clickable.
    modeBut:SetFrameLevel(content:GetFrameLevel() + 1)

    MinimapEngine:TakeOwnership(win, content)

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

    if not self.minimapEngineTimer then
        self.minimapEngineTimer = AlchemyGPS:ScheduleRepeatingTimer(function()
            MinimapEngine:Update()
        end, 0.1)
    end

    win:Show(true)
end
