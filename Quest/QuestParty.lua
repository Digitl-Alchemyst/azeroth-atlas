---------------------------------------------------------------------------------------
-- Alchemy GPS | Quest/QuestParty.lua
--
-- 2026-11-16 (user request: "we want to see how many group members and
-- which ones are on the same quest we are on in both the list and
-- tracker"). Which party / raid members have a quest in their log:
--   * the game's own C_QuestLog.IsUnitOnQuest(unit, questID) - works for
--     everyone in the group, addon or not (Carbonite.Quests uses it too)
--   * and, for anything the game won't say (an answer it hides as a
--     secret value, a member out of range), the quest ids other Alchemy
--     GPS users share over the group channel.
-- QuestList / QuestTracker put the count after the title ("[2]") and
-- the names in the tooltip (Party:Badge, Party:AddTooltip). Fires
-- QUEST_PARTY_CHANGED when the answer may have changed.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest

local Party = {}
Q.Party = Party

local PREFIX = "AlchemyGPS1"
local SEND_GAP = 3          -- seconds between two quest-list messages of ours
local CHUNK = 220           -- addon messages carry at most 255 bytes
local SHARED_TTL = 300      -- forget a member's shared list after this long
local BADGE = "|cff80c8ff[%d]|r"

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function groupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- The group's units other than the player.
local function groupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not UnitIsUnit(u, "player") then list[#list + 1] = u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then list[#list + 1] = u end
        end
    end
    return list
end

local function unitName(unit)
    local first, last = UnitName(unit)
    if not readable(first) or first == "" then return nil end
    if readable(last) and last ~= "" then return first .. " " .. last end
    return first
end

---------------------------------------------------------------------------------------
-- Shared lists (other Alchemy GPS users)
---------------------------------------------------------------------------------------

-- [first name] = { set = { [questID] = true }, t, pending = { ... } }
local shared = {}

local function senderBase(sender)
    return readable(sender) and sender:match("^([^%-]+)") or nil
end

local lastSent, lastSentAt, sendQueued = nil, 0, false
local function sendQuests()
    sendQueued = false
    local channel = groupChannel()
    if not channel or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        lastSent = nil
        return
    end
    local State = Q.State
    local ids = {}
    for _, q in ipairs(State and State.Quests or {}) do ids[#ids + 1] = q.questID end
    table.sort(ids)
    local all = table.concat(ids, ",")
    if all == lastSent and GetTime() - lastSentAt < SHARED_TTL / 2 then return end
    lastSent, lastSentAt = all, GetTime()
    -- "Q|part|of|ids": parts make one list together; part 1 starts a new one.
    local parts, cur = {}, ""
    for _, id in ipairs(ids) do
        local add = (cur == "" and "" or ",") .. id
        if #cur + #add > CHUNK then
            parts[#parts + 1] = cur
            cur = tostring(id)
        else
            cur = cur .. add
        end
    end
    parts[#parts + 1] = cur
    for i, p in ipairs(parts) do
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, ("Q|%d|%d|%s"):format(i, #parts, p), channel)
    end
end

local function queueSend()
    if sendQueued then return end
    sendQueued = true
    local wait = math.max(0.5, SEND_GAP - (GetTime() - lastSentAt))
    C_Timer.After(wait, function() pcall(sendQuests) end)
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local function onMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not GROUP_CHANNELS[channel] or not readable(msg) then return end
    local kind, part, total, list = strsplit("|", msg)
    if kind ~= "Q" then return end
    local base = senderBase(sender)
    if not base or base == UnitName("player") then return end
    part, total = tonumber(part), tonumber(total)
    if not part or not total then return end
    local e = shared[base] or {}
    shared[base] = e
    if part == 1 then e.pending = {} end
    e.pending = e.pending or {}
    for id in (list or ""):gmatch("%d+") do e.pending[tonumber(id)] = true end
    if part == total then
        e.set, e.pending, e.t = e.pending, nil, GetTime()
        Party:Changed()
    end
end

---------------------------------------------------------------------------------------
-- Who's on a quest
---------------------------------------------------------------------------------------

local cache, cacheSerial = {}, 0

function Party:Changed()
    wipe(cache)
    cacheSerial = cacheSerial + 1
    EventBus:Fire("QUEST_PARTY_CHANGED")
end

-- { { name, class }, ... } of group members with this quest, sorted.
function Party:GetMembers(questID)
    if not questID or not IsInGroup() then return nil end
    local hit = cache[questID]
    if hit then return hit end
    local list, seen = {}, {}
    local api = C_QuestLog and C_QuestLog.IsUnitOnQuest
    local now = GetTime()
    for _, unit in ipairs(groupUnits()) do
        local base = UnitName(unit)
        local on
        if api then
            local ok, r = pcall(api, unit, questID)
            if ok and readable(r) then on = r and true or false end
        end
        if on == nil and readable(base) then
            local e = shared[base]
            if e and e.set and now - (e.t or 0) < SHARED_TTL then on = e.set[questID] and true or false end
        end
        if on and readable(base) and not seen[base] then
            seen[base] = true
            local _, class = UnitClass(unit)
            list[#list + 1] = { name = unitName(unit) or base, class = class }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    cache[questID] = list
    return list
end

-- " [2]" after a title when anyone else in the group has the quest.
function Party:Badge(questID)
    local list = self:GetMembers(questID)
    if not list or #list == 0 then return "" end
    return " " .. BADGE:format(#list)
end

function Party:AddTooltip(questID)
    local list = self:GetMembers(questID)
    if not list or #list == 0 then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Also on this quest (%d):"):format(#list), 0.5, 0.78, 1)
    for _, m in ipairs(list) do
        local c = m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
        GameTooltip:AddLine("  " .. m.name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
local changePending = false
local function changedSoon()
    if changePending then return end
    changePending = true
    C_Timer.After(1, function()
        changePending = false
        Party:Changed()
    end)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        pcall(onMessage, ...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then wipe(shared) end
        lastSent = nil          -- someone new may need our list
        queueSend()
        changedSoon()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        local unit = ...
        if unit == "player" then queueSend() end
        changedSoon()
    elseif event == "QUEST_LOG_UPDATE" then
        queueSend()
    else
        queueSend()
        changedSoon()
    end
end)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end
