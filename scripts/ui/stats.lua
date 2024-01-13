local flib_format = require("__flib__/format")
local luautil = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local uiutils = require("scripts.ui.utils")

local uistats = {}

local prefix = commons.prefix
local uistats_prefix = prefix .. "-uistats."

---@param name string
---@return string
local function np(name) return uistats_prefix .. name end

---@type HeaderDef[]
local header_defs = {

    {name = "name", width = 180},
    {name = "delivery_count", width = 120, nosort = true},
    {name = "item_count", width = 120, nosort = true},
    {name = "throughput", width = 100}, {name = "total", width = 100},
    {name = "to_provider", width = 100, nosort = true},
    {name = "loading", width = 100, nosort = true},
    {name = "to_requester", width = 100, nosort = true},
    {name = "unloading", width = 100, nosort = true}
}

---@param tabbed_pane LuaGuiElement
function uistats.create(tabbed_pane)

    local bkg_style = "deep_frame_in_shallow_frame"

    local tab = tabbed_pane.add {type = "tab", caption = {np("stats")}}

    local frame = tabbed_pane.add {
        type = "frame",
        direction = "vertical",
        style = bkg_style
    }
    frame.style.padding = 0
    tabbed_pane.add_tab(tab, frame)

    uiutils.create_header(frame, header_defs, uistats_prefix, 3)

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
    uistats.update(player)
end

---@class Statistic 
---@field name string
---@field delivery_count integer
---@field amount integer
---@field total integer
---@field to_provider integer
---@field loading integer
---@field to_requester integer
---@field unloading integer
---@field time_count integer

local get_product_order = uiutils.get_product_order

---@type table<string, fun(t1:Train, t2:Train) : boolean>
local sort_methods = {

    name = --
    ---@param a1 Statistic
    ---@param a2 Statistic
    function(a1, a2)
        return get_product_order(a1.name) < get_product_order(a2.name)
    end,

    ["-name"] = --
    ---@param a1 Statistic
    ---@param a2 Statistic
    function(a1, a2)
        return get_product_order(a1.name) > get_product_order(a2.name)
    end,

    throughput = --
    ---@param a1 Statistic
    ---@param a2 Statistic
    function(a1, a2) return a1.amount < a2.amount end,

    ["-throughput"] = --
    ---@param a1 Statistic
    ---@param a2 Statistic
    function(a1, a2) return a1.amount > a2.amount end,

    total = --
    ---@param a1 Statistic
    ---@param a2 Statistic
    function(a1, a2)
        return (a1.time_count and (a1.total / a1.time_count) or 0) <
                   (a2.time_count and (a2.total / a2.time_count) or 0)
    end,

    ["-total"] = --
    ---@param a1 Statistic
    ---@param a2 Statistic
    function(a1, a2)
        return (a1.time_count and (a1.total / a1.time_count) or 0) >
                   (a2.time_count and (a2.total / a2.time_count) or 0)
    end
}

local time = flib_format.time

function uistats.update(player)

    ---@type fun(d:Device):boolean
    local filter = uiutils.build_station_filter(player)

    local content = uiutils.get_child(player, np("content"))
    local context = yutils.get_context()

    ---@type table<string, Statistic>
    local stats_map = {}

    content.clear()

    local filter = uiutils.build_delivery_filter(player)
    for _, event in pairs(context.event_log) do
        if event.type == commons.event_delivery_create then
            ---@type Delivery
            local delivery = event.delivery

            if filter(delivery) then

                ---@cast delivery -nil
                for name, amount in pairs(delivery.content) do

                    local stat = stats_map[name]
                    if not stat then
                        stat = {
                            name = name,
                            delivery_count = 1,
                            amount = amount,
                            time_count = 0,
                            total = 0,
                            to_provider = 0,
                            loading = 0,
                            to_requester = 0,
                            unloading = 0
                        }
                        stats_map[name] = stat
                    else
                        stat.delivery_count = stat.delivery_count + 1
                        stat.amount = stat.amount + amount
                    end
                    if delivery.end_tick then
                        stat.time_count = stat.time_count + 1

                        local start_tick = delivery.start_tick
                        local start_load_tick =
                            delivery.start_load_tick or start_tick
                        local end_load_tick =
                            delivery.end_load_tick or start_tick
                        local end_tick = delivery.end_tick
                        local start_unload_tick =
                            delivery.start_unload_tick or end_tick
                        stat.total = stat.total + (end_tick - start_tick)
                        stat.to_provider = stat.to_provider +
                                               (start_load_tick - start_tick)
                        stat.loading = stat.loading +
                                           (end_load_tick - start_load_tick)
                        stat.to_requester = stat.to_requester +
                                                (start_unload_tick -
                                                    end_load_tick)
                        stat.unloading = stat.unloading +
                                             (end_tick - start_unload_tick)
                    end
                end
            end
        end
    end

    ---@type Statistic[]
    local stats_list = tools.table_copy(stats_map)
    local uiconfig = uiutils.get_uiconfig(player)
    if not uiconfig.stats_sort then uiconfig.stats_sort = "name" end
    local sorter = sort_methods[uiconfig.stats_sort]
    if sorter then table.sort(stats_list, sorter) end

    for _, stat in pairs(stats_list) do

        local row = content
        local field_index = 1
        local signalid = tools.sprite_to_signal(stat.name)

        local proto
        ---@cast signalid -nil

        local sprite_name = stat.name
        if signalid.type == "item" then
            proto = game.item_prototypes[signalid.name]
        elseif signalid.type == "fluid" then
            proto = game.fluid_prototypes[signalid.name]
        elseif signalid.type == "virtual" then
            proto = game.virtual_signal_prototypes[signalid.name]
            sprite_name = "virtual-signal/" .. signalid.name
        end

        -------- name
        local fname = row.add {
            type = "label",
            caption = {"", "[img=" .. sprite_name .. "] ", proto.localised_name}
        }
        fname.style = "yatm_clickable_semibold_label"
        fname.style.horizontal_align = "center"
        fname.style.width = header_defs[field_index].width
        fname.style.horizontal_align = "left"
        field_index = field_index + 1
        tools.set_name_handler(fname, uiutils.np("delivery_detail"),
                               {product = stat.name})

        -------- Delivery count
        local fdelivery_count = row.add {
            type = "label",
            caption = tostring(stat.delivery_count)
        }
        fdelivery_count.style.horizontal_align = "center"
        fdelivery_count.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Amount
        local famount = row.add {
            type = "label",
            caption = tostring(luautil.format_number(stat.amount, true))
        }
        famount.style.horizontal_align = "center"
        famount.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- Throughput
        local fthroughput = row.add {
            type = "label",
            caption = tostring(math.ceil(
                                   stat.amount / config.log_keeping_delay + 0.5))
        }
        fthroughput.style.horizontal_align = "center"
        fthroughput.style.width = header_defs[field_index].width
        field_index = field_index + 1

        if stat.time_count == 0 then stat.time_count = nil end

        -------- Total time
        local ftotal = row.add {
            type = "label",
            caption = stat.time_count and
                time(math.ceil(stat.total / stat.time_count)) or ""
        }
        ftotal.style.horizontal_align = "center"
        ftotal.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- To provider
        local fto_provider = row.add {
            type = "label",
            caption = stat.time_count and
                time(math.ceil(stat.to_provider / stat.time_count)) or ""
        }
        fto_provider.style.horizontal_align = "center"
        fto_provider.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- loading
        local floading = row.add {
            type = "label",
            caption = stat.time_count and
                time(math.ceil(stat.loading / stat.time_count)) or ""
        }
        floading.style.horizontal_align = "center"
        floading.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- to requester
        local fto_requester = row.add {
            type = "label",
            caption = stat.time_count and
                time(math.ceil(stat.to_requester / stat.time_count)) or ""
        }
        fto_requester.style.horizontal_align = "center"
        fto_requester.style.width = header_defs[field_index].width
        field_index = field_index + 1

        -------- unloading
        local funloading = row.add {
            type = "label",
            caption = stat.time_count and
                time(math.ceil(stat.unloading / stat.time_count)) or ""
        }
        funloading.style.horizontal_align = "center"
        funloading.style.width = header_defs[field_index].width
        field_index = field_index + 1

        ---- Filler
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
        uiconfig.stats_sort = sort_name
    else
        uiconfig.stats_sort = "-" .. sort_name
    end
    uiutils.update(player)
end)

return uistats
