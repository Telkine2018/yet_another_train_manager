local commons = require("scripts.commons")
local data_util = require("__flib__.data-util")

local default_font_color = {1, 1, 1}
local prefix = commons.prefix

local empty_checkmark = {
    filename = data_util.empty_image,
    priority = "very-low",
    width = 1,
    height = 1,
    frame_count = 1,
    scale = 8
}

local styles = data.raw["gui-style"].default

styles["yatm_count_label_bottom"] = {
    type = "label_style",
    parent = "count_label",
    height = 36,
    width = 36,
    vertical_align = "bottom",
    horizontal_align = "right",
    right_padding = 2
}
styles["yatm_count_label_top"] = {
    type = "label_style",
    parent = "yatm_count_label_bottom",
    vertical_align = "top"
}

styles["yatm_count_label_center"] = {
    type = "label_style",
    parent = "yatm_count_label_bottom",
    vertical_align = "center"
}

-- CHECKBOX STYLES
-- checked = ascending, unchecked = descending
styles.yatm_sort_checkbox = {
    type = "checkbox_style",
    font = "default-bold",
    -- font_color = bold_font_color,
    padding = 0,
    default_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-down-white.png",
        size = { 16, 16 },
        scale = 0.5
    },
    hovered_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-down-hover.png",
        size = { 16, 16 },
        scale = 0.5
    },
    clicked_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-down-white.png",
        size = { 16, 16 },
        scale = 0.5
    },
    disabled_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-down-white.png",
        size = { 16, 16 },
        scale = 0.5
    },
    selected_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-up-white.png",
        size = { 16, 16 },
        scale = 0.5
    },
    selected_hovered_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-up-hover.png",
        size = { 16, 16 },
        scale = 0.5
    },
    selected_clicked_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-up-white.png",
        size = { 16, 16 },
        scale = 0.5
    },
    selected_disabled_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-up-white.png",
        size = { 16, 16 },
        scale = 0.5
    },
    checkmark = empty_checkmark,
    disabled_checkmark = empty_checkmark,
    text_padding = 5
}

styles.yatm_header_label = {

    font = "default-bold",
    type = "label_style",
    text_padding = 5,
    padding = 0
}

-- selected is orange by default
styles.yatm__selected_sort_checkbox = {
    type = "checkbox_style",
    parent = "yatm_sort_checkbox",
    -- font_color = bold_font_color,
    default_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-down-active.png",
        size = { 16, 16 },
        scale = 0.5
    },
    selected_graphical_set = {
        filename = "__core__/graphics/arrows/table-header-sort-arrow-up-active.png",
        size = { 16, 16 },
        scale = 0.5
    }
}


styles.yatm_table_row_frame_light = {
    type = "frame_style",
    parent = "statistics_table_item_frame",
    top_padding = 0,
    bottom_padding = 0,
    left_padding = 0,
    right_padding = 0,
    minimal_height = 52,
    horizontal_flow_style = {
        type = "horizontal_flow_style",
        vertical_align = "center",
        horizontal_spacing = 5,
        horizontally_stretchable = "on"
    },
    graphical_set = { base = { center = { position = { 76, 8 }, size = { 1, 1 } } } }
}

styles.yatm_table_row_frame_dark = {
    type = "frame_style",
    parent = "yatm_table_row_frame_light",
    graphical_set = {}
}

local default_orange_color = {r = 0.98, g = 0.66, b = 0.22}


local hovered_label_color = {
    r = 0.5 * (1 + default_orange_color.r),
    g = 0.5 * (1 + default_orange_color.g),
    b = 0.5 * (1 + default_orange_color.b)
}

local selected_label_color = {

    r = 0, g = 1, b = 1
}


styles.yatm_clickable_semibold_label = {
    type = "label_style",
    parent = "yatm_semibold_label",
    hovered_font_color = hovered_label_color,
    disabled_font_color = hovered_label_color
}

styles.yatm_selected_label = {
    type = "label_style",
    parent = "yatm_clickable_semibold_label",
    font_color = selected_label_color
}

styles.yatm_default_table = {
    type = "table_style",
    odd_row_graphical_set = {
        filename = "__core__/graphics/gui.png",
        position = { 78, 18 },
        size = 1,
        opacity = 0.7,
        scale = 1
    },
    vertical_line_color = { 0, 0, 0, 1 },
    top_cell_padding = 5,
    bottom_cell_padding = 5,
    right_cell_padding = 5,
    left_cell_padding = 5

}

styles.yatm_minimap_label = {
    type = "label_style",
    font = "default-game",
    font_color = default_font_color,
    size = 50,
    vertical_align = "bottom",
    horizontal_align = "right",
    right_padding = 4
}

styles.yatm_camera_label = {
    type = "label_style",
    font = prefix .. "-small_font",
    height = 15,
    width = 250,
    font_color = {0,255,0},
    right_padding = 4,
    left_margin = 5,
    vertical_align = "top",
    horizontal_align = "left",
}

styles.yatm_semibold_label = { type = "label_style", font = "default-semibold" }



for _, suffix in ipairs({ "default", "red", "green", "blue" }) do
    styles["yatm_small_slot_button_" .. suffix] = {
        type = "button_style",
        parent = "flib_slot_button_" .. suffix,
        size = 36,
        top_margin = 0
    }
end

data:extend { {
    type = "font",
    name = commons.layout_font,
    from = "default",
    size = 16
} }


styles[commons.modal_mask_name] = {
    type = "frame_style",
    graphical_set = {
        base = {
            type = "composition",
            filename = commons.png("images/modal_mask"),
            corner_size = 1,
            position = {0, 0}
        }
    }
}
