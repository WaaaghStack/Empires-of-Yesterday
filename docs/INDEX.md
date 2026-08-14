# Documentation index — Empires of Yesterday

World Conquest is the only game mode: fluid territory conquest on a 360×180 Earth globe with structures, units, and miners on owned mineral deposits.

## Canonical docs

| Doc | Contents |
|-----|----------|
| [DESIGN.md](../DESIGN.md) | Fantasy, controls, dictionary, structures/units, map gen, **WorldDataset + SCD1** architecture, **design locks**, Godot version story |
| [PERFORMANCE.md](../PERFORMANCE.md) | Frame budgets, SCD1 live paint, construction drain order, catch-up cap, env knobs, F3 HUD |
| [RUST.md](../RUST.md) | Build GDExtension, authority module list, TerritorySim SCD1 API, env vars |
| [QA_LIFECYCLE.md](../QA_LIFECYCLE.md) | When/how to run headless QA and smoke tests |
| [README.md](../README.md) | Quick start, play summary, Rust requirement for live |
| [REQUEST_SCD1_VERSIONED_PULL.md](REQUEST_SCD1_VERSIONED_PULL.md) | SCD1 main tables + domain monotonic pulls; full snaps only at start/gap |
| [AUDIT_CELL_WORLD_BUGS_UX.md](AUDIT_CELL_WORLD_BUGS_UX.md) | Cell-world / SCD1 / pathing / build UX audit + implement status |
| [REQUEST_SURGE_THEATERS_PAINT.md](REQUEST_SURGE_THEATERS_PAINT.md) | Outpost Pump/Drain/Surge, named theaters, beachhead+strike paint |

## Architecture snapshot (live Play)

1. **Map gen** — `WorldConquestMapGenerator.generate(map_id, seed)` (primary). `EarthMapGenerator` is a thin wrapper for default Earth.
2. **Authority** — Rust WorldDataset (grid, structures, world session, resource wallet).
3. **Presentation** — SCD1 per-domain versioned pulls (`Scd1DomainPull` / `pull_domain_since`); apply-only. PresentationTxn is legacy/QA only. Live domains: territory, structures, agents, bombers, wallet (**roads retired under R1**).
4. **Units** — Soldiers (barracks, Au+Ve upkeep) and bombers (hangars, spawn Au+Em, no continuous upkeep). Caps: 5 per structure, 100 global each.
5. **Oceans** — soldier ferry + beachhead claim (no land bridges).

## Godot version story (C12 / G2)

| Source | Value | Meaning |
|--------|-------|---------|
| `project.godot` `config/features` | `4.7` | Project feature tag |
| Day-to-day QA / Steam tools path | **4.6+** | Practical editor target in QA_LIFECYCLE |
| Rust gdext | Godot 4.x master line | Rebuild DLL after engine upgrades |

Treat **Godot 4.6+ with a matching `empire_territory` DLL** as the live development target. Do not invent separate product SKUs from metadata fields alone. Full write-up: [DESIGN.md](../DESIGN.md) § Godot version story.

## Design locks (short index)

See [DESIGN.md](../DESIGN.md) § Design locks for full text. IDs: **A13/F1** enemy AI outposts only; **A14** bomber no continuous upkeep; **F5** win ignores units; **F6** unit caps; **F7** shockwave visual cap (full economy credit); **R1** roads+bridges removed; **R2** ferry water 0.25× speed. Legacy F2–F4 superseded by R1.

**Direction (locked):** roads & land bridges removed — instant structure build, miners on owned deposits, no strain, pressure on any owned land, soldier ferry for oceans — [DESIGN.md](../DESIGN.md) § Direction — roads & bridges removed.

## Related paths

- Config constants: `WorldConquestConfig.gd`
- Economy registry: `EconomyCatalog.gd` / `EconomyLib.gd`
- Live asserts: `WorldDatasetAssert.gd`
- Extension crate: `rust/empire_territory/`
