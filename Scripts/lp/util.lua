-- Lootable Passives -- Reflection helpers, logging, and the small predicates everything uses.
--
-- The four _call_/_index_ helpers are built ONCE, at load, and passed by
-- reference. That is deliberate and load-bearing: allocating a closure per
-- invocation of a high-frequency hook produces registry churn that crashes
-- the game.

local SETTINGS = require("settings")

local MOD_NAME = SETTINGS.mod_name

-- SCRIPT_DIRECTORY means the mod's Scripts\ folder, NOT this file's folder.
--
-- This file used to be part of main.lua, where debug.getinfo gave Scripts\
-- directly. Now it lives in Scripts\lp\, so the trailing lp\ has to come back
-- off -- otherwise every path derived from this shifts one level down. The one
-- path that still is: journal.lua walks up from here to find the UE4SS root,
-- where the recovery journal lives.
local SCRIPT_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local SCRIPT_DIRECTORY = SCRIPT_SOURCE:match("^(.*[\\/])") or ""
-- The separator is part of the match and put back, so a parent folder whose
-- name merely ENDS in "lp" -- ".../help/" -- is not mistaken for our own.
SCRIPT_DIRECTORY = SCRIPT_DIRECTORY:gsub("([\\/])[Ll][Pp][\\/]$", "%1")

-- The mod's only log channel, and it is unconditional. What it carries is what
-- a player or a bug report needs: transaction reports, warnings, errors. There
-- is deliberately no second, switchable channel -- the one that used to exist
-- carried one-shot dumps of widget shapes, which answered questions that are
-- now settled and written into the comments beside the code they describe.
local function log(message)
    -- One newline, from print itself. This used to format a trailing \n AND
    -- call print, which double-spaced every line the mod wrote to UE4SS.log.
    print(string.format("[%s] %s", MOD_NAME, message))
end

--------------------------------------------------------------------------------
-- Reflection helpers
--------------------------------------------------------------------------------

-- These four are the mod's hottest code: a single gate pass runs 15-25 of them
-- and the resolve path runs them per passive per Pal per retry. Each therefore
-- uses the ARGUMENT form of pcall against a shared, module-level accessor
-- rather than `pcall(function() ... end)`, which would allocate a fresh closure
-- and a UE4SS registry ref on every call. Same semantics, no allocation.
local function _index_get(value)
    return value.get
end

local function _index_array_num(array)
    return array.GetArrayNum
end

local function _call_is_valid(object)
    return object:IsValid()
end

local function _call_to_string(value)
    return value:ToString()
end

local function _call_is_visible(widget)
    return widget:IsVisible()
end

local function unwrap(value)
    local value_type = type(value)
    if value ~= nil and (value_type == "userdata" or value_type == "table") then
        local has_get, getter = pcall(_index_get, value)
        if has_get and type(getter) == "function" then
            local succeeded, unwrapped = pcall(getter, value)
            if succeeded then
                return unwrapped
            end
        end
    end
    return value
end

local function is_valid(object)
    object = unwrap(object)
    if object == nil then
        return false
    end
    local succeeded, valid = pcall(_call_is_valid, object)
    return succeeded and valid == true
end

local function name_to_string(value)
    value = unwrap(value)
    if value == nil then
        return nil
    end
    local succeeded, result = pcall(_call_to_string, value)
    if succeeded and result ~= nil then
        return result
    end
    return tostring(value)
end

-- A GUID as a comparable string: its four int32s, property reads only, so
-- there is no arity to get wrong.
--
-- It lives here because two GUIDs that come from opposite ends of the engine
-- have to be compared with each other -- OwnerPlayerUId on a Pal's save
-- parameter, and PlayerUId on APalPlayerState -- and neither caller owns the
-- comparison.
--
-- The null GUID returns nil. An unowned Pal and a player state that has not
-- resolved yet both read as all zeroes, and "unknown" must never match
-- "unknown": that would deliver one player's modules to whoever happened to be
-- unresolved at the time.
local function guid_key(guid)
    guid = unwrap(guid)
    if guid == nil then
        return nil
    end
    local key
    pcall(function()
        key = string.format("%d-%d-%d-%d",
            unwrap(guid.A) or 0, unwrap(guid.B) or 0,
            unwrap(guid.C) or 0, unwrap(guid.D) or 0)
    end)
    if key == "0-0-0-0" then
        return nil
    end
    return key
end

local function array_count(array)
    if array == nil then
        return 0
    end
    local count = #array
    local has_method, method = pcall(_index_array_num, array)
    if has_method and type(method) == "function" then
        local succeeded, result = pcall(method, array)
        if succeeded and type(result) == "number" then
            count = result
        end
    end
    return count
end

local function write_lines(path, lines, label)
    if io == nil or type(io.open) ~= "function" then
        log("WARNING: Lua file I/O unavailable; cannot write " .. label .. ".")
        return false
    end
    local opened, handle = pcall(io.open, path, "w")
    if not opened or handle == nil then
        log("WARNING: could not open " .. label .. " for writing.")
        return false
    end
    local wrote = pcall(function()
        for _, line in ipairs(lines) do
            handle:write(line, "\n")
        end
        handle:flush()
        handle:close()
    end)
    return wrote
end

return {
    SCRIPT_DIRECTORY = SCRIPT_DIRECTORY,
    _call_is_visible = _call_is_visible,
    array_count = array_count,
    guid_key = guid_key,
    is_valid = is_valid,
    log = log,
    name_to_string = name_to_string,
    unwrap = unwrap,
    write_lines = write_lines,
}
