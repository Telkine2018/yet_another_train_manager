local commons = require("scripts.commons")

local prefix = commons.prefix
local png = commons.png


local item_slot_count = settings.startup[prefix .. "-item_slot_count"].value

local function create_base(base_name)
	local entity = table.deepcopy(data.raw['arithmetic-combinator']['arithmetic-combinator'])
	local decider = data.raw['decider-combinator']['decider-combinator']

	entity.name = base_name
	entity.icon = png(base_name .. '-item')
	entity.icon_mipmaps = 0
	entity.minable = { mining_time = 0.5, result = base_name }
	entity.circuit_wire_max_distance = 10
	entity.max_health = 500
	entity.active_energy_usage = '1KW'
	entity.energy_source = { type = "void" }
	entity.render_no_network_icon = false
	entity.render_no_power_icon = false
	entity.collision_box = { { -0.1, -0.6 }, { 0.1, 0.6 } }
	entity.radius_visualisation_specification = {
		sprite            = {
			filename = png("images/selection"),
			tint = { r = 1, g = 1, b = 0, a = .5 },
			height = 32,
			width = 32,
		},
		distance          = 3.0,
		draw_on_selection = false,
		draw_in_cursor    = true
	}

	entity.sprites = table.deepcopy(decider.sprites)
	for k, spec in pairs(entity.sprites) do
		for n, layer in pairs(spec.layers) do
			layer, layer.hr_version = layer.hr_version, nil -- only use hr version, for easier editing
			spec.layers[n] = layer
			if not layer.filename:match('^__base__/graphics/entity/combinator/hr%-decider%-combinator')
			then
				error('hr-decider-combinator sprite sheet incompatibility detected')
			end
			if not layer.filename:match('%-shadow%.png$')
			then
				layer.filename = png(base_name)
			else
				layer.filename = png(base_name .. '-shadow')
			end
		end
	end

	for prop, sprites in pairs(entity) do
		if not prop:match('_symbol_sprites$') then goto skip end
		for dir, spec in pairs(sprites) do
			spec, spec.hr_version = spec.hr_version, nil -- only use hr version, for easier editing
			sprites[dir] = spec
			if spec.filename ~= '__base__/graphics/entity/combinator/hr-combinator-displays.png'
			then
				error('hr-decider-combinator display symbols sprite sheet incompatibility detected')
			end
			spec.filename = png(base_name .. '-displays')
			spec.shift = table.deepcopy(decider.greater_symbol_sprites[dir].hr_version.shift)
		end
		::skip::
	end

	for _, k in ipairs {
		'corpse', 'dying_explosion', 'activity_led_sprites',
		'input_connection_points', 'output_connection_points',
		'activity_led_light_offsets', 'screen_light', 'screen_light_offsets',
		'input_connection_points', 'output_connection_points'
	} do
		local v = decider[k]
		if type(v) == 'table' then v = table.deepcopy(decider[k]) end
		entity[k] = v
	end

	do
		local invisible_sprite = { filename = png('invisible'), width = 1, height = 1 }
		local wire_conn = { wire = { red = { 0, 0 }, green = { 0, 0 } }, shadow = { red = { 0, 0 }, green = { 0, 0 } } }
		data:extend { entity,
			{ type = 'constant-combinator',
				name = base_name .. '-cc',
				flags = { 'placeable-off-grid' },
				collision_mask = {},
				item_slot_count = item_slot_count,
				circuit_wire_max_distance = 3,
				sprites = invisible_sprite,
				activity_led_sprites = invisible_sprite,
				activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
				circuit_wire_connection_points = { wire_conn, wire_conn, wire_conn, wire_conn },
				draw_circuit_wires = false } }
	end
end

create_base(commons.device_name)

local recipe, tech

	recipe =
	{
		type = 'recipe',
		name = commons.device_name,
		enabled = false,
		ingredients = {
			{ 'electronic-circuit', 4 }
		},
		result = commons.device_name
	}

	tech = {
		type = 'technology',
		name = commons.device_name,
		icon_size = 144,
		icon = png('tech'),
		effects = {
			{ type = 'unlock-recipe', recipe = commons.device_name }
		},
		unit = {
			count = 200,
			ingredients = {
				{ 'automation-science-pack', 1 },
				{ 'logistic-science-pack',   1 } },
			time = 15
		},
		order = 'a-d-d-z'
	}

if mods["nullius"] then

	recipe.ingredients = {
		{"arithmetic-combinator", 2},
		{"copper-cable", 10}
	}
	recipe.category = "tiny-crafting"
	recipe.always_show_made_in = true
	recipe.name = "nullius-" .. recipe.name

	
	tech.name = "nullius-" .. tech.name
	tech.order = "nullius-z-z-z"
	tech.unit = {
		count = 100,
		ingredients = {
			{"nullius-geology-pack", 1}, {"nullius-climatology-pack", 1}, {"nullius-mechanical-pack", 1}, {"nullius-electrical-pack", 1}
		},
		time = 25
	}
	tech.prerequisites = {"nullius-checkpoint-optimization", "nullius-traffic-control"}
	tech.ignore_tech_tech_cost_multiplier = true
	tech.effects = {
		{ type = 'unlock-recipe', recipe = recipe.name }
	}

end

data:extend {

	-- Item
	{
		type = 'item',
		name = commons.device_name,
		icon_size = 64,
		icon = png(commons.device_name .. '-item'),
		subgroup = 'circuit-network',
		order = 's[ensor]-bb[previse-transfer]',
		place_result = commons.device_name,
		stack_size = 10 },

	-- Recipe
	recipe,

	-- Technology
	tech
}

local ebuffer = {

	type = "electric-energy-interface",
	name = commons.teleport_electric_buffer_name,
	sprite = {

		filename = png("invisible")
	},
	energy_source = {
		type = "electric",
		usage_priority = "secondary-input",
		render_no_network_icon = false,
		buffer_capacity = commons.teleport_electric_buffer_size .. "J",
		input_flow_limit = (200 * 1000 * 1000) .. "W",
		output_flow_limit = "0W",
		drain = (20 * 1000 * 1000) .. "W"
	},
	collision_mask = {},
	collision_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
	selection_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
	selectable_in_game = false
}

data:extend { ebuffer }
