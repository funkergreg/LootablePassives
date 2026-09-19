-- luacheck config for this repo.
-- The mod runs inside UE4SS's embedded Lua 5.4, which injects a set of
-- globals (hooking, object lookup, threading) that no stock luacheck std
-- knows about. Without this list every UE4SS API call reads as an
-- "undefined variable" warning, burying the warnings that are real.
std = "lua54"

globals = {
    -- Hook registration
    "RegisterHook",
    "RegisterLoadMapPostHook",
    "UnregisterHook",
    "NotifyOnNewObject",

    -- Threading / scheduling
    "ExecuteInGameThread",
    "ExecuteWithDelay",
    "ExecuteAsync",
    "LoopAsync",

    -- Object lookup / construction
    "FindAllOf",
    "FindFirstOf",
    "StaticFindObject",
    "StaticConstructObject",
    "CreateInvalidObject",
    "FName",
    "UEHelpers",

    -- Misc UE4SS globals
    "UnrealVersion",
    "RegisterConsoleCommandHandler",
    "RegisterKeyBind",
}

max_line_length = 120

-- Field access into helper module tables (ids.X, inventory.X, journal.X, ...)
-- reads the module name again as a local in call sites; luacheck reports
-- that as upvalue shadowing even though it's an intentional destructure.
ignore = {
    "421", -- shadowing a local variable
    "431", -- shadowing an upvalue
}
