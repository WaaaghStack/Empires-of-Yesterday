extends SceneTree

## Headless: soldier nav rules — march to unclaimed land, bridge crossing, hostile team.
## godot --headless --path . -s res://soldier_nav_smoke_test.gd

const CFG := preload("res://WorldConquestConfig.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const RoutePlannerLib := preload("res://RoutePlannerRustBackend.gd")


func _init() -> void:
	print("=== Soldier Nav Smoke Test ===")
	_run()
	quit()


func _run() -> void:
	var lines: PackedStringArray = PackedStringArray()
	if not BattleTerritoryRustBackendLib.extension_available():
		_fail(lines, "Rust GDExtension not loaded")
		return

	if not _friendly_moves(lines):
		_write(lines)
		return
	_log(lines, "OK friendly soldier moved toward frontier")

	if not _hostile_moves(lines):
		_write(lines)
		return
	_log(lines, "OK hostile soldier moved toward frontier")

	if not _bridge_crossing(lines):
		_write(lines)
		return
	_log(lines, "OK soldier path crosses land bridge")

	_log(lines, "PASS soldier nav smoke")
	_write(lines)


func _friendly_moves(lines: PackedStringArray) -> bool:
	var map_data = EarthMapGeneratorLib.generate(4242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := _make_sim(map_data)
	var bid: int = 99
	var home: Vector2i = map_data.player_home_grid
	if not sim.try_spawn_soldier(bid, BattleTileControlLib.OWNER_FRIENDLY, home.x, home.y):
		_fail(lines, "friendly spawn failed")
		return false
	var snap0: Dictionary = sim.get_agent_snapshot()
	var gx0: PackedInt32Array = snap0.get("gx", PackedInt32Array())
	var gy0: PackedInt32Array = snap0.get("gy", PackedInt32Array())
	if gx0.is_empty():
		_fail(lines, "friendly soldier missing after spawn")
		return false
	var sx: int = gx0[0]
	var sy: int = gy0[0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		_fail(lines, "friendly soldier died")
		return false
	if snap["gx"][0] == sx and snap["gy"][0] == sy:
		_fail(lines, "friendly soldier did not move")
		return false
	return true


func _hostile_moves(lines: PackedStringArray) -> bool:
	var map_data = EarthMapGeneratorLib.generate(7777)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := _make_sim(map_data)
	var enemy_home: Vector2i = map_data.enemy_home_grid
	var bid: int = 100
	if not sim.try_spawn_soldier(bid, BattleTileControlLib.OWNER_HOSTILE, enemy_home.x, enemy_home.y):
		_fail(lines, "hostile spawn failed")
		return false
	var snap0: Dictionary = sim.get_agent_snapshot()
	var sx: int = snap0["gx"][0]
	var sy: int = snap0["gy"][0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		_fail(lines, "hostile soldier died")
		return false
	if snap["gx"][0] == sx and snap["gy"][0] == sy:
		_fail(lines, "hostile soldier did not move")
		return false
	return true


func _bridge_crossing(lines: PackedStringArray) -> bool:
	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var home: Vector2i = map_data.player_home_grid
	var inland: Vector2i = _find_inland_foreign(map_data, home)
	if inland.x < 0:
		_log(lines, "SKIP bridge crossing (no inland foreign tile)")
		return true
	var coastal: Vector2i = OutpostBuildLib.snap_to_nearest_coast(map_data, inland)
	if coastal.x < 0:
		_fail(lines, "no coastal landing for bridge test")
		return false
	var route: Dictionary = _rust_placement_route(map_data, coastal, home)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		_fail(lines, "no bridge route for soldier test")
		return false
	_install_persisted_land_bridge(map_data, coastal, path_packed, 11)
	var sim := _make_sim(map_data)
	var tc := sim.tile_control
	tc.sync_bridge_corridors_from_map(map_data, true)
	sim.sync_agent_nav()
	if sim.rust_field != null:
		sim.rust_field.sync_bridge_corridors_rust(map_data, true)
		sim.rust_field.sync_agent_nav_from(tc)
	var bid: int = 101
	if not sim.try_spawn_soldier(bid, BattleTileControlLib.OWNER_FRIENDLY, home.x, home.y):
		_fail(lines, "bridge spawn failed")
		return false
	var bridge_keys: Dictionary = {}
	for key: int in path_packed:
		bridge_keys[key] = true
	var crossed: bool = false
	for _i in range(40):
		sim.advance_round()
		var snap: Dictionary = sim.get_agent_snapshot()
		if int(snap.get("count", 0)) < 1:
			_fail(lines, "soldier died during bridge march")
			return false
		var gx: int = snap["gx"][0]
		var gy: int = snap["gy"][0]
		var key: int = map_data.cell_index(gx, gy)
		if bridge_keys.has(key):
			crossed = true
			break
	if not crossed:
		_fail(lines, "soldier never entered bridge corridor")
		return false
	return true


func _make_sim(map_data) -> BattleTerritorySimLib:
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		push_error("soldier_nav_smoke_test: rust live failed")
		return null
	if not sim.agents_ready():
		push_error("soldier_nav_smoke_test: agents not configured")
		return null
	sim.sync_agent_nav()
	return sim


func _rust_placement_route(map_data, landing: Vector2i, home: Vector2i) -> Dictionary:
	var empty: Dictionary = {"path_packed": PackedInt32Array()}
	if not RoutePlannerLib.extension_available():
		return empty
	var planner := RoutePlannerLib.new()
	var structures: Array = map_data.placed_structures
	if not planner.setup_map(map_data, structures):
		return empty
	planner.rebuild_portals(map_data, structures, home)
	return planner.find_route_sync(landing, OutpostBuildLib.KIND_CORRIDOR_LINK, true)


func _install_persisted_land_bridge(
	map_data, coastal: Vector2i, path_packed: PackedInt32Array, corridor_id: int
) -> void:
	map_data.bridge_corridors = []
	map_data.placed_structures.clear()
	map_data.placed_structures.append({
		"id": corridor_id,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": coastal.x,
		"gy": coastal.y,
		"kind": OutpostBuildLib.KIND_CORRIDOR_LINK,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": float(path_packed.size()),
		"source_gx": map_data.player_home_grid.x,
		"source_gy": map_data.player_home_grid.y,
	})
	var corridor_st: Dictionary = map_data.placed_structures[0]
	map_data.bridge_corridors.append({
		"id": int(corridor_st.get("id", corridor_id)),
		"team": int(corridor_st.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
		"gx": coastal.x,
		"gy": coastal.y,
		"path_keys": path_packed,
	})
	map_data.placed_structures.clear()


func _find_inland_foreign(map_data, home: Vector2i) -> Vector2i:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if not OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), [home]):
				continue
			if OutpostBuildLib.is_coastal_cell(map_data, gx, gy):
				continue
			return Vector2i(gx, gy)
	return Vector2i(-1, -1)


func _log(lines: PackedStringArray, msg: String) -> void:
	print(msg)
	lines.append(msg)


func _fail(lines: PackedStringArray, msg: String) -> void:
	_log(lines, "FAIL %s" % msg)


func _write(lines: PackedStringArray) -> void:
	var f := FileAccess.open("res://soldier_nav_smoke_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_line(line)
		f.close()
