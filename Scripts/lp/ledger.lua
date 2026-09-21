-- Lootable Passives -- The pending-grant ledger.
--
-- Modules a consumed Pal owes, on disk, until they are delivered. Written before
-- any delivery is attempted, so the debt survives a crash between the two.
--
-- Rows are keyed by owner and item id and carry a count, which bounds the file
-- at the number of module types times the players in the save, however many Pals
-- go through the machine. AddItem takes a count, so a row of 40 is one call.
--
-- The owner column is what lets a row be delivered to the player whose Pal it
-- came from; see ordered_for. Do not drop it; see CLAUDE.md on the delivery rule.
--
-- The file sits at util.UE4SS_ROOT, outside the folder the mod loader replaces on
-- a version change, as does the recovery journal.
--
-- This file is not the answer to a full inventory: add_modules reports a spill as
-- a success and the item still exists. What is left for it is having nobody to
-- deliver to, and surviving a crash.

local util = require("lp.util")
local passives = require("lp.passives")
local inventory = require("lp.inventory")

local log = util.log
local read_lines = util.read_lines
local remove_file = util.remove_file
local write_lines = util.write_lines
local is_module_id = passives.is_module_id

local LEDGER_PATH = util.UE4SS_ROOT .. "LootablePassives_pending.tsv"

-- Column layout stamp, per row. Bump when the columns change.
--
-- LPL2: version, owner, item id, count.
-- LPL1: version, item id, count. Still read, as ANY_OWNER rows.
local LEDGER_VERSION = "LPL2"
local LEDGER_VERSION_LEGACY = "LPL1"

-- Per-row ceiling. A count is saturated here and the excess is logged and
-- dropped.
local MAX_STACK = 9999

-- owner UId key -> item id -> count owed.
--
-- ANY_OWNER is the bucket for a Pal with no OwnerPlayerUId and for LPL1 rows.
-- ordered_for sends those to any candidate.
local ANY_OWNER = "*"
local pending = {}
local loaded = false

local function bucket_for(owner)
    local bucket = pending[owner]
    if bucket == nil then
        bucket = {}
        pending[owner] = bucket
    end
    return bucket
end

-- Flattens pending into { owner, item_id, count } rows, sorted by owner then
-- item id so the file is byte-stable between writes.
local function pending_rows()
    local rows = {}
    for owner, items in pairs(pending) do
        for item_id, count in pairs(items) do
            if count > 0 then
                rows[#rows + 1] = { owner = owner, item_id = item_id, count = count }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.owner ~= b.owner then
            return a.owner < b.owner
        end
        return a.item_id < b.item_id
    end)
    return rows
end

-- Declared ahead of total_owed, which calls it.
local load

-- Every public entry point calls load() first, so nothing outside this file has
-- to remember to.
local function total_owed()
    load()
    local total = 0
    for _, items in pairs(pending) do
        for _, count in pairs(items) do
            total = total + count
        end
    end
    return total
end

-- Writes every row, or removes the file when there are none.
local function persist()
    local rows = pending_rows()
    if #rows == 0 then
        remove_file(LEDGER_PATH)
        return true
    end
    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = table.concat(
            { LEDGER_VERSION, row.owner, row.item_id, tostring(row.count) }, "\t")
    end
    return write_lines(LEDGER_PATH, lines, "pending-grant ledger")
end

-- Reads the file once per session. A row is discarded if its stamp is neither
-- version, its count is not a positive number, or its item id is not one this
-- build defines -- is_module_id -- since such a row could never be delivered.
load = function()
    if loaded then
        return
    end
    loaded = true
    local lines = read_lines(LEDGER_PATH)
    if lines == nil then
        return
    end
    local discarded = 0
    for _, line in ipairs(lines) do
        local version, owner, item_id, count =
            line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if version == nil then
            -- Three columns: an LPL1 row, read as owned by nobody.
            local legacy_version, legacy_item, legacy_count =
                line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
            if legacy_version == LEDGER_VERSION_LEGACY then
                version, owner, item_id, count =
                    LEDGER_VERSION, ANY_OWNER, legacy_item, legacy_count
            end
        end
        if owner == nil or owner == "" then
            owner = ANY_OWNER
        end
        local number = tonumber(count)
        if version ~= LEDGER_VERSION or item_id == nil or number == nil or number <= 0 then
            discarded = discarded + 1
        elseif not is_module_id(item_id) then
            discarded = discarded + 1
        else
            local bucket = bucket_for(owner)
            bucket[item_id] = math.min(MAX_STACK, (bucket[item_id] or 0) + math.floor(number))
        end
    end
    if discarded > 0 then
        log(string.format("WARNING: discarded %d unusable row(s) from the pending-grant ledger.",
            discarded))
    end
    local owed = total_owed()
    if owed > 0 then
        log(string.format("%d module(s) owed from a previous session; will deliver when there is room.",
            owed))
    end
end

-- Records one Pal's worth of debt and persists once.
--
-- owner is the Pal's OwnerPlayerUId key, or nil for the ANY_OWNER bucket.
-- item_ids is a list; a repeated id counts once per occurrence.
--
-- Takes the whole list rather than one id at a time because persist() sorts and
-- rewrites the entire file per call. The accumulation is in-memory only, and the
-- write completes before the caller delivers anything.
local function owe(owner, item_ids)
    load()
    local bucket = bucket_for(owner or ANY_OWNER)
    local lost = {}
    for _, item_id in ipairs(item_ids) do
        local wanted = (bucket[item_id] or 0) + 1
        if wanted > MAX_STACK then
            lost[item_id] = (lost[item_id] or 0) + 1
            wanted = MAX_STACK
        end
        bucket[item_id] = wanted
    end
    for item_id, dropped in pairs(lost) do
        log(string.format(
            "WARNING: pending %s is capped at %d; %d module(s) could not be recorded and are lost.",
            item_id, MAX_STACK, dropped))
    end
    local written = persist()
    if not written then
        -- In memory but not on disk: a restart loses it, so it is reported
        -- rather than held silently.
        log(string.format(
            "WARNING: could not write the pending-grant ledger at %s. %d module(s) are owed in "
            .. "memory only and will be lost if the game closes before they are delivered.",
            LEDGER_PATH, #item_ids))
    end
    return written
end

-- Set once, on the first degraded pass in ordered_for.
local uid_warning_reported = false

-- Which candidates may receive this row, in order. An EMPTY RESULT MEANS HOLD
-- THE ROW -- flush counts it and leaves it on disk.
--
-- An ANY_OWNER row goes to all candidates in their given order. A row with an
-- owner goes to candidates whose uid matches, and to no others. The result is a
-- list rather than one candidate because a grant can fail and because one player
-- can briefly have two characters.
--
-- One fallback: if NO candidate yields a readable uid, the comparison cannot run
-- at all, and the row is sent to the others in their given order with a warning.
-- A uid that reads and does not match is not this case.
local function ordered_for(owner, candidates)
    if owner == ANY_OWNER then
        return candidates
    end
    local matched, others, readable = {}, {}, false
    for _, candidate in ipairs(candidates) do
        if candidate.uid ~= nil then
            readable = true
            if candidate.uid == owner then
                matched[#matched + 1] = candidate
            else
                others[#others + 1] = candidate
            end
        else
            others[#others + 1] = candidate
        end
    end
    if #matched > 0 then
        return matched
    end
    if not readable then
        if not uid_warning_reported then
            uid_warning_reported = true
            log("WARNING: no player UId could be read from any candidate, so modules cannot be "
                .. "matched to the player who owned the Pal. Delivering to the nearest player "
                .. "instead. This is a fault in the mod, not in the save.")
        end
        return others
    end
    return {}
end

-- Delivers every row it can. Returns delivered, owed, spilled, held.
--
-- Each row goes to ordered_for's first candidate that add_modules succeeds on;
-- a failure moves to the next candidate and a row with no candidates is counted
-- in held. Whatever is not delivered stays on disk.
--
-- near_location, when given, is the point delivery_candidates measures distance
-- from; it orders the fallback only.
local function flush(near_location)
    load()
    local rows = pending_rows()
    if #rows == 0 then
        return 0, 0, 0, 0
    end
    local candidates = inventory.delivery_candidates(near_location)
    if #candidates == 0 then
        -- Distinct from every candidate failing, so it gets its own line.
        log(string.format("No player inventory available; %d module(s) stay owed.", total_owed()))
        return 0, total_owed(), 0, 0
    end

    local delivered, spilled, held, changed = 0, 0, 0, false
    -- ordered_for's answer is memoised per owner: pending_rows sorts by owner,
    -- so a player with many owed item types partitions the candidate list once.
    local by_owner = {}
    for _, row in ipairs(rows) do
        local recipients = by_owner[row.owner]
        if recipients == nil then
            recipients = ordered_for(row.owner, candidates)
            by_owner[row.owner] = recipients
        end
        local reason = nil
        for _, candidate in ipairs(recipients) do
            local granted, detail = inventory.add_modules(candidate.data, row.item_id, row.count)
            if granted then
                local bucket = pending[row.owner]
                if bucket ~= nil then
                    bucket[row.item_id] = nil
                    if next(bucket) == nil then
                        pending[row.owner] = nil
                    end
                end
                delivered = delivered + row.count
                if detail == "spilled" then
                    spilled = spilled + row.count
                end
                changed = true
                reason = nil
                break
            end
            reason = detail
        end
        if #recipients == 0 then
            -- Counted, not logged: the caller reports the total once, where a
            -- per-row line would repeat for every item type one Pal owed.
            held = held + row.count
        elseif reason ~= nil then
            log(string.format("Could not deliver %s x%d to any of %d player(s): %s. Still owed.",
                row.item_id, row.count, #recipients, tostring(reason)))
        end
    end
    if changed then
        persist()
    end
    return delivered, total_owed(), spilled, held
end

return {
    LEDGER_PATH = LEDGER_PATH,
    flush = flush,
    owe = owe,
    total_owed = total_owed,
}
