# Empires of Yesterday — World Conquest

Fluid territory-conquest strategy on a 3D Earth globe (Godot 4.6+). Two empires pump colored pressure across a height-mapped world; the fronts meet, cancel, and flow like water. No units — the territory is the army.

## How to play

1. **Main Menu → Play** — generates a random Earth run (fixed seed via `RunState.run_seed`).
2. Your capital (blue) and the enemy capital (red) pump pressure continuously.
3. Earn **Supply** from owned tiles. Spend it on:
   - **Outpost (400)** — forward pressure pump; place on any land except enemy-held tiles. It links to your network by road, then builds.
   - **Land Bridge (250)** — water crossing to a foreign coast; conducts pressure and acts as a road.
4. Win by owning all reachable land or draining enemy power to zero.

### Controls

- **Right-drag** rotate globe, **wheel** zoom
- **Left-click** place structure (with a build button armed), **Esc** cancel
- **Pause** / **▶ x1** speed controls, **Inspect** tile inspector
- **F3** — toggle perf HUD (FPS, CPU/GPU counters, sim/overlay context); see [PERFORMANCE.md](PERFORMANCE.md)

## Headless QA

```powershell
# Full QA (script/scene loads, sim goldens, Rust parity)
godot --headless --path . res://qa_runner.tscn

# Bridge/outpost routing smoke
godot --headless --path . -s res://bridge_invasion_smoke_test.gd
```

## Docs

- [DESIGN.md](DESIGN.md) — mechanics, terminology, architecture
- [PERFORMANCE.md](PERFORMANCE.md) — sim performance notes and knobs
- [RUST.md](RUST.md) — building the Rust territory backend
- [QA_LIFECYCLE.md](QA_LIFECYCLE.md) — when/how to run QA

Session logs are written to `logs/latest_run.txt` (path printed at startup).
