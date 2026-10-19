-- Lootable Passives -- Whether this world's host runs the mod, and its
-- authoritative settings.
--
-- The host tells each player. On the machine that holds the world, the text
-- from format_payload is sent through
-- APalPlayerController::Debug_ReceiveCheatCommand_ToClient(FString Message)
-- (Pal.hpp), a client RPC, on the joining player's controller 3 s after the
-- join (lp/joins.lua), and on every remote controller when the host changes
-- surgery_extraction or conveyor_extraction. A controller IsLocalController()
-- reports true for is skipped: a listen host reads its own settings.
--
-- The host also sends notices, NOTICE_PREFIX and a message, which a client
-- logs and shows on screen through lp/notice.lua.
--
-- On a client, a hook on the same function reads the text, which arrives as
-- its second argument. A text with neither prefix is not this mod's and is
-- ignored. The hook runs inside the engine's handling of the RPC, so it only
-- records the values and logs; nothing reads them until the Surgery gate and
-- list do, from their own hooks. What a client has heard is forgotten on each
-- map load, which is when it joins or leaves a world.

local util = require("lp.util")
local options = require("lp.options")
local notice = require("lp.notice")
local role = require("lp.role")
local hooks = require("lp.hooks")

local field = util.field
local find_all = util.find_all
local guid_key = util.guid_key
local is_valid = util.is_valid
local log = util.log
local method = util.method
local unwrap = util.unwrap
local debug_log = options.debug_log

local PAYLOAD_PREFIX = "LootablePassives host"
local PAYLOAD_VERSION = "1"

-- A message from the host for its players to read, sent through the same RPC.
local NOTICE_PREFIX = "LootablePassives notice "

local RECEIVE_HOOK = "/Script/Pal.PalPlayerController:Debug_ReceiveCheatCommand_ToClient"

-- What the client has heard from its host, or nil before anything arrived.
local heard = nil

--------------------------------------------------------------------------------
-- The payload
--------------------------------------------------------------------------------

local function bit(value)
    return value and "1" or "0"
end

-- The host's text: the prefix, the payload version, and each authoritative
-- setting as name=0 or name=1.
local function format_payload(surgery, conveyor)
    return string.format("%s v%s surgery=%s conveyor=%s", PAYLOAD_PREFIX, PAYLOAD_VERSION,
        bit(surgery), bit(conveyor))
end

-- { surgery = bool, conveyor = bool } from a host text, or nil when text is not
-- one. A setting the text does not name reads as false.
local function parse_payload(text)
    if type(text) ~= "string" or text:sub(1, #PAYLOAD_PREFIX + 1) ~= PAYLOAD_PREFIX .. " " then
        return nil
    end
    local version = text:match("^" .. PAYLOAD_PREFIX .. " v(%d+)")
    if version == nil then
        return nil
    end
    return {
        version = version,
        surgery = text:match("[ ]surgery=1") ~= nil,
        conveyor = text:match("[ ]conveyor=1") ~= nil,
    }
end

-- The message text of a host notice, or nil when text is not one.
local function parse_notice(text)
    if type(text) ~= "string" or text:sub(1, #NOTICE_PREFIX) ~= NOTICE_PREFIX then
        return nil
    end
    local message = text:sub(#NOTICE_PREFIX + 1)
    return message ~= "" and message or nil
end

--------------------------------------------------------------------------------
-- Sending, on the machine that holds the world
--------------------------------------------------------------------------------

local function _call_one(object, name, argument)
    return object[name](object, argument)
end

-- Sends the current payload to one controller. Returns whether the call
-- returned.
local function send(controller, text)
    debug_log("handshake: sending to a player controller: " .. text)
    return (pcall(_call_one, controller, "Debug_ReceiveCheatCommand_ToClient", text))
end

local function current_payload()
    return format_payload(options.surgery_on(), options.conveyor_on())
end

-- Every valid PalPlayerController that is not this machine's own, as
-- { controller, uid }.
local function remote_controllers()
    local found = {}
    for _, controller in ipairs(find_all("PalPlayerController")) do
        if is_valid(controller) and method(controller, "IsLocalController") ~= true then
            found[#found + 1] = {
                controller = controller,
                uid = guid_key(field(field(controller, "PlayerState"), "PlayerUId")),
            }
        end
    end
    return found
end

-- The joining player's controller, matched by PlayerUId. Logs once when none
-- matches.
local function send_to_player(_, uid)
    if not role.is_authority() then
        return
    end
    local controllers = remote_controllers()
    debug_log(string.format("handshake: player %s joined; %d remote controller(s)", tostring(uid),
        #controllers))
    for _, entry in ipairs(controllers) do
        if entry.uid == uid then
            if not send(entry.controller, current_payload()) then
                log("WARNING: could not tell a joining player that this host runs Lootable "
                    .. "Passives; their game hides its Surgery operations until a setting changes "
                    .. "here or they rejoin.")
            end
            return
        end
    end
    debug_log("handshake: no player controller matched the joining player " .. tostring(uid))
end

-- Every remote controller, after the host changed an authoritative setting.
local function send_to_all()
    if not role.is_authority() then
        return
    end
    local text = current_payload()
    local controllers = remote_controllers()
    debug_log(string.format("handshake: a setting changed; sending to %d remote controller(s)",
        #controllers))
    for _, entry in ipairs(controllers) do
        send(entry.controller, text)
    end
end

-- Shows message to every player: through notice.once where this machine has a
-- UI, and as a host notice to every remote controller. Keyed by the message
-- itself, so each distinct message shows once per world on each machine.
local function broadcast(message)
    if not role.is_authority() then
        return
    end
    if role.has_ui() then
        notice.once(message, message)
    end
    local text = NOTICE_PREFIX .. message
    for _, entry in ipairs(remote_controllers()) do
        send(entry.controller, text)
    end
end

--------------------------------------------------------------------------------
-- Receiving, on a client
--------------------------------------------------------------------------------

-- Host notices received and not yet shown. The receiver only queues them;
-- show_notices runs on the next game-thread tick.
local pending_notices = {}

local function show_notices()
    local queued = pending_notices
    pending_notices = {}
    for _, message in ipairs(queued) do
        notice.once(message, message)
    end
end

local schedule_notices = util.coalescer(show_notices, 0)

local function _call_to_string(value)
    return value:ToString()
end

local function on_receive(_, message)
    if role.is_authority() then
        return
    end
    local value = unwrap(message)
    local converted, text = pcall(_call_to_string, value)
    if not converted then
        text = type(value) == "string" and value or nil
    end
    local notice_text = parse_notice(text)
    if notice_text ~= nil then
        pending_notices[#pending_notices + 1] = notice_text
        schedule_notices()
        return
    end
    local payload = parse_payload(text)
    if payload == nil then
        debug_log("handshake: a cheat-command text arrived that is not the host's: "
            .. tostring(text):sub(1, 80))
        return
    end
    debug_log("handshake: received " .. text)
    local changed = heard == nil or heard.surgery ~= payload.surgery
        or heard.conveyor ~= payload.conveyor
    heard = payload
    if changed then
        log(string.format("The host runs Lootable Passives: Surgery extraction %s, conveyor "
            .. "extraction %s.", payload.surgery and "on" or "off",
            payload.conveyor and "on" or "off"))
    end
end

--------------------------------------------------------------------------------
-- The answer the Surgery gate and list use
--------------------------------------------------------------------------------

-- Whether this machine may offer the Surgery operations surgery_extraction
-- covers. Where the world is held, the local setting decides. On a client,
-- only a host that has said it runs the mod with surgery_extraction on. Unknown
-- role: false.
local function surgery_allowed()
    if role.is_authority() then
        return options.surgery_on()
    end
    return heard ~= nil and heard.surgery
end

-- Why surgery_allowed() is false: "off_here" where the world is held and its
-- setting is off, "off_host" when the host said it is off, "unconfirmed" when a
-- client has not heard from its host. nil when allowed.
local function refusal()
    if surgery_allowed() then
        return nil
    end
    if role.is_authority() then
        return "off_here"
    end
    if heard ~= nil then
        return "off_host"
    end
    return "unconfirmed"
end

-- Called from main.lua's map-load hook.
local function forget()
    heard = nil
    pending_notices = {}
end

-- Registers the receiving hook. Called once, at load; lp/joins.lua's listener
-- is send_to_player.
local function install()
    hooks.register({
        path = RECEIVE_HOOK,
        callback = on_receive,
        half = "ui",
        label = "the host-settings receiver",
        note = "This game then hides the mod's Surgery operations in a multiplayer world.",
    })
end

return {
    NOTICE_PREFIX = NOTICE_PREFIX,
    broadcast = broadcast,
    forget = forget,
    format_payload = format_payload,
    install = install,
    parse_notice = parse_notice,
    parse_payload = parse_payload,
    refusal = refusal,
    send_to_all = send_to_all,
    send_to_player = send_to_player,
    surgery_allowed = surgery_allowed,
}
