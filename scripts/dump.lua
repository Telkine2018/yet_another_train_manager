local tools = require("scripts.tools")

local dump = {}

local filename = "dump.txt"
local maxlevel = 20
local lines = {}

local recurs_map = {}
local recurs_index = 1

local function flush()
    if #lines > 0 then
        table.insert(lines, "")
        local s = table.concat(lines, "\n")
        helpers.write_file(filename, s, true)
        lines = {}
    end
end

local function append(msg)
    table.insert(lines, msg)
    if #lines > 500 then
        flush()
    end
end

local function dump_level(data, prefix, level, path)
    local start = ","
    for key, value in pairs(data) do
        if type(value) == "table" and level < maxlevel then
            if not recurs_map[value] then
                recurs_index = recurs_index + 1
                recurs_map[value] = recurs_index
                append(prefix .. start .. "\"" .. tostring(key) .. "\": {")
                append(prefix .. "\t\"__name\": \"table(" .. tostring(recurs_index) .. ")\"")
                append(prefix .. "\t,\"__path\":\"" .. path .. "[" .. tostring(key) .. "]\"")
                if value.__self then
                    append(prefix .. "\t\",object_name\":\"" .. value.object_name .. "\"")
                    if value.object_name == "LuaEntity" then
                        if not value.valid then
                            append(prefix .. "\t,\"valid\":false")
                        else
                            append(prefix .. "\t,\"type\":\"" .. value.type .. "\"")
                            append(prefix .. "\t,\"name\":\"" .. value.name .. "\"")
                            append(prefix .. "\t,\"unit_number\":\"" .. value.unit_number .. "\"")
                            append(prefix .. "\t,\"position\":\"(" .. value.position.x .. "," .. value.position.y .. ")\"")
                        end
                    elseif value.object_name == "LuaTrain" then
                        if not value.valid then
                            append(prefix .. "\t,\"valid\":false")
                        else
                            append(prefix .. "\t,\"od\":" .. value.id .. "")
                            append(prefix .. "\t,\"state\":\"" .. tools.get_constant_name(value.state, defines.train_state) .. "\"")
                        end
                    end
                end

                dump_level(value, prefix .. "\t", level + 1, path .. "[" .. tostring(key) .. "]")
                append(prefix .. "}")
            else
                append(prefix .. start .. "\"" .. tostring(key) .. "\" : \"ref table(" .. recurs_map[value] .. ")\"")
            end
        else
            local svalue
            local t = type(value)
            if t == "string" then
                svalue = "\"" .. value .. "\""
            elseif t == "number" or t == "boolean" or t == "nil" then
                svalue = tostring(value)
            elseif t == "userdata" then
                svalue = "\"userdata\""
            else
                svalue = "\"" .. tostring(value) .. "\""
            end
            append(prefix .. start .. "\"" .. tostring(key) .. "\":" .. svalue)
        end
        start = ","
    end
end

function dump.process()
    recurs_map = {}
    recurs_index = 0
    helpers.write_file(filename, "", false)
    dump_level(storage, "", 0, "")
    flush()
    recurs_map = nil
end

if false then
    local has_dump
    tools.on_event(defines.events.on_tick, function(e)
        if not has_dump then
            has_dump = true
            dump.process()
        end
    end)
end

commands.add_command("yatm_dump", { "yatm_dump" }, dump.process)

return dump
