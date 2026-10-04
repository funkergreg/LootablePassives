-- Lootable Passives -- the things it is safe to change.
--
-- Passive ids, insertion routes and marker names are not here: they live in
-- lp/ids.lua, where each has to match a row in the PalSchema JSON exactly.
-- Prices are not here either and are not configurable.

return {
    -- Pal Disassembly Conveyor extraction: on or off.
    --
    -- False stops lp/conveyor.lua's hooks being registered at all. Read in one
    -- place, main.lua. The Surgery Table half does not read it.
    --
    -- A debt already on disk is still delivered with this off: the ledger loads
    -- itself, independently of this setting.
    conveyor_extraction = true,

    -- The Edit-button gate on the Surgery screen: on or off.
    --
    -- A KILL SWITCH, kept because this is the only part of the mod that writes
    -- to a UI widget while the player is looking at it, on a hook that fires
    -- for as long as the screen is open. If the Surgery screen ever misbehaves
    -- on someone's install, this is the first thing to turn off. False stops
    -- main.lua scheduling enforce_extraction_gate at all, which removes that
    -- writing without changing anything else: the tab page is still recorded, so
    -- extraction, insertion and the panel repaint are unaffected.
    --
    -- What is lost is the gate's refusal of a click that cannot succeed -- an
    -- empty slot, an unsupported passive, a duplicate insert. Each of those is
    -- checked again in lp/transaction.lua, which unwinds: a duplicate insert
    -- refunds the module, a bad extraction restores the passive. Neither
    -- refunds the operation's gold, which vanilla charges on confirm, before
    -- this mod runs.
    --
    -- The gate blocks the click; it does not change how the button looks. See
    -- the note on set_edit_interactable in lp/ui.lua.
    surgery_ui_gate = true,
}
