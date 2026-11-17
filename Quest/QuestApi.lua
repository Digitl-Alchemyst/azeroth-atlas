-- Alchemy GPS | Quest / QuestApi
-- Version-tolerant access to the quest log. WoW Forever's client mixes
-- API generations (modern C_* namespaces next to classic-era content),
-- and this project has hit "that global doesn't exist here" three
-- times already, so nothing in the Quest module calls a quest-log API
-- directly - it goes through here, where each call is existence-
-- checked and falls back to the older equivalent.
--
-- Ported from Carbonite/Compat/Api.lua's Api.Quest section (:498-804),
-- which solves the same problem for the same client. Kept: log
-- enumeration, quest id <-> log index, objectives. Dropped: selection
-- and abandon helpers (this addon has no quest-log window). Added on
-- top, because the rest of the module needs one normalized answer:
-- GetEntry (a flat record whichever API produced it), IsComplete,
-- IsFlaggedCompleted, IsOnQuest, GetTitle.

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Quest = AlchemyGPS.Modules.Quest or {}

local Api = {}
AlchemyGPS.Modules.Quest.Api = Api

-- Captured once, at load: the legacy globals as Blizzard defined them.
local C_QuestLog = _G.C_QuestLog
local LegacyGetQuestLogTitle = _G.GetQuestLogTitle
local LegacyGetNumQuestLogEntries = _G.GetNumQuestLogEntries
local LegacyGetQuestLogIndexByID = _G.GetQuestLogIndexByID
local LegacyGetNumQuestLeaderBoards = _G.GetNumQuestLeaderBoards
local LegacyGetQuestLogLeaderBoard = _G.GetQuestLogLeaderBoard
local LegacyIsQuestFlaggedCompleted = _G.IsQuestFlaggedCompleted

local function modern(name)
    local fn = C_QuestLog and C_QuestLog[name]
    return type(fn) == "function" and fn or nil
end

-- Calls fn(...) and returns its first result, or nil if it threw. Quest
-- APIs on this client have errored on ids they don't know rather than
-- returning nil; a tracker row is never worth a Lua error popup.
local function try(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function LegacyQuestInfo(logIndex)
    if not LegacyGetQuestLogTitle then return nil end
    local title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
        frequency, questID = LegacyGetQuestLogTitle(logIndex)
    if title == nil then return nil end
    return {
        title = title,
        level = level,
        suggestedGroup = suggestedGroup,
        isHeader = isHeader,
        isCollapsed = isCollapsed,
        isComplete = isComplete,
        frequency = frequency,
        questID = questID,
    }
end

function Api:GetNumEntries()
    local fn = modern("GetNumQuestLogEntries")
    if fn then return fn() end
    if LegacyGetNumQuestLogEntries then return LegacyGetNumQuestLogEntries() end
    return 0, 0
end

-- Raw record for a log row, in whichever shape the client returns.
function Api:GetInfo(logIndex)
    if not logIndex then return nil end
    local fn = modern("GetInfo")
    if fn then return try(fn, logIndex) end
    return LegacyQuestInfo(logIndex)
end

-- Completion, for a quest in the log. The modern record has no
-- isComplete field (it is a separate call); the legacy one carries it
-- as 1 / -1 (failed) / nil.
function Api:IsComplete(questID, rawInfo)
    if rawInfo and rawInfo.isComplete ~= nil then
        local v = rawInfo.isComplete
        return v == true or v == 1
    end
    local fn = modern("IsComplete")
    if fn then return try(fn, questID) == true end
    local idx = self:GetLogIndexForQuestID(questID)
    local info = idx > 0 and LegacyQuestInfo(idx)
    return info ~= nil and info ~= false and info.isComplete == 1
end

function Api:IsFailed(questID, rawInfo)
    if rawInfo and rawInfo.isComplete == -1 then return true end
    local fn = modern("IsFailed")
    if fn then return try(fn, questID) == true end
    return false
end

-- One log row as a flat record the rest of the module can rely on:
-- title, level, questID, isHeader, isCollapsed, isComplete (bool),
-- isFailed (bool), isHidden, frequency, suggestedGroup. nil for a row
-- that doesn't exist.
function Api:GetEntry(logIndex)
    local info = self:GetInfo(logIndex)
    if type(info) ~= "table" then return nil end

    local entry = {
        title = info.title,
        level = info.level,
        questID = info.questID,
        isHeader = info.isHeader and true or false,
        isCollapsed = info.isCollapsed and true or false,
        isHidden = info.isHidden and true or false,
        frequency = info.frequency,
        suggestedGroup = info.suggestedGroup,
        isComplete = false,
        isFailed = false,
    }
    if not entry.isHeader and entry.questID and entry.questID > 0 then
        entry.isComplete = self:IsComplete(entry.questID, info)
        entry.isFailed = self:IsFailed(entry.questID, info)
    end
    return entry
end

function Api:GetQuestIDForLogIndex(logIndex)
    if not logIndex then return nil end
    local fn = modern("GetQuestIDForLogIndex")
    if fn then return try(fn, logIndex) end
    local info = LegacyQuestInfo(logIndex)
    return info and info.questID or nil
end

function Api:GetLogIndexForQuestID(questID)
    if not questID then return 0 end
    local fn = modern("GetLogIndexForQuestID")
    if fn then return try(fn, questID) or 0 end
    if LegacyGetQuestLogIndexByID then
        return LegacyGetQuestLogIndexByID(questID) or 0
    end
    local numEntries = self:GetNumEntries() or 0
    for index = 1, numEntries do
        if self:GetQuestIDForLogIndex(index) == questID then return index end
    end
    return 0
end

-- { {text=, finished=, numFulfilled=, numRequired=, type=}, ... } for a
-- quest in the log, or nil. The by-id call is preferred because it
-- keeps working for quests sitting under a collapsed log header.
function Api:GetObjectives(questID, logIndex)
    if not questID or questID <= 0 then return nil end

    local fn = modern("GetQuestObjectives")
    if fn then
        local objectives = try(fn, questID)
        if type(objectives) == "table" then return objectives end
    end

    logIndex = logIndex or self:GetLogIndexForQuestID(questID)
    if not logIndex or logIndex <= 0 or not LegacyGetNumQuestLeaderBoards
        or not LegacyGetQuestLogLeaderBoard then
        return nil
    end

    local objectives = {}
    for i = 1, LegacyGetNumQuestLeaderBoards(logIndex) or 0 do
        local text, objectiveType, finished = LegacyGetQuestLogLeaderBoard(i, logIndex)
        objectives[i] = {
            text = text,
            type = objectiveType,
            finished = finished and true or false,
        }
    end
    return objectives
end

-- Has this character ever turned the quest in?
function Api:IsFlaggedCompleted(questID)
    local fn = modern("IsQuestFlaggedCompleted") or LegacyIsQuestFlaggedCompleted
    return try(fn, questID) == true
end

-- Is the quest in the log right now? nil when the client can't say
-- (no by-id call), so callers can tell "no" from "unknown".
function Api:IsOnQuest(questID)
    local fn = modern("IsOnQuest")
    if fn then return try(fn, questID) == true end
    if LegacyGetQuestLogIndexByID then
        return (LegacyGetQuestLogIndexByID(questID) or 0) > 0
    end
    return nil
end

function Api:GetTitle(questID)
    local title = try(modern("GetTitleForQuestID"), questID)
    if type(title) == "string" and title ~= "" then return title end
    title = try(modern("GetQuestInfo"), questID)
    if type(title) == "string" and title ~= "" then return title end
    return nil
end

-- Live quest POIs Blizzard publishes for a map:
-- { {questID=, x=0..1, y=0..1}, ... } or nil.
function Api:GetQuestsOnMap(mapID)
    local list = try(modern("GetQuestsOnMap"), mapID)
    return type(list) == "table" and list or nil
end

-- Blizzard's own "next step" waypoint for a quest: mapID, x, y (0..1).
function Api:GetNextWaypoint(questID)
    local fn = modern("GetNextWaypoint")
    if not fn then return nil end
    local ok, mapID, x, y = pcall(fn, questID)
    if ok and mapID and x and y then return mapID, x, y end
    return nil
end
