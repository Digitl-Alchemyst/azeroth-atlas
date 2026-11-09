-- Alchemy GPS | Core / Logger
-- Level-based logger that writes to DEFAULT_CHAT_FRAME with a
-- consistent `|cff... [AlchemyGPS] ...|r` prefix. Modules acquire a
-- per-module logger via Logger:Get("Map") instead of a naked print().
--
-- Adapted from AlchemyNavigation/Core/Logger.lua (rename only).

local AlchemyGPS = _G.AlchemyGPS

local Logger = {}
AlchemyGPS.Core.Logger = Logger

local LEVEL = {
    DEBUG = 1,
    INFO  = 2,
    WARN  = 3,
    ERROR = 4,
    OFF   = 99,
}
Logger.LEVEL = LEVEL

-- Global cap: anything below this level is dropped before formatting.
-- Defaults to INFO; toggled to DEBUG with `/gps debug` or the
-- Settings window's Debug mode checkbox (Phase 3+).
Logger.minLevel = LEVEL.INFO

local LEVEL_PREFIX = {
    [LEVEL.DEBUG] = "|cff808080[D]|r ",
    [LEVEL.INFO]  = "|cffc0c0ff[I]|r ",
    [LEVEL.WARN]  = "|cffffd200[W]|r ",
    [LEVEL.ERROR] = "|cffff4040[E]|r ",
}

local ADDON_PREFIX = "|cffc0c0ff[AlchemyGPS]|r "

local function emit(level, tag, fmt, ...)
    if level < Logger.minLevel then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local line = ADDON_PREFIX .. LEVEL_PREFIX[level] .. (tag and ("[" .. tag .. "] ") or "") .. msg
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    else
        print(line)
    end
end

local Bound = {}
Bound.__index = Bound

function Bound:debug(fmt, ...) emit(LEVEL.DEBUG, self.tag, fmt, ...) end
function Bound:info(fmt, ...)  emit(LEVEL.INFO,  self.tag, fmt, ...) end
function Bound:warn(fmt, ...)  emit(LEVEL.WARN,  self.tag, fmt, ...) end
function Bound:error(fmt, ...) emit(LEVEL.ERROR, self.tag, fmt, ...) end

-- Module-friendly entry point. Returns an object with debug/info/warn/error
-- methods bound to a tag.
function Logger:Get(tag)
    return setmetatable({ tag = tag }, Bound)
end

function Logger:SetLevel(level)
    if type(level) == "string" then
        level = LEVEL[level:upper()]
    end
    if level then self.minLevel = level end
end

-- Shorthand for the root logger.
function Logger:debug(fmt, ...) emit(LEVEL.DEBUG, nil, fmt, ...) end
function Logger:info(fmt, ...)  emit(LEVEL.INFO,  nil, fmt, ...) end
function Logger:warn(fmt, ...)  emit(LEVEL.WARN,  nil, fmt, ...) end
function Logger:error(fmt, ...) emit(LEVEL.ERROR, nil, fmt, ...) end
