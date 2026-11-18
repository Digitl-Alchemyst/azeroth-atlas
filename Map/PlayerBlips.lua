-- Alchemy GPS | Map / PlayerBlips
-- 2026-11-16 (user request): other players on the map.
--   Party members  - blue
--   Raid members   - orange (members of your own raid sub-group count
--                    as party, blue)
--   Guildmates     - green
--   Enemy players  - red, or optionally their faction's emblem
--
-- Colors come from Carbonite's own player-dot icons, already shipped
-- in Gfx\Map (IconPlyrP is blue, IconPlyrF orange, IconPlyrG green,
-- IconPlyrZ gray - the gray one is tinted red for enemies).
--
-- Where each kind's position comes from:
--   * Party / raid: the game reports group members' map positions
--     directly (C_Map.GetPlayerMapPosition with a party/raid unit).
--   * Guild: the game does NOT report where guildmates are. Carbonite
--     solved this by having every copy of the addon tell the guild where
--     its player is over a hidden addon channel; this does the same.
--     Only guildmates who also run Alchemy GPS show up, and only while
--     sharing is on (Settings > Map, on by default). Your position is
--     never sent from inside a dungeon.
--   * Friends (2026-11-18, user request, from Carbonite): the same
--     message, sent as a hidden addon whisper (a couple every 2 seconds,
--     each friend every 10 seconds or more) to each
--     online friends-list character (Settings > Map, "Share my position
--     with friends"). A whisper is only believed when its sender is on
--     YOUR friends list, so a stranger can't put a dot on your map. A
--     friend who's also a guildmate stays green. Yellow dots.
--   * Enemies: the game never reports an enemy player's position.
--     Carbonite's old enemy tracker ("Punks") marked an enemy at YOUR
--     position at the moment you detected them - in combat-log range,
--     targeted, moused over or with a visible nameplate, all of which
--     mean they're close. This does the same: the dot marks where you
--     were when you last saw them, fading out over two minutes.
--
-- Drawn with the same pooled frames and ClipFrameW point clip as every
-- other map icon (MinimapEngine.lua), at the Service layer, under the
-- player marker.

local AlchemyGPS = _G.AlchemyGPS
local MinimapEngine = AlchemyGPS.Map

local GFX = "Interface\\AddOns\\AlchemyGPS\\Gfx\\Map\\"
local TEX = {
    party = GFX .. "IconPlyrP",
    raid  = GFX .. "IconPlyrF",
    guild = GFX .. "IconPlyrG",
    enemy = GFX .. "IconPlyrZ",
    friend = GFX .. "IconPlyrZ",     -- tinted yellow when drawn
}
local FACTION_TEX = {
    Horde    = "Interface\\WorldStateFrame\\HordeIcon",
    Alliance = "Interface\\WorldStateFrame\\AllianceIcon",
}
local KIND_LABEL = { party = "Party", raid = "Raid", guild = "Guild", enemy = "Enemy", friend = "Friend" }
local FILTER_KEY = { party = "Party", raid = "Raid", guild = "Guild", enemy = "Enemy", friend = "Friend" }
-- Friends: whispered a couple at a time (the game drops addon messages
-- sent faster than about one a second), each at most every 10 seconds.
local FRIEND_TICK = 2             -- seconds between sends
local FRIEND_PER_TICK = 2         -- friends whispered per send
local FRIEND_EVERY = 10           -- seconds before the same friend again
local FRIEND_TTL = 60             -- drop a friend not heard from in this long

local DOT_SIZE = 14
local FACTION_SIZE = 20
local GROUP_REFRESH = 0.25        -- seconds between group position reads
local GUILD_SEND_INTERVAL = 5     -- seconds between our own broadcasts
local GUILD_TTL = 20              -- drop a guildmate not heard from in this long
local ENEMY_TTL = 120             -- enemies fade out over this long
local ENEMY_MIN_ALPHA = 0.35
local COMM_PREFIX = "AlchemyGPS1"

local guild = {}    -- [name] = { map, x, y, class, level, t }
local enemies = {}  -- [name] = { wx, wy, cont, faction, class, level, t }

local function profile()
    return AlchemyGPS.db and AlchemyGPS.db.profile
end

local function filterOn(kind)
    local p = profile()
    local filters = p and p.MapFilters
    return not filters or filters[FILTER_KEY[kind]] ~= false
end

local function optOn(key, default)
    local p = profile()
    local v = p and p[key]
    if v == nil then return default end
    return v
end

-- World position of a unit on the map the engine is showing, or nil.
local function unitWorld(engine, unit)
    local map = C_Map.GetBestMapForUnit(unit)
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, unit)
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    map = engine:CanonicalizeMapID(map)
    -- Inside a dungeon: only someone on the floor being looked at, placed
    -- on that floor (a WoW Forever art floor stands in for the client
    -- map it matches - MinimapEngine:FloorForMap).
    if engine.Cont == engine.DUNGEON_CONT and engine.DungeonFloors then
        local floor = engine:FloorForMap(map)
        if not floor or floor ~= engine:GetViewMapId() then return nil end
        map = floor
    end
    if engine:FindContinent(map) ~= engine.Cont then return nil end
    return engine:GetWorldPos(map, x * 100, y * 100)
end

-- The player's own map id and 0-100 coordinates, read live (the map
-- window may be closed, so the engine's own copies can be stale).
local function playerZonePos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return MinimapEngine:CanonicalizeMapID(map), x * 100, y * 100
end

local function classColorText(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

-- Names. This server gives characters a first AND a last name: the
-- second value UnitName returns is the last name (on a normal server
-- it would be the realm) - the same reading Frames Forever uses
-- (Frames_Forever/Core/Data/Name.lua). Who's who is decided by GUID,
-- never by name; names are only for tooltips.
local function readable(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return type(v) == "string" and v ~= ""
end

local function unitFullName(unit)
    local first, last = UnitName(unit)
    if not readable(first) then return nil end
    if readable(last) then return first .. " " .. last end
    return first
end

-- Names from chat senders and the combat log come as "First-Suffix",
-- where the suffix may be the last name or the realm.
local function displayName(raw)
    if not readable(raw) then return nil end
    local base, suffix = raw:match("^([^%-]+)%-(.+)$")
    if not suffix then return raw end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and suffix == realm then return base end
    return base .. " " .. suffix
end

local function isMyGUID(guid)
    return readable(guid) and guid == UnitGUID("player")
end

---------------------------------------------------------------------------------------
-- Guild position sharing
---------------------------------------------------------------------------------------

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
end

-- Our position message, or nil when there's nothing to share (inside
-- an instance, or nowhere on the map).
local function positionMessage()
    if IsInInstance() then return nil end
    local map, x, y = playerZonePos()
    if not map then return nil end
    local cont = MinimapEngine:FindContinent(map)
    if not cont or cont == MinimapEngine.DUNGEON_CONT then return nil end
    local _, class = UnitClass("player")
    -- GUID: lets every receiver - including this client, which gets its
    -- own broadcast back - know for certain whose position it is.
    -- Full name: for the tooltip, since the sender name the game
    -- attaches may carry only part of it.
    return ("P|%d|%.2f|%.2f|%s|%d|%s|%s"):format(map, x, y, class or "",
        UnitLevel("player") or 0, UnitGUID("player") or "",
        (unitFullName("player") or ""):gsub("|", ""))
end

local function sendGuildPosition()
    if not IsInGuild() or not optOn("ShareGuildPosition", true) then return end
    local msg = positionMessage()
    if msg then C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "GUILD") end
end

-- 2026-11-18: friends-list characters who are online right now.
local function onlineFriends()
    local out = {}
    if not (C_FriendList and C_FriendList.GetNumFriends) then return out end
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.name then
            out[#out + 1] = info.name
        end
    end
    return out
end

local friendSentAt = {}   -- [name] = GetTime() of our last whisper

local function sendFriendPosition()
    if not optOn("ShareFriendPosition", true) then return end
    local friends = onlineFriends()
    if #friends == 0 then return end
    local now = GetTime()
    -- The friends waiting longest first.
    table.sort(friends, function(a, b) return (friendSentAt[a] or 0) < (friendSentAt[b] or 0) end)
    local msg
    for i = 1, math.min(FRIEND_PER_TICK, #friends) do
        local name = friends[i]
        if now - (friendSentAt[name] or 0) < FRIEND_EVERY then break end
        msg = msg or positionMessage()
        if not msg then return end
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "WHISPER", name)
        friendSentAt[name] = now
    end
end

-- Is this whisper's sender on our friends list?
local function isFriend(sender)
    if not sender or not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
    local short = Ambiguate and Ambiguate(sender, "none") or sender
    return C_FriendList.GetFriendInfo(short) ~= nil or C_FriendList.GetFriendInfo(sender) ~= nil
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(GUILD_SEND_INTERVAL, function()
        pcall(sendGuildPosition)
    end)
    C_Timer.NewTicker(FRIEND_TICK, function()
        pcall(sendFriendPosition)
    end)
end

---------------------------------------------------------------------------------------
-- Enemy detection
---------------------------------------------------------------------------------------

local band = bit and bit.band
local TYPE_PLAYER = _G.COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local REACTION_HOSTILE = _G.COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40

local myPos = { t = 0 }
local function playerWorldNow()
    local now = GetTime()
    if now - myPos.t > 0.5 then
        myPos.t = now
        myPos.wx, myPos.wy, myPos.cont = nil, nil, nil
        local map, x, y = playerZonePos()
        if map then
            local cont = MinimapEngine:FindContinent(map)
            if cont then
                myPos.wx, myPos.wy = MinimapEngine:GetWorldPos(map, x, y)
                myPos.cont = cont
            end
        end
    end
    return myPos.wx, myPos.wy, myPos.cont
end

local function oppositeFaction()
    local mine = UnitFactionGroup("player")
    if mine == "Horde" then return "Alliance" end
    if mine == "Alliance" then return "Horde" end
    return nil
end

-- Keyed by GUID. `name` is already a display name; `unit` (optional)
-- fills in faction / class / level.
local function recordEnemy(guid, name, unit)
    if not readable(guid) or isMyGUID(guid) then return end
    local now = GetTime()
    local e = enemies[guid]
    if e and now - e.t < 1 and not unit then return end   -- combat log spam
    local wx, wy, cont = playerWorldNow()
    if not wx then return end
    e = e or {}
    e.wx, e.wy, e.cont, e.t = wx, wy, cont, now
    e.name = name or e.name or "?"
    e.faction = e.faction or oppositeFaction()
    if unit then
        e.faction = UnitFactionGroup(unit) or e.faction
        local _, class = UnitClass(unit)
        e.class = class or e.class
        e.level = UnitLevel(unit) or e.level
    end
    enemies[guid] = e
end

local function checkUnit(unit)
    if UnitExists(unit) and UnitIsPlayer(unit) and UnitIsEnemy("player", unit)
        and not UnitIsUnit(unit, "player") then
        recordEnemy(UnitGUID(unit), unitFullName(unit), unit)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not band or not CombatLogGetCurrentEventInfo then return end
        local _, _, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
        if srcFlags and band(srcFlags, TYPE_PLAYER) ~= 0 and band(srcFlags, REACTION_HOSTILE) ~= 0 then
            recordEnemy(srcGUID, displayName(srcName))
        end
        if dstFlags and band(dstFlags, TYPE_PLAYER) ~= 0 and band(dstFlags, REACTION_HOSTILE) ~= 0 then
            recordEnemy(dstGUID, displayName(dstName))
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        checkUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        checkUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        checkUnit((...))
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= COMM_PREFIX or not msg then return end
        -- Guild broadcasts, and (2026-11-18) whispers from friends only.
        if channel ~= "GUILD" and not (channel == "WHISPER" and isFriend(sender)) then return end
        local kind, map, x, y, class, level, guid, fullName = strsplit("|", msg)
        if kind ~= "P" then return end
        -- Your own broadcast comes back to you on the guild channel.
        -- Senders on the first build of this feature sent no GUID; they
        -- can't be told apart from you reliably, so they're ignored.
        if not readable(guid) or isMyGUID(guid) then return end
        map, x, y = tonumber(map), tonumber(x), tonumber(y)
        if not map or not x or not y then return end
        local now = GetTime()
        local old = guild[guid]
        guild[guid] = {
            name = readable(fullName) and fullName or displayName(sender) or "?",
            map = map, x = x, y = y, class = readable(class) and class or nil,
            level = tonumber(level), sender = sender, t = now,
            -- Heard on the guild channel lately: a guildmate (green),
            -- whatever else they are.
            guildT = (channel == "GUILD" and now) or (old and old.guildT),
        }
    end
end)

---------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------

local function BlipOnEnter(frm)
    local pt = frm.blip
    if not pt then return end
    GameTooltip:SetOwner(frm, "ANCHOR_CURSOR")
    GameTooltip:SetText(classColorText(pt.name, pt.class))
    local line = KIND_LABEL[pt.kind] or ""
    if pt.level and pt.level > 0 then line = ("Level %d  %s"):format(pt.level, line) end
    GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
    if pt.kind == "enemy" and pt.seen then
        GameTooltip:AddLine(("Seen near you %ds ago"):format(GetTime() - pt.seen), 1, 0.5, 0.5)
    end
    if MinimapEngine:IsTrackingPlayer(pt.guid) then
        GameTooltip:AddLine("The arrow is tracking them", 0.4, 0.8, 1)
    end
    GameTooltip:AddLine("Right-click: track, whisper, invite", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BlipOnLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------------------
-- Tracking a player (2026-11-18, user request, from Carbonite: "Right-
-- click a party, raid or friend dot to set the arrow on them. The same
-- menu offers Whisper, Invite and Report AFK" - Carbonite's player-icon
-- menu, Map:OnButPlyrMenu / Menu_OnTrackPlyr). The arrow (and a light-
-- blue ant trail on the map) follows them until you stop it - right-
-- click the arrow or the dot - or they leave your group, stop sharing
-- (guild) or fade off the map (enemies: where you last saw them).
-- Followed by GUID, so a name change or a rejoin doesn't confuse it.
---------------------------------------------------------------------------------------

local tracked         -- { guid, kind, name }
local trackTarget = {}

local function say(fmt, ...)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAlchemy GPS|r: " .. fmt:format(...))
    end
end

local function groupUnitFor(guid)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if UnitGUID("raid" .. i) == guid then return "raid" .. i end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            if UnitGUID("party" .. i) == guid then return "party" .. i end
        end
    end
end

-- A unit's world position and continent wherever the map is looking.
local function unitWorldAnywhere(unit)
    local map = C_Map.GetBestMapForUnit(unit)
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, unit)
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    map = MinimapEngine:CanonicalizeMapID(map)
    local cont = MinimapEngine:FindContinent(map)
    local wx, wy
    if cont then wx, wy = MinimapEngine:GetWorldPos(map, x * 100, y * 100) end
    if not wx then return nil end
    return wx, wy, cont
end

function MinimapEngine:IsTrackingPlayer(guid)
    return tracked ~= nil and guid ~= nil and tracked.guid == guid
end

function MinimapEngine:TrackPlayer(pt)
    if not pt or not pt.guid then return end
    tracked = { guid = pt.guid, kind = pt.kind, name = pt.name or "?",
        -- what /target needs: the name chat uses, else the first name
        target = pt.whisper or (pt.name or ""):match("^(%S+)") }
    say("tracking %s", tracked.name)
end

function MinimapEngine:StopTrackPlayer(why)
    if not tracked then return end
    if why then say("stopped tracking %s - %s", tracked.name, why) end
    tracked = nil
    for _, f in ipairs(self.TrackTrailFrms or {}) do f:Hide() end
end

-- The tracked player as an arrow target (QuestRouting's shape, kind =
-- "player"), or nil.
function MinimapEngine:TrackedPlayerTarget()
    if not tracked then return nil end
    local wx, wy, cont, detail, unit
    if tracked.kind == "party" or tracked.kind == "raid" then
        unit = groupUnitFor(tracked.guid)
        if not unit then
            self:StopTrackPlayer("they left your group")
            return nil
        end
        wx, wy, cont = unitWorldAnywhere(unit)
        detail = "Right-click the arrow to stop tracking"
    elseif tracked.kind == "guild" or tracked.kind == "friend" then
        local g = guild[tracked.guid]
        if not g then
            self:StopTrackPlayer("they stopped sharing where they are")
            return nil
        end
        cont = self:FindContinent(g.map)
        wx, wy = self:GetWorldPos(g.map, g.x, g.y)
        detail = "Right-click the arrow to stop tracking"
    else
        local e = enemies[tracked.guid]
        if not e then
            self:StopTrackPlayer("not seen for two minutes")
            return nil
        end
        wx, wy, cont = e.wx, e.wy, e.cont
        detail = ("Where you saw them %ds ago"):format(GetTime() - e.t)
    end
    if not wx or not cont then return nil end    -- in a dungeon, say
    local t = trackTarget
    t.kind, t.x, t.y, t.cont, t.inside = "player", wx, wy, cont, nil
    t.name, t.detail = "Tracking " .. tracked.name, detail
    t.unit, t.npc = unit, tracked.target      -- the arrow's click-to-target
    return t
end

local function inBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

local function BlipOnMouseUp(frm, button)
    local pt = frm.blip
    if button ~= "RightButton" or not pt then return end
    local BigMap = AlchemyGPS.Modules.Map.BigMap
    if not (BigMap and BigMap.OpenMenu) then return end
    GameTooltip:Hide()
    local items = { { pt.name or "?", nil, nil, true } }
    if MinimapEngine:IsTrackingPlayer(pt.guid) then
        items[#items + 1] = { "Stop tracking", function() MinimapEngine:StopTrackPlayer() end }
    elseif pt.guid then
        items[#items + 1] = { "Track with the arrow", function() MinimapEngine:TrackPlayer(pt) end }
    end
    if pt.whisper and pt.kind ~= "enemy" then
        items[#items + 1] = { "Whisper", function()
            if ChatFrame_SendTell then ChatFrame_SendTell(pt.whisper) end
        end }
    end
    if pt.whisper and (pt.kind == "guild" or pt.kind == "friend") then
        items[#items + 1] = { "Invite to group", function()
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(pt.whisper)
            elseif InviteUnit then
                InviteUnit(pt.whisper)
            end
        end }
    end
    if pt.unit and inBattleground() and ReportPlayerIsPVPAFK then
        items[#items + 1] = { "Report AFK", function()
            if UnitExists(pt.unit) then ReportPlayerIsPVPAFK(pt.unit) end
        end }
    end
    BigMap.OpenMenu(frm, items)
end

local function collect(engine)
    local pts = {}

    -- Party / raid. inGroup is keyed by GUID, so a guildmate who is
    -- also in the group is drawn once, in the group color.
    local inRaid = IsInRaid()
    local doParty, doRaid = filterOn("party"), filterOn("raid")
    local inGroup = {}
    local function addMember(unit, kind)
        if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
        local guid = UnitGUID(unit)
        if isMyGUID(guid) then return end
        if guid then inGroup[guid] = true end
        if (kind == "party" and not doParty) or (kind == "raid" and not doRaid) then return end
        local wx, wy = unitWorld(engine, unit)
        if wx then
            local _, class = UnitClass(unit)
            pts[#pts + 1] = { x = wx, y = wy, kind = kind, name = unitFullName(unit) or "?",
                class = class, level = UnitLevel(unit), guid = guid, unit = unit,
                whisper = (UnitName(unit)) }
        end
    end
    if inRaid then
        local mySub
        local n = GetNumGroupMembers()
        local subs = {}
        for i = 1, n do
            local _, _, sub = GetRaidRosterInfo(i)
            subs[i] = sub
            if UnitIsUnit("raid" .. i, "player") then mySub = sub end
        end
        for i = 1, n do
            addMember("raid" .. i, (subs[i] == mySub) and "party" or "raid")
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            addMember("party" .. i, "party")
        end
    end

    -- Guild (skip anyone already drawn as a group member)
    local now = GetTime()
    for guid, g in pairs(guild) do
        -- 2026-11-18: guild, or a friend heard only by whisper.
        local kind = (g.guildT and now - g.guildT <= GUILD_TTL) and "guild" or "friend"
        if now - g.t > (kind == "guild" and GUILD_TTL or FRIEND_TTL) or isMyGUID(guid) then
            guild[guid] = nil
        else
            if filterOn(kind) and not inGroup[guid] then
                local cont = engine:FindContinent(g.map)
                if cont and cont == engine.Cont then
                    local wx, wy = engine:GetWorldPos(g.map, g.x, g.y)
                    if wx then
                        pts[#pts + 1] = { x = wx, y = wy, kind = kind, name = g.name,
                            class = g.class, level = g.level, guid = guid, whisper = g.sender }
                    end
                end
            end
        end
    end

    -- Enemies
    local factionIcons = optOn("EnemyFactionIcons", false)
    for guid, e in pairs(enemies) do
        local age = now - e.t
        if age > ENEMY_TTL or isMyGUID(guid) then
            enemies[guid] = nil
        elseif filterOn("enemy") and e.cont == engine.Cont then
            local fade = 1 - (1 - ENEMY_MIN_ALPHA) * (age / ENEMY_TTL)
            local pt = { x = e.wx, y = e.wy, kind = "enemy", name = e.name,
                class = e.class, level = e.level, seen = e.t, alpha = fade, guid = guid }
            if factionIcons and e.faction and FACTION_TEX[e.faction] then
                pt.tex = FACTION_TEX[e.faction]
                pt.size = FACTION_SIZE
            end
            pts[#pts + 1] = pt
        end
    end

    return pts
end

function MinimapEngine:UpdatePlayerBlips()
    if not self.Frm or not self.Cont then
        if self.PlayerBlipFrms then
            for _, f in ipairs(self.PlayerBlipFrms) do f:Hide() end
        end
        return
    end
    self.PlayerBlipFrms = self.PlayerBlipFrms or {}

    local now = GetTime()
    if not self.PlayerBlipAt or now >= self.PlayerBlipAt then
        self.PlayerBlipAt = now + GROUP_REFRESH
        self.PlayerBlipPts = collect(self)
    end
    local pts = self.PlayerBlipPts or {}
    local frms = self.PlayerBlipFrms

    for n = #frms + 1, #pts do
        local frm = self:CreateMiniFrame()
        frm:EnableMouse(true)
        frm:SetScript("OnEnter", BlipOnEnter)
        frm:SetScript("OnLeave", BlipOnLeave)
        frm:SetScript("OnMouseUp", BlipOnMouseUp)
        frms[n] = frm
    end

    -- One level above the Service layer: over quest/service icons,
    -- still under the player marker (overlay strata).
    local level = (self.Frm:GetFrameLevel() or 1) + (self.SERVICE_LEVEL_OFFSET or 6) + 1
    for i, pt in ipairs(pts) do
        local frm = frms[i]
        local tex = pt.tex or TEX[pt.kind]
        if frm.blipTex ~= tex then
            frm.texture:SetTexture(tex)
            frm.blipTex = tex
        end
        frm.blip = pt
        local size = pt.size or DOT_SIZE
        if tracked and pt.guid == tracked.guid then size = size * 1.4 end
        if self:ClipFrameW(frm, pt.x, pt.y, size, size) then
            frm:SetFrameLevel(level)
            if pt.kind == "enemy" and not pt.tex then
                frm.texture:SetVertexColor(1, 0.15, 0.15, 1)
            elseif pt.kind == "friend" then
                frm.texture:SetVertexColor(1, 0.85, 0.15, 1)
            else
                frm.texture:SetVertexColor(1, 1, 1, 1)
            end
            frm:SetAlpha(pt.alpha or 1)
        end
    end
    for n = #pts + 1, #frms do
        frms[n]:Hide()
    end

    -- 2026-11-18: the ant trail to a tracked player, light blue.
    self.TrackTrailFrms = self.TrackTrailFrms or {}
    local t = tracked and self:TrackedPlayerTarget()
    if t and t.cont == self.Cont and self.PlyrX then
        local dx, dy = t.x - self.PlyrX, t.y - self.PlyrY
        self:DrawAntTrail(self.TrackTrailFrms, dx, dy, (dx * dx + dy * dy) ^ .5, .4, .8, 1, 1)
    else
        for _, f in ipairs(self.TrackTrailFrms) do f:Hide() end
    end
end

---------------------------------------------------------------------------------------
-- /gps blips - prints every player dot the map currently has, with the
-- data behind it, so a stray dot can be identified instead of guessed.
---------------------------------------------------------------------------------------

AlchemyGPS.Core.SlashCommands:Register("blips", function()
    local print = function(...) DEFAULT_CHAT_FRAME:AddMessage(string.format(...)) end
    print("|cffffd100Alchemy GPS player dots|r  (you: %s / %s)",
        tostring(unitFullName("player")), tostring(UnitGUID("player")))
    local pts = MinimapEngine.PlayerBlipPts or {}
    if #pts == 0 then print("  none drawn") end
    for _, pt in ipairs(pts) do
        print("  %s  %s", pt.kind, tostring(pt.name))
    end
    for guid, g in pairs(guild) do
        print("  guild entry: name=%s sender=%s guid=%s age=%ds",
            tostring(g.name), tostring(g.sender), tostring(guid), GetTime() - g.t)
    end
end, "list the party/raid/guild/enemy dots on the map")
