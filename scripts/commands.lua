local flib_format = require("__flib__/format")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")
local device_selection = require("scripts.device_selection")

local cmd = {}
local prefix = commons.prefix

---@type Runtime
local devices_runtime

---@param p CustomCommandData
local function cmd_scheduler(p)
    local player = game.players[p.player_index]
    local disabled = p.parameter == "off"
    settings.global["yaltn-disabled"] = { value = disabled }
    player.print("yaltn scheduler, disabled=" .. tostring(disabled))
end

---@param p CustomCommandData
local function cmd_disable_network(p)
    local player = game.players[p.player_index]
    local network = yutils.get_network_base(player.force_index, player.surface_index)
    network.disabled = true
    player.print({ "yaltn-messages.command_network_disabled", player.surface.name })
    if network.connected_network then
        network.connected_network.disabled = true
        player.print({ "yaltn-messages.command_network_disabled", game.surfaces[network.connected_network.surface_index].name })
    end
end

---@param p CustomCommandData
local function cmd_enable_network(p)
    local player = game.players[p.player_index]
    local network = yutils.get_network_base(player.force_index, player.surface_index)
    network.disabled = false
    player.print({ "yaltn-messages.command_network_enabled", player.surface.name })
    if network.connected_network then
        network.connected_network.disabled = false
        player.print({ "yaltn-messages.command_network_enabled", game.surfaces[network.connected_network.surface_index].name })
    end
end

---@param p CustomCommandData
local function cmd_log(p)
    local player = game.players[p.player_index]
    local param = p.parameter
    local level
    if param then
        level = tonumber(param)
        if not level then level = config.log_to_index[param] end
    end
    if not level then
        if config.log_level == 0 then
            level = 2
        else
            level = 0
        end
    end
    player.print("yaltn log, level=" .. config.index_to_log[level])
    settings.global["yaltn-log_level"] = { value = config.index_to_log[level] }
end

---@param p CustomCommandData
local function cmd_trains(p)
    local player = game.players[p.player_index]
    player.print("---- Stuck/Invalid Trains -- ")

    local context = yutils.get_context()
    local force_index = player.force_index
    for _, train in pairs(context.trains) do
        if train.train.valid then
            if train.train.front_stock.force_index == force_index and yutils.is_train_stuck(train) then
                player.print({
                    prefix .. "-logger.train_stuck",
                    flib_format.time(train.timeout_tick),
                    logger.gps_to_text(train.train.front_stock),
                    (train.delivery and logger.delivery_to_text(train.delivery) or "*")
                })
            end
        elseif not train.teleporting then
            player.print({
                prefix .. "-logger.train_invalid",
                flib_format.time(train.timeout_tick),
                (train.delivery and logger.delivery_to_text(train.delivery) or "*")
            })
        end
    end
end

---@param p CustomCommandData
local function cmd_manual_mode(p)
    local player = game.players[p.player_index]
    player.print("---- Set manual mode -- ")

    local manual_mode = true
    local count = 0
    local force = player.force

    local filter = p.parameter
    for _, surface in pairs(game.surfaces) do
        for _, train in pairs(surface.get_trains(force)) do
            if filter then
                local schedule = train.schedule
                if schedule then
                    local records = schedule.records
                    for _, r in pairs(records) do
                        if r.station and string.find(r.station, filter, 1, true) then
                            train.manual_mode = manual_mode
                            count = count + 1
                            break
                        end
                    end
                end
            else
                train.manual_mode = manual_mode
                count = count + 1
            end
        end
    end
    player.print("#train=" .. count)
end

---@param p CustomCommandData
local function cmd_stat(p)
    local player = game.players[p.player_index]
    local context = yutils.get_context()
    local force_index = player.force_index

    local station_count = 0
    local depot_count = 0
    local used_depot_count = 0
    local buffer_count = 0
    local refueler_count = 0
    local feeder_count = 0
    local invalid_device_count = 0
    for _, device in pairs(devices_runtime.map) do
        ---@cast device Device
        if device.force_id == force_index then
            station_count = station_count + 1
            if device.role == defs.device_roles.depot then
                depot_count = depot_count + 1
                if device.train then
                    used_depot_count = used_depot_count + 1
                end
            elseif device.role == defs.device_roles.buffer then
                buffer_count = buffer_count + 1
            elseif device.role == defs.device_roles.refueler then
                refueler_count = refueler_count + 1
            elseif device.role == defs.device_roles.feeder then
                feeder_count = feeder_count + 1
            end
            if not device.entity.valid then
                invalid_device_count = invalid_device_count + 1
            end
        end
    end

    local train_count = 0
    local free_train_count = 0
    local free_cargo_count = 0
    local free_fluid_count = 0
    local invalid_train_count = 0
    for _, train in pairs(context.trains) do
        train_count = train_count + 1
        if train.depot and train.depot.force_id == force_index and
            train.depot.role == defs.device_roles.depot then
            free_train_count = free_train_count + 1
            if train.cargo_count > 0 then
                free_cargo_count = free_cargo_count + 1
            end
            if train.fluid_capacity > 0 then
                free_fluid_count = free_fluid_count + 1
            end
        end
        if not train.train.valid then
            invalid_train_count = invalid_train_count + 1
        end
    end

    player.print("#stations=" .. station_count)
    player.print("#depots=" .. depot_count)
    player.print("#used depots=" .. used_depot_count)
    player.print("#free depots=" .. (depot_count - used_depot_count))
    player.print("#buffer=" .. buffer_count)
    player.print("#feeder=" .. feeder_count)
    player.print("#refueler_count=" .. refueler_count)
    player.print("#trains=" .. train_count)
    player.print("#free trains=" .. free_train_count)
    player.print("#free cargo trains=" .. free_cargo_count)
    player.print("#free fluid trains=" .. free_fluid_count)
    player.print("#used trains=" .. (train_count - free_train_count))
    player.print("#invalid_train_count=" .. invalid_train_count)
    player.print("#invalid_device_count=" .. invalid_device_count)
end

---@param p CustomCommandData
local function cmd_active(p)
    local player = game.players[p.player_index]
    local force_index = player.force_index
    for _, device in pairs(devices_runtime.map) do
        ---@cast device Device
        if device.entity.force_index == force_index then
            device.dconfig.inactive = nil
            device.inactive = nil
        end
    end
end

---@param p CustomCommandData
local function cmd_list_manual(p)
    local player = game.players[p.player_index]
    player.print("---- List train in manual mode -- ")

    local count = 0
    local force = player.force
    local context = yutils.get_context()
    for _, surface in pairs(game.surfaces) do
        for _, train in pairs(surface.get_trains(force)) do
            if train.front_stock.force == force and train.manual_mode then
                local mtrain = context.trains[train.id]
                if not(mtrain and mtrain.teleporting) then
                    player.print({ "", "TRAIN=", logger.gps_to_text(train.front_stock) })
                    count = count + 1
                end
            end
        end
    end
    player.print("#train=" .. count)
end

---@param p CustomCommandData
local function cmd_distances(p)
    local player = game.players[p.player_index]
    local sid = p.parameter
    local id
    player.clear_console()
    if not sid then
        local vars = tools.get_vars(player)
        id = vars.selected_device_id
    else
        id = tonumber(sid)
    end

    if not id then
        player.print("need id")
        return
    end

    local device = devices_runtime.map[id]
    ---@cast device Device

    player.print("------------------ To ------- ")
    local to_count = 0
    if (device.distance_cache) then
        for toid, dist in pairs(device.distance_cache) do
            local to_device = devices_runtime.map[toid]
            ---@cast to_device Device
            if to_device then
                local pos = "[" .. to_device.position.x .. "," .. to_device.position.y .. "]"
                player.print("To: " .. to_device.trainstop.backer_name .. pos .. " = " .. tostring(dist))
                to_count = to_count + 1
            end
        end
    end
    local from_count = 0
    player.print("------------------ From ------- ")
    for _, from_device in pairs(devices_runtime.map) do
        ---@cast from_device Device
        if from_device.distance_cache and from_device.distance_cache[id] then
            local pos = "[" .. from_device.position.x .. "," .. from_device.position.y .. "]"
            player.print("From: " .. from_device.trainstop.backer_name .. pos .. " = " .. tostring(from_device.distance_cache[id]))
            from_count = from_count + 1
        end
    end
    player.print("---- #to=" .. to_count .. ", #from=" .. from_count)
end

---@param p CustomCommandData
local function cmd_teleporters(p)
    local player = game.players[p.player_index]

    device_selection.show_teleporters(player)
end

commands.add_command("yatm_scheduler", { "yaltn_scheduler" }, cmd_scheduler)
commands.add_command("yatm_disable_network", { "yaltn_disable_network" }, cmd_disable_network)
commands.add_command("yatm_enable_network", { "yaltn_enable_network" }, cmd_enable_network)
commands.add_command("yatm_log", { "yaltn_log" }, cmd_log)
commands.add_command("yatm_trains", { "yaltn_trains" }, cmd_trains)
commands.add_command("yatm_stat", { "yaltn_stat" }, cmd_stat)
commands.add_command("yatm_manual_mode", { "yaltn_manual_mode" }, cmd_manual_mode)
commands.add_command("yatm_active", { "yatm_active" }, cmd_active)
commands.add_command("yatm_list_manual", { "yatm_list_manual" }, cmd_list_manual)
commands.add_command("yatm_distances", { "yatm_distances" }, cmd_distances)
commands.add_command("yatm_teleporters", { "yatm_teleporters" }, cmd_teleporters)

local function on_load() devices_runtime = Runtime.get("Device") end
tools.on_load(on_load)

return cmd
