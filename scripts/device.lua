local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local config = require("scripts.config")
local yutils = require("scripts.yutils")
local multisurf = require("scripts.multisurf")
local allocator = require("scripts.allocator")
local teleport = require("scripts.teleport")
local trainconf = require("scripts.trainconf")
local logger = require("scripts.logger")
local depotstats = require("scripts.depotstats")

------------------------------------------------------
local device_manager = {}

local prefix = commons.prefix

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime

local remove_device

local default_network_mask = config.default_network_mask

local set_device_image = yutils.set_device_image
local read_train_internals = yutils.read_train_internals
local band = bit32.band

local depot_role = defs.device_roles.depot
local buffer_role = defs.device_roles.buffer
local provider_role = defs.device_roles.provider
local requester_role = defs.device_roles.requester
local builder_role = defs.device_roles.builder
local feeder_role = defs.device_roles.feeder
local teleporter_role = defs.device_roles.teleporter

local provider_and_requester_role = defs.device_roles.provider_and_requester
local refueler_role = defs.device_roles.refueler
local provider_requester_buffer_feeder_roles =
    defs.provider_requester_buffer_feeder_roles
local buffer_feeder_roles = defs.buffer_feeder_roles
local provider_requester_roles = defs.provider_requester_roles
local depot_roles = defs.depot_roles
local train_available_states = defs.train_available_states

local get_vars = tools.get_vars
local device_name = commons.device_name
local get_context = yutils.get_context

local train_refresh_delay = 120
local fuel_refresh_delay = 1200


local create_count_signal = {
    type = "virtual",
    name = commons.prefix .. "-create_count"
}
local train_count_signal = {
    type = "virtual",
    name = commons.prefix .. "-train_count"
}

-----------------------------------------------------

---@param device Device
local function clear_train_stop(device)
    if device.trainstop_id then
        local context = get_context()
        context.trainstop_map[device.trainstop_id] = nil
        device.trainstop_id = nil
        if device.train then yutils.remove_train(device.train, true) end
    end
end

-- reroute train when a delivery is cancelled
---@param train Train
local function reroute_train(train)
    if train and train.train.valid and not train.train.manual_mode then
        train.delivery = nil
        local train_network = yutils.get_network(train.front_stock)
        local depot = allocator.find_free_depot(train_network, train)

        -- case depot
        if train.depot then
            if depot_roles[train.depot.role] then
                yutils.unlink_train_from_depots(train.depot, train)
            end
        end
        if depot then
            if depot.role == depot_role or depot.role == builder_role then
                yutils.link_train_to_depot(depot, train)
                train.state = defs.train_states.to_depot
                read_train_internals(train)
                allocator.route_to_station(train, depot)
            end
        else
            logger.report_depot_not_found(train.network, train.network_mask, train)
            train.train.manual_mode = true
        end
    end
end

---@param device Device
local function clear_device(device)
    local role = device.role
    if not role then return end

    device.role = nil

    local network = device.network
    if depot_roles[role] then
        yutils.remove_depot(device)
        local train = device.train
        if train and train.train.valid then
            if not train.train.manual_mode then
                logger.report_manual(train)
                train.train.manual_mode = true
            end
        end
        return
    elseif provider_requester_buffer_feeder_roles[role] then
        for _, request in pairs(device.requested_items) do
            request.cancelled = true
        end

        if buffer_feeder_roles[role] then
            local train = device.train
            if train and train.train.valid and not train.train.manual_mode then
                logger.report_manual(train)
                train.train.manual_mode = true
            end
        end

        yutils.clear_production(device)
        if device.deliveries and next(device.deliveries) then
            local deliveries = tools.table_dup(device.deliveries)
            for _, delivery in pairs(deliveries) do
                yutils.cancel_delivery(delivery)
                reroute_train(delivery.train)
            end
        end

        device.deliveries = {}
        device.requested_items = {}
        device.produced_items = {}
    elseif role == refueler_role then
        network.refuelers[device.id] = nil
        local train = device.train
        device.train = nil
        if train and train.train.valid and not train.train.manual_mode then
            logger.report_manual(train)
            train.train.manual_mode = true
        end
    elseif role == teleporter_role then
        if device.ebuffer then
            device.ebuffer.destroy()
            device.ebuffer = nil
        end
        if device.network.teleporters then
            device.network.teleporters[device.id] = nil
            if not next(device.network.teleporters) then
                device.network.teleporters = nil
            end
        end
    end
end

-----------------------------------------------------

---@param entity LuaEntity
---@param wire integer
---@return LuaEntity
local function create_cc(entity, wire)
    local cc = entity.surface.create_entity {
        name = commons.cc_name,
        position = entity.position,
        force = entity.force,
        create_build_effect_smoke = false
    }
    ---@cast cc -nil
    entity.connect_neighbour {
        wire = wire,
        target_entity = cc,
        source_circuit_id = defines.circuit_connector_id.combinator_output
    }
    cc.destructible = false
    return cc
end

---@param entity LuaEntity
---@param wire integer
---@return LuaEntity
local function create_input(entity, wire)
    local input = entity.surface.create_entity {
        name = entity.name .. '-cc',
        position = entity.position,
        force = entity.force,
        create_build_effect_smoke = false
    }
    ---@cast input -nil
    entity.connect_neighbour {
        wire = wire,
        target_entity = input,
        source_circuit_id = defines.circuit_connector_id.combinator_input
    }
    input.destructible = false
    return input
end

---@param device Device
function device_manager.get_red_input(device)
    local in_red = device.in_red
    if in_red then return in_red end
    device.in_red = create_input(device.entity, defines.wire_type.red)
    return device.in_red
end

---@param device Device
function device_manager.get_green_input(device)
    local in_green = device.in_green
    if in_green then return in_green end
    device.in_green = create_input(device.entity, defines.wire_type.green)
    return device.in_green
end

---@param device Device
local function create_ccs(device)
    local entity = device.entity
    device.out_red = create_cc(entity, defines.wire_type.red)
    device.out_green = create_cc(entity, defines.wire_type.green)
end

---@param device  Device
local function delete_ccs(device)
    for _, name in pairs({ "out_red", "out_green", "in_red", "in_green" }) do
        local cc = device[name]
        if cc and cc.valid then cc.destroy() end
    end
end

---@param device Device
function device_manager.delete_red_input(device)
    local in_red = device.in_red
    if in_red then
        in_red.destroy()
        device.in_red = nil
    end
end

---@param device Device
function device_manager.delete_green_input(device)
    local in_green = device.in_green
    if in_green then
        in_green.destroy()
        device.in_green = nil
    end
    return device.in_green
end

---@param entity LuaEntity
---@param tags Tags?
---@return Device
local function new_device(entity, tags)
    local context = get_context()

    ---@type Device
    local device = {
        id = entity.unit_number,
        entity = entity,
        produced_items = {},
        requested_items = {},
        network = yutils.get_network(entity),
        force_id = entity.force_index,
        deliveries = {}
    }

    local cb = entity.get_or_create_control_behavior() --[[@as LuaArithmeticCombinatorControlBehavior]]
    local config_id = cb.parameters.second_constant
    local need_register = true

    --[[@type DeviceConfig]]
    local dconfig
    if tags then
        dconfig = tags --[[@as DeviceConfig]]
        dconfig.inactive = config.inactive_on_copy
        device.inactive = dconfig.inactive and 1 or nil
    elseif config_id > 0 then
        dconfig = context.configs[config_id]
        need_register = false
    end

    if not dconfig then
        dconfig = { role = 0 }
        need_register = true
    end

    device.dconfig = dconfig
    if need_register then
        config_id = context.config_id
        context.config_id = config_id + 1
        local parameters = cb.parameters
        parameters.second_constant = config_id
        cb.parameters = parameters
        context.configs[config_id] = dconfig
        dconfig.id = config_id
    end
    dconfig.remove_tick = nil

    create_ccs(device)
    yutils.update_runtime_config(device)
    return device
end

local rail_types = {
    ["straight-rail"] = true,
    ["curved-rail"] = true

}

---@param entity LuaEntity
local function clear_distance_cache(entity)
    local surfaces_to_clear = global.surfaces_to_clear
    if not surfaces_to_clear then
        surfaces_to_clear = {}
        global.surfaces_to_clear = surfaces_to_clear
    end
    surfaces_to_clear[entity.surface_index] = true
end

---@param entity LuaEntity
---@param tags Tags
local function on_entity_built(entity, tags)
    if rail_types[entity.type] then
        clear_distance_cache(entity)
        return
    end
    local name = entity.name
    if name == device_name then
        local device = new_device(entity, tags)
        devices_runtime:add(device)
    elseif name == commons.se_elevator_name then
        multisurf.add_elevator(entity)
    end
end

---@param entity LuaEntity
local function on_entity_destroyed(entity)
    if rail_types[entity.type] then
        clear_distance_cache(entity)
        return
    end

    local name = entity.name
    if name == device_name then
        local id = entity.unit_number
        ---@cast id -nil

        local device = devices[id]
        if not device then return end

        device.dconfig.remove_tick = game.tick
        delete_ccs(device)
        remove_device(device)
    elseif name == "train-stop" then
        local context = get_context()
        local device = context.trainstop_map[entity.unit_number]
        if device ~= nil then
            clear_device(device)
            clear_train_stop(device)
        end
    elseif name == commons.se_elevator_name then
        multisurf.remove_elevator(entity)
    end
end

---@param ev EventData.on_entity_cloned
local function on_entity_clone(ev)
    local source = ev.source
    local dest = ev.destination
    local src_id = source.unit_number
    local dst_id = dest.unit_number

    ---@cast src_id -nil
    ---@cast dst_id -nil

    if source.name == device_name then
        -- debug(create_trace, "clone sensor")
        local device = devices[src_id]
        if not device then return end

        local dst_device = new_device(dest)

        local cb_red = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        cb_red.parameters = device.out_red.get_control_behavior().parameters

        local cb_green = device.out_green.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        cb_green.parameters = device.out_green.get_control_behavior().parameters

        if dst_id and src_id then
            remove_device(device)
            devices_runtime:add(dst_device)
        end
    elseif source.name == device_name .. "-cc" then
        dest.destroy()
    end
end

---@param evt EventData.on_built_entity | EventData.on_robot_built_entity | EventData.script_raised_built | EventData.script_raised_revive
local function on_built(evt)
    local e = evt.created_entity or evt.entity
    if not e or not e.valid then return end

    on_entity_built(e, evt.tags)
end

---@param evt EventData.on_pre_player_mined_item|EventData.on_entity_died|EventData.script_raised_destroy
local function on_destroyed(evt)
    local entity = evt.entity

    on_entity_destroyed(entity)
end

------------------------------------------------------------------------

local entity_filter = {
    { filter = 'type', type = 'curved-rail' },
    { filter = 'type', type = 'straight-rail' },
    { filter = 'name', name = device_name },
    { filter = "name", name = commons.se_elevator_name }
}

local entity_destroyed_filter = {
    { filter = 'type', type = 'curved-rail' },
    { filter = 'type', type = 'straight-rail' },
    { filter = 'name', name = device_name },
    { filter = "name", name = "train-stop" },
    { filter = "name", name = commons.se_elevator_name }
}

tools.on_event(defines.events.on_built_entity, on_built, entity_filter)
tools.on_event(defines.events.on_robot_built_entity, on_built, entity_filter)
tools.on_event(defines.events.script_raised_built, on_built, entity_filter)
tools.on_event(defines.events.script_raised_revive, on_built, entity_filter)

tools.on_event(defines.events.on_pre_player_mined_item, on_destroyed, entity_destroyed_filter)
tools.on_event(defines.events.on_robot_pre_mined, on_destroyed, entity_destroyed_filter)
tools.on_event(defines.events.on_entity_died, on_destroyed, entity_destroyed_filter)
tools.on_event(defines.events.script_raised_destroy, on_destroyed, entity_destroyed_filter)

tools.on_event(defines.events.on_entity_cloned, on_entity_clone, {
    { filter = 'name', name = device_name },
    { filter = 'name', name = commons.cc_name }
})

------------------------------------------------------------------------

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end

tools.on_load(on_load)

local function on_init()
    ---@type EntityMap<Device>
    tools.fire_on_load()
end

tools.on_init(on_init)

------------------------------------------------------------------------

local wire_red = defines.wire_type.red
local wire_green = defines.wire_type.green
local circuit_input = defines.circuit_connector_id.combinator_input

---@param device Device
local function connect_train_to_device(device)
    if device.role ~= depot_role and device.role ~= buffer_role then return end
    if device.train then return end

    local context = get_context()
    local trainstop = device.trainstop
    if not device.trainstop_id or not trainstop then return end
    local ttrain = trainstop.get_stopped_train()
    if ttrain and not ttrain.manual_mode then
        local train = context.trains[ttrain.id]
        if not train then
            if device.role == depot_role then
                yutils.add_train_to_depot(device, ttrain)
            elseif device.role == buffer_role then
                yutils.add_train_to_buffer_feeder(device, ttrain)
            end
        else
            yutils.unlink_train_from_depots(train.depot, train)
            yutils.link_train_to_depot(device, train)
            train.network_mask = device.network_mask
        end
    end
end

---@param device Device
local function find_train_stop(device)
    clear_train_stop(device)

    device.trainstop = nil

    local area = yutils.get_device_area(device)
    local position = device.entity.position
    local trainstops = device.entity.surface.find_entities_filtered {
        name = "train-stop",
        area = area
    }
    if not trainstops or #trainstops == 0 then return end

    local dmin
    for _, ts in pairs(trainstops) do
        local d = tools.distance2(position, ts.position)
        if not dmin or d < dmin then
            dmin = d
            device.trainstop = ts
        end
    end

    local trainstop = device.trainstop
    if not trainstop.connected_rail then
        device.trainstop = nil
        return
    end

    if trainstop then
        local context = get_context()
        if context.trainstop_map[trainstop.unit_number] then
            device.trainstop = nil
        else
            device.trainstop_id = trainstop.unit_number
            context.trainstop_map[device.trainstop_id] = device
            device.position = trainstop.position

            local cb = trainstop.get_or_create_control_behavior() --[[@as LuaTrainStopControlBehavior]]
            if cb then
                if not cb.read_from_train then
                    cb.read_from_train = true
                end
                cb.set_trains_limit = false
                trainstop.trains_limit = nil
            end
        end
    end
end

---@param device Device
remove_device = function(device)
    clear_device(device)
    clear_train_stop(device)
    devices_runtime:remove(device)
end

local used_roles = {

    [defs.device_roles.depot] = true,
    [defs.device_roles.requester] = true,
    [defs.device_roles.provider] = true,
    [defs.device_roles.provider_and_requester] = true,
    [defs.device_roles.buffer] = true,
    [defs.device_roles.refueler] = true,
    [defs.device_roles.builder] = true,
    [defs.device_roles.feeder] = true,
    [defs.device_roles.teleporter] = true

}

local monitor_train_states = {
    [defs.train_states.at_depot] = true,
    [defs.train_states.at_buffer] = true,
    [defs.train_states.at_feeder] = true
}

local virtual_to_internals = defs.virtual_to_internals

---@param device Device
local function process_device(device)
    local device_entity = device.entity

    get_context()

    if config.disabled then return end

    if not device_entity.valid then
        remove_device(device)
        return
    end

    set_device_image(device)

    local role = 0
    local circuit = device_entity.get_circuit_network(wire_red, circuit_input)
    local conf_changed

    local dconfig = device.dconfig
    role = dconfig.role
    device.inactive = dconfig.inactive and 1 or nil

    -- no role
    if not used_roles[role] then
        if device.role then
            clear_device(device)
            clear_train_stop(device)
            device.role = nil
        end
        return
    end

    ---@cast circuit -nil

    -- role change
    if role ~= device.role then
        conf_changed = true
        if device.role then clear_device(device) end
    end

    if not (device.trainstop_id and device.trainstop and device.trainstop.valid and
            device.trainstop.connected_rail) then
        find_train_stop(device)
        if not device.trainstop_id then
            clear_device(device)
            return
        end
        conf_changed = true
    end

    if device.network.disabled then return end

    local function read_virtual_signals()
        ---@cast circuit -nil
        local red_signals = circuit.signals

        if red_signals then
            for _, signal_amount in ipairs(red_signals) do
                local signal = signal_amount.signal
                if signal.type == "virtual" then
                    local v = virtual_to_internals[signal.name]
                    if v then
                        device[v] = signal_amount.count
                    end
                end
            end
        end
    end

    -- depot role
    if role == depot_role then
        device.network_mask = dconfig.network_mask or default_network_mask
        device.priority = dconfig.priority or 0
        device.parking_penalty = dconfig.parking_penalty
        if circuit then
            ---@cast circuit -nil
            read_virtual_signals()
        end
        if device.role ~= depot_role then
            yutils.add_depot(device)
            conf_changed = true
        end
        if conf_changed then
            connect_train_to_device(device)
        end

        local train = device.train
        if train then
            train.network_mask = device.network_mask
            if monitor_train_states[train.state] then
                if (GAMETICK - train.refresh_tick) >= fuel_refresh_delay then
                    yutils.check_refuel(train)
                end
                train.timeout_tick = nil
            end
        end
        return
    elseif role == builder_role then
        if not (device.trainstop.connected_rail and
                device.trainstop.connected_rail.valid) then
            clear_device(device)
            return
        end

        device.network_mask = dconfig.network_mask or default_network_mask
        device.priority = dconfig.priority or 0
        device.rpriority = dconfig.rpriority or 0
        if device.conf_change then
            device.builder_pattern = dconfig.builder_pattern
            device.builder_gpattern = dconfig.builder_gpattern
            device.builder_fuel_item = dconfig.builder_fuel_item
            device.no_remove_constraint = dconfig.no_remove_constraint
            device.conf_change = nil
            conf_changed = true
        end

        if circuit then
            device.builder_stop_create = nil
            device.builder_stop_remove = nil
            device.builder_remove_destroy = nil
            read_virtual_signals()
        end

        local create_count = allocator.get_create_count(device)

        local stat = depotstats.get(device.network, device.builder_gpattern)

        ---@type ConstantCombinatorParameters
        local parameters = {
            {
                index = 1,
                signal = create_count_signal,
                count = create_count
            }, {
            index = 2,
            signal = train_count_signal,
            count = stat.used
        }
        }
        yutils.set_device_output(device, parameters)

        if device.role ~= builder_role then
            yutils.add_builder(device)
            conf_changed = true
        end
        if conf_changed then
            if not allocator.builder_compute_conf(device) then
                clear_device(device)
            end
        end
        return
    end

    if provider_requester_buffer_feeder_roles[role] then
        if device.role ~= role then
            if buffer_feeder_roles[role] then trainconf.scan_device(device) end

            if role == buffer_role then
                device.role = buffer_role
                local train = connect_train_to_device(device)
                if train then
                    yutils.update_production_from_content(device, train)
                end
            end
        end

        device.role = role --[[@as DeviceRole]]

        ---@cast circuit -nil
        local red_signals = circuit and circuit.signals

        ---@type table<string, Signal>
        local content_map = {}
        ---@type table<string, integer>
        local threshold_map

        device.network_mask = dconfig.network_mask or default_network_mask
        device.max_delivery = dconfig.max_delivery or config.default_max_delivery
        device.priority = dconfig.priority or 0
        device.delivery_timeout = dconfig.delivery_timeout or config.delivery_timeout
        device.inactivity_delay = dconfig.inactivity_delay
        device.locked_slots = dconfig.locked_slots
        device.threshold = dconfig.threshold or config.default_threshold
        device.delivery_penalty = dconfig.delivery_penalty or config.delivery_penalty
        device.combined = dconfig.combined
        device.red_wire_as_stock = dconfig.red_wire_as_stock

        if red_signals then
            for _, signal_amount in ipairs(red_signals) do
                local signal = signal_amount.signal
                local signal_type = signal.type
                local name = signal.name
                if name and signal_amount.count ~= 0 then
                    if signal_type == "item" then
                        content_map["item/" .. name] = signal_amount
                    elseif signal_type == "fluid" then
                        content_map["fluid/" .. name] = signal_amount
                    elseif signal_type == "virtual" then
                        local v = virtual_to_internals[name]
                        if v then
                            device[v] = signal_amount.count
                        end
                    end
                end
            end
        end

        circuit = device_entity.get_circuit_network(wire_green, circuit_input)

        device.priority_map = nil
        if circuit then
            local green_signals = circuit.signals
            if green_signals then
                threshold_map = {}
                for _, signal_amount in ipairs(green_signals) do
                    local signal_type = signal_amount.signal.type
                    local name = signal_amount.signal.name
                    if name and signal_amount.count ~= 0 then
                        local count = math.abs(signal_amount.count)
                        if signal_type == "virtual" then
                            local v = virtual_to_internals[name]
                            if v then
                                device[v] = count
                            end
                        elseif signal_type == "item" then
                            threshold_map["item/" .. name] = count
                        elseif signal_type == "fluid" then
                            threshold_map["fluid/" .. name] = count
                        end
                    end
                end
                if dconfig.green_wire_as_priority then
                    device.priority_map = threshold_map
                    threshold_map = {}
                end
            end
        end

        if device.internal_requests then
            for name, count in pairs(device.internal_requests) do
                local signal_amount = content_map[name]
                if signal_amount then
                    signal_amount.count = signal_amount.count - count
                else
                    content_map[name] = { count = -count }
                end
            end
        end

        if device.internal_threshold then
            if threshold_map then
                for name, count in pairs(device.internal_threshold) do
                    if not threshold_map[name] then
                        threshold_map[name] = count
                    end
                end
            else
                threshold_map = device.internal_threshold
            end
        elseif not threshold_map then
            threshold_map = {}
        end

        local default_threshold = device.threshold
        local tick = GAMETICK

        if provider_requester_roles[role] then
            local is_max_delivery = device.max_delivery and
                table_size(device.deliveries) >=
                device.max_delivery
            for name, signal_count in pairs(content_map) do
                local count = signal_count.count
                if count < 0 then
                    if role == provider_role then
                        local production = device.produced_items[name]
                        if production then
                            production.provided = 0
                            if production.requested == 0 then
                                yutils.remove_production(production)
                            end
                        end
                        goto skip
                    end
                    count = -count

                    local threshold = threshold_map[name] or default_threshold
                    local request = device.requested_items[name]
                    if request then
                        request.requested = count
                        request.threshold = threshold
                        if count - request.provided < threshold then
                            goto skip
                        end
                        if is_max_delivery then goto skip end

                        if not request.inqueue then
                            yutils.add_request(request)
                        end
                    else
                        request = {
                            name = name,
                            requested = count,
                            provided = 0,
                            threshold = threshold,
                            device = device,
                            create_tick = GAMETICK
                        }
                        device.requested_items[name] = request
                        if count < threshold then
                            goto skip
                        end
                        if is_max_delivery then goto skip end

                        yutils.add_request(request)
                    end
                else
                    if role == requester_role then
                        local request = device.requested_items[name]
                        if request then
                            request.requested = 0
                            if request.provided == 0 then
                                yutils.remove_request(request)
                            end
                        end
                        goto skip
                    end

                    if device.internal_requests and device.internal_requests[name] then
                        goto skip
                    end

                    local production = device.produced_items[name]
                    if production then
                        production.provided = count
                    else
                        production = {
                            name = name,
                            requested = 0,
                            provided = count,
                            device = device,
                            create_tick = tick,
                            priority = device.priority,
                            position = device.position
                        }
                        yutils.add_production(production)
                    end
                end
                ::skip::
            end
        elseif role == buffer_role then
            local train = device.train

            device.station_locked = dconfig.station_locked
            for name, signal_count in pairs(content_map) do
                local count = signal_count.count
                if count < 0 then
                    count = -count

                    local threshold = threshold_map[name] or default_threshold

                    local content_provided = 0
                    local produced = device.produced_items[name]
                    if produced then
                        content_provided = produced.provided
                    end
                    count = count - content_provided
                    if count < 0 then
                        count = 0
                    end

                    local request = device.requested_items[name]
                    if request then
                        request.requested = count
                        request.threshold = threshold

                        if (count - request.provided) < threshold then
                            goto skip
                        end
                        if train and not train_available_states[train.state] then
                            goto skip
                        end
                        if not request.inqueue then
                            yutils.add_request(request)
                        end
                    else
                        request = {
                            name = name,
                            requested = count,
                            provided = 0,
                            threshold = threshold,
                            device = device,
                            create_tick = GAMETICK
                        }
                        device.requested_items[name] = request

                        if count < threshold then
                            goto skip
                        end
                        if train and not train_available_states[train.state] then
                            goto skip
                        end
                        yutils.add_request(request)
                    end
                    ::skip::
                end
            end

            if train and monitor_train_states[train.state] and
                (GAMETICK - train.refresh_tick) >= fuel_refresh_delay then
                yutils.check_refuel(train)
                device.train.timeout_tick = nil
            end
        elseif role == feeder_role then
            device.station_locked = dconfig.station_locked
            device.max_load_time = dconfig.max_load_time
            if not device.train then
                if not device.inactive then
                    local train = allocator.find_train(device, device.network_mask, device.patterns)
                    if not train then return end
                    yutils.unlink_train_from_depots(train.depot, train)
                    allocator.route_to_station(train, device);
                    yutils.link_train_to_feeder(device, train)
                end
            else
                if device.train.state == defs.train_states.at_feeder then
                    device.train.timeout_tick = nil
                    local ttrain = device.train.train
                    if ttrain and ttrain.valid then
                        yutils.update_production_from_content(device,
                            device.train)
                    end
                end
            end
            return
        end

        -- clean request and production
        if table_size(content_map) < table_size(device.requested_items) +
            table_size(device.produced_items) then
            local to_remove
            for name, request in pairs(device.requested_items) do
                if not content_map[name] and request.provided == 0 then
                    if not to_remove then to_remove = {} end
                    to_remove[name] = request
                end
            end
            if to_remove then
                for name, request in pairs(to_remove) do
                    yutils.remove_request(request)
                    device.requested_items[name] = nil
                end
            end
            to_remove = nil
            for name, request in pairs(device.produced_items) do
                if not content_map[name] and request.requested == 0 then
                    if not to_remove then to_remove = {} end
                    to_remove[name] = request
                end
            end
            if to_remove then
                for name, production in pairs(to_remove) do
                    yutils.remove_production(production)
                    device.produced_items[name] = nil
                end
            end
        end

        if device.red_wire_as_stock then
            local network_mask = device.network_mask
            local network = device.network

            local items = {}
            for name, pmap in pairs(network.productions) do
                for _, product in pairs(pmap) do
                    if band(product.device.network_mask, network_mask) ~= 0 then
                        items[name] = (items[name] or 0) + (product.provided - product.requested)
                    end
                end
            end
            local parameters = yutils.build_parameters(items, 1)
            if device.out_red.valid then
                local cb = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
                cb.parameters = parameters
            end
        end
        return
    elseif role == refueler_role then
        if device.role ~= role then
            local network = yutils.get_network(device.entity)

            network.refuelers[device.id] = device
        end

        device.role = refueler_role
        device.network_mask = dconfig.network_mask or default_network_mask
        device.priority = dconfig.priority or 0
        device.inactivity_delay = dconfig.inactivity_delay

        ---@cast circuit -nil
        if circuit then
            read_virtual_signals()
        end
    elseif role == teleporter_role then
        if device.role ~= teleporter_role then
            device.role = teleporter_role
            if not device.network.teleporters then
                device.network.teleporters = {}
            end
            device.network.teleporters[device.id] = device
            device.ebuffer = (device.entity.surface.create_entity {
                name = commons.teleport_electric_buffer_name,
                position = device.entity.position,
                force = device.entity.force
            }) --[[@as LuaEntity]]
        end
        device.teleport_range = dconfig.teleport_range or config.teleport_range
        if circuit then
            read_virtual_signals()
        end
        local trains = device.trainstop.get_train_stop_trains()
        local count = 0
        local name = device.trainstop.backer_name
        for _, train in pairs(trains) do
            local schedule = train.schedule
            local current = schedule.current
            local index = 1
            for _, r in pairs(schedule.records) do
                if r.station == name then
                    if index >= current then
                        count = count + 1
                    end
                    break
                end
                index = index + 1
            end
        end
        local parameters = {
            {
                index = 1,
                signal = train_count_signal,
                count = count
            }
        }
        yutils.set_device_output(device, parameters)

        if teleport.check_teleport(device) then
            yutils.set_device_image(device)
        end
        return
    end
end

tools.on_event(defines.events.on_entity_renamed,
    ---@param e EventData.on_entity_renamed
    function(e)
        local entity = e.entity
        if entity.type ~= "train-stop" then return end

        local context = get_context()
        local device = context.trainstop_map[entity.unit_number]
        if not device then return end
        local need_rename
        ---@type table<integer, LuaTrain>
        local train_set = {}
        if device.deliveries then
            for _, delivery in pairs(device.deliveries) do
                if delivery.requester.trainstop == entity and delivery.train and
                    delivery.train.train.valid then
                    train_set[delivery.train.id] = delivery.train.train
                    break
                end
                if delivery.provider.trainstop == entity and delivery.train and
                    delivery.train.train.valid then
                    train_set[delivery.train.id] = delivery.train.train
                end
            end
        end
        if device.train and device.train.train.valid then
            train_set[device.train.id] = device.train.train
        end

        for _, train in pairs(train_set) do
            local schedule = train.schedule
            local records = schedule.records
            local need_refresh
            for _, record in pairs(records) do
                if record.station == e.old_name then
                    record.station = entity.backer_name
                    need_refresh = true
                end
            end
            if need_refresh then train.schedule = schedule end
        end
    end)

local function remove_surface(surface_index)
    local context = get_context()
    local to_delete = {}
    for id, device in pairs(devices) do
        if device.network.surface_index == surface_index then
            to_delete[id] = device
        end
    end
    for id, _ in pairs(to_delete) do devices_runtime:remove(id) end
    for _, nn in pairs(context.networks) do
        nn[surface_index] = nil
        for _, network in pairs(nn) do
            if network.connected_network and
                network.connected_network.surface_index == surface_index then
                network.connected_network = nil
                network.connecting_ids = nil
                network.connecting_trainstops = nil
            end
        end
    end
end

tools.on_event(defines.events.on_pre_surface_deleted, --
    ---@param e EventData.on_pre_surface_deleted
    function(e) remove_surface(e.surface_index) end)

tools.on_event(defines.events.on_surface_cleared, --
    ---@param e EventData.on_surface_cleared
    function(e) remove_surface(e.surface_index) end)

tools.on_event(defines.events.on_surface_renamed, --
    ---@param e EventData.on_surface_renamed
    function(e)
        local context = get_context()
        for _, nn in pairs(context.networks) do
            for _, network in pairs(nn) do
                if network.surface_index == e.surface_index then
                    network.surface_name = e.new_name
                end
            end
        end
    end)

Runtime.register {
    name = "Device",
    global_name = "controllers",
    process = process_device,
    ntick = config.nticks,
    max_per_run = config.max_per_run,
    refresh_rate = config.reaction_time * 60 / config.nticks
}

return device_manager
