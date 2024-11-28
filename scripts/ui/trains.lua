local flib_format = require("__flib__/format")
local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uitrains = {}

local prefix = commons.prefix
local uitrains_prefix = prefix .. "-uitrains."

local slot_internal_color = uiutils.slot_internal_color
local slot_provided_color = uiutils.slot_provided_color
local slot_requested_color = uiutils.slot_requested_color
local slot_transit_color = uiutils.slot_transit_color
local slot_signal_color = uiutils.slot_signal_color

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

---@param name string
---@return string
local function np(name) return uitrains_prefix .. name end

---@type HeaderDef[]
local header_defs = {

    { name = "map",           width = 100,        nosort = true }, { name = "state", width = 100 },
    { name = "composition",   width = 200 },
    { name = "route",         width = 140,        nosort = true },
    { name = "shipment",      width = 8 * 42 + 2, nosort = true },
    { name = "last_use_date", width = 100 }
}

---@param tabbed_pane LuaGuiElement
function uitrains.create(tabbed_pane)
    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add { type = "tab", caption = { np("trains") } }

    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    uiutils.create_header(frame, header_defs, uitrains_prefix)

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
        name = np("content"),
        style = "yatm_default_table"
    }
    content.draw_vertical_lines = true
    content.style.horizontally_stretchable = true

    ---------------------------------------

    local player = game.players[tabbed_pane.player_index]
    uitrains.update(player)
end

---@type table<string, fun(t1:Train, t2:Train) : boolean>
local sort_methods = {

    state = --
    ---@param t1 Train
    ---@param t2 Train
        function(t1, t2) return t1.state < t2.state end,

    ["-state"] = --
    ---@param t1 Train
    ---@param t2 Train
        function(t1, t2) return t2.state < t1.state end,

    last_use_date = --
    ---@param t1 Train
    ---@param t2 Train
        function(t1, t2) return (t1.last_use_date or 0) < (t2.last_use_date or 0) end,

    ["-last_use_date"] = --
    ---@param t1 Train
    ---@param t2 Train
        function(t1, t2) return (t1.last_use_date or 0) > (t2.last_use_date or 0) end,

    composition = --
    ---@param t1 Train
    ---@param t2 Train
        function(t1, t2)
            return t1.gpattern < t2.gpattern or (t1.gpattern == t2.gpattern and (t1.rpattern < t2.rpattern))
        end,

    ["-composition"] = --
    ---@param t1 Train
    ---@param t2 Train
        function(t1, t2)
            t1, t2 = t2, t1
            return t1.gpattern < t2.gpattern or (t1.gpattern == t2.gpattern and (t1.rpattern < t2.rpattern))
        end
}

function uitrains.update(player)
    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))

    local context = yutils.get_context()

    ---@type Train[]
    local sorted_trains = {}
    local filter = uiutils.build_train_filter(player)
    for _, train in pairs(context.trains) do
        if train.train.valid and filter(train) then
            table.insert(sorted_trains, train)
        end
    end

    local uiconfig = uiutils.get_uiconfig(player)

    if uiconfig.train_sort then
        local sort = sort_methods[uiconfig.train_sort]
        if sort then table.sort(sorted_trains, sort) end
    end

    content.clear()

    local idx = 1
    for _, train in pairs(sorted_trains) do
        local row = content
        local field_index = 1

        local map = row.add { type = "minimap" }
        map.style.width = header_defs[field_index].width
        map.style.height = header_defs[field_index].width
        map.style.bottom_margin = 5
        map.style.top_margin = 5
        map.entity = train.front_stock
        map.zoom = 1
        local fid = map.add {
            type = "label",
            caption = tostring(train.id),
            style = "yatm_clickable_semibold_label",
            name = uiutils.np("train"),
            tags = { id = train.id }
        }
        fid.style.horizontal_align = "center"
        fid.style.width = header_defs[field_index].width

        local state_label = { np("state" .. train.state) }
        if not train.has_fuel then
            state_label = { "", state_label, { np("nofuel") } }
        end
        field_index = field_index + 1
        local fstate = row.add {
            type = "label",
            caption = state_label
        }
        fstate.style.horizontal_align = "center"
        fstate.style.width = header_defs[field_index].width
        field_index = field_index + 1

        local fcompo = uiutils.create_train_composition(row, train.rpattern)
        fcompo.style.width = header_defs[field_index].width
        fcompo.style.horizontal_align = "center"
        field_index = field_index + 1

        uiutils.create_delivery_routing(row, train.delivery, header_defs[field_index].width)
        field_index = field_index + 1

        local _, content_table = uiutils.create_product_table(row, np("shipment"), 8, 1)
        local products = {}
        local items = train.train.get_contents()
        for _, item in pairs(items) do
            local signalid = tools.signal_to_id(item --[[@as SignalFilter]])
            ---@cast signalid -nil
            products[signalid] = item.count
        end
        local fluids = train.train.get_fluid_contents()
        for name, count in pairs(fluids) do
            products["fluid/" .. name] = count
        end
        if next(products) then
            local sorted_products = uiutils.sort_products(products)
            uiutils.display_products(content_table, sorted_products, slot_transit_color, np("tooltip-transit-item"))
        end
        field_index = field_index + 1

        -- last used date
        local flast_use_date = row.add {
            type = "label",
            caption = flib_format.time(game.tick - (train.last_use_date or 0))
        }
        flast_use_date.style.horizontal_align = "center"
        flast_use_date.style.width = header_defs[field_index].width
        field_index = field_index + 1


        local ew = row.add { type = "empty-widget" }
        ew.style.horizontally_stretchable = true
    end
end

tools.on_named_event(np("sort"), defines.events.on_gui_checked_state_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local sort_name = e.element.tags.sort --[[@as string]]
        local player = game.players[e.player_index]
        local uiconfig = uiutils.get_uiconfig(player)
        if e.element.state then
            uiconfig.train_sort = sort_name
        else
            uiconfig.train_sort = "-" .. sort_name
        end
        uiutils.update(player)
    end)

return uitrains
