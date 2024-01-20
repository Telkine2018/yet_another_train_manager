local flib_format = require("__flib__/format")
local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uievents = {}

local prefix = commons.prefix
local uievents_prefix = prefix .. "-uievents."

local event_table = {}
for n, value in pairs(commons) do
    if tools.starts_with(n, "event_") then event_table[value] = n end
end

---@param name string
---@return string
local function np(name) return uievents_prefix .. name end

---@type HeaderDef[]
local header_defs = {
    { name = "id",           width = 80 }, --
    { name = "time",         width = 80 }, --
    { name = "surface",      width = 120 }, --
    { name = "network_mask", width = 80 }, --
    { name = "type",         width = 140 }, --
    { name = "station",      width = 140 }, --
    { name = "train",        width = 100 }, { name = "info", width = 300 }
}

---@param tabbed_pane LuaGuiElement
function uievents.create(tabbed_pane)
    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add { type = "tab", caption = { np("events") } }

    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    uiutils.create_header(frame, header_defs, uievents_prefix, 3)

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
    uievents.update(player)
end

---@type table<string, fun(t1:Train, t2:Train) : boolean>
local sort_methods = {

    id = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.id < a2.id end,

    ["-id"] = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.id > a2.id end,

    time = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.time < a2.time end,

    ["-time"] = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.time > a2.time end,

    surface = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.surface < a2.surface end,

    ["-surface"] = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.surface > a2.surface end

}

function uievents.update(player)
    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))

    local context = yutils.get_context()

    ---@type table<string, LogEvent>
    local events_list = {}
    for id, event in pairs(context.event_log) do
        if event.type ~= commons.event_delivery_create and event.type ~=
            commons.event_delivery_complete then
            table.insert(events_list, event)
        end
    end

    local uiconfig = uiutils.get_uiconfig(player)

    local nosort = true
    if uiconfig.events_sort then
        local sort = sort_methods[uiconfig.events_sort]
        if sort then
            table.sort(events_list, sort)
            nosort = false
        end
    end
    if nosort then
        table.sort(events_list, function(e1, e2) return e2.id < e1.id end)
    end

    content.clear()

    local idx = 1
    for _, event in pairs(events_list) do
        local row = content
        local field_index = 1

        -------- Id
        local fid = row.add { type = "label", caption = tostring(event.id) }
        fid.style.horizontal_align = "center"
        fid.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Time
        local ftime = row.add {
            type = "label",
            caption = flib_format.time(GAMETICK - event.time)
        }
        ftime.style.horizontal_align = "center"
        ftime.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Surface
        local surface = event.surface or ""
        local fsurface = row.add { type = "label", caption = surface }
        fsurface.style.horizontal_align = "center"
        fsurface.style.width = header_defs[field_index].width
        field_index = field_index + 1

        ------- Network mask
        local network_mask =
            event.network_mask and tostring(event.network_mask) or ""
        local fnetwork = row.add { type = "label", caption = network_mask }
        fnetwork.style.horizontal_align = "center"
        fnetwork.style.width = header_defs[field_index].width
        field_index = field_index + 1

        ------- Label
        local ftype = row.add {
            type = "label",
            caption = { np(event_table[event.type]) }
        }
        ftype.style.horizontal_align = "center"
        ftype.style.width = header_defs[field_index].width
        field_index = field_index + 1

        ------- Station
        local fstation
        if (event.device and event.device.trainstop.valid) then
            fstation = uiutils.create_station_name(content, event.device,
                header_defs[field_index].width)
        else
            fstation = row.add { type = "empty-widget" }
        end
        fstation.style.width = header_defs[field_index].width
        field_index = field_index + 1

        ------- Train
        local ftrain
        local train = event.train
        if not train and event.delivery then
            train = event.delivery.train
        end
        if (train and train.train.valid) then
            ftrain = content.add {
                type = "label",
                caption = tostring(train.id),
                style = "yatm_clickable_semibold_label"
            }
            tools.set_name_handler(ftrain, uiutils.np("train"), { id = train.id })
        else
            ftrain = row.add { type = "empty-widget" }
        end
        ftrain.style.horizontal_align = "center"
        ftrain.style.width = header_defs[field_index].width
        field_index = field_index + 1

        ----- Info
        local finfo
        if event.delivery then
            local flow = content.add { type = "flow", direction = "vertical" }
            local combined_delivery = event.delivery
            while combined_delivery do
                local inner_table = uiutils.create_delivery_routing_horizontal(flow, event.delivery, header_defs[field_index].width)
                for name, amount in pairs(event.delivery.content) do
                    uiutils.create_product_button(inner_table, name, amount, uiutils.slot_transit_color)
                end
                combined_delivery = combined_delivery.combined_delivery
            end
            finfo = flow
        elseif event.request_name and event.request_amount then
            finfo = content.add { type = "flow", direction = "horizontal" }
            uiutils.create_product_button(finfo, event.request_name, event.request_amount, uiutils.slot_requested_color)
        elseif event.target_teleport then
            finfo = uiutils.create_station_name(content, event.target_teleport, header_defs[field_index].width)
        else
            finfo = row.add { type = "empty-widget" }
        end
        finfo.style.horizontal_align = "center"
        finfo.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- End
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
            uiconfig.events_sort = sort_name
        else
            uiconfig.events_sort = "-" .. sort_name
        end
        uiutils.update(player)
    end)

return uievents
