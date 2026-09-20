-- Lootable Passives -- The pending-grant ledger.
--
-- What a Pal owed when the conveyor ate it, held until someone has room.
--
-- WHY THIS EXISTS -- AND IT IS NARROWER THAN IT LOOKS.
--
-- A FULL INVENTORY IS NOT A FAILURE. Measured in game: AddItem_ServerInternal
-- returns Success with a full bag and the engine spills the item onto the
-- ground at the player's feet. The item is created either way. An earlier
-- comment here claimed it failed with FailedContainerOverflowSlotNum and that
-- was simply wrong -- the enum value exists, this path does not produce it.
-- That wrong belief caused real duplication, because a spill was scored as a
-- failure, left owed, and granted again on the next pass.
--
-- So this file is NOT the answer to a full inventory; the engine is. What is
-- left for it is the case where there is no one to grant to at all -- an
-- unattended base, or a dedicated server with nobody online -- plus surviving
-- a crash between a Pal being destroyed and its modules being created. Both
-- are real, and neither is the common path.
--
-- WHY IT IS KEYED BY OWNER AND ITEM, NOT BY EVENT. One row per player per
-- module type, counted. That caps the file at the 115 module types that exist
-- times the players in the save, no matter how many Pals go through the machine,
-- so the size bound still falls out of the shape instead of being a limit
-- someone has to pick and tune. AddItem takes a Count, so a row of 40 is one
-- call, not 40.
--
-- The owner half is load-bearing in multiplayer. A Pal's modules belong to the
-- player who owned the Pal, and a debt that outlives the moment it was incurred
-- has to remember whose it was -- otherwise the next delivery pays every
-- outstanding row to whoever is standing nearest, which is exactly the bug this
-- replaced.
--
-- WHERE IT LIVES. Beside the recovery journal at the UE4SS root, and for the
-- same reason: Scripts\ is inside the tree the official mod loader wipes and
-- reinstalls whenever Version changes in Info.json, which would throw away
-- every outstanding debt on an update.

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local inventory = require("lp.inventory")

local log = util.log
local write_lines = util.write_lines

local UE4SS_ROOT = util.SCRIPT_DIRECTORY:match("^(.*[\\/]UE4SS[\\/])") or util.SCRIPT_DIRECTORY
local LEDGER_PATH = UE4SS_ROOT .. "LootablePassives_pending.tsv"

-- Bump if the column layout changes. A ledger stamped otherwise is from a
-- different build and is discarded rather than guessed at -- the loader can
-- leave one orphaned across an update.
--
-- LPL1 is still READ, and deliberately: it is the same debt, one column short.
-- Discarding it would throw away modules a player is owed purely because they
-- updated the mod, and the missing column has a safe reading -- "for nobody in
-- particular", which is how every LPL1 row behaved anyway.
local LEDGER_VERSION = "LPL2"
local LEDGER_VERSION_LEGACY = "LPL1"

-- The game's own stack ceiling for these items. Past it AddItem would fail
-- forever on a row that can never be delivered, so the count saturates and the
-- overflow is dropped -- loudly, because it is the one case where this file
-- does lose something.
local MAX_STACK = 9999

-- owner UId key -> item id -> count owed.
--
-- ANY_OWNER covers the two cases with no player attached: a Pal with no
-- OwnerPlayerUId recorded, and rows read back from an LPL1 ledger. Those fall
-- through to the fallback order in delivery_candidates, which is what every row
-- used to do.
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

local function pending_rows()
    local rows = {}
    for owner, items in pairs(pending) do
        for item_id, count in pairs(items) do
            if count > 0 then
                rows[#rows + 1] = { owner = owner, item_id = item_id, count = count }
            end
        end
    end
    -- Sorted so the file is stable between writes and a diff of it means
    -- something.
    table.sort(rows, function(a, b)
        if a.owner ~= b.owner then
            return a.owner < b.owner
        end
        return a.item_id < b.item_id
    end)
    return rows
end

local function total_owed()
    local total = 0
    for _, items in pairs(pending) do
        for _, count in pairs(items) do
            total = total + count
        end
    end
    return total
end

local function persist()
    local rows = pending_rows()
    if #rows == 0 then
        if os ~= nil and type(os.remove) == "function" then
            pcall(os.remove, LEDGER_PATH)
        end
        return true
    end
    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = table.concat(
            { LEDGER_VERSION, row.owner, row.item_id, tostring(row.count) }, "\t")
    end
    return write_lines(LEDGER_PATH, lines, "pending-grant ledger")
end

-- Every id is re-checked against passive_items.lua on load. A row naming an
-- item this build no longer defines would be ungrantable forever, and silently
-- retrying it on every flush is worse than saying so once and dropping it.
local function load()
    if loaded then
        return
    end
    loaded = true
    if io == nil or type(io.open) ~= "function" then
        return
    end
    local opened, handle = pcall(io.open, LEDGER_PATH, "r")
    if not opened or handle == nil then
        return
    end
    local known = {}
    for _, item_id in pairs(PASSIVE_ITEMS) do
        known[item_id] = true
    end
    local discarded = 0
    while true do
        local read_ok, line = pcall(handle.read, handle, "*l")
        if not read_ok or line == nil then
            break
        end
        local version, owner, item_id, count =
            line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if version == nil then
            -- Three columns: an LPL1 row. Same debt, owner unknown.
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
        elseif not known[item_id] then
            discarded = discarded + 1
        else
            local bucket = bucket_for(owner)
            bucket[item_id] = math.min(MAX_STACK, (bucket[item_id] or 0) + math.floor(number))
        end
    end
    pcall(handle.close, handle)
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

-- Record a debt. Called the instant a Pal is confirmed consumed, before any
-- attempt to deliver, so a crash between the two costs nothing.
--
-- owner is the Pal's OwnerPlayerUId key, or nil when the engine recorded none.
local function owe(owner, item_id, count)
    load()
    local bucket = bucket_for(owner or ANY_OWNER)
    local current = bucket[item_id] or 0
    local wanted = current + (count or 1)
    if wanted > MAX_STACK then
        log(string.format(
            "WARNING: pending %s is capped at %d; %d module(s) could not be recorded and are lost.",
            item_id, MAX_STACK, wanted - MAX_STACK))
        wanted = MAX_STACK
    end
    bucket[item_id] = wanted
    local written = persist()
    if not written then
        -- The debt is in memory but not on disk, so a crash or restart loses
        -- it. Say so: silently holding an unpersisted IOU is the failure mode
        -- the journal's own writability check exists to prevent.
        log(string.format(
            "WARNING: could not write the pending-grant ledger at %s. %s is owed in memory only "
            .. "and will be lost if the game closes before it is delivered.", LEDGER_PATH, item_id))
    end
    return written
end

-- Said once per session. The degraded case below is a code fault, not a
-- situation, and repeating it per row per flush would bury it.
local uid_warning_reported = false

-- Who may receive this row, in order. Empty means HOLD IT.
--
-- Returns recipients, degraded.
--
-- A row with a known owner goes to that owner and to nobody else. It is a list
-- rather than a single candidate only because a grant can still fail -- see
-- add_modules -- and two characters for one player is a state the engine can
-- briefly be in.
--
-- HOLDING IS THE POINT, and it is why this is not a mere preference. A guest
-- can queue ten Pals and log off while the machine is still eating them; a
-- preference with a fallback would then hand all ten Pals' modules to the host,
-- which is the behaviour this whole change exists to remove. The debt is on
-- disk, and it is retried on every map load and on every later disassembly, so
-- holding costs the player nothing but time.
--
-- THE ONE FALLBACK is for the comparison not running at all. If no candidate
-- yields a readable PlayerUId then the fault is ours, not the player's, and
-- withholding modules over a broken read would be a silent regression -- so pay
-- out in the old order and say loudly that it happened. A uid that is readable
-- and simply does not match is a different answer and is trusted.
local function ordered_for(owner, candidates)
    if owner == ANY_OWNER then
        return candidates, false
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
        return matched, false
    end
    if not readable then
        if not uid_warning_reported then
            uid_warning_reported = true
            log("WARNING: no player UId could be read from any candidate, so modules cannot be "
                .. "matched to the player who owned the Pal. Delivering to the nearest player "
                .. "instead. This is a fault in the mod, not in the save.")
        end
        return others, true
    end
    return {}, false
end

-- Deliver what is owed.
--
-- A ROW GOES TO ITS OWNER FIRST. That is the rule; delivery_candidates supplies
-- only the order to work down when the owner is not online, and near_location
-- breaks ties within it by distance to the machine.
--
-- A player whose bag is full is skipped, not waited on: the next candidate is
-- tried. Anything still owed at the end simply stays owed.
--
-- Returns delivered, owed, spilled, held -- where held counts modules kept back
-- because the player they belong to is not online. Held is not an error and is
-- not warned about here; the caller decides whether it is worth a line.
local function flush(near_location)
    load()
    local rows = pending_rows()
    if #rows == 0 then
        return 0, 0, 0, 0
    end
    local candidates = inventory.delivery_candidates(near_location)
    if #candidates == 0 then
        -- Distinct from "everyone is full", and worth distinguishing: this is
        -- what a wrong class name or an unloaded world looks like.
        log(string.format("No player inventory available; %d module(s) stay owed.", total_owed()))
        return 0, total_owed(), 0, 0
    end

    local delivered, spilled, held, changed = 0, 0, 0, false
    for _, row in ipairs(rows) do
        local recipients = ordered_for(row.owner, candidates)
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
            -- The owner is not online. Silent by design: the caller reports it
            -- once per disassembly, and a per-row line here would repeat it up
            -- to four times for one Pal.
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
    load = load,
    owe = owe,
    total_owed = total_owed,
}
