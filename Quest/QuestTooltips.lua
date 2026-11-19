---------------------------------------------------------------------------------------
-- Azeroth Atlas | Quest/QuestTooltips.lua
--
-- 2026-11-18 (user request, from Carbonite: "Quest info on mob and item
-- tooltips - Hovering a mob or item shows which quest needs it and your
-- progress (for example "Kobold Vermin: 4/10")").
--
-- The way Carbonite.Quests' Tooltips.lua does it: the hovered mob's or
-- item's name is looked for in the objectives of the quests in your
-- log; each quest it's part of adds its title and that objective's
-- progress line. Also, hovering the NPC who takes in a quest of yours
-- says so ("Hand in here", green once it's ready) - matched by NPC id
-- against the quest data's turn-in giver.
--
-- A quest the game already lists on the tooltip isn't added twice.
-- Answers are cached per name until the quest log changes. The data
-- has no loot tables, so a mob that only DROPS a quest item isn't
-- matched (Carbonite can't either). Settings > Quests: QuestTooltips.
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Q = AzerothAtlas.Modules.Quest

local Tips = {}
Q.Tooltips = Tips

local HEAD = "|cff66b3ffQuest:|r "
local cache = {}        -- [lower name] = { lines } (false: nothing)
local turnins = {}      -- [npcId] = { questID, ... }, rebuilt with cache

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function rebuildTurnins()
    wipe(turnins)
    local Catalog = Q.Catalog
    if not Catalog or not Catalog.GetEndpoints then return end
    for _, q in ipairs(Q.State.Quests or {}) do
        for _, se in ipairs(Catalog:GetEndpoints(q.questID, true) or {}) do
            local _, _, _, _, giverId = Catalog:UnpackSE(se)
            if giverId then
                turnins[giverId] = turnins[giverId] or {}
                table.insert(turnins[giverId], q.questID)
            end
        end
    end
end

local function title(q)
    local Pins = Q.Pins
    if Pins and Pins.ColoredTitle then return Pins:ColoredTitle(q.level, q.title, q.questID) end
    return q.title
end

-- { {text, r, g, b}, ... } for a name, or false.
local function linesFor(name)
    local key = name:lower()
    local hit = cache[key]
    if hit ~= nil then return hit end
    local lines = {}
    for _, q in ipairs(Q.State.Quests or {}) do
        local matched
        for _, o in ipairs(q.objectives or {}) do
            if o.text and o.text ~= "" and o.text:lower():find(key, 1, true) then
                if not matched then
                    matched = true
                    lines[#lines + 1] = { HEAD .. title(q), 1, 1, 1, q.title }
                end
                if o.finished then
                    lines[#lines + 1] = { "  " .. o.text, 0.5, 0.75, 0.5 }
                else
                    lines[#lines + 1] = { "  " .. o.text, 1, 1, 1 }
                end
            end
        end
    end
    hit = #lines > 0 and lines or false
    cache[key] = hit
    return hit
end

-- Does the tooltip already have this text on a line (the game's own
-- quest lines)?
local function hasLine(tip, text)
    local name = tip:GetName()
    if not name then return false end
    for i = 2, tip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local s = fs and fs:GetText()
        if readable(s) and s and s:find(text, 1, true) then return true end
    end
    return false
end

local function addLines(tip, name, npcId)
    if Q.Core:Opt("QuestTooltips") == false or not Q.State or not Q.State.Scanned then return end
    if tip.azerothAtlasQuestTip == name then return end     -- already added to this showing
    local added = false
    -- Very short names ("Rat") would match inside other words ("Pirate").
    local lines = readable(name) and name and #name >= 4 and linesFor(name)
    if lines then
        for _, l in ipairs(lines) do
            if not (l[5] and hasLine(tip, l[5])) then
                if not added then tip:AddLine(" ") end
                tip:AddLine(l[1], l[2], l[3], l[4])
                added = true
            end
        end
    end
    local list = npcId and turnins[npcId]
    if list then
        for _, questID in ipairs(list) do
            local q = Q.State:GetQuest(questID)
            if q then
                if not added then tip:AddLine(" ") end
                if q.ready then
                    tip:AddLine("|cff66ff66Hand in here:|r " .. title(q), 1, 1, 1)
                else
                    tip:AddLine("|cff9d9d9dHands in here (not done yet):|r " .. title(q), 1, 1, 1)
                end
                added = true
            end
        end
    end
    tip.azerothAtlasQuestTip = name
    if added then tip:Show() end
end

local function onUnit(tip)
    if not tip or not tip.GetUnit then return end
    local _, unit = tip:GetUnit()
    if not unit or not readable(unit) or UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    local npcId = readable(guid) and guid and tonumber((select(6, strsplit("-", guid))))
    pcall(addLines, tip, name, npcId)
end

local function onItem(tip)
    if not tip or not tip.GetItem then return end
    local name = tip:GetItem()
    pcall(addLines, tip, name, nil)
end

function Tips:Start()
    local function changed()
        wipe(cache)
        rebuildTurnins()
    end
    EventBus:Subscribe("QUEST_STATE_CHANGED", changed)
    EventBus:Subscribe("QUEST_CATALOG_READY", changed)
    changed()

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
            if tip == GameTooltip then onUnit(tip) end
        end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
            if tip == GameTooltip or tip == ItemRefTooltip then onItem(tip) end
        end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", onUnit)
        GameTooltip:HookScript("OnTooltipSetItem", onItem)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onItem) end
    end
    -- A new showing may be for the same name again.
    GameTooltip:HookScript("OnTooltipCleared", function(tip) tip.azerothAtlasQuestTip = nil end)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipCleared", function(tip) tip.azerothAtlasQuestTip = nil end)
    end
end
