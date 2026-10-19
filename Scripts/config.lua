-- Lootable Passives settings.
--
-- Edit with the game or the dedicated server stopped; a change applies at the
-- next start. Better Mod Manager, when installed, changes these while the game
-- runs and saves each change here too.
--
-- A mod update replaces this file with the defaults below. Changes made in
-- Better Mod Manager are kept across updates.
return {
    -- Extract One, Extract All and this mod's implants at the Pal Surgery
    -- Table. Set by the host in multiplayer. Default true.
    surgery_extraction = true,

    -- Pals fed to the Disassembly Conveyor also yield implants of their
    -- passives. Set by the host in multiplayer. Default true.
    conveyor_extraction = true,

    -- Blocks the Surgery Edit button when the operation cannot work. Turn off
    -- if the Surgery screen misbehaves. Default true.
    surgery_ui_gate = true,

    -- Adds DEBUG lines to UE4SS.log. Leave off unless reporting a bug.
    -- Default false.
    debug = false, -- stage:DebugMode

    -- Unlocks remove_mod_items below. Default false.
    advanced_features = false,

    -- WARNING: destructive. Required before uninstalling this mod. Host only,
    -- and only while advanced_features is true: removes every Lootable
    -- Passives implant from the inventories and chests loaded in the world,
    -- which takes about 25 seconds, shows the count in a game notice, then
    -- sets itself back to false. Pals keep their passives. Default false.
    remove_mod_items = false,
}
