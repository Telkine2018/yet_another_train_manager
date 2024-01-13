local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local trainconf = require("scripts.trainconf")

local prefix = commons.prefix

local uiutils = {}

---@param name string
---@return string
local function np(name) return prefix .. "layout_editor" .. name end

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

uiutils.tab = {
    stock = 1,
    stations = 2,
    trains = 3,
    history = 4,
    assign = 5,
    depots = 6,
    events = 7,
    stats = 8
}

uiutils.uiframe_name = commons.prefix .. "-uiframe"
uiutils.element_prefix = commons.prefix .. "-uiutils."

uiutils.slot_internal_color = "flib_slot_pink"
uiutils.slot_provided_color = "flib_slot_green"
uiutils.slot_requested_color = "flib_slot_red"
uiutils.slot_transit_color = "flib_slot_blue"
uiutils.slot_signal_color = "flib_slot_grey"

---@param name string
---@return string
local function np(name) return uiutils.element_prefix .. name end

---@param player LuaPlayer
---@return UIConfig
function uiutils.get_uiconfig(player)

    ---@type UIConfig
    local uiconfig = tools.get_vars(player).uiconfig
    if not uiconfig then
        uiconfig = {}
        tools.get_vars(player).uiconfig = uiconfig
    end
    return uiconfig
end

---@param player LuaPlayer
---@return LuaGuiElement
function uiutils.get_frame(player) return
    player.gui.screen[uiutils.uiframe_name] end

---@param player LuaPlayer
---@param name string
function uiutils.get_child(player, name)
    return tools.get_child(player.gui.screen[uiutils.uiframe_name], name)
end

-- #region Filters

---@param player  LuaPlayer
---@return fun(d:Device):boolean
function uiutils.build_station_filter(player)

    local conditions = {}

    local uiconfig = uiutils.get_uiconfig(player)
    if uiconfig.network_mask and uiconfig.network_mask ~= 0 then

        ---@param device Device
        local cond = function(device)
            return bit32.band(device.network_mask, uiconfig.network_mask) ~= 0
        end
        table.insert(conditions, cond)
    end

    if uiconfig.signal_filter then

        ---@param device Device
        local cond = function(device)

            return device.requested_items[uiconfig.signal_filter] or
                       device.produced_items[uiconfig.signal_filter] or
                       (device.internal_requests and
                           device.internal_requests[uiconfig.signal_filter])
        end
        table.insert(conditions, cond)
    end

    if uiconfig.surface_name then

        ---@param device Device
        local cond = function(device)

            return device.network.surface_name == uiconfig.surface_name
        end
        table.insert(conditions, cond)
    end

    if uiconfig.text_filter and uiconfig.text_filter ~= "" then

        ---@param device Device
        local cond = function(device)
            return device.trainstop and device.trainstop.valid and
                       string.find(device.trainstop.backer_name,
                                   uiconfig.text_filter, 1, true)
        end
        table.insert(conditions, cond)
    end

    if uiconfig.station_state and uiconfig.station_state ~= 0 then

        ---@param device Device
        local cond = function(device)
            return device.image_index == uiconfig.station_state
        end
        table.insert(conditions, cond)
    end

    ---@param device Device
    return function(device)

        for _, cond in pairs(conditions) do
            if not cond(device) then return false end
        end
        return true
    end
end

---@param player  LuaPlayer
---@return fun(d:Delivery):boolean
function uiutils.build_delivery_filter(player)

    local conditions = {}

    local uiconfig = uiutils.get_uiconfig(player)
    if uiconfig.network_mask and uiconfig.network_mask ~= 0 then

        ---@param delivery Delivery
        local cond = function(delivery)
            return bit32.band(delivery.requester.network_mask,
                              uiconfig.network_mask) ~= 0 or
                       bit32.band(delivery.provider.network_mask,
                                  uiconfig.network_mask) ~= 0
        end
        table.insert(conditions, cond)
    end

    if uiconfig.signal_filter then

        ---@param delivery Delivery
        local cond = function(delivery)
            return delivery.content[uiconfig.signal_filter]
        end
        table.insert(conditions, cond)
    end

    if uiconfig.surface_name then

        ---@param delivery Delivery
        local cond = function(delivery)

            return delivery.requester.network.surface_name ==
                       uiconfig.surface_name or
                       delivery.provider.network.surface_name ==
                       uiconfig.surface_name
        end
        table.insert(conditions, cond)
    end

    if uiconfig.text_filter then

        ---@param delivery Delivery
        local cond = function(delivery)
            return (delivery.provider.trainstop and
                       delivery.provider.trainstop.valid and
                       string.find(delivery.provider.trainstop.backer_name,
                                   uiconfig.text_filter, 1, true)) or
                       (delivery.requester.trainstop and
                           delivery.requester.trainstop.valid and
                           string.find(delivery.requester.trainstop.backer_name,
                                       uiconfig.text_filter, 1, true))
        end
        table.insert(conditions, cond)
    end

    ---@param delivery Delivery
    return function(delivery)

        for _, cond in pairs(conditions) do
            if not cond(delivery) then return false end
        end
        return true
    end
end

---@param player  LuaPlayer
---@return fun(train:Train):boolean
function uiutils.build_train_filter(player)

    local conditions = {}

    local uiconfig = uiutils.get_uiconfig(player)
    if uiconfig.network_mask and uiconfig.network_mask ~= 0 then
        ---@param train Train
        local cond = function(train)
            return bit32.band(train.network_mask, uiconfig.network_mask) ~= 0
        end
        table.insert(conditions, cond)
    end

    if uiconfig.signal_filter then
        ---@param train Train
        local cond = function(train)
            return train.delivery and
                       train.delivery.content[uiconfig.signal_filter]
        end
        table.insert(conditions, cond)
    end

    if uiconfig.surface_name then
        ---@param train Train
        local cond = function(train)
            return train.front_stock.valid and train.front_stock.surface.name ==
                       uiconfig.surface_name
        end
        table.insert(conditions, cond)
    end

    if uiconfig.text_filter and uiconfig.text_filter ~= "" then
        ---@param train Train
        local cond = function(train)
            return train.delivery and
                       ((train.delivery.provider.trainstop and
                           train.delivery.provider.trainstop.valid and
                           string.find(
                               train.delivery.provider.trainstop.backer_name,
                               uiconfig.text_filter, 1, true)) or
                           (train.delivery.requester.trainstop and
                               train.delivery.requester.trainstop.valid and
                               string.find(
                                   train.delivery.requester.trainstop
                                       .backer_name, uiconfig.text_filter, 1,
                                   true)))
        end
        table.insert(conditions, cond)
    end

    ---@param train Train
    return function(train)
        for _, cond in pairs(conditions) do
            if not cond(train) then return false end
        end
        return true
    end
end

-- #endregion

-- #region Components

---@type table<string, string>
local order_cache = {}

---@param name string
---@return string
function uiutils.get_product_order(name)

    local order = order_cache[name]
    if not order then
        local signal = tools.sprite_to_signal(name) --[[@as SignalID]]
        local proto
        if signal.type == "item" then
            proto = game.item_prototypes[signal.name]
            order = proto.group.order .. "  " .. proto.subgroup.order ..
                        "  " .. proto.order
        elseif signal.type == "fluid" then
            proto = game.fluid_prototypes[signal.name]
            order = proto.group.order .. "  " .. proto.subgroup.order ..
                        "  " .. proto.order
        elseif signal.type == "virtual" then
            proto = game.virtual_signal_prototypes[signal.name]
            order = proto.subgroup.order .. "  " .. proto.order
        else
            order = ""
        end
        order_cache[name] = order
    end
    return order
end

local get_product_order = uiutils.get_product_order

function uiutils.sort_products(products)

    local list = {}
    for name, count in pairs(products) do
        local order = get_product_order(name)
        table.insert(list, {name = name, count = count, order = order})
        ::skip::
    end

    table.sort(list, function(e1, e2) return e1.order < e2.order end)
    return list
end

---@param container LuaGuiElement
---@param sorted_products {name:string, count:integer}[]
---@param style string
---@param tooltip string
---@param handler_name string?
---@param handler_tags Tags?
function uiutils.display_products(container, sorted_products, style, tooltip, handler_name, handler_tags)

    if not handler_name then handler_name = np("product_button") end
    for _, sorted_product in ipairs(sorted_products) do
        local name, count = sorted_product.name, sorted_product.count
        local signalid = tools.sprite_to_signal(name)
        local proto
        ---@cast signalid -nil

        local sprite_name = name
        if signalid.type == "item" then
            proto = game.item_prototypes[signalid.name]
        elseif signalid.type == "fluid" then
            proto = game.fluid_prototypes[signalid.name]
        elseif signalid.type == "virtual" then
            proto = game.virtual_signal_prototypes[signalid.name]
            sprite_name = "virtual-signal/" .. signalid.name
        else
            goto skip
        end
        local formatted = luautil.format_number(count, true)
        if not tooltip then
            tooltip = np("tooltip-item")
        end
        local button = container.add {
            type = "sprite-button",
            sprite = sprite_name,
            style = style,
            tooltip = { tooltip, formatted, proto.localised_name, "[img=" .. sprite_name .. "]" }
        }
        tools.set_name_handler(button, handler_name, handler_tags)
        local label = button.add {
            type = "label",
            name = "label",
            style = "yatm_count_label_bottom",
            ignored_by_interaction = true
        }
        label.caption = formatted
        ::skip::
    end
end

uiutils.bkg_style = "deep_frame_in_shallow_frame"

local bkg_style = uiutils.bkg_style

---@param container LuaGuiElement
---@param content_name string
---@param cols integer
---@param lines integer
---@return LuaGuiElement
---@return LuaGuiElement
function uiutils.create_product_table(container, content_name, cols, lines)

    local frame = container.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }

    local content = frame.add {
        type = "table",
        column_count = cols,
        style = "slot_table"
    }

    tools.set_name_handler(content, content_name)
    frame.style.width = cols * 40 + 2
    frame.style.right_margin = 6
    content.style.minimal_height = lines * 41
    return frame, content
end

---@param row LuaGuiElement
---@param delivery Delivery
---@param field_widh integer
---@return LuaGuiElement
function uiutils.create_delivery_routing(row, delivery, field_widh)

    local delivery_flow = row.add {type = "flow", direction = "vertical"}
    delivery_flow.style.horizontal_align = "center"
    if delivery then
        local provider = delivery.provider
        local f
        if provider.trainstop.valid then
            f = delivery_flow.add {
                type = "label",
                caption = provider.trainstop.backer_name,
                style = "yatm_clickable_semibold_label",
                tooltip = {uiutils.np("station_tooltip")}
            }
            f.style.horizontal_align = "center"
            f.style.width = field_widh
            tools.set_name_handler(f, uiutils.np("station"),
                                   {device = provider.id})
        end
        local requester = delivery.requester
        if requester.trainstop.valid then
            f = delivery_flow.add {
                type = "sprite",
                sprite = commons.prefix .. "_down"
            }
            f.style.horizontal_align = "center"
            f = delivery_flow.add {
                type = "label",
                caption = requester.trainstop.backer_name,
                style = "yatm_clickable_semibold_label",
                tooltip = {uiutils.np("station_tooltip")}
            }
            tools.set_name_handler(f, uiutils.np("station"),
                                   {device = requester.id})
            f.style.width = field_widh
            f.style.horizontal_align = "center"
        end
    else
        delivery_flow.style.width = field_widh
    end
    return delivery_flow
end

---@param flow LuaGuiElement
---@param delivery Delivery
---@param field_widh integer
---@return LuaGuiElement
function uiutils.create_delivery_routing_horizontal(flow, delivery, field_widh)

    local delivery_flow = flow.add {type = "flow", direction = "horizontal"}
    if delivery then
        local provider = delivery.provider
        local f
        if provider.trainstop.valid then
            f = delivery_flow.add {
                type = "label",
                caption = provider.trainstop.backer_name,
                style = "yatm_clickable_semibold_label",
                tooltip = {uiutils.np("station_tooltip")}
            }
            tools.set_name_handler(f, uiutils.np("station"),
                                   {device = provider.id})
            f.style.left_margin = 4
        end
        local requester = delivery.requester
        if requester.trainstop.valid then
            f = delivery_flow.add {
                type = "sprite",
                sprite = commons.prefix .. "_arrow"
            }
            f.style.top_margin = 2
            f.style.left_margin = 4
            f = delivery_flow.add {
                type = "label",
                caption = requester.trainstop.backer_name,
                style = "yatm_clickable_semibold_label",
                tooltip = {uiutils.np("station_tooltip")}
            }
            tools.set_name_handler(f, uiutils.np("station"),
                                   {device = requester.id})
        end
        delivery_flow.style.width = field_widh
    else
        delivery_flow.style.width = field_widh
    end
    return delivery_flow
end

---@param row LuaGuiElement
---@param caption LocalisedString
---@param field_widh integer
---@return LuaGuiElement
function uiutils.create_textfield(row, caption, field_widh)

    local textfield = row.add {type = "label", caption = caption}
    textfield.style.horizontal_align = "center"
    textfield.style.width = field_widh
    return textfield
end

---@param player LuaPlayer
---@param entity LuaEntity
---@param follow LuaEntity?
function uiutils.zoom_to(player, entity, follow)

    if not entity.valid then return end

    if remote.interfaces["space-exploration"] and
        remote.call("space-exploration", "remote_view_is_unlocked",
                    {player = player}) then
        local zone = remote.call("space-exploration",
                                 "get_zone_from_surface_index",
                                 {surface_index = entity.surface_index})
        if zone then
            remote.call("space-exploration", "remote_view_start", {
                player = player,
                zone_name = zone.name,
                position = entity.position,
                freeze_history = true,
                location_name = ""
            })
            if follow and follow.surface_index == entity.surface_index then
                player.zoom_to_world(entity.position, 0.5, follow)
            end
            return
        end
    end

    if entity.surface_index == player.surface_index then
        player.close_map()
        if follow and follow.surface_index ~= player.surface_index then
            follow = nil
        end
        if follow then
            player.zoom_to_world(entity.position, 0.5, follow)
        else
            player.zoom_to_world(entity.position, 0.5)
        end
    end
end

uiutils.np = np

---@param frame LuaGuiElement
---@param header_defs HeaderDef[]
---@param prefix string
---@param offset integer?
---@return LuaGuiElement
function uiutils.create_header(frame, header_defs, prefix, offset)

    local header = frame.add {
        type = "table",
        column_count = #header_defs,
        style = "yatm_default_table"
    }
    header.draw_vertical_lines = true
    if not offset then offset = 3 end
    for i, header_def in pairs(header_defs) do
        local h
        if header_def.nosort then
            h = header.add {
                type = "label",
                caption = {prefix .. header_def.name},
                style = "yatm_header_label"
            }

        else
            h = header.add {
                type = "checkbox",
                caption = {prefix .. header_def.name},
                style = "yatm_sort_checkbox",
                state = false
            }
            tools.set_name_handler(h, prefix .. "sort", {sort = header_def.name})
        end
        h.style.width = header_def.width + offset
        offset = 0
    end
    return header
end

---@param content LuaGuiElement
---@param pattern string
---@return LuaGuiElement
function uiutils.create_train_composition(content, pattern)

    local ftrains = content.add {type = "flow", direction="horizontal"}
    local markers = yutils.create_layout_strings(pattern)
    local text = table.concat(markers)
    local label = ftrains.add {type = "label", caption = text}
    ftrains.style.minimal_height = 30
    label.style.font = commons.layout_font
    return ftrains
end

---@param content LuaGuiElement
---@param device Device
---@return LuaGuiElement
function uiutils.create_device_composition(content, device)
    local flow = content.add {type="flow", direction="vertical"}
    if device.patterns then
        for pattern, _ in pairs(device.patterns) do
            uiutils.create_train_composition(flow, pattern)
        end
    end
    return flow
end

---@param content LuaGuiElement
---@param device Device
---@param width integer?
---@return LuaGuiElement
function uiutils.create_station_name(content, device, width)

    local name = device.trainstop.backer_name
    local fname = content.add {
        type = "label",
        caption = name,
        style = "yatm_clickable_semibold_label",
        tooltip = {np("station_tooltip")}
    }
    if width then fname.style.width = width end
    tools.set_name_handler(fname, np("station"), {device = device.id})
    return fname
end

---@param row LuaGuiElement
---@param name string
---@param amount integer
---@param color string
---@return LuaGuiElement
function uiutils.create_product_button(row, name, amount, color)

    local signalid = tools.sprite_to_signal(name)
    local proto
    ---@cast signalid -nil

    local sprite_name = name
    if signalid.type == "item" then
        proto = game.item_prototypes[signalid.name]
    elseif signalid.type == "fluid" then
        proto = game.fluid_prototypes[signalid.name]
    elseif signalid.type == "virtual" then
        proto = game.virtual_signal_prototypes[signalid.name]
        sprite_name = "virtual-signal/" .. signalid.name
    end

    local formatted = luautil.format_number(amount, true)
    local button = row.add {
        type = "sprite-button",
        sprite = sprite_name,
        style = color,
        tooltip = { np("tooltip-item"), formatted, proto.localised_name, "[img=" .. sprite_name .. "]"
        }
    }
    tools.set_name_handler(button, np("product_button"))
    local label = button.add {
        type = "label",
        name = "label",
        style = "yatm_count_label_bottom",
        ignored_by_interaction = true
    }
    label.caption = formatted
    return button
end

-- #endregion

-- #region Global handler

---@param player LuaPlayer
---@return boolean
function uiutils.can_teleport(player)
    return game.active_mods["Teleporters"] and
               player.force.technologies["teleporter"].enabled
end

---@param player LuaPlayer
---@param surface LuaSurface
---@param position MapPosition
function uiutils.teleport(player, surface, position)

    uiutils.hide(player)
    if remote.interfaces["space-exploration"] then
        remote.call("space-exploration", "remote_view_stop", {player = player})
    end
    if player.vehicle then
        if player.vehicle.type == "spider-vehicle" then
            player.vehicle.teleport(position, surface, true)
        end
    else
        player.teleport(position, surface, true)
    end
end

tools.on_named_event(uiutils.np("station"), defines.events.on_gui_click,
---@param e EventData.on_gui_click
                     function(e)

    if not (e.element and e.element.valid) then return end
    local player = game.players[e.player_index]

    local device_id = e.element.tags.device
    ---@type Device
    local device = devices[device_id]
    if not device then return end

    local entity = device.entity
    if not entity.valid then return end

    if device.trainstop and device.trainstop.valid then
        rendering.draw_circle {
            surface = device.trainstop.surface,
            target = device.trainstop,
            color = {0, 1, 0},
            draw_on_ground = true,
            radius = 2,
            time_to_live = 600,
            width = 5,
            players = {player}
        }
    end

    if e.button == defines.mouse_button_type.left then
        if not (e.control or e.shift or e.alt) then
            player.opened = entity
        elseif e.shift and not e.control then
            uiutils.select_station(player, device.id)
        elseif e.control and not e.shift then
            uiutils.zoom_to(player, entity)
        elseif e.shift and e.control then
            if device.trainstop and device.trainstop.valid then
                player.opened = device.trainstop
            end
        end
    elseif e.button == defines.mouse_button_type.right then
        if uiutils.can_teleport(player) then

            local position = entity.position
            if entity.direction == 0 or entity.direction == 0.5 then
                position = {position.x, position.y - 1}
            else
                position = {position.x - 1, position.y}
            end
            uiutils.teleport(player, entity.surface, position)
        end
    end

end)

tools.on_named_event(np("train"), defines.events.on_gui_click, --
---@param e EventData.on_gui_click
function(e)
    local player = game.players[e.element.player_index]
    local context = yutils.get_context()
    local id = e.element.tags.id
    ---@type Train
    local train = context.trains[id]
    if train and train.train.valid then
        local front_stock = train.train.front_stock

        rendering.draw_circle {
            surface = front_stock.surface,
            target = front_stock,
            color = {0, 1, 0},
            draw_on_ground = true,
            radius = 3,
            time_to_live = 600,
            width = 5,
            players = {player}
        }

        if e.button == defines.mouse_button_type.left then
            if e.control then
                uiutils.hide(player)
                uiutils.zoom_to(player, train.front_stock, train.front_stock)
            else
                player.opened = train.train.front_stock
            end
        elseif e.button == defines.mouse_button_type.right then
            if uiutils.can_teleport(player) then
                local position = front_stock.position
                local orientation =
                    math.floor((front_stock.orientation - 0.125)) / 0.5

                if orientation == 0 or orientation == 3 then
                    position.y = position.y + 2
                else
                    position.x = position.x + 2
                end
                uiutils.teleport(player, front_stock.surface, position)
            end
        end
    end
end)


tools.on_named_event(np("delivery_detail"), defines.events.on_gui_click, --
---@param e EventData.on_gui_click
function(e)
    local player = game.players[e.element.player_index]

    uiutils.set_signal_filter(player, e.element.tags.product)
    uiutils.show_tab(player, uiutils.tab.history)
    uiutils.update(player)
end)

-- #endregion

function uiutils.hide(player) end
function uiutils.update(player) end
function uiutils.select_station(player, stationid) end
function uiutils.show_tab(player, index) end
function uiutils.set_signal_filter(player, name) end

return uiutils
