local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local config = require("scripts.config")
local Runtime = require("scripts.runtime")
local spatial_index = require("scripts.spatial_index")
local trainconf = require("scripts.trainconf")
local logger = require("scripts.logger")

local yutils = {}

---@type Runtime
local devices_runtime

---@type Runtime
local trains_runtime

---@type Context
local context

local is_configuration_changed

local image_operations = {

    "+", "-", "*", "/", "%", "^", "<<", ">>", "AND", "OR", "XOR"
}

local provider_role = defs.device_roles.provider
local requester_role = defs.device_roles.requester
local buffer_role = defs.device_roles.buffer
local depot_role = defs.device_roles.depot
local feeder_role = defs.device_roles.feeder
local builder_role = defs.device_roles.builder
local refueler_role = defs.device_roles.refueler
local teleport_role = defs.device_roles.teleporter

local band = bit32.band

---@param context Context
local function update_trains(context)
    local toremove = {}
    for _, train in pairs(context.trains) do
        if not trainconf.get_train_composition(train) then
            toremove[train.id] = train
        end
    end
    for id, _ in pairs(toremove) do
        context.trains[id] = nil
    end
end

---@param context Context
function yutils.convert_mask_to_pattern(context)
    update_trains(context)
    if context.pattern_ids then
        return false
    end

    context.pattern_ids = {}
    for _, d in pairs(devices_runtime.map) do
        local device = d --[[@as Device]]
        local dconfig = device.dconfig

        trainconf.scan_device(device)

        trainconf.load_config_from_mask(device)

        yutils.update_runtime_config(device)

        device.loco_mask = nil
        device.cargo_mask = nil
        device.fluid_mask = nil
        device.rloco_mask = nil

        dconfig.loco_mask = nil
        dconfig.cargo_mask = nil
        dconfig.fluid_mask = nil
        dconfig.rloco_mask = nil

        if dconfig.role == defs.device_roles.builder then
            device.builder_create_count = (device.builder_remove_count or 0) + device.create_count
        end
    end
    return true
end

local function on_configuration_changed(context)
    is_configuration_changed = true

    if not context.session_tick then
        context.session_tick  = -1
    end

    yutils.fix_all(context)
    yutils.convert_mask_to_pattern(context)
    for _, d in pairs(devices_runtime.map) do
        local device = d --[[@as Device]]
        device.distance_cache = nil
    end

    --- Init UI
    yutils.init_ui(context)

    --- Init SE
    for _, map in pairs(context.networks) do
        for _, network in pairs(map) do
            network.connected_network = nil
            network.connecting_ids = nil
            network.connecting_trainstops = nil
            network.connecting_outputs = nil
            network.is_orbit = nil
        end
    end
    yutils.init_se(context)
    global.debug_version = commons.debug_version
    game.print { "yaltn-device.update-message" }
end

---@return Context
function yutils.get_context()
    if context then return context end

    context = global.context --[[@as Context]]
    if context then
        yutils.load_pattern_cache()
        if not is_configuration_changed then
            on_configuration_changed(context)
        end
        return context
    end

    devices_runtime = Runtime.get("Device")
    trains_runtime = Runtime.get("Trains")
    context = {
        networks = {},
        running_requests = nil,
        waiting_requests = {},
        version = commons.context_version,
        trainstop_map = {},
        event_id = 1,
        event_log = {},
        configs = {},
        config_id = 1,
        delivery_id = 1,
        min_log_id = 1,
        pattern_ids = {},
        session_tick = -1
    }
    context.trains = trains_runtime.map --[[@as table<integer, Train>]]
    global.context = context
    return context
end

tools.on_init(yutils.get_context)
tools.on_configuration_changed(
---@param data ConfigurationChangedData
    function(data)
        on_configuration_changed(yutils.get_context())
    end)

---@param device Device
function yutils.fix_device_internals(device)
    for _, request in pairs(device.requested_items) do
        request.requested = 9
        request.provided = 0
    end
    for _, produced in pairs(device.produced_items) do
        produced.requested = 0
        produced.provided = 0
    end
    for _, delivery in pairs(device.deliveries) do
        for name, count in pairs(delivery.content) do
            if delivery.provider == device then
                local produced = delivery.provider.produced_items[name]
                if produced then
                    produced.requested = (produced.requested or 0) + count
                end
            end
            if delivery.requester == device then
                local requester = delivery.requester.requested_items[name]
                if requester then
                    requester.provided = (requester.provided or 0) + count
                end
            end
        end
    end
    if defs.buffer_feeder_roles[device.role] and device.train and device.train.train.valid then
        yutils.update_production_from_content(device, device.train)
    end
end

function yutils.purge_config()
    local context = yutils.get_context()
    local to_remove = {}
    local limit_date = game.tick - 60 * 7200
    local configs = context.configs
    for id, config in pairs(configs) do
        if config.remove_tick and config.remove_tick < limit_date then
            table.insert(to_remove, id)
        end
    end
    for _, id in pairs(to_remove) do
        configs[id] = nil
    end
end

---@param name string?
---@return boolean
local function is_invalid_name(name)
    if not name then
        return true
    end
    local signal = tools.sprite_to_signal(name)
    if not signal then
        return true
    end
    if signal.type == "item" then
        local proto = game.item_prototypes[signal.name]
        if not proto then
            return true
        end
    elseif signal.type == "fluid" then
        local proto = game.fluid_prototypes[signal.name]
        if not proto then
            return true
        end
    else
        local proto = game.virtual_signal_prototypes[signal.name]
        if not proto then
            return true
        end
    end
    return false
end

---@param signal_table table<string, any>
local function fix_signal_table(signal_table)
    if not signal_table then
        return
    end
    local removed = {}
    for name, _ in pairs(signal_table) do
        if is_invalid_name(name) then
            table.insert(removed, name)
        end
    end
    for _, name in pairs(removed) do
        signal_table[name] = nil
    end
end

---@param delivery Delivery
local function fix_delivery(delivery)
    local combined_delivery = delivery
    while combined_delivery do
        fix_signal_table(combined_delivery.content)
        combined_delivery = combined_delivery.combined_delivery
    end
end

---@param device Device
local function fix_device(device)
    fix_signal_table(device.requested_items)
    fix_signal_table(device.produced_items)
    if device.deliveries then
        for _, delivery in pairs(device.deliveries) do
            fix_delivery(delivery)
        end
    end
    fix_signal_table(device.internal_requests)
    fix_signal_table(device.internal_threshold)

    local dconfig = device.dconfig
    if dconfig and dconfig.requests then
        local index = 1
        while index <= #dconfig.requests do
            local request = dconfig.requests[index]
            if is_invalid_name(request.name) then
                table.remove(dconfig.requests, index)
            else
                index = index + 1
            end
        end
    end
    if device.parking_penalty then
        device.parking_penalty = nil
        device.is_parking = true
    end
end

---@param network SurfaceNetwork
local function fix_network(network)
    fix_signal_table(network.productions)
end

---@param context Context
function yutils.fix_all(context)
    for _, device in pairs(devices_runtime.map) do
        ---@cast device Device
        fix_device(device)
    end
    for _, nn in pairs(context.networks) do
        for _, network in pairs(nn) do
            fix_network(network)
        end
    end

    ---@param request_table Request[]
    local function fix_request_table(request_table)
        if not request_table then return end

        if request_table then
            local index = 1
            while index <= #request_table do
                if is_invalid_name(request_table[index].name) then
                    table.remove(request_table, index)
                else
                    index = index + 1
                end
            end
        end
    end

    fix_request_table(context.waiting_requests)
    fix_request_table(context.running_requests)

    for _, train in pairs(context.trains) do
        if train.state == defs.train_states.to_requester then
            if train.depot then
                if train.train.valid then
                    if train.train.state == defines.train_state.destination_full then
                        train.state = defs.train_states.at_waiting_station
                    else
                        train.state = defs.train_states.to_waiting_station
                    end
                end
            end
        end
    end
    context.request_iter = 0
    context.event_log    = {}
    context.min_log_id   = 1
    context.event_id     = 1
end

---@param context Context
function yutils.purge_logs(context)
    local event_log = {}
    local min_tick = game.tick - config.log_keeping_delay * 60
    local min_id
    for id, event in pairs(context.event_log) do
        if event.time >= min_tick then
            event_log[id] = event
        else
            if not min_id or min_id > id then
                min_id = id
            end
        end
    end
    context.event_log = event_log
    context.min_log_id = min_id or 1
end

---@param force_index integer
---@param surface_index integer
---@return SurfaceNetwork
function yutils.get_network_base(force_index, surface_index)
    local context = yutils.get_context()

    local networks_perforce = context.networks[force_index]
    if not networks_perforce then
        networks_perforce = {}
        context.networks[force_index] = networks_perforce
    end

    local network = networks_perforce[surface_index]
    if network then return network end

    ---@type SurfaceNetwork
    local network = {

        productions = {},
        surface_index = surface_index,
        force_index = force_index,
        production_indexes = {},
        surface_name = game.surfaces[surface_index].name,
        used_depots = {},
        free_depots = {},
        refuelers = {},
        teleporters = {}
    }
    networks_perforce[surface_index] = network
    return network
end

---@param force_index integer
---@param surface_index integer
---@return SurfaceNetwork?
function yutils.find_network_base(force_index, surface_index)

    local networks_perforce = context.networks[force_index]
    if not networks_perforce then return nil end

    local network = networks_perforce[surface_index]
    if not network then return nil end

    return network
end


---@param entity LuaEntity
function yutils.get_network(entity)
    return yutils.get_network_base(entity.force_index, entity.surface_index)
end

---@param request Request
function yutils.add_request(request)
    local device = request.device
    local name = request.name

    if request.inqueue then return end

    if device.inactive then return end

    request.inqueue = true
    request.cancelled = false
    local context = yutils.get_context()
    device.requested_items[name] = request
    if context.waiting_requests then
        table.insert(context.waiting_requests, request)
    else
        context.waiting_requests = { request }
    end
end

---@param request Request
function yutils.remove_request(request)
    local device = request.device
    local name = request.name

    device.requested_items[name] = nil
    request.cancelled = true
end

---@param production Request
function yutils.add_production(production)
    local device = production.device
    local network = device.network
    local name = production.name

    device.produced_items[name] = production
    local productions_for_name = network.productions[name]
    if not productions_for_name then
        productions_for_name = {}
        network.productions[name] = productions_for_name
    end
    local previous = productions_for_name[device.id]
    productions_for_name[device.id] = production
    if previous then spatial_index.remove_from_network(network, production) end
end

---@param production Request
function yutils.remove_production(production)
    local device = production.device
    local network = device.network
    local name = production.name

    device.produced_items[name] = nil
    local productions_for_name = network.productions[name]
    if not productions_for_name then return end
    productions_for_name[device.id] = nil
    if table_size(productions_for_name) == 0 then
        network.productions[name] = nil
    end
end

---@param delivery Delivery
function yutils.remove_provider_delivery(delivery)
    while delivery do
        local provider = delivery.provider
        if not delivery.loading_done then
            for name, count in pairs(delivery.content) do
                local produced = provider.produced_items[name]
                if produced then
                    produced.requested = produced.requested - count
                end
            end
            delivery.loading_done = true
        end
        if delivery.train then provider.deliveries[delivery.train.id] = nil end
        delivery = delivery.combined_delivery
    end
end

local search_radius = 3
local centered_position = { x = 0, y = 0 }

local front_width = 5
local back_width = 3
local side_width = 3

---@param device Device
---@param centered boolean?
function yutils.get_device_area(device, centered)
    local xd, yd
    local position
    if centered then
        position = centered_position
    else
        position = device.entity.position
    end

    local area
    local orientation = device.entity.orientation
    if orientation == 0 then
        area = {
            { position.x - side_width, position.y - front_width },
            { position.x + side_width, position.y + back_width }
        }
    elseif orientation == 0.5 then
        area = {
            { position.x - side_width, position.y - back_width },
            { position.x + side_width, position.y + front_width }
        }
    elseif orientation == 0.25 then
        area = {
            { position.x - back_width,  position.y - side_width },
            { position.x + front_width, position.y + side_width }
        }
    else
        area = {
            { position.x - front_width, position.y - side_width },
            { position.x + back_width,  position.y + side_width }
        }
    end
    return area
end

---@param delivery Delivery
---@param reschedule boolean?
function yutils.remove_requester_delivery(delivery, reschedule)
    while delivery do
        local requester = delivery.requester
        if not delivery.unloading_done then
            for name, count in pairs(delivery.content) do
                local request = requester.requested_items[name]
                if request then
                    request.provided = request.provided - count
                end
            end
            delivery.unloading_done = true
        end
        if delivery.train then requester.deliveries[delivery.train.id] = nil end
        delivery = delivery.combined_delivery
    end
end

---@param delivery Delivery
function yutils.cancel_delivery(delivery)
    if not delivery or delivery.cancelled then return end

    logger.report_cancel_delivery(delivery)
    yutils.remove_provider_delivery(delivery)
    yutils.remove_requester_delivery(delivery)
    delivery.cancelled = true
    if delivery.train then delivery.train.delivery = nil end
end

---@param train Train
---@param report_manual boolean ?
function yutils.remove_train(train, report_manual)
    if not train then return end
    if train.teleporting then return end

    local station = train.depot
    train.state = defs.train_states.removed
    train.network.trainstats_change = true
    if train.origin_id then
        local origin = devices_runtime.map[train.origin_id] --[[@as Device]]
        if origin and origin.create_count then
            origin.network.trainstats_change = true
        end
        train.origin_id = nil
    end
    if station and defs.buffer_feeder_roles[station.role] then
        for name, _ in pairs(station.produced_items) do
            station.network.productions[name][station.id] = nil
        end
        station.produced_items = {}
    end

    if train.delivery then yutils.cancel_delivery(train.delivery) end

    trains_runtime:remove(train)
    if train.train.valid and not train.train.manual_mode then
        if report_manual then
            logger.report_manual(train)
        end
        train.train.manual_mode = true
    end
    if station then
        if station.role == depot_role then
            station.network.used_depots[station.id] = nil
            station.network.free_depots[station.id] = station
        end
        if station.trains then station.trains[train.id] = nil end
        station.freezed = nil
        station.train = nil
        train.depot = nil
    end
end

local loco_mask_signal = {
    type = "virtual",
    name = commons.prefix .. "-loco_mask"
}
local cargo_mask_signal = {
    type = "virtual",
    name = commons.prefix .. "-cargo_mask"
}
local fluid_mask_signal = {
    type = "virtual",
    name = commons.prefix .. "-fluid_mask"
}
local identifier_signal = {
    type = "virtual",
    name = commons.prefix .. "-identifier"
}

---@param train Train
---@param device Device
function yutils.set_train_composition(train, device)
    if device.out_red.valid and not device.red_wire_as_stock then
        local cb = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]

        cb.set_signal(1, { signal = loco_mask_signal, count = train.loco_mask })
        cb.set_signal(2, { signal = cargo_mask_signal, count = train.cargo_mask })
        cb.set_signal(3, { signal = fluid_mask_signal, count = train.fluid_mask })
        cb.set_signal(3, { signal = identifier_signal, count = train.pattern_id })
    end
end

---@param train Train
---@param device Device
function yutils.set_waiting_schedule(train, device)
    local ttrain = train.train
    if not ttrain.valid then return end

    device.train = train
    ttrain.schedule = {
        current = 1,
        records = {
            {
                station = device.trainstop.backer_name,
                wait_conditions = {
                    { type = "inactivity", ticks = 300, compare_type = "and" }
                }
            }
        }
    }
end

local fuel_cache = {}

---@param train Train
---@param min_time integer @ min time in second
---@return boolean
function yutils.has_fuel(train, min_time)
    local ttrain = train.train
    if not ttrain.valid then return false end
    if min_time <= 0 then return false end

    for _, fb in pairs(ttrain.locomotives) do
        for _, loco in pairs(fb) do
            local inv = loco.get_fuel_inventory()
            local loco_proto = loco.prototype
            local energy_usage = min_time * 60 * loco_proto.max_energy_usage -- energy consumption / ticks
            local fuel_value = 0
            if inv then
                local contents = inv.get_contents()

                local effectivity = 1.0
                local burner_prototype = loco_proto.burner_prototype
                if burner_prototype then
                    effectivity = burner_prototype.effectivity
                end

                for fuel, amount in pairs(contents) do
                    local proto_fuel = fuel_cache[fuel]
                    if not proto_fuel then
                        proto_fuel = game.item_prototypes[fuel].fuel_value
                        fuel_cache[fuel] = proto_fuel
                    end
                    fuel_value = fuel_value + proto_fuel * amount * effectivity
                end

                local burner = loco.burner
                if burner then
                    fuel_value = fuel_value + burner.remaining_burning_fuel
                end
                if fuel_value < energy_usage then return false end

                local bri = loco.get_burnt_result_inventory()
                if bri and #bri > 0 and bri.is_full() then
                    return false
                end
            end
        end
    end

    return true
end

---@param ttrain LuaTrain
---@param station Device
---@return Train
function yutils.create_train(ttrain, station)
    ---@type Train
    local train = {
        id = ttrain.id,
        train = ttrain,
        network = station.network,
        state = defs.train_states.at_depot,
        depot = station,
        network_mask = station.network_mask,
        refresh_tick = game.tick,
        front_stock = ttrain.front_stock,
        origin_id = station.id
    }
    station.network.trainstats_change = true
    trainconf.get_train_composition(train)
    return train
end

---@param depot Device
---@param ttrain LuaTrain
---@return Train
function yutils.add_train_to_depot(depot, ttrain)
    local train = yutils.create_train(ttrain, depot)
    trains_runtime:add(train)
    train.state = defs.train_states.at_depot
    yutils.link_train_to_depot(depot, train)
    yutils.set_waiting_schedule(train, depot)
    yutils.read_train_internals(train)
    train.is_empty =
        ttrain.get_item_count() == 0 and ttrain.get_fluid_count() == 0
    if not train.is_empty and config.auto_clean then
        ttrain.clear_fluids_inside()
        ttrain.clear_items_inside()
    end
    return train
end

---@param buffer Device
---@param ttrain LuaTrain
---@return Train
function yutils.add_train_to_buffer_feeder(buffer, ttrain)
    local train = yutils.create_train(ttrain, buffer)
    train.depot = nil
    trains_runtime:add(train)
    yutils.link_train_to_buffer(buffer, train)
    if buffer.role == buffer_role then
        train.state = defs.train_states.at_buffer
    else
        train.state = defs.train_states.at_feeder
    end
    buffer.train = train
    train.depot = buffer
    yutils.set_waiting_schedule(train, buffer)
    yutils.read_train_internals(train)
    yutils.update_production_from_content(buffer, train)
    return train
end

---@param network SurfaceNetwork
---@param train Train
---@return Device?
function yutils.find_refueler(network, train)
    local network_mask = train.network_mask
    local position = train.front_stock.position
    local refueler_list = {}
    local goals = {}
    for _, refueler in pairs(network.refuelers) do
        if refueler.train == nil then
            if band(network_mask, refueler.network_mask) == 0 then
                goto skip
            end

            if refueler.patterns and not (refueler.patterns[train.gpattern] or refueler.patterns[train.rpattern]) then
                goto skip
            end

            if not refueler.trainstop.connected_rail then goto skip end

            if refueler.inactive then goto skip end

            table.insert(refueler_list, refueler)
            table.insert(goals, { train_stop = refueler.trainstop })
        end
        ::skip::
    end

    local goal_count = table_size(goals)
    if goal_count == 0 then
        return nil
    elseif goal_count == 1 then
        return refueler_list[1]
    end

    local result = game.request_train_path {
        goals = goals,
        train = train.train,
        type = "any-goal-accessible"
    }
    if not result.found_path then
        return nil
    end
    return refueler_list[result.goal_index]
end

---@param train Train
---@param device Device
function yutils.route_to_refueler(train, device)
    local records = {}
    local ttrain = train.train
    local change_surface_records

    device.freezed = false
    local trainstop = device.trainstop
    if USE_SE then
        local front_stock = train.front_stock
        if front_stock.surface_index ~= device.entity.surface_index then
            local from_network = yutils.get_network_base(front_stock.force_index, front_stock.surface_index)
            yutils.add_cross_network_trainstop(from_network, front_stock.position, records)

            table.insert(records, {
                station = trainstop.backer_name,
                wait_conditions = {
                    { type = "inactivity", compare_type = "and", ticks = 300 }
                }
            })
            change_surface_records = records
            records = {}
        end
    end

    table.insert(records, {
        rail = trainstop.connected_rail,
        temporary = true,
        rail_direction = trainstop.connected_rail_direction,
        wait_conditions = { { type = "time", compare_type = "and", ticks = 10 } }
    })

    table.insert(records, {
        station = trainstop.backer_name,
        wait_conditions = {
            { type = "inactivity", compare_type = "and", ticks = 120 }
        }
    })

    table.insert(records, {
        rail = trainstop.connected_rail,
        temporary = true,
        rail_direction = trainstop.connected_rail_direction,
        wait_conditions = {
            { type = "inactivity", compare_type = "and", ticks = 120 }
        }
    })

    if (change_surface_records) then
        train.splitted_schedule = { records }
        ttrain.schedule = { current = 1, records = change_surface_records }
    else
        ttrain.schedule = { current = 1, records = records }
        train.splitted_schedule = {}
    end
end

---@param train Train
function yutils.read_train_internals(train)
    if not train.train.valid then return end

    if config.refuel_min > 0 then
        train.has_fuel = yutils.has_fuel(train, config.refuel_min)
    end
    train.is_empty = train.train.get_item_count() == 0 and train.train.get_fluid_count() == 0
    if not train.is_empty then
        log("not empty train")
    end
    train.refresh_tick = GAMETICK
end

local black = commons.colors.black
local yellow = commons.colors.yellow
local green = commons.colors.green
local blue = commons.colors.blue
local red = commons.colors.red
local cyan = commons.colors.cyan
local orange = commons.colors.orange
local grey = commons.colors.grey
local light_grey = commons.colors.light_grey
local pink = commons.colors.pink
local purple = commons.colors.purple

local requester_roles = defs.requester_roles
local requester_roles_no_buffer = defs.requester_roles_no_buffer

local depot_roles = {
    [defs.device_roles.depot] = 1,
    [defs.device_roles.refueler] = 1,
    [defs.device_roles.builder] = 1
}

---@param device Device
function yutils.set_device_image(device)
    local image_index
    local role = device.role

    if depot_roles[role] then
        if device.inactive then
            image_index = pink
        elseif device.train then
            image_index = blue
        else
            image_index = cyan
        end
        goto setting
    end

    if device.inactive then
        image_index = pink
        goto setting
    end

    if requester_roles[role] then
        ---@type Request
        for _, r in pairs(device.requested_items) do
            if (r.requested - r.provided) >= r.threshold then
                image_index = red
                goto setting
            end
        end
    end

    if next(device.deliveries) then
        image_index = yellow
        goto setting
    end

    if next(device.produced_items) then
        image_index = green
        goto setting
    end

    if requester_roles[role] then
        image_index = orange
        goto setting
    end

    if role == teleport_role then
        if device.ebuffer and device.ebuffer.energy < commons.teleport_electric_buffer_size then
            image_index = red
        else
            image_index = green
        end
    elseif not role or not device.trainstop then
        image_index = black
    else
        image_index = grey
    end

    ::setting::
    if device.image_index ~= image_index then
        device.image_index = image_index
        local ac = device.entity
        if ac and ac.valid then
            local cb = ac.get_or_create_control_behavior() --[[@as LuaArithmeticCombinatorControlBehavior]]
            local parameters = cb.parameters
            parameters.operation = image_operations[image_index]
            cb.parameters = parameters
        end
    end
end

---@param from_network SurfaceNetwork
---@param position MapPosition
---@param records any[]
---@return LuaEntity?
function yutils.add_cross_network_trainstop(from_network, position, records) end

---@param context Context
---@param force boolean?
function yutils.init_se(context, force) end

function yutils.register_se() end

---@param train Train
---@return boolean
function yutils.is_train_stuck(train)
    if not train.timeout_tick or not train.timeout_pos then return false end

    if not train.timeout_pos or train.timeout_tick >= GAMETICK then
        return false
    end

    local position = train.train.front_stock.position
    if position.x == train.timeout_pos.x and position.y == train.timeout_pos.y then
        return true
    end
    train.timeout_pos = position
    train.timeout_tick = GAMETICK + train.timeout_delay
    return false
end

---@param train Train
---@return table<string, int>
local function get_train_content(train)
    local train_content = {}
    local ttrain = train.train
    if train.cargo_count > 0 then
        local cargo_content = ttrain.get_contents()
        for base_name, count in pairs(cargo_content) do
            local name = "item/" .. base_name
            train_content[name] = count
        end
    end

    if train.fluid_capacity > 0 then
        local fluid_content = ttrain.get_fluid_contents()
        for base_name, count in pairs(fluid_content) do
            local name = "fluid/" .. base_name
            train_content[name] = count
        end
    end
    return train_content
end

yutils.get_train_content = get_train_content

---@param device Device
---@param train Train
function yutils.update_production_from_content(device, train)
    local train_content = get_train_content(train)

    for name, count in pairs(train_content) do
        local production = device.produced_items[name]
        if production then
            production.provided = count
        else
            production = {
                name = name,
                requested = 0,
                provided = count,
                device = device,
                create_tick = GAMETICK,
                priority = device.priority,
                position = device.position
            }
            yutils.add_production(production)
        end
    end

    for name, production in pairs(device.produced_items) do
        if not train_content[name] then
            yutils.remove_production(production)
        end
    end

    return train_content
end

---@param train Train
function yutils.check_refuel(train)
    yutils.read_train_internals(train)
    if not train.has_fuel then
        local network = yutils.get_network(train.front_stock)
        local refueler = yutils.find_refueler(network, train)
        if not refueler and network.connected_network then
            refueler = yutils.find_refueler(network.connected_network, train)
        end
        if refueler then
            refueler.train = train
            train.state = defs.train_states.to_refueler
            train.refueler = refueler
            train.timeout_tick = nil

            -- free depot
            if train.depot and train.depot.role == depot_role then
                yutils.unlink_train_from_depots(train.depot, train)
            end
            yutils.set_train_composition(train, refueler)
            yutils.route_to_refueler(train, refueler)
            return true
        end
    end
    return false
end

---@param device Device
function yutils.clear_production(device)
    for name, _ in pairs(device.produced_items) do
        device.network.productions[name][device.id] = nil
    end
    device.produced_items = {}
end

---@param device Device
---@param role integer
function yutils.set_role(device, role)
    if not device then return end
    device.dconfig.role = role
end

---@param depot Device
---@param train Train
function yutils.link_train_to_depot(depot, train)
    if not depot then return end

    if depot.role == depot_role then
        depot.train = train
        train.depot = depot
        depot.network.used_depots[depot.id] = depot
        depot.network.free_depots[depot.id] = nil
    elseif depot.role == builder_role then
        yutils.link_train_to_builder(depot, train)
    end
end

---@param builder Device
---@param train Train
function yutils.link_train_to_builder(builder, train)
    if not builder then return end

    if not builder.trains then builder.trains = {} end
    builder.trains[train.id] = train
    train.depot = builder
end

---@param depot Device
---@param train Train
function yutils.unlink_train_from_depots(depot, train)
    if not depot then return end
    if not train then return end

    if depot.role == depot_role then
        train.depot = nil
        depot.train = nil
        depot.network.used_depots[depot.id] = nil
        depot.network.free_depots[depot.id] = depot
    elseif depot.role == builder_role then
        if depot.trains then depot.trains[train.id] = nil end
        train.depot = nil
    elseif depot.role == feeder_role then
        train.depot = nil
        depot.train = nil
    elseif depot.role == teleport_role then
        if depot.trains then
            depot.trains[train.id] = nil
        end
    end
end

---@param buffer Device
---@param train Train
function yutils.link_train_to_buffer(buffer, train)
    if not buffer then return end

    buffer.train = train
    train.depot = buffer
end

---@param feeder Device
---@param train Train
function yutils.link_train_to_feeder(feeder, train)
    if not feeder then return end

    feeder.train = train
    train.depot = feeder
end

---@param buffer Device
function yutils.unlink_train_from_buffer(buffer)
    if not buffer or not buffer.train then return end

    if buffer.train.delivery then
        buffer.deliveries[buffer.train.id] = nil
    end
    buffer.train.depot = nil
    buffer.train = nil
end

---@param depot Device
function yutils.add_depot(depot)
    depot.role = depot_role
    depot.network.free_depots[depot.id] = depot
end

---@param builder Device
function yutils.add_builder(builder)
    builder.role = builder_role
    builder.network.used_depots[builder.id] = builder
    builder.network.free_depots[builder.id] = builder
end

---@param depot Device
function yutils.remove_depot(depot)
    depot.network.used_depots[depot.id] = nil
    depot.network.free_depots[depot.id] = nil
end

---@param content table<string, integer>
---@return table<string, integer>
function yutils.content_to_item_map(content)
    local item_map = {}
    for name, count in pairs(content) do
        local signalid = tools.sprite_to_signal(name) --[[@as SignalID]]
        if signalid.type == "item" then
            item_map[signalid.name] = count
        end
    end
    return item_map
end

---@param pattern string?
---@return string[]
function yutils.create_layout_strings(pattern)
    local elements = trainconf.split_pattern(pattern)
    local markers  = { "" }

    for _, element in pairs(elements) do
        local marker
        local sprite_name = commons.generic_to_sprite[element.type]
        if sprite_name then
            marker = "[img=" .. sprite_name .. "]"
        else
            local item = game.entity_prototypes[element.type].items_to_place_this[1]
            if item then
                marker = "[item=" .. item.name .. "]"
            end
        end
        if marker then
            if element.count <= 2 then
                for i = 1, element.count do
                    table.insert(markers, marker)
                    if element.is_back then
                        table.insert(markers, "[img=" .. commons.revert_sprite .. "]")
                    end
                end
            else
                if element.count > 1 then
                    table.insert(markers, " " .. element.count .. "x")
                end
                table.insert(markers, marker)
                if element.is_back then
                    table.insert(markers, "[img=" .. commons.revert_sprite .. "]")
                end
            end
        end
    end
    return markers
end

function yutils.load_pattern_cache()
    PatternCache = {}
    for _, d in pairs(devices_runtime.map) do
        local device = d --[[@as Device]]
        if device.dconfig.patterns then
            for pattern in pairs(device.dconfig.patterns) do
                if not string.find(pattern, "[*]") then
                    local previous = PatternCache[pattern]
                    if not previous then
                        PatternCache[pattern] = trainconf.create_generic(pattern)
                    end
                end
            end
        end
    end
    global.pattern_cache = PatternCache
end

---@param content {[string]:integer}
---@param sign integer
---@return ConstantCombinatorParameters[]
function yutils.build_parameters(content, sign)
    ---@type ConstantCombinatorParameters[]
    local parameters
    local index = 1
    if content then
        parameters = {}
        for name, count in pairs(content) do
            local signalid = tools.sprite_to_signal(name)
            table.insert(parameters, {
                signal = signalid,
                count = sign * count,
                index = index
            })
            index = index + 1
        end
    else
        parameters = {}
    end
    return parameters
end

---@param device Device
---@param parameters ConstantCombinatorParameters[]
function yutils.set_device_output(device, parameters)
    if not device.out_red.valid then return end

    local cb = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    cb.parameters = parameters

    cb = device.out_green.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    cb.parameters = parameters
end

function yutils.update_runtime_config(device) end

function yutils.init_ui(context) end

function yutils.builder_compute_conf(builder) end

local function on_load()
    devices_runtime = Runtime.get("Device")
    trains_runtime = Runtime.get("Trains")

    if context then
        context.trains = trains_runtime.map --[[@as table<integer, Train>]]
    elseif global.debug_version == commons.debug_version then
        context = global.context
    end
    if global.pattern_cache then
        PatternCache = global.pattern_cache
    end

    yutils.register_se()
end

tools.on_load(on_load)
tools.on_nth_tick(60 * 60, yutils.purge_config)

logger.get_context = yutils.get_context


return yutils
