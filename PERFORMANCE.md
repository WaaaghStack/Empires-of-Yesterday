# Performance tuning — Empires of Yesterday (World Conquest)

Runtime budgets and knobs for the 360×180 Earth territory sim. Canonical mechanics: [DESIGN.md](DESIGN.md).

---

## Frame budgets (60 FPS target)

| Subsystem | Target |
|-----------|--------|
| Territory sim (all steps in one frame) | < 6 ms |
| Ownership overlay CPU + texture upload | < 2 ms |
| Globe GPU render | < 8 ms |
| HUD / soldiers / resources | < 2 ms |
| **Total** | < 16 ms sustained, p99 < 16 ms |

Engine: `Engine.max_fps = 60`, vsync on (`project.godot`).

## Sim budgets

| Path | Target |
|------|--------|
| World Conquest live step (Rust backend) | < 8 ms/step (`BATTLE_WORLD_CONQUEST_BENCH=1` gate in `qa_runner.gd`) |
| World Conquest 60 Hz frame (sim + overlay FFI) | p99 < 16 ms, min FPS ≥ 58 (`BATTLE_FPS_BENCH=1`) |
| CPU resolve, 96×72 fixture | `resolve_ms < 3000` (legacy QA gate) |
| Overlay refresh (pressure mode) | `OVERLAY_UPDATES_PER_SEC` = 3 Hz |
| Soldier dot refresh | `SOLDIER_VISUAL_UPDATES_PER_SEC` = 4 Hz |
| Sim stepping | `SIM_DT` = 1/14 s, ≤ `SIM_MAX_STEPS_PER_FRAME` (4) per frame |

## Territory sim optimizations (in place)

| Optimization | File | Effect |
|--------------|------|--------|
| **Rust GDExtension backend** (default when loaded) | `BattleTerritoryRustBackend.gd`, `rust/empire_territory/` | Full-grid propagation in native code; state syncs back per step |
| Frontier **active-set** sim (rebuild every 3 rounds or on frontier change) | `BattleTileControl.gd` | Avoids full 64 800-tile scan per round |
| Ping-pong pressure buffers, fixed 4-neighbor scratch | `BattleTileControl.gd` | No allocations in the flow inner loop |
| Cancel pass on active tiles only | `BattleTileControl.gd` | Cheaper overlap pass as fronts grow |
| Incremental ownership / conquest counts | `BattleTileControl.gd`, `BattleTerritorySim.gd` | No full-grid recount per round |
| **Frame-budgeted construction queue** | `OutpostConstructionQueue.gd`, `WorldConquestScreen._drain_outpost_construction_queue` | `_advance_outpost_construction` only enqueues; drain processes ≤1 road/corridor/marker sid per frame via `sync_bridge_corridors_for_sids` (no full-map sync) |
| Bridge → backend claimable sync throttled | `WorldConquestConfig.BRIDGE_BACKEND_SYNC_INTERVAL_SEC` (0.2 s) | Legacy interval; construction drain replaces time-based flush for CONNECTING growth |
| **Fast owner visual on backend sync** | `WorldConquestScreen._apply_owner_visual_from_backends` | Uses Rust `get_owner_display_r8` bytes path instead of 65k GDScript overlay loop |
| **Incremental owner sync (Rust)** | `sync_owners_delta`, `BattleTerritoryRustBackend._apply_owners_delta_to_tile_control` | Only changed owner cells cross FFI each sim batch |
| **Option A pressure pull** | `get_pressure_*` at overlay tick only | ~518 KB pressure FFI avoided per sim step |
| **Incremental owner overlay (Rust live)** | `consume_owner_overlay_delta` + `apply_ownership_overlay_delta` | One batched delta upload per frame; `set_data` not per-pixel |
| **Unified visual drain queue** | `OutpostConstructionQueue`, `WorldConquestScreen._drain_outpost_construction_queue` | Ordered drain: corridors → beachhead → roads → markers → overlay (≤`OVERLAY_DELTA_CELLS_PER_FRAME`) → gpu (never same frame as roads/markers/overlay; gpu blocked N+1 after overlay) |
| **Overlay delta enqueue** | `WorldConquestScreen._enqueue_ownership_overlay_delta` | Consumes Rust delta into queue; apply happens in drain, not inline in `_process` |
| **Deferred owner GPU upload** | `OutpostConstructionQueue.request_gpu_upload`, `EarthGlobeMap.flush_pending_owner_gpu_upload` | GPU commit only via queue drain slot; respects `OVERLAY_GPU_UPLOAD_MAX_HZ` |
| **Budget-aware sim catch-up** | `FrameBudgetProfiler.budget_allows_catchup`, `WorldConquestScreen._process` | Caps `advance_dt` to 1 step when prior frame exceeded `FRAME_BUDGET_MS` (16 ms) |
| **Incremental roads/markers** | `EarthGlobeMap.sync_roads(changed_sids)`, `refresh_connecting_markers` | Path cell growth syncs only dirty structure ids; pulse refresh touches connecting/building markers only |
| **Precomputed border mask** | `EarthGlobeMap._border_bytes_cache`, `ownership_display.gdshader` | 2 texture fetches per fragment instead of 9 |
| **Spawner FFI cache** | `BattleTerritoryRustBackend._maybe_update_spawners` | Skips `update_spawners` when placed spawners unchanged |
| **GPU fluid shader** | `shaders/globe/fluid_display.gdshader`, `EarthGlobeMap.apply_fluid_from_pressures_gpu` | No CPU `bake_fluid_rgba` on live path; camera-facing tex upload |
| **Incremental active set** | `TerritoryKernel.patch_active_indices`, `BattleTileControl._patch_active_indices` | Patches frontier tiles instead of full 64k scan when dirty set is small |
| **Claimable delta sync** | `update_claimable_delta`, `BattleTileControl.take_claimable_dirty_indices` | Bridge extend sends changed cells only |
| **Batched soldier aura** | `AgentLayer.apply_batched_aura` | One capped pressure add per tile per team per step |
| **Stamped soldier BFS** | `AgentLayer.plan_march_route` | Generation-stamped visit marks — no full-grid `fill` per replan |
| **Budgeted soldier replans** | `AgentLayer.run_budgeted_replans` | Cap BFS replans per tick; urgent stuck slots reserved |
| **Frontier-stale replans** | `TerritoryKernel.nav_dirty_stamp` | Replan only when ownership/claimable/nav masks change near agent |
| **Portal route graph** | `RoutePlanner` + `PortalGraph` | Rebuild on outpost/bridge change; scoped BFS per click |
| **Async route worker** | `RoutePlanner` background thread | Placement/hover pathfind off main thread |
| **Rust gradient in-place** | `sim.rs gradient_flow_pass_into` | No per-pass full-grid buffer clones |
| **Agent snapshot buffer reuse** | `TerritorySim.agent_snap_*` in `lib.rs` | Reuses Vec buffers across 4 Hz visual ticks |
| **SubViewport when visible** | `WorldConquestScreen` `UPDATE_WHEN_VISIBLE` | Skips 3D render when play area hidden |
| **Surface position LUT** | `EarthGlobeMap._surface_lut` | Soldiers/markers/roads skip per-frame trig |
| **Road/link segment pools** | `EarthGlobeMap._road_seg_pool`, `_link_seg_pool` | Reuses `MeshInstance3D` nodes |
| **Dirty-flag maintenance** | `WorldConquestScreen._has_active_construction`, `_bridges_repaired` | Skips outpost/bridge loops when idle |
| **Frame phase profiler** | `FrameBudgetProfiler.gd` | Always samples `_process` ms for F3 HUD; spike logging when `BATTLE_FRAME_BUDGET_LOG=1` |
| Globe meshes coarser than sim grid | `GLOBE_MESH_W/H` 144×72, `FLUID_MESH_W/H` 180×90 | GPU budget independent of sim resolution |
| GPU compute backend (optional) | `BattleTerritoryGpuField.gd`, `shaders/territory/*.glsl` | Flow on GPU; throttled owner readback; skips `pack_display` when owners-only |

## Placement / routing responsiveness

- `OUTPOST_PATHFIND_MAX_EXPAND` (12 000) caps route floods; hover preview uses greedy-only (`OUTPOST_HOVER_ALLOW_ASTAR=false`), replans at most every `OUTPOST_HOVER_REPLAN_SEC` (0.32 s), and draws ≤ `OUTPOST_PREVIEW_MAX_SEGMENTS` (48) 3D segments.
- Land-component IDs are precomputed once per map (`prepare_land_components`) so placement prechecks never flood-fill.
- Resource haul visuals capped at `RESOURCE_MAX_VISUAL_PULSES` (36); economy still credits all yield.

## Environment variables

| Env | Effect |
|-----|--------|
| `BATTLE_TERRITORY_BACKEND` | `rust` (default if loaded) / `gpu` / `cpu` |
| `BATTLE_PERF_LOG=1` | Per-phase sim timers via `BattlePerfProfiler` |
| `BATTLE_FRAME_BUDGET_LOG=1` | >16 ms spike logs via `FrameBudgetProfiler` (sampling always on for F3 CPU line) |
| `BATTLE_WORLD_CONQUEST_BENCH=1` | QA bench gate (60 sim-sec, fails > 8 ms/step) |
| `BATTLE_FPS_BENCH=1` | QA 60 Hz frame gate (120 sim-sec, p99 ≤ 16 ms, min FPS ≥ 58) |
| `BATTLE_RUST_COMPARE=0` | Skip the default Rust-vs-CPU parity QA check |

## Live debug HUD (F3)

During World Conquest play, press **F3** to toggle a perf overlay (top-right) showing:

- **FPS** (engine counter)
- **CPU** — `FrameBudgetProfiler` p50 / p95 / p99 ms for `WorldConquestScreen._process` (not SubViewport GPU render)
- **GPU** — draw calls, objects in frame, video/texture memory (`Performance` monitors)
- **Action context** — last sim steps, ownership overlay delta size, pending owner GPU upload flag

Off by default. HUD text is assembled by `WorldConquestScreen.perf_build_hud_text()` from `gather_perf_and_action_context()`.

CPU samples exclude the loading screen: `_process` returns before `begin_frame()` while `_loading`, then `reset_samples()` runs once bootstrap completes.

## Action-tagged RunLog lines

Hot paths emit `RunLog.info` / `warn` lines with an `action=` prefix plus fps/cpu/gpu counters, for example:

| Tag | When |
|-----|------|
| `action=sim` | Sim advanced (`steps=N`) — throttled ~2 s |
| `action=overlay:delta` | Incremental owner overlay patch (`cells=N`) |
| `action=resources` | Resource tick with pulses or link dirty |
| `action=gpu_upload` | Pending owner texture flush committed |
| `action=roads` | Road mesh sync |
| `action=markers` | Structure marker refresh |
| `action=fps_drop` | Sustained FPS &lt; 42 (existing drop watcher) |

Written to `logs/latest_run.txt` with the usual 0.25 s batch flush.

`FrameBudgetProfiler` phases (when `BATTLE_FRAME_BUDGET_LOG=1`): `sim`, `overlay`, `resources`, `roads`, `markers`, `gpu_upload`, plus existing `spawner_sync`, `outpost`, `bridge`, `soldiers`.

## RunLog I/O

Session logs batch-flush every **0.25 s** (immediate on window close), max **10 000** lines per session. Engine `print()` capture only in verbose mode (`RunLog.set_verbose(true)`).

## Known costs to watch

- `build_replay_tape(-1)` on the world map runs a full battle and can take many minutes — always pass a round cap in tests (QA bake compare uses 64).
- `operational_sources` now includes bridge landings; if bridge counts grow large, watch multi-source BFS cost in `nearest_path_to_target`.
- Owner readback from GPU backend is throttled via `readback_owners_if_due` (every 4 rounds on large maps); HUD counters mirror sim-side counts.
- Soldier march uses greedy steps toward a cached goal. BFS replans are **budgeted** (`SOLDIER_REPLANS_PER_TICK`), **frontier-triggered** (`nav_dirty_stamp`), with a long fallback interval (`SOLDIER_REPLAN_FALLBACK_ROUNDS`).