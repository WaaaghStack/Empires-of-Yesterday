extends SceneTree
## Headless: godot --headless --path . -s res://sphere_live_path_smoke_test.gd
## Avoids BattleTerritorySim (RunState autoload) — exercises map gen, Rust sim, routing.

const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const RoutePlannerRustBackendLib := preload("res://RoutePlannerRustBackend.gd")


func _init() -> void:
	print("=== Sphere Live Path Smoke ===")
	call_deferred("_run")


func _run() -> void:
	var code: int = _execute()
	if code == 0:
		print("PASS sphere live path smoke")
	else:
		print("FAIL sphere live path smoke")
	quit(code)


func _execute() -> int:
	if not WorldConquestConfigLib.SPHERE_GRID_ENABLED:
		print("FAIL SPHERE_GRID_ENABLED is false")
		return 1
	if not BattleTerritoryRustBackendLib.extension_available():
		print("FAIL TerritorySim extension missing")
		return 1

	var t0: int = Time.get_ticks_msec()
	var map_data = WorldConquestMapGeneratorLib.generate("earth", 424242)
	var gen_ms: int = Time.get_ticks_msec() - t0
	if map_data == null or not map_data.sphere_mode:
		print("FAIL map gen sphere_mode")
		return 1
	print(
		"OK  map cells=%d gen_ms=%d homes=%s / %s"
		% [map_data.cell_count, gen_ms, str(map_data.player_home_grid), str(map_data.enemy_home_grid)]
	)
	if map_data.equirect_to_cell.size() != map_data.overlay_width * map_data.overlay_height:
		print("FAIL equirect_to_cell size")
		return 1
	print("OK  equirect_to_cell size=%d" % map_data.equirect_to_cell.size())

	var tile := BattleTileControlLib.new()
	tile.setup(map_data)
	tile.enable_world_conquest_model(
		WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE
	)
	tile.seed_territory_battle(map_data)

	var rust := BattleTerritoryRustBackendLib.new()
	if not rust.setup_from_tile_control(map_data, tile, true):
		print("FAIL rust setup_from_tile_control")
		return 1
	print("OK  rust setup grid_authority")

	for _i in range(14):
		rust.step_round(tile)
	print("OK  rust stepped 14 rounds")

	var home: Vector2i = map_data.player_home_grid
	var target_cell := -1
	var seen: Dictionary = {}
	var queue: Array = [home.x]
	seen[home.x] = true
	var head := 0
	while head < queue.size() and target_cell < 0:
		var cur: int = int(queue[head])
		head += 1
		for n in map_data.get_neighbors(cur):
			var ni: int = int(n)
			if seen.has(ni):
				continue
			seen[ni] = true
			queue.append(ni)
			if map_data.is_land_cell_id(ni) and ni != home.x and queue.size() > 8:
				target_cell = ni
				break
	if target_cell < 0:
		print("FAIL no land target near home")
		return 1

	var target := Vector2i(target_cell, 0)
	var packed: Dictionary = OutpostBuildLib.pack_route_snapshot(map_data, [])
	if int(packed.get("grid_w", 0)) != map_data.cell_count:
		print("FAIL route snapshot grid_w=%s" % str(packed.get("grid_w", null)))
		return 1
	print("OK  route snapshot grid_w=%d" % int(packed.grid_w))

	var planner := RoutePlannerRustBackendLib.new()
	if not planner.setup_map(map_data, []):
		print("FAIL route planner setup_map")
		return 1
	planner.rebuild_portals(map_data, [], home)
	var route: Dictionary = planner.find_route_sync(target, OutpostBuildLib.KIND_SPAWNER, true)
	var path: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path.is_empty():
		var fb: Dictionary = OutpostBuildLib.nearest_path_to_target(map_data, target, [home], 0, true)
		path = fb.get("path_packed", PackedInt32Array())
		print("WARN rust route empty; fallback len=%d" % path.size())
	else:
		print("OK  rust outpost route len=%d" % path.size())
	if path.is_empty():
		print("FAIL no path to target %d" % target_cell)
		return 1
	if not OutpostBuildLib.path_is_cardinal_dense(map_data, path):
		print("FAIL path not graph-dense")
		return 1
	print("OK  path graph-dense")

	if map_data.is_land_cell_id(home.x) and not OutpostBuildLib.is_water_cell(map_data, home.x, 0):
		print("OK  is_water_cell land home")
	else:
		print("FAIL is_water_cell on land home")
		return 1

	return 0
