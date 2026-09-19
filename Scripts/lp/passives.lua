-- Lootable Passives -- Reading and diffing a Pal's passive list.
--
-- gained_lock is the mod's single most safety-critical predicate: it is
-- what tells a transaction of ours apart from an ordinary vanilla surgery. It
-- is written exactly once, here, having previously existed as two copies
-- sixty lines apart.

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local ids = require("lp.ids")

-- Localised so the function bodies below are byte-identical to what they
-- were in main.lua: this split is code motion, not a rewrite.
local array_count = util.array_count
local is_valid = util.is_valid
local name_to_string = util.name_to_string
local EXTRACTION_MODES = ids.EXTRACTION_MODES

--------------------------------------------------------------------------------
-- Passive list inspection
--------------------------------------------------------------------------------

local function get_skill_ids(parameter)
    if not is_valid(parameter) then
        return nil
    end
    local succeeded, skills = pcall(function()
        return parameter:GetPassiveSkillList()
    end)
    if not succeeded or skills == nil then
        return nil
    end
    local ids = {}
    for index = 1, array_count(skills) do
        ids[index] = name_to_string(skills[index]) or "<invalid>"
    end
    return ids
end

local function counts(ids)
    local result = {}
    for _, id in ipairs(ids or {}) do
        result[id] = (result[id] or 0) + 1
    end
    return result
end

-- Counts one id directly rather than via counts(), which would build and then
-- discard a whole id->count map to read a single key. remove_skill and
-- restore_replaced_passive each call this twice, so an extract-all over a
-- four-passive Pal was allocating a dozen throwaway tables on the transaction
-- path. counts() stays for the detectors, which genuinely need the whole map.
local function count_id(ids, wanted)
    local total = 0
    for _, id in ipairs(ids or {}) do
        if id == wanted then
            total = total + 1
        end
    end
    return total
end

-- A passive is extractable when it is a real passive, not one of this mod's own
-- markers or aliases, and has a module item to hand back. The module map is the
-- whole gate: a passive with no entry in passive_items.lua cannot be extracted,
-- because there would be nothing to give the player in exchange.
local function is_extractable(passive_id)
    return passive_id ~= nil
        and passive_id ~= "None"
        and EXTRACTION_MODES[passive_id] == nil
        and PASSIVE_ITEMS[passive_id] ~= nil
end

-- Exactly one of our markers appeared and no other marker moved; nil otherwise.
--
-- This is the mod's single most safety-critical predicate -- it is what tells a
-- transaction of ours apart from an ordinary vanilla surgery.
local function gained_lock(before, after)
    local gained
    local function examine(id)
        if EXTRACTION_MODES[id] == nil then
            return true
        end
        local delta = (after[id] or 0) - (before[id] or 0)
        if delta == 1 then
            if gained ~= nil then
                return false
            end
            gained = id
        elseif delta ~= 0 then
            return false
        end
        return true
    end
    for id in pairs(after) do
        if not examine(id) then
            return nil
        end
    end
    for id in pairs(before) do
        if after[id] == nil and not examine(id) then
            return nil
        end
    end
    return gained
end

-- The vanilla Surgery transaction replaces one selected passive with one of this
-- mod's markers. Recognize only that exact one-for-one transition, and report
-- which marker appeared so the caller knows which operation was requested.
local function detect_replaced_passive(before_ids, after_ids)
    if before_ids == nil or after_ids == nil or #before_ids ~= #after_ids then
        return nil, nil
    end
    local before = counts(before_ids)
    local after = counts(after_ids)

    local gained = gained_lock(before, after)
    if gained == nil then
        return nil, nil
    end

    local removed
    for id, before_count in pairs(before) do
        if EXTRACTION_MODES[id] == nil then
            local difference = before_count - (after[id] or 0)
            if difference == 1 and removed == nil then
                removed = id
            elseif difference ~= 0 then
                return nil, nil
            end
        end
    end
    if removed == nil then
        return nil, nil
    end
    for id, after_count in pairs(after) do
        if EXTRACTION_MODES[id] == nil and id ~= removed
            and after_count ~= (before[id] or 0)
        then
            return nil, nil
        end
    end
    return removed, gained
end

-- The empty-slot case, which is NOT a swap.
--
-- Vanilla treats an empty passive slot as a legitimate target, because normally
-- you are ADDING a passive. Selecting an empty slot and confirming therefore
-- appends the marker instead of replacing anything: [X] becomes [X, marker].
-- detect_replaced_passive rejects that (it requires equal lengths), so before
-- this existed the marker was simply left attached to the Pal as a real
-- passive, surviving even a game restart.
--
-- Recognise it explicitly so the marker can be taken straight back off. Returns
-- the marker that appeared, and only when nothing else changed at all.
local function detect_added_lock(before_ids, after_ids)
    if before_ids == nil or after_ids == nil then
        return nil
    end
    if #after_ids ~= #before_ids + 1 then
        return nil
    end
    local before = counts(before_ids)
    local after = counts(after_ids)

    local gained = gained_lock(before, after)
    if gained == nil then
        return nil
    end
    for id, count in pairs(after) do
        if EXTRACTION_MODES[id] == nil and count ~= (before[id] or 0) then
            return nil
        end
    end
    for id, count in pairs(before) do
        if EXTRACTION_MODES[id] == nil and count ~= (after[id] or 0) then
            return nil
        end
    end
    return gained
end

return {
    count_id = count_id,
    counts = counts,
    detect_added_lock = detect_added_lock,
    detect_replaced_passive = detect_replaced_passive,
    get_skill_ids = get_skill_ids,
    is_extractable = is_extractable,
}
