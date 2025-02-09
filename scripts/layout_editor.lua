local tools = require("scripts.tools")
local commons = require("scripts.commons")
local yutils = require("scripts.yutils")
local trainconf = require("scripts.trainconf")

local prefix = commons.prefix .. "-layout."

---@param name string
---@return string
local function np(name) return prefix .. name end

local frame_name = np("frame")

local layout_editor = {}

local wfield = 32
local wqty = 40

---@param line LuaGuiElement
---@param with_back boolean?
---@param count integer?
---@param type string?
---@param is_back boolean?
---@param generic boolean
local function add_cell(line, with_back, count, type, is_back, generic)
    local cell = line.add { type = "flow", direction = "horizontal" }
    if line.tags.same_width then
        cell.style.width = 140
    end
    local fstock
    local show_sens
    if generic then
        local sprite = trainconf.get_sprite(type)
        fstock = cell.add { type = "sprite-button", name = "gstock", sprite = sprite, tooltip = { np("stock-tooltip") } }
        tools.set_name_handler(fstock, np("gstock"))
    else
        local filter = { { filter = "type", type = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" } } }
        fstock = cell.add {
            type = "choose-elem-button",
            name = "rstock",
            elem_type = "entity",
            elem_filters = filter,
            entity = type
        }
        tools.set_name_handler(fstock, np("rstock"))
        show_sens = type and prototypes.entity[type].type == "locomotive"
    end

    fstock.style.left_margin = 20
    fstock.style.size = wfield
    cell.add { type = "label", caption = "x" }

    local fqty = cell.add { type = "textfield", name = "qty", numeric = true, text = count and tostring(count) or "" }
    fqty.style.width = wqty
    fqty.style.top_margin = 3

    if not count then
        fqty.enabled = false
    end

    if not generic then
        local fsens = cell.add {
            type = "sprite-button",
            name = "sens",
            sprite = is_back and commons.revert_sprite or commons.direct_sprite,
            tooltip = { np("sens-tooltip") }
        }
        fsens.style.size = wfield
        tools.set_name_handler(fsens, np("sens"))
        if not show_sens then
            fsens.visible = false
        end
    end
end

---@param line LuaGuiElement
---@param elements TrainConfElement[]
---@param with_back boolean?
---@param generic boolean
---@param same_width boolean
function layout_editor.add_line(line, elements, with_back, generic, same_width)
    line.tags = { generic = generic, same_width = same_width }
    line.clear()

    for _, element in pairs(elements) do
        add_cell(line, with_back, element.count, element.type, element.is_back, generic)
    end
    add_cell(line, with_back, nil, nil, false, generic)
end

local stock_options = {
    { type = "*", sprite = commons.locomotive_sprite },
    { type = "c", sprite = commons.cargo_wagon_sprite },
    { type = "f", sprite = commons.fluid_wagon_sprite },
}

---@param e EventData.on_gui_click
local function on_gstock_click(e)
    if e.button == 2 then
        if not (e.control) then
            local sprite = e.element.sprite
            local found
            for i = 1, #stock_options do
                local s = stock_options[i]
                if s.sprite == sprite then
                    found = i
                    break
                end
            end
            if not found then
                found = 1
            else
                found = found + 1
                if found > #stock_options then
                    found = 1
                end
            end
            e.element.sprite = stock_options[found].sprite
            local cell = e.element.parent
            ---@cast cell -nil
            cell.qty.enabled = true
            local line = cell.parent
            ---@cast line -nil
            local index = tools.index_of(line.children, cell)
            if #line.children == index then
                add_cell(line, false, nil, nil, nil, true)
            end
        end
    elseif e.button == 4 then
        local cell = e.element.parent
        ---@cast cell -nil
        local line = cell.parent
        ---@cast line -nil
        local index = tools.index_of(line.children, cell)
        if #line.children ~= index then
            cell.destroy()
        else
            e.element.sprite = nil
            cell.qty.text = "1"
        end
    end
end

tools.on_named_event(np("gstock"), defines.events.on_gui_click, on_gstock_click)

---@param e EventData.on_gui_click
local function on_sens_click(e)
    if e.button == 2 then
        if not (e.control) then
            local element = e.element

            if element.sprite == commons.revert_sprite then
                element.sprite = commons.direct_sprite
            else
                element.sprite = commons.revert_sprite
            end
        end
    end
end
tools.on_named_event(np("sens"), defines.events.on_gui_click, on_sens_click)

---@param e EventData.on_gui_elem_changed
local function on_rstock_element_changed(e)
    local type = e.element.elem_value
    local cell = e.element.parent
    ---@cast cell -nil
    local line = cell.parent
    ---@cast line -nil
    if type then
        cell.qty.enabled = true
        cell.qty.focus()
        local index = tools.index_of(line.children, cell)
        if #line.children == index then
            add_cell(line, false, nil, nil, false, false)
        end
    else
        local index = tools.index_of(line.children, cell)
        if #line.children ~= index then
            cell.destroy()
        else
            e.element.elem_value = nil
            cell.qty.text = "1"
        end
    end
    if cell.valid then
        local type        = e.element.elem_value
        cell.sens.visible = type and prototypes.entity[type].type == "locomotive"
    end
end
tools.on_named_event(np("rstock"), defines.events.on_gui_elem_changed, on_rstock_element_changed)

---@param layout_list LuaGuiElement
---@param pattern string?
---@param is_generic boolean?
local function add_layout_line(layout_list, pattern, is_generic)
    local layout_line = layout_list.add { type = "flow" }
    local delete = layout_line.add {
        type = "sprite-button",
        sprite = commons.prefix .. "-delete",
        tooltip = { np("delete-layout") },
        name = "delete"
    }
    delete.style.size = wfield
    delete.style.right_margin = 10
    tools.set_name_handler(delete, np("delete_layout"))

    local line = layout_line.add { type = "flow", direction = "horizontal", name = "cells" }
    local elements = trainconf.split_pattern(pattern)

    if is_generic == nil then
        is_generic = trainconf.is_generic(elements)
    end

    if is_generic then
        layout_editor.add_line(line, elements, false, true, true)
    else
        layout_editor.add_line(line, elements, true, false, true)
    end
end

tools.on_named_event(np("delete_layout"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local line = e.element.parent
        if line then
            line.destroy()
        end
    end)

---@param container LuaGuiElement
---@param patterns {[string]:boolean}
function layout_editor.create(container, patterns)
    local list = container.add { type = "flow", direction = "vertical", name = "layout_list" }
    if patterns then
        for pattern in pairs(patterns) do
            add_layout_line(list, pattern)
        end
    end
    return list
end

---@param player LuaPlayer
---@param patterns {[string]:boolean}
function layout_editor.create_frame(player, patterns)
    local gui_frame = player.gui.screen[commons.gui_frame_name]
    gui_frame.visible = false

    local previous = player.gui.screen[frame_name]
    if previous then
        previous.destroy()
    end

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
        sprite = "utility/close",
        hovered_sprite = "utility/close_black"
    }

    local inner_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    inner_frame.style.minimal_width = 600
    inner_frame.style.minimal_height = 200


    local button_frame = frame.add {
        type = "frame",
        direction = "horizontal",
        style = "flib_shallow_frame_in_shallow_frame"
    }

    button_frame.add {
        type = "button",
        caption = { np("add_generic_layout") },
        name = np("add_generic_layout")
    }
    button_frame.add {
        type = "button",
        caption = { np("add_specific_layout") },
        name = np("add_specific_layout")
    }
    button_frame.add {
        type = "button",
        caption = { np("close") },
        name = np("close")
    }

    layout_editor.create(inner_frame, patterns)
    frame.force_auto_center()
end

---@param player LuaPlayer
local function close_ui(player)
    local gui_frame = player.gui.screen[commons.gui_frame_name]
    if gui_frame then
        gui_frame.visible = true
    end

    local frame = player.gui.screen[frame_name]
    if frame then
        frame.destroy()
    end
end

---@param cells LuaGuiElement
---@return TrainConfElement[]
function layout_editor.read_cells(cells)
    ---@type TrainConfElement[]
    local elements = {}
    for _, cell in pairs(cells.children) do
        local qty = cell.qty
        local gstock = cell.gstock
        local sens = cell.sens
        local type
        if gstock then
            local sprite
            sprite = gstock.sprite
            if not sprite then goto skip end
            for _, s in pairs(stock_options) do
                if s.sprite == sprite then
                    type = s.type
                    break
                end
            end
            if not type then goto skip end
        else
            local rstock = cell.rstock
            type = rstock.elem_value
            if not type then goto skip end
        end

        local count = tonumber(qty.text)
        local is_back = sens and sens.sprite == commons.revert_sprite or false
        if count and count > 0 then
            ---@type TrainConfElement
            local element = {
                type = type,
                count = count,
                is_back = is_back
            }
            table.insert(elements, element)
        end
        ::skip::
    end
    return elements
end

---@param player LuaPlayer
local function save_patterns(player)
    local frame = player.gui.screen[frame_name]
    local layout_list = tools.get_child(frame, "layout_list")
    if not layout_list then
        return
    end

    local patterns = {}
    local has_specific_pattern
    for _, layout_line in pairs(layout_list.children) do
        local elements = layout_editor.read_cells(layout_line.cells)
        elements = trainconf.purify(elements)
        if not trainconf.is_generic(elements) then
            has_specific_pattern = true
        end
        local pattern = trainconf.create_pattern(elements)
        patterns[pattern] = true
    end

    local device = tools.get_vars(player).edited_device --[[@as Device]]
    if not device or not device.entity.valid then return end
    local dconfig = device.dconfig
    dconfig.has_specific_pattern = nil

    if not next(patterns) then
        dconfig.patterns = nil
    else
        dconfig.patterns = patterns
        dconfig.has_specific_pattern = has_specific_pattern
    end
    yutils.load_pattern_cache()
    layout_editor.update_patterns_in_frame(player, device)
end

tools.on_gui_click(np("close"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]

        save_patterns(player)
        close_ui(player)
    end)

tools.on_gui_click(np("add_generic_layout"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[frame_name]

        local layout_list = tools.get_child(frame, "layout_list")
        if layout_list then
            add_layout_line(layout_list, "*=1 c=1")
        end
    end)

tools.on_gui_click(np("add_specific_layout"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[frame_name]

        local layout_list = tools.get_child(frame, "layout_list")
        if layout_list then
            add_layout_line(layout_list, "", false)
        end
    end)

---@param player LuaPlayer
---@param device Device
function layout_editor.update_patterns_in_frame(player, device)
end

return layout_editor
