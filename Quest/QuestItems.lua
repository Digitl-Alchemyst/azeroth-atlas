-- Alchemy GPS | Quest / QuestItems
-- Quest items you have to use (a totem to plant, a horn to blow):
--
--   * a button for each, beside its quest on the tracker, and
--   * one key binding - "use the nearest quest's item" - that always
--     fires the item belonging to whichever tracked quest is closest,
--     so standing where a quest wants its item used and pressing the
--     key uses the right one.
--
-- Which item belongs to a quest comes from the client where it says
-- (GetQuestLogSpecialItemInfo), otherwise from the items QuestieDB
-- lists for the quest (Quest/Data/QuestDBRules.lua's QuestItems),
-- keeping the first one that is in the bags and can be used.
--
-- Using an item is a protected action, so these are secure buttons, and
-- a secure button can't be created, moved, shown, hidden or re-aimed
-- while in combat. Two consequences shape this file:
--
--   * The buttons are children of UIParent placed at screen positions
--     that match the tracker's rows, NOT anchored to the tracker. A
--     frame with a secure button anchored to it becomes protected
--     itself, and the tracker - which re-lays-out its rows constantly -
--     would start throwing "action blocked" errors in every fight.
--   * Nothing here changes during combat. What was wanted is remembered
--     and applied when combat ends; until then the buttons stay as they
--     were, which is still the right item nearly always.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest

local Items = {}
Q.Items = Items

Items.Buttons = {}
Items.Serial = 0            -- bumps when the bags change

local SIZE = 18
local NEAREST_NAME = "AlchemyGPSQuestItemNearest"
local BINDING = "CLICK " .. NEAREST_NAME .. ":LeftButton"

-- Key Bindings menu text (Bindings.xml names the binding itself).
_G.BINDING_HEADER_ALCHEMYGPS = "Alchemy GPS"
_G["BINDING_NAME_" .. BINDING] = "Use the nearest quest's item"

local function locked()
    return InCombatLockdown and InCombatLockdown()
end

---------------------------------------------------------------------------------------
-- Which item
---------------------------------------------------------------------------------------

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function itemCount(itemId)
    return call((_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount, itemId) or 0
end

local function itemUsable(itemId)
    return call((_G.C_Item and _G.C_Item.GetItemSpell) or _G.GetItemSpell, itemId) ~= nil
end

local function itemIcon(itemId)
    return call((_G.C_Item and _G.C_Item.GetItemIconByID) or _G.GetItemIcon, itemId)
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- true / false: whether the current target is in range of the item;
-- nil when there is no target or range doesn't apply to it.
local function itemInRange(itemId)
    if not UnitExists("target") then return nil end
    local fn = (_G.C_Item and _G.C_Item.IsItemInRange) or _G.IsItemInRange
    local inRange = call(fn, itemId, "target")
    if inRange == 1 then return true elseif inRange == 0 then return false end
    if inRange == nil then return nil end
    return inRange and true or false
end

local function itemCooldown(itemId)
    local fn = (_G.C_Container and _G.C_Container.GetItemCooldown) or _G.GetItemCooldown
    return call(fn, itemId)
end

-- The item to use for a quest in the log, or nil.
function Items:GetItem(q)
    local key = (Q.State.Serial or 0) .. ":" .. self.Serial
    if self._cacheKey ~= key then
        self._cacheKey, self._cache = key, {}
    end
    local cached = self._cache[q.questID]
    if cached ~= nil then return cached or nil end

    local found = false
    if _G.GetQuestLogSpecialItemInfo and q.logIndex and q.logIndex > 0 then
        -- link, icon, charges, showItemWhenComplete
        local ok, link, _, _, showWhenComplete = pcall(_G.GetQuestLogSpecialItemInfo, q.logIndex)
        local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id and (not q.ready or showWhenComplete) then found = id end
    end
    if not found and not q.ready and Q.Rules then
        for _, id in ipairs(Q.Rules:GetQuestItems(q.questID) or {}) do
            if itemCount(id) > 0 and itemUsable(id) then
                found = id
                break
            end
        end
    end
    self._cache[q.questID] = found
    return found or nil
end

-- The tracked quest closest to the player that has an item: questID, itemId.
function Items:GetNearest()
    local State, Routing = Q.State, Q.Routing
    if not State or not State.Scanned then return nil end
    local info = (Routing and Routing.QuestInfo) or {}
    local target = Routing and Routing.Target
    local routed = target and target.kind == "quest" and target.questID or nil

    local bestQuest, bestItem, bestDist
    for _, q in ipairs(State:GetWatchedQuests()) do
        local itemId = self:GetItem(q)
        if itemId then
            local entry = info[q.questID]
            -- No known distance sorts last; the routed quest breaks ties.
            local dist = (entry and entry.dist) or math.huge
            if not bestQuest or dist < bestDist or (dist == bestDist and q.questID == routed) then
                bestQuest, bestItem, bestDist = q.questID, itemId, dist
            end
        end
    end
    return bestQuest, bestItem
end

---------------------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------------------

local function buttonOnEnter(btn)
    if not btn.itemId then return end
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. btn.itemId) then
        GameTooltip:SetText("Quest item")
    end
    local q = btn.questID and Q.State:GetQuest(btn.questID)
    if q then GameTooltip:AddLine(q.title, 1, 0.82, 0.2) end
    local key = _G.GetBindingKey and _G.GetBindingKey(BINDING)
    GameTooltip:AddLine(key and ("Nearest quest's item: " .. key)
        or "Bind a key for the nearest quest's item in Key Bindings > Alchemy GPS", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function createButton(name)
    local btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    btn:SetSize(SIZE, SIZE)
    btn:SetFrameStrata("LOW")
    -- Both, as Questie does on this client: which of the two the secure
    -- handler acts on depends on a client setting, and it only acts on one.
    btn:RegisterForClicks("AnyUp", "AnyDown")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.25)

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    btn.count = count

    -- Range dot, top right: red when the target is out of range for the
    -- item, green when in range, hidden with no target (or an item that
    -- isn't used on one). The icon dims red when out of range too, the
    -- way action buttons do.
    -- A text dot, as Questie's tracker draws it.
    local range = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    range:SetPoint("TOPRIGHT", 3, 2)
    range:SetText("\226\151\143")     -- U+25CF BLACK CIRCLE, as UTF-8 bytes
    range:Hide()
    btn.rangeDot = range

    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints()
        btn.cooldown = cooldown
    end

    btn:SetScript("OnEnter", buttonOnEnter)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
    return btn
end

local function aim(btn, itemId, questID)
    if btn.itemId ~= itemId then
        btn:SetAttribute("type", itemId and "item" or nil)
        btn:SetAttribute("item", itemId and ("item:" .. itemId) or nil)
        btn.itemId = itemId
    end
    btn.questID = questID
end

local function refreshLook(btn)
    if not btn.itemId or not btn.icon then return end
    btn.icon:SetTexture(itemIcon(btn.itemId))
    local n = itemCount(btn.itemId)
    btn.count:SetText(n > 1 and n or "")
    if btn.cooldown then
        local start, duration, enable = itemCooldown(btn.itemId)
        if start and duration and duration > 0 and enable ~= 0 then
            btn.cooldown:SetCooldown(start, duration)
        else
            btn.cooldown:Hide()
        end
    end
end

-- Called by the tracker after it lays out: `rows` is
--   { {questID=, y=}, ... }   y = the quest row's offset below `win`'s top
-- or nil to hide every button. Safe to call at any time; in combat it
-- only remembers that it was asked.
function Items:Layout(win, rows)
    self.Wanted = { win = win, rows = rows }
    if locked() then
        self.Pending = true
        return
    end
    self.Pending = false

    local used = 0
    local left, right, top = win and win:GetLeft(), win and win:GetRight(), win and win:GetTop()
    if rows and left and top and Q.Core:Opt("TrackerItemButtons") then
        -- Outside the tracker's left edge, or its right one when the
        -- tracker sits against the left of the screen.
        local onRight = left < SIZE + 6
        for _, entry in ipairs(rows) do
            local q = Q.State:GetQuest(entry.questID)
            local itemId = q and self:GetItem(q)
            if itemId then
                used = used + 1
                local btn = self.Buttons[used]
                if not btn then
                    btn = createButton("AlchemyGPSQuestItem" .. used)
                    self.Buttons[used] = btn
                end
                aim(btn, itemId, entry.questID)
                refreshLook(btn)
                btn:ClearAllPoints()
                if onRight then
                    btn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + 2, top - entry.y)
                else
                    btn:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - 2, top - entry.y)
                end
                btn:Show()
            end
        end
    end
    for n = used + 1, #self.Buttons do
        self.Buttons[n]:Hide()
    end
    self.LaidLeft, self.LaidTop = left, top

    self:AimNearest()
end

-- True when the tracker has moved since the buttons were placed.
function Items:IsStale(win)
    -- In combat nothing can be moved anyway; asking again every frame
    -- would just redraw the tracker for nothing.
    if locked() or not self.Wanted or not self.Wanted.rows then return false end
    return win:GetLeft() ~= self.LaidLeft or win:GetTop() ~= self.LaidTop
end

function Items:AimNearest()
    if locked() then
        self.Pending = true
        return
    end
    local btn = self.Nearest
    if not btn then
        btn = CreateFrame("Button", NEAREST_NAME, UIParent, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        -- Never shown: a key binding clicks it whether it is or not.
        btn:SetScript("PostClick", function(b)
            if b.itemId then return end
            local now = GetTime()
            if (b.toldAt or 0) + 2 < now then
                b.toldAt = now
                Q.Core.Say("%s", "No tracked quest has an item to use right now.")
            end
        end)
        self.Nearest = btn
    end
    local questID, itemId = self:GetNearest()
    aim(btn, itemId, questID)
end

---------------------------------------------------------------------------------------
-- The key
---------------------------------------------------------------------------------------

-- /gps quest key [KEY | none]
function Items:SlashKey(arg)
    local say = function(text) Q.Core.Say("%s", text) end
    arg = (arg or ""):upper():gsub("%s+", "")
    if arg == "" then
        local key = _G.GetBindingKey and _G.GetBindingKey(BINDING)
        say(key and ("Nearest quest item is on " .. key .. ".")
            or "No key set. Use /gps quest key <KEY> (for example F or SHIFT-F), or Key Bindings > Alchemy GPS.")
        return
    end
    if locked() then
        say("Key bindings can't be changed in combat.")
        return
    end
    local old = { _G.GetBindingKey(BINDING) }
    for _, key in ipairs(old) do _G.SetBinding(key) end
    if arg ~= "NONE" then
        if not _G.SetBinding(arg, BINDING) then
            say("\"" .. arg .. "\" isn't a key the game accepts.")
            return
        end
    end
    local save = _G.SaveBindings or _G.AttemptToSaveBindings
    if save and _G.GetCurrentBindingSet then pcall(save, _G.GetCurrentBindingSet()) end
    say(arg == "NONE" and "Nearest quest item: key cleared." or ("Nearest quest item is now on " .. arg .. "."))
end

---------------------------------------------------------------------------------------

-- Range dots, a few times a second while any button is up. Only
-- textures change here, which is allowed in combat.
local RANGE_EVERY = 0.2
function Items:UpdateRange()
    for _, btn in ipairs(self.Buttons) do
        if btn:IsShown() and btn.itemId and btn.rangeDot then
            local inRange = itemInRange(btn.itemId)
            if inRange == nil then
                btn.rangeDot:Hide()
                btn.icon:SetVertexColor(1, 1, 1)
            elseif inRange then
                btn.rangeDot:SetTextColor(0.2, 1, 0.2)
                btn.rangeDot:Show()
                btn.icon:SetVertexColor(1, 1, 1)
            else
                btn.rangeDot:SetTextColor(1, 0.15, 0.15)
                btn.rangeDot:Show()
                btn.icon:SetVertexColor(1, 0.45, 0.45)
            end
        end
    end
end

function Items:Start()
    if self.Frame then return end
    local frame = CreateFrame("Frame")
    self.Frame = frame
    for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED" }) do
        Q.Core:SafeRegisterEvent(frame, event)
    end

    local function refresh()
        self.Queued = false
        -- The tracker lays the buttons out as part of drawing itself;
        -- with it closed there is still the key binding to keep aimed.
        local Tracker = Q.Tracker
        if Tracker and Tracker.Win and Tracker.Win:IsShown() then
            Tracker:Render()
        else
            self:AimNearest()
        end
    end

    local sinceRange = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        sinceRange = sinceRange + elapsed
        if sinceRange >= RANGE_EVERY then
            sinceRange = 0
            self:UpdateRange()
        end
    end)

    frame:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_COOLDOWN" then
            for _, btn in ipairs(self.Buttons) do
                if btn:IsShown() then refreshLook(btn) end
            end
            return
        end
        if event == "BAG_UPDATE" then
            self.Serial = self.Serial + 1
        elseif not self.Pending then
            return      -- combat ended with nothing waiting
        end
        -- Looting fires BAG_UPDATE in bursts.
        if not self.Queued then
            self.Queued = true
            Q.Core:After(0.5, refresh)
        end
    end)

    local function aimSoon() self:AimNearest() end
    EventBus:Subscribe("QUEST_ROUTE_CHANGED", aimSoon)
    EventBus:Subscribe("QUEST_STATE_CHANGED", aimSoon)
end
