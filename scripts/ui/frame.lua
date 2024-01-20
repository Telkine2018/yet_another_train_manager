local mod_gui = require("mod-gui")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local scheduler = require("scripts.scheduler")
local config = require("scripts.config")
local device_selection = require("scripts.device_selection")

local uiutils = require("scripts.ui.utils")
local uistock = require("scripts.ui.stock")
local uistations = require("scripts.ui.stations")
local uitrains = require("scripts.ui.trains")
local uihistory = require("scripts.ui.history")
local uiassign = require("scripts.ui.assign")
local uidepots = require("scripts.ui.depots")
local uievents = require("scripts.ui.events")
local uistats = require("scripts.ui.stats")

local tab_table = {
    uistock,
    uistations,
    uitrains,
    uihistory,
    uiassign,
    uidepots,
    uievents,
    uistats
}

local uiframe = {}

local prefix = commons.prefix
local uiframe_name = uiutils.uiframe_name
local uiframe_prefix = prefix .. "-uiframe."

---@param name string
---@return string
local function np(name) return uiframe_prefix .. name end

local refresh_rate_none = 1
local refresh_rate_2s = 2
local refresh_rate_5s = 3
local refresh_rate_10s = 4
local refresh_rate_30s = 5

local get_uiconfig = uiutils.get_uiconfig
local get_frame = uiutils.get_frame

local text_filter_name = np("text_filter")
local networkmask_name = np("network_mask")
local networkmask_field_name = np("network_field_mask")
local signal_filter_name = np("signal_filter")
local tab_name = np("tab")

local index_to_station_states = { 0, 1, 2, 3, 5, 7, 8, 10 }

local station_states_to_index = {}
for i1, i2 in pairs(index_to_station_states) do station_states_to_index[i2] = i1 end

---@param player LuaPlayer
local function close(player)
    local frame = get_frame(player)
    if frame then frame.destroy() end
end

---@param player LuaPlayer
function uiframe.hide(player)
    local frame = get_frame(player)
    if frame then frame.visible = false end
end

---@param player LuaPlayer
local function open(player)
    local frame = get_frame(player)
    if frame then
        frame.visible = not frame.visible
        if frame.visible then
            uiframe.set_station_state(player, 0)
        end
        return
    end

    close(player)

    local vars = tools.get_vars(player)
    if not vars.ui_refresh_rate then vars.ui_refresh_rate = refresh_rate_5s end

    local uiconfig = get_uiconfig(player)
    uiconfig.station_state = 0

    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = uiframe_name
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

    titleflow.add { type = "label", caption = { np("refresh_rate") } }
    local items = {
        { np("refresh_rate_none") }, { np("refresh_rate_2s") },
        { np("refresh_rate_5s") }, { np("refresh_rate_10s") },
        { np("refresh_rate_30s") }
    }
    titleflow.add {
        type = "drop-down",
        items = items,
        name = np("refresh_rate"),
        selected_index = vars.ui_refresh_rate
    }

    local progress = titleflow.add {
        type = "progressbar",
        value = 0,
        name = "progress",
        direction = "vertical"
    }
    progress.style.color = { 0, 1, 0, 1 }
    progress.style.font_color = { 0, 0, 0, 1 }
    progress.style.width = 50
    progress.style.bar_width = 21
    vars.ui_progress = progress

    titleflow.add {
        type = "sprite-button",
        name = np("refresh"),
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = prefix .. "_refresh_white",
        hovered_sprite = prefix .. "_refresh_black"
    }
    titleflow.add {
        type = "sprite-button",
        name = np("close"),
        tooltip = { np("close-tooltip") },
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = "utility/close_white",
        hovered_sprite = "utility/close_black"
    }

    local search_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    local label

    ---------------------------

    local search_panel1 = search_frame.add {
        type = "flow",
        direction = "horizontal"
    }
    search_panel1.style.vertical_align = "center"

    --------------- Text filter
    search_panel1.add { type = "label", caption = { np("text_filter") } }
    search_panel1.add {
        type = "textfield",
        name = text_filter_name,
        text = uiconfig.text_filter
    }

    --------------- Surface
    label = search_panel1.add { type = "label", caption = { np("surface") } }
    label.style.left_margin = 20
    local surface_names, selected_index = uiframe.get_surface_names(player)
    local surface_field = search_panel1.add {
        type = "drop-down",
        items = surface_names,
        selected_index = selected_index,
        name = np("surface")
    }

    --------------- Product
    label = search_panel1.add { type = "label", caption = { np("product") } }
    label.style.left_margin = 20
    local filter_signal = tools.sprite_to_signal(uiconfig.signal_filter)
    local signal_filter = search_panel1.add {
        type = "choose-elem-button",
        name = signal_filter_name,
        elem_type = "signal",
        signal = filter_signal,
        style = "yatm_small_slot_button_default"
    }

    --------------- Network
    label = search_panel1.add { type = "label", caption = { np("network_mask") } }
    label.style.left_margin = 20

    local network_mask_flow = search_panel1.add {
        type = "table",
        name = np("network_flow"),
        column_count = config.network_mask_size / 2
    }
    local network_mask = uiconfig.network_mask or 0
    local m = 1
    for i = 1, config.network_mask_size do
        local cb = network_mask_flow.add {
            type = "checkbox",
            tooltip = tostring(m),
            state = bit32.band(m, network_mask) ~= 0
        }
        tools.set_name_handler(cb, networkmask_name)
        m = m * 2
    end
    local network_mask_field = search_panel1.add {
        type = "textfield",
        name = networkmask_field_name,
        numeric = true,
        allow_negative = true,
        text = tostring(network_mask)
    }
    network_mask_field.style.width = 60

    --------------- Station state
    local station_state_flow = search_panel1.add {
        type = "flow",
        direction = "horizontal",
        name = np("station_state_flow")
    }
    label = station_state_flow.add { type = "label", caption = { np("state") } }
    label.style.left_margin = 20

    items = {}
    for i = 1, #index_to_station_states do
        local state = index_to_station_states[i]
        table.insert(items, { "",   i > 1 and ("[img=" .. prefix .. "_state_" .. state .. "] ") or "", { uiutils.np("state-" .. state) }
        })
    end
    station_state_flow.add {
        type = "drop-down",
        items = items,
        selected_index = station_states_to_index[uiconfig.station_state or 0],
        name = np("station_state")
    }
    station_state_flow.visible = false

    ------------------

    local tabbed_pane = frame.add { type = "tabbed-pane", name = tab_name }

    for _, tab in pairs(tab_table) do
        tab.create(tabbed_pane)
    end

    frame.style.minimal_width = settings.get_player_settings(player)["yaltn-ui_width"].value --[[@as integer]]
    frame.style.minimal_height = settings.get_player_settings(player)["yaltn-ui_height"].value --[[@as integer]]
    frame.force_auto_center()
end

tools.on_gui_click(np("close"), ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if e.control then
            close(player)
        else
            uiframe.hide(player)
        end
    end)

tools.on_named_event(text_filter_name, defines.events.on_gui_text_changed, ---@param e EventData.on_gui_text_changed
    function(e)
        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)
        uiconfig.text_filter = e.text
        uiframe.update(player)
    end)

tools.on_named_event(np("tab"), defines.events.on_gui_selected_tab_changed,
    ---@e EventData.on_gui_selected_tab_changed
    function(e) uiframe.update(game.players[e.player_index]) end)

tools.on_named_event(networkmask_name,
    defines.events.on_gui_checked_state_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)
        local mask = uiconfig.network_mask or 0
        if e.element.state then
            mask = bit32.bor(mask, bit32.lshift(1, e.element.get_index_in_parent() - 1))
        else
            mask = bit32.band(mask, bit32.bnot(bit32.lshift(1, e.element.get_index_in_parent() - 1)))
        end
        local networkmask_field = tools.get_child(get_frame(player),
            networkmask_field_name)

        if mask == 0 then
            uiconfig.network_mask = nil
            networkmask_field.text = ""
        else
            uiconfig.network_mask = mask
            networkmask_field.text = tostring(mask)
        end
        uiframe.update(player)
    end)

tools.on_named_event(networkmask_field_name, defines.events.on_gui_text_changed,
    ---@param e EventData.on_gui_text_changed
    function(e)
        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)
        ---@type number?
        local network_mask = 0
        if (e.text ~= '') then network_mask = tonumber(e.text) end

        uiconfig.network_mask = network_mask
        local flow = uiutils.get_child(player, np("network_flow"))
        ---@cast flow -nil
        local mask = 1
        for i = 1, #flow.children do
            local cb = flow.children[i]

            cb.state = bit32.band(network_mask, mask) ~= 0
            mask = mask * 2
        end
        uiframe.update(player)
    end)

tools.on_named_event(np("surface"),
    defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)
        uiconfig.surface_name = e.element.items[e.element.selected_index]
        if type(uiconfig.surface_name) ~= "string" then
            uiconfig.surface_name = nil
        end
        uiframe.update(player)
    end)

tools.on_named_event(signal_filter_name, defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
    function(e)
        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)
        local signalid = e.element.elem_value --[[@as SignalID]]
        local signal = tools.signal_to_sprite(signalid)
        if signal ~= nil and (signalid.type == "item" or signalid.type == "fluid") then
            uiconfig.signal_filter = signal
        else
            e.element.elem_value = nil
            uiconfig.signal_filter = nil
        end
        uiframe.update(player)
    end)

---@param player LuaPlayer
---@return string[]
---@return integer
function uiframe.get_surface_names(player)
    local context = yutils.get_context()
    local uiconfig = get_uiconfig(player)
    local items = {}
    local network_map = context.networks[player.force_index]
    if network_map then
        for _, network in pairs(network_map) do
            table.insert(items, game.surfaces[network.surface_index].name)
        end
    end
    table.sort(items)
    local index = 1
    for i = 1, #items do
        if items[i] == uiconfig.surface_name then
            index = i + 1
            break
        end
    end

    table.insert(items, 1, { np("all_surfaces") })
    return items, index
end

local function create_player_buttons()
    for _, player in pairs(game.players) do
        close(player)

        local button_flow = mod_gui.get_button_flow(player)
        local button_name = prefix .. ".openui"
        if button_flow[button_name] then
            button_flow[button_name].destroy()
        end

        if player.force.technologies[commons.device_name].researched then
            local button = button_flow.add {
                type = "sprite-button",
                name = button_name,
                sprite = prefix .. "_on_off",
                tooltip = { np("on_off_tooltip") },
                style = "tool_button"
            }
            button.style.width = 40
            button.style.height = 40
        end
    end
end

tools.on_gui_click(prefix .. ".openui", ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if not(e.shift or e.control or e.alt) then
            open(player)
        elseif e.control then
            device_selection.show_teleporters(player)
        end
    end)

tools.on_event(defines.events.on_research_finished,
    ---@param e EventData.on_research_finished
    function(e)
        if e.name == commons.device_name then create_player_buttons() end
    end)

function uiframe.init_ui(context)
    create_player_buttons()
end

yutils.init_ui = uiframe.init_ui

function uiframe.update(player)
    local frame = uiutils.get_frame(player)
    if not frame then return end
    if not frame.visible then return end

    local tab = frame[tab_name]
    local index = tab.selected_tab_index
    if not index then
        index = 1
    end
    local tab = tab_table[index]
    tab.update(player)
end

tools.on_named_event(np("refresh_rate"),
    defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        vars.ui_refresh_rate = e.element.selected_index
    end)

local refresh_delay = { 0, 2 * 60, 5 * 60, 10 * 60, 30 * 60 }

tools.on_nth_tick(60, function(e)
    if not config.ui_autoupdate then return end
    if not global.players then return end

    local tick = game.tick
    for player_index, vars in pairs(global.players) do
        local player = game.players[player_index]
        local vars = tools.get_vars(player)
        local refresh_rate = vars.ui_refresh_rate
        if not refresh_rate or refresh_rate == refresh_rate_none then
            goto skip
        end

        local refresh_tick = vars.ui_refresh_tick
        if not refresh_tick then
            refresh_tick = tick + refresh_delay[refresh_rate]
            vars.ui_refresh_tick = refresh_tick
        elseif tick >= refresh_tick then
            uiframe.update(player)
            refresh_tick = tick + refresh_delay[refresh_rate]
            vars.ui_refresh_tick = refresh_tick
            local progress = vars.ui_progress
            if progress.valid then progress.value = 1 end
        else
            local progress = vars.ui_progress
            if progress.valid then 
                progress.value = (refresh_delay[refresh_rate] - (refresh_tick - tick)) / refresh_delay[refresh_rate]
            end
        end
        ::skip::
    end
end)

tools.on_gui_click(np("refresh"), ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        uiframe.update(player)
    end)

tools.on_named_event(uiutils.np("product_button"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if not (e.element and e.element.valid) then return end

        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)

        if e.button == defines.mouse_button_type.left then
            local signal = e.element.sprite --[[@as string]]
            local signalid = tools.sprite_to_signal(signal) --[[@as SignalID]]
            if signal ~= nil and (signalid.type == "item" or signalid.type == "fluid") then
                uiconfig.signal_filter = signal
                local fsignal = uiutils.get_child(player, signal_filter_name)
                fsignal.elem_value = signalid
            end
        elseif e.button == defines.mouse_button_type.right then
            local fsignal = uiutils.get_child(player, signal_filter_name)
            fsignal.elem_value = nil
            uiconfig.signal_filter = nil
        end
        uiframe.update(player)
    end)


tools.on_named_event(uiutils.np("product_button_requested"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if not (e.element and e.element.valid) then return end

        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)

        if e.button == defines.mouse_button_type.left then
            local signal = e.element.sprite --[[@as string]]
            local signalid = tools.sprite_to_signal(signal) --[[@as SignalID]]
            if signal ~= nil and (signalid.type == "item" or signalid.type == "fluid") then
                uiconfig.signal_filter = signal
                local fsignal = uiutils.get_child(player, signal_filter_name)
                fsignal.elem_value = signalid
                uiframe.set_station_state(player, 0)
                uiutils.show_tab(player, uiutils.tab.stations)
                uiutils.update(player)
            end
        elseif e.button == defines.mouse_button_type.right then
            local fsignal = uiutils.get_child(player, signal_filter_name)
            fsignal.elem_value = nil
            uiconfig.signal_filter = nil
        end
        uiframe.update(player)
    end)

---@param player LuaPlayer
---@param tab_index integer
function uiframe.show_tab(player, tab_index)
    local tab              = uiutils.get_child(player, tab_name)
    tab.selected_tab_index = tab_index
    uiframe.update_filters(player, tab_index)
end

---@param player LuaPlayer
---@param name string
function uiframe.set_signal_filter(player, name)
    local signalid = tools.sprite_to_signal(name)
    local field = uiutils.get_child(player, signal_filter_name)
    field.elem_value = signalid --[[@as SignalID]]

    local uiconfig = get_uiconfig(player)
    uiconfig.signal_filter = name
end

tools.on_named_event(uiutils.np("surface"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if not (e.element and e.element.valid) then return end

        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)

        local surface = e.element.tags.surface

        local fsurface = uiutils.get_child(player, np("surface"))
        if e.button == defines.mouse_button_type.left then
            uiconfig.surface_name = surface
            for index, item in pairs(fsurface.items) do
                if item == surface then
                    fsurface.selected_index = index
                    break
                end
            end
            uiframe.update(player)
        elseif e.button == defines.mouse_button_type.right then
            uiconfig.surface_name = nil
            fsurface.selected_index = 1
            uiframe.update(player)
        end
    end)


---@param player any
---@param tab_index any
function uiframe.update_filters(player, tab_index)

    local station_state_flow = uiutils.get_child(player, np("station_state_flow"))
    local uiconfig = get_uiconfig(player)
    station_state_flow.visible = tab_index == 2
    if tab_index ~= 2 then
        uiconfig.station_state = nil
        local fstation_state = uiutils.get_child(player, np("station_state"))
        fstation_state.selected_index = 1
    end

end

tools.on_named_event(tab_name, defines.events.on_gui_selected_tab_changed,
    ---@param e EventData.on_gui_selected_tab_changed
    function(e)
        if not (e.element and e.element.valid) then return end

        local player = game.players[e.player_index]
        local tab_index = e.element.selected_tab_index
        uiframe.update_filters(player, tab_index)
        uiframe.update(player)
    end)

tools.on_named_event(np("station_state"),
    defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        local player = game.players[e.player_index]
        local uiconfig = get_uiconfig(player)

        local state = index_to_station_states[e.element.selected_index]
        if not state or state == 0 then
            uiconfig.station_state = nil
        else
            uiconfig.station_state = state
        end
        uiframe.update(player)
    end)

---@param player LuaPlayer
---@param station_state integer
function uiframe.set_station_state(player, station_state)
    local fstation_state = uiutils.get_child(player, np("station_state"))
    fstation_state.selected_index = station_states_to_index[station_state]
    local uiconfig = get_uiconfig(player)
    uiconfig.station_state = station_state
end

uiutils.hide = uiframe.hide
uiutils.update = uiframe.update
uiutils.show_tab = uiframe.show_tab
uiutils.set_signal_filter = uiframe.set_signal_filter

return uiframe
