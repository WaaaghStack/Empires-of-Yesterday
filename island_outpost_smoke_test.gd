extends SceneTree

## Headless: island outpost claimable + pressure injection.
## godot --headless --path . -s res://island_outpost_smoke_test.gd

const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")


func _init() -> void:
	print("=== Island Outpost Smoke Test ===")
	_run()
	quit()


func _run() -> void:
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
		return
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

	for _i in range(20):
		sim.advance_round()

	var pf: float = tc.pressure_friendly[idx]
	_log(lines, "After 20 rounds friendly pressure at island: %s" % pf)
	if tc.claimable_mask[idx] == 0:
		_log(lines, "FAIL island tile still unclaimable on CPU tile_control")
	elif pf < 0.001:
		_log(lines, "FAIL no friendly pressure injected on island (backend=%s)" % backend)
	else:
		_log(lines, "PASS island outpost pressure OK (backend=%s)" % backend)
	_write(lines)


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
