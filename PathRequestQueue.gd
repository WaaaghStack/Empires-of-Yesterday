class_name PathRequestQueue
extends RefCounted

const DEFAULT_MAX_FINDS_PER_FRAME := 16

var _max_finds: int = DEFAULT_MAX_FINDS_PER_FRAME
var _finds_this_frame: int = 0
var _budget_frame: int = -1
var _squad_routes: Dictionary = {}


func reset() -> void:
	_finds_this_frame = 0
	_budget_frame = -1
	_squad_routes.clear()


func set_max_finds_per_frame(max_finds: int) -> void:
	_max_finds = maxi(1, max_finds)


func get_squad_room_route(
	graph: DynamicPathGraph,
	squad_key: String,
	from_room_id: String,
	to_room_id: String,
	blocked: Array[String] = [],
) -> Array[String]:
	var cache_key := "%s|%s|%s" % [squad_key, from_room_id, to_room_id]
	if _squad_routes.has(cache_key):
		return _squad_routes[cache_key]
	if not _consume_find_budget():
		return []
	var route: Array[String] = graph.find_room_route(from_room_id, to_room_id, blocked)
	_squad_routes[cache_key] = route
	return route


func request_corridor_path(
	graph: DynamicPathGraph,
	from_pos: Vector2,
	to_pos: Vector2,
	from_room: Room,
	to_room: Room,
	blocked: Array[String] = [],
) -> PackedVector2Array:
	if not _consume_find_budget():
		return PackedVector2Array()
	return graph.find_path(from_pos, to_pos, blocked, from_room, to_room)


func _consume_find_budget() -> bool:
	var frame := Engine.get_process_frames()
	if _budget_frame != frame:
		_budget_frame = frame
		_finds_this_frame = 0
	if _finds_this_frame >= _max_finds:
		return false
	_finds_this_frame += 1
	return true
