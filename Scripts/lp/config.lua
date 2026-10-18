-- Lootable Passives -- The one reader of settings.lua.
--
-- Every getter reads package.loaded["settings"] at the moment it is called, so
-- a value changed while the game runs is seen by the next call. A missing value
-- is its default without comment; a value of the wrong type is logged once per
-- setting and its default used. If settings.lua fails to load, the error is
-- logged and every getter returns its default.

local util = require("lp.util")

local log = util.log

local loaded, load_error = pcall(require, "settings")
if not loaded then
    log("WARNING: settings.lua did not load, so every setting takes its default: "
        .. tostring(load_error))
end

local EMPTY = {}

-- Setting names already reported as the wrong type.
local reported = {}

local function settings_table()
    local settings = package.loaded["settings"]
    if type(settings) == "table" then
        return settings
    end
    return EMPTY
end

-- source[name] when it is of type wanted or nil; otherwise default, logged once
-- under label.
local function typed(source, name, wanted, default, label)
    local value = source[name]
    if value == nil then
        return default
    end
    if type(value) == wanted then
        return value
    end
    if not reported[label] then
        reported[label] = true
        log(string.format("WARNING: setting %s is a %s, not a %s; using %s.",
            label, type(value), wanted, tostring(default)))
    end
    return default
end

local function flag(name, default)
    return typed(settings_table(), name, "boolean", default, name)
end

local function debug_on()
    return flag("debug", false)
end

local function conveyor_on()
    return flag("conveyor_extraction", true)
end

local function gate_on()
    return flag("surgery_ui_gate", true)
end

--------------------------------------------------------------------------------
-- Fault scenarios
--
-- debug_faults is a list of scenarios, one per exchange, used in order. The
-- cursor names the next unused one and starts at 1 at every load of the mod.
-- An exchange is handed the cursor's index when it is captured
-- (peek_scenario), runs each attempt with that scenario active
-- (begin_scenario/end_scenario), and moves the cursor on only once it turns out
-- to be one of this mod's operations (advance_scenario). fault() reads the
-- active scenario, so nothing outside an exchange sees a fault.
--------------------------------------------------------------------------------

-- Every fault settings.lua documents, with its unarmed value.
local FAULT_DEFAULTS = {
    fail_journal_write = "",
    halt_after_journal = "",
    fail_refund = false,
    fail_resolve = false,
}

local cursor = 1
local active, active_index = nil, nil

-- The scenario list, or EMPTY when it is absent or not a table.
local function scenarios()
    return typed(settings_table(), "debug_faults", "table", EMPTY, "debug_faults")
end

-- The cursor's index when debug is on and a scenario table stands there; nil
-- otherwise.
local function peek_scenario()
    if debug_on() and type(scenarios()[cursor]) == "table" then
        return cursor
    end
    return nil
end

-- Makes scenario index active, or none when index is nil, debug is off or no
-- scenario table stands at index.
local function begin_scenario(index)
    active, active_index = nil, nil
    if index ~= nil and debug_on() then
        local scenario = scenarios()[index]
        if type(scenario) == "table" then
            active, active_index = scenario, index
        end
    end
end

local function end_scenario()
    active, active_index = nil, nil
end

-- Moves the cursor past index when it is the cursor's. Returns whether it did.
local function advance_scenario(index)
    if index ~= nil and index == cursor then
        cursor = cursor + 1
        return true
    end
    return false
end

-- The active scenario's value for name, typed as default is; default when no
-- scenario is active or debug is off.
local function fault(name, default)
    if active == nil or not debug_on() then
        return default
    end
    return typed(active, name, type(default), default,
        string.format("debug_faults[%d].%s", active_index, name))
end

-- Scenario index as "name=value" for each fault it arms, sorted and joined by
-- ", "; "no faults" when it arms none, "none" when there is no scenario there.
-- An unknown name is listed with a "?" prefix.
local function describe_scenario(index)
    local scenario = index and scenarios()[index]
    if type(scenario) ~= "table" then
        return "none"
    end
    local armed = {}
    for name, value in pairs(scenario) do
        local default = FAULT_DEFAULTS[name]
        if default == nil then
            armed[#armed + 1] = "?" .. tostring(name) .. "=" .. tostring(value)
        elseif value ~= default then
            armed[#armed + 1] = name .. "=" .. tostring(value)
        end
    end
    table.sort(armed)
    return #armed > 0 and table.concat(armed, ", ") or "no faults"
end

-- One line for the startup log: the scenario count and the next one.
local function describe_plan()
    local count = #scenarios()
    if count == 0 then
        return "no fault scenarios"
    end
    return string.format("%d fault scenario(s); next is %d of %d: %s", count, cursor, count,
        describe_scenario(cursor))
end

-- Logs message with a "DEBUG: " prefix when debug is on.
local function debug_log(message)
    if debug_on() then
        log("DEBUG: " .. message)
    end
end

-- Logs a fired fault with a "DEBUG FAULT: " prefix.
local function fault_log(message)
    log("DEBUG FAULT: " .. message)
end

-- True when the journal row "<state>/<phase>" is the one fail_journal_write
-- names.
local function journal_write_fails(state, phase)
    return fault("fail_journal_write", "") == state .. "/" .. phase
end

-- True when the journal row "<state>/<phase>" is the one halt_after_journal
-- names.
local function journal_write_halts(state, phase)
    return fault("halt_after_journal", "") == state .. "/" .. phase
end

-- The value lp/journal.lua raises to stop an exchange for halt_after_journal,
-- and lp/transaction.lua compares a caught error against.
local HALT = setmetatable({}, {
    __tostring = function() return "debug halt" end,
})

return {
    HALT = HALT,
    advance_scenario = advance_scenario,
    begin_scenario = begin_scenario,
    conveyor_on = conveyor_on,
    debug_log = debug_log,
    debug_on = debug_on,
    describe_plan = describe_plan,
    describe_scenario = describe_scenario,
    end_scenario = end_scenario,
    fault = fault,
    fault_log = fault_log,
    gate_on = gate_on,
    journal_write_fails = journal_write_fails,
    journal_write_halts = journal_write_halts,
    peek_scenario = peek_scenario,
}
