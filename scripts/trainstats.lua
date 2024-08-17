local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")


local trainstats = {}

---@param network SurfaceNetwork
local function compute_stat(network)
    ---@type table<string, integer>
    local stats = {}
    local context = yutils.get_context()


    local surface = game.surfaces[network.surface_index]
    local trains = surface.get_trains(network.force_index)

    for _, ttrain in pairs(trains) do
        
        local train = context.trains[ttrain.id]
        if train then
            local gpattern = train.gpattern
            stats[gpattern] = (stats[gpattern] or 0) + 1
        end
    end

    network.trainstats = stats
    network.trainstats_tick = GAMETICK
    network.trainstats_change = nil
end

---@param network SurfaceNetwork
---@param pattern string
---@return integer
function trainstats.get(network, pattern)
    if network.trainstats_change or not network.trainstats or network.trainstats_tick < GAMETICK - 300 then
        compute_stat(network)
    end
    local stat = network.trainstats[pattern]
    return stat
end

return trainstats
