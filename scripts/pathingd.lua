local tools = require("scripts.tools")
local commons = require("scripts.commons")
local Runtime = require("scripts.runtime")

local pathingd = {}

---@type Runtime
local devices_runtime

local distance = tools.distance

---@param from_device Device
---@param to_trainstop LuaEntity
---@return number
function pathingd.device_trainstop_distance(from_device, to_trainstop)
    local p1 = from_device.entity.position
    local p2 = to_trainstop.position
    local dist = distance(p1, p2)
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
function pathingd.rail_device_distance(rail, to_device)
    local p1 = rail.position
    local p2 = to_device.entity.position
    local dist = distance(p1, p2)

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
function pathingd.device_distance(from_device, to_device)
    local p1 = from_device.entity.position
    local p2 = to_device.entity.position
    local dist = distance(p1, p2)

    if not from_device.distance_cache then
        from_device.distance_cache = { [to_device.id] = dist }
    else
        from_device.distance_cache[to_device.id] = dist
    end
    return dist
end

---@param train Train
---@param to_device Device
function pathingd.train_distance(train, to_device)
    local p1 = train.front_stock.position
    local p2 = to_device.entity.position
    local dist = distance(p1, p2)
    return dist
end

---@param train Train
---@param trainstop LuaEntity
function pathingd.train_trainstop_distance(train, trainstop)
    local p1 = train.front_stock.position
    local p2 = trainstop.position
    local dist = distance(p1, p2)
    return dist
end

---@param device Device
---@return integer?
function pathingd.find_closest_incoming_rail(device)
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
                dist = pathingd.rail_device_distance(output, device)
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
function pathingd.find_closest_exiting_trainstop(device)
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
                dist = pathingd.device_trainstop_distance(device, ts)
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

return pathingd
