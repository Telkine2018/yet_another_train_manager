local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local config = require("scripts.config")
local Runtime = require("scripts.runtime")
local spatial_index = require("scripts.spatial_index")
local yutils = require("scripts.yutils")
local teleport = require("scripts.teleport")
local trainconf = require("scripts.trainconf")
local pathing = require("scripts.pathing")


local allocator = {}

local band = bit32.band
local distance2 = tools.distance2
local builder_penalty = 90

---@type Runtime
local trains_runtime

local depot_role = defs.device_roles.depot
local builder_role = defs.device_roles.builder
local feeder_role = defs.device_roles.feeder

---@param depot Device
---@return integer
local function get_create_count(depot)
    return (depot.create_count or 0) - (depot.trains and table_size(depot.trains) or 0)
end
allocator.get_create_count = get_create_count

---@param network SurfaceNetwork
---@param train Train
---@param device Device?
---@param is_parking boolean ?
---@return Device?
function allocator.find_free_depot(network, train, device, is_parking)
    local min_depot
    local min_d
    local min_priority
    local network_mask = train.network_mask

    ---@param depot Device
    local function check_depot(depot)
        if band(network_mask, depot.network_mask) == 0 then
            depot.failcode = 63
            return false
        end
        local patterns = depot.patterns
        if patterns and not (patterns[train.gpattern] or patterns[train.rpattern]) then
            depot.failcode = 64
            return false
        end

        if not depot.trainstop.connected_rail then
            depot.failcode = 67
            return false
        end

        if depot.builder_stop_remove then
            depot.failcode = 68
            return false
        end

        if depot.inactive then
            depot.failcode = 69
            return false
        end

        if depot.role == defs.device_roles.builder then
            if is_parking then return false end
            if not depot.no_remove_constraint then
                local create_count = (depot.create_count or 0) - (depot.trains and table_size(depot.trains) or 0)
                if create_count <= 0 then
                    depot.failcode = 70
                    return false
                end
            end
        end
        return true
    end

    if device and device.trainstop and device.trainstop.connected_rail then
        for _, depot in pairs(network.free_depots) do
            if depot.train == nil then
                local d
                if depot.distance_cache then
                    d = depot.distance_cache[device.id]
                end
                if not d then
                    if not depot.trainstop.connected_rail then
                        goto skip
                    end
                    d = pathing.device_distance(depot, device)
                end

                if d < 0 then
                    depot.failcode = 80
                    goto skip
                end

                local depot_priority
                if depot.role == builder_role then
                    d = d + builder_penalty

                    depot_priority = depot.rpriority or 0
                    if min_priority then
                        if min_priority > depot_priority then
                            depot.failcode = 61
                            goto skip
                        elseif min_priority == depot_priority and d > min_d then
                            depot.failcode = 62
                            goto skip
                        end
                    end
                else
                    if depot.parking_penalty then
                        if is_parking then
                            d = d - depot.parking_penalty
                            if d < 0 then
                                d = 0
                            end
                        else
                            d = d + depot.parking_penalty
                        end
                    end

                    depot_priority = 0
                    if not is_parking then
                        depot_priority = depot.priority
                        if min_priority then
                            if min_priority > depot_priority then
                                depot.failcode = 61
                                goto skip
                            elseif min_priority == depot_priority and d > min_d then
                                depot.failcode = 62
                                goto skip
                            end
                        end
                    else
                        if min_d and d > min_d then
                            depot.failcode = 62
                            goto skip
                        end
                    end
                end

                if check_depot(depot) then
                    min_depot = depot
                    min_d = d
                    min_priority = depot_priority
                end
            end
            ::skip::
        end

        if min_depot then
            min_depot.last_used_date = GAMETICK
            return min_depot
        end
        local connected_network = network.connected_network
        if connected_network then
            local index = pathing.find_closest_exiting_trainstop(device)
            if not index then return nil end

            local output = connected_network.connecting_outputs[index]
            local id = -output.unit_number
            for _, depot in pairs(connected_network.free_depots) do
                if depot.train == nil then
                    local d
                    if device.distance_cache then
                        d = device.distance_cache[id]
                    end
                    if not d then
                        if not depot.trainstop.connected_rail then
                            goto skip
                        end
                        d = pathing.rail_device_distance(output, depot)
                    end
                    if d < 0 then
                        goto skip
                    end
                    if depot.role == builder_role then
                        d = d + builder_penalty
                    end
                    if min_priority then
                        if min_priority > depot.priority then
                            depot.failcode = 61
                            goto skip
                        elseif min_priority == depot.priority and d > min_d then
                            depot.failcode = 62
                            goto skip
                        end
                    end
                    if check_depot(depot) then
                        min_depot = depot
                        min_d = d
                        min_priority = depot.priority
                    end
                end
                ::skip::
            end

            if min_depot then
                min_depot.last_used_date = GAMETICK
                return min_depot
            end
        end
    end

    local depot_list = {}
    local goals = {}
    for _, depot in pairs(network.free_depots) do
        if depot.trainstop.valid and depot.trainstop.connected_rail and check_depot(depot) then
            table.insert(depot_list, depot)
            table.insert(goals, { train_stop = depot.trainstop })
        end
    end
    local goal_count = table_size(goals)
    if goal_count == 0 then
        return nil
    elseif goal_count == 1 then
        return depot_list[1]
    end
    local result = game.request_train_path {
        goals = goals,
        train = train.train,
        type = "any-goal-accessible"
    }
    if result.found_path then
        return depot_list[result.goal_index]
    end
    return nil
end

local device_distance = pathing.device_distance

---@param device Device
---@param network_mask integer
---@param patterns {[string]:boolean}?
---@param is_item boolean?
function allocator.find_train(device, network_mask, patterns, is_item)
    local network = device.network

    local min_dist
    local min_priority
    local min_train
    local min_builder

    local pending_trains = {}

    local dst_id = device.id
    local dst_position = device.position
    local f_effective_distance = function(candidate)
        return device_distance(candidate, device)
    end
    local f_train_distance = function(train)
        return pathing.train_distance(train, device)
    end

    ---@param candidate Device
    ---@param train Train
    ---@return boolean
    local function test_train(candidate, train)
        if train and train.has_fuel and train.is_empty and
            not train.teleporting then
            local ttrain = train.train
            if ttrain.valid then
                local d
                if defs.train_at_station[train.state] then
                    if candidate.distance_cache then
                        d = candidate.distance_cache[dst_id]
                    end
                    if not d then
                        if not candidate.trainstop.connected_rail then
                            goto skip
                        end
                        d = f_effective_distance(candidate)
                    end
                else
                    if pending_trains then
                        table.insert(pending_trains, train)
                        goto skip
                    end

                    local cart_dist = tools.distance(train.front_stock.position, dst_position)
                    if min_dist and cart_dist >= min_dist then
                        goto skip
                    end

                    d = f_train_distance(train)
                end
                if d < 0 then
                    candidate.failcode = 80
                    device.failcode = device.failcode or candidate.failcode
                    goto skip
                end

                if min_dist and
                    (min_priority > candidate.priority or (d > min_dist and min_priority == candidate.priority)) then
                    candidate.failcode = 20
                    goto skip
                end

                if USE_SE then
                    if candidate.network.surface_index ~= train.front_stock.surface_index then
                        candidate.failcode = 21
                        goto skip
                    end
                end

                if candidate.freezed then goto skip end

                if patterns and not (patterns[train.gpattern] or patterns[train.rpattern]) then
                    candidate.failcode = 22
                    device.failcode = device.failcode or candidate.failcode
                    goto skip
                end

                if band(network_mask, train.network_mask) == 0 then
                    candidate.failcode = 23
                    device.failcode = device.failcode or candidate.failcode
                    goto skip
                end

                if candidate.inactive then
                    candidate.failcode = 27
                    device.failcode = device.failcode or candidate.failcode
                    goto skip
                end

                if not defs.train_available_states[train.state] then
                    goto skip
                end

                if is_item ~= nil then
                    if is_item then
                        if train.slot_count == 0 then
                            goto skip
                        end
                    else
                        if train.fluid_capacity == 0 then
                            goto skip
                        end
                    end
                end

                min_dist = d
                min_priority = candidate.priority
                min_train = train
                min_builder = nil
                return true
            end
        else
            candidate.failcode = 28
        end
        ::skip::
        return false
    end

    ---@param builder Device
    local function test_builder(builder)
        if builder.trains then
            for _, train in pairs(builder.trains) do
                test_train(builder, train)
            end
        end

        if builder.builder_stop_create then
            builder.failcode = 30
            goto skip_builder
        end

        local d
        if builder.distance_cache then
            d = builder.distance_cache[dst_id]
        end
        if not d then
            if not builder.trainstop.connected_rail then
                goto skip_builder
            end
            d = f_effective_distance(builder)
        end
        if d < 0 then
            goto skip_builder
        end
        d = d + builder_penalty

        if min_dist and (builder.priority < min_priority or (d > min_dist and min_priority == builder.priority)) then
            builder.failcode = 31
            goto skip_builder
        end

        if builder.freezed then goto skip_builder end

        if band(network_mask, builder.network_mask) == 0 then
            builder.failcode = 32
            goto skip_builder
        end

        if not builder.builder_pattern then
            builder.failcode = 34
            goto skip_builder
        end

        if patterns and not (patterns[builder.builder_pattern] or patterns[builder.builder_gpattern]) then
            builder.failcode = 33
            goto skip_builder
        end

        if builder.inactive then
            builder.failcode = 36
            goto skip_builder
        end

        if is_item ~= nil then
            if is_item then
                if builder.builder_cargo_count == 0 then
                    goto skip_builder
                end
            else
                if builder.builder_fluid_count == 0 then
                    goto skip_builder
                end
            end
        end

        if not allocator.builder_is_available(builder) then
            goto skip_builder
        end

        min_dist = d
        min_builder = builder
        min_train = nil
        min_priority = builder.priority
        ::skip_builder::
    end

    for _, depot in pairs(network.used_depots) do
        local train = depot.train

        depot.failcode = nil
        if depot.trainstop.connected_rail then
            test_train(depot, train)
            if depot.role == builder_role then
                test_builder(depot)
            end
        end
    end

    if pending_trains then
        local train_to_scan = pending_trains
        pending_trains = nil
        for _, train in pairs(train_to_scan) do
            test_train(train.depot, train)
        end
    end
    if min_train then
        min_train.last_use_date = GAMETICK
        if min_train.depot then
            min_train.depot.last_used_date = GAMETICK
        end
        return min_train
    end

    if min_builder then
        return allocator.builder_create_train(min_builder)
    end

    -- switch to connected netwok
    network = network.connected_network
    if not network then return nil end

    local index = pathing.find_closest_incoming_rail(device)
    if not index then
        return nil
    end

    local trainstop = network.connecting_trainstops[index]

    --- Reset variable
    dst_id = trainstop.unit_number
    dst_position = trainstop.position
    f_effective_distance = function(candidate)
        return pathing.device_trainstop_distance(candidate, trainstop)
    end
    f_train_distance = function(train)
        return pathing.train_trainstop_distance(train, trainstop)
    end
    pending_trains = {}

    for _, depot in pairs(network.used_depots) do
        local train = depot.train

        depot.failcode = nil
        test_train(depot, train)
        if depot.role == builder_role then
            test_builder(depot)
        end
    end

    if pending_trains then
        local train_to_scan = pending_trains
        pending_trains = nil
        for _, train in pairs(train_to_scan) do
            test_train(train.depot, train)
        end
    end
    if min_train then
        min_train.last_use_date = GAMETICK
        if min_train.depot then
            min_train.depot.last_used_date = GAMETICK
        end
        return min_train
    end

    if min_builder then
        return allocator.builder_create_train(min_builder)
    end

    return nil
end

---@param builder Device
---@return LuaEntity
local function get_builder_container(builder)
    local area = yutils.get_device_area(builder)
    local containers = builder.entity.surface.find_entities_filtered {
        type = { "container", "logistic-container", "linked-container" },
        area = area
    }
    local min_dist, min_container
    for _, container in pairs(containers) do
        local dist = tools.distance2(container.position, builder.position)
        if not min_container or dist < min_dist then
            min_dist = dist
            min_container = container
        end
    end
    return min_container
end

---@param builder Device
function allocator.builder_is_available(builder)
    builder.failcode = nil
    if not (builder.trainstop and builder.trainstop.valid) then
        builder.failcode = 10
        return false
    end

    local container = get_builder_container(builder)
    if not container then
        builder.failcode = 11
        return false
    end

    local inv = container.get_inventory(defines.inventory.chest)
    if inv then
        local content = inv.get_contents()

        for name, count in pairs(builder.builder_parts) do
            local existing = content[name] or 0
            if existing < count then
                builder.failcode = 13
                return false
            end
        end

        local fuel_count = content[builder.builder_fuel_item] or 0
        if fuel_count < builder.builder_fuel_count then
            builder.failcode = 16
            return false
        end
    else
        builder.failcode = 12
        return false
    end

    local count = builder.entity.surface.count_entities_filtered {
        type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
        area = builder.builder_area
    }
    if count > 0 then
        builder.failcode = 17
        return false
    end

    return true
end

local builder_directions = {
    [defines.direction.north] = { x = 0, y = 1 },
    [defines.direction.west] = { x = 1, y = 0 },
    [defines.direction.east] = { x = -1, y = 0 },
    [defines.direction.south] = { x = 0, y = -1 }
}

local builder_ortho_directions = {
    [defines.direction.north] = { x = 1, y = 0 },
    [defines.direction.west] = { x = 0, y = 1 },
    [defines.direction.east] = { x = 0, y = 1 },
    [defines.direction.south] = { x = 1, y = 0 }
}

---@param builder Device
---@return Train?
function allocator.builder_create_train(builder)
    local trainstop = builder.trainstop
    if not trainstop.connected_rail then
        return nil
    end
    local pos = trainstop.connected_rail.position
    local base_direction = trainstop.direction
    local move = builder_directions[base_direction]
    local xcoef, ycoef = move.x, move.y

    local surface = builder.entity.surface
    local first

    local pattern = builder.builder_pattern

    local content = {}

    ---@type LuaEntity[]
    local stock_list = {}
    local elements = trainconf.split_pattern(pattern)

    for _, element in pairs(elements) do
        for i = 1, element.count do
            local direction = base_direction
            local name
            local connect_direction = defines.rail_direction.front

            name = element.type
            if element.is_back then
                direction = tools.opposite_directions[direction]
                connect_direction = defines.rail_direction.back
            end

            content[name] = (content[name] or 0) + 1
            local size = 6 / 2
            pos = { x = pos.x + xcoef * size, y = pos.y + ycoef * size }
            local entity = surface.create_entity {
                name = name,
                position = pos,
                direction = direction,
                force = builder.entity.force
            }

            if not entity then
                for _, s in pairs(stock_list) do
                    s.destroy()
                end
                return nil
            end

            table.insert(stock_list, entity)
            ---@cast entity -nil

            if entity.type == "locomotive" and builder.builder_fuel_item then
                local inv = entity.get_inventory(defines.inventory.fuel) --[[@as LuaInventory]]
                local stack_size = game.item_prototypes[builder.builder_fuel_item].stack_size
                local count = stack_size * #inv
                inv.insert({ name = builder.builder_fuel_item, count = count })
                content[builder.builder_fuel_item] = (content[builder.builder_fuel_item] or 0) + count
            end

            if not first then
                first = entity
            else
                entity.connect_rolling_stock(connect_direction)
            end

            pos = { x = pos.x + xcoef * (size + 1), y = pos.y + ycoef * (size + 1) }
        end
    end

    -- remove used items
    local container = get_builder_container(builder)
    if container then
        local inv = container.get_inventory(defines.inventory.chest)
        if inv then
            for name, count in pairs(content) do
                inv.remove({ name = name, count = count })
            end
        end
    end

    if not first then return nil end

    local ttrain = first.train
    ttrain.manual_mode = false

    local train = yutils.create_train(ttrain, builder)
    trains_runtime:add(train)
    train.state = defs.train_states.to_requester
    yutils.read_train_internals(train)
    local create_count = builder.create_count or 0
    builder.create_count = create_count + 1
    builder.builder_create_count = (builder.builder_create_count or 0) + 1
    return train
end

---@param builder Device
---@return boolean
function allocator.builder_compute_conf(builder)
    local elements = trainconf.split_pattern(builder.builder_pattern)
    local content = trainconf.get_train_content(elements)
    builder.builder_parts = content

    local stack_size = builder.builder_fuel_item and game.item_prototypes[builder.builder_fuel_item].stack_size or 0
    local fuel_count = 0
    local stock_count = 0
    builder.builder_cargo_count = 0
    builder.builder_fluid_count = 0
    for name, count in pairs(content) do
        local proto = game.entity_prototypes[name]
        if builder.builder_fuel_item and proto.type == "locomotive" then
            fuel_count = fuel_count + proto.get_inventory_size(defines.inventory.fuel) * stack_size * count
        end
        if proto.type == "cargo-wagon" then
            builder.builder_cargo_count = builder.builder_cargo_count + 1
        elseif proto.type == "fluid-wagon" then
            builder.builder_fluid_count = builder.builder_fluid_count + 1
        end
        stock_count = stock_count + count
    end
    builder.builder_fuel_count = fuel_count

    local rail = builder.trainstop.connected_rail
    local pos = rail.position
    local direction = builder.trainstop.direction
    local disp = builder_directions[direction]
    local ortho = builder_ortho_directions[direction]

    local len = stock_count * 7
    local xend = pos.x + disp.x * (len + 1)
    local yend = pos.y + disp.y * (len + 1)
    builder.builder_entry = { xend, yend }

    xend = xend + 4 * disp.x
    yend = yend + 4 * disp.y
    local xstart = pos.x - 4 * disp.x
    local ystart = pos.y - 4 * disp.y

    local x1, y1 = math.min(xstart, xend), math.min(ystart, yend)
    local x2, y2 = math.max(xstart, xend), math.max(ystart, yend)
    x1 = x1 - 2 * ortho.x
    y1 = y1 - 2 * ortho.y
    x2 = x2 + 2 * ortho.x
    y2 = y2 + 2 * ortho.y
    builder.builder_area = { { x1, y1 }, { x2, y2 } }
    return true
end

---@param train Train
---@param builder Device
function allocator.builder_delete_train(train, builder)
    trains_runtime:remove(train)
    if builder.trains then builder.trains[train.id] = nil end

    local ttrain = train.train
    local content = {}
    for name, count in pairs(ttrain.get_contents()) do content[name] = count end

    -- collect content
    for _, carriage in pairs(ttrain.carriages) do
        if carriage.type == "locomotive" then
            local inv = carriage.get_inventory(defines.inventory.fuel)
            if inv then
                for name, count in pairs(inv.get_contents()) do
                    content[name] = (content[name] or 0) + count
                end
            end
            local loco = carriage
            local burner = loco.burner
            if burner then
                local current = burner.currently_burning
                if current then
                    local percent = 100 * burner.remaining_burning_fuel /
                        current.fuel_value
                    if percent >= 50 then
                        content[current.name] = (content[current.name] or 0) + 1
                    end
                end
            end
        end
        local name = carriage.name
        content[name] = (content[name] or 0) + 1
        carriage.destroy { raise_destroy = true }
    end

    if not builder.builder_remove_destroy then
        -- put in container
        local container = get_builder_container(builder)
        if container then
            local inv = container.get_inventory(defines.inventory.chest)
            if inv then
                for name, count in pairs(content) do
                    local inserted = inv.insert { name = name, count = count }
                    if inserted ~= count then
                        builder.entity.surface.spill_item_stack(
                            builder.position,
                            { name = name, count = count - inserted })
                    end
                end
            end
        end
    end

    builder.create_count = (builder.create_count or 0) - 1
    builder.builder_remove_count = (builder.builder_remove_count or 0) + 1
end

---@param train Train
function allocator.remove_train(train)
    if not train then return end
    if train.teleporting then return end

    local station = train.depot
    if station and defs.buffer_feeder_roles[station.role] then
        for name, _ in pairs(station.produced_items) do
            station.network.productions[name][station.id] = nil
        end
        station.produced_items = {}
    end

    if train.delivery then yutils.cancel_delivery(train.delivery) end

    trains_runtime:remove(train)
    if train.train.valid and not train.train.manual_mode then
        train.train.manual_mode = true
    end
    if station then
        if station.role == depot_role then
            station.network.used_depots[station.id] = nil
            station.network.free_depots[station.id] = station
        elseif station.role == builder_role then
            if station.trains then station.trains[train.id] = nil end
        end
        station.freezed = nil
        station.train = nil
        train.depot = nil
    end
end

---@param ttrain LuaTrain
---@param depot Device
function allocator.route_to_depot_same_surface(ttrain, depot)
    local records = {}
    depot.freezed = false
    local trainstop = depot.trainstop
    table.insert(records, {
        rail = trainstop.connected_rail,
        temporary = true,
        rail_direction = trainstop.connected_rail_direction,
        wait_conditions = {
            { type = "inactivity", compare_type = "and", ticks = 120 }
        }
    })

    table.insert(records, {
        station = trainstop.backer_name,
        wait_conditions = {
            { type = "inactivity", compare_type = "and", ticks = 300 }
        }
    })

    ttrain.schedule = { current = 1, records = records }
end

---@param ttrain LuaTrain
---@param depot Device
function allocator.insert_route_to_depot(ttrain, depot)
    local schedule = ttrain.schedule
    local records = schedule.records
    depot.freezed = false
    local index = schedule.current

    local trainstop = depot.trainstop
    table.insert(records, index, {
        rail = trainstop.connected_rail,
        temporary = true,
        rail_direction = trainstop.connected_rail_direction,
        wait_conditions = {
            { type = "time", compare_type = "and", ticks = 1 }
        }
    })

    table.insert(records, index + 1, {
        station = trainstop.backer_name,
        wait_conditions = {
            { type = "time", compare_type = "and", ticks = 1 }
        }
    })

    ttrain.schedule = { current = 1, records = records }
end

---@param train Train
---@param device Device
function allocator.route_to_station(train, device)
    local records = {}
    local ttrain = train.train
    local change_surface_records

    device.freezed = false
    local trainstop = device.trainstop
    local teleport_pos = train.front_stock.position

    if USE_SE then
        local front_stock = train.front_stock
        if front_stock.surface_index ~= device.entity.surface_index then
            local from_network = yutils.get_network_base(front_stock.force_index, front_stock.surface_index)
            local station = yutils.add_cross_network_trainstop(from_network, front_stock.position, records)
            if station then
                teleport_pos = station.position
            end

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

    teleport.add_teleporter(device.network, teleport_pos, device.position, records)

    if device.role == builder_role then
        local rails = device.entity.surface.find_entities_filtered {
            name = "straight-rail",
            position = device.builder_entry
        }
        if #rails > 0 then
            local rail = rails[1]
            table.insert(records, {
                rail = rail,
                temporary = true,
                wait_conditions = {
                    { type = "inactivity", compare_type = "and", ticks = 1 }
                }
            })
        end
    end

    if device.role == depot_role then
        table.insert(records, {
            rail = trainstop.connected_rail,
            temporary = true,
            rail_direction = trainstop.connected_rail_direction,
            wait_conditions = {
                { type = "inactivity", compare_type = "and", ticks = 120 }
            }
        })
    else
        table.insert(records, {
            rail = trainstop.connected_rail,
            temporary = true,
            rail_direction = trainstop.connected_rail_direction,
            wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
        })
    end

    table.insert(records, {
        station = trainstop.backer_name,
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

local function on_load()
    trains_runtime = Runtime.get("Trains")
end
tools.on_load(on_load)

yutils.builder_compute_conf = allocator.builder_compute_conf

return allocator
