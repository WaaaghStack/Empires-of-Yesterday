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
	print("meta: unit_count=%d frame_count=%d width=%s height=%s elev=%s fac_len=%d kind_len=%d" % [
		unit_count, frame_count, meta.get("width"), meta.get("height"), meta.get("elevation"),
		fac.size(), kind.size(),
	])
	if not meta.has("elevation") or not meta.has("river_x") or not meta.has("hill_block_r"):
		push_error("battle meta missing diorama terrain uniforms")
		return false
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
		var facing: PackedByteArray = fr.get("facing", PackedByteArray())
		var state: PackedByteArray = fr.get("state", PackedByteArray())
		var zs: PackedFloat32Array = fr.get("z", PackedFloat32Array())
		if facing.size() != unit_count or state.size() != unit_count or zs.size() != unit_count:
			push_error("battle frame %d missing facing/state/z tracks" % f)
			frames_ok = false
		var aim_x: PackedFloat32Array = fr.get("aim_x", PackedFloat32Array())
		var aim_y: PackedFloat32Array = fr.get("aim_y", PackedFloat32Array())
		if aim_x.size() != unit_count or aim_y.size() != unit_count:
			push_error("battle frame %d missing aim tracks" % f)
			frames_ok = false
	# Contact: some aim/fire/hit somewhere in the bake (short fights peak after the first third).
	var saw_fight := false
	for f in frames_to_check:
		var st: PackedByteArray = engine.get_last_battle_frame_xy(0, f).get("state", PackedByteArray())
		for s in st:
			var v := int(s)
			if v == 2 or v == 3 or v == 7:
				saw_fight = true
				break
		if saw_fight:
			break
	if not saw_fight:
		push_error("expected aim/fire/hit states during the fight")
	# 200 soldiers + 40 bombers per side, two sides => 480 units.
	var count_ok := unit_count == 480 and fac.size() == 480 and kind.size() == 480
	var frame_ok := frame_count > 0
	if not count_ok:
		push_error("battle unit_count expected 480, got %d" % unit_count)
	if not frame_ok:
		push_error("battle produced no frames")
	if not frames_ok:
		push_error("battle frame arrays not aligned to unit_count")
	return count_ok and frame_ok and frames_ok and saw_fight and _check_custom_battle_plan(engine)


func _check_custom_battle_plan(engine) -> bool:
	print("--- custom battle plan FFI (5v4 + left order) ---")
	var fac := PackedByteArray()
	var kind := PackedByteArray()
	var count := PackedInt32Array()
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var facing := PackedFloat32Array()
	var formation := PackedByteArray()
	var orders := PackedByteArray()
	for i in 5:
		fac.append(0)
		kind.append(0)
		count.append(100)
		xs.append(140.0)
		ys.append(90.0 + float(i) * 90.0)
		facing.append(0.0)
		formation.append(0)
		# Mixed: first two Blue Attack left, rest Front.
		orders.append(1 if i < 2 else 0)
	for i in 4:
		fac.append(1)
		kind.append(0)
		count.append(100)
		xs.append(860.0)
		ys.append(120.0 + float(i) * 110.0)
		facing.append(3.14159)
		formation.append(0)
		orders.append(0)
	var summary: Dictionary = engine.resolve_custom_battle_plan(
		2, 0, 0, fac, kind, count, xs, ys, facing, formation, orders
	)
	print("resolve_custom_battle_plan => %s" % summary)
	if summary.has("error"):
		push_error("plan resolve error: %s" % summary.get("error"))
		return false
	var unit_count := int(summary.get("unit_count", 0))
	if unit_count != 900:
		push_error("plan unit_count expected 900, got %d" % unit_count)
		return false
	var fr: Dictionary = engine.get_last_battle_frame_xy(0, 0)
	var y0: PackedFloat32Array = fr.get("y", PackedFloat32Array())
	if y0.size() != 900:
		push_error("plan frame 0 y size %d" % y0.size())
		return false
	return _check_replay_read(engine, 900)


func _check_replay_read(engine, unit_count: int) -> bool:
	print("--- replay read (scrum + fire bake) ---")
	var meta: Dictionary = engine.get_last_battle_meta(0)
	var fac: PackedByteArray = meta.get("fac", PackedByteArray())
	var kind: PackedByteArray = meta.get("kind", PackedByteArray())
	var frames := int(meta.get("frame_count", 0))
	var river := float(meta.get("river_x", 500.0))
	var min_gap := 999.0
	var crossed := false
	var fire_frames := 0
	var fire_peak := 0
	var mid := maxi(frames / 3, 1)
	for f in range(mini(frames, 80)):
		var fr: Dictionary = engine.get_last_battle_frame_xy(0, f)
		var xs: PackedFloat32Array = fr.get("x", PackedFloat32Array())
		var st: PackedByteArray = fr.get("state", PackedByteArray())
		var alive: PackedByteArray = fr.get("alive", PackedByteArray())
		if xs.size() != unit_count:
			continue
		var fire_n := 0
		var a_xs := PackedFloat32Array()
		var d_xs := PackedFloat32Array()
		for i in unit_count:
			if i >= fac.size() or int(kind[i]) != 0:
				continue
			var s := int(st[i]) if i < st.size() else 0
			if (i < alive.size() and int(alive[i]) == 0) or s == 4 or s == 6:
				continue
			if s == 3:
				fire_n += 1
			if int(fac[i]) == 0:
				a_xs.append(xs[i])
				if xs[i] > river + 0.5:
					crossed = true
			else:
				d_xs.append(xs[i])
				if xs[i] < river - 0.5:
					crossed = true
		if fire_n > 0:
			fire_frames += 1
			fire_peak = maxi(fire_peak, fire_n)
		if f >= 4 and not a_xs.is_empty() and not d_xs.is_empty():
			a_xs.sort()
			d_xs.sort()
			var gap: float = absf(float(d_xs[int(d_xs.size() / 2)]) - float(a_xs[int(a_xs.size() / 2)]))
			min_gap = minf(min_gap, gap)
	print("replay mid_frame=%d min_gap=%.1f crossed=%s fire_frames=%d fire_peak=%d" % [
		mid, min_gap, crossed, fire_frames, fire_peak
	])
	var ok := min_gap < 36.0 and crossed and fire_frames >= 2
	if not ok:
		push_error("replay read failed gap=%.1f fire_frames=%d" % [min_gap, fire_frames])
	return ok


func _check_scripts_parse() -> bool:
	print("--- parse-check new GDScript / battle shaders ---")
	# Only scripts that don't reference autoload globals (RunState/RunLog) — those globals aren't
	# registered when running via `-s`, so loading MainMenu/TwoWorldsGlobe here would false-fail.
	# They are validated by booting the scenes headlessly (see the install/boot check).
	var paths := [
		"res://BattleView.gd",
		"res://TwoWorldsBattle.gd",
		"res://CustomBattleSetup.gd",
		"res://shaders/battle_tracer.gdshader",
		"res://shaders/battle_billboard.gdshader",
		"res://shaders/battle_fx.gdshader",
		"res://shaders/battle_diorama.gdshader",
	]
	var all_ok := true
	for p in paths:
		var res = load(p)
		var ok := res != null and (res is GDScript or res is Shader)
		print("  %s => %s" % [p, "ok" if ok else "FAILED"])
		if not ok:
			all_ok = false
	if all_ok:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/battle_tracer.gdshader")
		var vp := SubViewport.new()
		vp.own_world_3d = true
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		mi.material_override = mat
		vp.add_child(mi)
		root.add_child(vp)
		print("  tracer ShaderMaterial on MeshInstance3D => ok")
	return all_ok
