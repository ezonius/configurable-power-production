-- Applies the startup multipliers to existing prototypes.
-- Runs in the data-final-fixes stage so that all other mods have already defined and
-- modified their data (anything another mod does in data-updates is overridden by us).
-- Only the exact named buildings below are modified; other entities (including modded
-- buildings reusing these prototype types) are left untouched.

local prefix = "configurable-power-production-"

-- Prototype type + name -> list of power properties to scale (dot paths; absent
-- properties are skipped silently).
local properties_by_building = {
	solar_panel = { "production" },
	accumulator = {
		"energy_source.buffer_capacity",
		"energy_source.input_flow_limit",
		"energy_source.output_flow_limit",
	},
	nuclear_reactor = { "consumption" },
	heating_tower = { "consumption" },
	heat_exchanger = { "energy_consumption" },
	heat_pipe = {
		"heat_buffer.max_transfer",
		"heat_buffer.specific_heat",
	},
	-- Vanilla 2.x generators have no max_power_output: their output is derived from
	-- fluid_usage_per_tick * maximum_temperature, so scale that as well when present.
	steam_engine = { "max_power_output", "fluid_usage_per_tick" },
	steam_turbine = { "max_power_output", "fluid_usage_per_tick" },
	fusion_reactor = { "power_input" },
	fusion_generator = {
		"energy_source.output_flow_limit",
		"energy_source.buffer_capacity",
	},
}

-- Prototype type + name for each building that has settings.
local buildings = {
	{ building = "solar-panel", type = "solar-panel" },
	{ building = "accumulator", type = "accumulator" },
	{ building = "nuclear-reactor", type = "reactor", has_neighbor_bonus_toggle = true },
	{ building = "heating-tower", type = "reactor", has_neighbor_bonus_toggle = true },
	{ building = "heat-pipe", type = "heat-pipe" },
	{ building = "heat-exchanger", type = "boiler" },
	{ building = "steam-engine", type = "generator" },
	{ building = "steam-turbine", type = "generator" },
	{ building = "fusion-reactor", type = "fusion-reactor" },
	{ building = "fusion-generator", type = "fusion-generator" },
}

local function get_multiplier(building, suffix)
	local setting = settings.startup[prefix .. building .. "-" .. suffix]
	if setting and type(setting.value) == "number" then
		return setting.value
	end
	return 1
end

local function get_path(prototype, path)
	local node = prototype
	for key in path:gmatch("[^.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

local function set_path(prototype, path, value)
	local keys = {}
	for key in path:gmatch("[^.]+") do
		keys[#keys + 1] = key
	end
	local last = table.remove(keys)
	local node = prototype
	for _, key in ipairs(keys) do
		if type(node) ~= "table" then
			return
		end
		node = node[key]
	end
	if type(node) == "table" then
		node[last] = value
	end
end

-- Scales an energy value ("100kW", "5MJ", 1000000) keeping the unit suffix intact.
local function scale_energy(value, multiplier)
	if type(value) == "number" then
		return value * multiplier
	end
	if type(value) ~= "string" then
		return value
	end
	local number, suffix = value:match("^%s*(%-?%d+%.?%d*)%s*([^%d%s].*)$")
	if not number then
		number = value:match("^%s*(%-?%d+%.?%d*)%s*$")
		suffix = ""
	end
	if not number then
		return value
	end
	return string.format("%g%s", tonumber(number) * multiplier, suffix)
end

-- Scale each named building's power properties and remember its name for recipe matching.
local entity_names = {}
for _, entry in ipairs(buildings) do
	local prototype = data.raw[entry.type] and data.raw[entry.type][entry.building]
	if prototype then
		local multiplier = get_multiplier(entry.building, "power-multiplier")
		if multiplier ~= 1 then
			for _, path in ipairs(properties_by_building[entry.building:gsub("%-", "_")] or {}) do
				local value = get_path(prototype, path)
				if value ~= nil then
					set_path(prototype, path, scale_energy(value, multiplier))
				end
			end
		end
		-- Optional extra multiplier (heat pipe heating radius is tuned separately
		-- from heat transfer; it is a plain tile count, not an energy value).
		local radius = get_multiplier(entry.building, "radius-multiplier")
		if prototype.heating_radius and radius ~= 1 then
			prototype.heating_radius = prototype.heating_radius * radius
		end
		entity_names[entry.building] = true
	end
end

-- Item weight scaling: heavier items consume more rocket lift capacity.
-- The entity's item shares the entity's name; absent items are skipped silently.
for _, entry in ipairs(buildings) do
	local item = data.raw.item and data.raw.item[entry.building]
	if item and item.weight then
		local multiplier = get_multiplier(entry.building, "weight-multiplier")
		if multiplier ~= 1 then
			item.weight = math.max(1, item.weight * multiplier)
		end
	end
end

-- Reactor neighbour bonus toggles. neighbour_bonus is the production increase per
-- orthogonally adjacent reactor (vanilla nuclear-reactor: 1, heating-tower: 0).
local function apply_neighbor_bonus(building, prototype)
	local setting = settings.startup[prefix .. building .. "-neighbor-bonus"]
	if not setting then
		return
	end
	if setting.value and prototype.neighbour_bonus == 0 then
		-- Enable the bonus for reactors that have none (vanilla heating tower).
		prototype.neighbour_bonus = 1
	elseif not setting.value and (prototype.neighbour_bonus or 0) > 0 then
		-- Disable the bonus for reactors that have one (vanilla nuclear reactor).
		prototype.neighbour_bonus = 0
	end
end
for _, entry in ipairs(buildings) do
	if entry.has_neighbor_bonus_toggle then
		local prototype = data.raw[entry.type] and data.raw[entry.type][entry.building]
		if prototype then
			apply_neighbor_bonus(entry.building, prototype)
		end
	end
end

-- Recipe cost scaling: never scale below 1 (minimum_value = 1 on the setting, clamped here as well).
local function scale_recipe(recipe, multiplier)
	if multiplier <= 1 then
		return
	end
	local scaled_energy = math.max(1, math.floor((recipe.energy_required or 0.5) * multiplier * 10000 + 0.5) / 10000)
	recipe.energy_required = scaled_energy
	local ingredients = recipe.ingredients
	if ingredients then
		for _, ingredient in ipairs(ingredients) do
			local amount = ingredient.amount
			if type(amount) == "number" then
				local scaled_amount = math.max(1, amount * multiplier)
				if scaled_amount % 1 == 0 then
					scaled_amount = math.floor(scaled_amount)
				end
				ingredient.amount = scaled_amount
			end
		end
	end
end

local function find_building(recipe)
	if entity_names[recipe.name] then
		return recipe.name
	end
	local results = recipe.results
	if results then
		for _, result in ipairs(results) do
			if entity_names[result.name] then
				return result.name
			end
		end
	end
	return nil
end

for _, recipe in pairs(data.raw.recipe or {}) do
	local building = find_building(recipe)
	if building then
		scale_recipe(recipe, get_multiplier(building, "recipe-multiplier"))
	end
end
