-- Alchemy GPS | Quest / HUDArrow
-- The floating arrow that points at where you're going, with what it is,
-- how far, and roughly how long. 2026-11-17 (user request): it follows,
-- first to last, your corpse (or the dungeon entrance to run back to),
-- the map's goto marker, then QuestRouting's current destination.
--
-- Ported from Carbonite/Modules/HUD/HUDEngine.lua's HUD:Update
-- (:206-371) - the arrow's direction relative to where the player is
-- facing, the "on course" colouring inside 5 degrees, the distance and
-- ETA line and its once-a-second ETA refresh - and from HUDArrow.lua's
-- accessor shape (GetDirectionDegrees/GetDistanceYards/GetTargetName/
-- GetETA). Carbonite's version hangs off its Nx.Window title-line
-- system and a secure click-to-target button; neither exists here, so
-- the frame itself is new: a bare arrow with three text lines under it.
--
-- Rotation uses the texture's own SetRotation, the same choice the map
-- engine made for its player marker and trail arrows (Carbonite rotates
-- by hand-computed texture coordinates, which this project tried once
-- and abandoned). Convention, shared with those: 0 = pointing up,
-- positive = counter-clockwise, and the arrow art points up unrotated.
--   bearing to target = atan2(-dx, -dy)   world X grows east, Y grows south
--   player facing     = GetPlayerFacing() 0 = north, counter-clockwise
--   arrow rotation    = bearing - facing  so "straight ahead" is up
-- The bearing formula is the one DrawAntTrail already uses for the map's
-- goto trail, confirmed pointing the right way in live play.

local AlchemyGPS = _G.AlchemyGPS
local EventBus = AlchemyGPS.Core.EventBus
local Q = AlchemyGPS.Modules.Quest

local HUD = {}
Q.HUD = HUD

local ARROW_SIZE = 48
local TEXT_WIDTH = 240
local TEXT_EVERY = 0.1          -- seconds between caption refreshes
local ETA_EVERY = 10            -- caption refreshes between ETA recalculations
local ON_COURSE_DEGREES = 5

local atan2, deg, floor = math.atan2, math.deg, math.floor

local function engine() return AlchemyGPS.Modules.Map and AlchemyGPS.Modules.Map.MinimapEngine end

-- The corpse, else the goto marker, as a destination shaped like
-- QuestRouting's targets (x, y, cont, name, detail), or nil. One table,
-- reused every frame.
local alt = {}
local function overrideTarget()
    local E = engine()
    if not E then return nil end
    if E.CorpseWX and UnitIsDeadOrGhost("player") then
        alt.kind, alt.x, alt.y, alt.cont = "corpse", E.CorpseWX, E.CorpseWY, E.CorpseCont
        alt.name = E.CorpseLabel or "Your corpse"
        alt.detail = E.CorpseLabel and "Run back in to your corpse" or "Run back to your corpse"
        alt.inside = nil
        return alt
    end
    if E.GotoWX then
        alt.kind, alt.x, alt.y, alt.cont = "goto", E.GotoWX, E.GotoWY, E.GotoCont
        alt.name, alt.detail, alt.inside = "Goto marker", "Right-click the arrow to clear", nil
        return alt
    end
    return nil
end

function HUD:Create()
    if self.Frm then return self.Frm end
    local Core = Q.Core

    -- Only the arrow itself is the frame (and so the only part that can
    -- take the mouse); the captions hang below it without making a
    -- large click-blocking box in the middle of the screen.
    local f = CreateFrame("Frame", "AlchemyGPSQuestArrow", UIParent)
    f:SetSize(ARROW_SIZE, ARROW_SIZE)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:Hide()
    self.Frm = f

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    self.Tex = tex
    self:ApplyStyle()

    local function line(font, anchorTo, gap)
        local fs = f:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOP", anchorTo, "BOTTOM", 0, gap)
        fs:SetWidth(TEXT_WIDTH)
        fs:SetJustifyH("CENTER")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetMaxLines then fs:SetMaxLines(2) end
        return fs
    end
    self.NameText = line("GameFontNormalSmall", f, -2)
    self.DetailText = line("GameFontHighlightSmall", self.NameText, -1)
    self.DistText = line("GameFontHighlightSmall", self.DetailText, -1)

    local anchor = Core:ProfileTable("ArrowAnchor")
    if not anchor.point then
        anchor.point, anchor.relPoint, anchor.x, anchor.y = "TOP", "TOP", 0, -170
    end
    AlchemyGPS.UI.Mixins.Draggable.EnableDragging(f, anchor)
    AlchemyGPS.UI.Mixins.Draggable.RestoreAnchor(f, UIParent)

    f:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        -- Right-click lets go of what the arrow is following: the goto
        -- marker, or a pinned quest route. The corpse can't be let go.
        local t = HUD.Following
        if t and t.kind == "goto" then
            local E = engine()
            if E then E:ClearGoto() end
        elseif not (t and t.kind == "corpse") and Q.Routing then
            Q.Routing:ClearManual()
        end
    end)
    f:SetScript("OnEnter", function(frm)
        GameTooltip:SetOwner(frm, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Navigation arrow")
        GameTooltip:AddLine("Points at your corpse when dead, else the map's goto marker, else your quest.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag to move. Right-click to clear the goto marker or release a pinned route.", 1, 1, 1, true)
        GameTooltip:AddLine("Lock it in place from /gps settings, Quests tab.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:ApplyOptions()
    return f
end

function HUD:ApplyStyle()
    if self.Tex then
        AlchemyGPS.UI.StyleOptions:ApplyIcon(self.Tex, "HUDArrow")
    end
end

function HUD:ApplyOptions()
    local f = self.Frm
    if not f then return end
    local Core = Q.Core
    f:SetScale(Core:Opt("ArrowScale") or 1)
    -- Locked means click-through as well as immovable.
    f:EnableMouse(not Core:Opt("ArrowLocked"))
end

---------------------------------------------------------------------------------------
-- Read-only state, for anything that wants what the arrow is showing
---------------------------------------------------------------------------------------

function HUD:GetDirectionDegrees() return self.DirDegrees or 0 end
function HUD:GetDistanceYards() return self.DistanceYards or 0 end
function HUD:GetTargetName() return self.TargetName or "" end
function HUD:GetETA() return self.ETA or false end

---------------------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------------------

local function formatDistance(yards)
    if yards >= 1000 then
        return ("%.2fk yds"):format(yards / 1000)
    end
    return ("%d yds"):format(floor(yards + .5))
end

function HUD:Update(elapsed)
    local Routing = Q.Routing
    local t = overrideTarget() or (Routing and Routing.Target)
    self.Following = t
    local f = self.Frm
    if not t or not Routing then
        if f and f:IsShown() then f:Hide() end
        self.DistanceYards, self.TargetName, self.ETA = nil, nil, nil
        return
    end

    local px, py, cont = Routing:GetPlayerPos()
    if not px then
        -- Inside an instance (or anywhere else the map can't place the
        -- player): there is no direction to show.
        if f and f:IsShown() then f:Hide() end
        return
    end

    f = f or self:Create()
    if not f:IsShown() then
        f:Show()
        self._textAt = TEXT_EVERY
    end

    local tex = self.Tex
    local far = t.cont ~= cont
    local yards, dirDist = 0, 0

    if far then
        tex:Hide()
    else
        local dx, dy = t.x - px, t.y - py
        yards = t.inside and 0 or (dx * dx + dy * dy) ^ .5 * Routing.YARDS_PER_WORLDUNIT

        -- Don't rotate when essentially on top of the target.
        local rotation = 0
        local facing = GetPlayerFacing and GetPlayerFacing()
        if facing and yards >= 1 then
            rotation = atan2(-dx, -dy) - facing
            local d = deg(rotation) % 360
            dirDist = d <= 180 and d or 360 - d
            self.DirDegrees = d
        else
            self.DirDegrees = 0
        end
        tex:SetRotation(rotation)
        tex:Show()

        if dirDist < ON_COURSE_DEGREES then
            if yards < 1 then
                -- Very close / inside the objective area: faded green.
                tex:SetVertexColor(.2, 1, .2, .6)
                tex:SetBlendMode("BLEND")
            else
                -- Pointed correctly: bright additive blue-white.
                tex:SetVertexColor(.7, .7, 1, 1)
                tex:SetBlendMode("ADD")
            end
        else
            -- Off-axis: warm yellow.
            tex:SetVertexColor(1, 1, .5, .9)
            tex:SetBlendMode("BLEND")
        end
    end

    self.DistanceYards = yards
    self.TargetName = t.name

    -- Reached the goto marker (the map clears it too, but only while its
    -- window is updating).
    if t.kind == "goto" and not far then
        local E = engine()
        if E and yards < (E.GOTO_ARRIVAL_YARDS or 7) then
            E:ClearGoto()
            if E.HideGotoFrames then E:HideGotoFrames() end
            UIErrorsFrame:AddMessage("Goto reached", 1, 1, 1, 1)
            PlaySoundFile(567455)
            return
        end
    end

    self._textAt = (self._textAt or 0) + elapsed
    if self._textAt < TEXT_EVERY then return end
    self._textAt = 0

    self.NameText:SetText(t.name or "")
    self.DetailText:SetText(t.detail or "")

    local str
    if far then
        str = "|cffa0a0a0On another continent|r"
        self.ETA = false
    elseif t.inside then
        str = "|cff66ff66In the objective area|r"
        self.ETA = false
    else
        local col = dirDist < ON_COURSE_DEGREES and "|cffa0a0ff" or ""
        str = col .. formatDistance(yards)

        local speed = Routing.PlyrSpeed or 0
        if speed > .1 then
            self._etaDelay = (self._etaDelay or 0) - 1
            if self._etaDelay <= 0 then
                self._etaDelay = ETA_EVERY
                local eta = yards / speed
                self.ETA = eta
                if eta < 60 then
                    self._etaStr = ("|cffdfffdf %d secs"):format(floor(eta + .5))
                else
                    self._etaStr = ("|cffdfdfdf %.1f mins"):format(eta / 60)
                end
            end
            str = str .. (self._etaStr or "")
        else
            self._etaDelay = 3
            self._etaStr = ""
            self.ETA = false
        end
    end
    self.DistText:SetText(str)
end

function HUD:ApplyShown()
    local driver = self.Driver
    if not driver then return end
    if Q.Core:Opt("ArrowShown") then
        driver:SetScript("OnUpdate", function(_, elapsed)
            self:Update(elapsed)
        end)
    else
        driver:SetScript("OnUpdate", nil)
        if self.Frm then self.Frm:Hide() end
    end
end

function HUD:Start()
    if self.Driver then return end
    -- The arrow frame hides itself when there is nothing to point at,
    -- and a hidden frame's OnUpdate stops - so the update runs on a
    -- separate, always-running driver frame.
    self.Driver = CreateFrame("Frame")
    self:ApplyShown()

    EventBus:Subscribe("QUEST_OPTION_CHANGED", function(_, key)
        if key == "ArrowShown" then
            self:ApplyShown()
        elseif key == "ArrowLocked" or key == "ArrowScale" then
            self:ApplyOptions()
        end
    end)
end
