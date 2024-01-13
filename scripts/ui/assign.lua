local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uiassign = {}

local prefix = commons.prefix
local uiassign_prefix = prefix .. "-uiassign."

---@param name string
---@return string
local function np(name) return uiassign_prefix .. name end

---@type HeaderDef[]
local header_defs = {

    { name = "surface",      width = 100 },
    { name = "network_mask", width = 100 },
    { name = "composition",  width = 200 },
    { name = "used",         width = 100 },
    { name = "free",         width = 100 },
    { name = "buffer",       width = 100, nosort = true }
}

---@param tabbed_pane LuaGuiElement
function uiassign.create(tabbed_pane)
    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add { type = "tab", caption = { np("assign") } }

    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    uiutils.create_header(frame, header_defs, uiassign_prefix, 0)

    local scroll = frame.add {
        type = "scroll-pane",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto",
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
    uiassign.update(player)
end

---@class Assign : TrainComposition
---@field surface string
---@field network_mask integer
---@field used_count integer
---@field free_count integer
---@field buffer_count integer
---@field gpattern string
---@field rpattern string

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

    network_mask = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.network_mask < a2.network_mask end,

    ["-network_mask"] = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2) return a1.network_mask > a2.network_mask end,

    composition = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2)
            return a1.gpattern < a2.gpattern or (a1.gpattern == a2.gpattern and (a1.rpattern < a2.rpattern))
        end,

    ["-composition"] = --
    ---@param a1 Assign
    ---@param a2 Assign
        function(a1, a2)
            a1, a2 = a2, a1
            return a1.gpattern < a2.gpattern or (a1.gpattern == a2.gpattern and (a1.rpattern < a2.rpattern))
        end,

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

function uiassign.update(player)
    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))

    local context = yutils.get_context()

    ---@type Train[]
    local assign_list = {}
    local filter = uiutils.build_train_filter(player)
    for _, train in pairs(context.trains) do
        if train.train.valid and filter(train) then
            table.insert(assign_list, train)
        end
    end

    ---@type table<string, Assign>
    local assign_map = {}
    local train_states = defs.train_states
    for _, train in pairs(assign_list) do
        local key = train.front_stock.surface.name .. "$$" .. train.rpattern

        ---@type Assign
        local assign = assign_map[key]
        if not assign then
            assign = {
                surface = train.front_stock.surface.name,
                network_mask = train.network_mask,
                rpattern = train.rpattern,
                gpattern = train.gpattern,
                free_count = 0,
                used_count = 0,
                buffer_count = 0
            }
            assign_map[key] = assign
        end
        if train.state == train_states.at_depot or train.state ==
            train_states.to_depot then
            assign.free_count = assign.free_count + 1
        else
            if train.depot and train.depot.role == defs.device_roles.buffer then
                assign.buffer_count = assign.buffer_count + 1
            else
                assign.used_count = assign.used_count + 1
            end
        end
    end

    ---@type Assign[]
    local assign_list = tools.table_copy(assign_map)

    local uiconfig = uiutils.get_uiconfig(player)

    if uiconfig.assign_sort then
        local sort = sort_methods[uiconfig.assign_sort]
        if sort then table.sort(assign_list, sort) end
    end

    content.clear()

    local idx = 1
    for _, assign in pairs(assign_list) do
        local row = content
        local field_index = 1

        -------- Surface
        local fsurface = row.add {
            type = "label",
            caption = tostring(assign.surface)
        }
        fsurface.style.horizontal_align = "center"
        fsurface.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Network
        local fnetwork = row.add {
            type = "label",
            caption = tostring(assign.network_mask)
        }
        fnetwork.style.horizontal_align = "center"
        fnetwork.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Composition
        local ftrains = uiutils.create_train_composition(content, assign.rpattern)
        ftrains.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Used count
        local fused_count = row.add {
            type = "label",
            caption = tostring(assign.used_count)
        }
        fused_count.style.horizontal_align = "center"
        fused_count.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Free count
        local ffree_count = row.add {
            type = "label",
            caption = tostring(assign.free_count)
        }
        ffree_count.style.horizontal_align = "center"
        ffree_count.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Buffer count
        local fbuffer = row.add {
            type = "label",
            caption = tostring(assign.buffer_count)
        }
        fbuffer.style.horizontal_align = "center"
        fbuffer.style.width = header_defs[field_index].width
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
            uiconfig.assign_sort = sort_name
        else
            uiconfig.assign_sort = "-" .. sort_name
        end
        uiutils.update(player)
    end)

return uiassign
