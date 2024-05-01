local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local device_manager = require("scripts.device")
local trainconf = require("scripts.trainconf")
local layout_editor = require("scripts.layout_editor")

local gui = {}

local prefix = commons.prefix
local frame_name = commons.gui_frame_name
local device_prefix = prefix .. "-device."

---@param name string
---@return string
local function np(name) return device_prefix .. name end

---@type Runtime
local devices_runtime
---@type EntityMap<Device>
local devices

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

---@param player LuaPlayer
local function get_frame(player) return player.gui.screen[frame_name] end

---@param player LuaPlayer
local function close_ui(player)
    local frame = get_frame(player)
    if frame then frame.destroy() end
    tools.get_vars(player).edited_device = nil
end

---@param e EventData.on_gui_closed
local function on_gui_closed(e)
    local player = game.get_player(e.player_index) --[[@as LuaPlayer]]
    close_ui(player)
end

local use_carry = {

    [defs.device_roles.provider] = true,
    [defs.device_roles.requester] = true,
    [defs.device_roles.provider_and_requester] = true,
    [defs.device_roles.buffer] = true,
    [defs.device_roles.feeder] = true
}

local has_priority = {

    [defs.device_roles.provider] = true,
    [defs.device_roles.requester] = true,
    [defs.device_roles.provider_and_requester] = true,
    [defs.device_roles.buffer] = true,
    [defs.device_roles.feeder] = true,
    [defs.device_roles.depot] = true,
    [defs.device_roles.builder] = true,
}


---@param parent LuaGuiElement
local function create_line(parent)
    local line = parent.add { type = "line" }
    line.style.top_margin = 5
    line.style.bottom_padding = 5
end

local use_requester = {

    [defs.device_roles.requester] = true,
    [defs.device_roles.provider_and_requester] = true,
    [defs.device_roles.buffer] = true
}

local use_provider_not_buffer = {

    [defs.device_roles.provider] = true,
    [defs.device_roles.provider_and_requester] = true
}

local use_all_enable = {

    [defs.device_roles.provider] = true,
    [defs.device_roles.requester] = true,
    [defs.device_roles.provider_and_requester] = true,
    [defs.device_roles.buffer] = true,
    [defs.device_roles.depot] = true,
    [defs.device_roles.refueler] = true,
    [defs.device_roles.builder] = true,
    [defs.device_roles.feeder] = true
}

---@param ftable LuaGuiElement
---@param device Device
local function create_fields(ftable, device)
    local dconfig = device.dconfig
    ftable.clear()

    local role = dconfig.role

    ---@param name string
    ---@param active boolean?
    ---@param len integer?
    ---@param value integer?
    local function create_mask(name, active, len, value)
        if not active then return end
        ftable.add { type = "label", caption = { np(name) } }
        local network_flow = ftable.add { type = "flow", name = name }
        local mask = 1
        local mask_value = value or dconfig[name] or 0
        if not len then
            len = settings.get_player_settings(ftable.player_index)["yaltn-gui_train_len"].value --[[@as integer]]
        end
        for i = 1, len do
            local state
            state = bit32.band(mask_value, mask) ~= 0
            network_flow.add {
                type = "checkbox",
                state = state,
                tooltip = { "", tostring(i) }
            }
            mask = 2 * mask
        end
    end

    ---@param name string
    ---@param active boolean
    ---@param tooltip string?
    ---@param allow_negative boolean?
    local function add_numeric_field(name, active, tooltip, allow_negative)
        if not active then return end

        if not tooltip then
            tooltip = ""
        end
        if not allow_negative then
            allow_negative = false
        end
        local value = dconfig[name]
        local svalue
        if value then svalue = tostring(value) end
        ftable.add { type = "label", caption = { np(name) } }
        local field = ftable.add {
            type = "textfield",
            name = name,
            numeric = true,
            text = svalue,
            allow_negative = true,
            clear_and_focus_on_right_click = true,
            tooltip = { tooltip }
        }
        field.style.width = 100
    end

    ---@param name string
    ---@param active boolean
    ---@param tooltip string?
    local function add_boolean_field(name, active, tooltip)
        if not active then return end

        local value = dconfig[name] or false
        ftable.add { type = "label", caption = { np(name) } }
        if not tooltip then
            tooltip = ""
        end
        local field = ftable.add {
            type = "checkbox",
            name = name,
            state = value,
            tooltip = { tooltip }
        }
    end

    ---@param name string
    ---@param active boolean
    ---@param filter any
    ---@param elem_type string
    ---@param default_item any
    local function add_item_field(name, active, filter, elem_type, default_item)
        if not active then return end
        if not elem_type then
            elem_type = "entity"
        end
        ftable.add { type = "label", caption = { np(name) } }

        local value = dconfig[name]
        if not value and default_item and game.item_prototypes[default_item] then
            value = default_item
        end
        if elem_type == "entity" then
            if value then
                local proto = game.item_prototypes[value]
                if proto then
                    value = proto.place_result.name
                end
            end
            ftable.add {
                type = "choose-elem-button",
                name = name,
                elem_type = "entity",
                elem_filters = filter,
                entity = value
            }
        elseif elem_type == "item" then
            ftable.add {
                type = "choose-elem-button",
                name = name,
                elem_type = "item",
                item = value,
                elem_filters = filter
            }
        end
    end

    create_mask("network_mask", use_all_enable[role], settings.get_player_settings(ftable.player_index)["yaltn-network_mask_size"].value --[[@as integer]])

    add_numeric_field("priority", has_priority[role], nil, true)
    add_numeric_field("rpriority", role == defs.device_roles.builder, nil, true)
    add_numeric_field("max_delivery", use_carry[role])
    add_numeric_field("delivery_timeout", use_requester[role] or role == defs.device_roles.feeder)
    add_numeric_field("threshold", use_requester[role])
    add_numeric_field("locked_slots", use_provider_not_buffer[role])
    add_numeric_field("inactivity_delay", use_carry[role], np("inactivity_delay.tooltip"))
    add_numeric_field("max_load_time", role == defs.device_roles.feeder, np("max_load_time.tooltip"))
    add_numeric_field("delivery_penalty", use_provider_not_buffer[role], nil, true)
    add_numeric_field("teleport_range", role == defs.device_roles.teleporter, nil, false)
    add_numeric_field("parking_penalty", role == defs.device_roles.depot, np("parking_penalty.tooltip"), true)

    add_boolean_field("station_locked", role == defs.device_roles.buffer or role == defs.device_roles.feeder)
    add_boolean_field("combined", use_requester[role], np("combined.tooltip"))
    add_boolean_field("no_remove_constraint", role == defs.device_roles.builder, np("no_remove_constraint.tooltip"))
    add_boolean_field("green_wire_as_priority", use_carry[role], np("green_wire_as_priority.tooltip"))

    local is_builder = role == defs.device_roles.builder
    if not is_builder then
        if use_all_enable[role] then
            ftable.add { type = "label", caption = { np("accepted_layout") } }

            local flow1 = ftable.add { type = "flow" }
            local flow2 = flow1.add { type = "flow", direction = "vertical", name = "layouts" }
            gui.update_patterns(flow2, device)

            local bedit = flow1.add { type = "sprite-button", sprite = commons.prefix .. "_arrow", name = np("edit_layout") }
            bedit.style.size = 24
        end
    else
        ftable.add { type = "label", caption = { np("train_layout") } }
        local line = ftable.add { type = "flow", name = "builder_layout" }

        local elements = trainconf.split_pattern(dconfig.builder_pattern)
        layout_editor.add_line(line, elements, true, false, false)
    end

    add_item_field("builder_fuel_item", is_builder, { { filter = "fuel" } }, "item", "nuclear-fuel")
end

---@param layouts LuaGuiElement
---@param device Device
function gui.update_patterns(layouts, device)
    layouts.clear()

    local patterns = device.dconfig.patterns or device.scanned_patterns
    if not patterns then
        return
    end
    for pattern in pairs(patterns) do
        local display = yutils.create_layout_strings(pattern)
        layouts.add { type = "label", caption = display }
    end
end

---@param player LuaPlayer
---@param device Device
function gui.update_patterns_in_frame(player, device)
    local frame = get_frame(player)
    if not frame then return end

    local layouts = tools.get_child(frame, "layouts")
    if not layouts then return end

    gui.update_patterns(layouts, device)
end

tools.on_gui_click(np("edit_layout"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local device = tools.get_vars(player).edited_device --[[@as Device]]
        if not device or not device.entity.valid then return end
        local dconfig = device.dconfig
        layout_editor.create_frame(player, dconfig.patterns or device.scanned_patterns)
    end)

local unit_x1 = "x1"
local unit_xstack = "xstack"
local unit_xwagon = "xwagon"
local unit_xtrain = "xtrain"


---@class UnitType
---@field name string
---@field sprite string
---@field tooltip LocalisedString
---@field cargo_coef integer
---@field is_stack boolean
---@field fluid_coef integer

---@param include_cargo boolean?
---@param include_fluid boolean?
---@return UnitType[]
local function get_units(include_cargo, include_fluid)
    local units_cache = {}

    ---@param name string
    ---@param cargo_coef integer
    ---@param is_stack boolean
    ---@param fluid_coef integer
    ---@param tooltip LocalisedString?
    local function insert_base(name, cargo_coef, is_stack, fluid_coef, tooltip)
        if not tooltip then
            tooltip = { np("unit-" .. name) }
        end
        table.insert(units_cache, {
            name = name,
            sprite = prefix .. "_" .. name,
            tooltip = tooltip,
            cargo_coef = cargo_coef,
            is_stack = is_stack,
            fluid_coef = fluid_coef
        })
    end
    insert_base(unit_x1, 1, false, 1)
    insert_base(unit_xstack, 1, true, 1)
    insert_base(unit_xwagon, config.ui_wagon_slots, true, config.ui_fluid_wagon_capacity,
        { np("unit-xwagon"),
            config.ui_wagon_slots,
            tools.comma_value(tostring(config.ui_fluid_wagon_capacity)) })
    insert_base(unit_xtrain,
        config.ui_wagon_slots * config.ui_train_wagon_count, true,
        config.ui_train_wagon_count * config.ui_fluid_wagon_capacity,
        { np("unit-xtrain"),
            config.ui_wagon_slots * config.ui_train_wagon_count,
            tools.comma_value(tostring(config.ui_train_wagon_count * config.ui_fluid_wagon_capacity)) })

    if include_cargo then
        local wagons = game.get_filtered_entity_prototypes { { filter = "type", type = "cargo-wagon" } }
        for _, wagon in pairs(wagons) do
            table.insert(units_cache, {
                name = wagon.name,
                sprite = "item/" .. wagon.items_to_place_this[1].name,
                tooltip = { np("unit-cargo-tooltip"), wagon.localised_name, wagon.get_inventory_size(defines.inventory.cargo_wagon) },
                cargo_coef = wagon.get_inventory_size(defines.inventory.cargo_wagon),
                is_stack = true,
                fluid_coef = 0
            })
        end
    end

    if include_fluid then
        local wagons = game.get_filtered_entity_prototypes { { filter = "type", type = "fluid-wagon" } }
        for _, wagon in pairs(wagons) do
            table.insert(units_cache, {
                name = wagon.name,
                sprite = "item/" .. wagon.items_to_place_this[1].name,
                tooltip = { np("unit-fluid-tooltip"), wagon.localised_name, tools.comma_value(tostring(wagon.fluid_capacity)) },
                cargo_coef = 1,
                is_stack = false,
                fluid_coef = wagon.fluid_capacity
            })
        end
    end

    return units_cache
end

---@param name string
---@return UnitType
local function get_unit(name)
    local units_cache_map = global.units_cache_map
    if not units_cache_map then
        local units_cache = get_units(true, true)
        global.units_cache_map = tools.table_map(units_cache, function(i, unit) return unit.name, unit end)
    end
    units_cache_map = global.units_cache_map

    local unit = units_cache_map[name]
    if unit then return unit end

    unit = units_cache_map[unit_xwagon]
    return unit
end

---@param name string
---@param include_cargo boolean?
---@param include_fluid boolean?
---@return integer
---@return UnitType[]
local function get_unit_index(name, include_cargo, include_fluid)
    local found = 1
    local units = get_units(include_cargo, include_fluid)
    for index, u in pairs(units) do
        if u.name == name then
            found = index
            return found, units
        end
    end
    return 1, units
end

---@param item string
---@param count integer
---@param unit_name string
---@param type string
local function get_real_count(item, count, unit_name, type)
    if not count then return 0 end

    local unit = get_unit(unit_name)
    if type == "item" then
        if unit.is_stack then
            local stack_size = tools.get_item_stack_size(item)
            return math.floor(count * unit.cargo_coef * stack_size + 0.5)
        else
            return math.floor(count * unit.cargo_coef + 0.5)
        end
    else
        return math.floor(count * unit.fluid_coef + 0.5)
    end
end

local qte_field_with = 70

---@param request RequestConfig?
---@return LocalisedString
local function get_request_tooltip(request)
    if not (request and request.name and request.amount and request.amount_unit) then
        return { np("request-item.tooltip") }
    end
    local signal = tools.sprite_to_signal(request.name)
    if not signal or (signal.type ~= "item" and signal.type ~= "fluid") then
        return { np("request-item.tooltip") }
    end

    ---@cast signal -nil
    local count = get_real_count(request.name, request.amount, request.amount_unit, signal.type)
    return { np("request-item-qty.tooltip"), tools.comma_value(count), "[" .. signal.type .. "=" .. signal.name .. "]" }
end

---@param flow LuaGuiElement
---@return RequestConfig?
local function get_request(flow)
    local fsignal = flow.signal
    local signal = fsignal.elem_value --[[as SignalID]]
    if signal and (signal.type == "item" or signal.type == "fluid") then
        local famount = flow.amount
        local amount = tonumber(famount.text)
        if amount and amount > 0 then
            local fthreshold = flow.threshold
            local threshold = tonumber(fthreshold.text)
            if not threshold or threshold > 0 then
                local famount_unit = flow[np("amount_unit")]
                local fthreshold_unit = flow[np("threshold_unit")]

                ---@type RequestConfig
                local request = {
                    name = signal.type .. "/" .. signal.name,
                    amount = amount,
                    threshold = threshold,
                    amount_unit = famount_unit and
                        famount_unit.tags.value,
                    threshold_unit = fthreshold_unit and
                        fthreshold_unit.tags.value
                }
                return request
            end
        end
    end
    return nil
end

---@param flow LuaGuiElement
local function update_request_tooltip(flow)
    local request = get_request(flow)
    local tooltip = get_request_tooltip(request)
    flow.signal.tooltip = tooltip
end

---@param request_table LuaGuiElement
---@param request RequestConfig?
---@return LuaGuiElement
---@return LuaGuiElement
---@return LuaGuiElement
local function create_request_field(request_table, request)
    ---@param flow LuaGuiElement
    ---@param name string
    ---@param value string?
    ---@return LuaGuiElement
    local function create_unit_field(flow, name, value, tooltip)
        if not value then value = unit_x1 end
        local unit = get_unit(value)
        local unit_field = flow.add {
            type = "sprite-button",
            sprite = unit.sprite,
            name = np(name),
            tooltip = unit.tooltip
        }
        unit_field.tags = { value = value }
        return unit_field
    end

    local flow = request_table.add { type = "flow", direction = "horizontal" }
    local signal_field = flow.add {
        type = "choose-elem-button",
        elem_type = "signal",
        name = "signal",
        tooltip = get_request_tooltip(request)
    }
    tools.set_name_handler(signal_field, np("request_signal"))

    local amount_field = flow.add {
        type = "textfield",
        name = "amount",
        numeric = true,
        allow_decimal = true,
        text = "",
        clear_and_focus_on_right_click = true,
        tooltip = { np("request-qty.tooltip") }
    }
    tools.set_name_handler(amount_field, np("amount"))
    amount_field.style.width = qte_field_with
    amount_field.style.top_margin = 5
    create_unit_field(flow, "amount_unit", request and request.amount_unit, np("request-qty-unit.tooltip"))

    amount_field.style.width = qte_field_with
    local threshold_field = flow.add {
        type = "textfield",
        name = "threshold",
        numeric = true,
        allow_decimal = true,
        text = "",
        clear_and_focus_on_right_click = true,
        tooltip = { np("request-threshold.tooltip") }
    }
    threshold_field.style.width = qte_field_with
    threshold_field.style.top_margin = 5
    tools.set_name_handler(threshold_field, np("threshold"))

    create_unit_field(flow, "threshold_unit", request and request.threshold_unit, np("request-threshold-unit.tooltip"))
    flow.style.right_margin = 16
    flow.style.left_margin = 16

    if request then
        local signal = tools.sprite_to_signal(request.name) --[[@as SignalID]]
        signal_field.elem_value = signal

        amount_field.text = request.amount and tostring(request.amount) or ""
        threshold_field.text = request.threshold and tostring(request.threshold) or ""
    end

    return signal_field, amount_field, threshold_field
end

---@param request_flow LuaGuiElement
---@param dconfig DeviceConfig
local function create_request_table(request_flow, dconfig)
    request_flow.clear()
    if not use_requester[dconfig.role] then return end

    create_line(request_flow)
    request_flow.add { type = "label", caption = { np("requests.title") } }

    local request_table = request_flow.add {
        type = "table",
        column_count = 2,
        name = "request_table"
    }

    local index = 1
    local requests = dconfig.requests or {}
    for i = 1, #requests + 1 do
        local request
        if index <= #requests then
            request = requests[index]
        end

        create_request_field(request_table, request)
        index = index + 1
    end
end

tools.on_named_event(np("request_signal"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed,
    function(e)
        local element = e.element
        if not (element and element.valid) then return end
        local item = element.elem_value
        local flow = element.parent
        local request_table = flow.parent
        local index = tools.index_of(request_table.children, flow)
        if index == #request_table.children then
            if item then
                create_request_field(request_table, nil)
            end
        else
            if not item then
                flow.destroy()
                return
            end
        end
        update_request_tooltip(flow)
    end)

tools.on_named_event(np("amount"), defines.events.on_gui_text_changed,
    ---@param e EventData.on_gui_text_changed,
    function(e)
        local flow = e.element.parent
        update_request_tooltip(flow)
    end)

---@param element LuaGuiElement
---@param unit UnitType
local function set_element_unit(element, unit)
    local name = unit.name
    element.sprite = unit.sprite
    local tags = element.tags
    tags.value = name
    element.tags = tags
    element.tooltip = unit.tooltip
end

---@param element LuaGuiElement
---@return boolean?
---@return boolean?
local function get_unit_selection(element)
    local flow = element.parent
    local signal = flow["signal"]
    local elem_value = signal.elem_value
    local include_cargo, include_fluid
    if elem_value and elem_value.type == "fluid" then
        include_fluid = true
    elseif elem_value and elem_value.type == "item" then
        include_cargo = true
    else
        include_fluid = true
        include_cargo = true
    end
    return include_cargo, include_fluid
end

---@param element LuaGuiElement
local function next_unit(element)
    local name = element.tags.value
    ---@cast name string

    if not name then name = unit_x1 end

    local include_cargo, include_fluid = get_unit_selection(element)
    local found, units = get_unit_index(name, include_cargo, include_fluid)
    found = found + 1
    if found > #units then found = 1 end
    local unit = units[found]
    set_element_unit(element, unit)
end

---@param element LuaGuiElement
local function prev_unit(element)
    local name = element.tags.value
    ---@cast name string

    if not name then name = unit_x1 end

    local include_cargo, include_fluid = get_unit_selection(element)
    local found, units = get_unit_index(name, include_cargo, include_fluid)
    found = found - 1
    if found <= 0 then found = #units end
    local unit = units[found]
    set_element_unit(element, unit)
end

---@param e EventData.on_gui_click
local function unit_handler(e)
    if e.button == defines.mouse_button_type.left then
        next_unit(e.element)
    else
        prev_unit(e.element)
    end
    update_request_tooltip(e.element.parent)
end

tools.on_gui_click(np("amount_unit"), unit_handler)
tools.on_gui_click(np("threshold_unit"), unit_handler)

---@param e EventData.on_gui_opened
local function on_gui_opened(e)
    local player = game.get_player(e.player_index) --[[@as LuaPlayer]]
    if not (e.entity and e.entity.name == commons.device_name) then
        close_ui(player)
        return
    end

    close_ui(player)

    player.opened = nil
    local device_entity = e.entity

    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = frame_name
    }

    local titleflow = frame.add { type = "flow" }
    local title_label = titleflow.add {
        type = "label",
        caption = { np("title") },
        style = "frame_title",
        ignored_by_interaction = true
    }

    local drag = titleflow.add {
        type = "empty-widget",
        style = "flib_titlebar_drag_handle"
    }

    drag.drag_target = frame
    titleflow.drag_target = frame
    titleflow.add {
        type = "sprite-button",
        name = np("close"),
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = "utility/close_white",
        hovered_sprite = "utility/close_black"
    }

    local inner_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    local device = devices[device_entity.unit_number]
    local selected_index = device.dconfig.role + 1

    local items = {
        { np("mode_disabled") },
        { np("mode_depot") },
        { np("mode_provider") },
        { np("mode_requester") },
        { np("mode_provider_and_requester") },
        { np("mode_buffer") },
        { np("mode_refueler") },
        { np("mode_builder") },
        { np("mode_feeder") },
        { np("mode_teleporter") }
    }
    local flow = inner_frame.add { type = "flow", direction = "horizontal" }
    flow.add { type = "label", caption = { np("mode") } }
    flow.add {
        type = "drop-down",
        items = items,
        name = np("mode"),
        selected_index = selected_index
    }
    local finactive = flow.add {
        type = "checkbox",
        caption = { np("inactive") },
        name = np("inactive"),
        state = device.dconfig.inactive == true
    }
    finactive.style.left_margin = 10

    create_line(inner_frame)

    local top_table = inner_frame.add {
        type = "table",
        column_count = 2
    }

    local ftable = top_table.add {
        type = "table",
        column_count = 2,
        name = "field_table",
    }

    create_fields(ftable, device)

    local scroll_request_table = inner_frame.add {
        type = "scroll-pane",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto"
    }
    scroll_request_table.style.maximal_height = 400

    local request_flow = scroll_request_table.add {
        type = "flow",
        direction = "vertical",
        name = "request_flow"
    }
    create_request_table(request_flow, device.dconfig)

    local button_frame = frame.add {
        type = "frame",
        direction = "horizontal",
        style = "flib_shallow_frame_in_shallow_frame"
    }

    button_frame.add {
        type = "button",
        caption = { np("save") },
        name = np("save")
    }
    button_frame.add {
        type = "button",
        caption = { np("read_signals") },
        name = np("read_signals")
    }
    button_frame.add {
        type = "button",
        caption = { np("importfa") },
        tooltip = { np("importfa-tooltip") },
        name = np("importfa")
    }

    tools.get_vars(player).edited_device = device
    frame.force_auto_center()
end

tools.on_gui_click(np("importfa"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if not remote.interfaces["factory_analyzer"] then
            player.print { np("factory-analyzer-not-found") }
            return
        end

        ---@type {[string]:number}
        local ingredients = remote.call("factory_analyzer", "get_ingredients", e.player_index)
        if not ingredients then
            player.print { np("no-selection-in-factory-analyzer") }
            return
        end

        local frame = get_frame(player)
        if not frame then return end

        local duration = settings.get_player_settings(player)["yaltn-fa_train_delay"].value --[[@as integer]]

        local request_table = tools.get_child(frame, "request_table")
        if not request_table then
            return
        end

        local existing_map = {}
        local index = 1
        while true do
            local rflow = request_table.children[index]
            if not rflow then break end

            local request = get_request(rflow)
            if request then
                existing_map[request.name] = request
            end
            index = index + 1
        end

        local use_stack = settings.get_player_settings(player)["yaltn-fa_use_stack"].value --[[@as  boolean]]
        local threshold_percent = settings.get_player_settings(player)["yaltn-fa_threshold_percent"].value --[[@as integer]]

        request_table.children[#request_table.children].destroy()
        for name, amount in pairs(ingredients) do
            if not existing_map[name] then
                local qty = amount * duration
                ---@type RequestConfig
                local request

                if use_stack then
                    local signal = tools.sprite_to_signal(name)
                    ---@cast signal -nil
                    if signal.type == "item" then
                        local proto = game.item_prototypes[signal.name]
                        request = {
                            name = name,
                            amount = math.ceil(qty / proto.stack_size),
                            amount_unit = unit_xstack,
                            threshold = math.ceil(qty * threshold_percent / proto.stack_size / 100),
                            threshold_unit = unit_xstack
                        }
                    end
                end

                if not request then
                    request = {
                        name = name,
                        amount = math.ceil(qty),
                        amount_unit = unit_x1,
                        threshold = math.ceil(qty * threshold_percent / 100),
                        threshold_unit = unit_x1
                    }
                end
                create_request_field(request_table, request)
            end
        end
        create_request_field(request_table)
    end)

---@param device Device
---@param player LuaPlayer?
local function update_runtime_config(device, player)
    device_manager.delete_red_input(device)
    device_manager.delete_green_input(device)

    local dconfig = device.dconfig
    device.patterns = dconfig.patterns or device.scanned_patterns
    device.has_specific_pattern = dconfig.has_specific_pattern
    device.inactive = dconfig.inactive and 1 or nil
    device.image_index = nil

    device.conf_change = true
    if not device.dconfig.requests then
        device.internal_requests = nil
        device.internal_threshold = nil
        return
    end

    device.internal_requests = nil
    device.internal_threshold = {}

    local red_signals = {}
    local index1 = 1

    for _, request in pairs(device.dconfig.requests) do
        local signal = tools.sprite_to_signal(request.name) --[[@as SignalID]]
        local request_count = get_real_count(request.name, request.amount, request.amount_unit, signal.type)

        if config.use_combinator_for_request then
            if request_count > 0 then
                table.insert(red_signals, { signal = signal, count = -request_count, index = index1 })
                index1 = index1 + 1
            end
        else
            if request_count > 0 then
                if not device.internal_requests then
                    device.internal_requests = {}
                end
                device.internal_requests[request.name] = request_count
            end
        end

        if request.threshold then
            local threshold_count = get_real_count(request.name, request.threshold, request.threshold_unit, signal.type)
            if threshold_count > 0 then
                device.internal_threshold[request.name] = threshold_count
            end

            if request_count and threshold_count and request_count <
                threshold_count then
                if player then
                    player.print({ "yaltn-messages.threshold_over_request" },
                        { 1, 0, 0 })
                end
            end
        end
    end

    if not next(device.internal_threshold) then
        device.internal_threshold = nil
    end

    if next(red_signals) then
        local red_input = device_manager.get_red_input(device)
        local cb = red_input.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
        cb.parameters = red_signals
    end
end

---@param player LuaPlayer
local function save_values(player)
    local device = tools.get_vars(player).edited_device --[[@as Device]]
    if not device or not device.entity.valid then return end
    local dconfig = device.dconfig

    local frame = get_frame(player)
    if not frame then return end

    local field_mode = tools.get_child(frame, np("mode")) --[[@as LuaGuiElement]]
    dconfig.role = field_mode.selected_index - 1

    local field_inactive = tools.get_child(frame, np("inactive")) --[[@as LuaGuiElement]]
    dconfig.inactive = field_inactive.state and true or nil

    local field_table = tools.get_child(frame, "field_table")
    ---@cast field_table -nil

    ---@param name string
    ---@param min integer?
    ---@param max integer?
    local function save_number(name, min, max)
        local field = field_table[name]
        if not field then
            dconfig[name] = nil
            return
        end

        local value = field.text
        if not value or value == '' then
            value = nil
        else
            value = tonumber(value)
            if min and value < min then value = min end
            if max and value > max then value = max end
        end
        dconfig[name] = value
    end

    ---@param name string
    local function save_boolean(name)
        local field = field_table[name]
        if not field then
            dconfig[name] = nil
            return
        end

        local value = field.state
        dconfig[name] = value and true or nil
    end


    ---@param name string
    ---@param values table<string, any>
    local function save_mask(name, values)
        local toggle_flow = field_table[name]
        if not toggle_flow then
            values[name] = nil
            return
        end

        local index = 1
        local mask  = 1
        local value = 0
        while true do
            local toggle = toggle_flow.children[index]
            if not toggle then break end
            if toggle.state then value = value + mask end

            index = index + 1
            mask = 2 * mask
        end
        if value == 0 then
            values[name] = nil
        else
            values[name] = value
        end
    end

    ---@param name string
    local function save_item(name)
        ---@type LuaGuiElement
        local field = field_table[name]
        if not field then
            dconfig[name] = nil
            return
        end

        local value = field.elem_value --[[@as string?]]
        if not value or value == '' then
            value = nil
        elseif field.elem_type == "entity" then
            value = game.entity_prototypes[value].items_to_place_this[1].name
        end
        dconfig[name] = value
    end

    save_number("priority")
    save_number("rpriority")
    save_number("max_delivery", 0, 100)
    save_number("delivery_timeout", 1, nil)
    save_number("threshold", 1, nil)
    save_number("locked_slots", 0, nil)
    save_number("inactivity_delay", 1, nil)
    save_number("max_load_time", 1, nil)
    save_number("delivery_penalty", 1, nil)
    save_number("teleport_range", 60, nil)
    save_number("parking_penalty", nil, nil)

    save_boolean("station_locked")
    save_boolean("combined")
    save_boolean("no_remove_constraint")
    save_boolean("green_wire_as_priority")
    

    save_mask("network_mask", dconfig)
    save_item("builder_fuel_item")

    if dconfig.role == defs.device_roles.builder then
        local line = tools.get_child(frame, "builder_layout")
        ---@cast line -nil
        local elements = layout_editor.read_cells(line)
        elements = trainconf.purify(elements)
        dconfig.builder_pattern = trainconf.create_pattern(elements)
        dconfig.builder_gpattern = trainconf.create_generic(dconfig.builder_pattern) or ""
        dconfig.patterns = { [dconfig.builder_gpattern] = true }
    end

    local request_table = tools.get_child(frame, "request_table")
    if not request_table then
        dconfig.requests = nil
    else
        ---@cast field_table -nil

        dconfig.requests = nil
        local index = 1
        while true do
            local rflow = request_table.children[index]
            if not rflow then break end

            local request = get_request(rflow)
            if request then
                if not dconfig.requests then
                    dconfig.requests = {}
                end
                table.insert(dconfig.requests, request)
            end

            index = index + 1
        end
    end

    yutils.update_runtime_config(device, player)
end


tools.on_event(defines.events.on_gui_opened, on_gui_opened)
tools.on_event(defines.events.on_gui_closed, on_gui_closed)

tools.on_gui_click(np("close"), ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        close_ui(player)
    end)

tools.on_gui_click(np("save"), ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        save_values(player)
        close_ui(player)
    end)

tools.on_gui_click(np("read_signals"), ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local device = tools.get_vars(player).edited_device --[[@as  Device]]

        if not (device.entity and device.entity.valid) then return end

        local green_circuit = device.entity.get_circuit_network(defines.wire_type.green,
            defines.circuit_connector_id.combinator_input)
        local red_circuit = device.entity.get_circuit_network(defines.wire_type.red,
            defines.circuit_connector_id.combinator_input)
        if not red_circuit then return end

        local signals = red_circuit.signals
        if not signals then return end

        local frame = get_frame(player)
        local request_table = tools.get_child(frame, "request_table")
        if not request_table then return end

        local index = 1
        local threshold = red_circuit.get_signal({
            type = "virtual",
            name = prefix .. "-threshold"
        })
        if not threshold or threshold == 0 then threshold = 1000 end

        for _, signal in pairs(signals) do
            if signal.signal.type ~= "virtual" then
                local rflow = request_table.children[index]
                local fsignal = rflow.signal
                fsignal.elem_value = signal.signal
                local famount = rflow.amount
                famount.text = tostring(math.abs(signal.count))

                local fthreshold = rflow.threshold
                fthreshold.text = tostring(threshold)
                if green_circuit then
                    local gvalue = green_circuit.get_signal(signal.signal)
                    if gvalue and gvalue > 0 then
                        fthreshold.text = tostring(math.abs(gvalue))
                    end
                end
                index = index + 1
                if index >= 12 then break end
            end
        end
    end)

tools.on_named_event(np("mode"), defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        local player = game.players[e.player_index]
        local device = tools.get_vars(player).edited_device --[[@as  Device]]
        if device and device.entity.valid then
            local role = e.element.selected_index - 1
            device.dconfig.role = role

            local frame = get_frame(player)
            local ftable = tools.get_child(frame, "field_table")
            ---@cast ftable -nil
            create_fields(ftable, device)

            local request_flow = tools.get_child(frame, "request_flow")
            ---@cast request_flow -nil
            create_request_table(request_flow, device.dconfig)
        end
    end)

tools.on_event(defines.events.on_gui_closed,
    ---@param e EventData.on_gui_closed
    function(e)
        local player = game.players[e.player_index]
        close_ui(player)
        if e.entity and e.entity.valid and e.entity.type == "cargo-wagon" then
            local ttrain = e.entity.train
            local context = yutils.get_context()
            local train = context.trains[ttrain.id]
            if not train then return end
            if train.depot and train.depot.role == defs.device_roles.buffer then
                yutils.update_production_from_content(train.depot, train)
            end
        end
    end)

tools.on_event(defines.events.on_gui_confirmed,
    ---@param e EventData.on_gui_confirmed
    function(e)
        local player = game.players[e.player_index]
        local frame = get_frame(player)

        if not frame then return end
        if not frame.visible then return end

        save_values(player)
        close_ui(player)
    end)

---@param e EventData.on_entity_settings_pasted
local function on_entity_settings_pasted(e)
    local src = e.source
    local dst = e.destination
    local player = game.players[e.player_index]

    if not dst or not dst.valid or not src or not src.valid then return end

    if src.name == commons.device_name and dst.name == commons.device_name then
        local device1 = devices[src.unit_number]
        local device2 = devices[dst.unit_number]

        local copy = game.json_to_table(game.table_to_json(device1.dconfig)) --[[@as DeviceConfig]]
        device2.dconfig = copy
        yutils.update_runtime_config(device2)
    end
end

tools.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)
yutils.update_runtime_config = update_runtime_config

layout_editor.update_patterns_in_frame = gui.update_patterns_in_frame

return gui
