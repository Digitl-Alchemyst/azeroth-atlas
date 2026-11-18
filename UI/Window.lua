-- Alchemy GPS | UI / Window
-- Ported from Carbonite/Modules/UI/UIEngine.lua's Nx.Window class
-- (lines 1524-4171) - the REAL legacy window chrome behind
-- Carbonite's undocked big map (free-drag resize from any edge/
-- corner via IsOnWinUI's hit-test feeding real StartSizing/
-- StartMoving, not a toggle between preset sizes), not the
-- simplified Carbonite/UI/Window.lua stand-in. See UI/SmallWindow.lua
-- for that simplified chrome, used by the Settings window instead.
--
-- Per the build plan's porting technique: copied nearly byte-for-
-- byte, aliased via `local Nx = AlchemyGPS` so the `Nx.Whatever`/
-- `self:Whatever` references inside copied bodies work unmodified.
-- The only changes from the real source are whole-function/whole-
-- branch deletions (never a rewrite of kept logic):
--
--   - Init() is a trimmed replacement: Carbonite's real version also
--     builds the right-click context menu (Nx.Menu:Create/AddItem)
--     and a SavedVariable-backed layout-data version/reset check
--     (Nx:GetData("Win")). Neither is ported - the context menu is
--     explicitly optional polish per the plan ("the user didn't ask
--     for it"), and the version/reset check only matters across
--     Carbonite's own version history, not this addon's.
--   - OpenMenu is a no-op stub for the same reason (right-click menu
--     not ported); OnMouseDown/OnMaxBut's own right-click branches
--     call it completely unmodified, they just do nothing now.
--   - OnCloseBut is trimmed to close-only per the plan's explicit
--     anchor note ("wire this to close-only, nothing else") - the
--     real version's else-branch toggles lock state or opens the
--     (unported) menu on any other click.
--   - Deleted whole functions that only existed to serve the unported
--     menu (Menu_OnHideInCombat..Menu_OnTrans - 7 functions) or
--     Carbonite's own slash-command/options layer this addon doesn't
--     have (ConsolePos/ConsoleShow/ConsoleSize/ParseConsole/
--     ResetLayouts/AdjustAll/UpdateCombat/CopyLayoutsCheck/
--     ClrSaveData/GetAttribute/SetAttribute/EnableMenu/Find/
--     FindNoCase). None of these are called by anything kept below.
--   - Deleted CaptureIndependentMinimizePositions/
--     RestoreIndependentMinimizePositions/SetShareMinimizePosition:
--     dead without a caller - nothing here ever calls
--     SetShareMinimizePosition, so self.ShareMinimizePosition is
--     always nil and every kept function's check of it is already a
--     harmless no-op branch.
--   - Deleted ResetBackdrops (the all-windows skin-change sweep,
--     plus its NineSliceUtil/atlas-chrome layering): CreateBorders
--     already applies the one fixed skin's backdrop directly at
--     creation, and this addon has no skin-switcher UI to trigger a
--     live re-skin.
--   - Deleted OnEvent and the window frame's OnMinBut/minimize-button
--     machinery isn't deleted (kept verbatim, see IsSizeMin etc.) but
--     is simply never reached: CreateButtons only wires it when a
--     caller asks for a "miner" button, which this addon never does.
--   - Deleted Nx.FixWin/Nx.InitWins (the post-login deferred-init
--     batch Create() queues every new frame into): this addon's
--     window is only ever created on demand, well after login, so
--     MinimapWindow.lua just calls InitLayoutData + SetLayoutMode(1)
--     directly instead of relying on that batch.
--   - CreateBorders drops the already-dead, already-commented-out
--     per-edge-texture block from the real source (its active code
--     was already just the two SetBackdrop lines kept here).
--
-- Nx.db.profile.Map.Compatibility (read by Adjust/SetLayoutMode,
-- Carbonite's own "don't touch secure frames in combat" safety flag)
-- is provided as a fixed default by Map/MinimapWindow.lua's
-- dbDefaults - see that file.

local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS
local L = AlchemyGPS:L()

Nx.prt = Nx.prt or function(...) AlchemyGPS.Core.Logger:info(...) end

Nx.Window = Nx.Window or {}
local Window = Nx.Window

-- Windows that need initialization after login (Carbonite's own
-- Create() queues every new frame here; see the file header - this
-- addon never drains it, which is harmless, just an unused list).
local NotInitializedWins = {}

-- Compatibility for GetMouseFoci API changes across client versions.
local GetMouseFoci = GetMouseFoci or GetMouseFocus

---------------------------------------------------------------------------------------
-- Initialize window system (trimmed - see file header)
---------------------------------------------------------------------------------------

function Window:Init()

    self.Wins = {}        -- All created windows

    self.BORDERW = 7
    self.BORDERH = 7

    self.SideNames = {
        "LEFT", "RIGHT", "", "TOP", "TOPLEFT", "TOPRIGHT", "",
        "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT"
    }

    self.StrataNames = {
        "LOW", "MEDIUM", "HIGH", "DIALOG",
        ["LOW"] = 1, ["MEDIUM"] = 2, ["HIGH"] = 3, ["DIALOG"] = 4,
    }
end

---------------------------------------------------------------------------------------
-- Set fade values used for next window create
---------------------------------------------------------------------------------------

function Window:SetCreateFade(fadein, fadeout)
    self.CFadeIn = fadein
    self.CFadeOut = fadeout
end

---------------------------------------------------------------------------------------
-- Create a Window
-- ()
-- ret: window table
---------------------------------------------------------------------------------------

function Window:Create(name, minResizeW, minResizeH, secure, titleLines, borderType, hide, noButs)

    local c2rgba = Nx.Util_str2rgba

    -- Real source reads/writes this window's layout (position, size,
    -- lock state, fade) through Nx:GetData("Win")[name], a Carbonite
    -- character-data accessor this addon doesn't have. Backed by
    -- AlchemyGPS.db.profile.WindowLayouts instead (an AceDB profile
    -- table, see Core/SavedVariables.lua's bind()) - confirmed live
    -- 2026-11-09 that drag/resize/lock already worked fine all along
    -- (OnMouseUp already calls RecordLayoutData, :1791-1808) but never
    -- persisted, because `wd` used to be a fresh empty table on every
    -- single Create() call, so `wd[name]` could never find anything
    -- saved by a previous session no matter what wrote into it.
    AlchemyGPS.db = AlchemyGPS.db or {}
    AlchemyGPS.db.profile = AlchemyGPS.db.profile or {}
    AlchemyGPS.db.profile.WindowLayouts = AlchemyGPS.db.profile.WindowLayouts or {}
    local wd = AlchemyGPS.db.profile.WindowLayouts
    local svdata = name and wd[name]

    if not svdata then        -- No data for our name?

        svdata = {}        -- New

        svdata["Hide"] = hide
        svdata["FI"] = self.CFadeIn or 1
        svdata["FO"] = self.CFadeOut or .75

        -- Link the new table back into `wd` so it's actually the same
        -- table AlchemyGPS.db.profile.WindowLayouts[name] holds, not
        -- an orphan local - every later SetLayoutData/RecordLayoutData
        -- call below mutates this same table in place (never
        -- reassigns self.SaveData), so this one link-up is all that's
        -- needed for every future write to reach the real saved file.
        if name then
            wd[name] = svdata
        end
    end

    -- New

    local win = {}

    setmetatable(win, self)
    self.__index = self

    win.SaveData = svdata

    if name then
        assert(self.Wins[win] == nil)
        self.Wins[win] = true

        win.Name = name
    end

    win.Secure = secure        -- Have secure children. Don't move in combat

    win.BorderW = self.BORDERW
    win.BorderH = self.BORDERH

    win.TitleLineH = 10
    win.TitleLines = titleLines or 1
    win.TitleH = win.TitleLines * win.TitleLineH + 2
    win.TopH = win.TitleH + win.BorderH

    win.ButW = 0            -- Top left corner button width

    win.Sizeable = true
    win.Border = true
    if borderType == false then
        win.Sizeable = false
        win.Border = false
    elseif borderType == 1 then
        win.Sizeable = false
    end

    win.MovSizing = false

    win.BackgndAlphaMin = .65
    win.BackgndAlphaDiff = .35    -- Max - min
    win.BackgndFade = .01        -- Current
    win.BackgndFadeTarget = 0    -- Target value
    win.BackgndFadeIn = svdata["FI"]
    win.BackgndFadeOut = svdata["FO"]

    win.ChildFrms = {}

    -- Create window frame

    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    win.Frm = f
    f.NxWin = win

    f:SetResizeBounds(minResizeW or 100, minResizeH or 40)

    f:SetWidth(10)
    f:SetHeight(win.TitleH + 50)

    f:SetPoint("TOPLEFT", 100, -100)
    f:SetMovable(true)
    f:SetResizable(true)
    tinsert(NotInitializedWins, f)
    f:SetScript("OnEvent", self.OnEvent)

    f:SetScript("OnMouseDown", self.OnMouseDown)
    f:SetScript("OnMouseUp", self.OnMouseUp)
    f:SetScript("OnMouseWheel", self.OnMouseWheel)

    f:SetScript("OnUpdate", self.OnUpdate)

    if not win.Border then

        local t = f:CreateTexture()
        t:SetColorTexture(c2rgba(".125|.125|.125|.75"))
        t:SetAllPoints(f)
        f.texture = t
    end

    -- Create title text

    win.TitleFStr = {}

    for n = 1, win.TitleLines do

        local fstr = f:CreateFontString()
        win.TitleFStr[n] = fstr
        fstr:SetFontObject("NxFontS")
        fstr:SetJustifyH("LEFT")
        fstr:SetJustifyV("MIDDLE")
        fstr:SetHeight(win.TitleLineH)
    end

    win:SetTitleXOff(0)

    -- Create GUI elements

    if win.Border then
        win:CreateBorders()
    end

    if not noButs then

        local y = win.Sizeable and -win.BorderH or -3
        local but = Nx.Button:Create(win.Frm, "Close", nil, nil, -win.BorderW, y, "TOPRIGHT", 12, 12, win.OnCloseBut, win)
        win.ButClose = but
        but.Frm:Hide()
        win.ButW = 15
    else
        win.NoButs = true
    end

    -- Init layout (start false)

    win.LayoutMode = false        -- "" = normal, "Max", "Min", "User"

    --

    win:Lock(svdata["Lk"])
    win:Show(not svdata["Hide"])

    -- Reset creation stuff

    self:SetCreateFade()

    return win
end

---------------------------------------------------------------------------------------
-- Create buttons
---------------------------------------------------------------------------------------

function Window:CreateButtons(closer, maxer, miner)

    self.Closer = closer
    self.Maxer = maxer
    self.Miner = miner        -- No buts can be set while min is on

    local x = self.BorderW - 26.5

    if self.Closer then
        self.ButClose.Frm:Show()
    end

    local y = self.Sizeable and -self.BorderH

    if self.Sizeable and self.Maxer then
        self.ButMaxer = Nx.Button:Create(self.Frm, "Max", nil, nil, x, y, "TOPRIGHT", 12, 12, self.OnMaxBut, self)
    end

    if self.Miner then
        self.ButMiner = Nx.Button:Create(self.Frm, "Min", nil, nil, x, y, "TOPRIGHT", 12, 12, self.OnMinBut, self)
    end

    self.ButW = -x - self.BorderW

    self:Lock(self:IsLocked())    -- Force button update
end

---------------------------------------------------------------------------------------
-- Create border frames
---------------------------------------------------------------------------------------

-- 2026-11-18: a window can wear its own look (Map/BigMapThemes.lua puts
-- any theme on the map window, small or big): self.SkinOverride =
-- { Backdrop, BdCol, BgCol }, each optional - what's missing comes from
-- the window skin.
function Window:SkinBackdrop()
    local o = self.SkinOverride
    return (o and o.Backdrop) or Nx.Skin:GetBackdrop()
end

function Window:SkinBorderCol()
    local o = self.SkinOverride
    return (o and o.BdCol) or Nx.Skin:GetBorderCol()
end

function Window:SkinBGCol()
    local o = self.SkinOverride
    if o and o.BgCol then return o.BgCol end
    if not self.Sizeable and self.Border then return Nx.Skin:GetFixedSizeBGCol() end
    return Nx.Skin:GetBGCol()
end

function Window:CreateBorders()
    self.Frm:SetBackdrop(self:SkinBackdrop())
end

function Window:SetBordersFade(fade)

    if self.Border then

        local col = self:SkinBorderCol()
        self.Frm:SetBackdropBorderColor(col[1], col[2], col[3], col[4] * fade)
    end
end

-- Repaints the frame edge and background in the current look (after a
-- skin or theme change). SetBackdrop resets the background colour to
-- white, so the colour is set again with the window's own fade.
function Window:ReSkin()
    self:CreateBorders()
    local fade = self.BackgndFade or 1
    self:SetBordersFade(fade)
    local f = self.Frm
    if f and f.SetBackdropColor then
        local col = self:SkinBGCol()
        local a = fade * (self.BackgndAlphaDiff or 0) + (self.BackgndAlphaMin or 1)
        f:SetBackdropColor(col[1], col[2], col[3], col[4] * a)
    end
end

---------------------------------------------------------------------------------------
-- Attach a child frame
---------------------------------------------------------------------------------------

function Window:Attach(childFrm, posX1, posX2, posY1, posY2, width, height)

    local f = self.Frm

    if not posX1 then
        posX1 = 0
        posX2 = 1
        posY1 = 0
        posY2 = 1
    end

    local child

    for i, ch in ipairs(self.ChildFrms) do
        if ch.Frm == childFrm then
            child = ch
            break
        end
    end

    if not child then

        child = {}
        tinsert(self.ChildFrms, child)
        child.Frm = childFrm
        childFrm:SetParent(f)        -- Triggers frame updates which can call attach again!
    end

    child.PosX1 = posX1
    child.PosX2 = posX2
    child.PosY1 = posY1
    child.PosY2 = posY2

    if width then
        child.ScaleW = width
        child.ScaleH = height
    end

    self:Adjust()
end

---------------------------------------------------------------------------------------
-- Detach a child frame
---------------------------------------------------------------------------------------

function Window:Detach(childFrm)

    Nx.prt(L["Detach %s"], #self.ChildFrms)

    for i, ch in ipairs(self.ChildFrms) do
        if ch.Frm == childFrm then
            tremove(self.ChildFrms, i)
            Nx.prt(L["Detach found %s"], #self.ChildFrms)
            break
        end
    end
end

---------------------------------------------------------------------------------------
-- Adjust title width and child frames to fit our client area
---------------------------------------------------------------------------------------

function Window:Adjust(skipChildren)
    if InCombatLockdown() and Nx.db.profile.Map.Compatibility then
        return
    end
    local f = self.Frm

    local w = f:GetWidth() - self.BorderW * 2
    local h = f:GetHeight() - self.TitleH - self.BorderH * 2

    for _, fstr in ipairs(self.TitleFStr) do
        fstr:SetWidth(w - self.ButW)
    end

    if not skipChildren then

        local x, y

        for n = 1, #self.ChildFrms do

            local child = self.ChildFrms[n]
            local cf = child.Frm

            if cf and not cf:IsProtected() then
                x = child.PosX1
                if x < 0 then
                    x = w + x    -- Offset from right edge
                elseif x <= 1 then
                    x = w * x    -- Percent
                end

                local x2 = child.PosX2
                if x2 < 0 then
                    x2 = w + x2    -- Offset from right edge
                elseif x2 <= 1 then
                    x2 = w * x2    -- Percent
                end

                y = child.PosY1
                if y <= -10000 then
                    y = y + 10000
                elseif y < 0 then
                    y = h + y
                elseif y <= 1 then
                    y = h * y
                end

                local y2 = child.PosY2
                if y2 <= -10000 then
                    y2 = y2 + 10000
                elseif y2 < 0 then
                    y2 = h + y2
                elseif y2 <= 1 then
                    y2 = h * y2
                end

                cf:SetPoint("TOPLEFT", f, "TOPLEFT", x + self.BorderW, -y - self.TopH)

                local childW = x2 - x
                local childH = y2 - y

                if child.ScaleW then

                    local sw = childW / child.ScaleW
                    local sh = childH / child.ScaleH
                    local scale = max(min(sw, sh), .001)
                    cf:SetScale(scale)

                    cf:SetPoint("TOPLEFT", f, "TOPLEFT", (self.BorderW + w * child.PosX1) / scale, (-self.TopH - h * child.PosY1) / scale)

                else

                    local inst = cf.NxInst

                    if inst and inst.SetSize then
                        inst:SetSize(childW, childH)
                    else
                        cf:SetWidth(childW)
                        cf:SetHeight(childH)
                    end
                end

                if cf.NxSetSize then
                    cf:NxSetSize(childW, childH)
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- Show or hide window
---------------------------------------------------------------------------------------

function Window:Show(show)

    local svdata = self.SaveData

    if show ~= false then
        self.Frm:Show()
        self.Frm:Raise()
        self.Frm:Raise()
        svdata["Hide"] = nil
    else
        if self.Frm:IsShown() then        -- Check first to avoid taint errors
            self.Frm:Hide()
        end
        svdata["Hide"] = true
    end
end

---------------------------------------------------------------------------------------
-- Check if shown
---------------------------------------------------------------------------------------

function Window:IsShown()

    local svdata = self.SaveData

    local vis = self.Frm:IsShown()
    if vis == nil then
        vis = false
    end

    return vis, not svdata["Hide"]
end

---------------------------------------------------------------------------------------
-- Check if visible (parent must also be visible)
---------------------------------------------------------------------------------------

function Window:IsVisible()
    return self.Frm:IsVisible()
end

---------------------------------------------------------------------------------------
-- Check if hidden from combat
---------------------------------------------------------------------------------------

function Window:IsCombatHidden()

    if self.SaveData["HideC"] then
        return UnitAffectingCombat("player")
    end
end

---------------------------------------------------------------------------------------
-- Lock or unlock window. Cannot move, resize or scale if locked
---------------------------------------------------------------------------------------
function Window:Lock(lock, fullLockout)

    self.Locked = lock
    self.Frm:EnableMouse(not lock)
    self.Frm:EnableMouseWheel(not lock)

    local svdata = self.SaveData

    svdata["Lk"] = lock or nil

    self:SetBordersFade(lock and 0 or self.BackgndFade)

    if self.ButClose then
        if lock then

            if self.Closer then
                self.ButClose:SetType("CloseLock")
            else
                self.ButClose.Frm:Show()
                self.ButClose:SetType("Lock")
            end
        else

            if self.Closer then
                self.ButClose:SetType("Close")
            else
                self.ButClose.Frm:Hide()
            end
        end

        self.ButClose:Update()
    end

    -- Locking can show the close/lock control. Reapply the minimized contract
    -- so registered windows still expose only their restore switch.
    self:ApplyMinimizedFrameVisibility()

    if fullLockout then
        self.FullLock = lock
    end
end

---------------------------------------------------------------------------------------
-- Get lock status of window
---------------------------------------------------------------------------------------

function Window:IsLocked()
    return self.Locked
end

---------------------------------------------------------------------------------------
-- Set if mouse enabled for window
---------------------------------------------------------------------------------------

function Window:EnableMouse(on)

    self.FullLock = not on

    if self.MovSizing then
        self.OnMouseUp(self.Frm, "")
    end

    if self.ButClose then
        if on then
            self.ButClose.Frm:Show()
        else
            self.ButClose.Frm:Hide()
        end
    end

    if on then
        self:Lock(self.Locked)        -- Restore
    else
        self.Frm:EnableMouse(on)
        self.Frm:EnableMouseWheel(on)
    end

end

---------------------------------------------------------------------------------------
-- Get title text width
---------------------------------------------------------------------------------------

function Window:GetTitleTextWidth()

    local w = 40

    for n = 1, self.TitleLines do

        local fstr = self.TitleFStr[n]
        fstr:SetWidth(0)

        w = max(self.TitleFStr[n]:GetStringWidth(), w)
    end

    return w
end

---------------------------------------------------------------------------------------
-- Set title text line height
---------------------------------------------------------------------------------------

function Window:SetTitleLineH(height)

    self.TitleLineH = height
    self.TitleH = self.TitleLines * self.TitleLineH + 2
    self.TopH = self.TitleH + self.BorderH

    local fname = height <= 10 and "NxFontS" or "NxFontM"

    for n = 1, self.TitleLines do

        local fstr = self.TitleFStr[n]
        fstr:SetFontObject(fname)
        fstr:SetHeight(height)
    end
end

---------------------------------------------------------------------------------------
-- Set the title text x offset (also y. rename!)
---------------------------------------------------------------------------------------

function Window:SetTitleXOff(x, yo)

    yo = yo or 0

    for n = 1, self.TitleLines do

        local fstr = self.TitleFStr[n]
        local y = -self.BorderH - (n - 1) * self.TitleLineH - .4        -- Fudge it so it looks better
        fstr:SetPoint("TOPLEFT", self.BorderW + x, y - yo)
        fstr:SetPoint("TOPRIGHT", self.Frm, "TOPRIGHT", -self.BorderW, y)
    end
end

---------------------------------------------------------------------------------------
-- Set our title text
---------------------------------------------------------------------------------------

function Window:SetTitle(text, line)

    line = line or 1
    if self.TitleFStr[line] then
        self.TitleFStr[line]:SetText(text)
    end
end

---------------------------------------------------------------------------------------
-- Set all title colors
---------------------------------------------------------------------------------------

function Window:SetTitleColors(r, g, b, a)

    for n = 1, self.TitleLines do

        local fstr = self.TitleFStr[n]
        fstr:SetTextColor(r, g, b, a)
    end
end

---------------------------------------------------------------------------------------
-- Set our title text
---------------------------------------------------------------------------------------

function Window:SetTitleJustify(mode, line)

    line = line or 1
    self.TitleFStr[line]:SetJustifyH(mode)
end

---------------------------------------------------------------------------------------
-- Get our background min max alpha
---------------------------------------------------------------------------------------

function Window:GetBGAlpha()

    local m = self.BackgndAlphaMin
    return m, m + self.BackgndAlphaDiff
end

---------------------------------------------------------------------------------------
-- Set our background min max alpha
---------------------------------------------------------------------------------------

function Window:SetBGAlpha(min, max)

    self.BackgndAlphaMin = min
    self.BackgndAlphaDiff = max - min

    self.BackgndFade = self.BackgndFadeTarget + .0001    -- Cause refresh
end

---------------------------------------------------------------------------------------
-- Get our current fade
---------------------------------------------------------------------------------------

function Window:GetFade()
    return self.BackgndFade
end

---------------------------------------------------------------------------------------
-- Set our background color
---------------------------------------------------------------------------------------

function Window:SetBGColor(r, g, b, a)
    if self.Frm.texture then
        self.Frm.texture:SetColorTexture(r, g, b, a or 1)
    end
end

---------------------------------------------------------------------------------------
-- Get win width and height
---------------------------------------------------------------------------------------

function Window:GetClientOffset()
    return self.BorderW, self.TitleH + self.BorderH
end

---------------------------------------------------------------------------------------
-- Set if win is sizeable
---------------------------------------------------------------------------------------

function Window:SetSizeable(on)
    self.Sizeable = on
end

---------------------------------------------------------------------------------------
-- Get win width and height (client size)
---------------------------------------------------------------------------------------

function Window:GetSize()

    return self.Frm:GetWidth() - self.BorderW * 2,
             self.Frm:GetHeight() - self.TitleH + self.BorderH * 2
end

---------------------------------------------------------------------------------------
-- Set win width and height (client size)
---------------------------------------------------------------------------------------

function Window:SetSize(width, height, skipChildren)
    if InCombatLockdown() then
        return
    end
    self.Frm:SetWidth(width + self.BorderW * 2)
    self.Frm:SetHeight(height + self.TitleH + self.BorderH * 2)

    self:Adjust(skipChildren)
end

---------------------------------------------------------------------------------------
-- Set win width and height (win size)
---------------------------------------------------------------------------------------

function Window:SetTotalSize(width, height, skipChildren)

    self.Frm:SetWidth(width)
    self.Frm:SetHeight(height)

    self:Adjust(skipChildren)
    self:RecordLayoutData()
end

---------------------------------------------------------------------------------------
-- Set win pos
---------------------------------------------------------------------------------------

function Window:SetPos(x, y)

    local f = self.Frm
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", x, y)

    self:RecordLayoutData()
end

---------------------------------------------------------------------------------------
-- Offset win pos
---------------------------------------------------------------------------------------

function Window:OffsetPos(xo, yo)

    local f = self.Frm
    local atPt, relTo, relPt, x, y = f:GetPoint()

    f:SetPoint(atPt, relTo, relPt, x + xo, y + yo)

    self:RecordLayoutData()
end

---------------------------------------------------------------------------------------
-- Get size of borders
---------------------------------------------------------------------------------------

function Window:GetBorderSize()
    return self.BorderW, self.BorderH
end

---------------------------------------------------------------------------------------
-- Set size of borders
---------------------------------------------------------------------------------------

function Window:SetBorderSize(w, h)

    self.BorderW = w
    self.BorderH = h
    self.TopH = self.TitleH + h
end

---------------------------------------------------------------------------------------
-- Reset layout to default
-- self = Win
---------------------------------------------------------------------------------------

function Window:ResetLayout()

    local data = self.SaveData

    if data["_X"] then

        for k, v in pairs(data) do

            if k ~= "_X" then
                if strsub(k, -1) == "X" then
                    local mode = strsub(k, 1, #k - 1)

                    self:SetLayoutData(mode, data["_X"], data["_Y"], data["_W"], data["_H"], data["_L"], data["_A"], data["_S"])

                    self:SetMaxSizeDefault()
                end
            end
        end

        self.LayoutMode = false
        data["MinUserPlaced"] = nil
        data["IndependentMinimizePositions"] = nil
        self:SetLayoutMode()
    end

    self:Lock(false)

    if self.Name == "NxMap1" or self.Name == "NxQuestWatch" then
        self.Frm:Show()
        data["Hide"] = nil
    end
end

---------------------------------------------------------------------------------------
-- Set max size to default
-- self = Win
---------------------------------------------------------------------------------------

function Window:SetMaxSizeDefault()

    local sw = GetScreenWidth()
    local sh = GetScreenHeight()
    self:SetLayoutData("Max", sw * .1, sh * .1, sw * .8, sh * .8, 2, "TOPLEFT")
end

---------------------------------------------------------------------------------------
-- Get current layout mode name
-- self = Win
---------------------------------------------------------------------------------------

function Window:GetLayoutMode()
    return self.LayoutMode
end

---------------------------------------------------------------------------------------
-- Copy only the screen anchor shared by normal and minimized layouts
---------------------------------------------------------------------------------------

local function IsLayoutNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local LayoutAnchorFactors = {
    TOPLEFT = { 0, 1 },
    TOP = { .5, 1 },
    TOPRIGHT = { 1, 1 },
    LEFT = { 0, .5 },
    CENTER = { .5, .5 },
    RIGHT = { 1, .5 },
    BOTTOMLEFT = { 0, 0 },
    BOTTOM = { .5, 0 },
    BOTTOMRIGHT = { 1, 0 },
}

function Window:CopyLayoutPosition(sourceMode, targetMode)

    sourceMode = sourceMode or ""
    targetMode = targetMode or ""

    local data = self.SaveData
    local x = data[sourceMode.."X"]
    local y = data[sourceMode.."Y"]

    if x == nil or y == nil then
        return
    end

    local aPt = data[sourceMode.."A"] or "TOPLEFT"
    local factors = LayoutAnchorFactors[aPt]
    local scale = data[sourceMode.."S"] or 1
    local w = data[sourceMode.."W"]
    local h = data[sourceMode.."H"]
    local sw = GetScreenWidth()
    local sh = GetScreenHeight()

    if self.MinimizeToEdge and factors
        and IsLayoutNumber(x) and IsLayoutNumber(y)
        and IsLayoutNumber(w) and IsLayoutNumber(h)
        and IsLayoutNumber(scale) and scale > 0
        and IsLayoutNumber(sw) and sw > 0 and IsLayoutNumber(sh) and sh > 0
        and not (x < 0 and x > -1) and x < 100000
        and not (y < 0 and y > -1) and y < 999999 then

        if w < 0 then
            w = sw * -w
        end
        if h < 0 then
            h = sh * -h
        end

        local left = sw * factors[1] + x * scale - w * scale * factors[1]
        local right = left + w * scale
        local top = sh * factors[2] - y * scale + h * scale * (1 - factors[2])
        local anchor = data["MinimizeAnchor"]

        if sourceMode ~= "Min" or (anchor ~= "TOPLEFT" and anchor ~= "TOPRIGHT") then
            local leftGap = math.max(0, left)
            local rightGap = math.max(0, sw - right)

            if math.min(leftGap, rightGap) <= sw * .1 and leftGap ~= rightGap then
                anchor = leftGap < rightGap and "TOPLEFT" or "TOPRIGHT"
            else
                local button = self.ButMiner and self.ButMiner.Frm
                local point = button and button:GetPoint()
                anchor = type(point) == "string" and string.find(point, "LEFT", 1, true)
                    and "TOPLEFT" or "TOPRIGHT"
            end
            data["MinimizeAnchor"] = anchor
        end

        data[targetMode.."A"] = anchor ~= "TOPLEFT" and anchor or nil
        data[targetMode.."X"] = anchor == "TOPRIGHT" and (right - sw) / scale or left / scale
        data[targetMode.."Y"] = (sh - top) / scale
        data[targetMode.."S"] = data[sourceMode.."S"]

    elseif factors and aPt ~= "TOPLEFT" and IsLayoutNumber(w) and IsLayoutNumber(h)
        and IsLayoutNumber(scale) and scale > 0
        and type(sw) == "number" and type(sh) == "number"
        and not (x < 0 and x > -1) and x < 100000
        and not (y < 0 and y > -1) and y < 999999 then

        if w < 0 then
            w = sw * -w
        end
        if h < 0 then
            h = sh * -h
        end

        local left = sw * factors[1] + x * scale - w * scale * factors[1]
        local top = sh * factors[2] - y * scale + h * scale * (1 - factors[2])

        data[targetMode.."A"] = nil
        data[targetMode.."X"] = left / scale
        data[targetMode.."Y"] = (sh - top) / scale
        data[targetMode.."S"] = data[sourceMode.."S"]
    else
        data[targetMode.."A"] = data[sourceMode.."A"]
        data[targetMode.."X"] = x
        data[targetMode.."Y"] = y
        data[targetMode.."S"] = data[sourceMode.."S"]
    end

    if targetMode == "Min" then
        if not IsLayoutNumber(data["MinW"]) then
            data["MinW"] = 125
        end
        if not IsLayoutNumber(data["MinH"]) then
            data["MinH"] = 40
        end
    end
end

---------------------------------------------------------------------------------------
-- Keep a saved window layout inside the current screen bounds
---------------------------------------------------------------------------------------

function Window:ClampLayoutPositionToScreen(mode, frameW, frameH)

    mode = mode or ""

    local data = self.SaveData
    local x = data[mode.."X"]
    local y = data[mode.."Y"]
    local w = frameW or data[mode.."W"]
    local h = frameH or data[mode.."H"]
    local scale = data[mode.."S"] or 1

    if type(x) ~= "number" or type(y) ~= "number"
        or type(w) ~= "number" or type(h) ~= "number"
        or type(scale) ~= "number" or scale <= 0
        or x ~= x or y ~= y or w ~= w or h ~= h or scale ~= scale then
        return false
    end

    w = math.abs(w)
    h = math.abs(h)
    if w <= 0 or h <= 0 then
        return false
    end

    local sw = GetScreenWidth()
    local sh = GetScreenHeight()
    if type(sw) ~= "number" or type(sh) ~= "number" or sw <= 0 or sh <= 0 then
        return false
    end

    local aPt = data[mode.."A"] or "TOPLEFT"
    local factors = LayoutAnchorFactors[aPt]
    if not factors then
        aPt = "TOPLEFT"
        factors = LayoutAnchorFactors.TOPLEFT
        data[mode.."A"] = nil
    end

    local xFactor = factors[1]
    local yFactor = factors[2]
    local scaledW = w * scale
    local scaledH = h * scale

    local anchorX = sw * xFactor + x * scale
    local anchorY = sh * yFactor - y * scale
    local left = anchorX - scaledW * xFactor
    local bottom = anchorY - scaledH * yFactor

    local targetLeft
    if scaledW <= sw then
        targetLeft = math.max(0, math.min(left, sw - scaledW))
    else
        targetLeft = 0
    end

    local targetBottom
    if scaledH <= sh then
        targetBottom = math.max(0, math.min(bottom, sh - scaledH))
    else
        targetBottom = sh - scaledH
    end

    local dx = targetLeft - left
    local dy = targetBottom - bottom
    if math.abs(dx) < .01 and math.abs(dy) < .01 then
        return false
    end

    data[mode.."X"] = x + dx / scale
    data[mode.."Y"] = y - dy / scale
    return true
end

---------------------------------------------------------------------------------------
-- Register and update controls hidden by the minimized layout
---------------------------------------------------------------------------------------

function Window:SetMinimizedHideFrames(frames)
    self.MinimizedHideFrames = frames
    self:ApplyMinimizedFrameVisibility()
end

function Window:ApplyMinimizedFrameVisibility()

    local frames = self.MinimizedHideFrames
    if not frames then
        return
    end

    if self.LayoutMode == "Min" then

        local visibility = self.MinimizedFrameVisibility
        if not visibility then
            visibility = {}
            self.MinimizedFrameVisibility = visibility

            for _, frame in ipairs(frames) do
                visibility[frame] = frame:IsShown() and true or false
            end
        end

        for _, frame in ipairs(frames) do
            frame:Hide()
        end

    elseif self.MinimizedFrameVisibility then

        local visibility = self.MinimizedFrameVisibility
        self.MinimizedFrameVisibility = nil

        for _, frame in ipairs(frames) do
            if visibility[frame] then
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- Switch our layout mode if different and not maximized
-- self = Win
---------------------------------------------------------------------------------------

function Window:SwitchLayoutMode(mode)

    mode = mode or ""

    if self.LayoutMode ~= mode then

        if self.LayoutMode == "Max" then
            self.LayoutModeNormal = mode        -- Remember for later
        else
            self:SetLayoutMode(mode)
        end
    end
end

---------------------------------------------------------------------------------------
-- Set our layout mode and change to size/position
-- (mode or 1 if first time (login))
-- self = Win
---------------------------------------------------------------------------------------

function Window:SetLayoutMode(mode)
    if InCombatLockdown() and Nx.db.profile.Map.Compatibility then
        return
    end
    local data = self.SaveData

    if mode == 1 then

        mode = data["Mode"]        -- nil, "Min", "Max"

        if mode == "Min" then
            self:SetLayoutMode()
            self:SetMinimize(true)
            return
        end
    end

    if mode == "" then
        mode = nil
    end

    data["Mode"] = mode

    mode = mode or ""

    local f = self.Frm

    local oldMode = self.LayoutMode
    if oldMode then
        self:RecordLayoutData()
    end

    if self.ButMiner then

        if mode == "Min" then
            data["Min"] = true
            self.ButMiner:SetPressed(true)

        else
            data["Min"] = nil
            self.ButMiner:SetPressed(false)
        end
    end

    if self.ButMaxer then

        if mode == "Max" then
            self.ButMaxer:SetType("MaxOn")
        else
            self.ButMaxer:SetType("Max")
        end
        self.ButMaxer:Update()
    end

    self.LayoutMode = mode

    local sw = GetScreenWidth()
    local sh = GetScreenHeight()

    if mode == "Max" and not data["MaxX"] then
        self:SetMaxSizeDefault()
    end

    if self.ShareMinimizePosition then
        local sourceMode = oldMode or ""

        if mode == "Min" and sourceMode ~= "Min" then
            self:CopyLayoutPosition(sourceMode, "Min")
        elseif sourceMode == "Min" and mode ~= "Min" then
            self:CopyLayoutPosition("Min", mode)
        end

        data["MinUserPlaced"] = nil

    elseif mode == "Min" and oldMode ~= "Min" and not data["MinUserPlaced"] then
        local atPt, _, relPt, minX, minY = f:GetPoint()
        if atPt and minX and minY and (not relPt or atPt == relPt) then
            self:SetLayoutData(mode, minX, -minY, 125, 28,
                data[(oldMode or "").."L"], atPt, f:GetScale())
        end
    end

    local x = data[mode.."X"]
    local y = data[mode.."Y"]
    local w = data[mode.."W"]
    local h = data[mode.."H"]

    if not IsLayoutNumber(x) or not IsLayoutNumber(y)
        or not IsLayoutNumber(w) or not IsLayoutNumber(h) then

        if mode == "Min" then
            local atPt, _, relPt, frameX, frameY = f:GetPoint()
            local hasFramePoint = atPt and IsLayoutNumber(frameX)
                and IsLayoutNumber(frameY) and (not relPt or atPt == relPt)

            x = IsLayoutNumber(x) and x
                or (hasFramePoint and frameX or sw * .9)
            y = IsLayoutNumber(y) and y
                or (hasFramePoint and -frameY or sh * .4)
            w = IsLayoutNumber(w) and w or 125
            h = IsLayoutNumber(h) and h or 28

            local attachPt = data[mode.."A"]
            if not attachPt and hasFramePoint then
                attachPt = atPt
            end

            local scale = data[mode.."S"]
            if not IsLayoutNumber(scale) or scale <= 0 then
                scale = f:GetScale()
                if not IsLayoutNumber(scale) or scale <= 0 then
                    scale = 1
                end
            end

            self:SetLayoutData(mode, x, y, w, h,
                data[(oldMode or "").."L"], attachPt, scale)
        else
            x = IsLayoutNumber(x) and x or sw * .4
            y = IsLayoutNumber(y) and y or sh * .4
            w = IsLayoutNumber(w) and w or sw * .2
            h = IsLayoutNumber(h) and h or sh * .2

            self:SetLayoutData(mode, x, y, w, h, false,
                data[mode.."A"], data[mode.."S"])
        end
    end

    if w < 0 then
        w = sw * -w
    end

    if h < 0 then
        h = sh * -h
    end

    if x >= 999999 then                -- Center
        x = (sw - w) * .5

    elseif x >= 300000 then                -- Offset + from screen center
        local s = data[mode.."S"] or 1
        x = (sw * .5 + (x - 300000)) / s

    elseif x >= 200000 then                -- Offset - from screen center
        local s = data[mode.."S"] or 1
        x = (sw * -.5 - (x - 200000)) / s

    elseif x > 100000 then                -- Offset from screen right
        x = sw - x + 100000 - self.BorderW

    elseif x < 0 and x > -1 then            -- % of width
        x = sw * -x
    end

    if y >= 999999 then                -- Center
        y = (sh - h) * .5
    elseif y < 0 and y > -1 then            -- % of height
        y = sh * -y
    end

    self:SetLayoutData(mode, x, y, w, h, false,
        data[mode.."A"], data[mode.."S"])

    if self.KeepMinimizePositionsOnScreen and (mode == "" or mode == "Min") then
        local clampW
        local clampH

        if self.ShareMinimizePosition then
            clampW = data["W"]
            clampH = data["H"]
            if type(clampW) ~= "number" or clampW <= 0 then
                clampW = data[mode.."W"]
            end
            if type(clampH) ~= "number" or clampH <= 0 then
                clampH = data[mode.."H"]
            end
        end

        self:ClampLayoutPositionToScreen(mode, clampW, clampH)

        if self.ShareMinimizePosition then
            self:CopyLayoutPosition(mode, mode == "Min" and "" or "Min")
        end
    else
        local aPt = data[mode.."A"] or "TOPLEFT"

        if aPt == "TOPLEFT" then
            if data[mode.."X"] > sw - 20 then
                data[mode.."X"] = sw - 20
            end
        end
        if aPt == "TOPRIGHT" or aPt == "RIGHT" or aPt == "BOTTOMRIGHT" then
            if data[mode.."X"] > 20 then
                data[mode.."X"] = 20
            end
        end
    end

    local aPt = data[mode.."A"] or "TOPLEFT"

    self:SetFrmStrata(data[mode.."L"])

    f:ClearAllPoints()
    f:SetPoint(aPt, data[mode.."X"], -data[mode.."Y"])
    f:SetWidth(data[mode.."W"])
    f:SetHeight(data[mode.."H"])
    f:SetScale(data[mode.."S"] or 1)
    f:SetAlpha(data[mode.."T"] or 1)

    if mode == "Max" then
        f:Raise()
        f:Raise()
    end

    if mode == "Min" then
        f:SetWidth(125)
        f:SetHeight(28)
    end

    self:Adjust()
    self:ApplyMinimizedFrameVisibility()
end

---------------------------------------------------------------------------------------
-- Set strata
-- self = Win
---------------------------------------------------------------------------------------

function Window:SetFrmStrata(layer)

    local svdata = self.SaveData
    svdata[self.LayoutMode.."L"] = layer

    -- ForceStrata (AlchemyGPS addition, 2026-11-16): a window that must
    -- always sit above other addons' frames (the map) pins its strata
    -- here instead of using the saved per-layout layer.
    self.Frm:SetFrameStrata(self.ForceStrata or self.StrataNames[layer] or "MEDIUM")
    if self.OnStrataChanged then self.OnStrataChanged(self) end
end

---------------------------------------------------------------------------------------
-- Init default data for a layout mode
-- self = Win
---------------------------------------------------------------------------------------

function Window:InitLayoutData(mode, x, y, w, h, layer, scale)

    local data = self.SaveData

    -- w and h are client size
    if w > 0 then
        w = w + self.BorderW
    end
    if h > 0 then
        h = h + self.BorderH + self.TitleH
    end

    local attach

    if scale then

        if x >= 300000 then            -- Offset + from screen center
        elseif x >= 200000 then            -- Offset - from screen center
            attach = "TOPRIGHT"
        end
    end

    if not mode then
        mode = ""
        self:SetLayoutData("_", x, y, w, h, layer, attach, scale)    -- Original position for reset
    end

    if not data[mode.."X"] then
        self:SetLayoutData(mode, x, y, w, h, layer, attach, scale)
    end

    if self.LoginDone then                -- Already logged in?
        self:SetLayoutMode(1)
    end
end

---------------------------------------------------------------------------------------
-- Set data for a layout mode
-- self = Win
---------------------------------------------------------------------------------------

function Window:SetLayoutData(mode, x, y, w, h, layer, attachPt, scale)

    if not Nx.Window.SaveDisabled then

        local data = self.SaveData

        if attachPt == "TOPLEFT" then
            attachPt = nil            -- Don't save default
        end

        data[mode.."A"] = attachPt
        data[mode.."X"] = x
        data[mode.."Y"] = y
        data[mode.."W"] = w
        data[mode.."H"] = h < 0 and h or max(h, 40)
        if layer ~= false then
            data[mode.."L"] = layer
        end
        data[mode.."S"] = scale ~= 1 and scale or nil
    end
end

---------------------------------------------------------------------------------------
-- Record current layout
-- self = Win
---------------------------------------------------------------------------------------

function Window:RecordLayoutData()

    if self.LayoutMode then

        local f = self.Frm
        local atPt, relTo, relPt, x, y = f:GetPoint()
        local scale = f:GetScale()

        -- A frame that's mid-drag can return nil from GetPoint when
        -- StartMoving/StopMovingOrSizing fires on a frame with no
        -- anchor. Bail out - there's nothing useful to record.
        if not (atPt and x and y) then return end

        assert(atPt == relPt)

        if x < 0 and x >= -1 then    -- Neg small numbers used for % of screen W
            x = 0
        end

        y = -y

        if y < 0 and y >= -1 then    -- Neg small numbers used for % of screen H
            y = 0
        end

        local w = f:GetWidth()
        local data = self.SaveData

        if self.LayoutMode == "" then

            if self.Name == "NxMap1" and data["MaxW"] and w >= data["MaxW"] then
                return
            end

        elseif self.LayoutMode == "Max" then

            if self.Name == "NxMap1" and data["W"] and w <= data["W"] then
                return
            end
        end

        local mode = self.LayoutMode
        self:SetLayoutData(mode, x, y, f:GetWidth(), f:GetHeight(), false, atPt, scale)

        if self.KeepMinimizePositionsOnScreen and (mode == "" or mode == "Min") then
            local clampW
            local clampH

            if self.ShareMinimizePosition then
                clampW = data["W"]
                clampH = data["H"]
                if type(clampW) ~= "number" or clampW <= 0 then
                    clampW = data[mode.."W"]
                end
                if type(clampH) ~= "number" or clampH <= 0 then
                    clampH = data[mode.."H"]
                end
            end

            if self:ClampLayoutPositionToScreen(mode, clampW, clampH) then
                f:ClearAllPoints()
                f:SetPoint(data[mode.."A"] or "TOPLEFT",
                    data[mode.."X"], -data[mode.."Y"])
            end
        end

        if self.ShareMinimizePosition and (mode == "" or mode == "Min") then
            self:CopyLayoutPosition(mode, mode == "Min" and "" or "Min")
            self.SaveData["MinUserPlaced"] = nil
        end
    end
end

---------------------------------------------------------------------------------------
-- Set user of the window (for event handlers) and generic callback function
-- (user table, function)
---------------------------------------------------------------------------------------

function Window:SetUser(user, func)

    self.User = user
    self.UserFunc = func
end

---------------------------------------------------------------------------------------
-- Register for hide notify
---------------------------------------------------------------------------------------

function Window:RegisterHide()

    local function func(self)
        self.NxWin:Notify("Hide")
    end

    self.Frm:SetScript("OnHide", func)
end

---------------------------------------------------------------------------------------
-- Notfiy user of the window
-- (name)
---------------------------------------------------------------------------------------

function Window:Notify(name, ...)

    if self.UserFunc then
        self.UserFunc(self.User, name, ...)
    end
end

---------------------------------------------------------------------------------------
-- Toggle window size
---------------------------------------------------------------------------------------

function Window:ToggleSize()

    if self.Sizeable then

        if self.LayoutMode ~= "Max" then

            self.LayoutModeNormal = self.LayoutMode
            self:SetLayoutMode("Max")
            self:Notify("SizeMax")

        else
            self:SetLayoutMode(self.LayoutModeNormal)
            self:Notify("SizeNorm")
        end
    end
end

function Window:OnMinBut(but, id, click)
    self:SetMinimize(but:GetPressed())
    -- SetLayoutMode no-ops in combat with Map.Compatibility on; re-sync the
    -- button to the layout that actually applied, or the stuck press corrupts
    -- the next minimize/restore cycle.
    local isMin = self.LayoutMode == "Min"
    if but:GetPressed() ~= isMin then
        but:SetPressed(isMin)
    end
    self.SaveData["Minimized"] = isMin
end

function Window:ToggleMinimize()
    self:SetMinimize(not self.ButMiner:GetPressed())
end

---------------------------------------------------------------------------------------
-- Toggle window minimize
---------------------------------------------------------------------------------------

function Window:SetMinimize(minOn)

    if self.ButMiner then

        if minOn then

            if self.LayoutMode ~= "Min" then
                self.LayoutModeNormal = self.LayoutMode
            end
            self:SetLayoutMode("Min")
            self:Notify("SizeMin")

        else
            local mode = self.LayoutModeNormal
            if mode == "Min" then
                mode = ""
            end
            self:SetLayoutMode(mode)
            self:Notify("SizeNorm")
        end
    end
end

function Window:IsSizeMax()
    return self.Sizeable and self.LayoutMode == "Max"
end

function Window:IsSizeMin()
    return self.ButMiner and self.ButMiner:GetPressed()
end

---------------------------------------------------------------------------------------
-- Check for moving or sizing
---------------------------------------------------------------------------------------

function Window:IsMovingOrSizing()
    return self.MovSizing
end

---------------------------------------------------------------------------------------
-- Mouse handling
-- self is frame
---------------------------------------------------------------------------------------

function Window:OnMouseDown(button)

    local this = self
    local win = this.NxWin

    local x, y = GetCursorPosition()
    x = x / this:GetEffectiveScale()
    y = y / this:GetEffectiveScale()

    ResetCursor()

    if win.Secure and InCombatLockdown() then
        return
    end

    if button == "LeftButton" then

        local side = win:IsOnWinUI(x, y)

        if win.Sizeable then
            if side > 0 then
                this:StartSizing(win.SideNames[side])
                win.MovSizing = true
            end
        end

        if not win.MovSizing and side == 0 then
            this:StartMoving()
            win.MovSizing = true
        end

        if win.MovSizing then

            SetCursor("INSPECT_CURSOR")
            -- Lift above other windows while dragging - but never DROP a
            -- window whose strata is pinned higher than this (ForceStrata).
            if not win.ForceStrata then
                this:SetFrameStrata("HIGH")
            end
        end

    elseif button == "MiddleButton" then

        win:ToggleSize()

    elseif button == "RightButton" then

        if IsShiftKeyDown() and IsControlKeyDown() then
            win:ResetLayout()
        else
            win:OpenMenu(win.NoButs)
        end

    end
end

---------------------------------------------------------------------------------------
-- Check if xy on window UI elements
-- (x, y)
---------------------------------------------------------------------------------------

function Window:IsOnWinUI(x, y)

    local f = self.Frm
    local top = f:GetTop()
    local bot = f:GetBottom()

    -- Bits set: 1=Left, 2=Right, 3=Top, 4=Bottom

    if self.Sizeable then

        local left = f:GetLeft()
        local rgt = f:GetRight()
        local bw = self.BorderW
        local bh = self.BorderH

        if x >= rgt - bw then

            if y >= top - bh then
                return 6        -- TOPRIGHT
            elseif y <= bot + bh then
                return 10        -- BOTTOMRIGHT
            end

            return 2            -- RIGHT

        elseif x < left + bw then

            if y >= top - bh then
                return 5        -- TOPLEFT
            elseif y <= bot + bh then
                return 9        -- BOTTOMLEFT
            end

            return 1            -- LEFT

        elseif y <= bot + bh then

            return 8            -- BOTTOM

        elseif y >= top - bh then

            return 4            -- TOP
        end
    else
        if y <= bot + self.BorderH then
            return 0            -- Header
        end
    end

    if y >= top - self.TopH then
        return 0                -- Header
    end

    return -1                    -- None
end

---------------------------------------------------------------------------------------
-- Mouse up message. Enable mouse also calls!
-- self = frame
---------------------------------------------------------------------------------------

function Window:OnMouseUp(button)

    local this = self
    local win = this.NxWin

    if win.MovSizing then

        this:StopMovingOrSizing()
        win.MovSizing = false

        if win.Secure and InCombatLockdown() then
            win.DeferredMouseUp = true
        else
            win:SetFrmStrata(win.SaveData[win.LayoutMode.."L"])
            this:Raise()
        end

        win:RecordLayoutData()

        if win.LayoutMode == "Min" and not win.ShareMinimizePosition then
            win.SaveData["MinUserPlaced"] = true
        end
    end

    ResetCursor()

    win:Adjust()
end

---------------------------------------------------------------------------------------

function Window:OnMouseWheel(value)

    if not IsShiftKeyDown() then
        return
    end

    if not (IsControlKeyDown() or IsAltKeyDown()) then
        return
    end

    local this = self
    local win = this.NxWin
    local f = win.Frm

    value = value > 0 and 1 or -1

    local cx, cy = GetCursorPosition()
    cx = cx / UIParent:GetEffectiveScale()
    cy = GetScreenHeight() - cy / UIParent:GetEffectiveScale()

    local s = f:GetScale()
    local top = GetScreenHeight() - f:GetTop() * s
    local left = f:GetLeft() * s

    local news = max(s + value * .025, .5)

    if IsAltKeyDown() then
        news = 1
    end

    local x = ((left - cx) * news / s + cx) / news
    local y = ((top - cy) * news / s + cy) / news

    f:SetScale(news)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", x, -y)

    win:Adjust()
    win:RecordLayoutData()
end

---------------------------------------------------------------------------------------
-- Win update
-- self = frame
---------------------------------------------------------------------------------------

function Window:OnUpdate(elapsed)

    local this = self
    local win = this.NxWin

    local secureOk = not (win.Secure and InCombatLockdown())

    if win.DeferredMouseUp and secureOk then
        win.DeferredMouseUp = nil
        win:SetFrmStrata(win.SaveData[win.LayoutMode.."L"])
        this:Raise()
    end

    if win.MovSizing and secureOk then
        if IsAltKeyDown() then
            Nx.Util_SnapToScreen(this)
        end
    end

    if win.CursorIsSet then
        win.CursorIsSet = false
        ResetCursor()
    end

    local x = not win.FullLock and Nx.Util_IsMouseOver(this)

    if x then
        if GetMouseFoci() == this then

            local x, y = GetCursorPosition()
            x = x / this:GetEffectiveScale()
            y = y / this:GetEffectiveScale()

            local side = win:IsOnWinUI(x, y)

            if side == 0 then
                SetCursor("ITEM_CURSOR")
                win.CursorIsSet = true

            elseif side > 0 then
                SetCursor("INTERACT_CURSOR")
                win.CursorIsSet = true
            end
        end
    end

    if (x or win.Sizing) and secureOk then

        win:Adjust()
        win.BackgndFadeTarget = win.BackgndFadeIn
    else

        win.BackgndFadeTarget = win.BackgndFadeOut
    end

    local fade = Nx.Util_StepValue(win.BackgndFade, win.BackgndFadeTarget, elapsed * 2)

    if fade ~= win.BackgndFade then

        if win.UserUpdateFade then
            win.UserUpdateFade(win.User, fade)
        end

        win.BackgndFade = fade

        local a = fade * win.BackgndAlphaDiff + win.BackgndAlphaMin
        if this.texture then
            this.texture:SetVertexColor(1, 1, 1, a)
        else

            local col = win:SkinBGCol()

            this:SetBackdropColor(col[1], col[2], col[3], col[4] * a)
        end

        if not win.Locked then
            win:SetBordersFade(fade)
        end

        if win.ButClose then
            win.ButClose.Frm:SetAlpha(fade * .9 + .1)
        end
        if win.ButMaxer then
            win.ButMaxer.Frm:SetAlpha(fade * .9 + .1)
        end
        if win.ButMiner then
            win.ButMiner.Frm:SetAlpha(fade * .9 + .1)
        end

        for n = 1, #win.ChildFrms do

            local child = win.ChildFrms[n]
            local cf = child.Frm

            local inst = cf.NxInst

            if inst and inst.SetFade then
                inst:SetFade(fade)
            else
                if cf.texture then
                    cf.texture:SetVertexColor(1, 1, 1, fade * .7 + .3)
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- The X - close only, nothing else (trimmed per the build plan; the
-- real source's else-branch toggles lock state or opens the unported
-- right-click menu on any other click).
---------------------------------------------------------------------------------------

function Window:OnCloseBut(but, id, click)

    if click == "LeftButton" and self.Closer then

        self:Show(false)
        self:RecordLayoutData()
        self:Notify("Close")
    end
end

function Window:OnMaxBut(but, id, click)

    if click == "LeftButton" then
        self:ToggleSize()
    else
        self:OpenMenu()
    end
end

-- Right-click context menu isn't ported (optional polish, not
-- required for v1 - see file header). Call sites (OnMouseDown's
-- right-click branch, OnMaxBut's non-left-click branch) are
-- unmodified; this just makes them no-ops.
function Window:OpenMenu(noLock)
end

-- No SavedVariable dependency, same as Skin/Button - init immediately
-- at file load rather than waiting for a lifecycle event. Missing
-- this call left self.Wins nil, breaking the very first Create().
Window:Init()
