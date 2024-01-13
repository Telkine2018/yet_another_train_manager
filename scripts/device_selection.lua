local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local allocator = require("scripts.allocator")
local trainconf = require("scripts.trainconf")

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

    if not entity or entity.name ~= commons.device_name or not entity.valid then
        vars.selected_device = nil
        return
    end

    vars.selected_device = entity

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
            end
            ::end_deliveries::
        end

        if next(device.requested_items) then
            color = device.dconfig.inactive and { 1, 0, 1, 1 } or { 1, 0, 0, 1 }
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
            color = device.dconfig.inactive and { 1, 0, 1, 1 } or { 0, 1, 0, 1 }
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
            local percent = device.ebuffer.energy /
                commons.teleport_electric_buffer_size * 100
            color = device.dconfig.inactive and { 1, 0, 1, 1 } or
                (percent < 0 and { 1, 0, 0, 1 } or { 0, 1, 0, 1 })
            if percent < 100 then
                color = { 1, 0, 0, 1 }
            else
                color = { 0, 1, 0, 1 }
            end
            if (device.teleport_last_src and device.teleport_last_src.trainstop.valid) then
                draw_text(" << " .. device.teleport_last_src.trainstop.backer_name)
            end
            if (device.teleport_last_dst and device.teleport_last_dst.trainstop.valid) then
                draw_text(" >> " .. device.teleport_last_dst.trainstop.backer_name)
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
                    draw_text{"", text}
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
