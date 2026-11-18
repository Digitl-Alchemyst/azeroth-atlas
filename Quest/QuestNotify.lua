---------------------------------------------------------------------------------------
-- Alchemy GPS | Quest/QuestNotify.lua
--
-- Telling you (and your group) when quests progress. Watches the quest
-- log on every QUEST_STATE_CHANGED and compares it with the last look.
--
-- Quest-complete sound (2026-11-18, user request, from Carbonite: "Plays
-- a sound when a quest completes, chosen from 8 (peon "work complete",
-- dwarf "well done", and so on)"): Carbonite's own list (OptionsEngine
-- .lua's OptsDataSounds / OptsDataSoundsIDs) - its chime, shipped here
-- as Snd\QuestComplete.ogg, and seven of the game's own voice lines by
-- sound-file ID. Settings > Quests: off, one of them, or a random one.
-- Only a quest that was in the log before and has just become ready to
-- turn in - not one picked up already complete ("go and talk to...").
--
-- Progress messages to the group (2026-11-18, user request, from
-- Carbonite: "Says in party or raid chat when you finish objectives,
-- after a set number of changes" - its TellPartyOfChanges): when an
-- objective's count crosses a multiple of N ("Kobold Vermin slain:
-- 5/10" with N = 5), when an objective is finished, and when the whole
-- quest is ready to turn in, a line goes to party / raid / instance
-- chat. Everyone in the group sees these, addon or not, so it's OFF
-- until switched on (Settings > Quests: GroupProgressMsg, N =
-- GroupProgressEvery). Sent at most one every 1.5 seconds.
--
-- Auto-watch (2026-11-18, user request, from Carbonite's "Auto-watch
-- changes" - "use this to make general improvements to our own
-- routing"): a quest you'd untracked is tracked again as soon as it
-- progresses (AutoWatchProgress, on), and optionally untracked once
-- it's ready to hand in (AutoUnwatchDone, off - the arrow then won't
-- lead you to the turn-in). Every progress also goes to the router
-- (Routing:NoteProgress), which keeps the arrow on the quest you're
-- working on rather than hopping to one slightly closer.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest

local Notify = {}
Q.Notify = Notify

Notify.SOUNDS = {
    { label = "Quest complete chime",        file = "Interface\\AddOns\\AlchemyGPS\\Snd\\QuestComplete.ogg" },
    { label = "Peon: \"Work complete\"",     file = 558132 },
    { label = "Undead: \"Congratulations\"", file = 542775 },
    { label = "Human: \"Congratulations\"",  file = 540654 },
    { label = "Dwarf: \"Well done\"",        file = 540042 },
    { label = "Gnome: \"Congratulations\"",  file = 540512 },
    { label = "Tauren: \"Yes\"",             file = 561484 },
    { label = "Undead warrior greeting",     file = 563198 },
}

-- The chosen sound: 0 = none, 1-8, or "random". Default: the chime.
function Notify:SoundChoice()
    local v = Q.Core:Opt("CompleteSound")
    if v == nil then return 1 end
    return v
end

function Notify:SoundLabel(choice)
    if choice == 0 then return "No sound" end
    if choice == "random" then return "A random one of these" end
    local s = self.SOUNDS[choice]
    return s and s.label or "?"
end

function Notify:PlaySound(choice)
    choice = choice or self:SoundChoice()
    if choice == 0 then return end
    if choice == "random" then choice = math.random(1, #self.SOUNDS) end
    local s = self.SOUNDS[choice]
    if s then pcall(PlaySoundFile, s.file, "Master") end
end

-- [questID] = { ready = bool, objectives = { [i] = text } } from the last look.
local last

local function snapshot()
    local snap = {}
    for _, q in ipairs(Q.State.Quests or {}) do
        local objs = {}
        for i, o in ipairs(q.objectives or {}) do objs[i] = { text = o.text, finished = o.finished } end
        snap[q.questID] = { ready = q.ready and true or false, objectives = objs, title = q.title }
    end
    return snap
end

local function counts(text)
    local have, need = (text or ""):match("(%d+)%s*/%s*(%d+)")
    return tonumber(have), tonumber(need)
end

-- Quests that moved forward between two looks: an objective's count
-- went up, an objective finished, or the quest became ready.
local function progressed(before, now)
    local out = {}
    for questID, cur in pairs(now) do
        local old = before[questID]
        if old then
            local moved = cur.ready and not old.ready
            for i, o in ipairs(cur.objectives) do
                local was = old.objectives[i]
                if was and o.text ~= was.text then
                    local have, oldHave = counts(o.text), counts(was.text)
                    if (o.finished and not was.finished) or (have and oldHave and have > oldHave) then
                        moved = true
                    end
                end
            end
            if moved then out[#out + 1] = questID end
        end
    end
    return out
end

function Notify:OnStateChanged()
    local State = Q.State
    if not State or not State.Scanned then return end
    local now = snapshot()
    -- Saved first: tracking a quest below fires QUEST_STATE_CHANGED
    -- again, and that pass must see nothing new.
    local before = last
    last = now
    if not before then return end

    local completed = {}
    for _, q in ipairs(State.Quests) do
        local old = before[q.questID]
        if old and q.ready and not old.ready then completed[#completed + 1] = q.questID end
    end
    if #completed > 0 then self:PlaySound() end
    if self.OnProgress then pcall(self.OnProgress, self, before, now) end

    local Routing = Q.Routing
    for _, questID in ipairs(progressed(before, now)) do
        if Routing and Routing.NoteProgress then Routing:NoteProgress(questID) end
        if Q.Core:Opt("AutoWatchProgress") ~= false and not State:IsWatched(questID) then
            State:SetWatched(questID, true)
        end
    end
    if Q.Core:Opt("AutoUnwatchDone") then
        for _, questID in ipairs(completed) do
            if State:IsWatched(questID) then State:SetWatched(questID, false) end
        end
    end
end

---------------------------------------------------------------------------------------
-- Progress messages
---------------------------------------------------------------------------------------

local SEND_GAP = 1.5
local queue, sending = {}, false

local function groupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function sendNext()
    local msg = table.remove(queue, 1)
    if not msg then
        sending = false
        return
    end
    local channel = groupChannel()
    if channel then pcall(SendChatMessage, msg, channel) end
    C_Timer.After(SEND_GAP, sendNext)
end

local function say(msg)
    -- Chat refuses some characters; colour codes and links don't belong.
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    queue[#queue + 1] = msg
    if not sending then
        sending = true
        sendNext()
    end
end

function Notify:OnProgress(before, now)
    if not Q.Core:Opt("GroupProgressMsg") or not groupChannel() then return end
    local every = math.max(1, Q.Core:Opt("GroupProgressEvery") or 1)
    for questID, cur in pairs(now) do
        local old = before[questID]
        if old then
            for i, o in ipairs(cur.objectives) do
                local was = old.objectives[i]
                if was and o.text ~= was.text and o.text ~= "" then
                    local send = o.finished and not was.finished
                    if not send then
                        local have, need = counts(o.text)
                        local oldHave = counts(was.text)
                        if have and oldHave and have > oldHave then
                            send = math.floor(have / every) ~= math.floor(oldHave / every)
                                or (need and have >= need)
                        end
                    end
                    if send then say(("%s: %s"):format(cur.title or "?", o.text)) end
                end
            end
            if cur.ready and not old.ready then
                say(("%s: ready to turn in"):format(cur.title or "?"))
            end
        end
    end
end

function Notify:Start()
    EventBus:Subscribe("QUEST_STATE_CHANGED", function() self:OnStateChanged() end)
    self:OnStateChanged()
end
