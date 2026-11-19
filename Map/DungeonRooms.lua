---------------------------------------------------------------------------------------
-- Azeroth Atlas | Map/DungeonRooms.lua
--
-- 2026-11-16. Inside a WoW Forever dungeon the game gives addons no
-- position at all (UnitPosition and C_Map.GetPlayerMapPosition are nil,
-- GetBestMapForUnit names no map). It DOES still name the room you are
-- in: the subzone text over the minimap ("Deep Archives",
-- "Ataal'Byzal"). Knowing where each room lies on the dungeon's level
-- art gives, as close as the game allows:
--   * which level you are on - the map turns to it by itself
--   * "you are in this room" - a glow over the room on the map
--   * party members' rooms - shared over the party channel by everyone
--     running Azeroth Atlas, and read from Forever Dungeon Routes' own
--     party messages too, so its users show up as well
--
-- Room data (Map/Data/DungeonRoomData.lua, made by
-- Tools/gen_dungeon_rooms.py): Forever Dungeon Routes by Checkov23 (MIT
-- license, github.com/Checkov23/ForeverDungeonRoutes), which generates
-- it from the client's own building files - every dungeon and raid with
-- named rooms. Classic ones sit on the game's own dungeon maps (the
-- maps drawn here too); WoW Forever's own on the Santiago Reyes art
-- Forever Dungeon Journal ships, matched level by level by picture name
-- (checked on The Drowned City 2026-11-16: Captain Dreadrise in Altar of
-- the Serpent, Var'Taka in Deep Archives, Min'loth on the Abyssal Dais).
-- 2026-11-16 extended from The Drowned City to all of them (user
-- request).
--
-- MIT License - Copyright (c) 2026 Checkov23 (room data below).
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files, to deal in
-- the Software without restriction, subject to the above copyright
-- notice and this permission notice being included in all copies or
-- substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS
-- IS", WITHOUT WARRANTY OF ANY KIND.
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
local MinimapEngine = AzerothAtlas.Modules.Map.MinimapEngine

-- Box sizes are pixels of the 1002x668 level map; u, v its 0-1 centre.
local MAP_W, MAP_H = 1002, 668

-- Map/Data/DungeonRoomData.lua (Tools/gen_dungeon_rooms.py):
-- Rooms[instanceID] = { { name, { level, u, v, width, height }, ... } }
-- where level < 100 is a Forever Dungeon Journal level index and
-- anything else the game's uiMapID.
local DATA = AzerothAtlas.DungeonRoomData or {}
local ROOMS = DATA.Rooms or {}
local FDR_KEYS = DATA.FDRKeys or {}

-- Other spellings of a room name the game may show.
local ALIASES = { ["Atal'Byzal"] = "Ataal'Byzal" }

-- Client maps of an instance, for MinimapEngine:BuildDungeonFloors when
-- the game names no map inside it.
function MinimapEngine:GetInstanceClientFloors(instanceID)
    return DATA.ClientFloors and DATA.ClientFloors[instanceID]
end

-- Extra levels drawn from the game's old map tiles (Upper Blackrock
-- Spire), appended to an instance's floors by ResolveDungeonMap.
function MinimapEngine:GetInstanceTileFloors(instanceID)
    return DATA.TileFloors and DATA.TileFloors[instanceID]
end
local FDR_PREFIX = "FDRGroup"
local COMM_PREFIX = "AzerothAtlas1"

local SEND_GAP = 2          -- seconds between two room messages of ours
local RESEND = 10           -- say it again this often while inside
local MEMBER_TTL = 35       -- forget a member not heard from in this long

local GFX = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Map\\"

---------------------------------------------------------------------------------------
-- Rooms
---------------------------------------------------------------------------------------

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function roomNamed(instanceID, name)
    local list = instanceID and ROOMS[instanceID]
    if not list or type(name) ~= "string" or name == "" then return nil end
    name = ALIASES[name] or name
    for _, room in ipairs(list) do
        if room[1] == name then return room end
    end
    return nil
end

-- Index into the engine's floors of the level a box is on, or nil when
-- that level isn't one of them (a client map of another wing that isn't
-- loaded; a Forever level drawn without FDJ's art).
local function boxLevel(b)
    local floors = MinimapEngine.DungeonFloors
    if not floors then return nil end
    local ref = b[1]
    if ref < 100 then
        local f = floors[ref]
        return (f and f.spec and f.spec.fdjName) and ref or nil
    end
    for i, f in ipairs(floors) do
        if f.mapId == ref or f.posMap == ref
            or (f.spec and (f.spec.fdrFloor == ref or f.spec.clientMap == ref)) then
            return i
        end
    end
    return nil
end

-- The level showing most of the room.
local function mainLevel(room)
    local area, best, bestArea = {}, nil, nil
    for n = 2, #room do
        local b = room[n]
        local level = boxLevel(b)
        if level then area[level] = (area[level] or 0) + b[4] * b[5] end
    end
    for level, a in pairs(area) do
        if not bestArea or a > bestArea or (a == bestArea and level < best) then
            best, bestArea = level, a
        end
    end
    return best
end

-- Centre (0-1 on the level's map, weighted by area) and a radius that
-- covers the room, as fractions of the map's width and height.
local function roomShape(room, level)
    local su, sv, sum = 0, 0, 0
    for n = 2, #room do
        local b = room[n]
        if boxLevel(b) == level then
            local a = b[4] * b[5]
            su, sv, sum = su + b[2] * a, sv + b[3] * a, sum + a
        end
    end
    if sum == 0 then return nil end
    local u, v = su / sum, sv / sum
    local r = 0
    for n = 2, #room do
        local b = room[n]
        if boxLevel(b) == level then
            local dx, dy = (b[2] - u) * MAP_W, (b[3] - v) * MAP_H
            local d = math.sqrt(dx * dx + dy * dy) + 0.5 * math.sqrt(b[4] * b[4] + b[5] * b[5])
            if d > r then r = d end
        end
    end
    return u, v, r / MAP_W
end

-- 2026-11-19 (user: Shady Saltseers - "since this quest is separate from
-- the boss can we just show the area on the map like we do with other
-- quests outside?"). A room shaded in the quest's colour for every
-- unfinished objective QuestData.DungeonObjectiveRooms ties to a room of
-- this dungeon - the same soft disc as "You are in ...", drawn under
-- the icons. { match = lower-case objective text, room = room name,
-- text = where exactly } (Quest/Data/QuestDBManual.lua).
function MinimapEngine:GetQuestRoomPins(level, place, zw)
    local pts = {}
    local instanceID = self.DungeonInstance
    local QD = AzerothAtlas.QuestData or {}
    local defs = instanceID and QD.DungeonObjectiveRooms and QD.DungeonObjectiveRooms[instanceID]
    local Quest = AzerothAtlas.Modules.Quest
    local State, Pins = Quest and Quest.State, Quest and Quest.Pins
    if not defs or not State or not State.Quests then return pts end
    for _, q in ipairs(State.Quests) do
        for _, o in ipairs(q.objectives or {}) do
            if not o.finished and type(o.text) == "string" and o.text ~= "" then
                local text = o.text:lower()
                for _, d in ipairs(defs) do
                    local room = text:find(d.match, 1, true) and roomNamed(instanceID, d.room)
                    local u, v, r
                    if room then u, v, r = roomShape(room, level) end
                    if u then
                        local wx, wy = place(u, v)
                        local cr, cg, cb = 1, 0.82, 0
                        if Pins and Pins.QuestColor then cr, cg, cb = Pins:QuestColor(q.questID) end
                        pts[#pts + 1] = {
                            x = wx, y = wy, kind = "questroom", tex = GFX .. "IconCircleFade",
                            worldSize = 2 * r * zw, minSize = 28, r = cr, g = cg, b = cb, alpha = 0.5,
                            title = q.title, under = true,
                        }
                        -- The disc lets clicks through to the map; this
                        -- ring in its middle carries the tooltip.
                        pts[#pts + 1] = {
                            x = wx, y = wy, kind = "questroomdot", tex = GFX .. "IconRing", size = 18,
                            r = cr, g = cg, b = cb, quest = true, title = q.title,
                            lines = { o.text, d.text or room[1] },
                        }
                    end
                end
            end
        end
    end
    return pts
end

-- The room the game says the player is in, inside a dungeon we have
-- rooms for, or nil.
function MinimapEngine:GetPlayerRoom()
    local instanceID = self.DungeonInstance
    if not instanceID or not ROOMS[instanceID] then return nil end
    local text = GetSubZoneText and GetSubZoneText()
    if not readable(text) then return nil end
    local room = roomNamed(instanceID, text)
    if not room then
        local zone = GetMinimapZoneText and GetMinimapZoneText()
        if readable(zone) then room = roomNamed(instanceID, zone) end
    end
    return room
end

-- 2026-11-19 (user: "no general level area we can detect leaving the
-- small boss room ... being in the general area with no named room?").
-- [instanceID] = the level the player is on when the game names no room
-- at all - for dungeons where every other level is wholly one named area.
-- The Drowned City: Atal'Byzal (level 2) is the lower level's only room;
-- every unnamed spot is the city itself.
local UNNAMED_LEVEL = {
    [2970] = 1,
}

-- True when the game shows no room name: empty, or only the dungeon's.
local function noRoomNamed()
    local sub = GetSubZoneText and GetSubZoneText()
    if not readable(sub) then return false end
    if sub == "" then return true end
    local zone = GetRealZoneText and GetRealZoneText()
    return readable(zone) and sub == zone
end

-- Level (index into floors) the player's room is on - for
-- ResolveDungeonMap.
function MinimapEngine:GetRoomLevel(floors)
    if not floors or not floors[1] then return nil end
    local room = self:GetPlayerRoom()
    local level = room and mainLevel(room)
    if level and floors[level] then return level, room end
    local unnamed = not room and UNNAMED_LEVEL[self.DungeonInstance]
    if unnamed and floors[unnamed] and noRoomNamed() then return unnamed end
    return nil
end

---------------------------------------------------------------------------------------
-- Party sharing
---------------------------------------------------------------------------------------

local members = {}   -- [key] = { name, class, instance, room, t, sender }

local function groupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function unitFullName(unit)
    local first, last = UnitName(unit)
    if not readable(first) or first == "" then return nil end
    if readable(last) and last ~= "" then return first .. " " .. last end
    return first
end

-- Chat senders come as "First-Suffix" (last name or realm).
local function senderIsMe(sender)
    if not readable(sender) then return true end
    local base, suffix = sender:match("^([^%-]+)%-?(.*)$")
    local first, last = UnitName("player")
    if base ~= first then return false end
    if not suffix or suffix == "" or suffix == last then return true end
    return GetNormalizedRealmName and suffix == GetNormalizedRealmName() or false
end

local function senderName(sender)
    local base, suffix = sender:match("^([^%-]+)%-?(.*)$")
    if not suffix or suffix == "" or (GetNormalizedRealmName and suffix == GetNormalizedRealmName()) then
        return base or sender
    end
    return base .. " " .. suffix
end

-- Class of a group member, by matching the sender to a party/raid unit.
local function senderClass(sender)
    local base = sender:match("^([^%-]+)")
    local prefix, n = "party", 4
    if IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local unit = prefix .. i
        if UnitExists(unit) and UnitName(unit) == base then
            local _, class = UnitClass(unit)
            return class
        end
    end
    return nil
end

local lastSent, lastSentAt = nil, 0
local function sendRoom(force)
    local channel = groupChannel()
    if not channel or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        lastSent = nil
        return
    end
    local instanceID = MinimapEngine.DungeonInstance
    local room = MinimapEngine:GetPlayerRoom()
    local msg = ("R|%d|%s|%s|%s"):format(room and instanceID or 0, room and room[1] or "",
        UnitGUID("player") or "", (unitFullName("player") or ""):gsub("|", ""))
    local now = GetTime()
    if not force and msg == lastSent and now - lastSentAt < RESEND then return end
    if now - lastSentAt < SEND_GAP and not force then return end
    if not room and lastSent == nil then return end   -- nothing to say, nothing to take back
    lastSent, lastSentAt = room and msg or nil, now
    pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, channel)
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(FDR_PREFIX)
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local function onAddonMessage(prefix, msg, channel, sender)
    if not GROUP_CHANNELS[channel] or not readable(msg) or not readable(sender) then return end
    if senderIsMe(sender) then return end
    local now = GetTime()
    if prefix == COMM_PREFIX then
        local kind, instanceID, room, guid, fullName = strsplit("|", msg)
        if kind ~= "R" then return end
        if guid and guid ~= "" and guid == UnitGUID("player") then return end
        members["fdr:" .. sender] = nil   -- running both addons: show once
        instanceID = tonumber(instanceID)
        if not instanceID or instanceID == 0 or not roomNamed(instanceID, room) then
            members[sender] = nil
            return
        end
        members[sender] = {
            name = (fullName and fullName ~= "") and fullName or senderName(sender),
            class = senderClass(sender), instance = instanceID, room = room, t = now,
        }
    elseif prefix == FDR_PREFIX then
        if members[sender] then return end   -- we already hear them directly
        local kind, key, room = strsplit("\t", msg)
        if kind ~= "P" then return end
        local instanceID = FDR_KEYS[key or ""]
        if not instanceID or not roomNamed(instanceID, room) then
            members["fdr:" .. sender] = nil
            return
        end
        members["fdr:" .. sender] = {
            name = senderName(sender), class = senderClass(sender),
            instance = instanceID, room = room, t = now, fdr = true,
        }
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        pcall(onAddonMessage, ...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not groupChannel() then wipe(members) end
        C_Timer.After(1, function() pcall(sendRoom, true) end)
    else
        -- The engine reads the instance on its next tick; send after it.
        C_Timer.After(0.5, function() pcall(sendRoom) end)
    end
end)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(RESEND, function() pcall(sendRoom) end)
end

---------------------------------------------------------------------------------------
-- Map pins (collected by DungeonPins.lua, same 0-1 placement)
---------------------------------------------------------------------------------------

local function classColor(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) end
    return name
end

-- Pins for the level being looked at. place(u, v) -> world x, y; zw is
-- the level's world width (sizes the room glow).
function MinimapEngine:GetRoomPins(level, place, zw)
    local pts = {}
    local instanceID = self.DungeonInstance
    if not instanceID or not ROOMS[instanceID] then return pts end

    -- You: only while the game hides your real position.
    local room = self.PlyrPosUnknown and self:GetPlayerRoom()
    if room then
        local u, v, r = roomShape(room, level)
        if u then
            local wx, wy = place(u, v)
            pts[#pts + 1] = {
                x = wx, y = wy, kind = "room", tex = GFX .. "IconCircleFade",
                worldSize = 2 * r * zw, minSize = 28, r = 0.3, g = 1, b = 0.3, alpha = 0.45,
                title = "You are in " .. room[1], under = true,
                lines = { "The game names the room you're in, not the spot,", "so the whole room is marked." },
            }
            pts[#pts + 1] = {
                x = wx, y = wy, kind = "you", tex = GFX .. "IconRing", size = 22,
                r = 0.3, g = 1, b = 0.3, title = "You (" .. room[1] .. ")",
            }
        end
    end

    -- Group members, spread around their room's centre - only while the
    -- game hides positions (otherwise PlayerBlips shows them exactly).
    if not self.PlyrPosUnknown then return pts end
    local now = GetTime()
    local byRoom = {}
    for key, m in pairs(members) do
        if now - m.t > MEMBER_TTL then
            members[key] = nil
        elseif m.instance == instanceID then
            local rm = roomNamed(instanceID, m.room)
            if rm then
                byRoom[rm] = byRoom[rm] or {}
                table.insert(byRoom[rm], m)
            end
        end
    end
    for rm, list in pairs(byRoom) do
        local u, v, r = roomShape(rm, level)
        if u then
            table.sort(list, function(a, b) return a.name < b.name end)
            local spread = math.min(r, 0.02)
            for i, m in ipairs(list) do
                local a = (i - 1) * 2 * math.pi / #list
                local du = (#list > 1) and spread * math.cos(a) or 0
                local dv = (#list > 1) and spread * math.sin(a) * MAP_W / MAP_H or 0
                local wx, wy = place(u + du, v + dv)
                pts[#pts + 1] = {
                    x = wx, y = wy, kind = "member", tex = GFX .. "IconPlyrP", size = 14,
                    title = classColor(m.name, m.class),
                    lines = { "In " .. rm[1] .. (m.fdr and " (Forever Dungeon Routes)" or ""),
                        "Room only: the game gives no exact position." },
                }
            end
        end
    end
    return pts
end

-- /aatlas where line.
function MinimapEngine:DescribeRoom()
    local text = GetSubZoneText and GetSubZoneText()
    local room = self:GetPlayerRoom()
    local n = 0
    for _ in pairs(members) do n = n + 1 end
    return ("subzone %q -> %s; %d group member(s) heard"):format(
        readable(text) and text or "?", room and (room[1] .. ", level " .. tostring(mainLevel(room))) or "no room", n)
end
