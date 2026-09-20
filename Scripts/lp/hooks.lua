-- Lootable Passives -- One bounded, re-armed hook registrar.
--
-- main.lua still carries two hand-rolled copies of this pattern. This is the
-- single implementation; the conveyor uses it so that there is not a third.
-- The two in main.lua should move here once the conveyor has been confirmed in
-- game and all three can be exercised in one session -- not before, because
-- that code is load-bearing and currently works.
--
-- The shape is load-bearing, not incidental. Every part of it is the settled
-- answer to the 0xffffffffffffffff access violation:
--
--   * Retries are BOUNDED. An unbounded 1-second retry against a path that
--     never resolves allocates a Lua closure and a UE4SS registry ref every
--     second, forever. That churn is what crashed the game.
--   * The hook callback is built ONCE, by the caller, at load. Same reason.
--     A callback passed here must not capture per-call state.
--   * One retry closure per registration, built here at registration time --
--     not one per attempt.
--   * A fresh retry budget PER MAP. The target only exists once a map that can
--     reach it has loaded, so exhausting the budget on the splash, login or
--     title map must not disable the hook for the rest of the session.

local util = require("lp.util")

local is_valid = util.is_valid
local log = util.log

-- Sized against the measured world-load time, not guessed. A widget hook's
-- Blueprint does not exist until a world is up, and the wait for one is both
-- long and VARIABLE: 19s on one startup, 25.6s on the next, on the same
-- machine. A 12-attempt budget at 1s exhausted before the target could
-- possibly appear, on every single startup, and warned about it; 30 then came
-- within 4s of doing the same. So the budget is set well past the slowest
-- observed load rather than just past the last one, because the only thing
-- exhausting it produces is a false warning about a hook that installs fine on
-- the next map load.
--
-- Still BOUNDED, but the bound is now cheap. entry.retry is built ONCE per
-- registration, so an attempt allocates nothing -- the per-attempt closure that
-- was the registry churn behind the 0xffffffffffffffff crash is gone, and the
-- cost of a longer budget is one pcall per second while a world loads.
local ATTEMPT_LIMIT = 90
local RETRY_DELAY_MS = 1000

-- Every registration made through this module, so map load can re-arm them.
local entries = {}

-- Reported as ONE line when the last hook lands, not four as they trickle in.
-- Two register at mod load (native functions exist from process start) and two
-- only once a world brings their widget Blueprints up, so the naive version
-- scattered four lines across twenty seconds of startup.
local announced = false

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

-- Are we actually in a world?
--
-- A widget hook cannot install on the splash, login or title maps, and saying
-- so there reads as a fault when it is the normal state of affairs. The warning
-- is worth having only if the hook is still missing once there is a world to
-- host it.
local function in_world()
    local character = nil
    pcall(function() character = FindFirstOf("PalPlayerCharacter") end)
    -- is_valid, not ~= nil. FindFirstOf can return a stale or default object
    -- that is non-nil and unusable, which is how this test wrongly reported
    -- "in world" from the title screen and fired the warning it exists to
    -- suppress. Every other object check in this mod uses is_valid; this one
    -- skipped it.
    return is_valid(character)
end

local function attempt(entry)
    if entry.registered then
        return
    end
    entry.attempts = entry.attempts + 1
    -- Argument-form pcall against the global: no closure allocated per attempt.
    local succeeded = pcall(RegisterHook, entry.path, entry.callback)
    if succeeded then
        entry.registered = true
        announce_if_complete()
    elseif entry.attempts < ATTEMPT_LIMIT then
        ExecuteWithDelay(RETRY_DELAY_MS, entry.retry)
    elseif not entry.warned and in_world() then
        -- Once per SESSION, not once per map, and never from a menu. Both
        -- conditions matter: RegisterLoadMapPostHook fires on the splash, login
        -- and title maps, where a widget hook CANNOT install and saying so is
        -- just alarming. Staying silent there costs nothing -- the budget
        -- re-arms on the next map load and the hook installs when the world
        -- appears.
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
-- note, when given, is appended to the gave-up message: what still works
-- without this hook, so the line reports a degraded mode rather than a fault.
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
    return entry
end

-- Called from main.lua's RegisterLoadMapPostHook. Gives every registration that
-- has not taken yet a fresh budget, and schedules one more round of attempts.
local function rearm_on_map_load()
    for _, entry in ipairs(entries) do
        if not entry.registered then
            -- The retry BUDGET resets; the warning does not.
            entry.attempts = 0
            ExecuteWithDelay(RETRY_DELAY_MS, entry.retry)
        end
    end
end

return {
    rearm_on_map_load = rearm_on_map_load,
    register = register,
}
