local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")
local allocator = require("scripts.allocator")
local scheduler = require("scripts.scheduler")
local Pathing = require("scripts.pathing")

local train_mgr = {}

---@type Runtime
local trains_runtime

local depot_role = defs.device_roles.depot
local buffer_role = defs.device_roles.buffer
local provider_role = defs.device_roles.provider
local requester_role = defs.device_roles.requester
local refueler_role = defs.device_roles.refueler
local builder_role = defs.device_roles.builder
local feeder_role = defs.device_roles.feeder

local buffer_feeder_roles = defs.buffer_feeder_roles

local oper_loading = 1
local oper_unloading = 2
local debug = tools.debug

local check_refuel = yutils.check_refuel

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
local operation_signal = {
    type = "virtual",
    name = commons.prefix .. "-operation"
}

local train_available_states = defs.train_available_states

---@param device Device
---@param train_content table<string, int>?
local function fire_train_arrived(device, train_content)
    local item_map
    if train_content then
        item_map = yutils.content_to_item_map(train_content)
    end
    remote.call("transfert_controller", "fire_train_arrived", device.main_controller, device.secondary_controllers, item_map)
end

---@param device Device
---@param content table<string, integer> ?
---@param train Train?
---@param sign integer?
---@param operation integer
local function set_device_output(device, content, train, sign, operation)
    if not device.out_red.valid then return end

    if not sign then sign = 1 end

    local parameters = nil

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

    local function apply_train_info(parameters, index)
        if train then
            if train.loco_mask ~= 0 then
                table.insert(parameters, {
                    signal = loco_mask_signal,
                    count = train.loco_mask,
                    index = index
                })
                index = index + 1
            end
            if train.cargo_mask ~= 0 then
                table.insert(parameters, {
                    signal = cargo_mask_signal,
                    count = train.cargo_mask,
                    index = index
                })
                index = index + 1
            end
            if train.fluid_mask ~= 0 then
                table.insert(parameters, {
                    signal = fluid_mask_signal,
                    count = train.fluid_mask,
                    index = index
                })
                index = index + 1
            end
            table.insert(parameters, {
                signal = identifier_signal,
                count = train.pattern_id,
                index = index
            })
            index = index + 1
        end

        table.insert(parameters, {
            signal = operation_signal,
            count = operation,
            index = index
        })

        index = index + 1
        return parameters, index
    end

    parameters, index = apply_train_info(parameters, index)

    local cb
    local red_wire_mode = device.red_wire_mode
    if red_wire_mode == 1 then
        cb = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        cb.parameters = parameters
    elseif red_wire_mode == 3 or red_wire_mode == 4 then
        if train then
            local rparameters, rindex = {}, 1
            rparameters, rindex = apply_train_info(rparameters, rindex)
            local delivery = train.delivery
            while delivery do
                for name, count in pairs(delivery.content) do
                    local signalid = tools.sprite_to_signal(name)
                    table.insert(rparameters, {
                        signal = signalid,
                        count = count,
                        index = rindex
                    })
                    rindex = rindex + 1
                end
                if red_wire_mode == 3 then
                    break
                else
                    delivery = delivery.combined_delivery
                end
            end
            cb = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
            cb.parameters = rparameters
        end
    end

    cb = device.out_green.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    cb.parameters = parameters
end

---@param device Device
local function clear_device_output(device)
    if not device then return end
    if device.red_wire_mode ~= 2 then
        local cb
        cb = device.out_red.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        cb.parameters = nil

        cb = device.out_green.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        cb.parameters = nil
    end
end

local wire_red = defines.wire_type.red
local circuit_input = defines.circuit_connector_id.combinator_input

---@param device Device
local function reload_production(device)
    local entity = device.entity
    if not entity.valid then return end

    local circuit = entity.get_circuit_network(wire_red, circuit_input)

    local signals
    if circuit then signals = circuit.signals end
    if not signals then
        for _, production in pairs(device.produced_items) do
            production.provided = 0
        end
        return
    end

    for _, signal in pairs(signals) do
        local name = signal.signal.type .. "/" .. signal.signal.name
        local production = device.produced_items[name]
        if production then
            if signal.count > 0 then
                production.provided = signal.count
            else
                production.provided = 0
            end
        end
    end
end

---@param device Device
local function reload_request(device)
    local entity = device.entity
    if not entity.valid then return end

    local circuit = entity.get_circuit_network(wire_red, circuit_input)

    local signals
    if circuit then signals = circuit.signals end
    if not signals then
        for _, request in pairs(device.requested_items) do
            request.requested = 0
        end
        return
    end

    for _, signal in pairs(signals) do
        local name = signal.signal.type .. "/" .. signal.signal.name
        local request = device.requested_items[name]
        if request then
            if signal.count < 0 then
                request.requested = -signal.count
            else
                request.requested = 0
            end
        end
    end
end

---@param network SurfaceNetwork
---@param train Train
---@param device Device?
---@return Device?
local function find_depot_and_route(network, train, device)
    local depot = allocator.find_free_depot(network, train, device)
    if not depot then
        logger.report_depot_not_found(network, train.network_mask, train)
        train.train.schedule = nil
        train.train.manual_mode = true
        train.state = defs.train_states.depot_not_found
        return nil
    end

    if depot.role ~= builder_role then
        yutils.set_train_composition(train, depot)
    end
    train.lock_time = game.tick + 10
    allocator.route_to_station(train, depot)
    yutils.link_train_to_depot(depot, train)
    return depot
end

---@param train Train
---@param delivery Delivery
---@return Delivery?
local function try_combine_request(train, delivery)
    local requester = delivery.requester

    if train.slot_count == 0 then
        return
    end

    local cargos = train.train.cargo_wagons
    local available_slots = 0
    for _, cargo in pairs(cargos) do
        local inv = cargo.get_inventory(defines.inventory.cargo_wagon)
        ---@cast inv -nil
        available_slots = available_slots + inv.count_empty_stacks(true, true)
    end
    if available_slots == 0 then
        return
    end

    local from_device = delivery.provider
    local delivery
    local found_request
    local found_dist
    local found_candidate

    for _, request in pairs(requester.requested_items) do
        local is_item = string.sub(request.name, 1, 1) == "i"
        if not is_item then goto skip end

        local requested = request.requested - request.provided
        if requested < request.threshold then goto skip end

        delivery = train.delivery
        while delivery do
            if delivery.content[request.name] then
                goto skip
            end
            delivery = delivery.combined_delivery
        end

        local candidate
        candidate = scheduler.find_provider(request, train.delivery.provider, true)
        if not candidate then goto skip end

        if buffer_feeder_roles[candidate.device.role] then
            goto skip
        end

        local dist
        if from_device.distance_cache then
            dist = from_device.distance_cache[candidate.device.id]
        end
        if not dist then
            dist = Pathing.device_distance(from_device, candidate.device)
        end

        if dist < 0 then goto skip end
        if found_dist and dist < found_dist then
            goto skip
        end
        found_dist = dist
        found_candidate = candidate
        found_request = request
        ::skip::
    end

    if found_request then
        local content = scheduler.create_payload(found_request, found_candidate, train, available_slots)
        local existing_content = yutils.get_train_content(train)
        delivery = scheduler.create_delivery(found_request, found_candidate, train, content, existing_content)
        return delivery
    end
end

---@param event EventData.on_train_changed_state
local function on_train_changed_state(event)
    local new_state = event.train.state
    local context = yutils.get_context()
    local gametick = game.tick

    if tools.tracing then
        debug("on_train_changed_state: train=" .. event.train.id ..
            ",new_state=" .. tools.get_constant_name(event.train.state, defines.train_state) ..
            ",old_state=" .. tools.get_constant_name(event.old_state, defines.train_state)
        )
    end

    if new_state == defines.train_state.wait_station then
        local train = context.trains[event.train.id]
        local trainstop = event.train.station

        if trainstop then
            -- train not managed
            if not train then
                local device = context.trainstop_map[trainstop.unit_number]
                if not device then return end
                if device.role == depot_role then
                    if device.train and device.train.id ~= event.train.id then
                        local train = yutils.create_train(event.train, device)
                        local depot = allocator.find_free_depot(device.network, train)
                        if depot then
                            allocator.route_to_depot_same_surface(event.train, depot)
                        else
                            logger.report_depot_not_found(device.network, device.network_mask, train)
                        end
                    else
                        yutils.add_train_to_depot(device, event.train)
                    end
                elseif buffer_feeder_roles[device.role] then
                    yutils.add_train_to_buffer_feeder(device, event.train)
                end
                return
                --- train managed
            else
                local delivery = train.delivery
                -- with delivery
                if delivery then
                    -- at provider
                    if delivery.provider.trainstop_id == trainstop.unit_number then
                        if delivery.provider.role ~= defs.device_roles.feeder then
                            train.state = defs.train_states.loading
                            delivery.start_load_tick = gametick
                            if delivery.requester.role == buffer_role then
                                local content = {}
                                for name, count in pairs(delivery.content) do
                                    local produced = delivery.requester.produced_items[name]
                                    if produced then
                                        count = count + produced.provided
                                    end
                                    content[name] = count
                                end
                                set_device_output(delivery.provider, content, train, -1, oper_loading)
                                if delivery.provider.main_controller then
                                    fire_train_arrived(delivery.provider, content)
                                end
                            else
                                if tools.tracing then
                                    debug("on_train_changed_state: to provider")
                                end
                                local target_content
                                if delivery.combined_delivery then
                                    local train_contents = yutils.get_train_content(train)
                                    target_content = {}
                                    for name, count in pairs(delivery.content) do
                                        target_content[name] = (train_contents[name] or 0) + count
                                    end
                                    set_device_output(delivery.provider, target_content, train, -1, oper_loading)
                                else
                                    target_content = delivery.content
                                    set_device_output(delivery.provider, target_content, train, -1, oper_loading)
                                end
                                if delivery.provider.main_controller then
                                    fire_train_arrived(delivery.provider, target_content)
                                end
                            end
                        end
                        return
                        -- at requester
                    elseif delivery.requester.trainstop_id == trainstop.unit_number then
                        train.state = defs.train_states.unloading
                        local requester = delivery.requester
                        if delivery.provider.main_controller then
                            fire_train_arrived(delivery.requester, nil)
                        end
                        if tools.tracing then
                            debug("on_train_changed_state: to requester")
                        end
                        if buffer_feeder_roles[delivery.provider.role] and delivery.provider.train == train then
                            local exit_content = {}
                            local auto_ajust_delivery = config.auto_ajust_delivery and delivery.requester.inactivity_delay
                            for name, count in pairs(delivery.content) do
                                local stock = delivery.provider.produced_items[name]
                                -- amount = train content after unloading
                                local amount = 0
                                if stock then
                                    local available = stock.provided - stock.requested
                                    amount = stock.provided - count
                                    if auto_ajust_delivery and available > 0 then
                                        local requested = delivery.requester.requested_items[name]
                                        if requested then
                                            local remaining_request = requested.requested - requested.provided
                                            local added_amount = math.min(available, remaining_request)
                                            if added_amount > 0 then
                                                delivery.content[name] = count + added_amount
                                                requested.provided = requested.provided + added_amount
                                                stock.requested = stock.requested + added_amount
                                                amount = amount - added_amount
                                            end
                                        end
                                    end
                                end
                                if amount < 0 then
                                    amount = 0
                                end
                                exit_content[name] = -amount
                            end
                            for name, stock in pairs(delivery.provider.produced_items) do
                                if not delivery.content[name] then
                                    exit_content[name] = -stock.provided
                                end
                            end
                            set_device_output(requester, exit_content, train, 1, oper_unloading)
                        else
                            set_device_output(requester, {}, train, 1, oper_unloading)
                            if train.depot and defs.provider_requester_roles[delivery.provider.role] then
                                yutils.unlink_train_from_depots(train.depot, train)
                            end
                        end
                        train.delivery.start_unload_tick = gametick
                        return
                    elseif train.state == defs.train_states.to_waiting_station
                        and train.depot
                        and train.depot.trainstop_id == trainstop.unit_number
                    then
                        train.state = defs.train_states.at_waiting_station
                    end
                    -- no delivery
                else
                    local station = context.trainstop_map[trainstop.unit_number]
                    if station then
                        local role = station.role

                        -- depot station
                        if role == depot_role then
                            if station.train and station.train.id == event.train.id then
                                yutils.read_train_internals(train)
                                if not train.is_empty and config.auto_clean then
                                    event.train.clear_items_inside()
                                    event.train.clear_fluids_inside()
                                    train.is_empty = true
                                end
                                train.state = defs.train_states.at_depot
                                train.last_delivery = nil
                                station.freezed = false
                                yutils.set_waiting_schedule(train, station)
                            end
                            return
                            -- buffer station
                        elseif role == buffer_role then
                            if station.train and station.train.id == event.train.id then
                                yutils.read_train_internals(train)
                                if train.last_delivery then
                                    train.last_delivery.end_tick = gametick
                                    train.last_delivery.start_unload_tick = gametick
                                end
                                train.state = defs.train_states.at_buffer
                                train.last_delivery = nil
                                train.last_use_date = gametick
                                station.freezed = false
                                yutils.set_waiting_schedule(train, station)
                            end
                            return
                            -- feeder station
                        elseif role == feeder_role then
                            if station.train and station.train.id == event.train.id then
                                yutils.read_train_internals(train)
                                if train.last_delivery then
                                    train.last_delivery.end_tick = gametick
                                    train.last_delivery.start_unload_tick = gametick
                                end
                                train.state = defs.train_states.at_feeder
                                train.last_delivery = nil
                                train.last_use_date = gametick
                                station.freezed = false
                                yutils.set_waiting_schedule(train, station)
                            end
                            -- refueler station
                        elseif role == refueler_role then
                            train.state = defs.train_states.at_refueler
                            train.last_delivery = nil
                            train.last_use_date = gametick
                            -- builder station
                        elseif role == builder_role then
                            allocator.builder_delete_train(train, station)
                        end
                    end
                end
            end
        else
            if train then
                local depot = train.depot
                if depot and depot.freezed then
                    depot.freezed = false
                    if depot.role == depot_role then
                        yutils.unlink_train_from_depots(depot, depot.train)
                    end
                end
            end
        end
        return
    elseif new_state == defines.train_state.manual_control then
        local train = context.trains[event.train.id]
        if train then
            if train.teleporting then return end
            yutils.remove_train(train)
        end
        return
    elseif event.old_state == defines.train_state.wait_station then
        local train = context.trains[event.train.id]
        if train then
            if train.state == defs.train_states.loading then
                local delivery = train.delivery

                if delivery.provider.main_controller then
                    remote.call("transfert_controller", "fire_train_leave", delivery.provider.main_controller)
                end

                if buffer_feeder_roles[delivery.requester.role] then
                    clear_device_output(delivery.provider)
                    yutils.remove_provider_delivery(delivery)
                    yutils.remove_requester_delivery(delivery)
                    delivery.end_load_tick = gametick
                    yutils.update_production_from_content(delivery.requester, train)
                    delivery.end_tick = gametick
                    train.last_use_date = gametick
                    logger.report_delivery_completion(train.delivery)
                    train.delivery = nil

                    if check_refuel(train) then return end

                    if delivery.requester.role == buffer_role then
                        train.state = defs.train_states.to_buffer
                    else
                        train.state = defs.train_states.to_feeder
                    end
                    allocator.route_to_station(train, delivery.requester)
                else
                    clear_device_output(delivery.provider)
                    train.state = defs.train_states.to_requester

                    -- need update of provider
                    reload_production(delivery.provider)
                    yutils.remove_provider_delivery(delivery)
                    delivery.end_load_tick = gametick
                    if delivery.requester.combined and train.cargo_count > 0 then
                        try_combine_request(train, delivery)
                    end
                end

                if new_state == defines.train_state.destination_full then
                    local delivery = train.delivery
                    if delivery and not train.depot then
                        local requester = delivery.requester
                        local depot = allocator.find_free_depot(requester.network, train, requester, true)
                        if not depot then
                            return
                        end
                        train.state = defs.train_states.to_waiting_station
                        yutils.link_train_to_depot(depot, train)
                        allocator.insert_route_to_depot(train.train, depot)
                    end
                end
                return
            elseif train.state == defs.train_states.unloading then
                local delivery = train.delivery

                if buffer_feeder_roles[delivery.provider.role] and
                    delivery.provider.train == train then
                    clear_device_output(delivery.requester)
                    yutils.remove_requester_delivery(delivery, true)
                    yutils.remove_provider_delivery(delivery)
                    delivery.end_tick = gametick
                    train.last_use_date = gametick
                    logger.report_delivery_completion(train.delivery)
                    train.delivery = nil
                    yutils.update_production_from_content(delivery.provider, train)
                    yutils.read_train_internals(train)

                    if check_refuel(train) then return end
                    if delivery.provider.role == buffer_role then
                        train.state = defs.train_states.to_buffer
                    else -- feeder_role
                        train.state = defs.train_states.to_feeder
                    end
                    allocator.route_to_station(train, delivery.provider)
                else
                    clear_device_output(delivery.requester)
                    train.state = defs.train_states.to_depot

                    -- need update of requester
                    local delivery = train.delivery
                    reload_request(delivery.requester)
                    yutils.remove_requester_delivery(delivery, true)
                    yutils.remove_provider_delivery(delivery)
                    local combined_delivery = delivery
                    while combined_delivery do
                        combined_delivery.end_tick = gametick
                        logger.report_delivery_completion(combined_delivery)
                        combined_delivery = combined_delivery.combined_delivery
                    end

                    train.last_use_date = gametick
                    train.delivery = nil

                    yutils.read_train_internals(train)
                    if not train.is_empty then
                        logger.report_train_not_empty(delivery)
                    end

                    if check_refuel(train) then return end

                    find_depot_and_route(delivery.provider.network, train, delivery.provider)
                    return
                end
            elseif train.state == defs.train_states.at_refueler then
                local station = train.depot
                clear_device_output(train.refueler)
                train.refueler.train = nil
                train.refueler = nil
                yutils.read_train_internals(train)
                if station then
                    yutils.set_train_composition(train, station)
                    if station.role == buffer_role then
                        train.state = defs.train_states.to_buffer
                        allocator.route_to_station(train, station)
                    elseif station.role == feeder_role then
                        train.state = defs.train_states.to_feeder
                        allocator.route_to_station(train, station)
                    end
                else
                    train.state = defs.train_states.to_depot
                    local network = yutils.get_network(train.train.front_rail)
                    find_depot_and_route(network, train)
                end
            elseif train.state == defs.train_states.feeder_loading then
                train.state = defs.train_states.to_requester
                local delivery = train.delivery
                local ttrain = train.train
                if delivery and ttrain.valid then
                    local existing_content = {}
                    clear_device_output(delivery.provider)
                    for name, count in pairs(ttrain.get_contents()) do
                        existing_content["item/" .. name] = count
                    end
                    for name, count in pairs(ttrain.get_fluid_contents()) do
                        existing_content["fluid/" .. name] = count
                    end
                    scheduler.create_delivery_schedule(delivery,
                        existing_content)
                end
            end
        end
    elseif new_state == defines.train_state.on_the_path and event.old_state == defines.train_state.destination_full then
        local train = context.trains[event.train.id]
        if train and train.state == defs.train_states.at_waiting_station then
            if train.depot then
                yutils.unlink_train_from_depots(train.depot, train)
            end
            train.state = defs.train_states.to_requester
        end
        return
    end
end

---@param event EventData.on_train_created
local function on_train_created(event)
    local context = yutils.get_context()
    if event.old_train_id_1 then
        yutils.remove_train(context.trains[event.old_train_id_1])
    end
    if event.old_train_id_2 then
        yutils.remove_train(context.trains[event.old_train_id_2])
    end
    if event.train then
        local ttrain = event.train
        if not ttrain.manual_mode then
            local trainstop = ttrain.station
            if trainstop then
                local device = context.trainstop_map[trainstop.unit_number]
                if device then
                    if device.role == depot_role then
                        yutils.add_train_to_depot(device, ttrain)
                    elseif device.role == buffer_role then
                        yutils.add_train_to_buffer_feeder(device, ttrain)
                    end
                end
            end
        end
    end
end

---@param e EventData.on_train_schedule_changed
local function on_train_schedule_changed(e)
    if not e.player_index then return end

    if tools.tracing then
        debug("on_train_schedule_changed: tick=" .. e.tick .. ",train=" .. e.train.id)
    end

    local context = yutils.get_context()
    local train = context.trains[e.train.id]
    if not train then return end

    yutils.remove_train(train, true)
end

if not commons.testing then
    tools.on_event(defines.events.on_train_schedule_changed, on_train_schedule_changed)
    tools.on_event(defines.events.on_train_changed_state, on_train_changed_state)
    tools.on_event(defines.events.on_train_created, on_train_created)
else
    ---@param event EventData.on_train_changed_state
    local function on_train_test_changed_state(event)
        local new_state = event.train.state
        if tools.tracing then
            debug("on_train_changed_state: tick=" .. event.tick .. ",train=" .. event.train.id ..
                ",new_state=" .. tools.get_constant_name(new_state, defines.train_state) ..
                ",old_state=" .. tools.get_constant_name(event.old_state, defines.train_state)
            )
        end
    end
    tools.on_event(defines.events.on_train_changed_state, on_train_test_changed_state)
end


local is_train_stuck = yutils.is_train_stuck

---@param train Train
local function process_trains(train)
    if config.disabled then
        return
    end
    if train.train.valid then
        if is_train_stuck(train) then
            logger.report_train_stuck(train)
        end
    else
        yutils.remove_train(train)
    end
end

local function on_load() trains_runtime = Runtime.get("Trains") end
tools.on_load(on_load)

Runtime.register {
    name = "Trains",
    global_name = "Trains",
    process = process_trains,
    ntick = 60,
    max_per_run = 10,
    refresh_rate = 4
}

return train_mgr
