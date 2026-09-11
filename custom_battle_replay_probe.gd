extends SceneTree

## Headless Custom Battle scenarios: pace clock + whether land chases aircraft.
## godot --headless --path . -s res://custom_battle_replay_probe.gd

const Pacing := preload("res://BattlePacing.gd")

func _init() -> void:
	print("=== Custom Battle replay probe ===")
	print("1x watch sec/frame=%.2f (was 0.56)" % Pacing.BATTLE_WATCH_SEC_PER_FRAME)
	if not ClassDB.class_exists("TwoWorldsEngine"):
		push_error("FAIL TwoWorldsEngine missing")
		quit()
		return
	var engine = ClassDB.instantiate("TwoWorldsEngine")
	var fail := 0
	fail += _probe(engine, "line vs line", _roster_line())
	fail += _probe(engine, "line vs bombers", _roster_line_vs_wings())
	fail += _probe(engine, "clerks vs wings", _roster_clerks_vs_wings())
	fail += _probe(engine, "stove charge vs line", _roster_stove())
	fail += _probe(engine, "compact mix", _roster_compact())
	fail += _probe(engine, "line around hill", _roster_hill())
	fail += _profile_viewer(engine)
	if fail == 0:
		print("PASS custom battle replay probe")
	else:
		push_error("FAIL custom battle replay probe (%d)" % fail)
	quit()


func _probe(engine, name: String, roster: Dictionary) -> int:
	print("--- %s ---" % name)
	_resolve(engine, roster)
	var meta: Dictionary = engine.get_last_battle_meta(0)
	var frames := int(meta.get("frame_count", 0))
	var n := int(meta.get("unit_count", 0))
	var kinds: PackedByteArray = meta.get("kind", PackedByteArray())
	var watch := float(frames) * Pacing.BATTLE_WATCH_SEC_PER_FRAME
	print("  units=%d frames=%d 1x_watch=%.0fs" % [n, frames, watch])
	if frames < 8:
		push_error("%s: too few frames" % name)
		return 1
	var land_air := 0
	var land_land := 0
	var clerk_air := 0
	var air_z := 0.0
	var fire_frames := 0
	var min_inf_gap := 9999.0
	var min_sol_gap := 9999.0
	var hill_cleared := 0
	var hill_inside := 0
	var facs: PackedByteArray = meta.get("fac", PackedByteArray())
	for fidx in frames:
		var fr: Dictionary = engine.get_last_battle_frame_xy(0, fidx)
		var st: PackedByteArray = fr.get("state", PackedByteArray())
		var az: PackedFloat32Array = fr.get("aim_z", PackedFloat32Array())
		var zs: PackedFloat32Array = fr.get("z", PackedFloat32Array())
		var xs: PackedFloat32Array = fr.get("x", PackedFloat32Array())
		var ys: PackedFloat32Array = fr.get("y", PackedFloat32Array())
		var alive: PackedByteArray = fr.get("alive", PackedByteArray())
		var fired := false
		var a_xs: Array[float] = []
		var d_xs: Array[float] = []
		var a_sol: Array[float] = []
		var d_sol: Array[float] = []
		for i in n:
			if i >= kinds.size() or i >= st.size():
				continue
			var k := int(kinds[i])
			if k == 1 and i < zs.size():
				air_z = maxf(air_z, float(zs[i]))
			var s := int(st[i])
			if s == 3:
				fired = true
				var zaim := float(az[i]) if i < az.size() else 0.0
				if k == 7:
					if zaim > 5.0:
						clerk_air += 1
				elif k != 1:
					if zaim > 5.0:
						land_air += 1
					else:
						land_land += 1
			if k != 1 and k != 6 and i < xs.size() and s != 4 and s != 6:
				if i < alive.size() and int(alive[i]) == 0:
					continue
				if i < facs.size() and int(facs[i]) == 0:
					a_xs.append(float(xs[i]))
					if k == 0:
						a_sol.append(float(xs[i]))
				elif i < facs.size():
					d_xs.append(float(xs[i]))
					if k == 0:
						d_sol.append(float(xs[i]))
			if k != 1 and i < ys.size():
				if i < alive.size() and int(alive[i]) == 0:
					continue
				var zz := float(zs[i]) if i < zs.size() else 0.0
				if zz <= 0.5:
					var hdx := float(xs[i]) - 260.0
					var hdy := float(ys[i]) - 460.0
					if hdx * hdx + hdy * hdy < 128.8 * 128.8:
						hill_inside += 1
					if i < facs.size() and int(facs[i]) == 0 and float(xs[i]) > 268.0:
						hill_cleared += 1
		if fired:
			fire_frames += 1
		if a_xs.size() >= 4 and d_xs.size() >= 4:
			a_xs.sort()
			d_xs.sort()
			min_inf_gap = minf(
				min_inf_gap,
				absf(float(a_xs[a_xs.size() / 2]) - float(d_xs[d_xs.size() / 2]))
			)
		if a_sol.size() >= 4 and d_sol.size() >= 4:
			a_sol.sort()
			d_sol.sort()
			min_sol_gap = minf(
				min_sol_gap,
				absf(float(a_sol[a_sol.size() / 2]) - float(d_sol[d_sol.size() / 2]))
			)
	print("  fire: frames=%d land->land=%d land->air=%d clerks->air=%d land_gap=%.1f sol_gap=%.1f" % [
		fire_frames, land_land, land_air, clerk_air, min_inf_gap, min_sol_gap
	])
	print("  max bomber z=%.1f hill_cleared=%d hill_inside=%d" % [air_z, hill_cleared, hill_inside])
	if _dead_air_still_hovering(engine, 0, n, kinds, frames):
		push_error("%s: dead flyers still crumpled at altitude" % name)
		return 1
	if Pacing.BATTLE_WATCH_SEC_PER_FRAME < 1.5:
		push_error("%s: 1x watch clock is still a timelapse (%.2fs/frame)" % [name, Pacing.BATTLE_WATCH_SEC_PER_FRAME])
		return 1
	if name == "line vs bombers" and (land_land == 0 or land_air * 3 > land_land):
		push_error("%s: line is chasing aircraft (land=%d air=%d)" % [name, land_land, land_air])
		return 1
	if name == "line vs line" and land_land == 0:
		push_error("%s: no land fire baked" % name)
		return 1
	if name == "clerks vs wings" and clerk_air == 0:
		push_error("%s: clerks not aiming at air" % name)
		return 1
	if name == "stove charge vs line" and land_land == 0:
		push_error("%s: chargers never fired" % name)
		return 1
	if name != "clerks vs wings" and fire_frames < 2:
		push_error("%s: no fire baked (frames=%d)" % [name, fire_frames])
		return 1
	if name != "clerks vs wings" and name != "compact mix" and min_inf_gap > 140.0:
		push_error("%s: land lines never closed (gap=%.1f)" % [name, min_inf_gap])
		return 1
	if name == "compact mix" and land_land == 0:
		push_error("%s: mixed roster never fought on land" % name)
		return 1
	if name == "compact mix" and frames >= 400:
		push_error("%s: leftover air/train kept the tape running (frames=%d)" % [name, frames])
		return 1
	if name == "line around hill" and hill_inside > 0:
		push_error("%s: land walked into the hill (inside=%d)" % [name, hill_inside])
		return 1
	if name == "line around hill" and hill_cleared == 0:
		push_error("%s: line milled on the hill rim" % name)
		return 1
	if name == "line vs line":
		return _check_volley_tracers(engine, frames, n)
	return 0


func _check_volley_tracers(engine, frames: int, n: int) -> int:
	print("--- volley tracers (FX sized to the bake, no pool cap) ---")
	var ViewScript: GDScript = load("res://BattleView.gd")
	var cap := int(ViewScript.fx_capacity(n))
	if cap < n:
		push_error("fx_capacity(%d)=%d still a pool cap" % [n, cap])
		return 1
	if int(ViewScript.fx_capacity(10000)) < 10000:
		push_error("fx_capacity does not cover a 10k bake")
		return 1
	if not engine.has_method("fill_battle_watch_pose"):
		push_error("fill_battle_watch_pose missing")
		return 1
	var peak := 0
	var peak_f := 1.0
	for fidx in mini(frames, 120):
		var st: PackedByteArray = engine.get_last_battle_frame_xy(0, fidx).get("state", PackedByteArray())
		var fire_n := 0
		for s in st:
			if int(s) == 3:
				fire_n += 1
		if fire_n > peak:
			peak = fire_n
			peak_f = float(fidx)
	var a: Dictionary = engine.fill_battle_watch_pose(0, peak_f, 0)
	var b: Dictionary = engine.fill_battle_watch_pose(0, peak_f, 2)
	var na := (a.get("fire_unit", PackedInt32Array()) as PackedInt32Array).size()
	var nb := (b.get("fire_unit", PackedInt32Array()) as PackedInt32Array).size()
	print("  units=%d peak_st_fire=%d lod0_tracers=%d lod2_tracers=%d fx_cap=%d" % [n, peak, na, nb, cap])
	if peak < 8:
		push_error("line vs line never peaked a volley (peak=%d)" % peak)
		return 1
	if na != nb:
		push_error("lod thinned tracers (%d vs %d)" % [na, nb])
		return 1
	if cap < peak:
		push_error("fx_capacity=%d cannot light peak volley %d" % [cap, peak])
		return 1
	return 0


func _resolve(engine, spec: Dictionary) -> void:
	engine.resolve_custom_battle_plan(
		int(spec.get("seed", 4)),
		0,
		0,
		spec.fac,
		spec.kind,
		spec.count,
		spec.xs,
		spec.ys,
		spec.facing,
		spec.formation,
		spec.orders,
	)


func _row(fac: int, kind: int, count: int, x: float, y: float) -> Dictionary:
	return {
		"fac": fac, "kind": kind, "count": count, "x": x, "y": y,
		"facing": 0.0 if fac == 0 else 3.14159, "formation": 0, "order": 0,
	}


func _pack(seed: int, rows: Array) -> Dictionary:
	var fac := PackedByteArray()
	var kind := PackedByteArray()
	var count := PackedInt32Array()
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var facing := PackedFloat32Array()
	var formation := PackedByteArray()
	var orders := PackedByteArray()
	for r in rows:
		fac.append(int(r.fac))
		kind.append(int(r.kind))
		count.append(int(r.count))
		xs.append(float(r.x))
		ys.append(float(r.y))
		facing.append(float(r.facing))
		formation.append(int(r.formation))
		orders.append(int(r.order))
	return {
		"seed": seed, "fac": fac, "kind": kind, "count": count,
		"xs": xs, "ys": ys, "facing": facing, "formation": formation, "orders": orders,
	}


func _roster_line() -> Dictionary:
	return _pack(11, [
		_row(0, 0, 80, 160.0, 300.0),
		_row(1, 0, 80, 840.0, 300.0),
	])


func _roster_line_vs_wings() -> Dictionary:
	return _pack(12, [
		_row(0, 0, 60, 160.0, 300.0),
		_row(1, 0, 40, 840.0, 300.0),
		_row(1, 1, 5, 840.0, 200.0),
	])


func _roster_clerks_vs_wings() -> Dictionary:
	return _pack(13, [
		_row(0, 7, 40, 200.0, 300.0),
		_row(0, 0, 20, 160.0, 360.0),
		_row(1, 1, 5, 840.0, 300.0),
	])


func _roster_stove() -> Dictionary:
	return _pack(14, [
		_row(0, 2, 40, 180.0, 300.0),
		_row(1, 0, 40, 820.0, 300.0),
	])


func _roster_compact() -> Dictionary:
	# Open ground (hill sits around y=460). Rank bands like Custom Battle templates.
	var rows: Array = []
	var sizes := [16, 5, 12, 8, 8, 4, 2, 10]
	var ys := [200.0, 120.0, 250.0, 300.0, 160.0, 220.0, 280.0, 190.0]
	for fac_i in 2:
		var x := 160.0 if fac_i == 0 else 840.0
		for k in 8:
			rows.append(_row(fac_i, k, int(sizes[k]), x, float(ys[k])))
	return _pack(15, rows)


func _roster_hill() -> Dictionary:
	# Hill center is (260, 460). Lines start on the chord so they must walk around.
	return _pack(16, [
		_row(0, 0, 36, 160.0, 460.0),
		_row(1, 0, 36, 840.0, 460.0),
	])


func _dead_air_still_hovering(engine, index: int, n: int, kinds: PackedByteArray, frames: int) -> bool:
	if frames < 1:
		return false
	var last: Dictionary = engine.get_last_battle_frame_xy(index, frames - 1)
	var zs: PackedFloat32Array = last.get("z", PackedFloat32Array())
	var alive: PackedByteArray = last.get("alive", PackedByteArray())
	var hovering := 0
	var dead_air := 0
	for i in mini(n, kinds.size()):
		if int(kinds[i]) != 1:
			continue
		if i < alive.size() and int(alive[i]) != 0:
			continue
		dead_air += 1
		if i < zs.size() and float(zs[i]) > 1.5:
			hovering += 1
	print("  dead air=%d hovering_at_altitude=%d" % [dead_air, hovering])
	return hovering > 0


func _profile_viewer(engine) -> int:
	print("--- viewer draw profile (baked replay, not combat) ---")
	_resolve(engine, _roster_fps())
	var meta: Dictionary = engine.get_last_battle_meta(0)
	var n := int(meta.get("unit_count", 0))
	var frames := int(meta.get("frame_count", 0))
	if n < 200 or frames < 4:
		push_error("fps roster too small units=%d frames=%d" % [n, frames])
		return 1
	if not engine.has_method("fill_battle_watch_pose"):
		push_error("fill_battle_watch_pose missing")
		return 1
	var posed: Dictionary = engine.fill_battle_watch_pose(0, 1.0, 0)
	if not bool(posed.get("ok", false)):
		push_error("fill_battle_watch_pose failed")
		return 1
	var pbufs: Array = posed.get("bufs", [])
	if pbufs.size() != 16:
		push_error("watch pose bufs=%d" % pbufs.size())
		return 1
	var t0 := Time.get_ticks_usec()
	for _i in 8:
		engine.get_last_battle_frame_xy(0, mini(_i, frames - 1))
	var ffi_ms := float(Time.get_ticks_usec() - t0) / 8.0 / 1000.0
	var view = load("res://BattleView.gd").new()
	root.add_child(view)
	view.play_engine_battle(engine, 0, {})
	var draw_ms := float(view.profile_render_ms(10))
	print("  units=%d frames=%d ffi_ms=%.2f draw_ms=%.2f  (10k ~%.0fms if linear)" % [
		n, frames, ffi_ms, draw_ms, draw_ms * 10000.0 / float(maxi(n, 1))
	])
	print("  note: bodies are MultiMesh billboards; combat is a Rust bake. Watch pose is mixed in Rust (fill_battle_watch_pose); Godot assigns buffers.")
	print("  prerendering video would freeze the Dominions camera.")
	if draw_ms > 2500.0:
		push_error("viewer draw path is broken (%.1fms at %d units)" % [draw_ms, n])
		return 1
	return 0


func _roster_fps() -> Dictionary:
	return _pack(21, [
		_row(0, 0, 400, 160.0, 300.0),
		_row(1, 0, 400, 840.0, 300.0),
	])
