-- Azeroth Atlas | Quest / HUDArrow
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

local AzerothAtlas = _G.AzerothAtlas
local EventBus = AzerothAtlas.Core.EventBus
local Q = AzerothAtlas.Modules.Quest

local HUD = {}
Q.HUD = HUD

local ARROW_SIZE = 48
local TEXT_WIDTH = 240
local TEXT_EVERY = 0.1          -- seconds between caption refreshes
local ETA_EVERY = 10            -- caption refreshes between ETA recalculations
local ON_COURSE_DEGREES = 5

local atan2, deg, floor = math.atan2, math.deg, math.floor

local function engine() return AzerothAtlas.Modules.Map and AzerothAtlas.Modules.Map.MinimapEngine end
local function f_shown(f) return f ~= nil and f:IsShown() end

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
    -- 2026-11-18 (user request, from Carbonite): on a flight, where it
    -- lands (Map/Travel.lua).
    local Travel = AzerothAtlas.Modules.Map and AzerothAtlas.Modules.Map.Travel
    local flight = Travel and UnitOnTaxi("player") and Travel:FlightTarget()
    if flight then return flight end
    -- 2026-11-18 (user request, from Carbonite): a player you're
    -- tracking (right-click their dot on the map - PlayerBlips.lua).
    local player = E.TrackedPlayerTarget and E:TrackedPlayerTarget()
    if player then return player end
    if E.GotoWX then
        alt.kind, alt.x, alt.y, alt.cont = "goto", E.GotoWX, E.GotoWY, E.GotoCont
        -- 2026-11-18: a waypoint's own name (/way, TomTom - Map/Waypoints.lua).
        local Waypoints = AzerothAtlas.Modules.Map and AzerothAtlas.Modules.Map.Waypoints
        local more = Waypoints and #Waypoints.List - (E.GotoUid and 1 or 0) or 0
        alt.name = E.GotoName or "Goto marker"
        alt.detail = more > 0 and ("Right-click the arrow to clear - %d more waypoint%s"):format(more, more == 1 and "" or "s")
            or "Right-click the arrow to clear"
        alt.inside = nil
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
    local f = CreateFrame("Frame", "AzerothAtlasQuestArrow", UIParent)
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
    AzerothAtlas.UI.Mixins.Draggable.EnableDragging(f, anchor)
    AzerothAtlas.UI.Mixins.Draggable.RestoreAnchor(f, UIParent)

    f:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        HUD:OnRightClick()
    end)
    f:SetScript("OnEnter", function(frm) HUD:ShowTooltip(frm) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:ApplyOptions()
    return f
end

function HUD:OnRightClick()
    -- Right-click lets go of what the arrow is following: the goto
    -- marker, or a pinned quest route. The corpse can't be let go.
    local t = HUD.Following
    if t and t.kind == "player" then
        local E = engine()
        if E then E:StopTrackPlayer() end
    elseif t and t.kind == "goto" then
        local E = engine()
        if E then E:ClearGoto() end
    elseif not (t and (t.kind == "corpse" or t.kind == "flight")) and Q.Routing then
        Q.Routing:ClearManual()
    end
end

function HUD:ShowTooltip(frm)
    GameTooltip:SetOwner(frm, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Navigation arrow")
    GameTooltip:AddLine("Points at your corpse when dead, where your flight lands while flying, else the map's goto marker, else your quest - by flight path or boat when that's quicker.", 1, 1, 1, true)
    GameTooltip:AddLine("Drag to move. Right-click to clear the goto marker or release a pinned route.", 1, 1, 1, true)
    if self.TargetWho then
        GameTooltip:AddLine("Click: target " .. self.TargetWho, 0.4, 0.8, 1, true)
    end
    GameTooltip:AddLine("Lock it in place from /aatlas settings, Quests tab.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

---------------------------------------------------------------------------------------
-- Click-to-target (2026-11-18, user request, from Carbonite's HUD
-- "target button", Track.TBut): click the arrow to target who you're
-- heading to - a tracked group member (by unit), else the name of the
-- tracked player, the quest's turn-in NPC or the objective's mob or
-- object (a /targetexact macro). Targeting needs a secure button, which
-- can't be moved, shown or changed in combat: it sits over the arrow,
-- set up between fights, and keeps its last target through a fight.
-- Drag, right-click and the tooltip pass through to the arrow.
-- Option: Quests tab, "Click the arrow to target..." (ArrowTargetButton).
---------------------------------------------------------------------------------------

function HUD:CreateTargetButton()
    if self.TargetBtn then return self.TargetBtn end
    local f = self.Frm
    local b = CreateFrame("Button", "AzerothAtlasQuestArrowTarget", UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("LOW")
    b:SetFrameLevel(f:GetFrameLevel() + 5)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("type1", "macro")
    b:HookScript("OnClick", function(_, button, down)
        if button == "RightButton" and not down then HUD:OnRightClick() end
    end)
    b:SetScript("OnDragStart", function()
        if not Q.Core:Opt("ArrowLocked") and f:IsMovable() then f:StartMoving() end
    end)
    b:SetScript("OnDragStop", function()
        local stop = f:GetScript("OnDragStop")
        if stop then stop(f) end
        HUD:PlaceTargetButton()
    end)
    b:SetScript("OnEnter", function(btn) HUD:ShowTooltip(btn) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.TargetBtn = b
    return b
end

function HUD:PlaceTargetButton()
    local b, f = self.TargetBtn, self.Frm
    if not b or not f or InCombatLockdown() then return end
    local cx, cy = f:GetCenter()
    if not cx then return end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * s, cy * s)
    b:SetSize(f:GetWidth() * s, f:GetHeight() * s)
end

-- Out of combat: point the button at t (or hide it).
function HUD:UpdateTargetButton(t)
    if InCombatLockdown() then return end
    local want = t and f_shown(self.Frm) and Q.Core:Opt("ArrowTargetButton") and not Q.Core:Opt("ArrowLocked")
        and (t.unit or t.npc)
    local b = self.TargetBtn
    if not want then
        self.TargetWho = nil
        if b and b:IsShown() then b:Hide() end
        return
    end
    b = b or self:CreateTargetButton()
    local key = (t.unit or "") .. "|" .. (t.npc or "")
    if b.key ~= key then
        b.key = key
        if t.unit then
            b:SetAttribute("type1", "target")
            b:SetAttribute("unit1", t.unit)
        else
            b:SetAttribute("type1", "macro")
            b:SetAttribute("macrotext1", "/targetexact " .. t.npc)
        end
    end
    self.TargetWho = t.unit and (UnitName(t.unit)) or t.npc
    self:PlaceTargetButton()
    if not b:IsShown() then b:Show() end
end

function HUD:ApplyStyle()
    if self.Tex then
        AzerothAtlas.UI.StyleOptions:ApplyIcon(self.Tex, "HUDArrow")
    end
end

function HUD:ApplyOptions()
    local f = self.Frm
    if not f then return end
    local Core = Q.Core
    f:SetScale(Core:Opt("ArrowScale") or 1)
    -- Locked means click-through as well as immovable.
    f:EnableMouse(not Core:Opt("ArrowLocked"))
    -- 2026-11-18: the X / Y offset sliders write the saved anchor.
    AzerothAtlas.UI.Mixins.Draggable.RestoreAnchor(f, UIParent)
    self:PlaceTargetButton()
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

local function inBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

function HUD:Update(elapsed)
    local Routing = Q.Routing
    local t = overrideTarget() or (Routing and Routing.Target)
    -- 2026-11-18: hidden in battlegrounds when that option is on.
    if t and Q.Core:Opt("ArrowHideInBG") and inBattleground() then t = nil end
    self.Following = t
    local f = self.Frm
    if not t or not Routing then
        if f and f:IsShown() then f:Hide() end
        self.DistanceYards, self.TargetName, self.ETA = nil, nil, nil
        self:UpdateTargetButton(nil)
        return
    end

    local px, py, cont = Routing:GetPlayerPos()
    if not px then
        -- Inside an instance (or anywhere else the map can't place the
        -- player): there is no direction to show.
        if f and f:IsShown() then f:Hide() end
        self:UpdateTargetButton(nil)
        return
    end

    -- 2026-11-18 (user request, from Carbonite): travel routing - when a
    -- flight or a boat is the quicker way, point at where it starts
    -- (Map/Travel.lua). Following stays the real destination, so
    -- right-click still clears it.
    local Travel = AzerothAtlas.Modules.Map and AzerothAtlas.Modules.Map.Travel
    local leg = Travel and Travel:NextLeg(t)
    if leg then t = leg end

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
    -- The real destination's who-to-target, even when the arrow points
    -- at a flight master on the way.
    local who = self.Following
    self:UpdateTargetButton((who and (who.unit or who.npc)) and who or t)

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
        -- 2026-11-18 (from Carbonite's Track.ShowDir): degrees off course.
        if Q.Core:Opt("ArrowDirText") then
            str = str .. (dirDist < 1 and (" %.1f deg"):format(dirDist) or (" %d deg"):format(floor(dirDist + .5)))
        end

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
        elseif key == "ArrowLocked" or key == "ArrowScale" or key == "ArrowAnchor" then
            self:ApplyOptions()
        end
    end)
end
