-- Alchemy GPS | Map/MouseActions.lua
---------------------------------------------------------------------------------------
-- Mouse-button actions you set yourself (2026-11-18, user request, from
-- Carbonite: "Choose what Alt/Ctrl plus left, middle, right or button-4
-- clicks do on the map" - "We want a settings menu where we can assign
-- these settings to keys our selves and are not active until assigned").
--
-- Carbonite: Nx.Map:InitFuncs / CallFunc and the ButL* / ButM* / ButR* /
-- But4* options (MapEngine.lua, Defaults.lua), which come with defaults
-- (Ctrl+left = Goto, middle = show player zone, ...). Here every slot
-- starts as "Nothing" - a click does what it always did until you give
-- it a job in Settings > Map, "Mouse clicks on the map". Plain left-drag
-- (pan) and plain right-click (the menu) stay as they are.
--
-- Saved per profile: profile.MapMouse[slot] = action id.
---------------------------------------------------------------------------------------

local AlchemyGPS = _G.AlchemyGPS
local MouseActions = {}
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}
AlchemyGPS.Modules.Map.MouseActions = MouseActions

local function M() return AlchemyGPS.Modules.Map end

local function bigShown()
    local BigMap = M().BigMap
    return BigMap and BigMap.IsBig and BigMap:IsBig() or false
end

-- The jobs a click can have, in the order the settings list them.
MouseActions.ACTIONS = {
    { id = "none", label = "Nothing" },
    { id = "goto", label = "Set the goto here", run = function(E)
        E:CaptureClick()
        E:SetGotoAtClick()
    end },
    { id = "waypoint", label = "Add a waypoint here", run = function(E)
        local wx, wy = E:CursorWorldPos()
        local zone, zx, zy
        if wx then zone, zx, zy = E:ZoneAtWorld(wx, wy) end
        local W = M().Waypoints
        if zone and W then
            W:Add(zone, zx / 100, zy / 100, { title = "Map waypoint", crazy = false, from = "map" })
        end
    end },
    { id = "cleargoto", label = "Clear the goto", run = function(E) E:ClearGoto() end },
    { id = "menu", label = "Open the map menu", run = function(E)
        E:CaptureClick()
        local menu = M().MapContextMenu
        if menu then menu:Open() end
    end },
    { id = "showplayer", label = "Show where you are", run = function(E) E:ShowPlayer() end },
    { id = "openzone", label = "Open the zone under the mouse (big map)", run = function(E)
        if not bigShown() then return end
        local wx, wy = E:CursorWorldPos()
        local zone = wx and E:ZoneAtWorld(wx, wy)
        if zone then E:BrowseTo("map", zone) end
    end },
    { id = "zoomin", label = "Zoom in", run = function(E) E:MouseWheel(1); E:MouseWheel(1) end },
    { id = "zoomout", label = "Zoom out", run = function(E) E:MouseWheel(-1); E:MouseWheel(-1) end },
    { id = "togglebig", label = "Switch small / big map", run = function()
        local w = M().MinimapWindow
        if w then w:ToggleMapSize() end
    end },
    { id = "questlist", label = "Open the quest list", run = function()
        local w = M().MinimapWindow
        if w then w:ToggleQuestList() end
    end },
}

local byId = {}
for _, a in ipairs(MouseActions.ACTIONS) do byId[a.id] = a end

-- The clicks that can be given a job, in the order the settings list them.
MouseActions.SLOTS = {
    { key = "LeftCtrl",   label = "Ctrl + left click" },
    { key = "LeftAlt",    label = "Alt + left click" },
    { key = "LeftShift",  label = "Shift + left click" },
    { key = "RightCtrl",  label = "Ctrl + right click" },
    { key = "RightAlt",   label = "Alt + right click" },
    { key = "RightShift", label = "Shift + right click" },
    { key = "Middle",     label = "Middle click" },
    { key = "MiddleCtrl", label = "Ctrl + middle click" },
    { key = "MiddleAlt",  label = "Alt + middle click" },
    { key = "Button4",    label = "Button 4" },
    { key = "Button4Ctrl", label = "Ctrl + button 4" },
    { key = "Button5",    label = "Button 5" },
    { key = "Button5Ctrl", label = "Ctrl + button 5" },
}

local BUTTON_NAME = {
    LeftButton = "Left", RightButton = "Right", MiddleButton = "Middle",
    Button4 = "Button4", Button5 = "Button5",
}

local function store()
    local db = AlchemyGPS.db
    if not db then return nil end
    db.profile.MapMouse = db.profile.MapMouse or {}
    return db.profile.MapMouse
end

function MouseActions:Get(slot)
    local s = store()
    return (s and s[slot]) or "none"
end

function MouseActions:Set(slot, id)
    local s = store()
    if s then s[slot] = (id ~= "none") and id or nil end
end

function MouseActions:Label(id)
    local a = byId[id]
    return a and a.label or byId.none.label
end

-- The slot a click falls in: Ctrl beats Alt beats Shift, as Carbonite.
local function slotFor(button)
    local base = BUTTON_NAME[button]
    if not base then return nil end
    if IsControlKeyDown() then return base .. "Ctrl" end
    if IsAltKeyDown() then return base .. "Alt" end
    if IsShiftKeyDown() then return base .. "Shift" end
    if base == "Left" or base == "Right" then return nil end   -- plain: pan / menu
    return base
end

-- Runs the job given to this click, if it has one. True when it did -
-- the map then skips what that click would otherwise do.
function MouseActions:Run(E, button)
    local slot = slotFor(button)
    if not slot then return false end
    local a = byId[self:Get(slot)]
    if not a or not a.run then return false end
    local ok, err = pcall(a.run, E)
    if not ok then AlchemyGPS.Core.Logger:Get("Map"):error("mouse action %s failed: %s", a.id, tostring(err)) end
    return true
end
