class_name RoutePlannerRustBackend
extends RefCounted

const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")

const ROUTE_KIND_OUTPOST := 0
const ROUTE_KIND_CORRIDOR := 1

var ready: bool = false
var _planner: RefCounted
var _grid_w: int = 0


static func extension_available() -> bool:
	return ClassDB.class_exists("RoutePlanner")


func setup_map(map_data, structures: Array) -> bool:
	_free()
	if map_data == null or not extension_available():
		return false
	_planner = ClassDB.instantiate("RoutePlanner")
	if _planner == null:
		return false
	_grid_w = map_data.grid_width
	OutpostBuildLib.prepare_land_components(map_data)
	var packed: Dictionary = OutpostBuildLib.pack_route_snapshot(map_data, structures)
	if packed.is_empty():
		_free()
		return false
	if not _planner.call(
		"set_map_snapshot",
		packed.grid_w,
		packed.grid_h,
		packed.wrap_longitude,
		packed.land_mask,
		packed.bridge_mask,
		packed.land_comp,
	):
		_free()
		return false
	ready = true
	return true


func update_infra(map_data, structures: Array) -> bool:
	if not ready or _planner == null or map_data == null:
		return false
	if not _planner.has_method("update_infra_mask"):
		# Stale DLL before incremental infra API — full snapshot still works.
		return setup_map(map_data, structures)
	var infra: PackedByteArray = OutpostBuildLib.pack_infra_mask_only(map_data, structures)
	if infra.is_empty():
		return false
	return bool(_planner.call("update_infra_mask", infra))


func rebuild_portals(map_data, structures: Array, player_home: Vector2i) -> void:
	if not ready or _planner == null or map_data == null:
		return
	var sources: Array[Vector2i] = OutpostBuildLib.operational_sources(
		structures, player_home, map_data
	)
	var source_keys := PackedInt32Array()
	for src: Vector2i in sources:
		if src.x >= 0:
			source_keys.append(map_data.cell_index(src.x, src.y))
	var bridge_keys := PackedInt32Array()
	for corridor: Dictionary in map_data.bridge_corridors:
		if (
			int(corridor.get("team", BattleTileControlLib.OWNER_FRIENDLY))
			!= BattleTileControlLib.OWNER_FRIENDLY
		):
			continue
		var gx: int = int(corridor.get("gx", -1))
		var gy: int = int(corridor.get("gy", -1))
		if gx >= 0:
			bridge_keys.append(map_data.cell_index(gx, gy))
	_planner.call("rebuild_portal_graph", source_keys, bridge_keys)


func decode_route_result(res: Dictionary) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if not bool(res.get("found", false)):
		return empty
	var path: PackedInt32Array = res.get("path_packed", PackedInt32Array())
	if path.is_empty():
		return empty
	var source_key: int = int(res.get("source_key", -1))
	var source := Vector2i(-1, -1)
	if source_key >= 0 and _grid_w > 0:
		source = OutpostBuildLib.grid_from_packed_key(source_key, _grid_w)
	return {"path_packed": path, "source": source}


func find_route_sync(
	landing: Vector2i, build_kind: String, allow_astar: bool
) -> Dictionary:
	if not ready or _planner == null or landing.x < 0:
		return {"path_packed": PackedInt32Array(), "source": Vector2i(-1, -1)}
	var kind: int = (
		ROUTE_KIND_CORRIDOR
		if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK
		else ROUTE_KIND_OUTPOST
	)
	var res: Dictionary = _planner.call(
		"find_route_sync", landing.x, landing.y, kind, allow_astar
	)
	return decode_route_result(res)


func start_route_async(
	landing: Vector2i, build_kind: String, allow_astar: bool
) -> int:
	if not ready or _planner == null or landing.x < 0:
		return -1
	var kind: int = (
		ROUTE_KIND_CORRIDOR
		if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK
		else ROUTE_KIND_OUTPOST
	)
	return int(
		_planner.call("start_route_async", landing.x, landing.y, kind, allow_astar)
	)


func cancel_route(request_id: int) -> void:
	if ready and _planner != null and request_id >= 0:
		_planner.call("cancel_route", request_id)


func poll_route() -> Dictionary:
	if not ready or _planner == null:
		return {"ready": false}
	return _planner.call("poll_route")


func _free() -> void:
	ready = false
	_planner = null
	_grid_w = 0
