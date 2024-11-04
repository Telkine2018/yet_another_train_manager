local migration = require("__flib__.migration")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local config = require("scripts.config")
local Runtime = require("scripts.runtime")
local spatial_index = require("scripts.spatial_index")
local trainconf = require("scripts.trainconf")
local logger = require("scripts.logger")
local yutils = require("scripts.yutils")


local migrations = {}

---@param context Context
local function update_trains(context)
    local toremove = {}
    for _, train in pairs(context.trains) do
        if not trainconf.get_train_composition(train) then
            toremove[train.id] = train
        end
    end
    for id, _ in pairs(toremove) do
        local train = context.trains[id]
        if train.delivery then
            yutils.cancel_delivery(train.delivery)
        end
        context.trains[id] = nil
    end
end

---@param context Context
local function convert_mask_to_pattern(context)
    if context.pattern_ids then
        return false
    end

    context.pattern_ids = {}
    local devices_runtime = Runtime.get("Device")
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


local function migration_2_0_0()

    local context = yutils.get_context()
    convert_mask_to_pattern(context)

    local devices_runtime = Runtime.get("Device")
    for _, d in pairs(devices_runtime.map) do
        local device = d --[[@as Device]]
        device.distance_cache = nil
    end

    if not context.session_tick then
        context.session_tick = -1
    end

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
    storage.units_cache_map = nil
    storage.units_cache = nil
    storage.debug_version = commons.debug_version
    for _, player in pairs((game.players)) do
        local vars = tools.get_vars(player)
        vars.ui_progress = nil
    end
    game.print({ "yaltn-device.update-message" }, commons.print_settings)
end

local migrations_table = {
    ["2.0.0"] = migration_2_0_0,
}


local function on_configuration_changed(data)
    Runtime.initialize()

    local context = yutils.get_context()
    update_trains(context)
    migration.on_config_changed(data, migrations_table)

    yutils.fix_all(context)
    
    --- Init UI
    yutils.init_ui(context)
end


---@param name string?
---@return boolean
local function is_invalid_name(name)
    if not name then
        return true
    end
    local signal = tools.id_to_signal(name)
    if not signal then
        return true
    end
    if signal.type == "item" then
        local proto = prototypes.item[signal.name]
        if not proto then
            return true
        end
    elseif signal.type == "fluid" then
        local proto = prototypes.fluid[signal.name]
        if not proto then
            return true
        end
    else
        local proto = prototypes.virtual_signal[signal.name]
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

    local dconfig = device.dconfig
    if dconfig then
        if dconfig.red_wire_as_stock then
            dconfig.red_wire_mode = 2
        else
            dconfig.red_wire_mode = 1
        end
        dconfig.red_wire_as_stock = nil
    end

    if device.red_wire_as_stock then
        device.red_wire_mode = 2
    else
        device.red_wire_mode = 1
    end
end

---@param network SurfaceNetwork
local function fix_network(network)
    fix_signal_table(network.productions)
end


---@param context Context
function yutils.fix_all(context)

    local devices_runtime = Runtime.get("Device")
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

script.on_configuration_changed(on_configuration_changed)

return migrations
