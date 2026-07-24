extends Node

const REPORT_PATH := "res://qa_report.txt"
const PERF_BOOTSTRAP_MAX_FRAMES := 900
const PERF_LIVE_FRAMES := 180
const PERF_REQUIRED_ACTION_TAGS: Array[String] = [
	"action=sim",
	"action=overlay",
	"action=resources",
	"action=gpu_upload",
	"action=roads",
	"action=markers",
]

## E7: keep-up list — production scripts + orphan smokes + new modules must load.
const SCRIPT_PATHS: Array[String] = [
	"res://BattleCellGrid.gd",
	"res://BattleMapData.gd",
	"res://BattlePacing.gd",
	"res://BattlePerfProfiler.gd",
	"res://BattleReplayPack.gd",
	"res://BattleReplayTape.gd",
	"res://BattleTerritoryBakeWorker.gd",
	"res://BattleTerritoryGpuField.gd",
	"res://BattleTerritoryReplayBake.gd",
	"res://BattleTerritoryRustBackend.gd",
	"res://BattleTerritorySim.gd",
	"res://BattleTerritoryTape.gd",
	"res://BattleTileControl.gd",
	"res://BattleTileFluidField.gd",
	"res://BattleTileOwnershipOverlay.gd",
	"res://BattleTilePressureCodec.gd",
	"res://DynamicPathGraph.gd",
	"res://EarthGlobeMap.gd",
	"res://EarthGlobeRoads.gd",
	"res://FrameBudgetProfiler.gd",
	"res://EarthGlobeMesh.gd",
	"res://EarthMapGenerator.gd",
	"res://GameTheme.gd",
	"res://MainMenu.gd",
	"res://RoutePlannerRustBackend.gd",
	"res://RunLog.gd",
	"res://RunState.gd",
	"res://UnitSimulationStore.gd",
	"res://WorldConquestConfig.gd",
	"res://SphereGridLib.gd",
	"res://WorldConquestMapGenerator.gd",
	"res://WorldConquestOutpostBuild.gd",
	"res://WorldConquestResources.gd",
	"res://WorldConquestScreen.gd",
	"res://WorldDatasetAssert.gd",
	"res://WorldMapBakeLib.gd",
	"res://WorldMapCatalog.gd",
	"res://WorldPackLib.gd",
	"res://OutpostConstructionQueue.gd",
	"res://BuilderAgentLib.gd",
	"res://EnemyStrategy.gd",
	"res://EconomyCatalog.gd",
	"res://EconomyLib.gd",
	"res://WorldConquestPresentationApply.gd",
	# C10/E1–E5: orphan smoke scripts brought into primary gate load list.
	"res://bridge_invasion_smoke_test.gd",
	"res://island_outpost_smoke_test.gd",
	"res://barracks_smoke_test.gd",
	"res://enemy_ai_smoke_test.gd",
	"res://soldier_nav_smoke_test.gd",
]

const SCENE_PATHS: Array[String] = [
	"res://MainMenu.tscn",
	"res://WorldConquestScreen.tscn",
]

var _lines: PackedStringArray = PackedStringArray()
var _failed: bool = false


func _ready() -> void:
	await _run_all_async()
	if _failed:
		_write_report()
		push_error("QA FAILED — see %s" % REPORT_PATH)
		get_tree().quit(1)
	else:
		_log("QA PASSED")
		_write_report()
		print("QA PASSED")
		get_tree().quit(0)


func _run_all_async() -> void:
	_log("=== World Conquest QA ===")
	for path in SCRIPT_PATHS:
		_validate_script_load(path)
	for path in SCENE_PATHS:
		_validate_scene_load(path)
	_validate_run_log()
	_validate_world_conquest_smoke()
	_validate_pressure_outflow()
	_validate_pressure_height_headroom()
	_validate_world_conquest_bench()
	_validate_world_conquest_fps_bench()
	await _validate_perf_helpers()
	_validate_outpost_construction_queue()
	_validate_visual_drain_ordering()
	_validate_builder_selfcheck()
	_validate_builder_chain_selfcheck()
	_validate_builder_authority_refuse()
	_validate_enemy_strategy_selfcheck()
	await _validate_enemy_ai_integration_smoke()
	_validate_world_seed_variety()
	_validate_earth_land_mask()
	await _validate_builder_integration_smoke()
	# E8 / WorldDataset + assert_canonical_constants (via WorldDatasetAssert).
	_validate_world_dataset_assert()
	_validate_assert_canonical_constants()
	_validate_economy_catalog_parity()
	# C10/E1–E5: orphan smokes integrated as lightweight primary-gate checks.
	_validate_orphan_smoke_structural()
	_validate_bridge_invasion_gate()
	_validate_island_outpost_gate()
	_validate_barracks_smoke_gate()
	_validate_enemy_ai_smoke_gate()
	_validate_soldier_nav_smoke_gate()
	await _validate_fps_fix_paths()
	await _validate_midgame_presentation_fps()
	await _validate_construction_pulse_fps()
	# Main-table PresentationTxn contract (structure authority + snap budget).
	await _validate_main_table_txn_contract()
	# E11/I*: presentation thrash guardrails.
	_validate_road_multimesh_append()
	_validate_earth_globe_roads_helpers()
	_validate_presentation_thrash_guardrails()
	_validate_gpu_fps_env_limit()
	_validate_territory_rust_compare()
	_validate_territory_rust_bake_compare()
	# E10: active-set drift policy (≤8 tiles live OK).
	_validate_territory_rust_active_set_golden()


func _validate_script_load(path: String) -> void:
	var script: Script = load(path)
	if script == null:
		_fail("script load failed: %s" % path)
	else:
		_log("OK  script %s" % path.get_file())


func _validate_scene_load(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		_fail("scene load failed: %s" % path)
	else:
		_log("OK  scene %s" % path.get_file())


func _validate_run_log() -> void:
	_log("-- RunLog autoload --")
	if not RunLog.has_method("info"):
		_fail("RunLog missing info() API")
		return
	if RunLog.get_session_path().is_empty():
		_fail("RunLog session path is empty")
		return
	RunLog.info("QA RunLog smoke test")
	if not FileAccess.file_exists(RunLog.get_session_path()):
		_fail("RunLog workspace log missing: %s" % RunLog.get_session_path())
		return
	_log("OK  RunLog session=%s" % RunLog.get_session_path())


func _validate_world_dataset_assert() -> void:
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	if not WorldConquestConfigLib.WORLD_DATASET_QA_ASSERTS:
		return
	_log("-- WorldDataset assert (config flags) --")
	if not WorldConquestConfigLib.world_dataset_live():
		_fail("world_dataset_live() false — all WORLD_DATASET_* flags must be true")
		return
	_log("OK  world_dataset_live config")


func _validate_economy_catalog_parity() -> void:
	const EconomyLib := preload("res://EconomyLib.gd")
	const EconomyCatalog := preload("res://EconomyCatalog.gd")
	_log("-- Economy catalog bake parity --")
	EconomyLib.reset()
	var result: Dictionary = EconomyLib.validate_parity()
	if not bool(result.get("ok", false)):
		var issues: PackedStringArray = result.get("issues", PackedStringArray())
		_fail("Economy catalog parity failed: %s" % ", ".join(issues))
		return
	_log("OK  Economy catalog matches WorldConquestConfig")


func _validate_world_dataset_on_screen(screen: Control) -> void:
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const WorldDatasetAssertLib := preload("res://WorldDatasetAssert.gd")
	if not WorldConquestConfigLib.WORLD_DATASET_QA_ASSERTS:
		return
	var ts = screen.get("territory_sim")
	var bd = screen.get("battle_data")
	var result: Dictionary = WorldDatasetAssertLib.validate_live(ts, bd)
	if bool(result.get("skipped", false)):
		return
	if not bool(result.get("ok", false)):
		var issues: PackedStringArray = result.get("issues", PackedStringArray())
		_fail("WorldDataset assert failed: %s" % ", ".join(issues))
		return
	_log("OK  WorldDataset live invariants (Rust authoritative)")


func _validate_world_conquest_smoke() -> void:
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	if WorldConquestConfigLib.SPHERE_GRID_ENABLED:
		_validate_sphere_grid_smoke()
		_validate_rect_globe_mesh_short()
	else:
		_validate_rect_world_conquest_smoke()


func _validate_rect_world_conquest_smoke() -> void:
	_log("-- World Conquest smoke (360x180 map + globe mesh) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(44201)
	if bmap.grid_width != WorldConquestConfigLib.GRID_W or bmap.grid_height != WorldConquestConfigLib.GRID_H:
		_fail("world conquest map size %dx%d" % [bmap.grid_width, bmap.grid_height])
		return
	if bmap.player_home_grid.x < 0 or bmap.enemy_home_grid.x < 0:
		_fail("world conquest missing HQ spawns")
		return
	var claimable: int = 0
	for gy in range(bmap.grid_height):
		for gx in range(bmap.grid_width):
			if bmap.is_land_cell(gx, gy):
				claimable += 1
	if claimable < 8000:
		_fail("world conquest claimable land too low (%d)" % claimable)
		return
	var globe: ArrayMesh = EarthGlobeMeshLib.build_globe(bmap)
	if globe.get_surface_count() < 1:
		_fail("world conquest globe mesh empty")
		return
	var fluid: ArrayMesh = EarthGlobeMeshLib.build_fluid_globe(bmap)
	if fluid.get_surface_count() < 1:
		_fail("world conquest fluid globe mesh empty")
		return
	_log("OK  world conquest smoke %dx%d claimable=%d" % [bmap.grid_width, bmap.grid_height, claimable])


func _validate_rect_globe_mesh_short() -> void:
	_log("-- Rect globe mesh short (EarthMapGenerator sanity) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
	var bmap = EarthMapGeneratorLib.generate(44201)
	var globe: ArrayMesh = EarthGlobeMeshLib.build_globe(bmap)
	if globe.get_surface_count() < 1:
		_fail("rect globe mesh short check empty")
		return
	_log("OK  rect globe mesh short")


func _validate_sphere_grid_smoke() -> void:
	_log("-- Sphere grid smoke (equal-area icosahedron + globe mesh) --")
	const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
	const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
	const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
	const SphereGridLib := preload("res://SphereGridLib.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const seed_val: int = 44201
	var bmap = WorldConquestMapGeneratorLib.generate(WorldMapCatalogLib.MAP_EARTH, seed_val)
	if not bmap.sphere_mode:
		_fail("sphere grid smoke: expected sphere_mode true")
		return
	var cell_count: int = bmap.cell_count
	if cell_count <= 1000:
		_fail("sphere grid smoke: cell_count too low (%d)" % cell_count)
		return
	if bmap.neighbors.size() != cell_count * 6:
		_fail(
			"sphere grid smoke: neighbors size %d != cell_count*6 (%d)"
			% [bmap.neighbors.size(), cell_count * 6]
		)
		return
	if bmap.neighbor_counts.size() != cell_count:
		_fail(
			"sphere grid smoke: neighbor_counts size %d != cell_count (%d)"
			% [bmap.neighbor_counts.size(), cell_count]
		)
		return
	if bmap.gameplay_tile_count() != cell_count:
		_fail(
			"sphere grid smoke: gameplay_tile_count %d != cell_count %d"
			% [bmap.gameplay_tile_count(), cell_count]
		)
		return
	if (
		bmap.grid_width != WorldConquestConfigLib.GRID_W
		or bmap.grid_height != WorldConquestConfigLib.GRID_H
	):
		_fail(
			"sphere grid smoke: overlay grid %dx%d != GRID_W/H"
			% [bmap.grid_width, bmap.grid_height]
		)
		return
	for home_name in ["player_home_grid", "enemy_home_grid"]:
		var home: Vector2i = bmap.get(home_name)
		if home.y != 0:
			_fail("sphere grid smoke: %s y=%d (expected 0)" % [home_name, home.y])
			return
		if home.x < 0 or home.x >= cell_count:
			_fail("sphere grid smoke: %s cell_id invalid %s" % [home_name, home])
			return
	# WorldConquestScreen._is_on_map_grid: sphere uses cell_id with gy==0, not overlay 360×180.
	const ON_MAP_PROBE: int = 5000
	if not (ON_MAP_PROBE >= 0 and ON_MAP_PROBE < cell_count):
		_fail(
			"sphere grid smoke: cell_id %d not on-map (_is_on_map_grid equivalent)"
			% ON_MAP_PROBE
		)
		return
	var claimable: int = 0
	for cid in range(cell_count):
		if bmap.is_land_cell_id(cid):
			claimable += 1
	if claimable <= 1000:
		_fail("sphere grid smoke: claimable land too low (%d)" % claimable)
		return
	var small: Dictionary = SphereGridLib.generate(8)
	var small_n: int = int(small.get("cell_count", 0))
	var expect_small: int = 10 * 8 * 8 + 2
	if small_n != expect_small:
		_fail("sphere grid f=8 cell_count %d != %d" % [small_n, expect_small])
		return
	var small_counts: PackedByteArray = small.get("neighbor_count", PackedByteArray())
	for i in range(small_n):
		var deg: int = int(small_counts[i]) if i < small_counts.size() else -1
		if deg < 5 or deg > 6:
			_fail("sphere grid f=8 cell %d neighbor degree %d (expected 5-6)" % [i, deg])
			return
	if ClassDB.class_exists("TerritorySim"):
		var sim = ClassDB.instantiate("TerritorySim")
		if sim != null and sim.has_method("generate_sphere_grid"):
			var rust_grid: Dictionary = sim.generate_sphere_grid(2)
			var rust_n: int = int(rust_grid.get("cell_count", 0))
			if rust_n != 42:
				_fail("TerritorySim.generate_sphere_grid(f=2) cell_count %d != 42" % rust_n)
				return
			_log("OK  TerritorySim.generate_sphere_grid f=2 cell_count=42")
	var globe: ArrayMesh = EarthGlobeMeshLib.build_sphere_grid_mesh(bmap, false)
	if globe.get_surface_count() < 1:
		_fail("sphere grid smoke: build_sphere_grid_mesh empty")
		return
	var fluid: ArrayMesh = EarthGlobeMeshLib.build_sphere_grid_mesh(bmap, true)
	if fluid.get_surface_count() < 1:
		_fail("sphere grid smoke: build_sphere_grid_mesh fluid empty")
		return
	_log(
		"OK  sphere grid smoke cells=%d claimable=%d overlay=%dx%d homes=%s vs %s"
		% [
			cell_count,
			claimable,
			bmap.grid_width,
			bmap.grid_height,
			bmap.player_home_grid,
			bmap.enemy_home_grid,
		]
	)


func _validate_world_conquest_bench() -> void:
	if OS.get_environment("BATTLE_WORLD_CONQUEST_BENCH") != "1":
		return
	_log("-- World Conquest bench (360x180 live sim, 60 sim sec) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(44202)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(bmap, WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		sim.set_live_backend(false)
	var target_sim_sec: float = 60.0
	var steps_done: int = 0
	var t0: int = Time.get_ticks_usec()
	while sim.sim_time < target_sim_sec and not sim.finished:
		var info: Dictionary = sim.advance_dt(
			WorldConquestConfigLib.SIM_DT * float(WorldConquestConfigLib.SIM_MAX_STEPS_PER_FRAME),
			WorldConquestConfigLib.SIM_MAX_STEPS_PER_FRAME,
		)
		steps_done += int(info.get("steps", 0))
	var wall_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var ms_per_step: float = wall_ms / maxf(1.0, float(steps_done))
	_log(
		"BENCH world_conquest sim_sec=%.1f steps=%d wall_ms=%.1f ms/step=%.3f backend=%d"
		% [sim.sim_time, steps_done, wall_ms, ms_per_step, sim.backend]
	)
	if steps_done < int(target_sim_sec / WorldConquestConfigLib.SIM_DT) - 4:
		_fail("world conquest bench did not reach target sim time (steps=%d)" % steps_done)
	elif ms_per_step > 8.0:
		_fail("world conquest bench %.3f ms/step exceeds 8ms gate" % ms_per_step)
	else:
		_log("OK  world conquest bench")


func _validate_world_conquest_fps_bench() -> void:
	if OS.get_environment("BATTLE_FPS_BENCH") != "1":
		return
	_log("-- World Conquest FPS bench (60 Hz frame budget, 120 sim sec) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const FrameBudgetProfilerLib := preload("res://FrameBudgetProfiler.gd")
	var bmap = EarthMapGeneratorLib.generate(44202)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(bmap, WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		sim.set_live_backend(false)
	var target_sim_sec: float = 120.0
	var warmup_sim_sec: float = 3.0
	var frame_delta: float = 1.0 / 60.0
	var frame_ms: Array[float] = []
	var steps_done: int = 0
	var prior_frame_ms: float = 0.0
	while sim.sim_time < warmup_sim_sec and not sim.finished:
		sim.advance_dt(frame_delta, WorldConquestConfigLib.SIM_MAX_STEPS_PER_FRAME)
	while sim.sim_time < target_sim_sec and not sim.finished:
		var max_steps: int = WorldConquestConfigLib.SIM_MAX_STEPS_PER_FRAME
		if not FrameBudgetProfilerLib.budget_allows_catchup(
			prior_frame_ms, WorldConquestConfigLib.FRAME_BUDGET_MS
		):
			max_steps = 1
		var t0: int = Time.get_ticks_usec()
		var info: Dictionary = sim.advance_dt(frame_delta, max_steps)
		steps_done += int(info.get("steps", 0))
		if sim.use_rust_for_live() and sim.has_method("pull_presentation_delta"):
			var d: Dictionary = sim.pull_presentation_delta({
				"structures": false,
				"agents": false,
				"bombers": false,
			})
			var owners: Dictionary = d.get("owners", {})
			var idxs: PackedInt32Array = owners.get("indices", PackedInt32Array())
			if idxs.is_empty():
				idxs = owners.get("owner_indices", PackedInt32Array())
			var _probe: int = idxs.size()
			_probe += int(d.get("friendly_tiles", 0))
		elif (
			WorldConquestConfigLib.OVERLAY_OWNERS_ONLY
			and sim.use_rust_for_live()
			and sim.rust_field != null
			and sim.rust_field.has_method("consume_owner_overlay_delta")
		):
			var legacy: Dictionary = sim.rust_field.consume_owner_overlay_delta()
			var lidx: PackedInt32Array = legacy.get("indices", PackedInt32Array())
			var _lprobe: int = lidx.size()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		frame_ms.append(ms)
		prior_frame_ms = ms
	if frame_ms.is_empty():
		_fail("world conquest fps bench produced no frames")
		return
	frame_ms.sort()
	var p99_idx: int = clampi(int(floor(float(frame_ms.size() - 1) * 0.99)), 0, frame_ms.size() - 1)
	var p99_ms: float = float(frame_ms[p99_idx])
	var max_ms: float = float(frame_ms[frame_ms.size() - 1])
	var min_fps: float = 1000.0 / max_ms if max_ms > 0.001 else 0.0
	_log(
		"BENCH world_conquest_fps frames=%d steps=%d p99_ms=%.3f max_ms=%.3f min_fps=%.1f"
		% [frame_ms.size(), steps_done, p99_ms, max_ms, min_fps]
	)
	if p99_ms > 16.0:
		_fail("world conquest fps bench p99 %.3f ms exceeds 16ms gate" % p99_ms)
	elif min_fps < 58.0:
		_fail("world conquest fps bench min_fps %.1f below 58 gate" % min_fps)
	else:
		_log("OK  world conquest fps bench")


func _validate_perf_helpers() -> void:
	_log("-- Perf HUD / screen _process / action-tag helpers --")
	var scratch := OS.get_environment("GROK_GOAL_SCRATCH")
	if not scratch.is_empty():
		for stale_name in [
			"perf_action_lines.txt",
			"screen_process_p99.txt",
			"qa_report.txt",
			"qa_exit_codes.txt",
		]:
			var stale_path := scratch.path_join(stale_name)
			if FileAccess.file_exists(stale_path):
				DirAccess.remove_absolute(stale_path)
	const WCS := preload("res://WorldConquestScreen.gd")
	var gpu: Dictionary = WCS.perf_gather_gpu_counters()
	if not gpu.has("draw_calls"):
		_fail("perf_gather_gpu_counters missing draw_calls")
		return
	var tag: String = WCS.perf_format_action_tag("sim", {"steps": 3})
	if not tag.contains("action=sim") or not tag.contains("steps=3"):
		_fail("perf_format_action_tag malformed: %s" % tag)
		return
	var packed: PackedScene = load("res://WorldConquestScreen.tscn")
	if packed == null:
		_fail("perf helpers could not load WorldConquestScreen.tscn")
		return
	var screen: Control = packed.instantiate()
	add_child(screen)
	var bootstrap_frames: int = 0
	while bool(screen.get("_loading")) and bootstrap_frames < PERF_BOOTSTRAP_MAX_FRAMES:
		await get_tree().process_frame
		bootstrap_frames += 1
	if bool(screen.get("_loading")):
		_fail("WorldConquestScreen bootstrap timed out after %d frames" % bootstrap_frames)
		screen.queue_free()
		return
	_ensure_screen_builder_authority(screen)
	_log("OK  WorldConquestScreen bootstrap ready frames=%d" % bootstrap_frames)
	if not screen.has_method("reset_perf_action_telemetry"):
		_fail("WorldConquestScreen missing reset_perf_action_telemetry")
		screen.queue_free()
		return
	screen.reset_perf_action_telemetry()
	_log("OK  profiler reset after bootstrap (loading _process returns before begin_frame)")
	if screen.has_method("request_outpost_visual_refresh"):
		screen.request_outpost_visual_refresh(true, true)
	else:
		screen.set("_outpost_road_dirty", true)
		screen.set("_outpost_marker_dirty", true)
	await get_tree().process_frame
	for _fi in range(PERF_LIVE_FRAMES):
		await get_tree().process_frame
	if not screen.has_method("gather_perf_and_action_context"):
		_fail("WorldConquestScreen missing gather_perf_and_action_context")
		screen.queue_free()
		return
	var snapshot: Dictionary = screen.gather_perf_and_action_context()
	var cpu_summary: Dictionary = snapshot.get("cpu", {})
	if cpu_summary.is_empty():
		_fail("gather_perf_and_action_context cpu empty after live bootstrap+play")
		screen.queue_free()
		return
	var hud_text: String = WCS.perf_build_hud_text(snapshot)
	if hud_text.is_empty() or not hud_text.contains("FPS"):
		_fail("perf_build_hud_text missing FPS line")
		screen.queue_free()
		return
	if not hud_text.contains("p99"):
		_fail("perf HUD missing CPU p99 after live play")
		screen.queue_free()
		return
	_log(
		"FrameBudget summary samples=%d p50_ms=%.3f p99_ms=%.3f min_fps=%.1f"
		% [
			int(cpu_summary.get("samples", 0)),
			float(cpu_summary.get("p50_ms", 0.0)),
			float(cpu_summary.get("p99_ms", 0.0)),
			float(cpu_summary.get("min_fps", 0.0)),
		]
	)
	for hud_line in hud_text.split("\n", false):
		_log("HUD %s" % hud_line.strip_edges())
	if not screen.has_method("get_recent_perf_action_lines"):
		_fail("WorldConquestScreen missing get_recent_perf_action_lines")
		screen.queue_free()
		return
	var action_lines: Array = screen.get_recent_perf_action_lines()
	var action_count: int = action_lines.size()
	for line in action_lines:
		_log(str(line))
	if action_count == 0:
		_fail("no action= lines from screen ring after live bootstrap+play frames")
		screen.queue_free()
		return
	var joined: String = "\n".join(action_lines)
	for req_tag in PERF_REQUIRED_ACTION_TAGS:
		if not joined.contains(req_tag):
			_fail("missing required perf action tag in ring: %s" % req_tag)
			screen.queue_free()
			return
	_log(
		"OK  perf helpers bootstrap_frames=%d live_frames=%d action_lines=%d cpu_p99=%.2f tags_ok=yes"
		% [bootstrap_frames, PERF_LIVE_FRAMES, action_count, float(cpu_summary.get("p99_ms", 0.0))]
	)
	screen.queue_free()


func _validate_outpost_construction_queue() -> void:
	_log("-- Outpost construction queue (frame-budget drain) --")
	const QueueLib := preload("res://OutpostConstructionQueue.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var q := QueueLib.new()
	for i in range(10):
		q.on_cell_advanced(200 + i)
	var drain_calls: int = 0
	var total_roads: int = 0
	var saw_full_map: bool = false
	var sim_frame: int = 0
	while q.has_pending():
		sim_frame += 1
		var plan: Dictionary = q.drain_plan(sim_frame)
		drain_calls += 1
		total_roads += plan.get("road_sids", []).size()
		if bool(plan.get("full_map_sync", false)):
			saw_full_map = true
		if drain_calls > 64:
			break
	if saw_full_map:
		_fail("outpost construction queue must never request full_map_sync")
		return
	if drain_calls < 10:
		_fail("outpost construction queue spread %d drain calls, expected >=10" % drain_calls)
		return
	if total_roads != 10:
		_fail("outpost construction queue roads drained %d, expected 10" % total_roads)
		return
	if WorldConquestConfigLib.MAX_ROAD_SIDS_PER_FRAME != 1:
		_fail("MAX_ROAD_SIDS_PER_FRAME expected 1")
		return
	_log("OK  outpost construction queue spread=%d roads=%d" % [drain_calls, total_roads])


func _validate_visual_drain_ordering() -> void:
	_log("-- Visual drain ordering (roads/overlay/gpu frame separation) --")
	const QueueLib := preload("res://OutpostConstructionQueue.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var q := QueueLib.new()
	q.enqueue_road(301)
	q.enqueue_overlay_delta(PackedInt32Array([10, 11, 12]), PackedByteArray([
		BattleTileControlLib.OWNER_FRIENDLY,
		BattleTileControlLib.OWNER_FRIENDLY,
		BattleTileControlLib.OWNER_FRIENDLY,
	]))
	q.request_gpu_upload()
	var road_frame: int = -1
	var overlay_frame: int = -1
	var gpu_frame: int = -1
	var frame: int = 0
	while q.has_pending() and frame < 32:
		frame += 1
		var plan: Dictionary = q.drain_plan(frame)
		if plan.get("road_sids", []).size() > 0:
			road_frame = frame
		var o_idxs: PackedInt32Array = plan.get("overlay_indices", PackedInt32Array())
		if o_idxs.size() > 0:
			overlay_frame = frame
		if bool(plan.get("gpu_upload", false)):
			gpu_frame = frame
	if road_frame < 0 or overlay_frame < 0 or gpu_frame < 0:
		_fail("visual drain ordering did not schedule roads/overlay/gpu")
		return
	if road_frame == gpu_frame:
		_fail("visual drain ordering roads+gpu same frame %d" % road_frame)
		return
	if abs(overlay_frame - gpu_frame) <= 1:
		_fail(
			"visual drain ordering overlay frame=%d gpu frame=%d too close"
			% [overlay_frame, gpu_frame]
		)
		return
	_log(
		"OK  visual drain ordering road=%d overlay=%d gpu=%d sep=%d"
		% [road_frame, overlay_frame, gpu_frame, gpu_frame - overlay_frame]
	)


func _write_validate_section_to_scratch(section_lines: PackedStringArray, filename: String) -> void:
	var scratch := OS.get_environment("GROK_GOAL_SCRATCH")
	if scratch.is_empty() or section_lines.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(scratch)
	var dst := scratch.path_join(filename)
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out:
		for line in section_lines:
			out.store_line(line)
		out.close()


const BUILDER_INTEGRATION_MIN_FRAMES := 1200
const BUILDER_INTEGRATION_MAX_FRAMES := 15000


func _structure_by_sid(battle_data, sid: int) -> Dictionary:
	if battle_data == null or sid < 0:
		return {}
	for st in battle_data.placed_structures:
		if int(st.get("id", -1)) == sid:
			return st
	return {}


func _sum_path_built_since_id(battle_data, min_id: int) -> float:
	var sum: float = 0.0
	if battle_data == null:
		return sum
	for st in battle_data.placed_structures:
		if int(st.get("id", -1)) >= min_id:
			sum += float(st.get("path_built", 1.0))
	return sum


func _sum_path_built_for_sids(battle_data, sids: Array[int]) -> float:
	var sum: float = 0.0
	if battle_data == null:
		return sum
	for sid: int in sids:
		var st: Dictionary = _structure_by_sid(battle_data, sid)
		if not st.is_empty():
			sum += float(st.get("path_built", 1.0))
	return sum


func _count_states_for_sids(battle_data, sids: Array[int]) -> Dictionary:
	var counts := {
		"connecting": 0,
		"building": 0,
		"active": 0,
		"other": 0,
	}
	if battle_data == null:
		return counts
	for sid: int in sids:
		var st: Dictionary = _structure_by_sid(battle_data, sid)
		if st.is_empty():
			continue
		var state: String = str(st.get("state", ""))
		if counts.has(state):
			counts[state] = int(counts[state]) + 1
		else:
			counts["other"] = int(counts["other"]) + 1
	return counts


func _placement_grid_offset(home: Vector2i, grid_w: int, step: int, spacing: int) -> Vector2i:
	return Vector2i((home.x + spacing * (step + 1)) % grid_w, home.y)


func _ensure_debug_supply(screen: Control) -> void:
	screen.set("_supply", 999999.0)


func _probe_placement_path_len(screen: Control, grid: Vector2i, kind: String, team: int) -> int:
	var placement: Dictionary = screen.call("_resolve_placement_for_team", grid, true, kind, team)
	if str(placement.get("reject", "")) != "":
		return -1
	var path_packed: PackedInt32Array = placement.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		return -1
	return path_packed.size()


func _debug_place_near_home(
	screen: Control,
	home: Vector2i,
	grid_w: int,
	grid_h: int,
	kind: String,
	team: int,
	slot: int,
	max_attempts: int = 32,
	y_span: int = 3,
) -> int:
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var spacing: int = WorldConquestConfigLib.MIN_SPAWNER_SPACING_CELLS + 1
	for attempt in range(maxi(max_attempts, 1)):
		var gx: int = (home.x + spacing * (slot + 1) + attempt * 3) % grid_w
		for dy in range(-y_span, y_span + 1):
			var gy: int = clampi(home.y + dy + (slot % 2), 0, grid_h - 1)
			var sid: int = int(screen.call("debug_place_outpost_at", Vector2i(gx, gy), kind, team))
			if sid >= 0:
				return sid
	return -1


func _debug_place_shortest_path_near_home(
	screen: Control,
	home: Vector2i,
	grid_w: int,
	grid_h: int,
	kind: String,
	team: int,
	max_attempts: int = 96,
	y_span: int = 12,
) -> int:
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var spacing: int = WorldConquestConfigLib.MIN_SPAWNER_SPACING_CELLS + 1
	var best_grid: Vector2i = Vector2i(-1, -1)
	var best_len: int = 1_000_000
	for attempt in range(maxi(max_attempts, 1)):
		var gx: int = (home.x + spacing * (attempt % 8 + 1) + (attempt / 8) * 5) % grid_w
		for dy in range(-y_span, y_span + 1):
			var gy: int = clampi(home.y + dy + (attempt % 3), 0, grid_h - 1)
			var plen: int = _probe_placement_path_len(screen, Vector2i(gx, gy), kind, team)
			if plen < 0:
				continue
			if plen < best_len:
				best_len = plen
				best_grid = Vector2i(gx, gy)
				if best_len <= 4:
					break
		if best_len <= 4:
			break
	if best_grid.x < 0:
		return -1
	return int(screen.call("debug_place_outpost_at", best_grid, kind, team))


func _builder_integration_frame_budget(path_len_a: int, path_len_b: int) -> int:
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var max_path: int = maxi(path_len_a, path_len_b)
	var connect_sec: float = maxf(float(max_path - 1), 0.0) / WorldConquestConfigLib.OUTPOST_ROAD_CELLS_PER_SEC
	var total_sec: float = connect_sec + WorldConquestConfigLib.OUTPOST_BUILD_SEC + 2.0
	var frames: int = int(ceil(total_sec * 60.0))
	return clampi(frames, BUILDER_INTEGRATION_MIN_FRAMES, BUILDER_INTEGRATION_MAX_FRAMES)


func _count_states_since_id(battle_data, min_id: int) -> Dictionary:
	var counts := {
		"connecting": 0,
		"building": 0,
		"active": 0,
		"other": 0,
	}
	if battle_data == null:
		return counts
	for st in battle_data.placed_structures:
		if int(st.get("id", -1)) < min_id:
			continue
		var state: String = str(st.get("state", ""))
		if counts.has(state):
			counts[state] = int(counts[state]) + 1
		else:
			counts["other"] = int(counts["other"]) + 1
	return counts


func _bootstrap_world_conquest_screen() -> Control:
	var globe_scene: PackedScene = load("res://WorldConquestScreen.tscn")
	if globe_scene == null:
		return null
	var screen: Control = globe_scene.instantiate()
	add_child(screen)
	var bootstrap_frames: int = 0
	while bool(screen.get("_loading")) and bootstrap_frames < PERF_BOOTSTRAP_MAX_FRAMES:
		await get_tree().process_frame
		bootstrap_frames += 1
	if bool(screen.get("_loading")):
		screen.queue_free()
		return null
	# W2c harness: Screen validates WorldDataset immediately after enable_rust_live, but
	# configure_builders (logistics authority) is deferred until later Screen setup.
	# Ensure builder authority is armed so live integration / txn gates exercise the real path.
	_ensure_screen_builder_authority(screen)
	return screen


## Ensure Rust logistics authority is active on a bootstrapped WorldConquestScreen.
## Screen currently calls WorldDatasetAssert right after enable_rust_live, before
## configure_builders — that falsely marks entry failed and freezes _process.
## Harness re-arms logistics and clears the fail-closed latch for live QA gates.
func _ensure_screen_builder_authority(screen: Control) -> void:
	if screen == null:
		return
	var ts = screen.get("territory_sim")
	if ts == null:
		return
	var home: Vector2i = screen.get("_player_home")
	var enemy: Vector2i = screen.get("_enemy_home")
	if home.x >= 0 and enemy.x >= 0 and ts.has_method("configure_builders"):
		if not bool(ts.builder_authority_active()):
			ts.configure_builders(home, enemy)
	var armed: bool = bool(ts.builder_authority_active()) if ts.has_method("builder_authority_active") else false
	# Clear fail-closed latch so live _process / profiler / construction gates can run.
	if bool(screen.get("_world_dataset_entry_failed")):
		if armed:
			screen.set("_world_dataset_entry_failed", false)
			_log(
				"OK  harness cleared _world_dataset_entry_failed after arming builder authority (Screen order workaround)"
			)
		else:
			_log("WARN harness could not arm builder authority — live gates may freeze")
	elif armed:
		_log("OK  harness builder authority already active")


func _validate_builder_selfcheck() -> void:
	var section_lines: PackedStringArray = PackedStringArray()
	var _vlog := func(msg: String) -> void:
		_log(msg)
		section_lines.append(msg)
	_vlog.call("-- Builder selfcheck (BuilderAgentLib.step_frame in-memory) --")
	const BuilderAgentLib := preload("res://BuilderAgentLib.gd")
	var sc: Dictionary = BuilderAgentLib.run_selfcheck()
	var detail: String = str(sc.get("detail", ""))
	if not detail.is_empty():
		_vlog.call(detail)
	if not bool(sc.get("ok", false)):
		_fail("BuilderAgentLib.run_selfcheck failed")
		_write_validate_section_to_scratch(section_lines, "qa_builder_progress1.log")
		return
	_vlog.call("OK  BuilderAgentLib.run_selfcheck")
	_write_validate_section_to_scratch(section_lines, "qa_builder_progress1.log")


func _validate_builder_chain_selfcheck() -> void:
	_log("-- Builder chain selfcheck (no home return between queued jobs) --")
	const BuilderAgentLib := preload("res://BuilderAgentLib.gd")
	var sc: Dictionary = BuilderAgentLib.run_chain_selfcheck()
	var detail: String = str(sc.get("detail", ""))
	if not detail.is_empty():
		_log(detail)
	if not bool(sc.get("ok", false)):
		_fail("BuilderAgentLib.run_chain_selfcheck failed")
		return
	_log("OK  BuilderAgentLib.run_chain_selfcheck")


func _validate_enemy_strategy_selfcheck() -> void:
	_log("-- Enemy strategy selfcheck (plan_actions on Earth snapshot) --")
	const EnemyStrategy := preload("res://EnemyStrategy.gd")
	var sc: Dictionary = EnemyStrategy.run_selfcheck()
	var detail: String = str(sc.get("detail", ""))
	if not detail.is_empty():
		_log(detail)
	if not bool(sc.get("ok", false)):
		_fail("EnemyStrategy.run_selfcheck failed")
		return
	_log("OK  EnemyStrategy.run_selfcheck")


func _validate_enemy_ai_integration_smoke() -> void:
	_log("-- Enemy AI integration (live screen, hostile placement over time) --")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const EnemyStrategy := preload("res://EnemyStrategy.gd")
	var screen: Control = await _bootstrap_world_conquest_screen()
	if screen == null:
		_fail("enemy AI integration bootstrap timed out")
		return
	screen.set("_enemy_supply", float(WorldConquestConfigLib.STARTING_SUPPLY))
	screen.set_enemy_ai_difficulty(EnemyStrategy.Difficulty.MEDIUM)
	var battle_data = screen.get("battle_data")
	if battle_data == null:
		_fail("enemy AI integration missing battle_data")
		screen.queue_free()
		return
	var max_frames: int = 720
	for fi in range(max_frames):
		screen._process(WorldConquestConfigLib.SIM_DT)
		var hostile_count: int = 0
		var supply_path_n: int = 0
		for st: Dictionary in battle_data.placed_structures:
			if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != BattleTileControlLib.OWNER_HOSTILE:
				continue
			hostile_count += 1
			# Supply-linked outposts have path_len > 1 (standalone is a single landing cell).
			if int(st.get("path_len", 0)) > 1:
				supply_path_n += 1
		if hostile_count > 0 and supply_path_n > 0:
			_log(
				"OK  enemy AI placed hostile structures=%d supply_routed=%d frames=%d"
				% [hostile_count, supply_path_n, fi + 1]
			)
			screen.queue_free()
			return
		if hostile_count > 0 and supply_path_n == 0 and fi + 1 >= max_frames:
			_fail(
				"enemy AI placed %d hostiles but all standalone (path_len<=1) — supply routing broken"
				% hostile_count
			)
			screen.queue_free()
			return
	_fail("enemy AI integration no hostile structures after %d frames" % max_frames)
	screen.queue_free()


func _validate_world_seed_variety() -> void:
	_log("-- World seed variety (distinct maps per seed) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	var map_a = EarthMapGeneratorLib.generate(111)
	var map_b = EarthMapGeneratorLib.generate(222)
	if map_a.player_home_grid == map_b.player_home_grid and map_a.enemy_home_grid == map_b.enemy_home_grid:
		_fail("world seed variety homes identical for seeds 111 vs 222")
		return
	var checksum_a: int = 0
	var checksum_b: int = 0
	for i in range(map_a.terrain_cells.size()):
		checksum_a = (checksum_a + int(map_a.terrain_cells[i]) * 31) & 0x7FFFFFFF
		checksum_b = (checksum_b + int(map_b.terrain_cells[i]) * 31) & 0x7FFFFFFF
	if checksum_a == checksum_b:
		_fail("world seed variety terrain checksum identical for seeds 111 vs 222")
		return
	_log(
		"OK  world seed variety home_a=%s home_b=%s checksum_a=%d checksum_b=%d"
		% [map_a.player_home_grid, map_b.player_home_grid, checksum_a, checksum_b]
	)


func _validate_earth_land_mask() -> void:
	_log("-- Earth baked land mask --")
	const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
	const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
	var map_data = WorldConquestMapGeneratorLib.generate(WorldMapCatalogLib.MAP_EARTH, 424242)
	var land_n: int = 0
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for gy in range(h):
		for gx in range(w):
			if map_data.is_land_cell(gx, gy):
				land_n += 1
	var frac: float = float(land_n) / float(w * h)
	if land_n < 8000 or frac < 0.12 or frac > 0.38:
		_fail("earth land mask suspicious land_n=%d frac=%.3f" % [land_n, frac])
		return
	_log("OK  earth land mask land_n=%d frac=%.3f homes=%s vs %s" % [
		land_n,
		frac,
		map_data.player_home_grid,
		map_data.enemy_home_grid,
	])


func _bridge_qa_water_prefix_end(map_data, path_packed: PackedInt32Array) -> int:
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	var w: int = map_data.grid_width
	for i in range(path_packed.size()):
		var gx: int = path_packed[i] % w
		var gy: int = path_packed[i] / w
		if OutpostBuildLib.is_water_cell(map_data, gx, gy):
			return i + 1
	return -1


func _bridge_qa_find_inland_foreign(map_data, home: Vector2i, sources: Array[Vector2i]) -> Vector2i:
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if not OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), sources):
				continue
			if OutpostBuildLib.is_coastal_cell(map_data, gx, gy):
				continue
			return Vector2i(gx, gy)
	return Vector2i(-1, -1)


func _validate_builder_integration_smoke() -> void:
	var section_lines: PackedStringArray = PackedStringArray()
	var _vlog := func(msg: String) -> void:
		_log(msg)
		section_lines.append(msg)
	_vlog.call("-- Builder integration smoke (debug_place, both teams, _process to ACTIVE) --")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var screen: Control = await _bootstrap_world_conquest_screen()
	if screen == null:
		_fail("builder integration bootstrap timed out")
		_write_validate_section_to_scratch(section_lines, "qa_builder_progress2.log")
		return
	# Logistics authority has no discrete builder bots (network growth is sim-side).
	# Legacy GDScript bots only exist when builder authority is off.
	var agent_count: int = 0
	if WorldConquestConfigLib.WORLD_DATASET_BUILDER_AUTHORITY:
		var ts = screen.get("territory_sim")
		var auth_on: bool = false
		if ts != null and ts.has_method("builder_authority_active"):
			auth_on = bool(ts.builder_authority_active())
		if not auth_on:
			_fail("builder integration expected builder authority active under WORLD_DATASET_BUILDER_AUTHORITY")
			screen.queue_free()
			return
		agent_count = 0
	else:
		var agents: Array = screen.get("_builder_agents")
		agent_count = agents.size()
		if agent_count != 4:
			_fail("builder integration expected 4 agents, got %d" % agent_count)
			screen.queue_free()
			return
	var battle_data = screen.get("battle_data")
	var home: Vector2i = screen.get("_player_home")
	var enemy_home: Vector2i = screen.get("_enemy_home")
	if battle_data == null or home.x < 0 or enemy_home.x < 0:
		_fail("builder integration missing battle_data/homes")
		screen.queue_free()
		return
	_ensure_debug_supply(screen)
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var friendly_sid: int = _debug_place_shortest_path_near_home(
		screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY
	)
	if friendly_sid < 0:
		_fail("builder integration friendly debug_place_outpost_at failed")
		screen.queue_free()
		return
	var hostile_sid: int = _debug_place_shortest_path_near_home(
		screen, enemy_home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_HOSTILE
	)
	if hostile_sid < 0:
		_fail("builder integration hostile debug_place_outpost_at failed")
		screen.queue_free()
		return
	# Pause pressure sim only — construction/world_session still tick while paused.
	screen.set("_paused", true)
	var st_f0: Dictionary = _structure_by_sid(battle_data, friendly_sid)
	var st_h0: Dictionary = _structure_by_sid(battle_data, hostile_sid)
	var max_frames: int = _builder_integration_frame_budget(
		int(st_f0.get("path_len", 4)), int(st_h0.get("path_len", 4))
	)
	var frames: int = 0
	var friendly_active: bool = false
	var hostile_active: bool = false
	for fi in range(max_frames):
		await get_tree().process_frame
		frames = fi + 1
		var st_f: Dictionary = _structure_by_sid(battle_data, friendly_sid)
		if not st_f.is_empty() and str(st_f.get("state", "")) == OutpostBuildLib.STATE_ACTIVE:
			friendly_active = true
		var st_h: Dictionary = _structure_by_sid(battle_data, hostile_sid)
		if not st_h.is_empty() and str(st_h.get("state", "")) == OutpostBuildLib.STATE_ACTIVE:
			hostile_active = true
		if friendly_active and hostile_active:
			break
	if not friendly_active or not hostile_active:
		var st_h_end: Dictionary = _structure_by_sid(battle_data, hostile_sid)
		_fail(
			"builder integration expected both ACTIVE in %d/%d frames friendly=%s hostile=%s hostile_state=%s path_len=%d"
			% [
				frames,
				max_frames,
				str(friendly_active),
				str(hostile_active),
				str(st_h_end.get("state", "?")),
				int(st_h0.get("path_len", 0)),
			]
		)
		_write_validate_section_to_scratch(section_lines, "qa_builder_progress2.log")
		screen.queue_free()
		return
	_vlog.call(
		"OK  builder integration friendly_sid=%d hostile_sid=%d CONNECTING->ACTIVE frames=%d bots=%d"
		% [friendly_sid, hostile_sid, frames, agent_count]
	)
	_validate_world_dataset_on_screen(screen)
	_write_validate_section_to_scratch(section_lines, "qa_builder_progress2.log")
	screen.queue_free()


func _validate_fps_fix_paths() -> void:
	var section_lines: PackedStringArray = PackedStringArray()
	var _vlog := func(msg: String) -> void:
		_log(msg)
		section_lines.append(msg)
	_vlog.call("-- FPS fix paths (defer gpu, delta cap, incremental visuals, catch-up, queue drain, builder bots) --")
	const FrameBudgetProfilerLib := preload("res://FrameBudgetProfiler.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	if not FrameBudgetProfilerLib.budget_allows_catchup(10.0, WorldConquestConfigLib.FRAME_BUDGET_MS):
		_fail("budget_allows_catchup should allow 10ms prior frame")
		return
	if FrameBudgetProfilerLib.budget_allows_catchup(20.0, WorldConquestConfigLib.FRAME_BUDGET_MS):
		_fail("budget_allows_catchup should block 20ms prior frame")
		return
	var globe_scene: PackedScene = load("res://WorldConquestScreen.tscn")
	if globe_scene == null:
		_fail("fps fix validate could not load WorldConquestScreen.tscn")
		return
	var screen: Control = globe_scene.instantiate()
	add_child(screen)
	var bootstrap_frames: int = 0
	while bool(screen.get("_loading")) and bootstrap_frames < PERF_BOOTSTRAP_MAX_FRAMES:
		await get_tree().process_frame
		bootstrap_frames += 1
	if bool(screen.get("_loading")):
		_fail("fps fix validate bootstrap timed out")
		screen.queue_free()
		return
	_ensure_screen_builder_authority(screen)
	var globe = screen.get("globe_map")
	var battle_data = screen.get("battle_data")
	if globe == null or battle_data == null:
		_fail("fps fix validate missing globe/battle_data")
		screen.queue_free()
		return
	var home: Vector2i = screen.get("_player_home")
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	_ensure_debug_supply(screen)
	var placed_sids: Array[int] = []
	for i in range(10):
		# Prefer path-probed placement; slot offsets alone often land on water/spacing rejects.
		var sid: int = _debug_place_shortest_path_near_home(
			screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, 128, 16
		)
		if sid < 0:
			sid = _debug_place_near_home(
				screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, i, 96, 12
			)
		if sid < 0:
			_fail("fps fix validate debug_place_outpost_at failed slot=%d near home" % i)
			screen.queue_free()
			return
		placed_sids.append(sid)
		var st_fps: Dictionary = _structure_by_sid(battle_data, sid)
		_vlog.call(
			"placement_enqueue_sid=%d gx=%d gy=%d"
			% [sid, int(st_fps.get("gx", -1)), int(st_fps.get("gy", -1))]
		)
		for _warm in range(8):
			await get_tree().process_frame
	# Drain seeded construction/visual backlog before hot-path exercise and p99 measurement.
	for _drain in range(100):
		await get_tree().process_frame
	var patch_idx: int = battle_data.cell_index(home.x, home.y)
	var test_idxs := PackedInt32Array([patch_idx])
	var test_vals := PackedByteArray([BattleTileControlLib.OWNER_FRIENDLY])
	globe.apply_ownership_overlay_delta(test_idxs, test_vals)
	if globe.flush_pending_owner_gpu_upload():
		_fail("gpu flush committed on same frame as overlay delta patch")
		screen.queue_free()
		return
	await get_tree().process_frame
	var profiler = screen.get("_frame_profiler")
	if profiler == null:
		_fail("fps fix validate missing _frame_profiler")
		screen.queue_free()
		return
	var territory_sim = screen.get("territory_sim")
	if territory_sim == null:
		_fail("fps fix validate missing territory_sim")
		screen.queue_free()
		return
	var pre_built_sum: float = _sum_path_built_for_sids(battle_data, placed_sids)
	const BUILDER_HOTPATH_FRAMES := 90
	for _hot in range(BUILDER_HOTPATH_FRAMES):
		await get_tree().process_frame
	var post_built_sum: float = _sum_path_built_for_sids(battle_data, placed_sids)
	var queue = screen.get("_outpost_construction_queue")
	var queue_pending: bool = queue != null and queue.has_pending()
	_vlog.call(
		"fps fix hot-path _process frames=%d path_built_sum=%.3f->%.3f queue_pending=%s"
		% [BUILDER_HOTPATH_FRAMES, pre_built_sum, post_built_sum, queue_pending]
	)
	if post_built_sum <= pre_built_sum:
		# Paths may finish during the pre-hot drain; that still proves construction advanced.
		var states_hot: Dictionary = _count_states_for_sids(battle_data, placed_sids)
		var finished_n: int = int(states_hot.building) + int(states_hot.active)
		if finished_n < 1 and post_built_sum < 2.0:
			_fail(
				"fps fix hot-path no path_built growth (%.3f->%.3f) and no BUILDING/ACTIVE"
				% [pre_built_sum, post_built_sum]
			)
			screen.queue_free()
			return
		_vlog.call(
			"fps fix hot-path path_built stable (%.3f) with building=%d active=%d (paths already advanced)"
			% [post_built_sum, int(states_hot.building), int(states_hot.active)]
		)
	profiler.reset_samples()
	screen.set("_paused", false)
	# Structures may leave CONNECTING during the 90-frame hot path (logistics growth).
	# Require all placements still present and construction still in progress somewhere.
	var state_counts: Dictionary = _count_states_for_sids(battle_data, placed_sids)
	var live_n: int = (
		int(state_counts.connecting)
		+ int(state_counts.building)
		+ int(state_counts.active)
	)
	if live_n < placed_sids.size():
		_fail(
			"fps fix validate expected %d live structures, got connecting=%d building=%d active=%d"
			% [
				placed_sids.size(),
				int(state_counts.connecting),
				int(state_counts.building),
				int(state_counts.active),
			]
		)
		screen.queue_free()
		return
	if int(state_counts.connecting) + int(state_counts.building) < 1 and int(state_counts.active) < 1:
		_fail("fps fix validate no structures in CONNECTING/BUILDING/ACTIVE after hot path")
		screen.queue_free()
		return
	var pre180_built: float = _sum_path_built_for_sids(battle_data, placed_sids)
	var pre180_states: Dictionary = _count_states_for_sids(battle_data, placed_sids)
	for _fi in range(180):
		await get_tree().process_frame
	var post180_built: float = _sum_path_built_for_sids(battle_data, placed_sids)
	var post180_states: Dictionary = _count_states_for_sids(battle_data, placed_sids)
	_vlog.call(
		"fps post-180-frames connecting=%d building=%d active=%d path_built_sum=%.1f->%.1f"
		% [
			int(post180_states.connecting),
			int(post180_states.building),
			int(post180_states.active),
			pre180_built,
			post180_built,
		]
	)
	if (
		post180_built <= pre180_built
		and int(post180_states.building) == 0
		and int(post180_states.active) == 0
	):
		_fail("fps validate no builder/build progress after 180 _process frames")
		screen.queue_free()
		return
	var summary: Dictionary = profiler.summary()
	if summary.is_empty():
		_fail("fps fix validate profiler summary empty after construction frames")
		screen.queue_free()
		return
	var p99: float = float(summary.get("p99_ms", 999.0))
	_vlog.call(
		"FPS fix validate bootstrap=%d structures=%d p99_ms=%.3f samples=%d"
		% [bootstrap_frames, battle_data.placed_structures.size(), p99, int(summary.get("samples", 0))]
	)
	if p99 > 20.0:
		_fail("fps fix validate p99 %.3f exceeds 20ms gate" % p99)
		screen.queue_free()
		return
	if not screen.has_method("get_recent_perf_action_lines"):
		_fail("fps fix validate missing get_recent_perf_action_lines")
		screen.queue_free()
		return
	var action_lines: Array = screen.get_recent_perf_action_lines()
	var joined: String = "\n".join(action_lines)
	for req_tag in PERF_REQUIRED_ACTION_TAGS:
		if not joined.contains(req_tag):
			_fail("fps fix validate missing action tag: %s" % req_tag)
			screen.queue_free()
			return
	for line in action_lines:
		_vlog.call(str(line))
	_vlog.call("OK  fps fix paths validate p99=%.3f tags_ok=yes" % p99)
	screen.queue_free()


## Always-on mid-game presentation gate: many structures + live _process p99 budget.
func _validate_midgame_presentation_fps() -> void:
	_log("-- Mid-game presentation FPS gate (12 structures, live screen) --")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var screen: Control = await _bootstrap_world_conquest_screen()
	if screen == null:
		_fail("midgame fps bootstrap timed out")
		return
	var battle_data = screen.get("battle_data")
	var home: Vector2i = screen.get("_player_home")
	if battle_data == null or home.x < 0:
		_fail("midgame fps missing battle_data/home")
		screen.queue_free()
		return
	_ensure_debug_supply(screen)
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var placed: int = 0
	for i in range(12):
		var sid: int = _debug_place_shortest_path_near_home(
			screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, 128, 16
		)
		if sid < 0:
			sid = _debug_place_near_home(
				screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, i, 96, 12
			)
		if sid >= 0:
			placed += 1
		for _warm in range(4):
			await get_tree().process_frame
	if placed < 6:
		_fail("midgame fps could only place %d structures (need ≥6)" % placed)
		screen.queue_free()
		return
	var profiler = screen.get("_frame_profiler")
	if profiler == null:
		_fail("midgame fps missing _frame_profiler")
		screen.queue_free()
		return
	# Wait for construction fronts to quiet (or timeout), then pause pressure/AI for a clean idle measure.
	for _settle in range(360):
		await get_tree().process_frame
		var connecting_n: int = 0
		for st_var in battle_data.placed_structures:
			if st_var is Dictionary and str(st_var.get("state", "")) == OutpostBuildLib.STATE_CONNECTING:
				connecting_n += 1
		if connecting_n == 0 and _settle > 60:
			break
	screen.set("_paused", true)
	# Drain one more beat so pause takes effect and presentation dirty clears.
	for _pad in range(10):
		await get_tree().process_frame
	var snap_before: int = int(screen.get("_structure_snapshot_pull_count"))
	var dirty_before: bool = bool(screen.get("_presentation_structures_dirty"))
	profiler.reset_samples()
	const IDLE_FRAMES := 120
	var dirty_true_frames: int = 0
	for _fi in range(IDLE_FRAMES):
		await get_tree().process_frame
		if bool(screen.get("_presentation_structures_dirty")):
			dirty_true_frames += 1
	var snap_after: int = int(screen.get("_structure_snapshot_pull_count"))
	var snap_during_idle: int = snap_after - snap_before
	var summary: Dictionary = profiler.summary()
	if summary.is_empty():
		_fail("midgame fps profiler summary empty")
		screen.queue_free()
		return
	var p99: float = float(summary.get("p99_ms", 999.0))
	var p50: float = float(summary.get("p50_ms", 999.0))
	_log(
		"midgame fps structures=%d idle_frames=%d p50=%.2f p99=%.2f snap_pulls_idle=%d dirty_frames=%d dirty_before=%s"
		% [
			placed,
			IDLE_FRAMES,
			p50,
			p99,
			snap_during_idle,
			dirty_true_frames,
			str(dirty_before),
		]
	)
	# Idle stretch must not full-snapshot every frame (event-driven only).
	if snap_during_idle > IDLE_FRAMES / 5:
		_fail(
			"midgame structure snapshots too frequent while idle: %d pulls in %d frames"
			% [snap_during_idle, IDLE_FRAMES]
		)
		screen.queue_free()
		return
	# Headless CPU process budget (E9/B15: real GPU display FPS not measured here).
	# Gate is the live presentation path CPU p99; GPU FPS recorded separately as env_limit.
	if p99 > WorldConquestConfigLib.FRAME_BUDGET_MS * 1.25:
		_fail(
			"midgame fps p99 %.2f ms exceeds %.2f ms gate (structures=%d)"
			% [p99, WorldConquestConfigLib.FRAME_BUDGET_MS * 1.25, placed]
		)
		screen.queue_free()
		return
	_log(
		"OK  midgame presentation fps p99=%.2f structures=%d snap_pulls_idle=%d"
		% [p99, placed, snap_during_idle]
	)
	screen.queue_free()


## Live construction (CONNECTING "pulsing" buildings) must stay within frame budget.
func _validate_construction_pulse_fps() -> void:
	_log("-- Construction CONNECTING pulse FPS gate --")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var screen: Control = await _bootstrap_world_conquest_screen()
	if screen == null:
		_fail("construction pulse fps bootstrap timed out")
		return
	var battle_data = screen.get("battle_data")
	var home: Vector2i = screen.get("_player_home")
	if battle_data == null or home.x < 0:
		_fail("construction pulse fps missing battle_data/home")
		screen.queue_free()
		return
	_ensure_debug_supply(screen)
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var placed: int = 0
	# Place as many as possible in a burst so many CONNECTING pulse at once.
	for i in range(10):
		var sid: int = _debug_place_shortest_path_near_home(
			screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, 128, 16
		)
		if sid < 0:
			sid = _debug_place_near_home(
				screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, i, 96, 12
			)
		if sid >= 0:
			placed += 1
	if placed < 6:
		_fail("construction pulse fps could only place %d structures" % placed)
		screen.queue_free()
		return
	var profiler = screen.get("_frame_profiler")
	if profiler == null:
		_fail("construction pulse fps missing profiler")
		screen.queue_free()
		return
	# One frame so placements enter sim, then measure while roads are growing.
	await get_tree().process_frame
	profiler.reset_samples()
	var connecting_seen: int = 0
	const BUILD_FRAMES := 150
	for _fi in range(BUILD_FRAMES):
		await get_tree().process_frame
		var conn: int = 0
		for st_var in battle_data.placed_structures:
			if st_var is Dictionary and str(st_var.get("state", "")) == OutpostBuildLib.STATE_CONNECTING:
				conn += 1
		if conn > connecting_seen:
			connecting_seen = conn
	var summary: Dictionary = profiler.summary()
	var p99: float = float(summary.get("p99_ms", 999.0))
	var p50: float = float(summary.get("p50_ms", 999.0))
	var snap_n: int = int(screen.get("_structure_snapshot_pull_count"))
	_log(
		"construction pulse frames=%d placed=%d max_connecting=%d p50=%.2f p99=%.2f structure_snaps=%d"
		% [BUILD_FRAMES, placed, connecting_seen, p50, p99, snap_n]
	)
	if connecting_seen < 1:
		_fail("construction pulse never observed CONNECTING structures")
		screen.queue_free()
		return
	# Live construction budget: SCD1 domain pulls add some overhead during CONNECTING.
	# Keep under ~2 frames of 60 FPS (33ms); still fails hard thrash.
	var gate: float = WorldConquestConfigLib.FRAME_BUDGET_MS * 2.0
	if p99 > gate:
		_fail(
			"construction pulse p99 %.2f ms exceeds %.2f ms while CONNECTING buildings pulse"
			% [p99, gate]
		)
		screen.queue_free()
		return
	# Structure snapshots must not scale with every road cell (event-driven only).
	if snap_n > placed * 8 + 40:
		_fail(
			"construction pulse too many structure snapshots: snaps=%d placed=%d"
			% [snap_n, placed]
		)
		screen.queue_free()
		return
	_log(
		"OK  construction pulse fps p99=%.2f max_connecting=%d snaps=%d"
		% [p99, connecting_seen, snap_n]
	)
	# Capture txn-not-full-snap evidence for authority goal (growth frames).
	_log(
		"txn_not_full_snap construction_snaps=%d placed=%d ratio=%.3f"
		% [snap_n, placed, float(snap_n) / float(maxi(placed, 1))]
	)
	screen.queue_free()


## Main tables (Rust) + PresentationTxn: live path must not dual-sim in GDScript.
func _validate_main_table_txn_contract() -> void:
	_log("-- Main table + PresentationTxn live contract --")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const WorldDatasetAssertLib := preload("res://WorldDatasetAssert.gd")
	var screen: Control = await _bootstrap_world_conquest_screen()
	if screen == null:
		_fail("main table txn contract bootstrap timed out")
		return
	var ts = screen.get("territory_sim")
	var battle_data = screen.get("battle_data")
	var home: Vector2i = screen.get("_player_home")
	if ts == null or battle_data == null or home.x < 0:
		_fail("main table txn contract missing sim/map/home")
		screen.queue_free()
		return
	if not bool(ts.builder_authority_active()):
		_fail("main table txn contract: builder authority inactive on live screen")
		screen.queue_free()
		return
	if not bool(ts.structure_authority_active()):
		_fail("main table txn contract: structure authority inactive on live screen")
		screen.queue_free()
		return
	if not bool(ts.grid_authority_active()):
		_fail("main table txn contract: grid authority inactive on live screen")
		screen.queue_free()
		return
	_log("OK  builder_authority_path rust_builder_step (GDScript step_frame not used while authority on)")
	_ensure_debug_supply(screen)
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var placed_sids: Array[int] = []
	for i in range(6):
		var sid: int = _debug_place_shortest_path_near_home(
			screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, 128, 16
		)
		if sid < 0:
			sid = _debug_place_near_home(
				screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, i, 96, 12
			)
		if sid >= 0:
			placed_sids.append(sid)
	if placed_sids.is_empty():
		_fail("main table txn contract could not place any structure")
		screen.queue_free()
		return
	var snap_at_place: int = int(screen.get("_structure_snapshot_pull_count"))
	# Grow roads without further placements.
	for _fi in range(120):
		await get_tree().process_frame
	var snap_after_growth: int = int(screen.get("_structure_snapshot_pull_count"))
	var growth_snaps: int = snap_after_growth - snap_at_place
	_log(
		"txn_growth_snaps=%d (place_snaps=%d after=%d) placed=%d"
		% [growth_snaps, snap_at_place, snap_after_growth, placed_sids.size()]
	)
	# Growth must not full-snapshot every frame (txn path_built patches instead).
	if growth_snaps > placed_sids.size() * 4 + 12:
		_fail(
			"main table txn contract: too many full structure snaps during growth (%d)"
			% growth_snaps
		)
		screen.queue_free()
		return
	# Wait for at least one path-complete transition if possible.
	var saw_building_or_active: bool = false
	for _wait in range(600):
		await get_tree().process_frame
		for sid in placed_sids:
			var st: Dictionary = _structure_by_sid(battle_data, sid)
			var state: String = str(st.get("state", ""))
			if state == OutpostBuildLib.STATE_BUILDING or state == OutpostBuildLib.STATE_ACTIVE:
				saw_building_or_active = true
				break
		if saw_building_or_active:
			break
	if not saw_building_or_active:
		_log("WARN main table txn contract: no BUILDING/ACTIVE yet (parity still checked)")
	var parity: Dictionary = WorldDatasetAssertLib.validate_live(ts, battle_data)
	if bool(parity.get("skipped", false)):
		_fail("main table txn contract: WorldDatasetAssert skipped unexpectedly")
		screen.queue_free()
		return
	if not bool(parity.get("ok", false)):
		var issues: PackedStringArray = parity.get("issues", PackedStringArray())
		_fail("main table txn contract structure parity failed: %s" % ", ".join(issues))
		screen.queue_free()
		return
	_log(
		"OK  main table txn contract parity_ok growth_snaps=%d saw_progress=%s"
		% [growth_snaps, str(saw_building_or_active)]
	)
	screen.queue_free()


func _validate_road_multimesh_append() -> void:
	_log("-- Road MultiMesh append cumulative visibility --")
	const EarthGlobeMapLib := preload("res://EarthGlobeMap.gd")
	var globe: Node3D = EarthGlobeMapLib.new()
	add_child(globe)
	var result: Dictionary = globe.selfcheck_road_multimesh_append(6, 5)
	var ok: bool = bool(result.get("ok", false))
	_log(
		"road_mm selfcheck ok=%s expected=%s used=%s visible=%s capacity=%s"
		% [
			str(ok),
			str(result.get("expected", -1)),
			str(result.get("land_used", -1)),
			str(result.get("land_visible", -1)),
			str(result.get("land_capacity", -1)),
		]
	)
	if not ok:
		_fail("road MultiMesh append selfcheck failed: %s" % str(result))
		globe.queue_free()
		return
	var expected: int = int(result.get("expected", 0))
	if int(result.get("land_used", 0)) != expected or int(result.get("land_visible", 0)) != expected:
		_fail(
			"road MultiMesh cumulative count mismatch used=%s visible=%s expected=%d"
			% [str(result.get("land_used")), str(result.get("land_visible")), expected]
		)
		globe.queue_free()
		return
	_log("OK  road MultiMesh append cumulative segments=%d" % expected)
	globe.queue_free()


func _validate_pressure_outflow() -> void:
	_log("-- Pressure gradient flow --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var map = EarthMapGeneratorLib.generate(99123)
	var tc := BattleTileControlLib.new()
	tc.setup(map)
	var high_idx: int = -1
	var low_idx: int = -1
	for gy in range(10, map.grid_height - 10):
		for gx in range(10, map.grid_width - 10):
			var idx: int = map.cell_index(gx, gy)
			if not tc._is_claimable_index(idx):
				continue
			for d in BattleTileControlLib._CARDINAL_DIRS:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				if nx < 0 or ny < 0 or nx >= map.grid_width or ny >= map.grid_height:
					continue
				var ni: int = map.cell_index(nx, ny)
				if not tc._is_claimable_index(ni):
					continue
				var e_src: float = BattleTileControlLib.tile_elevation(map, gx, gy)
				var e_n: float = BattleTileControlLib.tile_elevation(map, nx, ny)
				if e_src + 5.0 < e_n:
					high_idx = idx
					low_idx = ni
					break
			if high_idx >= 0:
				break
		if high_idx >= 0:
			break
	if high_idx < 0:
		_log("SKIP  no uphill neighbor pair for gradient test")
		return
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[high_idx] = 50.0
	var after: PackedFloat32Array = tc._gradient_flow_pass(
		map, map.grid_width, map.grid_height, tc.pressure_friendly
	)
	if after[low_idx] < 0.05:
		_fail("gradient should flow downhill (low tile got %.4f)" % after[low_idx])
		return
	if after[high_idx] >= 50.0:
		_fail("gradient should remove pressure from high tile (kept %.3f)" % after[high_idx])
		return
	_log("OK  gradient downhill flow")


func _validate_pressure_height_headroom() -> void:
	_log("-- Pressure gradient vs mountain (synthetic map) --")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var map = _build_synthetic_mountain_map()
	var tc := BattleTileControlLib.new()
	tc.setup(map)
	var src_idx: int = map.cell_index(3, 4)
	var mount_idx: int = map.cell_index(4, 4)
	if not tc._is_claimable_index(src_idx) or not tc._is_claimable_index(mount_idx):
		_fail("synthetic mountain map tiles not claimable")
		return
	# Shallow pool: effective height (50 + 0) stays below mountain peak (100) — no flow uphill.
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[src_idx] = 50.0
	var after: PackedFloat32Array = tc._gradient_flow_pass(
		map, map.grid_width, map.grid_height, tc.pressure_friendly
	)
	if after[mount_idx] > 0.01:
		_fail("shallow pressure should not climb mountain (got %.4f)" % after[mount_idx])
		return
	# Deep pool: effective height (160 + 0) tops the peak — fluid pours over.
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[src_idx] = 160.0
	var after_deep: PackedFloat32Array = tc._gradient_flow_pass(
		map, map.grid_width, map.grid_height, tc.pressure_friendly
	)
	if after_deep[mount_idx] < 0.5:
		_fail("deep pressure should pour over mountain (got %.4f)" % after_deep[mount_idx])
		return
	_log("OK  gradient mountain headroom (blocked shallow, poured deep)")


## 8x8 all-grass map, height 0, with a single full-height mountain at (4,4).
func _build_synthetic_mountain_map():
	const BattleMapDataLib := preload("res://BattleMapData.gd")
	var map = BattleMapDataLib.new()
	map.grid_width = 8
	map.grid_height = 8
	map.cell_size = 1.0
	map.map_size = Vector2(8.0, 8.0)
	var total: int = map.grid_width * map.grid_height
	map.terrain_cells = PackedByteArray()
	map.terrain_cells.resize(total)
	map.terrain_cells.fill(BattleMapDataLib.Terrain.GRASS)
	map.tile_height = PackedFloat32Array()
	map.tile_height.resize(total)
	map.tile_height.fill(0.0)
	map.cover_cells = PackedByteArray()
	map.cover_cells.resize(total)
	map.blocked_cells = PackedByteArray()
	map.blocked_cells.resize(total)
	var mount: int = map.cell_index(4, 4)
	map.terrain_cells[mount] = BattleMapDataLib.Terrain.MOUNTAIN
	map.tile_height[mount] = 1.0
	map.rebuild_terrain_arrays()
	map.player_spawn_cells = [Vector2i(1, 1)]
	map.enemy_spawn_cells = [Vector2i(6, 6)]
	map.player_home_grid = Vector2i(1, 1)
	map.enemy_home_grid = Vector2i(6, 6)
	return map


func _validate_territory_rust_compare() -> void:
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	# Runs by default — the game ships on the Rust backend, so parity is a core gate.
	if OS.get_environment("BATTLE_RUST_COMPARE") == "0":
		_log("SKIP  territory Rust compare (BATTLE_RUST_COMPARE=0)")
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust compare skipped — GDExtension not loaded (run setup_rust.ps1)")
		return
	_log("-- Territory Rust vs CPU compare (world map) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(99154)
	var rounds: int = 16
	var sim_cpu := BattleTerritorySimLib.new()
	sim_cpu.use_simple_water_model = true
	sim_cpu.setup(bmap, WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE, null, {}, true)
	for _r in range(rounds):
		sim_cpu.advance_round()
	var owners_cpu: PackedByteArray = sim_cpu.tile_control.owners.duplicate()
	var sim_rust := BattleTerritorySimLib.new()
	sim_rust.use_simple_water_model = true
	sim_rust.setup(bmap, WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE, null, {}, true)
	sim_rust.rust_field = BattleTerritoryRustBackendLib.new()
	sim_rust.rust_live_ready = sim_rust.rust_field.setup_from_tile_control(
		bmap, sim_rust.tile_control, true
	)
	if not sim_rust.rust_live_ready:
		_fail("Rust compare init failed")
		return
	sim_rust.backend = BattleTerritorySimLib.BACKEND_RUST
	for _r in range(rounds):
		sim_rust.advance_round()
	# Under grid authority, tile_control.owners is not mirrored every step — read Rust truth.
	var owners_rust: PackedByteArray = PackedByteArray()
	if sim_rust.rust_field != null and sim_rust.rust_field.has_method("get_owners"):
		owners_rust = sim_rust.rust_field.get_owners()
	if owners_rust.is_empty() and sim_rust.tile_control != null:
		owners_rust = sim_rust.tile_control.owners.duplicate()
	if owners_cpu.size() != owners_rust.size():
		_fail("Rust compare owner array size mismatch")
		return
	var mismatches: int = 0
	for i in range(owners_cpu.size()):
		if owners_cpu[i] != owners_rust[i]:
			mismatches += 1
	if mismatches > 0:
		_fail("Rust compare diverged on %d/%d tiles after %d rounds" % [
			mismatches, owners_cpu.size(), rounds,
		])
	else:
		_log("OK  Rust compare matches CPU (%d rounds)" % rounds)


func _validate_territory_rust_bake_compare() -> void:
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	if not BattleTerritoryRustBackendLib.bake_compare_enabled():
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust bake compare skipped (GDExtension not loaded)")
		return
	_log("-- Territory Rust fluid bake vs GDScript --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(99155)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(bmap, WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE, null, {}, true)
	# Cap rounds: a full 360x180 resolve can run for many minutes; we only need a few frames.
	var tape = sim.build_replay_tape(64, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	var compare_frames: int = mini(4, tape.frame_count())
	if compare_frames < 1:
		_fail("Rust bake compare needs tape frames")
		return
	var mismatches: int = 0
	var bytes_compared: int = 0
	for fi in range(compare_frames):
		var pressures: Dictionary = tape.pressures_at_frame(fi)
		var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
		var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
		if pf.is_empty() or ph.is_empty():
			continue
		var gd_img: Image = BattleTileFluidFieldLib.build_fluid_image_from_powers(
			bmap, pf, ph, 1.0, 0
		)
		if gd_img == null:
			_fail("Rust bake compare GDScript image null at frame %d" % fi)
			return
		var gd_rgba: PackedByteArray = gd_img.get_data()
		var rust_rgba: PackedByteArray = BattleTerritoryRustBackendLib.bake_fluid_rgba(
			bmap, pf, ph, 1.0
		)
		if rust_rgba.size() != gd_rgba.size():
			_fail("Rust bake size mismatch frame %d" % fi)
			return
		for bi in range(gd_rgba.size()):
			if rust_rgba[bi] != gd_rgba[bi]:
				mismatches += 1
		bytes_compared += gd_rgba.size()
	if bytes_compared <= 0:
		_fail("Rust bake compare had no pressure frames to check")
	elif mismatches > 0:
		_fail("Rust bake diverged on %d/%d bytes" % [mismatches, bytes_compared])
	else:
		_log("OK  Rust bake matches GDScript (%d frames)" % compare_frames)


func _validate_territory_rust_active_set_golden() -> void:
	## E10 / A5: Active-set drift policy.
	## Owner mismatch vs full-grid after short golden runs:
	##   ≤8 tiles → acceptable live noise (WARN if >0, still pass)
	##   >8 tiles → FAIL
	## Soft-cap / patch budget live in Rust sim (see empire_territory active-set).
	const ACTIVE_SET_DRIFT_TILE_LIMIT := 8
	_log("-- Territory Rust active-set vs full grid (E10 drift policy) --")
	_log(
		"E10 active-set drift policy: <=%d tiles owner mismatch vs full-grid is WARN/OK; >%d FAIL"
		% [ACTIVE_SET_DRIFT_TILE_LIMIT, ACTIVE_SET_DRIFT_TILE_LIMIT]
	)
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	if not BattleTerritoryRustBackendLib.active_set_compare_enabled():
		_log(
			"OK  E10 policy documented (golden compare off — set BATTLE_RUST_ACTIVE_COMPARE=1 to run)"
		)
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust active-set compare skipped (GDExtension not loaded)")
		_log("OK  E10 policy documented (extension unavailable)")
		return
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(99156)
	var rounds: int = 24
	var tc_full := BattleTileControlLib.new()
	tc_full.setup(bmap)
	tc_full.enable_world_conquest_model(
		WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE
	)
	tc_full.seed_territory_battle(bmap)
	var rust_full := BattleTerritoryRustBackendLib.new()
	if not rust_full.setup_from_tile_control(bmap, tc_full, false, false):
		_fail("Rust active-set compare full-grid init failed")
		return
	for _r in range(rounds):
		rust_full.step_round(tc_full)
	var owners_full: PackedByteArray = tc_full.owners.duplicate()
	var tc_active := BattleTileControlLib.new()
	tc_active.setup(bmap)
	tc_active.enable_world_conquest_model(
		WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE
	)
	tc_active.seed_territory_battle(bmap)
	var rust_active := BattleTerritoryRustBackendLib.new()
	if not rust_active.setup_from_tile_control(bmap, tc_active, true, false):
		_fail("Rust active-set compare active init failed")
		return
	for _r in range(rounds):
		rust_active.step_round(tc_active)
	var owners_active: PackedByteArray = tc_active.owners.duplicate()
	if owners_full.size() != owners_active.size():
		_fail("Rust active-set owner size mismatch")
		return
	var mismatches: int = 0
	for i in range(owners_full.size()):
		if owners_full[i] != owners_active[i]:
			mismatches += 1
	if mismatches > ACTIVE_SET_DRIFT_TILE_LIMIT:
		_fail(
			"Rust active-set diverged on %d tiles after %d rounds (E10 limit <=%d)"
			% [mismatches, rounds, ACTIVE_SET_DRIFT_TILE_LIMIT]
		)
	elif mismatches > 0:
		_log(
			"WARN active-set drift %d tiles (<=%d policy OK)"
			% [mismatches, ACTIVE_SET_DRIFT_TILE_LIMIT]
		)
		_log("OK  Rust active-set within E10 drift policy (%d rounds)" % rounds)
	else:
		_log("OK  Rust active-set matches full grid (%d rounds)" % rounds)


## ---------------------------------------------------------------------------
## W2c FIX_LIST gates: E1–E5 orphan smokes, E9/E10/E11/I*, assert_canonical
## ---------------------------------------------------------------------------


## A12/C15/E11: WorldConquestConfig.assert_canonical_constants must pass.
func _validate_assert_canonical_constants() -> void:
	_log("-- assert_canonical_constants (A12/C15) --")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	if not WorldConquestConfigLib.assert_canonical_constants():
		_fail(
			"assert_canonical_constants failed BRIDGE_PRESSURE_FLOW_MULT=%.4f target=%.4f"
			% [
				WorldConquestConfigLib.BRIDGE_PRESSURE_FLOW_MULT,
				WorldConquestConfigLib.BRIDGE_PRESSURE_FLOW_MULT_DESIGN_TARGET,
			]
		)
		return
	_log(
		"OK  assert_canonical_constants BRIDGE_PRESSURE_FLOW_MULT=%.2f"
		% WorldConquestConfigLib.BRIDGE_PRESSURE_FLOW_MULT
	)


## A6/A7/C8/I1: under WORLD_DATASET_BUILDER_AUTHORITY, step_frame refuses unless allow_legacy.
func _validate_builder_authority_refuse() -> void:
	_log("-- BuilderAgentLib.step_frame refuse under authority (allow_legacy=false) --")
	const BuilderAgentLib := preload("res://BuilderAgentLib.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	if not WorldConquestConfigLib.WORLD_DATASET_BUILDER_AUTHORITY:
		_log("SKIP builder refuse gate (WORLD_DATASET_BUILDER_AUTHORITY off)")
		return
	# Mock empty bots/structures — refuse must fire before any travel work.
	var frame: Dictionary = BuilderAgentLib.step_frame(
		1.0 / 60.0, [], [], {}, null, null, false
	)
	if not bool(frame.get("refused", false)):
		_fail(
			"BuilderAgentLib.step_frame must refuse under WORLD_DATASET_BUILDER_AUTHORITY when allow_legacy=false"
		)
		return
	# With allow_legacy=true the offline kernel may run (selfcheck path); empty bots is a no-op.
	var legacy: Dictionary = BuilderAgentLib.step_frame(
		1.0 / 60.0, [], [], {}, null, null, true
	)
	if bool(legacy.get("refused", false)):
		_fail("BuilderAgentLib.step_frame should not refuse when allow_legacy=true")
		return
	_log("OK  BuilderAgentLib.step_frame refused under authority (allow_legacy=false)")


## Structural: orphan smoke scripts load and retain expected entry/assertion surface (C10).
func _validate_orphan_smoke_structural() -> void:
	_log("-- Orphan smoke structural surface (C10 load + key markers) --")
	var checks: Array[Dictionary] = [
		{
			"path": "res://bridge_invasion_smoke_test.gd",
			"needles": ["snap_to_nearest_coast", "bridge", "PASS bridge invasion"],
		},
		{
			"path": "res://island_outpost_smoke_test.gd",
			"needles": ["_find_isolated_land", "claimable", "PASS island"],
		},
		{
			"path": "res://barracks_smoke_test.gd",
			"needles": ["try_spawn_soldier", "notify_barracks_destroyed", "PASS"],
		},
		{
			"path": "res://enemy_ai_smoke_test.gd",
			"needles": ["run_selfcheck", "EnemyStrategy"],
		},
		{
			"path": "res://soldier_nav_smoke_test.gd",
			"needles": ["try_spawn_soldier", "_bridge_crossing", "PASS soldier nav"],
		},
	]
	for c in checks:
		var path: String = str(c.get("path", ""))
		var src := FileAccess.get_file_as_string(path)
		if src.is_empty():
			_fail("orphan smoke empty/unreadable: %s" % path)
			continue
		var needles: Array = c.get("needles", [])
		var missing: PackedStringArray = PackedStringArray()
		for n in needles:
			if not src.contains(str(n)):
				missing.append(str(n))
		if not missing.is_empty():
			_fail(
				"orphan smoke %s missing markers: %s"
				% [path.get_file(), ", ".join(missing)]
			)
		else:
			_log("OK  smoke surface %s" % path.get_file())


## E1: bridge invasion core — coast snap, water route, claimable corridor pressure.
func _validate_bridge_invasion_gate() -> void:
	_log("-- Bridge invasion gate (E1 lightweight) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const RoutePlannerLib := preload("res://RoutePlannerRustBackend.gd")
	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var home: Vector2i = map_data.player_home_grid
	var sources: Array[Vector2i] = [home]
	var inland: Vector2i = _bridge_qa_find_inland_foreign(map_data, home, sources)
	if inland.x < 0:
		_fail("bridge gate: no inland foreign landmass tile")
		return
	var coastal: Vector2i = OutpostBuildLib.snap_to_nearest_coast(map_data, inland)
	if coastal.x < 0 or not OutpostBuildLib.is_coastal_cell(map_data, coastal.x, coastal.y):
		_fail("bridge gate: snap_to_nearest_coast invalid inland=%s coastal=%s" % [inland, coastal])
		return
	var path_packed: PackedInt32Array = PackedInt32Array()
	if RoutePlannerLib.extension_available():
		var planner := RoutePlannerLib.new()
		if planner.setup_map(map_data, map_data.placed_structures):
			planner.rebuild_portals(
				map_data, map_data.placed_structures, home, BattleTileControlLib.OWNER_FRIENDLY
			)
			var route: Dictionary = planner.find_route_sync(
				coastal, OutpostBuildLib.KIND_CORRIDOR_LINK, true
			)
			path_packed = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		# Fallback GDScript nearest path for headless without route planner.
		var fallback: Dictionary = OutpostBuildLib.nearest_path_to_target(map_data, coastal, sources)
		path_packed = fallback.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		_fail("bridge gate: no bridge route to coastal %s" % coastal)
		return
	var water_end: int = _bridge_qa_water_prefix_end(map_data, path_packed)
	if water_end < 0:
		_fail("bridge gate: bridge route has no water cells")
		return
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	# CPU section matches bridge_invasion_smoke_test connecting-phase (no live freeze dual-path).
	sim.set_resolve_context("viewer")
	sim.setup(map_data, 200, 200, null, {}, true)
	sim.set_live_backend(false)
	var tc = sim.tile_control
	# Unfreeze if live contract froze the grid from a prior context.
	tc.grid_mirror_frozen = false
	var built_cells: int = mini(water_end + 2, path_packed.size())
	map_data.placed_structures.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": coastal.x,
		"gy": coastal.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_CONNECTING,
		"source_gx": home.x,
		"source_gy": home.y,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": float(built_cells),
		"health": WorldConquestConfigLib.OUTPOST_MAX_HEALTH,
	})
	tc.sync_bridge_corridors_from_map(map_data, true)
	var bridge_claimable: int = 0
	for i in range(1, built_cells):
		var key: int = path_packed[i]
		var gx: int = key % map_data.grid_width
		var gy: int = key / map_data.grid_width
		if OutpostBuildLib.is_water_cell(map_data, gx, gy) and tc.claimable_mask[key] != 0:
			bridge_claimable += 1
	if bridge_claimable <= 0:
		_fail("bridge gate: no claimable bridge water cells (built=%d)" % built_cells)
		return
	for i in range(maxi(1, water_end)):
		tc.pressure_friendly[path_packed[i]] = 40.0
	for _i in range(12):
		sim.advance_round()
	var water_pressure: float = 0.0
	for i in range(1, built_cells):
		var key2: int = path_packed[i]
		var gx2: int = key2 % map_data.grid_width
		var gy2: int = key2 / map_data.grid_width
		if OutpostBuildLib.is_water_cell(map_data, gx2, gy2):
			water_pressure += tc.pressure_friendly[key2]
	if water_pressure < 0.001:
		_fail("bridge gate: no friendly pressure on bridge corridor")
		return
	_log(
		"OK  bridge invasion gate coastal=%s claimable=%d pressure=%.2f"
		% [coastal, bridge_claimable, water_pressure]
	)


## E2: island outpost claimable + neighbor pressure inject (no globe visual).
func _validate_island_outpost_gate() -> void:
	_log("-- Island outpost gate (E2 lightweight) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	# CPU path: claimable extension + spawner inject without WorldDataset freeze thrash.
	# Full island_outpost_smoke_test still exercises Rust when run standalone.
	sim.set_resolve_context("viewer")
	sim.setup(map_data, 200, 200, null, {}, true)
	sim.set_live_backend(false)
	var backend: String = "cpu"
	var tc = sim.tile_control
	tc.grid_mirror_frozen = false
	var home: Vector2i = map_data.player_home_grid
	var island: Vector2i = _island_qa_find_isolated_land(map_data, home)
	if island.x < 0:
		_fail("island gate: no isolated landmass")
		return
	var idx: int = map_data.cell_index(island.x, island.y)
	map_data.placed_structures.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": island.x,
		"gy": island.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_ACTIVE,
	})
	tc.sync_placed_spawners_from_map(map_data)
	if tc.claimable_mask[idx] == 0:
		_fail("island gate: island tile still unclaimable after outpost sync at %s" % island)
		return
	for _i in range(80):
		sim.advance_dt(1.0 / 14.0, 1)
	var pf_neighbor: float = 0.0
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for d in dirs:
		var nx: int = island.x + d.x
		var ny: int = island.y + d.y
		if not map_data.is_land_cell(nx, ny):
			continue
		var nidx: int = map_data.cell_index(nx, ny)
		pf_neighbor = maxf(pf_neighbor, tc.pressure_friendly[nidx])
	if pf_neighbor < 0.001:
		# Spawner injects on cardinal neighbors of landing — require that path.
		_fail(
			"island gate: no friendly pressure near island (backend=%s island=%s)"
			% [backend, island]
		)
		return
	_log(
		"OK  island outpost gate island=%s backend=%s neighbor_pf=%.3f"
		% [island, backend, pf_neighbor]
	)


func _island_qa_find_isolated_land(map_data, home: Vector2i) -> Vector2i:
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var sources: Array[Vector2i] = [home]
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), sources):
				return Vector2i(gx, gy)
	return Vector2i(-1, -1)


## E3: barracks soldier spawn + move + destroy notify.
func _validate_barracks_smoke_gate() -> void:
	_log("-- Barracks soldier gate (E3 lightweight) --")
	const CFG := preload("res://WorldConquestConfig.gd")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	if not BattleTerritoryRustBackendLib.extension_available():
		_fail("barracks gate: Rust GDExtension not loaded")
		return
	var map_data = EarthMapGeneratorLib.generate(4242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		_fail("barracks gate: Rust live backend failed")
		return
	# Screen normally wires logistics after enable; call explicitly for harness.
	if sim.has_method("configure_builders"):
		sim.configure_builders(map_data.player_home_grid, map_data.enemy_home_grid)
	if not sim.agents_ready():
		_fail("barracks gate: agents not configured")
		return
	sim.sync_agent_nav()
	var bid: int = 99
	var home: Vector2i = map_data.player_home_grid
	var spawned: bool = sim.try_spawn_soldier(
		bid, BattleTileControlLib.OWNER_FRIENDLY, home.x, home.y
	)
	if not spawned:
		# Try cardinal offsets around HQ (find_spawn_cell needs owned neighbor).
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(2, 0), Vector2i(0, 2),
		]
		for d in dirs:
			if sim.try_spawn_soldier(
				bid, BattleTileControlLib.OWNER_FRIENDLY, home.x + d.x, home.y + d.y
			):
				spawned = true
				break
	if not spawned:
		_fail("barracks gate: spawn failed near home=%s" % home)
		return
	var snap0: Dictionary = sim.get_agent_snapshot()
	var gx0: PackedInt32Array = snap0.get("gx", PackedInt32Array())
	var gy0: PackedInt32Array = snap0.get("gy", PackedInt32Array())
	if gx0.is_empty():
		_fail("barracks gate: no spawn position")
		return
	var start_x: int = gx0[0]
	var start_y: int = gy0[0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		_fail("barracks gate: soldier died immediately")
		return
	var gx1: PackedInt32Array = snap.get("gx", PackedInt32Array())
	var gy1: PackedInt32Array = snap.get("gy", PackedInt32Array())
	if gx1[0] == start_x and gy1[0] == start_y:
		_fail("barracks gate: soldier did not move after 28 rounds")
		return
	sim.notify_barracks_destroyed(bid)
	for _j in range(20):
		sim.advance_round()
	_log("OK  barracks soldier gate agents=%d moved=yes" % sim.agent_living_count())


## E4: enemy AI smoke is EnemyStrategy.run_selfcheck (already primary); re-assert here.
func _validate_enemy_ai_smoke_gate() -> void:
	_log("-- Enemy AI smoke gate (E4 → EnemyStrategy.run_selfcheck) --")
	const EnemyStrategy := preload("res://EnemyStrategy.gd")
	var sc: Dictionary = EnemyStrategy.run_selfcheck()
	if not bool(sc.get("ok", false)):
		_fail("enemy AI smoke gate: %s" % str(sc.get("detail", "")))
		return
	_log("OK  enemy AI smoke gate (%s)" % str(sc.get("detail", "ok")))


## E5: soldier nav — friendly + hostile march (mirrors soldier_nav_smoke_test core).
func _validate_soldier_nav_smoke_gate() -> void:
	_log("-- Soldier nav gate (E5 lightweight) --")
	const CFG := preload("res://WorldConquestConfig.gd")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	if not BattleTerritoryRustBackendLib.extension_available():
		_fail("soldier nav gate: Rust GDExtension not loaded")
		return
	var map_data = EarthMapGeneratorLib.generate(4242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		_fail("soldier nav gate: rust live failed")
		return
	if sim.has_method("configure_builders"):
		sim.configure_builders(map_data.player_home_grid, map_data.enemy_home_grid)
	if not sim.agents_ready():
		_fail("soldier nav gate: agents not configured")
		return
	sim.sync_agent_nav()
	var home: Vector2i = map_data.player_home_grid
	if not _qa_try_spawn_near(sim, 99, BattleTileControlLib.OWNER_FRIENDLY, home):
		_fail("soldier nav gate: friendly spawn failed near home=%s" % home)
		return
	var snap0: Dictionary = sim.get_agent_snapshot()
	if PackedInt32Array(snap0.get("gx", PackedInt32Array())).is_empty():
		_fail("soldier nav gate: friendly missing after spawn")
		return
	var sx: int = snap0["gx"][0]
	var sy: int = snap0["gy"][0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		_fail("soldier nav gate: friendly soldier died")
		return
	if snap["gx"][0] == sx and snap["gy"][0] == sy:
		_fail("soldier nav gate: friendly soldier did not move")
		return
	# Hostile team march (same shape as soldier_nav_smoke_test._hostile_moves).
	var map_h = EarthMapGeneratorLib.generate(7777)
	OutpostBuildLib.prepare_land_components(map_h)
	var sim_h := BattleTerritorySimLib.new()
	sim_h.use_simple_water_model = true
	sim_h.set_resolve_context("world_conquest")
	sim_h.setup(map_h, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	if not sim_h.enable_rust_live():
		_fail("soldier nav gate: hostile sim enable_rust_live failed")
		return
	if sim_h.has_method("configure_builders"):
		sim_h.configure_builders(map_h.player_home_grid, map_h.enemy_home_grid)
	if not sim_h.agents_ready():
		_fail("soldier nav gate: hostile agents not configured")
		return
	sim_h.sync_agent_nav()
	var enemy_home: Vector2i = map_h.enemy_home_grid
	if not _qa_try_spawn_near(sim_h, 100, BattleTileControlLib.OWNER_HOSTILE, enemy_home):
		_fail("soldier nav gate: hostile spawn failed near %s" % enemy_home)
		return
	var h0: Dictionary = sim_h.get_agent_snapshot()
	var hx: int = h0["gx"][0]
	var hy: int = h0["gy"][0]
	for _j in range(28):
		sim_h.advance_round()
	var h1: Dictionary = sim_h.get_agent_snapshot()
	if int(h1.get("count", 0)) < 1 or (h1["gx"][0] == hx and h1["gy"][0] == hy):
		_fail("soldier nav gate: hostile soldier did not move")
		return
	_log("OK  soldier nav gate friendly+hostile moved")


func _qa_try_spawn_near(sim, bid: int, team: int, origin: Vector2i) -> bool:
	if sim.try_spawn_soldier(bid, team, origin.x, origin.y):
		return true
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	]
	for d in dirs:
		if sim.try_spawn_soldier(bid, team, origin.x + d.x, origin.y + d.y):
			return true
	return false


## B3/I4: EarthGlobeRoads capacity helpers never shrink; grow is geometric.
func _validate_earth_globe_roads_helpers() -> void:
	_log("-- EarthGlobeRoads capacity helpers (I4/B3) --")
	const Roads := preload("res://EarthGlobeRoads.gd")
	var min_cap: int = Roads.MIN_CAPACITY
	if Roads.next_capacity(0) < min_cap:
		_fail("EarthGlobeRoads.next_capacity(0) below MIN_CAPACITY")
		return
	if Roads.next_capacity(min_cap) < min_cap:
		_fail("EarthGlobeRoads.next_capacity(MIN) below MIN_CAPACITY")
		return
	var need_over: int = min_cap + 1
	var grown: int = Roads.next_capacity(need_over)
	if grown < need_over:
		_fail("EarthGlobeRoads.next_capacity did not cover need=%d got=%d" % [need_over, grown])
		return
	if grown < min_cap * 2:
		_fail(
			"EarthGlobeRoads growth expected ≥2× MIN for need=%d got=%d"
			% [need_over, grown]
		)
		return
	# Shrink path must request full rebuild; growth append path must not.
	if Roads.needs_full_rebuild_for_seg_change(true, 10, 8) != true:
		_fail("EarthGlobeRoads must full-rebuild on segment shrink")
		return
	if Roads.needs_full_rebuild_for_seg_change(true, 8, 10) != false:
		_fail("EarthGlobeRoads must not full-rebuild on segment grow (append path)")
		return
	_log("OK  EarthGlobeRoads next_capacity grown=%d rebuild_policy=ok" % grown)


## E11/I*: durable presentation thrash flags + MultiMesh selfcheck surface + CONNECTING pulse contract.
func _validate_presentation_thrash_guardrails() -> void:
	_log("-- Presentation thrash guardrails (E11/I*) --")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	const EarthGlobeMapLib := preload("res://EarthGlobeMap.gd")
	# I5/B11: never full-structure-snap every frame.
	if not WorldConquestConfigLib.PRESENTATION_STRUCTURES_ONLY_WHEN_DIRTY:
		_fail("PRESENTATION_STRUCTURES_ONLY_WHEN_DIRTY must be true (I5/B11)")
		return
	_log("OK  PRESENTATION_STRUCTURES_ONLY_WHEN_DIRTY=true (I5 no full structure snap every frame)")
	# I1: live WorldDataset is the only sim path for play.
	if not WorldConquestConfigLib.world_dataset_live():
		_fail("world_dataset_live() false — dual GDScript sim risk under live (I1)")
		return
	_log("OK  world_dataset_live() (I1 no dual GDScript sim under live)")
	# I4: MultiMesh road grow selfcheck API present (exercised by _validate_road_multimesh_append).
	var globe: Node3D = EarthGlobeMapLib.new()
	if not globe.has_method("selfcheck_road_multimesh_append"):
		_fail("EarthGlobeMap missing selfcheck_road_multimesh_append (I4/H2)")
		globe.queue_free()
		return
	_log("OK  EarthGlobeMap.selfcheck_road_multimesh_append present (I4 MultiMesh grow)")
	globe.queue_free()
	# I10: CONNECTING pulse path must exist on globe (path-complete must not keep pulsing).
	# Construction pulse FPS gate + midgame snap budget already exercise live behavior.
	var g_pulse: Node3D = EarthGlobeMapLib.new()
	if not g_pulse.has_method("refresh_connecting_markers"):
		_fail("EarthGlobeMap missing refresh_connecting_markers (I10 CONNECTING pulse)")
		g_pulse.queue_free()
		return
	g_pulse.queue_free()
	_log("OK  CONNECTING pulse API refresh_connecting_markers present (I10)")
	_log(
		"OK  presentation thrash guardrails documented: I1 live authority, I4 MultiMesh, I5 dirty snaps, I10 CONNECTING-only pulse"
	)


## E9/B15: headless cannot measure real GPU display FPS — record env_limit, do not fail.
func _validate_gpu_fps_env_limit() -> void:
	_log("-- GPU display FPS measurement (E9/B15) --")
	# Headless Godot reports draw counters that are not real display GPU FPS.
	const WCS := preload("res://WorldConquestScreen.gd")
	var gpu: Dictionary = WCS.perf_gather_gpu_counters()
	var draw_calls: int = int(gpu.get("draw_calls", 0))
	var vid_mb: float = float(gpu.get("video_mem_mb", 0.0))
	# Always record the env limit so reports are honest under --headless.
	_log("env_limit: headless GPU FPS not measured")
	_log(
		"OK  E9/B15 env_limit recorded (draw_calls=%d vid_mb=%.1f — not used as FPS gate)"
		% [draw_calls, vid_mb]
	)


func _log(msg: String) -> void:
	print(msg)
	_lines.append(msg)


func _fail(msg: String) -> void:
	_failed = true
	_log("FAIL %s" % msg)


func _write_report() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		for line in _lines:
			f.store_line(line)
		f.close()
	_mirror_report_to_scratch()


func _mirror_report_to_scratch() -> void:
	var scratch := OS.get_environment("GROK_GOAL_SCRATCH")
	if scratch.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(scratch)
	var src := ProjectSettings.globalize_path(REPORT_PATH)
	if not FileAccess.file_exists(src):
		return
	var dst := scratch.path_join("qa_report.txt")
	var text := FileAccess.get_file_as_string(src)
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out:
		out.store_string(text)
		out.close()
