-- Offline test for lp/transaction.lua's resolve: which Pal an exchange in
-- flight is matched to when several are in flight at once.
--
--   lua tools\exchange_test.lua
--
-- Pals are Lua tables. The engine-facing reads are stubbed: lp.inventory
-- entirely, and in lp.passives the three reads of a Pal (get_skill_ids,
-- pal_key, owner_key). The detectors and the claim bookkeeping are the real
-- code. Nothing is written to disk.
local TEST_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local TOOLS_DIRECTORY = TEST_SOURCE:match("^(.*[\\/])") or "./"
package.path = TOOLS_DIRECTORY .. "../Scripts/?.lua;" .. package.path

local TEMP_DIRECTORY = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
require("lp.util").UE4SS_ROOT = TEMP_DIRECTORY:gsub("[\\/]?$", "/")

-- The game-thread scheduler. Delayed work is collected, not run, so a claim's
-- release happens only when the test calls run_scheduled.
local SCHEDULED = {}
function ExecuteInGameThreadWithDelay(_, fn)
    SCHEDULED[#SCHEDULED + 1] = fn
end
local function run_scheduled()
    local pending = SCHEDULED
    SCHEDULED = {}
    for _, fn in ipairs(pending) do
        fn()
    end
end

local real_print = print
print = function() end

-- request player id -> PlayerUId key
local UIDS = {}
local function noop() end
package.loaded["lp.inventory"] = {
    add_implant = noop,
    delivery_candidates = function() return {} end,
    find_inventory = noop,
    local_player_id = noop,
    player_id_number = function(id) return id end,
    player_uid = function(id) return UIDS[id] end,
    remove_skill = noop,
    restore_replaced_passive = noop,
    undo_swap = noop,
}

local passives = require("lp.passives")
local stubbed = {}
for name, value in pairs(passives) do
    stubbed[name] = value
end
local function copy(list)
    local result = {}
    for index, id in ipairs(list) do
        result[index] = id
    end
    return result
end
stubbed.get_skill_ids = function(pal) return copy(pal.skills) end
stubbed.pal_key = function(pal) return pal.key end
stubbed.owner_key = function(pal) return pal.owner end
package.loaded["lp.passives"] = stubbed

local transaction = require("lp.transaction")
local resolve_record = transaction.resolve_record
local claim = transaction.claim

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        real_print(string.format("FAIL %-52s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        real_print(string.format("ok   %-52s %s", label, tostring(got)))
    end
end

local function is_valid_true() return true end
local function pal(key, owner, skills)
    return { key = key, owner = owner, skills = skills, IsValid = is_valid_true }
end

-- A server-snapshot record of every Pal in pals, as they stand now.
local function snapshot(pals, request_player_id)
    local snapshots = {}
    for index, each in ipairs(pals) do
        snapshots[index] = { parameter = each, before_ids = copy(each.skills) }
    end
    return { snapshots = snapshots, request_player_id = request_player_id,
        mode_source = "server snapshot" }
end

-- The swap vanilla performs: the passive in slot index becomes the marker.
local function swap(each, index, marker)
    each.skills[index] = marker
end

local function key_of(resolved)
    return resolved and resolved.key
end

-- 1. One exchange, one candidate.
do
    local a = pal("A", "U1", { "Stamina_Up_1", "Alien" })
    local b = pal("B", "U1", { "Alien" })
    local record = snapshot({ a, b }, 1)
    swap(a, 1, "LP_ExtractOne")
    local resolved, vanilla = resolve_record(record)
    check("single exchange resolves to its Pal", key_of(resolved), "A")
    check("single exchange: passive", resolved and resolved.passive_id, "Stamina_Up_1")
    check("single exchange: not vanilla", vanilla, false)
end

-- 2. Two exchanges, the second captured after the first's swap, both Pals with
--    one owner: the first is ambiguous until the second claims its Pal.
do
    local a = pal("A", "U1", { "Stamina_Up_1" })
    local b = pal("B", "U1", { "PAL_ALLAttack_up1" })
    UIDS[1], UIDS[2] = "U1", "U2"
    local first = snapshot({ a, b }, 1)
    swap(a, 1, "LP_ExtractOne")
    local second = snapshot({ a, b }, 2)
    swap(b, 1, "LP_ExtractOne")

    local resolved, vanilla = resolve_record(first)
    check("first, before any claim: ambiguous", resolved, nil)
    check("first, before any claim: not vanilla", vanilla, false)
    resolved = resolve_record(second)
    check("second resolves to B", key_of(resolved), "B")
    claim(resolved.key, second)
    resolved = resolve_record(first)
    check("first, after B is claimed: resolves to A", key_of(resolved), "A")
    check("first, after B is claimed: passive", resolved and resolved.passive_id, "Stamina_Up_1")
    claim(resolved.key, first)
    check("second still resolves to B", key_of(resolve_record(second)), "B")
    run_scheduled()
end

-- 3. Two exchanges captured before either swap, on Pals with different
--    owners: each picks the Pal its requester owns.
do
    local a = pal("A", "U1", { "Stamina_Up_1" })
    local b = pal("B", "U2", { "PAL_ALLAttack_up1" })
    UIDS[1], UIDS[2] = "U1", "U2"
    local first = snapshot({ a, b }, 1)
    local second = snapshot({ a, b }, 2)
    swap(a, 1, "LP_ExtractOne")
    swap(b, 1, "LP_ExtractAll")
    check("owner picks A for requester U1", key_of(resolve_record(first)), "A")
    check("owner picks B for requester U2", key_of(resolve_record(second)), "B")
end

-- 4. The same, but nobody owns either Pal: neither can be told apart.
do
    local a = pal("A", nil, { "Stamina_Up_1" })
    local b = pal("B", nil, { "PAL_ALLAttack_up1" })
    local first = snapshot({ a, b }, 1)
    swap(a, 1, "LP_ExtractOne")
    swap(b, 1, "LP_ExtractOne")
    check("unowned and ambiguous: refused", resolve_record(first), nil)
end

-- 5. Another player's vanilla change next to this exchange does not refuse it.
do
    local a = pal("A", "U1", { "Stamina_Up_1" })
    local c = pal("C", "U2", { "Alien" })
    local record = snapshot({ a, c }, 1)
    swap(a, 1, "LP_ExtractOne")
    c.skills[1] = "PAL_ALLAttack_up1"
    check("vanilla change elsewhere: still resolves A", key_of(resolve_record(record)), "A")
end

-- 6. A vanilla operation on its own is reported as vanilla.
do
    local c = pal("C", "U2", { "Alien" })
    local record = snapshot({ c }, 1)
    c.skills[1] = "PAL_ALLAttack_up1"
    local resolved, vanilla = resolve_record(record)
    check("vanilla alone: no candidate", resolved, nil)
    check("vanilla alone: reported vanilla", vanilla, true)
end

-- 7. A claim is released after its hold, and only by its own holder.
do
    local a = pal("A", "U1", { "Stamina_Up_1" })
    local record = snapshot({ a }, 1)
    swap(a, 1, "LP_ExtractOne")
    local other = {}
    claim("A", other)
    check("claimed by another: skipped", resolve_record(record), nil)
    claim("A", record)
    run_scheduled()
    check("released after the newest holder's hold", key_of(resolve_record(record)), "A")
end

-- 8. Direct routes: the one Pal that gained a direct-route passive, and what
--    it replaced.
do
    local direct = transaction.direct_route_change
    local a = pal("A", "U1", { "Alien" })
    local record = snapshot({ a }, 1)
    a.skills[2] = "CoolTimeReduction_Down_1"
    local found, added, removed = direct(record)
    check("direct route appended: Pal", found and found.parameter.key, "A")
    check("direct route appended: added", added, "CoolTimeReduction_Down_1")
    check("direct route appended: nothing replaced", removed, nil)

    a = pal("A", "U1", { "Alien", "PAL_ALLAttack_up1" })
    record = snapshot({ a }, 1)
    a.skills[1] = "CoolTimeReduction_Down_1"
    found, added, removed = direct(record)
    check("direct route over a passive: added", added, "CoolTimeReduction_Down_1")
    check("direct route over a passive: replaced", removed, "Alien")

    a = pal("A", "U1", { "Alien" })
    record = snapshot({ a }, 1)
    a.skills[1] = "PAL_ALLAttack_up1"
    check("an alias target is not a direct route", direct(record), nil)

    a = pal("A", "U1", { "Alien" })
    local b = pal("B", "U2", { "Alien" })
    record = snapshot({ a, b }, 1)
    a.skills[2] = "CoolTimeReduction_Down_1"
    b.skills[2] = "CoolTimeReduction_Down_1"
    check("two Pals gained one: refused", direct(record), nil)
end

print = real_print
print(failures == 0 and "\nALL PASS" or string.format("\n%d FAILED", failures))
os.exit(failures == 0 and 0 or 1)
