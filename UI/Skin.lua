-- Alchemy GPS | UI / Skin
-- Simplified port of Carbonite's Nx.Skin (Modules/UI/UIEngine.lua,
-- Skin:Init/Set/Update at lines 1210-1486). Carbonite's real version
-- is a live-switchable, SavedVariable-backed theme picker across 12
-- skins; this addon has no skin-switcher UI (not a feature this
-- project asked for), so Init/Set/Update are merged into one
-- one-time setup hardcoded to its "Modern Dark" theme - the one
-- entry in Carbonite's own skin table that already uses stock
-- Blizzard textures (Interface\Tooltips\UI-Tooltip-Border) for the
-- window backdrop, needing no Carbonite Gfx asset at all. Only the
-- button textures (ButClose/ButMax/ButLock) still come from our own
-- Gfx\Skin\ folder - see Skin:GetTex.
--
-- GetBackdrop/GetBorderCol/GetBGCol/GetFixedSizeBGCol/GetTex below
-- are kept verbatim (UIEngine.lua:1488-1513) - the real accessors
-- Nx.Window reads from.

local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS

Nx.Skin = Nx.Skin or {}
local Skin = Nx.Skin

function Skin:Init()

    self.Path = "Interface\\AddOns\\AlchemyGPS\\Gfx\\Skin\\"

    self.Data = {
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
    }

    self.BdCol = { Nx.Util_str2rgba(self.Data["BdCol"]) }
    self.BgCol = { Nx.Util_str2rgba(self.Data["BgCol"]) }
    self.FixedBgCol = self.BgCol
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

-- No SavedVariable dependency (one fixed theme), so init immediately
-- at file load rather than waiting for a lifecycle event.
Skin:Init()
