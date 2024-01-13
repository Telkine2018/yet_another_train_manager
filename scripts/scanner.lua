local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local config = require("scripts.config")
local trainconf = require("scripts.trainconf")

local scanner = {}

local margin = 3
local margin2 = 2 * margin

---@type ScanInfo[]
local scan_infos = {

    { -- 0 ^
        xinit = -3 - margin,
        yinit = -1,
        dx = 0,
        dy = 7,
        width = 2 + margin2,
        height = 7
    }, { -- 0.25 >
        xinit = -6,
        yinit = -3 - margin,
        dx = -7,
        dy = 0,
        width = 7,
        height = 2 + margin2
    }, { -- 0.5 v
        xinit = -margin + 1,
        yinit = -6,
        dx = 0,
        dy = -7,
        width = 2 + margin2,
        height = 7
    }, { -- 0.75 <
        xinit = -1,
        yinit = 1 - margin,
        dx = 7,
        dy = 0,
        width = 7,
        height = 2 + margin2
    }
}

local scan_type_map = {
    "pump", "inserter", "loader", "loader-1x1", "mining-drill",
    "rail-chain-signal", "rail-signal", "train-stop", "straight-rail"
}

---@param device Device
function scanner.scan(device)

    local trainstop = device.trainstop
    if not trainstop.valid then return end

    local position = trainstop.position
    local info = scan_infos[trainstop.orientation / 0.25 + 1]

    local surface = trainstop.surface

    position = {
        x = position.x + info.xinit + info.dx,
        y = position.y + info.yinit + info.dy
    }

    local mask = 2
    ---@type integer ?
    local cargo_mask = 0
    ---@type integer ?
    local fluid_mask = 0

    local x = position.x
    local y = position.y

    local count = 0
    while true do

        local area = {{x, y}, {x + info.width, y + info.height}}
        local entities = surface.find_entities_filtered {
            area = area,
            type = scan_type_map
        }

        local has_rail
        local has_fluid
        local has_cargo
        local has_signal
        for _, entity in pairs(entities) do

            local type = entity.type
            if type == "straight-rail" then
                has_rail = true
            elseif type == "pump" then
                has_fluid = true
            elseif type == "inserter" or type == "loader" or type ==
                "loader-1x1" or type == "mining-drill" then
                has_cargo = true
            elseif type == "rail-chain-signal" or type == "rail-signal" or type ==
                "train-stop" then
                has_signal = true
            end
        end
        if has_signal or not has_rail then break end
        if has_cargo then cargo_mask = cargo_mask + mask end
        if has_fluid then fluid_mask = fluid_mask + mask end
        x = x + info.dx
        y = y + info.dy
        mask = mask * 2
    end

    trainconf.scan_device(device)
    device.patterns = device.dconfig.patterns or device.scanned_patterns
    device.has_specific_pattern = device.dconfig.has_specific_pattern
end

---@param device Device
function scanner.check_scan(device)
    if defs.provider_requester_roles[device.role] then scanner.scan(device) end
end

return scanner
