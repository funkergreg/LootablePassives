-- Lootable Passives -- the things it is safe to change.
--
-- Passive ids, insertion routes and marker names are not here: they live in
-- lp/ids.lua, where each has to match a row in the PalSchema JSON exactly.
-- Prices are not here either and are not configurable.
--
-- Read only through lp/config.lua, which reads this table on every use rather
-- than once at load, so a value changed while the game runs takes effect at the
-- point each entry below names. A value of the wrong type is logged once and
-- the default is used in its place. If this file fails to load, every entry
-- takes its default.

return {
    -- Debug mode: on or off. Default false.
    --
    -- tools/stage.ps1 writes this line: true for a dev build, false for a
    -- release, matching Info.json's DebugMode. True adds "DEBUG:" trace lines to
    -- UE4SS.log and arms debug_faults below. Read at every use.
    debug = false, -- stage:DebugMode

    -- Pal Disassembly Conveyor extraction: on or off. Default true.
    --
    -- False at load stops lp/conveyor.lua's hooks being registered. Turned true
    -- later, they are registered on the next map load. Turned false after they
    -- are registered, every firing returns at once and the Pals being tracked
    -- are forgotten, so none of them is paid for.
    --
    -- A debt already on disk is still delivered with this off: the ledger loads
    -- itself, independently of this setting.
    conveyor_extraction = true,

    -- The Edit-button gate on the Surgery screen: on or off. Default true.
    --
    -- A KILL SWITCH, kept because this is the only part of the mod that writes
    -- to a UI widget while the player is looking at it, on a hook that fires
    -- for as long as the screen is open. If the Surgery screen ever misbehaves
    -- on someone's install, this is the first thing to turn off. False stops
    -- main.lua scheduling enforce_extraction_gate at all, which removes that
    -- writing without changing anything else: the tab page is still recorded, so
    -- extraction, insertion and the panel repaint are unaffected. Turned false
    -- while the gate holds the button blocked, the button is released once.
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

    -- Injected failures for testing the recovery paths, as a list of
    -- scenarios. Each names the kind of Surgery exchange it waits for:
    --   on = "one"      Extract One
    --   on = "all"      Extract All
    --   on = "implant"  an implant from a disposable module
    -- and the next exchange of that kind takes the first unused scenario for
    -- it, so scenarios of different kinds can be run in any order. A scenario
    -- with no "on" is taken by an exchange of any kind. Each is used once per
    -- game start; an exchange of a kind with none left runs with no faults, and
    -- a vanilla operation never takes one. Ignored unless debug is true. Each
    -- fault logs a "DEBUG FAULT:" line when it fires.
    --
    -- Beside "on", a scenario holds any of these faults:
    --   fail_journal_write = "<row>"  that row's write fails without the file
    --                                 being opened, so the row before it stays
    --                                 on disk
    --   halt_after_journal = "<row>"  the exchange stops once that row is
    --                                 written, as if the game had crashed there
    --   fail_refund = true            an implant refund's direct grant fails,
    --                                 so the module is recorded as owed in the
    --                                 pending-grant ledger
    --   fail_resolve = true           every resolve attempt's result is
    --                                 discarded, so the exchange runs out of
    --                                 attempts and takes the stranded-marker
    --                                 path
    -- A row is named "<state>/<phase>" as lp/journal.lua writes it:
    -- "prepared/marker", "granted/marker", "prepared/loop", "granted/loop",
    -- "prepared/implant", "prepared/stranded".
    debug_faults = {},
}
