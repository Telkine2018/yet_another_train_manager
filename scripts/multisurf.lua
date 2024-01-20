local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local teleport = require("scripts.teleport")

local multisurf = {}

---@type Runtime
local trains_runtime

USE_SE = remote.interfaces["space-exploration"] ~= nil

local rescan_delay = 15 * 60

---@param context Context
local function clear_se(context)
    for _, ns in pairs(context.networks) do
        for _, network in pairs(ns) do
            network.connected_network = nil
            network.is_orbit = false
        end
    end
    context.use_se = false
end

---@param train Train
---@result table<int, boolean>
local function get_tracked_trains(train)
    local tracked
    local trainid = train.id
    for _, player in pairs(game.players) do
        local e = player.opened
        if e and e.object_name == "LuaEntity" and defs.tracked_types[e.type] then
            local ttrain = e.train
            if ttrain and ttrain.id == trainid then
                if not tracked then
                    tracked = {}
                    train.tracked = tracked
                end
                tracked[player.index] = true
            end
        end
    end
end

local function on_train_teleport_started(event)
    local context = yutils.get_context()
    local oldid = event.old_train_id_1
    local train = context.trains[oldid]
    if train then
        train.teleporting = true
        get_tracked_trains(train)
    end
end

local function on_train_teleport_finished(event)
    -- event.train
    -- event.old_train_id_1

    local context = yutils.get_context()
    local oldid = event.old_train_id_1
    local train = context.trains[oldid]
    if train then
        trains_runtime:remove(train)
        local newid = event.train.id
        train.train = event.train
        train.id = event.train.id
        train.teleporting = false
        train.front_stock = event.train.front_stock
        if train.depot and train.depot.trains then
            train.depot.trains[oldid] = nil
            train.depot.trains[newid] = train
        end
        trains_runtime:add(train)

        if train.splitted_schedule and #train.splitted_schedule > 0 then
            local records = table.remove(train.splitted_schedule, 1)
            train.train.schedule = {
                current = 1,
                records = records
            }
        end

        local delivery = train.delivery
        while delivery do
            if delivery then
                if delivery.requester.deliveries[oldid] then
                    delivery.requester.deliveries[oldid] = nil
                    delivery.requester.deliveries[newid] = delivery
                end

                if delivery.provider.deliveries[oldid] then
                    delivery.provider.deliveries[oldid] = nil
                    delivery.provider.deliveries[newid] = delivery
                end
            end
            delivery = delivery.combined_delivery
        end

        if train.tracked then
            for player_index, _ in pairs(train.tracked) do
                game.players[player_index].opened = train.front_stock
            end
            train.tracked = nil
        end
    end
end


---@param context Context
---@param force boolean?
function multisurf.init_se(context, force)
    if not USE_SE then
        if context.use_se then clear_se(context) end
        return
    end
    multisurf.register_se()
    for _, ff in pairs(context.networks) do
        for _, network in pairs(ff) do
            if not network.connected_network or force then
                multisurf.try_connect_network(network)
            end
        end
    end
end

local se_on_train_teleport_finished_event 
local se_on_train_teleport_started_event

function multisurf.register_se()

    if not USE_SE then
        return
    end

    if se_on_train_teleport_finished_event then return end
    se_on_train_teleport_finished_event = remote.call("space-exploration", "get_on_train_teleport_finished_event") --[[@as string]]
    se_on_train_teleport_started_event = remote.call("space-exploration", "get_on_train_teleport_started_event") --[[@as string]]
    script.on_event(se_on_train_teleport_finished_event, on_train_teleport_finished)
    script.on_event(se_on_train_teleport_started_event, on_train_teleport_started)
end

---@param network SurfaceNetwork
---@return boolean
local function connect(network)
    network.connected_network = nil
    network.connecting_trainstops = nil
    network.connecting_outputs = nil
    network.is_orbit = nil

    local trainstops = game.surfaces[network.surface_index].find_entities_filtered { name = commons.se_elevator_trainstop_name }
    if #trainstops == 0 then
        return false
    end

    local outputs = {}
    for _, ts in pairs(trainstops) do
        local position = ts.position
        local entities = ts.surface.find_entities_filtered { type = "curved-rail", position = { position.x - 14, position.y + 12 } }
        if #entities == 1 then
            table.insert(outputs, entities[1])
        else
            table.insert(outputs, nil)
        end
    end
    network.connecting_outputs = outputs
    network.connecting_trainstops = trainstops
    return true
end

---@param network SurfaceNetwork
function multisurf.try_connect_network(network)
    if not connect(network) then
        return
    end

    local zone = remote.call("space-exploration", "get_zone_from_surface_index", { surface_index = network.surface_index })
    if zone then
        local connected_zone
        if zone.orbit_index then
            connected_zone = remote.call("space-exploration", "get_zone_from_zone_index", { zone_index = zone.orbit_index })
            network.is_orbit = false
        elseif zone.type == "orbit" and zone.parent_index then
            connected_zone = remote.call("space-exploration", "get_zone_from_zone_index", { zone_index = zone.parent_index })
            network.is_orbit = true
        else
            return
        end
        local connected_network = yutils.get_network_base(network.force_index, connected_zone.surface_index)

        if connect(connected_network) then
            network.connected_network = connected_network
            connected_network.connected_network = network
            connected_network.is_orbit = not network.is_orbit
        end
    end
end

---@param e LuaEntity
function multisurf.remove_elevator(e)
    local network = yutils.get_network(e)
    multisurf.try_connect_network(network)
    network.connecting_ids = nil
end

---@param from_network SurfaceNetwork
---@param position MapPosition
---@param records any[]
---@return LuaEntity?
function multisurf.add_cross_network_trainstop(from_network, position, records)
    if not from_network.connecting_trainstops then return nil end

    local index = from_network.connection_index
    local found
    if index then
        found = from_network.connecting_trainstops[index]
    else
        local min_d
        for _, trainstop in pairs(from_network.connecting_trainstops) do
            if trainstop.valid then
                local d = tools.distance2(position, trainstop.position)
                if not found or d < min_d then
                    min_d = d
                    found = trainstop
                end
            end
        end
        if not found then return nil end
    end

    teleport.add_teleporter(from_network, position, found.position, records)

    table.insert(records, {
        station = found.backer_name,
        wait_conditions = { { type = "time", compare_type = "and", ticks = 10 } }
    })
    return found
end

---@param entity LuaEntity
local function udpate_network(entity)
    local network = yutils.get_network_base(entity.force_index, entity.surface_index)

    if network.connected_network then return end
    if network.connecting_ids then
        if network.connecting_ids[entity.unit_number] then return end
        network.connecting_ids[entity.unit_number] = true
    else
        network.connecting_ids = { [entity.unit_number] = true }
    end
    multisurf.try_connect_network(network)
end

---@param e EventData.on_selected_entity_changed
local function on_selected_entity_changed(e)
    local player = game.players[e.player_index]
    local entity = player.selected
    if not entity then return end
    if not tools.starts_with(entity.name, commons.se_elevator_name) then
        return
    end
    udpate_network(entity)
end

---@param e EventData.on_gui_opened
local function on_gui_opened(e)
    local player = game.players[e.player_index]
    local entity = e.entity
    if not entity then return end

    if not tools.starts_with(entity.name, commons.se_elevator_name) then
        return
    end
    udpate_network(entity)
end

tools.on_event(defines.events.on_selected_entity_changed,
    on_selected_entity_changed)
tools.on_event(defines.events.on_gui_opened, on_gui_opened)

yutils.init_se = multisurf.init_se
yutils.register_se = multisurf.register_se
yutils.add_cross_network_trainstop = multisurf.add_cross_network_trainstop

local function on_load()
    trains_runtime = Runtime.get("Trains")
end
tools.on_load(on_load)


return multisurf
