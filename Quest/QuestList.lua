-- Azeroth Atlas | Quest / QuestList
-- The full quest list: every quest in the log - tracked or not - under
-- its zone or dungeon, with a tick box per quest and per zone that
-- decides what the tracker shows. The tracker is the short "what am I
-- doing now" view and only lists what fits; this is the whole log.
--
--   Tick box on a quest    track / untrack it
--   Tick box on a zone     track / untrack everything in that zone
--   Click a quest          route the arrow to it (click again to release)
--   Right-click a quest    show / hide its objectives
--   Click a zone heading   fold / unfold it
--   Track all / none       every quest in the log
--
-- New UI on the small-window chrome (UI/SmallWindow.lua), like the
-- tracker. Opened from the tracker's "List" button, the Settings
-- window, or /aatlas quest list. Reads QuestState; tracking changes go
-- through QuestState too, so the tracker, map pins and arrow follow.

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Widget = AzerothAtlas.UI.Widget
local Q = AzerothAtlas.Modules.Quest

local List = {}
Q.List = List

List.Rows = {}

local TOP_BAR_H = 50        -- buttons, then the search box (2026-11-18)
local CHECK = 14
local TEXT_X = CHECK + 6
local RIGHT_W = 70
local QUEST_INDENT = 10
-- 2026-11-18: a quest's +/- sits right of its tick box, where a zone's
-- sits (user screenshot); the title moves over by this much.
local EXPAND_W = 13
local OBJECTIVE_INDENT = 46
-- Every row starts this far in: the zones' tick boxes touched the
-- window's left border and were cut off by it (user screenshot).
local LEFT_PAD = 4
local SCROLLBAR_W = 26

local floor = math.floor

-- Zone headings that are dungeons or raids, by name.
local function dungeonNames()
    local names = List._dungeonNames
    if not names then
        names = {}
        for _, packed in pairs((AzerothAtlas.QuestData and AzerothAtlas.QuestData.Instances) or {}) do
            local name = packed:match("^([^|]+)")
            if name then names[name] = true end
        end
        List._dungeonNames = names
    end
    return names
end

---------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------

local function checkOnClick(check)
    local row = check:GetParent()
    local State = Q.State
    if row.kind == "zone" then
        -- Anything untracked in the zone: track it all. Otherwise none.
        State:SetGroupWatched(row.zone, row.tracked < row.count)
    elseif row.kind == "quest" then
        State:SetWatched(row.questID, not State:IsWatched(row.questID))
    end
end

local function rowOnClick(row, button)
    local Core, Routing, State = Q.Core, Q.Routing, Q.State
    if row.kind == "zone" or row.kind == "member" then
        local folded = Core:Char("ListFolded")
        folded[row.zone] = (not folded[row.zone]) and true or nil
        List:Render()
    elseif row.kind == "pquest" then
        -- A party member's quest: clicks like ours when it's in our log.
        if State:GetQuest(row.questID) and button ~= "RightButton" then
            List:QuestClick(row.questID)
        end
    elseif row.kind == "quest" or row.kind == "objective" or row.kind == "text" then
        local questID = row.questID
        if button == "RightButton" and IsShiftKeyDown() and Q.Links then
            Q.Links:InsertInChat(questID)       -- 2026-11-18: link in chat
        elseif button == "RightButton" then
            -- 2026-11-16: the quest menu (Quest/QuestMenu.lua) - quest
            -- text, objectives, route, track, share, abandon.
            local open, text = Core:Char("ListOpen"), Core:Char("ListText")
            -- 2026-11-18: the quest text opens in the side panel
            -- (Quest/QuestDetails.lua) unless it's set to open under
            -- the quest.
            local Details = Q.Details
            local side = Details and Details:SidePanelOn()
            Q.Menu:Open(questID, {
                textShown = (side and Details:IsShowing(questID)) or (not side and text[questID]),
                onText = function()
                    if side then
                        Details:Toggle(questID)
                        return
                    end
                    text[questID] = (not text[questID]) and true or nil
                    List:Render()
                end,
                foldText = open[questID] and "Hide objectives" or "Show objectives",
                onFold = function()
                    open[questID] = (not open[questID]) and true or nil
                    List:Render()
                end,
                redraw = function() List:Render() end,
            })
        else
            List:QuestClick(questID)
        end
    end
end

-- 2026-11-18 (user): left-click on a quest -
--   click        its quest text (the side panel, or under the quest)
--   Shift-click  route the arrow there / stop
--   Ctrl-click   track / untrack
function List:QuestClick(questID)
    local Core, Routing, State = Q.Core, Q.Routing, Q.State
    if IsShiftKeyDown() then
        if Routing then Routing:ToggleManualQuest(questID) end
        self:Render()
    elseif IsControlKeyDown() then
        State:SetWatched(questID, not State:IsWatched(questID))
    else
        local Details = Q.Details
        if Details and Details:SidePanelOn() then
            Details:Toggle(questID)
        else
            local text = Core:Char("ListText")
            text[questID] = (not text[questID]) and true or nil
            self:Render()
        end
    end
end

-- 2026-11-18 (user): the +/- beside a quest with objectives folds them
-- open or shut - the same as the menu's "Show objectives".
local function expandOnClick(btn)
    local questID = btn:GetParent().questID
    if not questID then return end
    local open = Q.Core:Char("ListOpen")
    open[questID] = (not open[questID]) and true or nil
    List:Render()
end

local function rowOnEnter(row)
    -- 2026-11-17: hovering a quest lights it up on the map.
    local Pins = Q.Pins
    if Pins and Pins.SetFocus and row.kind ~= "zone" and row.questID then
        Pins:SetFocus(row.questID)
    end
    if row.kind == "zone" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.zone)
        GameTooltip:AddLine(("%d of %d tracked"):format(row.tracked, row.count), 1, 1, 1)
        GameTooltip:AddLine("Click: fold / unfold    Tick box: track all / none here", 0.6, 0.6, 0.6)
        GameTooltip:Show()
        return
    end
    if row.kind == "text" or row.kind == "note" then return end
    if row.kind == "member" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.memberName or "?")
        if row.full then
            GameTooltip:AddLine("Runs Azeroth Atlas: their whole quest log", 1, 1, 1)
        else
            GameTooltip:AddLine("Only the quests you share are known", 1, 1, 1)
        end
        GameTooltip:AddLine("Click: fold / unfold", 0.6, 0.6, 0.6)
        GameTooltip:Show()
        return
    end
    if row.kind == "pquest" and not Q.State:GetQuest(row.questID) then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.title or ("Quest " .. tostring(row.questID)))
        GameTooltip:AddLine("Not in your quest log", 0.8, 0.8, 0.8)
        if Q.Party then Q.Party:AddTooltip(row.questID) end
        GameTooltip:Show()
        return
    end
    local q = row.questID and Q.State:GetQuest(row.questID)
    if not q then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(q.title)
    local other = Q.Catalog and Q.Catalog:OtherClassQuest(q.questID)
    if other then
        GameTooltip:AddLine(("%s quest - shared with you; it may not be completable as your class"):format(other),
            1, 0.4, 0.4, true)
    end
    for _, o in ipairs(q.objectives) do
        if o.text ~= "" then
            if o.finished then
                GameTooltip:AddLine(o.text, 0.5, 0.75, 0.5)
            else
                GameTooltip:AddLine(o.text, 1, 1, 1)
                local note = Q.Catalog and Q.Catalog:ObjectiveNote(q.questID, o.text)
                if note then GameTooltip:AddLine("  " .. note.tip, 0.4, 0.8, 1, true) end
            end
        end
    end
    if q.ready then GameTooltip:AddLine("Ready to turn in", 0.4, 1, 0.4) end
    local part, total
    if Q.Catalog then part, total = Q.Catalog:GetChainPart(q.questID) end
    if part then GameTooltip:AddLine(("Part %d of %d in a chain"):format(part, total), 0.7, 0.7, 0.7) end
    if List.IsDaily(q) then GameTooltip:AddLine("Daily quest", 0.4, 0.7, 1) end
    GameTooltip:AddLine("Quest ID " .. q.questID, 0.6, 0.6, 0.6)
    if Q.Party then Q.Party:AddTooltip(q.questID) end
    if Pins and Pins.MapShown and Pins:MapShown() and (Pins.FocusCount or 0) == 0 then
        GameTooltip:AddLine("Not on the map on show", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: quest text    Shift-click: route here", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("Ctrl-click or tick box: track / untrack", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("+ / -: show / hide objectives", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: menu    Shift-right-click: link in chat", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function rowOnLeave()
    GameTooltip:Hide()
    if Q.Pins and Q.Pins.SetFocus then Q.Pins:SetFocus(nil) end
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local active = row:CreateTexture(nil, "BACKGROUND")
    active:SetAllPoints()
    active:SetColorTexture(1, 0.82, 0, 0.16)
    active:Hide()
    row.active = active

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)

    -- A plain tick box: the stock check-button template drags a label
    -- and a 32px hit box along with it.
    local check = CreateFrame("Button", nil, row)
    check:SetSize(CHECK, CHECK)
    local box = check:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints()
    box:SetColorTexture(0, 0, 0, 0.55)
    local edge = check:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    edge:SetDrawLayer("BACKGROUND", -1)
    local tick = check:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", -3, 3)
    tick:SetPoint("BOTTOMRIGHT", 3, -3)
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check.tick = tick
    check:SetScript("OnClick", checkOnClick)
    check:SetScript("OnEnter", function(c) rowOnEnter(c:GetParent()) end)
    check:SetScript("OnLeave", rowOnLeave)
    row.check = check

    -- 2026-11-18: +/- left of a quest's tick box (List:Render shows it).
    local expand = CreateFrame("Button", nil, row)
    expand:SetSize(EXPAND_W, CHECK)
    expand:SetPoint("TOPLEFT", 0, -2)
    local sign = expand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sign:SetPoint("CENTER", 0, 1)
    sign:SetTextColor(0.75, 0.75, 0.75)
    expand.sign = sign
    local glow = expand:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, 0.12)
    expand:SetScript("OnClick", expandOnClick)
    expand:Hide()
    row.expand = expand

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    if text.SetWordWrap then text:SetWordWrap(true) end
    row.text = text

    local right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("TOPRIGHT", -2, -2)
    right:SetWidth(RIGHT_W)
    right:SetJustifyH("RIGHT")
    right:SetTextColor(0.65, 0.65, 0.65)
    row.right = right

    row:SetScript("OnClick", rowOnClick)
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    return row
end

function List:AcquireRow(index)
    local row = self.Rows[index]
    if not row then
        row = createRow(self.Child)
        self.Rows[index] = row
    end
    return row
end

-- Lays a row out at offset y; returns its height. `state` for the tick
-- box: true, false, "some", or nil for no box.
-- `gap`: extra room between the tick box and the text (a quest's +/-).
local function placeRow(row, parent, y, width, indent, fontObject, text, rightText, state, gap)
    row.expand:Hide()
    width = width - LEFT_PAD
    local check = row.check
    if state == nil then
        check:Hide()
    else
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT", indent, -2)
        check:Show()
        if state then
            check.tick:Show()
            check.tick:SetDesaturated(state == "some")
            check.tick:SetAlpha(state == "some" and 0.5 or 1)
        else
            check.tick:Hide()
        end
    end

    local textX = indent + (state ~= nil and TEXT_X or 0) + (gap or 0)
    row.text:SetFontObject(fontObject)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", textX, -2)
    row.text:SetWidth(math.max(40, width - textX - (rightText and RIGHT_W or 0) - 2))
    row.text:SetText(text)
    row.right:SetText(rightText or "")

    local h = floor((row.text:GetStringHeight() or 10) + 0.5) + 5
    if h < CHECK + 4 then h = CHECK + 4 end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD, -y)
    row:SetSize(width, h)
    row:Show()
    return h
end

local function distanceText(entry)
    if not entry or not entry.res then return nil end
    if entry.far then return "far" end
    if not entry.yards then return nil end
    if entry.res.inside then return "here" end
    if entry.yards >= 1000 then return ("%.1fk"):format(entry.yards / 1000) end
    return ("%d yd"):format(floor(entry.yards + .5))
end

---------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------
-- Party view (2026-11-18, user request, from Carbonite's quest list
-- Party tab: "See your party members' quest logs, or only the quests
-- you share"). One foldable header per group member, then their quests
-- (Party:GetMemberLogs). "Shared only" keeps just the quests you have
-- too. A quest you have is clickable like on your own list.
---------------------------------------------------------------------------------------

-- 2026-11-18 (user request, from Carbonite: quest IDs, chain parts,
-- dailies).
local DAILY = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily) or _G.LE_QUEST_FREQUENCY_DAILY or 1
local function isDaily(q)
    return q and (q.frequency == DAILY or q.frequency == true)
end
List.IsDaily = isDaily

-- " (part 2/4)", " #1234", " (Daily)" after a title, as set.
local function titleExtras(questID, q)
    local s = ""
    -- 2026-11-18: a class quest shared with another class.
    local other = Q.Catalog and Q.Catalog:OtherClassQuest(questID)
    if other then s = s .. (" |cffff6060(%s quest)|r"):format(other) end
    if isDaily(q) then s = s .. " |cff66b3ff(Daily)|r" end
    if Q.Core:Opt("ListShowChain") ~= false and Q.Catalog then
        local part, total = Q.Catalog:GetChainPart(questID)
        if part then s = s .. (" |cff9d9d9d(part %d/%d)|r"):format(part, total) end
    end
    if Q.Core:Opt("ListShowIDs") then s = s .. (" |cff9d9d9d#%d|r"):format(questID) end
    return s
end
-- The tracker uses the same extras (2026-11-18, user: "on the tracker its
-- not showing part # of #").
List.TitleExtras = titleExtras

local function formatSeconds(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- "Dailies: 3 done today, reset in 5h 12m", or nil when there's nothing
-- daily to speak of (no daily in the log and none done).
function List:DailyLine()
    local done = _G.GetDailyQuestsCompleted and _G.GetDailyQuestsCompleted() or 0
    local inLog = 0
    for _, q in ipairs(Q.State.Quests) do
        if isDaily(q) then inLog = inLog + 1 end
    end
    if done == 0 and inLog == 0 then return nil end
    local reset = (C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset())
        or (_G.GetQuestResetTime and _G.GetQuestResetTime())
    local s = ("Dailies: %d done today, %d in your log"):format(done, inLog)
    if reset and reset > 0 then s = s .. ", reset in " .. formatSeconds(reset) end
    return s
end

-- 2026-11-18 (user request, from Carbonite): the search box. True when
-- the quest matches what's typed (no search: everything matches) -
-- its title, its zone heading or any objective, ignoring case.
local function matches(search, title, group, objectives)
    if not search then return true end
    if title and title:lower():find(search, 1, true) then return true end
    if group and group:lower():find(search, 1, true) then return true end
    for _, o in ipairs(objectives or {}) do
        if o.text and o.text:lower():find(search, 1, true) then return true end
    end
    return false
end

local function questTitleAndLevel(questID)
    local q = Q.State:GetQuest(questID)
    if q then return q.title, q.level end
    local Catalog = Q.Catalog
    local h = Catalog and Catalog.GetHeader and Catalog:GetHeader(questID)
    local title = Q.Api:GetTitle(questID) or (h and h.name)
    return title or ("Quest #" .. questID), h and h.level or 0
end

function List:RenderParty(width)
    local Core, Pins, State, Party = Q.Core, Q.Pins, Q.State, Q.Party
    local child = self.Child
    local folded = Core:Char("ListFolded")
    local sharedOnly = Core:Opt("ListPartySharedOnly") == true
    local used, y = 0, 2

    local function note(text)
        used = used + 1
        local row = self:AcquireRow(used)
        row.kind, row.zone, row.questID = "note", nil, nil
        y = y + placeRow(row, child, y, width, QUEST_INDENT, GameFontHighlightSmall, text, nil, nil)
        row.text:SetTextColor(0.65, 0.65, 0.65)
        row.text:SetAlpha(1)
        row.active:Hide()
    end

    local members = Party and Party:GetMemberLogs() or {}
    if #members == 0 then
        note(IsInGroup() and "Waiting for your group..." or "You're not in a group.")
    end
    for _, m in ipairs(members) do
        local key = "party:" .. m.name
        local quests = {}
        for _, id in ipairs(m.quests) do
            local mine = State:GetQuest(id)
            if (not sharedOnly or mine) and matches(self.Search, questTitleAndLevel(id), nil,
                mine and mine.objectives) then
                quests[#quests + 1] = id
            end
        end

        used = used + 1
        local row = self:AcquireRow(used)
        row.kind, row.zone, row.questID = "member", key, nil
        row.memberName, row.full = m.name, m.full
        local c = m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
        local name = c and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, m.name) or m.name
        local label = ("|cffa0a0a0%s|r %s"):format(folded[key] and "+" or "-", name)
        if m.level and m.level > 0 then label = label .. (" |cffa0a0a0%d|r"):format(m.level) end
        y = y + placeRow(row, child, y, width, 0, GameFontNormal, label,
            ("%d %s"):format(#quests, (sharedOnly or not m.full) and "shared" or "quests"), nil)
        row.text:SetTextColor(1, 0.82, 0)
        row.active:Hide()

        if not folded[key] or self.Search then
            if not m.full then note("Not running Azeroth Atlas - only the quests you share.") end
            if #quests == 0 then note("No quests to show.") end
            -- Sorted by level, then title.
            local rows = {}
            for _, id in ipairs(quests) do
                local title, level = questTitleAndLevel(id)
                rows[#rows + 1] = { id = id, title = title, level = level or 0 }
            end
            table.sort(rows, function(a, b)
                if a.level ~= b.level then return a.level < b.level end
                return a.title < b.title
            end)
            for _, r in ipairs(rows) do
                used = used + 1
                local qrow = self:AcquireRow(used)
                qrow.kind, qrow.zone, qrow.questID, qrow.title = "pquest", nil, r.id, r.title
                local mine = State:GetQuest(r.id) ~= nil
                y = y + placeRow(qrow, child, y, width, QUEST_INDENT, GameFontNormalSmall,
                    Pins:ColoredTitle(r.level, r.title, r.id) .. titleExtras(r.id, State:GetQuest(r.id)),
                    mine and "|cff66ff66you too|r" or nil, nil)
                qrow.text:SetAlpha(mine and 1 or 0.7)
                qrow.active:Hide()
            end
        end
        y = y + 4
    end

    for n = used + 1, #self.Rows do self.Rows[n]:Hide() end
    child:SetHeight(math.max(y, 1))
    self.Summary:SetText(("%d in your group"):format(#members))
    self.Win:SetTitle("Quest List - Party")
end

function List:SetView(view)
    Q.Core:SetOpt("ListView", view)
    self:UpdateBar()
    self:Render()
end

function List:UpdateBar()
    local party = Q.Core:Opt("ListView") == "party"
    if self.TrackAllBtn then self.TrackAllBtn:SetShown(not party) end
    if self.TrackNoneBtn then self.TrackNoneBtn:SetShown(not party) end
    if self.SharedBtn then
        self.SharedBtn:SetShown(party)
        self.SharedBtn:SetText(Q.Core:Opt("ListPartySharedOnly") and "Show all" or "Shared only")
    end
    if self.ViewBtn then self.ViewBtn:SetText(party and "My quests" or "Party") end
end

function List:Render()
    local win = self.Win
    if not win or not win:IsShown() then return end
    if Q.Core:Opt("ListView") == "party" then
        local width = win:GetWidth() - 16 - SCROLLBAR_W
        self.Child:SetWidth(width)
        return self:RenderParty(width)
    end

    local State, Routing, Core, Pins = Q.State, Q.Routing, Q.Core, Q.Pins
    local child = self.Child
    local width = win:GetWidth() - 16 - SCROLLBAR_W
    child:SetWidth(width)

    local quests = {}
    local search = self.Search
    for _, q in ipairs(State.Quests) do
        if matches(search, q.title, q.group, q.objectives) then quests[#quests + 1] = q end
    end
    table.sort(quests, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.title ~= b.title then return a.title < b.title end
        return a.questID < b.questID
    end)
    local groups = State:GroupQuests(quests)
    table.sort(groups, function(a, b)
        -- "Other" (no heading known) goes last.
        if (a.name == State.NO_GROUP) ~= (b.name == State.NO_GROUP) then return b.name == State.NO_GROUP end
        return a.name < b.name
    end)

    local info = (Routing and Routing.QuestInfo) or {}
    local target = Routing and Routing.Target
    local activeQuest = target and target.kind == "quest" and target.questID or nil
    local folded = Core:Char("ListFolded")
    local open = Core:Char("ListOpen")
    local textOpen = Core:Char("ListText")
    local dungeons = dungeonNames()

    local used, y, trackedTotal = 0, 2, 0
    local daily = self:DailyLine()
    if daily then
        used = used + 1
        local row = self:AcquireRow(used)
        row.kind, row.zone, row.questID = "note", nil, nil
        y = y + placeRow(row, child, y, width, 0, GameFontHighlightSmall, daily, nil, nil) + 2
        row.text:SetTextColor(0.4, 0.7, 1)
        row.text:SetAlpha(1)
        row.active:Hide()
    end
    for _, group in ipairs(groups) do
        local tracked = 0
        for _, q in ipairs(group.quests) do
            if State:IsWatched(q.questID) then tracked = tracked + 1 end
        end
        trackedTotal = trackedTotal + tracked
        local count = #group.quests

        used = used + 1
        local row = self:AcquireRow(used)
        row.kind, row.zone, row.questID, row.count, row.tracked = "zone", group.name, nil, count, tracked
        local state = (tracked == count) or (tracked > 0 and "some") or false
        local label = ("|cffa0a0a0%s|r %s%s"):format(folded[group.name] and "+" or "-", group.name,
            dungeons[group.name] and " |cff66b3ff(dungeon)|r" or "")
        y = y + placeRow(row, child, y, width, 0, GameFontNormal, label,
            ("%d / %d"):format(tracked, count), state)
        row.text:SetTextColor(1, 0.82, 0)
        row.active:Hide()

        -- While searching every heading with a match is open.
        if not folded[group.name] or search then
            for _, q in ipairs(group.quests) do
                local questID = q.questID
                local watched = State:IsWatched(questID)
                used = used + 1
                local qrow = self:AcquireRow(used)
                qrow.kind, qrow.zone, qrow.questID = "quest", nil, questID

                local title = Pins:ColoredTitle(q.level, q.title, questID)
                if q.isFailed then
                    title = title .. " |cffff4040(Failed)|r"
                elseif q.ready then
                    title = title .. " |cff66ff66(Complete)|r"
                end
                title = title .. titleExtras(questID, q)
                if Q.Party then title = title .. Q.Party:Badge(questID) end
                y = y + placeRow(qrow, child, y, width, QUEST_INDENT, GameFontNormalSmall, title,
                    distanceText(info[questID]) or (not watched and "untracked") or nil, watched, EXPAND_W)
                qrow.text:SetAlpha(watched and 1 or 0.6)
                if questID == activeQuest or (Q.Details and Q.Details:IsShowing(questID)) then
                    qrow.active:Show()
                else
                    qrow.active:Hide()
                end
                -- +/- when the quest has objectives to show.
                local hasObjectives = false
                for _, o in ipairs(q.objectives) do
                    if o.text ~= "" then hasObjectives = true break end
                end
                if hasObjectives then
                    qrow.expand:ClearAllPoints()
                    qrow.expand:SetPoint("TOPLEFT", qrow, "TOPLEFT", QUEST_INDENT + TEXT_X - 4, -2)
                    qrow.expand.sign:SetText(open[questID] and "-" or "+")
                    qrow.expand:Show()
                end

                if open[questID] then
                    local any = false
                    for _, o in ipairs(q.objectives) do
                        if o.text ~= "" then
                            any = true
                            used = used + 1
                            local orow = self:AcquireRow(used)
                            orow.kind, orow.zone, orow.questID = "objective", nil, questID
                            local tag = (not o.finished and Q.Catalog) and Q.Catalog:ObjectiveTag(questID, o.text) or ""
                            y = y + placeRow(orow, child, y, width, OBJECTIVE_INDENT,
                                GameFontHighlightSmall, o.text .. tag, nil, nil) - 3
                            if o.finished then
                                orow.text:SetTextColor(0.5, 0.7, 0.5)
                            else
                                orow.text:SetTextColor(0.9, 0.9, 0.9)
                            end
                            orow.text:SetAlpha(1)
                            orow.active:Hide()
                        end
                    end
                    if not any then
                        used = used + 1
                        local orow = self:AcquireRow(used)
                        orow.kind, orow.zone, orow.questID = "objective", nil, questID
                        y = y + placeRow(orow, child, y, width, OBJECTIVE_INDENT, GameFontHighlightSmall,
                            q.ready and "Ready to turn in." or "No listed objectives.", nil, nil) - 3
                        orow.text:SetTextColor(0.7, 0.7, 0.7)
                        orow.text:SetAlpha(1)
                        orow.active:Hide()
                    end
                    y = y + 4
                end

                -- 2026-11-16: the quest's own text, as Blizzard's quest
                -- log shows it (opened from the quest menu).
                if textOpen[questID] and not (Q.Details and Q.Details:SidePanelOn()) then
                    local desc, summary = Q.Api:GetQuestText(questID)
                    local function textRow(s, font, r, g, b, after)
                        used = used + 1
                        local trow = self:AcquireRow(used)
                        trow.kind, trow.zone, trow.questID = "text", nil, questID
                        y = y + placeRow(trow, child, y, width, OBJECTIVE_INDENT, font, s, nil, nil) + after
                        trow.text:SetTextColor(r, g, b)
                        trow.text:SetAlpha(1)
                        trow.active:Hide()
                    end
                    textRow("Quest Objectives", GameFontNormalSmall, 1, 0.82, 0, -4)
                    textRow(summary or "-", GameFontHighlightSmall, 0.92, 0.88, 0.78, 2)
                    textRow("Description", GameFontNormalSmall, 1, 0.82, 0, -4)
                    textRow(desc or "The game gave no text for this quest.", GameFontHighlightSmall,
                        0.92, 0.88, 0.78, 6)
                end
            end
        end
        y = y + 4
    end

    for n = used + 1, #self.Rows do self.Rows[n]:Hide() end
    child:SetHeight(math.max(y, 1))

    local total = #State.Quests
    if total == 0 then
        self.Summary:SetText(State.Scanned and "No quests in your log" or "Reading quest log...")
    elseif search then
        self.Summary:SetText(("%d of %d match"):format(#quests, total))
    else
        self.Summary:SetText(("%d quests, %d tracked"):format(total, trackedTotal))
    end
    win:SetTitle("Quest List")
end

---------------------------------------------------------------------------------------

function List:Create()
    if self.Win then return self.Win end
    local Core = Q.Core

    local anchor = Core:ProfileTable("ListAnchor")
    if not anchor.point then
        anchor.point, anchor.relPoint, anchor.x, anchor.y = "CENTER", "CENTER", 0, 20
    end

    local win = AzerothAtlas.UI.Window:Create{
        name = "AzerothAtlasQuestList",
        title = "Quest List",
        width = 340,
        height = 460,
        -- Above the map, which sits in DIALOG strata (2026-11-16).
        strata = "FULLSCREEN_DIALOG",
        dbAnchor = anchor,
        dbSize = Core:ProfileTable("ListSize"),
        resizable = true,
        minWidth = 260,
        minHeight = 180,
        onResizeStop = function() self:Render() end,
    }
    self.Win = win
    AzerothAtlas.UI.Mixins.Resizable.RestoreSize(win)
    AzerothAtlas.UI.Mixins.Draggable.RestoreAnchor(win, UIParent)

    local content = win.content

    local function barButton(x, label, onClick)
        local but = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        but:SetSize(76, 20)
        but:SetPoint("TOPLEFT", x, 0)
        but:SetText(label)
        but:SetScript("OnClick", onClick)
        return but
    end
    self.TrackAllBtn = barButton(0, "Track all", function() Q.State:SetGroupWatched(nil, true) end)
    self.TrackNoneBtn = barButton(80, "Track none", function() Q.State:SetGroupWatched(nil, false) end)
    -- 2026-11-18: the party view (List:RenderParty) and its filter.
    self.SharedBtn = barButton(0, "Shared only", function()
        Core:SetOpt("ListPartySharedOnly", not Core:Opt("ListPartySharedOnly"))
        self:UpdateBar()
        self:Render()
    end)
    self.ViewBtn = barButton(160, "Party", function()
        self:SetView(Core:Opt("ListView") == "party" and "mine" or "party")
    end)
    self:UpdateBar()

    -- 2026-11-18 (user request, from Carbonite): type to filter the list.
    local search = CreateFrame("EditBox", "AzerothAtlasQuestListSearch", content, "SearchBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", 6, -24)
    search:SetPoint("TOPRIGHT", -6, -24)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(box)
        local text = strtrim(box:GetText() or "")
        local want = text ~= "" and text:lower() or nil
        if want ~= self.Search then
            self.Search = want
            self:Render()
        end
    end)
    search:HookScript("OnEscapePressed", function(box) box:ClearFocus() end)
    search:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
    if search.Instructions then search.Instructions:SetText("Search quests, zones, objectives") end
    self.SearchBox = search

    local summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPRIGHT", -4, -5)
    summary:SetPoint("TOPLEFT", 240, -5)     -- clear of the bar's buttons
    summary:SetJustifyH("RIGHT")
    if summary.SetWordWrap then summary:SetWordWrap(false) end
    summary:SetTextColor(0.7, 0.7, 0.7)
    self.Summary = summary

    local scroll = Widget.CreateScrollFrame(content, "AzerothAtlasQuestListScroll")
    scroll:SetPoint("TOPLEFT", 0, -TOP_BAR_H)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_W, 4)
    self.Scroll = scroll
    self.Child = scroll.ScrollChild

    win:HookScript("OnShow", function() self:Render() end)
    return win
end

---------------------------------------------------------------------------------------
-- Docking (2026-11-17, user request: a button on the big map "that will
-- pop out an attached quest list"). Dock(frame) shows the list beside
-- the frame, full height - outside its right edge when there's room on
-- screen, else inside it. Dock(nil) puts it back where it was saved.
---------------------------------------------------------------------------------------

function List:IsDocked()
    return self.DockedTo ~= nil
end

function List:Dock(frame)
    local win = self:Create()
    self.DockedTo = frame
    if frame then
        win:ClearAllPoints()
        local right, screenRight = frame:GetRight(), UIParent:GetRight()
        local scale = frame:GetEffectiveScale() / win:GetEffectiveScale()
        local w = win:GetWidth()
        if right and screenRight and right * scale + w + 4 <= screenRight then
            win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
            win:SetHeight(math.max(180, frame:GetHeight() * scale))
        else
            win:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -48)
            win:SetHeight(math.max(180, frame:GetHeight() * scale - 80))
        end
        win:Show()
        self:Render()
    else
        AzerothAtlas.UI.Mixins.Resizable.RestoreSize(win)
        AzerothAtlas.UI.Mixins.Draggable.RestoreAnchor(win, UIParent)
    end
end

function List:Toggle()
    local win = self:Create()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
        self:Render()
    end
end

function List:Start()
    local function redraw() self:Render() end
    EventBus:Subscribe("QUEST_STATE_CHANGED", redraw)
    EventBus:Subscribe("QUEST_PARTY_CHANGED", redraw)
    -- 2026-11-18: quest IDs / chain parts shown or not.
    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(_, key)
        if key == "ListShowIDs" or key == "ListShowChain" then redraw() end
    end)
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", redraw)
    EventBus:Subscribe("QUEST_CATALOG_READY", redraw)
end
