-- Alchemy GPS | Quest / QuestState
-- The live half of the quest picture: what is in the log right now,
-- how far along each objective is, which quests are on the tracker.
-- Event-driven - a burst of quest-log events collapses into one rescan
-- a moment later, and consumers hear about it once, through the
-- "QUEST_STATE_CHANGED" EventBus message, only when something they can
-- see actually changed.
--
-- New code (not a port): Carbonite's equivalent is the CurQ/RealQ
-- machinery in BlizzardLog.lua, tangled into its own watch-window and
-- party-sharing state. What it shares with that code is the approach -
-- read Blizzard's log, never cache what Blizzard owns for longer than
-- one scan.
--
-- Quest record:
--   questID, title, level, header (log category), logIndex,
--   group      the zone or dungeon it is filed under - the header, or
--              "Other" when the log never showed us one
--   isComplete, isFailed, frequency, suggestedGroup,
--   objectives = { {text=, finished=, numFulfilled=, numRequired=}, ... },
--   ready      = true when there is nothing left to do but turn it in
--                (complete, or a quest with no objectives at all)
--
-- "Tracked" here means "shown on our tracker", and is this addon's own
-- per-character list, independent of Blizzard's watch list: every quest
-- is tracked unless the player untracked it (Shift-click on the
-- tracker). Missing means tracked, so a newly accepted quest shows up
-- without any bookkeeping.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest
local Api = Q.Api

local State = {}
Q.State = State

State.Quests = {}       -- log order
State.ById = {}
State.Serial = 0        -- bumps on every visible change

local EVENTS = {
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_WATCH_UPDATE",
    "UNIT_QUEST_LOG_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
}

-- Quest-log events arrive in bursts (one objective tick can fire
-- several); wait this long after the last one before rescanning.
local RESCAN_DELAY = 0.25

State.NO_GROUP = "Other"

function State:Start()
    if self.Frame then return end
    local frame = CreateFrame("Frame")
    self.Frame = frame
    for _, event in ipairs(EVENTS) do
        Q.Core:SafeRegisterEvent(frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEVEL_UP" then
            -- Nothing in the log changes, but what is trivial and what
            -- is newly available does.
            self.LevelSerial = (self.LevelSerial or 0) + 1
        end
        self:MarkDirty()
    end)
    self:MarkDirty()
end

function State:MarkDirty()
    local frame = self.Frame
    if not frame then return end
    self.DirtyFor = 0
    if self.Waiting then return end
    self.Waiting = true
    frame:SetScript("OnUpdate", function(f, elapsed)
        self.DirtyFor = self.DirtyFor + elapsed
        if self.DirtyFor >= RESCAN_DELAY then
            f:SetScript("OnUpdate", nil)
            self.Waiting = false
            self:Scan()
        end
    end)
end

local function copyObjectives(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for i, o in ipairs(raw) do
        out[i] = {
            text = (type(o.text) == "string" and o.text) or "",
            finished = o.finished and true or false,
            numFulfilled = o.numFulfilled,
            numRequired = o.numRequired,
        }
    end
    return out
end

local function finishRecord(q, rawObjectives)
    q.objectives = copyObjectives(rawObjectives)
    -- A quest Blizzard gave no objective list for at all (the call
    -- failed) is only "ready" if flagged complete; one with an empty
    -- list is a plain delivery quest, ready from the moment it's taken.
    q.ready = q.isComplete or (type(rawObjectives) == "table" and #q.objectives == 0)
    return q
end

function State:Scan()
    local quests, byId = {}, {}
    local Catalog = Q.Catalog

    local numEntries = Api:GetNumEntries() or 0
    local header
    for index = 1, numEntries do
        local e = Api:GetEntry(index)
        if e then
            if e.isHeader then
                header = e.title
            elseif e.questID and e.questID > 0 and not e.isHidden and not byId[e.questID] then
                local q = finishRecord({
                    questID = e.questID,
                    title = e.title or (Catalog and Catalog:GetName(e.questID)) or ("Quest " .. e.questID),
                    level = e.level or 0,
                    header = header,
                    logIndex = index,
                    isComplete = e.isComplete,
                    isFailed = e.isFailed,
                    frequency = e.frequency,
                    suggestedGroup = e.suggestedGroup,
                }, Api:GetObjectives(e.questID, index))
                quests[#quests + 1] = q
                byId[q.questID] = q
            end
        end
    end

    -- Quests under a collapsed log header aren't enumerated above. Any
    -- quest seen on an earlier scan that the client still says we're
    -- on is kept, read by id instead of by row.
    -- Their zone heading is whatever it was when last seen.
    local headers = Q.Core:Char("Headers")
    for _, q in ipairs(quests) do
        if q.header and q.header ~= "" then headers[q.questID] = q.header end
    end

    local known = Q.Core:Char("Known")
    for questID in pairs(known) do
        if not byId[questID] then
            if Api:IsOnQuest(questID) == true then
                local h = Catalog and Catalog:GetHeader(questID)
                local q = finishRecord({
                    questID = questID,
                    title = Api:GetTitle(questID) or (h and h.name) or ("Quest " .. questID),
                    level = h and h.level or 0,
                    header = headers[questID],
                    logIndex = 0,
                    isComplete = Api:IsComplete(questID),
                    isFailed = Api:IsFailed(questID),
                }, Api:GetObjectives(questID, 0))
                quests[#quests + 1] = q
                byId[questID] = q
            else
                known[questID] = nil
            end
        end
    end
    for questID, q in pairs(byId) do
        known[questID] = true
        q.group = (q.header and q.header ~= "" and q.header) or self.NO_GROUP
    end

    -- Untracked/collapsed flags for quests no longer in the log are
    -- just clutter in the saved file.
    for _, key in ipairs({ "Unwatched", "Collapsed", "Headers", "ListOpen", "ColorSlots" }) do
        local set = Q.Core:Char(key)
        for questID in pairs(set) do
            if not byId[questID] then set[questID] = nil end
        end
    end

    local parts = {}
    for _, q in ipairs(quests) do
        parts[#parts + 1] = q.questID
        parts[#parts + 1] = q.isComplete and "C" or (q.isFailed and "F" or "-")
        parts[#parts + 1] = q.title
        parts[#parts + 1] = q.group
        for _, o in ipairs(q.objectives) do
            parts[#parts + 1] = o.finished and "+" or "."
            parts[#parts + 1] = o.text
        end
    end
    parts[#parts + 1] = self.LevelSerial or 0
    local signature = table.concat(parts, "\031")

    self.Quests, self.ById = quests, byId
    self.Scanned = true
    if signature ~= self.Signature then
        self.Signature = signature
        self.Serial = self.Serial + 1
        EventBus:Fire("QUEST_STATE_CHANGED")
    end
end

---------------------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------------------

function State:GetQuest(questID)
    return self.ById[questID]
end

function State:IsInLog(questID)
    return self.ById[questID] ~= nil
end

function State:IsComplete(questID)
    local q = self.ById[questID]
    return q ~= nil and q.isComplete
end

function State:GetObjectiveProgress(questID)
    local q = self.ById[questID]
    return q and q.objectives or nil
end

function State:IsWatched(questID)
    return not Q.Core:Char("Unwatched")[questID]
end

-- Tracked quests, in log order. A fresh list each call; callers sort it.
function State:GetWatchedQuests()
    local unwatched = Q.Core:Char("Unwatched")
    local list = {}
    for _, q in ipairs(self.Quests) do
        if not unwatched[q.questID] then list[#list + 1] = q end
    end
    return list
end

function State:GetNumUnwatched()
    local unwatched = Q.Core:Char("Unwatched")
    local n = 0
    for _, q in ipairs(self.Quests) do
        if unwatched[q.questID] then n = n + 1 end
    end
    return n
end

function State:SetWatched(questID, watched)
    Q.Core:Char("Unwatched")[questID] = (not watched) and true or nil
    self.Serial = self.Serial + 1
    EventBus:Fire("QUEST_STATE_CHANGED")
end

-- Quests split by zone / dungeon heading, in the order given:
--   { {name=, quests={...}}, ... }
function State:GroupQuests(quests)
    local groups, byName = {}, {}
    for _, q in ipairs(quests) do
        local name = q.group or self.NO_GROUP
        local group = byName[name]
        if not group then
            group = { name = name, quests = {} }
            byName[name] = group
            groups[#groups + 1] = group
        end
        group.quests[#group.quests + 1] = q
    end
    return groups
end

-- Tracks or untracks every quest filed under one zone / dungeon
-- heading (nil: every quest in the log).
function State:SetGroupWatched(group, watched)
    local unwatched = Q.Core:Char("Unwatched")
    for _, q in ipairs(self.Quests) do
        if group == nil or q.group == group then
            unwatched[q.questID] = (not watched) and true or nil
        end
    end
    self.Serial = self.Serial + 1
    EventBus:Fire("QUEST_STATE_CHANGED")
end

function State:WatchAll()
    local unwatched = Q.Core:Char("Unwatched")
    for questID in pairs(unwatched) do unwatched[questID] = nil end
    self.Serial = self.Serial + 1
    EventBus:Fire("QUEST_STATE_CHANGED")
end
