-- Lootable Passives -- The exchange: capture, resolve, grant, remove.
--
-- Call order in the extraction path: begin_journal("prepared"), add_implant,
-- write_journal("granted"), remove_skill, clear_journal. The module is created
-- before the passive is removed. begin_journal settles any earlier row still on
-- disk before writing over it.

local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")
local recovery = require("lp.recovery")
local ui = require("lp.ui")
local is_valid = util.is_valid
local log = util.log
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
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
local local_player_id = inventory.local_player_id
local player_id_number = inventory.player_id_number
local player_uid = inventory.player_uid
local remove_skill = inventory.remove_skill
local restore_replaced_passive = inventory.restore_replaced_passive
local settle_before_exchange = recovery.settle_before_exchange
local current_page = ui.current_page
local on_transaction_complete = ui.on_transaction_complete
local selected_parameter = ui.selected_parameter
local selected_passive = ui.selected_passive
local visible_extraction_widget = ui.visible_extraction_widget

--------------------------------------------------------------------------------
-- Request capture
--------------------------------------------------------------------------------

-- Builds a record from the tab page: the selected slot's passive, the Pal's
-- parameter object, and its passive list before the swap. Returns nil if there
-- is no visible page with one of our operations pending, no parameter, or no
-- passive list.
--
-- An empty slot reads as a nil passive and is captured like any other: an
-- extract mode there appends its marker, which resolve_record reports as stray
-- and finalize_extraction removes.
local function capture_targeted_record(request_player_id)
    local widget = visible_extraction_widget()
    if not is_valid(widget) then
        return nil
    end
    local passive_id = selected_passive(widget)
    local parameter = selected_parameter(widget)
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

-- Snapshots every PalIndividualCharacterParameter in the world whose
-- OwnerPlayerUId is the requester's PlayerUId, via passives.snapshot_all, which
-- crash recovery also calls unfiltered. Returns nil, and logs, when the
-- requester's PlayerUId does not read: an unfiltered snapshot would resolve to a
-- marker swap on any player's Pal and grant its module to this requester.
local function snapshot_server_parameters(request_player_id)
    local owner = player_uid(request_player_id)
    if owner == nil then
        log(string.format(
            "WARNING: could not read the PlayerUId of requesting player %s, so this Surgery Table "
            .. "request was not tracked. If it was one of this mod's operations, its marker stays on "
            .. "the Pal and nothing was granted.",
            tostring(player_id_number(request_player_id))))
        return nil
    end
    return {
        snapshots = snapshot_all(owner),
        request_player_id = request_player_id,
        mode_source = "owner snapshot",
    }
end

-- True when the requester's PlayerId and the local player's both read and
-- differ. The recorded tab page is the local player's, so it says nothing about
-- such a request. False when either id cannot be read.
local function is_remote_request(request_player_id)
    local requester = player_id_number(request_player_id)
    local own = local_player_id()
    return requester ~= nil and own ~= nil and requester ~= own
end

-- For a request from the local player, tries capture_targeted_record first and
-- falls through to the owner snapshot only when there is no tab page at
-- all; a page that is present and yielded nothing returns nil instead. A remote
-- request goes straight to the snapshot, and its record carries remote = true,
-- which is what keeps finish off the local player's Surgery panel.
local function capture_record(request_player_id)
    if is_remote_request(request_player_id) then
        local fallback_ok, fallback = pcall(snapshot_server_parameters, request_player_id)
        if not fallback_ok or fallback == nil then
            return nil
        end
        fallback.remote = true
        return fallback
    end
    local succeeded, record = pcall(capture_targeted_record, request_player_id)
    if succeeded and record ~= nil then
        return record
    end
    if current_page() ~= nil then
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
            local removed, lock = detect_replaced_passive(snapshot.before_ids, after_ids)
            local stray = false
            if removed ~= nil then
                if snapshot.expect_passive_id ~= nil and removed ~= snapshot.expect_passive_id then
                    -- Logged, not refused: the passive list decides.
                    log(string.format(
                        "NOTE: the selected slot read as %s but the engine removed %s; "
                        .. "trusting the passive list.",
                        tostring(snapshot.expect_passive_id), tostring(removed)))
                end
            else
                lock = detect_added_lock(snapshot.before_ids, after_ids)
                stray = lock ~= nil
            end

            if lock ~= nil then
                -- A second candidate is a refusal, not a choice.
                if resolved ~= nil then
                    return nil
                end
                resolved = {
                    parameter = snapshot.parameter,
                    passive_id = removed,
                    item_id = removed and module_for(removed),
                    before_ids = snapshot.before_ids,
                    request_player_id = record.request_player_id,
                    mode_source = record.mode_source,
                    remote = record.remote,
                    lock = lock,
                    mode = EXTRACTION_MODES[lock],
                    stray = stray or nil,
                }
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

-- Logs the outcome. The panel refresh that follows it is
-- ui.on_transaction_complete, which reads mode and owns every timing decision
-- in it. Not called for a remote record: the panel is the local player's, and
-- the exchange was not.
local function finish(record, message, mode)
    log(message)
    if not record.remote then
        on_transaction_complete(mode)
    end
end

-- The first row of an exchange. write_journal replaces whatever row is on disk,
-- so recovery.settle_before_exchange runs first, against the exchange's Pal and
-- its passive list before the swap. False when either refuses.
local function begin_journal(parameter, before_ids, state, phase, passive_id, item_id, lock)
    return settle_before_exchange(parameter, before_ids)
        and write_journal(state, phase, passive_id, item_id, lock)
end

-- Is the marker still on the Pal?
local function marker_attached(parameter, lock)
    return count_id(get_skill_ids(parameter), lock) > 0
end

-- Restores the passive the swap replaced, on an extraction abort, and reports
-- what happened for the log.
--
-- journal_row says what is on disk for this exchange: "own" when its
-- prepared/marker row is, "write" when nothing is and one may be written, "none"
-- when the journal is unavailable. If the restore fails while the marker is
-- still attached, that row is kept or a stranded row naming the passive is
-- written, so recovery retries the restore. Anything this exchange journalled is
-- cleared otherwise.
local function restore_on_abort(record, journal_row)
    if restore_replaced_passive(record.parameter, record.passive_id, record.lock) then
        if journal_row == "own" then
            clear_journal()
        end
        return string.format("%s was restored", record.passive_id)
    end
    if not marker_attached(record.parameter, record.lock) then
        if journal_row == "own" then
            clear_journal()
        end
        return string.format("%s could NOT be restored and is lost", record.passive_id)
    end
    if journal_row == "own" or (journal_row == "write" and begin_journal(record.parameter,
            record.before_ids, "prepared", "stranded", record.passive_id, nil, record.lock))
    then
        return string.format("%s could not be restored yet; journalled so the restore is retried "
            .. "on the next map load", record.passive_id)
    end
    return string.format("%s could not be restored and could not be journalled; marker %s stays "
        .. "on the Pal", record.passive_id, record.lock)
end

-- One passive of an extract-all. The marker is still on the Pal here.
--
-- Returns true when the module was granted and the passive removed, and true as
-- a second value when the sweep has to stop.
--
-- Nothing here clears the journal. write_journal opens "w", so the next
-- iteration overwrites this one's row, and extract_all_remaining's caller writes
-- the outer row back when the sweep ends. The one row that must survive is
-- granted/loop after a failed removal, which is why that case stops the sweep.
local function extract_additional(parameter, passive_id, item_id, bag, lock)
    if not write_journal("prepared", "loop", passive_id, item_id, lock) then
        log(string.format(
            "SKIPPED %s: the recovery journal could not be written.", passive_id))
        return false, false
    end
    local granted, reason = add_implant(bag, item_id)
    if not granted then
        -- The passive is kept. The row on disk still reads prepared, which
        -- recovery acts on by removing the marker and nothing else.
        log(string.format("SKIPPED %s: implant grant failed (%s).", passive_id, tostring(reason)))
        return false, false
    end
    if not write_journal("granted", "loop", passive_id, item_id, lock) then
        -- Implant granted, passive still attached, no journal to authorise a
        -- replay. Both are kept.
        log(string.format(
            "WARNING: granted %s but the journal could not be updated; keeping passive %s.",
            item_id, passive_id))
        return false, false
    end
    if not remove_skill(parameter, passive_id) then
        -- Journal kept: granted/loop is the state recovery completes, by
        -- removing this passive and then the marker.
        log(string.format(
            "WARNING: granted %s but could not remove passive %s; the implant was kept, the sweep "
            .. "stops here, and the journal and marker are kept so the removal is retried on the "
            .. "next map load.",
            item_id, passive_id
        ))
        return false, true
    end
    return true, false
end

-- Extracts every remaining extractable passive on the Pal, skipping the
-- markers. Returns the count extracted, the list of ids skipped, and true as a
-- third value when extract_additional stopped the sweep.
local function extract_all_remaining(record, bag)
    local extracted, skipped = 0, {}
    for _, passive_id in ipairs(get_skill_ids(record.parameter) or {}) do
        if EXTRACTION_MODES[passive_id] == nil then
            if is_extractable(passive_id) then
                local taken, halted = extract_additional(record.parameter, passive_id,
                    module_for(passive_id), bag, record.lock)
                if halted then
                    return extracted, skipped, true
                end
                if taken then
                    extracted = extracted + 1
                else
                    skipped[#skipped + 1] = passive_id
                end
            else
                skipped[#skipped + 1] = passive_id
            end
        end
    end
    return extracted, skipped, false
end

-- 12 attempts at 250 ms. Each retry allocates one closure pair; see the note on
-- coalescer() in main.lua before raising either number.
local RESOLVE_ATTEMPTS = 12
local RESOLVE_INTERVAL_MS = 250

local finalize_extraction

-- Runs finalize_extraction(record, attempt) on the game thread after delay_ms.
local function schedule_finalize(record, attempt, delay_ms)
    ExecuteWithDelay(delay_ms, function()
        ExecuteInGameThread(function()
            finalize_extraction(record, attempt)
        end)
    end)
end

function finalize_extraction(record, attempt)
    local resolved = resolve_record(record)
    if resolved == nil then
        if attempt < RESOLVE_ATTEMPTS then
            schedule_finalize(record, attempt + 1, RESOLVE_INTERVAL_MS)
        else
            -- Out of attempts. Nothing has been journalled for this exchange,
            -- so a row on disk belongs to an earlier one and is not touched
            -- here. If stranded_marker finds a marker, the row written for it is
            -- what authorises lp/recovery.lua to remove it on the next map load.
            local snapshot, lock = stranded_marker(record)
            if snapshot == nil then
                finish(record, "No marker appeared, so this was not one of our operations; "
                    .. "nothing was changed.")
            else
                local journalled = begin_journal(snapshot.parameter, snapshot.before_ids,
                    "prepared", "stranded", snapshot.expect_passive_id, nil, lock)
                finish(record, string.format(
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
            remove_skill(record.parameter, record.lock)
            -- No refund on this path. unwind_alias below needs
            -- module_for(target) to name the module, and target == nil is the
            -- definition of this branch. Reachable only from a JSON route row
            -- with no IMPLANT_TARGET entry in lp/ids.lua.
            finish(record, string.format(
                "ERROR: no target passive configured for alias %s; alias removed. The module "
                .. "was spent and CANNOT be refunded -- nothing records which module it was. "
                .. "This is a data fault: that route has no IMPLANT_TARGET entry.",
                tostring(record.lock)), record.mode)
            return
        end

        -- Takes the alias off -- putting back the passive it overwrote, when it
        -- went into a filled slot -- and grants one module back. Returns whether
        -- the Pal is back as it was, and whether the module was refunded. Every
        -- abort below calls this.
        local function unwind_alias()
            local undone
            if record.passive_id ~= nil then
                undone = restore_replaced_passive(record.parameter, record.passive_id, record.lock)
            else
                undone = remove_skill(record.parameter, record.lock)
            end
            local bag = find_inventory(record.request_player_id)
            if not is_valid(bag) then
                return undone, false
            end
            return undone, (add_implant(bag, module_for(target)))
        end

        -- After unwind_alias, on an abort made with this exchange's
        -- prepared/implant row on disk, which recovery replays by installing
        -- target. Cleared once the alias is off. With the alias still attached,
        -- the row is kept when keep_insert is true, and otherwise rewritten as a
        -- stranded row, which recovery replays by finishing the unwind.
        local function settle_unwound(undone, keep_insert)
            if undone or not marker_attached(record.parameter, record.lock) then
                clear_journal()
            elseif not keep_insert then
                write_journal("prepared", "stranded", record.passive_id, nil, record.lock)
            end
        end

        -- Journalled as "prepared": the alias is on the Pal and the module is
        -- already spent, so this is the entry recovery completes the swap from.
        if not begin_journal(record.parameter, record.before_ids, "prepared", "implant",
                target, module_for(target), record.lock)
        then
            local undone, refunded = unwind_alias()
            finish(record, string.format(
                "ERROR: the recovery journal could not be written, so %s was not implanted. "
                .. "Alias undone=%s, module refunded=%s.",
                target, tostring(undone), tostring(refunded)), record.mode)
            return
        end

        -- Re-checked here rather than relying on the UI gate.
        if count_id(record.before_ids, target) > 0 then
            local undone, refunded = unwind_alias()
            -- Never keep_insert: installing target is the duplicate.
            settle_unwound(undone, false)
            finish(record, string.format(
                "Blocked a duplicate %s: this Pal already has it. Alias undone=%s, module refunded=%s.",
                target, tostring(undone), tostring(refunded)), record.mode)
            return
        end

        if restore_replaced_passive(record.parameter, target, record.lock) then
            clear_journal()
            finish(record, string.format("Implanted %s from a disposable module for player %s (%s).",
                    target, tostring(player_id_number(record.request_player_id)), record.mode_source),
                record.mode)
        else
            local undone, refunded = unwind_alias()
            -- A module that was not refunded is still paid for, so the insert
            -- stays journalled for recovery to retry.
            settle_unwound(undone, not refunded)
            finish(record, string.format(
                "ERROR: could not install %s from its module; alias undone=%s, module refunded=%s. "
                .. "The gold was spent.",
                target, tostring(undone), tostring(refunded)), record.mode)
        end
        return
    end

    -- Marker added with nothing removed: remove it and grant nothing.
    if record.stray then
        if remove_skill(record.parameter, record.lock) then
            finish(record, "Nothing extracted: an empty slot was selected, so the marker was removed again.")
        else
            local journalled = begin_journal(record.parameter, record.before_ids,
                "prepared", "stranded", nil, nil, record.lock)
            finish(record, string.format(
                "ERROR: an empty slot was selected and marker %s could not be removed. "
                .. "Journalled=%s; if true it is cleared on the next map load.",
                tostring(record.lock), tostring(journalled)))
        end
        return
    end

    if not is_extractable(record.passive_id) then
        finish(record, string.format("Blocked extraction of unsupported passive %s; %s.",
            record.passive_id, restore_on_abort(record, "write")))
        return
    end

    local bag = find_inventory(record.request_player_id)
    if not is_valid(bag) then
        finish(record, string.format("ERROR: inventory unavailable, so %s was not extracted; %s.",
            record.passive_id, restore_on_abort(record, "write")))
        return
    end

    -- Phase one: the passive the swap replaced with the marker.
    --
    -- The begin_journal result is checked and a failure aborts before
    -- add_implant, so nothing is granted without an entry recording it.
    if not begin_journal(record.parameter, record.before_ids, "prepared", "marker",
            record.passive_id, record.item_id, record.lock)
    then
        finish(record, string.format(
            "ERROR: the recovery journal could not be written, so %s was not extracted without "
            .. "crash protection; %s.", record.passive_id, restore_on_abort(record, "none")))
        return
    end
    local granted, reason = add_implant(bag, record.item_id)
    if not granted then
        finish(record, string.format("ERROR: implant grant failed for %s (%s); %s.",
            record.passive_id, tostring(reason), restore_on_abort(record, "own")))
        return
    end
    if not write_journal("granted", "marker", record.passive_id, record.item_id, record.lock) then
        -- Implant granted, marker still on the Pal, no entry advanced to
        -- authorise removing it. Stops here and keeps both.
        finish(record, string.format(
            "ERROR: granted %s but the journal could not be advanced; stopped before removing "
            .. "the marker. The implant was kept.", record.item_id))
        return
    end

    -- Phase two: extract-all sweeps the rest while the marker is still attached.
    local extra_extracted, extra_skipped = 0, {}
    if record.mode == "all" then
        local halted
        extra_extracted, extra_skipped, halted = extract_all_remaining(record, bag)
        if halted then
            -- The sweep's granted/loop row is on disk and the marker is still
            -- attached; recovery removes the passive and then the marker.
            finish(record, string.format(
                "ERROR: extract-all stopped after %s and %d more passive(s), when a passive could "
                .. "not be removed after its module was granted. The modules were kept, and the "
                .. "journal and marker are kept so the removal is finished on the next map load.",
                record.passive_id, extra_extracted))
            return
        end
        -- The sweep leaves its own last row on disk. Phase three's failure path
        -- below relies on the outer granted/marker row being the one recovery
        -- finds, so it is written back before that removal is attempted.
        if not write_journal("granted", "marker", record.passive_id, record.item_id, record.lock) then
            log("WARNING: the recovery journal could not be restored after the extract-all "
                .. "sweep. If the marker removal below fails, recovery replays the sweep's last "
                .. "row instead, which removes the marker and nothing else.")
        end
    end

    -- Phase three: remove the marker.
    if not remove_skill(record.parameter, record.lock) then
        -- Journal left in place, stamped granted/marker: that is the entry
        -- lp/recovery.lua completes by removing the marker.
        finish(record, string.format(
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
        finish(record, string.format(
            "Extracted %d passive(s) from this Pal for player %s (%s): %s plus %d more.%s",
            extra_extracted + 1, tostring(player_id_number(record.request_player_id)),
            record.mode_source, record.passive_id, extra_extracted, skipped_note))
    else
        finish(record, string.format(
            "Extracted %s into %s for player %s (%s).",
            record.passive_id, record.item_id,
            tostring(player_id_number(record.request_player_id)), record.mode_source))
    end
end

return {
    capture_record = capture_record,
    schedule_finalize = schedule_finalize,
}
