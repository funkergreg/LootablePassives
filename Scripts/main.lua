-- Lootable Passives -- entry point.
--
-- Blueprint paths, hook registration and startup.
local MOD_ROOT = (debug.getinfo(1, "S").source:gsub("^@", ""))
MOD_ROOT = MOD_ROOT:match("^(.*[\\/])") or ""
if type(package) == "table" then
    package.path = MOD_ROOT .. "?.lua;" .. (package.path or "")
end

local util = require("lp.util")
local options = require("lp.options")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local ui = require("lp.ui")
local transaction = require("lp.transaction")
local recovery = require("lp.recovery")
local hooks = require("lp.hooks")
local conveyor = require("lp.conveyor")
local ledger = require("lp.ledger")
local role = require("lp.role")
local joins = require("lp.joins")
local host = require("lp.host")
local notice = require("lp.notice")
local cleanup = require("lp.cleanup")

-- Before any setting is read: Better Mod Manager's saved values replace
-- config.lua's here.
options.register_with_bmm()

local coalescer = util.coalescer
local log = util.log
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local conveyor_on = options.conveyor_on
local debug_on = options.debug_on
local gate_on = options.gate_on
local surgery_on = options.surgery_on
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local JOURNAL_PATH = journal.JOURNAL_PATH
local journal_is_writable = journal.journal_is_writable
local name_list = passives.name_list
local begin_local_exchange = ui.begin_local_exchange
local check_local_exchange = ui.check_local_exchange
local consume_pending_refresh = ui.consume_pending_refresh
local edit_held = ui.edit_held
local enforce_extraction_gate = ui.enforce_extraction_gate
local forget_live_widgets = ui.forget_live_widgets
local note_live_page = ui.note_live_page
local note_live_screen = ui.note_live_screen
local note_operation_result = ui.note_operation_result
local refresh_pending = ui.refresh_pending
local release_extraction_gate = ui.release_extraction_gate
local capture_record = transaction.capture_record
local schedule_finalize = transaction.schedule_finalize
local schedule_recovery = recovery.schedule_recovery
local has_ui = role.has_ui
local is_authority = role.is_authority

-- Server side: runs where the swap is executed, on the host only.
local SERVER_REQUEST =
"/Script/Pal.PalMapObjectOperatingTableModel:RequestRequestChangePassiveSkill_ServerInternal"
-- Requesting side: RequestChangePassiveSkill(targetHandle, skillIndex,
-- PassiveSkill) on the same model (Pal.hpp), on the peer that clicked.
local LOCAL_REQUEST =
"/Script/Pal.PalMapObjectOperatingTableModel:RequestChangePassiveSkill"
local TAB_PAGE_BP =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/OperatingTable/" ..
    "WBP_OperatingTable_TabPage.WBP_OperatingTable_TabPage_C"
local UPDATE_BUTTON_STATE = TAB_PAGE_BP .. ":Update Button State"
-- Zero-argument event on the tab page (WBP_OperatingTable_TabPage.hpp).
local INVENTORY_UPDATED = TAB_PAGE_BP .. ":On Update Local Player Inventory"
local SCREEN_BP =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/OperatingTable/" ..
    "WBP_OperatingTable.WBP_OperatingTable_C"
local PASSIVE_UPDATED = SCREEN_BP .. ":OnPassiveUpdate"
-- OnOperatingPassiveNotifyied(Success) on the screen (WBP_OperatingTable.hpp):
-- the server's answer to a request, delivered to the peer that asked.
local OPERATION_NOTIFIED = SCREEN_BP .. ":OnOperatingPassiveNotifyied"
-- Zero-argument function on the screen that builds the operation list
-- (WBP_OperatingTable.hpp).
local LIST_BUILT = SCREEN_BP .. ":SetupPassiveChangeItem"


-- Hooks
--------------------------------------------------------------------------------

-- One entry per request between its pre- and post-callback, false where nothing
-- was captured. A request made inside another's call is pushed above it and
-- popped first, so each post-callback takes its own pre-callback's record.
local pending_records = {}

-- The pre-callback captures the record; the post-callback resolves it 100 ms
-- later. The pre-callback captures nothing where role.is_authority() is false.
-- Which capture strategy runs is capture_record's decision, not this hook's.
local function on_server_request(_, request_player_id)
    local record = false
    if is_authority() then
        record = capture_record(unwrap(request_player_id)) or false
    end
    pending_records[#pending_records + 1] = record
end

local function after_server_request()
    local record = table.remove(pending_records)
    if record then
        schedule_finalize(record, 1, 100)
    end
end

local schedule_gate_pass = coalescer(enforce_extraction_gate, 0)
local schedule_gate_release = coalescer(release_extraction_gate, 0)

-- One callback. For a Blueprint function UE4SS takes one callback, and runs it
-- after the function body.
--
-- The gate work is deferred a frame from here. surgery_ui_gate is read on every firing:
-- on, the gate pass is scheduled; off, nothing is scheduled unless the gate
-- still holds the button blocked, in which case one release is.
--
-- The context argument is the tab page: Update Button State is a method on
-- WBP_OperatingTable_TabPage_C. Recorded on every firing, including those where
-- a pass is already queued.
local function on_update_button_state(context)
    note_live_page(unwrap(context))
    if gate_on() then
        schedule_gate_pass()
    elseif edit_held() then
        schedule_gate_release()
    end
end

local schedule_refresh = coalescer(consume_pending_refresh, 0)

-- The click, on the peer that made it. The handle argument is not read: the Pal
-- comes from the recorded tab page. Logs nothing for a vanilla passive id
-- (a direct route only under debug), and does nothing where role.has_ui() is
-- false.
local function on_local_request(_, _, skill_index, passive_skill)
    if has_ui() then
        begin_local_exchange(name_to_string(passive_skill), unwrap(skill_index))
    end
end

local function describe_passive_update(passive_ids)
    return string.format("OnPassiveUpdate: [%s]", table.concat(name_list(unwrap(passive_ids)), ","))
end

-- OnPassiveUpdate fires on the screen after a passive change, for vanilla
-- operations as well as this mod's, hence the refresh_pending check. Logs the
-- passive list each firing carries, under debug.
--
-- The context argument is the screen, WBP_OperatingTable_C. A refresh armed
-- before this hook has fired once does the page half and skips the list rebuild.
local function on_passive_update(context, passive_ids)
    note_live_screen(unwrap(context))
    options.debug_logf(describe_passive_update, passive_ids)
    check_local_exchange("OnPassiveUpdate")
    if refresh_pending() then
        schedule_refresh()
    end
end

-- The operation list was built; the context is the screen.
local function on_list_built(context)
    ui.on_list_built(unwrap(context))
end

-- The server's verdict on the vanilla half of a request, on the peer that asked.
local function on_operation_notified(context, success)
    note_live_screen(unwrap(context))
    note_operation_result(unwrap(success))
end

-- The local inventory changed while the tab page exists. On a client, a module
-- arriving from the host is one of these.
local function on_local_inventory_update(context)
    note_live_page(unwrap(context))
    check_local_exchange("inventory update")
end

-- Delivering what a previous session left owed, where role.is_authority() is
-- true.
--
-- BOUNDED RETRY: 12 attempts at 5 s. The role is known before a player inventory
-- can be resolved, and an unbounded retry would allocate per attempt forever.
local FLUSH_ATTEMPT_LIMIT = 12
local FLUSH_INTERVAL_MS = 5000
local flush_attempts = 0
local flush_gave_up = false
-- Delivers what the ledger owes, reports each remote player's share to them,
-- and logs the count when anything was delivered. when ends the log line's
-- "Delivered N owed module(s)". Returns what is still owed.
local function deliver_owed(when)
    local delivered, owed, _, _, deliveries = ledger.flush()
    host.tell_grants("owed", deliveries)
    if delivered > 0 then
        log(string.format("Delivered %d owed module(s) %s; %d still owed.", delivered, when, owed))
    end
    return owed
end

local schedule_flush
local attempt_flush

function attempt_flush()
    if ledger.total_owed() == 0 then
        return
    end
    local authoritative = is_authority()

    if authoritative and deliver_owed("from an earlier session") == 0 then
        return
    end

    if flush_attempts < FLUSH_ATTEMPT_LIMIT then
        flush_attempts = flush_attempts + 1
        schedule_flush()
    elseif not flush_gave_up then
        -- Once per session. The debt stays on disk either way; silence here
        -- would read the same as owing nothing.
        flush_gave_up = true
        log(string.format(
            "%d module(s) are still owed but could not be delivered after %d attempts "
            .. "(this machine is the %s). They remain on disk, and are delivered when a player "
            .. "joins and on the next map load.", ledger.total_owed(), FLUSH_ATTEMPT_LIMIT,
            role.describe()))
    end
end

-- Coalesced, so a second world entry while a chain is running does not start a
-- second chain.
schedule_flush = coalescer(attempt_flush, FLUSH_INTERVAL_MS)

-- Each map load drops the role; role.on_known below runs once it is read again.
RegisterLoadMapPostHook(function()
    role.forget()
    cleanup.cancel()
    host.forget()
    notice.forget()
    forget_live_widgets()
    conveyor.apply()
end)

-- Entering a world, once its role is known: the widget hooks are armed where
-- there is a UI, and recovery and the ledger flush run where the world is held.
role.on_known(function()
    local authoritative = is_authority()
    hooks.arm(has_ui(), authoritative)
    if authoritative then
        -- Late enough for the world's containers to be in memory.
        util.run_later(10000, cleanup.request, "entering the world")
        schedule_recovery("entering the world")
        flush_attempts = 0
        flush_gave_up = false
        schedule_flush()
    end
end)

hooks.register({
    path = SERVER_REQUEST,
    callback = on_server_request,
    post = after_server_request,
    half = "server",
    label = "the Surgery exchange handler",
    note = "Without it no Surgery operation of this mod completes on this machine.",
})
hooks.register({
    path = UPDATE_BUTTON_STATE,
    callback = on_update_button_state,
    half = "ui",
    label = "the Edit-button eligibility gate",
    note = "The transaction enforces every rule the gate does either way.",
})
hooks.register({
    path = PASSIVE_UPDATED,
    callback = on_passive_update,
    half = "ui",
    label = "the passive-update trigger",
    note = "The exchange poll covers it.",
})
hooks.register({
    path = OPERATION_NOTIFIED,
    callback = on_operation_notified,
    half = "ui",
    label = "the Surgery result watcher",
    note = "A refused request is then only noticed by the exchange timeout.",
})
hooks.register({
    path = LIST_BUILT,
    callback = on_list_built,
    half = "ui",
    label = "the Surgery operation-list filter",
    note = "Operations the host does not allow then stay listed, and the Edit button refuses them.",
})
hooks.register({
    path = INVENTORY_UPDATED,
    callback = on_local_inventory_update,
    half = "ui",
    label = "the inventory-update trigger",
    note = "The exchange poll covers it.",
})
hooks.register({
    path = LOCAL_REQUEST,
    callback = on_local_request,
    half = "ui",
    label = "the Surgery request watcher",
    note = "Without it no exchange is tracked on this peer, so its Surgery panel is not repaired.",
})
conveyor.apply()

-- A setting changed while the game runs. Every other setting is read at its
-- next use.
options.on_changed(function(name, value)
    host.tell_setting(name, value)
    if name == "conveyor_extraction" then
        conveyor.apply()
    end
    if name == "surgery_extraction" or name == "conveyor_extraction" then
        host.send_to_all()
    end
    if name == "remove_mod_items" or name == "advanced_features" then
        cleanup.request("the setting changed")
    end
end)

host.install()
joins.on_joined(host.send_to_player)
joins.on_joined(function()
    cleanup.request("a player joined")
end)

-- Debug builds only: edits to config.lua while the game runs are applied.
options.watch_file()

-- A player joining: whatever the ledger owes is delivered, which reaches the
-- joining player if any of it is theirs.
joins.on_joined(function()
    if ledger.total_owed() > 0 then
        deliver_owed("when a player joined")
    end
end)
joins.install()

-- Reported at load rather than found mid-transaction: every exchange refuses
-- when its first journal write fails.
if not journal_is_writable() then
    log(string.format(
        "WARNING: the recovery journal at %s is NOT writable, so extraction will refuse. "
        .. "Check the folder's permissions.", JOURNAL_PATH))
end

-- The startup counts line. The numbers come from lp/passive_items.lua and
-- lp/ids.lua; each entry needs a matching row in the PalSchema JSON to be
-- reachable, so a number that reads low means a half that did not load. The
-- switches are as they stand at load; each is read again at every use.
local extract_operations, insert_routes = 0, 0
for _, mode in pairs(EXTRACTION_MODES) do
    if mode == "implant" then
        insert_routes = insert_routes + 1
    else
        extract_operations = extract_operations + 1
    end
end
log(string.format(
    "Loaded %d extractable passives, %d extraction operations, %d insert routes. "
    .. "Surgery extraction %s. Conveyor extraction %s. Surgery Edit-button gate %s. "
    .. "Debug mode %s.",
    passives.MODULE_COUNT, extract_operations, insert_routes,
    surgery_on() and "on" or "off (surgery_extraction = false)",
    conveyor_on() and "on" or "off (conveyor_extraction = false)",
    gate_on() and "on" or "off (surgery_ui_gate = false)",
    debug_on() and "on" or "off"
))
options.debug_log(options.describe_plan())
