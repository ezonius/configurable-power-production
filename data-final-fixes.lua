-- Applies the startup multipliers to existing prototypes.
-- Runs in the data-final-fixes stage so that all other mods have already defined and
-- modified their data (anything another mod does in data-updates is overridden by us).
-- Vanilla buildings are matched by exact prototype name; when the "apply to modded"
-- toggle is on, buildings from other mods are classified into the vanilla groups
-- (by prototype type first, then by name pattern) and inherit those multipliers.

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
	-- "energy_usage" is the machine-style power property; vanilla reactors/boilers
	-- don't have it, but modded buildings of other prototype types (e.g. Muluna's
	-- vacuum heating tower, an assembling-machine) do. On such machines the heat
	-- production rate is crafting_speed (fixed heat recipe), so scale it too.
	nuclear_reactor = { "consumption", "energy_usage", "crafting_speed" },
	heating_tower = { "consumption", "energy_usage", "crafting_speed" },
	heat_pipe = {
		"heat_buffer.max_transfer",
		"heat_buffer.specific_heat",
	},
	boiler = { "energy_consumption", "energy_usage" },
	heat_exchanger = { "energy_consumption", "energy_usage" },
	-- Vanilla 2.x generators have no max_power_output: their output is derived from
	-- fluid_usage_per_tick * maximum_temperature, so scale that as well when present.
	-- energy_source.output_flow_limit / max_fluid_usage are fusion-generator style
	-- properties (absent on vanilla generators), so modded buildings built on the
	-- fusion-generator prototype but classified as a turbine/engine scale too.
	steam_engine = { "max_power_output", "fluid_usage_per_tick", "energy_usage",
		"max_fluid_usage", "energy_source.output_flow_limit" },
	steam_turbine = { "max_power_output", "fluid_usage_per_tick", "energy_usage",
		"max_fluid_usage", "energy_source.output_flow_limit" },
	fusion_reactor = { "power_input" },
	fusion_generator = {
		"energy_source.output_flow_limit",
		"energy_source.buffer_capacity",
		"max_fluid_usage",
	},
	-- Lightning attractors: the energy source is the electric buffer/discharge
	-- (like an accumulator) — it scales the energy stored per lightning strike
	-- and the rate the stored energy can be fed into the grid.
	lightning_rod = { "energy_source.buffer_capacity", "energy_source.output_flow_limit" },
	lightning_collector = { "energy_source.buffer_capacity", "energy_source.output_flow_limit" },
}

-- Building list: exact vanilla prototype names. Optional flags:
--   power = gets a power production multiplier setting
--   radius = gets a heating-radius multiplier setting
--   range = gets an attract-range multiplier setting (lightning rods/collectors)
--   has_neighbor_bonus_toggle = gets a neighbour bonus bool setting
local buildings = {
	{ building = "solar-panel", type = "solar-panel", group = "solar", power = true },
	{ building = "accumulator", type = "accumulator", group = "solar", power = true },
	{ building = "nuclear-reactor", type = "reactor", group = "nuclear", power = true, radius = true,
		has_neighbor_bonus_toggle = true },
	{ building = "heating-tower", type = "reactor", group = "nuclear", power = true, radius = true,
		has_neighbor_bonus_toggle = true },
	{ building = "heat-pipe", type = "heat-pipe", group = "nuclear", power = true, radius = true },
	{ building = "boiler", type = "boiler", group = "steam", power = true },
	{ building = "heat-exchanger", type = "boiler", group = "steam", power = true },
	{ building = "steam-engine", type = "generator", group = "steam", power = true },
	{ building = "steam-turbine", type = "generator", group = "steam", power = true },
	{ building = "fusion-reactor", type = "fusion-reactor", group = "fusion", power = true },
	{ building = "fusion-generator", type = "fusion-generator", group = "fusion", power = true },
	{ building = "lightning-rod", type = "lightning-attractor", group = "lightning", power = true, range = true },
	{ building = "lightning-collector", type = "lightning-attractor", group = "lightning", power = true, range = true },
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

-- ---------------------------------------------------------------------------
-- Modded building classification: map a non-vanilla prototype to the vanilla
-- building whose multipliers it should inherit. Returns the vanilla building
-- name (e.g. "nuclear-reactor") or nil to leave the prototype untouched.
-- ---------------------------------------------------------------------------

-- Prototype types that identify a building group directly.
local type_to_building = {
	["solar-panel"] = "solar-panel",
	accumulator = "accumulator",
	reactor = nil, -- reactors need energy_source inspection (nuclear vs heating)
	["heat-pipe"] = "heat-pipe",
	boiler = nil, -- boilers need energy_source inspection (coal vs heat)
	generator = nil, -- generators need maximum_temperature inspection
	["fusion-reactor"] = "fusion-reactor",
	["lightning-attractor"] = "lightning-rod",
	["fusion-generator"] = nil, -- needs input fluid inspection (plasma vs steam)
}

-- Manual classification overrides, keyed by modded prototype name. The value is
-- the vanilla building whose multipliers to inherit, or false to leave the
-- prototype alone entirely. Takes precedence over the automatic classification.
local classification_overrides = {
	-- Muluna's vacuum boiler is primarily a crafting machine; ignore it.
	["muluna-advanced-boiler"] = false,
	-- Muluna's condenser turbine burns steam and outputs cooled steam, but is built
	-- on the fusion-generator prototype; it should behave like a steam turbine.
	["muluna-cycling-steam-turbine"] = "steam-turbine",
}

-- Fallback for buildings using other prototype types (e.g. Muluna's vacuum
-- heating tower is an assembling-machine): match distinctive name substrings.
local name_patterns = {
	{ pattern = "heating%-tower", building = "heating-tower" },
	{ pattern = "nuclear%-reactor", building = "nuclear-reactor" },
	{ pattern = "heat%-pipe", building = "heat-pipe" },
	{ pattern = "heat%-exchanger", building = "heat-exchanger" },
	{ pattern = "steam%-turbine", building = "steam-turbine" },
	{ pattern = "steam%-engine", building = "steam-engine" },
	{ pattern = "boiler", building = "boiler" },
	{ pattern = "solar%-panel", building = "solar-panel" },
	{ pattern = "fusion%-generator", building = "fusion-generator" },
	{ pattern = "fusion%-reactor", building = "fusion-reactor" },
}

local function classify_modded(prototype)
	local override = classification_overrides[prototype.name]
	if override ~= nil then
		return override or nil
	end
	local by_type = type_to_building[prototype.type]
	if by_type then
		return by_type
	end
	-- Reactors: burn nuclear fuel -> nuclear reactor group, otherwise heating tower.
	if prototype.type == "reactor" then
		local source = prototype.energy_source
		local categories = source and source.fuel_categories
		if categories then
			for _, category in ipairs(categories) do
				if category:find("nuclear") then
					return "nuclear-reactor"
				end
			end
		end
		return "heating-tower"
	end
	-- Boilers: burn fuel -> boiler group, everything else (e.g. heat source)
	-- is a heat exchanger.
	if prototype.type == "boiler" then
		local source = prototype.energy_source
		if source and (source.type == "burner" or source.type == "fluid") then
			return "boiler"
		end
		return "heat-exchanger"
	end
	-- Generators: hot fluid (>= 400 degrees, like the vanilla steam turbine's 500)
	-- is a turbine; cooler fluid (like the vanilla steam engine's 165) is an engine.
	if prototype.type == "generator" then
		local temperature = prototype.maximum_temperature or 0
		if temperature >= 400 then
			return "steam-turbine"
		end
		return "steam-engine"
	end
	-- Fusion generators that consume some fluid other than fusion plasma are
	-- really steam turbines (e.g. Muluna's condenser turbine burns steam).
	if prototype.type == "fusion-generator" then
		local input = prototype.input_fluid_box
		if input and input.filter and input.filter ~= "fusion-plasma" then
			return "steam-turbine"
		end
		return "fusion-generator"
	end
	-- Name-based fallback for other prototype types.
	local name = prototype.name or ""
	for _, entry in ipairs(name_patterns) do
		if name:find(entry.pattern) then
			return entry.building
		end
	end
	return nil
end


-- Prototype types that share names with power buildings but are not buildings
-- (remnants, explosions, signals, particles, decorations). Never classify these,
-- even when a name pattern matches (e.g. "nuclear-reactor-remnants").
local excluded_types = {
	["virtual-signal"] = true,
	explosion = true,
	["optimized-particle"] = true,
	["heat-interface"] = true,
	corpse = true,
	["optimized-decorative"] = true,
}

-- Log each classification once so modded building matches can be checked in
-- factorio-current.log (filter on "configurable-power-production").
local logged_classifications = {}
local function classify_and_log(prototype)
	if excluded_types[prototype.type] then
		return nil
	end
	local building = classify_modded(prototype)
	local key = prototype.name .. "|" .. tostring(building)
	if not logged_classifications[key] then
		logged_classifications[key] = true
		if building then
			log("[configurable-power-production] Classified modded prototype '"
				.. prototype.name .. "' (type " .. prototype.type .. ") as " .. building .. ".")
		else
			log("[configurable-power-production] Ignoring modded prototype '"
				.. prototype.name .. "' (type " .. prototype.type .. ", no classification).")
		end
	end
	return building
end

-- Colour-coded groups, matching the colors used in the setting names (locale).
-- Used to tag modded buildings with the group they were classified into.
local group_labels = {
	solar = { color = "yellow" },
	nuclear = { color = "green" },
	steam = { color = "orange" },
	fusion = { color = "blue" },
	lightning = { color = "purple" },
}
local group_by_building = {}
for _, entry in ipairs(buildings) do
	group_by_building[entry.building] = entry.group
end

-- Localised, colour-coded label of the vanilla building whose multipliers a
-- modded building inherits, e.g. [color=green]Heating tower[/color].
local function building_label(building)
	local group = group_by_building[building]
	return { "", "[color=", group_labels[group].color, "]", { "mod-building-label." .. building }, "[/color]" }
end

-- Scale each building's power properties and remember its name for recipe matching.
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
		-- Optional heating-radius multiplier. Entities that radiate heat thaw frozen
		-- terrain/entities around them (e.g. Aquilo). Reactors have no vanilla heating
		-- radius (default 0, and 0 multiplied stays 0), so a value above 1 enables
		-- ambient heating with a base radius of 1 tile times the multiplier.
		local radius = get_multiplier(entry.building, "radius-multiplier")
		if radius ~= 1 then
			local base = prototype.heating_radius or 1
			if base == 0 and radius > 1 then
				base = 1
			end
			prototype.heating_radius = base * radius
		end
		-- Optional attract-range multiplier (lightning rods/collectors). The range
		-- elongation extends how far away lightning strikes are attracted. Only
		-- scaled when the property is present, so other prototype types are safe.
		local range = get_multiplier(entry.building, "range-multiplier")
		if range ~= 1 then
			local base = prototype.range_elongation
			if base ~= nil then
				prototype.range_elongation = base * range
			end
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

-- Modded building support: classify every non-vanilla building prototype into a
-- vanilla group and apply that group's multipliers to it (and to its item).
local apply_to_modded_setting = settings.startup[prefix .. "apply-to-modded"]
if apply_to_modded_setting and apply_to_modded_setting.value then
	for proto_type, protos in pairs(data.raw) do
		if proto_type ~= "recipe" and proto_type ~= "item" and proto_type ~= "autoplace-control"
			and not proto_type:find("%-setting$") then
			for name, prototype in pairs(protos) do
				if type(prototype) == "table" and not entity_names[name] then
					local building = classify_and_log(prototype)
					if building then
						local multiplier = get_multiplier(building, "power-multiplier")
						if multiplier ~= 1 then
							for _, path in ipairs(properties_by_building[building:gsub("%-", "_")] or {}) do
								local value = get_path(prototype, path)
								if value ~= nil then
									set_path(prototype, path, scale_energy(value, multiplier))
								end
							end
						end
						local radius = get_multiplier(building, "radius-multiplier")
						if radius ~= 1 then
							-- Only write heating_radius where it is a valid prototype property
							-- (reactor/heat-pipe types, or already present as a custom field);
							-- unknown properties on other prototype types would break loading.
							local owns_radius = prototype.type == "reactor"
								or prototype.type == "heat-pipe"
								or prototype.heating_radius ~= nil
							if owns_radius then
								local base = prototype.heating_radius or 1
								if base == 0 and radius > 1 then
									base = 1
								end
								prototype.heating_radius = base * radius
							end
						end
						-- Optional attract-range multiplier (lightning rods/collectors).
						-- Only scaled when the property is present, so other prototype
						-- types are safe.
						local range = get_multiplier(building, "range-multiplier")
						if range ~= 1 then
							local base = prototype.range_elongation
							if base ~= nil then
								prototype.range_elongation = base * range
							end
						end
						local item = data.raw.item and data.raw.item[name]
						if item and item.weight then
							local weight = get_multiplier(building, "weight-multiplier")
							if weight ~= 1 then
								item.weight = math.max(1, item.weight * weight)
							end
						end
						-- Colour-coded tooltip showing which group's multipliers this
						-- building was classified into (CustomTooltipField, since 2.0.59).
						local group = group_labels[group_by_building[building]]
						if group then
							prototype.custom_tooltip_fields = prototype.custom_tooltip_fields or {}
							table.insert(prototype.custom_tooltip_fields, {
								name = { "entity-tooltip.configurable-power-production-multiplier-group" },
								value = building_label(building),
							})
						end
					end
				end
			end
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

local modded_building_names = nil
if apply_to_modded_setting and apply_to_modded_setting.value then
	modded_building_names = {}
	for proto_type, protos in pairs(data.raw) do
		if proto_type ~= "recipe" and proto_type ~= "item" and proto_type ~= "autoplace-control"
			and not proto_type:find("%-setting$") then
			for name, prototype in pairs(protos) do
				if type(prototype) == "table" and not entity_names[name] then
					local building = classify_and_log(prototype)
					if building then
						modded_building_names[name] = building
					end
				end
			end
		end
	end
end

for _, recipe in pairs(data.raw.recipe or {}) do
	local building = find_building(recipe)
	if not building and modded_building_names then
		local results = recipe.results
		if results then
			for _, result in ipairs(results) do
				building = modded_building_names[result.name]
				if building then
					break
				end
			end
		end
	end
	if building then
		scale_recipe(recipe, get_multiplier(building, "recipe-multiplier"))
	end
end


