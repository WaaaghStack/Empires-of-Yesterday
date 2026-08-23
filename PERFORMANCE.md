# Performance tuning — Empires of Yesterday (World Conquest)

Runtime budgets and knobs for the 360×180 Earth territory sim. Canonical mechanics: [DESIGN.md](DESIGN.md). Doc index: [docs/INDEX.md](docs/INDEX.md).

## Live authority pipeline (must stay cheap)

Live Play is **WorldDataset in Rust** (sim engine) + **SCD1 domain versioned pulls** on the Godot side (visualization only — apply-only, not dual-sim):

| Concern | Live behavior | Where |
|---------|---------------|--------|
| **SCD1 domain pulls** | Per-domain `pull_domain_since` rows with `version > last`; full seed only at start / allow-listed gap; structure tombstones via `removed_ids`. Live domains: territory, structures, agents, bombers, wallet (**roads retired — R1**) | `domain_version.rs`, `Scd1DomainPull.gd`, `WorldConquestScreen._flush_live_presentation_delta` |
| **Live owner paint** | Owners only via SCD1 `territory` apply — no live `get_owner_display_r8` / overlay-delta / owner-reconcile. Depth tint is display-only | `WorldConquestScreen._apply_scd1_territory`, `_scd1_repaint_territory` |
| **Live structures** | Place/destroy = Rust `structure_store_*` command, then SCD1 `structures` pull. `placed_structures` is apply-only cache under live — no pre-merge / no Godot→Rust `sync_structure_store_from_map` / no `_placed_spawners` push | `_commit_placed_structure`, `_pull_structure_render_cache`, `sync_spawners_from_structure_store` |
| **Roads MultiMesh** | **R1 retired** — `sync_roads` / `_setup_road_multimeshes` are no-ops (no ribbon paint) | `EarthGlobeMap.sync_roads` |
| **Sim catch-up cap** | When prior frame > `FRAME_BUDGET_MS` (16 ms), cap catch-up to **1** sim step | `FrameBudgetProfiler.budget_allows_catchup`, `WorldConquestScreen._process` |
| **End-game FPS ladder** | Soft-cap tighten at >20 ms (8k) / critical at >28 ms (5k); **sticky hysteresis** — once lowered, requires `SOFT_CAP_HEALTHY_FRAMES_TO_RAISE` (45) consecutive frames with prior ≤ `FRAME_BUDGET_MS` before raising to 24k; while soft-cap < DEFAULT, force `sim_max_steps ≤ 1` (no catch-up to 4); skip 1 sim frame at >28 ms (resume next); defer AI at >16 ms; skip markers/gpu/overlay/presentation on skip-sim frames | `WorldConquestConfig` `FRAME_MS_*` / `SOFT_CAP_*`, `WorldConquestScreen._process` / `_soft_cap_target_for_prior_ms` |
| **Construction drain order** | Ordered queue drain: beachhead → markers → overlay (≤`OVERLAY_DELTA_CELLS_PER_FRAME`) → gpu. Corridor/road slots idle under R1 | `OutpostConstructionQueue`, `WorldConquestScreen._drain_outpost_construction_queue` |
| **Unit replan FPS** | Path-block waits (no BFS); free-goal miss skip + soft goal claims; O(1) occupancy maps; ferry expand capped (`FERRY_MAX_EXPAND`); stuck replan backoff (`retarget_cd` never 0) | `agents.rs`, `bombers.rs`, `nav_rules.rs` |
| **Late FPS / ferry thrash** | Primary late-game collapse was pathfind ferry thrash as free tiles shrink (sim phase ~89→269 ms; ferry used `tile_count` ~64k; stuck set `retarget_cd=0`; `SOLDIER_REPLANS_PER_TICK=20`). Soft-cap tighten is secondary. Fixes: ferry expand 8k, replan budget 6, bomber expand max 12k, stuck backoff | `nav_rules.rs`, `WorldConquestConfig`, `agents.rs` |

Do not reintroduce PresentationTxn as the live paint path, per-step full pressure/R8 pulls, full structure snapshots every frame, or uncapped multi-step catch-up on live.

**Live owner paint (txn → SCD1):** under WorldDataset live, ownership visuals come only from SCD1 `territory` pulls (`_flush_live_presentation_delta` / `_scd1_repaint_territory`). Do not call `get_owner_display_r8`, `consume_owner_overlay_delta`, or overlay owner reconcile on the live path. Depth tint (`get_pressure_depth_r8`) is display-only and stays off the authority paint path.

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
| Mid-game presentation (12 structures, live screen) | p99 ≤ 20 ms always-on QA (`_validate_midgame_presentation_fps`) |
| CPU resolve, 96×72 fixture | `resolve_ms < 3000` (legacy QA gate) |
| Overlay refresh (ownership + depth R8) | `OVERLAY_UPDATES_PER_SEC` = 3 Hz — depth-tinted R8 upload; depth tint `OVERLAY_DEPTH_UPDATES_PER_SEC` = 0.25 Hz (every 4 s) |
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
| **Frame-budgeted construction queue** | `OutpostConstructionQueue.gd`, `WorldConquestScreen._drain_outpost_construction_queue` | Instant ACTIVE places enqueue markers/overlay only; corridor/road drains idle under R1 |
| Bridge → backend claimable sync throttled | `WorldConquestConfig.BRIDGE_BACKEND_SYNC_INTERVAL_SEC` (0.2 s) | Legacy interval; construction drain replaces time-based flush for CONNECTING growth |
| **Fast owner visual on backend sync** | `WorldConquestScreen._apply_owner_visual_from_backends` | Uses Rust `get_owner_display_r8` bytes path instead of 65k GDScript overlay loop |
| **Incremental owner sync (Rust)** | `sync_owners_delta`, `BattleTerritoryRustBackend._apply_owners_delta_to_tile_control` | Only changed owner cells cross FFI each sim batch |
| **Option A pressure pull** | `get_pressure_*` at overlay tick only (when `OVERLAY_OWNERS_ONLY` is false) | ~518 KB pressure FFI avoided per sim step |
| **Ownership-only pull contract** | `OVERLAY_OWNERS_ONLY` = true — owner R8 via `get_owner_display_r8` + deltas; depth tint via `get_pressure_depth_r8` at ≤0.25 Hz (`OVERLAY_DEPTH_TINT`); sim never waits on full pressure layers | `WorldConquestConfig`, `BattleTerritoryRustBackend` |
| **Active-set soft cap (tier-2)** | When over soft-cap (default `ACTIVE_SET_SOFT_CAP` / `SOFT_CAP_DEFAULT` = 24k), dry interiors pruned first; wet deep interiors pruned second — frontier/contested/tips protected. Godot may tighten to `SOFT_CAP_STRESS` (8k) or `SOFT_CAP_CRITICAL` (5k) via `set_active_set_soft_cap` when prior frame > `FRAME_MS_TIGHTEN_SOFT_CAP` / `FRAME_MS_SKIP_SIM`. Soft-cap is **sticky** (no raise until `SOFT_CAP_HEALTHY_FRAMES_TO_RAISE` healthy frames) so post-skip healthy `prior_ms` cannot snap back to 24k + 4-step catch-up. Rust enforces the runtime cap before every gradient pass. | `sim.rs` `enforce_active_set_soft_cap`, `TerritorySim.set_active_set_soft_cap`, `WorldConquestScreen._soft_cap_target_for_prior_ms` |
| **Incremental owner overlay (Rust live)** | `consume_owner_overlay_delta` + `apply_ownership_overlay_delta` | One batched delta upload per frame; `set_data` not per-pixel |
| **Unified visual drain queue** | `OutpostConstructionQueue`, `WorldConquestScreen._drain_outpost_construction_queue` | Ordered drain: beachhead → markers → overlay → gpu (corridor/road slots retired under R1) |
| **Overlay delta enqueue** | `WorldConquestScreen._enqueue_ownership_overlay_delta` | Consumes Rust delta into queue; apply happens in drain, not inline in `_process` |
| **Deferred owner GPU upload** | `OutpostConstructionQueue.request_gpu_upload`, `EarthGlobeMap.flush_pending_owner_gpu_upload` | GPU commit only via queue drain slot; respects `OVERLAY_GPU_UPLOAD_MAX_HZ` |
| **Budget-aware sim catch-up** | `FrameBudgetProfiler.budget_allows_catchup`, `WorldConquestScreen._process` | Caps `advance_dt` to 1 step when prior frame exceeded `FRAME_BUDGET_MS` (16 ms) |
| **End-game overload gates** | `WorldConquestScreen._process` | Sticky soft-cap + while lowered force ≤1 sim step; >16 ms: defer AI + skip construction drain on fat-sim frames; >20 ms: soft-cap ≤8k + skip overlay reconcile/depth + halve agent/bomber pulls; >28 ms: soft-cap 5k + skip sim 1 frame then resume (also skips AI/presentation/markers) |
| **Incremental markers** | `EarthGlobeMap.refresh_connecting_markers` | Pulse refresh touches building markers only (roads MultiMesh retired under R1) |
| **Road ribbons (3-lane)** | *(retired R1)* | `EarthGlobeMap.sync_roads` is a no-op |
| **Precomputed border mask** | `EarthGlobeMap._border_bytes_cache`, `ownership_display.gdshader` | 2 texture fetches per fragment instead of 9 |
| **Spawner FFI cache** | `BattleTerritoryRustBackend._maybe_update_spawners` | Skips `update_spawners` when placed spawners unchanged |
| **GPU fluid shader** | `shaders/globe/fluid_display.gdshader`, `EarthGlobeMap.apply_fluid_from_pressures_gpu` | No CPU `bake_fluid_rgba` on live path; camera-facing tex upload |
| **Incremental active set** | `TerritoryKernel.patch_active_indices`, `BattleTileControl._patch_active_indices` | Patches frontier tiles instead of full 64k scan when dirty set is small |
| **Claimable delta sync** | `update_claimable_delta`, `BattleTileControl.take_claimable_dirty_indices` | Beachhead / claimable extend sends changed cells only |
| **Batched soldier aura** | `AgentLayer.apply_batched_aura` | One capped pressure add per tile per team per step |
| **Stamped soldier BFS** | `AgentLayer.plan_march_route` | Generation-stamped visit marks — no full-grid `fill` per replan |
| **Budgeted soldier replans** | `AgentLayer.run_budgeted_replans` | Cap BFS replans per tick; urgent stuck slots reserved |
| **Frontier-stale replans** | `TerritoryKernel.nav_dirty_stamp` | Replan only when ownership/claimable/nav masks change near agent |
| **Portal route graph** | `RoutePlanner` + `PortalGraph` | Legacy placement planner; R1 Play placement is instant (no route gate) |
| **Async route worker** | `RoutePlanner` background thread | Placement/hover pathfind off main thread |
| **Rust gradient in-place** | `sim.rs gradient_flow_pass_into` | No per-pass full-grid buffer clones |
| **Agent snapshot buffer reuse** | `TerritorySim.agent_snap_*` in `lib.rs` | Reuses Vec buffers across 4 Hz visual ticks |
| **SubViewport when visible** | `WorldConquestScreen` `UPDATE_WHEN_VISIBLE` | Skips 3D render when play area hidden |
| **Surface position LUT** | `EarthGlobeMap._surface_lut` | Soldiers/markers skip per-frame trig |
| **Road/link segment pools** | *(retired R1)* | Road MultiMesh idle |
| **Incremental road MultiMesh** | *(retired R1)* | `sync_roads` no-op |
| **SCD1 domain pulls (live)** | `Scd1DomainPull.gd` + `pull_domain_since` | Rust main tables + per-domain epochs; Godot applies rows/tombstones only |
| **PresentationTxn (legacy/QA)** | `presentation_txn.rs` + `pull_presentation_txn` | Not live Play paint — QA/goldens only |
| **Event-driven route portals** | `WorldConquestScreen._ensure_route_portals_for_team` | Rebuild when versions or active team change — not on every place/pathfind |
| **Dirty-flag maintenance** | `WorldConquestScreen._has_active_construction`, `_bridges_repaired` | Skips idle construction loops; one-shot leftover corridor clear under R1 |
| **Frame phase profiler** | `FrameBudgetProfiler.gd` | Always samples `_process` ms for F3 HUD; spike logging when `BATTLE_FRAME_BUDGET_LOG=1`; fps_drop tags `likely_cpu`/`likely_gpu` + phase dump |
| Globe meshes coarser than sim grid | `GLOBE_MESH_W/H` 144×72, `FLUID_MESH_W/H` 180×90 | GPU budget independent of sim resolution |
| GPU compute backend (optional) | `BattleTerritoryGpuField.gd`, `shaders/territory/*.glsl` | Flow on GPU; throttled owner readback; skips `pack_display` when owners-only |

## Placement / routing responsiveness

- `OUTPOST_PATHFIND_MAX_EXPAND` (12 000) caps route floods; hover preview uses greedy-only (`OUTPOST_HOVER_ALLOW_ASTAR=false`), replans at most every `OUTPOST_HOVER_REPLAN_SEC` (0.32 s), and draws ≤ `OUTPOST_PREVIEW_MAX_SEGMENTS` (48) 3D segments.
- Land-component IDs are precomputed once per map (`prepare_land_components`) so placement prechecks never flood-fill.
- Resource miner shockwave visuals capped at `RESOURCE_MAX_VISUAL_SHOCKWAVES` (10); economy still credits all yield.
- Marker refresh + owner GPU upload defer when prior frame exceeded `FRAME_BUDGET_MS` / `FRAME_MS_DEFER_AI` (`WorldConquestScreen._drain_outpost_construction_queue`).
- Overlay apply also re-queues when prior frame > `FRAME_MS_TIGHTEN_SOFT_CAP`; fat-sim frames skip the entire construction drain.

## End-game FPS knobs (`WorldConquestConfig`)

| Knob | Default | Effect |
|------|---------|--------|
| `SOFT_CAP_DEFAULT` | 24000 | Normal active-set soft-cap |
| `SOFT_CAP_STRESS` | 8000 | Soft-cap when prior frame > `FRAME_MS_TIGHTEN_SOFT_CAP` / preempt |
| `SOFT_CAP_CRITICAL` | 5000 | Soft-cap when prior frame > `FRAME_MS_SKIP_SIM` |
| `SOFT_CAP_HEALTHY_FRAMES_TO_RAISE` | 45 | Consecutive budget-healthy frames before raising sticky soft-cap |
| `SOFT_CAP_LOG_INTERVAL_MS` | 3000 | Min gap between soft_cap RunLog lines if thrash returns |
| `SOLDIER_REPLANS_PER_TICK` | 6 | Soldier BFS replan budget/tick (was 20; late ferry thrash) |
| `BOMBER_SEARCH_EXPAND_MAX` | 12000 | Bomber strike BFS hard cap (was 40000) |
| `FRAME_MS_DEFER_AI` | 16 | Defer enemy/player AI off the same frame as a sim step; tighten marker/gpu gate |
| `FRAME_MS_TIGHTEN_SOFT_CAP` / `FRAME_MS_SOFT_CAP_PREEMPT` | 20 | Apply `SOFT_CAP_STRESS`; skip overlay reconcile/depth tint; halve agent pulls |
| `FRAME_MS_SKIP_SIM` | 28 | Skip `advance_dt` for one frame (+ AI/presentation), then force resume |

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
| `action=roads` | *(legacy)* Road mesh sync — idle under R1 |
| `action=markers` | Structure marker refresh |
| `action=fps_drop` | Sustained FPS &lt; 42; `note=likely_cpu` if CPU p99/last &gt; 12 ms else `likely_gpu`; includes `phases=` when available |

Written to `logs/latest_run.txt` with the usual 0.25 s batch flush.

`FrameBudgetProfiler` phases (when `BATTLE_FRAME_BUDGET_LOG=1`): `sim`, `overlay`, `resources`, `roads`, `markers`, `gpu_upload`, plus existing `spawner_sync`, `outpost`, `bridge`, `soldiers`.

## RunLog I/O

Session logs batch-flush every **0.25 s** (immediate on window close), max **10 000** lines per session. Engine `print()` capture only in verbose mode (`RunLog.set_verbose(true)`).

## ActivityTrace — txn timeline ↔ FPS timeline

For FPS drops, use the twin append-only files (shared `t_ms` clock):

| File | Contents |
|------|----------|
| `logs/activity_txn_latest.txt` | Commands + SCD1 pulls (`kind=place`, `kind=scd1_pull`, …) |
| `logs/activity_fps_latest.txt` | FPS / `frame_ms` samples (~4 Hz) + phase hints |

Cross-ref: when FPS dips at `t_ms=T`, scan txn lines near the same `t_ms` for row spikes / `mode=full`. Disable with `EOY_ACTIVITY_TRACE=0`. Sample rate: `EOY_ACTIVITY_FPS_HZ` (default 4).

## Known costs to watch

- `build_replay_tape(-1)` on the world map runs a full battle and can take many minutes — always pass a round cap in tests (QA bake compare uses 64).
- R1: placement no longer runs multi-source BFS / bridge landings; leftover route helpers are dead weight for Play.
- Owner readback from GPU backend is throttled via `readback_owners_if_due` (every 4 rounds on large maps); HUD counters mirror sim-side counts.
- Soldier march uses greedy steps toward a cached goal. BFS replans are **budgeted** (`SOLDIER_REPLANS_PER_TICK`), **frontier-triggered** (`nav_dirty_stamp`), with a long fallback interval (`SOLDIER_REPLAN_FALLBACK_ROUNDS`).