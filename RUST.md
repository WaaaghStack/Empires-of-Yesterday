# Rust GDExtension Integration (Empires of Yesterday)

This document describes how to build and use the Rust native extension that accelerates territory conquest simulation, replay fluid bake, pressure codec, and tape packing.

## Current Status

- **Location:** `rust/empire_territory/`
- **Godot class:** `TerritorySim` (RefCounted GDExtension)
- **Modules:** `sim.rs` (simple-water kernel + active-set), `fluid_bake.rs` (replay display RGBA), `tape_codec.rs` (pressure v2 + EYTR v2 pack body)
- **Packaging:** DLLs in `rust/empire_territory/bin/`, wired by `empire_territory.gdextension`

### Backend defaults (when extension is loaded)

| Context | Default | Override |
|---------|---------|----------|
| World Conquest live sim | Rust | `BATTLE_TERRITORY_BACKEND=cpu` or `gpu` |
| `build_replay_tape` (QA resolve) | Rust | `BATTLE_TERRITORY_BACKEND=cpu` forces GDScript |

Live Rust sim uses **active-set** gradient (faster) and skips the adaptive second gradient pass. Resolve uses **full grid** plus adaptive double-pass when the frontier moves enough — for exact parity with CPU golden tests.

Optional `use_adaptive_double_pass` in `setup_from_dict` (defaults to `!use_active_set`). The `BATTLE_RUST_ACTIVE_COMPARE` QA test disables it on both sides so it measures active-set gradient drift only.

## Prerequisites (Windows)

```powershell
winget install -e --id Rustlang.Rustup
```

After install, open a new terminal:

```powershell
rustc --version
cargo --version
rustup default stable
```

## Build & install

From the repo root:

```powershell
.\setup_rust.ps1
```

This runs `cargo build` (debug + release) and copies DLLs into `rust\empire_territory\bin\` with the names Godot expects.

Manual build:

```powershell
cd rust\empire_territory
cargo build --release
```

On corporate networks with SSL issues:

```powershell
$env:CARGO_HTTP_CHECK_REVOKE = "false"
.\setup_rust.ps1
```

**Important:** `.gdextension` files only support `;` comments — `#` breaks Godot ConfigFile parsing.

## Smoke test

```powershell
godot --headless --path . -s res://bridge_invasion_smoke_test.gd
```

Or: `.\setup_rust.ps1 -RunSmokeTest`. The Rust section of the smoke test logs a WARN if the GDExtension is not loaded.

## TerritorySim API (GDScript)

Setup via dictionary (avoids >15 FFI parameters):

```gdscript
var sim := TerritorySim.new()
sim.setup_from_dict({
    "grid_w": map.grid_width,
    "grid_h": map.grid_height,
    "claimable": tile_control.claimable_mask,
    # ... elevation, flow_mult, owners, pressures, spawners, use_active_set, etc.
})
sim.advance_round()           # one round
sim.advance_rounds(4)         # batch (resolve / tape)
var synced := sim.sync_into_tile_control()  # owners, pressures, tile counts
```

Other methods:

- `get_owners()`, `get_pressure_friendly()`, `get_pressure_hostile()`
- `bake_fluid_rgba(w, h, land_mask, pf, ph, power_scale)` → `PackedByteArray` RGBA8
- `bake_fluid_frames_parallel(frames_array)` → parallel batch bake (rayon)
- `encode_pressure_v2(pressure)`, `decode_pressure_v2(blob)`
- `pack_territory_tape_from_dict(meta_dict)` → EYTR v2 packed tape bytes

GDScript bridges: `BattleTerritoryRustBackend.gd`, hooks in `BattleTerritoryReplayBake.gd`, `BattleTilePressureCodec.gd`, `BattleReplayPack.gd`.

## Environment variables

| Variable | Effect |
|----------|--------|
| `BATTLE_TERRITORY_BACKEND` | `cpu`, `gpu`, or `rust` (see defaults above) |
| `BATTLE_RUST_COMPARE=0` | QA: skip the Rust vs CPU owner parity check (runs by default when the DLL is loaded) |
| `BATTLE_RUST_BAKE_COMPARE=1` | QA: Rust fluid bake vs GDScript byte compare |
| `BATTLE_RUST_ACTIVE_COMPARE=1` | QA: Rust active-set vs full-grid (≤8 tile drift OK) |
| `BATTLE_GPU_COMPARE=1` | QA: GPU vs CPU (unchanged) |

## QA

```powershell
godot --headless --path . res://qa_runner.tscn
```

The Rust vs CPU owner parity check (16 rounds, world map, exact match) runs by default when the extension is loaded. Optional env-gated checks: `BATTLE_RUST_BAKE_COMPARE=1`, `BATTLE_RUST_ACTIVE_COMPARE=1`, `BATTLE_WORLD_CONQUEST_BENCH=1`. See `QA_LIFECYCLE.md`.

## Development tips

- Reload: close Godot, rebuild, reopen (or use GDExtension reload if your editor supports it).
- `cargo check` for fast type-checking without linking a DLL.
- Constants in `sim.rs` / `fluid_bake.rs` should match `BattleTileControl.gd` / `BattleTileFluidField.gd` for parity.
- Resolve path expects **0 owner mismatches** vs CPU; active-set live path allows ≤8 tile drift (same as CPU active-set QA).

## References

- `DESIGN.md` §4 — hydrostatic territory model
- `BattleTileControl.gd` — GDScript reference sim
- `BattleTileFluidField.gd` — fluid bake reference
- `qa_runner.gd` — benches and golden tests
- `PERFORMANCE.md` — territory perf program notes
