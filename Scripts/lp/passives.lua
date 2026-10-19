-- Lootable Passives -- Reading and diffing a Pal's passive list.
--
-- The two detectors at the bottom decide whether a transaction was one of ours.
-- Both are built on gained_lock, which is written once, here.

local PASSIVE_ITEMS = require("lp.passive_items")
local util = require("lp.util")
local ids = require("lp.ids")

local array_count = util.array_count
local field = util.field
local find_all = util.find_all
local guid_key = util.guid_key
local is_valid = util.is_valid
local method = util.method
local name_to_string = util.name_to_string
local EXTRACTION_MODES = ids.EXTRACTION_MODES

--------------------------------------------------------------------------------
-- The module map, and the one seam onto it
--------------------------------------------------------------------------------
--
-- This is the only module that requires lp/passive_items.lua. Everything else asks
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

-- The passives whose Surgery route is a direct one: a row in
-- LootablePassivesOperatingTable.json that installs the passive itself and
-- spends its LP_Implant_* module. These are the passives with an LP_Implant_*
-- module that no alias in ids.IMPLANT_TARGET installs.
local ALIAS_TARGETS = {}
for _, target in pairs(ids.IMPLANT_TARGET) do
    ALIAS_TARGETS[target] = true
end
local DIRECT_ROUTES = {}
for passive_id, item_id in pairs(PASSIVE_ITEMS) do
    if ids.is_lp_implant(item_id) and not ALIAS_TARGETS[passive_id] then
        DIRECT_ROUTES[passive_id] = true
    end
end

local function is_direct_route(passive_id)
    return DIRECT_ROUTES[passive_id] == true
end

-- True for every Surgery operation surgery_extraction covers, by the passive id
-- the operation installs: an extraction marker, an LP_Insert_* alias, or a
-- direct-route passive. A passive owns at most one operating-table row, so a
-- direct-route passive's only operation is this mod's.
local function is_covered(passive_id)
    return passive_id ~= nil
        and (EXTRACTION_MODES[passive_id] ~= nil or DIRECT_ROUTES[passive_id] == true)
end

--------------------------------------------------------------------------------
-- Passive list inspection
--------------------------------------------------------------------------------

-- A TArray<FName> as a list of strings. An FName that will not convert becomes
-- "<invalid>", so the list length always matches the array's. nil in, empty
-- list out.
local function name_list(array)
    local names = {}
    for index = 1, array_count(array) do
        names[index] = name_to_string(array[index]) or "<invalid>"
    end
    return names
end

-- GetPassiveSkillList() as a list of strings, or nil if the parameter is invalid
-- or the call raises.
local function get_skill_ids(parameter)
    if not is_valid(parameter) then
        return nil
    end
    local skills = method(parameter, "GetPassiveSkillList")
    if skills == nil then
        return nil
    end
    return name_list(skills)
end

-- An FPalInstanceID, as field() returns it, turned into its InstanceId GUID as a
-- comparable string, or nil when either does not read. Property reads only,
-- through util.guid_key.
local function instance_key(instance_id)
    return guid_key(field(instance_id, "InstanceId"))
end

-- The Pal's IndividualId as instance_key reads it (Pal.hpp: FPalInstanceID
-- IndividualId at 0x0320 on UPalIndividualCharacterParameter).
local function pal_key(parameter)
    return instance_key(field(parameter, "IndividualId"))
end

-- The Pal's OwnerPlayerUId as a comparable string, or nil when it reads as the
-- null GUID.
--
-- OwnerPlayerUId is on the individual's SaveParameter struct, so this is two
-- property reads. GetSaveParameter() returns the struct by value and is not
-- called.
local function owner_key(parameter)
    return guid_key(field(field(parameter, "SaveParameter"), "OwnerPlayerUId"))
end

-- Every PalIndividualCharacterParameter in the world whose passive list reads,
-- as { parameter = ..., before_ids = { id, ... } }.
--
-- One walk of the object pool, shared by the server-snapshot capture in
-- lp/transaction.lua and the sweep in lp/recovery.lua. It is the most expensive
-- engine call in the mod. get_skill_ids does its own is_valid.
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

-- Does the parameter's passive list hold id? False when the list does not read.
-- Walks GetPassiveSkillList() in place rather than through get_skill_ids, so it
-- builds no table: the Surgery gate asks this every frame while an implant is
-- pending.
local function has_skill(parameter, id)
    if not is_valid(parameter) then
        return false
    end
    local skills = method(parameter, "GetPassiveSkillList")
    if skills == nil then
        return false
    end
    for index = 1, array_count(skills) do
        if name_to_string(skills[index]) == id then
            return true
        end
    end
    return false
end

-- The first of our markers or aliases in the list, or nil.
local function first_marker(skill_ids)
    for _, id in ipairs(skill_ids or {}) do
        if EXTRACTION_MODES[id] ~= nil then
            return id
        end
    end
    return nil
end

-- True when the id is a real passive -- not nil, not "None", not one of this
-- mod's markers or aliases -- and has an entry in lp/passive_items.lua.
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
    for id in pairs(EXTRACTION_MODES) do
        local delta = (after[id] or 0) - (before[id] or 0)
        if delta == 1 and gained == nil then
            gained = id
        elseif delta ~= 0 then
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
    first_marker = first_marker,
    get_skill_ids = get_skill_ids,
    has_skill = has_skill,
    instance_key = instance_key,
    is_covered = is_covered,
    is_direct_route = is_direct_route,
    is_extractable = is_extractable,
    is_module_id = is_module_id,
    module_for = module_for,
    name_list = name_list,
    owner_key = owner_key,
    pal_key = pal_key,
    snapshot_all = snapshot_all,
}
