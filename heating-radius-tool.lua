-- Data stage: selection tool + shortcut for updating the heating radius of
-- already-placed heating entities at runtime.
-- The multipliers in data-final-fixes.lua only affect prototypes; placed
-- entities read their prototype's heating_radius at placement time, so changed
-- multipliers do not apply to existing buildings. This tool fast-replaces the
-- selected entities so they pick up the current prototype values.

local icon = "__space-age__/graphics/icons/heating-tower.png"

data:extend({
	{
		type = "selection-tool",
		name = "cpp-heating-radius-update-tool",
		icon = icon,
		icon_size = 64,
		flags = { "not-stackable", "spawnable" },
		hidden = true,
		subgroup = "other",
		order = "z[cpp-heating-radius-update-tool]",
		stack_size = 1,
		select = {
			border_color = { 0.3, 1, 0.3 },
			mode = { "any-entity" },
			cursor_box_type = "copy",
		},
		alt_select = {
			border_color = { 0.3, 1, 0.3 },
			mode = { "any-entity" },
			cursor_box_type = "copy",
		},
	},
	{
		type = "shortcut",
		name = "cpp-heating-radius-update-shortcut",
		order = "z[cpp]",
		action = "spawn-item",
		item_to_spawn = "cpp-heating-radius-update-tool",
		toggleable = true,
		icon = icon,
		icon_size = 64,
		small_icon = icon,
		small_icon_size = 64,
	},
})
