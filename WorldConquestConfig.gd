class_name WorldConquestConfig
extends RefCounted

## World Conquest — 360×180 equirect Earth globe, human-scale Supply economy.

const GRID_W := 360
const GRID_H := 180
const SPHERE_GRID_FREQUENCY := 80
const SPHERE_GRID_ENABLED := true
const DEFAULT_WORLD_MAP_ID := "earth"
const CELL_SIZE := 1.0

const PLAYER_FORCE := 200
const ENEMY_FORCE := 200

const STARTING_SUPPLY := 1200
const SPAWNER_COST_SUPPLY := 400
## Land Bridge — opens a foreign coast for pressure flow (no outpost build on enemy soil).
const CORRIDOR_LINK_COST_SUPPLY := 250
const INCOME_PER_TILE_PER_SEC := 0.8

## Discrete sim step (~14/sec); internal only — UI shows sim time.
const SIM_DT := 1.0 / 14.0
## I6/B12: hard cap on sim catch-up steps per frame (never uncapped while-loops).
const SIM_MAX_STEPS_PER_FRAME := 4
## When the prior _process frame exceeded this budget, sim catch-up is capped to 1 step (I6).
const FRAME_BUDGET_MS := 16.0
## End-game FPS: defer AI ticks when prior frame exceeded this (same frame as a heavy sim step).
const FRAME_MS_DEFER_AI := 16.0
## End-game FPS: tighten active-set soft-cap + keep sim at most 1 step.
const FRAME_MS_TIGHTEN_SOFT_CAP := 20.0
## End-game FPS: skip advance_dt this frame (resume next — never skip two in a row).
const FRAME_MS_SKIP_SIM := 28.0
## Soft-cap / agent-visual throttle kicks in above this prior-frame cost (before TIGHTEN).
const FRAME_MS_SOFT_CAP_PREEMPT := 20.0
## Max ownership overlay cells applied to the globe per frame (remainder queued).
const OVERLAY_DELTA_CELLS_PER_FRAME := 48
## When overlay backlog exceeds this, drain faster so paint catch-up stays under ~0.5s.
const OVERLAY_DELTA_BURST_CELLS_PER_FRAME := 512
const OVERLAY_DELTA_BURST_PENDING_THRESHOLD := 256
## Full territory seed / huge batches skip the drip queue and apply R8 in one shot.
const OVERLAY_FULL_SEED_QUEUE_THRESHOLD := 512
const OVERLAY_UPDATES_PER_SEC := 3.0
## Depth tint alone (owners come from SCD1); keep ≤0.25 Hz to avoid remapping 64k cells too often.
const OVERLAY_DEPTH_UPDATES_PER_SEC := 0.25
## Partitioned anti-drift sweep: compare Rust owner vs globe cache per frame.
## Full 360×180 pass ≈ 68 s at 16/frame @ 60 fps (halved when prior frame exceeded budget).
const OVERLAY_RECONCILE_CELLS_PER_FRAME := 16
## Globe tint from tile ownership only — skips full pressure/R8 FFI every step (B10/I2/I3).
## Live path uses pull_presentation_delta owner deltas; never reintroduce per-step full pressure pulls.
const OVERLAY_OWNERS_ONLY := true
## Throttled pressure-depth tint on ownership shader (0.25 Hz; no per-step pressure FFI).
const OVERLAY_DEPTH_TINT := true
## Display normalize for depth R8 bake (Rust get_pressure_depth_r8).
const PRESSURE_VIS_REF := 48.0
const SOLDIER_VISUAL_UPDATES_PER_SEC := 4.0
## Max soldier BFS replans per sim tick (global budget across all units).
## Kept low (6): late-game ferry thrash — free tiles shrink, stuck agents replan
## with water-allowed BFS; 20×/tick was a primary FPS collapse driver (not soft-cap).
const SOLDIER_REPLANS_PER_TICK := 6
## Fallback replan interval when local frontier is stable (~3 s at 14 Hz).
const SOLDIER_REPLAN_FALLBACK_ROUNDS := 42
## Active-set soft-cap default (matches Rust ACTIVE_SET_SOFT_CAP).
const SIM_ACTIVE_SOFT_CAP := 24000
const SOFT_CAP_DEFAULT := SIM_ACTIVE_SOFT_CAP
## Under frame pressure (> FRAME_MS_TIGHTEN_SOFT_CAP), prune to this soft-cap.
const SOFT_CAP_STRESS := 8000
## Critical overload (> FRAME_MS_SKIP_SIM): prune harder so gradient stays cheap.
const SOFT_CAP_CRITICAL := 5000
## Sticky soft-cap: once lowered, require this many consecutive healthy frames
## (prior_ms ≤ FRAME_BUDGET_MS) before raising back toward DEFAULT. Prevents
## 5k↔24k thrash after a skip/heavy frame briefly looks healthy.
const SOFT_CAP_HEALTHY_FRAMES_TO_RAISE := 45
## Rate-limit soft_cap RunLog lines (ms) even if state flips again.
const SOFT_CAP_LOG_INTERVAL_MS := 3000
## Minimum time on the World Conquest loading screen (shader compile, Rust warm-up).
const WORLD_CONQUEST_MIN_LOAD_SEC := 2.5
## Capital deploy pick window once the globe is interactable (US-START-01).
const DEPLOY_PICK_SEC := 5.0
## Brief enemy capital pin after player commits deploy.
const DEPLOY_ENEMY_REVEAL_SEC := 1.5
## Orbit sensitivity multiplier while choosing a capital (pick phase only).
const DEPLOY_ORBIT_MULT := 2.75

const GLOBE_RADIUS := 100.0
## Radial displacement so mountains read as ridges (mesh + surface LUT).
const HEIGHT_SCALE := 16.0
const FLUID_SURFACE_LIFT := 0.45
## Atmosphere shell scale vs GLOBE_RADIUS (cosmetic rim).
const ATMOSPHERE_RADIUS_SCALE := 1.045
## Globe render mesh (coarser than sim grid for GPU budget).
const GLOBE_MESH_W := 144
const GLOBE_MESH_H := 72
## Ownership overlay mesh — matched to terrain mesh for GPU budget (sim stays 360×180).
const FLUID_MESH_W := 144
const FLUID_MESH_H := 72
## Internal SubViewport scale (1.0 = native play-area pixels).
const GLOBE_RENDER_SCALE := 0.85
## Max ownership texture GPU uploads per second (sim can outpace; catches up next upload).
const OVERLAY_GPU_UPLOAD_MAX_HZ := 30.0

const MIN_SPAWNER_SPACING_CELLS := 6
## Outpost build timer (legacy BUILDING state). R1 Play places structures as ACTIVE immediately.
const OUTPOST_BUILD_SEC := 5.0
const OUTPOST_ROAD_CELLS_PER_SEC := 2.0
## Each connecting route feeds its own road front at this rate (parallel when routes diverge).
## Shared logistics network — timer road growth (replaces builder bots).
##
## Design lock R1: roads and land bridges are cut from gameplay. Structures place instantly and
## haul lines are drawn straight to the nearest hub, so nothing in GDScript reads the LOGISTICS_*
## or ROAD_* knobs below anymore. They stay declared because the Rust territory extension still
## loads them; delete them only together with the Rust-side logistics network.
const LOGISTICS_RECONCILE_CELLS_PER_FRAME := 6480
const LOGISTICS_FULL_RECAL_SEC := 25.0
const LOGISTICS_PLACEMENT_HEAT_DECAY := 0.85
const LOGISTICS_BURST_BASE := 0.02
const LOGISTICS_BURST_RATIO := 1.35
const LOGISTICS_DRAIN_SPAWNER := 0.04
const LOGISTICS_DRAIN_BARRACKS := 0.06
const LOGISTICS_DRAIN_HANGAR := 0.06
const LOGISTICS_DRAIN_CORRIDOR := 0.03
const LOGISTICS_STRAIN_SENSITIVITY := 1.0
const MAX_NETWORK_ROAD_CELLS_PER_FRAME := 24
## Cell-paint roads via equirect overlay — OFF.
## Equirect Voronoi paint cannot draw a clean 3-wide ribbon (became island-sized blobs).
## Roads use MultiMesh ribbons: white centerlane + black side lanes (~3 cell widths).
const ROAD_CELL_PAINT := false
## Paths at or under this length (after spur trim) count as spurs for hierarchy paint.
const ROAD_SPUR_MAX_CELLS := 16
## Legacy builder visuals (unused when logistics authority is on).
const BUILDER_BOTS_PER_HOME := 4
const BUILDER_SURFACE_LIFT := 2.85
const BUILDER_ORBIT_RADIUS_CELLS := 3.5
const BUILDER_ORBIT_SPEED := 0.55
const BUILDER_RETURN_SEC := 0.45
## Throttle Rust/claimable sync while a bridge is extending (avoids per-cell full-grid work).
const BRIDGE_BACKEND_SYNC_INTERVAL_SEC := 0.2
## Per-frame construction drain caps (OutpostConstructionQueue).
const MAX_ROAD_SIDS_PER_FRAME := 1
const MAX_CORRIDOR_SIDS_PER_FRAME := 1
const MAX_MARKER_SIDS_PER_FRAME := 1
## Bridge deck height above globe sea level (water tiles).
const BRIDGE_SURFACE_LIFT := 3.4
## Safety cap for route search (bidirectional); avoids multi-second ocean floods.
const OUTPOST_PATHFIND_MAX_EXPAND := 12000
## B9: Hover preview uses greedy bridge only (no A*); keep false for responsive cursor on long routes.
const OUTPOST_HOVER_ALLOW_ASTAR := false
## Max 3D segments drawn for placement preview (subsample longer bridge paths).
const OUTPOST_PREVIEW_MAX_SEGMENTS := 48
## Min seconds between expensive hover route replans while cursor moves.
const OUTPOST_HOVER_REPLAN_SEC := 0.32
## Rust route planner on the preloaded world snapshot — sole placement pathfinder.
const ROUTE_RUST_ONLY := true
## B9: Async Rust route on click (keeps main thread responsive during A*) — keep true.
const ROUTE_ASYNC_PLACEMENT := true
const ROUTE_HOVER_PREVIEW := false
## One-time setup_map + portal build during loading (avoids hitch on first build-button press).
const ROUTE_PRELOAD_AT_LOAD := true
## Optional sync route near home after preload (warms Rust pathfinder caches).
const ROUTE_WARMUP_PROBE := true
## Debounce portal/infra refresh when operational sources change (new active spawner).
const ROUTE_SOURCE_DEBOUNCE_SEC := 0.4
## Debounce full infra-mask refresh while roads extend cell-by-cell during construction.
const ROUTE_ROAD_INFRA_DEBOUNCE_SEC := 2.5
const OUTPOST_MAX_HEALTH := 10.0
const OUTPOST_ENEMY_DPS := 3.0
## Barracks — same Supply economy as outposts; longer build; spawns soldiers (Aurelium).
const BARRACKS_COST_SUPPLY := 400
const BARRACKS_BUILD_SEC := 5.0
const BARRACKS_SPAWN_INTERVAL_SEC := 10.0
const BARRACKS_MAX_ACTIVE_UNITS := 5
const GLOBAL_SOLDIER_CAP := 100
const SOLDIER_SPAWN_AURELIUM_COST := 3.0
## Verdantite — infantry spawn + upkeep sink (R1 restore; Au remains primary deficit DPS gate).
const SOLDIER_SPAWN_VERDANTITE_COST := 1.0
const SOLDIER_UPKEEP_VERDANTITE_PER_SEC := 0.05
## Hangar — same economy as barracks; spawns bombers (Aurelium + Emberstone).
const HANGAR_COST_SUPPLY := 400
const HANGAR_BUILD_SEC := 5.0
const HANGAR_SPAWN_INTERVAL_SEC := 10.0
const HANGAR_MAX_ACTIVE_UNITS := 5
const GLOBAL_BOMBER_CAP := 100
const BOMBER_SPAWN_AURELIUM_COST := 3.0
## Emberstone — bomber spawn sink (R1 restore).
const BOMBER_SPAWN_EMBERSTONE_COST := 1.0
const BOMBER_MAX_HP := 100.0
const BOMBER_ORPHAN_DPS := 1.0
const BOMBER_MOVE_CELLS_PER_SEC := 2.0
const BOMBER_INFRA_MOVE_MULT := 3.0
const BOMBER_BOMB_POWER := 1000.0
const BOMBER_BOMB_INTERVAL_SEC := 10.0
const BOMBER_VISUAL_UPDATES_PER_SEC := 4.0
## Flight altitude lift — ~10× peak mountain visual (HEIGHT_SCALE * 10).
const BOMBER_SURFACE_LIFT := HEIGHT_SCALE * 10.0
## Strike pathfind starts local, widening on miss (BFS cell budgets).
## Cap at 12k (not 40k): same late-game pathfind thrash budget as land/ferry caps.
const BOMBER_SEARCH_EXPAND_INITIAL := 5000
const BOMBER_SEARCH_EXPAND_STEP := 5000
const BOMBER_SEARCH_EXPAND_MAX := 12000
## Force a fresh route evaluation after this many seconds on the same plan.
const BOMBER_PLAN_REEVAL_SEC := 25.0
const SOLDIER_UPKEEP_AURELIUM_PER_SEC := 0.15
const SOLDIER_MAX_HP := 40.0
const SOLDIER_ORPHAN_DPS := 4.0
const SOLDIER_MOVE_CELLS_PER_SEC := 2.0
const SOLDIER_INFRA_MOVE_MULT := 3.0
## While ferrying on open water, move at this fraction of land speed.
const SOLDIER_FERRY_MOVE_MULT := 0.25
const SOLDIER_AURA_PRESSURE := 5.0
const SOLDIER_SHOOT_ERODE_PER_SEC := 24.0
const SOLDIER_UPKEEP_DEFICIT_DPS := 2.5
## Canonical bridge pressure flow mult (A11/A12/C15).
## MUST match rust/empire_territory/src/world_edit.rs `BRIDGE_PRESSURE_FLOW_MULT`.
## Design target is 2.8 (obsolete docs mentioned 0.92 — that value is wrong).
const BRIDGE_PRESSURE_FLOW_MULT := 2.8
## Design-target constant used by assert_canonical_constants() (must equal BRIDGE_PRESSURE_FLOW_MULT).
const BRIDGE_PRESSURE_FLOW_MULT_DESIGN_TARGET := 2.8

## Win: all claimable land, or enemy cumulative power reaches zero.
const CONQUEST_LAND_FRAC := 1.0
const MAX_SIM_TIME_SEC := 7200.0
## Hostile pressure total at or below this counts as zero (matches HUD integer display).
const ZERO_POWER_VICTORY_EPS := 0.5
## Log when the slow GDScript owner→display overlay path runs during Rust live play.
const WORLD_DATASET_WARN_SLOW_OVERLAY := true
## Production live contract: all authority flags true. Do not introduce partial live modes.
## Individual flags remain for explicit CPU/QA harnesses only — not for runtime toggles mid-match.
## A2: under GRID_AUTHORITY live, tile_control.grid_mirror_frozen must be true (no dual grid writes).
const WORLD_DATASET_GRID_AUTHORITY := true
## A4/C5: Rust structure store is sole path_built / state authority under live.
const WORLD_DATASET_STRUCTURE_AUTHORITY := true
const WORLD_DATASET_WORLD_SESSION_TICK := true
## A6/A7/C8: when true, BuilderAgentLib.step_frame hard-refuses (Rust logistics owns construction).
const WORLD_DATASET_BUILDER_AUTHORITY := true
## A8: when true, resource balances live in Rust wallet; GDScript holds presentation mirrors only.
const WORLD_DATASET_RESOURCE_WALLET := true
## QA: assert single-source WorldDataset invariants during validate runs (E8).
const WORLD_DATASET_QA_ASSERTS := true
## B11/I5: never full-structure-snap every frame; pull_presentation_delta structures only when dirty.
const PRESENTATION_STRUCTURES_ONLY_WHEN_DIRTY := true


## True when Play uses the single Rust live world (presentation is pull_presentation_delta).
static func world_dataset_live() -> bool:
	return (
		WORLD_DATASET_GRID_AUTHORITY
		and WORLD_DATASET_STRUCTURE_AUTHORITY
		and WORLD_DATASET_WORLD_SESSION_TICK
		and WORLD_DATASET_BUILDER_AUTHORITY
		and WORLD_DATASET_RESOURCE_WALLET
	)


## A1/G3: production contract requires Rust live — no silent CPU dual-sim for World Conquest play.
static func world_dataset_require_live() -> bool:
	return world_dataset_live()


## A12/C15: shared-constant sanity (Godot side). Rust must match BRIDGE_PRESSURE_FLOW_MULT.
static func assert_canonical_constants() -> bool:
	if not is_equal_approx(BRIDGE_PRESSURE_FLOW_MULT, BRIDGE_PRESSURE_FLOW_MULT_DESIGN_TARGET):
		push_error(
			(
				"WorldConquestConfig: BRIDGE_PRESSURE_FLOW_MULT=%.4f != design target %.4f (A12)"
				% [BRIDGE_PRESSURE_FLOW_MULT, BRIDGE_PRESSURE_FLOW_MULT_DESIGN_TARGET]
			)
		)
		return false
	return true

const CAMERA_ORBIT_SPEED := 0.35
const CAMERA_PITCH_MIN := -1.2
const CAMERA_PITCH_MAX := 1.2
const CAMERA_ZOOM_STEP := 1.12
## Keep camera outside globe radius + max elevation + fluid lift.
const CAMERA_MIN_DISTANCE := 155.0
const CAMERA_MAX_DISTANCE := 320.0
const CAMERA_DEFAULT_DISTANCE := 200.0

## Slower creep spread than compact RTS maps (HOME_START_POWER / 2000 per step).
const WORLD_CONQUEST_PRESSURE_SCALE := 1.0 / 2000.0
## Per-round pressure from home base + operational spawners (1.0 = full output).
const PRESSURE_SOURCE_OUTPUT_MULT := 0.7
## Home + spawner pressure inject cadence in sim rounds (@ SIM_DT).
const PRESSURE_INJECT_INTERVAL_ROUNDS := 7

## Strategic minerals — Aurelium (yellow), Verdantite (green), Emberstone (orange).
const RESOURCE_TYPE_COUNT := 3
const RESOURCE_NAMES: Array[String] = ["Aurelium", "Verdantite", "Emberstone"]
const RESOURCE_SHORT: Array[String] = ["Au", "Ve", "Em"]
const RESOURCE_COLORS: Array[Color] = [
	Color(0.98, 0.86, 0.22, 1.0),
	Color(0.28, 0.88, 0.42, 1.0),
	Color(0.98, 0.52, 0.18, 1.0),
]
## Flat baseline: each team earns this much Au, Ve, and Em per sim-second so units
## can spawn/ferry even when the starting landmass has no owned deposits.
const TEAM_BASELINE_MINERAL_PER_SEC := 1.0
const RESOURCE_BLOBS_PER_TYPE := 22
const RESOURCE_BLOB_MIN_SPACING := 10
const RESOURCE_SPAWN_EXCLUSION := 24
## Yield per second by blob size tier (1 small, 2 medium, 3 large).
const RESOURCE_YIELD_BY_SIZE: Array[float] = [0.0, 0.6, 1.0, 1.8]
const RESOURCE_BLOB_CELL_COUNT: Array[int] = [0, 4, 9, 18]
## Visual shockwave budget (economy still full credit — Design lock F7).
## Visual-only cap (economy still credits all yield). Lowered for mid/late draw spikes.
const RESOURCE_MAX_VISUAL_SHOCKWAVES := 10
## Compat alias — prefer RESOURCE_MAX_VISUAL_SHOCKWAVES.
const RESOURCE_MAX_VISUAL_PULSES := RESOURCE_MAX_VISUAL_SHOCKWAVES
const RESOURCE_SHOCKWAVE_PERIOD_SEC := 2.0
const RESOURCE_SHOCKWAVE_DURATION_SEC := 0.65
## Globe-readable miner size (world units; globe radius is ~100).
const RESOURCE_MINER_SCALE := 3.6
## Shockwave ring start/end radii in world units (must read from orbit cam).
const RESOURCE_SHOCKWAVE_RADIUS_START := 2.2
const RESOURCE_SHOCKWAVE_RADIUS_END := 9.0
## Legacy haul-path rates (unused after miner visual cut; kept so old saves/tests don't KeyError).
const RESOURCE_LINK_CELLS_PER_SEC := 1.2
const RESOURCE_HAUL_CELLS_PER_SEC := 2.5

## Hostile opponent AI — throttled planner + spread execution (no per-frame full-map scans).
const ENEMY_AI_ENABLED := true
const ENEMY_AI_PLAN_INTERVAL_SEC := 1.25
const ENEMY_AI_ACTIONS_PER_FRAME := 1
const ENEMY_AI_MAX_ACTIONS_PER_PLAN := 3
const ENEMY_AI_MAX_CONCURRENT_BUILDS := 2
const ENEMY_AI_MAX_CANDIDATES := 20
const ENEMY_AI_FRONTIER_SAMPLE_STRIDE := 4
const ENEMY_AI_DEFAULT_DIFFICULTY := 1
const ENEMY_AI_VISION_BEGINNER := 18
const ENEMY_AI_VISION_MEDIUM := 28
const ENEMY_AI_VISION_EXPERT := 40
## Multi-structure AI caps / reserves (outposts + barracks + hangar; still no bridges).
const ENEMY_AI_MAX_BARRACKS := 3
const ENEMY_AI_MAX_HANGARS := 2
const ENEMY_AI_MIN_OUTPOSTS_BEFORE_MILITARY := 1
const ENEMY_AI_SUPPLY_RESERVE := 400
## Barracks/hangar planning: 0 so AI vs AI can place military when supply is ok
## even if Au/Em wallets are still warming up (soldiers still need Au at spawn time).
const ENEMY_AI_BARRACKS_MIN_AU := 0.0
const ENEMY_AI_HANGAR_MIN_EM := 0.0
## Soft spacing for barracks/hangar so they can sit near outposts on small beachheads.
## Outposts still use MIN_SPAWNER_SPACING_CELLS vs all structures.
const ENEMY_AI_MILITARY_SPACING_CELLS := 2
## R1: bridge AI removed — chance constants retired (unread).