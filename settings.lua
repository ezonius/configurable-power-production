-- Startup settings: per-building power production multipliers and recipe cost multipliers.
-- One power multiplier and one recipe multiplier per building; heat pipes get a recipe
-- multiplier only (they transport heat, they do not produce or consume power).

local prefix = "configurable-power-production-"

-- Color-coded groups (group color prefix is applied in the locale setting names).
local groups = {
	solar = "a",
	nuclear = "b",
	steam = "c",
	fusion = "d",
}

-- Each entry: building = prototype name, type = data.raw type, group = color-coded group,
-- power = whether the building gets a power production multiplier.
local buildings = {
	{ building = "solar-panel", type = "solar-panel", group = "solar", power = true },
	{ building = "accumulator", type = "accumulator", group = "solar", power = true },
	{ building = "nuclear-reactor", type = "reactor", group = "nuclear", power = true, radius = true },
	{ building = "heating-tower", type = "reactor", group = "nuclear", power = true, radius = true },
	{ building = "heat-pipe", type = "heat-pipe", group = "nuclear", power = true, radius = true },
	{ building = "heat-exchanger", type = "boiler", group = "steam", power = true },
	{ building = "steam-engine", type = "generator", group = "steam", power = true },
	{ building = "steam-turbine", type = "generator", group = "steam", power = true },
	{ building = "fusion-reactor", type = "fusion-reactor", group = "fusion", power = true },
	{ building = "fusion-generator", type = "fusion-generator", group = "fusion", power = true },
}

local settings = {}

for _, entry in ipairs(buildings) do
	local name = prefix .. entry.building .. "-"
	local order = groups[entry.group] .. entry.building

	if entry.power then
		settings[#settings + 1] = {
			type = "double-setting",
			name = name .. "power-multiplier",
			setting_type = "startup",
			default_value = 1,
			minimum_value = 0,
			maximum_value = 100,
			order = order .. "a",
		}
	end

	settings[#settings + 1] = {
		type = "double-setting",
		name = name .. "recipe-multiplier",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 1,
		maximum_value = 100,
		order = order .. "b",
	}

	-- Item weight multiplier: heavier items take more rocket lift capacity.
	settings[#settings + 1] = {
		type = "double-setting",
		name = name .. "weight-multiplier",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0,
		maximum_value = 100,
		order = order .. "c",
	}

	-- Heating radius multiplier for entities that radiate heat to their surroundings
	-- (thaws frozen terrain/entities on Aquilo). Reactors have no vanilla heating radius,
	-- so any value above 1 enables ambient heating with that radius in tiles.
	if entry.radius then
		settings[#settings + 1] = {
			type = "double-setting",
			name = name .. "radius-multiplier",
			setting_type = "startup",
			default_value = 1,
			minimum_value = 0,
			maximum_value = 100,
			order = order .. "d",
		}
	end
end

-- Reactor neighbour bonus toggles. Defaults match vanilla:
-- nuclear reactors have a neighbour bonus (neighbour_bonus = 1), heating towers do not (0).
settings[#settings + 1] = {
	type = "bool-setting",
	name = prefix .. "nuclear-reactor-neighbor-bonus",
	setting_type = "startup",
	default_value = true,
	order = groups.nuclear .. "nuclear-reactord",
}

settings[#settings + 1] = {
	type = "bool-setting",
	name = prefix .. "heating-tower-neighbor-bonus",
	setting_type = "startup",
	default_value = false,
	order = groups.nuclear .. "heating-towerd",
}

data:extend(settings)
