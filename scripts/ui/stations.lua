local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uistations = {}

local prefix = commons.prefix
local uistations_prefix = prefix .. "-uistations."

local slot_internal_color = uiutils.slot_internal_color
local slot_provided_color = uiutils.slot_provided_color
local slot_requested_color = uiutils.slot_requested_color
local slot_transit_color = uiutils.slot_transit_color
local slot_signal_color = uiutils.slot_signal_color

---@param name string
---@return string
local function np(name) return uistations_prefix .. name end

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime
local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

---@type HeaderDef[]
local header_defs = {

    {name = "surface", width = 80}, {name = "name", width = 150},
    {name = "state", width = 60}, {name = "network_mask", width = 80},
    {name = "product", width = 6 * 40 + 8, nosort = true},
    {name = "controls", width = 6 * 40 + 8, nosort = true},
    {name = "trains", width = 200, nosort = true}
}

---@param tabbed_pane LuaGuiElement
function uistations.create(tabbed_pane)

    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add {type = "tab", caption = {np("stations")}}
    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    uiutils.create_header(frame, header_defs, uistations_prefix)

    local scroll = frame.add {
        type = "scroll-pane",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto-and-reserve-space",
        name = np("scroll")
    }
    scroll.style.vertically_stretchable = true
    scroll.style.horizontally_stretchable = true

    local content = scroll.add {
        type = "table",
        column_count = #header_defs,
        name = np("content"),
        style = "yatm_default_table"
    }
    content.draw_vertical_lines = true
    content.style.horizontally_stretchable = true

    ---------------------------------------

    local player = game.players[tabbed_pane.player_index]
    uistations.update(player)
end

local control_signal_defs = {}
local control_to_remove = {
    ["network_mask"] = true,
    ["loco_mask"] = true,
    ["cargo_mask"] = true,
    ["fluid_mask"] = true
}
for vsignal, property in pairs(defs.virtual_to_internals) do
    if not control_to_remove[property] then
        control_signal_defs[vsignal] = property
    end
end

---@type table<string, fun(d1:Device, d2:Device) : boolean>
local sort_methods = {

    state = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2) return d1.image_index < d2.image_index end,
    ["-state"] = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2) return d2.image_index < d1.image_index end,
    name = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2)
        return d1.trainstop.backer_name < d2.trainstop.backer_name
    end,
    ["-name"] = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2)
        return d2.trainstop.backer_name < d1.trainstop.backer_name
    end,
    surface = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2) return d1.network.surface_name < d2.network.surface_name end,
    ["-surface"] = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2) return d2.network.surface_name < d1.network.surface_name end,
    network_mask = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2) return d1.network_mask < d2.network_mask end,
    ["-network_mask"] = --
    ---@param d1 Device
    ---@param d2 Device
    function(d1, d2) return d2.network_mask < d1.network_mask end
}

function uistations.update(player)

    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))

    ---@type Device[]
    local sorted_devices = {}
    for _, device in pairs(devices) do

        if defs.provider_requester_buffer_feeder_roles[device.role] then
            if filter(device) and device.trainstop.valid then
                table.insert(sorted_devices, device)
            end
        end
    end

    local uiconfig = uiutils.get_uiconfig(player)
    if uiconfig.station_sort then
        local sort = sort_methods[uiconfig.station_sort]
        if sort then table.sort(sorted_devices, sort) end
    end

    content.clear()
    local selected = ""
    if content.tags then selected = content.tags.selected --[[@as string]] end
    for _, device in pairs(sorted_devices) do

        ------ surface
        local field_index = 1
        local surface_name = device.trainstop.surface.name
        local fsurface = content.add {
            type = "label",
            caption = surface_name,
            style = "yatm_clickable_semibold_label"
        }
        fsurface.style.width = header_defs[field_index].width
        tools.set_name_handler(fsurface, uiutils.np("surface"),
                               {surface = surface_name})
        field_index = field_index + 1

        -------- station name
        local fname = uiutils.create_station_name(content, device,
                                             header_defs[field_index].width)
        if device.id == selected then fname.style = "yatm_selected_label" end
        field_index = field_index + 1

        ------ station state
        local state = device.image_index
        local fstate = content.add {
            type = "sprite-button",
            sprite = (state > 0) and (commons.prefix .. "_state_" .. state) or
                nil,
            tooltip = {uiutils.np("state-" .. state)}
        }
        local w = header_defs[field_index].width
        local fw = 24
        fstate.style.width = fw
        fstate.style.height = fw
        local margin = (w - fw) / 2
        fstate.style.left_margin = margin
        fstate.style.right_margin = margin
        field_index = field_index + 1

        ------ network mask
        local fnetwork = content.add {
            type = "label",
            caption = tostring(device.network_mask),
            style = "yatm_clickable_semibold_label"
        }
        tools.set_name_handler(fnetwork, uiutils.np("network"),
                               {network = device.network_mask})
        fnetwork.style.width = header_defs[field_index].width
        fnetwork.style.horizontal_align = "center"
        field_index = field_index + 1

        ------- content
        local content_frame, content_table =
            uiutils.create_product_table(content, np("station_content"), 6, 1)
        content_frame.style.vertical_align = "top"

        if next(device.produced_items) then
            local products = {}
            for name, r in pairs(device.produced_items) do
                local count = r.provided - r.requested
                if count > 0 then
                    table.insert(products, {name = name, count = count})
                end
            end
            uiutils.display_products(content_table, products,
                                     slot_provided_color,
                                     np("tooltip-provided-item"))
        end

        if device.internal_requests then
            local internal_table = uiutils.sort_products(
                                       device.internal_requests)
            uiutils.display_products(content_table, internal_table,
                                     slot_internal_color,
                                     np("tooltip-internal-item"))
        end

        if next(device.requested_items) then
            local requests = {}
            for name, r in pairs(device.requested_items) do
                local count = r.requested - r.provided
                if count >= r.threshold then
                    table.insert(requests, {name = name, count = count})
                end
            end
            uiutils.display_products(content_table, requests,
                                     slot_requested_color,
                                     np("tooltip-requested-item"))
        end

        if next(device.deliveries) then
            local transit = {}
            for _, delivery in pairs(device.deliveries) do
                for name, count in pairs(delivery.content) do
                    transit[name] = count + (transit[name] or 0)
                end
            end
            local transit_table = uiutils.sort_products(transit)
            uiutils.display_products(content_table, transit_table,
                                     slot_transit_color,
                                     np("tooltip-transit-item"))
        end
        field_index = field_index + 1

        ------- Control signals
        local control_frame, control_table =
            uiutils.create_product_table(content, np("station_control"), 6, 1)
        control_table.style.vertical_align = "top"

        local control_signal_map = {}
        for control_signal, property in pairs(control_signal_defs) do
            local value = device[property]
            if type(value) == "number" then
                control_signal_map["virtual/" .. control_signal] = value
            end
        end
        if next(control_signal_map) then

            local control_signal_list =
                uiutils.sort_products(control_signal_map)
            uiutils.display_products(control_table, control_signal_list, 
                                     slot_signal_color,
                                     np("tooltip-control-item"),
                                     np("control_item"), {device = device.id})
        end
        field_index = field_index + 1

        --- Accepted trains
        local ftrains = uiutils.create_device_composition(content, device)
        ftrains.style.width = header_defs[field_index].width
        field_index = field_index + 1
    end
end

tools.on_named_event(np("sort"), defines.events.on_gui_checked_state_changed,
---@param e EventData.on_gui_checked_state_changed
                     function(e)
    local sort_name = e.element.tags.sort --[[@as string]]
    local player = game.players[e.player_index]
    local uiconfig = uiutils.get_uiconfig(player)
    if e.element.state then
        uiconfig.station_sort = sort_name
    else
        uiconfig.station_sort = "-" .. sort_name
    end
    uiutils.update(player)
end)

function uistations.select_station(player, stationid)

    local scrollpane = uiutils.get_child(player, np("scroll"))
    local content = scrollpane.children[1]
    local tags = content.tags
    tags.selected = nil
    content.tags = tags

    uiutils.show_tab(player, uiutils.tab.stations)
    uiutils.update(player)
    local index = 2

    local fields = content.children
    local content_count = #fields
    local field_per_line = #header_defs

    while index <= content_count do
        local child = fields[index]
        if child.tags.device == stationid then
            scrollpane.scroll_to_element(child, "top-third")
            child.style = "yatm_selected_label"
            local tags = content.tags
            tags.selected = stationid
            content.tags = tags
            return
        end
        index = index + field_per_line
    end
end

uiutils.select_station = uistations.select_station

return uistations
