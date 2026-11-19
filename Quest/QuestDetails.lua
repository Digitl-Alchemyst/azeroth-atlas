---------------------------------------------------------------------------------------
-- Azeroth Atlas | Quest/QuestDetails.lua
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
--   DetailsDark       dark mode (default): the parchment desaturated and
--                     dimmed the way the DarkMode addon does Blizzard's
--                     windows (its default "Dark" setting: desaturate,
--                     tint 0.36), white text. Off: the regular parchment.
--   DetailsParchment  parchment background (default) or a plain black one
--   DetailsColor      "auto" (dark ink on regular parchment, white
--                     otherwise), "dark", "light", "gold"
--   DetailsScale      text size, 0.7 - 1.5
--
-- 2026-11-18: a button bar along the bottom - Track, Route, Share,
-- Abandon, Wowhead (the same actions as the list's right-click menu).
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Widget = AzerothAtlas.UI.Widget
local Q = AzerothAtlas.Modules.Quest

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

-- DarkMode's "Dark" colour mode (DarkMode/colors.lua), its default.
local DARK_TINT = 0.36

local function darkMode() return Q.Core:Opt("DetailsDark") ~= false end
local function parchment() return Q.Core:Opt("DetailsParchment") ~= false end
-- Regular parchment is the one light background; dark ink goes on it.
local function lightBackground() return parchment() and not darkMode() end

local function colors()
    local choice = Q.Core:Opt("DetailsColor") or "auto"
    if choice == "auto" or not COLORS[choice] then
        choice = lightBackground() and "dark" or "light"
    end
    return COLORS[choice][1], COLORS[choice][2]
end

-- A stock red button, greyed down to match in dark mode.
local function tintButton(b, dark)
    for _, region in ipairs({ b:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() ~= "HIGHLIGHT" then
            if region.SetDesaturated then region:SetDesaturated(dark) end
            local v = dark and 0.55 or 1
            region:SetVertexColor(v, v, v)
        end
    end
end

function Details:Create()
    if self.Frm then return self.Frm end
    local f = CreateFrame("Frame", "AzerothAtlasQuestDetails", UIParent, "BackdropTemplate")
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

    local scroll = Widget.CreateScrollFrame(f, "AzerothAtlasQuestDetailsScroll")
    scroll:SetPoint("TOPLEFT", PAD - 4, -28)
    scroll:SetPoint("BOTTOMRIGHT", -30, 38)
    f.scroll = scroll

    -- 2026-11-18: actions along the bottom.
    f.buttons = {}
    local function action(key, label, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetHeight(22)
        b:SetText(label)
        local fsx = b:GetFontString()
        if fsx then fsx:SetFontObject(GameFontNormalSmall) end
        b:SetScript("OnClick", function()
            if not self.QuestID then return end
            onClick(self.QuestID)
            self:Refresh()
        end)
        f.buttons[#f.buttons + 1] = b
        f[key] = b
        return b
    end
    action("trackBtn", "Track", function(questID)
        Q.State:SetWatched(questID, not Q.State:IsWatched(questID))
    end)
    action("routeBtn", "Route", function(questID)
        if Q.Routing then Q.Routing:ToggleManualQuest(questID) end
        if Q.List and Q.List.Render then Q.List:Render() end
        self:Refresh()
    end)
    action("shareBtn", "Share", function(questID) Q.Api:Share(questID) end)
    action("abandonBtn", "Abandon", function(questID)
        local q = Q.State:GetQuest(questID)
        local dialog = StaticPopup_Show("AZEROTHATLAS_ABANDON_QUEST", q and q.title or questID)
        if dialog then dialog.data = questID end
    end)
    action("wowheadBtn", "Wowhead", function(questID)
        if Q.Links then Q.Links:CopyWowhead(questID) end
    end)
    local function hint(b, text)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    hint(f.trackBtn, "Track / untrack on the quest tracker")
    hint(f.routeBtn, "Route the arrow to this quest / stop")
    hint(f.shareBtn, "Share with your group")
    hint(f.abandonBtn, "Abandon the quest (asks first)")
    hint(f.wowheadBtn, "Copy this quest's Wowhead link")
    -- Laid out to the panel's width: five equal buttons.
    local function layoutButtons()
        local n, gap = #f.buttons, 3
        local w = (f:GetWidth() - 12 - gap * (n - 1)) / n
        for i, b in ipairs(f.buttons) do
            b:ClearAllPoints()
            b:SetWidth(w)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6 + (i - 1) * (w + gap), 8)
        end
    end
    layoutButtons()
    f:HookScript("OnSizeChanged", layoutButtons)
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
    -- 2026-11-18: rewards (items with icons and tooltips, then XP and gold).
    f.rewardHead = fs("GameFontNormal")
    f.rewardBox = CreateFrame("Frame", nil, child)
    f.rewardBox:SetSize(1, 1)
    f.rewardBox.buttons = {}
    f.rewardBox.labels = {}
    f.party = fs("GameFontHighlightSmall")
    f.order = { f.title, f.sub, f.objHead, f.objs, f.sumHead, f.summary, f.descHead, f.desc,
        f.rewardHead, f.rewardBox, f.party }

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

---------------------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------------------

local ICON = 22
local ROW_GAP = 3

local function money(copper)
    if copper <= 0 then return nil end
    if _G.GetCoinTextureString then
        local ok, s = pcall(_G.GetCoinTextureString, copper)
        if ok and s then return s end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Item name colour: its quality, except white / grey on the regular
-- parchment, which wouldn't read - those take the panel's text colour.
local function qualityColor(quality, textColor)
    if quality and quality >= 2 then
        local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
        if c then return c.r, c.g, c.b end
    end
    if quality == 0 and not lightBackground() then return 0.62, 0.62, 0.62 end
    return textColor[1], textColor[2], textColor[3]
end

local function rewardButton(box, i)
    local b = box.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, box)
    b:SetHeight(ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT", 0, 0)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, -1)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.name:SetJustifyH("LEFT")
    if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    b:SetScript("OnEnter", function(self)
        if not self.link and not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.link then
            GameTooltip:SetHyperlink(self.link)
        else
            GameTooltip:SetHyperlink("item:" .. self.itemID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click links it in chat, like the game's own reward buttons.
    b:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        end
    end)
    box.buttons[i] = b
    return b
end

local function rewardLabel(box, i)
    local s = box.labels[i]
    if s then return s end
    s = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s:SetJustifyH("LEFT")
    if s.SetWordWrap then s:SetWordWrap(true) end
    box.labels[i] = s
    return s
end

-- Fills the reward box; returns its height (0 when the quest gives nothing).
local function layoutRewards(f, questID, width, textColor)
    local box = f.rewardBox
    for _, b in ipairs(box.buttons) do b:Hide() end
    for _, s in ipairs(box.labels) do s:Hide() end
    box:SetWidth(width)

    local r = Q.Api.GetRewards and Q.Api:GetRewards(questID)
    local xp = r and r.xp or 0
    if xp <= 0 and Q.Catalog then
        -- The client's figure is the one to trust; QuestieDB's only fills a
        -- gap, and never at the level cap (no XP there at all).
        local maxLevel = _G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel() or 60
        local h = Q.Catalog:GetHeader(questID)
        if h and h.xp > 0 and (UnitLevel("player") or 0) < maxLevel then xp = h.xp end
    end

    local y, nb, nl = 0, 0, 0
    local function label(text)
        nl = nl + 1
        local s = rewardLabel(box, nl)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
        s:SetWidth(width)
        s:SetText(text)
        s:SetTextColor(textColor[1], textColor[2], textColor[3])
        s:Show()
        y = y + (s:GetStringHeight() or 12) + ROW_GAP
    end
    local function items(list)
        for _, it in ipairs(list) do
            nb = nb + 1
            local b = rewardButton(box, nb)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
            b:SetWidth(width)
            b.icon:SetTexture(it.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.count:SetText(it.count and it.count > 1 and it.count or "")
            b.name:SetText(it.name or "Loading...")
            b.name:SetTextColor(qualityColor(it.quality, textColor))
            b.link, b.itemID = it.link, it.itemID
            b:Show()
            y = y + ICON + ROW_GAP
        end
    end

    if r and #r.choices > 0 then
        label(#r.choices > 1 and "Choose one of:" or "You will receive:")
        items(r.choices)
    end
    if r and #r.items > 0 then
        label((r and #r.choices > 0) and "You will also receive:" or "You will receive:")
        items(r.items)
    end
    local extras = {}
    if xp > 0 then extras[#extras + 1] = ("%s XP"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) end
    local m = r and money(r.money)
    if m then extras[#extras + 1] = m end
    if #extras > 0 then label(table.concat(extras, "     ")) end

    -- Item names still loading: look again shortly (a few times at most).
    if Details.RewardTriesFor ~= questID then
        Details.RewardTriesFor, Details.RewardTries = questID, 0
    end
    if r and not r.complete and C_Timer and Details.RewardTries < 6 then
        Details.RewardTries = Details.RewardTries + 1
        C_Timer.After(0.5, function() Details:Refresh() end)
    end
    box:SetHeight(math.max(1, y))
    return y
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

    local dark = darkMode()
    if parchment() then
        f.bg:SetTexture("Interface\\QuestFrame\\QuestBG")
        f.bg:SetTexCoord(0, 0.586, 0, 0.65)
        if f.bg.SetDesaturated then f.bg:SetDesaturated(dark) end
        if dark then
            f.bg:SetVertexColor(DARK_TINT, DARK_TINT, DARK_TINT, 1)
        else
            f.bg:SetVertexColor(1, 1, 1, 1)
        end
    else
        f.bg:SetColorTexture(0, 0, 0, 0.88)
        f.bg:SetTexCoord(0, 1, 0, 1)
        if f.bg.SetDesaturated then f.bg:SetDesaturated(false) end
    end
    if dark then
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    elseif parchment() then
        f:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)
    else
        f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end

    -- Buttons: their labels follow the quest's state.
    local routed = Q.Routing and Q.Routing.Target and Q.Routing.Target.kind == "quest"
        and Q.Routing.Target.questID == questID
    f.trackBtn:SetText(Q.State:IsWatched(questID) and "Untrack" or "Track")
    f.routeBtn:SetText(routed and "Unroute" or "Route")
    f.shareBtn:SetEnabled(Q.Api:CanShare(questID))
    for _, b in ipairs(f.buttons) do tintButton(b, dark) end
    local text, head = colors()
    local scale = Q.Core:Opt("DetailsScale") or 1

    local child = f.child
    child:SetScale(scale)
    local width = (f:GetWidth() - PAD - 30) / scale
    child:SetWidth(width)

    f.title:SetText(q.title or "?")
    local sub = {}
    if q.level and q.level > 0 then sub[#sub + 1] = "Level " .. q.level end
    local other = Q.Catalog and Q.Catalog:OtherClassQuest(questID)
    if other then sub[#sub + 1] = ("|cffff6060%s quest|r"):format(other) end
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
            local tag = (not o.finished and Q.Catalog) and Q.Catalog:ObjectiveTag(questID, o.text) or ""
            lines[#lines + 1] = (o.finished and "|cff408040" or "") .. "- " .. o.text .. (o.finished and "|r" or tag)
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

    local rewardHeight = layoutRewards(f, questID, width, text)
    f.rewardHead:SetText(rewardHeight > 0 and "Rewards" or "")

    -- Colours: headings, then body text.
    f.title:SetTextColor(head[1], head[2], head[3])
    for _, s in ipairs({ f.objHead, f.sumHead, f.descHead, f.rewardHead }) do
        s:SetTextColor(head[1], head[2], head[3])
    end
    for _, s in ipairs({ f.sub, f.objs, f.summary, f.desc, f.party }) do
        s:SetTextColor(text[1], text[2], text[3])
    end

    -- Stack them top to bottom.
    local y, gapAfter = 0, { [f.title] = 2, [f.sub] = 10, [f.objHead] = 3, [f.objs] = 10,
        [f.sumHead] = 3, [f.summary] = 10, [f.descHead] = 3, [f.desc] = 10,
        [f.rewardHead] = 4, [f.rewardBox] = 10 }
    for _, s in ipairs(f.order) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        s:SetWidth(width)
        local h
        if s == f.rewardBox then
            h = rewardHeight
            s:SetShown(h > 0)
        else
            h = s:GetText() ~= "" and (s:GetStringHeight() or 0) or 0
        end
        y = y + h + (h > 0 and (gapAfter[s] or 0) or 0)
    end
    child:SetHeight(math.max(1, y))
end

function Details:Start()
    local function refresh() self:Refresh() end
    EventBus:Subscribe("QUEST_STATE_CHANGED", refresh)
    EventBus:Subscribe("QUEST_PARTY_CHANGED", refresh)
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", refresh)
    -- 2026-11-18: the client finishing loading the shown quest's data or
    -- one of its reward items (Api:GetRewards) - draw the rewards then.
    local ev = CreateFrame("Frame")
    Q.Core:SafeRegisterEvent(ev, "QUEST_DATA_LOAD_RESULT")
    Q.Core:SafeRegisterEvent(ev, "GET_ITEM_INFO_RECEIVED")
    Q.Core:SafeRegisterEvent(ev, "GROUP_ROSTER_UPDATE")
    local pending = false
    ev:SetScript("OnEvent", function(_, event, id)
        if not self:IsShowing() then return end
        if event == "QUEST_DATA_LOAD_RESULT" and id ~= self.QuestID then return end
        if pending then return end
        pending = true
        C_Timer.After(0.2, function()
            pending = false
            self.RewardTriesFor = nil      -- a fresh round of retries
            self:Refresh()
        end)
    end)
    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(_, key)
        if key == "ListTextSide" and not self:SidePanelOn() then self:Hide() end
        refresh()
    end)
end
