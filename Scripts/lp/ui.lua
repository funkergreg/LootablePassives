-- Lootable Passives -- The Surgery widget: access, the Edit gate, panel repair,
-- and the local exchange this peer is waiting on.
--
-- The gate here makes checks the transaction also makes. The transaction runs
-- after vanilla has charged the gold; the gate refuses the click before it.
--
-- This module and lp/transaction.lua do not require each other. The one thing
-- the transaction reads from the tab page goes through lp/local_click.lua.

local util = require("lp.util")
local options = require("lp.options")
local ids = require("lp.ids")
local passives = require("lp.passives")
local local_click = require("lp.local_click")
local host = require("lp.host")
local notice = require("lp.notice")

local field = util.field
local is_valid = util.is_valid
local coalescer = util.coalescer
local log = util.log
local method = util.method
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local debug_log = options.debug_log
local debug_logf = options.debug_logf
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local is_extract_mode = ids.is_extract_mode
local first_marker = passives.first_marker
local get_skill_ids = passives.get_skill_ids
local has_skill = passives.has_skill
local is_covered = passives.is_covered
local is_direct_route = passives.is_direct_route
local is_extractable = passives.is_extractable
local surgery_allowed = host.surgery_allowed

-- The tab page's four passive cards, indexed by CachedPassiveSlotIndex + 1.
local PASSIVE_CARD_PROPERTIES = {
    "WBP_MainMenu_Pal_Skill_Passive",
    "WBP_MainMenu_Pal_Skill_Passive_1",
    "WBP_MainMenu_Pal_Skill_Passive_2",
    "WBP_MainMenu_Pal_Skill_Passive_3",
}

-- Built once and passed by reference to pcall, like the accessors in
-- lp/util.lua. Both visibility predicates below go through it.
local function _call_is_visible(widget)
    return widget:IsVisible()
end


--------------------------------------------------------------------------------
-- Surgery widget access
--------------------------------------------------------------------------------

-- The passive id on the widget's card named property_name, read from its
-- BindedPassiveSkillName. Returns nil for an invalid card or an empty slot,
-- which reads as "None".
local function card_passive(widget, property_name)
    local card = field(widget, property_name)
    if not is_valid(card) then
        return nil
    end
    local passive_id = name_to_string(field(card, "BindedPassiveSkillName"))
    if passive_id == "None" then
        return nil
    end
    return passive_id
end

-- The passive id on the card at the selected slot. Returns nil for a negative or
-- out-of-range index, and otherwise what card_passive returns.
--
-- Takes a widget its caller has already validated -- current_page() or
-- visible_extraction_widget() -- and does not validate it again.
local function selected_passive(widget)
    local index = field(widget, "CachedPassiveSlotIndex")
    if type(index) ~= "number" or index < 0 then
        return nil
    end
    local property_name = PASSIVE_CARD_PROPERTIES[index + 1]
    if property_name == nil then
        return nil
    end
    return card_passive(widget, property_name)
end

-- The tab page's selected Pal, as its PalIndividualCharacterParameter.
local function selected_parameter(page)
    return field(page, "CachedCharacter")
end

-- The tab page's CurrentPassiveId and its EXTRACTION_MODES entry. The mode is
-- nil when the pending operation is not one of ours.
local function pending_operation(page)
    local pending = name_to_string(field(page, "CurrentPassiveId"))
    return pending, EXTRACTION_MODES[pending]
end

--------------------------------------------------------------------------------
-- The widgets, and where they come from
--------------------------------------------------------------------------------
--
-- Both widgets arrive as the context argument of a hook on one of their own
-- methods: the tab page from Update Button State, the screen from
-- OnPassiveUpdate. Nothing in this file calls FindAllOf.

local live_page = nil
local live_screen = nil

-- True while this module is the reason the Edit button is blocked; see
-- block_edit. Reset by forget_live_widgets along with the page it was set on.
local edit_disabled_by_mod = false

-- The Surgery operation this peer asked for and is waiting on, or nil. Written
-- only in the local exchange section at the bottom of this file, and cleared by
-- forget_live_widgets.
local exchange = nil

-- Set once, the first time note_live_page is given something is_valid rejects.
local context_warning_reported = false

local function note_live_page(widget)
    if is_valid(widget) then
        live_page = widget
        return
    end
    if not context_warning_reported then
        context_warning_reported = true
        log("WARNING: the Update Button State hook did not hand us a usable tab page. The "
            .. "Edit-button gate cannot run, and extraction falls back to a snapshot "
            .. "of the requester's Pals to work out what was swapped. The transaction enforces every rule the "
            .. "gate does either way, so operations still behave; the click is simply not "
            .. "refused at the button, and the gold is spent before the refusal.")
    end
end

local function note_live_screen(widget)
    if is_valid(widget) then
        live_screen = widget
    end
end

-- Called from the map-load hook, which is the one point at which a recorded
-- widget is known not to belong to the current level.
local function forget_live_widgets()
    live_page = nil
    live_screen = nil
    edit_disabled_by_mod = false
    exchange = nil
end

local function current_page()
    if is_valid(live_page) then
        return live_page
    end
    live_page = nil
    return nil
end

local function current_screen()
    if is_valid(live_screen) then
        return live_screen
    end
    live_screen = nil
    return nil
end

-- The recorded tab page, if its CurrentPassiveId is one of ours.
--
-- A FAILED IsVisible call is treated as visible here, which is the opposite of
-- open_recorded below. This result feeds the transaction path, so an
-- unanswerable visibility question does not veto it; open_recorded guards
-- writes instead.
local function visible_extraction_widget()
    local page = current_page()
    if page == nil then
        return nil
    end
    local visible_ok, visible = pcall(_call_is_visible, page)
    if visible_ok and visible ~= true then
        return nil
    end
    if select(2, pending_operation(page)) ~= nil then
        return page
    end
    return nil
end

-- Builds a record from the tab page: the selected slot's passive, the Pal's
-- parameter object, and its passive list before the swap. Returns nil if there
-- is no visible page with one of our operations pending, no parameter, or no
-- passive list, with true as a second value when a tab page is recorded.
--
-- An empty slot reads as a nil passive and is captured like any other: an
-- extract mode there appends its marker, which the transaction reports as stray
-- and removes.
--
-- The record has a one-element snapshots list, the shape the transaction's
-- server snapshot has. expect_passive_id is the field specific to this one.
local function capture_local_click(request_player_id)
    local widget = visible_extraction_widget()
    if widget == nil then
        return nil, current_page() ~= nil
    end
    local parameter = selected_parameter(widget)
    local skill_ids = get_skill_ids(parameter)
    if skill_ids == nil then
        return nil, true
    end
    return {
        snapshots = {
            {
                parameter = parameter,
                before_ids = skill_ids,
                expect_passive_id = selected_passive(widget),
            },
        },
        request_player_id = request_player_id,
        mode_source = "targeted UI",
    }
end

local_click.capture = capture_local_click

-- Built once and passed to pcall by reference, like _call_is_visible above.
local function _call_set_interaction_enabled(widget, enabled)
    widget:SetIsInteractionEnabled(enabled)
end

-- The tab page's inner CommonButtonBase, the one the interaction flag lives on,
-- or nil.
local function edit_button(widget)
    local button = field(widget, "WBP_CommonButton")
    if not is_valid(button) then
        return nil
    end
    local inner = field(button, "WBP_PalInvisibleButton")
    if is_valid(inner) then
        return inner
    end
    return nil
end

-- The Edit button's state for the log: the outer WBP_CommonButton_C's
-- GetIsEnabled() and IsHovered() (UMG.hpp, zero arguments) and the inner
-- CommonButtonBase's IsInteractionEnabled() and bHasFocus.
local function edit_state(page)
    local outer = field(page, "WBP_CommonButton")
    local inner = edit_button(page)
    return string.format("edit outerEnabled=%s hovered=%s innerInteraction=%s innerFocus=%s",
        tostring(method(outer, "GetIsEnabled")), tostring(method(outer, "IsHovered")),
        tostring(method(inner, "IsInteractionEnabled")), tostring(field(inner, "bHasFocus")))
end

-- SetIsEnabled(bool) on a UWidget (UMG.hpp), prebuilt for pcall.
local function _call_set_is_enabled(widget, enabled)
    widget:SetIsEnabled(enabled)
end

-- Re-enables the outer Edit button when GetIsEnabled() reads false. This module
-- never disables it, so a false here was written by the game. Does nothing while
-- an exchange is pending, when a false may be the game holding the button for
-- a request in flight. when prefixes the log lines.
local function repair_edit(when, page)
    if exchange ~= nil then
        return
    end
    local outer = field(page, "WBP_CommonButton")
    if not is_valid(outer) or method(outer, "GetIsEnabled") ~= false then
        return
    end
    debug_log(when .. ": the outer Edit button reads disabled; calling SetIsEnabled(true) on it.")
    local succeeded = pcall(_call_set_is_enabled, outer, true)
    debug_log(string.format("%s: SetIsEnabled %s; the outer Edit button now reads enabled=%s.",
        when, succeeded and "returned" or "raised", tostring(method(outer, "GetIsEnabled"))))
end

-- Writes SetIsInteractionEnabled on the inner CommonButtonBase
-- (CommonUI.hpp:324, one bool argument). This stops the click and changes
-- nothing about the paint.
--
-- SetIsEnabled is called on neither button. On the outer WBP_CommonButton_C, a
-- plain UUserWidget, it gives a white cut-out; on the inner one it would be
-- reaching for CommonUI's DisabledStyle, and the game does not use that here --
-- bIsEnabled reads true on both buttons whether the game is refusing or not.
local function set_edit_interactable(widget, enabled)
    local inner = edit_button(widget)
    if inner ~= nil then
        pcall(_call_set_interaction_enabled, inner, enabled)
    end
end

-- Holds the button blocked, by refusing the click and by nothing else.
--
-- EnabledButton is not written. The property belongs to the Blueprint: Update Button State recomputes it
-- from scratch on a hook that fires while the screen is open, and this module
-- can only write it after that has happened. On a selection the game judges
-- usable -- an empty slot with an extract route is one, since vanilla has no
-- notion of extraction -- the two writes alternate and the button flickers
-- rather than greying. Blocked-and-lit is the accepted behaviour.
--
-- The interaction flag is not recomputed by the Blueprint, so it is written only
-- when IsInteractionEnabled() (CommonUI.hpp:340, no arguments) reads anything
-- but false. That read is on the button itself, so a page recreated without a
-- map load is written to even while edit_disabled_by_mod is still true from the
-- old one.
--
-- Logged on the transition only, never on the per-frame pass that finds the
-- button already held.
local function block_edit(widget, pending, index)
    if edit_disabled_by_mod and method(edit_button(widget), "IsInteractionEnabled") == false then
        return
    end
    set_edit_interactable(widget, false)
    edit_disabled_by_mod = true
    debug_log(string.format("Edit blocked: %s pending, slot %s holds %s.",
        tostring(pending), tostring(index), tostring(selected_passive(widget))))
end

-- Restores the interaction flag, and only if this module cleared it.
local function release_edit(widget)
    if not edit_disabled_by_mod then
        return -- never touched it, so there is nothing to undo
    end
    edit_disabled_by_mod = false
    set_edit_interactable(widget, true)
    debug_log("Edit released.")
end

-- Is the passive an alias would install already on the Pal?
--
-- Compares against IMPLANT_TARGET[pending], the id that ends up on the Pal,
-- rather than against the alias id, which never matches anything in the list.
local function alias_target_already_present(page, pending)
    local target = IMPLANT_TARGET[pending]
    return target ~= nil and has_skill(selected_parameter(page), target)
end

-- Blocks or releases the Edit button for the recorded tab page.
--
-- Runs for whatever operation is pending, including none: the release branch has
-- to be reachable from every state, or a block made in one state outlives it.
--
-- Blocks only while a slot is selected (CachedPassiveSlotIndex >= 0), and then
-- when an operation surgery_extraction covers is pending and
-- host.surgery_allowed() is false, when an extract mode is pending and that
-- slot does not hold an extractable passive -- selected_passive returns nil for
-- an empty slot, and is_extractable rejects it -- or when an alias is pending
-- and alias_target_already_present is true.
--
-- With no slot selected the button is released whatever is pending: vanilla
-- keeps Edit disabled itself in that state, and a CommonButtonBase whose
-- interaction is off cannot take gamepad focus, so a block here would send the
-- focus ring to the slot group when an operation is chosen from the list.
--
-- Takes no arguments so main.lua can hand it to coalescer() by reference; see
-- the note on coalescer() in lp/util.lua. main.lua does not schedule it at all
-- when surgery_ui_gate is false; it schedules
-- release_extraction_gate instead while edit_held() is true.
local function enforce_extraction_gate()
    local page = current_page()
    if page == nil then
        return
    end

    local index = field(page, "CachedPassiveSlotIndex")
    local slot_selected = type(index) == "number" and index >= 0
    local pending, mode = pending_operation(page)
    local blocked = slot_selected and (
        (is_covered(pending) and not surgery_allowed())
        or (is_extract_mode(mode) and not is_extractable(selected_passive(page)))
        or (mode == "implant" and alias_target_already_present(page, pending)))

    if blocked then
        block_edit(page, pending, index)
    else
        release_edit(page)
    end
end

-- True while this module holds the Edit button blocked.
local function edit_held()
    return edit_disabled_by_mod
end

-- Releases a block this module made on the recorded tab page, whatever is
-- pending. No arguments, for coalescer(), as enforce_extraction_gate.
local function release_extraction_gate()
    local page = current_page()
    if page ~= nil then
        release_edit(page)
    end
end

--------------------------------------------------------------------------------
-- The operation list
--------------------------------------------------------------------------------
--
-- While host.surgery_allowed() is false, every entry of the screen's operation
-- list whose PassiveId passives.is_covered accepts is collapsed. The list's
-- entries are created anew by every SetupPassiveChangeItem, so this runs after
-- each one, a frame later, on the screen that hook handed over.
--
-- Nothing rebuilds the list when host.surgery_allowed() changes: the list
-- follows at its next build (another Pal selected, or the table reopened), and
-- the Edit-button gate, which reads host.surgery_allowed() at every firing,
-- refuses or allows the click at once.

-- ESlateVisibility::Collapsed (UMG_enums.hpp).
local COLLAPSED = 1

-- What the player is told, once per world, by host.refusal() reason.
local REFUSAL_MESSAGES = {
    off_here = "Lootable Passives: Surgery extraction is off in this mod's settings, so its "
        .. "Surgery operations are hidden.",
    off_host = "Lootable Passives: the host has turned Surgery extraction off, so this mod's "
        .. "Surgery operations are hidden.",
    unconfirmed = "Lootable Passives: this world's host has not confirmed it runs this mod "
        .. "(1.3.0 or later), so its Surgery operations are hidden.",
}

-- UPanelWidget::GetChildAt(int32) (UMG.hpp), and UWidget::SetVisibility
-- (ESlateVisibility) (UMG.hpp): one argument each.
local function _call_get_child_at(panel, index)
    return panel:GetChildAt(index)
end

local function _call_set_visibility(widget, visibility)
    widget:SetVisibility(visibility)
end

-- Collapses the covered entries of the recorded screen's list, when
-- host.refusal() names a reason, and tells the player once per world when any
-- was collapsed. The list is the screen's WBP_PalCommonScrollList_Item's
-- ScrollBox_0 (WBP_PalCommonScrollList.hpp), whose children are the
-- WBP_OperatingTable_ItemList_C entries.
local function hide_refused_entries()
    local reason = host.refusal()
    local screen = current_screen()
    if reason == nil or screen == nil then
        return
    end
    local list = field(field(screen, "WBP_PalCommonScrollList_Item"), "ScrollBox_0")
    if not is_valid(list) then
        return
    end
    local hidden = 0
    for index = 0, (method(list, "GetChildrenCount") or 0) - 1 do
        local got, entry = pcall(_call_get_child_at, list, index)
        entry = got and unwrap(entry) or nil
        if is_valid(entry) and is_covered(name_to_string(field(entry, "PassiveId")))
            and pcall(_call_set_visibility, entry, COLLAPSED)
        then
            hidden = hidden + 1
        end
    end
    debug_log(string.format("operation list: %d entries hidden (%s)", hidden, reason))
    if hidden > 0 then
        notice.once(reason, REFUSAL_MESSAGES[reason])
    end
end

local schedule_hide = coalescer(hide_refused_entries, 0)

-- Called from main.lua's hook on the screen's SetupPassiveChangeItem, whose
-- Blueprint callback runs after the list is built. The context is the screen.
local function on_list_built(screen)
    note_live_screen(screen)
    if host.refusal() ~= nil then
        schedule_hide()
    end
end

--------------------------------------------------------------------------------
-- Panel repair
--------------------------------------------------------------------------------
--
-- This file does not write the passive cards. SetPassiveSkill and Clear on a
-- card are not called from anywhere; refresh_surgery_ui resets the panel
-- instead.

-- The recorded widget if it is valid and IsVisible reads true, else nil. Does
-- not scan for another. Positive visibility, for the write path: the inverse of
-- the rule in visible_extraction_widget, so a failed IsVisible call counts as
-- not open.
local function open_recorded(widget)
    if not is_valid(widget) then
        return nil
    end
    local visible_ok, visible = pcall(_call_is_visible, widget)
    if visible_ok and visible == true then
        return widget
    end
    return nil
end

-- Does the screen have a Pal selected? SetupPassiveChangeItem builds the
-- operation list from it, so the rebuild below is skipped when this is false.
local function has_selected_pal(screen)
    return is_valid(field(screen, "CurrentHandle"))
end

-- The three writes refresh_surgery_ui makes with an argument, built once and
-- passed to pcall by reference like _call_is_visible above.
local function _set_slot_index(page, index)
    page.CachedPassiveSlotIndex = index
end

local function _call_update_consume_item(page, item_name)
    page:UpdateCurrentConsumeItem(item_name)
end

local function _set_consume_item_id(screen, item_name)
    screen.CachedConsumeItemId = item_name
end

-- UpdateNum(FName) on the tab page (WBP_OperatingTable_TabPage.hpp:70), one
-- FName argument: redraws the chip's quantity readout for that item.
local function _call_update_num(page, item_name)
    page:UpdateNum(item_name)
end

-- The chip's quantity readout, BP_PalTextBlock_Num, for the log: its text
-- through GetText() and its visibility through GetVisibility() (UMG.hpp, both
-- zero-argument).
local function num_state(page)
    local block = field(page, "BP_PalTextBlock_Num")
    return string.format("count text=%s visibility=%s",
        tostring(name_to_string(method(block, "GetText"))), tostring(method(block, "GetVisibility")))
end

-- when, then "before" or "after" UpdateNum(None), then num_state(page).
local function describe_num(when, stage, page)
    return string.format("%s: %s UpdateNum(None): %s.", when, stage, num_state(page))
end

-- The passive ids the right-hand Pal detail is showing: card_passive of each of
-- its four cards whose IsVisible() reads true. A card the game has emptied keeps
-- its last name and is hidden, so it is left out. nil when the detail does not
-- read.
local function detail_passives(detail)
    if not is_valid(detail) then
        return nil
    end
    local shown = {}
    for _, property_name in ipairs(PASSIVE_CARD_PROPERTIES) do
        local passive_id = card_passive(detail, property_name)
        if passive_id ~= nil then
            local visible_ok, visible = pcall(_call_is_visible, field(detail, property_name))
            if visible_ok and visible == true then
                shown[#shown + 1] = passive_id
            end
        end
    end
    return shown
end

-- One log line on the Pal detail against the selected Pal, plus the tab page's
-- CurrentPassiveId and CachedPassiveSlotIndex as they stand, prefixed with when
-- it was read. Returns the detail widget, the shown list and the Pal's list; the
-- lists are nil when either side does not read.
local function log_detail_state(when, screen, page)
    local detail = field(screen, "WBP_IngameMenu_PalBox_PalDetail")
    local shown = detail_passives(detail)
    local actual = get_skill_ids(selected_parameter(page))
    local panel = string.format("panel operation=%s slot=%s; %s",
        tostring((pending_operation(page))), tostring(field(page, "CachedPassiveSlotIndex")),
        edit_state(page))
    if shown == nil or actual == nil then
        debug_log(string.format("%s: Pal detail check skipped, detail readable=%s, Pal list readable=%s; %s.",
            when, tostring(shown ~= nil), tostring(actual ~= nil), panel))
        return detail, nil, nil
    end
    debug_log(string.format("%s: Pal detail shows [%s]; the Pal has [%s]; %s.",
        when, table.concat(shown, ","), table.concat(actual, ","), panel))
    return detail, shown, actual
end

-- Element-wise equality, in order.
local function same_list(a, b)
    if #a ~= #b then
        return false
    end
    for index = 1, #a do
        if a[index] ~= b[index] then
            return false
        end
    end
    return true
end

-- Do two id lists hold the same ids in any order? Compares sorted copies.
local function same_ids(a, b)
    if #a ~= #b then
        return false
    end
    local left, right = {}, {}
    for index = 1, #a do
        left[index], right[index] = a[index], b[index]
    end
    table.sort(left)
    table.sort(right)
    return same_list(left, right)
end

-- BindFromHandle takes one UPalIndividualCharacterHandle*
-- (WBP_IngameMenu_PalBox_PalDetail.hpp) and rebinds the detail to that Pal.
local function _call_bind_from_handle(detail, handle)
    detail:BindFromHandle(handle)
end

-- Reads the screen's Pal detail against the selected Pal's passive list, logs
-- both, and rebinds the detail through BindFromHandle(CurrentHandle) when the
-- detail still shows one of our markers or a different set of passives. The log
-- is the result. when prefixes the log lines.
local function repair_detail(when, screen, page)
    local detail, shown, actual = log_detail_state(when, screen, page)
    if shown == nil then
        return
    end
    if first_marker(shown) == nil and same_ids(shown, actual) then
        return
    end
    local handle = field(screen, "CurrentHandle")
    if not is_valid(handle) then
        debug_log(when .. ": Pal detail is stale and NOT rebound: the screen has no CurrentHandle.")
        return
    end
    debug_log(when .. ": Pal detail is stale; calling BindFromHandle on it.")
    local succeeded = pcall(_call_bind_from_handle, detail, handle)
    shown = detail_passives(detail) or {}
    debug_log(string.format("%s: BindFromHandle %s; the Pal detail now shows [%s].",
        when, succeeded and "returned" or "raised", table.concat(shown, ",")))
end

-- Set once, the first time a refresh finds no open page.
local closed_skip_reported = false

-- Resets the panel after a transaction. Returns true if it wrote anything.
--
-- reset_panel clears the operation chip and consume-item count.
--
-- rebuild_list calls SetupPassiveChangeItem, which recreates every entry widget
-- in the operation list.
--
-- Both are skipped entirely unless the recorded page is open, and the screen
-- half is skipped unless the recorded screen is open. Nothing is written to a
-- widget that is not open.
local function refresh_surgery_ui(reset_panel, rebuild_list, when)
    local page = open_recorded(current_page())
    if page == nil then
        if not closed_skip_reported then
            closed_skip_reported = true
            debug_log("The Surgery panel was already closed when a refresh came due, so nothing was "
                .. "repainted. Expected if you close the screen right after an operation; the "
                .. "panel is rebuilt from scratch when you next open it.")
        end
        return false
    end
    local screen = open_recorded(current_screen())

    if reset_panel then
        -- -1 is the panel's no-slot-selected value.
        --
        -- "Set Passive Empty Item" takes no arguments
        -- (WBP_OperatingTable_TabPage.hpp:80) and its name contains spaces, so
        -- it is indexed rather than dotted. UpdateCurrentConsumeItem takes one
        -- FName and has no out-parameter (same header, line 92); it clears the
        -- quantity readout, which "Set Passive Empty Item" leaves alone.
        pcall(_set_slot_index, page, -1)
        pcall(_call_update_consume_item, page, FName("None"))
        method(page, "Set Passive Empty Item")
        method(page, "ReflectPassiveChange")
        method(page, "RefreshCurrentPassiveItem")
        -- The quantity readout survives the writes above after a consumable
        -- route; UpdateNum with no item is the vanilla redraw for it.
        debug_logf(describe_num, when, "before", page)
        pcall(_call_update_num, page, FName("None"))
        debug_logf(describe_num, when, "after", page)
    end

    if screen ~= nil then
        -- The screen holds its own copy of the consume item id and feeds it
        -- back to the page on refresh, so the page-level clear above is not
        -- sufficient on its own.
        if reset_panel then
            pcall(_set_consume_item_id, screen, FName("None"))
        end
        -- SetupPassiveChangeItem takes no arguments (WBP_OperatingTable.hpp:47).
        -- Entry validity is decided when each entry is created, which is why a
        -- module count only changes on a rebuild.
        if rebuild_list and has_selected_pal(screen) then
            method(screen, "SetupPassiveChangeItem")
        end
        method(screen, "RefreshItemDisplay")
        repair_detail(when, screen, page)
    end

    return true
end

-- Armed by on_transaction_complete below, consumed by whichever of two paths
-- reaches it first: main.lua's OnPassiveUpdate hook, or the next-tick timer that
-- function starts. Consuming it clears it, so the refresh runs once per arming.
-- nil when unarmed; otherwise the reset_panel value to refresh with.
local pending_reset = nil

-- The tab page's operation and slot as on_transaction_complete found them,
-- before any reset: the selection the finished exchange left behind. nil when
-- no backstop is due.
local finished_selection = nil

-- Runs the armed refresh, then repair_edit on the same page. repair_edit runs
-- here only, once per finished exchange, and not on the 1600 ms timer.
local function consume_pending_refresh()
    local reset_panel = pending_reset
    if reset_panel == nil then
        return
    end
    pending_reset = nil
    if refresh_surgery_ui(reset_panel, true, "refresh on finish") then
        repair_edit("refresh on finish", current_page())
    end
end

-- An accessor, not an exported variable: main.lua reads pending_reset, and
-- exporting it in the return table below would export its value at load time --
-- a permanent nil for every consumer.
local function refresh_pending()
    return pending_reset ~= nil
end

-- The callbacks the timers below take are built once, at load, and passed
-- to ExecuteInGameThreadWithDelay by reference; see the note on coalescer() in
-- lp/util.lua.
-- Resets the panel only when its operation and slot still equal
-- finished_selection, which is the game repainting the finished exchange's
-- selection. Any other selection is the player's, as is any selection while a
-- new exchange is pending; then the refresh runs without the reset.
local function reset_panel_now()
    local selection = finished_selection
    finished_selection = nil
    local page = current_page()
    local operation = page ~= nil and (pending_operation(page)) or nil
    local slot = page ~= nil and field(page, "CachedPassiveSlotIndex") or nil
    local stale = selection ~= nil and exchange == nil
        and operation == selection.operation and slot == selection.slot
    debug_log(string.format("reset at 1600 ms: panel operation=%s slot=%s, finished with "
        .. "operation=%s slot=%s; reset=%s.",
        tostring(operation), tostring(slot), tostring(selection and selection.operation),
        tostring(selection and selection.slot), tostring(stale)))
    refresh_surgery_ui(stale, false, "reset at 1600 ms")
end

-- What a finished exchange does to the Surgery panel. Called by the local
-- exchange section below with that exchange's mode.
--
-- The panel is reset for every mode, implants included. After an implant the
-- chip still names the alias and the Pal now carries its target, so the gate
-- would block the next click as a duplicate; clearing the selection is what
-- leaves the button in a state vanilla owns.
local function on_transaction_complete(mode)
    local reset_panel = true
    debug_log(string.format("Panel refresh armed for the %s exchange.", tostring(mode)))
    pending_reset = reset_panel

    -- The tick after finish: the marker is already off the Pal, and every
    -- millisecond here is a millisecond it stays painted in the slot.
    -- consume_pending_refresh runs at most once per arming.
    ExecuteInGameThreadWithDelay(0, consume_pending_refresh)

    if reset_panel then
        -- Not gated on the armed refresh: the late backstop for a repaint the
        -- game makes after the first refresh. reset_panel_now compares against
        -- the selection recorded here.
        local page = current_page()
        finished_selection = page ~= nil and {
            operation = (pending_operation(page)),
            slot = field(page, "CachedPassiveSlotIndex"),
        } or nil
        ExecuteInGameThreadWithDelay(1600, reset_panel_now)
    end
end

--------------------------------------------------------------------------------
-- The local exchange
--------------------------------------------------------------------------------
--
-- Each peer watches the operation it asked for itself. begin_local_exchange runs
-- from main.lua's hook on the model's RequestChangePassiveSkill, on the peer
-- that clicked; the server's half of the exchange may run on another machine.
-- check_local_exchange re-reads the Pal's passive list and calls the exchange
-- finished when no marker is on it and the list has moved from where it
-- started, then hands the mode to on_transaction_complete. The engine events
-- that call it are triggers only; the read is the check, so it does not matter
-- which of them fires on a given peer.

-- 50 polls at 100 ms: 5 s. Each poll is one passive-list read, and the poll
-- interval is how long the marker stays painted after the server half ends.
local EXCHANGE_POLL_MS = 100
local EXCHANGE_POLL_LIMIT = 50

-- Logs message, clears the pending exchange, and hands record's mode to
-- on_transaction_complete. The Pal detail is read and logged, under debug,
-- before any write of this module's: what it shows here is what the game
-- repainted alone.
local function end_local_exchange(record, message)
    log(message)
    exchange = nil
    if options.debug_on() then
        log_detail_state("at finish", current_screen(), current_page())
    end
    on_transaction_complete(record.mode)
end

-- Re-reads the pending exchange's Pal. Finished when no marker is on it and the
-- list differs from the one at the request, or when a marker was seen earlier
-- and is gone now even though the list is back where it started, as after an
-- abort or an empty-slot extraction. Returns whether it finished. trigger names
-- the calling event for the log.
local function check_local_exchange(trigger)
    local record = exchange
    if record == nil then
        return false
    end
    local after_ids = get_skill_ids(record.parameter)
    if after_ids == nil then
        return false
    end
    if trigger ~= "poll" then
        -- Every event-driven check is logged; the poll is not, since it repeats.
        debug_log(string.format("Checked the %s exchange (%s): the Pal has [%s].",
            record.lock, trigger, table.concat(after_ids, ",")))
    end
    local marker = first_marker(after_ids)
    if marker ~= nil then
        if not record.marker_seen then
            record.marker_seen = true
            debug_log(string.format("Marker %s is on the Pal (%s, poll %d); the server half is pending.",
                marker, trigger, record.polls))
        end
        return false
    end
    if not record.marker_seen and same_list(record.before_ids, after_ids) then
        return false
    end
    debug_log(string.format("The %s exchange finished on %s, poll %d.", record.lock, trigger,
        record.polls))
    end_local_exchange(record, string.format("Surgery %s finished; the Pal now has [%s].",
        record.lock, table.concat(after_ids, ",")))
    return true
end

local schedule_exchange_poll

local function run_exchange_poll()
    local record = exchange
    if record == nil then
        return
    end
    record.polls = record.polls + 1
    if check_local_exchange("poll") then
        return
    end
    if record.polls < EXCHANGE_POLL_LIMIT then
        schedule_exchange_poll()
        return
    end
    end_local_exchange(record, string.format(
        "WARNING: the %s exchange did not finish within %d ms (marker seen=%s, server accepted=%s). "
        .. "The Pal has [%s]. The panel is reset anyway; a marker still listed is stranded.",
        record.lock, EXCHANGE_POLL_MS * EXCHANGE_POLL_LIMIT, tostring(record.marker_seen),
        tostring(record.notified), table.concat(get_skill_ids(record.parameter) or {}, ",")))
end

-- One scheduled poll at a time; coalescer clears its flag before
-- run_exchange_poll runs, so the poll can reschedule itself.
schedule_exchange_poll = coalescer(run_exchange_poll, EXCHANGE_POLL_MS)

-- Called from main.lua's hook on the model's RequestChangePassiveSkill with the
-- requested passive id and slot index. Records nothing for any other passive
-- id; a direct route's is logged under debug.
-- The Pal is the recorded tab page's CachedCharacter, read now.
local function begin_local_exchange(passive_id, slot_index)
    local mode = EXTRACTION_MODES[passive_id]
    if mode == nil then
        if is_direct_route(passive_id) then
            debug_log(string.format("Requested the direct-route implant %s on slot %s; the game "
                .. "completes it, so the panel is not tracked.", passive_id, tostring(slot_index)))
        end
        return
    end
    local page = current_page()
    local parameter = page ~= nil and selected_parameter(page) or nil
    local before_ids = get_skill_ids(parameter)
    if before_ids == nil then
        debug_log(string.format(
            "Requested %s but the selected Pal's passive list does not read (tab page recorded=%s), "
            .. "so the panel is not repaired for this exchange.", passive_id, tostring(page ~= nil)))
        return
    end
    if exchange ~= nil then
        debug_log(string.format("A pending %s exchange is replaced by this request.", exchange.lock))
    end
    exchange = {
        mode = mode,
        lock = passive_id,
        parameter = parameter,
        before_ids = before_ids,
        polls = 0,
        marker_seen = false,
        notified = false,
    }
    debug_log(string.format("Requested %s on slot %s of a Pal with [%s]; waiting for the exchange to finish.",
        passive_id, tostring(slot_index), table.concat(before_ids, ",")))
    schedule_exchange_poll()
end

-- Called from main.lua's hook on the screen's OnOperatingPassiveNotifyied with
-- its Success argument: the server's answer to the vanilla half of the request.
local function note_operation_result(success)
    if exchange == nil then
        return
    end
    if success == false then
        log(string.format(
            "The server refused the %s request; nothing to wait for. The panel is left as vanilla "
            .. "shows it.", exchange.lock))
        exchange = nil
        return
    end
    if not exchange.notified then
        exchange.notified = true
        debug_log(string.format("The server accepted the %s request; the vanilla half is done.", exchange.lock))
    end
    check_local_exchange("operation notify")
end

return {
    begin_local_exchange = begin_local_exchange,
    check_local_exchange = check_local_exchange,
    consume_pending_refresh = consume_pending_refresh,
    edit_held = edit_held,
    enforce_extraction_gate = enforce_extraction_gate,
    forget_live_widgets = forget_live_widgets,
    note_live_page = note_live_page,
    note_live_screen = note_live_screen,
    note_operation_result = note_operation_result,
    on_list_built = on_list_built,
    refresh_pending = refresh_pending,
    release_extraction_gate = release_extraction_gate,
}
