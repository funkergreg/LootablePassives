-- Lootable Passives -- Replaying an interrupted exchange.
--
-- Every action here is JOURNAL-AUTHORISED. It refuses to act unless a journal
-- exists and exactly one Pal carries the marker it names. The deleted
-- sweep_stray_markers did the opposite -- it ran on every map load with
-- nothing authorising it -- and that is why it was dangerous.

local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")

-- Localised so the function bodies below are byte-identical to what they
-- were in main.lua: this split is code motion, not a rewrite.
local log = util.log
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local clear_journal = journal.clear_journal
local read_journal = journal.read_journal
local get_skill_ids = passives.get_skill_ids
local remove_skill = inventory.remove_skill
local restore_replaced_passive = inventory.restore_replaced_passive

--------------------------------------------------------------------------------
-- Crash recovery
--------------------------------------------------------------------------------

local function marked_parameters()
    local succeeded, parameters = pcall(function()
        return FindAllOf("PalIndividualCharacterParameter")
    end)
    if not succeeded or parameters == nil then
        return {}
    end
    local marked = {}
    for _, parameter in ipairs(parameters) do
        local ids = get_skill_ids(parameter)
        if ids ~= nil then
            for _, id in ipairs(ids) do
                if EXTRACTION_MODES[id] ~= nil then
                    marked[#marked + 1] = { parameter = parameter, ids = ids, lock = id }
                    break
                end
            end
        end
    end
    return marked
end

local function recover_interrupted_extraction(reason)
    local journal, discard = read_journal()
    if journal == nil then
        -- A journal we could not parse, or one from another build. read_journal
        -- has already said so loudly; removing it stops the same warning firing
        -- on every load from here on.
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
    local lock = journal.lock ~= "" and journal.lock or marked[1].lock
    local recovered

    if journal.phase == "implant" then
        -- Vanilla installed the alias and consumed the module, but the mod never
        -- got to swap the alias for the real passive. Finish the swap: the
        -- player has already paid for it.
        recovered = restore_replaced_passive(parameter, journal.passive_id, lock)
    elseif journal.phase == "stranded" then
        -- A transaction that vanilla committed but the mod could not resolve.
        -- Put the passive back if we know which one it was, and otherwise just
        -- take the marker off -- the empty-slot case appends a marker without
        -- replacing anything, so there is genuinely nothing to restore.
        if journal.passive_id ~= nil then
            recovered = restore_replaced_passive(parameter, journal.passive_id, lock)
        else
            recovered = remove_skill(parameter, lock)
        end
    elseif journal.phase == "marker" and journal.state == "prepared" then
        -- The implant was never granted, so put the passive back.
        recovered = restore_replaced_passive(parameter, journal.passive_id, lock)
    elseif journal.phase == "marker" and journal.state == "granted" then
        -- The implant exists; dropping the marker completes the exchange.
        recovered = remove_skill(parameter, lock)
    elseif journal.phase == "loop" and journal.state == "granted" then
        -- The implant exists but its passive is still attached.
        recovered = remove_skill(parameter, journal.passive_id)
            and remove_skill(parameter, lock)
    else
        -- phase "loop", state "prepared": nothing was granted and the passive is
        -- intact. Only the marker needs clearing.
        recovered = remove_skill(parameter, lock)
    end

    if recovered then
        clear_journal()
        log(string.format("Recovered interrupted extraction of %s after %s (%s/%s).",
            journal.passive_id, reason, journal.phase, journal.state))
    else
        log("WARNING: interrupted extraction could not be recovered; marker left untouched.")
    end
end

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
