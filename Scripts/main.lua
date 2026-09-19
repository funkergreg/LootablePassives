-- Lootable Passives -- entry point.
--
-- Configuration, Blueprint paths, hook registration and startup.
local MOD_ROOT = (debug.getinfo(1, "S").source:gsub("^@", ""))
MOD_ROOT = MOD_ROOT:match("^(.*[\\/])") or ""
if type(package) == "table" then
    package.path = MOD_ROOT .. "?.lua;" .. (package.path or "")
end

local PASSIVE_ITEMS = require("passive_items")
local util = require("lp.util")
local ids = require("lp.ids")
local journal = require("lp.journal")
local ui = require("lp.ui")
local transaction = require("lp.transaction")
local recovery = require("lp.recovery")
local hooks = require("lp.hooks")
local conveyor = require("lp.conveyor")
-- TEMPORARY. Delete with Scripts/lp/bench.lua; see that file's header.
local bench = require("lp.bench")

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
    function(context, request_player_id)
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

local button_hook_registered = false
-- True while a gate pass is already queued; see the comment in the hook below.
local gate_scheduled = false

-- The deferred gate pass is built ONCE, at load, and handed to ExecuteWithDelay
-- by reference. It captures no local, so there is nothing a per-call closure
-- would carry -- and Update Button State fires often enough that allocating one
-- per invocation is exactly the registry churn the hook's own comment below
-- blames for the 0xffffffffffffffff access violation. The coalescing flag alone
-- does not prevent it: ExecuteWithDelay(0, ...) completes within the tick, so
-- the flag clears and the next call would allocate again.
local function run_gate_pass_deferred()
    gate_scheduled = false
    ExecuteInGameThread(enforce_extraction_gate)
end

local BUTTON_HOOK_ATTEMPTS = 12
local button_hook_attempts = 0
local button_hook_warned = false

local function register_button_guard()
    button_hook_attempts = button_hook_attempts + 1
    if button_hook_registered then
        return
    end
    -- ONE callback, not two.
    --
    -- UE4SS does not run a separate post-callback for Blueprint function hooks.
    -- The log gives it away: the native hook on
    -- RequestRequestChangePassiveSkill_ServerInternal registers as "(3, 4)" --
    -- two distinct ids -- while this script hook registers as "(7, 7)". When the
    -- gate was moved into a post-callback it simply stopped executing, which is
    -- why three separate attempts to disable the Edit button appeared to fail:
    -- none of them ever ran.
    --
    -- So everything hangs off the pre-callback. The gate is deferred by one
    -- frame so it lands after the game's own logic has finished writing its
    -- result.
    --
    -- The deferral is COALESCED, and that is the fix for the hard crash.
    --
    -- Update Button State fires constantly -- hover, selection, money change,
    -- repaint -- and the previous version allocated two fresh Lua closures plus
    -- registry refs on every single invocation. That produced
    --   Error: [Lua::Registry::get_function_ref] Ref was not function
    -- followed by EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff with a
    -- call stack entirely inside UE4SS: the Lua registry was being churned
    -- faster than it could be kept consistent.
    --
    -- With this flag at most one gate pass is ever queued, so the hook allocates
    -- nothing while a pass is already pending no matter how often it fires.
    local succeeded = pcall(function()
        RegisterHook(UPDATE_BUTTON_STATE, function()
            if gate_scheduled then
                return
            end
            gate_scheduled = true
            ExecuteWithDelay(0, run_gate_pass_deferred)
        end)
    end)
    if succeeded then
        button_hook_registered = true
        log("Installed extraction eligibility guard.")
    elseif button_hook_attempts < BUTTON_HOOK_ATTEMPTS then
        ExecuteWithDelay(1000, register_button_guard)
    elseif not button_hook_warned then
        -- BOUNDED, like register_passive_update_hook. Warned once per SESSION,
        -- not once per map: the target Blueprint does not exist on the splash,
        -- login or title maps, so every startup exhausts the budget three or
        -- four times over and said so each time.
        button_hook_warned = true
        log(string.format(
            "Edit-button gate not installed after %d attempts. Expected before a world is "
            .. "loaded -- its widget Blueprint does not exist at the menu -- and it retries on "
            .. "each map load. The transaction enforces every rule the gate does either way.",
            BUTTON_HOOK_ATTEMPTS))
    end
end

-- Event-driven panel reset.
--
-- OnPassiveUpdate is the screen's own notification that the Pal's passive list
-- has changed, so it fires exactly when the panel has new data to draw -- after
-- our swap, not on a delay chosen by guesswork. It also fires for ordinary
-- vanilla inserts, hence the pending flag: this does nothing at all unless an
-- extraction of ours has just completed.
--
-- The work is deferred one frame and marshalled onto the game thread, the same
-- idiom as the button gate, so nothing re-enters the widget while the engine is
-- still inside its own notification. Closures are allocated only on the rare
-- pass where a reset is actually pending.
--
-- Retries are BOUNDED. An unbounded 1-second retry loop against a path that
-- never resolves would allocate a closure a second forever, which is precisely
-- the registry churn that caused the 0xffffffffffffffff crash. Twelve attempts
-- covers the widget BP not being loaded yet at mod startup; after that it gives
-- up once, loudly, and the timer fallback carries on working.
local passive_hook_registered = false
local passive_hook_attempts = 0
local passive_hook_warned = false
local PASSIVE_HOOK_ATTEMPTS = 12
-- True while a refresh pass is already queued; see the hook body.
local refresh_scheduled = false

local function register_passive_update_hook()
    if passive_hook_registered then
        return
    end
    passive_hook_attempts = passive_hook_attempts + 1
    local succeeded = pcall(function()
        RegisterHook(PASSIVE_UPDATED, function()
            -- Coalesced the same way as the button gate: at most one pass is
            -- ever queued, so this allocates nothing on the ordinary vanilla
            -- passive updates that also come through here.
            if not refresh_pending() or refresh_scheduled then
                return
            end
            refresh_scheduled = true
            ExecuteWithDelay(0, function()
                refresh_scheduled = false
                ExecuteInGameThread(consume_pending_refresh)
            end)
        end)
    end)
    if succeeded then
        passive_hook_registered = true
        log("Installed event-driven panel reset on OnPassiveUpdate.")
    elseif passive_hook_attempts < PASSIVE_HOOK_ATTEMPTS then
        ExecuteWithDelay(1000, register_passive_update_hook)
    elseif not passive_hook_warned then
        -- Setting this was missing, so the "warn once" guard guarded nothing
        -- and this line repeated on every map load before the world.
        passive_hook_warned = true
        log("OnPassiveUpdate not hookable yet. Expected before a world is loaded; retries on "
            .. "each map load, and timed panel resets cover it until then.")
    end
end

RegisterLoadMapPostHook(function()
    schedule_recovery("map load")
    -- Everything registered through lp/hooks.lua gets a fresh retry budget, for
    -- the same reason the two below do: the target does not exist on a title
    -- map, and failing there must not disable it for the session.
    hooks.rearm_on_map_load()
    bench.schedule() -- TEMPORARY
    if not button_hook_registered then
        -- Fresh retry budget per map, for the same reason the passive hook gets
        -- one: the target Blueprint only exists once a map that can show the
        -- Surgery UI has loaded, so exhausting the budget on a title map must
        -- not disable the gate for the rest of the session.
        -- The retry BUDGET resets; the warning does not. Re-arming the
        -- warning is what turned one honest notice into one per map.
        button_hook_attempts = 0
        ExecuteWithDelay(1000, register_button_guard)
    end
    if not passive_hook_registered then
        -- Fresh retry budget per map. The target Blueprint only exists once a
        -- map that can show the Surgery UI is loaded.
        passive_hook_attempts = 0
        ExecuteWithDelay(1000, register_passive_update_hook)
    end
end)

register_button_guard()
register_passive_update_hook()
conveyor.install()
bench.schedule() -- TEMPORARY
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
    "Loaded %d extractable passives, %d extraction operations, %d insert routes.",
    mapped_passive_count, extract_operations, insert_routes
))

if conveyor.DRY_RUN then
    log("The Pal Disassembly Conveyor watcher is in OBSERVATION MODE: it reports what it would "
        .. "hand over and creates nothing. See the header of lp/conveyor.lua.")
end
