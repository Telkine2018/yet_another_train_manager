local flib_format = require("__flib__/format")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local config = require("scripts.config")

local logger = {}

local prefix = commons.prefix

local icon_train_stuck = {type="item", name="locomotive"}
local icon_train_not_empty = {type="item", name="locomotive"}

---@param train LuaEntity
---@param icon SignalID
---@param msg LocalisedString
local function add_alert(train, icon, msg)

    local force_index = train.force_index
    for _, player in pairs(game.players) do
        if player.force_index == force_index then
            player.add_custom_alert(train, icon, msg, true)
        end
    end
end

---@param e LogEvent
local function add_event(e)

    local context = logger.get_context()
    local id = context.event_id
    e.id = id
    e.time = game.tick
    context.event_id = id + 1
    context.event_log[id] = e

    id = context.min_log_id
    local mintime = e.time - config.log_keeping_delay * 60
    while   id < context.event_id and
            (not context.event_log[id] 
            or context.event_log[id].time < mintime) do
        context.event_log[id] = nil
        id = id + 1
    end
    context.min_log_id = id
end

local format = string.format

---@param entity LuaEntity
function logger.gps_to_text(entity)

    if not(entity and entity.valid) then return end

    local position = entity.position
    return format("[gps=%s,%s,%s]", position["x"], position["y"],
                  entity.surface.name)
end
local gps_to_text = logger.gps_to_text

---@param trainstop LuaEntity
local function trainstop_to_text(trainstop)

    if not trainstop.valid then return end

    if config.show_surface_in_log then
        local name = trainstop.backer_name

        name = string.gsub(name, "%[item%=([^%]]+)%]", function(item)
            return "[img=item/" .. item .. "]" 
        end)
        name = string.gsub(name, "%[fluid%=([^%]]+)%]", function(item)
            return "[img=fluid/" .. item .. "]" 
        end)

        return trainstop.surface.name .. ":" .. name
    else
        return format("[train-stop=%d]", trainstop.unit_number)
    end
end
logger.trainstop_to_text = trainstop_to_text

---@param delivery Delivery
---@return table
function logger.delivery_to_text(delivery)

    local result = {prefix .. "-logger.delivery"}
    local first = true

    table.insert(result, tostring(delivery.id))

    local product_table = {""}
    local max = 0
    for name, amount in pairs(delivery.content) do

        if not first then table.insert(product_table, ",") end
        first = false

        local cc = {prefix .. "-logger.delivery-product"}
        local signal = tools.id_to_signal(name) 
        ---@cast signal -nil
        table.insert(cc, tostring(amount))
        table.insert(cc,
                     "[img=" .. signal.type .. "/" .. signal.name .. "] ")
        table.insert(product_table, cc)
        max = max + 1
        if max > 6 then break end
    end
    table.insert(result, product_table)

    local trainstop = delivery.provider.trainstop
    if trainstop and trainstop.valid then
        table.insert(result, trainstop_to_text(trainstop))
    else
        table.insert(result, "*");
    end

    trainstop = delivery.requester.trainstop
    if trainstop and trainstop.valid then
        table.insert(result, trainstop_to_text(trainstop))
    else
        table.insert(result, "*")
    end
    return result
end
local delivery_to_text = logger.delivery_to_text

---@param e LogEvent
---@return table
local function request_to_text(e)

    local result = {prefix .. "-logger.request"}
    local signal = tools.id_to_signal(e.request_name)
    ---@cast signal -nil
    table.insert(result, tostring(e.request_amount))
    table.insert(result, "[" .. signal.type .. "=" .. signal.name .. "]")
    local trainstop = e.device.trainstop
    if (trainstop.valid) then
        table.insert(result, trainstop_to_text(trainstop))
    else
        table.insert(result, "*")
    end

    return result
end

logger.request_to_text = request_to_text

---@param e LogEvent
---@param msg LocalisedString
local function print(e, msg) game.forces[e.force_id].print(msg, commons.print_settings) end

---@param e LogEvent
---@return LocalisedString
function logger.event_cancel_to_text(e)

    return {
        prefix .. "-logger.cancel", flib_format.time(e.time),
        delivery_to_text(e.delivery)
    }
end

---@param e LogEvent
---@return LocalisedString
function logger.event_producer_not_found_to_text(e)

    return {
        prefix .. "-logger.producer_not_found", flib_format.time(e.time),
        request_to_text(e)
    }
end

---@param delivery Delivery
function logger.report_cancel_delivery(delivery)

    ---@type LogEvent
    local e = {
        force_id = delivery.requester.force_id,
        type = commons.event_cancel_delivery,
        delivery = delivery
    }
    add_event(e)
    if config.log_level >= 1 then print(e, logger.event_cancel_to_text(e)) end
end

---@param request Request
function logger.report_producer_notfound(request)
    request.producer_failed_logged = true
    ---@type LogEvent
    local e = {
        force_id = request.device.force_id,
        type = commons.event_producer_not_found,
        request_name = request.name,
        request_amount = request.requested - request.provided,
        device = request.device,
        surface = request.device.network.surface_name,
        network_mask = request.device.network_mask
    }
    add_event(e)
    if config.log_level >= 1 then
        print(e, logger.event_producer_not_found_to_text(e))
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_train_not_found_to_text(e)

    return {
        prefix .. "-logger.train_not_found", flib_format.time(e.time),
        request_to_text(e)
    }
end

---@param request Request
function logger.report_train_notfound(request)
    request.train_notfound_logged = true
    ---@type LogEvent
    local e = {
        force_id = request.device.force_id,
        type = commons.event_train_not_found,
        request_name = request.name,
        request_amount = request.requested - request.provided,
        device = request.device,
        surface = request.device.network.surface_name,
        network_mask = request.device.network_mask
    }
    add_event(e)
    if config.log_level >= 1 then
        print(e, logger.event_train_not_found_to_text(e))
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_train_not_empty_to_text(e)

    return {
        prefix .. "-logger.train_not_empty", flib_format.time(e.time),
        delivery_to_text(e.delivery)
    }
end

---@param delivery Delivery
function logger.report_train_not_empty(delivery)

    ---@type LogEvent
    local e = {
        force_id = delivery.requester.force_id,
        type = commons.event_train_not_empty,
        delivery = delivery,
        device = delivery.requester,
        surface = delivery.requester.network.surface_name,
        network_mask = delivery.requester.network_mask
    }
    add_event(e)
    if config.log_level >= 1 then
        print(e, logger.event_train_not_empty_to_text(e))
    end
    local train = delivery.train
    if train and train.front_stock.valid then
        add_alert(train.front_stock, icon_train_not_empty, {"yaltn-error.train_not_empty", tostring(train.id)})
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_depot_notfound_to_text(e)

    return {
        prefix .. "-logger.depot_not_found", flib_format.time(e.time),
        game.surfaces[e.network.surface_index].name, tostring(e.network_mask)
    }
end

---@param network SurfaceNetwork
---@param train Train?
function logger.report_depot_not_found(network, train)

    ---@type LogEvent
    local e = {
        force_id = network.force_index,
        type = commons.event_depot_not_found,
        network = network,
        surface = network.surface_name,
        train = train
    }
    add_event(e)
    if config.log_level >= 1 then
        print(e, logger.event_depot_notfound_to_text(e))
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_delivery_creation_to_text(e)

    local delivery = e.delivery --[[@as Delivery]]
    return {
        prefix .. "-logger.delivery_creation", flib_format.time(e.time),
        delivery_to_text(delivery)
    }
end

---@param delivery Delivery
function logger.report_delivery_creation(delivery)

    ---@type LogEvent
    local e = {
        force_id = delivery.requester.force_id,
        type = commons.event_delivery_create,
        delivery = delivery
    }
    add_event(e)
    if config.log_level >= 2 then
        game.forces[delivery.requester.force_id].print(logger.event_delivery_creation_to_text(e), commons.print_settings)
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_delivery_completion_to_text(e)

    local delivery = e.delivery --[[@as Delivery]]
    return {
        prefix .. "-logger.delivery_completion",
        flib_format.time(delivery.end_tick),
        flib_format.time(delivery.end_tick - delivery.start_tick),
        delivery_to_text(delivery)

    }
end

---@param delivery Delivery
function logger.report_delivery_completion(delivery)

    ---@type LogEvent
    local e = {
        force_id = delivery.requester.force_id,
        type = commons.event_delivery_complete,
        delivery = delivery
    }
    add_event(e)
    if config.log_level >= 2 then
        game.forces[delivery.requester.force_id].print(logger.event_delivery_completion_to_text(e), commons.print_settings)
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_train_stuck_to_text(e)

    local ttrain = e.train.train
    local train_marker
    if ttrain.valid then
        train_marker = "[train=" .. ttrain.id .. "]"
    else
        train_marker = "*"
    end
    return {
        prefix .. "-logger.train_stuck", flib_format.time(e.time),
        gps_to_text(ttrain.front_stock),
        train_marker,
        (e.train.delivery and delivery_to_text(e.train.delivery) or "*")
    }
end

---@param train Train
function logger.report_train_stuck(train)

    if not train.train.valid then return end
    if train.active_reported then return end

    train.active_reported = true

    ---@type LogEvent
    local e = {
        force_id = train.train.front_stock.force_index,
        type = commons.event_train_stuck,
        train = train,
        surface = train.front_stock.surface.name,
        network_mask = train.network_mask,
        delivery = train.last_delivery
    }
    add_event(e)
    if config.log_level >= 1 then
        print(e, logger.event_train_stuck_to_text(e))
    end
    if train.front_stock.valid then
        add_alert(train.front_stock, icon_train_stuck, {"yaltn-error.train_stuck", tostring(train.id)})
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_teleportation_to_text(e)

    local delivery = e.delivery --[[@as Delivery]]
    return {
        prefix .. "-logger.teleport",
        flib_format.time(e.time),
        trainstop_to_text(e.source_teleport.trainstop),
        trainstop_to_text(e.target_teleport.trainstop)
    }
end

---@param source_teleport Device
---@param target_teleport Device
---@param train Train
function logger.report_teleportation(source_teleport, target_teleport, train)

    if not config.teleport_report then
        return
    end
    
    ---@type LogEvent
    local e = {
        force_id = source_teleport.force_id,
        type = commons.event_teleportation,
        source_teleport = source_teleport,
        target_teleport = target_teleport,
        device = source_teleport,
        surface = source_teleport.network.surface_name,
        network = source_teleport.network,
        train = train
    }
    add_event(e)
    if config.log_level >= 2 then
        game.forces[source_teleport.force_id].print(logger.event_teleportation_to_text(e), commons.print_settings)
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_teleport_fail_to_text(e)

    return {
        prefix .. "-logger.teleport_failure",
        flib_format.time(e.time),
        trainstop_to_text(e.source_teleport.trainstop),
        trainstop_to_text(e.target_teleport.trainstop),
        gps_to_text(e.target_teleport.entity)
    }
end

---@param source_teleport Device
---@param target_teleport Device
---@param train Train
function logger.report_teleport_fail(source_teleport, target_teleport, train)

    ---@type LogEvent
    local e = {
        force_id = target_teleport.force_id,
        type = commons.event_teleport_failure,
        device = target_teleport,
        target_teleport = target_teleport,
        source_teleport = source_teleport,
        surface = target_teleport.network.surface_name,
        network = target_teleport.network,
        train = train,
        
    }
    add_event(e)
    if config.log_level >= 1 then
        game.forces[target_teleport.force_id].print(logger.event_teleport_fail_to_text(e), commons.print_settings)
    end
end

---@param e LogEvent
---@return LocalisedString
function logger.event_manual_to_text(e)

    return {
        prefix .. "-logger.manual",
        flib_format.time(e.time),
        e.train and gps_to_text(e.train.front_stock)
    }
end

---@param train Train
function logger.report_manual(train)
    local ttrain = train.train
    if not ttrain or not ttrain.front_stock.valid then
        return
    end

    ---@type LogEvent
    local e = {
        force_id = train.front_stock.force_index,
        type = commons.event_no_depot,
        surface = train.network.surface_name,
        network = train.network,
        train = train,
    }
    
    if config.log_level >= 1 then
        game.forces[e.force_id].print(logger.event_manual_to_text(e), commons.print_settings)
    end
end

---@return Context
function logger.get_context()
    return {}
end

return logger
