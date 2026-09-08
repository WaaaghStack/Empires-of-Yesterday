extends SceneTree

## Headless smoke for the proposed two-worlds transaction engine (eon_engine via GDExtension).
## Verifies the TwoWorldsEngine class is registered, deterministic, and reconciles.
## godot --headless --path . -s res://two_worlds_smoke_test.gd

func _init() -> void:
	print("=== Two Worlds Engine Smoke ===")
	if not ClassDB.class_exists("TwoWorldsEngine"):
		push_error("FAIL TwoWorldsEngine class not registered (rebuild the Rust DLL)")
		quit()
		return
	var engine = ClassDB.instantiate("TwoWorldsEngine")
	var verdict := String(engine.self_check())
	print(verdict)
	var ok := verdict.contains("deterministic=true") and verdict.contains("reconciled=true")
	print("--- campaign summary (seed 2026) ---")
	print(String(engine.run_campaign_summary(2026, 60)))
	print("--- AI vs AI batch (24 matches) ---")
	var ai := String(engine.run_ai_vs_ai_batch(24, 400))
	print(ai)
	var ai_ok := ai.contains("all_reconciled=true") and ai.contains("deterministic=true")

	var battle_ok := _check_custom_battle(engine)
	var parse_ok := _check_scripts_parse()

	if ok and ai_ok and battle_ok and parse_ok:
		print("PASS two_worlds smoke")
	else:
		push_error("FAIL two_worlds smoke (determinism/reconcile/ai-vs-ai/battle/parse)")
	quit()


func _check_custom_battle(engine) -> bool:
	print("--- custom battle FFI (HD-2D viewer) ---")
	var summary: Dictionary = engine.resolve_custom_battle(1, 200, 40, 200, 40)
	print("resolve_custom_battle => %s" % summary)
	var meta: Dictionary = engine.get_last_battle_meta(0)
	var unit_count := int(meta.get("unit_count", 0))
	var frame_count := int(meta.get("frame_count", 0))
	var fac: PackedByteArray = meta.get("fac", PackedByteArray())
	var kind: PackedByteArray = meta.get("kind", PackedByteArray())
	print("meta: unit_count=%d frame_count=%d width=%s height=%s fac_len=%d kind_len=%d" % [
		unit_count, frame_count, meta.get("width"), meta.get("height"), fac.size(), kind.size(),
	])
	# Sample a few frames across the battle and confirm parallel arrays stream.
	var frames_to_check := [0, frame_count / 4, frame_count / 2, max(frame_count - 1, 0)]
	var frames_ok := true
	for f in frames_to_check:
		var fr: Dictionary = engine.get_last_battle_frame_xy(0, f)
		var xs: PackedFloat32Array = fr.get("x", PackedFloat32Array())
		var ys: PackedFloat32Array = fr.get("y", PackedFloat32Array())
		var alive: PackedByteArray = fr.get("alive", PackedByteArray())
		var n_alive := 0
		for a in alive:
			if a != 0:
				n_alive += 1
		print("  frame %d: x=%d y=%d alive=%d (living=%d)" % [f, xs.size(), ys.size(), alive.size(), n_alive])
		if xs.size() != unit_count or ys.size() != unit_count or alive.size() != unit_count:
			frames_ok = false
	# 200 soldiers + 40 bombers per side, two sides => 480 units.
	var count_ok := unit_count == 480 and fac.size() == 480 and kind.size() == 480
	var frame_ok := frame_count > 0
	if not count_ok:
		push_error("battle unit_count expected 480, got %d" % unit_count)
	if not frame_ok:
		push_error("battle produced no frames")
	if not frames_ok:
		push_error("battle frame arrays not aligned to unit_count")
	return count_ok and frame_ok and frames_ok


func _check_scripts_parse() -> bool:
	print("--- parse-check new GDScript ---")
	# Only scripts that don't reference autoload globals (RunState/RunLog) — those globals aren't
	# registered when running via `-s`, so loading MainMenu/TwoWorldsGlobe here would false-fail.
	# They are validated by booting the scenes headlessly (see the install/boot check).
	var paths := [
		"res://BattleView.gd",
		"res://TwoWorldsBattle.gd",
	]
	var all_ok := true
	for p in paths:
		var res = load(p)
		var ok := res != null and res is GDScript
		print("  %s => %s" % [p, "ok" if ok else "FAILED"])
		if not ok:
			all_ok = false
	return all_ok
