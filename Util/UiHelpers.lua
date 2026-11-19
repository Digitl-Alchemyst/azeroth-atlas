-- Azeroth Atlas | Util / UiHelpers
-- Ported verbatim from Carbonite/Modules/UI/UIEngine.lua: the small
-- frame-math helpers the ported Nx.Window class's OnUpdate (hover
-- fade, drag-to-screen-edge snap) depends on.
--   Nx.Util_StepValue    -- UIEngine.lua:674
--   Nx.Util_IsMouseOver  -- UIEngine.lua:699
--   Nx.Util_SnapToScreen -- UIEngine.lua:767

local AzerothAtlas = _G.AzerothAtlas
local Nx = AzerothAtlas

---
-- Step a value toward a target by a fixed amount
--
function Nx.Util_StepValue(value, target, step)
    if value < target then
        value = value + step
        if value > target then
            value = target
        end
    elseif value > target then
        value = value - step
        if value < target then
            value = target
        end
    end

    return value
end

---
-- Check if mouse is over a frame
-- @return x, y offsets from bottom-left, or nil if not over
--
function Nx.Util_IsMouseOver(frm)
    if not frm or not frm:IsShown() then
        return nil
    end

    local left = frm:GetLeft()
    local right = frm:GetRight()
    local top = frm:GetTop()
    local bottom = frm:GetBottom()

    if not left or not right or not top or not bottom then
        return nil
    end

    local x, y = GetCursorPosition()
    local scale = frm:GetEffectiveScale()
    if scale == 0 then scale = 1 end

    x = x / scale
    y = y / scale

    if x >= left and x <= right and y >= bottom and y <= top then
        return x - left, y - bottom
    end
end

---
-- Snap frame position to screen edges and action bars
--
function Nx.Util_SnapToScreen(frm)
    if not frm then
        return
    end

    local sw = GetScreenWidth()
    local sh = GetScreenHeight()

    local atPt, relTo, relPt, x, y = frm:GetPoint()
    if not x or not y then
        return
    end

    local sc = frm:GetScale()
    if not sc or sc == 0 then sc = 1 end

    local l = frm:GetLeft()
    local r = frm:GetRight()
    local t = frm:GetTop()
    local b = frm:GetBottom()

    if not l or not r or not t or not b then
        return
    end

    l = l * sc
    r = r * sc
    t = t * sc
    b = b * sc

    local dist = 4  -- Snap distance threshold

    if abs(l - 0) < dist then
        x = x - l / sc
    end

    if abs(r - sw) < dist then
        x = x - (r - sw) / sc
    end

    if MultiBarLeft and MultiBarLeft:IsVisible() then
        local ml = MultiBarLeft:GetLeft()
        if ml and abs(r - ml) < dist then
            x = x - (r - ml) / sc
        end
    end

    if MultiBarRight and MultiBarRight:IsVisible() then
        local ml = MultiBarRight:GetLeft()
        if ml and abs(r - ml) < dist then
            x = x - (r - ml) / sc
        end
    end

    if abs(b - 0) < dist then
        y = y - b / sc
    end

    if abs(t - sh) < dist then
        y = y - (t - sh) / sc
    end

    frm:SetPoint(atPt, x, y)
    return nil
end
