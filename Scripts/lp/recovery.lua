-- Lootable Passives -- Replaying an interrupted exchange.
--
-- Acts only on a journal row, and only against a Pal singled out as that row's:
-- the one Pal in the world carrying the row's marker, or, in
-- settle_before_exchange, the one besides the new exchange's Pal. Both
-- conditions are required: nothing here sweeps markers it has no journal entry
-- for.

local util = require("lp.util")
local config = require("lp.config")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")

local find_first = util.find_first
local has_authority = util.has_authority
local log = util.log
local run_later = util.run_later
local debug_log = config.debug_log
local clear_journal = journal.clear_journal
local read_journal = journal.read_journal
local count_id = passives.count_id
local first_marker = passives.first_marker
local has_skill = passives.has_skill
local pal_key = passives.pal_key
local snapshot_all = passives.snapshot_all
local remove_skill = inventory.remove_skill
local undo_swap = inventory.undo_swap

--------------------------------------------------------------------------------
-- Crash recovery
--------------------------------------------------------------------------------

-- Every Pal whose passive list holds lock, leaving out the Pal whose pal_key is
-- skip_key when one is given. The world walk is passives.snapshot_all; this is
-- the filter over it.
local function parameters_with(lock, skip_key)
    local marked = {}
    for _, snapshot in ipairs(snapshot_all()) do
        if count_id(snapshot.before_ids, lock) > 0
            and (skip_key == nil or pal_key(snapshot.parameter) ~= skip_key)
        then
            marked[#marked + 1] = snapshot.parameter
        end
    end
    return marked
end

-- Replays one journal row against parameter, which carries record.lock. Returns
-- whether the replay succeeded.
local function replay(record, parameter)
    local lock = record.lock
    if record.state == "granted" then
        -- The module exists. A marker row completes by removing the marker. A
        -- loop row also removes its passive first, which may already be off:
        -- this row stands while the extract-all sweep moves to the next passive,
        -- and remove_skill reports an absent id as removed.
        return (record.phase ~= "loop" or remove_skill(parameter, record.passive_id))
            and remove_skill(parameter, lock)
    end
    if record.phase == "loop" then
        -- Prepared: nothing granted, passive intact, so only the marker is
        -- removed.
        return remove_skill(parameter, lock)
    end
    -- Prepared implant, marker or stranded row: put the named passive back in
    -- the marker's place, or only remove the marker when the row names none or
    -- the Pal already carries the named passive. For an implant the passive is
    -- the alias's target and the module is already spent; completing the swap
    -- is what the row is for.
    local passive_id = record.passive_id
    if passive_id ~= nil and has_skill(parameter, passive_id) then
        log(string.format("Recovery: the Pal already carries %s, so only marker %s is removed.",
            passive_id, lock))
        passive_id = nil
    end
    return undo_swap(parameter, passive_id, lock)
end

-- Replays one journal row against the single Pal carrying its marker, then
-- clears the journal if the replay succeeded. Does nothing on a peer without
-- authority, where the row stays on disk.
local function recover_interrupted_extraction(reason)
    local record = read_journal()
    if record == nil then
        return
    end
    if not has_authority(find_first("PalPlayerCharacter")) then
        log(string.format(
            "Recovery journal left on disk after %s: this peer has no authority over the world, "
            .. "or no player is loaded yet.", reason))
        return
    end
    local marked = parameters_with(record.lock, nil)
    debug_log(string.format("recovery after %s: %d Pal(s) carry marker %s", reason, #marked,
        record.lock))
    if #marked ~= 1 then
        log(string.format(
            "WARNING: recovery journal found %d Pals carrying marker %s after %s; left all "
            .. "passives untouched.", #marked, record.lock, reason))
        return
    end

    if replay(record, marked[1]) then
        clear_journal()
        log(string.format("Recovered interrupted extraction of %s after %s (%s/%s).",
            record.passive_id, reason, record.phase, record.state))
    else
        log("WARNING: interrupted extraction could not be recovered; marker left untouched.")
    end
end

-- Called by lp/transaction.lua before it writes the first row of a new exchange,
-- which replaces whatever row is on disk. parameter and before_ids are the new
-- exchange's Pal and its passive list before the swap. Returns true when the
-- journal may be written.
--
-- With no row on disk, returns true. Otherwise the row is replayed now against
-- the one other Pal carrying the row's marker and cleared if that succeeds; it
-- is discarded if no other Pal carries it. It is left to be overwritten, with a
-- warning, when it cannot be told apart from the new exchange: the new Pal
-- already carried a marker, its IndividualId does not read, or two or more other
-- Pals carry one. Returns false only when the replay ran and failed, keeping the
-- row.
local function settle_before_exchange(parameter, before_ids)
    local record = read_journal()
    if record == nil then
        return true
    end
    local described = string.format("%s (%s/%s)",
        tostring(record.passive_id), record.phase, record.state)

    local current = pal_key(parameter)
    local marked = nil
    if current ~= nil and first_marker(before_ids) == nil then
        marked = parameters_with(record.lock, current)
    end
    debug_log(string.format("settle before exchange: %s other Pal(s) carry marker %s",
        marked and tostring(#marked) or "unknown", record.lock))
    if marked == nil or #marked > 1 then
        log(string.format(
            "WARNING: an earlier exchange of %s was still awaiting recovery and could not be told "
            .. "apart from this one. Its journal row is replaced, so it will NOT be recovered.",
            described))
        return true
    end
    if #marked == 0 then
        clear_journal()
        log(string.format(
            "Discarded the journal row of an earlier exchange of %s: no Pal carries its marker "
            .. "any more.", described))
        return true
    end
    if replay(record, marked[1]) then
        clear_journal()
        log(string.format(
            "Recovered an earlier interrupted exchange of %s before starting this one.", described))
        return true
    end
    log(string.format(
        "ERROR: an earlier exchange of %s is still awaiting recovery and could not be completed "
        .. "now. This operation is refused so that its journal row is kept.", described))
    return false
end

-- Runs one recovery pass 5 s from now, on the game thread.
local function schedule_recovery(reason)
    run_later(5000, recover_interrupted_extraction, reason)
end

return {
    schedule_recovery = schedule_recovery,
    settle_before_exchange = settle_before_exchange,
}
