-- Lootable Passives -- The crash-recovery journal.
--
-- One row per Pal with an exchange in flight, keyed by the Pal's IndividualId
-- (passives.pal_key). Each write replaces that Pal's row and leaves every other
-- row as it is, so two exchanges on two Pals never overwrite each other. Every
-- write_journal result is checked by its caller, which aborts rather than
-- continuing unjournalled.

local util = require("lp.util")
local options = require("lp.options")
local passives = require("lp.passives")

local HALT = options.HALT
local debug_log = options.debug_log
local fault_log = options.fault_log
local journal_write_fails = options.journal_write_fails
local journal_write_halts = options.journal_write_halts
local is_writable = util.is_writable
local log = util.log
local read_lines = util.read_lines
local remove_file = util.remove_file
local replace_file = util.replace_file
local module_for = passives.module_for

-- At util.UE4SS_ROOT, outside the directories the mod loader reinstalls this
-- mod into. The name carries the mod prefix because the folder does not.
local JOURNAL_PATH = util.UE4SS_ROOT .. "LootablePassives_journal.tsv"

--------------------------------------------------------------------------------
-- The rows
--
-- Columns: version, key, state, phase, passive_id, item_id, passive_name
--   version       JOURNAL_VERSION
--   key           the Pal's pal_key, or LEGACY_KEY for a row migrated from the
--                 single-row format, which names no Pal
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
--
-- A file whose first line is stamped LEGACY_VERSION holds one row in the
-- previous format, which has no key column. It is read as a LEGACY_KEY row and
-- the file is rewritten in this format.
--------------------------------------------------------------------------------

local JOURNAL_VERSION = "LPJ2"
local LEGACY_VERSION = "LPJ1"
local LEGACY_KEY = "legacy"

-- One row's fields as a table, or nil and a reason when the row is unusable.
local function validate(key, state, phase, passive_id, item_id, lock)
    if key == "" then
        return nil, "names no Pal"
    end
    if lock == "" then
        return nil, "names no marker"
    end
    -- A "stranded" row may name no passive, so only the exchanging phases
    -- require these two columns to agree with the module map.
    if phase ~= "stranded" then
        if passive_id == "" then
            return nil, "names no passive"
        end
        if module_for(passive_id) ~= item_id then
            return nil, "has an item mapping that no longer matches"
        end
    end
    return {
        key = key,
        state = state,
        phase = phase,
        passive_id = passive_id ~= "" and passive_id or nil,
        item_id = item_id ~= "" and item_id or nil,
        lock = lock,
    }
end

-- One line as a row, or nil and a reason.
local function parse_line(line)
    local version, key, state, phase, passive_id, item_id, lock = line:match(
        "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if version == JOURNAL_VERSION then
        return validate(key, state, phase, passive_id, item_id, lock)
    end
    local legacy_version, legacy_state, legacy_phase, legacy_passive, legacy_item, legacy_lock =
        line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if legacy_version == LEGACY_VERSION then
        return validate(LEGACY_KEY, legacy_state, legacy_phase, legacy_passive, legacy_item,
            legacy_lock)
    end
    local stamp = version or legacy_version
    if stamp ~= nil then
        return nil, string.format("is stamped %s; this build writes %s", stamp, JOURNAL_VERSION)
    end
    return nil, "is malformed"
end

local function format_row(row)
    return table.concat({
        JOURNAL_VERSION,
        row.key,
        row.state,
        row.phase,
        tostring(row.passive_id or ""),
        tostring(row.item_id or ""),
        tostring(row.lock or ""),
    }, "\t")
end

-- Writes rows, or removes the file when there are none. Returns whether that
-- succeeded.
local function store(rows)
    if #rows == 0 then
        remove_file(JOURNAL_PATH)
        return true
    end
    local lines = {}
    for index, row in ipairs(rows) do
        lines[index] = format_row(row)
    end
    return replace_file(JOURNAL_PATH, lines, "recovery journal")
end

-- Every usable row on disk, in file order. Each unusable line is logged and
-- dropped; a later key's row replaces an earlier one with the same key. The
-- file is rewritten when anything was dropped or migrated.
local function load_rows()
    local rows, positions = {}, {}
    local rewrite = false
    for _, line in ipairs(read_lines(JOURNAL_PATH) or {}) do
        local row, reason = parse_line(line)
        if row == nil then
            log(string.format("WARNING: discarded a recovery journal row that %s. An interrupted "
                .. "exchange it described was NOT replayed.", reason))
            rewrite = true
        else
            if row.key == LEGACY_KEY then
                rewrite = true
            end
            local at = positions[row.key]
            if at ~= nil then
                rows[at] = row
                rewrite = true
            else
                rows[#rows + 1] = row
                positions[row.key] = #rows
            end
        end
    end
    if rewrite then
        store(rows)
    end
    return rows
end

-- Writes the row for key, replacing that Pal's earlier row if there is one, and
-- returns whether the write succeeded. Under debug_faults, fail_journal_write
-- returns false for its row before the file is opened, and halt_after_journal
-- raises options.HALT once its row is written.
local function write_journal(key, state, phase, passive_id, item_id, passive_name)
    local described = string.format("%s/%s pal=%s passive=%s item=%s marker=%s", state, phase,
        tostring(key), tostring(passive_id), tostring(item_id), tostring(passive_name))
    if key == nil then
        log("WARNING: a recovery journal row could not be written: the Pal's id does not read.")
        return false
    end
    if journal_write_fails(state, phase) then
        fault_log("journal write failed on purpose: " .. described)
        return false
    end
    local row = {
        key = key,
        state = state,
        phase = phase,
        passive_id = passive_id,
        item_id = item_id,
        lock = passive_name,
    }
    local rows = load_rows()
    local replaced = false
    for index, existing in ipairs(rows) do
        if existing.key == key then
            rows[index] = row
            replaced = true
            break
        end
    end
    if not replaced then
        rows[#rows + 1] = row
    end
    local written = store(rows)
    debug_log(string.format("journal write %s: %s", written and "ok" or "FAILED", described))
    if written and journal_write_halts(state, phase) then
        fault_log("exchange halted after writing " .. described)
        error(HALT)
    end
    return written
end

-- Can the journal be written at all? Reported by main.lua at load.
local function journal_is_writable()
    return is_writable(JOURNAL_PATH)
end

-- Every row on disk, as { key, state, phase, passive_id, item_id, lock }.
local function read_journal()
    local rows = load_rows()
    for _, row in ipairs(rows) do
        debug_log(string.format("journal read: pal=%s %s/%s passive=%s item=%s marker=%s",
            row.key, row.state, row.phase, tostring(row.passive_id), tostring(row.item_id),
            row.lock))
    end
    return rows
end

-- The row for key, or nil.
local function read_row(key)
    for _, row in ipairs(load_rows()) do
        if row.key == key then
            return row
        end
    end
    return nil
end

-- Removes the row for key and leaves the others.
local function clear_journal(key)
    local rows = load_rows()
    local kept = {}
    for _, row in ipairs(rows) do
        if row.key ~= key then
            kept[#kept + 1] = row
        end
    end
    if #kept ~= #rows then
        store(kept)
    end
    debug_log("journal cleared for pal=" .. tostring(key))
end

return {
    JOURNAL_PATH = JOURNAL_PATH,
    LEGACY_KEY = LEGACY_KEY,
    clear_journal = clear_journal,
    journal_is_writable = journal_is_writable,
    read_journal = read_journal,
    read_row = read_row,
    write_journal = write_journal,
}
