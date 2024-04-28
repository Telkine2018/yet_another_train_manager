local tools = require("scripts.tools")
local commons = require("scripts.commons")

local prefix = commons.prefix

---@class IndexableEntity
---@field position MapPosition

---@class Device : EntityWithIdAndProcess,IndexableEntity,BaseDeviceConfig
---@field entity LuaEntity                                  @ Associated entity
---@field network SurfaceNetwork                            @ Owning surface
---@field out_red LuaEntity                                 @ Red output element
---@field out_green LuaEntity                               @ Green output element
---@field in_red LuaEntity                                  @ Red input element
---@field in_green LuaEntity                                @ Green input element
---@field force_id integer
---@field trainstop LuaEntity                               @ Associated train stop
---@field trainstop_id integer                              @ Associated train stop id
---@field requested_items table<string, Request>            @ Requested items (round to threshholds)
---@field produced_items table<string, Request>             @ Provided items (round to threshholds)
---@field priority_map table<string, integer>               @ Item => priority
---@field train Train                                       @ current train in/tp depot
---@field trains table<int, Train>                          @ trains that target depot
---@field deliveries {[int]:Delivery}                       @ indexed by train id
---@field image_index integer
---@field scanned_cargo_mask integer?
---@field scanned_fluid_mask integer?
---@field freezed boolean?
---@field dconfig DeviceConfig
---@field internal_requests table<string, integer>
---@field internal_threshold table<string, integer>
---@field last_used_date integer
---@field builder_locomotive_count integer
---@field builder_cargo_count integer
---@field builder_fluid_count integer
---@field builder_fuel_count integer
---@field builder_area BoundingBox
---@field builder_entry MapPosition
---@field conf_change boolean?
---@field builder_stop_create integer?
---@field builder_stop_remove integer?
---@field builder_remove_destroy integer?
---@field builder_create_count integer?
---@field builder_remove_count integer?
---@field builder_parts {[string]:integer}
---@field failcode int?
---@field create_count integer?
---@field ebuffer LuaEntity
---@field teleport_ecount integer?
---@field teleport_rcount integer?
---@field teleport_failure integer?
---@field teleport_last_dst Device?
---@field teleport_last_src Device?
---@field main_controller integer?
---@field secondary_controllers table<integer, boolean>?
---@field output_delivery_content boolean ?
---@field scanned_patterns {[string]:boolean}
---@field distance_cache {[integer]:number}
---@field inactive integer?

---@class BuilderConfig
---@field builder_locomotive_item string
---@field builder_cargo_wagon_item string
---@field builder_fluid_wagon_item string
---@field builder_fuel_item string
---@field builder_pattern string
---@field builder_gpattern string
---@field rpriority integer?                                @ Dismantling priority
---@field no_remove_constraint boolean?                     @ Dismantling priority

---@class BaseDeviceConfig : TrainComposition, BuilderConfig
---@field id integer                                        @ id config
---@field role integer                                      @ role definition
---@field network_mask integer?                             @ Network mask
---@field max_delivery integer?                             @ Max delivery
---@field priority integer?                                 @ Priority
---@field inactivity_delay integer?                         @ inactive delay (s) added to request
---@field max_load_time integer?                            @ max load time for feeder
---@field locked_slots integer?                             @ locked slot 
---@field delivery_timeout integer?                         @ Timeout (s) before reporting train
---@field threshold integer?                                @ default request threshold 
---@field delivery_penalty integer?                         @ Distance penalty for each penalty
---@field station_locked boolean?                           @ Locked to station
---@field teleport_range integer?                           @ teleporter range
---@field combined boolean?                                 @ Combined request
---@field patterns {[string]:boolean}?
---@field has_specific_pattern boolean?
---@field parking_penalty integer?
---@field green_wire_as_priority boolean?

---@class DeviceConfig : BaseDeviceConfig
---@field requests RequestConfig[]                          @ Default request
---@field remove_tick integer
---@field inactive boolean?                                 @ Device is not active

---@class RequestConfig
---@field name string
---@field amount integer
---@field threshold integer?
---@field amount_unit string
---@field threshold_unit string

---@class Request : IndexableEntity
---@field name string                                       @ full product name
---@field requested integer
---@field provided integer
---@field threshold integer
---@field device Device
---@field cancelled boolean
---@field inqueue boolean
---@field create_tick integer
---@field producer_failed_logged boolean?
---@field train_notfound_logged boolean?
---@field failcode integer
---@field in_index boolean?

---@class SurfaceNetwork
---@field force_index integer
---@field surface_name string
---@field surface_index integer
---@field disabled boolean  
---@field depots table<integer, Device>
---@field free_depots table<integer, Device>
---@field used_depots table<integer, Device>
---@field refuelers table<integer, Device>
---@field productions table<string, table<integer, Request>>    @ (product name) => (id device) => (Request)
---@field connected_network SurfaceNetwork
---@field connecting_trainstops LuaEntity[]
---@field connecting_outputs LuaEntity[]
---@field connection_index integer                              @ Last selected connection
---@field connecting_ids table<string, boolean>
---@field is_orbit boolean
---@field teleporters table<integer, Device>
---@field production_indexes table<string, ProductionIndex[]>   @ not used
---@field depotstats table<string, DepotStat>
---@field depotstats_tick integer

---@class DepotStat
---@field free integer
---@field used integer

---@class ProductionIndex
---@field priority integer
---@field name string
---@field node_index SpatialIndexLink?
---@field productions Request[]

---@class Delivery
---@field requester Device
---@field provider Device
---@field train Train
---@field content table<string, integer>
---@field loading_done boolean
---@field unloading_done boolean
---@field cancelled boolean
---@field start_tick integer                         @ start tick
---@field end_tick integer                           @ end tick
---@field start_load_tick integer                    @ start load tick
---@field end_load_tick integer                      @ end load tick
---@field start_unload_tick integer                  @ start unload tick
---@field id integer
---@field combined_delivery Delivery

---@class Train : EntityWithIdAndProcess, TrainComposition
---@field train LuaTrain
---@field slot_count integer                        @ count of slot
---@field cargo_count integer                       @ count of cargo wagon
---@field fluid_capacity integer
---@field delivery Delivery
---@field last_delivery Delivery
---@field network SurfaceNetwork
---@field state TrainState
---@field depot Device                              @ depot or buffer
---@field has_fuel boolean
---@field refueler Device
---@field refresh_tick integer
---@field is_empty boolean
---@field network_mask integer
---@field splitted_schedule TrainScheduleRecord[][]?
---@field teleporting boolean
---@field timeout_tick integer
---@field timeout_delay integer
---@field timeout_pos MapPosition
---@field active_reported boolean
---@field front_stock LuaEntity
---@field last_use_date integer
---@field tracked table<int, boolean>
---@field gpattern string
---@field rpattern string
---@field origin_id integer?

---@class Context
---@field networks table<integer, table<integer, SurfaceNetwork>>       @ index by force index / surface index 
---@field running_requests Request[]?                                   @ Running requests
---@field running_index integer                                         @ Running index
---@field waiting_requests Request[]                                    @ Waiting request
---@field version integer
---@field trainstop_map table<integer, Device>                          @ map id trainstop => device
---@field trains  table<integer, Train>
---@field delivery_id integer
---@field event_id integer                                              @ next id in log
---@field event_log table<int, LogEvent>                                @ logs
---@field min_log_id integer                                            @ min log to recover
---@field use_se boolean                                                @ use space exploration
---@field configs table<integer, DeviceConfig>
---@field config_id integer
---@field request_per_iteration integer
---@field request_iter integer
---@field pattern_ids {[string]:integer}

---@class LogEvent
---@field id integer
---@field severity integer
---@field time integer
---@field type integer
---@field force_id integer
---@field surface string?
---@field msg LocalisedString
---@field request_name string ?
---@field request_amount integer ?
---@field device Device?
---@field delivery Delivery?
---@field network SurfaceNetwork?
---@field network_mask integer?
---@field train Train?
---@field source_teleport Device?
---@field target_teleport Device?

---@class SpatialIndexNode
---@field priority integer
---@field spatial_type integer
---@field left SpatialIndexLink?
---@field right SpatialIndexLink?
---@field value number

---@alias SpatialIndexLink SpatialIndexNode | IndexableEntity

---@class UIConfig
---@field text_filter string
---@field network_mask integer?
---@field surface_name LocalisedString?
---@field signal_filter string?
---@field refresh_rate integer?
---@field station_state integer?
---@field station_sort string?
---@field train_sort string?
---@field history_sort string?
---@field assign_sort string?
---@field depots_sort string?
---@field events_sort string?
---@field stats_sort string?

---@class HeaderDef
---@field name string
---@field width integer
---@field nosort boolean?

---@class TrainComposition
---@field loco_mask integer?
---@field cargo_mask integer?
---@field fluid_mask integer?
---@field rloco_mask integer?
---@field pattern_id integer

---@class ScanInfo
---@field xinit integer
---@field yinit integer
---@field dx integer
---@field dy integer
---@field width integer
---@field height integer

---@class NetworkConnection$
---@field ts LuaEntity
---@field cts LuaEntity
---@field distance number
---@field index integer

local def = {}

---@enum DeviceState
def.device_states = {init = 0}

---@enum DeviceRole
def.device_roles = {
    depot = 1,
    provider = 2,
    requester = 3,
    provider_and_requester = 4,
    buffer = 5,
    refueler = 6,
    builder = 7,
    feeder = 8,
    teleporter = 9
}

---@enum TrainState
def.train_states = {
    at_depot = 1,
    unknown = 2,
    loading = 3,
    unloading = 4,
    to_producer = 5,
    to_requester = 6,
    to_depot = 7,
    depot_not_found = 8,
    to_buffer = 9,
    at_buffer = 10,
    to_refueler = 11,
    at_refueler = 12,
    to_feeder = 13,
    at_feeder = 14,
    feeder_loading = 15,
    waiting_for_requester = 16,
    removed = 17
}

def.provider_requester_buffer_feeder_roles = {

    [def.device_roles.provider] = true,
    [def.device_roles.requester] = true,
    [def.device_roles.provider_and_requester] = true,
    [def.device_roles.buffer] = true,
    [def.device_roles.feeder] = true
}

def.requester_roles = {
    [def.device_roles.requester] = true,
    [def.device_roles.provider_and_requester] = true,
    [def.device_roles.buffer] = true
}

def.requester_roles_no_buffer = {
    [def.device_roles.requester] = true,
    [def.device_roles.provider_and_requester] = true
}

def.provider_requester_roles = {

    [def.device_roles.provider] = true,
    [def.device_roles.requester] = true,
    [def.device_roles.provider_and_requester] = true
}

def.depot_roles = {
    [def.device_roles.depot] = true,
    [def.device_roles.builder] = true
}

def.buffer_feeder_roles = {
    [def.device_roles.buffer] = true,
    [def.device_roles.feeder] = true
}

def.no_scan_roles = {

    [def.device_roles.buffer] = true,
    [def.device_roles.feeder] = true,
    [def.device_roles.depot] = true,
    [def.device_roles.builder] = true,
    [def.device_roles.teleporter] = true
}

def.train_available_states = {
    [def.train_states.to_buffer] = true,
    [def.train_states.at_buffer] = true,
    [def.train_states.to_depot] = true,
    [def.train_states.at_depot] = true,
    [def.train_states.to_feeder] = true,
    [def.train_states.at_feeder] = true
}

def.train_at_station = {
    [def.train_states.at_buffer] = true,
    [def.train_states.at_depot] = true,
    [def.train_states.at_feeder] = true
}

def.virtual_to_internals = {

    [prefix .. "-network_mask"] = "network_mask",
    [prefix .. "-priority"] = "priority",
    [prefix .. "-max_delivery"] = "max_delivery",
    [prefix .. "-delivery_timeout"] = "delivery_timeout",
    [prefix .. "-threshold"] = "threshold",
    [prefix .. "-locked_slots"] = "locked_slots",
    [prefix .. "-inactivity_delay"] = "inactivity_delay",
    [prefix .. "-delivery_penalty"] = "delivery_penalty",

    [prefix .. "-builder_stop_create"] = "builder_stop_create",
    [prefix .. "-builder_stop_remove"] = "builder_stop_remove",
    [prefix .. "-builder_remove_destroy"] = "builder_remove_destroy",

    [prefix .. "-inactive"] = "inactive"


}

def.tracked_types = {

    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true
}

return def
