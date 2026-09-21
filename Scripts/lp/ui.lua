-- Lootable Passives -- The Surgery widget: access, the Edit gate, and panel repair.
--
-- The gate here duplicates checks the transaction also makes
-- TODO: simplify
--
-- This module must NOT require lp.transaction. transaction requires this one, and
-- keeping that edge one-directional is what stops the pair forming a cycle.

local SETTINGS = require("settings")
local util = require("lp.util")
local ids = require("lp.ids")
local passives = require("lp.passives")

local field = util.field
local method = util.method
local is_valid = util.is_valid
local log = util.log
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local is_extract_mode = ids.is_extract_mode
local count_id = passives.count_id
local get_skill_ids = passives.get_skill_ids
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

-- The passive id on the card at the selected slot, and that slot's index.
-- Returns nil, nil for an invalid widget, a negative or out-of-range index, or
-- an invalid card.
local function selected_passive(widget)
    if not is_valid(widget) then
        return nil, nil
    end
    local index = unwrap(widget.CachedPassiveSlotIndex)
    if type(index) ~= "number" or index < 0 then
        return nil, nil
    end
    local property_name = PASSIVE_CARD_PROPERTIES[index + 1]
    if property_name == nil then
        return nil, nil
    end
    local card = unwrap(widget[property_name])
    if not is_valid(card) then
        return nil, nil
    end
    return name_to_string(card.BindedPassiveSkillName), index
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
            .. "Edit-button gate cannot run, and extraction falls back to the whole-world "
            .. "snapshot to work out what was swapped. The transaction enforces every rule the "
            .. "gate does either way, so operations still behave; the button simply is not "
            .. "greyed out when it should be.")
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

-- The recorded tab page and its CurrentPassiveId, if that id is one of ours.
--
-- A FAILED IsVisible call is treated as visible here, which is the opposite of
-- is_open below. This result feeds the transaction path, so an unanswerable
-- visibility question does not veto it; is_open guards writes instead.
local function visible_extraction_widget()
    local page = current_page()
    if page == nil then
        return nil, nil
    end
    local visible_ok, visible = pcall(_call_is_visible, page)
    if visible_ok and visible ~= true then
        return nil, nil
    end
    local pending = name_to_string(field(page, "CurrentPassiveId"))
    if pending ~= nil and EXTRACTION_MODES[pending] ~= nil then
        return page, pending
    end
    return nil, nil
end

-- True while this module is the reason the button is blocked.
local edit_disabled_by_mod = false

-- Writes SetIsInteractionEnabled on the inner CommonButtonBase
-- (CommonUI.hpp:324, one bool argument).
--
-- SetIsEnabled on the outer WBP_CommonButton_C is not called. What the widget
-- offers instead is unknown: WBP_CommonButton.hpp declares no enabled/disabled
-- setter and no disabled-state animation -- Anm_Normal, Anm_NormalToFocus,
-- Anm_OpenFocus, Anm_DefaultToRed. describe_button_state below is the probe for
-- finding out which property carries it; see docs/PLAN.md.
local function set_edit_interactable(widget, enabled)
    local button = unwrap(widget.WBP_CommonButton)
    if not is_valid(button) then
        return
    end
    local inner = unwrap(button.WBP_PalInvisibleButton)
    if is_valid(inner) then
        pcall(function() inner:SetIsInteractionEnabled(enabled) end)
    end
end

-- A ONE-SHOT PROBE, to be deleted once docs/PLAN.md carries its answer.
--
-- Logs eight widget properties under a label, once per label per session. Reads
-- only, through field() and method(), so no argument is passed to anything.
local reported_button_states = {}

local function describe_button_state(page, label)
    if reported_button_states[label] then
        return
    end
    reported_button_states[label] = true
    local button = unwrap(field(page, "WBP_CommonButton"))
    local inner = nil
    if is_valid(button) then
        inner = unwrap(field(button, "WBP_PalInvisibleButton"))
    end
    local warning = unwrap(field(page, "Text_Warning"))
    local no_item = unwrap(field(page, "Image_NoItem"))
    local readings = {
        { "page.EnabledButton",         field(page, "EnabledButton") },
        { "button.bIsEnabled",          field(button, "bIsEnabled") },
        { "button.RenderOpacity",       field(button, "RenderOpacity") },
        { "button.Visibility",          field(button, "Visibility") },
        { "inner.bIsEnabled",           field(inner, "bIsEnabled") },
        { "inner.IsInteractionEnabled", method(inner, "IsInteractionEnabled") },
        { "Text_Warning.Visibility",    field(warning, "Visibility") },
        { "Image_NoItem.Visibility",    field(no_item, "Visibility") },
    }
    local parts = {}
    for _, reading in ipairs(readings) do
        parts[#parts + 1] = string.format("%s=%s", reading[1], tostring(unwrap(reading[2])))
    end
    log(string.format("BUTTON STATE [%s]: %s", label, table.concat(parts, " ")))
end

-- Writes EnabledButton and the interaction flag only when the pair is not
-- already in the wanted state, so a settled state costs no writes.
local function block_edit(widget)
    if unwrap(field(widget, "EnabledButton")) == false and edit_disabled_by_mod then
        return -- already blocked, and blocked by us: leave it alone
    end
    describe_button_state(widget, "before we block it")
    widget.EnabledButton = false
    set_edit_interactable(widget, false)
    edit_disabled_by_mod = true
    describe_button_state(widget, "after we block it")
end

-- Restores the interaction flag, and only if this module cleared it.
-- EnabledButton is not written back: Update Button State recomputes it.
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
    if target == nil then
        return false
    end
    local skill_ids = get_skill_ids(unwrap(page.CachedCharacter))
    if skill_ids == nil then
        return false
    end
    return count_id(skill_ids, target) > 0
end

-- Blocks or releases the Edit button for the recorded tab page.
--
-- Runs for whatever operation is pending, including none: the release branch has
-- to be reachable from every state, or a block made in one state outlives it.
--
-- Blocks when an extract mode is pending and the selected slot does not hold an
-- extractable passive -- selected_passive returns nil or "None" for an empty
-- slot, and is_extractable rejects both -- or when an alias is pending and
-- alias_target_already_present is true.
--
-- Takes no arguments so main.lua can hand it to ExecuteInGameThread by
-- reference; see the note on closure allocation in lp/hooks.lua.
local function enforce_extraction_gate()
    if SETTINGS.surgery_ui_gate == false then
        return
    end
    local page = current_page()
    if not is_valid(page) then
        return
    end

    local pending = name_to_string(field(page, "CurrentPassiveId"))
    local is_extraction = pending ~= nil and is_extract_mode(EXTRACTION_MODES[pending])
    local is_implant = pending ~= nil and EXTRACTION_MODES[pending] == "implant"

    local passive_id
    if is_extraction then
        passive_id = selected_passive(page)
    end

    local duplicate = is_implant and alias_target_already_present(page, pending)

    if (is_extraction and not is_extractable(passive_id)) or duplicate then
        block_edit(page)
    else
        -- The other half of the probe: EnabledButton false while this module is
        -- not the one blocking. The read stops once the label has fired.
        if not reported_button_states["vanilla disabled it"]
            and not edit_disabled_by_mod
            and unwrap(field(page, "EnabledButton")) == false
        then
            describe_button_state(page, "vanilla disabled it")
        end
        release_edit(page)
    end
end

--------------------------------------------------------------------------------
-- Panel repair
--------------------------------------------------------------------------------
--
-- This file does not write the passive cards. SetPassiveSkill and Clear on a
-- card are not called from anywhere; refresh_surgery_ui resets the panel
-- instead. See "Panel repaint: dead ends" in docs/PLAN.md.

-- Positive visibility, for the write path. The inverse of the rule in
-- visible_extraction_widget: a failed IsVisible call counts as not open.
local function is_open(widget)
    if not is_valid(widget) then
        return false
    end
    local visible_ok, visible = pcall(_call_is_visible, widget)
    return visible_ok and visible == true
end

-- The recorded widget if it is open, else nil. Does not scan for another.
local function open_recorded(widget)
    if widget ~= nil and is_open(widget) then
        return widget
    end
    return nil
end

-- Does the screen have a Pal selected? SetupPassiveChangeItem builds the
-- operation list from it, so the rebuild below is skipped when this is false.
local function has_selected_pal(screen)
    return is_valid(field(screen, "CurrentHandle"))
end

-- Set once, the first time a refresh finds no open page.
local closed_skip_reported = false

-- Resets the panel after a transaction. Returns true if it wrote anything.
--
-- reset_panel clears the operation chip and consume-item count; finish() passes
-- false for an implant, where that selection is not this mod's to clear.
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
        pcall(function() page.CachedPassiveSlotIndex = -1 end)
        pcall(function() page:UpdateCurrentConsumeItem(FName("None")) end)
        pcall(function() page["Set Passive Empty Item"](page) end)
        pcall(function() page:ReflectPassiveChange() end)
        pcall(function() page:RefreshCurrentPassiveItem() end)
    end

    if screen ~= nil then
        -- The screen holds its own copy of the consume item id and feeds it
        -- back to the page on refresh, so the page-level clear above is not
        -- sufficient on its own.
        if reset_panel then
            pcall(function() screen.CachedConsumeItemId = FName("None") end)
        end
        -- SetupPassiveChangeItem takes no arguments (WBP_OperatingTable.hpp:47).
        -- Entry validity is decided when each entry is created, which is why a
        -- module count only changes on a rebuild.
        if rebuild_list and has_selected_pal(screen) then
            pcall(function() screen:SetupPassiveChangeItem() end)
        end
        pcall(function() screen:RefreshItemDisplay() end)
    end

    return true
end

-- Armed by lp.transaction's finish, consumed by whichever of two paths reaches
-- it first: main.lua's OnPassiveUpdate hook, or finish's own timer. Consuming it
-- clears it, so the refresh runs once per arming.
local pending_refresh = nil

local function consume_pending_refresh()
    local pending = pending_refresh
    if pending == nil then
        return
    end
    pending_refresh = nil
    refresh_surgery_ui(pending.reset_panel, true)
end

-- Accessors, not an exported variable: three modules read or write
-- pending_refresh, and exporting it in the return table below would export its
-- value at load time -- a permanent nil for every consumer.
local function arm_refresh(reset_panel)
    pending_refresh = { reset_panel = reset_panel }
end

local function refresh_pending()
    return pending_refresh ~= nil
end

return {
    arm_refresh = arm_refresh,
    forget_live_widgets = forget_live_widgets,
    note_live_page = note_live_page,
    note_live_screen = note_live_screen,
    consume_pending_refresh = consume_pending_refresh,
    current_page = current_page,
    refresh_pending = refresh_pending,
    enforce_extraction_gate = enforce_extraction_gate,
    refresh_surgery_ui = refresh_surgery_ui,
    selected_passive = selected_passive,
    visible_extraction_widget = visible_extraction_widget,
}
