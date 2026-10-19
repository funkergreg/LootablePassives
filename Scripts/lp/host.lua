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
-- logs and shows on screen through lp/notice.lua, and grant reports,
-- GRANT_PREFIX, a kind and the modules it put in that player's inventory,
-- which a client logs: kind "owed" always, kind "now" only when the client's
-- own debug setting is true. While the host's debug setting is true, each of
-- its runtime setting changes is sent too, SETTING_PREFIX and name=value,
-- which a client logs only when its own debug setting is true.
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

-- What the host put in this player's inventory: GRANT_PREFIX, a kind ("now"
-- for a grant as the exchange or disassembly happens, "owed" for a delivery of
-- modules owed from earlier), then one <item id>x<count> per module type,
-- space-separated.
local GRANT_PREFIX = "LootablePassives grant "

-- A runtime change of one of the host's settings: SETTING_PREFIX, then
-- <name>=true or <name>=false.
local SETTING_PREFIX = "LootablePassives setting "

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

-- The grant report text for kind and items, a list of { item_id, count }.
local function format_grant(kind, items)
    local parts = {}
    for index, item in ipairs(items) do
        parts[index] = string.format("%sx%d", item[1], item[2])
    end
    return GRANT_PREFIX .. kind .. " " .. table.concat(parts, " ")
end

-- { kind = string, items = { { item_id, count }, ... } } from a grant report,
-- or nil when text is not one or names no item.
local function parse_grant(text)
    if type(text) ~= "string" or text:sub(1, #GRANT_PREFIX) ~= GRANT_PREFIX then
        return nil
    end
    local kind, rest = text:sub(#GRANT_PREFIX + 1):match("^(%a+) (.*)$")
    if kind == nil then
        return nil
    end
    local items = {}
    for token in rest:gmatch("%S+") do
        local item_id, count = token:match("^(.+)x(%d+)$")
        if item_id == nil then
            return nil
        end
        items[#items + 1] = { item_id, tonumber(count) }
    end
    if #items == 0 then
        return nil
    end
    return { kind = kind, items = items }
end

-- The setting-change text for name and value, a boolean.
local function format_setting(name, value)
    return string.format("%s%s=%s", SETTING_PREFIX, name, tostring(value))
end

-- name, value from a setting-change text, or nil when text is not one.
local function parse_setting(text)
    if type(text) ~= "string" or text:sub(1, #SETTING_PREFIX) ~= SETTING_PREFIX then
        return nil
    end
    local name, value = text:sub(#SETTING_PREFIX + 1):match("^([%w_]+)=(%a+)$")
    if value ~= "true" and value ~= "false" then
        return nil
    end
    return name, value == "true"
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

-- Reports deliveries, a list of { uid = <PlayerUId key>, item_id, count }, to
-- each remote player they went to, as one grant report of kind per player. A
-- delivery to this machine's own player, or with no uid, is not sent: that
-- player reads this machine's log.
local function tell_grants(kind, deliveries)
    if deliveries == nil or #deliveries == 0 or not role.is_authority() then
        return
    end
    local by_uid, order = {}, {}
    for _, delivery in ipairs(deliveries) do
        local uid = delivery.uid
        if uid ~= nil then
            local items = by_uid[uid]
            if items == nil then
                items = { counts = {}, list = {} }
                by_uid[uid] = items
                order[#order + 1] = uid
            end
            local item_id = delivery.item_id
            if items.counts[item_id] == nil then
                items.counts[item_id] = 0
                items.list[#items.list + 1] = item_id
            end
            items.counts[item_id] = items.counts[item_id] + (delivery.count or 1)
        end
    end
    if #order == 0 then
        return
    end
    local controllers = remote_controllers()
    for _, uid in ipairs(order) do
        local items = by_uid[uid]
        local listed = {}
        for index, item_id in ipairs(items.list) do
            listed[index] = { item_id, items.counts[item_id] }
        end
        for _, entry in ipairs(controllers) do
            if entry.uid == uid then
                send(entry.controller, format_grant(kind, listed))
                break
            end
        end
    end
end

-- Sends a runtime change of this host's setting name to every remote
-- controller, only while this host's debug setting is true.
local function tell_setting(name, value)
    if not role.is_authority() or not options.debug_on() then
        return
    end
    local text = format_setting(name, value)
    for _, entry in ipairs(remote_controllers()) do
        send(entry.controller, text)
    end
end

--------------------------------------------------------------------------------
-- Receiving, on a client
--------------------------------------------------------------------------------

-- The modules of a grant report as "<item id> x<count>, ...", and their total.
local function describe_items(items)
    local parts, total = {}, 0
    for index, item in ipairs(items) do
        parts[index] = string.format("%s x%d", item[1], item[2])
        total = total + item[2]
    end
    return table.concat(parts, ", "), total
end

-- Logs a grant report: "owed" always, any other kind only under debug.
local function log_grant(grant)
    local listed, total = describe_items(grant.items)
    if grant.kind == "owed" then
        log(string.format("The host delivered %d module(s) owed to you from earlier: %s.", total,
            listed))
    else
        debug_log(string.format("The host granted you %d module(s): %s.", total, listed))
    end
end

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
    local setting_name, setting_value = parse_setting(text)
    if setting_name ~= nil then
        debug_log(string.format("The host's setting %s is now %s.", setting_name,
            tostring(setting_value)))
        return
    end
    local grant = parse_grant(text)
    if grant ~= nil then
        log_grant(grant)
        return
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
    format_grant = format_grant,
    format_payload = format_payload,
    format_setting = format_setting,
    install = install,
    parse_grant = parse_grant,
    parse_notice = parse_notice,
    parse_payload = parse_payload,
    parse_setting = parse_setting,
    refusal = refusal,
    send_to_all = send_to_all,
    send_to_player = send_to_player,
    surgery_allowed = surgery_allowed,
    tell_grants = tell_grants,
    tell_setting = tell_setting,
}
