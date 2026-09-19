-- Lootable Passives -- The exchange: capture, resolve, grant, remove.
--
-- Ordered so a crash can never destroy a passive without compensation. The
-- module is granted BEFORE the passive is removed, and the journal records
-- each step so an interrupted exchange is replayed on the next load. If
-- anything goes wrong mid-transaction this would rather duplicate an item
-- than destroy a passive. Preserve that ordering.

local PASSIVE_ITEMS = require("passive_items")
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
local add_implant = inventory.add_implant
local find_inventory = inventory.find_inventory
local player_id_number = inventory.player_id_number
local remove_skill = inventory.remove_skill
local restore_replaced_passive = inventory.restore_replaced_passive
local consume_pending_refresh = ui.consume_pending_refresh
local arm_refresh = ui.arm_refresh
local refresh_surgery_ui = ui.refresh_surgery_ui
local selected_passive = ui.selected_passive
local visible_extraction_widget = ui.visible_extraction_widget

--------------------------------------------------------------------------------
-- Request capture
--------------------------------------------------------------------------------

local function capture_targeted_record(request_player_id)
    local widget, lock = visible_extraction_widget()
    if not is_valid(widget) then
        return nil
    end
    local passive_id = selected_passive(widget)
    -- An extraction needs a passive in the selected slot. An IMPLANT does not:
    -- targeting an empty slot is the normal case, so an absent passive here is
    -- expected rather than a reason to bail out to the whole-world scan.
    if (passive_id == nil or passive_id == "None")
        and is_extract_mode(EXTRACTION_MODES[lock])
    then
        return nil
    end
    local parameter = unwrap(widget.CachedCharacter)
    local ids = get_skill_ids(parameter)
    if ids == nil then
        return nil
    end
    -- A ONE-ELEMENT snapshot list, deliberately the same shape the dedicated-
    -- server path produces. The two used to be different record shapes resolved
    -- by two different branches, and the branches had silently drifted apart;
    -- see the comment on resolve_record. What is genuinely specific to this path
    -- is the widget's idea of which slot the player selected, so that travels as
    -- one explicit field instead of as a structural difference.
    return {
        snapshots = {
            {
                parameter = parameter,
                before_ids = ids,
                expect_passive_id = passive_id,
            },
        },
        request_player_id = request_player_id,
        mode_source = "targeted UI",
    }
end

-- A dedicated server has no Surgery widget. Snapshot once before the normal
-- transaction, then accept exactly one Pal whose passive was replaced by a
-- marker. No repeated polling scan, no UI repainting.
local function snapshot_server_parameters(request_player_id)
    local succeeded, parameters = pcall(function()
        return FindAllOf("PalIndividualCharacterParameter")
    end)
    if not succeeded or parameters == nil then
        return nil
    end
    local snapshots = {}
    for _, parameter in ipairs(parameters) do
        if is_valid(parameter) then
            local ids = get_skill_ids(parameter)
            if ids ~= nil then
                snapshots[#snapshots + 1] = {
                    parameter = parameter,
                    before_ids = ids,
                }
            end
        end
    end
    return {
        snapshots = snapshots,
        request_player_id = request_player_id,
        mode_source = "dedicated-server snapshot",
    }
end

-- ONE resolver loop over a list of snapshots, whatever produced them.
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
                    -- Worth seeing: it means the widget read is unreliable.
                    -- Not worth refusing over -- see the note above.
                    log(string.format(
                        "NOTE: the selected slot read as %s but the engine removed %s; "
                        .. "trusting the passive list.",
                        tostring(snapshot.expect_passive_id), tostring(removed)))
                end
                candidate = {
                    parameter = snapshot.parameter,
                    passive_id = removed,
                    item_id = PASSIVE_ITEMS[removed],
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
                -- Two Pals cannot both be the target of one transaction, so an
                -- ambiguous world is a refusal rather than a guess.
                if resolved ~= nil then
                    return nil
                end
                resolved = candidate
            end
        end
    end
    return resolved
end

-- Did the transaction strand one of our markers on a Pal without resolving?
--
-- Called only when resolve_record has given up. It answers a deliberately
-- narrower question than resolve_record does -- not "what was swapped" but
-- "is a marker of ours sitting on a Pal that did not have one before" -- which
-- is the thing that has to be cleaned up, and the thing a journal entry can
-- authorise recovery to do. Returns the snapshot and the marker, or nil.
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
                        -- More than one candidate means we cannot tell which Pal
                        -- the transaction touched; refuse rather than guess.
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

local function finish(message, mode)
    log(message)

    -- An implant is, as far as the panel is concerned, an ordinary vanilla
    -- insert: vanilla selected the item, vanilla charged it, and vanilla knows
    -- how many are left. So DO NOT reset the chip for one.
    --
    -- Forcing it empty is exactly what produced the "+" slot with a stray
    -- quantity beside it in screenshot 113. "Set Passive Empty Item" restored
    -- the "+" graphic, and vanilla then refreshed the remaining-module count
    -- into BP_PalTextBlock_Num for the item we had just hidden -- a count with
    -- nothing left to belong to. That is why clearing it did not help: the
    -- 00:17 log shows clearItem=true, the call landed, and vanilla wrote the
    -- number back afterwards. Leaving the selection alone keeps the module
    -- selected with its true count, which is what vanilla does for its own
    -- disposable implants, and lets the player implant again straight away.
    --
    -- An extraction is the opposite case: the marker on the chip is ours and
    -- vanilla has no reason to clear it, so the reset is still required there.
    local reset_panel = mode ~= "implant"
    arm_refresh(reset_panel)

    -- A FALLBACK, not the mechanism. The refresh normally happens on
    -- OnPassiveUpdate, which fires as soon as the engine has applied the
    -- change. This only covers the hook failing to register or the event not
    -- arriving, and it is short so that case is not painful either.
    ExecuteWithDelay(500, function()
        ExecuteInGameThread(consume_pending_refresh)
    end)

    if reset_panel then
        -- Extraction only, and deliberately unconditional rather than gated on
        -- pending_refresh. A marker label stranded on the chip was the most
        -- persistent bug this mod had, and emptying an already-empty chip costs
        -- nothing, so the belt-and-braces pass is worth keeping.
        --
        -- Implants are excluded because for them this call is NOT idempotent:
        -- it would hide vanilla's live selection and strand the quantity all
        -- over again.
        ExecuteWithDelay(1600, function()
            ExecuteInGameThread(function()
                refresh_surgery_ui(true, false)
            end)
        end)
    end
end

-- Extracts one additional passive during an extract-all. The marker is still on
-- the Pal at this point, so a crash here is recoverable.
-- copies is how many times this passive appears on the Pal. A single
-- RemovePassiveSkill clears them all at once, so the player is paid for every
-- copy BEFORE anything is removed.
local function extract_additional(parameter, passive_id, item_id, inventory, lock, copies)
    copies = copies or 1
    -- Checked, for the reason given at the marker-phase write: no journal means
    -- no crash protection, and skipping one passive beats extracting it
    -- unprotected. The marker is still on the Pal, so the sweep simply reports
    -- this one as skipped and the passive stays put.
    if not write_journal("prepared", "loop", passive_id, item_id, lock) then
        log(string.format(
            "SKIPPED %s: the recovery journal could not be written.", passive_id))
        return 0
    end
    local granted = 0
    for _ = 1, copies do
        local ok, reason = add_implant(inventory, item_id)
        if not ok then
            log(string.format("SKIPPED %s: implant grant failed (%s).", passive_id, tostring(reason)))
            break
        end
        granted = granted + 1
    end
    if granted < copies then
        -- Not every copy could be paid for -- a full inventory, most likely.
        -- Keep the passive AND keep whatever was granted: this mod would rather
        -- duplicate an item than destroy a passive it cannot fully compensate.
        clear_journal()
        return 0
    end
    if not write_journal("granted", "loop", passive_id, item_id, lock) then
        -- The implant is already granted and the passive is still attached. With
        -- no journal to authorise a replay, the safe end state is exactly this
        -- one: keep both. The player is up an item, which is the direction this
        -- mod always errs in.
        log(string.format(
            "WARNING: granted %s but the journal could not be updated; keeping passive %s.",
            item_id, passive_id))
        return 0
    end
    if not remove_skill(parameter, passive_id) then
        -- Journal deliberately KEPT: granted/loop is the case
        -- recover_interrupted_extraction finishes by removing the passive whose
        -- implant already exists. Clearing it here discarded the only record
        -- that the exchange was half-done.
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

local function extract_all_remaining(record, inventory)
    local extracted, skipped = 0, {}
    local ids = get_skill_ids(record.parameter) or {}

    -- Count copies and visit each id exactly ONCE.
    --
    -- The old loop walked the raw list, so a Pal carrying a duplicate was
    -- visited twice: the first pass granted an implant and removed every copy,
    -- and the second granted a further implant and then reported a removal
    -- failure for a passive that was already gone. Both of those appear in the
    -- 23:37 log against a Pal that had Infinite Stamina twice.
    local copies, order = {}, {}
    for _, passive_id in ipairs(ids) do
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
                PASSIVE_ITEMS[passive_id], inventory, record.lock, copies[passive_id])
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

-- Retry budget: 12 attempts at 250ms is a 3 second window, the same as the old
-- 30 at 100ms, but with well under half the Lua closures and registry refs. The
-- crash was traced to registry churn, and a failed resolve was the heaviest
-- allocator in the mod -- the "insert then switch to extraction" CTD landed
-- about two seconds after this loop gave up.
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
            -- Resolution has given up. The old code cleared the journal here and
            -- reported "nothing was changed", which was a claim it had no way to
            -- make: vanilla may well have swapped the passive for the marker
            -- already. Clearing was also self-defeating, because the journal is
            -- the ONLY thing that authorises recovery to touch a Pal.
            --
            -- So ask the narrower question instead. If a marker really is
            -- stranded, record it and let recover_interrupted_extraction replay
            -- it on the next map load. That is journal-authorised recovery and is
            -- categorically different from the deleted sweep_stray_markers, which
            -- ran on every load with nothing authorising it, over a set that had
            -- quietly grown from 2 markers to 56 entries.
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

    -- Disposable-implant insertion. Handled FIRST, because the two checks below
    -- are extraction rules that would both misfire here: an alias landing in an
    -- empty slot looks "stray" when it is in fact the normal case, and the
    -- is_extractable test does not apply to an insert at all.
    --
    -- The vanilla transaction has already installed the alias and charged the
    -- gold, and it either consumed the module through RequireItemId or did not
    -- (Key Items are not consumed, ordinary inventory items are expected to be;
    -- confirm by watching the count). All that remains is to put the real
    -- passive where the alias is -- the same AddPassiveSkill(new, override) swap
    -- the extraction path already relies on.
    if record.mode == "implant" then
        local target = IMPLANT_TARGET[record.lock]
        if target == nil then
            clear_journal()
            remove_skill(record.parameter, record.lock)
            finish(string.format("ERROR: no target passive configured for alias %s; alias removed.",
                tostring(record.lock)), record.mode)
            return
        end

        -- JOURNAL THE INSERT. This branch used to clear the journal and write
        -- nothing, so the implant path had no crash protection at all while the
        -- extraction path had a whole design for it -- an asymmetry that was
        -- nowhere documented.
        --
        -- The exposure is real: vanilla has already installed the alias AND
        -- consumed the module by the time we get here, so a crash before the
        -- swap below leaves an inert cosmetic alias permanently attached to the
        -- Pal with the module already spent. Nothing could then put it right,
        -- because recovery refuses to act without a journal.
        --
        -- "prepared" is the accurate state: the module is gone but the real
        -- passive is not on the Pal yet. Recovery finishes the swap.

        -- Give the module back. The vanilla transaction has already taken it
        -- through RequireItemId, so every abort below owes the player one.
        local function refund_module()
            local inventory = find_inventory(record.request_player_id)
            if not is_valid(inventory) then
                return false
            end
            return (add_implant(inventory, PASSIVE_ITEMS[target]))
        end

        if not write_journal("prepared", "implant", target, PASSIVE_ITEMS[target],
                record.lock)
        then
            local removed = remove_skill(record.parameter, record.lock)
            finish(string.format(
                "ERROR: the recovery journal could not be written, so %s was not implanted. "
                .. "Alias removal=%s, module refunded=%s.",
                target, tostring(removed), tostring(refund_module())), record.mode)
            return
        end

        -- The UI gate blocks duplicates, but UI state is never the safety
        -- mechanism here. If the Pal already carries the target, unwind.
        if count_id(record.before_ids, target) > 0 then
            local removed = remove_skill(record.parameter, record.lock)
            local refunded = refund_module()
            -- Unwound: no alias, module back. Nothing left to recover.
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
            -- Do not leave a cosmetic alias attached to the Pal. The swap now
            -- removes the alias before adding, so a failure here means the Pal
            -- has neither -- refund rather than charge for nothing.
            local removed = remove_skill(record.parameter, record.lock)
            local refunded = refund_module()
            -- Only clear once the alias is actually gone. If removal failed the
            -- Pal is still carrying it, and the journal is what lets recovery
            -- finish the swap on the next map load.
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

    -- Empty slot: the marker was appended rather than swapped in, so there is
    -- nothing to extract. Take the marker straight back off and grant nothing.
    if record.stray then
        local cleared = remove_skill(record.parameter, record.lock)
        if cleared then
            clear_journal()
            finish("Nothing extracted: an empty slot was selected, so the marker was removed again.")
        else
            -- The old message promised this "will be cleared on the next map
            -- load", which stopped being true when sweep_stray_markers was
            -- deleted -- nothing swept, and the journal was cleared one line
            -- above, so nothing authorised a sweep either. Journalling it as
            -- stranded makes the promise true again, through the authorised
            -- path: recovery removes a marker it has a record for.
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

    local inventory = find_inventory(record.request_player_id)
    if not is_valid(inventory) then
        restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        clear_journal()
        finish(string.format(
            "ERROR: inventory unavailable; restored %s instead of removing it.", record.passive_id))
        return
    end

    -- Phase one: the passive the vanilla swap replaced with our marker.
    --
    -- The return value is CHECKED, and a failure aborts before anything is
    -- granted. Grant-first ordering is the mod's entire crash-safety story and
    -- the journal is what makes it recoverable, so proceeding without one is
    -- running the dangerous half of the design with the safety half missing.
    -- Every call site used to discard this result, which meant an unwritable
    -- mod folder silently downgraded the exchange rather than refusing it.
    if not write_journal("prepared", "marker", record.passive_id, record.item_id, record.lock) then
        restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        finish(string.format(
            "ERROR: the recovery journal could not be written, so %s was restored rather than "
            .. "extracted without crash protection.", record.passive_id))
        return
    end
    local granted, reason = add_implant(inventory, record.item_id)
    if not granted then
        local restored = restore_replaced_passive(record.parameter, record.passive_id, record.lock)
        clear_journal()
        finish(string.format(
            "ERROR: implant grant failed for %s (%s); passive restoration=%s.",
            record.passive_id, tostring(reason), tostring(restored)))
        return
    end
    if not write_journal("granted", "marker", record.passive_id, record.item_id, record.lock) then
        -- The implant is granted and the marker is still on the Pal, which is a
        -- recoverable state ONLY while a journal says so. Without one, stop
        -- here: the player keeps the item and the Pal keeps the marker, and the
        -- next extraction of that slot puts it right. Removing the marker now
        -- would complete an exchange nothing could audit.
        finish(string.format(
            "ERROR: granted %s but the journal could not be advanced; stopped before removing "
            .. "the marker. The implant was kept.", record.item_id))
        return
    end

    -- Phase two: for extract-all, sweep the rest while the marker still pins
    -- the Pal for recovery purposes.
    local extra_extracted, extra_skipped = 0, {}
    if record.mode == "all" then
        extra_extracted, extra_skipped = extract_all_remaining(record, inventory)
    end

    -- Phase three: drop the marker. This is what frees the original slot.
    if not remove_skill(record.parameter, record.lock) then
        -- The journal is deliberately LEFT IN PLACE. It is stamped
        -- granted/marker, which is precisely the case
        -- recover_interrupted_extraction is written to finish: the implant
        -- exists, so dropping the marker completes the exchange. Clearing here
        -- threw away the only authorisation recovery has, so the sentence about
        -- preventing data loss was true of the item and false of the passive.
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
    capture_targeted_record = capture_targeted_record,
    finalize_extraction = finalize_extraction,
    snapshot_server_parameters = snapshot_server_parameters,
}
