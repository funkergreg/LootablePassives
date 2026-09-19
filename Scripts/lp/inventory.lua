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

    if wanted ~= nil then
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        local world = FindFirstOf("World")
        if is_valid(utility) and is_valid(world) then
            local found, character = pcall(function()
                return utility:GetPlayerCharacterByPlayerIndex(world, wanted)
            end)
            character = unwrap(character)
            if found and is_valid(character) then
                local controller = unwrap(character:GetPalPlayerController())
                if is_valid(controller) then
                    local state = unwrap(controller.PlayerState)
                    if is_valid(state) then
                        return state
                    end
                end
            end
        end
    end
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
    find_inventory = find_inventory,
    operation_result_code = operation_result_code,
    player_id_number = player_id_number,
    remove_skill = remove_skill,
    restore_replaced_passive = restore_replaced_passive,
}
