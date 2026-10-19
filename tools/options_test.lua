-- Offline test for lp/options.lua: runtime changes written back into
-- config.lua, and the startup reconciliation with Better Mod Manager.
--
--   lua tools\options_test.lua
--
-- Builds a throwaway Mods\ folder in the system temp directory, with a copy of
-- Scripts\config.lua and, for the second half, a stand-in for Better Mod
-- Manager's modconfig.lua. util.SCRIPT_DIRECTORY is pointed at the copy before
-- lp.options reads it, so the repo's config.lua is never written.
-- REGISTERED, SAVED and SET are globals shared with the stand-in library.
---@diagnostic disable: undefined-global
local TEST_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local TOOLS_DIRECTORY = TEST_SOURCE:match("^(.*[\\/])") or "./"
local SCRIPTS = TOOLS_DIRECTORY .. "../Scripts/"
package.path = SCRIPTS .. "?.lua;" .. package.path

local TEMP_DIRECTORY = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("[\\/]?$", "/")
local MODS = TEMP_DIRECTORY .. "lp_options_test/Mods/"
local MOD_SCRIPTS = MODS .. "LootablePassives/Scripts/"
local BMM_SCRIPTS = MODS .. "BetterModManager/Scripts/"
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function run(command)
    os.execute(command)
end
local function make_directory(path)
    if IS_WINDOWS then
        run('mkdir "' .. path:gsub("/", "\\") .. '" 2>NUL')
    else
        run('mkdir -p "' .. path .. '"')
    end
end
local function read_file(path)
    local handle = io.open(path, "r")
    if handle == nil then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function write_file(path, text)
    local handle = assert(io.open(path, "w"))
    handle:write(text)
    handle:close()
end

local SHIPPED = assert(read_file(SCRIPTS .. "config.lua"))
make_directory(MOD_SCRIPTS)
make_directory(BMM_SCRIPTS)

local LOGGED = {}
local real_print = print
print = function(message)
    LOGGED[#LOGGED + 1] = message
end

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        real_print(string.format("FAIL %-52s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        real_print(string.format("ok   %-52s %s", label, tostring(got)))
    end
end

local util = require("lp.util")
util.SCRIPT_DIRECTORY = MOD_SCRIPTS

-- A fresh lp.options against the throwaway folder, with config.lua as given.
local function fresh_options(config_text)
    write_file(MOD_SCRIPTS .. "config.lua", config_text)
    package.loaded["lp.options"] = nil
    return require("lp.options")
end

local function value_line(text, name)
    return text:match("\n(%s*" .. name .. "%s*=[^\n]*)")
end

-- 1. Without Better Mod Manager: config.lua alone.
os.remove(BMM_SCRIPTS .. "modconfig.lua")
local options = fresh_options(SHIPPED)
options.register_with_bmm()
check("shipped conveyor_extraction", options.conveyor_on(), true)
check("shipped surgery_extraction", options.surgery_on(), true)
check("removal not requested", options.removal_requested(), false)

local heard = {}
options.on_changed(function(name, value) heard[#heard + 1] = name .. "=" .. tostring(value) end)
options.set("conveyor_extraction", false)
check("live value changed", options.conveyor_on(), false)
check("listener heard it", heard[1], "conveyor_extraction=false")
local text = read_file(MOD_SCRIPTS .. "config.lua") or ""
check("line rewritten in place", value_line(text, "conveyor_extraction"),
    "    conveyor_extraction = false,")
check("other lines untouched", select(2, text:gsub("\n", "\n")), select(2, SHIPPED:gsub("\n", "\n")))
check("comments kept", text:find("Set by the host in multiplayer", 1, true) ~= nil, true)
check("no temporary file left", read_file(MOD_SCRIPTS .. "config.lua.tmp"), nil)

options.set("conveyor_extraction", false)
check("same value: no second notification", #heard, 1)
options.set("no_such_setting", true)
options.set("debug", "yes")
check("unknown name or wrong type ignored", #heard, 1)

local debug_value = SHIPPED:match("\n%s*debug%s*=%s*(%a+)")
local flipped = debug_value ~= "true"
options.set("debug", flipped)
text = read_file(MOD_SCRIPTS .. "config.lua")
check("debug rewritten, stage tag kept", value_line(text, "debug"),
    "    debug = " .. tostring(flipped) .. ", -- stage:DebugMode")

options.set("advanced_features", true)
options.set("remove_mod_items", true)
check("removal requested once both are true", options.removal_requested(), true)
options.set("remove_mod_items", false)
check("removal cleared", options.removal_requested(), false)

-- 2. The next start reads what was written back.
options = fresh_options(read_file(MOD_SCRIPTS .. "config.lua"))
check("written value survives a restart", options.conveyor_on(), false)

-- 3. A config.lua that does not load: defaults, and a warning.
LOGGED = {}
options = fresh_options("return {")
check("broken file: default used", options.conveyor_on(), true)
check("broken file: warned", (LOGGED[1] or ""):find("config.lua did not load", 1, true) ~= nil, true)

-- 4. A value of the wrong type: its default, warned once.
LOGGED = {}
options = fresh_options("return { surgery_extraction = 1 }")
check("wrong type: default used", options.surgery_on(), true)
options.surgery_on()
check("wrong type: warned once", #LOGGED, 1)

-- 5. With Better Mod Manager: a stand-in library records the registration and
--    starts with the values in SAVED.
write_file(BMM_SCRIPTS .. "modconfig.lua", [[
return {
    register = function(definition)
        REGISTERED = definition
        local values = {}
        for _, option in ipairs(definition.options) do
            if option.key then values[option.key] = option.default end
        end
        for key, value in pairs(SAVED or {}) do values[key] = value end
        return {
            values = values,
            set = function(key, value) values[key] = value; SET[#SET + 1] = key .. "=" .. tostring(value) end,
        }
    end,
}
]])

-- 5a. A value saved in Better Mod Manager wins over config.lua and is written
--     into it; a config.lua value differing from the default is handed to
--     Better Mod Manager. debug is registered with the file's value as its
--     default, so it is not handed over.
SAVED = { surgery_extraction = false }
SET = {}
local edited = SHIPPED:gsub("(\n%s*surgery_ui_gate%s*=%s*)true", "%1false")
edited = edited:gsub("(\n%s*debug%s*=%s*)%a+", "%1true")
options = fresh_options(edited)
options.register_with_bmm()
check("registered as LootablePassives", REGISTERED and REGISTERED.id, "LootablePassives")
check("no enabledKey", REGISTERED and REGISTERED.enabledKey, nil)
check("folder is the mod folder", (REGISTERED and REGISTERED.folder or ""):match("[\\/]([^\\/]+)$"),
    "LootablePassives")
check("saved value wins", options.surgery_on(), false)
check("saved value written into config.lua",
    value_line(read_file(MOD_SCRIPTS .. "config.lua"), "surgery_extraction"),
    "    surgery_extraction = false,")
check("file edit handed to Better Mod Manager", table.concat(SET, ","), "surgery_ui_gate=false")
check("file edit kept live", options.gate_on(), false)
check("debug from the file, not handed over", options.debug_on(), true)

-- 5b. Every option has its shipped default, and the removal depends on the
--     advanced switch.
local by_key = {}
for _, option in ipairs(REGISTERED.options) do
    if option.key then by_key[option.key] = option end
end
check("debug default is the file's value", by_key.debug and by_key.debug.default, true)
check("surgery default is the shipped one", by_key.surgery_ui_gate
    and by_key.surgery_ui_gate.default, true)
check("conveyor default is true", by_key.conveyor_extraction and by_key.conveyor_extraction.default,
    true)
check("removal depends on advanced",
    by_key.remove_mod_items and by_key.remove_mod_items.dependsOn, "advanced_features")
local longest = 0
for _, option in pairs(by_key) do
    longest = math.max(longest, #(option.description or ""))
end
check("descriptions at most 110 characters", longest <= 110, true)

-- 5c. Better Mod Manager's onChange applies and writes back; set() hands the
--     mod's own change to Better Mod Manager.
REGISTERED.onChange("conveyor_extraction", false)
check("onChange applied", options.conveyor_on(), false)
check("onChange written back",
    value_line(read_file(MOD_SCRIPTS .. "config.lua"), "conveyor_extraction"),
    "    conveyor_extraction = false,")
SET = {}
options.set("advanced_features", true)
check("set handed to Better Mod Manager", table.concat(SET, ","), "advanced_features=true")

-- 5d. debug turned off in Better Mod Manager during a dev build wins over the
--     build's true, and is written into config.lua.
SAVED = { debug = false }
SET = {}
options = fresh_options(SHIPPED:gsub("(\n%s*debug%s*=%s*)%a+", "%1true"))
options.register_with_bmm()
check("saved debug off wins over the build's on", options.debug_on(), false)
check("saved debug off written into config.lua",
    value_line(read_file(MOD_SCRIPTS .. "config.lua"), "debug"),
    "    debug = false, -- stage:DebugMode")
check("nothing handed over", table.concat(SET, ","), "")

-- 6. Debug builds: an edit to config.lua while the game runs is applied at the
--    next poll. The scheduler is a stand-in that runs one poll per call.
os.remove(BMM_SCRIPTS .. "modconfig.lua")
local SCHEDULED = {}
function ExecuteInGameThreadWithDelay(_, fn) SCHEDULED[#SCHEDULED + 1] = fn end
local function run_one_poll()
    local pending = SCHEDULED
    SCHEDULED = {}
    for _, fn in ipairs(pending) do fn() end
end
local debug_on_text = SHIPPED:gsub("(\n%s*debug%s*=%s*)%a+", "%1true")
options = fresh_options(debug_on_text)
heard = {}
options.on_changed(function(name, value) heard[#heard + 1] = name .. "=" .. tostring(value) end)
options.watch_file()
check("watch: a poll is scheduled", #SCHEDULED, 1)
run_one_poll()
check("watch: an unchanged file changes nothing", #heard, 0)
write_file(MOD_SCRIPTS .. "config.lua",
    debug_on_text:gsub("(\n%s*surgery_extraction%s*=%s*)true", "%1false"))
run_one_poll()
check("watch: the edit is applied", options.surgery_on(), false)
check("watch: listeners heard it", table.concat(heard, ","), "surgery_extraction=false")
write_file(MOD_SCRIPTS .. "config.lua", "return {")
run_one_poll()
check("watch: a broken edit is ignored", options.surgery_on(), false)
write_file(MOD_SCRIPTS .. "config.lua", debug_on_text:gsub("(\n%s*debug%s*=%s*)true", "%1false"))
run_one_poll()
check("watch: debug turned off in the file", options.debug_on(), false)
run_one_poll()
check("watch: stops once debug is off", #SCHEDULED, 0)
ExecuteInGameThreadWithDelay = nil

os.remove(MOD_SCRIPTS .. "config.lua")
os.remove(BMM_SCRIPTS .. "modconfig.lua")

print = real_print
print(failures == 0 and "\nALL PASS" or string.format("\n%d FAILED", failures))
os.exit(failures == 0 and 0 or 1)
