extends SceneTree

## Headless: island outpost claimable + pressure injection + globe visual paths.
## godot --headless --path . -s res://island_outpost_smoke_test.gd

const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const EarthGlobeMapLib := preload("res://EarthGlobeMap.gd")
const RunLogLib := preload("res://RunLog.gd")

var _passed: bool = false


func _init() -> void:
	print("=== Island Outpost Smoke Test ===")
	_passed = _run()
	quit(0 if _passed else 1)


func _run() -> bool:
	var lines: PackedStringArray = PackedStringArray()
	var rust_loaded: bool = ClassDB.class_exists("TerritorySim")
	_log(lines, "TerritorySim loaded: %s" % rust_loaded)
	if rust_loaded:
		var probe: RefCounted = ClassDB.instantiate("TerritorySim")
		_log(lines, "Has update_claimable: %s" % probe.has_method("update_claimable"))

	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, 200, 200, null, {}, true)

	var backend: String = "cpu"
	if sim.enable_rust_live():
		backend = "rust"
	else:
		_log(lines, "enable_rust_live failed (using CPU)")
	_log(lines, "Territory backend: %s" % backend)

	var tc := sim.tile_control
	var home: Vector2i = map_data.player_home_grid
	var island: Vector2i = _find_isolated_land(map_data, home)
	if island.x < 0:
		_log(lines, "FAIL no isolated landmass")
		_write(lines)
		return false
	_log(lines, "HQ %s island %s" % [home, island])

	var idx: int = map_data.cell_index(island.x, island.y)
	_log(
		lines,
		"Before outpost claimable=%d owners=%d rust_claimable=n/a" % [
			tc.claimable_mask[idx], tc.owners[idx]
		]
	)

	map_data.placed_structures.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": island.x,
		"gy": island.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_ACTIVE,
	})
	tc.sync_placed_spawners_from_map(map_data)
	tc.claim_tile(island.x, island.y, BattleTileControlLib.OWNER_FRIENDLY)
	if sim.rust_live_ready and sim.rust_field != null:
		sim.rust_field.sync_claimable_from(tc, map_data, true)
		sim.rust_field.sync_spawners_from(tc)

	_log(
		lines,
		"After sync claimable=%d owners=%d claimable_tiles=%d" % [
			tc.claimable_mask[idx], tc.owners[idx], tc.claimable_tile_count
		]
	)

	for _i in range(80):
		sim.advance_dt(1.0 / 14.0, 1)

	var pf: float = 0.0
	if backend == "rust" and sim.rust_field != null:
		var pf_arr: PackedFloat32Array = sim.rust_field.get_pressure_friendly()
		if idx >= 0 and idx < pf_arr.size():
			pf = pf_arr[idx]
	else:
		pf = tc.pressure_friendly[idx]
	_log(lines, "After 80 steps friendly pressure at island: %s" % pf)
	var sim_ok: bool = false
	if tc.claimable_mask[idx] == 0:
		_log(lines, "FAIL island tile still unclaimable on CPU tile_control")
	elif pf < 0.001:
		_log(lines, "FAIL no friendly pressure injected on island (backend=%s)" % backend)
	else:
		_log(lines, "PASS island outpost pressure OK (backend=%s)" % backend)
		sim_ok = true

	var visual_ok: bool = _run_visual_smoke(map_data, lines)
	_write(lines)
	return sim_ok and visual_ok


func _run_visual_smoke(map_data, lines: PackedStringArray) -> bool:
	var globe := EarthGlobeMapLib.new()
	root.add_child(globe)
	globe.setup(map_data)
	var w: int = map_data.grid_width
	var home: Vector2i = map_data.player_home_grid
	var path: Array[Vector2i] = [home]
	for step in range(4):
		path.append(Vector2i((home.x + 1 + step) % w, home.y))
	var packed: PackedInt32Array = OutpostBuildLib.path_to_packed_keys(path, w)
	var landing: Vector2i = path[path.size() - 1]
	map_data.placed_structures.append({
		"id": 2,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": landing.x,
		"gy": landing.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_built": 2.0,
		"path_len": path.size(),
		"path_keys": packed,
	})
	globe.sync_roads(map_data.placed_structures, [2])
	RunLogLib.emit_info("action=roads structures=%d" % map_data.placed_structures.size())
	globe.refresh_markers(
		map_data.placed_structures, home, map_data.enemy_home_grid, [2]
	)
	RunLogLib.emit_info("action=markers structures=%d" % map_data.placed_structures.size())
	var patch_idx: int = map_data.cell_index(landing.x, landing.y)
	var idxs := PackedInt32Array([patch_idx])
	var vals := PackedByteArray([BattleTileControlLib.OWNER_FRIENDLY])
	globe.apply_ownership_overlay_delta(idxs, vals)
	RunLogLib.emit_info("action=overlay:delta cells=1")
	if globe.flush_pending_owner_gpu_upload():
		_log(lines, "FAIL gpu_upload committed same frame as overlay delta")
		globe.queue_free()
		return false
	RunLogLib.emit_info("action=gpu_upload deferred same_frame=1")
	if not globe.owner_gpu_upload_pending():
		_log(lines, "FAIL expected pending gpu upload after overlay delta")
		globe.queue_free()
		return false
	globe.queue_free()
	_log(lines, "PASS island visual smoke (roads/markers/overlay defer)")
	return true


func _log(lines: PackedStringArray, msg: String) -> void:
	print(msg)
	lines.append(msg)


func _write(lines: PackedStringArray) -> void:
	var f := FileAccess.open("res://island_outpost_smoke_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_line(line)
		f.close()


func _find_isolated_land(map_data, home: Vector2i) -> Vector2i:
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