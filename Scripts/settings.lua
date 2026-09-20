-- Lootable Passives -- the things it is safe to change.
--
-- Everything in this file can be edited without breaking the mod. That is the
-- entry requirement, and it is why the file is short.
--
-- The passive ids, insertion routes and marker names are NOT here. They live in
-- lp/ids.lua, because each one has to match a row in the PalSchema JSON exactly
-- and editing one produces a dead route rather than a different behaviour.
-- Prices are not here either, and are not configurable at all -- see below.

return {
    mod_name = "LootablePassives",

    -- Pal Disassembly Conveyor extraction: on or off.
    --
    -- A change-once variable, deliberately not a settings UI. Turning it off
    -- leaves the Surgery Table half untouched -- extraction and insertion there
    -- are unaffected -- and simply stops the conveyor granting modules for the
    -- Pals it consumes. Nothing else in the mod reads it.
    --
    -- The prices this mod sets are NOT configurable and are not going to be:
    -- they live in 171 rows across four PalSchema JSON files, which has no
    -- templating, and the generator that could have derived them from one value
    -- was deleted on purpose. See docs/PLAN.md if that looks like an oversight.
    conveyor_extraction = true,
}
