-- Alchemy GPS | Quest / QuestTracker
-- The on-screen quest list that stands in for Blizzard's own tracker
-- (hidden by TrackerHider.lua). New UI on this addon's own small
-- window chrome (UI/SmallWindow.lua) - not a port. Carbonite's
-- WatchWindow.lua is built on its own Button.TypeData skin-table
-- system, which this addon doesn't have and shouldn't grow for one
-- window; what is borrowed from it, and from Questie's tracker, is
-- behaviour: quests grouped under their zone or dungeon, nearest first,
-- per-quest collapse, click a quest to route to it, and a "+N more" line
-- instead of running off the window.
--
--   Click a quest          route the arrow to it (click again to release)
--   Right-click            collapse / expand its objectives
--   Shift-click            take it off the tracker
--   Shift-right-click      put its link in chat (2026-11-18)
--   Click a zone heading   fold / unfold that zone's quests
--   Shift-click a heading  take the whole zone off the tracker
--   "Auto" in the title    route to whichever tracked quest is closest
--   "List"                 the full quest list (QuestList.lua)
--   "-" / "+"              roll the tracker up to its title bar
--
-- Usable quest items get a button beside their quest; those are
-- QuestItems.lua's, which this file only tells where the rows are.
--
-- Reads QuestState (what to list) and QuestRouting (distances, which
-- quest the arrow is on). Redraws when either says something changed,
-- plus a slow tick while visible so the distance column and nearest-
-- first order keep up as the player moves.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest

local Tracker = {}
Q.Tracker = Tracker

Tracker.Rows = {}

local SWATCH_W = 3
local TEXT_X = SWATCH_W + 4
local DIST_W = 44
local OBJECTIVE_INDENT = 10
local ROW_GAP = 1
local QUEST_GAP = 4
local FOOTER_H = 14
local ZONE_GAP = 2
local CONTENT_TOP = 28      -- SmallWindow.lua: content starts this far below the window's top
local COLLAPSED_H = 32      -- window height when rolled up: the title bar and its border
local REFRESH_EVERY = 2     -- seconds between distance/order refreshes

local floor = math.floor

local function rowOnClick(row, button)
    local State, Routing, Core = Q.State, Q.Routing, Q.Core
    if row.kind == "footer" then
        if row.restores then State:WatchAll() end
        return
    end
    if row.kind == "zone" then
        if IsShiftKeyDown() then
            State:SetGroupWatched(row.zone, false)
        else
            local folded = Core:Char("CollapsedZones")
            folded[row.zone] = (not folded[row.zone]) and true or nil
            Tracker:Render()
        end
        return
    end
    local questID = row.questID
    if not questID then return end

    if button == "RightButton" and IsShiftKeyDown() and Q.Links then
        Q.Links:InsertInChat(questID)       -- 2026-11-18: link in chat
    elseif button == "RightButton" then
        -- 2026-11-16: the quest menu (Quest/QuestMenu.lua) - collapse,
        -- route, track, share, abandon.
        local collapsed = Core:Char("Collapsed")
        Q.Menu:Open(questID, {
            foldText = collapsed[questID] and "Expand" or "Collapse",
            onFold = function()
                collapsed[questID] = (not collapsed[questID]) and true or nil
                Tracker:Render()
            end,
            redraw = function() Tracker:Render() end,
        })
    elseif IsShiftKeyDown() then
        State:SetWatched(questID, false)
    elseif Routing then
        Routing:ToggleManualQuest(questID)
        Tracker:Render()
    end
end

local function rowOnEnter(row)
    if row.kind == "footer" then
        if not row.restores then return end
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:SetText("Untracked quests")
        GameTooltip:AddLine("Click to put every quest back on the tracker.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if row.kind == "zone" then
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:SetText(row.zone)
        GameTooltip:AddLine("Click: fold / unfold", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: stop tracking every quest here", 0.6, 0.6, 0.6)
        GameTooltip:Show()
        return
    end
    local q = row.questID and Q.State:GetQuest(row.questID)
    if not q then return end

    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(q.title)
    if q.header and q.header ~= "" then
        GameTooltip:AddLine(q.header, 0.7, 0.7, 0.7)
    end
    for _, o in ipairs(q.objectives) do
        if o.text ~= "" then
            if o.finished then
                GameTooltip:AddLine(o.text, 0.5, 0.75, 0.5)
            else
                GameTooltip:AddLine(o.text, 1, 1, 1)
            end
        end
    end
    local t = Q.Routing and Q.Routing.Target
    if t and t.kind == "quest" and t.questID == q.questID and t.detail then
        GameTooltip:AddLine("Arrow: " .. t.detail, 1, 0.82, 0.2, true)
    end
    if Q.Party then Q.Party:AddTooltip(q.questID) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: route here    Right-click: menu (collapse, share, abandon)", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("Shift-click: stop tracking    Shift-right-click: link in chat", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function rowOnLeave()
    GameTooltip:Hide()
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local active = row:CreateTexture(nil, "BACKGROUND")
    active:SetAllPoints()
    active:Hide()
    row.active = active

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)

    local swatch = row:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 0, -1)
    swatch:SetPoint("BOTTOMLEFT", 0, 1)
    swatch:SetWidth(SWATCH_W)
    row.swatch = swatch

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    if text.SetWordWrap then text:SetWordWrap(true) end
    row.text = text

    local dist = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dist:SetPoint("TOPRIGHT", 0, -1)
    dist:SetWidth(DIST_W)
    dist:SetJustifyH("RIGHT")
    dist:SetTextColor(0.65, 0.65, 0.65)
    row.dist = dist

    row:SetScript("OnClick", rowOnClick)
    row:SetScript("OnEnter", rowOnEnter)
    row:SetScript("OnLeave", rowOnLeave)
    return row
end

function Tracker:AcquireRow(index)
    local row = self.Rows[index]
    if not row then
        row = createRow(self.Win.content)
        self.Rows[index] = row
    end
    return row
end

-- Lays one row out at vertical offset y and returns its height.
local function placeRow(row, parent, y, width, indent, fontObject, text, distText)
    row.text:SetFontObject(fontObject)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", TEXT_X + indent, -1)
    row.text:SetWidth(math.max(40, width - TEXT_X - indent - (distText and DIST_W or 0)))
    row.text:SetText(text)
    row.dist:SetText(distText or "")

    local h = floor((row.text:GetStringHeight() or 10) + 0.5) + 2
    if h < 12 then h = 12 end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    row:SetSize(width, h)
    row:Show()
    return h
end

local function distanceText(entry)
    if not entry or not entry.res then return "" end
    if entry.far then return "far" end
    if not entry.yards then return "" end
    if entry.res.inside then return "here" end
    if entry.yards >= 1000 then
        return ("%.1fk"):format(entry.yards / 1000)
    end
    return ("%d yd"):format(floor(entry.yards + .5))
end

-- Nearest first; quests with no known distance after those with one.
local function sortByDistance(quests, info)
    table.sort(quests, function(a, b)
        local ia, ib = info[a.questID], info[b.questID]
        local da, db = ia and ia.dist, ib and ib.dist
        if da and db then
            if da ~= db then return da < db end
        elseif da or db then
            return da ~= nil
        end
        if a.level ~= b.level then return a.level < b.level end
        return a.questID < b.questID
    end)
end

function Tracker:Render()
    local win = self.Win
    if not win or not win:IsShown() then return end

    local State, Routing, Core, Pins, Items = Q.State, Q.Routing, Q.Core, Q.Pins, Q.Items
    local content = win.content
    local quests = State:GetWatchedQuests()
    local total = #quests

    win:SetTitle(total > 0 and ("Quests (%d)"):format(total) or "Quests")
    self:UpdateAutoButton()
    if Core:Opt("TrackerCollapsed") then
        for n = 1, #self.Rows do self.Rows[n]:Hide() end
        if Items then Items:Layout(win, nil) end
        return
    end

    -- From the window's own explicit size, not content:GetWidth(): a
    -- frame sized purely by anchors hasn't always resolved its rect yet.
    local width = win:GetWidth() - 16
    local height = win:GetHeight() - 36

    local info = (Routing and Routing.QuestInfo) or {}
    sortByDistance(quests, info)

    -- One group per zone / dungeon heading, the group holding the
    -- nearest quest first - or a single unnamed group with the option off.
    local groups
    if Core:Opt("TrackerGroupByZone") then
        groups = State:GroupQuests(quests)      -- keeps the nearest-first order
    else
        groups = { { quests = quests } }
    end

    local target = Routing and Routing.Target
    local activeQuest = target and target.kind == "quest" and target.questID or nil
    local collapsed = Core:Char("Collapsed")
    local folded = Core:Char("CollapsedZones")
    local unwatched = State:GetNumUnwatched()
    local maxQuests = Core:Opt("TrackerMaxQuests") or 12

    local used, y, shown, hidden = 0, 0, 0, 0
    local itemRows = {}
    local full = false

    for _, group in ipairs(groups) do
        if full then break end
        local groupUsed, groupY, groupShown = used, y, 0

        if group.name then
            used = used + 1
            local row = self:AcquireRow(used)
            row.kind, row.questID, row.restores, row.zone = "zone", nil, nil, group.name
            local mark = folded[group.name] and "+" or "-"
            y = y + placeRow(row, content, y, width, 0, GameFontNormalSmall,
                ("|cffa0a0a0%s|r %s |cff808080(%d)|r"):format(mark, group.name, #group.quests), nil) + ROW_GAP
            row.text:SetTextColor(1, 0.82, 0)
            row.swatch:Hide()
            row.active:Hide()
        end

        if group.name and folded[group.name] then
            -- Still tracked and routed to, just not listed.
            hidden = hidden + #group.quests
            y = y + ZONE_GAP
        else
            for _, q in ipairs(group.quests) do
                if shown >= maxQuests then full = true; break end
                local startUsed, startY = used, y
                local questID = q.questID

                used = used + 1
                local row = self:AcquireRow(used)
                row.kind, row.questID, row.restores, row.zone = "quest", questID, nil, nil

                local title = Pins:ColoredTitle(q.level, q.title, questID)
                -- (Daily), (part 2/4), #ID - same settings as the quest list.
                if Q.List and Q.List.TitleExtras then
                    title = title .. Q.List.TitleExtras(questID, q)
                end
                if q.isFailed then
                    title = title .. " |cffff4040(Failed)|r"
                elseif q.ready then
                    title = title .. " |cff66ff66(Complete)|r"
                end
                if Q.Party then title = title .. Q.Party:Badge(questID) end
                if collapsed[questID] and not q.ready and #q.objectives > 0 then
                    title = "|cffa0a0a0+|r " .. title
                end
                local titleY = y
                y = y + placeRow(row, content, y, width, 0, GameFontNormalSmall, title,
                    distanceText(info[questID])) + ROW_GAP

                local r, g, b = Pins:QuestColor(questID)
                row.swatch:SetColorTexture(r, g, b, 0.9)
                row.swatch:Show()
                if questID == activeQuest then
                    if Routing:IsManualQuest(questID) then
                        row.active:SetColorTexture(1, 0.82, 0, 0.22)
                    else
                        row.active:SetColorTexture(1, 0.82, 0, 0.10)
                    end
                    row.active:Show()
                else
                    row.active:Hide()
                end

                -- A finished quest's objectives are all ticked; the title's
                -- "(Complete)" already says so.
                if not q.ready and not collapsed[questID] then
                    for _, o in ipairs(q.objectives) do
                        if o.text ~= "" then
                            used = used + 1
                            local orow = self:AcquireRow(used)
                            orow.kind, orow.questID, orow.restores, orow.zone = "objective", questID, nil, nil
                            y = y + placeRow(orow, content, y, width, OBJECTIVE_INDENT,
                                GameFontHighlightSmall, o.text, nil) + ROW_GAP
                            if o.finished then
                                orow.text:SetTextColor(0.5, 0.7, 0.5)
                            else
                                orow.text:SetTextColor(0.9, 0.9, 0.9)
                            end
                            orow.swatch:Hide()
                            orow.active:Hide()
                        end
                    end
                end
                y = y + QUEST_GAP

                -- Doesn't fit (leaving room for the footer if one will be
                -- needed)? Give this quest's rows back and stop - taking
                -- the zone heading too if it would be left with nothing
                -- under it - but always show at least one quest, however
                -- small the window.
                local needsFooter = (total - hidden - (shown + 1)) > 0 or unwatched > 0
                if shown > 0 and y + (needsFooter and FOOTER_H or 0) > height then
                    if groupShown == 0 then startUsed, startY = groupUsed, groupY end
                    for n = startUsed + 1, used do self.Rows[n]:Hide() end
                    used, y = startUsed, startY
                    full = true
                    break
                end
                shown = shown + 1
                groupShown = groupShown + 1
                itemRows[#itemRows + 1] = { questID = questID, y = CONTENT_TOP + titleY }
            end
            -- Stopped before listing anything under this heading (the
            -- quest limit): don't leave the heading on its own.
            if full and groupShown == 0 and group.name and used > groupUsed then
                for n = groupUsed + 1, used do self.Rows[n]:Hide() end
                used, y = groupUsed, groupY
            end
        end
    end

    local more = total - hidden - shown
    local footer
    if total == 0 and unwatched == 0 then
        footer = State.Scanned and "No quests in your log" or "Reading quest log..."
    elseif more > 0 and unwatched > 0 then
        footer = ("+%d more, %d untracked (click to restore)"):format(more, unwatched)
    elseif more > 0 then
        footer = ("+%d more"):format(more)
    elseif unwatched > 0 then
        footer = ("%d untracked (click to restore)"):format(unwatched)
    end
    if footer then
        used = used + 1
        local row = self:AcquireRow(used)
        row.kind, row.questID, row.restores, row.zone = "footer", nil, unwatched > 0, nil
        placeRow(row, content, y, width, 0, GameFontHighlightSmall, footer, nil)
        row.text:SetTextColor(0.6, 0.6, 0.6)
        row.swatch:Hide()
        row.active:Hide()
    end

    for n = used + 1, #self.Rows do
        self.Rows[n]:Hide()
    end

    if Items then Items:Layout(win, itemRows) end
end

function Tracker:UpdateAutoButton()
    local but = self.AutoBut
    if not but then return end
    if Q.Core:Opt("AutoTrack") then
        but.text:SetTextColor(0.4, 1, 0.4)
    else
        but.text:SetTextColor(0.55, 0.55, 0.55)
    end
end

function Tracker:ApplyLock()
    local win = self.Win
    if not win then return end
    local locked = Q.Core:Opt("TrackerLocked")
    if locked then
        win:RegisterForDrag()
    else
        win:RegisterForDrag("LeftButton")
    end
    if win.resizeGrip then
        if locked or Q.Core:Opt("TrackerCollapsed") then win.resizeGrip:Hide() else win.resizeGrip:Show() end
    end
end

-- Rolls the tracker up to its title bar, or back down. The top-left
-- corner is pinned first so the title bar stays where it is and the
-- body opens downward from it, wherever the window was anchored.
function Tracker:ApplyCollapsed()
    local win = self.Win
    if not win then return end
    local collapsed = Q.Core:Opt("TrackerCollapsed")

    local left, top = win:GetLeft(), win:GetTop()
    if left and top then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    if collapsed then
        win:SetHeight(COLLAPSED_H)
        win.content:Hide()
    else
        win:SetHeight(Q.Core:ProfileTable("TrackerSize").h or 300)
        win.content:Show()
    end
    if self.FoldBut then self.FoldBut.text:SetText(collapsed and "+" or "-") end
    self:ApplyLock()
    self:Render()
end

-- A small text button in the title bar, `x` in from the right edge.
local function titleButton(win, x, w, label, tipTitle, tipText, onClick)
    local but = CreateFrame("Button", nil, win)
    but:SetSize(w, 16)
    but:SetPoint("TOPRIGHT", x, -8)
    local text = but:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    but.text = text
    but:SetScript("OnClick", onClick)
    but:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText(tipTitle)
        GameTooltip:AddLine(tipText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    but:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return but
end

function Tracker:Create()
    if self.Win then return self.Win end
    local Core = Q.Core

    local anchor = Core:ProfileTable("TrackerAnchor")
    if not anchor.point then
        anchor.point, anchor.relPoint, anchor.x, anchor.y = "RIGHT", "RIGHT", -30, 40
    end

    local win = AlchemyGPS.UI.Window:Create{
        name = "AlchemyGPSQuestTracker",
        title = "Quests",
        width = 250,
        height = 300,
        strata = "LOW",
        dbAnchor = anchor,
        dbSize = Core:ProfileTable("TrackerSize"),
        resizable = true,
        minWidth = 170,
        minHeight = 90,
        onResizeStop = function() self:Render() end,
        noEscClose = true,
        onClose = function() Core:SetOpt("TrackerShown", false) end,
    }
    self.Win = win

    AlchemyGPS.UI.Mixins.Resizable.RestoreSize(win)
    AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(win, UIParent)

    -- Title bar, right to left: close, Auto, List, roll up.
    self.AutoBut = titleButton(win, -26, 34, "Auto", "Auto-track",
        "On: the arrow follows whichever tracked quest is closest. Off: it only follows a quest you click.",
        function() Core:SetOpt("AutoTrack", not Core:Opt("AutoTrack")) end)
    local listBut = titleButton(win, -62, 26, "List", "Quest list",
        "Every quest in your log by zone, with tracking on or off for each one or for a whole zone.",
        function() if Q.List then Q.List:Toggle() end end)
    listBut.text:SetTextColor(0.8, 0.8, 0.8)
    self.FoldBut = titleButton(win, -90, 16, "-", "Roll up",
        "Roll the tracker up to its title bar, or back down.",
        function() Core:SetOpt("TrackerCollapsed", not Core:Opt("TrackerCollapsed")) end)
    self.FoldBut.text:SetTextColor(0.8, 0.8, 0.8)

    local elapsedTotal = 0
    win:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= REFRESH_EVERY then
            elapsedTotal = 0
            self:Render()
        elseif Q.Items and Q.Items:IsStale(win) then
            -- Dragged: the item buttons aren't attached to the window
            -- (see QuestItems.lua), so they are moved after it.
            self:Render()
        end
    end)
    -- With the window hidden the buttons would be left floating.
    win:HookScript("OnHide", function()
        if Q.Items then Q.Items:Layout(win, nil) end
    end)

    self:ApplyLock()
    if Core:Opt("TrackerCollapsed") then self:ApplyCollapsed() end
    return win
end

function Tracker:ApplyShown()
    if Q.Core:Opt("TrackerShown") then
        self:Create():Show()
        self:Render()
    elseif self.Win then
        self.Win:Hide()
    end
end

function Tracker:Start()
    self:ApplyShown()

    local function redraw() self:Render() end
    EventBus:Subscribe("QUEST_STATE_CHANGED", redraw)
    EventBus:Subscribe("QUEST_PARTY_CHANGED", redraw)
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", redraw)
    EventBus:Subscribe("QUEST_CATALOG_READY", redraw)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(_, key)
        if key == "TrackerShown" then
            self:ApplyShown()
        elseif key == "TrackerLocked" then
            self:ApplyLock()
        elseif key == "TrackerCollapsed" then
            self:ApplyCollapsed()
        else
            self:Render()
        end
    end)
end
