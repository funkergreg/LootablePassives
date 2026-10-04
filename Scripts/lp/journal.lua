-- Lootable Passives -- The crash-recovery journal.
--
-- One row, rewritten at each step of an exchange. Every write_journal result is
-- checked by its caller, which aborts rather than continuing unjournalled.

local util = require("lp.util")
local passives = require("lp.passives")

local is_writable = util.is_writable
local log = util.log
local read_lines = util.read_lines
local remove_file = util.remove_file
local write_lines = util.write_lines
local module_for = passives.module_for

-- At util.UE4SS_ROOT, outside the folder the mod loader replaces on a Version
-- change. The name carries the mod prefix because the folder no longer does.
local JOURNAL_PATH = util.UE4SS_ROOT .. "LootablePassives_journal.tsv"

--------------------------------------------------------------------------------
-- The row
--
-- Columns: version, state, phase, passive_id, item_id, passive_name
--   version       JOURNAL_VERSION. Any other stamp is discarded unread.
--   state         "prepared" -- module not yet granted
--                 "granted"  -- module granted, removal still pending
--   phase         "marker"   -- the passive the swap replaced
--                 "loop"     -- one passive of an extract-all
--                 "implant"  -- an alias installed, module already spent
--                 "stranded" -- the swap happened and could not be resolved;
--                               passive_id and item_id may be empty
--   passive_id    the passive being exchanged, or empty
--   item_id       the module for it, or empty
--   passive_name  the marker id on the Pal
--------------------------------------------------------------------------------

-- Bump when the columns change. read_journal discards any other stamp, which is
-- what stops a journal orphaned across an update being replayed against
-- different column meanings.
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

-- Can the journal be written at all? Reported by main.lua at load.
local function journal_is_writable()
    return is_writable(JOURNAL_PATH)
end

-- The journal row as a table, or nil. A row that is unparseable, stamped for
-- another build, or internally inconsistent is logged, its file deleted, and nil
-- returned.
local function parse_journal()
    -- The first line is the whole journal; there is never a second exchange in
    -- flight.
    local line = (read_lines(JOURNAL_PATH) or {})[1]
    if line == nil then
        return nil
    end
    local version, state, phase, passive_id, item_id =
        line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t[^\t]*$")
    if version == nil then
        log("WARNING: ignored and discarded a malformed recovery journal.")
        return nil, true
    end
    if version ~= JOURNAL_VERSION then
        log(string.format(
            "WARNING: discarded a recovery journal stamped %s; this build writes %s. "
            .. "An interrupted exchange from another version was NOT replayed.",
            tostring(version), JOURNAL_VERSION))
        return nil, true
    end
    -- A "stranded" row may name no passive, so only the exchanging phases
    -- require these two columns to agree with the module map.
    if phase ~= "stranded" then
        if passive_id == "" then
            log("WARNING: ignored and discarded a recovery journal with no passive.")
            return nil, true
        end
        if module_for(passive_id) ~= item_id then
            log("WARNING: ignored a recovery journal whose item mapping no longer matches.")
            return nil, true
        end
    end
    return {
        state = state,
        phase = phase,
        passive_id = passive_id ~= "" and passive_id or nil,
        item_id = item_id ~= "" and item_id or nil,
    }
end

local function read_journal()
    local record, discard = parse_journal()
    if discard then
        remove_file(JOURNAL_PATH)
    end
    return record
end

local function clear_journal()
    remove_file(JOURNAL_PATH)
end

return {
    JOURNAL_PATH = JOURNAL_PATH,
    clear_journal = clear_journal,
    journal_is_writable = journal_is_writable,
    read_journal = read_journal,
    write_journal = write_journal,
}
