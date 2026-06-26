extends SceneTree

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const RoutePlannerLib := preload("res://RoutePlannerRustBackend.gd")

func _init() -> void:
	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var home: Vector2i = map_data.player_home_grid
	var inland: Vector2i = _find_inland_foreign(map_data, home, [home])
	var coastal: Vector2i = OutpostBuildLib.snap_to_nearest_coast(map_data, inland)
	var structures: Array = map_data.placed_structures
	var planner := RoutePlannerLib.new()
	var setup_ok: bool = planner.setup_map(map_data, structures)
	print("api_version=%s" % str(planner._planner.call("route_planner_api_version")))
	planner.rebuild_portals(map_data, structures, home, BattleTileControlLib.OWNER_FRIENDLY)
	var ffi: Dictionary = planner._planner.call(
		"find_route_sync",
		coastal.x,
		coastal.y,
		RoutePlannerLib.ROUTE_KIND_CORRIDOR,
		true,
	)
	var decoded: Dictionary = planner.decode_route_result(ffi)
	var lines: PackedStringArray = PackedStringArray([
		"setup=%s home=%s coastal=%s" % [setup_ok, home, coastal],
		"ffi_keys=%s" % str(ffi.keys()),
		"ffi found=%s reject=%s expand=%s path=%d" % [
			ffi.get("found", false),
			ffi.get("reject", "missing"),
			ffi.get("expand_count", "missing"),
			int(ffi.get("path_packed", PackedInt32Array()).size()),
		],
		"decoded path=%d reject=%s expand=%s" % [
			decoded.path_packed.size(),
			decoded.get("reject", "missing"),
			decoded.get("expand_count", "missing"),
		],
	])
	for line in lines:
		print(line)
	var log := FileAccess.open("res://tools/route_debug_result.txt", FileAccess.WRITE)
	for line in lines:
		log.store_line(line)
	log.close()
	quit(0 if decoded.path_packed.size() > 0 else 1)


func _find_inland_foreign(map_data, home: Vector2i, sources: Array[Vector2i]) -> Vector2i:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if not OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), sources):
				continue
			if OutpostBuildLib.is_coastal_cell(map_data, gx, gy):
				continue
			return Vector2i(gx, gy)
	return Vector2i(-1, -1)
