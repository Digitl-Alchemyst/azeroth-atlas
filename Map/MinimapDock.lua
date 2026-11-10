-- Alchemy GPS | Map / MinimapDock
-- Ported from Carbonite/Modules/Map/MapEngine.lua's Nx.Map.Dock
-- (:15919-16238, "MINIMAP BUTTON DOCK") - collects every addon-
-- injected minimap button (tracking, mail, LFG, queue status, DBM/
-- WeakAuras-style LibDBIcon buttons, etc.) out of the live Minimap
-- widget and arranges them in a small bar, instead of leaving them
-- cluttering whatever window currently owns the live widget.
--
-- Confirmed needed live, 2026-11-09: once MinimapEngine.lua borrows
-- the real Minimap widget (ApplyTakeOwnership), every button still
-- parented to it rides along and renders inside our window too.
--
-- NOT built on the real source's Nx.Window (the same UI/Window.lua
-- class our own map window uses) any more, despite the original port
-- having used it - that gave the bar a full backdrop/border "window"
-- enclosure around the icon row, which looked oversized for what's
-- really just a strip of icons (reported live, 2026-11-09, alongside
-- a screenshot). Rebuilt on a single plain, background-less
-- CreateFrame instead: just the icons floating directly over the
-- game world, plus one small square drag handle at the bar's leading
-- edge (its one visible/clickable element) to move the whole thing -
-- no title bar, no border, no backdrop fill. Position is hand-rolled
-- persistence (AlchemyGPS.db.profile.DockPosition), the same small
-- point/relPoint/x/y shape MinimapEngine.lua's debug overlay already
-- uses, since Nx.Window's own SaveData/RecordLayoutData machinery no
-- longer applies here.
--
-- Trimmed from the real two-part source:
--   - Nx.Map.Dock:Create (:15929-15965) - drops the Nx.Free paid-
--     version gate and Nx.db.profile.MiniMap.ButOwn settings check
--     (no Settings UI for this yet - always-on, which is this addon's
--     whole point), Window:SetCreateFade (fade-in polish, not
--     ported), and win.Frm:SetToplevel(true) (not needed - this
--     addon doesn't layer frames the way Carbonite's own window stack
--     does).
--   - Nx.Map.Dock:MinimapOwnInit (:15972-16068) - the one-time full
--     EnumerateFrames() sweep, kept verbatim in shape (same known-
--     name list minus Carbonite's own launcher button, same anchored-
--     to-Minimap-but-parented-elsewhere detection, same exclude
--     list), minus the CT_Core-specific texture-name match (a single
--     known addon's own custom detection hack, not a general
--     mechanism).
--   - Nx.Map.Dock:MinimapDetachFrms (:16090-16238) - the continuous
--     layout, kept verbatim for the math (same 32/max(w,32) per-icon
--     scale-normalize, same CENTER/TOPLEFT anchor formula), minus the
--     corner/spacing/minimize SavedVariable options (Nx.db.profile.
--     MiniMap.But*) this addon has no Settings UI for yet - fixed at
--     a single never-wrapping line instead of the real source's
--     multi-row/column grid, since a single line is what actually
--     docks flush against another window's edge. Row vs. column is
--     the one option this addon DOES expose (AlchemyGPS.db.profile.
--     DockOrientation, Settings window's "Icon bar: vertical column"
--     checkbox) - the real source has no row/column toggle at all,
--     only a 4-corner start-point choice that still wraps into a
--     grid.
--   - The real source's own tick-counter throttle
--     (Frm.NxMap.Tick % self.UpdateMod) doesn't exist here (this
--     addon's map Update() has no equivalent shared tick counter) -
--     an AceTimer repeating timer serves the same "don't do this
--     every single frame" purpose.
--   - Nx.Map:MinimapDetachFrms's OWN continuous mm:GetChildren() scan
--     (MapEngine.lua:3803-3907, separate from the Dock's one-time
--     EnumerateFrames sweep - catches buttons that get parented
--     directly to Minimap after the dock already exists) IS ported
--     here, folded into Scan() below instead of kept as a separate
--     function, since this addon has no equivalent "MMOwnedFrms"
--     bookkeeping table split across two objects to preserve.

local AlchemyGPS = _G.AlchemyGPS

local MinimapDock = AlchemyGPS.Modules.Map and AlchemyGPS.Modules.Map.MinimapDock or {}
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}
AlchemyGPS.Modules.Map.MinimapDock = MinimapDock

-- Real source's mmOwnerNames (MapEngine.lua:15979-15981), minus
-- "NXMiniMapBut" (Carbonite's own launcher button - no equivalent
-- here) - reordered (not resorted from the real source's own order)
-- so the calendar/clock/mail trio Scan() always finds first lands
-- first in self.Frms too, i.e. right after Create()'s drag handle
-- (requested live, 2026-11-09: "add the clock the calendar button
-- and a mail notifier under the square we use to move it"). Layout()
-- skips any entry that isn't currently IsShown() (MiniMapMailFrame in
-- particular only shows with unread mail), so the bar just shrinks/
-- grows around whichever of the three are actually present, no gap
-- left behind.
local KNOWN_NAMES = {
    "GameTimeFrame", "TimeManagerClockButton", "MiniMapMailFrame",
    "MiniMapWorldMapButton", "MiniMapTracking", "MiniMapVoiceChatFrame",
    "QueueStatusMinimapButton", "MiniMapInstanceDifficulty",
    "GarrisonLandingPageMinimapButton", "MiniMapLFGFrame",
}

-- Real source's excludeFrames (MapEngine.lua:3860) PLUS the real
-- source's separate self.AddonMinimapNames list (MapEngine.lua:315-
-- 324) - that one isn't an exclude list in the real source, it's the
-- recognize list for a whole separate subsystem (world-map POI pins
-- for gathering/questing addons, drawn at their real coordinates on
-- Carbonite's own big map) this addon hasn't built. Without that
-- subsystem to claim them first, these pins fall through to the
-- Dock's own "anchored to Minimap but parented elsewhere" sweep like
-- any other button would - and unlike a real button, a node pin's
-- owning addon re-SetPoints it to Minimap every single frame to track
-- player position/rotation, fighting our own reparent-to-the-dock
-- every time ScanChildren()/Layout() tick. Confirmed live, 2026-11-10:
-- GatherMate2 node pins flashing between the map and the icon bar -
-- exactly that tug-of-war. Excluding the name here (GatherMatePin)
-- stops the Dock from ever claiming them in the first place; the rest
-- of Carbonite's own recognize-list names are included pre-emptively
-- for the same reason, even though only GatherMate2 was confirmed.
local EXCLUDE_NAME_PATTERNS = {
    "HandyNotesPin", "QuestieFrame", "GatherNote", "GatherMatePin",
    "MobMapMinimapDot_", "CartographerNotesPOI", "RecipeRadarMinimapIcon",
    "NauticusMiniIcon", "ZGVMarkerMini",
}

local ICON_SPACING = 30
local BASE_X = 15
local BASE_Y = 15
local HANDLE_SIZE = 16

local function isExcluded(f)
    local name = f:GetName()
    if not name then return false end
    for _, pat in ipairs(EXCLUDE_NAME_PATTERNS) do
        if name:find(pat, 1, true) then return true end
    end
    return false
end

-- Kept verbatim from Nx.Map:SetChildLevels (MapEngine.lua:2201-2213) -
-- bumps a button's own nested children (icon texture, cooldown swipe,
-- count text, etc.) to the same frame level as the button itself.
local function setChildLevels(frm, lvl)
    for _, child in ipairs({ frm:GetChildren() }) do
        child:SetFrameLevel(lvl)
        if child:GetNumChildren() > 0 then
            setChildLevels(child, lvl + 1)
        end
    end
end

function MinimapDock:Create()
    if self.Win then return end

    local f = CreateFrame("Frame", "AlchemyGPSDock", UIParent)
    f:SetSize(HANDLE_SIZE, HANDLE_SIZE)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetFrameStrata("MEDIUM")

    local saved = AlchemyGPS.db and AlchemyGPS.db.profile and AlchemyGPS.db.profile.DockPosition
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x, saved.y)
    else
        -- Roughly the real source's own default spot (MapEngine.lua
        -- :15954, 45px in from the right edge, 8% of screen height
        -- down from the top) - no longer driven by Window:
        -- InitLayoutData's percent-or-pixel convention since that
        -- class isn't used here any more, just a fixed pixel default.
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -45, -60)
    end

    -- Small grab-handle icon at the bar's leading edge (TOPLEFT corner
    -- - "front" for either orientation: the left end of a row, or the
    -- top of a column) - the bar's one visible, clickable element.
    -- Drag it to move the whole bar; nothing else on the bar responds
    -- to the mouse at all. Blizzard's own window-drag cursor icon, not
    -- a custom asset - every WoW client ships it, and it already
    -- reads as "grab this" at a glance.
    local handle = CreateFrame("Button", nil, f)
    handle:SetSize(HANDLE_SIZE, HANDLE_SIZE)
    handle:SetPoint("CENTER", f, "TOPLEFT", BASE_X, -BASE_Y)
    local tex = handle:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(handle)
    tex:SetTexture("Interface\\Cursor\\UI-Cursor-Move")
    handle:SetHighlightTexture("Interface\\Cursor\\UI-Cursor-Move")
    handle:GetHighlightTexture():SetBlendMode("ADD")
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() f:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        AlchemyGPS.db.profile.DockPosition = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    self.Handle = handle

    self.Win = f

    self.OwnedFrms = {}
    self.Frms = {}

    self:Scan()

    -- Real source's own 3-second delay before the one-time full sweep
    -- (MapEngine.lua:15962) - gives slower-loading addons' minimap
    -- buttons a chance to exist first.
    AlchemyGPS:ScheduleTimer(function() self:Scan() end, 3)

    -- Real source's continuous mm:GetChildren() scan + grid layout are
    -- two separate throttled passes (MapEngine.lua:3803-3907 vs.
    -- :16090-16238); one repeating timer covers both here.
    self.UpdateTicker = AlchemyGPS:ScheduleRepeatingTimer(function()
        self:ScanChildren()
        self:Layout()
    end, 1)
end

-- Split out of Scan() so ScanChildren()'s own continuous 1-second
-- pass can retry it too, not just Scan()'s one-time immediate+3s-
-- later pair. Confirmed live, 2026-11-10: the clock/calendar/mail
-- trio only showed up after manually toggling the Blizzard minimap
-- on/off a few times, sometimes not the first toggle either - those
-- three globals don't always exist yet at either of Scan()'s two
-- fixed checkpoints (Blizzard's own FrameXML appears to finish
-- creating them lazily, on some later event neither checkpoint
-- lines up with), and nothing used to re-check KNOWN_NAMES after
-- that. Cheap enough (a handful of global-table lookups) to just run
-- every tick alongside ScanChildren() until each name resolves - the
-- owned[] guard already makes it a no-op once it has.
function MinimapDock:ScanKnownNames()
    local owned = self.OwnedFrms
    for _, name in ipairs(KNOWN_NAMES) do
        local f = _G[name]
        if f and not owned[f] then
            owned[f] = true
            table.insert(self.Frms, f)
        end
    end
end

-- Trimmed from Nx.Map.Dock:MinimapOwnInit's full sweep (MapEngine.lua
-- :15972-16068) - same two real passes (known global names, then
-- every live frame anchored to Minimap via SetPoint but parented
-- elsewhere), minus the CT_Core-specific texture match (see file
-- header).
function MinimapDock:Scan()
    local mm = _G["Minimap"]
    if not mm then return end

    self:ScanKnownNames()

    local owned = self.OwnedFrms
    local mapFrm = AlchemyGPS.Modules.Map.MinimapEngine and AlchemyGPS.Modules.Map.MinimapEngine.Frm
    local winFrm = self.Win

    local f = EnumerateFrames()
    while f do
        if f ~= mm and not owned[f] and not f:IsObjectType("Model") then
            local ok, pt, relTo = pcall(f.GetPoint, f)
            if ok and relTo == mm then
                local parent = f:GetParent()
                if parent ~= mm and parent ~= mapFrm and parent ~= winFrm and not isExcluded(f) then
                    owned[f] = true
                    table.insert(self.Frms, f)
                end
            end
        end
        f = EnumerateFrames(f)
    end
end

-- Trimmed from Nx.Map:MinimapDetachFrms's continuous half
-- (MapEngine.lua:3819-3898) - catches buttons parented directly to
-- Minimap after Scan()'s one-time sweep already ran (late-loading
-- addons). Cheap (just mm's direct children, not a full
-- EnumerateFrames sweep), so safe to run every tick of the repeating
-- timer. Also retries ScanKnownNames() every tick here (see that
-- function's header) for the same "late-loading" reason.
--
-- BUG FIX 2026-11-10: this pass never applied isExcluded() at all -
-- only Scan()'s EnumerateFrames half did. GatherMate2's node pins are
-- direct children of Minimap (not "anchored to Minimap but parented
-- elsewhere", the case Scan() guards), so this pass was the one
-- actually grabbing them every second regardless of the exclude list,
-- fighting GatherMate's own continuous re-anchor-to-Minimap and
-- causing the reported flashing between the map and the icon bar.
function MinimapDock:ScanChildren()
    self:ScanKnownNames()

    local mm = _G["Minimap"]
    if not mm then return end

    local owned = self.OwnedFrms

    for _, child in ipairs({ mm:GetChildren() }) do
        if child:IsShown() and not owned[child] and child:IsObjectType("Frame") and not isExcluded(child) then
            owned[child] = true
            table.insert(self.Frms, child)
        end
    end
end

-- Trimmed from Nx.Map.Dock:MinimapDetachFrms (MapEngine.lua:16090-
-- 16238) - same per-icon scale-normalize and CENTER/TOPLEFT anchor
-- math, fixed to a single line (row or column, never wrapping) that
-- grows unbounded in one direction instead of the real source's
-- configurable corner/column-count/spacing grid (no Settings UI for
-- those yet) - a single line is what actually docks cleanly against
-- another window's edge, which a multi-row grid doesn't. Row vs.
-- column is the one option this addon DOES expose (AlchemyGPS.db.
-- profile.DockOrientation, Settings window's "Icon bar: vertical
-- column" checkbox) - the real source has no row/column toggle at
-- all, only a 4-corner start-point choice that still wraps into a
-- grid. Slot 0 in the line is reserved for Create()'s drag handle -
-- icons start at slot 1 - and the bar's own frame is never resized
-- to fit them (no backdrop to size-fit any more, and un-clipped
-- children render fine past their parent's declared bounds), unlike
-- the real source's win:SetSize(34, 11)-per-layout-pass behavior.
function MinimapDock:IsVertical()
    return AlchemyGPS.db and AlchemyGPS.db.profile
        and AlchemyGPS.db.profile.DockOrientation == "Column"
end

function MinimapDock:Layout()
    local win = self.Win
    if not win then return end

    local butLvl = win:GetFrameLevel() + 1
    local strata = win:GetFrameStrata()
    local vertical = self:IsVertical()

    local n = 1

    -- Gated on IsShown(), NOT IsVisible() like the real source's own
    -- check (MapEngine.lua:16150) - deliberately diverges, fixed
    -- 2026-11-10 after tracing a real deadlock this addon creates for
    -- itself: GameTimeFrame/TimeManagerClockButton/MiniMapMailFrame
    -- are children of MinimapCluster, a SIBLING of Minimap, not a
    -- descendant of it. The real source never hides that whole
    -- cluster (confirmed by its own source - only ever reparents/
    -- hides Minimap itself), so IsVisible() tracking their real
    -- ancestor is fine there. Our own NativeMinimapHide.lua DOES hide
    -- the whole cluster though (simpler, but collateral damage to
    -- every other child riding along) - while it's hidden, these
    -- three are IsShown()==true (their own flag) but
    -- IsVisible()==false (inherited from the hidden ancestor), and
    -- IsVisible() was exactly the condition gating the SetParent(win)
    -- call below that would rescue them onto our always-visible dock -
    -- a catch-22 they could never climb out of on their own. Gating
    -- on IsShown() instead breaks it: reparents them the moment
    -- they're first discovered regardless of the stale ancestor,
    -- which is what actually fixes their visibility. Confirmed live:
    -- they previously only ever appeared after manually toggling the
    -- Blizzard minimap on/off, since only an actual
    -- MinimapCluster:Show() made IsVisible() briefly true long enough
    -- for a Layout() tick to catch it.
    for _, f in ipairs(self.Frms) do
        if f:IsShown() then
            local w = f:GetWidth()
            if w and w > 0 then
                local sc = 32 / math.max(w, 32)
                local x = vertical and BASE_X or (BASE_X + n * ICON_SPACING)
                local y = vertical and (BASE_Y + n * ICON_SPACING) or BASE_Y

                f:SetParent(win)
                f:ClearAllPoints()
                f:SetPoint("CENTER", win, "TOPLEFT", x / sc, -y / sc)
                f:SetScale(sc)
                f:SetFrameStrata(strata)
                f:SetFrameLevel(butLvl)
                setChildLevels(f, butLvl + 1)

                n = n + 1
            else
                -- Real source's own fix for a specific addon
                -- (Outfitter) whose minimap button goes invisible
                -- without this nudge (MapEngine.lua:16206-16209) -
                -- width not resolved yet; Layout()'s next tick
                -- retries once it is.
                f:Show()
            end
        end
    end
end
