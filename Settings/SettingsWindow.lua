-- Alchemy GPS | Settings / SettingsWindow
-- The settings window: /gps settings. Built on the simplified
-- UI/SmallWindow.lua chrome (AlchemyGPS.UI.Window), not the heavy
-- ported Nx.Window used by the minimap itself - this is a small
-- fixed-size utility panel, not something that needs free-edge
-- resize.
--
-- Two checkboxes + one button, per the build plan:
--   - "Hide Blizzard minimap": the existing native-hide toggle,
--     wired to MinimapWindow's own saved value (the same one
--     /gps minimap hide|show already drives).
--   - "Debug mode": a runtime-only toggle (resets off on relog),
--     wired straight to Core.Logger's level - no saved preference.
--   - "Show Minimap": a one-way button, not a toggle. Opens the
--     placeholder Nx.Window-chrome minimap window; that window only
--     ever closes via its own X, never from here.
--
-- Adapted from AlchemyNavigation/Modules/Settings/SettingsWindow.lua
-- (same structure; the per-cluster button toggles that file already
-- tried and cut don't apply here - this addon never had them).

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Settings = AlchemyGPS.Modules.Settings or {}

local SettingsWindow = {}
AlchemyGPS.Modules.Settings.SettingsWindow = SettingsWindow

local function minimapDB()
    local MinimapWindow = AlchemyGPS:GetModule("MinimapWindow", true)
    return MinimapWindow and MinimapWindow:DB().profile or {}
end

local win
local nextCBID = 0
-- Tracked so Refresh() can re-sync checked-state against the DB -
-- needed because MinimapWindow:ForceNativeHidden() can flip
-- NativeMinimapHidden from outside this window (opening/closing the
-- Live-mode minimap window), and a checkbox only reads get() once, at
-- creation, otherwise.
local checkboxes = {}

local function addCheckbox(parent, y, label, get, set)
    nextCBID = nextCBID + 1
    local cb = CreateFrame("CheckButton", "AlchemyGPSSettingsCB" .. nextCBID, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 4, y)
    cb:SetSize(24, 24)

    local text = _G[cb:GetName() .. "Text"]
    if text then text:SetText(label) end

    cb:SetChecked(get() and true or false)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)

    tinsert(checkboxes, { cb = cb, get = get })
    return cb
end

local function build(content)
    local y = -6

    addCheckbox(content, y, "Hide Blizzard minimap",
        function() return minimapDB().NativeMinimapHidden == true end,
        function(value)
            minimapDB().NativeMinimapHidden = value
            local NativeMinimapHide = AlchemyGPS.Modules.Map.NativeMinimapHide
            if NativeMinimapHide then NativeMinimapHide:SetNativeHidden(value) end
        end)
    y = y - 26

    local Logger = AlchemyGPS.Core.Logger
    addCheckbox(content, y, "Debug mode",
        function() return Logger.minLevel == Logger.LEVEL.DEBUG end,
        function(value) Logger:SetLevel(value and "DEBUG" or "INFO") end)
    y = y - 34

    local showBut = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    showBut:SetSize(120, 22)
    showBut:SetPoint("TOPLEFT", 4, y)
    showBut:SetText("Show Minimap")
    showBut:SetScript("OnClick", function()
        local MinimapWindow = AlchemyGPS:GetModule("MinimapWindow", true)
        if MinimapWindow then MinimapWindow:Open() end
    end)
end

local function create()
    if win then return win end

    win = AlchemyGPS.UI.Window:Create{
        name   = "AlchemyGPSSettingsWindow",
        title  = "Alchemy GPS Settings",
        width  = 270,
        height = 160,
    }

    build(win.content)
    AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(win, UIParent, { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })

    return win
end

function SettingsWindow:Refresh()
    for _, entry in ipairs(checkboxes) do
        entry.cb:SetChecked(entry.get() and true or false)
    end
end

function SettingsWindow:IsShown()
    return win ~= nil and win:IsShown()
end

function SettingsWindow:Open()
    create():Show()
end

function SettingsWindow:Close()
    if win then win:Hide() end
end

function SettingsWindow:Toggle()
    if self:IsShown() then self:Close() else self:Open() end
end

AlchemyGPS.Core.SlashCommands:Register("settings", function()
    SettingsWindow:Toggle()
end, "open the settings window")
