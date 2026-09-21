-- Lootable Passives -- Player lookup, item grants, and passive mutation.
--
-- Nothing here removes an item. add_modules is the only item-creation call in
-- the mod.

local util = require("lp.util")
local passives = require("lp.passives")

local find_all = util.find_all
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
            -- The pcall wraps the COMPARISON, not just the read, so an
            -- unreadable PlayerId cannot compare equal to an absent wanted id.
            local matched = false
            pcall(function()
                matched = player_id_number(state.PlayerId) == wanted
            end)
            if matched then
                return state
            end
        end
    end

    -- There is no PlayerIndex fallback here on purpose. PlayerId and
    -- PlayerIndex are different numbers; see CLAUDE.md.
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
    local bag = unwrap(util.method(state, "GetInventoryData"))
    if is_valid(bag) then
        return bag
    end
    return nil
end

-- Every player with a reachable inventory, as
-- { data = <inventory>, uid = <PlayerUId key or nil>, distance = <number>,
--   local_player = <bool> }, sorted local-player-first and then by distance.
--
-- uid is what lp/ledger.lua matches a debt's recorded owner against. The sort
-- order below is only the fallback it works down when no candidate matches;
-- see the note on ordered_for there, and CLAUDE.md on the delivery rule.
--
-- Distances are squared and never rooted: only their order is used.
local function delivery_candidates(near_location)
    local found = {}
    for _, character in ipairs(find_all("PalPlayerCharacter")) do
        if is_valid(character) then
            local data, uid = nil, nil
            pcall(function()
                local controller = unwrap(character:GetPalPlayerController())
                if is_valid(controller) then
                    local state = unwrap(controller.PlayerState)
                    if is_valid(state) then
                        data = unwrap(state:GetInventoryData())
                        -- Property read on APalPlayerState (Pal.hpp: FGuid
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
-- reported as one; the counts are read only to fill in detail. See CLAUDE.md,
-- "Item creation: the engine spills".
local function add_modules(data, item_id, count)
    if not is_valid(data) then
        return false, "no inventory"
    end
    -- One FName for all three calls: constructing it is a name-table lookup.
    local name = FName(item_id)
    local before = -1
    pcall(function() before = unwrap(data:CountItemNum(name)) or -1 end)
    local succeeded, result = pcall(function()
        return data:AddItem_ServerInternal(name, count, false, 0.0, true)
    end)
    if not succeeded then
        return false, "call raised an error"
    end
    local code = operation_result_code(result)
    local after = -1
    pcall(function() after = unwrap(data:CountItemNum(name)) or -1 end)
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

-- RemovePassiveSkill(FName), verified by COUNT rather than by list length.
--
-- The call filters the list by name and removes every copy, so on a Pal holding
-- two copies the length falls by two. Returns true when the count of skill_id
-- fell.
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

-- Replaces one of our markers with a passive.
--
-- REMOVES FIRST, THEN ADDS. AddPassiveSkill(AddSkill, OverrideSkill) is called
-- with the marker as OverrideSkill, but the removal above it is what the result
-- check relies on; do not drop it. See CLAUDE.md.
--
-- Returns true only when the marker's count is zero and the passive's count has
-- risen by one, so a failed add leaves the Pal with neither and every caller
-- checks the result.
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

    local restored = succeeded
        and after ~= nil
        and count_id(after, extraction_mode) == 0
        and count_id(after, passive_id) == count_id(before, passive_id) + 1

    if not restored then
        -- Both lists in full, uncapped: their shape is what identifies the
        -- failure.
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
    player_id_number = player_id_number,
    remove_skill = remove_skill,
    restore_replaced_passive = restore_replaced_passive,
}
