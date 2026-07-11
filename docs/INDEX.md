# Documentation index — Empires of Yesterday

World Conquest is the only game mode: fluid territory conquest on a 360×180 Earth globe with multi-structure logistics and units.

## Canonical docs

| Doc | Contents |
|-----|----------|
| [DESIGN.md](../DESIGN.md) | Fantasy, controls, dictionary, structures/units, map gen, **WorldDataset + PresentationTxn** architecture, **design locks**, Godot version story |
| [PERFORMANCE.md](../PERFORMANCE.md) | Frame budgets, PresentationTxn, MultiMesh roads, construction drain order, catch-up cap, env knobs, F3 HUD |
| [RUST.md](../RUST.md) | Build GDExtension, authority module list, TerritorySim API, env vars |
| [QA_LIFECYCLE.md](../QA_LIFECYCLE.md) | When/how to run headless QA and smoke tests |
| [README.md](../README.md) | Quick start, play summary, Rust requirement for live |
| [REQUEST_SCD1_VERSIONED_PULL.md](REQUEST_SCD1_VERSIONED_PULL.md) | **Proposal:** SCD1 main tables + domain monotonic pulls; full snaps only at start/gap |

## Architecture snapshot (live Play)

1. **Map gen** — `WorldConquestMapGenerator.generate(map_id, seed)` (primary). `EarthMapGenerator` is a thin wrapper for default Earth.
2. **Authority** — Rust WorldDataset (grid, structures, world session, logistics, resource wallet).
3. **Presentation** — SCD1 per-domain versioned pulls (`Scd1DomainPull` / `pull_domain_since`); apply-only. PresentationTxn is legacy/QA only.
4. **Units** — Soldiers (barracks, Aurelium upkeep) and bombers (hangars, no upkeep). Caps: 5 per structure, 100 global each.

## Godot version story (C12 / G2)

| Source | Value | Meaning |
|--------|-------|---------|
| `project.godot` `config/features` | `4.7` | Project feature tag |
| Day-to-day QA / Steam tools path | **4.6+** | Practical editor target in QA_LIFECYCLE |
| Rust gdext | Godot 4.x master line | Rebuild DLL after engine upgrades |

Treat **Godot 4.6+ with a matching `empire_territory` DLL** as the live development target. Do not invent separate product SKUs from metadata fields alone. Full write-up: [DESIGN.md](../DESIGN.md) § Godot version story.

## Design locks (short index)

See [DESIGN.md](../DESIGN.md) § Design locks for full text. IDs: **A13/F1** enemy AI outpost+bridge only; **A14** bomber no upkeep; **F2** player standalone outpost fallback; **F3** logistics strain subtle; **F4** logistics owns roads; **F5** win formula ignores units; **F6** unit caps; **F7** haul visual cap.

## Related paths

- Config constants: `WorldConquestConfig.gd`
- Economy registry: `EconomyCatalog.gd` / `EconomyLib.gd`
- Live asserts: `WorldDatasetAssert.gd`
- Extension crate: `rust/empire_territory/`
