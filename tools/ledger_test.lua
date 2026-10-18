-- Offline test for lp/ledger.lua: the on-disk format and who gets paid.
--
--   lua tools\ledger_test.lua
--
-- An automated test, but not a verifier for the JSON data.
-- It covers the part of the mod with no engine call in it:
-- owe/persist/load and ordered_for. lp.inventory is stubbed, so the assertions
-- are about which candidate was chosen, never about an item existing.
--
-- Writes and removes LootablePassives_pending.tsv in the system temp directory
-- while it runs: util.UE4SS_ROOT is pointed there before lp.ledger reads it, so
-- an aborted run leaves nothing under Scripts\ for a stage to ship.
local TEST_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local TOOLS_DIRECTORY = TEST_SOURCE:match("^(.*[\\/])") or "./"
package.path = TOOLS_DIRECTORY .. "../Scripts/?.lua;" .. package.path

local TEMP_DIRECTORY = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
require("lp.util").UE4SS_ROOT = TEMP_DIRECTORY:gsub("[\\/]?$", "/")

-- Stub the engine-facing half. require caches by module name, so seeding
-- package.loaded is enough for ledger.lua's own require to pick these up.
package.loaded["lp.inventory"] = {
    delivery_candidates = function() return CANDIDATES or {} end,
    add_modules = function(data, item_id, count)
        GRANTS[#GRANTS + 1] = { who = data.name, item_id = item_id, count = count }
        return true, nil
    end,
}

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-46s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        print(string.format("ok   %-46s %s", label, tostring(got)))
    end
end

local function read_file(path)
    local handle = io.open(path, "r")
    if handle == nil then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

local function fresh_ledger()
    package.loaded["lp.ledger"] = nil
    return require("lp.ledger")
end

local ALICE = "1-2-3-4"
local BOB = "5-6-7-8"

GRANTS = {}
CANDIDATES = {}

-- 1. owe writes an LPL2 row per owner per item, and reloads to the same totals.
--
-- owe takes ONE PAL'S WORTH of item ids, so a repeated id in the list is a
-- repeated debt and the whole list costs a single file write.
-- The ledger loads lazily, so removing the file after require is still a clean
-- start.
local ledger = fresh_ledger()
local path = ledger.LEDGER_PATH
os.remove(path)
ledger.owe(ALICE, { "LP_Implant_Stamina_Up_1", "LP_Implant_Stamina_Up_1" })
ledger.owe(ALICE, { "LP_Implant_Stamina_Up_1" })
ledger.owe(BOB, { "LP_Implant_Rare" })
ledger.owe(nil, { "LP_Implant_Legend", "LP_Implant_Legend",
    "LP_Implant_Legend", "LP_Implant_Legend" })
check("total owed in memory", ledger.total_owed(), 8)

local text = read_file(path)
check("row count on disk", select(2, text:gsub("\n", "\n")), 3)
check("alice row present",
    text:find("LPL2\t1%-2%-3%-4\tLP_Implant_Stamina_Up_1\t3") ~= nil, true)
check("unowned row uses the lock",
    text:find("LPL2\t%*\tLP_Implant_Legend\t4") ~= nil, true)

-- Loading is LAZY and no longer a public step: nothing is read off disk until
-- something asks, and every public reader asks.
ledger = fresh_ledger()
check("total owed after reload", ledger.total_owed(), 8)

-- 2. A row with a known owner goes to that owner and to nobody else. An
-- unowned row has no owner to match, so with two players online it is held.
GRANTS = {}
CANDIDATES = {
    { data = { name = "host" },  uid = BOB },
    { data = { name = "alice" }, uid = ALICE },
}
local delivered, owed, spilled, held = ledger.flush()
check("delivered the owned rows", delivered, 4)
check("unowned row still owed", owed, 4)
check("nothing spilled", spilled, 0)
check("unowned row held", held, 4)
local by_item = {}
for _, grant in ipairs(GRANTS) do by_item[grant.item_id] = grant.who end
check("alice's modules went to alice", by_item["LP_Implant_Stamina_Up_1"], "alice")
check("bob's modules went to the host", by_item["LP_Implant_Rare"], "host")
check("unowned modules went to nobody", by_item["LP_Implant_Legend"], nil)
check("file rewritten to the undelivered row only", read_file(path),
    "LPL2\t*\tLP_Implant_Legend\t4\n")

-- ...and goes to the one player once only one is online.
GRANTS = {}
CANDIDATES = { { data = { name = "host" }, uid = BOB } }
delivered = ledger.flush()
check("unowned row, lone player: delivered", delivered, 4)
check("unowned row, lone player: recipient", GRANTS[1] and GRANTS[1].who, "host")
check("ledger file removed when empty", read_file(path), nil)

-- 3. An owner who is not online has the row HELD, not paid to someone else.
ledger = fresh_ledger()
ledger.owe(ALICE, { "LP_Implant_Rare", "LP_Implant_Rare", "LP_Implant_Rare" })
GRANTS = {}
CANDIDATES = { { data = { name = "host" }, uid = BOB } }
delivered, owed, spilled, held = ledger.flush()
check("held for an absent owner: delivered", delivered, 0)
check("held for an absent owner: still owed", owed, 3)
check("held for an absent owner: held count", held, 3)
check("held for an absent owner: no grants", #GRANTS, 0)

-- ...and is delivered once that owner turns up.
CANDIDATES = {
    { data = { name = "host" },  uid = BOB },
    { data = { name = "alice" }, uid = ALICE },
}
delivered, owed, spilled, held = ledger.flush()
check("owner returns: delivered", delivered, 3)
check("owner returns: recipient", GRANTS[1] and GRANTS[1].who, "alice")

-- 4. No readable uid anywhere: the row cannot be matched, so it is held while
-- two players are online and goes to the one player otherwise.
ledger = fresh_ledger()
ledger.owe(ALICE, { "LP_Implant_Rare" })
GRANTS = {}
CANDIDATES = {
    { data = { name = "host" },  uid = nil },
    { data = { name = "alice" }, uid = nil },
}
delivered, owed, spilled, held = ledger.flush()
check("unreadable uid, two players: delivered", delivered, 0)
check("unreadable uid, two players: still owed", owed, 1)
check("unreadable uid, two players: nothing spilled", spilled, 0)
check("unreadable uid, two players: held", held, 1)
CANDIDATES = { { data = { name = "host" }, uid = nil } }
delivered = ledger.flush()
check("unreadable uid, lone player: delivered", delivered, 1)
check("unreadable uid, lone player: recipient", GRANTS[1] and GRANTS[1].who, "host")
os.remove(path)

print(failures == 0 and "\nALL PASS" or string.format("\n%d FAILURE(S)", failures))
os.exit(failures == 0 and 0 or 1)
