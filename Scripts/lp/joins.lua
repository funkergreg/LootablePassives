-- Lootable Passives -- A player joining the world, on the machine that holds it.
--
-- APalPlayerState::OnCompleteLoadWorldPartitionAndAdjustCharacter_InServer
-- (Pal.hpp) fires on the server for a joining player, twice per join, with the
-- joining BP_PalPlayerState_C as its context. It does not fire for a listen
-- host's own entry into its world.
--
-- A firing for a player whose join is already pending is ignored, so each join
-- notifies once. Listeners run JOIN_DELAY_MS after the first firing, on the game
-- thread, with the player state and its PlayerUId key, and only while the state
-- is still valid and this machine holds the world.

local util = require("lp.util")
local hooks = require("lp.hooks")
local role = require("lp.role")

local field = util.field
local guid_key = util.guid_key
local is_valid = util.is_valid
local log = util.log
local run_later = util.run_later
local unwrap = util.unwrap
local is_authority = role.is_authority

local JOIN_HOOK =
"/Script/Pal.PalPlayerState:OnCompleteLoadWorldPartitionAndAdjustCharacter_InServer"

local JOIN_DELAY_MS = 3000

local listeners = {}

-- PlayerUId key -> true while that player's join is waiting to notify.
local pending = {}

local function notify(state, uid)
    pending[uid] = nil
    if not is_valid(state) or not is_authority() then
        return
    end
    for _, listener in ipairs(listeners) do
        local succeeded, raised = pcall(listener, state, uid)
        if not succeeded then
            log("ERROR: a player-join step raised a Lua error: " .. tostring(raised))
        end
    end
end

local function on_join(context)
    if not is_authority() then
        return
    end
    local state = unwrap(context)
    local uid = guid_key(field(state, "PlayerUId"))
    if uid == nil or pending[uid] then
        return
    end
    pending[uid] = true
    run_later(JOIN_DELAY_MS, notify, state, uid)
end

-- listener(player_state, uid) runs once per join. Register at load.
local function on_joined(listener)
    listeners[#listeners + 1] = listener
end

-- Registers the join hook. Called once, at load.
local function install()
    hooks.register({
        path = JOIN_HOOK,
        callback = on_join,
        half = "server",
        label = "the player-join watcher",
        note = "Modules owed to a player are then delivered only on map load and conveyor runs.",
    })
end

return {
    install = install,
    on_joined = on_joined,
}
