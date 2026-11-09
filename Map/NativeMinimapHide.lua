-- Alchemy GPS | Map / NativeMinimapHide
-- Pure visibility toggle for Blizzard's own minimap exactly as it
-- ships: hidden means gone completely (cluster and everything in it,
-- since every child button is its descendant), shown means fully
-- restored to stock - native position, native buttons, nothing
-- reparented or masked.
--
-- Ported from AlchemyNavigation/Modules/Map/Minimap.lua's
-- SetNativeHidden/IsNativeHidden. That file's dual-purpose split with
-- an undocked-overlay mechanism doesn't apply here - this project's
-- undocked map is the real ported Nx.Map/ClipMMW mechanism (later
-- phase), not an overlay hack, so only the native-hide half carries
-- over.
--
-- Public API: NativeMinimapHide:SetNativeHidden(hidden) / IsNativeHidden()

local AlchemyGPS = _G.AlchemyGPS
AlchemyGPS.Modules.Map = AlchemyGPS.Modules.Map or {}

local NativeMinimapHide = {}
AlchemyGPS.Modules.Map.NativeMinimapHide = NativeMinimapHide

function NativeMinimapHide:SetNativeHidden(hidden)
    local cluster = _G.MinimapCluster
    if not cluster then return end

    self.NativeHidden = hidden

    if hidden then
        cluster:SetScript("OnShow", cluster.Hide)
        cluster:Hide()
        -- Belt-and-suspenders on top of the OnShow hook: Blizzard
        -- re-shows some children via a path OnShow doesn't catch.
        if not self.MMHideTimer then
            self.MMHideTimer = AlchemyGPS:ScheduleRepeatingTimer(function()
                if self.NativeHidden then cluster:Hide() end
            end, 0.2)
        end
    else
        cluster:SetScript("OnShow", nil)
        cluster:Show()
        if self.MMHideTimer then
            AlchemyGPS:CancelTimer(self.MMHideTimer)
            self.MMHideTimer = nil
        end
    end

    AlchemyGPS.Core.EventBus:Fire(hidden and "MAP_NATIVE_HIDDEN" or "MAP_NATIVE_SHOWN")
end

function NativeMinimapHide:IsNativeHidden() return self.NativeHidden == true end
