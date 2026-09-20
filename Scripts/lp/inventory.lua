-- Lootable Passives -- Player lookup, item grants, and passive mutation.
--
-- This mod only ever ADDS items. Taking them away costs a container walk per
-- item and is not currently done anywhere.

local util = require("lp.util")
local passives = require("lp.passives")

-- Localised so the function bodies below are byte-identical to what they
-- were in main.lua: this split is code motion, not a rewrite.
local is_valid = util.is_valid
local log = util.log
local unwrap = util.unwrap
local count_id = passives.count_id
local get_skill_ids = passives.get_skill_ids
local guid_key = util.guid_key

-- EPalItemOperationResult::Success
local ITEM_RESULT_SUCCESS = 0

--------------------------------------------------------------------------------
-- Player inventory
--------------------------------------------------------------------------------

local function player_id_number(value)
    value = unwrap(value)
    if type(value) == "number" then
        return value
    end
    return tonumber(value)
end

local function find_player_state(request_player_id)
    local wanted = player_id_number(request_player_id)
    local succeeded, states = pcall(function()
        return FindAllOf("PalPlayerState")
    end)
    local only_state = nil
    local state_count = 0
    if succeeded and states ~= nil then
        for _, state in ipairs(states) do
            if is_valid(state) then
                state_count = state_count + 1
                only_state = state
                local matched = false
                pcall(function()
                    matched = player_id_number(state.PlayerId) == wanted
                end)
                if matched then
                    return state
                end
            end
        end
    end

    -- REMOVED: a GetPlayerCharacterByPlayerIndex(world, wanted) fallback.
    --
    -- It passed a PlayerId where a PlayerIndex belongs. Those are different
    -- things: PlayerId is a unique identifier -- 259 in this mod's own logs --
    -- while PlayerIndex is a small 0-based index into the local player array.
    -- Asking for index 259 is an out-of-range lookup, and this is one of the
    -- two calls that could have produced the EXCEPTION_ACCESS_VIOLATION seen
    -- during development. It only ran when the PlayerId scan above had already
    -- failed, which is never in single-player, so it was shipped unexercised.
    --
    -- Nothing replaces it. If the scan cannot match the requesting player, the
    -- honest answer is "no player", and the caller refuses the exchange.

    -- SINGLE-PLAYER ONLY, deliberately. With one player state loaded there is
    -- no ambiguity about who asked. With two or more this returns nil rather
    -- than guessing, so a multiplayer request whose id did not match fails
    -- closed instead of handing another player's Pal to the wrong inventory.
    if state_count == 1 then
        return only_state
    end
    return nil
end

local function find_inventory(request_player_id)
    local state = find_player_state(request_player_id)
    if not is_valid(state) then
        return nil
    end
    local succeeded, inventory = pcall(function()
        return state:GetInventoryData()
    end)
    inventory = unwrap(inventory)
    if succeeded and is_valid(inventory) then
        return inventory
    end
    return nil
end

-- Who may receive a granted module, in fallback order.
--
-- find_inventory(nil) resolves a player only when EXACTLY ONE exists, which is
-- a single-player rule. A base-camp machine has no requesting player, so this
-- returns an ordered list instead of a lookup.
--
-- Each entry is { data = <inventory>, uid = <PlayerUId key or nil>,
-- local_player = <bool> }. The uid is the part that matters most: it is what
-- lets the ledger give a Pal's modules to the player who owned that Pal, rather
-- than to whoever this list happens to rank first.
--
-- THIS ORDER IS NOW THE FALLBACK, NOT THE RULE. lp/ledger.lua puts a row's
-- recorded owner ahead of everything here and only then works down this list,
-- so what is left for the ordering below is the case where the owner is not
-- online at all.
--
-- It still prefers the locally controlled player there, and for the original
-- reason: on a listen server that is the host, the machine running this mod, and
-- therefore the only player guaranteed to have the item definitions that make an
-- LP_Implant render. A guest without the mod sees an unresolved placeholder.
--
-- What changed is which of two wrong answers is preferred. Ranking the host
-- first unconditionally meant a guest could feed the conveyor and the host would
-- collect the modules -- silently, every time, with the guest's Pal gone. That
-- is worse than a placeholder icon, and the placeholder case is already known to
-- be survivable: the multiplayer test showed unresolvable items rendering as
-- blank chest entries and crashing nothing.
--
-- We still cannot ask a peer whether it has the mod. UE4SS Lua has no custom
-- network channel and nothing exposes a peer's loaded DataTables, so "deliver
-- only to a player who has the mod" is not implementable as stated. Owner-first
-- is the closest available approximation of the intent.
--
-- On a DEDICATED server there is no locally controlled player, so this falls
-- through to nearest-first. That is correct there: every client of a modded
-- dedicated server is expected to have installed the mod, and Info.json ships
-- IsServer install rules for exactly that.
--
-- Distance is compared SQUARED. Only the ordering matters, so no square root.
local function delivery_candidates(near_location)
    local characters = nil
    pcall(function() characters = FindAllOf("PalPlayerCharacter") end)
    local found = {}
    for _, character in ipairs(characters or {}) do
        if is_valid(character) then
            local data, uid = nil, nil
            pcall(function()
                local controller = unwrap(character:GetPalPlayerController())
                if is_valid(controller) then
                    local state = unwrap(controller.PlayerState)
                    if is_valid(state) then
                        data = unwrap(state:GetInventoryData())
                        -- A property read on APalPlayerState (Pal.hpp: FGuid
                        -- PlayerUId at 0x0598), not a call.
                        uid = guid_key(state.PlayerUId)
                    end
                end
            end)
            if is_valid(data) then
                local local_player = false
                pcall(function() local_player = character:IsLocallyControlled() == true end)
                local distance = math.huge
                if near_location ~= nil then
                    pcall(function()
                        local here = character:K2_GetActorLocation()
                        local dx = (unwrap(here.X) or 0) - (unwrap(near_location.X) or 0)
                        local dy = (unwrap(here.Y) or 0) - (unwrap(near_location.Y) or 0)
                        local dz = (unwrap(here.Z) or 0) - (unwrap(near_location.Z) or 0)
                        distance = dx * dx + dy * dy + dz * dz
                    end)
                end
                found[#found + 1] = {
                    data = data,
                    uid = uid,
                    distance = distance,
                    local_player = local_player,
                }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.local_player ~= b.local_player then
            return a.local_player -- the local player outranks distance
        end
        return a.distance < b.distance
    end)
    return found
end

--------------------------------------------------------------------------------
-- Mutation
--------------------------------------------------------------------------------

-- AddItem_ServerInternal returns EPalItemOperationResult, where Success is 0.
-- Anything else (notably FailedContainerOverflowSlotNum on a full inventory)
-- must abort the exchange, or the passive is removed for nothing.
local function operation_result_code(value)
    value = unwrap(value)
    if type(value) == "number" then
        return value
    end
    local text = tostring(value)
    local numeric = tonumber(text)
    if numeric ~= nil then
        return numeric
    end
    if text:find("SuccessNoOperation", 1, true) then
        return 1
    end
    if text:find("Success", 1, true) then
        return ITEM_RESULT_SUCCESS
    end
    return nil
end

local function add_implant(inventory, item_id)
    local succeeded, result = pcall(function()
        return inventory:AddItem_ServerInternal(FName(item_id), 1, false, 0.0, true)
    end)
    if not succeeded then
        return false, "call raised an error"
    end
    local code = operation_result_code(result)
    if code == nil then
        return false, "unrecognized result " .. tostring(result)
    end
    if code ~= ITEM_RESULT_SUCCESS then
        return false, "EPalItemOperationResult=" .. tostring(code)
    end
    return true, nil
end

-- A COUNTED grant, for the conveyor's pending ledger.
--
-- add_implant above grants exactly one and is what the Surgery Table wants.
-- This takes a count, because AddItem_ServerInternal honours one -- measured:
-- asking for 5 delivered 5, asking for 50 delivered 50 -- so a debt of 40 is
-- one call rather than forty.
--
-- Returns true only on Success. A full bag reports
-- FailedContainerOverflowSlotNum and creates NOTHING, so a false here means
-- the whole count is still owed, never part of it.
-- Success means THE ITEM WAS CREATED -- not that it is in the bag.
--
-- Measured, and it overturns what a comment in this file used to claim: with a
-- full inventory AddItem_ServerInternal returns Success and the game spills the
-- item onto the ground at the player's feet. It does NOT return
-- FailedContainerOverflowSlotNum. That value exists in the enum; this path does
-- not produce it.
--
-- So a count that does not move is NOT a failure, and treating it as one cost
-- real duplication: the debt stayed owed, the next flush granted again, and
-- each retry spilled another copy. One module was created five times that way.
--
-- The count is still read, but only to tell the player WHERE the item went.
-- Returns ok, detail -- where detail on success means "spilled, look on the
-- ground" and on failure means why nothing was created at all.
local function add_modules(data, item_id, count)
    if not is_valid(data) then
        return false, "no inventory"
    end
    local before = -1
    pcall(function() before = unwrap(data:CountItemNum(FName(item_id))) or -1 end)
    local succeeded, result = pcall(function()
        return data:AddItem_ServerInternal(FName(item_id), count, false, 0.0, true)
    end)
    if not succeeded then
        return false, "call raised an error"
    end
    local code = operation_result_code(result)
    local after = -1
    pcall(function() after = unwrap(data:CountItemNum(FName(item_id))) or -1 end)
    if code ~= ITEM_RESULT_SUCCESS then
        return false, "EPalItemOperationResult=" .. tostring(code)
    end
    if before >= 0 and after >= 0 and after - before == count then
        return true, nil
    end
    -- Created, but it did not land in the bag. The engine put it on the ground.
    return true, "spilled"
end

-- Verification here is COUNT-BASED, deliberately, not length-based.
--
-- RemovePassiveSkill(id) filters the list by name, so on a Pal carrying two
-- copies of the same passive it takes BOTH and the length falls by two. The old
-- check demanded #after == #before - 1, so it reported failure on precisely the
-- case it had just successfully cleaned up. That is the origin of the two
-- "could not remove passive Stamina_Up_1" warnings in the 23:37 session, logged
-- while the passive was in fact already gone.
local function remove_skill(parameter, skill_id)
    local before = get_skill_ids(parameter)
    if before == nil then
        return false
    end
    local succeeded = pcall(function()
        parameter:RemovePassiveSkill(FName(skill_id))
    end)
    local after = get_skill_ids(parameter)
    return succeeded
        and after ~= nil
        and count_id(after, skill_id) < count_id(before, skill_id)
end

-- Puts a passive in place of one of our markers.
--
-- THE ORDER MATTERS: the marker comes off FIRST, then the passive goes on.
--
-- AddPassiveSkill(AddSkill, OverrideSkill) does not reliably honour the
-- override. In the 23:35 and 23:37 sessions it APPENDED the passive and left
-- the marker sitting there, which is exactly what screenshot 118 shows --
-- Infinite Stamina and Infinite Stamina (Module) side by side on one Pal. Every
-- implant in that session then reported "could not restore", because the old
-- check required the list length to stay constant.
--
-- Appending is also how the overwrite case crashed. Overwriting a passive on a
-- Pal whose slots were already full leaves the marker occupying a slot, so
-- adding on top of it produces a FIFTH entry -- and the passive panel has only
-- four cards to index. Removing first means the list never grows beyond what
-- the UI can address, which is why inserting into an EMPTY slot never crashed:
-- there was a spare slot to absorb the append.
--
-- The trade is that a failed add now leaves the Pal with neither the marker nor
-- the passive, so every caller checks the result and the implant callers refund
-- the module.
local function restore_replaced_passive(parameter, passive_id, extraction_mode)
    local before = get_skill_ids(parameter)
    if before == nil then
        return false
    end
    pcall(function() parameter:RemovePassiveSkill(FName(extraction_mode)) end)
    local succeeded = pcall(function()
        parameter:AddPassiveSkill(FName(passive_id), FName(extraction_mode))
    end)
    local after = get_skill_ids(parameter)

    -- Judged on the OUTCOME rather than on how the engine got there: the marker
    -- is gone, and the passive is present once more than it was.
    local restored = succeeded
        and after ~= nil
        and count_id(after, extraction_mode) == 0
        and count_id(after, passive_id) == count_id(before, passive_id) + 1

    if not restored then
        -- Always log the lists themselves, uncapped. Reporting only "could not
        -- restore" is what hid the append behaviour for an entire test cycle;
        -- the shape of the list says immediately what happened. This fires only
        -- when a swap genuinely failed, which is both rare and the single worst
        -- thing this mod can do to a Pal -- exactly the line a bug report needs.
        local before_text, after_text = "?", "?"
        pcall(function() before_text = table.concat(before, ",") end)
        pcall(function() after_text = table.concat(after or {}, ",") end)
        log(string.format(
            "ERROR: could not put %s in place of %s. before=[%s] after=[%s]",
            tostring(passive_id), tostring(extraction_mode), before_text, after_text))
    end
    return restored
end

return {
    add_implant = add_implant,
    add_modules = add_modules,
    find_inventory = find_inventory,
    delivery_candidates = delivery_candidates,
    operation_result_code = operation_result_code,
    player_id_number = player_id_number,
    remove_skill = remove_skill,
    restore_replaced_passive = restore_replaced_passive,
}
