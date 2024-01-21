local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local Runtime = require("scripts.runtime")
local yutils = require("scripts.yutils")
local config = require("scripts.config")
local logger = require("scripts.logger")


local depotstats = {}

---@param network SurfaceNetwork
local function compute_stat(network)
    local stats = {}

    local function create_stat(pattern)
        local stat = stats[pattern]
        if not stat then
            stat = { free = 0, used = 0 }
            stats[pattern] = stat
        end
        return stat
    end

    local stat
    for _, depot in pairs(network.used_depots) do
        if depot.role == defs.device_roles.depot then
            local train = depot.train
            if train then
                stat = create_stat(train.rpattern)
                stat.used = stat.used + 1

                local stat = create_stat(train.gpattern)
                stat.used = stat.used + 1
            end
        end
    end
    for _, depot in pairs(network.free_depots) do
        if depot.role == defs.device_roles.depot then
            local empty = true
            if depot.patterns then
                for pattern in pairs(depot.patterns) do
                    local stat = create_stat(pattern)
                    stat.free = stat.free + 1
                    empty = false
                end
            end

            if empty then
                stat = create_stat("")
                stat.free = stat.free + 1
            end
        end
    end
    network.depotstats = stats
    network.depotstats_tick = GAMETICK
end

---@param network SurfaceNetwork
---@param pattern string
---@return DepotStat
function depotstats.get(network, pattern)
    if not network.depotstats or network.depotstats_tick < GAMETICK - 300 then
        compute_stat(network)
    end
    local stat = network.depotstats[pattern]
    local gstat = network.depotstats[""]
    return {
        used = (stat and stat.used or 0) + (gstat and gstat.used or 0),
        free = (stat and stat.free or 0) + (gstat and gstat.free or 0)
    }
end

return depotstats
