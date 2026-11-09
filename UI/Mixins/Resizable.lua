-- Alchemy GPS | UI / Mixins / Resizable
-- Adds bottom-right corner resizing to any Frame. Stores width/height
-- in `dbSize` so the user's resize persists across reloads.
--
-- Ported verbatim (namespace rename only) from AlchemyNavigation's
-- own already-proven UI/Mixins/Resizable.lua. Not used by the
-- Settings window (fixed size), but Window.lua references this
-- module unconditionally at file scope, so it's ported alongside it.

local AlchemyGPS = _G.AlchemyGPS
local Resizable = {}
AlchemyGPS.UI.Mixins = AlchemyGPS.UI.Mixins or {}
AlchemyGPS.UI.Mixins.Resizable = Resizable

function Resizable:EnableResizing(dbSize, minW, minH, maxW, maxH, onResizeStop)
    self.dbSize = dbSize

    self:SetResizable(true)
    if self.SetResizeBounds then
        self:SetResizeBounds(minW or 80, minH or 60, maxW or 4096, maxH or 4096)
    else
        if self.SetMinResize then self:SetMinResize(minW or 80, minH or 60) end
        if self.SetMaxResize then self:SetMaxResize(maxW or 4096, maxH or 4096) end
    end

    local grip = CreateFrame("Button", nil, self)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(self:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        self:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        self:StopMovingOrSizing()
        if self.dbSize then
            self.dbSize.w = self:GetWidth()
            self.dbSize.h = self:GetHeight()
        end
        if onResizeStop then onResizeStop() end
    end)
    self.resizeGrip = grip
end

function Resizable:RestoreSize(fallback)
    local s = self.dbSize or fallback
    if s and s.w and s.h then self:SetSize(s.w, s.h) end
end
