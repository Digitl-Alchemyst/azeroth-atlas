---------------------------------------------------------------------------------------
-- Alchemy GPS | Quest/QuestDetails.lua
--
-- 2026-11-18 (user request, from Carbonite: "Details beside the list -
-- Quest text in a side panel, with a parchment background, and colour
-- and scale settings. Ours opens the text under the quest").
--
-- A panel stuck to the quest list's side (its right, or its left when
-- the screen has no room there) showing one quest: title, level and
-- zone, objectives with progress, the "Quest Objectives" summary, the
-- description, and who in the group has it too. Opened from the list's
-- right-click "Show quest text"; while it's open, clicking another
-- quest shows that one. Hides with the list.
--
-- Settings > Quests, "Quest text":
--   ListTextSide      true: this panel (default); false: under the quest
--   DetailsParchment  parchment background (default) or a dark one
--   DetailsColor      "auto" (dark ink on parchment, white on dark),
--                     "dark", "light", "gold"
--   DetailsScale      text size, 0.7 - 1.5
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Widget = AlchemyGPS.UI.Widget
local Q = AlchemyGPS.Modules.Quest

local Details = {}
Q.Details = Details

local WIDTH = 300
local PAD = 14

-- { text, heading } colours per choice.
local COLORS = {
    dark  = { { 0.18, 0.10, 0.02 }, { 0.42, 0.13, 0.0 } },
    light = { { 0.92, 0.92, 0.92 }, { 1, 0.82, 0 } },
    gold  = { { 1, 0.86, 0.55 }, { 1, 0.95, 0.75 } },
}
Details.COLOR_CHOICES = {
    { id = "auto",  label = "Automatic (dark ink on parchment)" },
    { id = "dark",  label = "Dark ink" },
    { id = "light", label = "White" },
    { id = "gold",  label = "Gold" },
}

function Details:SidePanelOn()
    return Q.Core:Opt("ListTextSide") ~= false
end

local function colors()
    local choice = Q.Core:Opt("DetailsColor") or "auto"
    if choice == "auto" or not COLORS[choice] then
        choice = (Q.Core:Opt("DetailsParchment") ~= false) and "dark" or "light"
    end
    return COLORS[choice][1], COLORS[choice][2]
end

function Details:Create()
    if self.Frm then return self.Frm end
    local f = CreateFrame("Frame", "AlchemyGPSQuestDetails", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 400)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:EnableMouse(true)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    f.bg = bg

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() self:Hide() end)

    local scroll = Widget.CreateScrollFrame(f, "AlchemyGPSQuestDetailsScroll")
    scroll:SetPoint("TOPLEFT", PAD - 4, -28)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    f.scroll = scroll
    local child = scroll.ScrollChild
    f.child = child

    local function fs(font)
        local s = child:CreateFontString(nil, "OVERLAY", font)
        s:SetJustifyH("LEFT")
        if s.SetWordWrap then s:SetWordWrap(true) end
        return s
    end
    f.title = fs("GameFontNormalLarge")
    f.sub = fs("GameFontHighlightSmall")
    f.objHead = fs("GameFontNormal")
    f.objs = fs("GameFontHighlight")
    f.sumHead = fs("GameFontNormal")
    f.summary = fs("GameFontHighlight")
    f.descHead = fs("GameFontNormal")
    f.desc = fs("GameFontHighlight")
    f.party = fs("GameFontHighlightSmall")
    f.order = { f.title, f.sub, f.objHead, f.objs, f.sumHead, f.summary, f.descHead, f.desc, f.party }

    self.Frm = f
    return f
end

-- Beside the list: right of it, or left when there's no room.
function Details:Place()
    local f, list = self.Frm, Q.List and Q.List.Win
    if not f or not list then return end
    f:ClearAllPoints()
    f:SetHeight(math.max(200, list:GetHeight()))
    local scale = list:GetEffectiveScale() / f:GetEffectiveScale()
    local right = list:GetRight()
    if right and right * scale + WIDTH + 2 > UIParent:GetRight() then
        f:SetPoint("TOPRIGHT", list, "TOPLEFT", -2, 0)
    else
        f:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, 0)
    end
end

function Details:IsShowing(questID)
    return self.Frm ~= nil and self.Frm:IsShown() and (questID == nil or self.QuestID == questID)
end

function Details:Show(questID)
    local list = Q.List and Q.List.Win
    if not questID or not list or not list:IsShown() then return end
    local f = self:Create()
    self.QuestID = questID
    if not self.Hooked then
        self.Hooked = true
        list:HookScript("OnHide", function() self:Hide() end)
        list:HookScript("OnSizeChanged", function() if f:IsShown() then self:Place() end end)
    end
    self:Place()
    f:Show()
    self:Refresh()
    if Q.List.Render then Q.List:Render() end
end

function Details:Hide()
    if self.Frm then self.Frm:Hide() end
    self.QuestID = nil
    if Q.List and Q.List.Render then Q.List:Render() end
end

function Details:Toggle(questID)
    if self:IsShowing(questID) then self:Hide() else self:Show(questID) end
end

local function hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

function Details:Refresh()
    local f = self.Frm
    if not f or not f:IsShown() then return end
    local questID = self.QuestID
    local q = questID and Q.State:GetQuest(questID)
    if not q then
        -- Turned in or abandoned.
        self:Hide()
        return
    end

    local parchment = Q.Core:Opt("DetailsParchment") ~= false
    if parchment then
        f.bg:SetTexture("Interface\\QuestFrame\\QuestBG")
        f.bg:SetTexCoord(0, 0.586, 0, 0.65)
        f.bg:SetVertexColor(1, 1, 1, 1)
        f:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)
    else
        f.bg:SetColorTexture(0, 0, 0, 0.88)
        f.bg:SetTexCoord(0, 1, 0, 1)
        f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
    local text, head = colors()
    local scale = Q.Core:Opt("DetailsScale") or 1

    local child = f.child
    child:SetScale(scale)
    local width = (f:GetWidth() - PAD - 30) / scale
    child:SetWidth(width)

    f.title:SetText(q.title or "?")
    local sub = {}
    if q.level and q.level > 0 then sub[#sub + 1] = "Level " .. q.level end
    if q.group then sub[#sub + 1] = q.group end
    if q.isFailed then sub[#sub + 1] = "|cffff4040Failed|r"
    elseif q.ready then sub[#sub + 1] = "|cff20a020Complete|r" end
    -- 2026-11-18: chain part, daily, quest ID.
    local part, total
    if Q.Catalog then part, total = Q.Catalog:GetChainPart(questID) end
    if part then sub[#sub + 1] = ("Part %d of %d"):format(part, total) end
    if Q.List and Q.List.IsDaily and Q.List.IsDaily(q) then sub[#sub + 1] = "Daily" end
    sub[#sub + 1] = "ID " .. questID
    f.sub:SetText(table.concat(sub, "  -  "))

    local lines = {}
    for _, o in ipairs(q.objectives or {}) do
        if o.text ~= "" then
            lines[#lines + 1] = (o.finished and "|cff408040" or "") .. "- " .. o.text .. (o.finished and "|r" or "")
        end
    end
    if #lines == 0 then lines[1] = q.ready and "Ready to turn in." or "No listed objectives." end
    f.objHead:SetText("Progress")
    f.objs:SetText(table.concat(lines, "\n"))

    local desc, summary = Q.Api:GetQuestText(questID)
    f.sumHead:SetText("Quest Objectives")
    f.summary:SetText(summary or "-")
    f.descHead:SetText("Description")
    f.desc:SetText(desc or "The game gave no text for this quest.")

    local members = Q.Party and Q.Party:GetMembers(questID)
    if members and #members > 0 then
        local names = {}
        for _, m in ipairs(members) do names[#names + 1] = m.name end
        f.party:SetText(hex(head) .. "Also on this quest:|r " .. table.concat(names, ", "))
    else
        f.party:SetText("")
    end

    -- Colours: headings, then body text.
    f.title:SetTextColor(head[1], head[2], head[3])
    for _, s in ipairs({ f.objHead, f.sumHead, f.descHead }) do
        s:SetTextColor(head[1], head[2], head[3])
    end
    for _, s in ipairs({ f.sub, f.objs, f.summary, f.desc, f.party }) do
        s:SetTextColor(text[1], text[2], text[3])
    end

    -- Stack them top to bottom.
    local y, gapAfter = 0, { [f.title] = 2, [f.sub] = 10, [f.objHead] = 3, [f.objs] = 10,
        [f.sumHead] = 3, [f.summary] = 10, [f.descHead] = 3, [f.desc] = 10 }
    for _, s in ipairs(f.order) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        s:SetWidth(width)
        local h = s:GetText() ~= "" and (s:GetStringHeight() or 0) or 0
        y = y + h + (h > 0 and (gapAfter[s] or 0) or 0)
    end
    child:SetHeight(math.max(1, y))
end

function Details:Start()
    local function refresh() self:Refresh() end
    EventBus:Subscribe("QUEST_STATE_CHANGED", refresh)
    EventBus:Subscribe("QUEST_PARTY_CHANGED", refresh)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(key)
        if key == "ListTextSide" and not self:SidePanelOn() then self:Hide() end
        refresh()
    end)
end
