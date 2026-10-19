-- Offline test for lp/host.lua's handshake text and lp/passives.lua's set of
-- Surgery operations surgery_extraction covers.
--
--   lua tools\host_test.lua
--
-- Pure Lua: no engine call is made. Nothing is written to disk.
local TEST_SOURCE = debug.getinfo(1, "S").source:gsub("^@", "")
local TOOLS_DIRECTORY = TEST_SOURCE:match("^(.*[\\/])") or "./"
package.path = TOOLS_DIRECTORY .. "../Scripts/?.lua;" .. package.path

local real_print = print
print = function() end

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        real_print(string.format("FAIL %-52s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        real_print(string.format("ok   %-52s %s", label, tostring(got)))
    end
end

local host = require("lp.host")
local passives = require("lp.passives")
local ids = require("lp.ids")

-- 1. The handshake text round-trips, and anything else is not one.
for _, case in ipairs({ { true, true }, { true, false }, { false, true }, { false, false } }) do
    local text = host.format_payload(case[1], case[2])
    local payload = host.parse_payload(text)
    local label = string.format("round trip surgery=%s conveyor=%s", tostring(case[1]),
        tostring(case[2]))
    check(label .. ": surgery", payload and payload.surgery, case[1])
    check(label .. ": conveyor", payload and payload.conveyor, case[2])
end
check("text format", host.format_payload(true, false),
    "LootablePassives host v1 surgery=1 conveyor=0")
check("a vanilla cheat command is not one", host.parse_payload("god"), nil)
check("a probe text is not one", host.parse_payload("LP_HANDSHAKE_PROBE surgery=1"), nil)
check("prefix without version is not one", host.parse_payload("LootablePassives host"), nil)
check("nil is not one", host.parse_payload(nil), nil)
local later = host.parse_payload("LootablePassives host v2 surgery=1 conveyor=1 extra=1")
check("a later version still reads", later and later.surgery, true)
local missing = host.parse_payload("LootablePassives host v1 conveyor=1")
check("an unnamed setting reads as off", missing and missing.surgery, false)

-- 1b. Host notices: the message after the prefix, and nothing else is one.
check("a notice reads", host.parse_notice(host.NOTICE_PREFIX .. "Hello there."), "Hello there.")
check("an empty notice is not one", host.parse_notice(host.NOTICE_PREFIX), nil)
check("a settings text is not a notice", host.parse_notice(host.format_payload(true, true)), nil)
check("a notice is not a settings text", host.parse_payload(host.NOTICE_PREFIX .. "x"), nil)
check("nil is not a notice", host.parse_notice(nil), nil)

-- 1c. Grant reports: kind and items round-trip, and nothing else is one.
local grant_text = host.format_grant("owed", { { "LP_Implant_SwimSpeed_up_2", 2 },
    { "PalPassiveSkillChange_Consumable_PAL_ALLAttack_up3", 1 } })
check("grant text format", grant_text, "LootablePassives grant owed LP_Implant_SwimSpeed_up_2x2 "
    .. "PalPassiveSkillChange_Consumable_PAL_ALLAttack_up3x1")
local grant = host.parse_grant(grant_text)
check("grant kind", grant and grant.kind, "owed")
check("grant item count", grant and #grant.items, 2)
check("grant first item", grant and grant.items[1][1], "LP_Implant_SwimSpeed_up_2")
check("grant first count", grant and grant.items[1][2], 2)
check("grant id ending in a digit", grant and grant.items[2][1],
    "PalPassiveSkillChange_Consumable_PAL_ALLAttack_up3")
check("a grant with no items is not one", host.parse_grant("LootablePassives grant now "), nil)
check("a malformed item is not one", host.parse_grant("LootablePassives grant now LP_Implant_A"),
    nil)
check("a notice is not a grant", host.parse_grant(host.NOTICE_PREFIX .. "x"), nil)
check("a grant is not a notice", host.parse_notice(grant_text), nil)
check("a grant is not a settings text", host.parse_payload(grant_text), nil)

-- 1d. Setting changes: name and value round-trip, and nothing else is one.
check("setting text format", host.format_setting("surgery_ui_gate", false),
    "LootablePassives setting surgery_ui_gate=false")
local setting_name, setting_value = host.parse_setting(host.format_setting("debug", true))
check("setting name", setting_name, "debug")
check("setting value", setting_value, true)
check("a setting with no value is not one", host.parse_setting("LootablePassives setting debug="),
    nil)
check("a setting of another type is not one",
    host.parse_setting("LootablePassives setting debug=1"), nil)
check("a grant is not a setting", host.parse_setting(grant_text), nil)
check("a setting is not a settings text",
    host.parse_payload(host.format_setting("surgery_extraction", true)), nil)

-- 2. The covered set: both markers, every alias, every direct route, and no
--    vanilla passive or module.
local covered, markers, aliases, direct = 0, 0, 0, 0
for id, mode in pairs(ids.EXTRACTION_MODES) do
    if passives.is_covered(id) then
        covered = covered + 1
        if mode == "implant" then aliases = aliases + 1 else markers = markers + 1 end
    end
end
local real_passives, vanilla_module_passives = 0, 0
for passive_id, item_id in pairs(require("lp.passive_items")) do
    if passives.is_direct_route(passive_id) then
        direct = direct + 1
    end
    if passives.is_covered(passive_id) then
        covered = covered + 1
        real_passives = real_passives + 1
        if item_id:sub(1, 11) ~= "LP_Implant_" then
            vanilla_module_passives = vanilla_module_passives + 1
        end
    end
end
check("markers covered", markers, 2)
check("aliases covered", aliases, 54)
check("direct routes", direct, 61)
check("covered real passives are the direct routes", real_passives, 61)
check("no passive with a vanilla module is covered", vanilla_module_passives, 0)
check("covered ids in all, as PalSchema's rows added", covered, 117)
check("an alias target is not covered by its own id", passives.is_covered("Stamina_Up_1"), false)
check("nil is not covered", passives.is_covered(nil), false)
check("None is not covered", passives.is_covered("None"), false)

print = real_print
print(failures == 0 and "\nALL PASS" or string.format("\n%d FAILED", failures))
os.exit(failures == 0 and 0 or 1)
