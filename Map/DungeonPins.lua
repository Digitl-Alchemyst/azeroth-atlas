---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/DungeonPins.lua
--
-- 2026-11-16 (user request: "show all the quest locations on the
-- dungeon map"). Marks drawn over a dungeon level:
--   bosses       the boss's portrait (skull when none can be drawn);
--                gold and larger when a quest in your log needs it
--   transitions  the way to another level: an arrow, click to look at
--                that level
--   entrance     where you come in
--   quests       givers and turn-ins standing inside the dungeon
--
-- 2026-11-17 (user request: "mark the entrance with the Leatrix icons",
-- "it still shows the skulls not the boss portraits", "1 quest is not
-- showing, a quest I can pick up here is not showing"):
--   * Leatrix Maps' own pins come first (Map/Data/LeatrixDungeonPins.lua,
--     keyed by the game map of the level): every classic dungeon level's
--     entrance, level arrows and bosses - with each boss's display ID,
--     so its portrait can always be drawn. Forever Dungeon Journal's
--     DUNGEON_MAPS is the fallback (WoW Forever's own dungeons).
--   * Icons are Leatrix's: the game's Dungeon / Raid map pin for the
--     entrance, Garr_LevelUpgradeArrow for the level arrows.
--   * A boss without a display ID is matched by name to FDJ's journal
--     record (FDJ.DB[dungeon].bosses: its NPC id), which is what
--     FDJ.SetBossPortrait needs - the map's own boss rows have only a
--     name and a spot, which is why the skulls stayed.
--   * A quest needs a boss when an unfinished objective names it, or FDJ's
--     journal text for the quest does ("kill Amnennar the Coldbringer and
--     return his skull" - the objective itself only says "Skull of the
--     Coldbringer").
--   * Quest givers and turn-ins inside the dungeon come from FDJ's
--     MAP_QUEST_PINS (Belnistrasz in Razorfen Downs): a turn-in for a
--     quest in your log, a pickup for one you can take.
-- Positions are 0-1 on the level's art, the same art drawn under them,
-- so they line up whether or not the game reports where you are.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine

local BOSS_SIZE, QUEST_SIZE, LEVEL_SIZE, ENTRANCE_SIZE, SPOT_SIZE = 24, 30, 22, 24, 22
local RING_EXTRA = 8                      -- the quest ring round a quest boss
local PORTRAIT_RETRY = 3                  -- seconds before asking FDJ again
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GFX = "Interface\\AddOns\\AlchemyGPS\\Gfx\\Map\\"
local COLLECT_INTERVAL = 0.5

-- Icon specs (UI/StyleOptions.lua's shape: tex / atlas / coords).
local SPEC = {
    boss     = { tex = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
    entrance = { atlas = "Dungeon", fallback = "Interface\\Icons\\INV_Misc_Bone_Skull_02" },
    raid     = { atlas = "Raid", fallback = "Interface\\Icons\\INV_Misc_Bone_Skull_02" },
    level    = { atlas = "Garr_LevelUpgradeArrow", fallback = "Interface\\Icons\\INV_Misc_Map_01" },
    ring     = { tex = GFX .. "IconRing" },
}
local texSpecs = {}   -- plain-texture specs for pins that only name a texture (room pins)
local function specFor(pt)
    if pt.iconSpec then return pt.iconSpec end
    local s = texSpecs[pt.tex or ""]
    if not s then
        s = { tex = pt.tex }
        texSpecs[pt.tex or ""] = s
    end
    return s
end

local function fdj()
    local t = _G.FDJ or _G.ForeverDungeonJournal_NS
    return type(t) == "table" and t or nil
end

-- FDJ's own label for a transition ("Shark exit", "Swim down here").
local function fdjText(key, ...)
    local t = fdj()
    if not key or not t then return nil end
    local L = t.L
    if type(L) == "function" then
        local ok, s = pcall(L, key, ...)
        if ok and type(s) == "string" and s ~= key then return s end
    elseif type(L) == "table" and type(L[key]) == "string" then
        return L[key]
    end
    return nil
end

-- "Oggleflint <Ragefire Chieftain>" -> "Oggleflint"; "Sneed's Shredder /
-- Sneed" -> the shown name plus each name a quest might use.
local function bossNames(name)
    name = tostring(name or "?"):gsub("%s*<.->", "")
    local names = {}
    for part in (name .. " / "):gmatch("(.-) / ") do
        if part ~= "" then names[#names + 1] = part end
    end
    if #names == 0 then names[1] = name end
    return name, names
end

-- FDJ's journal text for a quest (lower case), by quest id, built once.
local journalObjective
local function journalText(questID)
    if not journalObjective then
        local t = fdj()
        if not t or type(t.DB) ~= "table" then return nil end
        journalObjective = {}
        for _, d in pairs(t.DB) do
            if type(d) == "table" and type(d.quests) == "table" then
                for _, q in ipairs(d.quests) do
                    if type(q) == "table" and q.id and type(q.objective) == "string" then
                        journalObjective[q.id] = q.objective:lower()
                    end
                end
            end
        end
    end
    return journalObjective[questID]
end

-- FDJ's journal record for a boss (it has the NPC id the portrait needs).
local function journalBoss(dungeon, names)
    local t = fdj()
    local d = t and type(t.DB) == "table" and t.DB[dungeon]
    if type(d) ~= "table" or type(d.bosses) ~= "table" then return nil end
    for _, b in ipairs(d.bosses) do
        if type(b) == "table" and type(b.name) == "string" then
            local lname = b.name:lower()
            for _, n in ipairs(names or {}) do
                if lname == n:lower() then return b end
            end
        end
    end
    return nil
end

-- Lower-cased boss name -> { "Quest title: objective", ... } for every
-- unfinished objective in the log that needs that boss: the objective
-- names it, QuestData.DungeonQuestBosses says it drops the item, FDJ's
-- journal text for the quest names it, or - by
-- QuestData.DungeonObjectiveHints - the objective is found near it (the
-- Tablets of I'lalai, which no addon or database has a position for).
local function questNeeds(bosses, instanceID)
    local Quest = AlchemyGPS.Modules.Quest
    local State = Quest and Quest.State
    local QD = AlchemyGPS.QuestData or {}
    local drops = QD.DungeonQuestBosses or {}
    local hints = instanceID and QD.DungeonObjectiveHints and QD.DungeonObjectiveHints[instanceID] or {}
    local needs = {}
    if not State or not State.Quests then return needs end
    local function add(lname, line)
        local list = needs[lname] or {}
        for _, l in ipairs(list) do
            if l == line then return end
        end
        list[#list + 1] = line
        needs[lname] = list
    end
    for _, q in ipairs(State.Quests) do
        local first
        for _, o in ipairs(q.objectives or {}) do
            if not o.finished and o.text ~= "" then
                first = first or o
                local text = o.text:lower()
                for _, b in ipairs(bosses) do
                    for _, n in ipairs(b.names) do
                        local lname = n:lower()
                        if text:find(lname, 1, true) or drops[q.questID] == n then
                            add(lname, q.title .. ": " .. o.text)
                        end
                    end
                end
                for _, h in ipairs(hints) do
                    if text:find(h.match, 1, true) then
                        add(h.boss:lower(), q.title .. ": " .. o.text)
                        add(h.boss:lower(), "|cffa0a0a0" .. h.text .. "|r")
                    end
                end
            end
        end
        local jt = first and journalText(q.questID)
        if jt then
            for _, b in ipairs(bosses) do
                for _, n in ipairs(b.names) do
                    local lname = n:lower()
                    if jt:find(lname, 1, true) then add(lname, q.title .. ": " .. first.text) end
                end
            end
        end
    end
    return needs
end

local function needsFor(needs, b)
    local all
    for _, n in ipairs(b.names) do
        local list = needs[n:lower()]
        if list then
            all = all or {}
            for _, l in ipairs(list) do all[#all + 1] = l end
        end
    end
    return all
end

-- Whether a quest could be picked up now (not done, not in the log, its
-- prerequisites met).
local function canPickUp(questID)
    local Quest = AlchemyGPS.Modules.Quest
    local Api, Rules = Quest and Quest.Api, Quest and Quest.Rules
    if Api and Api.IsFlaggedCompleted and Api:IsFlaggedCompleted(questID) then return false end
    if Rules and Rules.Check then
        local ok = Rules:Check(questID)
        return ok and true or false
    end
    return true
end

-- Quest givers and turn-ins inside the dungeon (FDJ.MAP_QUEST_PINS).
local function questSpots(pts, fdjName, floor, place)
    local t = fdj()
    local list = fdjName and t and type(t.MAP_QUEST_PINS) == "table" and t.MAP_QUEST_PINS[fdjName]
    if type(list) ~= "table" then return end
    local Quest = AlchemyGPS.Modules.Quest
    local State = Quest and Quest.State
    local StyleOptions = AlchemyGPS.UI.StyleOptions
    -- 2026-11-17: a quest that ends somewhere other than its giver (FDJ
    -- lists Extinguishing the Idol as ending at Belnistrasz and at his
    -- brazier; the escort ends at the brazier, the bonfire) is handed in
    -- only there.
    local endsElsewhere = {}
    for _, g in ipairs(list) do
        for _, s in ipairs(type(g) == "table" and type(g.spots) == "table" and g.spots or {}) do
            for _, q in ipairs(type(s.quests) == "table" and s.quests or {}) do
                local st, en = false, false
                for _, a in ipairs(q.acts or {}) do
                    if a == "start" then st = true elseif a == "end" then en = true end
                end
                if en and not st and q.id then endsElsewhere[q.id] = true end
            end
        end
    end
    for _, g in ipairs(list) do
        if type(g) == "table" and (g.floor or 1) == floor and type(g.x) == "number" and type(g.y) == "number" then
            local lines, names, rank = {}, {}, 0     -- rank: 3 ready to hand in, 2 can pick up, 1 in progress
            for _, s in ipairs(type(g.spots) == "table" and g.spots or {}) do
                local shown = false
                for _, q in ipairs(type(s.quests) == "table" and s.quests or {}) do
                    local acts = {}
                    for _, a in ipairs(q.acts or {}) do acts[a] = true end
                    if acts.start and acts["end"] and endsElsewhere[q.id] then acts["end"] = nil end
                    local inLog = q.id and State and State.GetQuest and State:GetQuest(q.id)
                    if inLog and acts["end"] then
                        if inLog.ready then
                            lines[#lines + 1] = "|cff40ff40Turn in:|r " .. (q.name or inLog.title or "?")
                            rank = math.max(rank, 3)
                        else
                            lines[#lines + 1] = "|cffa0a0a0In progress:|r " .. (q.name or inLog.title or "?")
                            rank = math.max(rank, 1)
                        end
                        shown = true
                    elseif not inLog and acts.start and q.id and canPickUp(q.id) then
                        lines[#lines + 1] = "|cffffd100Pick up:|r " .. (q.name or "?")
                        rank = math.max(rank, 2)
                        shown = true
                    end
                end
                if shown and s.name then names[#names + 1] = s.name end
            end
            if rank > 0 then
                local wx, wy = place(g.x, g.y)
                pts[#pts + 1] = {
                    x = wx, y = wy, kind = "quest", size = SPOT_SIZE,
                    iconSpec = StyleOptions:GetOption(rank == 2 and "QuestGiverIcon" or "QuestIcon"),
                    desat = rank == 1 or nil, r = 1, g = 1, b = 1,
                    title = table.concat(names, ", "), lines = lines, quest = true, plain = true,
                }
            end
        end
    end
end

-- FDJ's data for a classic dungeon level drawn from the game's own map:
-- the entry and level index whose floor names that uiMapID.
local setPinArt   -- defined above UpdateDungeonPins

local function collect(engine)
    local pts = {}
    local mapId = engine:GetViewMapId()
    local level = engine:GetViewFloorIndex()
    local winfo = mapId and engine.MapWorldInfo[mapId]
    if not winfo or engine.HideDungeonArt then return pts end
    local _, zx, zy, zw, zh = engine:GetWorldZoneInfo(engine.DUNGEON_CONT, mapId)
    if not zx then return pts end
    local function place(x, y)
        return zx + x * zw, zy + y * zh
    end

    local spec = winfo.CustomArt
    local data, floor, fdjName
    if spec and spec.fdjName and spec.fdjFloor then
        local t = fdj()
        data, floor, fdjName = t and t.DUNGEON_MAPS and t.DUNGEON_MAPS[spec.fdjName], spec.fdjFloor, spec.fdjName
    elseif not spec and not winfo.Blank then
        -- FDJ's spots are on the game's own map art only.
        data, floor, fdjName = MinimapEngine:GetFDJForClientMap(mapId)
    end
    if type(data) ~= "table" then data = {} end
    floor = floor or 0

    -- Leatrix's pins: on any drawing of the game's own map of the level
    -- (C_Map art, the game's map tiles FDJ points at, Leatrix's art) -
    -- not on FDJ's own picture of a level (spec.path), whose spots differ.
    -- 2026-11-17: FDJ's Razorfen Downs is the game's tiles, and FDJ's list
    -- there lacks Plaguemaw (the quilboar at the bonfire) - Leatrix has him.
    local all = AlchemyGPS.LeatrixDungeonPins
    local lrows = not (spec and spec.path) and all
        and (all[mapId] or (spec and spec.clientMap and all[spec.clientMap])
            or (winfo.PosMap and all[winfo.PosMap]))

    -- Bosses: { x, y, name, names, level, displayID, rare, fdjBoss }.
    local blist = {}
    if lrows then
        for _, r in ipairs(lrows) do
            if r[1] == "boss" then
                local name, names = bossNames(r[5])
                blist[#blist + 1] = {
                    x = r[2], y = r[3], name = name, names = names, level = r[6], displayID = r[7],
                    rare = (r[8] == 2 or r[8] == 4) or nil, skullLevel = (r[8] == 3) or nil,
                }
            end
        end
    else
        for _, b in ipairs(type(data.bosses) == "table" and data.bosses or {}) do
            if (b.floor or 1) == floor and type(b.x) == "number" and type(b.y) == "number" then
                local name, names = bossNames(b.name)
                blist[#blist + 1] = { x = b.x, y = b.y, name = name, names = names, fdjBoss = b }
            end
        end
    end

    local needs = questNeeds(blist, engine.DungeonInstance)
    for _, b in ipairs(blist) do
        local wx, wy = place(b.x, b.y)
        local need = needsFor(needs, b)
        local size = need and QUEST_SIZE or BOSS_SIZE
        pts[#pts + 1] = {
            x = wx, y = wy, kind = "boss", iconSpec = SPEC.boss, size = size,
            r = 1, g = need and 0.82 or 1, b = need and 0 or 1,
            title = b.name, names = b.names, lines = need, quest = need and true or nil,
            boss = b.fdjBoss or { name = b.name }, fdjName = fdjName, displayID = b.displayID,
            level = b.level, rare = b.rare, skullLevel = b.skullLevel,
        }
        if need then
            pts[#pts + 1] = {
                x = wx, y = wy, kind = "ring", iconSpec = SPEC.ring, size = size + RING_EXTRA,
                r = 1, g = 0.82, b = 0, nomouse = true, quest = true,
            }
        end
    end

    -- Level arrows (the arrow points up for the level above).
    if lrows then
        for _, r in ipairs(lrows) do
            if r[1] == "level" and type(r[4]) == "number" then
                local wx, wy = place(r[2], r[3])
                local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r[4])
                pts[#pts + 1] = {
                    x = wx, y = wy, kind = "level", iconSpec = SPEC.level, size = LEVEL_SIZE,
                    rot = r[5] and 0 or math.pi, r = 1, g = 1, b = 1,
                    title = (info and info.name) or (r[5] and "Way up" or "Way down"),
                    lines = { "Click to look at that level" }, toMap = r[4],
                }
            end
        end
    else
        for _, tr in ipairs(type(data.transitions) == "table" and data.transitions or {}) do
            if (tr.floor or 1) == floor and type(tr.x) == "number" and type(tr.y) == "number" and tr.to then
                local wx, wy = place(tr.x, tr.y)
                local label = fdjText(tr.labelKey, tr.to) or fdjText(tr.tipKey, tr.to)
                local c = tr.color
                pts[#pts + 1] = {
                    x = wx, y = wy, kind = "level", iconSpec = SPEC.level, size = LEVEL_SIZE,
                    rot = (tr.to < floor) and 0 or math.pi,
                    r = c and c[1] or 1, g = c and c[2] or 1, b = c and c[3] or 1,
                    title = label or ((tr.to > floor) and "Way down" or "Way up"),
                    lines = { "Click to look at that level" }, to = tr.to,
                    toMap = type(data.floors) == "table" and type(data.floors[tr.to]) == "table"
                        and data.floors[tr.to].uiMapID or nil,
                }
            end
        end
    end

    -- Entrance(s): the game's Dungeon / Raid pin, as Leatrix draws it.
    if lrows then
        for _, r in ipairs(lrows) do
            if r[1] == "entrance" then
                local wx, wy = place(r[2], r[3])
                local raid = r[4] == "raid"
                pts[#pts + 1] = {
                    x = wx, y = wy, kind = "entrance", iconSpec = raid and SPEC.raid or SPEC.entrance,
                    size = ENTRANCE_SIZE, r = 1, g = 1, b = 1, title = raid and "Raid entrance" or "Entrance",
                }
            end
        end
    else
        local e = data.entrance
        if type(e) == "table" and (e.floor or 1) == floor and type(e.x) == "number" then
            local wx, wy = place(e.x, e.y)
            pts[#pts + 1] = {
                x = wx, y = wy, kind = "entrance", iconSpec = SPEC.entrance, size = ENTRANCE_SIZE,
                r = 1, g = 1, b = 1, title = "Entrance",
            }
        end
    end

    -- Quest givers and turn-ins inside.
    questSpots(pts, fdjName, floor, place)

    -- You and your group, by the room the game names (DungeonRooms.lua).
    if engine.GetRoomPins then
        local you
        for _, p in ipairs(engine:GetRoomPins(level, place, zw)) do
            pts[#pts + 1] = p
            if p.kind == "you" then you = p end
        end
        -- Center on: bring a newly entered room into the middle.
        local room = you and you.title
        if room and room ~= engine.RoomCentered and engine:IsViewingPlayerFloor() then
            local win = AlchemyGPS.Modules.Map.MinimapWindow
            local ZoomController = AlchemyGPS.Modules.Map.ZoomController
            if ZoomController and not (win and win:DB().profile.AutoFollow == false) then
                ZoomController:Move(you.x, you.y, nil, 10)
            end
        end
        engine.RoomCentered = room
    end
    return pts
end

local function PinOnEnter(frm)
    local pt = frm.pin
    if not pt then return end
    GameTooltip:SetOwner(frm, "ANCHOR_CURSOR")
    GameTooltip:SetText(pt.title or "?", 1, 0.82, 0)
    if pt.kind == "boss" then
        if pt.rare then
            GameTooltip:AddLine("Rare", 0.7, 0.8, 1)
        else
            GameTooltip:AddLine("Boss", 1, 0.5, 0.25)
        end
        if pt.level then
            if pt.skullLevel or pt.level >= (UnitLevel("player") or 1) + 10 then
                GameTooltip:AddLine("Level ??", 1, 0.1, 0.1)
            else
                local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(pt.level)
                GameTooltip:AddLine("Level " .. pt.level, c and c.r or 1, c and c.g or 1, c and c.b or 1)
            end
        end
    end
    if pt.kind == "you" then
        GameTooltip:AddLine("The game names the room you're in, not the spot.", 0.9, 0.9, 0.9, true)
    end
    for _, line in ipairs(pt.lines or {}) do
        if pt.plain then
            GameTooltip:AddLine(line, 1, 1, 1, true)
        else
            GameTooltip:AddLine(line, pt.quest and 1 or 0.9, pt.quest and 0.82 or 0.9, pt.quest and 0 or 0.9, true)
        end
    end
    GameTooltip:Show()
end

local function PinOnLeave()
    GameTooltip:Hide()
end

local function PinOnMouseUp(frm, button)
    local pt = frm.pin
    if button == "LeftButton" and pt and (pt.to or pt.toMap) then
        -- A game map level: find it by map id (the game's level order
        -- may differ from FDJ's). FDJ art levels: same numbering.
        local engine = MinimapEngine
        local floors = engine.DungeonFloors
        if not floors then return end
        if pt.toMap then
            for i, f in ipairs(floors) do
                if f.mapId == pt.toMap then engine:SetViewFloor(i) return end
            end
            return
        end
        if floors[pt.to] then engine:SetViewFloor(pt.to) end
    end
end

---------------------------------------------------------------------------------------
-- Pin art
---------------------------------------------------------------------------------------

-- Round portraits: a mask texture on the pin, the way Leatrix rounds
-- its own (Texture:SetMask, used before, can leave the texture blank).
local function roundMask(frm, on)
    if not frm.CreateMaskTexture then return end
    if on then
        if not frm.portraitMask then
            local m = frm:CreateMaskTexture()
            m:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(frm.texture)
            frm.portraitMask = m
        end
        if not frm.maskOn then
            frm.texture:AddMaskTexture(frm.portraitMask)
            frm.maskOn = true
        end
    elseif frm.maskOn then
        frm.texture:RemoveMaskTexture(frm.portraitMask)
        frm.maskOn = nil
    end
end

-- Lets go of a boss portrait on this frame (FDJ's go back to its pool).
local function releasePortrait(frm)
    if frm.portraitSrc == "fdj" then
        local t = fdj()
        if t and t.ReleasePortrait then pcall(t.ReleasePortrait, frm.texture) end
    end
    roundMask(frm, false)
    frm.portraitFor, frm.portraitShown, frm.portraitSrc, frm.pinSpec = nil, nil, nil, nil
end

-- The pin's picture: a boss's portrait when one can be drawn, else its
-- icon. True when a portrait is shown.
function setPinArt(frm, pt, now)   -- the local declared above collect
    if pt.kind == "boss" then
        if pt.displayID and SetPortraitTextureFromCreatureDisplayID then
            -- Leatrix's display ID: the game draws the portrait itself.
            local key = "d" .. pt.displayID
            if frm.portraitFor ~= key then
                if frm.portraitFor then releasePortrait(frm) end
                frm.texture.agpsAtlas, frm.texture.agpsTC = nil, nil
                frm.texture:SetTexCoord(0, 1, 0, 1)
                local ok = pcall(SetPortraitTextureFromCreatureDisplayID, frm.texture, pt.displayID)
                frm.portraitFor, frm.portraitShown, frm.portraitSrc, frm.pinSpec = key, ok, "display", nil
                roundMask(frm, ok)
            end
            if frm.portraitShown then return true end
        else
            local t = fdj()
            if pt.fdjName and t and t.SetBossPortrait then
                local key = pt.fdjName .. "\0" .. tostring(pt.title)
                if frm.portraitFor ~= key or (not frm.portraitShown and now >= (frm.portraitRetry or 0)) then
                    if frm.portraitFor and frm.portraitFor ~= key then releasePortrait(frm) end
                    frm.texture.agpsAtlas, frm.texture.agpsTC = nil, nil
                    -- FDJ's journal record carries the NPC id the portrait needs.
                    local rec = journalBoss(pt.fdjName, pt.names) or pt.boss
                    local ok, shown = pcall(t.SetBossPortrait, frm.texture, pt.fdjName, rec)
                    frm.portraitFor, frm.portraitSrc, frm.pinSpec = key, "fdj", nil
                    frm.portraitShown = ok and shown == true
                    frm.portraitRetry = now + PORTRAIT_RETRY
                    roundMask(frm, frm.portraitShown)
                end
                if frm.portraitShown then return true end
            end
        end
    elseif frm.portraitFor then
        releasePortrait(frm)
    end
    local spec = specFor(pt)
    if frm.pinSpec ~= spec then
        AlchemyGPS.UI.StyleOptions:ApplyIconSpec(frm.texture, spec)
        frm.pinSpec = spec
    end
    return false
end

function MinimapEngine:UpdateDungeonPins()
    local frms = self.DungeonPinFrms
    if not self.Frm or self.Cont ~= self.DUNGEON_CONT then
        if frms then
            for _, f in ipairs(frms) do f:Hide() end
        end
        self.DungeonPinPts = nil
        return
    end
    frms = frms or {}
    self.DungeonPinFrms = frms

    local now = GetTime()
    local viewMap = self:GetViewMapId()
    if not self.DungeonPinAt or now >= self.DungeonPinAt or self.DungeonPinMap ~= viewMap then
        self.DungeonPinAt, self.DungeonPinMap = now + COLLECT_INTERVAL, viewMap
        local ok, res = pcall(collect, self)
        if ok then
            self.DungeonPinPts = res
        else
            self.DungeonPinPts = {}
            if self.DungeonPinError ~= res then
                self.DungeonPinError = res
                print("|cffff6060Alchemy GPS|r dungeon map pins: " .. tostring(res))
            end
        end
    end
    local pts = self.DungeonPinPts or {}

    for n = #frms + 1, #pts do
        local frm = self:CreateMiniFrame()
        frm:EnableMouse(true)
        frm:SetScript("OnEnter", PinOnEnter)
        frm:SetScript("OnLeave", PinOnLeave)
        frm:SetScript("OnMouseUp", PinOnMouseUp)
        frms[n] = frm
    end

    -- Same tier as the Service layer: over the level art, under the
    -- player dots and the player marker.
    local level = (self.Frm:GetFrameLevel() or 1) + (self.SERVICE_LEVEL_OFFSET or 6)
    for i, pt in ipairs(pts) do
        local frm = frms[i]
        local okArt, portrait = pcall(setPinArt, frm, pt, now)
        if not okArt then
            if self.DungeonPinError ~= portrait then
                self.DungeonPinError = portrait
                print("|cffff6060Alchemy GPS|r dungeon pin art: " .. tostring(portrait))
            end
            portrait = false
        end
        frm.pin = pt
        local size = pt.size
        if pt.worldSize then size = math.max(pt.minSize or 16, pt.worldSize * (self.ScaleDraw or 1)) end
        if self:ClipFrameW(frm, pt.x, pt.y, size, size, pt.rot) then
            -- The room glow sits under the pins and lets clicks through
            -- (it can cover much of the map); people sit over them.
            local up = (pt.under and -1) or ((pt.kind == "you" or pt.kind == "member" or pt.kind == "ring") and 2)
                or (pt.quest and 1) or 0
            frm:SetFrameLevel(level + up)
            frm:EnableMouse(not (pt.under or pt.nomouse))
            frm:SetAlpha(pt.alpha or 1)
            frm.texture:SetDesaturated(pt.desat and true or false)
            if portrait then
                frm.texture:SetVertexColor(1, 1, 1, 1)
            else
                frm.texture:SetVertexColor(pt.r or 1, pt.g or 1, pt.b or 1, 1)
            end
        end
    end
    for n = #pts + 1, #frms do
        frms[n]:Hide()
    end
end
