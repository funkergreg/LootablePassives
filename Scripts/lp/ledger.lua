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
-- came from; see ordered_for.
--
-- The file sits at util.UE4SS_ROOT, outside the directories the mod loader
-- reinstalls this mod into, as does the recovery journal.
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

-- Column layout stamp, per row: version, owner, item id, count. Bump when the
-- columns change.
local LEDGER_VERSION = "LPL2"

-- Per-row ceiling. A count is saturated here and the excess is logged and
-- dropped.
local MAX_STACK = 9999

-- owner UId key -> item id -> count owed.
--
-- ANY_OWNER is the bucket for a Pal with no OwnerPlayerUId. ordered_for sends
-- those to any candidate.
local ANY_OWNER = "*"
local pending = {}
local loaded = false

-- True while the file on disk is known not to match pending: the last persist
-- failed. flush retries the write on every call until one lands.
local disk_stale = false

local function bucket_for(owner)
    local bucket = pending[owner]
    if bucket == nil then
        bucket = {}
        pending[owner] = bucket
    end
    return bucket
end

local function row_order(a, b)
    if a.owner ~= b.owner then
        return a.owner < b.owner
    end
    return a.item_id < b.item_id
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
    table.sort(rows, row_order)
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

-- Writes rows, which must be what pending_rows() would return for pending now,
-- or removes the file when there are none. Taken as an argument so a caller that
-- already holds the sorted rows does not sort them again.
local function persist(rows)
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

-- Reads the file once per session. A row is discarded if its stamp is not
-- LEDGER_VERSION, its count is not a positive number, or its item id is not one
-- this build defines -- is_module_id -- since such a row could never be
-- delivered.
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
        local number = tonumber(count)
        if version ~= LEDGER_VERSION or number == nil or number <= 0
            or not is_module_id(item_id)
        then
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
    local written = persist(pending_rows())
    disk_stale = not written
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

-- Which candidates may receive this row. An EMPTY RESULT MEANS HOLD THE ROW --
-- flush counts it and leaves it on disk.
--
-- A row with an owner goes to candidates whose uid matches, and to no others.
-- The result is a list rather than one candidate because a grant can fail and
-- because one player can briefly have two characters.
--
-- A row that cannot be matched -- an ANY_OWNER row, or any row when NO candidate
-- yields a readable uid -- goes to the one candidate when exactly one player is
-- online, and is held otherwise. A uid that reads and does not match is not
-- this case.
local function ordered_for(owner, candidates)
    if owner ~= ANY_OWNER then
        local matched, readable = {}, false
        for _, candidate in ipairs(candidates) do
            if candidate.uid ~= nil then
                readable = true
                if candidate.uid == owner then
                    matched[#matched + 1] = candidate
                end
            end
        end
        if readable then
            return matched
        end
        if not uid_warning_reported then
            uid_warning_reported = true
            log("WARNING: no player UId could be read from any candidate, so modules cannot be "
                .. "matched to the player who owned the Pal. They are delivered only while a "
                .. "single player is online, and held otherwise. This is a fault in the mod, not "
                .. "in the save.")
        end
    end
    if #candidates == 1 then
        return candidates
    end
    return {}
end

-- Rewrites the file as rows after a flush changed pending, or retries a rewrite
-- that failed earlier. rows is as persist takes it. A failure leaves delivered
-- rows on disk, which load() would read back and deliver again next session, so
-- it is logged on every attempt.
local function sync_after_flush(rows)
    disk_stale = not persist(rows)
    if disk_stale then
        log(string.format(
            "WARNING: could not rewrite the pending-grant ledger at %s after a delivery. It may "
            .. "still list modules already delivered, which would be delivered again next "
            .. "session. Retried on the next delivery attempt.", LEDGER_PATH))
    end
end

-- Delivers every row it can. Returns delivered, owed, spilled, held, and the
-- deliveries made, as a list of { uid = <recipient's PlayerUId key>, item_id,
-- count }.
--
-- Each row goes to ordered_for's first candidate that add_modules succeeds on;
-- a failure moves to the next candidate and a row with no candidates is counted
-- in held. Whatever is not delivered stays on disk.
local function flush()
    load()
    local rows = pending_rows()
    if disk_stale then
        sync_after_flush(rows)
    end
    if #rows == 0 then
        return 0, 0, 0, 0, {}
    end
    local candidates = inventory.delivery_candidates()
    if #candidates == 0 then
        -- Distinct from every candidate failing, so it gets its own line.
        local owed = total_owed()
        log(string.format("No player inventory available; %d module(s) stay owed.", owed))
        return 0, owed, 0, 0, {}
    end

    local delivered, spilled, held = 0, 0, 0
    local deliveries = {}
    -- The rows not delivered, in the order pending_rows sorted them, which is
    -- what persist takes; built here so the rewrite below does not sort again.
    local remaining = {}
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
        local taken = false
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
                deliveries[#deliveries + 1] = { uid = candidate.uid, item_id = row.item_id,
                    count = row.count }
                if detail == "spilled" then
                    spilled = spilled + row.count
                end
                taken = true
                reason = nil
                break
            end
            reason = detail
        end
        if not taken then
            remaining[#remaining + 1] = row
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
    if #remaining < #rows then
        sync_after_flush(remaining)
    end
    return delivered, total_owed(), spilled, held, deliveries
end

-- Drops every debt whose item id matches(item_id) is true, for every owner,
-- and persists. Returns the number of modules dropped, and whether the file
-- now matches.
local function forget_items(matches)
    load()
    local dropped = 0
    for _, items in pairs(pending) do
        for item_id, count in pairs(items) do
            if matches(item_id) then
                dropped = dropped + count
                items[item_id] = nil
            end
        end
    end
    if dropped == 0 then
        return 0, true
    end
    local written = persist(pending_rows())
    disk_stale = not written
    return dropped, written
end

return {
    LEDGER_PATH = LEDGER_PATH,
    flush = flush,
    forget_items = forget_items,
    owe = owe,
    total_owed = total_owed,
}
