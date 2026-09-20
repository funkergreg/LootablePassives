-- Lootable Passives -- entry point.
--
-- Configuration, Blueprint paths, hook registration and startup.
local MOD_ROOT = (debug.getinfo(1, "S").source:gsub("^@", ""))
MOD_ROOT = MOD_ROOT:match("^(.*[\\/])") or ""
if type(package) == "table" then
    package.path = MOD_ROOT .. "?.lua;" .. (package.path or "")
end

local SETTINGS = require("settings")
local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local ui = require("lp.ui")
local transaction = require("lp.transaction")
local recovery = require("lp.recovery")
local hooks = require("lp.hooks")
local conveyor = require("lp.conveyor")
local ledger = require("lp.ledger")

-- Localised so the hook bodies below read as they did before the split.
local is_valid = util.is_valid
local log = util.log
local unwrap = util.unwrap
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local JOURNAL_PATH = journal.JOURNAL_PATH
local journal_is_writable = journal.journal_is_writable
local consume_pending_refresh = ui.consume_pending_refresh
local enforce_extraction_gate = ui.enforce_extraction_gate
local refresh_pending = ui.refresh_pending
local visible_tab_page = ui.visible_tab_page
local capture_targeted_record = transaction.capture_targeted_record
local finalize_extraction = transaction.finalize_extraction
local snapshot_server_parameters = transaction.snapshot_server_parameters
local schedule_recovery = recovery.schedule_recovery
local mapped_passive_count = 0

for _ in pairs(PASSIVE_ITEMS) do
    mapped_passive_count = mapped_passive_count + 1
end

local SERVER_REQUEST =
"/Script/Pal.PalMapObjectOperatingTableModel:RequestRequestChangePassiveSkill_ServerInternal"
local TAB_PAGE_BP =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/OperatingTable/" ..
    "WBP_OperatingTable_TabPage.WBP_OperatingTable_TabPage_C"
local UPDATE_BUTTON_STATE = TAB_PAGE_BP .. ":Update Button State"
local SCREEN_BP =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/OperatingTable/" ..
    "WBP_OperatingTable.WBP_OperatingTable_C"
-- Fires once the engine has finished applying a passive change, which is the
-- moment the panel becomes safe to repaint. See finish().
local PASSIVE_UPDATED = SCREEN_BP .. ":OnPassiveUpdate"


-- Hooks
--------------------------------------------------------------------------------

local pending_record = nil

RegisterHook(
    SERVER_REQUEST,
    function(_, request_player_id)
        local request_id = unwrap(request_player_id)
        local succeeded, record = pcall(capture_targeted_record, request_id)
        if not succeeded or record == nil then
            local page_ok, page = pcall(visible_tab_page)
            if not page_ok or not is_valid(page) then
                local fallback_ok, fallback = pcall(snapshot_server_parameters, request_id)
                record = fallback_ok and fallback or nil
            else
                record = nil
            end
        end
        -- ONE SLOT, not a queue.
        pending_record = record
    end,
    function()
        local record = pending_record
        pending_record = nil
        if record ~= nil then
            ExecuteWithDelay(100, function()
                ExecuteInGameThread(function()
                    finalize_extraction(record, 1)
                end)
            end)
        end
    end
)

-- Both widget hooks, registered through lp/hooks.lua.
--
-- The retry/bound/warn-once/re-arm machinery lives there now; what stays here
-- is the part that is specific to these two hooks, which is the COALESCING.
-- That is load-bearing and is the fix for a hard crash:
--
-- Update Button State fires constantly -- hover, selection, money change,
-- repaint -- and an earlier version allocated fresh Lua closures plus registry
-- refs on every single invocation. That produced
--   Error: [Lua::Registry::get_function_ref] Ref was not function
-- followed by EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff with a call
-- stack entirely inside UE4SS: the Lua registry churned faster than it could be
-- kept consistent. With a coalescing flag, at most one pass is ever queued and
-- the hook allocates nothing while one is pending, however often it fires.
--
-- Every function below is built ONCE, at load, and passed by reference. The
-- flag alone is not enough: ExecuteWithDelay(0, ...) completes within the tick,
-- so the flag clears and a per-call closure would be allocated again.

-- True while a gate pass is already queued.
local gate_scheduled = false

local function run_gate_pass_deferred()
    gate_scheduled = false
    ExecuteInGameThread(enforce_extraction_gate)
end

-- ONE callback, not two.
--
-- UE4SS does not run a separate post-callback for Blueprint function hooks. The
-- log gives it away: the native hook on
-- RequestRequestChangePassiveSkill_ServerInternal registers as "(3, 4)" -- two
-- distinct ids -- while a script hook registers as "(7, 7)". When the gate was
-- moved into a post-callback it simply stopped executing, which is why three
-- separate attempts to disable the Edit button appeared to fail: none ran.
--
-- So everything hangs off the pre-callback, deferred one frame so it lands
-- after the game's own logic has finished writing its result.
local function on_update_button_state()
    if gate_scheduled then
        return
    end
    gate_scheduled = true
    ExecuteWithDelay(0, run_gate_pass_deferred)
end

-- True while a refresh pass is already queued.
local refresh_scheduled = false

local function run_refresh_deferred()
    refresh_scheduled = false
    ExecuteInGameThread(consume_pending_refresh)
end

-- Event-driven panel reset.
--
-- OnPassiveUpdate is the screen's own notification that the Pal's passive list
-- has changed, so it fires exactly when the panel has new data to draw -- after
-- our swap, not on a delay chosen by guesswork. It also fires for ordinary
-- vanilla inserts, hence the pending check: this does nothing at all unless an
-- extraction of ours has just completed.
local function on_passive_update()
    if not refresh_pending() or refresh_scheduled then
        return
    end
    refresh_scheduled = true
    ExecuteWithDelay(0, run_refresh_deferred)
end

-- Delivering what a previous session left owed.
--
-- BOUNDED RETRY, not a single shot. A map load fires well before the world is
-- usable: measured, a player inventory took roughly 15-25 seconds to resolve
-- after the map hook. One attempt at 5 seconds finds nothing, does nothing,
-- and the debt then waits for the NEXT map load -- which on a long session
-- never comes. Same bounded-retry shape as the widget hooks, and for the same
-- reason: unbounded retries allocate a closure per attempt forever, which is
-- the registry churn behind the 0xffffffffffffffff crash.
local FLUSH_ATTEMPT_LIMIT = 12
local FLUSH_INTERVAL_MS = 5000
local flush_attempts = 0
local flush_gave_up = false
-- COALESCED, like the button gate. RegisterLoadMapPostHook fires on the splash,
-- login and title maps before the world, and each firing used to start its own
-- retry chain without cancelling the last -- three ran at once, visible in the
-- log as attempts 40ms apart instead of 5s. Harmless while Lua is
-- single-threaded and the first success clears the ledger, but it is the shape
-- of a double delivery and there is no reason to keep it.
local flush_scheduled = false
local retry_flush

local function schedule_flush()
    if flush_scheduled then
        return
    end
    flush_scheduled = true
    ExecuteWithDelay(FLUSH_INTERVAL_MS, retry_flush)
end

local function attempt_flush()
    if ledger.total_owed() == 0 then
        return
    end
    local actor = nil
    pcall(function() actor = FindFirstOf("PalPlayerCharacter") end)
    local authoritative = false
    if is_valid(actor) then
        pcall(function() authoritative = actor:HasAuthority() == true end)
    end

    if authoritative then
        local delivered, owed = ledger.flush(nil)
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
        -- Said once. The debt is NOT lost -- it stays on disk and is retried on
        -- the next map load -- but silence here would look identical to having
        -- nothing owed at all.
        flush_gave_up = true
        log(string.format(
            "%d module(s) are still owed but could not be delivered after %d attempts "
            .. "(authoritative player found: %s). They remain on disk and will be retried on the "
            .. "next map load.", ledger.total_owed(), FLUSH_ATTEMPT_LIMIT, tostring(authoritative)))
    end
end

-- Built once, at load, and handed to ExecuteWithDelay by reference.
retry_flush = function()
    flush_scheduled = false
    ExecuteInGameThread(attempt_flush)
end

RegisterLoadMapPostHook(function()
    schedule_recovery("map load")
    -- Every hook gets a fresh retry budget: a widget Blueprint does not exist
    -- on the splash, login or title maps, and exhausting the budget there must
    -- not leave the hook disabled for the rest of the session.
    hooks.rearm_on_map_load()
    -- Retry point. A debt can outlive the session that created it, and a map
    -- load is the moment a player exists again with a bag that may have room.
    -- flush is a no-op when nothing is owed.
    flush_attempts = 0
    flush_gave_up = false
    schedule_flush()
end)

hooks.register(UPDATE_BUTTON_STATE, on_update_button_state,
    "the Edit-button eligibility gate",
    "The transaction enforces every rule the gate does either way.")
hooks.register(PASSIVE_UPDATED, on_passive_update,
    "the event-driven panel reset on OnPassiveUpdate",
    "Timed panel resets cover it until then.")
local conveyor_on = SETTINGS.conveyor_extraction ~= false
if conveyor_on then
    conveyor.install()
    ledger.load()
end
schedule_recovery("mod startup")

-- Said once, loudly, at load rather than discovered mid-transaction. If this
-- line reads false, extraction will refuse rather than run unprotected.
if not journal_is_writable() then
    log(string.format(
        "WARNING: the recovery journal at %s is NOT writable, so extraction will refuse. "
        .. "Check the folder's permissions.", JOURNAL_PATH))
end

-- Counts, not names. The three numbers are the cheap check that both halves of
-- the mod loaded and agree: the modules come from passive_items.lua, the routes
-- from settings.lua, and each one needs a matching row in the PalSchema JSON to
-- be reachable in game. A number that reads low here means a half that did not
-- load; the full 56-id enumeration this replaced said no more than that.
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
    .. "Conveyor extraction %s.",
    mapped_passive_count, extract_operations, insert_routes,
    conveyor_on and "on" or "off (conveyor_extraction = false in settings.lua)"
))


