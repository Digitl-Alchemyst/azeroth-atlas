-- Alchemy GPS | Quest / QuestList
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
-- window, or /gps quest list. Reads QuestState; tracking changes go
-- through QuestState too, so the tracker, map pins and arrow follow.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Widget = AlchemyGPS.UI.Widget
local Q = AlchemyGPS.Modules.Quest

local List = {}
Q.List = List

List.Rows = {}

local TOP_BAR_H = 26
local CHECK = 14
local TEXT_X = CHECK + 6
local RIGHT_W = 70
local QUEST_INDENT = 10
local OBJECTIVE_INDENT = 34
local SCROLLBAR_W = 26

local floor = math.floor

-- Zone headings that are dungeons or raids, by name.
local function dungeonNames()
    local names = List._dungeonNames
    if not names then
        names = {}
        for _, packed in pairs((AlchemyGPS.QuestData and AlchemyGPS.QuestData.Instances) or {}) do
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
    if row.kind == "zone" then
        local folded = Core:Char("ListFolded")
        folded[row.zone] = (not folded[row.zone]) and true or nil
        List:Render()
    elseif row.kind == "quest" or row.kind == "objective" or row.kind == "text" then
        local questID = row.questID
        if button == "RightButton" then
            -- 2026-11-16: the quest menu (Quest/QuestMenu.lua) - quest
            -- text, objectives, route, track, share, abandon.
            local open, text = Core:Char("ListOpen"), Core:Char("ListText")
            Q.Menu:Open(questID, {
                textShown = text[questID],
                onText = function()
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
        elseif IsShiftKeyDown() then
            State:SetWatched(questID, not State:IsWatched(questID))
        elseif Routing then
            Routing:ToggleManualQuest(questID)
            List:Render()
        end
    end
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
    if row.kind == "text" then return end   -- the quest's own text: already on screen
    local q = row.questID and Q.State:GetQuest(row.questID)
    if not q then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(q.title)
    for _, o in ipairs(q.objectives) do
        if o.text ~= "" then
            if o.finished then
                GameTooltip:AddLine(o.text, 0.5, 0.75, 0.5)
            else
                GameTooltip:AddLine(o.text, 1, 1, 1)
            end
        end
    end
    if q.ready then GameTooltip:AddLine("Ready to turn in", 0.4, 1, 0.4) end
    if Q.Party then Q.Party:AddTooltip(q.questID) end
    if Pins and Pins.MapShown and Pins:MapShown() and (Pins.FocusCount or 0) == 0 then
        GameTooltip:AddLine("Not on the map on show", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: route here    Right-click: menu (quest text, share, abandon)", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("Tick box or Shift-click: track / untrack", 0.6, 0.6, 0.6)
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
local function placeRow(row, parent, y, width, indent, fontObject, text, rightText, state)
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

    local textX = indent + (state ~= nil and TEXT_X or 0)
    row.text:SetFontObject(fontObject)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", textX, -2)
    row.text:SetWidth(math.max(40, width - textX - (rightText and RIGHT_W or 0) - 2))
    row.text:SetText(text)
    row.right:SetText(rightText or "")

    local h = floor((row.text:GetStringHeight() or 10) + 0.5) + 5
    if h < CHECK + 4 then h = CHECK + 4 end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
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

function List:Render()
    local win = self.Win
    if not win or not win:IsShown() then return end

    local State, Routing, Core, Pins = Q.State, Q.Routing, Q.Core, Q.Pins
    local child = self.Child
    local width = win:GetWidth() - 16 - SCROLLBAR_W
    child:SetWidth(width)

    local quests = {}
    for i, q in ipairs(State.Quests) do quests[i] = q end
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

        if not folded[group.name] then
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
                if Q.Party then title = title .. Q.Party:Badge(questID) end
                y = y + placeRow(qrow, child, y, width, QUEST_INDENT, GameFontNormalSmall, title,
                    distanceText(info[questID]) or (not watched and "untracked") or nil, watched)
                qrow.text:SetAlpha(watched and 1 or 0.6)
                if questID == activeQuest then qrow.active:Show() else qrow.active:Hide() end

                if open[questID] then
                    local any = false
                    for _, o in ipairs(q.objectives) do
                        if o.text ~= "" then
                            any = true
                            used = used + 1
                            local orow = self:AcquireRow(used)
                            orow.kind, orow.zone, orow.questID = "objective", nil, questID
                            y = y + placeRow(orow, child, y, width, OBJECTIVE_INDENT,
                                GameFontHighlightSmall, o.text, nil, nil) - 3
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
                if textOpen[questID] then
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

    local win = AlchemyGPS.UI.Window:Create{
        name = "AlchemyGPSQuestList",
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
    AlchemyGPS.UI.Mixins.Resizable.RestoreSize(win)
    AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(win, UIParent)

    local content = win.content

    local function barButton(x, label, onClick)
        local but = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        but:SetSize(76, 20)
        but:SetPoint("TOPLEFT", x, 0)
        but:SetText(label)
        but:SetScript("OnClick", onClick)
        return but
    end
    barButton(0, "Track all", function() Q.State:SetGroupWatched(nil, true) end)
    barButton(80, "Track none", function() Q.State:SetGroupWatched(nil, false) end)

    local summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPRIGHT", -4, -5)
    summary:SetJustifyH("RIGHT")
    summary:SetTextColor(0.7, 0.7, 0.7)
    self.Summary = summary

    local scroll = Widget.CreateScrollFrame(content, "AlchemyGPSQuestListScroll")
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
        AlchemyGPS.UI.Mixins.Resizable.RestoreSize(win)
        AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(win, UIParent)
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
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", redraw)
    EventBus:Subscribe("QUEST_CATALOG_READY", redraw)
end
