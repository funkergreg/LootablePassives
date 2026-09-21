-- Lootable Passives -- The exchange: capture, resolve, grant, remove.
--
-- Call order in the extraction path: write_journal("prepared"), add_implant,
-- write_journal("granted"), remove_skill, clear_journal. The module is created
-- before the passive is removed. Do not reorder these; see CLAUDE.md under
-- "Invariants worth preserving".

local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")
local ui = require("lp.ui")
local is_valid = util.is_valid
local log = util.log
local unwrap = util.unwrap
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local is_extract_mode = ids.is_extract_mode
local clear_journal = journal.clear_journal
local write_journal = journal.write_journal
local count_id = passives.count_id
local counts = passives.counts
local detect_added_lock = passives.detect_added_lock
local detect_replaced_passive = passives.detect_replaced_passive
local get_skill_ids = passives.get_skill_ids
local is_extractable = passives.is_extractable
local module_for = passives.module_for
local snapshot_all = passives.snapshot_all
local add_implant = inventory.add_implant
local find_inventory = inventory.find_inventory
local player_id_number = inventory.player_id_number
local remove_skill = inventory.remove_skill
local restore_replaced_passive = inventory.restore_replaced_passive
local consume_pending_refresh = ui.consume_pending_refresh
local arm_refresh = ui.arm_refresh
local current_page = ui.current_page
local refresh_surgery_ui = ui.refresh_surgery_ui
local selected_passive = ui.selected_passive
local visible_extraction_widget = ui.visible_extraction_widget

--------------------------------------------------------------------------------
-- Request capture
--------------------------------------------------------------------------------

-- Builds a record from the tab page: the selected slot's passive, the Pal's
-- parameter object, and its passive list before the swap. Returns nil if there
-- is no page, no parameter, or no passive list.
local function capture_targeted_record(request_player_id)
    local widget, lock = visible_extraction_widget()
    if not is_valid(widget) then
        return nil
    end
    local passive_id = selected_passive(widget)
    -- An empty slot returns nil or "None". That is a refusal for the two
    -- extract modes and is accepted for an implant.
    if (passive_id == nil or passive_id == "None")
        and is_extract_mode(EXTRACTION_MODES[lock])
    then
        return nil
    end
    local parameter = unwrap(widget.CachedCharacter)
    local skill_ids = get_skill_ids(parameter)
    if skill_ids == nil then
        return nil
    end
    -- A one-element snapshots list, the same shape snapshot_server_parameters
    -- returns, so resolve_record has one loop rather than two branches.
    -- expect_passive_id is the field specific to this producer.
    return {
        snapshots = {
            {
                parameter = parameter,
                before_ids = skill_ids,
                expect_passive_id = passive_id,
            },
        },
        request_player_id = request_player_id,
        mode_source = "targeted UI",
    }
end

-- Snapshots every PalIndividualCharacterParameter in the world, via
-- passives.snapshot_all, which crash recovery also calls.
local function snapshot_server_parameters(request_player_id)
    return {
        snapshots = snapshot_all(),
        request_player_id = request_player_id,
        mode_source = "dedicated-server snapshot",
    }
end

-- Tries capture_targeted_record first. Falls through to the whole-world
-- snapshot only when there is no tab page at all; a page that is present and
-- yielded nothing returns nil instead.
local function capture_record(request_player_id)
    local succeeded, record = pcall(capture_targeted_record, request_player_id)
    if succeeded and record ~= nil then
        return record
    end
    local page_ok, page = pcall(current_page)
    if page_ok and is_valid(page) then
        return nil
    end
    local fallback_ok, fallback = pcall(snapshot_server_parameters, request_player_id)
    return fallback_ok and fallback or nil
end

-- Re-reads each snapshot's passive list and looks for one of two shapes: a
-- passive replaced by a marker (detect_replaced_passive) or a marker added with
-- nothing removed (detect_added_lock, recorded as stray). Returns the single
-- candidate, or nil if none or more than one matched.
local function resolve_record(record)
    if record == nil or record.snapshots == nil then
        return nil
    end

    local resolved = nil
    for _, snapshot in ipairs(record.snapshots) do
        if is_valid(snapshot.parameter) then
            local after_ids = get_skill_ids(snapshot.parameter)
            local candidate = nil
            local removed, lock = detect_replaced_passive(snapshot.before_ids, after_ids)
            if removed ~= nil then
                if snapshot.expect_passive_id ~= nil
                    and snapshot.expect_passive_id ~= "None"
                    and removed ~= snapshot.expect_passive_id
                then
                    -- Logged, not refused: the passive list decides.
                    log(string.format(
                        "NOTE: the selected slot read as %s but the engine removed %s; "
                        .. "trusting the passive list.",
                        tostring(snapshot.expect_passive_id), tostring(removed)))
                end
                candidate = {
                    parameter = snapshot.parameter,
                    passive_id = removed,
                    item_id = module_for(removed),
                    before_ids = snapshot.before_ids,
                    request_player_id = record.request_player_id,
                    mode_source = record.mode_source,
                    lock = lock,
                    mode = EXTRACTION_MODES[lock],
                }
            else
                local added = detect_added_lock(snapshot.before_ids, after_ids)
                if added ~= nil then
                    candidate = {
                        parameter = snapshot.parameter,
                        before_ids = snapshot.before_ids,
                        request_player_id = record.request_player_id,
                        mode_source = record.mode_source,
                        lock = added,
                        mode = EXTRACTION_MODES[added],
                        stray = true,
                    }
                end
            end

            if candidate ~= nil then
                -- A second candidate is a refusal, not a choice.
                if resolved ~= nil then
                    return nil
                end
                resolved = candidate
            end
        end
    end
    return resolved
end

-- Narrower question than resolve_record: does any snapshot's passive list now
-- hold more of one of our markers than it did before. Returns that snapshot and
-- the marker id, or nil, nil -- including when two snapshots match.
--
-- Its answer is what write_journal("stranded") records, and a journal entry is
-- the only thing lp/recovery.lua acts on.
local function stranded_marker(record)
    if record == nil or record.snapshots == nil then
        return nil, nil
    end
    local found_snapshot, found_lock
    for _, snapshot in ipairs(record.snapshots) do
        if is_valid(snapshot.parameter) then
            local after_ids = get_skill_ids(snapshot.parameter)
            if after_ids ~= nil then
                local before = counts(snapshot.before_ids)
                local after = counts(after_ids)
                for id in pairs(after) do
                    if EXTRACTION_MODES[id] ~= nil and (after[id] or 0) > (before[id] or 0) then
                        if found_lock ~= nil then
                            return nil, nil
                        end
                        found_snapshot, found_lock = snapshot, id
                    end
                end
            end
        end
    end
    return found_snapshot, found_lock
end

-- Logs the outcome and arms the panel refresh.
--
-- reset_panel is false for mode == "implant", which is what stops
-- refresh_surgery_ui clearing the operation chip and the consume-item count for
-- an insert. See the note on refresh_surgery_ui in lp/ui.lua.
local function finish(message, mode)
    log(message)

    local reset_panel = mode ~= "implant"
    arm_refresh(reset_panel)

    -- Second path to the same armed refresh, for when the OnPassiveUpdate hook
    -- does not reach it. consume_pending_refresh runs at most once per arming.
    ExecuteWithDelay(500, function()
        ExecuteInGameThread(consume_pending_refresh)
    end)

    if reset_panel then
        -- Unconditional, and not gated on the armed refresh. Excluded for an
        -- implant because this call is not idempotent there: it clears a
        -- selection the mod did not make.
        ExecuteWithDelay(1600, function()
            ExecuteInGameThread(function()
                refresh_surgery_ui(true, false)
            end)
        end)
    end
end

-- One passive of an extract-all. The marker is still on the Pal here.
--
-- copies is how many times this passive appears in the list; RemovePassiveSkill
-- filters by name and takes every copy in one call, so all copies are granted
-- before the single removal. Returns the number granted, or 0.
local function extract_additional(parameter, passive_id, item_id, bag, lock, copies)
    copies = copies or 1
    if not write_journal("prepared", "loop", passive_id, item_id, lock) then
        log(string.format(
            "SKIPPED %s: the recovery journal could not be written.", passive_id))
        return 0
    end
    local granted = 0
    for _ = 1, copies do
        local ok, reason = add_implant(bag, item_id)
        if not ok then
            log(string.format("SKIPPED %s: implant grant failed (%s).", passive_id, tostring(reason)))
            break
        end
        granted = granted + 1
    end
    if granted < copies then
        -- Fewer granted than copies: keep the passive and keep what was
        -- granted.
        clear_journal()
        return 0
    end
    if not write_journal("granted", "loop", passive_id, item_id, lock) then
        -- Implant granted, passive still attached, no journal to authorise a
        -- replay. Both are kept.
        log(string.format(
            "WARNING: granted %s but the journal could not be updated; keeping passive %s.",
            item_id, passive_id))
        return 0
    end
    if not remove_skill(parameter, passive_id) then
        -- Journal kept: granted/loop is the state recovery completes.
        log(string.format(
            "WARNING: granted %s but could not remove passive %s; the implant was kept, and the "
            .. "journal is kept so the removal is retried on the next map load.",
            item_id, passive_id
        ))
        return 0
    end
    clear_journal()
    return granted
end

-- Extracts every remaining extractable passive on the Pal. Returns the count
-- extracted and the list of ids skipped.
local function extract_all_remaining(record, bag)
    local extracted, skipped = 0, {}
    local skill_ids = get_skill_ids(record.parameter) or {}

    -- Counts copies per id and builds a visit order, so each id is visited once
    -- however many copies of it the list holds.
    local copies, order = {}, {}
    for _, passive_id in ipairs(skill_ids) do
        if EXTRACTION_MODES[passive_id] == nil then
            if copies[passive_id] == nil then
                copies[passive_id] = 0
                order[#order + 1] = passive_id
            end
            copies[passive_id] = copies[passive_id] + 1
        end
    end

    for _, passive_id in ipairs(order) do
        if is_extractable(passive_id) then
            local taken = extract_additional(record.parameter, passive_id,
                module_for(passive_id), bag, record.lock, copies[passive_id])
            if taken > 0 then
                extracted = extracted + taken
            else
                skipped[#skipped + 1] = passive_id
            end
        else
            skipped[#skipped + 1] = passive_id
        end
    end
    return extracted, skipped
end

-- 12 attempts at 250 ms. Each retry allocates one closure pair; see the note on
-- registry churn in lp/hooks.lua before raising either number.
local RESOLVE_ATTEMPTS = 12
local RESOLVE_INTERVAL_MS = 250

local function finalize_extraction(record, attempt)
    local resolved = resolve_record(record)
    if resolved == nil then
        if attempt < RESOLVE_ATTEMPTS then
            ExecuteWithDelay(RESOLVE_INTERVAL_MS, function()
                ExecuteInGameThread(function()
                    finalize_extraction(record, attempt + 1)
                end)
            end)
        else
            -- Out of attempts. The journal is NOT cleared unconditionally here:
            -- if stranded_marker finds a marker, the entry it writes is what
            -- authorises lp/recovery.lua to remove it on the next map load.
            local snapshot, lock = stranded_marker(record)
            if lock == nil then
                clear_journal()
                finish("No marker appeared, so this was not one of our operations; "
                    .. "nothing was changed.")
            else
                local passive_id = snapshot.expect_passive_id
                if passive_id == "None" then
                    passive_id = nil
                end
                local journalled =
                    write_journal("prepared", "stranded", passive_id, nil, lock)
                finish(string.format(
                    "WARNING: the exchange could not be resolved and marker %s is stranded on "
                    .. "this Pal. Journalled=%s; if true it is cleaned up on the next map load.",
                    tostring(lock), tostring(journalled)))
            end
        end
        return
    end
    record = resolved

    -- Implant insertion, handled before the two extraction checks below: the
    -- stray test would match an alias in an empty slot, and is_extractable does
    -- not apply to an insert.
    if record.mode == "implant" then
        local target = IMPLANT_TARGET[record.lock]
        if target == nil then
            clear_journal()
            remove_skill(record.parameter, record.lock)
            -- No refund on this path. unwind_alias below needs
            -- module_for(target) to name the module, and target == nil is the
            -- definition of this branch. Reachable only from a JSON route row
            -- with no IMPLANT_TARGET entry in lp/ids.lua.
            finish(string.format(
                "ERROR: no target passive configured for alias %s; alias removed. The module "
                .. "was spent and CANNOT be refunded -- nothing records which module it was. "
                .. "This is a data fault: that route has no IMPLANT_TARGET entry.",
                tostring(record.lock)), record.mode)
            return
        end

        -- Removes the alias and grants one module back. Every abort below calls
        -- this; they differ in their clear_journal policy and their message.
        local function unwind_alias()
            local removed = remove_skill(record.parameter, record.lock)
            local bag = find_inventory(record.request_player_id)
            if not is_valid(bag) then
                return removed, false
            end
            return removed, (add_implant(bag, module_for(target)))
        end

        -- Journalled as "prepared": the alias is on the Pal and the module is
        -- already spent, so this is the entry recovery completes the swap from.
        if not write_journal("prepared", "implant", target, module_for(target),
                record.lock)
        then
            local removed, refunded = unwind_alias()
            finish(string.format(
                "ERROR: the recovery journal could not be written, so %s was not implanted. "
                .. "Alias removal=%s, module refunded=%s.",
                target, tostring(removed), tostring(refunded)), record.mode)
            return
        end

        -- Re-checked here rather than relying on the UI gate.
        if count_id(record.before_ids, target) > 0 then
            local removed, refunded = unwind_alias()
            -- Alias off, module back: nothing left for recovery.
            clear_journal()
            finish(string.format(
                "Blocked a duplicate %s: this Pal already has it. Alias removal=%s, module refunded=%s.",
                target, tostring(removed), tostring(refunded)), record.mode)
            return
        end

        if restore_replaced_passive(record.parameter, target, record.lock) then
            clear_journal()
            finish(string.format("Implanted %s from a disposable module for player %s (%s).",
                    target, tostring(player_id_number(record.request_player_id)), record.mode_source),
                record.mode)
        else
            local removed, refunded = unwind_alias()
            -- Cleared only if the alias came off; otherwise the entry is what
            -- recovery acts on.
            if removed then
                clear_journal()
            end
            finish(string.format(
                "ERROR: could not install %s from its module; alias removal=%s, module refunded=%s. "
                .. "The gold was spent.",
                target, tostring(removed), tostring(refunded)), record.mode)
        end
        return
    end

    -- Marker added with nothing removed: remove it and grant nothing.
    if record.stray then
        local cleared = remove_skill(record.parameter, record.lock)
        if cleared then
            clear_journal()
            finish("Nothing extracted: an empty slot was selected, so the marker was removed again.")
        else
            local journalled = write_journal(
                "prepared", "stranded", nil, nil, record.lock)
            finish(string.format(
                "ERROR: an empty slot was selected and marker %s could not be removed. "
                .. "Journalled=%s; it will be cleared on the next map load.",
                tostring(record.lock), tostring(journalled)))
        end
        return
    end

    if not is_extractable(record.passive_id) then
        restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        clear_journal()
        finish(string.format(
            "Blocked extraction of unsupported passive %s and restored it.", record.passive_id))
        return
    end

    local bag = find_inventory(record.request_player_id)
    if not is_valid(bag) then
        restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        clear_journal()
        finish(string.format(
            "ERROR: inventory unavailable; restored %s instead of removing it.", record.passive_id))
        return
    end

    -- Phase one: the passive the swap replaced with the marker.
    --
    -- The write_journal result is checked and a failure aborts before
    -- add_implant, so nothing is granted without an entry recording it.
    if not write_journal("prepared", "marker", record.passive_id, record.item_id, record.lock) then
        restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        finish(string.format(
            "ERROR: the recovery journal could not be written, so %s was restored rather than "
            .. "extracted without crash protection.", record.passive_id))
        return
    end
    local granted, reason = add_implant(bag, record.item_id)
    if not granted then
        local restored = restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        clear_journal()
        finish(string.format(
            "ERROR: implant grant failed for %s (%s); passive restoration=%s.",
            record.passive_id, tostring(reason), tostring(restored)))
        return
    end
    if not write_journal("granted", "marker", record.passive_id, record.item_id, record.lock) then
        -- Implant granted, marker still on the Pal, no entry advanced to
        -- authorise removing it. Stops here and keeps both.
        finish(string.format(
            "ERROR: granted %s but the journal could not be advanced; stopped before removing "
            .. "the marker. The implant was kept.", record.item_id))
        return
    end

    -- Phase two: extract-all sweeps the rest while the marker is still attached.
    local extra_extracted, extra_skipped = 0, {}
    if record.mode == "all" then
        extra_extracted, extra_skipped = extract_all_remaining(record, bag)
    end

    -- Phase three: remove the marker.
    if not remove_skill(record.parameter, record.lock) then
        -- Journal left in place, stamped granted/marker: that is the entry
        -- lp/recovery.lua completes by removing the marker.
        finish(string.format(
            "ERROR: marker cleanup failed after granting %s. The implant was retained, and the "
            .. "journal is kept so the marker is cleaned up on the next map load.",
            record.passive_id))
        return
    end
    clear_journal()

    if record.mode == "all" then
        local skipped_note = ""
        if #extra_skipped > 0 then
            skipped_note = string.format(" Skipped (no implant): %s.", table.concat(extra_skipped, ", "))
        end
        finish(string.format(
            "Extracted %d passive(s) from this Pal for player %s (%s): %s plus %d more.%s",
            extra_extracted + 1, tostring(player_id_number(record.request_player_id)),
            record.mode_source, record.passive_id, extra_extracted, skipped_note))
    else
        finish(string.format(
            "Extracted %s into %s for player %s (%s).",
            record.passive_id, record.item_id,
            tostring(player_id_number(record.request_player_id)), record.mode_source))
    end
end

return {
    capture_record = capture_record,
    finalize_extraction = finalize_extraction,
}
