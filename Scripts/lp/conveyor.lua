-- Lootable Passives -- Extract-all on the Pal Disassembly Conveyor.
--
-- A Pal consumed by the conveyor owes one module per extractable passive. The
-- debt goes to lp/ledger.lua and is delivered to a player's inventory: now if
-- there is room, later if there is not.
--
--------------------------------------------------------------------------------
-- The engine surface
--------------------------------------------------------------------------------
--
-- The conveyor's internal name contains neither "Conveyor" nor "Disassembly".
-- It is ConvertCharacterToItem. Verified against CXXHeaderDump/Pal.hpp:
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
--
-- Every engine call below takes no arguments except Get(Index), and none has an
-- out-parameter. Deliberate: a wrong-arity native call is an access violation
-- pcall cannot catch. TryGetContainer(Out&) and GetMapObjectLocation(FVector&)
-- are avoided in favour of GetContainer() and K2_GetActorLocation().
--
--------------------------------------------------------------------------------
-- Three things that are load-bearing, each learned the hard way
--------------------------------------------------------------------------------
--
-- BOTH HOOKS ARE REQUIRED. OnProceedConvertProcess fires per frame while the
-- machine is converting and goes SILENT once the queue empties, so on its own a
-- departure went unnoticed until the next insertion -- and consuming the last
-- Pal in a queue would never have granted at all. The container's own change
-- notification catches arrival and departure.
--
-- DO NOT THROTTLE THE PASS. An earlier version sampled at most twice a second
-- against os.clock(), which left the last-seen progress rate stale by up to a
-- second and silently misfiled completed conversions as withdrawals. The
-- per-call cost is one small array read; the expensive container walk is
-- already guarded by tracked[key] == nil.
--
-- CONSUMED VS WITHDRAWN IS THE PROGRESS RATE, and nothing else. It runs past
-- 1.0 exactly when a conversion completes -- measured at 1.000, 1.002, 1.003,
-- 1.004, 1.014 -- while a Pal pulled out by hand sat at 0.217, 0.238, 0.293,
-- 0.383. Do NOT replace this with an "is the individual still findable" test:
-- that answered "still exists" for all four consumed Pals, because a
-- UPalIndividualCharacterParameter outlives the Pal it belongs to, and it cost
-- 240-330 ms per departure walking 1776 objects.

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local passives = require("lp.passives")
local ledger = require("lp.ledger")
local hooks = require("lp.hooks")

local array_count = util.array_count
local is_valid = util.is_valid
local log = util.log
local unwrap = util.unwrap
local get_skill_ids = passives.get_skill_ids
local is_extractable = passives.is_extractable

local PROCEED_HOOK =
"/Script/Pal.PalBuildObjectConvertCharacterToItem:OnProceedConvertProcess_ServerInternal"
local CONTAINER_HOOK =
"/Script/Pal.PalMapObjectConvertCharacterToItemModel:OnUpdateCharacterContainer_ServerInternal"

-- A conversion that reaches this is complete; below it the Pal was taken back
-- out. See the note above for the measured separation, which is the whole scale.
local COMPLETE_RATE = 0.999

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

-- A queued Pal is keyed by the four int32s of its InstanceId GUID. These are
-- PROPERTY reads on plain structs, not calls, so there is no arity to get wrong.
local function guid_key(guid)
    guid = unwrap(guid)
    if guid == nil then
        return nil
    end
    local key
    pcall(function()
        key = string.format("%d-%d-%d-%d",
            unwrap(guid.A) or 0, unwrap(guid.B) or 0,
            unwrap(guid.C) or 0, unwrap(guid.D) or 0)
    end)
    if key == "0-0-0-0" then
        return nil -- the null GUID: an empty entry, not a Pal
    end
    return key
end

local function instance_key(instance_id)
    instance_id = unwrap(instance_id)
    if instance_id == nil then
        return nil
    end
    local guid
    pcall(function() guid = instance_id.InstanceId end)
    return guid_key(guid)
end

--------------------------------------------------------------------------------
-- Reading the queue
--------------------------------------------------------------------------------

local function read_process_rates(model)
    local rates = {}
    local array
    if not pcall(function() array = model.ConvertProcessArray end) or array == nil then
        return rates
    end
    for index = 1, array_count(array) do
        local entry = unwrap(array[index])
        if entry ~= nil then
            local key, rate
            pcall(function() key = instance_key(entry.IndividualId) end)
            pcall(function() rate = unwrap(entry.ConvertProgressRate) end)
            if key ~= nil then
                rates[key] = tonumber(rate) or 0.0
            end
        end
    end
    return rates
end

-- instance key -> the extractable passives that Pal is carrying.
--
-- Read from the conveyor's OWN character container via the model, not from the
-- generic slots observer: that observer fires for every container in the world
-- and matching it back to one machine is work this does not need to do.
local function read_queued_passives(model)
    local found = {}
    local module
    if not pcall(function() module = unwrap(model:GetCharacterContainerModule()) end) then
        return found
    end
    if not is_valid(module) then
        return found
    end
    local container
    if not pcall(function() container = unwrap(module:GetContainer()) end) then
        return found
    end
    if not is_valid(container) then
        return found
    end

    local slot_count = 0
    pcall(function() slot_count = unwrap(container:Num()) or 0 end)
    for index = 0, slot_count - 1 do
        local slot
        pcall(function() slot = unwrap(container:Get(index)) end)
        if is_valid(slot) then
            local handle
            pcall(function() handle = unwrap(slot:GetHandle()) end)
            if is_valid(handle) then
                local key
                pcall(function() key = instance_key(handle.ID) end)
                local parameter
                pcall(function() parameter = unwrap(handle:TryGetIndividualParameter()) end)
                if key ~= nil and is_valid(parameter) then
                    local extractable = {}
                    for _, passive_id in ipairs(get_skill_ids(parameter) or {}) do
                        if is_extractable(passive_id) then
                            extractable[#extractable + 1] = passive_id
                        end
                    end
                    found[key] = extractable
                end
            end
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Tracking
--------------------------------------------------------------------------------

-- instance key -> { passives = { id, ... }, rate = number }
--
-- Keyed globally rather than per model on purpose: the key is the Pal's own
-- InstanceId, unique across the world, so two conveyors running at once cannot
-- collide and a Pal cannot be in two queues.
local tracked = {}

-- Reported ONCE, the first time it matters. The gate fails closed, so a wrong
-- answer makes the whole feature silently inert -- which is indistinguishable
-- from the hooks not firing unless it says which it was.
local authority_reported = false

-- Only the authoritative peer may create items.
--
-- Every hook here is a _ServerInternal function, so on a client they should not
-- fire for remote-initiated work -- but "should not" is not a safeguard, and
-- the ledger also flushes unprompted on map load. A client running
-- AddItem_ServerInternal locally would mint an item the server knows nothing
-- about: it vanishes on reload at best, and desyncs the container at worst.
--
-- AActor::HasAuthority() is 0-arg on the machine's own actor. Deliberately not
-- UGameplayStatics::IsServer(WorldContextObject): that is the CDO-call-with-
-- world-context shape implicated in this session's access violation, and there
-- is no reason to take that risk for a boolean.
--
-- Fails CLOSED. If authority cannot be established, nothing is created.
local function may_create_items(actor)
    local valid_actor = is_valid(actor)
    local authoritative = false
    local asked = false
    if valid_actor then
        asked = pcall(function() authoritative = actor:HasAuthority() == true end)
    end
    local allowed = valid_actor and asked and authoritative
    -- Only the NEGATIVE case is worth a line. "It works" is evidenced by the
    -- Disassembly lines that follow; "it silently will not" is not evidenced by
    -- anything, because the gate fails closed and looks exactly like the hooks
    -- never firing.
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
    local location
    pcall(function() location = actor:K2_GetActorLocation() end)
    return location
end

-- The Pal is already gone by the time this runs, so the debt is RECORDED FIRST
-- and delivered second. A crash between the two costs nothing; the other order
-- would lose the passives outright.
local function on_consumed(entry, actor)
    if not may_create_items(actor) then
        -- A client saw the conversion but the server owns the outcome. Say
        -- nothing: the authoritative peer is handling it, and a warning here
        -- would fire for every Pal every guest watches.
        return
    end
    local names = {}
    for _, passive_id in ipairs(entry.passives) do
        local item_id = PASSIVE_ITEMS[passive_id]
        if item_id ~= nil then
            ledger.owe(item_id, 1)
            names[#names + 1] = passive_id
        end
    end
    if #names == 0 then
        return
    end

    -- One line, cause before effect. The spill notice used to print from
    -- inside flush, ahead of the summary it explains, which read backwards.
    local delivered, owed, spilled = ledger.flush(actor_location(actor))
    local summary = string.format("Disassembly yielded %d module(s): %s.",
        #names, table.concat(names, ", "))
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

-- The actor comes from the MODEL, not from a stashed "last seen" reference.
-- With two conveyors running, a single shared slot would flip between them and
-- the authority check and drop location could be answered by the wrong machine.
local function pass(model)
    local actor = nil
    pcall(function() actor = unwrap(model:GetActor()) end)
    local rates = read_process_rates(model)

    -- First sighting: snapshot while the Pal still exists. This is the only
    -- chance -- once the entry disappears the parameter is gone with it.
    local queued
    for key, rate in pairs(rates) do
        if tracked[key] == nil then
            queued = queued or read_queued_passives(model)
            local extractable = queued[key]
            if extractable ~= nil then
                tracked[key] = { passives = extractable, rate = rate }
            end
        else
            tracked[key].rate = rate
        end
    end

    for key, entry in pairs(tracked) do
        if rates[key] == nil then
            tracked[key] = nil
            if entry.rate >= COMPLETE_RATE then
                on_consumed(entry, actor)
            end
            -- Below the completion mark the Pal was withdrawn and is alive.
            -- Nothing is owed and nothing is said.
        end
    end
end

-- Both callbacks are built ONCE, at load, and handed to hooks.register by
-- reference. Neither captures per-call state -- see the note at the top of
-- hooks.lua for why that matters more here than it looks.
local function on_proceed(_, model_param)
    local model = unwrap(model_param)
    if is_valid(model) then
        pass(model)
    end
end

-- No arguments: the context IS the model.
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
