-- Alchemy GPS | Core / SlashCommands
-- Single owner for the `/gps` slash command. Modules register
-- subcommands via SlashCommands:Register("minimap", handler, helpText).
--
-- Adapted from AlchemyNavigation/Core/SlashCommands.lua (rename only).

local AlchemyGPS = _G.AlchemyGPS
local Logger = AlchemyGPS.Core.Logger:Get("Slash")

local SlashCommands = {}
AlchemyGPS.Core.SlashCommands = SlashCommands

local registry = {}
local helpLines = {}

function SlashCommands:Register(cmd, fn, help)
    registry[cmd:lower()] = fn
    if help then helpLines[#helpLines + 1] = ("  /gps %s - %s"):format(cmd, help) end
end

local function dispatch(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" or input == "help" or input == "?" then
        Logger:info("Alchemy GPS slash commands:")
        for _, line in ipairs(helpLines) do
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
        end
        return
    end

    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd:lower()
    local handler = registry[cmd]
    if handler then
        handler(rest)
    else
        Logger:warn("unknown subcommand %q (try /gps help)", cmd)
    end
end

function SlashCommands:Init()
    _G.SLASH_GPSCMD1 = "/gps"
    _G.SlashCmdList["GPSCMD"] = dispatch
end

-- Built-in subcommand: toggle debug log level.
SlashCommands:Register("debug", function()
    local Logger_ = AlchemyGPS.Core.Logger
    if Logger_.minLevel == Logger_.LEVEL.DEBUG then
        Logger_:SetLevel("INFO")
        Logger_:info("debug logging OFF")
    else
        Logger_:SetLevel("DEBUG")
        Logger_:info("debug logging ON")
    end
end, "toggle debug logging")

AlchemyGPS.Core.EventBus:Subscribe("ALCHEMYGPS_ENABLE", function()
    SlashCommands:Init()
end)
