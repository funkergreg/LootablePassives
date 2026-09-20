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
-- WHY IT IS KEYED BY ITEM, NOT BY EVENT. One row per module type, counted. That
-- caps the file at the 115 module types that exist, no matter how many Pals go
-- through the machine, so the size bound falls out of the shape instead of
-- being a limit someone has to pick and tune. AddItem takes a Count, so a row
-- of 40 is one call, not 40.
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
local LEDGER_VERSION = "LPL1"

-- The game's own stack ceiling for these items. Past it AddItem would fail
-- forever on a row that can never be delivered, so the count saturates and the
-- overflow is dropped -- loudly, because it is the one case where this file
-- does lose something.
local MAX_STACK = 9999

-- item id -> count owed.
local pending = {}
local loaded = false

local function pending_rows()
    local rows = {}
    for item_id, count in pairs(pending) do
        if count > 0 then
            rows[#rows + 1] = { item_id = item_id, count = count }
        end
    end
    table.sort(rows, function(a, b) return a.item_id < b.item_id end)
    return rows
end

local function total_owed()
    local total = 0
    for _, count in pairs(pending) do
        total = total + count
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
        lines[#lines + 1] = table.concat({ LEDGER_VERSION, row.item_id, tostring(row.count) }, "\t")
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
        local version, item_id, count = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
        local number = tonumber(count)
        if version ~= LEDGER_VERSION or item_id == nil or number == nil or number <= 0 then
            discarded = discarded + 1
        elseif not known[item_id] then
            discarded = discarded + 1
        else
            pending[item_id] = math.min(MAX_STACK, (pending[item_id] or 0) + math.floor(number))
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
local function owe(item_id, count)
    load()
    local current = pending[item_id] or 0
    local wanted = current + (count or 1)
    if wanted > MAX_STACK then
        log(string.format(
            "WARNING: pending %s is capped at %d; %d module(s) could not be recorded and are lost.",
            item_id, MAX_STACK, wanted - MAX_STACK))
        wanted = MAX_STACK
    end
    pending[item_id] = wanted
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

-- Deliver what is owed.
--
-- near_location, when given, breaks ties by distance to the machine. It is only
-- a tiebreak: delivery_candidates puts the LOCAL player first regardless,
-- because they are the one certain to have the mod's item definitions. See the
-- note there -- that ordering is a safety rule, not a convenience.
--
-- A player whose bag is full is skipped, not waited on: the next candidate is
-- tried. Anything still owed at the end simply stays owed.
local function flush(near_location)
    load()
    local rows = pending_rows()
    if #rows == 0 then
        return 0, 0, 0
    end
    local candidates = inventory.delivery_candidates(near_location)
    if #candidates == 0 then
        -- Distinct from "everyone is full", and worth distinguishing: this is
        -- what a wrong class name or an unloaded world looks like.
        log(string.format("No player inventory available; %d module(s) stay owed.", total_owed()))
        return 0, total_owed(), 0
    end

    local delivered, spilled, changed = 0, 0, false
    for _, row in ipairs(rows) do
        local reason = nil
        for _, data in ipairs(candidates) do
            local granted, detail = inventory.add_modules(data, row.item_id, row.count)
            if granted then
                pending[row.item_id] = nil
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
        if reason ~= nil then
            log(string.format("Could not deliver %s x%d to any of %d player(s): %s. Still owed.",
                row.item_id, row.count, #candidates, tostring(reason)))
        end
    end
    if changed then
        persist()
    end
    return delivered, total_owed(), spilled
end

return {
    LEDGER_PATH = LEDGER_PATH,
    flush = flush,
    load = load,
    owe = owe,
    total_owed = total_owed,
}
