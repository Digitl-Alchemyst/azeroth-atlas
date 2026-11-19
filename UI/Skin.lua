-- Azeroth Atlas | UI / Skin
-- Build-order step 13 (2026-11-11): full 12-skin switchable registry,
-- explicit user request ("give me a tab in settings... style I swap
-- in and out"). Was a trimmed port of Carbonite's Nx.Skin hardcoded
-- to one entry ("Modern Dark") - see this file's own prior header
-- (kept below in spirit): "this addon has no skin-switcher UI... so
-- Init/Set/Update are merged into one one-time setup." That's no
-- longer true - this is now the real multi-skin Set/Update mechanism,
-- ported from Carbonite's actual Nx.Skin:Init/Set/Update
-- (Modules/UI/UIEngine.lua:1210-1513).
--
-- The other 11 skins' data (Blackout, Blackout Blues, Dialog Blue,
-- Dialog Gold, Simple Blue, Stone, Tool Blue, Modern Light, Glass,
-- Class Color, Faction) is copied verbatim from that same real source
-- block, confirmed on disk - only two edits from the original: (1)
-- Blackout/Simple Blue's `edgeFile` pointed at Carbonite's own live
-- install path (`Interface\Addons\Carbonite\Gfx\Skin\EdgeSquare`) -
-- rewritten to AzerothAtlas's own copy (Gfx/Skin/EdgeSquare.tga, copied
-- in this same build step) so this doesn't depend on Carbonite being
-- installed/enabled, the same "add them to our addon" reasoning
-- behind every other asset this step copied in. (2) Carbonite's own
-- WinBrH/WinBrV/TabOff/TabOn fields are dropped entirely - confirmed
-- by reading UI/Window.lua's own CreateBorders/SetBordersFade that
-- this addon's window chrome never reads them (it only ever calls
-- GetBackdrop/GetBorderCol/GetBGCol/GetFixedSizeBGCol), so porting
-- that extra border-bar/tab art would be dead data.
--
-- 10 of these 12 skins use only stock Blizzard border paths (already
-- available, zero asset copying) - only Blackout and Simple Blue need
-- the one real EdgeSquare.tga file.
--
-- GetBackdrop/GetBorderCol/GetBGCol/GetFixedSizeBGCol/GetTex are kept
-- verbatim (UIEngine.lua:1488-1513) - the real accessors Nx.Window
-- already reads.

local AzerothAtlas = _G.AzerothAtlas
local Nx = AzerothAtlas

Nx.Skin = Nx.Skin or {}
local Skin = Nx.Skin

local LOCAL_EDGE_SQUARE = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Skin\\EdgeSquare"

function Skin:Init()

    self.Path = "Interface\\AddOns\\AzerothAtlas\\Gfx\\Skin\\"

    self.Skins = {
        ["Blackout"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = LOCAL_EDGE_SQUARE,
                ["tile"] = true,
                ["tileSize"] = 8,
                ["edgeSize"] = 8,
                ["insets"] = { ["left"] = 0, ["right"] = 0, ["top"] = 0, ["bottom"] = 0 },
            },
            ["BdCol"] = "0|0|0|1",
            ["BgCol"] = "0|0|0|1",
        },
        ["Blackout Blues"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"] = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"] = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = ".8|.8|1|1",
            ["BgCol"] = "0|0|0|1",
        },
        ["Dialog Blue"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\DialogFrame\\UI-DialogBox-Border",
                ["tile"] = true,
                ["tileSize"] = 16,
                ["edgeSize"] = 16,
                ["insets"] = { ["left"] = 2, ["right"] = 2, ["top"] = 2, ["bottom"] = 2 },
            },
            ["BdCol"] = ".8|.8|1|1",
            ["BgCol"] = ".125|.125|.125|.88",
        },
        ["Dialog Gold"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
                ["tile"] = true,
                ["tileSize"] = 16,
                ["edgeSize"] = 16,
                ["insets"] = { ["left"] = 2, ["right"] = 2, ["top"] = 2, ["bottom"] = 2 },
            },
            ["BdCol"] = "1|1|1|1",
            ["BgCol"] = ".15|.15|0|.88",
        },
        ["Simple Blue"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = LOCAL_EDGE_SQUARE,
                ["tile"] = true,
                ["tileSize"] = 8,
                ["edgeSize"] = 8,
                ["insets"] = { ["left"] = 0, ["right"] = 0, ["top"] = 0, ["bottom"] = 0 },
            },
            ["BdCol"] = "0.7|0.7|1|0.8",
            ["BgCol"] = ".125|.125|.125|.88",
        },
        ["Stone"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Glues\\Common\\TextPanel-Border",
                ["tile"] = false,
                ["tileSize"] = 256,
                ["edgeSize"] = 16,
                ["insets"] = { ["left"] = 3, ["right"] = 2, ["top"] = 2, ["bottom"] = 2 },
            },
            ["BdCol"] = "1|1|1|1",
            ["BgCol"] = "0.06|0.06|0.06|.9",
        },
        ["Tool Blue"] = {
            ["Backdrop"] = {
                ["bgFile"] = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"] = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"] = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = ".8|1|1|.8",
            ["BgCol"] = ".125|.125|.125|.88",
        },
        ["Modern Dark"] = {
            ["Backdrop"] = {
                ["bgFile"]   = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"]     = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"]   = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = "0.30|0.36|0.46|0.95",
            ["BgCol"] = "0.06|0.07|0.10|0.92",
        },
        ["Modern Light"] = {
            ["Backdrop"] = {
                ["bgFile"]   = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"]     = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"]   = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = "0.50|0.55|0.65|0.95",
            ["BgCol"] = "0.88|0.88|0.92|0.92",
        },
        ["Glass"] = {
            ["Backdrop"] = {
                ["bgFile"]   = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"]     = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"]   = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = "1|1|1|0.40",
            ["BgCol"] = "0|0|0|0.40",
        },
        ["Class Color"] = {
            ["Backdrop"] = {
                ["bgFile"]   = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"]     = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"]   = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = "0.40|0.55|0.95|0.85",
            ["BgCol"] = "0.06|0.07|0.10|0.92",
            ["BdColResolve"] = function()
                local _, class = UnitClass("player")
                local cc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
                local c = class and cc and cc[class]
                if c then
                    return string.format("%f|%f|%f|0.90", c.r, c.g, c.b)
                end
            end,
        },
        ["Faction"] = {
            ["Backdrop"] = {
                ["bgFile"]   = "Interface\\Buttons\\White8x8",
                ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
                ["tile"]     = true,
                ["tileSize"] = 9,
                ["edgeSize"] = 9,
                ["insets"]   = { ["left"] = 1, ["right"] = 1, ["top"] = 1, ["bottom"] = 1 },
            },
            ["BdCol"] = "0.40|0.55|0.95|0.85",
            ["BgCol"] = "0.06|0.07|0.10|0.92",
            ["BdColResolve"] = function()
                local f = UnitFactionGroup("player")
                if f == "Alliance" then return "0.18|0.45|0.95|0.90" end
                if f == "Horde"    then return "0.85|0.20|0.20|0.90" end
            end,
        },
    }

    -- Build-order step 13 fix, 2026-11-11: AzerothAtlas.db does NOT
    -- exist yet at this point - Core/SavedVariables.lua only creates
    -- it later, on the AZEROTHATLAS_INITIALIZE event (PLAYER_LOGIN), not
    -- at file-load time (same timing gap MinimapWindow.lua's own
    -- OnEnable comment already documents for the exact same reason).
    -- Calling Set() here with a DB read, and Set() unconditionally
    -- writing AzerothAtlas.db.profile.Skin.*, crashed this file's own
    -- load with "attempt to index a nil value (field 'db')" every
    -- single addon load - which aborted Window:Create() further down
    -- the chain (CreateBorders succeeds since self.Data was already
    -- set before the crash, but SetBordersFade's GetBorderCol() then
    -- indexed a nil self.BdCol, since Update() never got to run) -
    -- the actual cause of the live "map replaced by a stuck white box"
    -- report, not the ResetWindows backdrop-color gap fixed earlier
    -- same day (a real, smaller bug, but not this one). Init() now
    -- only ever sets the hardcoded default here; the real saved choice
    -- is re-applied below once AzerothAtlas.db actually exists.
    self:Set("Modern Dark", true)

    AzerothAtlas.Core.EventBus:Subscribe("AZEROTHATLAS_INITIALIZE", function()
        local saved = AzerothAtlas.db and AzerothAtlas.db.profile.Skin
        if saved and saved.Name and saved.Name ~= "Modern Dark" then
            self:Set(saved.Name, true)
        end
    end)
end

-- Ordered names for the Style tab's swatch row - Lua tables have no
-- defined pairs() order, so the UI needs an explicit list.
Skin.Names = {
    "Modern Dark", "Modern Light", "Glass", "Class Color", "Faction",
    "Blackout", "Blackout Blues", "Dialog Blue", "Dialog Gold",
    "Simple Blue", "Stone", "Tool Blue",
}

function Skin:Set(skinName, init)
    self.Data = self.Skins[skinName or ""]

    if not self.Data then
        -- New default for fresh profiles (or an unrecognized saved
        -- name, e.g. from an older version) - same fallback real
        -- Carbonite's own Set uses.
        skinName = "Modern Dark"
        self.Data = self.Skins[skinName]
    end

    -- AzerothAtlas.db may not exist yet (see Init()'s own comment) -
    -- only persist the choice when there's somewhere real to put it;
    -- Update() below already tolerates that the same way.
    if AzerothAtlas.db then
        AzerothAtlas.db.profile.Skin = AzerothAtlas.db.profile.Skin or {}
        AzerothAtlas.db.profile.Skin.Name = skinName

        if not init then
            AzerothAtlas.db.profile.Skin.WinBdColor = self.Data["BdCol"]
            AzerothAtlas.db.profile.Skin.WinFixedBgColor = ".5|.5|.5|.5"
            AzerothAtlas.db.profile.Skin.WinSizedBgColor = self.Data["BgCol"]
        end
    end

    self:Update()

    if not init then
        self:ResetWindows()
    end
end

function Skin:Update()
    -- Themes can opt into a live-state border color (class/faction)
    -- via BdColResolve; the saved value is still the fallback when
    -- the resolver returns nil (e.g. no faction match).
    local data = self.Data
    local resolved
    if data and type(data["BdColResolve"]) == "function" then
        local ok, val = pcall(data.BdColResolve)
        if ok then resolved = val end
    end
    local sv = AzerothAtlas.db and AzerothAtlas.db.profile.Skin
    local bdColStr = resolved or (sv and sv.WinBdColor) or data["BdCol"]
    local bgColStr = (sv and sv.WinSizedBgColor) or data["BgCol"]
    local fixedColStr = (sv and sv.WinFixedBgColor) or ".5|.5|.5|.5"

    self.BdCol = { Nx.Util_str2rgba(bdColStr) }
    self.BgCol = { Nx.Util_str2rgba(bgColStr) }
    self.FixedBgCol = { Nx.Util_str2rgba(fixedColStr) }
end

-- Re-applies the current skin to every already-created window -
-- build-order step 13's reason to bring this back. UI/Window.lua's
-- own header notes this ("ResetBackdrops") was deleted because
-- "this addon has no skin-switcher UI to trigger a live re-skin" -
-- that's exactly what changed.
--
-- Fixed same-day regression, 2026-11-11: a real WoW API behavior -
-- calling :SetBackdrop() (which CreateBorders does) resets a frame's
-- backdrop COLOR to opaque white, discarding any prior
-- :SetBackdropColor tint. SetBordersFade only re-tints the BORDER
-- color, never the background - in normal play the background tint
-- is reapplied by Window:OnUpdate's own per-tick fade branch, but
-- ONLY while win.BackgndFade is actively changing value that tick, so
-- a window sitting at a settled fade level (the common case) never
-- got its background re-tinted after a skin change at all - left
-- looking like an opaque white box where the map used to be, not
-- fixing itself until the next time the user happened to mouse over
-- it (which nudges BackgndFade and triggers that branch). Replicates
-- that exact same color/alpha math here instead of relying on it.
function Skin:ResetWindows()
    local Window = Nx.Window
    if not (Window and Window.Wins) then return end
    for win in pairs(Window.Wins) do
        -- 2026-11-18: Window:ReSkin is this same repaint, and keeps a
        -- window's own theme (SkinOverride) if it has one.
        if win.ReSkin then
            win:ReSkin()
        elseif win.CreateBorders then
            win:CreateBorders()
        end
    end
end

function Skin:GetBackdrop()
    return self.Data["Backdrop"]
end

function Skin:GetBorderCol()
    return self.BdCol
end

function Skin:GetBGCol()
    return self.BgCol
end

function Skin:GetFixedSizeBGCol()
    return self.FixedBgCol
end

function Skin:GetTex(txName)
    return self.Path .. txName
end

-- No lifecycle event to hook (Settings/SavedVariables load earlier
-- than any window gets created), so init immediately at file load,
-- same as before.
Skin:Init()
