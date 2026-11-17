---------------------------------------------------------------------------------------
-- Alchemy GPS | Quest/QuestMenu.lua
--
-- 2026-11-16 (user request: "need to be able to share and abandon quest
-- in our menus both the list and the tracker"; "see the quest text of
-- each quest in the list like blizzards quest menu"). The right-click
-- menu of a quest row in the quest list and the tracker:
--   Show / hide quest text    (list: opens the quest's text under it)
--   <the window's own fold>   (list: objectives; tracker: collapse)
--   Route here / Stop routing
--   Track / Untrack
--   Share with group          (greyed when the game says it can't be)
--   Abandon quest...          (asks first)
-- Same look as the map's right-click menu (Map/MapContextMenu.lua).
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local Q = AlchemyGPS.Modules.Quest

local Menu = {}
Q.Menu = Menu

local ROW_H, ROW_GAP, PAD, WIDTH = 16, 2, 10, 190
local menu

local function close()
    if menu then menu:Hide() end
end
Menu.Close = close

StaticPopupDialogs["ALCHEMYGPS_ABANDON_QUEST"] = {
    text = "Abandon \"%s\"?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        if data and Q.Api:Abandon(data) then
            UIErrorsFrame:AddMessage(("Abandoned: %s"):format(Q.State:GetQuest(data) and Q.State:GetQuest(data).title or data),
                1, 0.82, 0)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(0.4, 0.4, 0.8, 0.35)
    row:SetHighlightTexture(hl)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
    fs:SetJustifyH("LEFT")
    row.text = fs
    row:SetScript("OnClick", function(self)
        if self.action then self.action() end
        close()
    end)
    return row
end

local function create()
    if menu then return menu end
    menu = CreateFrame("Frame", "AlchemyGPSQuestMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu.rows = {}
    local titleFs = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleFs:SetPoint("TOPLEFT", PAD + 4, -PAD)
    titleFs:SetPoint("TOPRIGHT", -PAD - 4, -PAD)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    menu.title = titleFs
    -- Close when the mouse has been off the menu for a moment, like a
    -- dropdown, and on Escape.
    menu:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver(4, -4, -4, 4) then
            self.away = 0
        else
            self.away = (self.away or 0) + elapsed
            if self.away > 1.5 then close() end
        end
    end)
    tinsert(UISpecialFrames, "AlchemyGPSQuestMenu")
    menu:Hide()
    return menu
end

-- items: { { text, action, disabled, tip }, ... }
local function show(title, items)
    local m = create()
    m.title:SetText(title)
    local y = -PAD - 16
    for i, it in ipairs(items) do
        local row = m.rows[i] or createRow(m)
        m.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, y)
        row:SetPoint("TOPRIGHT", m, "TOPRIGHT", -PAD, y)
        row.text:SetText(it[1])
        row.action = it[2]
        row:SetEnabled(not it[3])
        row.text:SetTextColor(it[3] and 0.5 or 1, it[3] and 0.5 or 0.82, it[3] and 0.5 or 0)
        row:Show()
        y = y - ROW_H - ROW_GAP
    end
    for i = #items + 1, #m.rows do m.rows[i]:Hide() end
    m:SetSize(WIDTH, -y + PAD - ROW_GAP)
    local x, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 8, cy / s + 8)
    m.away = 0
    m:Show()
end

-- Opens the menu for a quest. opts:
--   textShown      the quest's text is open in the list (nil: no text row)
--   onText         toggles it
--   foldText/onFold  the window's own fold row (objectives / collapse)
--   redraw         the window's re-render
function Menu:Open(questID, opts)
    local State, Routing, Api = Q.State, Q.Routing, Q.Api
    local q = questID and State:GetQuest(questID)
    if not q then return end
    opts = opts or {}
    local items = {}
    if opts.onText then
        items[#items + 1] = { opts.textShown and "Hide quest text" or "Show quest text", opts.onText }
    end
    if opts.onFold then
        items[#items + 1] = { opts.foldText, opts.onFold }
    end
    if Routing and Routing.ToggleManualQuest then
        local routed = Routing.Target and Routing.Target.kind == "quest" and Routing.Target.questID == questID
        items[#items + 1] = { routed and "Stop routing here" or "Route here", function()
            Routing:ToggleManualQuest(questID)
            if opts.redraw then opts.redraw() end
        end }
    end
    local watched = State:IsWatched(questID)
    items[#items + 1] = { watched and "Untrack" or "Track", function()
        State:SetWatched(questID, not watched)
    end }
    local canShare = Api:CanShare(questID)
    items[#items + 1] = { IsInGroup() and "Share with group" or "Share with group (not in a group)",
        function() Api:Share(questID) end, not canShare }
    items[#items + 1] = { "|cffff6060Abandon quest...|r", function()
        local dialog = StaticPopup_Show("ALCHEMYGPS_ABANDON_QUEST", q.title)
        if dialog then dialog.data = questID end
    end }
    show(q.title, items)
end
