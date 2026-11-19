-- Azeroth Atlas | Quest / QuestRules
-- "Could this character pick this quest up right now?" - and the other
-- things Quest/Data/QuestDBRules.lua knows that the Carbonite rows
-- don't: quests started by a dropped item, the paths wandering quest
-- givers walk, and the items quests hand you to use.
--
-- The pickup rules are a port of Questie's QuestieDB.IsDoable
-- (Questie/Database/QuestieDB.lua), reading the same fields, which
-- Tools/gen_quest_rules.py packs into one short string per quest:
--
--   s  any one of these quests turned in     g  all of them turned in
--   x  none of these turned in or in the log (mutually exclusive)
--   p  this quest in the log                 n  follow-up not done/taken
--   b  a breadcrumb for this quest, which must not be done/taken
--   l / L  level at least / at most          r  race mask
--   k  profession skill                      m / M  reputation floor / cap
--   c  a spell known (negative: not known)
--
-- Before this, the only chain knowledge was Carbonite's QuestPrev (the
-- reverse of each row's "next quest" link), which knows one predecessor
-- per quest and nothing about a giver's later steps: every quest in a
-- chain showed as available at once. QuestPrev is still used, but only
-- for the handful of quests QuestieDB has no record of.

local AzerothAtlas = _G.AzerothAtlas
local Q = AzerothAtlas.Modules.Quest
local Api = Q.Api

local QuestData = AzerothAtlas.QuestData or {}
local RuleData = QuestData.Rules or {}
-- 2026-11-19: hand-written rules (Quest/Data/QuestDBManual.lua) win.
for questID, packed in pairs(QuestData.ManualRules or {}) do RuleData[questID] = packed end
local StartItemData = QuestData.StartItems or {}
local PatrolData = QuestData.Patrols or {}
local QuestItemData = QuestData.QuestItems or {}
local Prev = QuestData.Prev or {}

local Rules = {}
Q.Rules = Rules

-- Bumps when something a rule reads changes outside the quest log (a
-- profession, a reputation), so cached pickup lists know to rebuild.
Rules.Serial = 0

local tonumber, floor = tonumber, math.floor

---------------------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------------------

local LIST_KEYS = { s = true, g = true, x = true }
local PAIR_KEYS = { k = true, m = true, M = true }
local parsed = {}

local function rule(questID)
    local r = parsed[questID]
    if r == nil then
        r = false
        local packed = RuleData[questID]
        if packed == "?" then
            r = { unknown = true }
        elseif packed then
            r = {}
            for key, value in packed:gmatch("(%a)=([^;]+)") do
                if LIST_KEYS[key] then
                    local list = {}
                    for id in value:gmatch("%d+") do list[#list + 1] = tonumber(id) end
                    r[key] = list
                elseif PAIR_KEYS[key] then
                    local a, b = value:match("^(%-?%d+):(%-?%d+)$")
                    if a then r[key] = { tonumber(a), tonumber(b) } end
                else
                    r[key] = tonumber(value)
                end
            end
        end
        parsed[questID] = r
    end
    return r or nil
end

---------------------------------------------------------------------------------------
-- What the character is
---------------------------------------------------------------------------------------

-- QuestieDB's race bits (src/corrections/enum/expansions.lua): race id
-- n is bit n-1 for the original races, with the later ones listed.
local RACE_BIT = {
    [22] = 2 ^ 21, [24] = 2 ^ 23, [25] = 2 ^ 24, [26] = 2 ^ 25, [95] = 2 ^ 32, [96] = 2 ^ 33,
}

local function raceBit()
    local bit = Rules._raceBit
    if bit == nil then
        local _, _, raceID = UnitRace("player")
        bit = raceID and (RACE_BIT[raceID] or (raceID <= 11 and 2 ^ (raceID - 1))) or false
        Rules._raceBit = bit
    end
    return bit or nil
end

-- { [skillLineId] = rank } for every skill the character has, or nil
-- when this client can't list skills by id.
local function skills()
    local t = Rules._skills
    if t == nil then
        t = false
        local info = _G.C_SkillInfo
        if info and info.GetNumSkillLines and info.GetSkillLineInfo then
            local ok, n = pcall(info.GetNumSkillLines)
            if ok and type(n) == "number" then
                t = {}
                for i = 1, n do
                    local ok2, line = pcall(info.GetSkillLineInfo, i)
                    if ok2 and type(line) == "table" and line.skillID and not line.isHeader then
                        t[line.skillID] = line.rank or 0
                    end
                end
            end
        end
        Rules._skills = t
    end
    return t or nil
end

-- Current reputation value with a faction, or nil if the character
-- hasn't met it.
local function standing(factionID)
    local rep = _G.C_Reputation
    if rep and rep.GetFactionDataByID then
        local ok, d = pcall(rep.GetFactionDataByID, factionID)
        if ok and type(d) == "table" then return d.currentStanding end
        return nil
    end
    if _G.GetFactionInfoByID then
        local ok, name, _, _, _, _, value = pcall(_G.GetFactionInfoByID, factionID)
        if ok and name then return value end
    end
    return nil
end

local function knowsSpell(spellID)
    local book = _G.C_SpellBook
    local fn = (book and book.IsSpellKnown) or _G.IsPlayerSpell or _G.IsSpellKnown
    if not fn then return nil end
    local ok, known = pcall(fn, spellID)
    if ok then return known and true or false end
    return nil
end

local function done(questID)
    return Api:IsFlaggedCompleted(questID)
end

local function active(questID)
    local State = Q.State
    return State ~= nil and State:IsInLog(questID)
end

-- A prerequisite counts as met when it was turned in - or when a quest
-- it is mutually exclusive with was (a chain's Alliance/Horde or
-- class-specific twin). Same substitution Questie makes.
local function met(questID)
    if done(questID) then return true end
    local r = rule(questID)
    if r and r.x then
        for i = 1, #r.x do
            if done(r.x[i]) then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------------------
-- The check
---------------------------------------------------------------------------------------

-- ok, reason. Covers what depends on the character and their history;
-- faction, class and the quest's own level range are Catalog:IsEligible.
-- "Already done" and "already in the log" are the caller's to check.
function Rules:Check(questID, level)
    local r = rule(questID)
    if not r or r.unknown then
        local prev = Prev[questID]
        if prev and not done(prev) then return false, "needs quest " .. prev end
        return true
    end

    if r.s then
        local any = false
        for i = 1, #r.s do
            if met(r.s[i]) then any = true; break end
        end
        if not any then return false, "needs quest " .. r.s[1] end
    elseif r.g then
        for i = 1, #r.g do
            if not met(r.g[i]) then return false, "needs quest " .. r.g[i] end
        end
    end
    if r.x then
        for i = 1, #r.x do
            local other = r.x[i]
            if done(other) or active(other) then return false, "exclusive with quest " .. other end
        end
    end
    if r.p and not active(r.p) then return false, "part of quest " .. r.p end
    if r.n and (done(r.n) or active(r.n)) then return false, "follow-up " .. r.n .. " already taken" end
    if r.b and (done(r.b) or active(r.b)) then return false, "leads to quest " .. r.b .. ", already taken" end

    level = level or UnitLevel("player") or 1
    if r.l and level < r.l then return false, "needs level " .. r.l end
    if r.L and level > r.L then return false, "only up to level " .. r.L end

    if r.r then
        local bit = raceBit()
        if bit and floor(r.r / bit) % 2 == 0 then return false, "wrong race" end
    end
    if r.k then
        local have = skills()
        local rank = have and have[r.k[1]]
        if not rank or rank < r.k[2] then return false, "needs profession " .. r.k[1] end
    end
    if r.m then
        local value = standing(r.m[1])
        if not value or value < r.m[2] then return false, "needs reputation with " .. r.m[1] end
    end
    if r.M then
        local value = standing(r.M[1])
        if value and value >= r.M[2] then return false, "too much reputation with " .. r.M[1] end
    end
    if r.c then
        local known = knowsSpell(math.abs(r.c))
        if known ~= nil then
            if r.c > 0 and not known then return false, "needs a spell" end
            if r.c < 0 and known then return false, "ruled out by a spell" end
        end
    end
    return true
end

-- The level a quest asks for, where QuestieDB disagrees with the row.
function Rules:GetMinLevel(questID)
    local r = rule(questID)
    return r and r.l or nil
end

---------------------------------------------------------------------------------------
-- Item-started quests, patrol paths, quest items
---------------------------------------------------------------------------------------

-- "1443:56.8,30;57.1,31.2" (repeated, "|"-separated from index `from`)
-- -> { {mapId=1443, n=2, 56.8, 30, 57.1, 31.2}, ... }
local function unpackPoints(parts, from)
    local out = {}
    for i = from, #parts do
        local mapId, coords = parts[i]:match("^(%d+):(.+)$")
        if mapId then
            local list, n = { mapId = tonumber(mapId) }, 0
            for x, y in coords:gmatch("([%d.]+),([%d.]+)") do
                list[n * 2 + 1], list[n * 2 + 2] = tonumber(x), tonumber(y)
                n = n + 1
            end
            list.n = n
            if n > 0 then out[#out + 1] = list end
        end
    end
    return out
end

local function split(packed)
    local parts = {}
    for part in packed:gmatch("[^|]+") do parts[#parts + 1] = part end
    return parts
end

local startItems = {}

-- { itemId=, name=, droppers=, world=, areas={ {mapId=, n=, x, y, ...}, ... } }
-- for a quest begun by an item that drops, else nil. `world` marks an
-- item that drops nearly anywhere (Tools/gen_quest_rules.py decides).
function Rules:GetStartItem(questID)
    local info = startItems[questID]
    if info == nil then
        info = false
        local packed = StartItemData[questID]
        if packed then
            -- Matched field by field: the droppers field can be empty,
            -- which a gmatch split would skip.
            local itemId, name, droppers, tail = packed:match("^(%d+)|([^|]*)|([^|]*)|?(.*)$")
            if itemId then
                info = {
                    itemId = tonumber(itemId), name = name,
                    droppers = droppers ~= "" and droppers ~= "world drop" and droppers or nil,
                    -- Drops all over the world: nowhere worth a pin.
                    world = droppers == "world drop" or nil,
                    areas = unpackPoints(split(tail or ""), 1),
                }
            end
        end
        startItems[questID] = info
    end
    return info or nil
end

-- [mapId] = { questID, ... }: item-started quests whose item drops there.
function Rules:GetStartItemQuests(mapId)
    local index = self._startItemsByMap
    if not index then
        index = {}
        for questID, packed in pairs(StartItemData) do
            for id in packed:gmatch("|(%d+):") do
                id = tonumber(id)
                index[id] = index[id] or {}
                index[id][#index[id] + 1] = questID
            end
        end
        for _, list in pairs(index) do table.sort(list) end
        self._startItemsByMap = index
    end
    return index[mapId]
end

local patrols = {}

-- { {mapId=, n=, x, y, ...}, ... }: the paths an NPC walks, or nil.
function Rules:GetPatrol(npcId)
    if not npcId then return nil end
    local paths = patrols[npcId]
    if paths == nil then
        local packed = PatrolData[npcId]
        paths = packed and unpackPoints(split(packed), 1) or false
        if paths and #paths == 0 then paths = false end
        patrols[npcId] = paths
    end
    return paths or nil
end

-- Item ids a quest gives or asks you to carry: { id, ... } or nil.
function Rules:GetQuestItems(questID)
    local packed = QuestItemData[questID]
    if not packed then return nil end
    local list = {}
    for id in packed:gmatch("%d+") do list[#list + 1] = tonumber(id) end
    return list
end

---------------------------------------------------------------------------------------

function Rules:Start()
    if self.Frame then return end
    local frame = CreateFrame("Frame")
    self.Frame = frame
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "UPDATE_FACTION", "LEARNED_SPELL_IN_TAB" }) do
        Q.Core:SafeRegisterEvent(frame, event)
    end
    -- Reputation ticks on every kill; one bump a few seconds later is
    -- plenty for something that only decides which pickup pins show.
    frame:SetScript("OnEvent", function()
        self._skills = nil
        if self._pending then return end
        self._pending = true
        Q.Core:After(3, function()
            self._pending = false
            self.Serial = self.Serial + 1
        end)
    end)
end
