-- Lootable Passives -- Reading and diffing a Pal's passive list.
--
-- The two detectors at the bottom decide whether a transaction was one of ours.
-- Both are built on gained_lock, which is written once, here.

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local ids = require("lp.ids")

local array_count = util.array_count
local find_all = util.find_all
local is_valid = util.is_valid
local method = util.method
local name_to_string = util.name_to_string
local EXTRACTION_MODES = ids.EXTRACTION_MODES

--------------------------------------------------------------------------------
-- The module map, and the one seam onto it
--------------------------------------------------------------------------------
--
-- This is the only module that requires passive_items.lua. Everything else asks
-- module_for or is_module_id.

-- The item a passive yields when extracted, or nil if it has no entry.
local function module_for(passive_id)
    return PASSIVE_ITEMS[passive_id]
end

-- The reverse lookup, as a set built once at load rather than per query.
local MODULE_IDS = {}
local MODULE_COUNT = 0
for _, item_id in pairs(PASSIVE_ITEMS) do
    MODULE_IDS[item_id] = true
    MODULE_COUNT = MODULE_COUNT + 1
end

local function is_module_id(item_id)
    return MODULE_IDS[item_id] == true
end

--------------------------------------------------------------------------------
-- Passive list inspection
--------------------------------------------------------------------------------

-- GetPassiveSkillList() as a list of strings, or nil if the parameter is invalid
-- or the call raises. An FName that will not convert becomes "<invalid>", so the
-- list length always matches the array's.
local function get_skill_ids(parameter)
    if not is_valid(parameter) then
        return nil
    end
    local skills = method(parameter, "GetPassiveSkillList")
    if skills == nil then
        return nil
    end
    local skill_ids = {}
    for index = 1, array_count(skills) do
        skill_ids[index] = name_to_string(skills[index]) or "<invalid>"
    end
    return skill_ids
end

-- Every PalIndividualCharacterParameter in the world, as
-- { parameter = ..., before_ids = { id, ... } }.
--
-- One walk of the object pool, shared by the dedicated-server capture in
-- lp/transaction.lua and the sweep in lp/recovery.lua. It is the most expensive
-- engine call in the mod; both callers run it only on a path where something has
-- already failed. get_skill_ids does its own is_valid.
local function snapshot_all()
    local found = {}
    for _, parameter in ipairs(find_all("PalIndividualCharacterParameter")) do
        local skill_ids = get_skill_ids(parameter)
        if skill_ids ~= nil then
            found[#found + 1] = { parameter = parameter, before_ids = skill_ids }
        end
    end
    return found
end

-- id -> number of times it appears.
local function counts(skill_ids)
    local result = {}
    for _, id in ipairs(skill_ids or {}) do
        result[id] = (result[id] or 0) + 1
    end
    return result
end

-- One id's count, without building the whole map counts() would. The detectors
-- use counts(); the transaction path uses this.
local function count_id(skill_ids, wanted)
    local total = 0
    for _, id in ipairs(skill_ids or {}) do
        if id == wanted then
            total = total + 1
        end
    end
    return total
end

-- True when the id is a real passive -- not nil, not "None", not one of this
-- mod's markers or aliases -- and has an entry in passive_items.lua.
--
-- The module map is the gate: no entry means nothing to hand back, so nothing to
-- extract.
local function is_extractable(passive_id)
    return passive_id ~= nil
        and passive_id ~= "None"
        and EXTRACTION_MODES[passive_id] == nil
        and module_for(passive_id) ~= nil
end

-- The id of the single marker whose count rose by exactly one, provided no other
-- marker's count moved at all. nil otherwise, including when two markers rose.
--
-- Both detectors below start here. It is what separates a transaction of ours
-- from an ordinary surgery.
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

-- Does every non-marker id in `a` have the same count in `b`, ignoring one
-- exempt id? One direction only, so callers that need both say so by calling it
-- twice.
local function non_markers_match(a, b, except)
    for id, count in pairs(a) do
        if EXTRACTION_MODES[id] == nil and id ~= except and count ~= (b[id] or 0) then
            return false
        end
    end
    return true
end

-- One non-marker passive gone, one marker gained, list length unchanged, nothing
-- else moved. Returns the removed passive id and the marker id, or nil, nil.
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
    if not non_markers_match(after, before, removed) then
        return nil, nil
    end
    return removed, gained
end

-- A marker appended with nothing removed: the list is one longer and one marker
-- was gained. Returns that marker id, or nil.
--
-- detect_replaced_passive requires equal lengths and so rejects this shape,
-- which is why it is recognised separately.
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
    -- Both directions: one sweep alone would not notice a non-marker that
    -- disappeared.
    if not non_markers_match(after, before) or not non_markers_match(before, after) then
        return nil
    end
    return gained
end

return {
    MODULE_COUNT = MODULE_COUNT,
    count_id = count_id,
    counts = counts,
    detect_added_lock = detect_added_lock,
    detect_replaced_passive = detect_replaced_passive,
    get_skill_ids = get_skill_ids,
    is_extractable = is_extractable,
    is_module_id = is_module_id,
    module_for = module_for,
    snapshot_all = snapshot_all,
}
