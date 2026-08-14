# Empires of Yesterday — World Conquest

Fluid territory-conquest strategy on a 3D Earth globe (**Godot 4.6+**, project features tag 4.7). Two empires pump colored pressure across a height-mapped world; the fronts meet, cancel, and flow like water. You expand with **outposts**, **barracks**, and **hangars**, field **soldiers** and **bombers**, mine strategic minerals from owned deposits, and cross oceans with **soldier ferry**.

## Requirements for live play

- **Godot 4.6+** editor/export that can load the project (see [DESIGN.md](DESIGN.md) § Godot version story).
- **Rust GDExtension** built and installed (`empire_territory` DLL). Live World Conquest uses the **WorldDataset** authority path — presentation is apply-only via **SCD1 domain pulls**. Without the extension loaded, Play does not run the intended live contract.

```powershell
.\setup_rust.ps1
```

See [RUST.md](RUST.md) for build details.

## How to play

1. **Main Menu → Play** — pick a **theater** (Earth / Pangea / Archipelago) then generate a random run (fixed seed via `RunState.run_seed`). **Custom World…** starts from a theater preset and lets you tweak seed + land/resource/mountain criteria before Generate & Play.
2. Your capital (blue) and the enemy capital (red) pump pressure continuously.
3. Earn **Supply** from owned tiles (starts at 800; income is slow — a blob funds buildings, not a spray). Spend it on:
   - **Outpost (400)** — forward pressure pump; place on any land except enemy-held tiles. **Builds instantly.** Click a placed outpost to set **Pump / Drain / Battery**; **Surge** dumps a Battery tank as one wave.
   - **Barracks (400)** — spawns **soldiers** (Aurelium + Verdantite spawn; Au+Ve upkeep).
   - **Hangar (400)** — spawns **bombers** (Aurelium + Emberstone spawn; no continuous upkeep).
4. Own **Aurelium / Verdantite / Emberstone** deposits — miners appear and pulse when the deposit is in your territory.
5. Cross oceans with **soldiers** (ferry at 1/4 land speed); landings open beachhead claimable land. **Paint** a coast to rally ferries, or inland land to aim bombers.
6. Win by owning all reachable land or draining enemy **pressure** to zero (units do not change the win formula).

### Controls

- **Right-drag** rotate globe, **wheel** zoom
- **Left-click** place structure (with a build button armed), **Esc** cancel
- **Outpost / Barracks / Hangar** arm placement; **Inspect** tile inspector
- **Paint** — arm a rally pin (coast = soldier beachhead, inland = bomber strike)
- Click a friendly **Outpost** then **Mode** (Pump / Drain / Battery) and **Surge**
- **Pause** / **▶ x1** speed controls
- **F3** — toggle perf HUD (FPS, CPU/GPU counters, sim/overlay context); see [PERFORMANCE.md](PERFORMANCE.md)

## Headless QA

```powershell
# Full QA (script/scene loads, sim goldens, Rust parity, WorldDataset asserts, ferry gate)
godot --headless --path . res://qa_runner.tscn

# Ferry beachhead smoke (filename legacy: was bridge invasion)
godot --headless --path . -s res://bridge_invasion_smoke_test.gd

# Instant place / island visual smoke
godot --headless --path . -s res://island_outpost_smoke_test.gd

# Soldier nav (land march; ferry covered by beachhead smoke)
godot --headless --path . -s res://soldier_nav_smoke_test.gd
```

## Docs

- [docs/INDEX.md](docs/INDEX.md) — documentation index
- [DESIGN.md](DESIGN.md) — mechanics, terminology, architecture, design locks
- [PERFORMANCE.md](PERFORMANCE.md) — sim performance notes and knobs
- [RUST.md](RUST.md) — building the Rust territory backend
- [QA_LIFECYCLE.md](QA_LIFECYCLE.md) — when/how to run QA

Session logs are written to `logs/latest_run.txt` (path printed at startup).
