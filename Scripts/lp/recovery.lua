-- Lootable Passives -- Replaying an interrupted exchange.
--
-- Acts only on a journal row, and only when exactly one Pal in the world carries
-- a marker. Both conditions are required: nothing here sweeps markers it has no
-- journal entry for.

local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")

local log = util.log
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local clear_journal = journal.clear_journal
local read_journal = journal.read_journal
local snapshot_all = passives.snapshot_all
local remove_skill = inventory.remove_skill
local restore_replaced_passive = inventory.restore_replaced_passive

--------------------------------------------------------------------------------
-- Crash recovery
--------------------------------------------------------------------------------

-- Every Pal carrying one of our markers, as { parameter = ..., lock = <id> }.
-- The world walk is passives.snapshot_all; this is the filter over it.
local function marked_parameters()
    local marked = {}
    for _, snapshot in ipairs(snapshot_all()) do
        for _, id in ipairs(snapshot.before_ids) do
            if EXTRACTION_MODES[id] ~= nil then
                marked[#marked + 1] = { parameter = snapshot.parameter, lock = id }
                break
            end
        end
    end
    return marked
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
    local marked = marked_parameters()
    if #marked ~= 1 then
        log(string.format(
            "WARNING: recovery journal found %d marker targets after %s; left all passives untouched.",
            #marked, reason))
        return
    end

    local parameter = marked[1].parameter
    -- The marker is taken from the Pal, not from the journal: read_journal
    -- returns no lock column.
    local lock = marked[1].lock
    local recovered

    if record.phase == "implant" then
        -- The alias is on the Pal and the module is already spent; completing
        -- the swap is what the row is for.
        recovered = restore_replaced_passive(parameter, record.passive_id, lock)
    elseif record.phase == "stranded" then
        -- Restore the passive if the row names one; otherwise only the marker
        -- has to come off.
        if record.passive_id ~= nil then
            recovered = restore_replaced_passive(parameter, record.passive_id, lock)
        else
            recovered = remove_skill(parameter, lock)
        end
    elseif record.phase == "marker" and record.state == "prepared" then
        -- Nothing was granted: put the passive back.
        recovered = restore_replaced_passive(parameter, record.passive_id, lock)
    elseif record.phase == "marker" and record.state == "granted" then
        -- The module exists; removing the marker completes the exchange.
        recovered = remove_skill(parameter, lock)
    elseif record.phase == "loop" and record.state == "granted" then
        -- The module exists and its passive is still attached: remove both.
        recovered = remove_skill(parameter, record.passive_id)
            and remove_skill(parameter, lock)
    else
        -- phase "loop", state "prepared": nothing granted, passive intact, so
        -- only the marker is removed.
        recovered = remove_skill(parameter, lock)
    end

    if recovered then
        clear_journal()
        log(string.format("Recovered interrupted extraction of %s after %s (%s/%s).",
            record.passive_id, reason, record.phase, record.state))
    else
        log("WARNING: interrupted extraction could not be recovered; marker left untouched.")
    end
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
}
