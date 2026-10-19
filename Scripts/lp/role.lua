-- Lootable Passives -- Which part this machine plays in the current world.
--
-- One of four roles:
--   standalone    a world with multiplayer off
--   listen_host   a world hosted by this game, with or without anyone joined
--   dedicated     a dedicated server
--   client        a game joined to someone else's world
--
-- Read from UPalUtility's IsServer, IsDedicatedServer and IsMultiplayer,
-- called on its class default object with the PalGameStateInGame as world
-- context (Pal.hpp, UPalUtility). nil until a PalGameStateInGame exists, which
-- it does not at the title screen. forget() returns it to nil on each map load
-- and starts reading it again.
--
-- Every getter fails closed: an unknown role is neither authoritative nor has a
-- UI.

local util = require("lp.util")

local call_one = util.call_one
local coalescer = util.coalescer
local find_first = util.find_first
local is_valid = util.is_valid
local log = util.log

local UTILITY_PATH = "/Script/Pal.Default__PalUtility"

-- What the startup and world-entry lines call each role.
local ROLE_TEXT = {
    standalone = "single player",
    listen_host = "listen host",
    dedicated = "dedicated server",
    client = "client",
}

-- 120 attempts at 1 s after each map load. A map with no PalGameStateInGame,
-- the title screen among them, uses the whole budget and resolves nothing.
local ATTEMPT_LIMIT = 120
local RETRY_DELAY_MS = 1000

local current = nil
local utility = nil
local listeners = {}
local attempts = 0

-- One UPalUtility predicate against context: true or false, or nil when the
-- call raises.
local function ask(name, context)
    local succeeded, answer = call_one(utility, name, context)
    if not succeeded then
        return nil
    end
    return answer == true
end

-- UPalUtility's class default object, found once and kept, or nil.
local function pal_utility()
    if not is_valid(utility) then
        local found, object = pcall(StaticFindObject, UTILITY_PATH)
        if not found or not is_valid(object) then
            return nil
        end
        utility = object
    end
    return utility
end

-- The role, or nil when there is no PalGameStateInGame or any of the calls
-- raises.
local function read_role()
    local context = find_first("PalGameStateInGame")
    if context == nil then
        return nil
    end
    if pal_utility() == nil then
        return nil
    end
    local server = ask("IsServer", context)
    if server == nil then
        return nil
    end
    if not server then
        return "client"
    end
    local dedicated = ask("IsDedicatedServer", context)
    if dedicated == nil then
        return nil
    end
    if dedicated then
        return "dedicated"
    end
    local multiplayer = ask("IsMultiplayer", context)
    if multiplayer == nil then
        return nil
    end
    return multiplayer and "listen_host" or "standalone"
end

-- Calls every on_known listener with the current role, each under its own
-- pcall. Scheduled rather than called from resolve(), so a listener never runs
-- inside the hook callback whose getter call resolved the role. Does nothing
-- when the role was forgotten again before this ran.
local function notify()
    if current == nil then
        return
    end
    for _, listener in ipairs(listeners) do
        local succeeded, raised = pcall(listener, current)
        if not succeeded then
            log("ERROR: a world-entry step raised a Lua error: " .. tostring(raised))
        end
    end
end

local schedule_notify = coalescer(notify, 0)

-- The role, reading it when it is not known yet. The read that finds it logs
-- one line and schedules the listeners.
local function resolve()
    if current ~= nil then
        return current
    end
    current = read_role()
    if current ~= nil then
        log(string.format("This machine is the %s in this world.", ROLE_TEXT[current]))
        schedule_notify()
    end
    return current
end

local schedule_attempt
local function attempt()
    if resolve() ~= nil then
        return
    end
    attempts = attempts + 1
    if attempts < ATTEMPT_LIMIT then
        schedule_attempt()
    end
end
schedule_attempt = coalescer(attempt, RETRY_DELAY_MS)

-- Called from main.lua's map-load hook: drops the role and starts a fresh
-- budget of reads for the new map.
local function forget()
    current = nil
    attempts = 0
    schedule_attempt()
end

-- listener(role) runs once per map load, on the game thread, once the role is
-- known. Register at load.
local function on_known(listener)
    listeners[#listeners + 1] = listener
end

-- The world's authoritative copy is on this machine: single player, a listen
-- host, or a dedicated server.
local function is_authority()
    local role = resolve()
    return role ~= nil and role ~= "client"
end

-- This machine draws the game's UI: everything but a dedicated server.
local function has_ui()
    local role = resolve()
    return role ~= nil and role ~= "dedicated"
end

-- The role's name for a log line, or "unknown".
local function describe()
    return ROLE_TEXT[current] or "unknown"
end

return {
    describe = describe,
    forget = forget,
    has_ui = has_ui,
    is_authority = is_authority,
    on_known = on_known,
    pal_utility = pal_utility,
}
