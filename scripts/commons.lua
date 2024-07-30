local tools = require("scripts.tools")

local prefix = "yaltn"
local modpath = "__yet_another_train_manager__"
local device_name = prefix .. "-device"

local commons = {

    debug_version = 4,
    prefix = prefix,
    modpath = modpath,
    device_name = device_name,
    graphic_path = modpath .. '/graphics/%s.png',
    cc_name = device_name .. "-cc",
    context_version = 1,
    teleport_electric_buffer_name = prefix .. "-teleport-electric-buffer",

    event_cancel_delivery = 1,
    event_producer_not_found = 2,
    event_train_not_found = 3,
    event_depot_not_found = 4,
    event_train_not_empty = 5,
    event_train_stuck  = 6,
    event_delivery_create  = 7,
    event_delivery_complete  = 8,
    event_teleportation = 9,
    event_teleport_failure = 10,
    event_manual = 11,

    teleport_electric_buffer_size = 1000*1000*1000,

    se_elevator_name = "se-space-elevator",
    se_elevator_trainstop_name = "se-space-elevator-train-stop",

    colors = {
        black = 1,
        yellow = 2,
        green = 3,
        blue = 4,
        red = 5,
        cyan = 6,
        orange = 7,
        grey = 8,
        light_grey = 9,
        pink = 10,
        -- purple = 11
    },

    color_names = { },

    color_def = {
        { 0,0,0 },
        { 255,216, 0},
        { 0,255,0 },
        { 0, 0, 255 },
        { 255, 0, 0 },
        { 0, 255, 255},
        { 255, 106, 9},
        { 64, 64, 64 },
        { 160,160, 160 },
        { 255, 0, 220},
        -- { 178, 0, 255}
    },

    locomotive_sprite = prefix .. "_locomotive",
    cargo_wagon_sprite = prefix .. "_cargo-wagon",
    fluid_wagon_sprite = prefix .. "_fluid-wagon",
    any_stock_sprite = prefix .. "_any_stock",
    revert_sprite = prefix .. "_revert",
    direct_sprite = prefix .. "_direct",
    layout_font = prefix .. "_layout",

    gui_frame_name = prefix .. "-frame",
    modal_mask_name = prefix .. "-modal_mask"

}

commons.generic_to_sprite = {
    ["l"] = commons.locomotive_sprite,
    ["f"] = commons.fluid_wagon_sprite,
    ["c"] = commons.cargo_wagon_sprite,
    ["*"] = commons.locomotive_sprite,
}

for name, index in pairs(commons.colors) do
    commons.color_names[index] = name
end

---@param name string
---@return string
function commons.png(name) return (commons.graphic_path):format(name) end

return commons

