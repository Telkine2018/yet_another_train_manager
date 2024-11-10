local flib_format = require("__flib__/format")
local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uidepots = {}

local prefix = commons.prefix
local uidepots_prefix = prefix .. "-uidepots."

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
local function np(name) return uidepots_prefix .. name end

---@type HeaderDef[]
local header_defs = {

    {name = "surface", width = 200}, 
    {name = "used", width = 100}, 
    {name = "free", width = 100}, {name="last_use_date", width=80}
}

---@param tabbed_pane LuaGuiElement
function uidepots.create(tabbed_pane)

    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add {type = "tab", caption = {np("depots")}}

    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    uiutils.create_header(frame, header_defs, uidepots_prefix, 3)

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
    uidepots.update(player)
end

---@class Statistic 
---@field surface string
---@field used_count integer
---@field free_count integer
---@field last_use_date integer?
---@field last_use_id integer?

---@type table<string, fun(t1:Train, t2:Train) : boolean>
local sort_methods = {

    surface = --
    ---@param a1 Assign
    ---@param a2 Assign
    function(a1, a2) return a1.surface < a2.surface end,

    ["-surface"] = --
    ---@param a1 Assign
    ---@param a2 Assign
    function(a1, a2) return a1.surface > a2.surface end,

    used = --
    ---@param a1 Assign
    ---@param a2 Assign
    function(a1, a2) return a1.used_count < a2.used_count end,

    ["-used"] = --
    ---@param a1 Assign
    ---@param a2 Assign
    function(a1, a2) return a2.used_count < a1.used_count end,

    free = --
    ---@param a1 Assign
    ---@param a2 Assign
    function(a1, a2) return a1.free_count < a2.free_count end,

    ["-free"] = --
    ---@param a1 Assign
    ---@param a2 Assign
    function(a1, a2) return a2.free_count < a1.free_count end

}

function uidepots.update(player)

    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))

    local context = yutils.get_context()

    ---@type table<string, Statistic>
    local depots_map = {}
    for _, device in pairs(devices) do
        if device.role == defs.device_roles.depot then
            local key = device.network.surface_name

            ---@type Statistic
            local stat = depots_map[key]
            if not stat then
                stat = {
                    surface = device.network.surface_name,
                    free_count = 0,
                    used_count = 0
                }
                depots_map[key] = stat
            end
            if device.train then
                stat.used_count = stat.used_count + 1
            else
                stat.free_count = stat.free_count + 1
            end
            if not stat.last_use_date or stat.last_use_date > (device.last_used_date or 0) then
                stat.last_use_date = device.last_used_date or 0
                stat.last_use_id = device.id or 0
            end
        end
    end

    ---@type Statistic[]
    local depots_list = tools.table_copy(depots_map)

    local uiconfig = uiutils.get_uiconfig(player)

    if uiconfig.depots_sort then
        local sort = sort_methods[uiconfig.depots_sort]
        if sort then table.sort(depots_list, sort) end
    end

    content.clear()

    local idx = 1
    for _, stat in pairs(depots_list) do

        local row = content
        local field_index = 1

        -------- Surface
        local fsurface = row.add {
            type = "label",
            caption = tostring(stat.surface)
        }
        fsurface.style.horizontal_align = "center"
        fsurface.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Used count
        local fused_count = row.add {
            type = "label",
            caption = tostring(stat.used_count)
        }
        fused_count.style.horizontal_align = "center"
        fused_count.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Free count
        local ffree_count = row.add {
            type = "label",
            caption = tostring(stat.free_count)
        }
        ffree_count.style.horizontal_align = "center"
        ffree_count.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Last use date
        local flast_use_date = row.add {
            type = "label",
            caption = stat.last_use_date and flib_format.time(game.tick - stat.last_use_date) or "",
            style = "yatm_clickable_semibold_label"
        }
        if stat.last_use_id then
            tools.set_name_handler(flast_use_date, uiutils.np("station"), {device = stat.last_use_id})
        end

        flast_use_date.style.horizontal_align = "center"
        flast_use_date.style.width = header_defs[field_index].width
        field_index = field_index + 1
       
        local ew = row.add {type = "empty-widget"}
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
        uiconfig.depots_sort = sort_name
    else
        uiconfig.depots_sort = "-" .. sort_name
    end
    uiutils.update(player)
end)

return uidepots
