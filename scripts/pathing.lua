local tools = require("scripts.tools")
local commons = require("scripts.commons")
local Runtime = require("scripts.runtime")
local pathingd = require("scripts.pathingd")
local config = require("scripts.config")

local pathing = {}

--[[
local request_type = "any-goal-accessible"
local measure_field = "penalty"
]]
local request_type = "path"
local measure_field = "total_length"

---@type Runtime
local devices_runtime

local front_direction = defines.rail_direction.front
local back_direction = defines.rail_direction.back

local steps_limit = nil

---@param direction integer
---@return integer
local function opposite(direction)
    return direction == front_direction and back_direction or front_direction
end

---@param from_device Device
---@param to_trainstop LuaEntity
---@return number
function pathing.device_trainstop_distance(from_device, to_trainstop)
    local rail = from_device.trainstop.connected_rail
    local direction = from_device.trainstop.connected_rail_direction
    local path_request = {
        type = request_type,
        goals = { { train_stop = to_trainstop } },
        from_front = {
            rail = rail,
            direction = direction
        },
        from_back = {
            rail = rail,
            direction = opposite(direction)
        },
        steps_limit = steps_limit
    }
    local result = game.request_train_path(path_request)
    local dist
    if not result.found_path then
        dist = -1
    else
        dist = result[measure_field]
    end
    if not from_device.distance_cache then
        from_device.distance_cache = { [to_trainstop.unit_number] = dist }
    else
        from_device.distance_cache[to_trainstop.unit_number] = dist
    end
    return dist
end

---@param rail LuaEntity
---@param to_device Device
---@return number
function pathing.rail_device_distance(rail, to_device)
    local path_request = {
        type = request_type,
        goals = { { train_stop = to_device.trainstop } },
        steps_limit = steps_limit
    }
    path_request.from_front = {
        rail = rail,
        direction = defines.rail_direction.front
    }
    path_request.from_back = {
        rail = rail,
        direction = defines.rail_direction.back
    }
    local result = game.request_train_path(path_request)
    local dist
    if not result.found_path then
        dist = -1
    else
        dist = result[measure_field]
    end
    if not to_device.distance_cache then
        to_device.distance_cache = { [-rail.unit_number] = dist }
    else
        to_device.distance_cache[-rail.unit_number] = dist
    end
    return dist
end

---@param from_device Device
---@param to_device Device
---@return number
function pathing.device_distance(from_device, to_device)
    local path_request = {
        type = request_type,
        goals = { { train_stop = to_device.trainstop } },
        steps_limit = steps_limit
    }
    local ptrainstop = from_device.trainstop
    local dist
    local connected_rail = ptrainstop.connected_rail
    if not connected_rail then
        return -1
    end
    local direction = ptrainstop.connected_rail_direction
    path_request.from_front = {
        rail = connected_rail,
        direction = direction
    }
    path_request.from_back = {
        rail = connected_rail,
        direction = opposite(direction)
    }
    local result = game.request_train_path(path_request)
    if not result.found_path then
        dist = -1
    else
        dist = result[measure_field]
    end
    if not from_device.distance_cache then
        from_device.distance_cache = { [to_device.id] = dist }
    else
        from_device.distance_cache[to_device.id] = dist
    end
    return dist
end

---@param train Train
---@param to_device Device
function pathing.train_distance(train, to_device)
    local path_request = {
        type = request_type,
        goals = { { train_stop = to_device.trainstop } },
        train = train.train,
        steps_limit = steps_limit
    }
    path_request.train = train.train
    local result = game.request_train_path(path_request)
    if not result.found_path then
        return -1
    else
        return result[measure_field]
    end
end

---@param train Train
---@param trainstop LuaEntity
function pathing.train_trainstop_distance(train, trainstop)
    local path_request = {
        type = request_type,
        goals = { { train_stop = trainstop } },
        train = train.train,
        steps_limit = steps_limit
    }
    path_request.train = train.train
    local result = game.request_train_path(path_request)
    if not result.found_path then
        return -1
    else
        return result[measure_field]
    end
end

---@param device Device
---@return integer?
function pathing.find_closest_incoming_rail(device)
    local network = device.network
    local index = 1
    local min
    local min_index
    for _, output in pairs(network.connecting_outputs) do
        local dist
        if output and output.valid then
            if device.distance_cache then
                dist = device.distance_cache[-output.unit_number]
            end
            if not dist then
                dist = pathing.rail_device_distance(output, device)
            end
            if dist > 0 then
                if not min or min > dist then
                    min = dist
                    min_index = index
                end
            end
        end
        index = index + 1
    end
    network.connection_index = min_index
    network.connected_network.connection_index = min_index
    return min_index
end

---@param device Device
---@return integer?
function pathing.find_closest_exiting_trainstop(device)
    local network = device.network
    local index = 1
    local connecting_trainstops = network.connecting_trainstops
    local min
    local min_index
    for _, ts in pairs(connecting_trainstops) do
        local dist
        if device.distance_cache then
            dist = device.distance_cache[ts.unit_number]
        end
        if ts.valid then
            if not dist then
                dist = pathing.device_trainstop_distance(device, ts)
            end
            if dist > 0 then
                if not min or min > dist then
                    min = dist
                    min_index = index
                end
            end
        end
        index = index + 1
    end
    network.connection_index = min_index
    network.connected_network.connection_index = min_index
    return min_index
end

local function clear_cache()
    if config.disabled then return end
    local surfaces_to_clear = global.surfaces_to_clear
    if surfaces_to_clear then
        for _, device in pairs(devices_runtime.map) do
            ---@cast device Device
            if global.surfaces_to_clear[device.network.surface_index] then
                device.distance_cache = nil
            end
        end
        global.surfaces_to_clear = nil
    end
end

local function on_load()
    devices_runtime = Runtime.get("Device")
end
tools.on_load(on_load)

tools.on_nth_tick(60, clear_cache)

if  settings.startup["yaltn-use_direct_distance"].value then
    return pathingd
else
    return pathing
end
