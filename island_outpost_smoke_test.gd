extends SceneTree

## Headless: R1 island claim via ferry beachhead, then outpost pressure + globe visuals.
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
		"Before beachhead claimable=%d owners=%d" % [
			tc.claimable_mask[idx] if idx >= 0 and idx < tc.claimable_mask.size() else -1,
			tc.owners[idx] if idx >= 0 and idx < tc.owners.size() else -1,
		]
	)

	# R1: ferry beachhead opens the foreign landmass — not bridges, not outpost-on-unclaimable.
	var beach: Dictionary = {}
	if backend == "rust" and sim.rust_field != null:
		beach = sim.rust_field.extend_beachhead_from_landing(
			island.x, island.y, BattleTileControlLib.OWNER_FRIENDLY
		)
		if sim.rust_field.has_method("apply_world_edit_result"):
			sim.rust_field.apply_world_edit_result(tc, beach, map_data)
	elif tc != null:
		tc.extend_beachhead_from_landing(
			map_data, island.x, island.y, BattleTileControlLib.OWNER_FRIENDLY
		)

	var claimable_now: bool = false
	if backend == "rust" and sim.rust_field != null and sim.rust_field.has_method("claimable_at_index"):
		claimable_now = bool(sim.rust_field.claimable_at_index(idx))
	elif idx >= 0 and idx < tc.claimable_mask.size():
		claimable_now = int(tc.claimable_mask[idx]) != 0
	if not claimable_now and not bool(beach.get("changed", false)):
		_log(lines, "FAIL ferry beachhead did not claim island %s" % island)
		_write(lines)
		return false
	_log(lines, "OK ferry beachhead claimable island=%s" % island)

	map_data.placed_structures.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": island.x,
		"gy": island.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_ACTIVE,
	})
	# Under rust live + grid authority the CPU claimable mirror stays frozen; spawners alone
	# drive pressure inject once beachhead made the landmass claimable.
	if not (backend == "rust" and tc.grid_mirror_frozen):
		tc.sync_placed_spawners_from_map(map_data)
	else:
		tc._load_placed_spawners_from_map(map_data)
	if sim.rust_live_ready and sim.rust_field != null:
		sim.rust_field.sync_spawners_from(tc)

	_log(
		lines,
		"After outpost sync claimable_tiles=%d" % tc.claimable_tile_count
	)

	for _i in range(80):
		sim.advance_dt(1.0 / 14.0, 1)

	var pf_neighbor: float = _max_neighbor_friendly_pressure(
		map_data, island, backend, sim, tc
	)
	_log(lines, "After 80 steps max friendly pressure on island neighbors: %s" % pf_neighbor)
	var sim_ok: bool = false
	if pf_neighbor < 0.001:
		_log(lines, "FAIL no friendly pressure injected near island (backend=%s)" % backend)
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
	var home: Vector2i = map_data.player_home_grid
	var landing: Vector2i = home
	if map_data.sphere_mode:
		for nbr: int in map_data.get_neighbors(home.x):
			if map_data.is_land_cell_id(nbr):
				landing = Vector2i(nbr, 0)
				break
	else:
		var w: int = map_data.grid_width
		landing = Vector2i((home.x + 1) % w, home.y)
	map_data.placed_structures.append({
		"id": 2,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": landing.x,
		"gy": landing.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_ACTIVE,
		"path_built": 1.0,
		"path_len": 1,
		"path_keys": PackedInt32Array([map_data.cell_index(landing.x, landing.y)]),
	})
	# R1: sync_roads is a no-op; keep call so RunLog action sequence stays comparable.
	globe.sync_roads(map_data.placed_structures, [2])
	RunLogLib.emit_info("action=markers structures=%d" % map_data.placed_structures.size())
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
	_log(lines, "PASS island visual smoke (instant ACTIVE + markers/overlay defer)")
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


func _max_neighbor_friendly_pressure(
	map_data, center: Vector2i, backend: String, sim, tc
) -> float:
	## Spawner inject uses sphere graph neighbors on Earth maps — not flat cardinals.
	var best: float = 0.0
	var neighbor_idxs: Array[int] = []
	if map_data.sphere_mode:
		for nbr: int in map_data.get_neighbors(center.x):
			if map_data.is_land_cell_id(nbr):
				neighbor_idxs.append(nbr)
	else:
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		for d in dirs:
			var nx: int = center.x + d.x
			var ny: int = center.y + d.y
			if not map_data.is_land_cell(nx, ny):
				continue
			neighbor_idxs.append(map_data.cell_index(nx, ny))
	var pf_arr: PackedFloat32Array = PackedFloat32Array()
	var use_rust_pf: bool = backend == "rust" and sim.rust_field != null
	if use_rust_pf:
		pf_arr = sim.rust_field.get_pressure_friendly()
	for nidx in neighbor_idxs:
		if nidx < 0:
			continue
		var pf: float = 0.0
		if use_rust_pf:
			if nidx < pf_arr.size():
				pf = pf_arr[nidx]
		else:
			pf = tc.pressure_friendly[nidx]
		best = maxf(best, pf)
	return best


func _find_isolated_land(map_data, home: Vector2i) -> Vector2i:
	var sources: Array[Vector2i] = [home]
	if map_data.sphere_mode:
		for cid in range(map_data.cell_count):
			if not map_data.is_land_cell_id(cid):
				continue
			if OutpostBuildLib.needs_bridge_route(map_data, Vector2i(cid, 0), sources):
				return Vector2i(cid, 0)
		return Vector2i(-1, -1)
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), sources):
				return Vector2i(gx, gy)
	return Vector2i(-1, -1)
