-- Lootable Passives -- Extract-all on the Pal Disassembly Conveyor.
--
-- Two hooks watch the machine. Each consumed Pal's extractable passives become
-- a debt in lp/ledger.lua, which delivers it.
--
--------------------------------------------------------------------------------
-- The engine surface
--------------------------------------------------------------------------------
--
-- The conveyor's class name is ConvertCharacterToItem; it contains neither
-- "Conveyor" nor "Disassembly". From CXXHeaderDump/Pal.hpp:
--
--   APalBuildObjectConvertCharacterToItem : APalBuildObject
--       void OnProceedConvertProcess_ServerInternal(
--                UPalMapObjectConvertCharacterToItemModel* Model)         <- hooked
--   UPalMapObjectConvertCharacterToItemModel : UPalMapObjectConcreteModelBase
--       TArray<FPalMapObjectConvertCharacterToItemProcessItem> ConvertProcessArray
--       void OnUpdateCharacterContainer_ServerInternal()                  <- hooked
--   FPalMapObjectConvertCharacterToItemProcessItem
--       { FPalInstanceID IndividualId; float ConvertProgressRate; }
--   FPalInstanceID { FGuid PlayerUId; FGuid InstanceId; FString DebugName; }
--   FPalIndividualCharacterSaveParameter
--       { FGuid OwnerPlayerUId; ... }                             <- read, 0x00C0
--
-- Every engine call in this file is zero-argument except container:Get(Index),
-- and none takes an out-parameter: GetContainer() rather than
-- TryGetContainer(Out&). A wrong-arity native call is an access violation pcall
-- does not catch.
--
--------------------------------------------------------------------------------
-- Three guesses at behavior (take with caution)
--------------------------------------------------------------------------------
--
-- BOTH HOOKS ARE REGISTERED. OnProceedConvertProcess fires per frame while the
-- machine is converting and stops when the queue empties;
-- OnUpdateCharacterContainer fires on arrival and departure. Each covers cases
-- the other does not.
--
-- THE PASS IS NOT THROTTLED. pass() runs on every firing of either hook. The
-- per-call cost is one array read and one GUID read; the container walk inside
-- it is guarded by bucket[key] == nil.
--
-- CONSUMED VERSUS WITHDRAWN IS DECIDED BY THE RATE ALONE: the last rate seen
-- plus twice the last step between firings, against COMPLETE_RATE. The
-- projection is there because the firing that completes a Pal can remove it
-- before a rate at the threshold is read. Whether the individual still exists
-- is not tested: a UPalIndividualCharacterParameter outlives the Pal it belongs
-- to.

local util = require("lp.util")
local config = require("lp.config")
local passives = require("lp.passives")
local ledger = require("lp.ledger")
local hooks = require("lp.hooks")

local array_count = util.array_count
local field = util.field
local guid_key = util.guid_key
local has_authority = util.has_authority
local is_valid = util.is_valid
local log = util.log
local method = util.method
local unwrap = util.unwrap
local conveyor_on = config.conveyor_on
local debug_log = config.debug_log
local get_skill_ids = passives.get_skill_ids
local instance_key = passives.instance_key
local is_extractable = passives.is_extractable
local module_for = passives.module_for
local owner_key = passives.owner_key

local PROCEED_HOOK =
"/Script/Pal.PalBuildObjectConvertCharacterToItem:OnProceedConvertProcess_ServerInternal"
local CONTAINER_HOOK =
"/Script/Pal.PalMapObjectConvertCharacterToItemModel:OnUpdateCharacterContainer_ServerInternal"

-- GUESS: ConvertProgressRate at or above this counts the Pal as consumed; below it, as withdrawn.
local COMPLETE_RATE = 0.999
-- Multiplier on the last step in the projection above.
local STEP_MARGIN = 2

--------------------------------------------------------------------------------
-- Reading the queue
--------------------------------------------------------------------------------

-- instance key -> ConvertProgressRate, for every entry in the model's queue.
--
-- Reads go through util.field rather than pcall with a closure: this runs on
-- every firing of the progress hook, once per queued Pal.
local function read_process_rates(model)
    local rates = {}
    local array = field(model, "ConvertProcessArray")
    if array == nil then
        return rates
    end
    for index = 1, array_count(array) do
        local entry = unwrap(array[index])
        if entry ~= nil then
            local key = instance_key(field(entry, "IndividualId"))
            if key ~= nil then
                rates[key] = tonumber(field(entry, "ConvertProgressRate")) or 0.0
            end
        end
    end
    return rates
end

-- Get(Index) takes an argument, so it is not util.method; passed to pcall by
-- reference like the accessors in lp/util.lua.
local function _call_get(container, index)
    return container:Get(index)
end

-- instance key -> { passives = { id, ... }, owner = <UId key or nil> }, walked
-- from the model's own character container rather than from the world's slots
-- observer, which fires for every container in the world.
local function read_queued_passives(model)
    local found = {}
    local container_module = method(model, "GetCharacterContainerModule")
    if not is_valid(container_module) then
        return found
    end
    local container = method(container_module, "GetContainer")
    if not is_valid(container) then
        return found
    end

    local slot_count = method(container, "Num") or 0
    for index = 0, slot_count - 1 do
        local got, slot = pcall(_call_get, container, index)
        slot = got and unwrap(slot) or nil
        if is_valid(slot) then
            local handle = method(slot, "GetHandle")
            if is_valid(handle) then
                local key = instance_key(field(handle, "ID"))
                local parameter = method(handle, "TryGetIndividualParameter")
                if key ~= nil and is_valid(parameter) then
                    local extractable = {}
                    for _, passive_id in ipairs(get_skill_ids(parameter) or {}) do
                        if is_extractable(passive_id) then
                            extractable[#extractable + 1] = passive_id
                        end
                    end
                    -- Owner and passives are read in the same pass, while the
                    -- parameter is still reachable from the container.
                    found[key] = { passives = extractable, owner = owner_key(parameter) }
                end
            end
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Tracking
--------------------------------------------------------------------------------

-- model key -> instance key ->
--   { passives = { id, ... }, owner = <UId key or nil>, rate = number, step = number }
--
-- One bucket per conveyor. pass(model) treats every entry missing from that
-- model's queue as having left it, so it may only look at the entries that model
-- put there.
local tracked = {}

-- Bucket key for entries whose model InstanceId does not read.
local UNKEYED_MODEL = "?"

-- The model's own InstanceId (Pal.hpp: FGuid InstanceId at 0x00A0 on
-- UPalMapObjectConcreteModelBase), a property read, and its bucket in tracked.
local function bucket_for(model)
    local key = guid_key(field(model, "InstanceId")) or UNKEYED_MODEL
    local bucket = tracked[key]
    if bucket == nil then
        bucket = {}
        tracked[key] = bucket
    end
    return bucket
end

-- Each set once, on the first occurrence.
local authority_reported = false
local unowned_reported = false

-- Gates item creation on util.has_authority, which fails closed. Shared with
-- main.lua's ledger flush; what is local here is the reporting.
local function may_create_items(actor)
    local allowed, valid_actor, asked, authoritative = has_authority(actor)
    -- Only the negative case logs: a closed gate and an unfired hook look the same in the log otherwise.
    if not allowed and not authority_reported then
        authority_reported = true
        log(string.format(
            "Conveyor extraction is INACTIVE on this peer (actorValid=%s asked=%s authority=%s). "
            .. "Expected on a multiplayer client -- the server grants instead. Unexpected in "
            .. "single-player, and would mean nothing is ever created.",
            tostring(valid_actor), tostring(asked), tostring(authoritative)))
    end
    return allowed
end

-- Records the debt, then delivers it. ledger.owe writes to disk before
-- ledger.flush is called.
local function on_consumed(entry, actor)
    if not may_create_items(actor) then
        return
    end
    if entry.owner == nil and not unowned_reported then
        unowned_reported = true
        log("No owner UId could be read from the consumed Pal, so its modules are delivered only "
            .. "while a single player is online, and held otherwise. Expected only for a Pal "
            .. "nobody owns; in single-player it means the OwnerPlayerUId read is not working.")
    end

    -- entry.passives holds only ids is_extractable accepted, and each has a module.
    local names = entry.passives
    if #names == 0 then
        return
    end
    -- One owe() call for the whole Pal: it sorts and rewrites the entire file per call.
    local owed_items = {}
    for index, passive_id in ipairs(names) do
        owed_items[index] = module_for(passive_id)
    end
    ledger.owe(entry.owner, owed_items)

    local delivered, owed, spilled, held = ledger.flush()
    local summary = string.format("Disassembly yielded %d module(s): %s.",
        #names, table.concat(names, ", "))
    if held > 0 then
        summary = summary .. string.format(
            " %d held because the player they belong to is not online, or could not be "
            .. "identified while more than one player is; held modules are delivered when "
            .. "that is resolved.", held)
    end
    if spilled > 0 then
        summary = summary .. string.format(
            " %d would not fit and %s dropped on the ground.",
            spilled, spilled == 1 and "was" or "were")
    end
    if owed > 0 then
        summary = summary .. string.format(
            " Delivered %d; %d still owed and held until there is somewhere to put them.",
            delivered, owed)
    end
    log(summary)
end

-- One pass over the model's queue: snapshots newly seen Pals, updates the rate
-- of those already tracked, and resolves entries that have left the queue.
--
-- actor is read from the model in the pass that needs it rather than cached, so
-- two conveyors cannot answer each other's authority check.
local function pass(model)
    local rates = read_process_rates(model)
    local bucket = bucket_for(model)

    -- The container walk happens only for a key not already tracked.
    local queued
    for key, rate in pairs(rates) do
        if bucket[key] == nil then
            queued = queued or read_queued_passives(model)
            local snapshot = queued[key]
            if snapshot ~= nil then
                -- read_queued_passives builds a fresh table per key, so it is
                -- kept rather than copied.
                snapshot.rate = rate
                snapshot.step = 0.0
                bucket[key] = snapshot
            end
        else
            local entry = bucket[key]
            -- Both hooks call pass, so a firing with no progress keeps the
            -- last positive step rather than resetting it.
            if rate > entry.rate then
                entry.step = rate - entry.rate
            end
            entry.rate = rate
        end
    end

    -- Gone from this model's queue: consumed when the projected rate reaches
    -- COMPLETE_RATE, withdrawn below it. A withdrawal owes nothing.
    local actor
    for key, entry in pairs(bucket) do
        if rates[key] == nil then
            bucket[key] = nil
            local consumed = entry.rate + STEP_MARGIN * entry.step >= COMPLETE_RATE
            debug_log(string.format(
                "conveyor: a Pal left the queue at rate %.4f (last step %.4f): %s",
                entry.rate, entry.step, consumed and "consumed" or "withdrawn"))
            if consumed then
                actor = actor or method(model, "GetActor")
                on_consumed(entry, actor)
            end
        end
    end
end

-- Both hook callbacks below are built once, at load, and handed to
-- hooks.register by reference; neither captures per-call state.
--
-- The container hook is zero-parameter, so its context argument is the model
-- and this is its callback as is.
--
-- With config.conveyor_on() false, returns before reading the model, and
-- empties tracked on the first such firing: a Pal tracked before the switch
-- went off is never paid for, whatever its rate.
local function pass_if_valid(model_param)
    if not conveyor_on() then
        if next(tracked) ~= nil then
            tracked = {}
            log("Conveyor extraction switched off; Pals being tracked were forgotten.")
        end
        return
    end
    local model = unwrap(model_param)
    if is_valid(model) then
        pass(model)
    end
end

-- The proceed hook's model is its first parameter, after the context.
local function on_proceed(_, model_param)
    pass_if_valid(model_param)
end

local installed = false

-- Registers both hooks, once; later calls do nothing.
local function install()
    if installed then
        return
    end
    installed = true
    hooks.register(PROCEED_HOOK, on_proceed, "the conveyor progress watcher")
    hooks.register(CONTAINER_HOOK, pass_if_valid, "the conveyor arrival/departure watcher")
end

local function is_installed()
    return installed
end

return {
    install = install,
    is_installed = is_installed,
}
