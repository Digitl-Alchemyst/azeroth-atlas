-- Azeroth Atlas | Core / SlashCommands
-- Single owner for the `/aatlas` slash command. Modules register
-- subcommands via SlashCommands:Register("minimap", handler, helpText).
--
-- Adapted from AlchemyNavigation/Core/SlashCommands.lua (rename only).

local AzerothAtlas = _G.AzerothAtlas
local Logger = AzerothAtlas.Core.Logger:Get("Slash")

local SlashCommands = {}
AzerothAtlas.Core.SlashCommands = SlashCommands

local registry = {}
local helpLines = {}

function SlashCommands:Register(cmd, fn, help)
    registry[cmd:lower()] = fn
    if help then helpLines[#helpLines + 1] = ("  /aatlas %s - %s"):format(cmd, help) end
end

local function dispatch(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" or input == "help" or input == "?" then
        Logger:info("Azeroth Atlas slash commands:")
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
        Logger:warn("unknown subcommand %q (try /aatlas help)", cmd)
    end
end

function SlashCommands:Init()
    _G.SLASH_AATLASCMD1 = "/aatlas"
    _G.SlashCmdList["AATLASCMD"] = dispatch
end

-- Built-in subcommand: toggle debug log level.
SlashCommands:Register("debug", function()
    local Logger_ = AzerothAtlas.Core.Logger
    if Logger_.minLevel == Logger_.LEVEL.DEBUG then
        Logger_:SetLevel("INFO")
        Logger_:info("debug logging OFF")
    else
        Logger_:SetLevel("DEBUG")
        Logger_:info("debug logging ON")
    end
end, "toggle debug logging")

AzerothAtlas.Core.EventBus:Subscribe("AZEROTHATLAS_ENABLE", function()
    SlashCommands:Init()
end)
