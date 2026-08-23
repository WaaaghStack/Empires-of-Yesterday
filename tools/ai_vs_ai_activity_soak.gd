extends SceneTree

## AI vs AI activity soak — headless, wall-clock duration.
## Writes ActivityTrace txn/fps logs; exit 0 always after soak (analysis is offline).
##   godot --headless --path . -s res://tools/ai_vs_ai_activity_soak.gd
## Env: EOY_SOAK_SEC (default 45), EOY_AI_VS_AI=1

const WC_SCENE := "res://WorldConquestScreen.tscn"
const REPORT := "res://logs/ai_vs_ai_activity_soak_result.txt"
const DEFAULT_SEC := 45.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("EOY_AI_VS_AI", "1")
	OS.set_environment("EOY_ACTIVITY_TRACE", "1")
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null:
		_done(false, "RunState missing")
		return
	rs.set("ai_vs_ai", true)
	rs.set("skip_deploy_pick", true)
	rs.set("first_run_clarity", false)
	rs.set("custom_world", false)
	rs.set("world_map_id", "earth")
	rs.set("run_seed", int(Time.get_ticks_msec()) & 0x7FFFFFFF)
	rs.set("ai_difficulty", 1)

	var wall_sec: float = DEFAULT_SEC
	var env: String = OS.get_environment("EOY_SOAK_SEC").strip_edges()
	if not env.is_empty():
		wall_sec = maxf(15.0, float(env))

	if change_scene_to_file(WC_SCENE) != OK:
		_done(false, "scene load failed")
		return

	var screen: Node = await _wait_ready()
	if screen == null:
		_done(false, "screen never ready")
		return
	if not bool(screen.call("_live_rust_presentation")):
		_done(false, "live rust presentation off")
		return

	var t0: int = Time.get_ticks_msec()
	var placed_f0: int = int(screen.get("_run_player_structures_placed"))
	var placed_h0: int = int(screen.get("_run_enemy_structures_placed"))
	print("AI_VS_AI_ACTIVITY_SOAK start wall_sec=%.0f seed live=1" % wall_sec)

	while float(Time.get_ticks_msec() - t0) / 1000.0 < wall_sec:
		await process_frame

	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var placed_f: int = int(screen.get("_run_player_structures_placed")) - placed_f0
	var placed_h: int = int(screen.get("_run_enemy_structures_placed")) - placed_h0
	var msg: String = (
		"DONE elapsed=%.1fs placed_friendly=%d placed_hostile=%d txn=%s fps=%s"
		% [
			elapsed,
			placed_f,
			placed_h,
			"logs/activity_txn_latest.txt",
			"logs/activity_fps_latest.txt",
		]
	)
	print("AI_VS_AI_ACTIVITY_SOAK %s" % msg)
	_done(true, msg)


func _wait_ready() -> Node:
	var tries: int = 0
	while tries < 900:
		await process_frame
		tries += 1
		var screen: Node = root.get_node_or_null("WorldConquestScreen")
		if screen == null:
			var cur: Node = current_scene
			if cur != null and cur.get_script() != null:
				if str(cur.get_script().resource_path).ends_with("WorldConquestScreen.gd"):
					screen = cur
		if screen != null and not bool(screen.get("_loading")):
			return screen
	return null


func _done(ok: bool, detail: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	var f: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	if f:
		f.store_string("ok=%s\n%s\n" % ["1" if ok else "0", detail])
		f.close()
	var trace: Node = root.get_node_or_null("ActivityTrace")
	if trace != null and trace.has_method("flush"):
		trace.call("flush")
	quit(0 if ok else 1)
