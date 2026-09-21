-- Lootable Passives -- Reflection helpers, logging, file access, and the small
-- predicates everything uses.
--
-- The _call_/_index_ helpers are module-level functions passed to pcall by
-- reference, never `pcall(function() ... end)`. field() and method() are the
-- general form.

local SETTINGS = require("settings")

local MOD_NAME = SETTINGS.mod_name

-- The mod's Scripts\ folder, not this file's folder: the trailing lp\ is
-- stripped. The separator is matched and put back, so a parent folder whose name
-- merely ends in "lp" is not stripped too.
local SCRIPT_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local SCRIPT_DIRECTORY = SCRIPT_SOURCE:match("^(.*[\\/])") or ""
SCRIPT_DIRECTORY = SCRIPT_DIRECTORY:gsub("([\\/])[Ll][Pp][\\/]$", "%1")

-- Where the mod's runtime files go: the UE4SS root, not Scripts\.
--
-- Scripts\ is inside the tree the mod loader replaces on a Version change, so a
-- file written there does not survive an update. Falls back to SCRIPT_DIRECTORY
-- if the path does not contain a UE4SS folder.
--
-- Derived once, here, because the journal and the ledger must agree on it.
local UE4SS_ROOT = SCRIPT_DIRECTORY:match("^(.*[\\/]UE4SS[\\/])") or SCRIPT_DIRECTORY

-- The mod's only log channel, and it is unconditional. There is no second,
local function log(message)
    -- print supplies the newline. Do not format one in as well.
    print(string.format("[%s] %s", MOD_NAME, message))
end

--------------------------------------------------------------------------------
-- Reflection helpers
--------------------------------------------------------------------------------

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

-- The key is an argument to these two, which is what lets field() and method()
-- cover every property name without a helper each.
local function _index_key(object, key)
    return object[key]
end

local function _call_key(object, key)
    return object[key](object)
end

-- Read one property off an engine object, or call one of its zero-argument
-- methods. A read or call that raises returns nil. Neither unwraps the result.
--
-- method() IS FOR ZERO-ARGUMENT CALLS ONLY. Anything taking arguments stays
-- written out at its call site, where its arity is visible next to it.
local function field(object, key)
    if object == nil then
        return nil
    end
    local succeeded, value = pcall(_index_key, object, key)
    if not succeeded then
        return nil
    end
    return value
end

local function method(object, key)
    if object == nil then
        return nil
    end
    local succeeded, value = pcall(_call_key, object, key)
    if not succeeded then
        return nil
    end
    return value
end

-- Calls :get() on a UE4SS parameter wrapper and returns the result; returns the
-- value unchanged if it has no getter.
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

-- UE4SS's own IsValid(), through unwrap. False for nil and for a call that
-- raises.
local function is_valid(object)
    object = unwrap(object)
    if object == nil then
        return false
    end
    local succeeded, valid = pcall(_call_is_valid, object)
    return succeeded and valid == true
end

-- FName:ToString(), falling back to tostring(). Prefer to use this for every FName.
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

-- An FGuid as a comparable string, from its four int32s. Property reads only.
--
-- Returns nil for the null GUID, so two unresolved GUIDs never compare equal.
--
-- Lives here because the two GUIDs it is used on come from different places --
-- OwnerPlayerUId on a Pal's SaveParameter, PlayerUId on APalPlayerState -- and
-- lp/ledger.lua compares them against each other.
local function _guid_parts(guid)
    return unwrap(guid.A), unwrap(guid.B), unwrap(guid.C), unwrap(guid.D)
end

local function guid_key(guid)
    guid = unwrap(guid)
    if guid == nil then
        return nil
    end
    local succeeded, a, b, c, d = pcall(_guid_parts, guid)
    if not succeeded then
        return nil
    end
    local key = string.format("%d-%d-%d-%d", a or 0, b or 0, c or 0, d or 0)
    if key == "0-0-0-0" then
        return nil
    end
    return key
end

-- Length of a TArray, from GetArrayNum() where the array has one and from # if
-- not.
local function array_count(array)
    if array == nil then
        return 0
    end
    local count = #array
    local has_num, get_num = pcall(_index_array_num, array)
    if has_num and type(get_num) == "function" then
        local succeeded, result = pcall(get_num, array)
        if succeeded and type(result) == "number" then
            count = result
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- The object pool, and the authority question
--------------------------------------------------------------------------------

-- FindAllOf and FindFirstOf with one nil convention between them: find_all
-- always returns a table, so callers can ipairs it unguarded, and find_first
-- returns a validated object or nil.
--
-- is_valid rather than ~= nil on the single form: FindFirstOf can return a
-- non-nil object that is not usable.
local function find_all(class)
    local succeeded, found = pcall(FindAllOf, class)
    if succeeded and found ~= nil then
        return found
    end
    return {}
end

local function find_first(class)
    local succeeded, found = pcall(FindFirstOf, class)
    if succeeded and is_valid(found) then
        return found
    end
    return nil
end

-- AActor::HasAuthority(), which is zero-argument.
--
-- Returns allowed, valid_actor, asked, authoritative -- each stage of the
-- conjunction, so a caller can report which one failed. An unasked question
-- counts as unauthorised: this FAILS CLOSED.
--
-- Not UGameplayStatics::IsServer(WorldContextObject)
--
-- One implementation, here, because it gates every AddItem_ServerInternal in the
-- mod.
local function has_authority(actor)
    local valid_actor = is_valid(actor)
    local authoritative = false
    local asked = false
    if valid_actor then
        local succeeded, answer = pcall(_call_key, actor, "HasAuthority")
        asked = succeeded
        authoritative = answer == true
    end
    return valid_actor and asked and authoritative, valid_actor, asked, authoritative
end

--------------------------------------------------------------------------------
-- Files
--------------------------------------------------------------------------------
--
-- io and os are guarded on every use here, and every read, write and delete in
-- the mod goes through these three functions. Parsing stays with whoever owns
-- the format.

-- Every line of a file, or nil if it could not be opened. An empty file returns
-- an empty table, which is a different answer from nil.
local function read_lines(path)
    if io == nil or type(io.open) ~= "function" then
        return nil
    end
    local opened, handle = pcall(io.open, path, "r")
    if not opened or handle == nil then
        return nil
    end
    local lines = {}
    while true do
        local read_ok, line = pcall(handle.read, handle, "*l")
        if not read_ok or line == nil then
            break
        end
        lines[#lines + 1] = line
    end
    pcall(handle.close, handle)
    return lines
end

local function remove_file(path)
    if os == nil or type(os.remove) ~= "function" then
        return false
    end
    return (pcall(os.remove, path))
end

-- Writes one line per entry, newline-terminated, and returns whether the whole
-- write succeeded. label names the file in the two warnings.
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
    UE4SS_ROOT = UE4SS_ROOT,
    array_count = array_count,
    field = field,
    find_all = find_all,
    find_first = find_first,
    guid_key = guid_key,
    has_authority = has_authority,
    is_valid = is_valid,
    log = log,
    method = method,
    name_to_string = name_to_string,
    read_lines = read_lines,
    remove_file = remove_file,
    unwrap = unwrap,
    write_lines = write_lines,
}
