extends SceneTree

## AI vs AI FPS soak (windowed — not headless).
## Launch via tools/run_ai_vs_ai_fps_soak.ps1 or:
##   godot --path <repo> -s res://tools/ai_vs_ai_fps_soak.gd
## Env: EOY_AI_VS_AI=1 (also set by the PowerShell helper).
## Env: EOY_SOAK_SEC=<seconds> overrides default wall (360).

const WALL_SEC_DEFAULT := 360.0
const SAMPLE_INTERVAL_SEC := 1.0
const REPORT_PATH := "res://logs/ai_vs_ai_fps_soak_result.txt"
const WC_SCENE := "res://WorldConquestScreen.tscn"

## Window bounds in soak-elapsed seconds (late = 3-6m for 360s wall).
const WIN_EARLY_END := 120.0
const WIN_MID_END := 180.0
const WIN_LATE_END_DEFAULT := 360.0

const PASS_LATE_AVG := 50.0
const PASS_LATE_MIN := 40.0
const PASS_MID_AVG := 50.0

var _wall_sec: float = WALL_SEC_DEFAULT
var _win_late_end: float = WIN_LATE_END_DEFAULT


func _initialize() -> void:
	call_deferred("_run_soak")


func _resolve_wall_sec() -> float:
	var env: String = OS.get_environment("EOY_SOAK_SEC").strip_edges()
	if env.is_empty():
		return WALL_SEC_DEFAULT
	var v: float = float(env)
	if v < 60.0:
		return WALL_SEC_DEFAULT
	return v


func _run_soak() -> void:
	randomize()
	var seed_val: int = randi() & 0x7FFFFFFF
	_wall_sec = _resolve_wall_sec()
	_win_late_end = minf(_wall_sec, WIN_LATE_END_DEFAULT)
	if _wall_sec > WIN_LATE_END_DEFAULT:
		_win_late_end = _wall_sec

	# SceneTree -s scripts do not resolve autoload identifiers at parse time.
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null:
		_finish_fail(seed_val, {}, "RunState autoload missing under /root", [], 0)
		return

	rs.set("ai_vs_ai", true)
	rs.set("skip_deploy_pick", true)
	rs.set("first_run_clarity", false)
	rs.set("custom_world", true)
	rs.set("world_map_id", "earth")
	rs.set("run_seed", seed_val)
	rs.set("land_bias", 0.45)
	rs.set("resource_density", 1.4)
	rs.set("mountain_bias", 0.25)
	rs.set("start_region", "any")
	rs.set("ai_difficulty", 2) ## Expert

	var criteria: Dictionary = rs.call("map_gen_criteria") as Dictionary
	criteria["ai_difficulty"] = int(rs.get("ai_difficulty"))

	print("AI_VS_AI_FPS_SOAK start seed=%d wall_sec=%.0f criteria=%s" % [seed_val, _wall_sec, str(criteria)])

	var err: Error = change_scene_to_file(WC_SCENE)
	if err != OK:
		_finish_fail(seed_val, criteria, "change_scene_to_file failed err=%d" % int(err), [], 0)
		return

	# Wait until WorldConquestScreen is current and bootstrap finished (_loading=false).
	var screen: Node = await _wait_for_wc_ready()
	if screen == null:
		_finish_fail(seed_val, criteria, "WorldConquestScreen never became ready", [], 0)
		return

	var land_cells: int = _count_land_cells(screen)
	var custom_ok: bool = _custom_world_check(screen, criteria, land_cells)
	print(
		(
			"CUSTOM_WORLD check: ok=%s land_cells=%d land_bias=%.2f resource_density=%.2f mountain_bias=%.2f start_region=%s ai_difficulty=%d"
			% [
				str(custom_ok),
				land_cells,
				float(criteria.get("land_bias", 0.0)),
				float(criteria.get("resource_density", 1.0)),
				float(criteria.get("mountain_bias", 0.0)),
				str(criteria.get("start_region", "any")),
				int(criteria.get("ai_difficulty", -1)),
			]
		)
	)

	var samples: Array = [] ## {t_sec, fps, structures, msec}
	var soak_start_msec: int = Time.get_ticks_msec()
	var battle_ended_early: bool = false

	while true:
		var elapsed_sec: float = float(Time.get_ticks_msec() - soak_start_msec) / 1000.0
		if elapsed_sec >= _wall_sec:
			break
		if _is_battle_finished(screen):
			battle_ended_early = true
			print("AI_VS_AI_FPS_SOAK battle finished at t=%.1fs" % elapsed_sec)
			break

		var fps: float = Engine.get_frames_per_second()
		var msec: int = Time.get_ticks_msec()
		var structs: int = _try_structure_count(screen)
		samples.append({"t_sec": elapsed_sec, "fps": fps, "structures": structs, "msec": msec})
		print(
			(
				"SOAK t=%.0fs fps=%.1f structures=%d"
				% [elapsed_sec, fps, structs]
			)
		)

		await create_timer(SAMPLE_INTERVAL_SEC).timeout

	var result: Dictionary = _evaluate(samples, battle_ended_early)
	_write_report(seed_val, criteria, land_cells, custom_ok, samples, result)
	var passed: bool = bool(result.get("passed", false))
	print("AI_VS_AI_FPS_SOAK %s — %s" % ["PASS" if passed else "FAIL", str(result.get("reason", ""))])
	quit(0 if passed else 1)


func _wait_for_wc_ready() -> Node:
	var deadline_msec: int = Time.get_ticks_msec() + 600_000 ## 10 min load budget
	while Time.get_ticks_msec() < deadline_msec:
		await process_frame
		var scene: Node = current_scene
		if scene == null or not is_instance_valid(scene):
			continue
		# WorldConquestScreen exposes _loading during bootstrap.
		var loading = scene.get("_loading")
		if loading == null:
			continue
		if not bool(loading):
			await process_frame
			return scene
	return null


func _is_battle_finished(screen: Node) -> bool:
	if screen == null or not is_instance_valid(screen):
		return true
	var finished = screen.get("_battle_finished")
	if finished != null and bool(finished):
		return true
	var overlay = screen.get("end_overlay")
	if overlay != null and overlay is CanvasItem and (overlay as CanvasItem).visible:
		return true
	return false


func _try_structure_count(screen: Node) -> int:
	if screen == null or not is_instance_valid(screen):
		return -1
	var bd = screen.get("battle_data")
	if bd != null:
		var arr = bd.placed_structures
		if arr is Array:
			return (arr as Array).size()
	var enemy_n = screen.get("_run_enemy_structures_placed")
	var player_n = screen.get("_run_player_structures_placed")
	if enemy_n != null and player_n != null:
		return int(enemy_n) + int(player_n)
	var placed = screen.get("_run_structures_placed")
	if placed != null:
		return int(placed)
	return -1


func _count_land_cells(screen: Node) -> int:
	var bd = screen.get("battle_data") if screen != null else null
	if bd == null:
		return -1
	var n: int = 0
	var sphere: bool = bool(bd.sphere_mode)
	if sphere:
		var cell_count: int = int(bd.cell_count)
		if bd.has_method("is_land_cell_id"):
			for cid in range(cell_count):
				if bd.is_land_cell_id(cid):
					n += 1
		return n
	var w: int = int(bd.grid_width)
	var h: int = int(bd.grid_height)
	if bd.has_method("is_land_cell"):
		for gy in range(h):
			for gx in range(w):
				if bd.is_land_cell(gx, gy):
					n += 1
	return n


func _custom_world_check(screen: Node, criteria: Dictionary, land_cells: int) -> bool:
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null or not bool(rs.get("custom_world")):
		print("CUSTOM_WORLD FAIL: RunState.custom_world is false")
		return false
	if absf(float(rs.get("land_bias")) - float(criteria.get("land_bias", 0.0))) > 0.001:
		print("CUSTOM_WORLD FAIL: land_bias mismatch")
		return false
	if absf(float(rs.get("resource_density")) - float(criteria.get("resource_density", 1.0))) > 0.001:
		print("CUSTOM_WORLD FAIL: resource_density mismatch")
		return false
	var bd = screen.get("battle_data") if screen != null else null
	if bd == null:
		print("CUSTOM_WORLD FAIL: battle_data null")
		return false
	if land_cells < 0:
		print("CUSTOM_WORLD FAIL: land cell count unavailable")
		return false
	if land_cells == 0:
		print("CUSTOM_WORLD FAIL: map has zero land cells")
		return false
	# Nontrivial land_bias should still produce a real landmass; Custom World is procedural.
	if not bool(criteria.get("procedural", false)):
		print("CUSTOM_WORLD FAIL: expected procedural=true in map_gen_criteria")
		return false
	var tag: String = str(bd.get("pack_visual_tag")) if bd != null else ""
	if tag == "":
		print("CUSTOM_WORLD FAIL: pack_visual_tag empty (procedural albedo cache tag missing)")
		return false
	print(
		(
			"CUSTOM_WORLD OK: procedural battle_data land_cells=%d tag=%s (criteria via RunState.map_gen_criteria)"
			% [land_cells, tag]
		)
	)
	return true


func _window_stats(samples: Array, t0: float, t1: float) -> Dictionary:
	var fps_vals: Array[float] = []
	for s in samples:
		var t: float = float(s.get("t_sec", -1.0))
		if t >= t0 and t < t1:
			fps_vals.append(float(s.get("fps", 0.0)))
	if fps_vals.is_empty():
		return {"count": 0, "min": 0.0, "avg": 0.0, "max": 0.0, "below_45": 0, "below_35": 0}
	var mn: float = fps_vals[0]
	var mx: float = fps_vals[0]
	var sum: float = 0.0
	var below_45: int = 0
	var below_35: int = 0
	for v in fps_vals:
		mn = minf(mn, v)
		mx = maxf(mx, v)
		sum += v
		if v < 45.0:
			below_45 += 1
		if v < 35.0:
			below_35 += 1
	return {
		"count": fps_vals.size(),
		"min": mn,
		"avg": sum / float(fps_vals.size()),
		"max": mx,
		"below_45": below_45,
		"below_35": below_35,
	}


func _evaluate(samples: Array, battle_ended_early: bool) -> Dictionary:
	var early: Dictionary = _window_stats(samples, 0.0, WIN_EARLY_END)
	var mid: Dictionary = _window_stats(samples, WIN_EARLY_END, WIN_MID_END)
	var late: Dictionary = _window_stats(samples, WIN_MID_END, _win_late_end)
	var out := {
		"early": early,
		"mid": mid,
		"late": late,
		"battle_ended_early": battle_ended_early,
		"passed": false,
		"reason": "",
	}
	if int(late.get("count", 0)) <= 0:
		out["reason"] = (
			"no late-window (3-6m) FPS samples"
			+ (" (battle ended early)" if battle_ended_early else "")
		)
		return out
	var late_avg: float = float(late.get("avg", 0.0))
	var late_min: float = float(late.get("min", 0.0))
	var mid_avg: float = float(mid.get("avg", 0.0))
	var mid_ok: bool = int(mid.get("count", 0)) <= 0 or mid_avg >= PASS_MID_AVG
	var late_ok: bool = late_avg >= PASS_LATE_AVG and late_min >= PASS_LATE_MIN
	if late_ok and mid_ok:
		out["passed"] = true
		out["reason"] = "mid avg=%.1f late avg=%.1f >= %.0f late min=%.1f >= %.0f" % [
			mid_avg, late_avg, PASS_LATE_AVG, late_min, PASS_LATE_MIN
		]
	else:
		var parts: PackedStringArray = []
		if not mid_ok:
			parts.append("mid avg=%.1f < %.0f" % [mid_avg, PASS_MID_AVG])
		if late_avg < PASS_LATE_AVG:
			parts.append("late avg=%.1f < %.0f" % [late_avg, PASS_LATE_AVG])
		if late_min < PASS_LATE_MIN:
			parts.append("late min=%.1f < %.0f" % [late_min, PASS_LATE_MIN])
		out["reason"] = ", ".join(parts)
	return out


func _finish_fail(seed_val: int, criteria: Dictionary, reason: String, samples: Array, land_cells: int) -> void:
	var result := {
		"early": _window_stats(samples, 0.0, WIN_EARLY_END),
		"mid": _window_stats(samples, WIN_EARLY_END, WIN_MID_END),
		"late": _window_stats(samples, WIN_MID_END, _win_late_end),
		"battle_ended_early": false,
		"passed": false,
		"reason": reason,
	}
	_write_report(seed_val, criteria, land_cells, false, samples, result)
	print("AI_VS_AI_FPS_SOAK FAIL — %s" % reason)
	quit(1)


func _fmt_window(name: String, w: Dictionary) -> String:
	return (
		"%s: n=%d min=%.1f avg=%.1f max=%.1f below45=%d below35=%d"
		% [
			name,
			int(w.get("count", 0)),
			float(w.get("min", 0.0)),
			float(w.get("avg", 0.0)),
			float(w.get("max", 0.0)),
			int(w.get("below_45", 0)),
			int(w.get("below_35", 0)),
		]
	)


func _write_report(
	seed_val: int,
	criteria: Dictionary,
	land_cells: int,
	custom_ok: bool,
	samples: Array,
	result: Dictionary
) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	var early: Dictionary = result.get("early", {})
	var mid: Dictionary = result.get("mid", {})
	var late: Dictionary = result.get("late", {})
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== AI vs AI FPS Soak ===")
	lines.append("seed=%d" % seed_val)
	lines.append("criteria=%s" % str(criteria))
	lines.append("custom_world_ok=%s land_cells=%d" % [str(custom_ok), land_cells])
	lines.append("wall_sec=%.0f sample_interval=%.1f sample_count=%d" % [_wall_sec, SAMPLE_INTERVAL_SEC, samples.size()])
	lines.append("battle_ended_early=%s" % str(result.get("battle_ended_early", false)))
	lines.append(_fmt_window("0-2m", early))
	lines.append(_fmt_window("2-3m", mid))
	lines.append(_fmt_window("3-6m (late)", late))
	lines.append(
		"late below45=%d below35=%d"
		% [int(late.get("below_45", 0)), int(late.get("below_35", 0))]
	)
	var passed: bool = bool(result.get("passed", false))
	lines.append("result=%s" % ("PASS" if passed else "FAIL"))
	lines.append("reason=%s" % str(result.get("reason", "")))
	var path: String = ProjectSettings.globalize_path(REPORT_PATH)
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Failed to write report at %s" % path)
		for line in lines:
			print(line)
		return
	for line in lines:
		f.store_line(line)
		print(line)
	f.close()
	print("Wrote report: %s" % path)
