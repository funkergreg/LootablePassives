-- Lootable Passives -- The exchange: capture, resolve, grant, remove.
--
-- Call order in the extraction path: begin_journal (a "prepared" row), add_implant,
-- write_journal("granted"), remove_skill, clear_journal. The module is created
-- before the passive is removed. begin_journal settles any earlier row still on
-- disk before writing over it.
--
-- Nothing here writes to the Surgery panel. Each peer repairs its own panel from
-- what it observes in lp/ui.lua; this file only logs outcomes.

local util = require("lp.util")
local config = require("lp.config")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local inventory = require("lp.inventory")
local ledger = require("lp.ledger")
local recovery = require("lp.recovery")
local ui = require("lp.ui")
local is_valid = util.is_valid
local log = util.log
local run_later = util.run_later
local HALT = config.HALT
local debug_log = config.debug_log
local fault = config.fault
local fault_log = config.fault_log
local begin_scenario = config.begin_scenario
local claim_scenario = config.claim_scenario
local describe_scenario = config.describe_scenario
local end_scenario = config.end_scenario
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local clear_journal = journal.clear_journal
local write_journal = journal.write_journal
local count_id = passives.count_id
local counts = passives.counts
local detect_added_lock = passives.detect_added_lock
local detect_replaced_passive = passives.detect_replaced_passive
local get_skill_ids = passives.get_skill_ids
local has_skill = passives.has_skill
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
local undo_swap = inventory.undo_swap
local settle_before_exchange = recovery.settle_before_exchange
local current_page = ui.current_page
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

-- Snapshots every PalIndividualCharacterParameter in the world, via
-- passives.snapshot_all, which crash recovery also calls. There is no owner
-- filter: the Pal a player operates on need not carry that player's
-- OwnerPlayerUId. resolve_record refuses when more than one snapshot shows a
-- marker swap, which is what keeps two players' simultaneous requests apart.
local function snapshot_server_parameters(request_player_id)
    return {
        snapshots = snapshot_all(),
        request_player_id = request_player_id,
        mode_source = "server snapshot",
    }
end

-- True when the requester's PlayerId and the local player's both read and are
-- equal. False when either id cannot be read.
local function is_local_request(request_player_id)
    local requester = player_id_number(request_player_id)
    return requester ~= nil and requester == local_player_id()
end

-- For a request from the local player, tries capture_targeted_record first and
-- falls through to the server snapshot only when there is no tab page at
-- all; a page that is present and yielded nothing returns nil instead. Any other
-- request, including one whose requester cannot be identified, goes straight to
-- the snapshot: the recorded tab page is the local player's.
local function capture_record(request_player_id)
    local is_local = is_local_request(request_player_id)
    debug_log(string.format("capture: requester=%s local=%s is_local=%s",
        tostring(player_id_number(request_player_id)), tostring(local_player_id()),
        tostring(is_local)))
    if is_local then
        local succeeded, record = pcall(capture_targeted_record, request_player_id)
        if succeeded and record ~= nil then
            debug_log(string.format("capture: targeted UI, selected passive %s",
                tostring(record.snapshots[1].expect_passive_id)))
            return record
        end
        if current_page() ~= nil then
            debug_log("capture: tab page present but yielded no record; request not tracked")
            return nil
        end
    end
    local fallback_ok, fallback = pcall(snapshot_server_parameters, request_player_id)
    if not fallback_ok then
        debug_log("capture: server snapshot raised; request not tracked")
        return nil
    end
    debug_log(string.format("capture: server snapshot of %d Pals", #fallback.snapshots))
    return fallback
end

-- How a passive list neither detector matched has moved since the snapshot:
-- "marker" when any marker's count rose, "vanilla" when the list differs in any
-- other way, nil when it is unchanged or does not read. Compared element by
-- element first, so an unchanged list builds no tables.
local function unmatched_change(before_ids, after_ids)
    if after_ids == nil then
        return nil
    end
    if #before_ids == #after_ids then
        local same = true
        for index = 1, #before_ids do
            if before_ids[index] ~= after_ids[index] then
                same = false
                break
            end
        end
        if same then
            return nil
        end
    end
    local before = counts(before_ids)
    for id, count in pairs(counts(after_ids)) do
        if EXTRACTION_MODES[id] ~= nil and count > (before[id] or 0) then
            return "marker"
        end
    end
    return "vanilla"
end

-- Re-reads each snapshot's passive list and looks for one of two shapes: a
-- passive replaced by a marker (detect_replaced_passive) or a marker added with
-- nothing removed (detect_added_lock, recorded as stray). Returns the single
-- candidate, or nil if none or more than one matched.
--
-- The second return is true when nothing matched, at least one list changed,
-- and no marker's count rose in any of them: a vanilla operation that has
-- already happened, so retrying cannot turn it into one of ours.
local function resolve_record(record)
    if record == nil or record.snapshots == nil then
        return nil, false
    end

    local resolved = nil
    local vanilla_seen, marker_seen = false, false
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

            if lock == nil then
                local change = unmatched_change(snapshot.before_ids, after_ids)
                marker_seen = marker_seen or change == "marker"
                vanilla_seen = vanilla_seen or change == "vanilla"
            else
                -- A second candidate is a refusal, not a choice.
                if resolved ~= nil then
                    return nil, false
                end
                resolved = {
                    parameter = snapshot.parameter,
                    passive_id = removed,
                    item_id = removed and module_for(removed),
                    before_ids = snapshot.before_ids,
                    request_player_id = record.request_player_id,
                    mode_source = record.mode_source,
                    lock = lock,
                    mode = EXTRACTION_MODES[lock],
                    stray = stray or nil,
                }
            end
        end
    end
    return resolved, resolved == nil and vanilla_seen and not marker_seen
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

-- The first row of an exchange, always "prepared". write_journal replaces
-- whatever row is on disk, so recovery.settle_before_exchange runs first,
-- against the exchange's Pal and its passive list before the swap. False when
-- either refuses.
local function begin_journal(parameter, before_ids, phase, passive_id, item_id, lock)
    return settle_before_exchange(parameter, before_ids)
        and write_journal("prepared", phase, passive_id, item_id, lock)
end

-- The journal after an abort's undo, for both the extraction and the implant
-- abort. undone is the undo's result.
--
-- on_disk says what this exchange has journalled:
--   "keep"     its row is on disk and stays if the marker is still attached
--   "replace"  its row is on disk and is rewritten as a stranded row if the
--              marker is still attached; write_journal alone, since the row
--              being replaced is this exchange's
--   "write"    nothing is on disk and a stranded row may be written, through
--              begin_journal, which settles an earlier row first
--   "none"     the journal is unavailable
-- The stranded row names record.passive_id, so recovery's replay finishes the
-- undo.
--
-- Returns "off" when the undo succeeded or the marker is gone anyway, having
-- cleared any row this exchange has on disk; "journalled" when the marker is
-- still attached and a row stands for recovery; "unjournalled" when it is
-- still attached and no row could stand.
local function journal_after_undo(record, undone, on_disk)
    if undone or not has_skill(record.parameter, record.lock) then
        if on_disk == "keep" or on_disk == "replace" then
            clear_journal()
        end
        return "off"
    end
    local journalled = on_disk == "keep"
        or (on_disk == "replace"
            and write_journal("prepared", "stranded", record.passive_id, nil, record.lock))
        or (on_disk == "write" and begin_journal(record.parameter, record.before_ids,
            "stranded", record.passive_id, nil, record.lock))
    return journalled and "journalled" or "unjournalled"
end

-- Restores the passive the swap replaced, on an extraction abort, and reports
-- what happened for the log. on_disk is as journal_after_undo takes it: "keep"
-- for this exchange's prepared/marker row, whose replay is the restore.
local function restore_on_abort(record, on_disk)
    local restored = restore_replaced_passive(record.parameter, record.passive_id, record.lock)
    local outcome = journal_after_undo(record, restored, on_disk)
    if restored then
        return string.format("%s was restored", record.passive_id)
    end
    if outcome == "off" then
        return string.format("%s could NOT be restored and is lost", record.passive_id)
    end
    if outcome == "journalled" then
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
    local journalled = write_journal("granted", "loop", passive_id, item_id, lock)
    if not journalled then
        log(string.format(
            "WARNING: granted %s but the journal could not be updated; removing passive %s "
            .. "without it.", item_id, passive_id))
    end
    if not remove_skill(parameter, passive_id) then
        if not journalled then
            -- No granted/loop row stands to finish the removal, so the sweep
            -- moves on with the passive still attached.
            log(string.format(
                "WARNING: granted %s and could not remove passive %s; no journal row records it, "
                .. "so both are kept.", item_id, passive_id))
            return false, false
        end
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

--------------------------------------------------------------------------------
-- Implant insertion
--------------------------------------------------------------------------------

-- Takes the alias off -- putting back the passive it overwrote, when it went
-- into a filled slot -- and grants one module for target back. When the grant
-- fails, the module is recorded in lp/ledger.lua against the requester's
-- PlayerUId, or the ledger's any-owner bucket when that does not read, and
-- delivered on a later flush. Returns whether the Pal is back as it was, and
-- "refunded" or "owed". Every abort in finalize_implant calls this.
local function unwind_alias(record, target)
    local undone = undo_swap(record.parameter, record.passive_id, record.lock)
    local item_id = module_for(target)
    if fault("fail_refund", false) then
        fault_log("direct refund of " .. item_id .. " skipped on purpose")
    else
        local bag = find_inventory(record.request_player_id)
        if is_valid(bag) and add_implant(bag, item_id) then
            return undone, "refunded"
        end
    end
    ledger.owe(player_uid(record.request_player_id), { item_id })
    log(string.format("Could not refund %s directly; recorded it as owed.", item_id))
    return undone, "owed"
end

-- A resolved record whose marker is an alias: replaces the alias with
-- IMPLANT_TARGET[record.lock], or unwinds and refunds.
local function finalize_implant(record)
    local target = IMPLANT_TARGET[record.lock]
    if target == nil then
        remove_skill(record.parameter, record.lock)
        -- No refund on this path. unwind_alias needs module_for(target) to name
        -- the module, and target == nil is the definition of this branch.
        -- Reachable only from a JSON route row with no IMPLANT_TARGET entry in
        -- lp/ids.lua.
        log(string.format(
            "ERROR: no target passive configured for alias %s; alias removed. The module "
            .. "was spent and CANNOT be refunded -- nothing records which module it was. "
            .. "This is a data fault: that route has no IMPLANT_TARGET entry.",
            tostring(record.lock)))
        return
    end

    -- Journalled as "prepared": the alias is on the Pal and the module is
    -- already spent, so this is the entry recovery completes the swap from.
    if not begin_journal(record.parameter, record.before_ids, "implant",
            target, module_for(target), record.lock)
    then
        local undone, refund = unwind_alias(record, target)
        log(string.format(
            "ERROR: the recovery journal could not be written, so %s was not implanted. "
            .. "Alias undone=%s, module %s.",
            target, tostring(undone), refund))
        return
    end

    -- Re-checked here rather than relying on the UI gate.
    if count_id(record.before_ids, target) > 0 then
        local undone, refund = unwind_alias(record, target)
        -- The prepared/implant row on disk replays by installing target, which
        -- here is the duplicate, so it is never kept.
        journal_after_undo(record, undone, "replace")
        log(string.format(
            "Blocked a duplicate %s: this Pal already has it. Alias undone=%s, module %s.",
            target, tostring(undone), refund))
        return
    end

    if restore_replaced_passive(record.parameter, target, record.lock) then
        clear_journal()
        log(string.format("Implanted %s from a disposable module for player %s (%s).",
            target, tostring(player_id_number(record.request_player_id)), record.mode_source))
    else
        local undone, refund = unwind_alias(record, target)
        -- The module is refunded or owed, so the prepared/implant row is
        -- replaced by one that finishes the unwind, or cleared when the alias
        -- is already off.
        journal_after_undo(record, undone, "replace")
        log(string.format(
            "ERROR: could not install %s from its module; alias undone=%s, module %s. "
            .. "The gold was spent.",
            target, tostring(undone), refund))
    end
end

--------------------------------------------------------------------------------
-- Finalize
--------------------------------------------------------------------------------

-- 12 attempts at 250 ms. Each retry allocates one closure; see the note on
-- coalescer() in lp/util.lua before raising either number.
local RESOLVE_ATTEMPTS = 12
local RESOLVE_INTERVAL_MS = 250

local finalize_extraction

-- Runs finalize_extraction(record, attempt) under an argument-form pcall, with
-- record.scenario the active fault scenario for the duration. A raised
-- config.HALT is logged as the debug halt it is; any other error is logged as
-- an ERROR.
local function run_finalize(record, attempt)
    begin_scenario(record.scenario)
    local succeeded, raised = pcall(finalize_extraction, record, attempt)
    end_scenario()
    if succeeded then
        return
    end
    if raised == HALT then
        fault_log("the exchange stopped where halt_after_journal names; the journal row on disk "
            .. "is replayed on the next map load")
    else
        log("ERROR: the exchange raised a Lua error and stopped: " .. tostring(raised))
    end
end

-- Runs finalize_extraction(record, attempt) on the game thread after delay_ms.
local function schedule_finalize(record, attempt, delay_ms)
    run_later(delay_ms, run_finalize, record, attempt)
end

-- On the first attempt that resolves the record, claims the fault scenario for
-- its mode (config.claim_scenario), stores it on the record and makes it
-- active. A record that already has one keeps it.
local function claim_for(record, mode)
    if record.scenario_claimed then
        return
    end
    record.scenario_claimed = true
    record.scenario = claim_scenario(mode)
    if record.scenario ~= nil then
        begin_scenario(record.scenario)
        debug_log(string.format("this %s exchange runs under fault scenario %d (%s)", mode,
            record.scenario, describe_scenario(record.scenario)))
    else
        debug_log(string.format("no fault scenario left for this %s exchange", mode))
    end
end

function finalize_extraction(record, attempt)
    local resolved, vanilla = resolve_record(record)
    if resolved ~= nil then
        claim_for(record, resolved.mode)
        debug_log(string.format("resolve attempt %d: marker %s (%s) replaced %s%s", attempt,
            tostring(resolved.lock), tostring(resolved.mode), tostring(resolved.passive_id),
            resolved.stray and ", stray" or ""))
        if fault("fail_resolve", false) then
            fault_log("resolve attempt result discarded on purpose")
            resolved = nil
        end
    elseif attempt == 1 or attempt == RESOLVE_ATTEMPTS or vanilla then
        debug_log(string.format("resolve attempt %d of %d: nothing matched (vanilla=%s)",
            attempt, RESOLVE_ATTEMPTS, tostring(vanilla)))
    end
    if resolved == nil then
        if vanilla then
            -- The same outcome as running out of attempts with no marker, on
            -- the first attempt that sees the change.
            log("A passive list changed with no marker, so this was not one of our "
                .. "operations; nothing was changed.")
        elseif attempt < RESOLVE_ATTEMPTS then
            schedule_finalize(record, attempt + 1, RESOLVE_INTERVAL_MS)
        else
            -- Out of attempts. Nothing has been journalled for this exchange,
            -- so a row on disk belongs to an earlier one and is not touched
            -- here. If stranded_marker finds a marker, the row written for it is
            -- what authorises lp/recovery.lua to remove it on the next map load.
            local snapshot, lock = stranded_marker(record)
            if snapshot == nil then
                log("No marker appeared, so this was not one of our operations; "
                    .. "nothing was changed.")
            else
                -- The selected slot's passive is named only when its count
                -- fell, so recovery puts back a passive the swap removed and
                -- otherwise only removes the marker.
                local lost = snapshot.expect_passive_id
                local after_ids = get_skill_ids(snapshot.parameter)
                if lost ~= nil and (after_ids == nil
                        or count_id(after_ids, lost) >= count_id(snapshot.before_ids, lost))
                then
                    lost = nil
                end
                local journalled = begin_journal(snapshot.parameter, snapshot.before_ids,
                    "stranded", lost, nil, lock)
                log(string.format(
                    "WARNING: the exchange could not be resolved and marker %s is stranded on "
                    .. "this Pal. Journalled=%s, naming passive %s; if true it is cleaned up on "
                    .. "the next map load.",
                    tostring(lock), tostring(journalled), tostring(lost)))
            end
        end
        return
    end
    record = resolved

    -- Implant insertion, handled before the two extraction checks below: the
    -- stray test would match an alias in an empty slot, and is_extractable does
    -- not apply to an insert.
    if record.mode == "implant" then
        finalize_implant(record)
        return
    end

    -- Marker added with nothing removed: remove it and grant nothing.
    if record.stray then
        if remove_skill(record.parameter, record.lock) then
            log("Nothing extracted: an empty slot was selected, so the marker was removed again.")
        else
            local journalled = begin_journal(record.parameter, record.before_ids,
                "stranded", nil, nil, record.lock)
            log(string.format(
                "ERROR: an empty slot was selected and marker %s could not be removed. "
                .. "Journalled=%s; if true it is cleared on the next map load.",
                tostring(record.lock), tostring(journalled)))
        end
        return
    end

    if not is_extractable(record.passive_id) then
        log(string.format("Blocked extraction of unsupported passive %s; %s.",
            record.passive_id, restore_on_abort(record, "write")))
        return
    end

    local bag = find_inventory(record.request_player_id)
    if not is_valid(bag) then
        log(string.format("ERROR: inventory unavailable, so %s was not extracted; %s.",
            record.passive_id, restore_on_abort(record, "write")))
        return
    end

    -- Phase one: the passive the swap replaced with the marker.
    --
    -- The begin_journal result is checked and a failure aborts before
    -- add_implant, so nothing is granted without an entry recording it.
    if not begin_journal(record.parameter, record.before_ids, "marker",
            record.passive_id, record.item_id, record.lock)
    then
        log(string.format(
            "ERROR: the recovery journal could not be written, so %s was not extracted without "
            .. "crash protection; %s.", record.passive_id, restore_on_abort(record, "none")))
        return
    end
    local granted, reason = add_implant(bag, record.item_id)
    if not granted then
        log(string.format("ERROR: implant grant failed for %s (%s); %s.",
            record.passive_id, tostring(reason), restore_on_abort(record, "keep")))
        return
    end
    if not write_journal("granted", "marker", record.passive_id, record.item_id, record.lock) then
        -- The prepared/marker row may still be on disk, and its replay would
        -- restore the passive the module was just granted for. The marker is
        -- removed now instead; if that fails, a stranded row naming no passive
        -- replaces it, and if that also fails the row is deleted. An extract-all
        -- sweep is not started.
        local outcome
        if remove_skill(record.parameter, record.lock) then
            clear_journal()
            outcome = "the marker was removed"
        elseif write_journal("prepared", "stranded", nil, nil, record.lock) then
            outcome = "the marker could not be removed and is journalled for removal on the next "
                .. "map load"
        else
            clear_journal()
            outcome = string.format("the marker could not be removed or journalled; %s stays on "
                .. "the Pal", record.lock)
        end
        log(string.format(
            "ERROR: granted %s but the journal could not be advanced; %s.%s",
            record.item_id, outcome,
            record.mode == "all" and " Extract-all stopped after the first passive." or ""))
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
            log(string.format(
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
        log(string.format(
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
        log(string.format(
            "Extracted %d passive(s) from this Pal for player %s (%s): %s plus %d more.%s",
            extra_extracted + 1, tostring(player_id_number(record.request_player_id)),
            record.mode_source, record.passive_id, extra_extracted, skipped_note))
    else
        log(string.format(
            "Extracted %s into %s for player %s (%s).",
            record.passive_id, record.item_id,
            tostring(player_id_number(record.request_player_id)), record.mode_source))
    end
end

return {
    capture_record = capture_record,
    schedule_finalize = schedule_finalize,
}
