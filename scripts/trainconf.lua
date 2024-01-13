local commons = require("scripts.commons")
local defs = require("scripts._defs")

local trainconf = {}

local cargo_range = 1
local fluid_range = 1000
local loco_range = 1000000

---@class TrainConfElement
---@field type string
---@field count integer
---@field is_back boolean

---@class TrainConf
---@field elements TrainConfElement[]
---@field index integer?
---@field is_generic boolean?

---@alias TrainPattern string

---@type {[string]:string}
PatternCache = {}

---@param pattern TrainPattern?
---@return TrainConfElement[]
function trainconf.split_pattern(pattern)
    if not pattern then
        return {}
    end
    local elements = {}
    for eq in string.gmatch(pattern, "%S+") do
        local splitter = string.gmatch(eq, "[^=]+")
        local type = splitter()
        local scount = splitter()
        local is_back = false
        if string.sub(type, 1, 1) == "<" then
            type = string.sub(type, 2)
            is_back = true
        end

        ---@type TrainConfElement
        local element = {
            type = type,
            count = tonumber(scount) --[[@as integer]],
            is_back = is_back
        }

        table.insert(elements, element)
    end
    return elements
end

---@param elements TrainConfElement[]
---@return TrainPattern
function trainconf.create_pattern(elements)
    local list = {}
    local start = true
    for _, element in pairs(elements) do
        if not start then
            table.insert(list, " ")
        else
            start = false
        end
        if element.is_back then
            table.insert(list, "<")
        end
        table.insert(list, element.type)
        table.insert(list, "=")
        table.insert(list, element.count)
    end
    return table.concat(list)
end

---@param train Train
---@return boolean
function trainconf.get_train_composition(train)
    local generic_elements = {}
    local specific_elements = {}
    ---@type TrainConfElement
    local last_generic
    ---@type TrainConfElement
    local last_specific

    train.slot_count = 0
    train.fluid_capacity = 0
    train.cargo_count = 0

    train.loco_mask = 0
    train.cargo_mask = 0
    train.fluid_mask = 0
    train.pattern_id = 0

    local ttrain = train.train
    if not ttrain.valid then
        return false
    end

    local back_movers = {}
    for _, loco in pairs(ttrain.locomotives.back_movers) do
        back_movers[loco.unit_number] = true
    end

    local carriages = ttrain.carriages
    local len = #carriages
    local id = 100

    local mask = 1
    for index = 1, len do
        local carriage = carriages[index]
        local generic_type = carriage.type
        local name = carriage.name
        local is_back
        if generic_type == "locomotive" then
            generic_type = "*"
            is_back = back_movers[carriage.unit_number] ~= nil
            id = id + loco_range
            if index <= 31 then
                train.loco_mask = bit32.bor(train.loco_mask, mask)
            end
        elseif generic_type == "cargo-wagon" or generic_type == "artillery-wagon" then
            generic_type = "c"
            train.slot_count = train.slot_count + carriage.prototype.get_inventory_size(defines.inventory.cargo_wagon)
            train.cargo_count = train.cargo_count + 1
            id = id + cargo_range
            if index <= 31 then
                train.cargo_mask = bit32.bor(train.cargo_mask, mask)
            end
        elseif generic_type == "fluid-wagon" then
            generic_type = "f"
            train.fluid_capacity = train.fluid_capacity + carriage.prototype.fluid_capacity
            id = id + fluid_range
            if index <= 31 then
                train.fluid_mask = bit32.bor(train.fluid_mask, mask)
            end
        else
            generic_type = "*"
        end

        if last_generic and last_generic.type == generic_type then
            last_generic.count = last_generic.count + 1
        else
            last_generic = {
                type = generic_type,
                count = 1
            }
            table.insert(generic_elements, last_generic)
        end

        if last_specific and last_specific.type == name and last_specific.is_back == is_back then
            last_specific.count = last_specific.count + 1
        else
            last_specific = {
                type = name,
                count = 1,
                is_back = is_back
            }
            table.insert(specific_elements, last_specific)
        end
        len = len + 1
        mask = 2 * mask
    end
    if generic_elements[#generic_elements].type == "*" then
        table.remove(generic_elements, #generic_elements)
    end
    train.gpattern = trainconf.create_pattern(generic_elements)
    train.rpattern = trainconf.create_pattern(specific_elements)
    train.pattern_id = id
    return true
end

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
function trainconf.scan_device(device)
    local trainstop = device.trainstop

    device.scanned_patterns = nil
    if defs.no_scan_roles[device.role] then
        return
    end

    if not (trainstop and trainstop.valid) then return end

    local position = trainstop.position
    local info = scan_infos[trainstop.orientation / 0.25 + 1]

    local surface = trainstop.surface

    position = {
        x = position.x + info.xinit + info.dx,
        y = position.y + info.yinit + info.dy
    }

    local x = position.x
    local y = position.y

    ---@type TrainConfElement
    local last_fluid_element = { type = "*", count = 1 }
    ---@type TrainConfElement
    local last_cargo_element = { type = "*", count = 1 }

    ---@type TrainConfElement[]
    local cargo_elements = { last_cargo_element }

    ---@type TrainConfElement[]
    local fluid_elements = { last_fluid_element }


    local start = trainstop.position
    while true do
        local area = { { x, y }, { x + info.width, y + info.height } }
        local entities = surface.find_entities_filtered {
            area = area,
            type = scan_type_map
        }

        local has_rail
        local has_fluid
        local has_cargo
        local has_signal

        local cargo_and_fluid = true
        for _, entity in pairs(entities) do
            local type = entity.type
            if type == "straight-rail" then
                has_rail = true
            elseif type == "pump" then
                has_fluid = true
            elseif type == "inserter" or type == "loader" or type ==
                "loader-1x1" or type == "mining-drill" then
                has_cargo = true
            elseif type == "train-stop" then
                if entity.position.x == start.x or entity.position.y == start.y then
                    has_signal = true
                end
            elseif type == "rail-chain-signal" or type == "rail-signal" then
                has_signal = true
            end
        end
        if has_signal or not has_rail then break end

        local cargo_type
        local fluid_type
        if has_cargo then
            cargo_type = "c"
            if has_fluid then
                fluid_type = "f"
            else
                fluid_type = "c"
            end
        elseif has_fluid then
            cargo_type = "f"
            fluid_type = "f"
        else
            cargo_type = "*"
            fluid_type = "*"
        end

        cargo_and_fluid = cargo_and_fluid and cargo_type == fluid_type
        if last_cargo_element.type == cargo_type then
            last_cargo_element.count = last_cargo_element.count + 1
        else
            last_cargo_element = {
                type = cargo_type,
                count = 1
            }
            table.insert(cargo_elements, last_cargo_element)
        end

        if last_fluid_element.type == fluid_type then
            last_fluid_element.count = last_fluid_element.count + 1
        else
            last_fluid_element = {
                type = fluid_type,
                count = 1
            }
            table.insert(fluid_elements, last_fluid_element)
        end
        x = x + info.dx
        y = y + info.dy
    end

    if last_cargo_element.type == "*" then
        table.remove(cargo_elements, #cargo_elements)
        table.remove(fluid_elements, #fluid_elements)
    end

    if #cargo_elements == 0 and #fluid_elements == 0 then
        device.scanned_patterns = nil
        return
    end

    device.scanned_patterns = {}
    if #cargo_elements > 0 then
        local pattern = trainconf.create_pattern(cargo_elements)
        device.scanned_patterns[pattern] = true
    end
    if #fluid_elements > 0 then
        local pattern = trainconf.create_pattern(fluid_elements)
        device.scanned_patterns[pattern] = true
    end
end

---@param elements TrainConfElement[]
function trainconf.get_train_content(elements)
    ---@type {[string]:integer}
    local content = {}
    for _, element in pairs(elements) do
        content[element.type] = (content[element.type] or 0) + element.count
    end
    return content
end

---@param device Device
function trainconf.check_scan_device(device)
    if defs.provider_requester_roles[device.role] then trainconf.scan_device(device) end
end

---@param device_patterns {[string]:boolean}
---@param config_patterns string[]
function trainconf.patterns_equals(device_patterns, config_patterns)
    if table_size(device_patterns) ~= table_size(config_patterns) then return false end
    for _, name in pairs(config_patterns) do
        if not device_patterns[name] then
            return false
        end
    end
    return true
end

---@param config_patterns string[]
function trainconf.config_to_device_patterns(config_patterns)
    local set = {}
    for _, name in pairs(config_patterns) do
        set[name] = true
    end
    return set
end

---@param patterns1 {[string]:boolean}?
---@param patterns2 {[string]:boolean}?
---@return {[string]:boolean}?
function trainconf.intersect_patterns(patterns1, patterns2)
    if not patterns1 then
        return patterns2
    end
    if not patterns2 then
        return patterns1
    end
    local result = {}
    for name, _ in pairs(patterns1) do
        if patterns2[name] then
            result[name] = true
        end
        local generic = PatternCache[name]
        if patterns2[generic] then
            result[name] = true
        end
    end
    for name in pairs(patterns2) do
        local generic = PatternCache[name]
        if patterns1[generic] then
            result[name] = true
        end
    end
    return result
end

---@param pattern string?
---@return TrainComposition
function trainconf.pattern_to_mask(pattern)
    if not pattern then
        return {}
    end
    local index = 1
    local elements = trainconf.split_pattern(pattern)
    local cargo_mask = 0
    local fluid_mask = 0
    local loco_mask = 0
    local mask = 1

    local function apply_cargo()
        cargo_mask = bit32.bor(cargo_mask, mask)
    end
    local function apply_fluid()
        fluid_mask = bit32.bor(fluid_mask, mask)
    end
    local function apply_loco()
        loco_mask = bit32.bor(loco_mask, mask)
    end
    local function no_apply() end

    for _, element in pairs(elements) do
        local f = no_apply
        if element.type == "*" then
            f = apply_loco
        elseif element.type == "c" then
            f = apply_cargo
        elseif element.type == "f" then
            f = apply_fluid
        elseif element.type == "l" then
            f = apply_loco
        else
            local proto = game.entity_prototypes[element.type]
            if proto.type == "cargo-wagon" then
                f = apply_cargo
            elseif proto.type == "fluid-wagon" then
                f = apply_fluid
            elseif proto.type == "locomotive" then
                f = apply_loco
            else
                f = no_apply
            end
        end
        for i = 1, element.count do
            f()
            mask = 2 * mask
            index = index + 1
            if index > 30 then
                goto done
            end
        end
    end
    ::done::
    return {
        cargo_mask = cargo_mask ~= 0 and cargo_mask or nil,
        fluid_mask = fluid_mask ~= 0 and fluid_mask or nil,
        loco_mask = loco_mask ~= 0 and loco_mask or nil
    }
end

---@param compo TrainComposition
---@param keep_loco boolean?
---@param use_fluid boolean?
---@return TrainConfElement[]?
function trainconf.mask_to_pattern(compo, keep_loco, use_fluid)
    local mask = 1
    local cargo_mask = compo.cargo_mask or 0
    local fluid_mask = compo.fluid_mask or 0
    local loco_mask = compo.loco_mask or 0
    local rloco_mask = compo.rloco_mask or 0
    loco_mask = bit32.bor(loco_mask, rloco_mask)
    local elements = {}
    ---@type TrainConfElement
    local last_element
    for i = 1, 32 do
        local type
        local is_back = false
        type = "*"

        if not use_fluid then
            if bit32.band(cargo_mask, mask) ~= 0 then
                type = "c"
            elseif bit32.band(fluid_mask, mask) ~= 0 then
                type = "f"
            end
        else
            if bit32.band(fluid_mask, mask) ~= 0 then
                type = "f"
            elseif bit32.band(cargo_mask, mask) ~= 0 then
                type = "c"
            end
        end

        if bit32.band(loco_mask, mask) ~= 0 then
            type = keep_loco and "l" or "*"
        end
        if keep_loco and bit32.band(rloco_mask, mask) ~= 0 then
            type = keep_loco and "l" or "*"
            is_back = true
        end
        if last_element and last_element.type == type and last_element.is_back == is_back then
            last_element.count = last_element.count + 1
        else
            last_element = {
                type = type,
                count = 1,
                is_back = is_back
            }
            table.insert(elements, last_element)
        end
        mask = 2 * mask
    end
    if #elements >= 1 and elements[#elements].type == "*" then
        table.remove(elements, #elements)
    end
    if #elements == 0 then
        return nil
    end
    return elements
end

---@param device Device
function trainconf.load_config_from_mask(device)
    local dconfig = device.dconfig
    local pattern_mask = dconfig
    dconfig.patterns = nil
    dconfig.builder_pattern = nil
    dconfig.builder_gpattern = nil
    local elements
    if dconfig.role == defs.device_roles.builder then
        elements = trainconf.mask_to_pattern(pattern_mask, true)
        if elements then
            for _, element in pairs(elements) do
                if element.type == "c" then
                    element.type = dconfig.builder_cargo_wagon_item
                elseif element.type == "f" then
                    element.type = dconfig.builder_fluid_wagon_item
                elseif element.type == "l" or element.type == "*" then
                    element.type = dconfig.builder_locomotive_item
                else
                    goto failed
                end
            end
            dconfig.builder_pattern = trainconf.create_pattern(elements)
            dconfig.builder_cargo_wagon_item = nil
            dconfig.builder_fluid_wagon_item = nil
            dconfig.builder_locomotive_item = nil
        end
        ::failed::
    end

    local cargo_elements = trainconf.mask_to_pattern(pattern_mask, false, false)
    if cargo_elements then
        local gpattern = trainconf.create_pattern(cargo_elements)
        dconfig.patterns = { [gpattern] = true }
        if dconfig.role == defs.device_roles.builder then
            dconfig.builder_gpattern = gpattern
        end
    end

    local fluid_elements = trainconf.mask_to_pattern(pattern_mask, false, true)
    if fluid_elements then
        local gpattern = trainconf.create_pattern(fluid_elements)
        if gpattern then
            if dconfig.patterns then
                dconfig.patterns[gpattern] = true
            else
                dconfig.patterns = { [gpattern] = true }
            end
        end
    end
end

---@param type string?
---@return string?
function trainconf.get_sprite(type)
    if not type then return nil end
    local sprite_name = commons.generic_to_sprite[type]
    if sprite_name then
        return sprite_name
    else
        local proto = game.entity_prototypes[type.type]
        if proto then
            local item = proto.items_to_place_this[1]
            if item then
                return "item/" .. item.name
            end
        end

        return "virtual/signal-anything"
    end
end

---@param elements TrainConfElement[]
---@return boolean
function trainconf.is_generic(elements)
    for _, element in pairs(elements) do
        if not commons.generic_to_sprite[element.type] then
            return false
        end
    end
    return true
end

---@param elements TrainConfElement[]
---@return TrainConfElement[]
function trainconf.purify(elements)
    ---@type TrainConfElement[]
    local result = {}
    ---@type TrainConfElement
    local last_element

    for _, e in pairs(elements) do
        if last_element and e.type == last_element.type and e.is_back == last_element.is_back then
            last_element.count = last_element.count + e.count
        else
            table.insert(result, e)
            last_element = e
        end
    end

    if last_element and last_element.type == "*" then
        table.remove(result, #result)
    end
    return result
end

---@param pattern string?
---@return string?
function trainconf.create_generic(pattern)
    if not pattern then return nil end

    local elements = trainconf.split_pattern(pattern)
    ---@type TrainConfElement[]
    local result = {}
    for _, element in pairs(elements) do
        local name = element.type
        local proto = game.entity_prototypes[name]
        local type = proto.type
        if type == "locomotive" then
            type = "*"
        elseif type == "cargo-wagon" then
            type = "c"
        elseif type == "fluid-wagon" then
            type = "f"
        else
            type = "*"
        end
        --- @type TrainConfElement
        local e = {
            count = element.count,
            type = type
        }
        table.insert(result, e)
    end
    result = trainconf.purify(result)
    return trainconf.create_pattern(result)
end

return trainconf
