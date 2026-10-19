-- Lootable Passives -- Replaying an interrupted exchange.
--
-- Acts only on a journal row, and only against that row's Pal: the Pal whose
-- pal_key is the row's key, and only while it carries the row's marker. A row
-- migrated from the single-row format names no Pal, and is replayed against the
-- one Pal carrying its marker that has no row of its own. Nothing here sweeps
-- markers it has no journal row for.

local util = require("lp.util")
local options = require("lp.options")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")
local role = require("lp.role")

local log = util.log
local run_later = util.run_later
local debug_log = options.debug_log
local LEGACY_KEY = journal.LEGACY_KEY
local clear_journal = journal.clear_journal
local read_journal = journal.read_journal
local read_row = journal.read_row
local count_id = passives.count_id
local has_skill = passives.has_skill
local pal_key = passives.pal_key
local snapshot_all = passives.snapshot_all
local remove_skill = inventory.remove_skill
local undo_swap = inventory.undo_swap
local is_authority = role.is_authority

--------------------------------------------------------------------------------
-- Crash recovery
--------------------------------------------------------------------------------

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

local function describe(record)
    return string.format("%s (%s/%s)", tostring(record.passive_id), record.phase, record.state)
end

-- Replays record against parameter and clears its row if that succeeded.
local function replay_and_clear(record, parameter, reason)
    if replay(record, parameter) then
        clear_journal(record.key)
        log(string.format("Recovered interrupted exchange of %s after %s.", describe(record),
            reason))
    else
        log(string.format("WARNING: interrupted exchange of %s could not be recovered after %s; "
            .. "its marker and journal row are kept.", describe(record), reason))
    end
end

-- The legacy row: the one Pal carrying its marker, among the Pals no other row
-- names.
local function recover_legacy(record, snapshots, keyed, reason)
    local marked = {}
    for _, snapshot in ipairs(snapshots) do
        if count_id(snapshot.before_ids, record.lock) > 0 and not keyed[snapshot.key or ""] then
            marked[#marked + 1] = snapshot.parameter
        end
    end
    debug_log(string.format("recovery after %s: %d Pal(s) carry legacy marker %s", reason,
        #marked, record.lock))
    if #marked ~= 1 then
        log(string.format(
            "WARNING: recovery journal found %d Pals carrying marker %s after %s; left all "
            .. "passives untouched.", #marked, record.lock, reason))
        return
    end
    replay_and_clear(record, marked[1], reason)
end

-- Replays every journal row against its own Pal. Does nothing where
-- role.is_authority() is false, where the rows stay on disk.
--
-- A row whose Pal is not loaded is kept for the next pass. A row whose Pal no
-- longer carries its marker is cleared: there is nothing left to finish.
local function recover_interrupted_extraction(reason)
    local rows = read_journal()
    if #rows == 0 then
        return
    end
    if not is_authority() then
        log(string.format(
            "Recovery journal left on disk after %s: this machine is the %s, which does not hold "
            .. "the world.", reason, role.describe()))
        return
    end
    local snapshots = snapshot_all()
    local by_key, keyed = {}, {}
    for _, snapshot in ipairs(snapshots) do
        snapshot.key = pal_key(snapshot.parameter)
        if snapshot.key ~= nil then
            by_key[snapshot.key] = snapshot
        end
    end
    for _, record in ipairs(rows) do
        keyed[record.key] = true
    end

    for _, record in ipairs(rows) do
        if record.key == LEGACY_KEY then
            recover_legacy(record, snapshots, keyed, reason)
        else
            local snapshot = by_key[record.key]
            if snapshot == nil then
                log(string.format("Recovery journal row for %s kept after %s: its Pal is not "
                    .. "loaded.", describe(record), reason))
            elseif count_id(snapshot.before_ids, record.lock) == 0 then
                clear_journal(record.key)
                log(string.format("Discarded the journal row of %s after %s: its Pal no longer "
                    .. "carries marker %s.", describe(record), reason, record.lock))
            else
                replay_and_clear(record, snapshot.parameter, reason)
            end
        end
    end
end

-- Called by lp/transaction.lua before it writes the first row of a new exchange
-- on the Pal whose pal_key is key, which replaces that Pal's earlier row.
-- before_ids is the Pal's passive list before the new swap. Rows of other Pals
-- are not read.
--
-- With no earlier row for this Pal, does nothing. An earlier row whose marker
-- is gone from before_ids is discarded. One whose marker is still in
-- before_ids cannot be told apart from the new exchange, and is replaced with
-- a warning.
local function settle_before_exchange(key, before_ids)
    local record = read_row(key)
    if record == nil then
        return
    end
    if count_id(before_ids, record.lock) > 0 then
        log(string.format(
            "WARNING: an earlier exchange of %s on this Pal was still awaiting recovery and could "
            .. "not be told apart from this one. Its journal row is replaced, so it will NOT be "
            .. "recovered.", describe(record)))
    else
        log(string.format(
            "Discarded the journal row of an earlier exchange of %s on this Pal: the Pal no longer "
            .. "carries its marker.", describe(record)))
    end
end

-- Runs one recovery pass 5 s from now, on the game thread.
local function schedule_recovery(reason)
    run_later(5000, recover_interrupted_extraction, reason)
end

return {
    schedule_recovery = schedule_recovery,
    settle_before_exchange = settle_before_exchange,
}
