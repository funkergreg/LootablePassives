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

local log = util.log

local ATTEMPT_LIMIT = 12
local RETRY_DELAY_MS = 1000

-- Every registration made through this module, so map load can re-arm them.
local entries = {}

local function attempt(entry)
    if entry.registered then
        return
    end
    entry.attempts = entry.attempts + 1
    -- Argument-form pcall against the global: no closure allocated per attempt.
    local succeeded = pcall(RegisterHook, entry.path, entry.callback)
    if succeeded then
        entry.registered = true
        log(string.format("Installed %s.", entry.label))
    elseif entry.attempts < ATTEMPT_LIMIT then
        ExecuteWithDelay(RETRY_DELAY_MS, entry.retry)
    elseif not entry.warned then
        entry.warned = true
        log(string.format(
            "Note: %s is not hookable yet (its target is not loaded on this map); "
            .. "gave up after %d attempts and will try again on the next map load.",
            entry.label, ATTEMPT_LIMIT))
    end
end

-- path      the UFunction to hook, e.g. "/Script/Pal.PalFoo:Bar"
-- callback  built once by the caller; must capture no per-call state
-- label     what to call it in the log, e.g. "the conveyor extraction hook"
local function register(path, callback, label)
    local entry = {
        path = path,
        callback = callback,
        label = label or path,
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
            entry.attempts = 0
            entry.warned = false
            ExecuteWithDelay(RETRY_DELAY_MS, entry.retry)
        end
    end
end

return {
    rearm_on_map_load = rearm_on_map_load,
    register = register,
}
