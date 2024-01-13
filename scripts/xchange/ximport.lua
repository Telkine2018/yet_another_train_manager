
local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")

local ximport = {}

local xchg_service_name = "xchg_service"

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime

local names = {

    "train-stop",
    commons.device_name,
    commons.cc_name
}

---@param context Context
function ximport.process(context)

    if not remote.interfaces[xchg_service_name] then
        return
    end
    
    local xdevices = remote.call(xchg_service_name, "get", "devices") --[[@as table<int,XDevice>?]]
    local xtrains = remote.call(xchg_service_name, "get", "trains")  --[[@as table<int,XTrain>]]
    local xcontext = remote.call(xchg_service_name, "get", "context") --[[@as XContext ]]

    context.delivery_id = xcontext.delivery_id
    context.config_id = xcontext.config_id
    context.event_id = xcontext.event_id

    if not xdevices then return end

    ---@type table<int, LuaEntity>
    local entity_map = {}
    ---@type table<int, LuaTrain>
    local train_map = {}
    for _, surface in pairs(game.surfaces) do
        local entities = surface.find_entities_filtered{name=names}
        for _, entity in pairs(entities) do
            entity_map[entity.unit_number] = entity
        end

        local trains = surface.get_trains()
        for _, train in pairs(trains) do
            train_map[train.id] = train
        end
    end

    ---@param unit_number integer
    ---@return LuaEntity
    local function get_entity(unit_number)
        if not unit_number then
            local r = nil
            return r --[[@as LuaEntity]]
        end
        local e = entity_map[unit_number]
        entity_map[unit_number] = nil
        return e
    end

    for _, xdevice in pairs(xdevices) do

        local entity = get_entity(xdevice.id)

        ---@type Device
        local device = {
            entity = entity,
            force_id = entity.force_index,
            deliveries = {},
            requested_items = {},
            produced_items = {},
            dconfig = xdevice.dconfig
        }

        for name, value in pairs(xdevice) do
            if not device[name] then
                device[name] = value
            end
        end

        device.network = yutils.get_network(entity)
        device.out_red = get_entity(xdevice.out_red)
        device.out_green = get_entity(xdevice.out_green)
        device.in_red = get_entity(xdevice.in_red)
        device.in_green = get_entity(xdevice.in_green)
        device.force_id = entity.force_index
        device.trainstop = get_entity(xdevice.trainstop_id)

        context.configs[xdevice.dconfig.id] = xdevice.dconfig
        devices_runtime:add(device)

        if device.trainstop then
            context.trainstop_map[device.trainstop.unit_number] = device
        end
    end

    for _, entity in pairs(entity_map) do
        if entity.name == commons.cc_name then
            entity.destroy()
        end
    end

    for _, xtrain in pairs(xtrains) do
        local ttrain = train_map[xtrain.id]
        ---@type Train
        local train =   {
            id = xtrain.id,
            train = ttrain,
            state = xtrain.state,
            network = yutils.get_network(ttrain.front_stock),
            front_stock = ttrain.front_stock,
            depot = xtrain.depot and devices[xtrain.depot],
            refueler = xtrain.refueler and devices[xtrain.refueler],
            network_mask = xtrain.network_mask,
            refresh_tick = 0,
        }
        for name, value in pairs(xtrain) do
            train[name] = value
        end
        train.train = ttrain
        train.network = yutils.get_network(ttrain.front_stock)
        train.front_stock = ttrain.front_stock
        train.depot = xtrain.depot and devices[xtrain.depot]
        train.refueler = xtrain.refueler and devices[xtrain.refueler]

        context.trains[train.id] = train
        if train.depot then
            train.depot.train = train
        end
        if train.refueler then
            train.refueler.train = train
        end
        yutils.get_train_composition(train)
        yutils.read_train_internals(train)
    end

    for _, device in pairs(devices) do
        device.position = device.entity.position
        yutils.update_runtime_config(device)
        local role = device.dconfig.role
        if role == defs.device_roles.buffer and device.train then
            yutils.update_production_from_content(device, device.train)
        elseif role == defs.device_roles.depot then
            local network = yutils.get_network(device.entity)
            if device.train then
                network.used_depots[device.id] = device
            else
                network.free_depots[device.id] = device
            end
        elseif role == defs.device_roles.refueler then
            local network = yutils.get_network(device.entity)
            network.refuelers[device.id] = device
        end
    end
end

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end

tools.on_load(on_load)

yutils.ximport = ximport.process

return ximport