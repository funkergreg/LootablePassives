-- Lootable Passives -- Replaying an interrupted exchange.
--
-- Acts only on a journal row, and only against a Pal singled out as that row's:
-- the one Pal in the world carrying a marker, or, in settle_before_exchange, the
-- one besides the new exchange's Pal. Both conditions are required: nothing here
-- sweeps markers it has no journal entry for.

local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")

local log = util.log
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local clear_journal = journal.clear_journal
local read_journal = journal.read_journal
local count_id = passives.count_id
local get_skill_ids = passives.get_skill_ids
local pal_key = passives.pal_key
local snapshot_all = passives.snapshot_all
local remove_skill = inventory.remove_skill
local restore_replaced_passive = inventory.restore_replaced_passive

--------------------------------------------------------------------------------
-- Crash recovery
--------------------------------------------------------------------------------

-- Does the list hold one of our markers?
local function has_marker(skill_ids)
    for _, id in ipairs(skill_ids or {}) do
        if EXTRACTION_MODES[id] ~= nil then
            return true
        end
    end
    return false
end

-- Every Pal carrying one of our markers, as { parameter = ..., lock = <id> },
-- leaving out the Pal whose pal_key is skip_key when one is given. The world
-- walk is passives.snapshot_all; this is the filter over it.
local function marked_parameters(skip_key)
    local marked = {}
    for _, snapshot in ipairs(snapshot_all()) do
        for _, id in ipairs(snapshot.before_ids) do
            if EXTRACTION_MODES[id] ~= nil then
                if skip_key == nil or pal_key(snapshot.parameter) ~= skip_key then
                    marked[#marked + 1] = { parameter = snapshot.parameter, lock = id }
                end
                break
            end
        end
    end
    return marked
end

-- Replays one journal row against parameter, whose marker is lock. The marker is
-- taken from the Pal, not from the journal: read_journal returns no lock column.
-- Returns whether the replay succeeded.
local function replay(record, parameter, lock)
    if record.phase == "implant" then
        -- The alias is on the Pal and the module is already spent; completing
        -- the swap is what the row is for.
        return restore_replaced_passive(parameter, record.passive_id, lock)
    elseif record.phase == "stranded" then
        -- Restore the passive if the row names one; otherwise only the marker
        -- has to come off.
        if record.passive_id ~= nil then
            return restore_replaced_passive(parameter, record.passive_id, lock)
        end
        return remove_skill(parameter, lock)
    elseif record.phase == "marker" and record.state == "prepared" then
        -- Nothing was granted: put the passive back.
        return restore_replaced_passive(parameter, record.passive_id, lock)
    elseif record.phase == "marker" and record.state == "granted" then
        -- The module exists; removing the marker completes the exchange.
        return remove_skill(parameter, lock)
    elseif record.phase == "loop" and record.state == "granted" then
        -- The module exists. Its passive is usually still attached, but this row
        -- also stands while the extract-all sweep moves to the next passive, so
        -- the passive may already be off. remove_skill reports a count that did
        -- not fall as a failure, so what is gone is not asked for again; the
        -- marker's removal is what decides the outcome.
        local attached = count_id(get_skill_ids(parameter) or {}, record.passive_id) > 0
        return (not attached or remove_skill(parameter, record.passive_id))
            and remove_skill(parameter, lock)
    end
    -- phase "loop", state "prepared": nothing granted, passive intact, so only
    -- the marker is removed.
    return remove_skill(parameter, lock)
end

-- Replays one journal row against the single marked Pal, then clears the
-- journal if the replay succeeded.
local function recover_interrupted_extraction(reason)
    local record, discard = read_journal()
    if record == nil then
        -- read_journal has already logged why. Removing the file stops the same
        -- warning on every subsequent load.
        if discard then
            clear_journal()
        end
        return
    end
    local marked = marked_parameters(nil)
    if #marked ~= 1 then
        log(string.format(
            "WARNING: recovery journal found %d marker targets after %s; left all passives untouched.",
            #marked, reason))
        return
    end

    if replay(record, marked[1].parameter, marked[1].lock) then
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
-- the one other Pal carrying a marker and cleared if that succeeds; it is
-- discarded if no other Pal carries one. It is left to be overwritten, with a
-- warning, when it cannot be told apart from the new exchange: the new Pal
-- already carried a marker, its IndividualId does not read, or two or more other
-- Pals carry one. Returns false only when the replay ran and failed, keeping the
-- row.
local function settle_before_exchange(parameter, before_ids)
    local record, discard = read_journal()
    if record == nil then
        if discard then
            clear_journal()
        end
        return true
    end
    local described = string.format("%s (%s/%s)",
        tostring(record.passive_id), record.phase, record.state)

    local current = pal_key(parameter)
    local marked = nil
    if current ~= nil and not has_marker(before_ids) then
        marked = marked_parameters(current)
    end
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
    if replay(record, marked[1].parameter, marked[1].lock) then
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
    ExecuteWithDelay(5000, function()
        ExecuteInGameThread(function()
            recover_interrupted_extraction(reason)
        end)
    end)
end

return {
    schedule_recovery = schedule_recovery,
    settle_before_exchange = settle_before_exchange,
}
