-- Azeroth Atlas | Map/CombatState.lua
---------------------------------------------------------------------------------------
-- The map in combat (2026-11-18, user request, from Carbonite's "Hide
-- the map in combat"): "control with a setting, currently in combat we
-- cannot open or close either map window we want to be able to close
-- the big map or other windows in combat or reopen them but auto close
-- going to mini map mode when combat starts and closing the quest list
-- add another setting to let us remember the state before combat and
-- return to it when exiting combat".
--
--   * The map and quest windows now open, close and switch small / big
--     in combat too: none of them hold protected frames, so the window
--     code's "not in combat" guard (Carbonite's Map.Compatibility, kept
--     for windows with protected children) no longer applies to them
--     (UI/Window.lua).
--   * When combat starts: the big map drops to the small map
--     (CombatShrinkMap) and the quest list closes (CombatCloseQuestList).
--   * When it ends: both go back the way they were before the fight
--     (CombatRestore) - big map, quest list and whether it was docked.
--     Something you open or close yourself during the fight wins: only
--     what this file changed is put back.
-- Settings > Map, "In combat". All three on by default.
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
local CombatState = {}
AzerothAtlas.Modules.Map = AzerothAtlas.Modules.Map or {}
AzerothAtlas.Modules.Map.CombatState = CombatState

local function opt(key)
    local db = AzerothAtlas.db
    return not db or db.profile[key] ~= false
end

local function mapWin()
    local w = AzerothAtlas.Modules.Map.MinimapWindow
    return w, w and w.Win
end

local function questList()
    local Q = AzerothAtlas.Modules.Quest
    return Q and Q.List
end

local function mapIsBig()
    local _, win = mapWin()
    return win ~= nil and win:IsShown() and win.IsSizeMax ~= nil and win:IsSizeMax()
end

local function listShown()
    local List = questList()
    return List ~= nil and List.Win ~= nil and List.Win:IsShown()
end

function CombatState:OnCombatStart()
    local changed = {}
    local List = questList()
    local docked = List and List.IsDocked and List:IsDocked() or false

    if opt("CombatCloseQuestList") and listShown() then
        if docked then
            local BigMap = AzerothAtlas.Modules.Map.BigMap
            if BigMap then BigMap:CloseDockedList() end
        else
            List.Win:Hide()
        end
        changed.list = docked and "docked" or "free"
    end
    if opt("CombatShrinkMap") and mapIsBig() then
        local _, win = mapWin()
        win:ToggleSize()
        changed.big = true
    end
    self.Changed = changed
end

function CombatState:OnCombatEnd()
    local changed = self.Changed
    self.Changed = nil
    if not changed or not opt("CombatRestore") then return end
    local w, win = mapWin()
    -- Back to big - unless the map was closed (or made big again) since.
    if changed.big and win and win:IsShown() and not mapIsBig() then
        win:ToggleSize()
    end
    if changed.list and not listShown() then
        local List = questList()
        if changed.list == "docked" then
            local BigMap = AzerothAtlas.Modules.Map.BigMap
            if BigMap and mapIsBig() then BigMap:ToggleQuests() end
        elseif List then
            List:Toggle()
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    local ok, err
    if event == "PLAYER_REGEN_DISABLED" then
        ok, err = pcall(CombatState.OnCombatStart, CombatState)
    else
        ok, err = pcall(CombatState.OnCombatEnd, CombatState)
    end
    if not ok then AzerothAtlas.Core.Logger:Get("Map"):error("combat map state: %s", tostring(err)) end
end)
