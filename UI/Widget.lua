-- Alchemy GPS | UI / Widget
-- Base "create a skinned frame" factory. Trimmed port of
-- Carbonite/UI/Widget.lua: only the Frame factory + backdrop helper
-- Window.lua actually uses. Carbonite's Button/EditBox/Slider/
-- CheckButton factories are still dropped - nothing in this addon
-- needs them yet, and Carbonite's generic Mixin.Apply composition
-- helper is dropped too, in favor of the plain direct-assignment
-- style the existing UI/Mixins files already use.
--
-- Build-order step 13, 2026-11-11: CreateScrollFrame added back
-- (Carbonite/UI/Widget.lua:62) - the Style tab's category list is
-- the first thing in this addon that actually needs one.
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

-- Stock Blizzard scroll chrome (scrollbar + up/down buttons) wrapping
-- a single child frame (`sf.ScrollChild`) that holds the actual
-- content and must be sized explicitly by the caller (its height is
-- what determines how far the frame can scroll).
function Widget.CreateScrollFrame(parent, name)
    local sf = CreateFrame("ScrollFrame", name, parent or UIParent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    sf:SetScrollChild(child)
    sf.ScrollChild = child
    return sf
end
