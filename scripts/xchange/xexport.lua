
local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")

local xdef = require("scripts.xchange.xdef")

local xchg_service_name = "xchg_service"

local xexport = {}

---@type EntityMap<Device>
local devices
---@type Runtime
local devices_runtime


---@return boolean
function xexport.process()

    local context = yutils.get_context()

    for _, train in pairs(context.trains) do
        if train.state ~= defs.train_states.at_depot and 
        train.state ~= defs.train_states.at_buffer then
            return false
        end
    end

    local xdevices = {}
    for id, device in pairs(devices) do
        ---@cast device Device

        ---@type XDevice
        local xdevice = {
            unit_number = device.entity.unit_number,

            out_red = device.out_red and device.out_red.unit_number,
            out_green = device.out_green and device.out_green.unit_number,
            in_red = device.in_red and device.in_red.unit_number,
            in_green = device.in_green and device.in_green.unit_number,
            trainstop_id = device.trainstop and device.trainstop.unit_number,
            train = device.train and device.train.train and device.train.train.id,
            dconfig = device.dconfig,
            scanned_cargo_mask = device.scanned_cargo_mask,
            scanned_fluid_mask = device.scanned_fluid_mask 
        }
        xdevices[xdevice.unit_number] = xdevice
    end

    local xtrains = {}

    for _, train in pairs(context.trains) do
        ---@cast train Train

        local ttrain = train.train

        ---@type XTrain
        local xtrain = {
            id = ttrain.id,
            depot = train.depot and train.depot.id,
            refueler = train.refueler and train.refueler.id,
            state = train.state
        }
        xtrains[xtrain.id] = xtrain
    end

    remote.call(xchg_service_name, "set", "devices", xdevices)
    remote.call(xchg_service_name, "set", "trains", xtrains)
    return true
end

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end

tools.on_load(on_load)


return xexport