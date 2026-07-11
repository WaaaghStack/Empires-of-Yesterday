# Empires of Yesterday — World Conquest

Fluid territory-conquest strategy on a 3D Earth globe (**Godot 4.6+**, project features tag 4.7). Two empires pump colored pressure across a height-mapped world; the fronts meet, cancel, and flow like water. You expand with **outposts**, **land bridges**, **barracks**, and **hangars**, field **soldiers** and **bombers**, and haul strategic minerals over a **logistics road** network.

## Requirements for live play

- **Godot 4.6+** editor/export that can load the project (see [DESIGN.md](DESIGN.md) § Godot version story).
- **Rust GDExtension** built and installed (`empire_territory` DLL). Live World Conquest uses the **WorldDataset** authority path — presentation is apply-only via **PresentationTxn**. Without the extension loaded, Play does not run the intended live contract.

```powershell
.\setup_rust.ps1
```

See [RUST.md](RUST.md) for build details.

## How to play

1. **Main Menu → Play** — generates a random Earth run (fixed seed via `RunState.run_seed`).
2. Your capital (blue) and the enemy capital (red) pump pressure continuously.
3. Earn **Supply** from owned tiles. Spend it on:
   - **Outpost (400)** — forward pressure pump; place on any land except enemy-held tiles. It links to your network by road, then builds.
   - **Barracks (400)** — spawns **soldiers** (Aurelium spawn cost + upkeep).
   - **Hangar (400)** — spawns **bombers** (Aurelium spawn cost; no continuous upkeep).
   - **Land Bridge (250)** — water crossing to a foreign coast; conducts pressure (flow mult **2.8**) and acts as a road.
4. Own **Aurelium / Verdantite / Emberstone** deposits to fund units and logistics.
5. Win by owning all reachable land or draining enemy **pressure** to zero (units do not change the win formula).

### Controls

- **Right-drag** rotate globe, **wheel** zoom
- **Left-click** place structure (with a build button armed), **Esc** cancel
- **Outpost / Barracks / Hangar / Land Bridge** arm placement; **Inspect** tile inspector
- **Pause** / **▶ x1** speed controls
- **F3** — toggle perf HUD (FPS, CPU/GPU counters, sim/overlay context); see [PERFORMANCE.md](PERFORMANCE.md)

## Headless QA

```powershell
# Full QA (script/scene loads, sim goldens, Rust parity, WorldDataset asserts)
godot --headless --path . res://qa_runner.tscn

# Bridge/outpost routing smoke
godot --headless --path . -s res://bridge_invasion_smoke_test.gd
```

## Docs

- [docs/INDEX.md](docs/INDEX.md) — documentation index
- [DESIGN.md](DESIGN.md) — mechanics, terminology, architecture, design locks
- [PERFORMANCE.md](PERFORMANCE.md) — sim performance notes and knobs
- [RUST.md](RUST.md) — building the Rust territory backend
- [QA_LIFECYCLE.md](QA_LIFECYCLE.md) — when/how to run QA

Session logs are written to `logs/latest_run.txt` (path printed at startup).
