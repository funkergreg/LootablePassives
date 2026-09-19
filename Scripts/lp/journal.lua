-- Lootable Passives -- The crash-recovery journal.
--
-- Grant-first ordering is the mod's entire crash-safety story and this file is
-- what makes it recoverable. Every write is CHECKED by its caller; a failure
-- aborts the exchange rather than running it unprotected.

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")

-- Localised so the function bodies below are byte-identical to what they
-- were in main.lua: this split is code motion, not a rewrite.
local SCRIPT_DIRECTORY = util.SCRIPT_DIRECTORY
local log = util.log
local write_lines = util.write_lines

-- The journal must NOT live in this folder.
--
-- Scripts\ sits inside the tree the official mod loader manages. On any change
-- to Version in Info.json the loader uninstalls and reinstalls the mod folder
-- from Mods\ManagedMods\<PackageName>\InstallManifest.json, and that manifest
-- lists only the files the loader itself copied -- so a journal written here is
-- orphaned or swept on every update, taking an in-flight transaction with it.
-- DebugMode:true does the same on every single launch.
--
-- So climb out to the UE4SS root, which is not managed per-mod and is already
-- where UE4SS writes its own log. The name keeps the mod prefix because it is no
-- longer in a folder that identifies it. Falls back to the old location if the
-- path does not look the way we expect, which is better than not journalling.
local UE4SS_ROOT = SCRIPT_DIRECTORY:match("^(.*[\\/]UE4SS[\\/])") or SCRIPT_DIRECTORY
local JOURNAL_PATH = UE4SS_ROOT .. "LootablePassives_journal.tsv"

--------------------------------------------------------------------------------
-- Recovery journal
--
-- Columns: version, state, phase, passive_id, item_id, extractgion_mode
--   version  JOURNAL_VERSION. A journal stamped with anything else is from a
--            different build of this mod and is discarded rather than replayed,
--            because these column meanings are not guaranteed across versions.
--            The official loader can leave one orphaned across an update.
--   state    "prepared" (implant not yet granted) | "granted" (implant granted,
--            removal still pending)
--   phase    "marker"   the passive the vanilla swap replaced
--            "loop"     one of the additional passives removed by an extract-all
--            "stranded" vanilla committed the swap but the mod could not resolve
--                       it. passive_id and item_id may be empty here, because the
--                       empty-slot case appends a marker without replacing
--                       anything; there is then nothing to restore, only a
--                       marker to remove.
--   passive_name the marker passive name, so recovery can find the Pal again
--
-- Written OUTSIDE the loader-managed mod folder; see JOURNAL_PATH above for why.
--------------------------------------------------------------------------------

-- Bump this if the column layout changes. A journal stamped with anything else
-- is from a different version of this mod and cannot be trusted to mean what
-- these columns mean -- which matters because the loader can leave an orphaned
-- journal behind across an update.
local JOURNAL_VERSION = "LPJ1"

local function write_journal(state, phase, passive_id, item_id, passive_name)
    return write_lines(JOURNAL_PATH, {
        table.concat({
            JOURNAL_VERSION,
            state,
            phase,
            tostring(passive_id or ""),
            tostring(item_id or ""),
            tostring(passive_name or ""),
        }, "\t"),
    }, "recovery journal")
end

-- Is the journal path writable at all?
--
-- Checked once, at load, and reported loudly. Every write_journal call site used
-- to discard the return value, so on an install where io is unavailable or the
-- directory is read-only the entire grant-first crash-safety story silently did
-- not exist: the exchange ran unjournalled and nothing refused to proceed.
local journal_writable = nil

local function journal_is_writable()
    if journal_writable ~= nil then
        return journal_writable
    end
    journal_writable = false
    if io ~= nil and type(io.open) == "function" then
        local opened, handle = pcall(io.open, JOURNAL_PATH, "a")
        if opened and handle ~= nil then
            pcall(handle.close, handle)
            journal_writable = true
        end
    end
    return journal_writable
end

local function read_journal()
    if io == nil or type(io.open) ~= "function" then
        return nil
    end
    local opened, handle = pcall(io.open, JOURNAL_PATH, "r")
    if not opened or handle == nil then
        return nil
    end
    local read_ok, line = pcall(handle.read, handle, "*l")
    pcall(handle.close, handle)
    if not read_ok or line == nil then
        return nil
    end
    local version, state, phase, passive_id, item_id, passive_name =
        line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if version == nil then
        log("WARNING: ignored and discarded a malformed recovery journal.")
        return nil, true
    end
    if version ~= JOURNAL_VERSION then
        -- Loudly, not silently: this is a journal we cannot act on, and leaving
        -- it in place would only mean re-reading it on every load forever.
        log(string.format(
            "WARNING: discarded a recovery journal stamped %s; this build writes %s. "
            .. "An interrupted exchange from another version was NOT replayed.",
            tostring(version), JOURNAL_VERSION))
        return nil, true
    end
    -- A stranded marker legitimately has no passive to restore -- the empty-slot
    -- case appends a marker without replacing anything -- so only the phases
    -- that actually exchange an item require these two columns.
    if phase ~= "stranded" then
        if passive_id == "" then
            log("WARNING: ignored and discarded a recovery journal with no passive.")
            return nil, true
        end
        if PASSIVE_ITEMS[passive_id] ~= item_id then
            log("WARNING: ignored a recovery journal whose item mapping no longer matches.")
            return nil, true
        end
    end
    return {
        state = state,
        phase = phase,
        passive_id = passive_id ~= "" and passive_id or nil,
        item_id = item_id ~= "" and item_id or nil,
        passive_name = passive_name,
    }
end

local function clear_journal()
    if os ~= nil and type(os.remove) == "function" then
        pcall(os.remove, JOURNAL_PATH)
    end
end

return {
    JOURNAL_PATH = JOURNAL_PATH,
    clear_journal = clear_journal,
    journal_is_writable = journal_is_writable,
    read_journal = read_journal,
    write_journal = write_journal,
}
