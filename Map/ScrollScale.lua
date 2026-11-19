-- Azeroth Atlas | Map / ScrollScale
-- The scale-step calculator used by mouse-wheel zoom and
-- ZoomController:ScrollSteps. Ported near-verbatim from
-- Carbonite/Modules/Map/ScrollScale.lua - only the pure Compute
-- formula; that file's Apply/legacy-rewire halves exist to bridge
-- Carbonite's own competing global Nx.Map, which doesn't apply here
-- (MinimapEngine/ZoomController call Compute directly).
--
-- The formula:
--   delta = value (>= 0 zoom in, < 0 zoom out)
--   if value < 0 then value = value * 0.76923  -- asymmetric feel
--   new = max(current + value * current * 0.3, MIN_SCALE)
--
-- The 0.76923 factor (~= 10/13) is the legacy magic that makes
-- zoom-out feel slower than zoom-in. The 0.3 factor controls how
-- much one scroll tick changes the scale. MIN_SCALE clamps to 0.015
-- so we can't drop below "world view".

local AzerothAtlas = _G.AzerothAtlas
AzerothAtlas.Modules.Map = AzerothAtlas.Modules.Map or {}

local ScrollScale = {}
AzerothAtlas.Modules.Map.ScrollScale = ScrollScale

ScrollScale.MIN_SCALE        = 0.015
ScrollScale.STEP             = 0.3
ScrollScale.ZOOM_OUT_DAMPING = 0.76923    -- = 10 / 13

-- Pure function: compute next scale from (current, ticks).
function ScrollScale:Compute(currentScale, value)
    if not currentScale or currentScale <= 0 then currentScale = 1 end
    if value < 0 then value = value * self.ZOOM_OUT_DAMPING end
    local next_ = currentScale + value * currentScale * self.STEP
    if next_ < self.MIN_SCALE then next_ = self.MIN_SCALE end
    return next_
end
