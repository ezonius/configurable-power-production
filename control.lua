-- Runtime stage: the heating radius update tool.
-- Selecting entities with the tool fast-replaces them so they re-read the
-- (possibly changed) prototype heating_radius. Only entities whose prototype
-- actually has a heating radius are touched.

local tool_name = "cpp-heating-radius-update-tool"

-- Captures everything needed to re-create the entity before it is destroyed.
-- Returns the create_entity definition and the saved item contents.
local function snapshot(entity, player_index)
	local def = {
		type = entity.type,
		name = entity.name,
		position = entity.position,
		direction = entity.direction,
		orientation = entity.orientation,
		force = entity.force,
		quality = entity.quality,
		player = player_index,
		create_build_effect_smoke = false,
		spawn_decorations = false,
		raise_built = true,
	}

	-- Preserve fuel and burnt result contents (e.g. fuel cells in a reactor).
	local fuel_inventory = entity.get_fuel_inventory()
	local fuel = fuel_inventory and fuel_inventory.valid and fuel_inventory.get_contents() or nil
	local burnt_inventory = entity.get_burnt_result_inventory()
	local burnt = burnt_inventory and burnt_inventory.valid and burnt_inventory.get_contents() or nil

	return def, fuel, burnt
end

local function restore_contents(entity, contents)
	if not contents then
		return
	end
	for _, item in pairs(contents) do
		for _, inventory in pairs({ entity.get_fuel_inventory(), entity.get_burnt_result_inventory() }) do
			if inventory and inventory.valid then
				inventory.insert({ name = item.name, count = item.count, quality = item.quality })
			end
		end
	end
end

local function update_entity(entity, player_index)
	if not entity.valid or not entity.prototype then
		return false
	end

	-- Only touch prototypes that actually have a heating radius (reactors,
	-- heat pipes, and modded buildings that declare one).
	local ok, radius = pcall(function()
		return entity.prototype.heating_radius
	end)
	if not ok or radius == nil then
		return false
	end

	local def, fuel, burnt = snapshot(entity, player_index)
	local surface = entity.surface
	entity.destroy()

	local new_entity = surface.create_entity(def)
	if not new_entity then
		return false
	end

	restore_contents(new_entity, fuel)
	restore_contents(new_entity, burnt)
	return true
end

local function on_selected_area(event)
	if event.item ~= tool_name then
		return
	end
	local count = 0
	for _, entity in pairs(event.entities) do
		if update_entity(entity, event.player_index) then
			count = count + 1
		end
	end
	if count > 0 then
		local message = { "cpp-info.updated-entities", count }
		local player = game.get_player(event.player_index)
		if player then
			player.print(message)
		end
	end
end

script.on_event({
	defines.events.on_player_selected_area,
	defines.events.on_player_alt_selected_area,
}, on_selected_area)
