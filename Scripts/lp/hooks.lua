-- Lootable Passives -- One bounded, re-armed hook registrar.
--
-- Every hook the mod registers goes through here. Coalescing a hook that fires
-- at frame rate is not here; that is lp/util.lua's coalescer().
--
-- Each registration names its half: "ui" or "server". A /Script/ path is
-- attempted at once. A /Game/ path is a Blueprint, which does not exist until a
-- world has loaded, so it is attempted only from arm(), and only when the role
-- has a UI: a dedicated server never attempts one.
--
-- Four properties of the shape below are deliberate:
--
--   * Retries are BOUNDED.
--   * The callback is built once, by the caller, at load, and must capture no
--     per-call state.
--   * One retry closure per registration, built at registration time, not one
--     per attempt.
--   * A fresh retry budget each time arm() runs.

local util = require("lp.util")

local log = util.log

-- 90 attempts at 1 s. The budget has to outlast a world load, which varies by
-- tens of seconds; exhausting it produces only a warning about a hook that
-- installs on the next map load. entry.retry is built once per registration, so
-- an attempt allocates nothing and a long budget is cheap.
local ATTEMPT_LIMIT = 90
local RETRY_DELAY_MS = 1000

-- Every registration made through this module, so arm() can re-arm them.
local entries = {}

-- The halves the current role runs, set by arm(); nil until the first arm().
local active = nil

local announced = false

local function counts(entry)
    return active ~= nil and active[entry.half] == true
end

-- One line, when every registration of the current role's halves has landed.
-- Waits for the first arm(), since which hooks count depends on the role.
local function announce_if_complete()
    if announced or active == nil then
        return
    end
    local installed = {}
    for _, entry in ipairs(entries) do
        if counts(entry) and not entry.disabled then
            if not entry.registered then
                return
            end
            installed[#installed + 1] = entry.label
        end
    end
    announced = true
    log(string.format("All %d hooks installed: %s.", #installed, table.concat(installed, ", ")))
end

-- Schedules entry.retry, unless one is already scheduled. entry.pending is what
-- keeps a registration to one retry chain however often arm() re-arms it.
local function schedule_retry(entry)
    if entry.pending then
        return
    end
    entry.pending = true
    ExecuteInGameThreadWithDelay(RETRY_DELAY_MS, entry.retry)
end

-- Argument-form pcall against the global: no closure per attempt. The post
-- argument is passed only when there is one. Returns pcall's results: whether
-- it succeeded, then RegisterHook's PreId and PostId.
local function register_now(entry)
    if entry.post ~= nil then
        return pcall(RegisterHook, entry.path, entry.callback, entry.post)
    end
    return pcall(RegisterHook, entry.path, entry.callback)
end

local function attempt(entry)
    entry.pending = false
    if entry.registered or entry.disabled then
        return
    end
    entry.attempts = entry.attempts + 1
    local succeeded, pre_id, post_id = register_now(entry)
    if succeeded then
        entry.registered = true
        entry.pre_id = pre_id
        entry.post_id = post_id
        announce_if_complete()
    elseif entry.attempts < ATTEMPT_LIMIT then
        schedule_retry(entry)
    elseif not entry.warned then
        -- Once per session; the budget re-arms on every arm().
        entry.warned = true
        log(string.format(
            "%s is not installed after %d attempts; it is retried on the next map load.%s",
            entry.label, ATTEMPT_LIMIT, entry.note and (" " .. entry.note) or ""))
    end
end

-- Attempts entry now when it may be: a /Script/ path always, a /Game/ path
-- once arm() has seen a role with a UI.
local function attempt_if_ready(entry)
    if not entry.blueprint or (active ~= nil and active.ui) then
        attempt(entry)
    end
end

-- spec.path      the UFunction to hook, e.g. "/Script/Pal.PalFoo:Bar"
-- spec.callback  built once by the caller; must capture no per-call state. For
--                a /Script/ path it runs before the function; for a /Game/
--                path, after it
-- spec.post      optional, /Script/ paths only: runs after the function
-- spec.half      "ui" or "server": which roles count it in the installed line
-- spec.label     what to call it in the log, e.g. "the conveyor extraction hook"
-- spec.note      appended to the gave-up message: what still works without it
--
-- Returns the registration, for set_enabled.
local function register(spec)
    local entry = {
        path = spec.path,
        callback = spec.callback,
        post = spec.post,
        half = spec.half,
        label = spec.label,
        note = spec.note,
        blueprint = spec.path:sub(1, 6) == "/Game/",
        attempts = 0,
        registered = false,
        disabled = false,
        pending = false,
        warned = false,
    }
    entry.retry = function() attempt(entry) end
    entries[#entries + 1] = entry
    attempt_if_ready(entry)
    return entry
end

-- Disabled: UnregisterHook with the ids RegisterHook returned, if it is
-- registered, and no further attempts. Enabled: a fresh budget, attempted at
-- once when it may be. Does nothing when the state already matches.
--
-- Must not be called from inside the hook being unregistered; schedule it.
local function set_enabled(entry, enabled)
    if enabled ~= entry.disabled then
        return
    end
    entry.disabled = not enabled
    if enabled then
        entry.attempts = 0
        attempt_if_ready(entry)
        return
    end
    if entry.registered then
        local succeeded, raised = pcall(UnregisterHook, entry.path, entry.pre_id, entry.post_id)
        if succeeded then
            entry.registered = false
            entry.pre_id, entry.post_id = nil, nil
        else
            log(string.format("WARNING: could not remove %s: %s", entry.label, tostring(raised)))
        end
    end
end

-- Called once the role of a newly entered world is known. Records which halves
-- count, then resets the budget of every registration of those halves that has
-- not taken yet and schedules another round. A chain already running keeps
-- running on the fresh budget rather than gaining a second.
local function arm(has_ui, is_authority)
    active = { ui = has_ui, server = is_authority }
    for _, entry in ipairs(entries) do
        if not entry.registered and not entry.disabled and counts(entry) then
            -- The budget resets; entry.warned does not.
            entry.attempts = 0
            schedule_retry(entry)
        end
    end
    announce_if_complete()
end

return {
    arm = arm,
    register = register,
    set_enabled = set_enabled,
}
