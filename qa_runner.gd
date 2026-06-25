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
	"res://FrameBudgetProfiler.gd",
	"res://EarthGlobeMesh.gd",
	"res://EarthMapGenerator.gd",
	"res://GameTheme.gd",
	"res://MainMenu.gd",
	"res://RunLog.gd",
	"res://RunState.gd",
	"res://UnitSimulationStore.gd",
	"res://WorldConquestConfig.gd",
	"res://WorldConquestOutpostBuild.gd",
	"res://WorldConquestResources.gd",
	"res://WorldConquestScreen.gd",
	"res://OutpostConstructionQueue.gd",
	"res://BuilderAgentLib.gd",
	"res://EnemyStrategy.gd",
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
	_validate_enemy_strategy_selfcheck()
	await _validate_enemy_ai_integration_smoke()
	_validate_world_seed_variety()
	_validate_bridge_pipe_suction()
	await _validate_builder_integration_smoke()
	await _validate_fps_fix_paths()
	_validate_territory_rust_compare()
	_validate_territory_rust_bake_compare()
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


func _validate_world_conquest_smoke() -> void:
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
		if (
			WorldConquestConfigLib.OVERLAY_OWNERS_ONLY
			and sim.use_rust_for_live()
			and sim.rust_field != null
			and sim.rust_field.has_method("consume_owner_overlay_delta")
		):
			var d: Dictionary = sim.rust_field.consume_owner_overlay_delta()
			var idxs: PackedInt32Array = d.get("indices", PackedInt32Array())
			if idxs.size() > 0:
				# Touch delta payload so FFI cost is included in the frame budget.
				var vals: PackedByteArray = d.get("values", PackedByteArray())
				var _probe: int = int(vals[0]) if vals.size() > 0 else 0
				_probe += idxs.size()
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
	return screen


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
		for st: Dictionary in battle_data.placed_structures:
			if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) == BattleTileControlLib.OWNER_HOSTILE:
				hostile_count += 1
		if hostile_count > 0:
			_log("OK  enemy AI placed hostile structures=%d frames=%d" % [hostile_count, fi + 1])
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


func _validate_bridge_pipe_suction() -> void:
	_log("-- Bridge pipe suction (corridor pressure via real map route) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	var map_data = null
	var home: Vector2i = Vector2i(-1, -1)
	var coastal: Vector2i = Vector2i(-1, -1)
	var path_packed: PackedInt32Array = PackedInt32Array()
	var sources: Array[Vector2i] = []
	for try_seed in [424242, 44201, 44202, 99123]:
		map_data = EarthMapGeneratorLib.generate(try_seed)
		OutpostBuildLib.prepare_land_components(map_data)
		home = map_data.player_home_grid
		sources = [home]
		var inland: Vector2i = _bridge_qa_find_inland_foreign(map_data, home, sources)
		if inland.x < 0:
			continue
		coastal = OutpostBuildLib.snap_to_nearest_coast(map_data, inland)
		if coastal.x < 0:
			continue
		var route: Dictionary = OutpostBuildLib.nearest_corridor_path_to_target(
			map_data, coastal, sources
		)
		path_packed = route.get("path_packed", PackedInt32Array())
		if not path_packed.is_empty():
			break
	if path_packed.is_empty() or map_data == null:
		_fail("bridge pipe suction no corridor route on sample seeds")
		return
	map_data.bridge_corridors = []
	map_data.placed_structures = []
	map_data.placed_structures.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": coastal.x,
		"gy": coastal.y,
		"kind": OutpostBuildLib.KIND_CORRIDOR_LINK,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": float(path_packed.size()),
	})
	map_data.bridge_corridors.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": coastal.x,
		"gy": coastal.y,
		"path_keys": path_packed,
	})
	map_data.placed_structures.clear()
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, 200, 200, null, {}, true)
	sim.set_live_backend(false)
	var tc := sim.tile_control
	tc.sync_bridge_corridors_from_map(map_data, true)
	var landing_key: int = map_data.cell_index(coastal.x, coastal.y)
	const BridgeFlowMeasureLib := preload("res://BridgeFlowMeasure.gd")
	if not BridgeFlowMeasureLib.run_pipe_unit_selfcheck():
		_fail("bridge pipe unit suction selfcheck")
		return
	_log("OK  bridge pipe unit suction selfcheck")
	var source_key: int = (
		path_packed[0] if path_packed.size() > 0 else map_data.cell_index(home.x, home.y)
	)
	var flow: Dictionary = BridgeFlowMeasureLib.measure_suction_delta(
		sim, tc, map_data, path_packed, landing_key, source_key, 30, "cpu"
	)
	_log("OK  %s" % BridgeFlowMeasureLib.format_result(flow))
	if not bool(flow.get("pass", false)):
		_fail(
			"bridge pipe suction natural landing pre=%.3f post=%.3f delta=%.3f"
			% [float(flow.get("pre", 0.0)), float(flow.get("post", 0.0)), float(flow.get("delta", 0.0))]
		)
		return


func _bridge_qa_water_prefix_end(map_data, path_packed: PackedInt32Array) -> int:
	const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
	var w: int = map_data.grid_width
	for i in range(path_packed.size()):
		var gx: int = path_packed[i] % w
		var gy: int = path_packed[i] / w
		if OutpostBuildLib.is_water_cell(map_data, gx, gy):
			return i + 1
	return -1


func _bridge_qa_find_inland_foreign(map_data, home: Vector2i, sources: Array) -> Vector2i:
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
	var agents: Array = screen.get("_builder_agents")
	if agents.size() != 4:
		_fail("builder integration expected 4 agents, got %d" % agents.size())
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
	# Freeze battle sim so BUILDING-phase pressure damage cannot destroy the hostile outpost.
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
		% [friendly_sid, hostile_sid, frames, agents.size()]
	)
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
		var sid: int = _debug_place_near_home(
			screen, home, w, h, OutpostBuildLib.KIND_SPAWNER, BattleTileControlLib.OWNER_FRIENDLY, i
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
	var next_id: int = placed_sids[0] if not placed_sids.is_empty() else 200
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
		_fail("fps fix hot-path _process frames did not grow path_built")
		screen.queue_free()
		return
	profiler.reset_samples()
	screen.set("_paused", false)
	var connecting_count: int = int(_count_states_for_sids(battle_data, placed_sids).connecting)
	if connecting_count < 10:
		_fail("fps fix validate expected 10 CONNECTING structures, got %d" % connecting_count)
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
	var owners_rust: PackedByteArray = sim_rust.tile_control.owners.duplicate()
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
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	if not BattleTerritoryRustBackendLib.active_set_compare_enabled():
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust active-set compare skipped (GDExtension not loaded)")
		return
	_log("-- Territory Rust active-set vs full grid --")
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
	if mismatches > 8:
		_fail("Rust active-set diverged on %d tiles after %d rounds" % [mismatches, rounds])
	elif mismatches > 0:
		_log("WARN active-set drift %d tiles" % mismatches)
	else:
		_log("OK  Rust active-set matches full grid (%d rounds)" % rounds)


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
