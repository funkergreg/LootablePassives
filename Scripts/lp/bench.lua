-- Lootable Passives -- TEMPORARY grant bench. DELETE THIS FILE BEFORE RELEASE.
--
-- A self-triggering test of the item-grant mechanics, deliberately independent
-- of the conveyor: it fires on a timer once the player is in world, so the
-- grant path can be characterised without disassembling anything.
--
-- It exists to answer questions the conveyor work is blocked on:
--
--   1. Does AddItem_ServerInternal actually land? Verified by CountItemNum
--      before and after, not by trusting the return code.
--   2. Does the Count parameter work, or does the game add one and report
--      success? Test 2 asks for 5.
--   3. Which container receives a module? The free-slot breakdown is logged
--      before and after, so the one that changes is the answer.
--   4. What does a partial fit do -- add what fits, or fail outright? Only
--      answerable with a near-full inventory; run this with Common nearly full
--      and test 4 (a large count) will say.
--
-- This file is scaffolding. It ships with nothing. When the grant path is
-- settled, delete the file and its two lines in main.lua.

local util = require("lp.util")
local inventory = require("lp.inventory")

local is_valid = util.is_valid
local log = util.log
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local array_count = util.array_count

-- How long to wait after the inventory first resolves, so the bench lands well
-- after the world has settled rather than during load.
local BENCH_DELAY_MS = 15000
local POLL_MS = 2000
local POLL_LIMIT = 60

-- ROUTE CLOSED: constructing a UPalIncidentBase to call DropItem on.
--
-- Do not try this again. StaticConstructObject on that class took the game down
-- with EXCEPTION_ACCESS_VIOLATION reading 0x2a8, in the engine, called from
-- UE4SS. The probe that did it was described in this file as unable to crash
-- because it "only constructs and inspects" -- construction is not inspection,
-- it runs engine code, and that was simply wrong.
--
-- Two calls in that probe were new and either could be the fault:
-- StaticConstructObject, and UPalUtility::GetPlayerCharacterByPlayerIndex,
-- which despite appearing in lp/inventory.lua is only reached there when a
-- player id is known and so had never actually executed. Both are avoided now:
-- the player actor comes from FindFirstOf, which this mod uses safely
-- throughout.

-- The adds are characterised: Count works, stacking works, modules land in the
-- 54-slot container. Leaving them on just mints 57 more modules per session, so
-- they are off. Turn back on to re-test partial fit with a nearly-full bag.
local BENCH_RUN_ADDS = false

-- Spawn a real drop map object through the game's own server function.
--
-- Lower risk than the constructed incident above: RequestSpawnMapObject_Server
-- is a sanctioned call with three plain arguments, and the worst likely outcome
-- is a spawn that fails or an empty drop object on the ground rather than a
-- crash. It DOES mutate the world -- expect an object near the player that may
-- persist in the save.
local BENCH_TRY_SPAWN = false

-- { item id, count }. Ids checked against Scripts/passive_items.lua.
local CASES = {
    { "LP_Implant_MoveSpeed_up_1", 1 },
    { "LP_Implant_Deffence_up2",   5 },
    { "LP_Implant_Stamina_Up_1",   1 },
    { "LP_Implant_PAL_oraora",     50 },
}

local function container_report(data)
    local parts = {}
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
                parts[#parts + 1] = string.format("c%d:%d/%d", index, empty, total)
            end
        end
    end)
    return table.concat(parts, " ")
end

local function count_of(data, item_id)
    local count = -1
    pcall(function() count = unwrap(data:CountItemNum(FName(item_id))) or -1 end)
    return count
end

-- FindFirstOf, deliberately. GetPlayerCharacterByPlayerIndex is a candidate
-- for the crash above and is not worth the risk for something this simple.
local function player_character()
    local character = nil
    pcall(function() character = FindFirstOf("PalPlayerCharacter") end)
    return character
end

-- How does an EXISTING world drop store its item?
--
-- This decides whether the spawn route is worth anything. If a drop's contents
-- live in a UPalItemContainer, spawning one gets us an empty bag we cannot
-- fill, because the only AddItem in the reflection surface is on the player's
-- inventory -- the same wall every other route hit. If instead the item is just
-- the model's ItemId.StaticId property, a spawn plus a property write may be a
-- real drop.
--
-- Pure reads against drops already lying in the world. Nothing is spawned,
-- nothing is called that creates or mutates.
local function probe_existing_drops()
    local models = nil
    pcall(function() models = FindAllOf("PalMapObjectDropItemModel") end)
    if models == nil or #models == 0 then
        log("BENCH DROP ANATOMY no drop models in the world to inspect.")
        return
    end
    local examined = 0
    for _, model in ipairs(models) do
        if examined >= 3 then
            break
        end
        if is_valid(model) then
            examined = examined + 1
            local static_id = "?"
            pcall(function()
                static_id = name_to_string(model.ItemId.StaticId) or "<none>"
            end)
            -- Does the drop carry a container, and what is in it?
            local container_state = "no item container module"
            pcall(function()
                local module = unwrap(model:GetItemContainerModule())
                if is_valid(module) then
                    local container = unwrap(module:GetContainer())
                    if not is_valid(container) then
                        container_state = "module but no container"
                        return
                    end
                    local total = 0
                    pcall(function() total = unwrap(container:Num()) or 0 end)
                    local contents = {}
                    for index = 0, total - 1 do
                        local slot
                        pcall(function() slot = unwrap(container:Get(index)) end)
                        if is_valid(slot) then
                            local empty = true
                            pcall(function() empty = unwrap(slot:IsEmpty()) == true end)
                            if not empty then
                                local sid, n = "?", 0
                                pcall(function() sid = name_to_string(slot.ItemId.StaticId) or "?" end)
                                pcall(function() n = unwrap(slot.StackCount) or 0 end)
                                contents[#contents + 1] = string.format("%s x%d", sid, n)
                            end
                        end
                    end
                    container_state = string.format("container %d slot(s) holding [%s]",
                        total, table.concat(contents, ", "))
                end
            end)
            log(string.format("BENCH DROP ANATOMY %d: ItemId.StaticId=%s | %s",
                examined, static_id, container_state))
        end
    end
end

-- The map-object spawn route.
--
-- Palworld splits a world drop into an ACTOR (APalMapObjectDropItem, which
-- carries no item data at all -- its only property is bMovementActive) and a
-- MODEL (UPalMapObjectDropItemModel, which has the FPalItemId). So raw
-- SpawnActor cannot work: there is nowhere on the actor to put an item. The
-- game's own RequestSpawnMapObject_Server creates both halves and registers
-- them with the manager, which is why it is the one worth trying.
--
-- Reads are unconditional. The spawn itself is behind BENCH_TRY_SPAWN.
local function probe_map_object_spawn()
    local manager = nil
    pcall(function() manager = FindFirstOf("PalMapObjectManager") end)
    if not is_valid(manager) then
        log("BENCH SPAWN PROBE PalMapObjectManager not found; route is out.")
        return
    end
    local drop_id, sk_id, chest_id = "?", "?", "?"
    pcall(function()
        local static_data = manager.StaticData
        -- name_to_string, not tostring: an FName printed with tostring comes
        -- out as "FNameUserdata: 000001DF50F0E428", which is what the last run
        -- logged and it said nothing at all.
        drop_id = name_to_string(static_data.DropItem3DMapObjectId) or "?"
        sk_id = name_to_string(static_data.DropItem3DSKMapObjectId) or "?"
        chest_id = name_to_string(static_data.MapObjectId_ItemChest) or "?"
    end)
    local models_before = 0
    pcall(function() models_before = #(FindAllOf("PalMapObjectDropItemModel") or {}) end)
    log(string.format(
        "BENCH SPAWN PROBE manager=true dropItem3D=%s dropItem3DSK=%s itemChest=%s dropModels=%d",
        drop_id, sk_id, chest_id, models_before))

    if not BENCH_TRY_SPAWN then
        log("BENCH SPAWN is OFF (BENCH_TRY_SPAWN=false).")
        return
    end
    if drop_id == "?" or drop_id == "None" then
        log("BENCH SPAWN no usable DropItem3DMapObjectId; not attempting.")
        return
    end
    local character = player_character()
    if not is_valid(character) then
        log("BENCH SPAWN no player character to spawn near; skipped.")
        return
    end
    -- Reuse the engine's own vectors rather than building structs by hand.
    local location, rotation = nil, nil
    pcall(function() location = character:K2_GetActorLocation() end)
    pcall(function() rotation = character:K2_GetActorRotation() end)
    if location == nil or rotation == nil then
        log("BENCH SPAWN could not read player transform; skipped.")
        return
    end

    -- Logged immediately before the call, and the log is flushed per line, so
    -- if this is the last line in the file the fault is in this call and
    -- nowhere else. The previous probe could not be localised after the fact
    -- because it made three engine calls between two log lines.
    log(string.format("BENCH SPAWN about to call RequestSpawnMapObject_Server(%s). "
        .. "If the log ends here, that call is the fault.", drop_id))
    local result = nil
    local called = pcall(function()
        result = manager:RequestSpawnMapObject_Server(FName(drop_id), location, rotation)
    end)
    local models_after = 0
    pcall(function() models_after = #(FindAllOf("PalMapObjectDropItemModel") or {}) end)
    log(string.format(
        "BENCH SPAWN called=%s returned=%s dropModels %d -> %d (delta %d)",
        tostring(called), tostring(unwrap(result)), models_before, models_after,
        models_after - models_before))
end

local function run()
    local data = nil
    pcall(function() data = inventory.find_inventory(nil) end)
    if not is_valid(data) then
        log("BENCH aborted: inventory no longer resolvable.")
        return
    end

    log("BENCH begin. free/total per container before: " .. container_report(data))

    if not BENCH_RUN_ADDS then
        log("BENCH adds are OFF (BENCH_RUN_ADDS=false); characterised already: "
            .. "Count works, stacking works, modules land in the 54-slot container.")
    end

    for index, case in ipairs(BENCH_RUN_ADDS and CASES or {}) do
        local item_id, count = case[1], case[2]
        local before = count_of(data, item_id)
        local result = nil
        local called = pcall(function()
            result = data:AddItem_ServerInternal(FName(item_id), count, false, 0.0, true)
        end)
        local code = inventory.operation_result_code(result)
        local after = count_of(data, item_id)
        log(string.format(
            "BENCH add %d: %s x%d -> called=%s result=%s code=%s count %d -> %d (delta %d)",
            index, item_id, count, tostring(called), tostring(result), tostring(code),
            before, after, after - before))
    end

    log("BENCH end. free/total per container after: " .. container_report(data))

    probe_existing_drops()
    probe_map_object_spawn()

end

local started = false
local polls = 0
local poll

local function begin()
    ExecuteInGameThread(run)
end

poll = function()
    if started then
        return
    end
    polls = polls + 1
    local data = nil
    pcall(function() data = inventory.find_inventory(nil) end)
    if is_valid(data) then
        started = true
        log(string.format("BENCH inventory resolved; running the grant bench in %d seconds.",
            BENCH_DELAY_MS / 1000))
        ExecuteWithDelay(BENCH_DELAY_MS, begin)
        return
    end
    if polls < POLL_LIMIT then
        ExecuteWithDelay(POLL_MS, poll)
    end
end

-- Called at load and again on each map load, so a title-screen start does not
-- burn the poll budget before there is a world to run in.
local function schedule()
    if started then
        return
    end
    polls = 0
    ExecuteWithDelay(POLL_MS, poll)
end

return {
    schedule = schedule,
}
