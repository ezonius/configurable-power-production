# Configurable Power Production

Adds startup settings for per-building power production multipliers and recipe cost multipliers for power buildings. Settings are grouped and color-coded (solar / nuclear / steam / fusion / lightning).

## Buildings covered

| Group | Buildings |
|---|---|
| Solar | solar panel, accumulator |
| Nuclear | nuclear reactor, heating tower, heat pipe |
| Steam | boiler, heat exchanger, steam engine, steam turbine |
| Fusion | fusion reactor, fusion generator |
| Lightning | lightning rod, lightning collector |

## Per-building settings (startup)

- **Power multiplier** — scales the building's power production/conversion (e.g. solar `production`, accumulator buffer and flow limits, reactor `consumption`, generator fluid usage and power output, lightning attractor buffer/discharge).
- **Recipe cost multiplier** — scales the crafting recipe cost of the building itself (1–100; heat pipes included).
- **Item weight multiplier** — scales the item weight (heavier items take more rocket lift capacity).
- **Heating radius multiplier** (nuclear group) — scales the heating radius of heat pipes, nuclear reactors and heating towers. Reactors have no vanilla heating radius, so any value above 1 enables ambient heating (thaws frozen terrain/entities, e.g. Aquilo).
- **Attract range multiplier** (lightning group) — extends how far away lightning strikes are attracted to rods/collectors.
- **Reactor neighbour bonus toggles** — enable/disable the neighbour bonus for nuclear reactors (default: on) and heating towers (default: off, vanilla behaviour).

All multipliers default to 1 (vanilla behaviour).

## Compatibility

- **Apply to modded buildings** (startup toggle, default off): also applies the group multipliers to buildings added by other mods. Modded buildings get no settings of their own; they are classified into the vanilla groups (by prototype type, then by name pattern) and inherit the multipliers of the vanilla building they resemble.
- Applied in the data-final-fixes stage, so it overrides prototype changes made by other mods.

## Heating radius updater tool

The multipliers only change prototypes; already-placed entities read their heating radius when built. A shortcut (heating tower icon, "Heating radius updater") gives a selection tool: selecting already-placed heating entities (reactors, heat pipes, modded heating buildings) fast-replaces them so they pick up the changed prototype heating radius. Fuel and burnt results are preserved.

## Settings changes require a restart

Startup settings only apply when a save is (re)loaded after changing them.

## License

MIT — see [LICENSE](LICENSE).
