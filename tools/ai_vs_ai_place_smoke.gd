extends SceneTree

## Short AI vs AI placement smoke (headless).
## Proves both sides place via live path: command → structure_store upsert → SCD1 apply.
## Usage:
##   godot --headless --path . -s res://tools/ai_vs_ai_place_smoke.gd
## Env: EOY_AI_VS_AI=1 (set here). Optional EOY_PLACE_SMOKE_FRAMES (default 900).

const CFG := preload("res://WorldConquestConfig.gd")
const WC_SCENE := "res://WorldConquestScreen.tscn"
const REPORT_PATH := "res://logs/ai_vs_ai_place_smoke_result.txt"
const DEFAULT_MAX_FRAMES := 1800


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("EOY_AI_VS_AI", "1")
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null:
		_fail("RunState autoload missing")
		return
	rs.set("ai_vs_ai", true)
	rs.set("skip_deploy_pick", true)
	rs.set("first_run_clarity", false)
	rs.set("custom_world", false)
	rs.set("world_map_id", "earth")
	rs.set("run_seed", 424242)
	rs.set("ai_difficulty", 1)

	var err: Error = change_scene_to_file(WC_SCENE)
	if err != OK:
		_fail("change_scene_to_file failed err=%d" % int(err))
		return

	var screen: Node = await _wait_ready()
	if screen == null:
		_fail("WorldConquestScreen never ready")
		return

	if not bool(screen.call("_live_rust_presentation")):
		_fail("live rust presentation not active (need WorldDataset + Rust DLL)")
		return

	var max_frames: int = DEFAULT_MAX_FRAMES
	var env_frames: String = OS.get_environment("EOY_PLACE_SMOKE_FRAMES").strip_edges()
	if not env_frames.is_empty():
		max_frames = maxi(120, int(env_frames))

	var start_friendly: int = int(screen.get("_run_player_structures_placed"))
	var start_hostile: int = int(screen.get("_run_enemy_structures_placed"))
	print(
		"AI_VS_AI_PLACE_SMOKE start live=1 frames_max=%d start_f=%d start_h=%d"
		% [max_frames, start_friendly, start_hostile]
	)

	var placed_f: int = 0
	var placed_h: int = 0
	var frames: int = 0
	while frames < max_frames:
		await process_frame
		frames += 1
		placed_f = int(screen.get("_run_player_structures_placed")) - start_friendly
		placed_h = int(screen.get("_run_enemy_structures_placed")) - start_hostile
		if placed_f > 0 and placed_h > 0:
			_pass(frames, placed_f, placed_h)
			return
		if frames % 300 == 0:
			print(
				"AI_VS_AI_PLACE_SMOKE progress frames=%d placed_f=%d placed_h=%d"
				% [frames, placed_f, placed_h]
			)

	_fail(
		"timeout frames=%d placed_friendly=%d placed_hostile=%d (need both > 0)"
		% [frames, placed_f, placed_h]
	)


func _wait_ready() -> Node:
	var tries: int = 0
	while tries < 600:
		await process_frame
		tries += 1
		var screen: Node = root.get_node_or_null("WorldConquestScreen")
		if screen == null:
			var cur: Node = current_scene
			if cur != null and cur.get_script() != null:
				var path: String = str(cur.get_script().resource_path)
				if path.ends_with("WorldConquestScreen.gd"):
					screen = cur
		if screen == null:
			continue
		if bool(screen.get("_loading")):
			continue
		return screen
	return null


func _pass(frames: int, placed_f: int, placed_h: int) -> void:
	var msg: String = (
		"PASS frames=%d placed_friendly=%d placed_hostile=%d path=upsert→SCD1"
		% [frames, placed_f, placed_h]
	)
	print("AI_VS_AI_PLACE_SMOKE %s" % msg)
	_write_report(true, msg)
	quit(0)


func _fail(reason: String) -> void:
	push_error("AI_VS_AI_PLACE_SMOKE FAIL — %s" % reason)
	_write_report(false, reason)
	quit(1)


func _write_report(ok: bool, detail: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	var text: String = "ok=%s\n%s\n" % ["1" if ok else "0", detail]
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
