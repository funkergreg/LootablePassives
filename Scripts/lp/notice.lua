-- Lootable Passives -- A message to the player, once per world per reason.
--
-- Each message is logged, then added to the game's on-screen log through
-- UPalLogManager::AddLog(EPalLogPriority, const FText&, const FPalLogAdditionalData&)
-- (Pal.hpp), on the manager UPalUtility::GetLogManager(WorldContextObject)
-- returns, with PalGameStateInGame as the context. The priority is Important
-- (2, Pal_enums.hpp) and the additional data an empty table.
--
-- What has been shown is forgotten on each map load.

local util = require("lp.util")
local options = require("lp.options")

local find_first = util.find_first
local is_valid = util.is_valid
local log = util.log
local debug_log = options.debug_log

local UTILITY_PATH = "/Script/Pal.Default__PalUtility"
local PRIORITY_IMPORTANT = 2

local shown = {}

local function _call_one(object, name, argument)
    return object[name](object, argument)
end

local function _call_add_log(manager, text)
    return manager:AddLog(PRIORITY_IMPORTANT, FText(text), {})
end

-- The world's log manager, or nil.
local function log_manager()
    local context = find_first("PalGameStateInGame")
    if context == nil then
        return nil
    end
    local found, utility = pcall(StaticFindObject, UTILITY_PATH)
    if not found or not is_valid(utility) then
        return nil
    end
    local succeeded, manager = pcall(_call_one, utility, "GetLogManager", context)
    if succeeded and is_valid(manager) then
        return manager
    end
    return nil
end

-- Logs text and adds it to the on-screen log, unless key was already shown in
-- this world.
local function once(key, text)
    if shown[key] then
        return
    end
    shown[key] = true
    log(text)
    if FText == nil then
        debug_log("notice: UE4SS provides no FText, so the message is in UE4SS.log only")
        return
    end
    debug_log("notice: FText is a " .. type(FText))
    local manager = log_manager()
    if manager == nil then
        debug_log("notice: no log manager, so the message is in UE4SS.log only")
        return
    end
    debug_log("notice: calling UPalLogManager:AddLog")
    local succeeded, raised = pcall(_call_add_log, manager, text)
    if not succeeded then
        debug_log("notice: AddLog raised: " .. tostring(raised))
    end
end

-- Called from main.lua's map-load hook.
local function forget()
    shown = {}
end

return {
    forget = forget,
    once = once,
}
