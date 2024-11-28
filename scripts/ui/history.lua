local flib_format = require("__flib__/format")
local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uihistory = {}

local prefix = commons.prefix
local uihistory_prefix = prefix .. "-uihistory."

local slot_internal_color = uiutils.slot_internal_color
local slot_provided_color = uiutils.slot_provided_color
local slot_requested_color = uiutils.slot_requested_color
local slot_transit_color = uiutils.slot_transit_color
local slot_signal_color = uiutils.slot_signal_color

---@param name string
---@return string
local function np(name) return uihistory_prefix .. name end

---@type HeaderDef[]
local header_defs = {

    { name = "id",           width = 50 }, { name = "start", width = 80 },
    { name = "trainid",      width = 60 },
    { name = "routing",      width = 300,        nosort = true },
    { name = "shipment",     width = 6 * 40 + 8, nosort = true },
    { name = "duration",     width = 100 }
}

---@param tabbed_pane LuaGuiElement
function uihistory.create(tabbed_pane)
    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add { type = "tab", caption = { np("history") } }

    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    local header = frame.add { type = "table", column_count = #header_defs }
    header.style = "yatm_default_table"
    header.draw_vertical_lines = true

    uiutils.create_header(frame, header_defs, uihistory_prefix)

    local scroll = frame.add {
        type = "scroll-pane",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto-and-reserve-space",
        name = np("scroll")
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.vertically_stretchable = true

    local content = scroll.add {
        type = "table",
        column_count = #header_defs + 1,
        name = np("content")
    }
    content.style = "yatm_default_table"
    content.draw_vertical_lines = true
    content.style.horizontally_stretchable = true

    ---------------------------------------

    local player = game.players[tabbed_pane.player_index]
    uihistory.update(player)
end

local sort_methods = {

    id = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2) return d1.id < d2.id end,

    ["-id"] = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2) return d2.id < d1.id end,

    start = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2) return d2.start_tick < d1.start_tick end,

    ["-start"] = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2) return d1.start_tick < d2.start_tick end,

    trainid = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2) return d1.train.id < d2.train.id end,

    ["-trainid"] = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2) return d2.train.id < d1.train.id end,

    duration = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2)
            return (d1.end_tick and (d1.end_tick - d1.start_tick) or -1) <
                (d2.end_tick and (d2.end_tick - d2.start_tick) or -1)
        end,

    ["-duration"] = --
    ---@param d1 Delivery
    ---@param d2 Delivery
    ---@return boolean
        function(d1, d2)
            local d1, d2 = d2, d1
            return (d1.end_tick and (d1.end_tick - d1.start_tick) or -1) <
                (d2.end_tick and (d2.end_tick - d2.start_tick) or -1)
        end
}

---@param player LuaPlayer
function uihistory.update(player)
    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))

    content.clear()

    local context = yutils.get_context()

    local filter = uiutils.build_delivery_filter(player)

    ---@type Delivery[]
    local deliveries = {}
    for _, event in pairs(context.event_log) do
        if event.type == commons.event_delivery_create and
            filter(event.delivery) then
            table.insert(deliveries, event.delivery)
        end
    end

    local uiconfig = uiutils.get_uiconfig(player)
    if uiconfig.history_sort then
        local sorter = sort_methods[uiconfig.history_sort]
        if sorter then table.sort(deliveries, sorter) end
    else
        table.sort(deliveries, function(d1, d2) return d1.id < d2.id end)
    end

    local tick = game.tick
    for i = 1, #deliveries do
        local delivery = deliveries[1 + #deliveries - i]

        local row = content
        local field_index = 1

        uiutils.create_textfield(row, tostring(delivery.id),
            header_defs[field_index].width)
        field_index = field_index + 1

        uiutils.create_textfield(row, flib_format.time(tick - delivery.start_tick), header_defs[field_index].width)
        field_index = field_index + 1

        local trainfield = uiutils.create_textfield(row, tostring(delivery.train.id), header_defs[field_index].width)
        trainfield.style = "yatm_clickable_semibold_label"
        trainfield.style.width = header_defs[field_index].width
        trainfield.style.horizontal_align = "center"
        tools.set_name_handler(trainfield, uiutils.np("train"), { id = delivery.train.id })
        field_index = field_index + 1

        uiutils.create_delivery_routing_horizontal(row, delivery, header_defs[field_index].width)
        field_index = field_index + 1

        local _, content_table = uiutils.create_product_table(row, np("shipment"), 6, 1)
        local sorted_products
        if not delivery.combined_delivery then
            sorted_products = uiutils.sort_products(delivery.content)
        else
            local all_contents = {}
            local current = delivery
            while current do
                for name, amount in pairs(current.content) do
                    all_contents[name] = (all_contents[name] or 0) + amount
                end
                current = current.combined_delivery
            end
            sorted_products = uiutils.sort_products(all_contents)
        end
        uiutils.display_products(content_table, sorted_products, slot_transit_color, np("tooltip-transit-item"))
        field_index = field_index + 1

        local ftime = uiutils.create_textfield(row,
            (delivery.start_tick and delivery.end_tick and flib_format.time(delivery.end_tick - delivery.start_tick)) or "*",
            header_defs[field_index].width)
        ftime.raise_hover_events = true
        tools.set_name_handler(ftime, np("time"), { id = delivery.id })
        field_index = field_index + 1

        local ew = row.add { type = "empty-widget" }
        ew.style.horizontally_stretchable = true
    end
end

tools.on_gui_click(np("id"), ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.element.player_index]
        local context = yutils.get_context()
        local id = e.element.tags.id
        local train = context.trains[id]
        if train and train.train.valid then
            player.zoom_to_world(train.front_stock.position, 0.5, train.front_stock)
        end
    end)

tools.on_named_event(np("sort"), defines.events.on_gui_checked_state_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local sort_name = e.element.tags.sort --[[@as string]]
        local player = game.players[e.player_index]
        local uiconfig = uiutils.get_uiconfig(player)
        if e.element.state then
            uiconfig.history_sort = sort_name
        else
            uiconfig.history_sort = "-" .. sort_name
        end
        uiutils.update(player)
    end)

tools.on_named_event(np("time"), defines.events.on_gui_hover, --
    ---@param e EventData.on_gui_hover
    function(e)
        local id = e.element.tags.id

        local context = yutils.get_context()
        for _, event in pairs(context.event_log) do
            if event.type == commons.event_delivery_create and event.delivery and
                event.delivery.id == id then
                local delivery = event.delivery
                ---@cast delivery -nil

                if delivery.end_tick then
                    local gametick = game.tick
                    local start_tick = delivery.start_tick or gametick
                    local end_tick = delivery.end_tick or gametick
                    local start_load_tick = delivery.start_load_tick or start_tick
                    local end_load_tick = delivery.end_load_tick or start_load_tick
                    local start_unload_tick = delivery.start_unload_tick or end_load_tick
                    e.element.tooltip = {
                        np("tooltip-time"), flib_format.time(end_tick - start_tick),
                        flib_format.time(start_load_tick - start_tick),
                        flib_format.time(end_load_tick - start_load_tick),
                        flib_format.time(start_unload_tick - end_load_tick),
                        flib_format.time(end_tick - start_unload_tick)
                    }
                end
                return
            end
        end
    end)

return uihistory
