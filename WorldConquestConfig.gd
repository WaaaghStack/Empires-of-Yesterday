class_name WorldConquestConfig
extends RefCounted

## World Conquest — 360×180 equirect Earth globe, human-scale Supply economy.

const GRID_W := 360
const GRID_H := 180
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
const SIM_MAX_STEPS_PER_FRAME := 4
## When the prior _process frame exceeded this budget, sim catch-up is capped to 1 step.
const FRAME_BUDGET_MS := 16.0
## Max ownership overlay cells applied to the globe per frame (remainder queued).
const OVERLAY_DELTA_CELLS_PER_FRAME := 48
const OVERLAY_UPDATES_PER_SEC := 3.0
## Partitioned anti-drift sweep: compare Rust owner vs globe cache per frame.
## Full 360×180 pass ≈ 68 s at 16/frame @ 60 fps (halved when prior frame exceeded budget).
const OVERLAY_RECONCILE_CELLS_PER_FRAME := 16
## Globe tint from tile ownership only — skips pressure FFI and peak scans.
const OVERLAY_OWNERS_ONLY := true
const SOLDIER_VISUAL_UPDATES_PER_SEC := 4.0
## Max soldier BFS replans per sim tick (global budget across all units).
const SOLDIER_REPLANS_PER_TICK := 20
## Fallback replan interval when local frontier is stable (~3 s at 14 Hz).
const SOLDIER_REPLAN_FALLBACK_ROUNDS := 42
const SIM_ACTIVE_SOFT_CAP := 8000
## Minimum time on the World Conquest loading screen (shader compile, Rust warm-up).
const WORLD_CONQUEST_MIN_LOAD_SEC := 2.5

const GLOBE_RADIUS := 100.0
## Subtle displacement so land reads as one continuous shell (not floating plates).
const HEIGHT_SCALE := 7.0
const FLUID_SURFACE_LIFT := 0.35
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
## Outpost must link by road from HQ or nearest active outpost, then finish construction.
const OUTPOST_BUILD_SEC := 5.0
const OUTPOST_ROAD_CELLS_PER_SEC := 1.0
## Flying builder bots per home base (player + enemy); future scaling hooks here.
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
## Hover preview: greedy bridge only (no A*); keeps cursor responsive on long routes.
const OUTPOST_HOVER_ALLOW_ASTAR := false
## Max 3D segments drawn for placement preview (subsample longer bridge paths).
const OUTPOST_PREVIEW_MAX_SEGMENTS := 48
## Min seconds between expensive hover route replans while cursor moves.
const OUTPOST_HOVER_REPLAN_SEC := 0.32
## Rust route planner on the preloaded world snapshot — sole placement pathfinder.
const ROUTE_RUST_ONLY := true
## Async Rust route on click (keeps main thread responsive during A*).
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
const BARRACKS_BUILD_SEC := 60.0
const BARRACKS_SPAWN_INTERVAL_SEC := 10.0
const BARRACKS_MAX_ACTIVE_UNITS := 5
const GLOBAL_SOLDIER_CAP := 100
const SOLDIER_SPAWN_AURELIUM_COST := 3.0
const SOLDIER_UPKEEP_AURELIUM_PER_SEC := 0.15
const SOLDIER_MAX_HP := 40.0
const SOLDIER_ORPHAN_DPS := 4.0
const SOLDIER_MOVE_CELLS_PER_SEC := 2.0
const SOLDIER_INFRA_MOVE_MULT := 3.0
const SOLDIER_AURA_PRESSURE := 0.48
const SOLDIER_SHOOT_ERODE_PER_SEC := 24.0
const SOLDIER_UPKEEP_DEFICIT_DPS := 2.5
## Pressure flow multiplier on built bridge water cells (vs land).
const BRIDGE_PRESSURE_FLOW_MULT := 2.8

## Win: all claimable land, or enemy cumulative power reaches zero.
const CONQUEST_LAND_FRAC := 1.0
const MAX_SIM_TIME_SEC := 7200.0
## Hostile pressure total at or below this counts as zero (matches HUD integer display).
const ZERO_POWER_VICTORY_EPS := 0.5
## Log when the slow GDScript owner→display overlay path runs during Rust live play.
const WORLD_DATASET_WARN_SLOW_OVERLAY := true
## Rust kernel owns owners/claimable/reachability during WC live — skip GDScript grid mirror writes.
const WORLD_DATASET_GRID_AUTHORITY := true
## Rust structure store owns outpost/corridor sim state — GDScript placed_structures is render cache.
const WORLD_DATASET_STRUCTURE_AUTHORITY := true
## Building timers, construction damage, and barracks spawns in one Rust world_session_tick.
const WORLD_DATASET_WORLD_SESSION_TICK := true
## Builder job queues, path_built growth, and bot travel in Rust (GDScript visuals only).
const WORLD_DATASET_BUILDER_AUTHORITY := true
## Resource balances stored in Rust dataset; deposit tick still computed in GDScript.
const WORLD_DATASET_RESOURCE_WALLET := true
## QA: assert single-source WorldDataset invariants during validate runs.
const WORLD_DATASET_QA_ASSERTS := true


static func world_dataset_live() -> bool:
	return (
		WORLD_DATASET_GRID_AUTHORITY
		and WORLD_DATASET_STRUCTURE_AUTHORITY
		and WORLD_DATASET_WORLD_SESSION_TICK
		and WORLD_DATASET_BUILDER_AUTHORITY
		and WORLD_DATASET_RESOURCE_WALLET
	)

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
const PRESSURE_SOURCE_OUTPUT_MULT := 0.5
## Home + spawner pressure inject cadence in sim rounds (@ SIM_DT).
const PRESSURE_INJECT_INTERVAL_ROUNDS := 10

## Strategic minerals — Aurelium (yellow), Verdantite (green), Emberstone (orange).
const RESOURCE_TYPE_COUNT := 3
const RESOURCE_NAMES: Array[String] = ["Aurelium", "Verdantite", "Emberstone"]
const RESOURCE_SHORT: Array[String] = ["Au", "Ve", "Em"]
const RESOURCE_COLORS: Array[Color] = [
	Color(0.98, 0.86, 0.22, 1.0),
	Color(0.28, 0.88, 0.42, 1.0),
	Color(0.98, 0.52, 0.18, 1.0),
]
const RESOURCE_BLOBS_PER_TYPE := 22
const RESOURCE_BLOB_MIN_SPACING := 10
const RESOURCE_SPAWN_EXCLUSION := 24
## Yield per second by blob size tier (1 small, 2 medium, 3 large).
const RESOURCE_YIELD_BY_SIZE: Array[float] = [0.0, 0.6, 1.0, 1.8]
const RESOURCE_BLOB_CELL_COUNT: Array[int] = [0, 4, 9, 18]
const RESOURCE_LINK_CELLS_PER_SEC := 1.2
const RESOURCE_HAUL_CELLS_PER_SEC := 2.5
## Cap simultaneous haul pulse draw instances (economy still credits all yields).
const RESOURCE_MAX_VISUAL_PULSES := 36

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
const ENEMY_AI_BRIDGE_CHANCE_BEGINNER := 0.08
const ENEMY_AI_BRIDGE_CHANCE_MEDIUM := 0.28
const ENEMY_AI_BRIDGE_CHANCE_EXPERT := 0.48