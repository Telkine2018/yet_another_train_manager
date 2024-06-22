local tools = require("scripts.tools")
local runtime = require("scripts.runtime")

local config = {

    disabled = false,
    delivery_penalty = 300,         -- delivery penalty 
    nticks = 5,                     -- Scan delay (tick: > 5)
    max_per_run = 20,               -- Max par run
    reaction_time = 2,              -- reaction time (s)
    default_threshold = 1000,       -- default delivery threshold
    log_level = 0,                  -- log level
    refuel_min = 120,                -- Minimum fuel duration (s)
    auto_clean = true,
    default_network_mask = 1,
    default_max_delivery = 1,
    delivery_timeout = 60,
    log_keeping_delay = 300,
    show_surface_in_log = true,
    inactive_on_copy = true,
    ui_wagon_slots = 40,
    ui_fluid_wagon_capacity = 25000,
    ui_train_wagon_count = 4,
    teleport_range = 300,
    teleport_threshold = 2,
    teleport_animation = true,
    teleport_report = false,
    auto_ajust_delivery = true,
    auto_rename_station = true,
    
    show_train_mask = true,
    gui_train_len = 16,
    network_mask_size = 16,
    ui_request_max = 12,
    ui_width = 1000,
    ui_height = 600,
    uistock_produced_cols = 8,
    uistock_requested_cols = 6,
    uistock_transit_cols = 6,
    uistock_internals_cols = 8,
    uistock_lines = 18,
    ui_autoupdate = true,

    fa_train_delay = 60,
    fa_use_stack = false,
    fa_threshold_percent = 50.0,

    default_parking_penalty = 300,

    teleport_timeout = 30 * 60,
    teleport_min_distance = 90,

    use_combinator_for_request = false,
}

config.log_to_index = {["off"] = 0, ["error"] = 1, ["delivery"] = 2}

local excluded = {["reaction_time"] = true, ["log_level"] = true}

config.index_to_log = {}
for name, index in pairs(config.log_to_index) do
    config.index_to_log[index] = name
end

local function load_config()

    config.reaction_time = settings.global["yaltn-reaction_time"].value
    local devices_runtime = runtime.get_existing("Device")
    if devices_runtime then
        devices_runtime.config.refresh_rate = math.floor(config.reaction_time * 60 / config.nticks)
    end

    local log_text = settings.global["yaltn-log_level"].value
    config.log_level = config.log_to_index[log_text]

    for name, _ in pairs(config) do
        if not excluded[name] then
            local setting = settings.global["yaltn-" .. name]
            if setting then config[name] = setting.value --[[@as any]] end
        end
    end
    config.refuel_min = settings.global["yaltn-refuel_min"].value --[[@as integer]]
end

tools.on_load(load_config)

tools.on_event(defines.events.on_runtime_mod_setting_changed,
---@param e EventData.on_runtime_mod_setting_changed
               function(e) 
                load_config() 
                global.units_cache_map = nil
            end)

return config

