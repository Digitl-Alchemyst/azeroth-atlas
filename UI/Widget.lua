-- Alchemy GPS | UI / Widget
-- Base "create a skinned frame" factory. Trimmed port of
-- Carbonite/UI/Widget.lua: only the Frame factory + backdrop helper
-- Window.lua actually uses. Carbonite's Button/ScrollFrame/EditBox/
-- Slider/CheckButton factories are dropped - nothing in this addon
-- needs them yet, and Carbonite's generic Mixin.Apply composition
-- helper is dropped too, in favor of the plain direct-assignment
-- style the existing UI/Mixins files already use.
--
-- Ported verbatim (namespace rename only) from AlchemyNavigation's
-- own already-proven UI/Widget.lua, per the build plan's porting
-- technique of reusing real working code instead of re-deriving it.

local AlchemyGPS = _G.AlchemyGPS
local Widget = {}
AlchemyGPS.UI = AlchemyGPS.UI or {}
AlchemyGPS.UI.Widget = Widget

-- Wraps SetBackdrop with sensible defaults. On 9.x+ a Frame needs the
-- BackdropTemplate to expose SetBackdrop; CreateFrame below handles
-- that template selection.
local function setCarbBackdrop(self, bgFile, edgeFile, tile, tileSize, edgeSize, insets)
    if not self.SetBackdrop then return end
    self:SetBackdrop({
        bgFile   = bgFile or "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = edgeFile or "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = tile ~= false,
        tileSize = tileSize or 16,
        edgeSize = edgeSize or 16,
        insets   = insets or { left = 4, right = 4, top = 4, bottom = 4 },
    })
end

-- Frame creator. Selects the BackdropTemplate when present so
-- :SetBackdrop is available; older clients have it on every Frame.
function Widget.CreateFrame(parent, name)
    local template = "BackdropTemplate"
    if not _G.BackdropTemplateMixin then template = nil end
    local f = CreateFrame("Frame", name, parent or UIParent, template)
    f.SetCarbBackdrop = setCarbBackdrop
    return f
end
