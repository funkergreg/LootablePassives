-- Offline test for lp/journal.lua: one row per Pal, and the migration of the
-- single-row format.
--
--   lua tools\journal_test.lua
--
-- Writes and removes LootablePassives_journal.tsv in the system temp directory
-- while it runs: util.UE4SS_ROOT is pointed there before lp.journal reads it, so
-- an aborted run leaves nothing under Scripts\ for a stage to ship.
local TEST_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local TOOLS_DIRECTORY = TEST_SOURCE:match("^(.*[\\/])") or "./"
package.path = TOOLS_DIRECTORY .. "../Scripts/?.lua;" .. package.path

local TEMP_DIRECTORY = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
require("lp.util").UE4SS_ROOT = TEMP_DIRECTORY:gsub("[\\/]?$", "/")

-- UE4SS's print adds no line break; the mod's log lines carry their own.
local LOGGED = {}
local real_print = print
print = function(message)
    LOGGED[#LOGGED + 1] = message
end

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        real_print(string.format("FAIL %-46s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        real_print(string.format("ok   %-46s %s", label, tostring(got)))
    end
end

local function read_file(path)
    local handle = io.open(path, "r")
    if handle == nil then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

local function write_file(path, text)
    local handle = assert(io.open(path, "w"))
    handle:write(text)
    handle:close()
end

local function line_count(text)
    return text and select(2, text:gsub("\n", "\n")) or 0
end

local journal = require("lp.journal")
local path = journal.JOURNAL_PATH
os.remove(path)

local PAL_A = "1-1-1-1"
local PAL_B = "2-2-2-2"

-- 1. Two Pals keep two rows; a write to one leaves the other alone.
check("empty journal reads no rows", #journal.read_journal(), 0)
check("write A", journal.write_journal(PAL_A, "prepared", "marker", "Stamina_Up_1",
    "LP_Implant_Stamina_Up_1", "LP_ExtractOne"), true)
check("write B", journal.write_journal(PAL_B, "prepared", "implant", "PAL_ALLAttack_up1",
    "LP_Implant_PAL_ALLAttack_up1", "LP_Insert_PAL_ALLAttack_up1"), true)
check("two rows on disk", line_count(read_file(path)), 2)
check("write A again", journal.write_journal(PAL_A, "granted", "marker", "Stamina_Up_1",
    "LP_Implant_Stamina_Up_1", "LP_ExtractOne"), true)
local rows = journal.read_journal()
check("still two rows", #rows, 2)
check("A first, in place", rows[1] and rows[1].key, PAL_A)
check("A advanced to granted", rows[1] and rows[1].state, "granted")
check("B untouched", rows[2] and rows[2].state, "prepared")
check("B's phase", rows[2] and rows[2].phase, "implant")
check("read_row B", journal.read_row(PAL_B) and journal.read_row(PAL_B).lock,
    "LP_Insert_PAL_ALLAttack_up1")
check("no temporary file left", read_file(path .. ".tmp"), nil)

-- 2. Clearing one Pal's row keeps the other; clearing the last removes the file.
journal.clear_journal(PAL_A)
check("A cleared", journal.read_row(PAL_A), nil)
check("B kept", journal.read_row(PAL_B) ~= nil, true)
journal.clear_journal(PAL_B)
check("file removed when empty", read_file(path), nil)

-- 3. A stranded row may name no passive.
check("stranded with no passive", journal.write_journal(PAL_A, "prepared", "stranded", nil, nil,
    "LP_ExtractAll"), true)
check("stranded row reads", journal.read_row(PAL_A) and journal.read_row(PAL_A).passive_id, nil)
journal.clear_journal(PAL_A)

-- 4. No key, no row.
check("nil key refused", journal.write_journal(nil, "prepared", "marker", "Stamina_Up_1",
    "LP_Implant_Stamina_Up_1", "LP_ExtractOne"), false)
check("nothing written for nil key", read_file(path), nil)

-- 5. A single-row file from the previous format is read as the legacy row and
--    rewritten in the current one.
write_file(path, "LPJ1\tgranted\tloop\tStamina_Up_1\tLP_Implant_Stamina_Up_1\tLP_ExtractAll\n")
rows = journal.read_journal()
check("legacy row read", #rows, 1)
check("legacy row key", rows[1] and rows[1].key, journal.LEGACY_KEY)
check("legacy row phase", rows[1] and rows[1].phase, "loop")
check("file migrated", (read_file(path) or ""):find("^LPJ2\tlegacy\tgranted\tloop\t") ~= nil, true)
check("legacy row coexists with a new one", journal.write_journal(PAL_B, "prepared", "marker",
    "Stamina_Up_1", "LP_Implant_Stamina_Up_1", "LP_ExtractOne"), true)
check("two rows after a new write", #journal.read_journal(), 2)
os.remove(path)

-- 6. An unusable line is dropped and logged; the usable rows around it stay.
write_file(path, table.concat({
    "LPJ2\t1-1-1-1\tprepared\tmarker\tStamina_Up_1\tLP_Implant_Stamina_Up_1\tLP_ExtractOne",
    "garbage",
    "LPJ2\t3-3-3-3\tprepared\tmarker\tStamina_Up_1\tLP_Implant_Wrong\tLP_ExtractOne",
    "LPJ9\t4-4-4-4\tprepared\tmarker\tStamina_Up_1\tLP_Implant_Stamina_Up_1\tLP_ExtractOne",
    "LPJ2\t2-2-2-2\tprepared\tmarker\tStamina_Up_1\tLP_Implant_Stamina_Up_1\t",
    "LPJ2\t5-5-5-5\tgranted\tmarker\tStamina_Up_1\tLP_Implant_Stamina_Up_1\tLP_ExtractOne",
    "",
}, "\n"))
LOGGED = {}
rows = journal.read_journal()
check("usable rows kept", #rows, 2)
check("first usable row", rows[1] and rows[1].key, PAL_A)
check("second usable row", rows[2] and rows[2].key, "5-5-5-5")
local warnings = 0
for _, line in ipairs(LOGGED) do
    if line:find("WARNING: discarded a recovery journal row", 1, true) then
        warnings = warnings + 1
    end
end
check("each unusable line warned", warnings, 4)
check("file rewritten to the usable rows", line_count(read_file(path)), 2)

-- 7. Two rows for one key: the later one wins.
write_file(path, table.concat({
    "LPJ2\t1-1-1-1\tprepared\tmarker\tStamina_Up_1\tLP_Implant_Stamina_Up_1\tLP_ExtractOne",
    "LPJ2\t1-1-1-1\tgranted\tmarker\tStamina_Up_1\tLP_Implant_Stamina_Up_1\tLP_ExtractOne",
    "",
}, "\n"))
rows = journal.read_journal()
check("duplicate key collapsed", #rows, 1)
check("later row wins", rows[1] and rows[1].state, "granted")
os.remove(path)

print = real_print
print(failures == 0 and "\nALL PASS" or string.format("\n%d FAILED", failures))
os.exit(failures == 0 and 0 or 1)
