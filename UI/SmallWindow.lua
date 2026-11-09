-- Alchemy GPS | UI / SmallWindow
-- A Window is a Frame with: title bar, close button, draggable
-- mixin, optional resizable mixin, ESC-to-close, and a content-area
-- child frame that holds the body. Ported from Carbonite/UI/Window.lua
-- (the simplified chrome, not the big legacy Nx.Window class in
-- UI/Window.lua) via AlchemyNavigation's own already-proven copy.
-- Named SmallWindow.lua, not Window.lua, only to avoid a filename
-- collision with this addon's other UI/Window.lua - the Lua table
-- this file creates is AlchemyGPS.UI.Window, matching
-- AlchemyNavigation.UI.Window exactly; there's no namespace
-- collision with the big Nx.Window (= AlchemyGPS.Window) class.
--
-- Used by the Settings window only (Settings/SettingsWindow.lua) -
-- the minimap window itself uses the heavier Nx.Window chrome for
-- genuine free-edge resize, since that's the one actual behavior
-- this whole addon exists to port faithfully.

local AlchemyGPS = _G.AlchemyGPS
local Widget = AlchemyGPS.UI.Widget
local Draggable = AlchemyGPS.UI.Mixins.Draggable
local Resizable = AlchemyGPS.UI.Mixins.Resizable

local Window = {}
AlchemyGPS.UI.Window = Window

local Methods = {}

function Methods:SetTitle(text)
    self.titleText:SetText(text or "")
end

function Methods:GetContent()
    return self.content
end

-- Builds a new window. `spec` keys:
--   name      string  Global frame name (optional but recommended -
--                      required for ESC-to-close via UISpecialFrames).
--   title     string  Title-bar text.
--   width     number  Default width.
--   height    number  Default height.
--   parent    frame   Parent frame (defaults to UIParent).
--   dbAnchor  table   Anchor persistence target (Draggable mixin).
--   dbSize    table   Size persistence target (Resizable mixin).
--   resizable bool    Enable corner resize.
--   minWidth / minHeight / maxWidth / maxHeight  number  Resize bounds.
--   onResizeStop function  Called once when a resize drag ends.
--   strata    string  Frame strata.
function Window:Create(spec)
    spec = spec or {}
    local f = Widget.CreateFrame(spec.parent or UIParent, spec.name)
    for k, v in pairs(Methods) do f[k] = v end

    f:SetSize(spec.width or 400, spec.height or 300)
    f:SetFrameStrata(spec.strata or "MEDIUM")
    f:SetCarbBackdrop()
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Title bar
    local titleBar = f:CreateTexture(nil, "ARTWORK")
    titleBar:SetColorTexture(0, 0, 0, 0.6)
    titleBar:SetPoint("TOPLEFT", 6, -6)
    titleBar:SetPoint("TOPRIGHT", -6, -6)
    titleBar:SetHeight(20)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
    title:SetText(spec.title or "")
    f.titleText = title

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Content frame. Insets here are "the edges" - the container
    -- border/title-bar margin that stays visible around the content
    -- and is what you drag to move the window. The content frame
    -- itself always fills whatever's left automatically, because it's
    -- anchored by these fixed insets rather than an explicit size -
    -- resizing the container never needs separate logic to resize it.
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     8,  -28)
    content:SetPoint("BOTTOMRIGHT", -8,  8)
    f.content = content

    Draggable.EnableDragging(f, spec.dbAnchor)
    if spec.resizable then
        Resizable.EnableResizing(f, spec.dbSize, spec.minWidth, spec.minHeight, spec.maxWidth, spec.maxHeight, spec.onResizeStop)
    end

    -- ESC support: register so the default UISpecialFrames stack
    -- closes us, same as every other Blizzard panel.
    if spec.name then
        tinsert(UISpecialFrames, spec.name)
    end

    return f
end
