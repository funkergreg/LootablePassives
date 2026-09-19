-- Lootable Passives -- The Surgery widget: access, the Edit gate, and panel repair.
--
-- UI state is never a safety mechanism. Gating the Edit button is a courtesy;
-- every rule it enforces is also enforced at the transaction, because the click
-- can get through. Never write the passive cards directly -- reset the panel.
--
-- This module must NOT require lp.transaction. transaction reaches in here (for
-- the widget reads and the repaint) and the one-directional edge is what keeps
-- the two from becoming a cycle.

local util = require("lp.util")
local ids = require("lp.ids")
local passives = require("lp.passives")

-- Localised so the function bodies below are byte-identical to what they
-- were in main.lua: this split is code motion, not a rewrite.
local _call_is_visible = util._call_is_visible
local is_valid = util.is_valid
local name_to_string = util.name_to_string
local unwrap = util.unwrap
local IMPLANT_TARGET = ids.IMPLANT_TARGET
local EXTRACTION_MODES = ids.EXTRACTION_MODES
local is_extract_mode = ids.is_extract_mode
local count_id = passives.count_id
local get_skill_ids = passives.get_skill_ids
local is_extractable = passives.is_extractable

local SURGERY_TAB_CLASS = "WBP_OperatingTable_TabPage_C"
local SURGERY_SCREEN_CLASS = "WBP_OperatingTable_C"

local PASSIVE_CARD_PROPERTIES = {
    "WBP_MainMenu_Pal_Skill_Passive",
    "WBP_MainMenu_Pal_Skill_Passive_1",
    "WBP_MainMenu_Pal_Skill_Passive_2",
    "WBP_MainMenu_Pal_Skill_Passive_3",
}


--------------------------------------------------------------------------------
-- Surgery widget access
--------------------------------------------------------------------------------

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

-- Returns the visible Surgery tab page whose pending operation is one of our
-- markers, plus that marker's name.
-- The one visible-tab-page scan, shared by both callers below.
--
-- require_marker restricts the result to a page whose pending operation is one
-- of ours, and additionally returns which one. Both variants were written out
-- separately before, which meant three copies of the load-bearing and
-- distinctly non-obvious rule on the next line: a FAILED IsVisible call counts
-- as visible. Getting that wrong in one copy and not the other is a silent
-- divergence, so it is stated once.
local function find_visible_tab_page(require_marker)
    local succeeded, widgets = pcall(function()
        return FindAllOf(SURGERY_TAB_CLASS)
    end)
    if not succeeded or widgets == nil then
        return nil, nil
    end
    for _, widget in ipairs(widgets) do
        if is_valid(widget) then
            local visible_ok, visible = pcall(_call_is_visible, widget)
            if not visible_ok or visible then
                if not require_marker then
                    return widget, nil
                end
                local pending = name_to_string(widget.CurrentPassiveId)
                if pending ~= nil and EXTRACTION_MODES[pending] ~= nil then
                    return widget, pending
                end
            end
        end
    end
    return nil, nil
end

-- A visible Surgery tab page with one of our operations pending.
local function visible_extraction_widget()
    return find_visible_tab_page(true)
end

-- Blocking the Edit button.
local edit_disabled_by_mod = false

local function set_edit_interactable(widget, enabled)
    local button = unwrap(widget.WBP_CommonButton)
    if not is_valid(button) then
        return
    end
    local inner = unwrap(button.WBP_PalInvisibleButton)
    if is_valid(inner) then
        pcall(function() inner:SetIsInteractionEnabled(enabled) end)
    end
    -- SetIsEnabled(false) on the outer WBP_CommonButton_C is NOT used. It works
    -- -- the 04:57 log shows it succeeding -- but it renders the button as a
    -- white cut-out rather than the game's normal greyed-out state, because a
    -- UUserWidget's disabled appearance is not styled for this widget. Blocking
    -- input on the inner CommonButtonBase is enough to stop the click, and
    -- EnabledButton = false is what the game itself uses to show the greyed look.
end

-- Both of these write only when the state is not already what is wanted.
--
-- The flicker came from writing unconditionally on every gate pass: the game
-- set the button enabled, the mod set it disabled, the game set it enabled
-- again. Reading EnabledButton first means at most one write per genuine change
-- by the game, and no writes at all once the state has settled.
local function block_edit(widget)
    local current
    local read_ok = pcall(function() current = unwrap(widget.EnabledButton) end)
    if read_ok and current == false and edit_disabled_by_mod then
        return -- already blocked, and blocked by us: leave it alone
    end
    widget.EnabledButton = false
    set_edit_interactable(widget, false)
    edit_disabled_by_mod = true
end

local function release_edit(widget)
    if not edit_disabled_by_mod then
        return -- never touched it, so there is nothing to undo
    end
    edit_disabled_by_mod = false
    set_edit_interactable(widget, true)
end

-- Both operations require the SELECTED slot to hold an extractable passive.
--
-- An EMPTY slot must be rejected. Vanilla enables Edit for one because the
-- normal operation ADDS a passive, but there is nothing there to extract, and
-- confirming it appends the marker instead of swapping it. selected_passive
-- returns nil or "None" for an empty slot and is_extractable rejects both.
-- Any visible Surgery tab page, regardless of which operation is pending.
local function visible_tab_page()
    local widget = find_visible_tab_page(false)
    return widget
end

-- Vanilla will not implant a passive a Pal already carries: it compares the
-- chosen passive id against the Pal's list and refuses on a match.
--
-- An implant alias has a DIFFERENT id from the passive it installs, so that
-- comparison stopped matching and the duplicate check quietly ceased to apply.
-- Screenshot 118 is the result: a Pal holding Infinite Stamina twice. Re-impose
-- the check against the TARGET passive, which is what will actually be on the
-- Pal once the swap completes.
local function alias_target_already_present(page, pending)
    local target = IMPLANT_TARGET[pending]
    if target == nil then
        return false
    end
    local ids = get_skill_ids(unwrap(page.CachedCharacter))
    if ids == nil then
        return false
    end
    return count_id(ids, target) > 0
end

-- Finds ANY visible tab page, not only one with a marker pending.
--
-- The earlier version bailed out unless one of our markers was selected, so
-- once it had disabled the button, switching to a normal insert operation left
-- the gate inert and the button disabled forever. Release has to be reachable
-- from every state the player can switch into, not just from ours.
local function enforce_extraction_gate()
    local page = visible_tab_page()
    if not is_valid(page) then
        return
    end

    local pending
    pcall(function() pending = name_to_string(page.CurrentPassiveId) end)
    -- Only the two EXTRACT operations are gated. An implant alias is left alone:
    -- inserting into an empty slot is exactly what it is for, so blocking on
    -- "nothing extractable selected" would make it unusable.
    local is_extraction = pending ~= nil and is_extract_mode(EXTRACTION_MODES[pending])
    local is_implant = pending ~= nil and EXTRACTION_MODES[pending] == "implant"

    local passive_id
    if is_extraction then
        passive_id = selected_passive(page)
    end

    -- Only consulted while one of our implant aliases is pending, so this costs
    -- nothing during normal play.
    local duplicate = is_implant and alias_target_already_present(page, pending)

    if (is_extraction and not is_extractable(passive_id)) or duplicate then
        block_edit(page)
    else
        release_edit(page)
    end
end

--------------------------------------------------------------------------------
-- Extraction
--------------------------------------------------------------------------------

-- Repainting the passive slots after an exchange.
--
-- Three panel-level approaches were tried and measured, not guessed at:
--   ReflectPassiveChange / RefreshCurrentPassiveItem / RefreshItemDisplay
--       ran in the 03:53 session and did not repaint the slots.
--   "On Click Pal List" with the screen's own CurrentHandle reported
--       reselect=true in the 04:50 session -- it genuinely executed -- and the
--       stale label still stayed. Re-selecting the Pal already selected is
--       evidently a no-op inside the Blueprint, which is why clicking to a
--       DIFFERENT Pal and back is what works by hand.
--
--   Writing the cards directly with SetPassiveSkill / Clear was tried next and
--       was WORSE. The calls succeeded -- the 22:03 session reported
--       "cleared=4 failed=0" -- but Clear() leaves a card blank rather than
--       showing the empty "+" slot, and the cards are reused across Pal
--       selections, so every Pal afterwards displayed an empty panel even when
--       it plainly had four passives. The empty state is its own visual, hinted
--       at by the card's Anm_EmptySlot_HideToShow animation, and Clear() does
--       not reach it. "The calls succeeded" is not the same as "the result was
--       correct", and that distinction cost a test cycle.
--
-- What is left is the one thing not yet tried: stop repainting at all and
-- RESET THE PANEL instead, which is what the vanilla flow does anyway once an
-- operation has been consumed. See the body below.
--
-- Worth keeping in mind: BindedPassiveSkillName was already correct while
-- Text_SkillName was stale, so the card data agreed with reality the whole time
-- and only the paint was wrong. Never diagnose staleness from the bound value.

-- rebuild_list rebuilds the operation list from scratch. That is reserved for
-- the LAST pass of the refresh ladder: it destroys and recreates all 118 entry
-- widgets, so doing it while the player may still be moving the cursor over one
-- of them is asking for a destroyed-widget access.
local function refresh_surgery_ui(reset_panel, rebuild_list)
    -- The operation chip is reset ONLY for our own marker operations. An
    -- implant is a vanilla insert and vanilla owns that state; see finish().
    local pages
    if reset_panel then
        local pages_ok
        pages_ok, pages = pcall(function()
            return FindAllOf(SURGERY_TAB_CLASS)
        end)
        if not pages_ok then
            pages = nil
        end
    end

    for _, page in ipairs(pages or {}) do
        if is_valid(page) then
            -- Deselect, then return the operation chip to its empty state.
            --
            -- CachedPassiveSlotIndex = -1 is what the panel treats as "nothing
            -- chosen". "Set Passive Empty Item" is the widget's own reset for the
            -- chip, arity checked at WBP_OperatingTable_TabPage.hpp:80 (no args);
            -- the name contains spaces so it must be indexed, not dotted.
            --
            -- The end state is deliberately the same one you get immediately
            -- after clicking a Pal: chip back to "+", nothing selected, Edit
            -- greyed. The operation has been consumed, so leaving it selected was
            -- what produced a stale label over a slot that was already empty,
            -- and an Edit button whose verdict kept flipping.
            pcall(function() page.CachedPassiveSlotIndex = -1 end)
            -- Clear the CONSUME ITEM as well as the chip.
            --
            -- "Set Passive Empty Item" restores the "+" graphic but leaves
            -- BP_PalTextBlock_Num showing the stock count of whatever was last
            -- selected. That is the stray "(2)" in the corner of an empty slot
            -- in screenshot 113: not a selection artefact but a leftover
            -- quantity readout, still counting modules the player no longer has
            -- selected. UpdateCurrentConsumeItem takes one FName and has no
            -- output parameter (WBP_OperatingTable_TabPage.hpp:92).
            pcall(function() page:UpdateCurrentConsumeItem(FName("None")) end)
            pcall(function() page["Set Passive Empty Item"](page) end)
            pcall(function() page:ReflectPassiveChange() end)
            pcall(function() page:RefreshCurrentPassiveItem() end)
        end
    end

    local screens_ok, screens = pcall(function()
        return FindAllOf(SURGERY_SCREEN_CLASS)
    end)
    if screens_ok and screens ~= nil then
        for _, screen in ipairs(screens) do
            if is_valid(screen) then
                -- The screen caches the last consume item id and feeds it back
                -- to the panel on refresh, so clearing it on the page alone is
                -- not enough -- the quantity comes straight back.
                if reset_panel then
                    pcall(function() screen.CachedConsumeItemId = FName("None") end)
                end
                -- Rebuild the operation list.
                --
                -- Entries are created with a validity flag returned by
                -- Setup(PassiveId, IsValid&), and a module route is only valid
                -- while the player holds a module. The list is built once when
                -- the panel opens, which is exactly why an entry for a module
                -- you just spent your last copy of lingers until you close the
                -- panel (screenshot 115). SetupPassiveChangeItem takes no
                -- arguments (WBP_OperatingTable.hpp:47).
                if rebuild_list then
                    pcall(function() screen:SetupPassiveChangeItem() end)
                end
                pcall(function() screen:RefreshItemDisplay() end)
            end
        end
    end

end

-- Set when a transaction completes and the panel has not yet been refreshed for
-- it. reset_panel records whether the operation chip itself should be cleared:
-- true for our own markers, false for an implant, where vanilla owns that state.
--
-- Whichever mechanism reaches it first consumes it, so the refresh runs exactly
-- once -- the OnPassiveUpdate hook normally, the timer in finish() if that hook
-- never fires.
--
-- This used to be a bare "panel reset pending" boolean, which was only ever set
-- for extractions. That made the hook return early for every implant, leaving
-- implants on the timers alone -- the two-to-three second lag, while extraction
-- felt immediate. Both paths now ride the same event.
local pending_refresh = nil

local function consume_pending_refresh()
    local pending = pending_refresh
    if pending == nil then
        return
    end
    pending_refresh = nil
    -- rebuild_list is always true here. It used to be held back to the last
    -- timer pass out of caution about destroying a hovered entry widget, but on
    -- the event it lands right after the click, while the cursor is still on the
    -- Edit button -- strictly safer than doing it a second later, and it is what
    -- makes the module count and the spent-module row update immediately.
    refresh_surgery_ui(pending.reset_panel, true)
end

-- ACCESSORS, not an exported variable.
--
-- pending_refresh is written by lp.transaction (in finish), read and cleared
-- here, and read by main.lua's OnPassiveUpdate hook -- three modules, one
-- mutable. Exporting it in this module's return table would export the VALUE at
-- load time, so every consumer would hold a permanent nil and the event path
-- would silently never fire. These two functions are what keep the variable in
-- one place while the split leaves three readers.
--
-- Whichever mechanism reaches consume_pending_refresh first wins; the others
-- then find nil and do nothing. That is the consume-once contract the event and
-- its timer fallback both rely on.
local function arm_refresh(reset_panel)
    pending_refresh = { reset_panel = reset_panel }
end

local function refresh_pending()
    return pending_refresh ~= nil
end

return {
    arm_refresh = arm_refresh,
    consume_pending_refresh = consume_pending_refresh,
    refresh_pending = refresh_pending,
    enforce_extraction_gate = enforce_extraction_gate,
    refresh_surgery_ui = refresh_surgery_ui,
    selected_passive = selected_passive,
    visible_extraction_widget = visible_extraction_widget,
    visible_tab_page = visible_tab_page,
}
