-- Lootable Passives -- Player lookup, item grants, and passive mutation.
--
-- Nothing here removes an item. add_modules is the only item-creation call in
-- the mod.

local util = require("lp.util")
local passives = require("lp.passives")

local field = util.field
local find_all = util.find_all
local is_valid = util.is_valid
local log = util.log
local method = util.method
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

-- The PalPlayerState whose PlayerId matches, or -- only when exactly one state
-- is loaded -- that one state. Returns nil with two or more states and no
-- match, rather than picking one.
local function find_player_state(request_player_id)
    local wanted = player_id_number(request_player_id)
    local only_state = nil
    local state_count = 0
    for _, state in ipairs(find_all("PalPlayerState")) do
        if is_valid(state) then
            state_count = state_count + 1
            only_state = state
            -- An unreadable PlayerId reads as nil and never matches, including
            -- an absent wanted id.
            local id = player_id_number(field(state, "PlayerId"))
            if id ~= nil and id == wanted then
                return state
            end
        end
    end

    -- There is no PlayerIndex fallback here on purpose. PlayerId and
    -- PlayerIndex are different numbers.
    if state_count == 1 then
        return only_state
    end
    return nil
end

-- The character's PalPlayerState, through GetPalPlayerController() and the
-- controller's PlayerState property, or nil when either does not read as valid.
local function player_state_of(character)
    local controller = method(character, "GetPalPlayerController")
    if not is_valid(controller) then
        return nil
    end
    local state = field(controller, "PlayerState")
    if is_valid(state) then
        return state
    end
    return nil
end

-- The PlayerId of the locally controlled player, or nil when no character reads
-- as locally controlled or its PlayerState cannot be read. A dedicated server
-- has no local player.
local function local_player_id()
    for _, character in ipairs(find_all("PalPlayerCharacter")) do
        if is_valid(character) and method(character, "IsLocallyControlled") == true then
            local state = player_state_of(character)
            if state ~= nil then
                return player_id_number(field(state, "PlayerId"))
            end
        end
    end
    return nil
end

local function find_inventory(request_player_id)
    local state = find_player_state(request_player_id)
    if not is_valid(state) then
        return nil
    end
    local bag = method(state, "GetInventoryData")
    if is_valid(bag) then
        return bag
    end
    return nil
end

-- Every player with a reachable inventory, as
-- { data = <inventory>, uid = <PlayerUId key or nil> }, in FindAllOf order.
--
-- uid is what lp/ledger.lua matches a debt's recorded owner against.
local function delivery_candidates()
    local found = {}
    for _, character in ipairs(find_all("PalPlayerCharacter")) do
        local state = is_valid(character) and player_state_of(character) or nil
        if state ~= nil then
            local data = method(state, "GetInventoryData")
            if is_valid(data) then
                -- Property read on APalPlayerState (Pal.hpp: FGuid PlayerUId at
                -- 0x0598), not a call.
                found[#found + 1] = { data = data, uid = guid_key(field(state, "PlayerUId")) }
            end
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Mutation
--------------------------------------------------------------------------------

-- EPalItemOperationResult as a number. The value arrives as a number on some
-- paths and as an enum name on others, hence the text parsing.
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

local function _call_count_item_num(data, name)
    return unwrap(data:CountItemNum(name))
end

-- CountItemNum(FName), or -1 when the call raises or returns nil.
local function item_count(data, name)
    local succeeded, count = pcall(_call_count_item_num, data, name)
    if succeeded and count ~= nil then
        return count
    end
    return -1
end

-- Built once and passed to pcall by reference, like the accessors in
-- lp/util.lua.
local function _call_add_item(data, name, count)
    return data:AddItem_ServerInternal(name, count, false, 0.0, true)
end

local function _call_remove_passive(parameter, name)
    parameter:RemovePassiveSkill(name)
end

local function _call_add_passive(parameter, add_name, override_name)
    parameter:AddPassiveSkill(add_name, override_name)
end

-- The only item-creation call in the mod. Returns ok, detail.
--
-- AddItem_ServerInternal(FName, Count, bool, float, bool). The count is honoured
-- in one call, so a debt of 40 is one call.
--
-- ok is true when the result code is Success and false otherwise. detail is
-- "spilled" when the result was Success but CountItemNum did not rise by count,
-- and a reason string when ok is false.
--
-- A SUCCESS RESULT WITH NO COUNT CHANGE IS NOT A FAILURE and must not be
-- reported as one; the counts are read only to fill in detail.
local function add_modules(data, item_id, count)
    if not is_valid(data) then
        return false, "no inventory"
    end
    -- One FName for all three calls: constructing it is a name-table lookup.
    local name = FName(item_id)
    local before = item_count(data, name)
    local succeeded, result = pcall(_call_add_item, data, name, count)
    if not succeeded then
        return false, "call raised an error"
    end
    local code = operation_result_code(result)
    local after = item_count(data, name)
    if code ~= ITEM_RESULT_SUCCESS then
        return false, "EPalItemOperationResult=" .. tostring(code)
    end
    if before >= 0 and after >= 0 and after - before == count then
        return true, nil
    end
    return true, "spilled"
end

-- add_modules with a count of one. Not a second implementation: the enum
-- handling and the spill rule live in one place.
local function add_implant(data, item_id)
    return add_modules(data, item_id, 1)
end

-- RemovePassiveSkill(FName). Returns true when the call did not raise and
-- skill_id is absent from the passive list afterwards, including when it was
-- absent before.
local function remove_skill(parameter, skill_id)
    if not is_valid(parameter) then
        return false
    end
    local succeeded = pcall(_call_remove_passive, parameter, FName(skill_id))
    local after = get_skill_ids(parameter)
    return succeeded and after ~= nil and count_id(after, skill_id) == 0
end

-- Replaces one of our markers with a passive.
--
-- REMOVES FIRST, THEN ADDS. AddPassiveSkill(AddSkill, OverrideSkill) is called
-- with the marker as OverrideSkill, but the removal above it is what the result
-- check relies on.
--
-- Returns true only when the marker's count is zero and the passive's count has
-- risen by one, so a failed add leaves the Pal with neither and every caller
-- checks the result.
local function restore_replaced_passive(parameter, passive_id, extraction_mode)
    local before = get_skill_ids(parameter)
    if before == nil then
        return false
    end
    local marker = FName(extraction_mode)
    pcall(_call_remove_passive, parameter, marker)
    local succeeded = pcall(_call_add_passive, parameter, FName(passive_id), marker)
    local after = get_skill_ids(parameter)

    local restored = succeeded
        and after ~= nil
        and count_id(after, extraction_mode) == 0
        and count_id(after, passive_id) == count_id(before, passive_id) + 1

    if not restored then
        -- Both lists in full, uncapped: their shape is what identifies the
        -- failure.
        log(string.format(
            "ERROR: could not put %s in place of %s. before=[%s] after=[%s]",
            tostring(passive_id), tostring(extraction_mode),
            table.concat(before, ","), table.concat(after or {}, ",")))
    end
    return restored
end

-- Takes the marker lock off the Pal: restore_replaced_passive when passive_id
-- names the passive it replaced, remove_skill when it is nil. Returns that call's
-- result.
local function undo_swap(parameter, passive_id, lock)
    if passive_id ~= nil then
        return restore_replaced_passive(parameter, passive_id, lock)
    end
    return remove_skill(parameter, lock)
end

return {
    add_implant = add_implant,
    add_modules = add_modules,
    find_inventory = find_inventory,
    delivery_candidates = delivery_candidates,
    local_player_id = local_player_id,
    player_id_number = player_id_number,
    remove_skill = remove_skill,
    restore_replaced_passive = restore_replaced_passive,
    undo_swap = undo_swap,
}
