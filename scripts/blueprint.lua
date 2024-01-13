local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local config = require("scripts.config")
local yutils = require("scripts.yutils")

------------------------------------------------------

---@type Runtime
local devices_runtime

---@type EntityMap<Device>
local devices

local prefix = commons.prefix

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end

tools.on_load(on_load)

---@param bp LuaItemStack
---@param mapping table<integer, LuaEntity>
---@param surface LuaSurface
local function register_mapping(bp, mapping, surface)

    local context = yutils.get_context()

    local bp_count = bp.get_blueprint_entity_count()
    if #mapping ~= 0 then
        for index = 1, bp_count do
            local entity = mapping[index]
            if entity and entity.valid and entity.name == commons.device_name then
                local device = devices[entity.unit_number]
                if device then
                    bp.set_blueprint_entity_tags(index, device.dconfig)
                end
            end
        end
    elseif bp_count > 0 then
        local bp_entities = bp.get_blueprint_entities()
        if bp_entities then
            for index = 1, bp_count do
                local entity = bp_entities[index]
                if entity.name == commons.device_name then
                    local entities = surface.find_entities_filtered {
                        name = commons.device_name,
                        position = entity.position,
                        radius = 0.1
                    }
                    if #entities > 0 then
                        local entity = entities[1]
                        local device = devices[entity.unit_number]
                        if device then
                            bp.set_blueprint_entity_tags(index, device.dconfig)
                        end
                    end
                end
            end
        end
    end
end

local function on_register_bp(e)

    local player = game.get_player(e.player_index)
    ---@cast player -nil
    local vars = tools.get_vars(player)
    if e.gui_type == defines.gui_type.item and e.item and e.item.is_blueprint and
        e.item.is_blueprint_setup() and player.cursor_stack and
        player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint and
        not player.cursor_stack.is_blueprint_setup() then
        vars.previous_bp = {blueprint = e.item, tick = e.tick}
    else
        vars.previous_bp = nil
    end
end

---@param player LuaPlayer
---@return LuaItemStack?
local function get_bp_to_setup(player)

    -- normal drag-select
    local bp = player.blueprint_to_setup
    if bp and bp.valid_for_read and bp.is_blueprint_setup() then return bp end

    -- alt drag-select (skips configuration dialog)
    bp = player.cursor_stack
    if bp and bp.valid_for_read and bp.is_blueprint and bp.is_blueprint_setup() then

        while bp.is_blueprint_book do
            bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
        end
        return bp
    end

    -- update of existing blueprint
    local previous_bp = tools.get_vars(player).previous_bp
    if previous_bp and previous_bp.tick == game.tick and previous_bp.blueprint and
        previous_bp.blueprint.valid_for_read and
        previous_bp.blueprint.is_blueprint_setup() then
        return previous_bp.blueprint
    end
end

tools.on_event(defines.events.on_player_setup_blueprint,
---@param e EventData.on_player_setup_blueprint
               function(e)
    local player = game.players[e.player_index]
    ---@type table<integer, LuaEntity>
    local mapping = e.mapping.get()
    local bp = get_bp_to_setup(player)
    if bp then register_mapping(bp, mapping, player.surface) end
end)

tools.on_event(defines.events.on_gui_closed, on_register_bp)
