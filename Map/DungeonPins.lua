---------------------------------------------------------------------------------------
-- Alchemy GPS | Map/DungeonPins.lua
--
-- 2026-11-16 (user request: "show all the quest locations on the
-- dungeon map"). On a WoW Forever dungeon level drawn from Forever
-- Dungeon Journal's art (MinimapEngine:GetFDJDungeon), its own marks
-- are drawn on the map too, read live from FDJ.DUNGEON_MAPS:
--   bosses       skull; gold and larger when a quest in your log needs
--                it (its objective text names the boss, or
--                QuestData.DungeonQuestBosses says it drops the item)
--   transitions  the way to another level: an arrow, click to look at
--                that level
--   entrance     where you come in
-- Positions are 0-1 on the level's art, the same art drawn under them,
-- so they line up whether or not the game reports where you are.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local MinimapEngine = AlchemyGPS.Modules.Map.MinimapEngine

local BOSS_SIZE, QUEST_SIZE, LEVEL_SIZE, ENTRANCE_SIZE = 24, 30, 20, 20
local RING_EXTRA = 8                      -- the quest ring round a quest boss
local PORTRAIT_RETRY = 3                  -- seconds before asking FDJ again
-- Boss portraits (2026-11-16, user request: "use the boss portrait icons
-- instead of the skulls"): drawn by Forever Dungeon Journal's own
-- FDJ.SetBossPortrait - its bundled art, the Encounter Journal's display,
-- or its model-made portraits - round-masked like a unit frame. The skull
-- stays for a boss FDJ has no portrait for (yet: its portraits can arrive
-- a moment later, so it is asked again).
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GFX = "Interface\\AddOns\\AlchemyGPS\\Gfx\\Map\\"
local COLLECT_INTERVAL = 0.5

local TEX = {
    boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    level = "Interface\\Buttons\\UI-MicroStream-Yellow",     -- an arrow pointing down
    entrance = "Interface\\Icons\\INV_Misc_Key_03",          -- the map's own entrance icon
}

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

-- Lower-cased boss name -> { "Quest title: objective", ... } for every
-- unfinished objective in the log that needs that boss - or, by
-- QuestData.DungeonObjectiveHints, is found near it (the Tablets of
-- I'lalai, which no addon or database has a position for).
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
        list[#list + 1] = line
        needs[lname] = list
    end
    for _, q in ipairs(State.Quests) do
        for _, o in ipairs(q.objectives or {}) do
            if not o.finished and o.text ~= "" then
                local text = o.text:lower()
                for _, b in ipairs(bosses) do
                    local lname = type(b.name) == "string" and b.name:lower()
                    if lname and (text:find(lname, 1, true) or drops[q.questID] == b.name) then
                        add(lname, q.title .. ": " .. o.text)
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
    end
    return needs
end

-- FDJ's data for a classic dungeon level drawn from the game's own map:
-- the entry and level index whose floor names that uiMapID (FDJ places
-- its bosses on the game's map there, the map drawn here).
local setPinArt   -- defined above UpdateDungeonPins

local function fdjForClientMap(mapId)
    return MinimapEngine:GetFDJForClientMap(mapId)
end

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
        data, floor, fdjName = fdjForClientMap(mapId)
    end
    if type(data) ~= "table" then data, floor = {}, 0 end

    local bosses = type(data.bosses) == "table" and data.bosses or {}
    local needs = questNeeds(bosses, engine.DungeonInstance)
    for _, b in ipairs(bosses) do
        if (b.floor or 1) == floor and type(b.x) == "number" and type(b.y) == "number" then
            local wx, wy = place(b.x, b.y)
            local need = type(b.name) == "string" and needs[b.name:lower()]
            local size = need and QUEST_SIZE or BOSS_SIZE
            pts[#pts + 1] = {
                x = wx, y = wy, kind = "boss", tex = TEX.boss, size = size,
                r = 1, g = need and 0.82 or 1, b = need and 0 or 1,
                title = b.name, lines = need, quest = need and true or nil,
                boss = b, fdjName = fdjName,
            }
            if need then
                pts[#pts + 1] = {
                    x = wx, y = wy, kind = "ring", tex = GFX .. "IconRing", size = size + RING_EXTRA,
                    r = 1, g = 0.82, b = 0, nomouse = true, quest = true,
                }
            end
        end
    end

    for _, tr in ipairs(type(data.transitions) == "table" and data.transitions or {}) do
        if (tr.floor or 1) == floor and type(tr.x) == "number" and type(tr.y) == "number" and tr.to then
            local wx, wy = place(tr.x, tr.y)
            local label = fdjText(tr.labelKey, tr.to) or fdjText(tr.tipKey, tr.to)
            local c = tr.color
            pts[#pts + 1] = {
                x = wx, y = wy, kind = "level", tex = TEX.level, size = LEVEL_SIZE,
                rot = (tr.to < floor) and math.pi or 0,
                r = c and c[1] or 1, g = c and c[2] or 1, b = c and c[3] or 1,
                title = label or ((tr.to > floor) and "Way down" or "Way up"),
                lines = { "Click to look at that level" }, to = tr.to,
                toMap = type(data.floors) == "table" and type(data.floors[tr.to]) == "table"
                    and data.floors[tr.to].uiMapID or nil,
            }
        end
    end

    local e = data.entrance
    if type(e) == "table" and (e.floor or 1) == floor and type(e.x) == "number" then
        local wx, wy = place(e.x, e.y)
        pts[#pts + 1] = {
            x = wx, y = wy, kind = "entrance", tex = TEX.entrance, size = ENTRANCE_SIZE,
            r = 1, g = 1, b = 1, title = "Entrance",
        }
    end

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
    if pt.kind == "boss" then GameTooltip:AddLine("Boss", 0.8, 0.8, 0.8) end
    if pt.kind == "you" then
        GameTooltip:AddLine("The game names the room you're in, not the spot.", 0.9, 0.9, 0.9, true)
    end
    for _, line in ipairs(pt.lines or {}) do
        GameTooltip:AddLine(line, pt.quest and 1 or 0.9, pt.quest and 0.82 or 0.9, pt.quest and 0 or 0.9, true)
    end
    GameTooltip:Show()
end

local function PinOnLeave()
    GameTooltip:Hide()
end

local function PinOnMouseUp(frm, button)
    local pt = frm.pin
    if button == "LeftButton" and pt and pt.to then
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

-- The pin's picture: a boss's FDJ portrait when there is one, else its
-- own texture. True when a portrait is shown.
local function setMask(tex, mask)
    if tex.SetMask then pcall(tex.SetMask, tex, mask) end
end

function setPinArt(frm, pt, now)   -- the local declared above fdjForClientMap
    local t = fdj()
    if pt.boss and pt.fdjName and t and t.SetBossPortrait then
        local key = pt.fdjName .. "\0" .. tostring(pt.boss.name)
        if frm.portraitFor ~= key or (not frm.portraitShown and now >= (frm.portraitRetry or 0)) then
            frm.portraitFor, frm.pinTex = key, nil
            local ok, shown = pcall(t.SetBossPortrait, frm.texture, pt.fdjName, pt.boss)
            frm.portraitShown = ok and shown == true
            frm.portraitRetry = now + PORTRAIT_RETRY
            setMask(frm.texture, frm.portraitShown and PORTRAIT_MASK or "")
        end
        if frm.portraitShown then return true end
    elseif frm.portraitFor then
        -- This frame showed a portrait before: hand it back to FDJ's pool.
        if t and t.ReleasePortrait then pcall(t.ReleasePortrait, frm.texture) end
        setMask(frm.texture, "")
        frm.portraitFor, frm.portraitShown, frm.pinTex = nil, nil, nil
    end
    if frm.pinTex ~= pt.tex then
        frm.texture:SetTexture(pt.tex)
        frm.pinTex = pt.tex
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
        self.DungeonPinPts = collect(self)
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
    local now = GetTime()
    for i, pt in ipairs(pts) do
        local frm = frms[i]
        local portrait = setPinArt(frm, pt, now)
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
