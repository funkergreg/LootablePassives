-- Lootable Passives -- Removing this mod's implants from the world.
--
-- Runs where the world is held, while options.removal_requested() is true:
-- when either setting turns on, on entering a world, and when a player joins.
-- On a client it only tells the player that the host runs it.
--
-- A run reads the id of every PalItemContainer in memory once, in one frame,
-- and keeps only those ids as plain numbers. It then walks them three times,
-- SLICE per frame: it counts the LP_Implant_* stacks, removes them, then counts
-- again. Each slice looks up its containers by id through
-- UPalItemContainerManager::GetContainer(const FPalContainerId&) (Pal.hpp), and
-- the manager and the network item component with FindFirstOf, in that frame:
-- no engine object is held from one frame to the next, since the garbage
-- collector may free it in between. A container that is gone by its slice is
-- skipped.
-- One release line reports what was found before anything is removed, and one
-- what remains after. Then it drops the ledger's debts of those items. Only when
-- nothing remains and the ledger was written does it clear remove_mod_items,
-- through options.set, which also saves that into config.lua and Better Mod
-- Manager. Otherwise the request stays, and the next trigger runs it again.
--
-- The 21 vanilla PalPassiveSkillChange_Consumable_* implants are left alone,
-- and so is every Pal's passive list.
--
-- Removal is UPalNetworkItemComponent::RequestDispose_ToServer(const FGuid&
-- RequestID, const FPalItemSlotIdAndNum& SlotInfo) (Pal.hpp), called on the
-- first network item component found in that frame, with the slot's container
-- id, its index and its whole stack. It empties the slot before it returns.

local util = require("lp.util")
local options = require("lp.options")
local role = require("lp.role")
local ledger = require("lp.ledger")
local notice = require("lp.notice")
local host = require("lp.host")
local is_lp_implant = require("lp.ids").is_lp_implant

local array_count = util.array_count
local coalescer = util.coalescer
local field = util.field
local find_all = util.find_all
local find_first = util.find_first
local guid_key = util.guid_key
local guid_parts = util.guid_parts
local is_valid = util.is_valid
local log = util.log
local method = util.method
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local debug_log = options.debug_log
local debug_logf = options.debug_logf

-- Containers per frame. A full walk in one frame held the game thread for
-- seconds.
local SLICE = 100

local UNFINISHED_NOTICE = "Lootable Passives: removing this mod's implants did not finish; the "
    .. "host will try again."

-- The run in progress, or nil.
---@type table|nil
local run = nil

--------------------------------------------------------------------------------
-- One container
--------------------------------------------------------------------------------

-- "guild chest", "chest" (a container a map object owns) or "inventory" (any
-- other, which includes the players' own).
local function kind_of(container)
    if field(container, "bIsGuildChestContainer") == true then
        return "guild chest"
    end
    if guid_key(field(container, "OwnerMapObjectInstanceId")) ~= nil then
        return "chest"
    end
    return "inventory"
end

local function describe_first_dispose(component)
    return "cleanup: calling RequestDispose_ToServer for the first time this run, on "
        .. tostring(method(component, "GetFullName"))
end

local function describe_dispose(count, slot_index, returned, raised, slot)
    return string.format("cleanup: dispose x%d at slot %s returned=%s%s; the slot now holds %s x%s",
        count, tostring(slot_index), tostring(returned),
        returned and "" or (" (" .. tostring(raised) .. ")"),
        tostring(name_to_string(field(field(slot, "ItemId"), "StaticId"))),
        tostring(field(slot, "StackCount")))
end

local function describe_stack(phase, item_id, count, kind, container)
    return string.format("cleanup %s: %s x%d in a %s (%s)", phase, item_id, count, kind,
        tostring(method(container, "GetFullName")))
end

local function _call_dispose(component, request_id, slot_info)
    component:RequestDispose_ToServer(request_id, slot_info)
end

-- Asks the component to dispose of the slot's whole stack. Returns whether the
-- call returned; whether the stack went is what the verify pass counts.
local function dispose(state, component, slot, count)
    local a, b, c, d = guid_parts(field(field(slot, "ContainerId"), "ID"))
    if a == nil then
        return false
    end
    local slot_info = {
        SlotId = {
            ContainerId = { ID = { A = a, B = b, C = c, D = d } },
            SlotIndex = field(slot, "SlotIndex"),
        },
        Num = count,
    }
    local request_id = {
        A = math.random(1, 0x7FFFFFFF),
        B = math.random(1, 0x7FFFFFFF),
        C = math.random(1, 0x7FFFFFFF),
        D = math.random(1, 0x7FFFFFFF),
    }
    if not state.dispose_logged then
        state.dispose_logged = true
        debug_logf(describe_first_dispose, component)
    end
    local returned, raised = pcall(_call_dispose, component, request_id, slot_info)
    debug_logf(describe_dispose, count, slot_info.SlotId.SlotIndex, returned, raised, slot)
    return returned
end

-- Visits every LP_Implant_* stack in container: counts it under its kind in
-- the phase's tally, and in the "remove" phase disposes of it through
-- component.
local function visit(state, container, component)
    local phase = state.phase
    local tally = state.tallies[phase]
    if not is_valid(container) then
        return
    end
    local slots = field(container, "ItemSlotArray")
    if slots == nil then
        return
    end
    local kind = nil
    for index = 1, array_count(slots) do
        local slot = unwrap(slots[index])
        local item_id = name_to_string(field(field(slot, "ItemId"), "StaticId"))
        if is_lp_implant(item_id) then
            local count = tonumber(field(slot, "StackCount")) or 0
            if count > 0 then
                kind = kind or kind_of(container)
                if phase ~= "count" then
                    debug_logf(describe_stack, phase, item_id, count, kind, container)
                end
                tally[kind] = (tally[kind] or 0) + count
                tally.stacks = (tally.stacks or 0) + 1
                if phase == "remove" and not dispose(state, component, slot, count) then
                    tally.refused = (tally.refused or 0) + 1
                end
            end
        end
    end
end

-- UPalItemContainerManager::GetContainer(const FPalContainerId&) (Pal.hpp):
-- one argument.
local function _call_get_container(manager, container_id)
    return manager:GetContainer(container_id)
end

-- The id of every PalItemContainer in memory, each as { A, B, C, D }, read in
-- this frame from UPalContainerBase's ID (Pal.hpp). A container whose id does
-- not read is left out.
local function container_ids()
    local ids = {}
    for _, container in ipairs(find_all("PalItemContainer")) do
        local a, b, c, d = guid_parts(field(field(container, "ID"), "ID"))
        if a ~= nil then
            ids[#ids + 1] = { a, b, c, d }
        end
    end
    return ids
end

--------------------------------------------------------------------------------
-- The run
--------------------------------------------------------------------------------

local function describe(tally)
    return string.format("%d in inventories, %d in chests, %d in guild chests (%d stacks)",
        tally.inventory or 0, tally.chest or 0, tally["guild chest"] or 0, tally.stacks or 0)
end

local function total(tally)
    return (tally.inventory or 0) + (tally.chest or 0) + (tally["guild chest"] or 0)
end

local function finish(state)
    local found, verified = state.tallies.count, state.tallies.verify
    local remaining = total(verified)
    local dropped, written = ledger.forget_items(is_lp_implant)
    run = nil
    if remaining == 0 and written then
        log(string.format("Removed this mod's implants from the world: %s; %d owed implant(s) "
            .. "dropped from the ledger. Pals keep their passives. Containers not loaded now, "
            .. "and implants lying on the ground, were not reached.", describe(found), dropped))
        options.set("remove_mod_items", false)
        host.broadcast(string.format("Lootable Passives: the host removed %d of this mod's "
            .. "implants from the world.", total(found)))
        return
    end
    log(string.format("WARNING: removing this mod's implants did not finish: %d remain (%s)%s. "
        .. "remove_mod_items stays on, so it runs again on the next world entry or player join.",
        remaining, describe(verified), written and "" or "; the ledger could not be written"))
    host.broadcast(UNFINISHED_NOTICE)
end

local schedule_step

local function step()
    local state = run
    if state == nil then
        return
    end
    local manager = find_first("PalItemContainerManager")
    local component = state.phase == "remove" and find_first("PalNetworkItemComponent") or nil
    if manager == nil or (state.phase == "remove" and component == nil) then
        run = nil
        log("WARNING: removing this mod's implants stopped: the item container manager or a "
            .. "player's network item component is gone. remove_mod_items stays on, so it runs "
            .. "again on the next world entry or player join.")
        host.broadcast(UNFINISHED_NOTICE)
        return
    end
    local last = math.min(state.index + SLICE - 1, #state.ids)
    for index = state.index, last do
        local id = state.ids[index]
        local found, container = pcall(_call_get_container, manager,
            { ID = { A = id[1], B = id[2], C = id[3], D = id[4] } })
        if found then
            visit(state, unwrap(container), component)
        end
    end
    state.index = last + 1
    if state.index <= #state.ids then
        schedule_step()
        return
    end
    state.index = 1
    if state.phase == "count" then
        log(string.format("Removing this mod's implants from the world: found %s in %d loaded "
            .. "container(s).", describe(state.tallies.count), #state.ids))
        state.phase = total(state.tallies.count) > 0 and "remove" or "verify"
        schedule_step()
    elseif state.phase == "remove" then
        if (state.tallies.remove.refused or 0) > 0 then
            debug_log(string.format("cleanup: %d dispose call(s) raised",
                state.tallies.remove.refused))
        end
        state.phase = "verify"
        schedule_step()
    else
        finish(state)
    end
end

schedule_step = coalescer(step, 0)

-- Starts a run when one is requested and none is running. reason names the
-- trigger in the debug log.
local function request(reason)
    if run ~= nil or not options.removal_requested() then
        return
    end
    if not role.is_authority() then
        if role.has_ui() then
            notice.once("cleanup_client", "Lootable Passives: only the host can remove this "
                .. "mod's items from the world; the setting does nothing in this game.")
        end
        return
    end
    if find_first("PalNetworkItemComponent") == nil then
        log("Removing this mod's implants waits for a player to be online; it runs when one "
            .. "joins.")
        return
    end
    log(string.format("Removing this mod's implants from the world has started (after %s).",
        tostring(reason)))
    host.broadcast("Lootable Passives: the host is removing this mod's implants from the world.")
    run = {
        ids = container_ids(),
        index = 1,
        phase = "count",
        tallies = { count = {}, remove = {}, verify = {} },
    }
    schedule_step()
end

-- Drops a run in progress: its containers belong to the world being left.
-- Called from main.lua's map-load hook. The request stays, so the next world
-- entry runs it again.
local function cancel()
    if run ~= nil then
        run = nil
        log("Removing this mod's implants was interrupted by a map load; it runs again on the "
            .. "next world entry.")
    end
end

return {
    cancel = cancel,
    request = request,
}
