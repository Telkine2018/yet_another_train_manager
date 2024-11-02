local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local config = require("scripts.config")
local yutils = require("scripts.yutils")
local logger = require("scripts.logger")

------------------------------------------------------

---@type Runtime
local trains_runtime
---@type Runtime
local devices_runtime

local teleport = {}

local prefix = commons.prefix

local band = bit32.band

local depot_role = defs.device_roles.depot
local buffer_role = defs.device_roles.buffer
local provider_role = defs.device_roles.provider
local requester_role = defs.device_roles.requester
local builder_role = defs.device_roles.builder
local feeder_role = defs.device_roles.feeder
local teleporter_role = defs.device_roles.teleporter

local distance = tools.distance
local get_context = yutils.get_context

---@param device Device
function teleport.try_teleport(device) end

---@param network SurfaceNetwork
---@param start_pos MapPosition
---@param target_pos MapPosition
---@param records ScheduleRecord[]
---@return boolean ?
function teleport.add_teleporter(network, start_pos, target_pos, records)
    if not network.teleporters then return end

    local dd = distance(start_pos, target_pos)
    if dd < config.teleport_min_distance then return end

    local min_d1
    local min_tlp1
    local min_d2
    local min_tlp2
    for _, tlp in pairs(network.teleporters) do
        if not tlp.inactive and tlp.trainstop and tlp.trainstop.valid then
            local d1 = distance(tlp.position, start_pos)
            if d1 < tlp.teleport_range then
                if not min_d1 or min_d1 > d1 then
                    min_d1 = d1
                    min_tlp1 = tlp
                end
            end

            local d2 = distance(tlp.position, target_pos)
            if d2 < tlp.teleport_range then
                if not min_d2 or min_d2 > d2 then
                    min_d2 = d2
                    min_tlp2 = tlp
                end
            end
        end
    end

    if min_tlp1 == min_tlp2 then return end
    if not min_d1 or not min_d2 then return end

    if min_d1 + min_d2 > dd / config.teleport_threshold then return end

    local trainstop = min_tlp1.trainstop
    local connected_rail = trainstop.connected_rail
    if not (connected_rail and connected_rail.valid) then return end

    local rail_direction = trainstop.connected_rail_direction
    local rev_rail_direction = rail_direction == defines.rail_direction.front and defines.rail_direction.back or defines.rail_direction.front

    ---@type LuaEntity?
    local rail = connected_rail.get_rail_segment_end(rev_rail_direction)
    if not rail then return end
    rail = rail.get_connected_rail {
        rail_direction = rev_rail_direction,
        rail_connection_direction = defines.rail_connection_direction.straight
    }
    if not rail then return end
    rail = rail.get_connected_rail {
        rail_direction = rev_rail_direction,
        rail_connection_direction = defines.rail_connection_direction.straight
    }

    if rail then
        table.insert(records, {

            rail = rail,
            temporary = true,
            rail_direction = rail_direction,
            wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
        })
    end

    table.insert(records, {
        rail = connected_rail,
        temporary = true,
        rail_direction = rail_direction,
        wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
    })

    table.insert(records, {
        station = trainstop.backer_name,
        wait_conditions = {
            {
                type = "time",
                compare_type = "and",
                ticks = config.teleport_timeout
            }
        }
    })

    table.insert(records, {
        rail = min_tlp2.trainstop.connected_rail,
        temporary = true,
        rail_direction = min_tlp2.trainstop.connected_rail_direction,
        wait_conditions = { { type = "time", compare_type = "and", ticks = 1 } }
    })

    return true
end

---@class TeleportInfo
---@field device Device
---@field train Train
---@field ttrain LuaTrain
---@field schedule TrainSchedule
---@field xd number
---@field yd number
---@field dst_ttrain LuaTrain?
---@field dst_trainstop LuaEntity
---@field dst_device Device

---@param device Device
---@return TeleportInfo?
---@return boolean?
local function get_teleport_info(device)
    device.failcode = nil
    local src_trainstop = device.trainstop
    if not (src_trainstop and src_trainstop.valid) then
        device.failcode = 200
        return nil, false
    end

    local ttrain = src_trainstop.get_stopped_train();
    if ttrain == nil then return nil, false end

    local context = get_context()
    local train = context.trains[ttrain.id]
    if not train then return nil, false end

    if not device.ebuffer then return nil, true end

    if device.ebuffer.energy < commons.teleport_electric_buffer_size then
        device.failcode = 201
        return nil, true
    end

    local schedule = ttrain.schedule
    ---@cast schedule -nil
    local r = schedule.records[schedule.current + 1]
    local connected_rail = r.rail
    if not connected_rail then
        device.failcode = 202
        return nil, true
    end

    local dst_trainstop = connected_rail.get_rail_segment_stop(r.rail_direction)
    if not dst_trainstop then
        device.failcode = 203
        return nil, true
    end


    local rail_direction = dst_trainstop.connected_rail_direction
    local rev_rail_direction = rail_direction == defines.rail_direction.front and defines.rail_direction.back or defines.rail_direction.front
    local rail = dst_trainstop.connected_rail
    if rail == nil then
        return nil, true
    end
    local end_rail = rail.get_rail_segment_end(rev_rail_direction)
    local rail_len = math.ceil(
        math.max(
            math.abs(rail.position.x - end_rail.position.x),
            math.abs(rail.position.y - end_rail.position.y)))

    local pos1 = connected_rail.position
    local x1, x2, y1, y2
    local xd, yd = 0, 0
    local margin = 7

    local direction = dst_trainstop.direction
    if direction == defines.direction.east then
        xd = -1
        x1 = pos1.x - rail_len - margin
        x2 = pos1.x + margin
        y1 = pos1.y - 1
        y2 = pos1.y + 1
    elseif direction == defines.direction.west then
        xd = 1
        x1 = pos1.x - margin
        x2 = pos1.x + rail_len + margin
        y1 = pos1.y - 1
        y2 = pos1.y + 1
    elseif direction == defines.direction.north then
        yd = 1
        y1 = pos1.y - margin
        y2 = pos1.y + rail_len + margin
        x1 = pos1.x - 1
        x2 = pos1.x + 1
    elseif direction == defines.direction.south then
        yd = -1
        y1 = pos1.y - rail_len - margin
        y2 = pos1.y + margin
        x1 = pos1.x - 1
        x2 = pos1.x + 1
    end

    local dst_device = context.trainstop_map[dst_trainstop.unit_number]
    if not dst_device then
        device.failcode = 205
        return nil, true
    end

    device.teleport_last_dst = dst_device
    dst_device.teleport_last_src = device

    local dst_train = dst_trainstop.get_stopped_train();
    if dst_train then
        return {

            device = device,
            train = train,
            ttrain = ttrain,
            pos1 = pos1,
            xd = xd,
            yd = yd,
            schedule = schedule,
            dst_trainstop = dst_trainstop,
            dst_ttrain = dst_train,
            dst_device = dst_device
        }
    end

    local count = device.entity.surface.count_entities_filtered {
        type = { "locomotive", "cargo-wagon", "fluid-wagon" },
        area = { { x1, y1 }, { x2, y2 } }
    }

    rendering.draw_rectangle {
        color = { 1, 0, 0 },
        surface = dst_trainstop.surface,
        forces = { dst_trainstop.force_index },
        time_to_live = 120,
        left_top = { x1, y1 },
        right_bottom = { x2, y2 }
    }

    if count > 0 then
        device.failcode = 204
        return nil, true
    end

    return {

        device = device,
        train = train,
        ttrain = ttrain,
        pos1 = pos1,
        xd = xd,
        yd = yd,
        schedule = schedule,
        dst_trainstop = dst_trainstop,
        dst_device = dst_device
    }
end

---@param train Train
---@param newtrain LuaTrain
local function reconnect_trains(train, newtrain)
    local context = get_context()
    local oldid = train.id
    local newid = newtrain.id

    trains_runtime:remove(train)
    context.trains[oldid] = nil
    train.train = newtrain
    train.id = newid
    train.front_stock = newtrain.front_stock
    if train.depot and train.depot.trains then
        train.depot.trains[oldid] = nil
        train.depot.trains[newid] = train
    end
    context.trains[newid] = train

    local delivery = train.delivery
    if delivery then
        while delivery do
            if delivery.requester.deliveries[oldid] then
                delivery.requester.deliveries[oldid] = nil
                delivery.requester.deliveries[newid] = delivery
            end

            if delivery.provider.deliveries[oldid] then
                delivery.provider.deliveries[oldid] = nil
                delivery.provider.deliveries[newid] = delivery
            end
            delivery = delivery.combined_delivery
        end
    end
    if train.depot then
        if train.depot.trains and train.depot.trains[oldid] then
            train.depot.trains[oldid] = nil
            train.depot.trains[newid] = train
        end
    end

    train.teleporting = false
    trains_runtime:add(train)
end

---@param info TeleportInfo
---@return boolean
local function do_teleport(info)
    local device = info.device
    local train = info.train
    local pos1 = info.pos1
    local xd = info.xd
    local yd = info.yd
    local ttrain = info.ttrain
    local dst_trainstop = info.dst_trainstop
    local schedule = info.schedule

    train.teleporting = true
    device.ebuffer.energy = 0

    local carriages = ttrain.carriages
    local back_movers = {}
    for _, loco in pairs(ttrain.locomotives.back_movers) do
        back_movers[loco.unit_number] = true
    end

    local x = pos1.x + xd * 3
    local y = pos1.y + yd * 3

    local first
    local surface = device.entity.surface
    local force = device.entity.force

    local create_list = {}
    local failure = false
    local index = 1
    for _, carriage in pairs(carriages) do
        local direction = dst_trainstop.direction
        if back_movers[carriage.unit_number] then
            direction = tools.get_opposite_direction(direction)
        end
        local created = surface.create_entity {
            name = carriage.name,
            position = { x, y },
            force = force,
            direction = direction
        }

        if not created then
            for _, c in pairs(create_list) do c.destroy() end
            info.dst_device.teleport_failure = (info.dst_device.teleport_failure or 0) + 1
            logger.report_teleport_fail(info.device, info.dst_device, info.train)
            failure = true
            train.teleporting = false
            return true
        end

        local passenger = carriage.get_driver()
        if passenger then created.set_driver(passenger) end
        local grid = carriage.grid
        if grid then
            local equipment = grid.equipment
            local cgrid = created.grid
            ---@cast cgrid -nil
            for _, e in pairs(equipment) do
                local ce = cgrid.put { name = e.name, position = e.position }
                ce.energy = e.energy
                if e.type == "energy-shield-equipment" then
                    ce.shield = e.shield
                end
                local burner = e.burner
                if burner and ce then
                    local cburner = ce.burner
                    if cburner then
                        cburner.currently_burning = burner.currently_burning
                        cburner.heat = burner.heat
                        cburner.remaining_burning_fuel = burner.remaining_burning_fuel

                        local contents = burner.inventory.get_contents()
                        for _, item in pairs(contents) do
                            cburner.inventory.insert { name = item.name, count = item.count }
                        end
                    end
                end
            end
        end
        table.insert(create_list, created)
        local type = carriage.type
        local last
        if type == "locomotive" then
            local src = carriage.get_inventory(defines.inventory.fuel) --[[@as LuaInventory]]
            local dst = created.get_inventory(defines.inventory.fuel) --[[@as LuaInventory]]
            for i = 1, #src do dst[i].set_stack(src[i]) end
            local burner = carriage.burner
            if burner then
                local dst_burner = created.burner
                dst_burner.currently_burning = burner.currently_burning
                dst_burner.remaining_burning_fuel =
                    burner.remaining_burning_fuel
                dst_burner.heat = burner.heat
            end
        elseif type == "cargo-wagon" then
            local src = carriage.get_inventory(defines.inventory.cargo_wagon) --[[@as LuaInventory]]
            local dst = created.get_inventory(defines.inventory.cargo_wagon) --[[@as LuaInventory]]
            dst.set_bar(src.get_bar())
            local is_filtered = src.is_filtered()
            for i = 1, #src do dst[i].set_stack(src[i]) end
            if is_filtered then
                for i = 1, #src do
                    dst.set_filter(i, src.get_filter(i))
                end
            end
        elseif type == "fluid-wagon" then
            for name, count in pairs(carriage.get_fluid_contents()) do
                created.insert_fluid { name = name, amount = count }
            end
        end
        if not first then
            first = created
        else
            if not created.connect_rolling_stock(defines.rail_direction.back) then
                created.connect_rolling_stock(defines.rail_direction.front)
            end
        end
        x = x + 7 * xd
        y = y + 7 * yd
        index = index + 1
    end
    device.teleport_ecount = (device.teleport_ecount or 0) + 1
    info.dst_device.teleport_rcount = (info.dst_device.teleport_rcount or 0) + 1

    if not first then
        train.teleporting = false
        return true
    end

    for _, carriage in pairs(ttrain.carriages) do carriage.destroy() end

    schedule.current = schedule.current + 2
    first.train.schedule = schedule
    first.train.manual_mode = false

    local newtrain = first.train
    reconnect_trains(train, newtrain)

    logger.report_teleportation(info.device, info.dst_device, train)
    return failure
end

---@param infolist TeleportInfo[]
---@return table<integer, Train>?
local function collect_players_trains(infolist)
    local result = nil
    ---@type table<int, Train>
    local map = {}
    for _, info in pairs(infolist) do map[info.train.id] = info.train end
    for _, player in pairs(game.players) do
        local e = player.opened
        if e and e.object_name == "LuaEntity" and defs.tracked_types[e.type] then
            local train = e.train
            if train and train.valid and map[train.id] then
                if not result then result = {} end
                result[player.index] = map[train.id]
            end
        end
    end
    return result
end

---@param map table<integer, Train>?
local function restore_player_trains(map)
    if not map then return end

    for index, train in pairs(map) do
        if train.train.valid then
            game.players[index].opened = train.train.front_stock
        end
    end
end

---@class TrainTeleportInfo
---@field force LuaForce
---@field surface LuaSurface
---@field carriages CarriageTeleportInfo[]
---@field schedule TrainSchedule
---@field train Train
---@field info TeleportInfo

---@class CarriageTeleportInfo
---@field name string
---@field type string
---@field direction integer
---@field position MapPosition
---@field fuel_inv LuaInventory
---@field currently_burning LuaItemPrototype
---@field remaining_burning_fuel number
---@field heat number
---@field cargo_inv LuaInventory
---@field bar integer?
---@field filters string[]
---@field fluids table<string, integer>
---@field passenger (LuaEntity|LuaPlayer)?
---@field grid  TrainGridInfo[]

---@class TrainGridInfo
---@field name string
---@field position EquipmentPosition
---@field energy number
---@field shield number?
---@field currently_burning LuaItemPrototype?
---@field remaining_burning_fuel number?
---@field heat number?
---@field fuel ItemCountWithQuality[]

---@param device Device
---@return boolean
function teleport.check_teleport(device)
    local infomap
    ---@type TeleportInfo[]
    local infolist
    local context

    while true do
        local info, failed = get_teleport_info(device)

        if failed then return false end
        if not info then
            return false
        else
            if not infomap then
                infomap = {}
                infolist = {}
            end

            table.insert(infolist, info)
            if not info.dst_ttrain then break end

            if not context then context = get_context() end

            local dst_device = info.dst_device

            -- there is a loop in teleport request
            if infomap[dst_device.id] then
                local player_map = collect_players_trains(infolist)
                local ti = teleport.extract_teleportation_info(info)
                ti.train.teleporting = true
                for _, carriage in pairs(ti.train.train.carriages) do
                    carriage.destroy()
                end
                local failure = false
                for i = #infolist - 1, 1, -1 do
                    if do_teleport(infolist[i]) then
                        failure = true
                        break
                    end
                end
                if not failure then
                    if teleport.apply_teleportation(ti) then
                        yutils.remove_train(ti.train)
                    else
                        restore_player_trains(player_map)
                    end
                else
                    yutils.remove_train(ti.train)
                end
                return true
            end
            infomap[device.id] = info
            device = dst_device
        end
    end
    if infolist then
        local player_map = collect_players_trains(infolist)
        for i = #infolist, 1, -1 do
            if do_teleport(infolist[i]) then break end
        end
        restore_player_trains(player_map)
    end
    return true
end

---@param info TeleportInfo
---@return TrainTeleportInfo
function teleport.extract_teleportation_info(info)
    local device = info.device
    local train = info.train
    local pos1 = info.pos1
    local xd = info.xd
    local yd = info.yd
    local ttrain = info.ttrain
    local dst_trainstop = info.dst_trainstop

    train.teleporting = true

    local carriages = ttrain.carriages
    local back_movers = {}
    for _, loco in pairs(ttrain.locomotives.back_movers) do
        back_movers[loco.unit_number] = true
    end

    local x = pos1.x + xd * 3
    local y = pos1.y + yd * 3

    local first
    local surface = device.entity.surface
    local force = device.entity.force

    ---@type TrainTeleportInfo
    local result = {
        force = force --[[@as LuaForce]],
        surface = surface,
        carriages = {},
        schedule = ttrain.schedule,
        train = train,
        info = info
    }

    local index = 1
    for _, carriage in pairs(carriages) do
        local direction = dst_trainstop.direction
        if back_movers[carriage.unit_number] then
            direction = tools.get_opposite_direction(direction)
        end

        ---@type CarriageTeleportInfo
        local created = {
            name = carriage.name,
            direction = direction --[[@as integer]],
            position = { x, y },
            type = carriage.type,
            passenger = carriage.get_driver()
        }
        table.insert(result.carriages, created)

        local grid = carriage.grid
        if grid then
            local equipment = grid.equipment
            created.grid = {}
            for _, e in pairs(equipment) do
                ---@type TrainGridInfo
                local ce = { name = e.name, position = e.position }
                table.insert(created.grid, ce)
                ce.energy = e.energy
                if e.type == "energy-shield-equipment" then
                    ce.shield = e.shield
                end
                local burner = e.burner
                if burner then
                    ce.currently_burning = burner.currently_burning
                    ce.heat = burner.heat
                    ce.fuel = burner.inventory.get_contents()
                end
            end
        end

        local type = created.type
        if type == "locomotive" then
            local src = carriage.get_inventory(defines.inventory.fuel) --[[@as LuaInventory]]
            local dst = game.create_inventory(#src)
            created.fuel_inv = dst
            for i = 1, #src do dst[i].set_stack(src[i]) end
            local burner = carriage.burner
            if burner then
                created.currently_burning = burner.currently_burning
                created.remaining_burning_fuel = burner.remaining_burning_fuel
                created.heat = burner.heat
            end
        elseif type == "cargo-wagon" then
            local src = carriage.get_inventory(defines.inventory.cargo_wagon) --[[@as LuaInventory]]
            local dst = game.create_inventory(#src)
            created.cargo_inv = dst
            created.bar = src.get_bar()
            for i = 1, #src do dst[i].set_stack(src[i]) end
            if src.is_filtered then
                created.filters = {}
                for i = 1, #src do
                    created.filters[i] = src.get_filter(i)
                end
            end
        elseif type == "fluid-wagon" then
            created.fluids = carriage.get_fluid_contents()
        end
        x = x + 7 * xd
        y = y + 7 * yd
    end
    return result
end

---@param ti TrainTeleportInfo
---@return  boolean -- true if failure
function teleport.apply_teleportation(ti)
    local last
    local first
    local surface = ti.surface
    local create_list = {}
    local failure = false
    for _, carriage in pairs(ti.carriages) do
        local created = surface.create_entity {
            name = carriage.name,
            position = carriage.position,
            force = ti.force,
            direction = carriage.direction --[[@as defines.direction]]
        }

        if not created then
            for _, c in pairs(create_list) do c.destroy() end
            failure = true
            ti.info.dst_device.teleport_failure = (ti.info.dst_device.teleport_failure or 0) + 1
            logger.report_teleport_fail(ti.info.device, ti.info.dst_device, ti.info.train)
            break
        end
        if ti.passenger then created.set_driver(ti.passenger) end
        table.insert(create_list, created)

        local type = carriage.type
        if type == "locomotive" then
            local src = carriage.fuel_inv --[[@as LuaInventory]]
            local dst = created.get_inventory(defines.inventory.fuel) --[[@as LuaInventory]]
            for i = 1, #src do dst[i].set_stack(src[i]) end

            local burner = carriage.burner
            local dst_burner = created.burner
            if dst_burner then
                dst_burner.currently_burning = carriage.currently_burning
                dst_burner.remaining_burning_fuel = carriage.remaining_burning_fuel
                dst_burner.heat = carriage.heat
            end
        elseif type == "cargo-wagon" then
            local src = carriage.cargo_inv
            local dst = created.get_inventory(defines.inventory.cargo_wagon) --[[@as LuaInventory]]
            dst.set_bar(carriage.bar)
            for i = 1, #src do dst[i].set_stack(src[i]) end
            if carriage.filters then
                for i = 1, #src do
                    dst.set_filter(i, carriage.filters[i])
                end
            end
        elseif type == "fluid-wagon" then
            for name, amount in pairs(carriage.fluids) do
                created.insert_fluid { name = name, amount = amount }
            end
        end

        if carriage.grid then
            local grid = created.grid
            if grid then
                for _, e in pairs(carriage.grid) do
                    local ce = grid.put { name = e.name, position = e.position }
                    if ce then
                        ce.energy = e.energy
                        if e.shield then ce.shield = e.shield end
                        if e.currently_burning then
                            local burner = ce.burner
                            if burner then
                                burner.currently_burning = e.currently_burning
                                burner.remaining_burning_fuel = e.remaining_burning_fuel
                                burner.heat = e.heat
                                if e.fuel then
                                    for _, item in pairs(e.fuel) do
                                        burner.inventory.insert { name = item.name, count = item.count, quality = item.quality }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if not first then
            first = created
        else
            if not created.connect_rolling_stock(defines.rail_direction.back) then
                created.connect_rolling_stock(defines.rail_direction.front)
            end
        end
    end

    if not first or failure then
        ti.train.teleporting = false
        teleport.release_teleportation(ti)
        return true
    end

    ti.info.device.teleport_ecount = (ti.info.device.teleport_ecount or 0) + 1
    ti.info.dst_device.teleport_rcount = (ti.info.dst_device.teleport_rcount or 0) + 1

    local schedule = ti.schedule
    schedule.current = schedule.current + 2
    first.train.schedule = schedule
    first.train.manual_mode = false

    local newtrain = first.train
    reconnect_trains(ti.train, newtrain)
    teleport.release_teleportation(ti)
    local info = ti.info
    logger.report_teleportation(info.device, info.dst_device, ti.train)
    return false
end

---@param ti TrainTeleportInfo
function teleport.release_teleportation(ti)
    for _, carriage in pairs(ti.carriages) do
        if carriage.fuel_inv then carriage.fuel_inv.destroy() end
        if carriage.cargo_inv then carriage.cargo_inv.destroy() end
    end
end

local function on_load()
    trains_runtime = Runtime.get("Trains")
    devices_runtime = Runtime.get("Device")
end
tools.on_load(on_load)

return teleport
