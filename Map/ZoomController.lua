-- Alchemy GPS | Map / ZoomController
-- Owns scale + position animation for our minimap window's map
-- engine. Ported from Carbonite/Modules/Map/ZoomController.lua -
-- only the canvas-agnostic scale/position primitives (GetScale,
-- SetScale, ScrollSteps, Move). GotoPlayer/GotoCurrentZone/
-- CenterMap/CenterMap1To1/RememberScale all depend on the real
-- world-art canvas (zone/instance detection, Coords:WorldFromZone)
-- that doesn't exist until build-order step 8 - not ported here,
-- not approximated.
--
-- MinimapEngine:Update() reads ScaleDraw/MapPosXDraw/MapPosYDraw and
-- interpolates them toward Scale/MapPosX/MapPosY every tick (ported
-- from MapEngine.lua's own per-frame "Adjust draw scale and
-- position" block); StepTime is the number of frames remaining in
-- that animation. Legacy distance/snap thresholds (0.25 world units;
-- 0.01 inverse-scale difference) preserved verbatim.
--
-- Public API:
--   ZoomController:GetScale()
--   ZoomController:SetScale(scale, stepTime)
--   ZoomController:ScrollSteps(steps)          discrete in/out delta
--   ZoomController:Move(x, y, scale, stepTime) drive an animation

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local ZoomController = {}
AlchemyGPS.Modules.Map.ZoomController = ZoomController

-- Our single map instance lives directly on MinimapEngine (no
-- Nx.Map.Maps[1] indirection - this addon has exactly one map, ever).
local function mapInst()
    return AlchemyGPS.Modules.Map.MinimapEngine
end

-- Snap tolerances - identical to the legacy thresholds.
local POS_SNAP_DIST       = 0.25
local INV_SCALE_SNAP_DIFF = 0.01
-- Beyond this on-screen distance (in map units * scale / window size)
-- the legacy code accelerates the animation to 1 frame.
local FAR_JUMP_THRESHOLD  = 10

function ZoomController:GetScale()
    local m = mapInst()
    return m and m.Scale
end

function ZoomController:SetScale(scale, stepTime)
    local m = mapInst()
    if not m or not scale then return end
    self:Move(m.MapPosX, m.MapPosY, scale, stepTime or 10)
end

function ZoomController:ScrollSteps(steps)
    local m = mapInst()
    local ScrollScale = AlchemyGPS.Modules.Map.ScrollScale
    if not m or not ScrollScale then return end
    local sign = steps >= 0 and 1 or -1
    for _ = 1, math.abs(steps) do
        m.Scale = ScrollScale:Compute(m.Scale, sign)
    end
    m.StepTime = 10
end

function ZoomController:Move(x, y, scale, stepTime)
    local m = mapInst()
    if not m then return end

    m.MapPosX = x
    m.MapPosY = y
    if scale then m.Scale = scale end

    local dx = (m.MapPosXDraw or 0) - m.MapPosX
    local dy = (m.MapPosYDraw or 0) - m.MapPosY
    local dist = math.sqrt(dx * dx + dy * dy)

    local sz = math.max(m.MapW or 1, m.MapH or 1)

    -- Big on-screen jump while zoomed in -> animate fast.
    if (dist * (m.Scale or 1) / sz) > FAR_JUMP_THRESHOLD then
        stepTime = 1
    end

    -- If we're already in an animation, never extend it. StepTime
    -- may be negative when a continuation has been queued; treat as
    -- duration via abs().
    local st = math.abs(m.StepTime or 0)
    if st > 0 and st < (stepTime or 0) then
        stepTime = st
    end

    m.StepTime = stepTime or 10

    -- Snap on small position deltas so cumulative float drift stops
    -- the drawn copy lagging the logical pos forever.
    if dist < POS_SNAP_DIST then
        m.MapPosXDraw = m.MapPosX
        m.MapPosYDraw = m.MapPosY
    end

    -- Likewise for scale: when the inverse-scale gap is tiny, snap.
    if math.abs(1 / (m.ScaleDraw or 1) - 1 / (m.Scale or 1)) < INV_SCALE_SNAP_DIFF then
        m.ScaleDraw = m.Scale
        if dist < POS_SNAP_DIST then m.StepTime = 0 end
    end
end
