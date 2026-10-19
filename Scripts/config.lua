-- Lootable Passives settings.
--
-- Edit this file with the game or the dedicated server stopped; the change
-- applies at the next start. Better Mod Manager, when installed, changes these
-- while the game runs and saves each change into this file too.
--
-- A mod update replaces this file and restores the defaults below. Settings
-- changed through Better Mod Manager are kept across updates.
return {
    -- Extract One, Extract All and every implant this mod adds to the Pal
    -- Surgery Table. Set by the host in multiplayer. Default true.
    surgery_extraction = true,

    -- Pals fed to the Disassembly Conveyor also yield implants of their
    -- passives. Set by the host in multiplayer. Default true.
    conveyor_extraction = true,

    -- Blocks the Surgery Edit button when the operation cannot work. Turn off
    -- if the Surgery screen misbehaves. Default true.
    surgery_ui_gate = true,

    -- Adds DEBUG trace lines to UE4SS.log. Leave off unless reporting a bug.
    -- Default false.
    debug = true, -- stage:DebugMode

    -- Unlocks the host tool below. Default false.
    experimental_features = false,

    -- Host only, and only while experimental_features is true: removes every
    -- Lootable Passives implant from the inventories and chests loaded in the
    -- world when the world is entered, then sets itself back to false. Pals
    -- keep their passives. Default false.
    remove_mod_items = false,
}
