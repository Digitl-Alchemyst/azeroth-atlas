-- Alchemy GPS | UI / Button
-- Ported from Carbonite/Modules/UI/UIEngine.lua's Nx.Button class
-- (lines 4352-5057). This is the real button widget the ported
-- Nx.Window chrome (UI/Window.lua) uses for its Close/Max controls -
-- hit-testing, pressed/hover state, and the atlas/legacy-texture
-- rendering path (UpdateAtlasLook/Update) are all load-bearing and
-- kept verbatim.
--
-- Trims from the real source (both explicitly allowed by the build
-- plan's "delete whole unneeded branches" rule):
--   - TypeData kept to just Close/CloseLock/Lock/Max/MaxOn - the only
--     types Nx.Window's Create/CreateButtons/Lock ever request. The
--     other ~30 entries (Chk/Tab/Scroll/the Map* buttons/etc.) belong
--     to Carbonite UI this addon doesn't have.
--   - OnEnter/OnLeave drop the GameTooltip-on-hover lines (Carbonite's
--     dedicated Nx.TooltipText frame isn't ported - cosmetic only,
--     not a feature this project asked for). The hover-highlight
--     itself (but.Over + :Update()) is unchanged.
--   - EditBox/ScrollBar (the rest of the original file through the
--     start of the Menu system) aren't ported - this addon's window
--     has no search box or scrollbar.

local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS
local L = AlchemyGPS:L()

Nx.Button = Nx.Button or {}
local Button = Nx.Button

Button.TypeData = {
    ["Close"] = {
        Skin = true,
        Up = "ButClose",
        Dn = "ButClose",
        Tip = L["Close/Menu"],
    },
    ["CloseLock"] = {
        Skin = true,
        Up = "ButLock",
        Dn = "ButLock",
        Tip = L["Close/Unlock"],
    },
    ["Lock"] = {
        Skin = true,
        Up = "ButLock",
        Dn = "ButLock",
        Tip = L["Unlock"],
    },
    ["Max"] = {
        Tip = L["Maximize"],
        Skin = true,
        Up = "ButMax",
        Dn = "ButMax",
        VRGBAUp = "1|1|1|1",
    },
    ["MaxOn"] = {
        Tip = L["Restore"],
        Skin = true,
        Up = "ButMax",
        Dn = "ButMax",
        VRGBAUp = ".5|.5|1|1",
    },
}

---------------------------------------------------------------------------------------

function Button:Init()

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    self.OverFrm = f

    f:SetFrameStrata("MEDIUM")
    f:Hide()

    local t = f:CreateTexture()
    t:SetColorTexture(Nx.Util_str2rgba("0.06|0.06|0.250|1"))
    t:SetAllPoints(f)
    t:SetBlendMode("ADD")
    f.texture = t
end

---------------------------------------------------------------------------------------
-- Create a Button
---------------------------------------------------------------------------------------

function Button:Create(parentFrm, typ, text, tip, bx, by, side, width, height, func, user, template)

    parentFrm = parentFrm or UIParent

    local but = {}

    setmetatable(but, self)
    self.__index = self

    but:SetUser(user, func)

    but.Type = self.TypeData[typ]

    assert(not typ or but.Type)

    local fType = template and "Button" or "Frame"
    local fname = text and ("NxBut" .. text)

    local f = CreateFrame(fType, fname, parentFrm, template)
    but.Frm = f
    f.NxBut = but

    but.Tip = tip
    f.NxTip = tip or (typ and self.TypeData[typ].Tip)

    side = side or "TOPLEFT"
    f:SetPoint(side, bx, by)

    f:SetWidth(width)
    f:SetHeight(height)

    f:SetScript("OnMouseDown", self.OnMouseDown)
    f:SetScript("OnMouseUp", self.OnMouseUp)
    f:SetScript("OnEnter", self.OnEnter)
    f:SetScript("OnLeave", self.OnLeave)
    f:EnableMouse(true)

    f:SetScript("OnUpdate", self.OnUpdate)

    local t = f:CreateTexture()
    f.texture = t
    t:SetAllPoints(f)

    f:Show()

    if text then

        local fstr = f:CreateFontString()
        but.FStr = fstr
        fstr:SetFontObject("NxFontS")
        fstr:SetJustifyH("CENTER")
        fstr:SetHeight(height)
        but:SetText(text, 0, 0)
        fstr:Show()
    end

    but:Update()

    if template then    -- Social frame template?

        local reg = { f:GetRegions() }
        for n, o in ipairs(reg) do
            if o:IsObjectType("Texture") and o ~= f.texture then
                o:Hide()
            end
        end
    end

    return but
end

---------------------------------------------------------------------------------------

function Button:SetUser(user, func)
    self.User = user
    self.UserFunc = func
end

function Button:GetType()
    return self.Type
end

function Button:SetType(typ)

    local typeData = typ and self.TypeData[typ]
    self.Frm.NxTip = self.Tip or (typeData and typeData.Tip)
    self.Type = typeData
    self.Frm:EnableMouse(typeData ~= nil)
    return typeData ~= nil
end

function Button:SetId(id)
    self.Id = id
end

function Button:GetPressed()
    return self.Pressed
end

function Button:SetPressed(down)
    self.Pressed = down
    self:Update()
end

function Button:GetState()
    return self.State
end

function Button:SetState(state)
    self.State = state
    self:Update()
end

function Button:SetText(text, x, y)

    local fstr = self.FStr

    if strbyte(text) ~= 124 then        -- |
        text = "|cffffbfaf" .. text
    end

    fstr:SetText(text)

    if x then
        fstr:SetPoint("CENTER", x, y + 1)
    end
end

function Button:SetAlpha(a)
    self.Frm:SetAlpha(a)
end

function Button:SetTexture(tex)
    self.Tx = tex
end

function Button:SetPos(side, x, y)
    self.Frm:SetPoint(side, x, y)
end

function Button:SetSize(w, h)
    self.Frm:SetWidth(w)
    self.Frm:SetHeight(h)
end

---------------------------------------------------------------------------------------

function Button:OnMouseDown(button)

    local this = self
    local but = this.NxBut
    if not but or not but.Type then
        return
    end

    if button == "LeftButton" or button == "MiddleButton" then

        if but.Type.Bool then

            but.Pressed = not but.Pressed

            if but.UserFunc then
                but.UserFunc(but.User, but, but.Id, button)
            end

        elseif but.Type.States then

            but.State = but.State % but.Type.States + 1

            if but.UserFunc then
                but.UserFunc(but.User, but, but.Id, button)
            end

        else
            but.Pressed = true
            but.MouseDownButton = button

        end
    end

    if but.Type.Scroll then

        local x, y = GetCursorPosition()
        but.ScrollingX = x / this:GetEffectiveScale()
        but.ScrollingY = y / this:GetEffectiveScale()
        but.Scrolling = true

        return

    elseif button == "RightButton" then

        if but.UserFunc then
            but.UserFunc(but.User, but, but.Id, button)
        end
    end

    but:Update()
end

---------------------------------------------------------------------------------------

function Button:OnMouseUp(button)

    local this = self
    local but = this.NxBut
    if not but or not but.Type then
        return
    end

    if button == "LeftButton" then

        if not (but.Type.Bool or but.Type.States or but.Type.Scroll) then

            local wasPressed = but.Pressed and but.MouseDownButton == button
            but.Pressed = false
            but.MouseDownButton = nil

            -- Moving or resizing a window can place its close button beneath
            -- the cursor before release. A release without a matching press
            -- must never activate that button and close the entire window.
            if wasPressed and Nx.Util_IsMouseOver(but.Frm) then

                if but.UserFunc then
                    but.UserFunc(but.User, but, but.Id, button)
                end
            end

        elseif but.Type.Scroll then

            but.Pressed = false
        end
    end

    but.Scrolling = false

    but:Update()
end

---------------------------------------------------------------------------------------
-- Handle mouse on button
---------------------------------------------------------------------------------------

function Button:OnEnter(motion)

    local this = self
    local but = this.NxBut

    but.Over = true
    but:Update()
end

function Button:OnLeave(motion)

    local this = self
    local but = this.NxBut

    but.Over = nil
    but:Update()
end

---------------------------------------------------------------------------------------

function Button:OnUpdate(elapsed)

    local this = self
    local but = this.NxBut

    if but.Scrolling then

        local cx, cy = GetCursorPosition()
        cx = cx / this:GetEffectiveScale()
        cy = cy / this:GetEffectiveScale()

        local x = cx - but.ScrollingX
        local y = but.ScrollingY - cy

        if x ~= 0 or y ~= 0 then

            but.ScrollingX = cx
            but.ScrollingY = cy

            if IsShiftKeyDown() then
                x = x * .1
                y = y * .1
            end

            if but.UserFunc then
                but.UserFunc(but.User, but, but.Id, "scroll", x, y)
            end
        end
    end
end

---------------------------------------------------------------------------------------
-- Atlas-based looks: AtlasUp/AtlasDn replace the Up/Dn file textures, DnUV mirrors
-- UpUV, IconUp/IconDn draw an overlay atlas (IconScale of the button size)
---------------------------------------------------------------------------------------

function Button:UpdateAtlasLook(typ, f, tx)

    local pressed = not self.State and self.Pressed
    local baseAtlas, uv, icon, iconCol

    if self.State then
        baseAtlas = nil
    elseif pressed then
        baseAtlas = typ.AtlasDn or typ.AtlasUp
        uv = typ.DnUV
        icon = typ.IconDn or typ.IconUp
        iconCol = typ.IconVRGBADn or typ.IconVRGBAUp
    else
        baseAtlas = typ.AtlasUp
        uv = typ.UpUV
        icon = typ.IconUp
        iconCol = typ.IconVRGBAUp
    end

    if baseAtlas then
        tx:SetAtlas(baseAtlas)
        self.TxCoordSet = true
    elseif uv then
        tx:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
        self.TxCoordSet = true
    elseif self.TxCoordSet then
        tx:SetTexCoord(0, 1, 0, 1)
        self.TxCoordSet = nil
    end

    local it = f.NxIcon
    if icon then
        if not it then
            it = f:CreateTexture(nil, "OVERLAY")
            f.NxIcon = it
        end
        it:SetAtlas(icon)
        local scale = typ.IconScale or .7
        it:ClearAllPoints()
        it:SetPoint("CENTER", f, "CENTER", typ.IconOffX or 0, typ.IconOffY or 0)
        it:SetSize(f:GetWidth() * scale, f:GetHeight() * scale)
        if iconCol then
            it:SetVertexColor(Nx.Util_str2rgba(iconCol))
        else
            it:SetVertexColor(1, 1, 1, 1)
        end
        it:Show()
    elseif it then
        it:Hide()
    end
end

function Button:Update()

    local typ = self.Type
    if not typ then
        return
    end

    local Skin = Nx.Skin

    local f = self.Frm
    local tx = f.texture

    if self.State then

        local stateT = typ[self.State] or typ[1]

        local txName = self.Tx or stateT.Tx or typ.Tx

        if typ.Skin then
            txName = Skin:GetTex(txName)
        else
            if txName then
                if type(txName) == "string" then
                    txName = gsub(txName, "%$", "Interface\\Icons\\")
                else
                    if (strmatch(txName, "|")) then
                        tx:SetColorTexture(Nx.Util_str2rgba(txName))
                    else
                        tx:SetTexture(txName)
                    end
                    txName = nil
                end
            end
        end

        if txName then
            tx:SetTexture(txName)
        else
            local rgb = stateT.RGB
            if rgb then
                tx:SetColorTexture(Nx.Util_str2rgb(rgb))
            end
        end

        if stateT.Alpha then
            tx:SetVertexColor(1, 1, 1, stateT.Alpha)
        elseif stateT.VRGBA then
            tx:SetVertexColor(Nx.Util_str2rgba(stateT.VRGBA))
        end

        local sz = stateT.Size
        if sz then
            f:SetWidth(sz)
            f:SetHeight(sz)
        end

    else

        if self.Pressed then

            local txName = self.Tx or typ.Dn

            if typ.Skin then
                txName = Skin:GetTex(txName)
            else
                if txName then
                    if type(txName) == "string" then
                        txName = gsub(txName, "%$", "Interface\\Icons\\")
                    else
                        if (strmatch(txName, "|")) then
                            tx:SetColorTexture(Nx.Util_str2rgba(txName))
                        else
                            tx:SetTexture(txName)
                        end
                        txName = nil
                    end
                end
            end

            if txName then
                tx:SetTexture(txName)
            else
                local rgb = typ.RGBDn
                if rgb then
                    tx:SetColorTexture(Nx.Util_str2rgb(rgb))
                end
            end

            if typ.AlphaDn then
                tx:SetVertexColor(1, 1, 1, typ.AlphaDn)
            elseif typ.VRGBADn then
                tx:SetVertexColor(Nx.Util_str2rgba(typ.VRGBADn))
            end

            local sz = typ.SizeDn
            if sz then
                f:SetWidth(sz)
                f:SetHeight(sz)
            end

        else

            local txName = self.Tx or typ.Up

            if typ.Skin then
                txName = Skin:GetTex(txName)
            else
                if txName then
                    if type(txName) == "string" then
                        txName = gsub(txName, "%$", "Interface\\Icons\\")
                    else
                        if (strmatch(txName, "|")) then
                            tx:SetColorTexture(Nx.Util_str2rgba(txName))
                        else
                            tx:SetTexture(txName)
                        end
                        txName = nil
                    end
                end
            end

            if txName then
                tx:SetTexture(txName)
                if typ.UpUV then
                    local uv = typ.UpUV
                    tx:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
                end
            else
                local rgb = typ.RGBUp
                if rgb then
                    tx:SetColorTexture(Nx.Util_str2rgb(rgb))
                end
            end

            if typ.AlphaUp then
                tx:SetVertexColor(1, 1, 1, typ.AlphaUp)
            elseif typ.VRGBAUp then
                tx:SetVertexColor(Nx.Util_str2rgba(typ.VRGBAUp))
            end

            local sz = typ.SizeUp
            if sz then
                f:SetWidth(sz)
                f:SetHeight(sz)
            end
            if typ.WidthUp then
                f:SetWidth(typ.WidthUp)
            end
            if typ.HeightUp then
                f:SetHeight(typ.HeightUp)
            end
        end
    end

    self:UpdateAtlasLook(typ, f, tx)

    local of = Nx.Button.OverFrm

    if self.Over then

        of:ClearAllPoints()
        if self.IsListRow and self.NxListInst and self.NxListInst.Frm then
            local listFrm = self.NxListInst.Frm
            local lineH = self.NxListInst.GetLineH and self.NxListInst:GetLineH() or f:GetHeight()
            of:SetPoint("TOPLEFT", listFrm, "LEFT", 0, f:GetTop() and (f:GetTop() - listFrm:GetTop() + lineH * 0.5) or 0)
            of:SetPoint("TOPLEFT", f, "LEFT", -2, lineH * 0.5 - 1)
            of:SetWidth(listFrm:GetWidth() - 4)
            of:SetHeight(lineH)
        else
            of:SetPoint("TOPLEFT", f, -1, 1)
            of:SetWidth(f:GetWidth() + 2)
            of:SetHeight(f:GetHeight() + 2)
        end

        if self.Pressed then
            of.texture:SetColorTexture(Nx.Util_str2rgba(".188|.188|.5|1"))
        elseif self.IsListRow then
            of.texture:SetColorTexture(Nx.Util_str2rgba("0.5|0.5|0.7|0.18"))
        else
            of.texture:SetColorTexture(Nx.Util_str2rgba("0.06|0.06|.250|1"))
        end

        of:SetParent(f)

        of:Show()
        Nx.Button.OverFrmOwn = f

    else
        if Nx.Button.OverFrmOwn == f then
            of:Hide()
        end
    end

    if typ.Dim then
        SetDesaturation(tx, not self.Pressed)
    end
end

Button:Init()
