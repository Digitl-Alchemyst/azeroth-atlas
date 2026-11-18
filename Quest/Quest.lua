-- Alchemy GPS | Quest / Quest
-- The questing companion's module shell: saved settings, the start-up
-- sequence that brings the other Quest/*.lua pieces online, and the
-- `/gps quest` slash command.
--
-- Pieces (each in its own file, each on AlchemyGPS.Modules.Quest):
--   Api          version-tolerant quest-log access        QuestApi.lua
--   Catalog      the bundled quest database               QuestCatalog.lua
--   State        live quest log cache                     QuestState.lua
--   Routing      "where should I go next" resolver        QuestRouting.lua
--   SuperTrack   keeps Blizzard's own tracking in step    SuperTrack.lua
--   TrackerHider hides Blizzard's quest tracker           TrackerHider.lua
--   Pins         quest pins for the map window            QuestPins.lua
--   Rules        who can pick a quest up; drop/patrol data QuestRules.lua
--   Overlay      shaded quest areas and patrol lines       QuestOverlay.lua
--   Items        usable quest item buttons and hotkey      QuestItems.lua
--   Tracker      the on-screen quest list                 QuestTracker.lua
--   List         the full quest list window               QuestList.lua
--   HUD          the routing arrow                        HUDArrow.lua
--
-- Settings live in AlchemyGPS.db.profile.Quest (per profile) and
-- AlchemyGPS.db.char.Quest (per character: which quests are untracked
-- or collapsed). Read them through Core:Opt / Core:Char, never
-- directly: Core/SavedVariables.lua only seeds a module's defaults
-- when its whole table is missing, so an option added in a later
-- version would be nil in an existing profile. Opt() answers from
-- DEFAULTS in that case - the same "missing key means default"
-- convention the map filters use.

local AlchemyGPS = _G.AlchemyGPS
local Module = AlchemyGPS.Core.Module
local EventBus = AlchemyGPS.Core.EventBus

AlchemyGPS.Modules.Quest = AlchemyGPS.Modules.Quest or {}
local Q = AlchemyGPS.Modules.Quest

local DEFAULTS = {
    HideBlizzTracker = true,    -- replace Blizzard's tracker with ours
    TrackerShown = true,
    TrackerLocked = false,
    TrackerMaxQuests = 12,      -- rows beyond this fold into "+N more"
    AutoTrack = true,           -- route to the closest tracked quest
    ArrowShown = true,
    ArrowLocked = false,
    ArrowScale = 1,
    -- 2026-11-18 (user request, from Carbonite's HUD options): degrees
    -- off course after the distance, click the arrow to target who
    -- you're heading to, hide it in battlegrounds.
    ArrowDirText = false,
    ArrowTargetButton = true,
    ArrowHideInBG = false,
    RouteTrail = true,          -- ant trail to the routed target on the map
    SuperTrackSync = true,      -- mirror our target into C_SuperTrack
    ShowLowLevel = false,       -- pickup pins for trivial (gray) quests
    ShowEventQuests = false,    -- pickup pins for holiday/event quests
    ShowQuestAreas = true,      -- shade where tracked objectives are found
    ShowPatrolPaths = true,     -- draw the route a wandering quest NPC walks
    TrackerGroupByZone = true,  -- zone / dungeon headings on the tracker
    TrackerCollapsed = false,   -- tracker rolled up to its title bar
    TrackerItemButtons = true,  -- usable quest items beside the tracker
}

local Core = Module:New("Quest", {
    defaults = {
        profile = {
            Quest = {},
        },
        char = {
            Quest = {},
        },
    },
})
Q.Core = Core
Core.DEFAULTS = DEFAULTS

function Core:Opt(key)
    local v = self:DB().profile[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

function Core:SetOpt(key, value)
    self:DB().profile[key] = value
    EventBus:Fire("QUEST_OPTION_CHANGED", key, value)
end

-- A named sub-table of the profile (window anchors/sizes), created on
-- first use so the Draggable/Resizable mixins have somewhere to write.
function Core:ProfileTable(key)
    local profile = self:DB().profile
    if type(profile[key]) ~= "table" then profile[key] = {} end
    return profile[key]
end

-- Per-character sets: Unwatched[questID], Collapsed[questID], Known[questID],
-- Headers[questID], CollapsedZones[name], ListOpen[questID].
function Core:Char(key)
    local char = self:DB().char
    if type(char[key]) ~= "table" then char[key] = {} end
    return char[key]
end

-- Quest difficulty colour, plus whether the quest is trivial (gray) for
-- this character: r, g, b, trivial.
--
-- This client grades each quest itself
-- (C_PlayerInfo.GetContentDifficultyQuestForPlayer), and that grade -
-- not the generic GetQuestDifficultyColor(level), whose thresholds are
-- different - is what Blizzard's own quest log colours by. So with a
-- quest id whose data the client has loaded, its answer is used as is.
-- Otherwise it is the classic level rule (red +5, orange +3, yellow -2,
-- green down to the client's trivial range, then gray), the same
-- fallback Questie uses here.
local COLORS = {
    Trivial = { 0.5, 0.5, 0.5 },
    Easy = { 0.25, 0.75, 0.25 },
    Fair = { 1, 1, 0 },
    Difficult = { 1, 0.5, 0.25 },
    Impossible = { 1, 0.1, 0.1 },
}
local nativeColors

local function nativeDifficulty(questID)
    local grade = _G.C_PlayerInfo and _G.C_PlayerInfo.GetContentDifficultyQuestForPlayer
    local enum = _G.Enum and _G.Enum.RelativeContentDifficulty
    if not grade or not enum then return nil end
    -- Without the quest's data loaded the client answers "Fair" for anything.
    if type(_G.HaveQuestData) == "function" then
        local ok, have = pcall(_G.HaveQuestData, questID)
        if not ok or not have then return nil end
    end
    if not nativeColors then
        nativeColors = {}
        for name, color in pairs(COLORS) do
            if enum[name] ~= nil then nativeColors[enum[name]] = { color, name == "Trivial" } end
        end
    end
    local ok, value = pcall(grade, questID)
    return ok and nativeColors[value] or nil
end

-- How many levels below the character a quest stays green.
local function greenRange(playerLevel)
    local log = _G.C_QuestLog
    for _, fn in ipairs({ log and log.GetTrivialRange, _G.GetQuestGreenRange }) do
        if type(fn) == "function" then
            local ok, v = pcall(fn)
            if ok and type(v) == "number" then return v end
        end
    end
    -- Classic's gray-level table, expressed as a range below the player.
    if playerLevel <= 5 then return playerLevel end
    if playerLevel <= 39 then return math.floor(playerLevel / 10) + 5 end
    if playerLevel <= 59 then return math.floor(playerLevel / 5) + 1 end
    return 9
end

function Core:Difficulty(level, questID)
    if questID and questID > 0 then
        local native = nativeDifficulty(questID)
        if native then
            local c = native[1]
            return c[1], c[2], c[3], native[2]
        end
    end

    local playerLevel = UnitLevel("player") or 1
    if not level or level <= 0 then level = playerLevel end
    local diff = level - playerLevel
    local c, trivial = COLORS.Trivial, false
    if diff >= 5 then
        c = COLORS.Impossible
    elseif diff >= 3 then
        c = COLORS.Difficult
    elseif diff >= -2 then
        c = COLORS.Fair
    elseif -diff <= greenRange(playerLevel) then
        c = COLORS.Easy
    else
        trivial = true
    end
    return c[1], c[2], c[3], trivial
end

-- Runs fn after `delay` seconds. C_Timer where the client has it,
-- AceTimer otherwise.
function Core:After(delay, fn)
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(delay, fn)
    else
        AlchemyGPS:ScheduleTimer(fn, delay)
    end
end

-- Registers a game event on a frame, tolerating names this client
-- doesn't know (some builds raise an error for those instead of
-- ignoring them).
function Core:SafeRegisterEvent(frame, event)
    return (pcall(frame.RegisterEvent, frame, event))
end

local STARTUP = {
    "Catalog", "Rules", "State", "TrackerHider", "Routing", "SuperTrack", "Pins", "Overlay",
    "Items", "Tracker", "List", "Details", "Notify", "Tooltips", "HUD",
}

function Core:Start()
    if self.Started then return end
    self.Started = true

    -- One piece failing to start must not take the others with it.
    for _, name in ipairs(STARTUP) do
        local piece = Q[name]
        if piece and piece.Start then
            local ok, err = pcall(piece.Start, piece)
            if not ok then
                self.log:error("%s failed to start: %s", name, tostring(err))
            end
        end
    end
end

function Core:OnEnable()
    -- Same timing gap MinimapWindow.lua documents: modules enable
    -- before Core/SavedVariables.lua has bound the real saved table,
    -- and self:DB() hands back a defaults-only stand-in until then.
    -- Starting from that would apply defaults over the user's choices.
    local function startOnceReady()
        if not AlchemyGPS.Core.SavedVariables:GetModuleDB(self:GetName()) then
            AlchemyGPS:ScheduleTimer(startOnceReady, 0.1)
            return
        end
        self:Start()
    end
    startOnceReady()

    AlchemyGPS.Core.SlashCommands:Register("quest", function(rest)
        self:Slash(rest)
    end, "quest tracker / arrow / pins (try /gps quest help)")
end

---------------------------------------------------------------------------------------
-- /gps quest
---------------------------------------------------------------------------------------

local function say(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffc0c0ff[AlchemyGPS]|r " .. (ok and msg or tostring(fmt)))
    end
end
Core.Say = say

local function onOff(v) return v and "on" or "off" end

function Core:PrintStatus()
    local Catalog, State, Routing = Q.Catalog, Q.State, Q.Routing
    say("quest database: %s (%d quests)",
        Catalog and Catalog.Ready and "loaded" or "loading", Catalog and Catalog.Count or 0)
    local inLog = State and #State.Quests or 0
    local watched = State and #State:GetWatchedQuests() or 0
    say("quest log: %d quests, %d tracked", inLog, watched)
    local t = Routing and Routing.Target
    if t then
        say("routing to: %s (%s)", tostring(t.name), tostring(t.source))
    else
        say("routing to: nothing")
    end
    say("tracker %s, arrow %s, auto-track %s, hide Blizzard tracker %s",
        onOff(self:Opt("TrackerShown")), onOff(self:Opt("ArrowShown")),
        onOff(self:Opt("AutoTrack")), onOff(self:Opt("HideBlizzTracker")))
end

-- Dumps what the bundled database and the live client each say about
-- one quest - the comparison to reach for when a pin or the arrow
-- lands somewhere wrong.
local function dungeonList(ids, fmt, none)
    if not ids then return none or "" end
    local names = {}
    for i, id in ipairs(ids) do
        names[i] = ("%s [%d]"):format(tostring((Q.Catalog:GetInstanceEntrance(id))), id)
    end
    return fmt:format(table.concat(names, ", "))
end

function Core:DumpQuest(questID)
    local Catalog, State, Api, Routing = Q.Catalog, Q.State, Q.Api, Q.Routing
    local Map = AlchemyGPS.Map
    local row = Catalog and Catalog.Quests[questID]
    if not row then
        say("quest %d: not in the bundled database", questID)
    else
        local h = Catalog:GetHeader(questID)
        say("quest %d: %s (level %d, min %d, side %d)", questID, h.name, h.level, h.minLevel, h.side)
        for _, key in ipairs({ "Start", "End" }) do
            if row[key] then
                local name, zone, x, y = Catalog:UnpackSE(row[key])
                local wx, wy = Map:GetWorldPos(zone, x, y)
                say("  %s: %s  map %d  %.2f, %.2f  ->  world %s",
                    key, tostring(name), zone, x, y,
                    wx and ("%.1f, %.1f"):format(wx, wy) or "(not on a known continent)")
            end
        end
        local n = 0
        while row.Objectives and row.Objectives[n + 1] do n = n + 1 end
        for i = 1, n do
            local geo = Catalog:GetObjectiveGeo(questID, i)
            local clusters = Catalog:GetObjectiveClusters(questID, i)
            say("  objective %d: %s - %d locations, %d pin clusters%s", i,
                tostring(geo and geo.name), geo and geo.n or 0, clusters and #clusters or 0,
                dungeonList(geo and geo.dungeons, " (inside: %s)"))
        end
        if Q.Rules then
            local ok, why = Q.Rules:Check(questID)
            local item = Q.Rules:GetStartItem(questID)
            say("  can be picked up now: %s%s", ok and "yes" or ("no - " .. tostring(why)),
                Api:IsFlaggedCompleted(questID) and " (already turned in)" or "")
            if item then
                say("  started by an item: %s (%d), from %s", tostring(item.name), item.itemId,
                    tostring(item.droppers or "unknown"))
            end
        end
        do
            local r, g, b, trivial = self:Difficulty(h.level, questID)
            say("  difficulty: |cff%02x%02x%02x%s|r, quest level %d, you %d", r * 255, g * 255, b * 255,
                trivial and "trivial" or "colour", h.level, UnitLevel("player") or 0)
        end
        say("  picked up%s, turned in%s",
            dungeonList(Catalog:GetEndpointDungeons(questID, false), " inside %s", " outdoors or unknown"),
            dungeonList(Catalog:GetEndpointDungeons(questID, true), " inside %s", " outdoors or unknown"))
    end

    local q = State and State:GetQuest(questID)
    if q then
        say("  in log: complete=%s ready=%s objectives=%d", tostring(q.isComplete), tostring(q.ready), #q.objectives)
        local mapID, lx, ly = Api:GetNextWaypoint(questID)
        if mapID then
            say("  live waypoint: map %d  %.2f, %.2f", mapID, lx * 100, ly * 100)
        end
        local info = Routing and Routing.QuestInfo[questID]
        if info and info.res then
            say("  resolved: %s via %s, map %s, %s", tostring(info.res.name), tostring(info.res.source),
                tostring(info.res.mId), info.yards and ("%d yd"):format(info.yards) or "distance unknown")
        else
            say("  resolved: no position")
        end
    else
        say("  not in the quest log")
    end
end

function Core:Slash(rest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = rest:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "status" then
        self:PrintStatus()
    elseif cmd == "tracker" then
        self:SetOpt("TrackerShown", not self:Opt("TrackerShown"))
        say("quest tracker %s", onOff(self:Opt("TrackerShown")))
    elseif cmd == "arrow" then
        self:SetOpt("ArrowShown", not self:Opt("ArrowShown"))
        say("routing arrow %s", onOff(self:Opt("ArrowShown")))
    elseif cmd == "auto" then
        self:SetOpt("AutoTrack", not self:Opt("AutoTrack"))
        say("auto-track closest quest %s", onOff(self:Opt("AutoTrack")))
    elseif cmd == "blizz" then
        self:SetOpt("HideBlizzTracker", not self:Opt("HideBlizzTracker"))
        say("Blizzard quest tracker %s", self:Opt("HideBlizzTracker") and "hidden" or "shown")
    elseif cmd == "list" then
        if Q.List then Q.List:Toggle() end
    elseif cmd == "key" then
        if Q.Items then Q.Items:SlashKey(arg) end
    elseif cmd == "areas" then
        self:SetOpt("ShowQuestAreas", not self:Opt("ShowQuestAreas"))
        say("quest areas on the map %s", onOff(self:Opt("ShowQuestAreas")))
    elseif cmd == "patrols" then
        self:SetOpt("ShowPatrolPaths", not self:Opt("ShowPatrolPaths"))
        say("patrol paths on the map %s", onOff(self:Opt("ShowPatrolPaths")))
    elseif cmd == "hide" or cmd == "unhide" then
        local Pins = Q.Pins
        if arg == "all" and cmd == "unhide" then
            Pins:UnhideAll()
            say("every hidden quest is back on the map")
        elseif tonumber(arg) then
            Pins:SetHidden(tonumber(arg), cmd == "hide")
            say("quest %d %s", tonumber(arg), cmd == "hide" and "hidden from the map" or "back on the map")
        else
            local list = {}
            for id in pairs(self:ProfileTable("HiddenQuests")) do
                list[#list + 1] = ("%d %s"):format(id, Q.Catalog:GetName(id) or "?")
            end
            table.sort(list)
            say("hidden quests: %s", #list > 0 and table.concat(list, ", ") or "none")
            say("/gps quest hide <questID> | unhide <questID> | unhide all")
        end
    elseif cmd == "trackall" then
        if Q.State then Q.State:WatchAll() end
        say("tracking every quest in the log")
    elseif cmd == "route" then
        local id = tonumber(arg)
        if Q.Routing then
            if id then
                Q.Routing:SetManualQuest(id)
                say("routing to quest %d", id)
            else
                Q.Routing:ClearManual()
                say("manual route cleared")
            end
        end
    elseif cmd == "dump" then
        local id = tonumber(arg)
        if not id and Q.Routing and Q.Routing.Target then id = Q.Routing.Target.questID end
        if id then
            self:DumpQuest(id)
        else
            say("usage: /gps quest dump <questID>")
        end
    else
        say("/gps quest - status")
        say("/gps quest tracker | arrow | auto | blizz - toggle that piece")
        say("/gps quest list - the full quest list window")
        say("/gps quest key <KEY> - bind \"use the nearest quest item\" (no key: show it)")
        say("/gps quest areas | patrols - toggle shaded quest areas / patrol paths")
        say("/gps quest hide <questID> | unhide <questID|all> - quests kept off the map")
        say("/gps quest trackall - put every quest back on the tracker")
        say("/gps quest route <questID> - route to a quest (no id: clear)")
        say("/gps quest dump <questID> - database vs. live data for one quest")
    end
end
