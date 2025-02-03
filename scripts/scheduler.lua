local tools = require("scripts.tools")
local commons = require("scripts.commons")

local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")
local multisurf = require("scripts.multisurf")
local allocator = require("scripts.allocator")
local teleport = require("scripts.teleport")
local trainconf = require("scripts.trainconf")
local Pathing = require("scripts.pathing")

local scheduler = {}

---@type Runtime
local devices_runtime
local devices

local depot_role = defs.device_roles.depot
local buffer_role = defs.device_roles.buffer
local train_available_states = defs.train_available_states
local buffer_feeder_roles = defs.buffer_feeder_roles

local find_train = allocator.find_train
local band = bit32.band

local debug = tools.debug


local find_closest_incoming_rail = Pathing.find_closest_incoming_rail
local device_distance = Pathing.device_distance
local train_distance = Pathing.train_distance


local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

---@type fun():Context
local get_context = yutils.get_context

---@param r1 Request
---@param r2 Request
local function request_compare(r1, r2)
    local d1 = r1.device
    local p1 = (d1.priority_map and d1.priority_map[r1.name]) or d1.priority
    local d2 = r2.device
    local p2 = (d2.priority_map and d2.priority_map[r2.name]) or d2.priority
    if p1 ~= p2 then
        return p1 > p2
    end
    return r1.create_tick < r2.create_tick
end

---@param request Request
---@param forbidden Device?
---@param no_surface_change boolean?
---@return Request?
---@return NetworkConnection?
local function find_provider(request, forbidden, no_surface_change)
    local candidate
    local candidate_priority
    local candidate_dist
    local device = request.device
    local device_role = device.role
    local network = device.network

    ---@param production Request
    ---@param dist number
    ---@return boolean?
    local function check_production(production, dist)
        local production_device = production.device

        if candidate then
            local pdevice = production.device
            local production_priority = (pdevice.priority_map and pdevice.priority_map[production.name]) or pdevice.priority

            if dist > candidate_dist then
                if candidate_priority >= production_priority then
                    production_device.failcode = 40
                    return
                end
            else
                if candidate_priority > production_priority then
                    production_device.failcode = 40
                    return
                end
            end
        end

        if buffer_feeder_roles[production_device.role] then
            if buffer_feeder_roles[device_role] then
                production_device.failcode = 42
                return
            end
            local train = production_device.train
            if not train then
                production_device.failcode = 43
                request.failcode = 43
                return
            end
            if not train_available_states[train.state] then
                production_device.failcode = production_device.failcode or 44
                request.failcode = request.failcode or 44
                return
            end
            if not train.has_fuel then
                production_device.failcode = 45
                request.failcode = 45
                return
            end
            if not defs.train_at_station[train.state] and train.front_stock.valid then
                dist = train_distance(train, device)
                if dist < 0 then return end

                if candidate then
                    local pdevice = production.device
                    local production_priority = (pdevice.priority_map and pdevice.priority_map[production.name]) or pdevice.priority
                    if dist > candidate_dist then
                        if candidate_priority >= production_priority then
                            pdevice.failcode = 46
                            return
                        end
                    else
                        if candidate_priority > production_priority then
                            pdevice.failcode = 46
                            return
                        end
                    end
                end
            end
        end

        local available = production.provided - production.requested
        if available < request.threshold then
            production_device.failcode = 48
            request.failcode = 48
            return
        end

        local delivery_count = table_size(production_device.deliveries)
        if delivery_count >= 1 then
            if production_device.max_delivery and delivery_count >= production_device.max_delivery then
                production_device.failcode = 82
                return
            end

            dist = dist + delivery_count * (production_device.delivery_penalty or config.delivery_penalty)
            if candidate_dist and dist >= candidate_dist then
                production_device.failcode = 49
                return
            end
        end

        if band(production_device.network_mask, device.network_mask) == 0 then
            production_device.failcode = 50
            request.failcode = 50
            return
        end

        if device.patterns and production_device.patterns then
            local compatible
            for pattern, _ in pairs(production_device.patterns) do
                if device.patterns[pattern] then
                    goto match
                end
                local generic = PatternCache[pattern]
                if generic and device.patterns[generic] then
                    goto match
                end
            end
            if not compatible then
                if device.has_specific_pattern then
                    for pattern, _ in pairs(device.patterns) do
                        local generic = PatternCache[pattern]
                        if generic and production_device.patterns[generic] then
                            goto match
                        end
                    end
                end
                request.failcode = 52
                return
            end
            ::match::
        end

        if production_device.freezed then
            production_device.failcode = 54
            request.failcode = 54
            return
        end

        if not production_device.trainstop.connected_rail then
            production_device.failcode = 55
            request.failcode = 55
            return
        end

        if production_device.inactive then
            production_device.failcode = 56
            request.failcode = 56
            return
        end

        if production_device == forbidden then
            return
        end

        candidate = production
        candidate_dist = dist
        local dev = production.device
        candidate_priority = (dev.priority_map and dev.priority_map[production.name]) or dev.priority
        return true
    end

    local productions = network.productions[request.name]
    if productions then
        for _, production in pairs(productions) do
            local production_device = production.device
            local dist

            if production_device.distance_cache then
                dist = production_device.distance_cache[device.id]
            end
            if not dist then
                dist = device_distance(production_device, device)
            end

            if dist > 0 then
                check_production(production, dist)
            else
                request.failcode = 57
            end
        end
        if candidate then
            return candidate
        end
    end

    if no_surface_change then
        return nil
    end
    network = network.connected_network
    if not network then
        return nil
    end

    productions = network.productions[request.name]
    if not productions or not next(productions) then
        return
    end

    local index = find_closest_incoming_rail(device)
    if not index then
        return nil
    end

    local trainstop = network.connecting_trainstops[index]
    if not trainstop then
        return nil
    end
    for _, production in pairs(productions) do
        local production_device = production.device
        local dist
        if production_device.distance_cache then
            dist = production_device.distance_cache[trainstop.unit_number]
        end
        if not dist then
            dist = Pathing.device_trainstop_distance(production_device, trainstop)
        end
        if dist > 0 then
            check_production(production, dist)
        end
    end
    return candidate
end

scheduler.find_provider = find_provider

---@param delivery Delivery
---@param existing_content table<string, integer>
function scheduler.create_delivery_schedule(delivery, existing_content)
    local provider = delivery.provider
    local requester = delivery.requester
    local train = delivery.train

    ---@type ScheduleRecord[][]
    local splitted_schedule = {}

    ---@type ScheduleRecord[]
    local records = {}
    local teleport_pos = train.front_stock.position

    -- goto provider
    if not buffer_feeder_roles[delivery.provider.role] then
        local load_condition = {}
        for name, count in pairs(delivery.content) do
            local signal = tools.id_to_signal(name)
            ---@cast signal -nil
            if existing_content then
                count = count + (existing_content[name] or 0)
            end
            table.insert(load_condition, {
                type = signal.type .. "_count",
                compare_type = "and",
                condition = {
                    comparator = ">=",
                    first_signal = signal,
                    constant = count
                }
            })
        end

        if provider.inactivity_delay and provider.inactivity_delay > 0 then
            table.insert(load_condition, {
                type = "inactivity",
                compare_type = "and",
                ticks = 60 * provider.inactivity_delay
            })
        end

        if USE_SE then
            local front_stock = delivery.train.front_stock
            if front_stock.surface_index ~= provider.network.surface_index then
                local from_network = yutils.get_network_base(front_stock.force_index, front_stock.surface_index)
                local station = multisurf.add_cross_network_trainstop(from_network, front_stock.position, records)
                if station then teleport_pos = station.position end
                table.insert(records, {
                    station = provider.trainstop.backer_name,
                    wait_conditions = load_condition
                })
                table.insert(splitted_schedule, records)
                records = {}
            end
        end

        teleport.add_teleporter(provider.network, teleport_pos, provider.position, records)

        local backer_name = provider.trainstop.backer_name
        local needed
        if config.allow_trainstop_name_routing then
            local station_list = game.train_manager.get_train_stops { 
                surface = provider.trainstop.surface, station_name = backer_name, force = provider.trainstop.force }
            needed = #station_list > 1
        else
            needed = true
        end
        if needed then
            table.insert(records, {
                rail = provider.trainstop.connected_rail,
                temporary = true,
                rail_direction = provider.trainstop.connected_rail_direction,
                wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
            })
        end


        table.insert(records, {
            station = backer_name,
            wait_conditions = load_condition
        })
        teleport_pos = provider.position

        if requester.role == buffer_role then
            table.insert(records, {
                rail = provider.trainstop.connected_rail,
                temporary = true,
                rail_direction = provider.trainstop.connected_rail_direction,
                wait_conditions = {
                    { type = "time", compare_type = "and", ticks = 1 }
                }
            })
        end
    else
        train.state = defs.train_states.to_requester
    end

    if (USE_SE) then
        if (provider.network.surface_index ~= requester.network.surface_index) then
            local front_stock = delivery.train.front_stock

            local index = #records + 1
            local station = multisurf.add_cross_network_trainstop(
                provider.network, front_stock.position, records)
            if station then teleport_pos = station.position end
            table.insert(records, {
                station = delivery.requester.trainstop.backer_name,
                wait_conditions = { { type = "empty", compare_type = "and" } }
            })
            table.insert(splitted_schedule, records)
            records = {}
        end
    end

    if delivery.requester.role ~= buffer_role then
        teleport.add_teleporter(requester.network, teleport_pos,
            requester.position, records)


        local backer_name = requester.trainstop.backer_name
        local needed
        if config.allow_trainstop_name_routing then
            local station_list = game.train_manager.get_train_stops { 
                surface =  requester.trainstop.surface,
                station_name = backer_name, 
                force = requester.trainstop.force }
            needed = #station_list > 1
        else
            needed = true
        end
        if needed then
            table.insert(records, {
                rail = requester.trainstop.connected_rail,
                temporary = true,
                rail_direction = requester.trainstop.connected_rail_direction,
                wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
            })
        end

        if requester.inactivity_delay then
            table.insert(records, {
                station = backer_name,
                wait_conditions = {
                    {
                        type = "inactivity",
                        compare_type = "and",
                        ticks = requester.inactivity_delay * 60
                    }
                }
            })
        else
            if not buffer_feeder_roles[provider.role] then
                table.insert(records, {
                    station = requester.trainstop.backer_name,
                    wait_conditions = { { type = "empty", compare_type = "and" } }
                })
            else
                table.insert(records, {
                    station = requester.trainstop.backer_name,
                    wait_conditions = {}
                })
            end
        end

        if buffer_feeder_roles[provider.role] then
            local unload_conditions = records[#records].wait_conditions
            for name, count in pairs(delivery.content) do
                local signal = tools.id_to_signal(name)
                ---@cast signal -nil
                if existing_content then
                    count = (existing_content[name] or 0) - count
                end

                local condition
                if count > 0 then
                    condition = {
                        comparator = "<=",
                        first_signal = signal,
                        constant = count
                    }
                else
                    condition = {
                        comparator = "=",
                        first_signal = signal,
                        constant = 0
                    }
                end
                table.insert(unload_conditions, {
                    type = signal.type .. "_count",
                    compare_type = "and",
                    condition = condition
                })
            end

            table.insert(records, {
                rail = requester.trainstop.connected_rail,
                temporary = true,
                rail_direction = requester.trainstop.connected_rail_direction,
                wait_conditions = {
                    { type = "time", compare_type = "and", ticks = 1 }
                }
            })

            -- to display station
            table.insert(records, {
                station = provider.trainstop.backer_name,
                wait_conditions = {
                    { type = "time", compare_type = "and", ticks = 1 }
                }
            })
        end
    else
        -- to display station
        table.insert(records, {
            station = requester.trainstop.backer_name,
            wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
        })
    end

    if #splitted_schedule > 0 then
        if not buffer_feeder_roles[requester.role] then
            table.insert(records, {
                rail = requester.trainstop.connected_rail,
                temporary = true,
                rail_direction = requester.trainstop.connected_rail_direction,
                wait_conditions = {
                    { type = "time", compare_type = "and", ticks = 1 }
                }
            })
        end
        table.insert(splitted_schedule, records)
        records = splitted_schedule[1]
        table.remove(splitted_schedule, 1)
        train.splitted_schedule = splitted_schedule
    else
        train.splitted_schedule = nil
    end

    local schedule = { current = 1, records = records }

    -- schedule = { current = 1, records = { { station = "Temp", wait_conditions = { { type = "empty", compare_type = "and" } } } } }
    train.train.schedule = schedule
end

---@param request Request
---@param candidate Request
---@param train Train
---@return table<string, integer>
function scheduler.create_payload(request, candidate, train, available_slots)
    local content = {}
    local signal = tools.id_to_signal(request.name)
    ---@cast signal -nil

    local available_amount = candidate.provided - candidate.requested
    local amount
    amount = request.requested - request.provided
    if amount > available_amount then
        amount = available_amount
    end

    local capacity
    local fluid_capacity = train.fluid_capacity

    if signal.type == "item" then
        local stack_size = prototypes.item[signal.name].stack_size
        local locked_slots = 0
        if train.cargo_count > 0 then
            locked_slots = (candidate.device.locked_slots or 0) * train.cargo_count
        end
        available_slots = available_slots - locked_slots
        capacity = available_slots * stack_size
        local slot_count = math.floor(amount / stack_size)
        if slot_count == 0 then
            slot_count = 1
        else
            amount = slot_count * stack_size
        end
        available_slots = available_slots - slot_count
    else
        capacity = fluid_capacity
        fluid_capacity = 0
    end

    amount = math.min(amount, capacity)
    if amount == 0 then
        log("error")
    end
    content[request.name] = amount
    request.provided = request.provided + amount
    candidate.requested = candidate.requested + amount

    if table_size(request.device.requested_items) > 1 then
        for other_name, other_request in pairs(request.device.requested_items) do
            if other_name ~= request.name then
                local other_candidate = candidate.device.produced_items[other_name]
                if other_candidate then
                    local other_signal = tools.id_to_signal(other_name)
                    ---@cast other_signal -nil

                    available_amount = other_candidate.provided - other_candidate.requested
                    amount = other_request.requested - other_request.provided
                    if amount > available_amount then
                        amount = available_amount
                    end

                    local train_size
                    if other_signal.type == "item" then
                        local stack_size = prototypes.item[other_signal.name].stack_size
                        train_size = available_slots * stack_size
                        if available_slots <= 0 then
                            goto next_r
                        end
                        local slot_count = math.floor(amount / stack_size)
                        if slot_count == 0 then
                            slot_count = 1
                        else
                            amount = slot_count * stack_size
                        end
                        available_slots = available_slots - slot_count
                    else
                        if fluid_capacity == 0 then
                            goto next_r
                        end
                        train_size = fluid_capacity
                        fluid_capacity = 0
                    end

                    if amount > train_size then
                        amount = train_size
                    end
                    if amount > 0 then
                        content[other_name] = amount
                        other_request.provided = other_request.provided + amount
                        other_candidate.requested = other_candidate.requested + amount
                    end
                end
            end
            ::next_r::
        end
    end
    return content
end

local create_payload = scheduler.create_payload

---@param request Request
---@param candidate Request
---@param train Train
---@param content table<string, integer>
---@param existing_content table<string, integer>
---@return Delivery
local function create_delivery(request, candidate, train, content, existing_content)
    if tools.tracing then
        debug("create_delivery:" .. request.name .. "=" .. request.requested)
    end
    local device = request.device
    local context = get_context()
    local delivery_id = context.delivery_id
    local gametick = game.tick
    ---@type Delivery
    local delivery = {
        content = content,
        provider = candidate.device,
        requester = request.device,
        train = train,
        start_tick = gametick,
        id = delivery_id,
        combined_delivery = train.delivery
    }
    context.delivery_id = delivery_id + 1
    request.producer_failed_logged = nil
    request.train_notfound_logged = nil
    logger.report_delivery_creation(delivery)

    train.timeout_delay = (device.delivery_timeout or config.delivery_timeout) * 60
    train.timeout_tick = gametick + train.timeout_delay
    train.timeout_pos = train.front_stock.position
    train.active_reported = nil
    request.device.deliveries[train.id] = delivery
    request.create_tick = gametick
    candidate.device.deliveries[train.id] = delivery
    train.delivery = delivery
    train.last_delivery = delivery

    train.state = defs.train_states.to_producer
    local candidate_device = candidate.device
    candidate_device.inactivity_delay = nil
    scheduler.create_delivery_schedule(delivery, existing_content)

    if device.network.reservations then
        device.network.reservations[request.name] = nil
    end

    local station = train.depot
    if not train.train.has_path and station then
        local schedule = train.train.schedule
        ---@cast schedule -nil
        table.insert(schedule.records, 1, {
            rail = station.trainstop.connected_rail,
            temporary = true,
            rail_direction = station.trainstop.connected_rail_direction
        })
        train.train.schedule = schedule
        station.freezed = true
    else
        if buffer_feeder_roles[candidate_device.role] then
            local empty = true
            if not candidate_device.station_locked then
                for _, p in pairs(candidate_device.produced_items) do
                    if p.provided ~= p.requested then
                        empty = false
                        break
                    end
                end
            end
            if train.state ~= defs.train_states.feeder_loading then
                train.state = defs.train_states.to_requester
            end
            if not candidate_device.station_locked then
                if empty then
                    if station then
                        yutils.unlink_train_from_buffer(station)
                        yutils.clear_production(station)
                    end
                end
            end
        else
            yutils.unlink_train_from_depots(station, train)
        end
    end
    return delivery
end
scheduler.create_delivery = create_delivery

---@param request Request
function scheduler.process_request(request)
    local device = request.device
    local context = get_context()

    if tools.tracing then
        tools.debug("scheduler.process_request: " .. request.name .. "=" .. request.requested)
    end

    request.inqueue = false
    request.failcode = nil
    request.device.failcode = nil
    if not device.entity or not device.entity.valid then return end

    if device.network.reservations_tick == context.session_tick then
        if device.network.reservations and device.network.reservations[request.name] then
            request.failcode = 81
            return
        end
    else
        device.network.reservations = nil
    end

    if request.cancelled then return end

    if device.network.disabled then return end

    if device.inactive then
        return
    end

    if buffer_feeder_roles[device.role] and device.train and
        not train_available_states[device.train.state] then
        return
    end

    if device.max_delivery and table_size(device.deliveries) >=
        device.max_delivery then
        return
    end

    if device.train and device.train.delivery then return end

    if not device.trainstop.connected_rail then return end

    local requested = request.requested - request.provided
    if requested < request.threshold then return end

    local candidate = find_provider(request)
    if not candidate then
        if device.reservation then
            if device.network.reservations_tick == context.session_tick then
                device.network.reservations[request.name] = true
            else
                device.network.reservations = { [request.name] = true }
                device.network.reservations_tick = context.session_tick
            end
        end
        if not request.producer_failed_logged then
            logger.report_producer_notfound(request)
        end
        table.insert(context.waiting_requests, request)
        request.inqueue = true
        return
    end

    -- find train
    candidate.failcode = nil
    local candidate_device = candidate.device

    ---@type Train?
    local train

    local reserved_slot = 0
    local reserved_fluid = 0
    local existing_content
    local is_item = string.sub(request.name, 1, 1) == "i"
    if not buffer_feeder_roles[device.role] and not buffer_feeder_roles[candidate_device.role] then
        local patterns = trainconf.intersect_patterns(device.patterns, candidate_device.patterns)
        candidate_device.failcode = nil
        train = find_train(candidate_device, patterns, is_item)
        if not train then
            if not request.train_notfound_logged then
                logger.report_train_notfound(request)
            end
            table.insert(context.waiting_requests, request)
            request.inqueue = true
            request.failcode = candidate_device.failcode or 60
            return
        end
        ::train_found::
    elseif buffer_feeder_roles[candidate_device.role] then
        train = candidate_device.train
        if not train then
            request.failcode = 60
            return
        end

        local ttrain = train.train
        if not ttrain.valid then
            request.failcode = 60
            yutils.remove_train(train, true)
            return
        end
        existing_content = {}
        for _, item in pairs(ttrain.get_contents()) do
            local signalid = tools.signal_to_id(item)
            ---@cast signalid -nil
            existing_content[signalid] = item.count
            local produced = device.produced_items[signalid]
            if produced then produced.provided = item.count end
        end
        for name, count in pairs(ttrain.get_fluid_contents()) do
            local sname = "fluid/" .. name
            existing_content[sname] = count
            local produced = device.produced_items[sname]
            if produced then produced.provided = count end
        end
    elseif device.role == buffer_role then
        train = device.train
        if not train then
            train = find_train(candidate_device, device.patterns, is_item)
            if not train then
                request.failcode = 60
                return
            end
            yutils.unlink_train_from_depots(train.depot, train)
            yutils.link_train_to_buffer(device, train)
        end

        local ttrain = train.train
        if not ttrain.valid then
            request.failcode = 60
            yutils.remove_train(train, true)
            return
        end
        existing_content = {}
        for _, item in pairs(ttrain.get_contents()) do
            local signalid = tools.signal_to_id(item)
            ---@cast signalid -nil
            local name = item.name
            local count = item.count
            reserved_slot = reserved_slot + math.ceil(count / prototypes.item[name].stack_size)
            existing_content[signalid] = count
            local produced = device.produced_items[signalid]
            if produced then produced.provided = count end
        end
        for name, count in pairs(ttrain.get_fluid_contents()) do
            reserved_fluid = reserved_fluid + count
            local sname = "fluid/" .. name
            existing_content[sname] = count
            local produced = device.produced_items[sname]
            if produced then produced.provided = count end
        end
    end

    ---@cast train -nil

    local content = {}
    if buffer_feeder_roles[candidate_device.role] then
        content = {}
        local available_amount = candidate.provided - candidate.requested
        local amount = request.requested - request.provided
        if amount > available_amount then
            amount = available_amount
        end
        content[request.name] = amount
        request.provided = request.provided + amount
        candidate.requested = candidate.requested + amount
        if table_size(request.device.requested_items) > 1 then
            for other_name, other_request in pairs(request.device.requested_items) do
                if other_name ~= request.name then
                    local other_candidate = candidate.device.produced_items[other_name]
                    if other_candidate then
                        amount = other_request.requested - other_request.provided
                        available_amount = other_candidate.provided - other_candidate.requested
                        if amount > available_amount then
                            amount = available_amount
                        end

                        if amount > 0 then
                            content[other_name] = amount
                            other_request.provided = other_request.provided + amount
                            other_candidate.requested = other_candidate.requested + amount
                        end
                    end
                end
            end
        end
    else
        local available_slots = train.slot_count - reserved_slot
        content = create_payload(request, candidate, train, available_slots)
    end

    create_delivery(request, candidate, train, content, existing_content)

    if tools.tracing then
        debug("create_delivery: request=" .. request.name .. ",count=" .. request.requested)
    end
end

---@param data NthTickEventData
function scheduler.process(data)
    local context = get_context()
    if config.disabled then return end

    if not context.running_requests then
        local waiting_requests = context.waiting_requests

        if not waiting_requests or table_size(waiting_requests) == 0 then
            return
        end

        context.running_requests = waiting_requests
        context.running_index = 1
        context.waiting_requests = {}
        table.sort(context.running_requests, request_compare)

        context.request_per_iteration = #context.running_requests / 12
        context.request_iter = 0
        context.session_tick = game.tick
        if tools.tracing then
            tools.debug("scheduler.process: (context.running_requests)")
        end
    end

    context.request_iter = context.request_iter + context.request_per_iteration
    while context.request_iter >= 1 do
        if context.running_index > #context.running_requests then
            context.running_requests = nil
            return
        end

        local request = context.running_requests[context.running_index]
        scheduler.process_request(request)
        context.running_index = context.running_index + 1
        context.request_iter = context.request_iter - 1
    end
end

tools.on_nth_tick(5, scheduler.process)

return scheduler
