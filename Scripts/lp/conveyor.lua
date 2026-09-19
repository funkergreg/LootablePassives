-- Lootable Passives -- Extract-all on the Pal Disassembly Conveyor.
--
--                        *** OBSERVATION PASS. GRANTS NOTHING YET. ***
--
-- DRY_RUN below is true. This module watches a conveyor consume a Pal and logs
-- the modules it WOULD hand over. It does not create an item.
--
--------------------------------------------------------------------------------
-- The engine surface
--------------------------------------------------------------------------------
--
-- The conveyor's internal name contains neither "Conveyor" nor "Disassembly".
-- It is ConvertCharacterToItem. Verified against CXXHeaderDump/Pal.hpp:
--
--   APalBuildObjectConvertCharacterToItem : APalBuildObject                  (9959)
--       UPalMapObjectConvertCharacterToItemParameterComponent* ConvertCharacterToItemParameter
--       void OnProceedConvertProcess_ServerInternal(
--                UPalMapObjectConvertCharacterToItemModel* Model)            <- hooked
--
--   UPalMapObjectConvertCharacterToItemModel : UPalMapObjectConcreteModelBase (26713)
--       TArray<FPalMapObjectConvertCharacterToItemProcessItem> ConvertProcessArray
--       void OnUpdateCharacterContainer_ServerInternal()                     <- hooked
--
--   FPalMapObjectConvertCharacterToItemProcessItem                           (5031)
--       { FPalInstanceID IndividualId; float ConvertProgressRate; }
--
--   FPalInstanceID { FGuid PlayerUId; FGuid InstanceId; FString DebugName; }
--   FGuid          { int32 A, B, C, D; }
--
-- ARITY IS CHECKED, and it has to be: a wrong-arity native call is an access
-- violation that pcall does NOT catch. Every engine call here takes no
-- arguments except Get(Index), and none has an out-parameter:
--
--   model:GetCharacterContainerModule()   -> UPalMapObjectCharacterContainerModule
--   module:GetContainer()                 -> UPalIndividualCharacterContainer
--   container:Num()                       -> int32
--   container:Get(Index)                  -> UPalIndividualCharacterSlot
--   slot:GetHandle()                      -> UPalIndividualCharacterHandle
--   handle:TryGetIndividualParameter()    -> UPalIndividualCharacterParameter
--   parameter:GetPassiveSkillList()       -> TArray<FName>   (already used elsewhere)
--
-- Deliberately NOT used: TryGetContainer(OutContainer&) and
-- GetMapObjectLocation(FVector&) take out-parameters. GetContainer() and
-- GetTransform() return the same information by value.
--
--------------------------------------------------------------------------------
-- What the first observation session established (2026-09-19)
--------------------------------------------------------------------------------
--
-- SURVEY: containerSlots=10 queueCapacity=3 processTime=5.0 itemContainerModule=none
--
--  * THE MACHINE HAS NO OUTPUT CONTAINER. `GetItemContainerModule()` returns
--    nothing, which settles the question this module was written to ask: the
--    produced items really are world drops, and modules cannot simply be added
--    to a container on the machine. Whatever the grant path turns out to be, it
--    is not that. The remaining candidates are a world drop (build a temp
--    container and a DropItem map object) or the player's inventory via
--    inventory.lua, with a stated limitation for guilds and dedicated servers.
--
--  * ONE HOOK WAS NOT ENOUGH, and the way it failed is the lesson.
--    OnProceedConvertProcess fires only while the machine is actively
--    converting. With the queue empty it goes silent, so a Pal leaving was not
--    noticed until the NEXT Pal was inserted -- both events landing in the same
--    millisecond, and a Pal removed and re-inserted in between never being
--    seen leaving at all, so re-insertion looked like a no-op. If the last Pal
--    in a queue were consumed and nothing else inserted, the grant would simply
--    never fire. OnUpdateCharacterContainer_ServerInternal is the fix: the
--    container's own change notification, which fires on arrival AND departure.
--
--  * THE PROGRESS THRESHOLD LOOKED WRONG AND WAS NOT. Departures were first
--    observed at rate 0.913 and 0.303, which read as "the rate is unusable".
--    It was the MEASUREMENT that was broken: an os.clock() throttle meant the
--    last sample held was stale by up to a second. With the throttle gone the
--    second session was unambiguous -- consumptions at 1.002, 1.004, 1.002,
--    1.003, withdrawals at 0.293 and 0.238. The rate overshoots 1.0 on
--    completion and is nowhere near it otherwise. See COMPLETE_RATE.
--
--  * AN EXISTENCE TEST DOES NOT WORK, and this is worth not rediscovering.
--    Asking whether the individual is still findable after it leaves the queue
--    returned "still exists" for all four CONSUMED Pals: a
--    UPalIndividualCharacterParameter outlives the Pal it belongs to. It also
--    cost 240-330 ms per departure walking 1776 objects -- a quarter-second
--    stall on the game thread. Do not reach for FindAllOf here again.
--
--------------------------------------------------------------------------------
-- Why capture-then-resolve, and why the journal has to lead here
--------------------------------------------------------------------------------
--
-- On the Surgery Table the module is granted BEFORE the passive is removed, so
-- a crash mid-exchange duplicates an item rather than destroying a passive.
-- That ordering is impossible here: the game destroys the Pal on its own
-- schedule and does not ask. So the passive list is read while the Pal is still
-- queued -- on FIRST SIGHTING -- and held until it leaves.
--
-- That makes the recovery journal the primary safety net rather than the
-- exception path, and it is the piece still to be written.
--
--------------------------------------------------------------------------------
-- Still open, and how to close it
--------------------------------------------------------------------------------
--
--  1. UNATTENDED. Does any of this fire while no player is near the base, and
--     is there a recipient when it does? The RECIPIENT line answers both: it
--     reports playerStates and whether an inventory resolves, at the instant of
--     each departure. Read together with the timestamps it also says whether
--     conversions ran while away or were replayed in a burst on return.
--     This is the question that decides the grant path.
--  2. A PAL WITHDRAWN AT 0.999+. Not observed and probably not reachable by
--     hand -- it is a ~10 ms window out of a 5 s conversion -- but if it
--     happens the Pal is treated as consumed and gets its passives duplicated.
--     Erring the other way would destroy them instead, which is worse.
--
-- CLOSED: cadence. OnProceedConvertProcess fires per frame while converting
-- (~14-33/s; 989 calls in 69 s), OnUpdateCharacterContainer only on a slot
-- change (11 in the same span). The per-call cost is one small array read, so
-- no throttle -- the throttle is what broke the rate measurement in the first
-- place.
--
--------------------------------------------------------------------------------
-- TRACING -- temporary, and all of it comes out together
--------------------------------------------------------------------------------
--
-- Every branch below reports entry and exit, including the ones that return
-- early. That is deliberate and it is why: the first observation session lost a
-- Pal's departure entirely and misfiled two consumptions, and neither showed up
-- as an error -- they showed up as MISSING LINES. A silent early return is
-- indistinguishable from a path that never ran, so while this is being
-- characterised every path says so.
--
-- trace() is local to this file, unconditional, and BUDGETED: after
-- TRACE_BUDGET lines it stops and says so once, which keeps a hook that turns
-- out to fire per frame from filling the disk. The state-transition lines --
-- QUEUED, CONSUMED, WITHDRAWN, WARNING, SURVEY -- go through log() instead and
-- are never budgeted, so exhausting the trace can never hide the events that
-- matter.
--
-- There is deliberately NO settings switch for this. The mod's verbose/diag
-- channel was deleted on purpose; this is not a reprise of it. It is scaffolding
-- for one question, it lives in one file, and it comes out with DRY_RUN.
--
-- Once those are answered: write the grant path, journal each snapshot at first
-- sighting (state "pending", phase "conveyor") so recovery.lua can replay an
-- interrupted grant, then delete DRY_RUN, the survey, the cadence counter and
-- this section.

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local passives = require("lp.passives")
local inventory = require("lp.inventory")
local hooks = require("lp.hooks")

local array_count = util.array_count
local is_valid = util.is_valid
local log = util.log
local unwrap = util.unwrap
local get_skill_ids = passives.get_skill_ids
local is_extractable = passives.is_extractable

-- See "TRACING" in the header. Budgeted so a per-frame hook cannot fill a disk;
-- state transitions use log() and are never budgeted.
-- Sized so a per-frame hook cannot exhaust it before a 5-second conversion
-- completes. If "TRACE budget exhausted" appears early, that is itself the
-- answer to the cadence question, and tracing should switch to change-only.
local TRACE_BUDGET = 20000
local trace_lines = 0

local function trace(message)
    if trace_lines > TRACE_BUDGET then
        return
    end
    trace_lines = trace_lines + 1
    if trace_lines > TRACE_BUDGET then
        log(string.format("TRACE budget of %d lines exhausted; tracing off. "
            .. "Transitions are still logged.", TRACE_BUDGET))
        return
    end
    log("TRACE " .. message)
end

-- Fires while the machine is converting. Carries the model as its argument.
-- Good for sampling progress; USELESS for noticing a departure, because it goes
-- silent the moment the queue empties. See the session notes above.
local PROCEED_HOOK =
"/Script/Pal.PalBuildObjectConvertCharacterToItem:OnProceedConvertProcess_ServerInternal"

-- The container's own change notification. Takes no arguments; the hook context
-- IS the model. This is the authoritative arrival/departure signal.
local CONTAINER_HOOK =
"/Script/Pal.PalMapObjectConvertCharacterToItemModel:OnUpdateCharacterContainer_ServerInternal"

-- Nothing is created while this is true.
local DRY_RUN = true

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

-- A queued Pal is keyed by the four int32s of its InstanceId GUID. Read as
-- PROPERTIES: FPalInstanceID and FGuid are plain structs, so this is a field
-- walk, not a call, and there is no arity to get wrong.
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
    -- All-zero is the null GUID, i.e. an empty entry, not a Pal.
    if key == "0-0-0-0" then
        return nil
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

-- instance key -> ConvertProgressRate, for every Pal currently being converted.
local function read_process_rates(model)
    local rates = {}
    local array
    if not pcall(function() array = model.ConvertProcessArray end) or array == nil then
        trace("read_process_rates: ConvertProcessArray unreadable or nil -> {}")
        return rates
    end
    local count = array_count(array)
    local described, found = {}, 0
    for index = 1, count do
        local entry = unwrap(array[index])
        if entry == nil then
            trace(string.format("read_process_rates: entry %d is nil", index))
        else
            local key, rate
            pcall(function() key = instance_key(entry.IndividualId) end)
            pcall(function() rate = unwrap(entry.ConvertProgressRate) end)
            if key == nil then
                trace(string.format("read_process_rates: entry %d has no usable InstanceId", index))
            else
                found = found + 1
                rates[key] = tonumber(rate) or 0.0
                described[#described + 1] = string.format("%s@%.3f", key, rates[key])
            end
        end
    end
    trace(string.format("read_process_rates: arrayNum=%d usable=%d [%s]",
        count, found, table.concat(described, " ")))
    return rates
end

-- instance key -> the extractable passives that Pal is carrying.
--
-- Read from the conveyor's OWN character container, reached through the model,
-- rather than from the generic slots observer: the observer fires for every
-- container in the world -- palbox, party, base -- and matching it back to one
-- machine is work this does not need to do.
local function read_queued_passives(model)
    trace("read_queued_passives: enter")
    local found = {}
    local module
    if not pcall(function() module = unwrap(model:GetCharacterContainerModule()) end) then
        trace("read_queued_passives: GetCharacterContainerModule raised -> {}")
        return found
    end
    if not is_valid(module) then
        trace("read_queued_passives: character container module invalid -> {}")
        return found
    end
    local container
    if not pcall(function() container = unwrap(module:GetContainer()) end) then
        trace("read_queued_passives: GetContainer raised -> {}")
        return found
    end
    if not is_valid(container) then
        trace("read_queued_passives: container invalid -> {}")
        return found
    end

    local slot_count = 0
    pcall(function() slot_count = unwrap(container:Num()) or 0 end)
    trace(string.format("read_queued_passives: container has %d slot(s)", slot_count))
    local occupied = 0
    for index = 0, slot_count - 1 do
        local slot
        pcall(function() slot = unwrap(container:Get(index)) end)
        if not is_valid(slot) then
            trace(string.format("read_queued_passives: slot %d invalid", index))
        else
            local handle
            pcall(function() handle = unwrap(slot:GetHandle()) end)
            if not is_valid(handle) then
                -- The ordinary empty-slot case; there are 10 of these and only
                -- 3 can be busy, so this is expected noise, not a fault.
                trace(string.format("read_queued_passives: slot %d empty (no handle)", index))
            else
                local key
                pcall(function() key = instance_key(handle.ID) end)
                local parameter
                pcall(function() parameter = unwrap(handle:TryGetIndividualParameter()) end)
                if key == nil then
                    trace(string.format("read_queued_passives: slot %d handle has no usable InstanceId", index))
                elseif not is_valid(parameter) then
                    -- THE SILENT SKIP. A Pal present in ConvertProcessArray but
                    -- landing here is never snapshotted and never tracked, and
                    -- before tracing that looked exactly like the hook not
                    -- firing. If a missing QUEUED line is ever explained, it is
                    -- most likely explained by this line.
                    trace(string.format(
                        "read_queued_passives: slot %d key=%s HAS NO INDIVIDUAL PARAMETER -- skipped",
                        index, key))
                else
                    occupied = occupied + 1
                    local all, extractable = {}, {}
                    for _, passive_id in ipairs(get_skill_ids(parameter) or {}) do
                        all[#all + 1] = passive_id
                        if is_extractable(passive_id) then
                            extractable[#extractable + 1] = passive_id
                        end
                    end
                    found[key] = extractable
                    trace(string.format(
                        "read_queued_passives: slot %d key=%s all=[%s] extractable=[%s]",
                        index, key, table.concat(all, ","), table.concat(extractable, ",")))
                end
            end
        end
    end
    trace(string.format("read_queued_passives: exit with %d occupied slot(s)", occupied))
    return found
end

-- Consumed, or taken back out?
--
-- ConvertProgressRate runs past 1.0 exactly when the conversion completes.
-- Measured across two sessions: consumed at 1.002, 1.004, 1.002 and 1.003;
-- withdrawn by hand at 0.293 and 0.238. The gap is the whole scale, so the
-- threshold sits just under 1.0 rather than at some fraction of it.
--
-- This only works because nothing throttles the sampling. If a throttle is ever
-- reintroduced, the last rate held goes stale and this silently starts
-- misfiling consumptions as withdrawals -- which is precisely what happened the
-- first time round.
local COMPLETE_RATE = 0.999

-- Is there anyone to give a module TO, right now?
--
-- This is the whole of open question 1, asked at the only moment that matters:
-- the instant a Pal is consumed. If it reports a resolvable inventory even
-- while the player is on the far side of the map, an inventory grant is viable
-- and the world drop is optional. If it reports none, the world drop is the
-- only workable output.
--
-- Cheap: PalPlayerState is a handful of objects, not the 1776 that made the
-- existence test unusable. find_inventory(nil) takes the "exactly one player
-- state" fallback, which is the single-player case.
-- Which base camp does this conveyor belong to, if any?
--
-- GetBaseCampIdBelongTo is a no-argument getter on UPalMapObjectConcreteModelBase.
-- It matters because UPalBaseCampUtility::RequestMoveInventoryItemToBaseCamp --
-- the game's own quick-stack-to-base -- takes a base camp id, and that is the
-- one sanctioned way found so far to get an item out of the player's inventory
-- and into storage without touching a container directly.
local function describe_base_camp(model)
    local guid
    if not pcall(function() guid = unwrap(model:GetBaseCampIdBelongTo()) end) then
        return "baseCamp=<call failed>"
    end
    local key = guid_key(guid)
    return "baseCamp=" .. (key or "none")
end

local function describe_recipient()
    local states, count = nil, 0
    pcall(function() states = FindAllOf("PalPlayerState") end)
    for _, state in ipairs(states or {}) do
        if is_valid(state) then
            count = count + 1
        end
    end
    local data = nil
    pcall(function() data = inventory.find_inventory(nil) end)
    local resolved = is_valid(data)

    -- The last unverified link in the quick-stack route. Getting a module out
    -- of the inventory and into base storage needs its FPalItemSlotId, and the
    -- way there is InventoryMultiHelper.Containers (a property) -> Get(i) (one
    -- int argument) -> GetSlotId() (no arguments). No out-parameters anywhere.
    -- If containers reads 0 here, that route is closed and only the DropItem
    -- instances in DROP ROUTES are left.
    local containers, slots = 0, 0
    if resolved then
        pcall(function()
            local helper = unwrap(data.InventoryMultiHelper)
            if is_valid(helper) then
                local list = helper.Containers
                for index = 1, array_count(list) do
                    local container = unwrap(list[index])
                    if is_valid(container) then
                        containers = containers + 1
                        local n = 0
                        pcall(function() n = unwrap(container:Num()) or 0 end)
                        slots = slots + n
                    end
                end
            end
        end)
    end
    return string.format("playerStates=%d inventoryResolvable=%s invContainers=%d invSlotsAllTypes=%d",
        count, tostring(resolved), containers, slots)
end

-- How much room do MODULES actually have?
--
-- invSlotsAllTypes above is the sum across all six EPalPlayerInventoryType
-- containers -- Common, DropSlot, Essential, WeaponLoadout, PlayerEquipArmor,
-- FoodEquip -- so it counts key items and equipment slots a module can never
-- occupy. It is a number, but not the number that decides anything, and it
-- should not be quoted as inventory headroom.
--
-- This breaks it down per container and counts EMPTY slots, and asks the game
-- directly which inventory type a module is routed to.
-- GetInventoryTypeFromStaticItemID takes one FName and returns an enum by
-- value: no out-parameter, nothing to get wrong.
local inventory_surveyed = false

-- Can we MAKE a DropItem caller, since none exists?
--
-- This is the only mechanism found that works when the player's inventory is
-- full. Everything that routes through AddItem_ServerInternal fails at free==0
-- with FailedContainerOverflowSlotNum, which is precisely the case that has to
-- work -- so a deferred ledger is a safety net, not a solution.
--
-- UPalIncidentBase exposes DropItem(ItemId, DropNum, SpawnLocation,
-- ReleaseDirection) and has settable OwnerObject/OccuredObject, and UE4SS
-- exposes StaticConstructObject. So the question is whether an instance can be
-- built with an Outer that has a world, and whether the function is reachable
-- on it.
--
-- THIS PROBE DOES NOT CALL DropItem. Construction and reflection lookup only.
-- Calling it is the dangerous step: if the implementation dereferences state a
-- constructed-but-uninitialised incident does not have, that is a native access
-- violation, and pcall does not catch those. That call goes behind its own flag
-- once this reports the object can be built at all.
local incident_probed = false

local function probe_constructed_dropper(actor)
    if incident_probed then
        return
    end
    incident_probed = true
    local class_object = nil
    pcall(function() class_object = StaticFindObject("/Script/Pal.PalIncidentBase") end)
    if class_object == nil then
        log("DROPPER PROBE PalIncidentBase class not found; the constructed-dropper route is out.")
        return
    end
    local outer = actor
    if outer == nil then
        pcall(function() outer = FindFirstOf("World") end)
    end
    local built = nil
    local constructed = pcall(function()
        built = StaticConstructObject(class_object, outer)
    end)
    local has_drop = false
    if built ~= nil then
        pcall(function() has_drop = built.DropItem ~= nil end)
    end
    log(string.format(
        "DROPPER PROBE classFound=true outer=%s constructed=%s valid=%s hasDropItem=%s",
        tostring(outer ~= nil), tostring(constructed), tostring(is_valid(built)),
        tostring(has_drop)))
end

local function survey_inventory()
    if inventory_surveyed then
        return
    end
    local data = nil
    pcall(function() data = inventory.find_inventory(nil) end)
    if not is_valid(data) then
        return
    end
    inventory_surveyed = true

    local module_type = "?"
    pcall(function()
        module_type = tostring(unwrap(
            data:GetInventoryTypeFromStaticItemID(FName("LP_Implant_MoveSpeed_up_1"))))
    end)

    local report = {}
    pcall(function()
        local helper = unwrap(data.InventoryMultiHelper)
        if not is_valid(helper) then
            return
        end
        local list = helper.Containers
        for index = 1, array_count(list) do
            local container = unwrap(list[index])
            if is_valid(container) then
                local total, empty = 0, 0
                pcall(function() total = unwrap(container:Num()) or 0 end)
                for slot_index = 0, total - 1 do
                    local slot
                    pcall(function() slot = unwrap(container:Get(slot_index)) end)
                    if is_valid(slot) then
                        local is_empty = false
                        pcall(function() is_empty = unwrap(slot:IsEmpty()) == true end)
                        if is_empty then
                            empty = empty + 1
                        end
                    end
                end
                report[#report + 1] = string.format("c%d:%d/%d free", index, empty, total)
            end
        end
    end)
    log(string.format("INVENTORY moduleTargetType=%s %s",
        module_type, table.concat(report, " ")))
end

-- Which world-drop route, if any, is actually reachable?
--
-- The vanilla flow -- create a temporary UPalItemContainer, put the item in it,
-- queue a UPalItemThrottledSpawnRequest -- CANNOT be driven from Lua: there is
-- no exposed UFunction to create a container, and the only AddItem in the whole
-- of Pal.hpp is UPalPlayerInventoryData::AddItem_ServerInternal. So the
-- candidates are indirect, and this reports which of them exist at the moment a
-- drop would be wanted.
--
--   PalStatusCollectItem  DropItem(ItemId, Num, SpawnLocation, ReleaseDirection)
--   PalIncidentBase       the same signature, on a random-incident object
--       Exactly the call we want. Both are UObjects we do not own, so the
--       question is whether a live instance is ever around to call it on.
--       Calling one on a class-default object is NOT an option: it would reach
--       for a world that a CDO does not have, and a native access violation is
--       not something pcall can catch.
--
--   PalNetworkItemComponent  RequestDrop_ToServer(SlotAndNumArray, Location, bAutoPickup)
--       The long way round: grant the module to the player, find its slot, ask
--       the game to drop it at the conveyor. Only exposed APIs, but it needs a
--       player present and one free inventory slot, which reintroduces a
--       smaller version of the fullness problem this route exists to avoid.
--
-- READ-ONLY. It counts objects and calls nothing.
local drop_routes_surveyed = false

local function survey_drop_routes()
    if drop_routes_surveyed then
        return
    end
    drop_routes_surveyed = true
    local counts = {}
    for _, class_name in ipairs({
        "PalStatusCollectItem",
        "PalIncidentBase",
        "PalNetworkItemComponent",
        "PalItemContainerManager",
        "PalMapObjectDropItemModel",
        "PalNetworkBaseCampComponent",
    }) do
        local found, total = nil, 0
        pcall(function() found = FindAllOf(class_name) end)
        for _, object in ipairs(found or {}) do
            if is_valid(object) then
                total = total + 1
            end
        end
        counts[#counts + 1] = string.format("%s=%d", class_name, total)
    end
    -- The CDO route: UPalBaseCampUtility takes a WorldContextObject, which is
    -- the signature of a static utility, and lp/inventory.lua already reaches
    -- UPalUtility this way. Finding it is read-only; nothing is called.
    local cdo = nil
    pcall(function() cdo = StaticFindObject("/Script/Pal.Default__PalBaseCampUtility") end)
    counts[#counts + 1] = "PalBaseCampUtilityCDO=" .. tostring(is_valid(cdo) or cdo ~= nil)
    log("DROP ROUTES " .. table.concat(counts, " "))
end

--------------------------------------------------------------------------------
-- Tracking
--------------------------------------------------------------------------------

-- instance key -> { passives = { id, ... }, rate = number }
--
-- Keyed globally rather than per model on purpose: the key is the Pal's own
-- InstanceId, which is unique across the world, so two conveyors running at
-- once cannot collide and a Pal cannot be in two queues.
local tracked = {}

local function describe(passive_ids)
    if #passive_ids == 0 then
        return "none"
    end
    return table.concat(passive_ids, ", ")
end

local function grant_for(key, entry)
    trace(string.format("grant_for: enter key=%s passives=%d dryRun=%s",
        key, #entry.passives, tostring(DRY_RUN)))
    local modules = {}
    for _, passive_id in ipairs(entry.passives) do
        local item_id = PASSIVE_ITEMS[passive_id]
        if item_id ~= nil then
            modules[#modules + 1] = item_id
        end
    end
    if DRY_RUN then
        log(string.format(
            "CONSUMED %s (last rate %.3f) carrying [%s]; WOULD grant %d module(s): [%s]. "
            .. "(dry run -- nothing was created)",
            key, entry.rate, describe(entry.passives), #modules, describe(modules)))
        return
    end
    -- Not reachable yet. The machine has no output container, so this has to be
    -- a world drop or an inventory grant, and it must journal before it grants.
    log(string.format("ERROR: conveyor grant path is not implemented; %d module(s) lost for %s.",
        #modules, key))
end

-- Set by on_proceed, which is the only callback that receives the actor. Used
-- as the Outer for the constructed-dropper probe: an actor definitely has a
-- world, which a bare UObject may not.
local last_actor = nil

local function on_departure(key, entry, model)
    trace(string.format("on_departure: enter key=%s lastRate=%.3f passives=[%s]",
        key, entry.rate, table.concat(entry.passives, ",")))
    log(string.format("RECIPIENT at departure of %s: %s %s",
        key, describe_recipient(), describe_base_camp(model)))
    survey_drop_routes()
    survey_inventory()
    probe_constructed_dropper(last_actor)
    if entry.rate >= COMPLETE_RATE then
        grant_for(key, entry)
    else
        log(string.format(
            "WITHDRAWN %s left the queue at rate %.3f, short of the %.3f completion mark; "
            .. "granting nothing.", key, entry.rate, COMPLETE_RATE))
    end
end

-- Two latches, not one. The container hook has no actor, so a single latch
-- meant that whichever hook fired first could permanently lose the
-- actor-derived fields to "?" -- and those are three of the four answers.
local surveyed_full = false
local surveyed_model = false

-- One line, once. Reads properties and no-argument getters only.
local function survey(actor, model)
    if surveyed_full or (actor == nil and surveyed_model) then
        return
    end
    if actor ~= nil then
        surveyed_full = true
    else
        surveyed_model = true
    end
    local slots, capacity, process_time = "?", "?", "?"
    if actor ~= nil then
        pcall(function()
            local parameter = unwrap(actor.ConvertCharacterToItemParameter)
            if is_valid(parameter) then
                slots = tostring(unwrap(parameter.ContainerSlotNum))
                capacity = tostring(unwrap(parameter.ConvertQueueCapacity))
                process_time = tostring(unwrap(parameter.RequiredConvertProcessTime))
            end
        end)
    end
    local item_container = "none"
    pcall(function()
        local module = unwrap(model:GetItemContainerModule())
        if is_valid(module) then
            local container = unwrap(module:GetContainer())
            item_container = is_valid(container) and "yes, with a container" or "module but no container"
        end
    end)
    log(string.format(
        "SURVEY conveyor: containerSlots=%s queueCapacity=%s processTime=%s itemContainerModule=%s",
        slots, capacity, process_time, item_container))
end

-- Cadence instrumentation. Open question 3; delete once read.
local proceed_calls, container_calls, cadence_logged = 0, 0, 0
local function note_cadence()
    local total = proceed_calls + container_calls
    if total < cadence_logged + 200 then
        return
    end
    cadence_logged = total
    log(string.format("HOOK CALLS proceed=%d containerUpdate=%d", proceed_calls, container_calls))
end

-- The state machine. Both hooks funnel here.
--
-- No throttle. The arrival branch is the only expensive one and it is already
-- guarded by tracked[key] == nil, so the per-call cost is one array read. An
-- earlier version throttled on os.clock() and could drop the very transition it
-- existed to catch.
local function pass(model, source)
    local before = {}
    for key, entry in pairs(tracked) do
        before[#before + 1] = string.format("%s@%.3f", key, entry.rate)
    end
    trace(string.format("pass: enter via %s; tracked=[%s]", source, table.concat(before, " ")))

    local rates = read_process_rates(model)

    -- First sighting: snapshot while the Pal still exists. This is the only
    -- chance to read it; once it is gone the parameter is gone too.
    local queued
    for key, rate in pairs(rates) do
        if tracked[key] == nil then
            trace(string.format("pass: %s is NEW (rate %.3f); walking the container", key, rate))
            queued = queued or read_queued_passives(model)
            local extractable = queued[key]
            if extractable == nil then
                -- In ConvertProcessArray but not resolvable in the container.
                -- Not tracked, so the next pass retries -- but if a Pal is only
                -- ever seen here, its passives are never captured and its
                -- eventual consumption grants nothing.
                trace(string.format(
                    "pass: %s is in the process array but NOT resolvable in the container; "
                    .. "not tracked, will retry next pass", key))
            else
                tracked[key] = { passives = extractable, rate = rate }
                log(string.format("QUEUED %s carrying [%s] (%d extractable).",
                    key, describe(extractable), #extractable))
            end
        else
            trace(string.format("pass: %s known, rate %.3f -> %.3f",
                key, tracked[key].rate, rate))
            tracked[key].rate = rate
        end
    end

    for key, entry in pairs(tracked) do
        if rates[key] == nil then
            trace(string.format("pass: %s is GONE from the process array", key))
            tracked[key] = nil
            on_departure(key, entry, model)
        end
    end

    local remaining = 0
    for _ in pairs(tracked) do remaining = remaining + 1 end
    trace(string.format("pass: exit via %s; %d still tracked", source, remaining))
end

-- Both callbacks are built ONCE, at load, and handed to hooks.register by
-- reference. Neither captures per-call state -- see the note at the top of
-- hooks.lua about why that matters more here than it looks.
local function on_proceed(context, model_param)
    proceed_calls = proceed_calls + 1
    note_cadence()
    trace(string.format("on_proceed: enter (call %d)", proceed_calls))
    local actor = unwrap(context)
    local model = unwrap(model_param)
    if is_valid(actor) then
        last_actor = actor
    end
    if not is_valid(model) then
        trace("on_proceed: model argument invalid -> exit doing nothing")
        return
    end
    survey(actor, model)
    pass(model, "on_proceed")
    trace("on_proceed: exit")
end

-- No arguments: the context IS the model.
local function on_container_update(context)
    container_calls = container_calls + 1
    note_cadence()
    trace(string.format("on_container_update: enter (call %d)", container_calls))
    local model = unwrap(context)
    if not is_valid(model) then
        trace("on_container_update: context is not a valid model -> exit doing nothing")
        return
    end
    survey(nil, model)
    pass(model, "on_container_update")
    trace("on_container_update: exit")
end

local function install()
    hooks.register(PROCEED_HOOK, on_proceed,
        "the conveyor progress watcher (observation only)")
    hooks.register(CONTAINER_HOOK, on_container_update,
        "the conveyor arrival/departure watcher (observation only)")
end

return {
    DRY_RUN = DRY_RUN,
    install = install,
}
