data:extend({
    {
        type = "bool-setting",
        name = "yaltn-debug",
		setting_type = "startup",
        default_value = false,
		order="aa"
    },
    {
        type = "bool-setting",
        name = "yaltn-disabled",
		setting_type = "runtime-global",
        default_value = false,
		order="aa"
    },
    {
        type = "double-setting",
        name = "yaltn-reaction_time",
		setting_type = "runtime-global",
        default_value = 2,
        minimum_value = 0.15,
		order="ab"
    },
    {
        type = "int-setting",
        name = "yaltn-default_threshold",
		setting_type = "runtime-global",
        default_value = 1000,
		order="ac"
    },
    {
        type = "string-setting",
        name = "yaltn-log_level",
		setting_type = "runtime-global",
        default_value = "delivery",
        allowed_values = { "off", "error", "delivery"},
		order="ad"
    },
    {
        type = "int-setting",
        name = "yaltn-refuel_min",
		setting_type = "runtime-global",
        default_value = 120,
        minimum_value = 120,
		order="ae"
    },
    {
        type = "bool-setting",
        name = "yaltn-auto_clean",
		setting_type = "runtime-global",
        default_value = true,
		order="af"
    },
    {
        type = "int-setting",
        name = "yaltn-log_keeping_delay",
		setting_type = "runtime-global",
        default_value = 300,
		order="ag",
        minimum_value = 120
    },
    {
        type = "bool-setting",
        name = "yaltn-show_surface_in_log",
		setting_type = "runtime-global",
        default_value = true,
		order="ah"
    },
    {
        type = "bool-setting",
        name = "yaltn-inactive_on_copy",
        setting_type = "runtime-global",
        default_value = true,
        order="ai"
    },
    {
        type = "int-setting",
        name = "yaltn-default_network_mask",
		setting_type = "runtime-global",
        default_value = 1,
		order="aj"
    },
    {
        type = "int-setting",
        name = "yaltn-max_delivery",
		setting_type = "runtime-global",
        default_value = 1,
        minimum_value = 1,
		order="ak"
    },
    {
        type = "int-setting",
        name = "yaltn-delivery_timeout",
		setting_type = "runtime-global",
        default_value = 60,
		order="al"
    },
    {
        type = "int-setting",
        name = "yaltn-teleport_range",
		setting_type = "runtime-global",
        default_value = 300,
        minimum_value= 30,
		order="am"
    }
    ,
    {
        type = "int-setting",
        name = "yaltn-teleport_threshold",
		setting_type = "runtime-global",
        default_value = 2,
        minimum_value= 2,
		order="an"
    },
    {
        type = "int-setting",
        name = "yaltn-teleport_timeout",
		setting_type = "runtime-global",
        order="ao",
        minimum_value = 300,
        default_value = 30 * 60,
    },
    {
        type = "int-setting",
        name = "yaltn-teleport_min_distance",
		setting_type = "runtime-global",
        order="ap",
        minimum_value = 30,
        default_value = 90
    },
    {
        type = "int-setting",
        name = "yaltn-ui_wagon_slots",
		setting_type = "runtime-global",
        order="ar",
        minimum_value = 1,
        default_value = 40
    },
    {
        type = "int-setting",
        name = "yaltn-ui_fluid_wagon_capacity",
		setting_type = "runtime-global",
        order="as",
        minimum_value = 1,
        default_value = 25000
    },
    {
        type = "int-setting",
        name = "yaltn-ui_train_wagon_count",
		setting_type = "runtime-global",
        order="at",
        minimum_value = 1,
        default_value = 4,
        maximum_value = 31
    },
})

data:extend({
        {
            type = "bool-setting",
            name = "yaltn-show_train_mask",
            setting_type = "runtime-per-user",
            default_value = true,
            order="aa"
        },
        {
            type = "int-setting",
            name = "yaltn-gui_train_len",
            setting_type = "runtime-per-user",
            default_value = 16,
            order="ab",
            maximum_value  = 32
        },
        {
            type = "int-setting",
            name = "yaltn-network_mask_size",
            setting_type = "runtime-per-user",
            default_value = 16,
            order="ac",
            minimum_value = 4,
            maximum_value  = 32
        },
        {
            type = "int-setting",
            name = "yaltn-ui_request_max",
            setting_type = "runtime-per-user",
            order="ad",
            minimum_value = 4,
            default_value = 12,
            maximum_value  = 64
        },
        {
            type = "int-setting",
            name = "yaltn-ui_width",
            setting_type = "runtime-per-user",
            order="ah",
            minimum_value = 500,
            default_value = 1000
        },
        {
            type = "int-setting",
            name = "yaltn-ui_height",
            setting_type = "runtime-per-user",
            order="ai",
            minimum_value = 500,
            default_value = 800
        }
        ,{
            type = "int-setting",
            name = "yaltn-fa_train_delay",
            setting_type = "runtime-per-user",
            order="aj",
            minimum_value = 10,
            default_value = 60
        },{
            type = "bool-setting",
            name = "yaltn-fa_use_stack",
            setting_type = "runtime-per-user",
            order="ak",
            default_value = false
        },{
            type = "double-setting",
            name = "yaltn-fa_threshold_percent",
            setting_type = "runtime-per-user",
            order="al",
            default_value = 50
        }
})

