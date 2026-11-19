---------------------------------------------------------------------------------------
-- Azeroth Atlas | Map/BigMapThemes.lua
--
-- 2026-11-17 (user request: "give the big map themes I can choose from in
-- the settings"). Leatrix Maps' 15 map themes (UI/ThemeLibrary.lua),
-- applied to the big map.
--
-- 2026-11-18 (user request: "all themes able to be put on either"): one
-- list for both maps - the 12 window skins (UI/Skin.lua, by name) and the
-- 15 map themes (by number). Settings > Style:
--   Minimap Theme   MinimapWindow.MinimapTheme = a map theme's number, or
--                   nil = the window skin (picking a skin there sets the
--                   window skin, which every window wears, as before)
--   Big Map Theme   MinimapWindow.BigMapTheme = a number, a skin name, or
--                   0 = the same as the minimap
-- A skin on one map only is worn through the window's SkinOverride
-- (UI/Window.lua). Leatrix's "Glass" and "Class colour" are renamed
-- Frosted Glass and Class Tint (the skins have a Glass and a Class Color).
--
-- What a theme paints, following Leatrix's ApplyMapTheme:
--   title bar     gradient bgBottom -> bgTop (Rainbow: rainbow segments,
--                 Blizzard: the game's rock background)
--   frame edge    black (Glass: a 1-pixel white rim, see-through frame;
--                 Blizzard: the game's frame border art; Handheld / Retro
--                 TV: their casing)
--   toolbar       buttons in the title bar colours, accent border, icon-
--                 colour text, hover-colour highlight
--   footer        the coordinates bar, same as the title bar
--   menus         list colours (background, accent border, hover rows)
-- Colour themes ("color" or class colour) use Leatrix's wash recipe:
-- accent = colour x 0.85, hover = colour at 0.22, title bar = the colour
-- at 10% (bottom) to 20% (top).
-- Handheld and Retro TV are drawn the way Leatrix draws them, minus its
-- power-switch animations and the handheld's gem game.
---------------------------------------------------------------------------------------

local AzerothAtlas = _G.AzerothAtlas
AzerothAtlas.Modules.Map = AzerothAtlas.Modules.Map or {}

local Themes = {}
AzerothAtlas.Modules.Map.BigMapThemes = Themes

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local BLIZZ_LAYOUT = "ButtonFrameTemplateNoPortrait"

Themes.DEFAULT = 12     -- Blizzard (what the big map used before themes)

---------------------------------------------------------------------------------------
-- Theme list and colours
---------------------------------------------------------------------------------------

local function palettes()
    local lib = AzerothAtlas.UI.ThemeLibrary
    return lib and lib.Palettes or {}
end

local function palette(id)
    for _, p in ipairs(palettes()) do
        if p.id == id then return p end
    end
    return nil
end

-- Every theme, { { id, name }, ... }: the window skins (id = the skin's
-- name) then the map themes (id = number). forBig: "Same as the minimap"
-- (0) first.
function Themes:GetList(forBig)
    local list = {}
    if forBig then list[1] = { id = 0, name = "Same as the minimap" } end
    local Skin = AzerothAtlas.Skin
    for _, name in ipairs(Skin and Skin.Names or {}) do
        list[#list + 1] = { id = name, name = name, skin = true }
    end
    for _, p in ipairs(palettes()) do list[#list + 1] = { id = p.id, name = p.name } end
    return list
end

local function str2rgba(s)
    local Util = AzerothAtlas.Util_str2rgba
    if Util and s then return { Util(s) } end
    return { 0, 0, 0, 1 }
end

-- A window skin's own colours (not the saved tweaks of the one in use).
local function skinColours(name)
    local Skin = AzerothAtlas.Skin
    local data = Skin and Skin.Skins and Skin.Skins[name]
    if not data then return nil end
    local bd = data.BdCol
    if type(data.BdColResolve) == "function" then
        local ok, v = pcall(data.BdColResolve)
        if ok and v then bd = v end
    end
    return data, str2rgba(bd), str2rgba(data.BgCol)
end

-- The colours a theme paints with, or nil for 0 / an unknown id.
function Themes:Resolve(id)
    local p = palette(id)
    if not p then return nil end
    local r, g, b
    if p.classColor then
        local _, cls = UnitClass("player")
        local c = (cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]) or NORMAL_FONT_COLOR
        r, g, b = c.r, c.g, c.b
    elseif p.color then
        r, g, b = p.color[1], p.color[2], p.color[3]
    end
    local s = { p = p }
    if r then
        s.accent = { r * 0.85, g * 0.85, b * 0.85 }
        s.hover = { r, g, b, 0.22 }
        s.bgBottom = { r * 0.10, g * 0.10, b * 0.10, 1 }
        s.bgTop = { r * 0.20, g * 0.20, b * 0.20, 1 }
    else
        s.accent = p.accent
        s.hover = p.hover
        s.bgBottom = { p.bgBottom[1], p.bgBottom[2], p.bgBottom[3], p.bgBottom[4] or 1 }
        s.bgTop = { p.bgTop[1], p.bgTop[2], p.bgTop[3], p.bgTop[4] or 1 }
    end
    local a = s.accent
    local m = math.max(a[1], a[2], a[3])
    local k = m > 0 and 1 / m or 1
    s.icon = p.icon or { a[1] * k, a[2] * k, a[3] * k }
    if p.blizzard then
        s.list = { 0.13, 0.08, 0.045, 0.55, 0.42, 0.22, 0.97 }
    elseif p.list then
        s.list = p.list
    else
        s.list = { s.bgTop[1], s.bgTop[2], s.bgTop[3], a[1], a[2], a[3], 0.95 }
    end
    return s
end

-- Two colours for the Settings swatch: background and accent.
function Themes:Preview(id)
    if type(id) == "string" then
        local _, bd, bg = skinColours(id)
        if bd then return bg, bd end
    end
    local s = self:Resolve(id)
    if not s then return { 0.12, 0.12, 0.12, 1 }, { 0.45, 0.45, 0.45, 1 } end
    local bg = s.bgTop
    return { bg[1], bg[2], bg[3], math.max(bg[4] or 1, 0.6) }, { s.accent[1], s.accent[2], s.accent[3], 1 }
end

---------------------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------------------

local function gradient(t, bottom, top)
    t:SetTexture(WHITE)
    t:SetVertexColor(1, 1, 1, 1)
    t:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1),
        CreateColor(top[1], top[2], top[3], top[4] or 1))
end

local function flat(t, r, g, b, a)
    t:SetTexture(WHITE)
    t:SetVertexColor(r, g, b, a or 1)
end

-- A plain texture on `owner`, remembered in `parts`.
local function solid(owner, parts, layer, sub, r, g, b, a)
    local t = owner:CreateTexture(nil, layer, nil, sub)
    flat(t, r, g, b, a)
    parts[#parts + 1] = t
    return t
end

local function makeRound(owner, t)
    if not owner.CreateMaskTexture then return end
    local m = owner:CreateMaskTexture()
    m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
end

local function disc(owner, parts, layer, sub, size, r, g, b, a, point, x, y)
    local t = solid(owner, parts, layer, sub, r, g, b, a)
    t:SetSize(size, size)
    t:SetPoint("CENTER", owner, point, x, y)
    makeRound(owner, t)
    return t
end

local function rect(owner, parts, layer, sub, w, h, r, g, b, a, point, x, y)
    local t = solid(owner, parts, layer, sub, r, g, b, a)
    t:SetSize(w, h)
    t:SetPoint("CENTER", owner, point, x, y)
    return t
end

-- Round-cornered rectangle reaching l/r/t/b past `owner`'s edges.
local function roundRect(owner, parts, layer, sub, cr, cg, cb, l, r, t, b, rad, dy)
    dy = dy or 0
    local tall = solid(owner, parts, layer, sub, cr, cg, cb, 1)
    tall:SetPoint("TOPLEFT", owner, "TOPLEFT", -l + rad, t + dy)
    tall:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", r - rad, -b + dy)
    local wide = solid(owner, parts, layer, sub, cr, cg, cb, 1)
    wide:SetPoint("TOPLEFT", owner, "TOPLEFT", -l, t - rad + dy)
    wide:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", r, -b + rad + dy)
    disc(owner, parts, layer, sub, rad * 2, cr, cg, cb, 1, "TOPLEFT", -l + rad, t - rad + dy)
    disc(owner, parts, layer, sub, rad * 2, cr, cg, cb, 1, "TOPRIGHT", r - rad, t - rad + dy)
    disc(owner, parts, layer, sub, rad * 2, cr, cg, cb, 1, "BOTTOMLEFT", -l + rad, -b + rad + dy)
    disc(owner, parts, layer, sub, rad * 2, cr, cg, cb, 1, "BOTTOMRIGHT", r - rad, -b + rad + dy)
end

local function label(owner, parts, text, r, g, b, point, x, y, size)
    local fs = owner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetPoint("CENTER", owner, point, x, y)
    if size then
        local font = fs:GetFont()
        if font then fs:SetFont(font, size, "") end
    end
    parts[#parts + 1] = fs
    return fs
end

local function showParts(parts, on)
    for _, p in ipairs(parts or {}) do p:SetShown(on) end
end

---------------------------------------------------------------------------------------
-- Rainbow (title bar and footer)
---------------------------------------------------------------------------------------

local function rainbowColors()
    local p = palette(11)
    return p and p.rainbowColors or { { 1, 0, 0 }, { 0, 0, 1 } }, p and p.rainbowShade or 0.3
end

-- Segments on `owner` laid over `region` (re-laid out by Themes:Tick).
local function makeRainbow(owner, region, sub)
    local colors, shade = rainbowColors()
    local n = #colors - 1
    local rb = { region = region, n = n }
    for i = 1, n do
        local seg = owner:CreateTexture(nil, "BACKGROUND", nil, sub)
        local c1, c2 = colors[i], colors[i + 1]
        seg:SetTexture(WHITE)
        seg:SetGradient("HORIZONTAL", CreateColor(c1[1] * shade, c1[2] * shade, c1[3] * shade, 1),
            CreateColor(c2[1] * shade, c2[2] * shade, c2[3] * shade, 1))
        rb[i] = seg
    end
    local dark = owner:CreateTexture(nil, "BACKGROUND", nil, sub + 1)
    dark:SetTexture(WHITE)
    dark:SetAllPoints(region)
    dark:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0))
    rb.dark = dark
    return rb
end

local function layoutRainbow(rb)
    local w = rb.region:GetWidth()
    if not w or w <= 0 or w == rb.w then return end
    rb.w = w
    for i = 1, rb.n do
        local seg = rb[i]
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", rb.region, "TOPLEFT", w * (i - 1) / rb.n, 0)
        seg:SetPoint("BOTTOMLEFT", rb.region, "BOTTOMLEFT", w * (i - 1) / rb.n, 0)
        seg:SetWidth(w / rb.n)
    end
end

local function showRainbow(rb, on)
    if not rb then return end
    for i = 1, rb.n do rb[i]:SetShown(on) end
    rb.dark:SetShown(on)
    if on then rb.w = nil layoutRainbow(rb) end
end

---------------------------------------------------------------------------------------
-- The art themes
---------------------------------------------------------------------------------------

local function buildBlizzard(bm)
    local f = bm.Win.Frm
    local b = CreateFrame("Frame", nil, f)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 2)
    b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    b:EnableMouse(false)
    local pieces = {}
    function b:GetNineSlicePiece(name)
        if not pieces[name] then pieces[name] = b:CreateTexture(nil, "BORDER") end
        return pieces[name]
    end
    local ok = NineSliceUtil and NineSliceUtil.ApplyLayoutByName and NineSliceUtil.GetLayout
        and NineSliceUtil.GetLayout(BLIZZ_LAYOUT)
        and pcall(NineSliceUtil.ApplyLayoutByName, b, BLIZZ_LAYOUT)
    if not ok then
        local bd = CreateFrame("Frame", nil, b, "BackdropTemplate")
        bd:SetAllPoints()
        bd:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 32 })
    end
    if pieces.Center then pieces.Center:Hide() end
    return { frame = b }
end

local function buildGlass(bm)
    local f = bm.Win.Frm
    local parts = {}
    local top = solid(f, parts, "BORDER", 7, 1, 1, 1, 0.55)
    top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(1)
    local bottom = solid(f, parts, "BORDER", 7, 1, 1, 1, 0.55)
    bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(1)
    local left = solid(f, parts, "BORDER", 7, 1, 1, 1, 0.55)
    left:SetPoint("TOPLEFT", 0, -1) left:SetPoint("BOTTOMLEFT", 0, 1) left:SetWidth(1)
    local right = solid(f, parts, "BORDER", 7, 1, 1, 1, 0.55)
    right:SetPoint("TOPRIGHT", 0, -1) right:SetPoint("BOTTOMRIGHT", 0, 1) right:SetWidth(1)
    local sheen = f:CreateTexture(nil, "BACKGROUND", nil, 5)
    sheen:SetTexture(WHITE)
    sheen:SetPoint("TOPLEFT", 1, -1) sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(11)
    sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.12))
    parts[#parts + 1] = sheen
    return { parts = parts }
end

local function buildHandheld(bm)
    local f = bm.Win.Frm
    local parts = {}
    local pl, pr, pt, pb = 96, 96, 18, 30
    -- Body: a darker copy a little lower is the plastic's thickness.
    roundRect(f, parts, "BACKGROUND", -8, 0.04, 0.04, 0.05, pl, pr, pt, pb, 40, -4)
    roundRect(f, parts, "BACKGROUND", -7, 0.13, 0.13, 0.15, pl, pr, pt, pb, 40)
    local shine = solid(f, parts, "BACKGROUND", -6, 1, 1, 1, 0.14)
    shine:SetPoint("TOPLEFT", f, "TOPLEFT", -pl + 40, pt)
    shine:SetPoint("TOPRIGHT", f, "TOPRIGHT", pr - 40, pt)
    shine:SetHeight(2)
    -- Screen surround and the name under it.
    roundRect(f, parts, "BACKGROUND", -5, 0.05, 0.05, 0.06, 12, 12, 10, 22, 8)
    label(f, parts, "AZEROTH ATLAS  \194\183  POCKET MAP", 0.42, 0.42, 0.47, "BOTTOM", 0, -12)
    -- Red power light.
    disc(f, parts, "ARTWORK", 0, 14, 1, 0.20, 0.20, 0.35, "LEFT", -6, 0)
    disc(f, parts, "ARTWORK", 1, 7, 1, 0.25, 0.25, 1, "LEFT", -6, 0)
    -- D-pad.
    local dx, dy = -54, 24
    rect(f, parts, "ARTWORK", 0, 20, 60, 0.01, 0.01, 0.01, 1, "LEFT", dx, dy - 3)
    rect(f, parts, "ARTWORK", 0, 60, 20, 0.01, 0.01, 0.01, 1, "LEFT", dx, dy - 3)
    rect(f, parts, "ARTWORK", 1, 20, 60, 0.06, 0.06, 0.07, 1, "LEFT", dx, dy)
    rect(f, parts, "ARTWORK", 1, 60, 20, 0.06, 0.06, 0.07, 1, "LEFT", dx, dy)
    disc(f, parts, "ARTWORK", 2, 12, 0.11, 0.11, 0.12, 1, "LEFT", dx, dy)
    -- A and B buttons.
    local faceTop, faceBottom = CreateColor(0.74, 0.40, 0.64, 1), CreateColor(0.48, 0.17, 0.40, 1)
    for _, btn in ipairs({ { "A", 70, 34 }, { "B", 38, 14 } }) do
        local x, y = btn[2], btn[3]
        disc(f, parts, "ARTWORK", 0, 30, 0.18, 0.05, 0.14, 1, "RIGHT", x, y - 3)
        local face = disc(f, parts, "ARTWORK", 1, 30, 1, 1, 1, 1, "RIGHT", x, y)
        face:SetGradient("VERTICAL", faceBottom, faceTop)
        label(f, parts, btn[1], 0.96, 0.86, 0.93, "RIGHT", x, y)
    end
    -- Power button, bottom left.
    disc(f, parts, "ARTWORK", 0, 30, 0.02, 0.02, 0.03, 1, "BOTTOMLEFT", -60, 21)
    local power = disc(f, parts, "ARTWORK", 1, 30, 1, 1, 1, 1, "BOTTOMLEFT", -60, 24)
    power:SetGradient("VERTICAL", CreateColor(0.30, 0.06, 0.06, 1), CreateColor(0.58, 0.15, 0.15, 1))
    label(f, parts, "POWER", 0.42, 0.42, 0.47, "BOTTOMLEFT", -60, 2, 8)
    -- Speaker holes, at an angle.
    local angle = math.rad(25)
    for row = 1, 4 do
        for col = 1, 3 do
            local lx, ly = (col - 2) * 9, (row - 2.5) * -9
            local x = 64 + lx * math.cos(angle) - ly * math.sin(angle)
            local y = -118 + lx * math.sin(angle) + ly * math.cos(angle)
            disc(f, parts, "ARTWORK", 0, 5, 0.03, 0.03, 0.04, 1, "RIGHT", x, y)
        end
    end
    return { parts = parts }
end

local function buildTV(bm)
    local f = bm.Win.Frm
    local parts = {}
    local pl, pr, pt, pb = 12, 62, 12, 16
    -- Wood casing: colour, grain, shading, bevel.
    local wood = solid(f, parts, "BACKGROUND", -8, 0.40, 0.24, 0.12, 1)
    wood:SetPoint("TOPLEFT", f, "TOPLEFT", -pl, pt)
    wood:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pr, -pb)
    local grain = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    grain:SetTexture(ROCK, "REPEAT", "REPEAT")
    grain:SetHorizTile(true) grain:SetVertTile(true)
    grain:SetVertexColor(0.55, 0.35, 0.18, 0.55)
    grain:SetAllPoints(wood)
    parts[#parts + 1] = grain
    local shade = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    shade:SetTexture(WHITE)
    shade:SetAllPoints(wood)
    shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(1, 0.9, 0.7, 0.06))
    parts[#parts + 1] = shade
    local bt = solid(f, parts, "BACKGROUND", -5, 1, 0.85, 0.65, 0.30)
    bt:SetPoint("TOPLEFT", wood) bt:SetPoint("TOPRIGHT", wood) bt:SetHeight(2)
    local bl = solid(f, parts, "BACKGROUND", -5, 1, 0.85, 0.65, 0.20)
    bl:SetPoint("TOPLEFT", wood) bl:SetPoint("BOTTOMLEFT", wood) bl:SetWidth(2)
    local bb = solid(f, parts, "BACKGROUND", -5, 0, 0, 0, 0.45)
    bb:SetPoint("BOTTOMLEFT", wood) bb:SetPoint("BOTTOMRIGHT", wood) bb:SetHeight(2)
    local br = solid(f, parts, "BACKGROUND", -5, 0, 0, 0, 0.35)
    br:SetPoint("TOPRIGHT", wood) br:SetPoint("BOTTOMRIGHT", wood) br:SetWidth(2)
    -- Bezel round the screen.
    local bezel = solid(f, parts, "BACKGROUND", -4, 0.05, 0.05, 0.05, 1)
    bezel:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5) bezel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 5, -5)
    local lip = solid(f, parts, "BACKGROUND", -3, 0.20, 0.18, 0.16, 1)
    lip:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2) lip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    -- Side panel: two knobs, a grille and a power light.
    local panel = solid(f, parts, "BACKGROUND", -4, 0, 0, 0, 0.25)
    panel:SetPoint("TOPLEFT", f, "TOPRIGHT", 12, -2)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pr - 2, 2)
    for _, knob in ipairs({ { -30, 120 }, { -78, 30 } }) do
        local y, ang = knob[1], math.rad(knob[2])
        local ring = disc(f, parts, "ARTWORK", 0, 36, 0.10, 0.07, 0.05, 1, "TOPRIGHT", 36, y)
        local face = disc(f, parts, "ARTWORK", 1, 30, 1, 1, 1, 1, "TOPRIGHT", 36, y)
        face:SetGradient("VERTICAL", CreateColor(0.28, 0.26, 0.23, 1), CreateColor(0.68, 0.64, 0.57, 1))
        disc(f, parts, "ARTWORK", 2, 10, 0.20, 0.18, 0.16, 1, "TOPRIGHT", 36, y)
        local pointer = f:CreateLine(nil, "ARTWORK", nil, 3)
        pointer:SetThickness(2)
        pointer:SetColorTexture(0.95, 0.92, 0.85, 1)
        pointer:SetStartPoint("CENTER", ring, math.cos(ang) * 5, math.sin(ang) * 5)
        pointer:SetEndPoint("CENTER", ring, math.cos(ang) * 13, math.sin(ang) * 13)
        parts[#parts + 1] = pointer
    end
    for i = 1, 12 do
        local slat = solid(f, parts, "ARTWORK", 0, 0.07, 0.05, 0.03, 0.85)
        slat:SetSize(34, 2)
        slat:SetPoint("TOP", f, "TOPRIGHT", 36, -112 - (i - 1) * 6)
        local light = solid(f, parts, "ARTWORK", 0, 1, 0.85, 0.65, 0.12)
        light:SetSize(34, 1)
        light:SetPoint("TOP", slat, "BOTTOM", 0, 0)
    end
    disc(f, parts, "ARTWORK", 0, 16, 1, 0.25, 0.10, 0.35, "BOTTOMRIGHT", 36, 18)
    disc(f, parts, "ARTWORK", 1, 7, 1, 0.30, 0.15, 1, "BOTTOMRIGHT", 36, 18)
    -- Screen effects over the map: vignette, glare, scanlines. Takes no clicks.
    local screen = CreateFrame("Frame", nil, f)
    screen:SetAllPoints(bm.Content)
    screen:EnableMouse(false)
    local function edge(p1, p2, size, horizontal, fromStart)
        local t = screen:CreateTexture(nil, "BORDER")
        t:SetTexture(WHITE)
        t:SetPoint(p1) t:SetPoint(p2)
        if horizontal then t:SetWidth(size) else t:SetHeight(size) end
        local dark, clear = CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0)
        local o = horizontal and "HORIZONTAL" or "VERTICAL"
        if fromStart then t:SetGradient(o, dark, clear) else t:SetGradient(o, clear, dark) end
    end
    edge("TOPLEFT", "TOPRIGHT", 30, false, false)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", 30, false, true)
    edge("TOPLEFT", "BOTTOMLEFT", 30, true, true)
    edge("TOPRIGHT", "BOTTOMRIGHT", 30, true, false)
    local glare = screen:CreateTexture(nil, "OVERLAY")
    glare:SetTexture(WHITE)
    glare:SetPoint("TOPLEFT") glare:SetPoint("TOPRIGHT")
    glare:SetHeight(70)
    glare:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.07))
    screen.lines = {}
    return { parts = parts, screen = screen }
end

-- One line every 3 pixels down the TV screen.
local function layoutScanlines(screen)
    local h = screen:GetHeight()
    if not h or h <= 0 or h == screen.h then return end
    screen.h = h
    local count = math.floor(h / 3)
    for i = 1, count do
        local line = screen.lines[i]
        if not line then
            line = screen:CreateTexture(nil, "ARTWORK")
            line:SetTexture(WHITE)
            line:SetVertexColor(0, 0, 0, 0.13)
            line:SetPoint("TOPLEFT", 0, -3 * i)
            line:SetPoint("TOPRIGHT", 0, -3 * i)
            line:SetHeight(1)
            screen.lines[i] = line
        end
        line:Show()
    end
    for i = count + 1, #screen.lines do screen.lines[i]:Hide() end
end

local BUILDERS = { blizzard = buildBlizzard, glass = buildGlass, handheld = buildHandheld, tv = buildTV }

local function artKind(p)
    if not p then return nil end
    if p.blizzard then return "blizzard" end
    if p.glass then return "glass" end
    if p.handheld then return "handheld" end
    if p.tv then return "tv" end
    return nil
end

local function showArt(art, on)
    if not art then return end
    if art.frame then art.frame:SetShown(on) end
    if art.screen then art.screen:SetShown(on) end
    showParts(art.parts, on)
end

---------------------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------------------

-- Paints (or, with s = nil, un-paints) one toolbar button.
local function paintButton(b, s)
    if not b.edges then
        b.edges = {}
        for i = 1, 4 do
            local e = b:CreateTexture(nil, "BORDER")
            e:SetTexture(WHITE)
            b.edges[i] = e
        end
        b.edges[1]:SetPoint("TOPLEFT") b.edges[1]:SetPoint("TOPRIGHT") b.edges[1]:SetHeight(1)
        b.edges[2]:SetPoint("BOTTOMLEFT") b.edges[2]:SetPoint("BOTTOMRIGHT") b.edges[2]:SetHeight(1)
        b.edges[3]:SetPoint("TOPLEFT") b.edges[3]:SetPoint("BOTTOMLEFT") b.edges[3]:SetWidth(1)
        b.edges[4]:SetPoint("TOPRIGHT") b.edges[4]:SetPoint("BOTTOMRIGHT") b.edges[4]:SetWidth(1)
    end
    if s then
        gradient(b.bg, s.bgBottom, s.bgTop)
        for _, e in ipairs(b.edges) do e:SetVertexColor(s.accent[1], s.accent[2], s.accent[3], 0.9) e:Show() end
        b.text:SetTextColor(s.icon[1], s.icon[2], s.icon[3])
        flat(b.hl, s.hover[1], s.hover[2], s.hover[3], math.max(s.hover[4] or 0.15, 0.15))
    else
        flat(b.bg, 0, 0, 0, 0.6)
        for _, e in ipairs(b.edges) do e:Hide() end
        b.text:SetTextColor(1, 0.82, 0)
        flat(b.hl, 1, 1, 1, 0.12)
    end
end

function Themes:Apply(bm, id)
    local win = bm.Win
    local f = win.Frm
    local s = self:Resolve(id)
    local p = s and s.p
    bm.ThemeSpec = s

    -- Title bar.
    if not bm.TitleTex then
        local t = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        t:SetHeight(win.TopH or 20)
        bm.TitleTex = t
    end
    local tt = bm.TitleTex
    if not s then
        tt:Hide()
    elseif p.blizzard then
        tt:SetTexture(ROCK, "REPEAT", "REPEAT")
        tt:SetHorizTile(true) tt:SetVertTile(true)
        tt:SetVertexColor(1, 1, 1, 1)
        tt:Show()
    else
        tt:SetHorizTile(false) tt:SetVertTile(false)
        gradient(tt, s.bgBottom, s.bgTop)
        tt:Show()
    end

    -- Footer.
    local fb = bm.FootBg
    if fb then
        if not s then
            fb:SetHorizTile(false) fb:SetVertTile(false)
            flat(fb, 0, 0, 0, 0.6)
        elseif p.blizzard then
            fb:SetTexture(ROCK, "REPEAT", "REPEAT")
            fb:SetHorizTile(true) fb:SetVertTile(true)
            fb:SetVertexColor(1, 1, 1, 1)
        else
            fb:SetHorizTile(false) fb:SetVertTile(false)
            gradient(fb, s.bgBottom, s.bgTop)
        end
    end

    -- Rainbow.
    local rainbow = p and p.rainbow or false
    if rainbow and not bm.TitleRainbow then
        bm.TitleRainbow = makeRainbow(f, tt, 3)
        bm.FootRainbow = makeRainbow(bm.Foot, bm.Foot, 1)
    end
    showRainbow(bm.TitleRainbow, rainbow)
    showRainbow(bm.FootRainbow, rainbow)

    -- Toolbar.
    for _, b in ipairs(bm.Buttons or {}) do paintButton(b, s) end

    -- Art themes: build on first use, show only the one in use.
    local kind = artKind(p)
    bm.Art = bm.Art or {}
    if kind and not bm.Art[kind] then bm.Art[kind] = BUILDERS[kind](bm) end
    for k, art in pairs(bm.Art) do showArt(art, k == kind) end

    -- Frame edge and background, worn as the window's own look
    -- (UI/Window.lua SkinOverride) so the window's fade keeps them:
    --   a skin by name   that skin's border and colours
    --   a map theme      the window skin's border and background (Frosted
    --                    Glass: see-through), black edge (art themes: none)
    --   0 / nil          the window skin, nothing of its own
    local Skin = AzerothAtlas.Skin
    local ov
    if type(id) == "string" then
        local data, bd, bg = skinColours(id)
        if data then ov = { Backdrop = data.Backdrop, BdCol = bd, BgCol = bg } end
    elseif s then
        local bgc = Skin and Skin.GetBGCol and Skin:GetBGCol() or { 0, 0, 0, 0.9 }
        ov = {
            BgCol = { bgc[1], bgc[2], bgc[3], p.glass and 0 or bgc[4] },
            BdCol = kind and { 0, 0, 0, 0 } or { 0, 0, 0, 1 },
        }
    end
    win.SkinOverride = ov
    if win.ReSkin then win:ReSkin() end
    bm.ThemeKind = kind
end

-- Every tick while the big map is up: frame levels and sizes that the
-- map's own updates can change.
function Themes:Tick(bm)
    local art = bm.Art and bm.ThemeKind and bm.Art[bm.ThemeKind]
    if art then
        local base = bm.Content and bm.Content:GetFrameLevel() or bm.Win.Frm:GetFrameLevel()
        local fr = art.frame or art.screen
        if fr and fr:GetFrameLevel() ~= base + 40 then fr:SetFrameLevel(base + 40) end
        if art.screen then layoutScanlines(art.screen) end
    end
    if bm.TitleRainbow and bm.TitleRainbow[1]:IsShown() then
        layoutRainbow(bm.TitleRainbow)
        layoutRainbow(bm.FootRainbow)
    end
end

-- Menu colours for Map/BigMap.lua's popup menus: bg rgba, border rgb,
-- row highlight rgba; nil = the default tooltip look.
function Themes:MenuColors(bm)
    local s = bm and bm.ThemeSpec
    if not s then return nil end
    local l, h = s.list, s.hover
    return { l[1], l[2], l[3], l[7] or 0.95 }, { l[4], l[5], l[6] },
        { h[1] + (1 - h[1]) * 0.3, h[2] + (1 - h[2]) * 0.3, h[3] + (1 - h[3]) * 0.3, 0.3 }
end
