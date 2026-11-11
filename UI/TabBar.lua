-- Alchemy GPS | UI / TabBar
-- Build-order step 13 (2026-11-11): the Settings window's first tab
-- strip ("General"/"Style"), explicit user request. Ported near-
-- verbatim from Carbonite/UI/TabBar.lua - already small, modern,
-- built on stock Blizzard PanelTabButtonTemplate (no NineSlice/atlas
-- hand-rolling, no AceGUI dependency), so there was nothing to trim.
-- Namespace rename only (Carbonite.UI.TabBar -> AlchemyGPS.UI.TabBar).
--
--   local bar = AlchemyGPS.UI.TabBar:New {
--       parent  = parentFrame,
--       anchor  = { point = "TOPLEFT", x = 0, y = 0 },
--       tabs    = {
--           { id = "general", label = "General" },
--           { id = "style",   label = "Style" },
--       },
--       selected = "general",
--       onSelect = function(bar, id) ... end,
--   }
--
--   bar:Select("style")
--   bar:GetSelected()
--   bar:SetEnabled("style", false)

local AlchemyGPS = _G.AlchemyGPS
local TabBar = {}
AlchemyGPS.UI.TabBar = TabBar

local Methods = {}

function Methods:Select(id, silent)
    for _, tab in ipairs(self._tabs) do
        local active = (tab.id == id)
        if active and tab.button.LeftActive then
            if _G.PanelTemplates_SelectTab then _G.PanelTemplates_SelectTab(tab.button) end
        else
            if _G.PanelTemplates_DeselectTab then _G.PanelTemplates_DeselectTab(tab.button) end
        end
    end
    self._selected = id
    if not silent and self._onSelect then self._onSelect(self, id) end
end

function Methods:GetSelected()
    return self._selected
end

function Methods:SetEnabled(id, enabled)
    for _, tab in ipairs(self._tabs) do
        if tab.id == id then
            if enabled then tab.button:Enable() else tab.button:Disable() end
            return
        end
    end
end

function Methods:Each(fn)
    for _, tab in ipairs(self._tabs) do fn(tab.id, tab.button) end
end

local function makeTab(parent, spec, index)
    local name = parent:GetName() and (parent:GetName() .. "Tab" .. index) or nil
    local t = CreateFrame("Button", name, parent, "PanelTabButtonTemplate")
    if t.SetID then t:SetID(index) end
    if t.SetText then t:SetText(spec.label or spec.id or "") end
    if _G.PanelTemplates_TabResize then
        _G.PanelTemplates_TabResize(t, 0)
    end
    return t
end

function TabBar:New(spec)
    spec = spec or {}
    local parent = spec.parent or UIParent

    local bar = CreateFrame("Frame", spec.name, parent)
    for k, v in pairs(Methods) do bar[k] = v end
    bar:SetHeight(spec.height or 30)
    if spec.width then bar:SetWidth(spec.width) end

    if spec.anchor then
        bar:SetPoint(spec.anchor.point or "TOPLEFT",
            spec.anchor.relativeTo or parent,
            spec.anchor.relPoint or (spec.anchor.point or "TOPLEFT"),
            spec.anchor.x or 0, spec.anchor.y or 0)
    end

    bar._tabs = {}
    bar._onSelect = spec.onSelect

    local prevButton
    for i, tabSpec in ipairs(spec.tabs or {}) do
        local btn = makeTab(bar, tabSpec, i)
        if prevButton then
            btn:SetPoint("LEFT", prevButton, "RIGHT", -16, 0)
        else
            btn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 4, 0)
        end

        btn:SetScript("OnClick", function()
            bar:Select(tabSpec.id)
        end)

        bar._tabs[i] = { id = tabSpec.id, label = tabSpec.label, button = btn }
        prevButton = btn
    end

    if spec.selected then bar:Select(spec.selected, true) end
    return bar
end
