local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")

local uiutils = require("scripts.ui.utils")

local uistock = {}

local prefix = commons.prefix
local uistock_prefix = prefix .. "-uistock."
---@param name string
---@return string
local function np(name) return uistock_prefix .. name end

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime


local slot_internal_color = uiutils.slot_internal_color 
local slot_provided_color = uiutils.slot_provided_color 
local slot_requested_color= uiutils.slot_requested_color 
local slot_transit_color = uiutils.slot_transit_color 
local slot_signal_color = uiutils.slot_signal_color


---@param tabbed_pane LuaGuiElement
function uistock.create(tabbed_pane)

    local tab = tabbed_pane.add {
        type = "tab",
        caption = {np("stock")}
    }
    local content = tabbed_pane.add {
        type = "table",
        column_count = 4,
        name = np("content")
    }
    content.vertical_centering = false
    tabbed_pane.add_tab(tab, content)

    content.style.minimal_width = settings.get_player_settings(tabbed_pane.player_index)["yaltn-ui_width"].value --[[@as integer]]
    content.style.minimal_height = settings.get_player_settings(tabbed_pane.player_index)["yaltn-ui_height"].value --[[@as integer]]

    local bkg_style = "deep_frame_in_shallow_frame"

    ---------------------------------------

    local function create_product_tab(name, cols)

        local frame = content.add {
            type = "frame",
            direction = "vertical",
            style = bkg_style
        }
        frame.style.padding = 5

        frame.add {type = "label", caption = {np(name)}}

        local scroll = frame.add {
            type = "scroll-pane",
            horizontal_scroll_policy = "never",
            vertical_scroll_policy = "dont-show-but-allow-scrolling"
        }

        local content = scroll.add {
            type = "table",
            column_count = cols,
            name = np(name .. "_table"),
            style = "slot_table"
        }

        frame.style.vertical_align = "top"
        content.style.minimal_width = cols * 40 + 2
        content.style.minimal_height = config.uistock_lines * 42
        scroll.style.maximal_height = (config.uistock_lines + 3) * 42
    end

    create_product_tab("provided", config.uistock_produced_cols)
    create_product_tab("requested", config.uistock_requested_cols)
    create_product_tab("transit", config.uistock_transit_cols)
    create_product_tab("internals", config.uistock_internals_cols)

    local player = game.players[tabbed_pane.player_index]
    uistock.update(player)
end

function uistock.update(player)

    local provided_table = uiutils.get_child(player, np("provided_table"))
    local requested_table = uiutils.get_child(player,np("requested_table"))
    local transit_table = uiutils.get_child(player, np("transit_table"))
    local internals_table = uiutils.get_child(player, np("internals_table"))

    local uiconfig = uiutils.get_uiconfig(player)
    local signal_filter = uiconfig.signal_filter

    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local provided = {}
    local requested = {}
    local transit = {}
    local deliveries = {}
    local internals = {}
    if signal_filter then
        local name = signal_filter
        for _, device in pairs(devices) do
            if device.dconfig and not device.inactive and filter(device) then
                local r = device.produced_items[name]
                if r then
                    local count = r.provided - r.requested
                    if count > 0 then
                        provided[name] = (provided[name] or 0) + count
                    end
                end
                r = device.requested_items[name]
                if r then
                    local count = r.requested - r.provided
                    if count >= r.threshold then
                        requested[name] = (requested[name] or 0) + count
                    end
                end
                for _, d in pairs(device.deliveries) do
                    if not deliveries[d.id] then
                        deliveries[d.id] = true
                        local count = d.content[name]
                        if count and count > 0 then
                            transit[name] = (transit[name] or 0) + count
                        end
                    end
                end
                if device.internal_requests then
                    local count = device.internal_requests[name]
                    if count then
                        internals[name] = (internals[name] or 0) + count
                    end
                end
            end
        end

    else
        for _, device in pairs(devices) do
            if device.dconfig and not device.inactive and filter(device) then
                for name, r in pairs(device.produced_items) do
                    local count = r.provided - r.requested
                    if count > 0 then
                        provided[name] = (provided[name] or 0) + count
                    end
                end
                for name, r in pairs(device.requested_items) do
                    local count = r.requested - r.provided
                    if count >= r.threshold then
                        requested[name] = (requested[name] or 0) + count
                    end
                end
                for _, d in pairs(device.deliveries) do
                    if not deliveries[d.id] then
                        deliveries[d.id] = true
                        for item, count in pairs(d.content) do
                            if count > 0 then
                                transit[item] = (transit[item] or 0) + count
                            end
                        end
                    end
                end
                if device.internal_requests then
                    for name, count in pairs(device.internal_requests) do
                        internals[name] = (internals[name] or 0) + count
                    end
                end
            end
        end
    end

    provided_table.clear()
    requested_table.clear()
    transit_table.clear()
    internals_table.clear()

    uistock.display_products(provided, provided_table, slot_provided_color)
    uistock.display_products(requested, requested_table, slot_requested_color, uiutils.np("product_button_requested"))
    uistock.display_products(transit, transit_table, slot_transit_color)
    uistock.display_products(internals, internals_table, slot_internal_color)
end

local sort_products = uiutils.sort_products

---@param products table<string, integer>
---@param container LuaGuiElement
---@param style string
---@param handler_name string?
function uistock.display_products(products, container, style, handler_name)

    local sorted_products = sort_products(products)
    uiutils.display_products(container, sorted_products, style, np("tooltip-item"), handler_name)
end

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end

tools.on_load(on_load)

return uistock
