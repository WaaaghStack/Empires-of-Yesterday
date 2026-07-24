# Rust GDExtension Integration (Empires of Yesterday)

This document describes how to build and use the Rust native extension that accelerates territory conquest simulation, world session (structures/units), logistics, presentation transactions, replay fluid bake, pressure codec, and tape packing.

## Current Status

- **Location:** `rust/empire_territory/`
- **Godot class:** `TerritorySim` (RefCounted GDExtension)
- **Packaging:** DLLs in `rust/empire_territory/bin/`, wired by `empire_territory.gdextension`
- **Live Play contract:** WorldDataset authority + **SCD1 domain versioned pulls** (see DESIGN.md and `docs/REQUEST_SCD1_VERSIONED_PULL.md`). Live World Conquest expects this extension loaded. PresentationTxn is **not** the live paint path.

### Authority modules (`rust/empire_territory/src/`)

| Module | Role |
|--------|------|
| `lib.rs` | GDExtension entry, `TerritorySim` FFI surface (`pull_domain_since`, `scd1_*`) |
| `domain_version.rs` | Per-domain epochs, gap full-pull allow-list + cooldown policy |
| `sim.rs` | Territory kernel — gradient flow, inject, active-set / full-grid |
| `structures.rs` | Structure store (outpost, barracks, hangar, corridor) + row `version` |
| `world_session.rs` | Build timers, construction damage, barracks/hangar spawns, soldier upkeep tick |
| `agents.rs` | Soldiers — march, aura, caps + row `version` |
| `bombers.rs` | Bombers — strike plans, bomb, caps + row `version` |
| `logistics.rs` | Shared road network, strain, path completion (replaces builder bots as authority) |
| `builders.rs` | Legacy builder-agent path (presentation / compatibility; logistics owns live roads) |
| `economy.rs` | Content tables (costs, drains, caps) mirrored from EconomyCatalog |
| `resources.rs` | Resource wallet / haul credit authority |
| `presentation_txn.rs` | **Legacy** change feed (QA only — not live Play paint) |
| `world_edit.rs` | Structure placement / edit helpers under authority |
| `route.rs` + `pathfind/` | Route planner, nav rules, battle nav |
| `grid_query.rs` | Grid lookups for FFI / queries |
| `fluid_bake.rs` | Replay display RGBA bake |
| `tape_codec.rs` | Pressure v2 + EYTR v2 pack body |

### Live SCD1 pull API (Godot)

| Method | Role |
|--------|------|
| `pull_domain_since(domain, last_version, force_full)` | Full current rows with `version > last` (or full domain if `force_full` / start). Structures also emit `removed_ids` (tombstones) and `bridge_corridors` on full/incremental packs |
| `scd1_domain_epoch(domain)` | High-water for domain |
| `scd1_sim_generation()` | Match generation (resets force seed) |
| `scd1_decide_full_pull(...)` | Allow-list reason or empty (incremental) |
| `scd1_note_full_pull(reason)` | Cooldown + `FULL_RESYNC` log |

Domains: `territory`, `structures`, `roads`, `agents`, `bombers`, `wallet`. Client: `Scd1DomainPull.gd` (per-domain full-pull cooldown; rewinds `last_version` on full seed / sim_generation). Harness: `scd1_version_pull_harness.gd`.

**Authority split:** Rust is the sim engine (mutations, pathing, domain epochs). Godot is visualization only (SCD1 apply, billboards, overlays). `pull_presentation_txn` is **legacy/QA only** — not live Play paint.

### Backend defaults (when extension is loaded)

| Context | Default | Override |
|---------|---------|----------|
| World Conquest live sim | Rust (WorldDataset) | `BATTLE_TERRITORY_BACKEND=cpu` or `gpu` (QA/harness only; GPU live fails WorldDataset assert) |
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

Other methods (selection):

- `get_owners()`, `get_pressure_friendly()`, `get_pressure_hostile()`
- `pull_presentation_txn` / presentation delta consumers (live paint path)
- `world_session_tick(dt, friendly_aurelium)` — structures + unit spawns under WorldDataset
- `try_spawn_agent` / `try_spawn_bomber`, structure snapshots
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
- Constants in `sim.rs` / `fluid_bake.rs` / economy tables should match `BattleTileControl.gd` / `WorldConquestConfig.gd` / `EconomyCatalog.gd` for parity.
- Resolve path expects **0 owner mismatches** vs CPU; active-set live path allows ≤8 tile drift (same as CPU active-set QA).
- After Godot editor upgrades, rebuild gdext against the same major line (see DESIGN.md Godot version story).

## References

- `DESIGN.md` — mechanics, WorldDataset architecture, design locks
- `BattleTileControl.gd` — GDScript reference sim (QA)
- `BattleTileFluidField.gd` — fluid bake reference
- `qa_runner.gd` — benches and golden tests
- `PERFORMANCE.md` — territory perf program notes
- `docs/INDEX.md` — doc map
