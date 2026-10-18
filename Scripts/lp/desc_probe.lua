-- Lootable Passives -- one-shot description probe.
--
-- On its first run, calls BP_PalUIFunctionLibrary_C::BuildPassiveSkillDescText
-- (FName passiveName, UObject* __WorldContext, FText& Text) on the library's CDO
-- for every real passive in ids.IMPLANT_TARGET, and logs one line per passive:
--   DESC<TAB><alias><TAB><real passive><TAB><key>=<text>[<TAB>...]
-- with one key=text pair for every field the out table holds after the call.
-- Every later run does nothing. Logs before each engine call.
local util = require("lp.util")
local ids = require("lp.ids")

local log = util.log
local name_to_string = util.name_to_string

local LIBRARY_CLASS = "BP_PalUIFunctionLibrary_C"

local ran = false

local function _find_class()
    return FindObject("BlueprintGeneratedClass", LIBRARY_CLASS)
end

local function _get_cdo(class)
    return class:GetCDO()
end

local function _build(cdo, passive, world, out)
    return cdo:BuildPassiveSkillDescText(FName(passive), world, out)
end

-- Every key the out table holds, as key=text, joined by tabs.
local function describe_out(out)
    local parts = {}
    for key, value in pairs(out) do
        parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(name_to_string(value)))
    end
    table.sort(parts)
    return table.concat(parts, "\t")
end

local function probe()
    log("DESC probe: FindObject(BlueprintGeneratedClass, " .. LIBRARY_CLASS .. ")")
    local found, class = pcall(_find_class)
    if not found or not util.is_valid(class) then
        log("DESC probe: library class not found: " .. tostring(class))
        return
    end
    log("DESC probe: GetCDO")
    local got, cdo = pcall(_get_cdo, class)
    if not got or not util.is_valid(cdo) then
        log("DESC probe: no CDO: " .. tostring(cdo))
        return
    end
    local world = util.find_first("PalPlayerCharacter")
    if world == nil then
        log("DESC probe: no PalPlayerCharacter for the world context")
        return
    end

    local aliases = {}
    for alias in pairs(ids.IMPLANT_TARGET) do
        aliases[#aliases + 1] = alias
    end
    table.sort(aliases)

    for _, alias in ipairs(aliases) do
        local real = ids.IMPLANT_TARGET[alias]
        local out = {}
        log("DESC probe: BuildPassiveSkillDescText " .. real)
        local called, result = pcall(_build, cdo, real, world, out)
        if called then
            log(string.format("DESC\t%s\t%s\t%s\treturn=%s", alias, real, describe_out(out),
                tostring(name_to_string(result))))
        else
            log(string.format("DESC\t%s\t%s\tERROR %s", alias, real, tostring(result)))
        end
    end
    log("DESC probe: done")
end

-- Schedules the probe on the game thread the first time it is called.
local function run_once()
    if ran then
        return
    end
    ran = true
    util.run_later(0, probe)
end

return {
    run_once = run_once,
}
