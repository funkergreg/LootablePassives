-- Lootable Passives -- One bounded, re-armed hook registrar.
--
-- The two widget hooks in main.lua and both conveyor hooks register through
-- here. main.lua's SERVER_REQUEST hook calls RegisterHook directly, since it
-- takes a pre- and a post-callback. Coalescing a hook that fires at frame rate
-- is not here; that is main.lua's coalescer().
--
-- Four properties of the shape below are deliberate:
--
--   * Retries are BOUNDED.
--   * The callback is built once, by the caller, at load, and must capture no
--     per-call state.
--   * One retry closure per registration, built at registration time, not one
--     per attempt.
--   * A fresh retry budget per map, since the target of a widget hook does not
--     exist until a world has loaded.

local util = require("lp.util")

local find_first = util.find_first
local log = util.log

-- 90 attempts at 1 s. The budget has to outlast a world load, which varies by
-- tens of seconds; exhausting it produces only a warning about a hook that
-- installs on the next map load. entry.retry is built once per registration, so
-- an attempt allocates nothing and a long budget is cheap.
local ATTEMPT_LIMIT = 90
local RETRY_DELAY_MS = 1000

-- Every registration made through this module, so map load can re-arm them.
local entries = {}

local announced = false

-- One line, when the last registration lands. Two register at load and two only
-- once a world exists, so reporting each one separately would scatter four lines
-- across a startup.
local function announce_if_complete()
    if announced then
        return
    end
    local installed = {}
    for _, entry in ipairs(entries) do
        if not entry.registered then
            return
        end
        installed[#installed + 1] = entry.label
    end
    if #installed == 0 then
        return
    end
    announced = true
    log(string.format("All %d hooks installed: %s.", #installed, table.concat(installed, ", ")))
end

-- Is a player character resolvable? Suppresses warning on the
-- splash, login and title maps, where a widget hook has nothing to bind to.
local function in_world()
    -- util.find_first validates before returning; raw FindFirstOf can return a
    -- non-nil object that is not usable.
    return find_first("PalPlayerCharacter") ~= nil
end

local function attempt(entry)
    if entry.registered then
        return
    end
    entry.attempts = entry.attempts + 1
    -- Argument-form pcall against the global: no closure per attempt.
    local succeeded = pcall(RegisterHook, entry.path, entry.callback)
    if succeeded then
        entry.registered = true
        announce_if_complete()
    elseif entry.attempts < ATTEMPT_LIMIT then
        ExecuteWithDelay(RETRY_DELAY_MS, entry.retry)
    elseif not entry.warned and in_world() then
        -- Once per session, and only from a world: the budget re-arms on every
        -- map load, so exhausting it at a menu is not a fault.
        entry.warned = true
        log(string.format(
            "%s is not installed yet. Expected before a world is loaded -- its target does not "
            .. "exist at the menu -- and it retries on each map load.%s",
            entry.label, entry.note and (" " .. entry.note) or ""))
    end
end

-- path      the UFunction to hook, e.g. "/Script/Pal.PalFoo:Bar"
-- callback  built once by the caller; must capture no per-call state
-- label     what to call it in the log, e.g. "the conveyor extraction hook"
-- note      appended to the gave-up message: what still works without it
local function register(path, callback, label, note)
    local entry = {
        path = path,
        callback = callback,
        label = label or path,
        note = note,
        attempts = 0,
        registered = false,
        warned = false,
    }
    entry.retry = function() attempt(entry) end
    entries[#entries + 1] = entry
    attempt(entry)
end

-- Called from main.lua's RegisterLoadMapPostHook: resets the budget of every
-- registration that has not taken yet and schedules another round.
local function rearm_on_map_load()
    for _, entry in ipairs(entries) do
        if not entry.registered then
            -- The budget resets; entry.warned does not.
            entry.attempts = 0
            ExecuteWithDelay(RETRY_DELAY_MS, entry.retry)
        end
    end
end

return {
    rearm_on_map_load = rearm_on_map_load,
    register = register,
}
