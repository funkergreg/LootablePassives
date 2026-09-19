-- Lootable Passives -- Which passive ids are ours, and what each one means.
--
-- EXTRACTION_MODES answers two questions with one table -- is this id ours, and
-- which operation is it. Splitting those two questions apart is worth doing,
-- but do it carefully: this set grew from 2 marker names to 56 entries, and
-- code that treated every member as a marker was once a near-miss for
-- stripping real passives off Pals.

local SETTINGS = require("settings")

-- Every passive this mod registers, mapped to what should happen when the
-- vanilla transaction installs it: "one" and "all" extract, "implant" inserts.
--
-- Kept as a flat name -> mode-string table because a great deal of code treats
-- EXTRACTION_MODES[id] purely as "is this one of ours?", and those call sites must
-- keep working unchanged. IMPLANT_TARGET carries the extra data for aliases.
local EXTRACTION_MODES = {}

-- Read directly rather than copied key-for-key into a second table: the copy
-- was identical to its source, so it bought nothing but a second name and 54
-- redundant inserts at load. Both call sites only ever read it.
local IMPLANT_TARGET = SETTINGS.implant_aliases or {}

for name, mode in pairs(SETTINGS.modes or {}) do
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
