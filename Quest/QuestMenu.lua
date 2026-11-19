---------------------------------------------------------------------------------------
-- Azeroth Atlas | Quest/QuestMenu.lua
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

local AzerothAtlas = _G.AzerothAtlas
local Q = AzerothAtlas.Modules.Quest

local Menu = {}
Q.Menu = Menu

local ROW_H, ROW_GAP, PAD, WIDTH = 16, 2, 10, 190
local menu

local function close()
    if menu then menu:Hide() end
end
Menu.Close = close

StaticPopupDialogs["AZEROTHATLAS_ABANDON_QUEST"] = {
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
    menu = CreateFrame("Frame", "AzerothAtlasQuestMenu", UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, "AzerothAtlasQuestMenu")
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

---------------------------------------------------------------------------------------
-- Links (2026-11-18, user request, from Carbonite: "Shift-right-click
-- puts a quest link in chat. Quest links can carry level and part
-- number. You can also copy a Wowhead link" - "make work for both list
-- and tracker"). Both windows' Shift-right-click and this menu's two
-- rows call these. The level and chain part go AFTER the link as plain
-- text - the server may refuse a link whose own text was changed.
---------------------------------------------------------------------------------------

local Links = {}
Q.Links = Links

local WOWHEAD = "https://www.wowhead.com/classic/quest=%d"

function Links:Get(questID)
    local q = Q.State:GetQuest(questID)
    local get = _G.GetQuestLink
    if get then
        local ok, link = pcall(get, questID)
        if ok and type(link) == "string" and link:find("|Hquest:") then return link end
        local idx = Q.Api:GetLogIndexForQuestID(questID)
        if idx then
            ok, link = pcall(get, idx)
            if ok and type(link) == "string" and link:find("|Hquest:") then return link end
        end
    end
    local title = (q and q.title) or Q.Api:GetTitle(questID) or ("Quest " .. questID)
    return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(questID, (q and q.level) or 0, title)
end

-- The link, plus " (level 12, part 2/4)" when that's switched on.
function Links:ChatText(questID)
    local text = self:Get(questID)
    if Q.Core:Opt("QuestLinkExtras") ~= false then
        local q = Q.State:GetQuest(questID)
        local bits = {}
        if q and q.level and q.level > 0 then bits[#bits + 1] = "level " .. q.level end
        local part, total
        if Q.Catalog then part, total = Q.Catalog:GetChainPart(questID) end
        if part then bits[#bits + 1] = ("part %d/%d"):format(part, total) end
        if #bits > 0 then text = text .. " (" .. table.concat(bits, ", ") .. ")" end
    end
    return text
end

-- Into the chat box being typed in, or a new one.
function Links:InsertInChat(questID)
    local text = self:ChatText(questID)
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if box and ChatEdit_InsertLink then
        ChatEdit_InsertLink(text)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
    end
end

StaticPopupDialogs["AZEROTHATLAS_COPY_URL"] = {
    text = "%s\n\nPress Ctrl+C to copy.",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        if box then
            box:SetText(data or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Links:CopyWowhead(questID)
    local q = Q.State:GetQuest(questID)
    StaticPopup_Show("AZEROTHATLAS_COPY_URL", (q and q.title) or ("Quest " .. questID), nil,
        WOWHEAD:format(questID))
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
    items[#items + 1] = { "Link in chat  |cff9d9d9d(Shift-right-click)|r", function()
        Links:InsertInChat(questID)
    end }
    items[#items + 1] = { "Copy Wowhead link", function() Links:CopyWowhead(questID) end }
    local canShare = Api:CanShare(questID)
    items[#items + 1] = { IsInGroup() and "Share with group" or "Share with group (not in a group)",
        function() Api:Share(questID) end, not canShare }
    items[#items + 1] = { "|cffff6060Abandon quest...|r", function()
        local dialog = StaticPopup_Show("AZEROTHATLAS_ABANDON_QUEST", q.title)
        if dialog then dialog.data = questID end
    end }
    show(q.title, items)
end
