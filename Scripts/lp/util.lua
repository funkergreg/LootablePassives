-- Lootable Passives -- Reflection helpers, logging, file access, and the small
-- predicates everything uses.
--
-- The _call_/_index_ helpers are module-level functions passed to pcall by
-- reference, never `pcall(function() ... end)`. field() and method() are the
-- general form.

-- The tag on every log line, and the filter the dev process reads UE4SS.log by.
local MOD_NAME = "LootablePassives"

-- The mod's Scripts\ folder, not this file's folder: the trailing lp\ is
-- stripped. The separator is matched and put back, so a parent folder whose name
-- merely ends in "lp" is not stripped too.
local SCRIPT_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local SCRIPT_DIRECTORY = SCRIPT_SOURCE:match("^(.*[\\/])") or ""
SCRIPT_DIRECTORY = SCRIPT_DIRECTORY:gsub("([\\/])[Ll][Pp][\\/]$", "%1")

-- Where the mod's runtime files go: the UE4SS root, not Scripts\.
--
-- Scripts\ is one of the directories the official mod loader installs this mod
-- into. The loader reinstalls them when Info.json's Version changes, and at
-- every launch when Info.json sets DebugMode. The UE4SS root is not one of
-- them. Falls back to SCRIPT_DIRECTORY if the path does not contain a UE4SS
-- folder.
--
-- Derived once, here, because the journal and the ledger must agree on it.
local UE4SS_ROOT = SCRIPT_DIRECTORY:match("^(.*[\\/]UE4SS[\\/])") or SCRIPT_DIRECTORY

-- The mod's only log channel, and it is unconditional.
local function log(message)
    -- UE4SS's print writes no line break of its own.
    print(string.format("[%s] %s\n", MOD_NAME, message))
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

-- Read one property off an engine object, or call one of its zero-argument
-- methods, and return the result through unwrap. A read or call that raises
-- returns nil, as does a nil object.
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
    return unwrap(value)
end

local function method(object, key)
    if object == nil then
        return nil
    end
    local succeeded, value = pcall(_call_key, object, key)
    if not succeeded then
        return nil
    end
    return unwrap(value)
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
-- Takes the GUID as field() returns it, already unwrapped; every caller reads it
-- that way.
--
-- Returns nil for the null GUID and for nil, so two unresolved GUIDs never
-- compare equal.
--
-- Lives here because the two GUIDs it is used on come from different places --
-- OwnerPlayerUId on a Pal's SaveParameter, PlayerUId on APalPlayerState -- and
-- lp/ledger.lua and passives.snapshot_all compare them against each other.
local function _guid_parts(guid)
    return unwrap(guid.A), unwrap(guid.B), unwrap(guid.C), unwrap(guid.D)
end

local function guid_key(guid)
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
-- Scheduling
--------------------------------------------------------------------------------

-- Runs fn(a, b) on the game thread after delay_ms, through
-- ExecuteInGameThreadWithDelay.
--
-- ALLOCATES ONE CLOSURE PER CALL, so it is for one-off work, never a per-frame
-- path; that is coalescer() below.
local function run_later(delay_ms, fn, a, b)
    ExecuteInGameThreadWithDelay(delay_ms, function()
        fn(a, b)
    end)
end

-- Wraps work in a scheduler that keeps at most one deferred pass queued: the
-- returned function runs work on the game thread after delay ms, through
-- ExecuteInGameThreadWithDelay, and does nothing while a pass is already
-- queued. The flag clears before work runs, so work may reschedule itself.
--
-- Called at LOAD. Each call builds its flag and its runner once, so the
-- scheduler it returns allocates nothing however often a hook fires.
local function coalescer(work, delay)
    local scheduled = false
    local run
    run = function()
        scheduled = false
        work()
    end
    return function()
        if scheduled then
            return
        end
        scheduled = true
        ExecuteInGameThreadWithDelay(delay, run)
    end
end

--------------------------------------------------------------------------------
-- Files
--------------------------------------------------------------------------------
--
-- io and os are guarded on every use here, and every read, write and delete in
-- the mod goes through these four functions. Parsing stays with whoever owns
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

-- Opens path for append, which creates it, and returns whether that worked. A
-- zero-byte file -- one this probe created -- is removed again; its size is
-- measured while the handle is still open.
local function is_writable(path)
    if io == nil or type(io.open) ~= "function" then
        return false
    end
    local opened, handle = pcall(io.open, path, "a")
    if not opened or handle == nil then
        return false
    end
    local sized, size = pcall(handle.seek, handle, "end")
    pcall(handle.close, handle)
    if sized and size == 0 then
        remove_file(path)
    end
    return true
end

-- file:write and file:flush report an I/O failure by returning nil and a
-- message, not by raising; assert turns that into a raise for the pcall below.
local function _write_all(handle, lines)
    for _, line in ipairs(lines) do
        assert(handle:write(line, "\n"))
    end
    assert(handle:flush())
end

-- Writes one line per entry, newline-terminated, and returns whether the whole
-- write succeeded, close included. label names the file in the warnings.
--
-- Opening "w" truncates the file, so a false return can leave it empty or
-- partial rather than as it was.
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
    local wrote, write_error = pcall(_write_all, handle, lines)
    local close_ok, closed, close_error = pcall(handle.close, handle)
    if not wrote then
        log("WARNING: could not write " .. label .. ": " .. tostring(write_error))
        return false
    end
    if not close_ok or not closed then
        log("WARNING: could not close " .. label .. ": "
            .. tostring(close_ok and close_error or closed))
        return false
    end
    return true
end

return {
    UE4SS_ROOT = UE4SS_ROOT,
    array_count = array_count,
    coalescer = coalescer,
    field = field,
    find_all = find_all,
    find_first = find_first,
    guid_key = guid_key,
    has_authority = has_authority,
    is_valid = is_valid,
    is_writable = is_writable,
    log = log,
    method = method,
    name_to_string = name_to_string,
    read_lines = read_lines,
    remove_file = remove_file,
    run_later = run_later,
    unwrap = unwrap,
    write_lines = write_lines,
}
