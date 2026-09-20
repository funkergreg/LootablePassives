-- Lootable Passives -- Which passive ids are ours, and what each one means.
--
-- EXTRACTION_MODES answers two questions with one table -- is this id ours, and
-- which operation is it. Splitting those two questions apart is worth doing,
-- but do it carefully: this set grew from 2 marker names to 56 entries, and
-- code that treated every member as a marker was once a near-miss for
-- stripping real passives off Pals.

-- These two tables live HERE, not in settings.lua, because they are not
-- settings. Every key has to match a row in the PalSchema JSON exactly: a
-- changed name does not configure anything, it produces a dead list entry or
-- an inert alias left on a Pal. settings.lua is for what a player may safely
-- change, and neither of these is that.

-- Marker passives, one per operation. The vanilla Surgery transaction swaps
-- the player's chosen passive for one of these; which marker appears is how
-- the runtime knows which operation was requested.
local MODES = {
    LP_ExtractOne = "one",
    LP_ExtractAll = "all",
}

-- Disposable-implant insertion routes: alias passive -> the real passive.
-- The list resolves each entry by ROW NAME, so a second row is given its own
-- name and registered as a real passive in DT_PassiveSkill_Main with its own
-- name/description text. Selecting it makes the vanilla transaction install
-- the ALIAS, and the same swap already used by Extract One / Extract All then
-- replaces the alias with the real passive.
--
-- All 54 of them: exactly the passives whose only operating-table row is
-- the vanilla recipe one. The other 61 need no alias, because their row is
-- already keyed on the real passive id and so renders with the right name
-- and rank already.
--
-- Rank shown in each comment is the target passive's own rank, and matches
-- the Rank on that route's row. These keys must stay in step with the rows
-- in PalSchema's LootablePassivesInsertRoutes.json -- a key here with no
-- row is a dead operation, and a row with no key here installs an inert
-- alias and leaves it on the Pal. Nothing checks that at build time any
-- more; the insert-route count in the startup log line is what reports it.
local IMPLANT_TARGET = {
    LP_Insert_SwimSpeed_up_2 = "SwimSpeed_up_2",                               -- Ace Swimmer (rank +3)
    LP_Insert_CraftSpeed_up2 = "CraftSpeed_up2",                               -- Artisan (rank +3)
    LP_Insert_MutationPal_Babysitter = "MutationPal_Babysitter",               -- Babysitter (rank +4)
    LP_Insert_PAL_ALLAttack_up1 = "PAL_ALLAttack_up1",                         -- Brave (rank +1)
    LP_Insert_Deffence_up2 = "Deffence_up2",                                   -- Burly Body (rank +3)
    LP_Insert_PAL_FullStomach_Down_1 = "PAL_FullStomach_Down_1",               -- Dainty Eater (rank +1)
    LP_Insert_PAL_ALLAttack_up3 = "PAL_ALLAttack_up3",                         -- Demon God (rank +4)
    LP_Insert_WorldTree_CraftSpeed = "WorldTree_CraftSpeed",                   -- Demon's Hand (rank +5)
    LP_Insert_Deffence_up3 = "Deffence_up3",                                   -- Diamond Body (rank +4)
    LP_Insert_PAL_FullStomach_Down_2 = "PAL_FullStomach_Down_2",               -- Diet Lover (rank +3)
    LP_Insert_WorldTree_MoveSpeed = "WorldTree_MoveSpeed",                     -- Dimensional Leap (rank +5)
    LP_Insert_Stamina_Up_3 = "Stamina_Up_3",                                   -- Eternal Engine (rank +4)
    LP_Insert_PAL_ALLAttack_up2 = "PAL_ALLAttack_up2",                         -- Ferocious (rank +3)
    LP_Insert_SalePrice_Up_2 = "SalePrice_Up_2",                               -- Fine Furs (rank +1)
    LP_Insert_Stamina_Up_2 = "Stamina_Up_2",                                   -- Fit as a Fiddle (rank +1)
    LP_Insert_WorldTree_ATK_DEF = "WorldTree_ATK_DEF",                         -- God of Destruction (rank +5)
    LP_Insert_Deffence_up1 = "Deffence_up1",                                   -- Hard Skin (rank +1)
    LP_Insert_AutoHPRegeneRate_Passive = "AutoHPRegeneRate_Passive",           -- Healing Coach (rank +3)
    LP_Insert_PAL_Sanity_Down_3 = "PAL_Sanity_Down_3",                         -- Heart of the Immovable King (rank +4)
    LP_Insert_MutationPal_ExplosionResist = "MutationPal_ExplosionResist",     -- Heavily Armored (rank +4)
    LP_Insert_WorldTree_Sanity = "WorldTree_Sanity",                           -- Hermit Sage (rank +5)
    LP_Insert_MutationPal_Mutant = "MutationPal_Mutant",                       -- Idiosyncratic (rank +4)
    LP_Insert_MutationPal_Immortal = "MutationPal_Immortal",                   -- Immortality (rank +4)
    LP_Insert_CoolTimeReduction_Up_2 = "CoolTimeReduction_Up_2",               -- Impatient (rank +1)
    LP_Insert_Stamina_Up_1 = "Stamina_Up_1",                                   -- Infinite Stamina (rank +3)
    LP_Insert_Nocturnal = "Nocturnal",                                         -- Insomnia (rank +1)
    LP_Insert_SwimSpeed_up_3 = "SwimSpeed_up_3",                               -- King of the Waves (rank +4)
    LP_Insert_TrainerLogging_up1 = "TrainerLogging_up1",                       -- Logging Foreman (rank +3)
    LP_Insert_PAL_FullStomach_Down_3 = "PAL_FullStomach_Down_3",               -- Mastery of Fasting (rank +4)
    LP_Insert_NonKilling = "NonKilling",                                       -- Mercy Hit (rank -1)
    LP_Insert_TrainerMining_up1 = "TrainerMining_up1",                         -- Mine Foreman (rank +3)
    LP_Insert_TrainerWorkSpeed_UP_1 = "TrainerWorkSpeed_UP_1",                 -- Motivational Leader (rank +3)
    LP_Insert_Noukin = "Noukin",                                               -- Musclehead (rank +2)
    LP_Insert_MoveSpeed_up_1 = "MoveSpeed_up_1",                               -- Nimble (rank +1)
    LP_Insert_SalePrice_Up_1 = "SalePrice_Up_1",                               -- Noble (rank +3)
    LP_Insert_Test_PalEgg_HatchingSpeed_Up = "Test_PalEgg_HatchingSpeed_Up",   -- Philanthropist (rank +3)
    LP_Insert_PAL_Sanity_Down_1 = "PAL_Sanity_Down_1",                         -- Positive Thinker (rank +1)
    LP_Insert_ReloadSpeedUp_Passive = "ReloadSpeedUp_Passive",                 -- Reload Master (rank +3)
    LP_Insert_CraftSpeed_up3 = "CraftSpeed_up3",                               -- Remarkable Craftsmanship (rank +4)
    LP_Insert_MoveSpeed_up_2 = "MoveSpeed_up_2",                               -- Runner (rank +3)
    LP_Insert_WorldTree_DEF = "WorldTree_DEF",                                 -- Sanctified Meat Shield (rank +5)
    LP_Insert_CoolTimeReduction_Up_1 = "CoolTimeReduction_Up_1",               -- Serenity (rank +3)
    LP_Insert_CraftSpeed_up1 = "CraftSpeed_up1",                               -- Serious (rank +1)
    LP_Insert_RideJumpCount_Increase2 = "RideJumpCount_Increase2",             -- Sky Strider (rank +4)
    LP_Insert_SwimSpeed_up_1 = "SwimSpeed_up_1",                               -- Sleek Stroke (rank +1)
    LP_Insert_TrainerDEF_UP_1 = "TrainerDEF_UP_1",                             -- Stronghold Strategist (rank +3)
    LP_Insert_MoveSpeed_up_3 = "MoveSpeed_up_3",                               -- Swift (rank +4)
    LP_Insert_WorldTree_ATK = "WorldTree_ATK",                                 -- Twin-Edged Holy Blade (rank +5)
    LP_Insert_Vampire = "Vampire",                                             -- Vampiric (rank +4)
    LP_Insert_TrainerATK_UP_1 = "TrainerATK_UP_1",                             -- Vanguard (rank +3)
    LP_Insert_PlayerSP_DecreaseRate_Passive = "PlayerSP_DecreaseRate_Passive", -- Wellness Watcher (rank +3)
    LP_Insert_PAL_CorporateSlave = "PAL_CorporateSlave",                       -- Work Slave (rank +1)
    LP_Insert_PAL_Sanity_Down_2 = "PAL_Sanity_Down_2",                         -- Workaholic (rank +3)
    LP_Insert_WorldTree_FullStomach = "WorldTree_FullStomach",                 -- World Tree's Bounty (rank +5)
}

-- Every passive this mod registers, mapped to what should happen when the
-- vanilla transaction installs it: "one" and "all" extract, "implant" inserts.
--
-- Kept as a flat name -> mode-string table because a great deal of code treats
-- EXTRACTION_MODES[id] purely as "is this one of ours?", and those call sites
-- must keep working unchanged. IMPLANT_TARGET carries the extra alias data.
local EXTRACTION_MODES = {}

for name, mode in pairs(MODES) do
    EXTRACTION_MODES[name] = mode
end
for alias in pairs(IMPLANT_TARGET) do
    EXTRACTION_MODES[alias] = "implant"
end

-- True for the two extraction operations only. The empty-slot rule differs by
-- kind: extracting from an empty slot is meaningless and must be blocked, while
-- implanting INTO an empty slot is the normal, correct case.
local function is_extract_mode(mode)
    return mode == "one" or mode == "all"
end

return {
    IMPLANT_TARGET = IMPLANT_TARGET,
    EXTRACTION_MODES = EXTRACTION_MODES,
    is_extract_mode = is_extract_mode,
}
