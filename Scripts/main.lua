-- Lootable Passives -- entry point.
--
-- Blueprint paths, hook registration and startup.
local MOD_ROOT = (debug.getinfo(1, "S").source:gsub("^@", ""))
MOD_ROOT = MOD_ROOT:match("^(.*[\\/])") or ""
if type(package) == "table" then
    package.path = MOD_ROOT .. "?.lua;" .. (package.path or "")
end

local SETTINGS = require("settings")
local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local passives = require("lp.passives")
local ui = require("lp.ui")
local transaction = require("lp.transaction")
local recovery = require("lp.recovery")
local hooks = require("lp.hooks")
local conveyor = require("lp.conveyor")
local ledger = require("lp.ledger")

local coalescer = util.coalescer
local has_authority = util.has_authority
local log = util.log
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local JOURNAL_PATH = journal.JOURNAL_PATH
local journal_is_writable = journal.journal_is_writable
local name_list = passives.name_list
local begin_local_exchange = ui.begin_local_exchange
local check_local_exchange = ui.check_local_exchange
local consume_pending_refresh = ui.consume_pending_refresh
local enforce_extraction_gate = ui.enforce_extraction_gate
local forget_live_widgets = ui.forget_live_widgets
local note_live_page = ui.note_live_page
local note_live_screen = ui.note_live_screen
local note_operation_result = ui.note_operation_result
local refresh_pending = ui.refresh_pending
local capture_record = transaction.capture_record
local schedule_finalize = transaction.schedule_finalize
local schedule_recovery = recovery.schedule_recovery

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


-- Hooks
--------------------------------------------------------------------------------

local pending_record = nil

-- The pre-callback captures the record; the post-callback resolves it 100 ms
-- later.
--
-- One slot, not a queue. Which capture strategy runs is capture_record's
-- decision, not this hook's.
RegisterHook(
    SERVER_REQUEST,
    function(_, request_player_id)
        pending_record = capture_record(unwrap(request_player_id))
    end,
    function()
        local record = pending_record
        pending_record = nil
        if record ~= nil then
            schedule_finalize(record, 1, 100)
        end
    end
)

local gate_on = SETTINGS.surgery_ui_gate ~= false
local schedule_gate_pass = coalescer(enforce_extraction_gate, 0)

-- One callback, and it is the PRE-callback.
--
-- UE4SS does not run a post-callback for a Blueprint function hook, so the gate
-- work is deferred a frame from here, and not scheduled at all with the gate off.
--
-- The context argument is the tab page: Update Button State is a method on
-- WBP_OperatingTable_TabPage_C. Recorded on every firing, including those where
-- a pass is already queued.
local function on_update_button_state(context)
    note_live_page(unwrap(context))
    if gate_on then
        schedule_gate_pass()
    end
end

local schedule_refresh = coalescer(consume_pending_refresh, 0)

-- The click, on the peer that made it. The handle argument is not read: the Pal
-- comes from the recorded tab page. Logs nothing for a vanilla passive id.
local function on_local_request(_, _handle, skill_index, passive_skill)
    begin_local_exchange(name_to_string(passive_skill), unwrap(skill_index))
end

-- OnPassiveUpdate fires on the screen after a passive change, for vanilla
-- operations as well as this mod's, hence the refresh_pending check. Logs the
-- passive list each firing carries.
--
-- The context argument is the screen, WBP_OperatingTable_C. A refresh armed
-- before this hook has fired once does the page half and skips the list rebuild.
local function on_passive_update(context, passive_ids)
    note_live_screen(unwrap(context))
    log(string.format("OnPassiveUpdate: [%s]", table.concat(name_list(unwrap(passive_ids)), ",")))
    check_local_exchange("OnPassiveUpdate")
    if refresh_pending() then
        schedule_refresh()
    end
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

-- Delivering what a previous session left owed.
--
-- BOUNDED RETRY: 12 attempts at 5 s. A map load fires before a player inventory
-- can be resolved, and an unbounded retry would allocate per attempt forever.
local FLUSH_ATTEMPT_LIMIT = 12
local FLUSH_INTERVAL_MS = 5000
local flush_attempts = 0
local flush_gave_up = false
-- Coalesced through the same factory as the widget hooks:
-- RegisterLoadMapPostHook fires several times before a world exists, and each
-- firing would otherwise start its own retry chain.
local schedule_flush
local attempt_flush

function attempt_flush()
    if ledger.total_owed() == 0 then
        return
    end
    -- The same fail-closed probe the conveyor gates on; see util.has_authority.
    local authoritative = has_authority(util.find_first("PalPlayerCharacter"))

    if authoritative then
        local delivered, owed = ledger.flush()
        if delivered > 0 then
            log(string.format("Delivered %d module(s) owed from an earlier session; %d still owed.",
                delivered, owed))
        end
        if owed == 0 then
            return
        end
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
            .. "(authoritative player found: %s). They remain on disk and will be retried on the "
            .. "next map load.", ledger.total_owed(), FLUSH_ATTEMPT_LIMIT, tostring(authoritative)))
    end
end

schedule_flush = coalescer(attempt_flush, FLUSH_INTERVAL_MS)

RegisterLoadMapPostHook(function()
    schedule_recovery("map load")
    forget_live_widgets()
    -- Fresh retry budget per map: a widget Blueprint does not exist on the
    -- splash, login or title maps, so a budget exhausted there must not leave
    -- the hook unregistered for the rest of the session.
    hooks.rearm_on_map_load()
    flush_attempts = 0
    flush_gave_up = false
    schedule_flush()
end)

-- Widget hooks first, native hooks after: hooks.announce_if_complete reports as
-- soon as every registration made so far has taken, and a native hook takes at
-- load while a widget hook waits for a world.
hooks.register(UPDATE_BUTTON_STATE, on_update_button_state,
    "the Edit-button eligibility gate",
    "The transaction enforces every rule the gate does either way.")
hooks.register(PASSIVE_UPDATED, on_passive_update,
    "the passive-update trigger",
    "The exchange poll covers it.")
hooks.register(OPERATION_NOTIFIED, on_operation_notified,
    "the Surgery result watcher",
    "A refused request is then only noticed by the exchange timeout.")
hooks.register(INVENTORY_UPDATED, on_local_inventory_update,
    "the inventory-update trigger",
    "The exchange poll covers it.")
hooks.register(LOCAL_REQUEST, on_local_request,
    "the Surgery request watcher",
    "Without it no exchange is tracked on this peer, so its Surgery panel is not repaired.")
local conveyor_on = SETTINGS.conveyor_extraction ~= false
if conveyor_on then
    conveyor.install()
end
schedule_recovery("mod startup")

-- Reported at load rather than found mid-transaction: every exchange refuses
-- when its first journal write fails.
if not journal_is_writable() then
    log(string.format(
        "WARNING: the recovery journal at %s is NOT writable, so extraction will refuse. "
        .. "Check the folder's permissions.", JOURNAL_PATH))
end

-- The startup counts line. The numbers come from passive_items.lua and
-- lp/ids.lua; each entry needs a matching row in the PalSchema JSON to be
-- reachable, so a number that reads low means a half that did not load.
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
    .. "Conveyor extraction %s. Surgery Edit-button gate %s.",
    passives.MODULE_COUNT, extract_operations, insert_routes,
    conveyor_on and "on" or "off (conveyor_extraction = false in settings.lua)",
    gate_on and "on" or "off (surgery_ui_gate = false in settings.lua)"
))
