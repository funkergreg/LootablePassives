-- Lootable Passives -- The one reader of Scripts/config.lua, and the Better Mod
-- Manager registration.
--
-- config.lua is read once, at load, into the live table. Every getter reads the
-- live table when it is called, so a value changed while the game runs is seen
-- by the next call. A missing value is its default without comment; a value of
-- the wrong type is logged once per setting and its default used. If config.lua
-- fails to load, the error is logged and every getter returns its default.
--
-- A value changes at runtime through Better Mod Manager's onChange, or through
-- set(), the mod's own. Either way it is written into the installed config.lua
-- (only that key's value, on its own line), set() also hands it to Better Mod
-- Manager, and the on_changed listeners run.

local util = require("lp.util")

local log = util.log
local read_lines = util.read_lines
local replace_file = util.replace_file

local CONFIG_PATH = util.SCRIPT_DIRECTORY .. "config.lua"
local BMM_LIBRARY = util.SCRIPT_DIRECTORY .. "../../BetterModManager/Scripts/modconfig.lua"
local BMM_ID = "LootablePassives"

-- Every setting, with the default the mod ships, which also fixes its type.
local DEFAULTS = {
    surgery_extraction = true,
    conveyor_extraction = true,
    surgery_ui_gate = true,
    debug = false,
    advanced_features = false,
    remove_mod_items = false,
}

local EMPTY = {}

local loaded, file_values = pcall(dofile, CONFIG_PATH)
if not loaded or type(file_values) ~= "table" then
    log("WARNING: config.lua did not load, so every setting takes its default: "
        .. tostring(loaded and "it did not return a table" or file_values))
    file_values = EMPTY
end

-- The settings as the mod uses them: config.lua's values, then each change.
local live = {}
for name, value in pairs(file_values) do
    live[name] = value
end

-- Setting names already reported as the wrong type.
local reported = {}

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

local function flag(name)
    return typed(live, name, "boolean", DEFAULTS[name], name)
end

local function debug_on()
    return flag("debug")
end

local function conveyor_on()
    return flag("conveyor_extraction")
end

local function gate_on()
    return flag("surgery_ui_gate")
end

local function surgery_on()
    return flag("surgery_extraction")
end

local function advanced_on()
    return flag("advanced_features")
end

-- True while both advanced_features and remove_mod_items are true.
local function removal_requested()
    return advanced_on() and flag("remove_mod_items")
end

-- Logs message with a "DEBUG: " prefix when debug is on.
local function debug_log(message)
    if debug_on() then
        log("DEBUG: " .. message)
    end
end

--------------------------------------------------------------------------------
-- Runtime changes
--------------------------------------------------------------------------------

-- Rewrites the value on each line of the installed config.lua that assigns
-- true or false to a key in changes, keeping everything else on the line and
-- every other line. Writes nothing when no line changes. Returns whether the
-- file now holds the values; logs one warning when it does not.
local function write_back(changes)
    local lines = read_lines(CONFIG_PATH)
    if lines == nil then
        log("WARNING: config.lua could not be read, so a changed setting is not saved; it "
            .. "applies until the game closes.")
        return false
    end
    local rewritten = false
    for index, line in ipairs(lines) do
        local indent, name, assign, value, rest =
            line:match("^(%s*)([%a_][%w_]*)(%s*=%s*)(%a+)(.*)$")
        local wanted = nil
        if name ~= nil then
            wanted = changes[name]
        end
        if wanted ~= nil and (value == "true" or value == "false")
            and value ~= tostring(wanted)
        then
            lines[index] = indent .. name .. assign .. tostring(wanted) .. rest
            rewritten = true
        end
    end
    if not rewritten then
        return true
    end
    if replace_file(CONFIG_PATH, lines, "config.lua") then
        return true
    end
    log("WARNING: a changed setting could not be saved into config.lua; it applies until the "
        .. "game closes.")
    return false
end

local listeners = {}

-- listener(name, value) runs after each runtime change of a setting. Register
-- at load.
local function on_changed(listener)
    listeners[#listeners + 1] = listener
end

-- Better Mod Manager's handle, once registered.
---@type table|nil
local bmm = nil

-- Applies one boolean setting: the live table, then config.lua, then the
-- listeners. Does nothing for an unknown name, a non-boolean value, or a value
-- the setting already has. Logs the change as a DEBUG line when debug is on
-- before or after it, so turning debug itself off is logged too.
local function change(name, value)
    if DEFAULTS[name] == nil or type(value) ~= "boolean" or flag(name) == value then
        return
    end
    local was_debug = debug_on()
    live[name] = value
    if was_debug or debug_on() then
        log(string.format("DEBUG: Setting %s is now %s.", name, tostring(value)))
    end
    write_back({ [name] = value })
    for _, listener in ipairs(listeners) do
        local succeeded, raised = pcall(listener, name, value)
        if not succeeded then
            log("ERROR: reacting to a setting change raised a Lua error: " .. tostring(raised))
        end
    end
end

--------------------------------------------------------------------------------
-- Debug builds: config.lua edits while the game runs
--------------------------------------------------------------------------------
--
-- While debug is on, config.lua is read again every CONFIG_POLL_MS, and each
-- setting whose value in the file differs from the live one goes through
-- change(), as a Better Mod Manager change would. That is how a dedicated
-- server's settings are changed without a restart in a dev build, which the
-- loader reinstalls, with config.lua's defaults, at every launch.

local CONFIG_POLL_MS = 5000

local last_text = nil

local function read_text()
    local lines = read_lines(CONFIG_PATH)
    return lines and table.concat(lines, "\n") or nil
end

local schedule_poll

local function poll_file()
    if not debug_on() then
        debug_log("config.lua is no longer watched: debug is off")
        return
    end
    local text = read_text()
    if text ~= nil and text ~= last_text then
        last_text = text
        local chunk = load(text, "config.lua", "t", {})
        local succeeded, values = false, nil
        if chunk ~= nil then
            succeeded, values = pcall(chunk)
        end
        if succeeded and type(values) == "table" then
            for name in pairs(DEFAULTS) do
                local value = values[name]
                if type(value) == "boolean" and value ~= flag(name) then
                    debug_log(string.format("config.lua was edited: %s = %s", name,
                        tostring(value)))
                    change(name, value)
                end
            end
        else
            debug_log("config.lua was edited but does not load; its values are not applied")
        end
    end
    schedule_poll()
end

-- Starts the watch when debug is on. Called once, from main.lua, after its
-- on_changed listeners are registered.
local function watch_file()
    if not debug_on() then
        return
    end
    schedule_poll = schedule_poll or util.coalescer(poll_file, CONFIG_POLL_MS)
    last_text = read_text()
    debug_log(string.format("config.lua is watched for edits every %d ms: %s", CONFIG_POLL_MS,
        CONFIG_PATH))
    schedule_poll()
end

-- The mod's own change of a setting, as change() does it, and handed to Better
-- Mod Manager when it is registered so its menu and saved values follow.
local function set(name, value)
    change(name, value)
    if bmm ~= nil and flag(name) == value then
        pcall(bmm.set, name, value)
    end
end

--------------------------------------------------------------------------------
-- Better Mod Manager
--------------------------------------------------------------------------------

local function option(name, label, description, depends_on)
    return {
        key = name,
        type = "toggle",
        label = label,
        description = description,
        default = DEFAULTS[name],
        dependsOn = depends_on,
    }
end

local OPTIONS = {
    { type = "header", label = "Extraction" },
    option("surgery_extraction", "Surgery extraction",
        "Extract One, Extract All and this mod's implants at the Surgery Table. Set by the "
        .. "host in multiplayer."),
    option("conveyor_extraction", "Conveyor extraction",
        "Pals fed to the Disassembly Conveyor also yield implants of their passives. "
        .. "Set by the host in multiplayer."),
    { type = "header", label = "Troubleshooting" },
    option("surgery_ui_gate", "Surgery button check",
        "Blocks the Edit button when the operation cannot work. Turn off if the Surgery "
        .. "screen misbehaves."),
    option("debug", "Debug logging",
        "Adds DEBUG lines to UE4SS.log. Leave off unless reporting a bug."),
    { type = "header", label = "Host tools" },
    option("advanced_features", "Enable advanced features",
        "Unlocks Remove all mod items, below."),
    option("remove_mod_items", "Remove all mod items",
        "WARNING: destructive. Required before uninstalling. Takes about 25 s, shows a "
        .. "notice, then turns off.", "advanced_features"),
}

-- The mod's folder: the parent of Scripts\.
local function mod_folder()
    return util.SCRIPT_DIRECTORY:match("^(.*)[\\/][^\\/]+[\\/]$") or util.SCRIPT_DIRECTORY
end

-- Each setting's value from the two sources at startup. A value Better Mod
-- Manager has saved (one that differs from its registered default) wins, and
-- is written into config.lua. Otherwise a config.lua value that differs from
-- the registered default is handed to Better Mod Manager.
---@param handle table
local function reconcile(handle)
    local changes = {}
    for _, entry in ipairs(OPTIONS) do
        local name, default = entry.key, entry.default
        if name ~= nil then
            local saved = handle.values[name]
            local current = flag(name)
            if type(saved) == "boolean" and saved ~= default then
                if saved ~= current then
                    live[name] = saved
                    changes[name] = saved
                end
            elseif current ~= default then
                pcall(handle.set, name, current)
            end
        end
    end
    if next(changes) ~= nil then
        write_back(changes)
    end
end

-- Registers with Better Mod Manager when it is installed, and reconciles the
-- two sources once. Without it, does nothing: config.lua alone controls the
-- mod. Called once, at load, before any setting is read.
local function register_with_bmm()
    local library = loadfile(BMM_LIBRARY)
    if library == nil then
        debug_log("Better Mod Manager is not installed; config.lua alone controls the settings.")
        return
    end
    local loaded_library, module = pcall(library)
    if not loaded_library or type(module) ~= "table" or type(module.register) ~= "function" then
        log("WARNING: Better Mod Manager's library did not load, so the settings are not in its "
            .. "menu: " .. tostring(module))
        return
    end
    -- Each option was built with its shipped default from DEFAULTS. debug is
    -- registered with this build's config.lua value as read at load instead (true
    -- in a dev build, false in a release). Better Mod Manager shows that value
    -- and saves only a change from it.
    for _, entry in ipairs(OPTIONS) do
        if entry.key == "debug" then
            entry.default = flag("debug")
        end
    end
    local registered, handle = pcall(module.register, {
        id = BMM_ID,
        name = "Lootable Passives",
        description = "Turns Pal passives into Disposable Implants at the Pal Surgery Table and "
            .. "the Disassembly Conveyor.",
        folder = mod_folder(),
        options = OPTIONS,
        onChange = change,
    })
    if not registered or type(handle) ~= "table" then
        log("WARNING: registering with Better Mod Manager failed, so the settings are not in its "
            .. "menu: " .. tostring(handle))
        return
    end
    bmm = handle
    reconcile(handle)
end

--------------------------------------------------------------------------------
-- Fault scenarios
--
-- debug_faults is a list of scenarios. Each names the operation kind it waits
-- for in its "on" field -- "one", "all" or "implant", as lp/ids.lua's
-- EXTRACTION_MODES values -- and an exchange of that kind claims the first
-- unused scenario for it once the exchange is known to be this mod's
-- (claim_scenario). A scenario with no "on" matches any kind. Each is used once
-- per load of the mod. The exchange runs each attempt with its scenario active
-- (begin_scenario/end_scenario); fault() reads the active scenario, so nothing
-- outside an exchange sees a fault.
--------------------------------------------------------------------------------

-- Every fault lp/faults.lua documents, with its unarmed value.
local FAULT_DEFAULTS = {
    fail_journal_write = "",
    halt_after_journal = "",
    fail_refund = false,
    fail_resolve = false,
}

-- The values "on" may take.
local KINDS = { one = true, all = true, implant = true }

-- Scenario index -> true once claimed.
local used = {}
local active, active_index = nil, nil

-- The scenario list from lp/faults.lua, or EMPTY when it did not load or is not
-- a table.
local loaded_faults, fault_list = pcall(require, "lp.faults")
if not loaded_faults then
    fault_list = EMPTY
elseif type(fault_list) ~= "table" then
    log("WARNING: lp/faults.lua returned a " .. type(fault_list) .. ", not a table; using no "
        .. "scenarios.")
    fault_list = EMPTY
end

-- Claims and returns the index of the first unused scenario whose "on" is mode
-- or absent, when debug is on; nil when there is none.
local function claim_scenario(mode)
    if not debug_on() then
        return nil
    end
    for index, scenario in ipairs(fault_list) do
        if not used[index] and type(scenario) == "table"
            and (scenario.on == nil or scenario.on == mode)
        then
            used[index] = true
            return index
        end
    end
    return nil
end

-- Makes scenario index active, or none when index is nil, debug is off or no
-- scenario table stands at index.
local function begin_scenario(index)
    active, active_index = nil, nil
    if index ~= nil and debug_on() then
        local scenario = fault_list[index]
        if type(scenario) == "table" then
            active, active_index = scenario, index
        end
    end
end

local function end_scenario()
    active, active_index = nil, nil
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

-- Scenario index as "on <kind>: name=value, ...", the faults sorted; "no
-- faults" in place of the list when it arms none, "none" when there is no
-- scenario there. An unknown fault name, or an "on" that is not a kind, is
-- listed with a "?" prefix.
local function describe_scenario(index)
    local scenario = index and fault_list[index]
    if type(scenario) ~= "table" then
        return "none"
    end
    local armed = {}
    for name, value in pairs(scenario) do
        local default = FAULT_DEFAULTS[name]
        if name ~= "on" then
            if default == nil then
                armed[#armed + 1] = "?" .. tostring(name) .. "=" .. tostring(value)
            elseif value ~= default then
                armed[#armed + 1] = name .. "=" .. tostring(value)
            end
        end
    end
    table.sort(armed)
    local on = scenario.on
    local kind = on == nil and "any" or (KINDS[on] and on or "?" .. tostring(on))
    return string.format("on %s: %s", kind, #armed > 0 and table.concat(armed, ", ") or "no faults")
end

-- One line for the startup log: every scenario with its index, and which are
-- used.
local function describe_plan()
    local list = fault_list
    if #list == 0 then
        return "no fault scenarios"
    end
    local parts = {}
    for index = 1, #list do
        parts[index] = string.format("%d (%s%s)", index, describe_scenario(index),
            used[index] and ", used" or "")
    end
    return string.format("%d fault scenario(s): %s", #list, table.concat(parts, "; "))
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
    begin_scenario = begin_scenario,
    claim_scenario = claim_scenario,
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
    on_changed = on_changed,
    register_with_bmm = register_with_bmm,
    removal_requested = removal_requested,
    set = set,
    surgery_on = surgery_on,
    watch_file = watch_file,
}
