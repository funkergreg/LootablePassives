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
-- TryGetContainer(Out&), K2_GetActorLocation() rather than
-- GetMapObjectLocation(FVector&). A wrong-arity native call is an access
-- violation pcall does not catch; see CLAUDE.md.
--
--------------------------------------------------------------------------------
-- Three things not to change without reading docs/PLAN.md first
--------------------------------------------------------------------------------
--
-- BOTH HOOKS ARE REGISTERED. OnProceedConvertProcess fires per frame while the
-- machine is converting and stops when the queue empties;
-- OnUpdateCharacterContainer fires on arrival and departure. Each covers cases
-- the other does not.
--
-- THE PASS IS NOT THROTTLED. pass() runs on every firing of either hook. The
-- per-call cost is one array read; the container walk inside it is guarded by
-- tracked[key] == nil.
--
-- CONSUMED VERSUS WITHDRAWN IS DECIDED BY COMPLETE_RATE, and by nothing else.
-- Do not substitute a test for whether the individual still exists: a
-- UPalIndividualCharacterParameter outlives the Pal it belongs to.

local util = require("lp.util")
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
local get_skill_ids = passives.get_skill_ids
local is_extractable = passives.is_extractable
local module_for = passives.module_for

local PROCEED_HOOK =
"/Script/Pal.PalBuildObjectConvertCharacterToItem:OnProceedConvertProcess_ServerInternal"
local CONTAINER_HOOK =
"/Script/Pal.PalMapObjectConvertCharacterToItemModel:OnUpdateCharacterContainer_ServerInternal"

-- ConvertProgressRate at or above this counts the Pal as consumed; below it, as
-- withdrawn. See CLAUDE.md for the measurements behind the value.
local COMPLETE_RATE = 0.999

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

-- A Pal's InstanceId GUID as a comparable string. Property reads only, through
-- util.guid_key, which the player-state side of the owner comparison also uses.
local function instance_key(instance_id)
    instance_id = unwrap(instance_id)
    if instance_id == nil then
        return nil
    end
    return guid_key(field(instance_id, "InstanceId"))
end

-- The Pal's OwnerPlayerUId as a comparable string, or nil when it reads as the
-- null GUID.
--
-- OwnerPlayerUId is on the individual's SaveParameter struct, so this is two
-- property reads. GetSaveParameter() returns the struct by value and is not
-- called.
local function owner_key(parameter)
    local save = unwrap(field(parameter, "SaveParameter"))
    if save == nil then
        return nil
    end
    return guid_key(field(save, "OwnerPlayerUId"))
end

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
                rates[key] = tonumber(unwrap(field(entry, "ConvertProgressRate"))) or 0.0
            end
        end
    end
    return rates
end

-- instance key -> { passives = { id, ... }, owner = <UId key or nil> }, walked
-- from the model's own character container rather than from the world's slots
-- observer, which fires for every container in the world.
local function read_queued_passives(model)
    local found = {}
    local container_module = unwrap(method(model, "GetCharacterContainerModule"))
    if not is_valid(container_module) then
        return found
    end
    local container = unwrap(method(container_module, "GetContainer"))
    if not is_valid(container) then
        return found
    end

    local slot_count = unwrap(method(container, "Num")) or 0
    for index = 0, slot_count - 1 do
        local slot
        -- Get(Index) takes an argument, so it is written out: util.method is for
        -- zero-arity calls only.
        pcall(function() slot = unwrap(container:Get(index)) end)
        if is_valid(slot) then
            local handle = unwrap(method(slot, "GetHandle"))
            if is_valid(handle) then
                local key = instance_key(field(handle, "ID"))
                local parameter = unwrap(method(handle, "TryGetIndividualParameter"))
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

-- instance key -> { passives = { id, ... }, owner = <UId key or nil>,
--                   rate = number }
--
-- Keyed by InstanceId, which is unique across the world, so entries from two
-- conveyors share one table without colliding.
local tracked = {}

-- Each set once, on the first occurrence.
local authority_reported = false
local unowned_reported = false

-- Gates item creation on util.has_authority, which fails closed. Shared with
-- main.lua's ledger flush; what is local here is the reporting.
local function may_create_items(actor)
    local allowed, valid_actor, asked, authoritative = has_authority(actor)
    -- Only the negative case logs: a closed gate and an unfired hook look the
    -- same in the log otherwise.
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

local function actor_location(actor)
    if not is_valid(actor) then
        return nil
    end
    return method(actor, "K2_GetActorLocation")
end

-- Records the debt, then delivers it. ledger.owe writes to disk before
-- ledger.flush is called; do not reorder these.
local function on_consumed(entry, actor)
    if not may_create_items(actor) then
        return
    end
    if entry.owner == nil and not unowned_reported then
        unowned_reported = true
        log("No owner UId could be read from the consumed Pal, so its modules go to the nearest "
            .. "player rather than to whoever owned it. Expected only for a Pal nobody owns; in "
            .. "single-player it means the OwnerPlayerUId read is not working.")
    end

    -- One owe() call for the whole Pal: it sorts and rewrites the entire file
    -- per call.
    local names, owed_items = {}, {}
    for _, passive_id in ipairs(entry.passives) do
        local item_id = module_for(passive_id)
        if item_id ~= nil then
            owed_items[#owed_items + 1] = item_id
            names[#names + 1] = passive_id
        end
    end
    if #names == 0 then
        return
    end
    ledger.owe(entry.owner, owed_items)

    -- Logged BEFORE the delivery call, so this line with no summary line after
    -- it localises a crash to the delivery. Remove once docs/PLAN.md no longer
    -- lists an unexplained CTD.
    log(string.format("Disassembly consumed a Pal owing %d module(s); delivering.", #names))
    local delivered, owed, spilled, held = ledger.flush(actor_location(actor))
    local summary = string.format("Disassembly yielded %d module(s): %s.",
        #names, table.concat(names, ", "))
    if held > 0 then
        summary = summary .. string.format(
            " %d held for the player who owned the Pal, who is not online; they are delivered "
            .. "when that player next plays.", held)
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
-- actor is read from the model on every pass rather than cached, so two
-- conveyors cannot answer each other's authority check or drop location.
local function pass(model)
    local actor = unwrap(method(model, "GetActor"))
    local rates = read_process_rates(model)

    -- The container walk happens only for a key not already tracked.
    local queued
    for key, rate in pairs(rates) do
        if tracked[key] == nil then
            queued = queued or read_queued_passives(model)
            local snapshot = queued[key]
            if snapshot ~= nil then
                tracked[key] = {
                    passives = snapshot.passives,
                    owner = snapshot.owner,
                    rate = rate,
                }
            end
        else
            tracked[key].rate = rate
        end
    end

    -- Gone from the queue: consumed at or above COMPLETE_RATE, withdrawn below
    -- it. A withdrawal owes nothing and logs nothing.
    for key, entry in pairs(tracked) do
        if rates[key] == nil then
            tracked[key] = nil
            if entry.rate >= COMPLETE_RATE then
                on_consumed(entry, actor)
            end
        end
    end
end

-- Both callbacks are built once, at load, and handed to hooks.register by
-- reference; neither captures per-call state. See lp/hooks.lua.
local function on_proceed(_, model_param)
    local model = unwrap(model_param)
    if is_valid(model) then
        pass(model)
    end
end

-- Zero-parameter hook: the context argument is the model.
local function on_container_update(context)
    local model = unwrap(context)
    if is_valid(model) then
        pass(model)
    end
end

local function install()
    hooks.register(PROCEED_HOOK, on_proceed, "the conveyor progress watcher")
    hooks.register(CONTAINER_HOOK, on_container_update, "the conveyor arrival/departure watcher")
end

return {
    install = install,
}
