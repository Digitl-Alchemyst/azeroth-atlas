-- Azeroth Atlas | Quest / TrackerHider
-- Hides Blizzard's own quest tracker while this addon's tracker
-- replaces it, and puts it back exactly as it was when the option is
-- turned off.
--
-- Ported close to verbatim from Carbonite.Quests/TrackerHider.lua
-- (:22-270) - hiding this frame cleanly is a solved problem there
-- (which frame name each client generation uses, staying out of the
-- way of Edit Mode, never touching a protected frame in combat, the
-- hidden parent needing a real rect), and this project's standing rule
-- is to port that kind of thing rather than re-derive it. Changes:
--   - Nx.Quest methods became TrackerHider methods; the hide/show
--     decision reads this addon's own HideBlizzTracker option instead
--     of Carbonite's Quest.Enable + QuestWatch.HideBlizz pair.
--   - Nx.isRetail became a local IS_RETAIL (WOW_PROJECT_ID check). It
--     is false on WoW Forever, so the legacy reparent path is the one
--     that runs here; the retail state-driver path is kept so the file
--     stays a faithful, complete port.
--   - With the option off, a tracker this addon never hid is left
--     completely alone: no OnShow hook is installed on it and "restore"
--     does nothing. Carbonite hooks and force-shows it either way; a
--     player who keeps Blizzard's tracker should get Blizzard's
--     tracker, untouched.
--   - The driver doesn't listen for PLAYER_LOGIN: this module starts
--     after login (see Quest.lua's OnEnable) and applies immediately.
--   - The rest of Carbonite's file from :272 on (Nx.Quest:Init) is
--     Carbonite's own quest-engine setup, not tracker hiding.

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Q = AzerothAtlas.Modules.Quest

local TrackerHider = {}
Q.TrackerHider = TrackerHider

local InCombatLockdown = _G.InCombatLockdown
local RegisterStateDriver = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver

local IS_RETAIL = _G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE

-- BLIZZARD TRACKER HIDING (Retail + Classic + Anniversary + MoP Classic)
local TRACKER_FRAMES = {
    "ObjectiveTrackerFrame", -- Retail / modern
    "WatchFrame",            -- Classic / MoP Classic / Anniversary
    "QuestWatchFrame",       -- Fallback (some UI variants)
    "QuestTimerFrame",       -- Anniversary / Classic timed quests
}

-- ObjectiveTrackerFrame is an Edit Mode-managed Blizzard system on Retail.
-- It must not be reparented, have its alpha/mouse state altered, or get an
-- OnShow hook. Retail visibility is instead controlled through Blizzard's
-- secure visibility state driver. Legacy tracker frames retain the original
-- handling on Classic clients.
local function CanManage(name)
    if name == "ObjectiveTrackerFrame" and IS_RETAIL then
        return RegisterStateDriver ~= nil and UnregisterStateDriver ~= nil
    end
    return true
end

local function IsProtectedAndLockedDown(frame)
    return frame and frame.IsProtected and frame:IsProtected() and InCombatLockdown()
end

function TrackerHider:Init()
    if self.h then return end

    local hiddenParent = CreateFrame("Frame", nil, UIParent)
    -- The hider needs a valid rect: MoP Classic's Wrath-style
    -- WatchFrame_Update computes (WatchFrame:GetTop() -
    -- WatchFrame:GetParent():GetBottom()) on every quest-log event,
    -- even while the tracker is hidden. An unanchored, unsized parent
    -- has no rect, so GetBottom() returns nil and Blizzard's arithmetic
    -- errors out (WatchFrame.lua:471 "arithmetic on a nil value").
    hiddenParent:SetAllPoints(UIParent)
    hiddenParent:Hide()

    self.h = {
        hiddenParent = hiddenParent,
        hooked = {},
        orig = {},
        retailDriverHidden = false,
        retailOriginalAlpha = nil,
        pending = false,
    }

    local driver = CreateFrame("Frame", nil, UIParent)
    self.h.driver = driver

    Q.Core:SafeRegisterEvent(driver, "PLAYER_ENTERING_WORLD")
    Q.Core:SafeRegisterEvent(driver, "PLAYER_REGEN_ENABLED")
    Q.Core:SafeRegisterEvent(driver, "ADDON_LOADED")

    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not self.h.pending then
            return
        end
        self.h.pending = false
        self:Apply()
    end)
end

function TrackerHider:SetRetailVisible(frame, visible)
    local h = self.h
    if not h or not frame or not RegisterStateDriver or not UnregisterStateDriver then
        return
    end

    if InCombatLockdown() then
        h.pending = true
        return
    end

    if visible then
        if h.retailOriginalAlpha ~= nil then
            frame:SetAlpha(h.retailOriginalAlpha)
            h.retailOriginalAlpha = nil
        end
        if h.retailDriverHidden then
            -- Resolve "show" through Blizzard's secure driver before removing
            -- ours. This clears statehidden without calling the tracker's
            -- layout/update methods from addon execution.
            RegisterStateDriver(frame, "visibility", "show")
            UnregisterStateDriver(frame, "visibility")
            h.retailDriverHidden = false
        end
    elseif not h.retailDriverHidden then
        -- The secure state driver evaluates on a short timer. Blizzard can
        -- call Show() between evaluations while refreshing objectives during
        -- movement or taxi travel, which otherwise produces a visible flash.
        -- Alpha is a visual guard only: no script hook or layout method is
        -- installed, so Blizzard retains its normal update execution path.
        h.retailOriginalAlpha = frame:GetAlpha()
        frame:SetAlpha(0)
        RegisterStateDriver(frame, "visibility", "hide")
        h.retailDriverHidden = true
    end
end

function TrackerHider:ShouldHide()
    -- While Blizzard's Edit Mode is open the user almost certainly wants
    -- to position Blizzard's tracker frame, so let it show even if the
    -- hide preference is on. The hide is restored on Edit Mode exit via
    -- the EditMode.Enter / EditMode.Exit hooks.
    if self.editModeActive then
        return false
    end
    return Q.Core:Opt("HideBlizzTracker") == true
end

-- Hook Edit Mode events so the hider yields while the user is
-- positioning frames. The EventRegistry / EditModeManagerFrame check
-- makes this a no-op on clients without Edit Mode.
function TrackerHider:BindEditMode()
    if self.editModeBound then return end
    if not (_G.EventRegistry and _G.EditModeManagerFrame) then return end
    self.editModeBound = true
    _G.EventRegistry:RegisterCallback("EditMode.Enter", function()
        self.editModeActive = true
        self:Apply()
    end)
    _G.EventRegistry:RegisterCallback("EditMode.Exit", function()
        self.editModeActive = false
        self:Apply()
    end)
end

function TrackerHider:CaptureOriginal(frame, key)
    local h = self.h
    if not h or h.orig[key] then
        return
    end

    local mouseEnabled = true
    if frame.IsMouseEnabled then
        mouseEnabled = frame:IsMouseEnabled()
    end

    h.orig[key] = {
        parent = frame:GetParent(),
        alpha = frame:GetAlpha(),
        mouseEnabled = mouseEnabled,
    }
end

function TrackerHider:SetVisible(frame, key, visible)
    local h = self.h
    if not h or not frame then
        return
    end

    if IsProtectedAndLockedDown(frame) then
        h.pending = true
        return
    end

    if visible then
        -- Nothing was ever hidden: there is no original state to put
        -- back, and force-showing a tracker Blizzard itself is keeping
        -- hidden (no quests watched) would be a change, not a restore.
        local orig = h.orig[key]
        if not orig then
            return
        end

        frame:SetParent(orig.parent or UIParent)
        frame:SetAlpha(orig.alpha or 1)
        if frame.EnableMouse then
            frame:EnableMouse(orig.mouseEnabled ~= false)
        end
        h.orig[key] = nil

        -- Blizzard_QuestTimer owns whether QuestTimerFrame is shown: its
        -- Update method shows the frame only while GetQuestTimers() returns at
        -- least one active timer. Force-showing it here would leave an empty
        -- timer panel when the hide option is disabled. Refresh the Blizzard
        -- state after restoring the frame instead.
        if key == "QuestTimerFrame" then
            if type(frame.Update) == "function" then
                frame:Update()
            elseif frame.numTimers and frame.numTimers > 0 then
                frame:Show()
            else
                frame:Hide()
            end
        else
            frame:Show()
        end
        return
    end

    self:CaptureOriginal(frame, key)
    frame:SetParent(h.hiddenParent)
    frame:SetAlpha(0)
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    frame:Hide()
end

function TrackerHider:HookFrame(name)
    local h = self.h
    if not h or h.hooked[name] or not CanManage(name) then
        return
    end

    if name == "ObjectiveTrackerFrame" and IS_RETAIL then
        return
    end

    local frame = _G[name]
    if not frame or not frame.HookScript then
        return
    end

    h.hooked[name] = true
    frame:HookScript("OnShow", function(f)
        if self:ShouldHide() then
            self:SetVisible(f, name, false)
        end
    end)
end

function TrackerHider:Apply()
    if not self.h then
        self:Init()
    end

    -- Lazy-bind Edit Mode events; safe to call multiple times.
    self:BindEditMode()

    local hide = self:ShouldHide()

    for i = 1, #TRACKER_FRAMES do
        local name = TRACKER_FRAMES[i]
        local frame = _G[name]
        if frame and CanManage(name) then
            if name == "ObjectiveTrackerFrame" and IS_RETAIL then
                self:SetRetailVisible(frame, not hide)
            else
                if hide then self:HookFrame(name) end
                self:SetVisible(frame, name, not hide)
            end
        end
    end
end

function TrackerHider:Start()
    self:Apply()
    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(_, key)
        if key == "HideBlizzTracker" then self:Apply() end
    end)
end
