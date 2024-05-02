local flib_format = require("__flib__/format")
local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local allocator = require("scripts.allocator")
local trainconf = require("scripts.trainconf")
local pathing = require("scripts.pathing")

local device_selection = {}

local prefix = commons.prefix
local frame_name = prefix .. "-frame"

local comma_value = tools.comma_value

---@type Runtime
local devices_runtime
---@type EntityMap<Device>
local devices

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

-- #region Signal display

local area_color = { 1, 1, 0, 0.02 }

---@param device Device
local function trainstop_to_text(device)
    local trainstop = device.trainstop
    if not trainstop.valid then return "<invalide>" end
    return trainstop.surface.name .. ":" .. trainstop.backer_name
end

local tag_signal = commons.prefix .. "-teleporter_range"

---@param player LuaPlayer
---@return boolean?
local function remove_teleport_range(player)
    local force = player.force
    local tags = force.find_chart_tags(player.surface)
    local found
    for _, t in ipairs(tags) do
        if t.icon and t.icon.name == tag_signal then
            t.destroy()
            found = true
        end
    end
    return found
end


---@param player LuaPlayer
---@param device Device
local function show_teleport_range(player, device)
    local surface = device.entity.surface
    local force = player.force
    local range = device.teleport_range

    local count = math.floor(32 * range / 200)
    if count == 0 then return end

    local position = device.entity.position
    local icon = {
        type = "virtual",
        name = tag_signal
    }
    for i = 0, 2 * count - 1 do
        local angle = i * math.pi / count
        local cos = math.cos(angle)
        local sin = math.sin(angle)

        local x = position.x + range * cos
        local y = position.y + range * sin

        force.add_chart_tag(surface, {
            icon = icon,
            position = { x, y },
            last_user = player
        })
    end
end

---@param player LuaPlayer
local function show_teleporters(player)
    local context = yutils.get_context()
    local network = yutils.get_network_base(player.force_index, player.surface_index)

    if not remove_teleport_range(player) then
        if network.teleporters then
            for _, teleporter in pairs(network.teleporters) do
                show_teleport_range(player, teleporter)
            end
        end
    end
end
device_selection.show_teleporters = show_teleporters

local flow_name = commons.prefix .. ".selection_flow"

---@param player LuaPlayer
---@return LuaGuiElement
local function get_flow(player)
    local flow = player.gui.left[flow_name]
    if flow then return flow end
    flow = player.gui.left.add { type = "frame", direction = "vertical", name = flow_name }
    return flow
end

---@param player LuaPlayer
---@param entity LuaEntity
local function show_selected(player, entity)
    local vars = tools.get_vars(player)

    if vars.selected_device_area_id then
        rendering.destroy(vars.selected_device_area_id)
        vars.selected_device_area_id = nil
    end

    if vars.selected_device_text_ids then
        for _, id in pairs(vars.selected_device_text_ids) do
            rendering.destroy(id)
        end
        vars.selected_device_text_ids = nil
    end

    local flow = player.gui.left[flow_name]
    if flow then
        flow.destroy()
    end

    if not entity or entity.name ~= commons.device_name or not entity.valid then
        vars.selected_device = nil
        return
    end

    ---@type Device
    local device = devices[entity.unit_number]
    vars.selected_device_id = entity.unit_number
    if not device then return end

    if not device.trainstop or not device.trainstop.valid then
        local area = yutils.get_device_area(device, true)
        vars.selected_device_area_id = rendering.draw_rectangle {
            draw_on_ground = true,
            width = 2,
            left_top = entity,
            left_top_offset = area[1],
            right_bottom = entity,
            right_bottom_offset = area[2],
            surface = entity.surface,
            color = area_color,
            only_in_alt_mode = true
        }
    else
        vars.selected_device_area_id = rendering.draw_circle {

            color = area_color,
            target = device.trainstop,
            surface = entity.surface,
            radius = 1,
            width = 3,
            draw_on_ground = true,
            only_in_alt_mode = true
        }

        local ids = {}
        vars.selected_device_text_ids = ids
        local colors = commons.colors

        local y = -1
        local yd = 1.2
        local color = { 1, 1, 1, 1 }

        local text_line = 0
        local max_line = 10

        local function draw_text(text)
            local renderid = rendering.draw_text {
                target = device.entity,
                use_rich_text = true,
                only_in_alt_mode = true,
                target_offset = { 0, y },
                surface = device.entity.surface,
                text = text,
                alignment = "center",
                vertical_alignment = "bottom",
                scale = 2,
                color = color
            }
            y = y - yd
            table.insert(ids, renderid)
            text_line = text_line + 1
            return renderid
        end

        if next(device.deliveries) then
            color = { 1, 1, 0, 1 }
            for _, delivery in pairs(device.deliveries) do
                local d = delivery
                while delivery do
                    for name, amount in pairs(delivery.content) do
                        local text
                        if delivery.provider == device then
                            text = { "yaltn-messages.tooltip_delivery_to" }
                        else
                            text = { "yaltn-messages.tooltip_delivery_from" }
                        end
                        local signalId = tools.sprite_to_signal(name) --[[@as SignalID]]
                        table.insert(text, comma_value(amount))
                        table.insert(text, "[" .. signalId.type .. "=" ..
                            signalId.name .. "]")
                        if delivery.provider == device then
                            table.insert(text, trainstop_to_text(delivery.requester))
                        else
                            table.insert(text, trainstop_to_text(delivery.provider))
                        end
                        draw_text(text)
                        if text_line > max_line then goto end_deliveries end
                    end
                    delivery = delivery.combined_delivery
                end
                if d.train and d.train.front_stock.valid and not d.train.teleporting then
                    local flow = get_flow(player)

                    local distance = pathing.train_distance(d.train, device)
                    local pos = d.train.front_stock.position
                    local camera = flow.add { type = "camera", position = pos, surface = entity.surface_index }
                    camera.style.size = 300
                    camera.zoom = 0.2
                    camera.entity = d.train.front_stock

                    local label_flow = camera.add { type = "flow", direction = "vertical" }
                    local label_value

                    if distance > 0 then
                        label_value = string.format("%0.1f", distance) .. " m"
                    else
                        label_value = "N/A"
                    end

                    local fdistance = label_flow.add { type = "label", caption =  label_value}
                    fdistance.style = "yatm_camera_label"

                    local duration = game.tick - d.start_tick
                    local fduration = label_flow.add { type = "label", caption = flib_format.time(duration) }
                    fduration.style = "yatm_camera_label"

                    local schedule = d.train.train.schedule
                    local current = schedule.current
                    local records = schedule.records
                    local station
                    for index = current, #records do
                        station = records[index].station
                        if station then
                            break
                        end
                    end
                    if station then
                        local fstation = label_flow.add { type = "label", caption = "-> " .. station }
                        fstation.style = "yatm_camera_label"
                    end
                    local train = d.train.train
                    local contents = train.get_contents()
                    local fluid_contents = train.get_fluid_contents()
                    if next(contents) or next(fluid_contents) then

                        for item, count in pairs(contents) do
                            local content_table = {}
                            table.insert(content_table, flib_format.number(count))
                            table.insert(content_table, "x")
                            table.insert(content_table, "[item=" .. item .."]")
                            local caption = table.concat(content_table," ")
                            local fcontent = label_flow.add { type = "label", caption = caption }
                            fcontent.style = "yatm_camera_label"
                            end
                        for fluid, count in pairs(fluid_contents) do
                            local content_table = {}
                            table.insert(content_table, flib_format.number(count))
                            table.insert(content_table, "x")
                            table.insert(content_table, "[fluid=" .. fluid .."]")
                            local fcontent = label_flow.add { type = "label", caption = caption }
                            fcontent.style = "yatm_camera_label"
                        end
                    end
                end
            end
            ::end_deliveries::
        end

        if next(device.requested_items) then
            color = device.inactive and { 1, 0, 1, 1 } or { 1, 0, 0, 1 }
            for name, request in pairs(device.requested_items) do
                local amount = request.requested - request.provided
                if amount >= request.threshold then
                    local text = { "yaltn-messages.tooltip_requested_item" }
                    local signalId = tools.sprite_to_signal(name) --[[@as SignalID]]
                    table.insert(text, comma_value(amount))
                    table.insert(text, "[" .. signalId.type .. "=" ..
                        signalId.name .. "]")
                    if request.failcode then
                        table.insert(text, { "", " (", { "yaltn-error.m" .. request.failcode }, ")" })
                    else
                        table.insert(text, "")
                    end
                    draw_text(text)
                    if text_line > max_line then break end
                end
            end
        end

        if next(device.produced_items) then
            color = device.inactive and { 1, 0, 1, 1 } or { 0, 1, 0, 1 }
            for name, request in pairs(device.produced_items) do
                local amount = request.provided - request.requested
                local text = { "yaltn-messages.tooltip_provide_item" }
                local signalId = tools.sprite_to_signal(name) --[[@as SignalID]]
                table.insert(text, comma_value(amount))
                table.insert(text,
                    "[" .. signalId.type .. "=" .. signalId.name .. "]")
                draw_text(text)
                if text_line > max_line then break end
            end
        end

        if device.ebuffer then
            local percent = device.ebuffer.energy / commons.teleport_electric_buffer_size * 100
            color = device.inactive and { 1, 0, 1, 1 } or (percent < 100 and { 1, 0, 0, 1 } or { 0, 1, 0, 1 })
            if (device.teleport_last_src and device.teleport_last_src.trainstop.valid) then
                draw_text(" << " .. device.teleport_last_src.trainstop.backer_name)
            end
            if (device.teleport_last_dst and device.teleport_last_dst.trainstop.valid) then
                draw_text(" >> " .. device.teleport_last_dst.trainstop.backer_name)

                local flow = get_flow(player)
                local entity = device.teleport_last_dst.trainstop
                local pos = entity.position
                local direction = entity.direction
                local offset = 5
                if direction == defines.direction.north then
                    pos.y = pos.y - offset
                elseif direction == defines.direction.south then
                    pos.y = pos.y + offset
                elseif direction == defines.direction.west then
                    pos.x = pos.x + offset
                elseif direction == defines.direction.east then
                    pos.x = pos.x - offset
                end
                local camera = flow.add { type = "camera", position = pos, surface = entity.surface_index }
                camera.style.size = 300
                camera.zoom = 0.2
            end
            if device.failcode and device.failcode >= 200 and device.failcode <= 300 then
                draw_text { "yaltn-teleport.m" .. device.failcode }
            end
            local ecount = device.teleport_ecount or 0
            local rcount = device.teleport_rcount or 0
            draw_text(string.format("%.2f %%", percent) .. " (" ..
                tostring(ecount) .. "/" .. tostring(rcount) .. "/" ..
                tostring(device.teleport_failure or 0) .. ")")
        end

        if device.role == defs.device_roles.builder then
            local create_count = (device.builder_create_count or 0)
            local remove_count = (device.builder_remove_count or 0)
            local target_count = (device.trains and table_size(device.trains) or
                0)
            local text = " (" .. tostring(create_count) .. "/" .. tostring(remove_count) .. "/" .. target_count .. ")"
            draw_text(text)
        end

        if settings.get_player_settings(player)["yaltn-show_train_mask"].value then
            trainconf.scan_device(device)
            device.patterns = device.dconfig.patterns or device.scanned_patterns
            if device.patterns then
                for pattern in pairs(device.patterns) do
                    local markers = yutils.create_layout_strings(pattern)
                    local text = table.concat(markers)
                    draw_text { "", text }
                end
            end
        end

        if device.role == defs.device_roles.builder then
            allocator.builder_is_available(device)
            if device.failcode and device.failcode > 10 and device.failcode < 20 then
                draw_text({ "yaltn-error.m" .. device.failcode });
            end
        end
    end
end

---@param e EventData.on_selected_entity_changed
local function on_selected_entity_changed(e)
    local player = game.players[e.player_index]
    local entity = player.selected

    show_selected(player, entity)
end

local function scan_players()
    for _, player in pairs(game.players) do
        show_selected(player, player.selected)
    end
end

tools.on_nth_tick(60, scan_players)

tools.on_event(defines.events.on_selected_entity_changed,
    on_selected_entity_changed)

return device_selection
