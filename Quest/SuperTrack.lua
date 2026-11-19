-- Azeroth Atlas | Quest / SuperTrack
-- Mirrors the routed quest into Blizzard's own "super-tracked quest"
-- (C_SuperTrack), so the native pieces that follow that value - the
-- world map's highlighted quest POI, the minimap's quest area - point
-- at the same quest our arrow does instead of at something else.
--
-- One-way on purpose: this addon tells Blizzard what it is routing to;
-- it does not adopt whatever Blizzard's UI super-tracks. Carbonite also
-- listens the other way (SuperTrack.lua's OnSuperTrackChanged, :702) to
-- feed its own target pipeline; with Blizzard's tracker hidden there is
-- little here that would change the value behind our back, and a
-- two-way sync is exactly where the two would start fighting.
--
-- The combat deferral is not optional. Carbonite flags the hazard in
-- two separate files (QuestRouting.lua:51-58, QuestWatchSurface.lua
-- :44-51): an insecure SetSuperTrackedQuestID call fires
-- SUPER_TRACKING_CHANGED in the addon's taint, and Blizzard's
-- QuestDataProvider reacts by calling the combat-protected
-- SetPassThroughButtons. So every mutation goes through
-- RunNowOrAfterCombat - run immediately out of combat, otherwise queue
-- until PLAYER_REGEN_ENABLED. Ported from Carbonite/Modules/
-- TaintlessHelpers/TaintlessHelpers.lua: CallBlizzardAPI (:36),
-- RunNowOrAfterCombat (:48), SetSuperTrackedQuestIDSafe (:90).
--
-- Every C_SuperTrack function is looked up at call time and
-- existence-checked: this client may not have the namespace at all, in
-- which case this whole file quietly does nothing.

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Q = AzerothAtlas.Modules.Quest

local SuperTrack = {}
Q.SuperTrack = SuperTrack

local securecallfunction = _G.securecallfunction

local function superTrackAPI(name)
    local st = _G.C_SuperTrack
    local fn = st and st[name]
    return type(fn) == "function" and fn or nil
end

local function CallBlizzardAPI(api, ...)
    if type(api) ~= "function" then return false end
    if securecallfunction then
        securecallfunction(api, ...)
    else
        api(...)
    end
    return true
end

local pending = {}
local combatFrame

local function RunNowOrAfterCombat(fn)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pending[#pending + 1] = fn
        return
    end
    fn()
end

function SuperTrack:IsAvailable()
    return superTrackAPI("SetSuperTrackedQuestID") ~= nil
end

-- Sets (questID) or clears (0/nil) the super-tracked quest. Returns
-- false if this client has no such API.
function SuperTrack:SetQuest(questID)
    local api = superTrackAPI("SetSuperTrackedQuestID")
    if not api then return false end
    questID = questID or 0

    -- Only the newest request matters; a stale one queued during a
    -- fight must not undo it afterwards.
    self.Wanted = questID
    RunNowOrAfterCombat(function()
        if self.Wanted ~= questID then return end
        local get = superTrackAPI("GetSuperTrackedQuestID")
        if get then
            local ok, current = pcall(get)
            if ok and (current or 0) == questID then return end
        end
        self.OwnQuestID = questID
        pcall(CallBlizzardAPI, api, questID)
    end)
    return true
end

-- Pushes the current route target (or "nothing") to Blizzard.
function SuperTrack:Sync()
    if not Q.Core:Opt("SuperTrackSync") then return end
    local target = Q.Routing and Q.Routing.Target
    local questID = target and target.kind == "quest" and target.questID or 0
    if questID == self.LastSynced then return end
    self.LastSynced = questID
    self:SetQuest(questID)
end

function SuperTrack:Start()
    if combatFrame then return end
    combatFrame = CreateFrame("Frame")
    Q.Core:SafeRegisterEvent(combatFrame, "PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function()
        if #pending == 0 then return end
        local queue = pending
        pending = {}
        for _, fn in ipairs(queue) do
            pcall(fn)
        end
    end)

    EventBus:Subscribe("QUEST_ROUTE_CHANGED", function()
        self:Sync()
    end)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(_, key, value)
        if key ~= "SuperTrackSync" then return end
        if value then
            self.LastSynced = nil
            self:Sync()
        elseif self.OwnQuestID and self.OwnQuestID ~= 0 then
            -- Turned off: hand back what we set, leave anything else alone.
            self.LastSynced = nil
            self:SetQuest(0)
        end
    end)
end
