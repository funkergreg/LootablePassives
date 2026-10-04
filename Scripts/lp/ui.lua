-- Lootable Passives -- The Surgery widget: access, the Edit gate, and panel repair.
--
-- The gate here duplicates checks the transaction also makes, and the
-- duplication is load-bearing rather than accidental: the transaction runs
-- after vanilla has charged the gold, so only a refusal at the button keeps a
-- doomed operation from costing anything. Do not collapse the two.
--
-- This module must NOT require lp.transaction. transaction requires this one, and
-- keeping that edge one-directional is what stops the pair forming a cycle.

local util = require("lp.util")
local ids = require("lp.ids")
local passives = require("lp.passives")

local field = util.field
local is_valid = util.is_valid
local log = util.log
local method = util.method
local name_to_string = util.name_to_string
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local is_extract_mode = ids.is_extract_mode
local has_skill = passives.has_skill
local is_extractable = passives.is_extractable

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

-- The passive id on the card at the selected slot. Returns nil for a negative or
-- out-of-range index, an invalid card, or an empty slot, which reads as "None".
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
--
-- Do not reintroduce a scan here without good reason.

local live_page = nil
local live_screen = nil

-- True while this module is the reason the Edit button is blocked; see
-- block_edit. Reset by forget_live_widgets along with the page it was set on.
local edit_disabled_by_mod = false

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
-- EnabledButton is NOT written, and reintroducing that write is a regression.
-- The property belongs to the Blueprint: Update Button State recomputes it
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
local function block_edit(widget)
    if edit_disabled_by_mod and method(edit_button(widget), "IsInteractionEnabled") == false then
        return
    end
    set_edit_interactable(widget, false)
    edit_disabled_by_mod = true
end

-- Restores the interaction flag, and only if this module cleared it.
local function release_edit(widget)
    if not edit_disabled_by_mod then
        return -- never touched it, so there is nothing to undo
    end
    edit_disabled_by_mod = false
    set_edit_interactable(widget, true)
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
-- Blocks when an extract mode is pending and the selected slot does not hold an
-- extractable passive -- selected_passive returns nil for an empty slot, and
-- is_extractable rejects it -- or when an alias is pending and
-- alias_target_already_present is true.
--
-- Takes no arguments so main.lua can hand it to ExecuteInGameThread by
-- reference; see the note on coalescer() in main.lua. main.lua does not schedule
-- it at all when surgery_ui_gate is false in settings.lua.
local function enforce_extraction_gate()
    local page = current_page()
    if page == nil then
        return
    end

    local pending, mode = pending_operation(page)
    local blocked = (is_extract_mode(mode) and not is_extractable(selected_passive(page)))
        or (mode == "implant" and alias_target_already_present(page, pending))

    if blocked then
        block_edit(page)
    else
        release_edit(page)
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

-- Set once, the first time a refresh finds no open page.
local closed_skip_reported = false

-- Resets the panel after a transaction. Returns true if it wrote anything.
--
-- reset_panel clears the operation chip and consume-item count;
-- on_transaction_complete passes false for an implant, where that selection is
-- not this mod's to clear.
--
-- rebuild_list calls SetupPassiveChangeItem, which recreates every entry widget
-- in the operation list.
--
-- Both are skipped entirely unless the recorded page is open, and the screen
-- half is skipped unless the recorded screen is open. Nothing is written to a
-- widget that is not open.
local function refresh_surgery_ui(reset_panel, rebuild_list)
    local page = open_recorded(current_page())
    if page == nil then
        if not closed_skip_reported then
            closed_skip_reported = true
            log("The Surgery panel was already closed when a refresh came due, so nothing was "
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
    end

    return true
end

-- Armed by on_transaction_complete below, consumed by whichever of two paths
-- reaches it first: main.lua's OnPassiveUpdate hook, or the 500 ms timer that
-- function starts. Consuming it clears it, so the refresh runs once per arming.
-- nil when unarmed; otherwise the reset_panel value to refresh with.
local pending_reset = nil

local function consume_pending_refresh()
    local reset_panel = pending_reset
    if reset_panel == nil then
        return
    end
    pending_reset = nil
    refresh_surgery_ui(reset_panel, true)
end

-- An accessor, not an exported variable: main.lua reads pending_reset, and
-- exporting it in the return table below would export its value at load time --
-- a permanent nil for every consumer.
local function refresh_pending()
    return pending_reset ~= nil
end

-- The three callbacks the timers below take are built once, at load, and passed
-- to ExecuteWithDelay and ExecuteInGameThread by reference; see the note on
-- coalescer() in main.lua.
local function reset_panel_now()
    refresh_surgery_ui(true, false)
end

local function consume_on_game_thread()
    ExecuteInGameThread(consume_pending_refresh)
end

local function reset_on_game_thread()
    ExecuteInGameThread(reset_panel_now)
end

-- What a finished transaction does to the Surgery panel. Called by
-- lp.transaction's finish with that transaction's mode.
--
-- reset_panel is false for mode == "implant", which is what stops
-- refresh_surgery_ui clearing the operation chip and the consume-item count for
-- an insert: that selection is not this mod's to clear. See the note on
-- refresh_surgery_ui above.
local function on_transaction_complete(mode)
    local reset_panel = mode ~= "implant"
    pending_reset = reset_panel

    -- Second path to the same armed refresh, for when the OnPassiveUpdate hook
    -- does not reach it. consume_pending_refresh runs at most once per arming.
    ExecuteWithDelay(500, consume_on_game_thread)

    if reset_panel then
        -- Unconditional, and not gated on the armed refresh.
        ExecuteWithDelay(1600, reset_on_game_thread)
    end
end

return {
    forget_live_widgets = forget_live_widgets,
    note_live_page = note_live_page,
    note_live_screen = note_live_screen,
    consume_pending_refresh = consume_pending_refresh,
    current_page = current_page,
    on_transaction_complete = on_transaction_complete,
    refresh_pending = refresh_pending,
    enforce_extraction_gate = enforce_extraction_gate,
    selected_parameter = selected_parameter,
    selected_passive = selected_passive,
    visible_extraction_widget = visible_extraction_widget,
}
