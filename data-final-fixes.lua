local commons = require("scripts.commons")

if mods["nullius"] then
	local name = "nullius-" .. commons.device_name

	data.raw["recipe"][name].subgroup = data.raw["train-stop"]["train-stop"].subgroup
	data.raw["item"][commons.device_name].subgroup = data.raw["item"]["train-stop"].subgroup
	table.insert(data.raw.technology["nullius-broadcasting-1"].prerequisites, name)
end
