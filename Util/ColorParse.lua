-- Alchemy GPS | Util / ColorParse
-- Ported from Carbonite/Modules/UI/UIEngine.lua (Nx.Split at
-- Carbonite/Util/NxSplit.lua:17, Nx.Util_str2rgba/str2rgb at
-- UIEngine.lua:613/623). Needed by the ported Nx.Window/Nx.Button
-- code's "R|G|B|A" skin-color strings.

local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS

-- Cache for split results (weak values for garbage collection).
local TempTable = setmetatable({}, { __mode = "v" })

--- Split `p` by single-character `d`. Returns the pieces as
--- multiple values (use { Nx.Split(...) } to collect).
function Nx.Split(d, p)
    if p and not string.find(p, d) then
        return p
    end
    if not p then
        return nil
    end
    if #p <= 1 then return p end

    if TempTable[p] then
        return unpack(TempTable[p], 1, table.maxn(TempTable[p]))
    end

    local pieces = { strsplit(d, p) }
    TempTable[p] = pieces
    return unpack(pieces)
end

---
-- Parse "R|G|B|A" string to RGBA floats
--
function Nx.Util_str2rgba(colors)
    local arr = { Nx.Split("|", colors) }
    return tonumber(arr[1]), tonumber(arr[2]), tonumber(arr[3]), tonumber(arr[4])
end

---
-- Parse "R|G|B" string to RGB floats
--
function Nx.Util_str2rgb(colors)
    local arr = { Nx.Split("|", colors) }
    return tonumber(arr[1]), tonumber(arr[2]), tonumber(arr[3])
end
