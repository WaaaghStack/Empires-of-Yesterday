class_name DynamicPathGraph
extends RefCounted

var nodes: Dictionary = {}
var edges: Array[Array] = []
var door_connections: Array[Dictionary] = []
var room_name_to_node: Dictionary = {}
var corridor_rects: Array[Rect2] = []
var corridor_segments: Array[Dictionary] = []
var _path_cache: Dictionary = {}
var _cache_hits: int = 0
var _finds_this_frame: int = 0
var _find_budget_frame: int = -1
const MAX_FINDS_PER_FRAME_DEFAULT := 4
const DOOR_ENTRY_INSET := 14.0
var _max_finds_per_frame: int = MAX_FINDS_PER_FRAME_DEFAULT


func set_max_finds_per_frame(max_finds: int) -> void:
	_max_finds_per_frame = maxi(1, max_finds)


func invalidate_cache_for_door(_door_node_id: String = "") -> void:
	_path_cache.clear()


func find_path(
	from_pos: Vector2,
	to_pos: Vector2,
	blocked_nodes: Array[String] = [],
	from_room: Variant = null,
	to_room: Variant = null,
) -> PackedVector2Array:
	var from_id: String = _room_map_id(from_room)
	var to_id: String = _room_map_id(to_room)
	if from_room and to_room and from_id != "" and to_id != "":
		var cache_key := "%s|%s|%s" % [from_id, to_id, str(blocked_nodes)]
		if _path_cache.has(cache_key):
			_cache_hits += 1
			var cached: PackedVector2Array = _path_cache[cache_key]
			if not cached.is_empty():
				return cached
	var frame := Engine.get_process_frames()
	if _find_budget_frame != frame:
		_find_budget_frame = frame
		_finds_this_frame = 0
	if _finds_this_frame >= _max_finds_per_frame:
		return _fallback_path(from_pos, to_pos, from_room, to_room)
	_finds_this_frame += 1
	var start_id: String = _nearest_node(from_pos, from_room)
	var end_id: String = _nearest_node(to_pos, to_room)
	if start_id.is_empty() or end_id.is_empty():
		return _fallback_path(from_pos, to_pos, from_room, to_room)
	if start_id == end_id:
		var inside := _path_inside_same_node(from_pos, to_pos, from_room, to_room)
		if not inside.is_empty():
			return inside
		return _fallback_path(from_pos, to_pos, from_room, to_room)
	var ids: Array[String] = _a_star(start_id, end_id, blocked_nodes)
	if ids.is_empty() and not blocked_nodes.is_empty():
		var retry_blocked: Array[String] = []
		ids = _a_star(start_id, end_id, retry_blocked)
	if ids.is_empty():
		return _fallback_path(from_pos, to_pos, from_room, to_room)
	var result := _build_corridor_points(from_pos, ids, to_pos)
	if from_room and to_room and from_id != "" and to_id != "":
		var cache_key := "%s|%s|%s" % [from_id, to_id, str(blocked_nodes)]
		_path_cache[cache_key] = result
	return result

func find_room_route(from_room_id: String, to_room_id: String, blocked_nodes: Array[String] = []) -> Array[String]:
	if from_room_id.is_empty() or to_room_id.is_empty():
		return []
	if from_room_id == to_room_id:
		var same_room: Array[String] = [from_room_id]
		return same_room
	var ids: Array[String] = _a_star(from_room_id, to_room_id, blocked_nodes)
	if ids.is_empty() and not blocked_nodes.is_empty():
		var retry_blocked: Array[String] = []
		ids = _a_star(from_room_id, to_room_id, retry_blocked)
	return ids

func is_in_corridor(pos: Vector2) -> bool:
	return _point_in_corridor(pos)

func get_door_positions() -> Array[Dictionary]:
	var door_list: Array[Dictionary] = []
	for connection in door_connections:
		var room_node: String = connection.get("room_node", "")
		var spine_node: String = connection.get("spine_node", "")
		if room_node.is_empty() or spine_node.is_empty():
			continue
		if not nodes.has(room_node) or not nodes.has(spine_node):
			continue
		var spine_pos: Vector2 = nodes[spine_node]
		var outward: Vector2 = _corridor_dir_from_spine(spine_node)
		if outward.length_squared() < 0.01:
			outward = (spine_pos - nodes[room_node]).normalized()
		door_list.append({
			"id": "%s_%s" % [room_node, spine_node],
			"position": spine_pos,
			"rotation": outward.angle(),
			"room_node": room_node,
			"spine_node": spine_node,
		})
	return door_list


func _corridor_dir_from_spine(spine_id: String) -> Vector2:
	for segment in corridor_segments:
		var door_a: String = segment.get("door_a", "")
		var door_b: String = segment.get("door_b", "")
		if door_a == spine_id and nodes.has(door_b):
			return nodes[door_b] - nodes[door_a]
		if door_b == spine_id and nodes.has(door_a):
			return nodes[door_a] - nodes[door_b]
	return Vector2.ZERO

func room_to_node(room_name: String) -> String:
	return room_name_to_node.get(room_name, "")

func _fallback_path(from_pos: Vector2, to_pos: Vector2, from_room: Variant, to_room: Variant) -> PackedVector2Array:
	if not from_room or not to_room or from_room == to_room:
		return PackedVector2Array()
	var ids: Array[String] = find_room_route(_room_map_id(from_room), _room_map_id(to_room))
	if ids.is_empty():
		return PackedVector2Array()
	return _build_corridor_points(from_pos, ids, to_pos)

func _path_inside_same_node(
	from_pos: Vector2, to_pos: Vector2, from_room: Variant, to_room: Variant
) -> PackedVector2Array:
	if from_pos.distance_to(to_pos) <= 8.0:
		return PackedVector2Array()
	if from_room and to_room and from_room == to_room:
		if _room_contains_point(from_room, from_pos, 8.0) and _room_contains_point(from_room, to_pos, 8.0):
			return PackedVector2Array([to_pos])
	if _point_in_corridor(from_pos) and _point_in_corridor(to_pos):
		return PackedVector2Array([to_pos])
	return PackedVector2Array()

func _build_corridor_points(from_pos: Vector2, ids: Array[String], to_pos: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var cursor := from_pos
	for i in range(ids.size()):
		var id: String = ids[i]
		var is_door: bool = id.contains("_door_")
		var is_final_room: bool = i == ids.size() - 1 and not is_door
		if not is_door and not is_final_room:
			continue
		var node_pos: Vector2 = nodes[id]
		if is_door:
			var toward_pos: Vector2 = to_pos
			for j in range(i + 1, ids.size()):
				var next_id: String = ids[j]
				if nodes.has(next_id):
					toward_pos = nodes[next_id]
					break
			var inset_dir: Vector2 = toward_pos - node_pos
			if inset_dir.length_squared() > 1.0:
				node_pos += inset_dir.normalized() * DOOR_ENTRY_INSET
		if cursor.distance_to(node_pos) <= 4.0:
			continue
		points.append(node_pos)
		cursor = node_pos
	if cursor.distance_to(to_pos) > 4.0:
		points.append(to_pos)
	return points

func _nearest_node(pos: Vector2, room_hint: Variant = null) -> String:
	var hint_id: String = _room_map_id(room_hint)
	if room_hint and hint_id != "" and _room_contains_point(room_hint, pos, 12.0):
		if nodes.has(hint_id):
			return hint_id
	var corridor_node := _nearest_corridor_node(pos)
	if not corridor_node.is_empty():
		return corridor_node
	var best_id := ""
	var best_dist: float = INF
	for id in nodes.keys():
		if str(id).contains("_door_"):
			continue
		var node_pos: Vector2 = nodes[id]
		var dist: float = pos.distance_to(node_pos)
		if dist < best_dist:
			best_dist = dist
			best_id = id
	return best_id

func _nearest_corridor_node(pos: Vector2) -> String:
	for segment in corridor_segments:
		var rect: Rect2 = segment.get("rect", Rect2())
		if rect.size == Vector2.ZERO or not rect.has_point(pos):
			continue
		var door_a: String = segment.get("door_a", "")
		var door_b: String = segment.get("door_b", "")
		if not nodes.has(door_a) or not nodes.has(door_b):
			continue
		if pos.distance_to(nodes[door_a]) <= pos.distance_to(nodes[door_b]):
			return door_a
		return door_b
	return ""

func _point_in_corridor(pos: Vector2) -> bool:
	for rect in corridor_rects:
		if rect.has_point(pos):
			return true
	for segment in corridor_segments:
		var rect: Rect2 = segment.get("rect", Rect2())
		if rect.size != Vector2.ZERO and rect.has_point(pos):
			return true
	return false

func _a_star(start_id: String, end_id: String, blocked: Array[String]) -> Array[String]:
	var open: Array[String] = [start_id]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_id: 0.0}
	while not open.is_empty():
		open.sort_custom(func(a, b): return g_score.get(a, INF) < g_score.get(b, INF))
		var current: String = open[0]
		open.remove_at(0)
		if current == end_id:
			return _reconstruct(came_from, current)
		for neighbor in _neighbors(current):
			if neighbor in blocked:
				continue
			var tentative: float = g_score.get(current, INF) + nodes[current].distance_to(nodes[neighbor])
			if tentative < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative
				if neighbor not in open:
					open.append(neighbor)
	var no_path: Array[String] = []
	return no_path

func _neighbors(node_id: String) -> Array[String]:
	var result: Array[String] = []
	for edge in edges:
		if edge[0] == node_id:
			result.append(edge[1])
		elif edge[1] == node_id:
			result.append(edge[0])
	return result

func _reconstruct(came_from: Dictionary, current: String) -> Array[String]:
	var path: Array[String] = [current]
	while current in came_from:
		current = came_from[current]
		path.insert(0, current)
	return path

func _room_map_id(room: Variant) -> String:
	if room == null:
		return ""
	if room is Dictionary:
		return str(room.get("map_room_id", ""))
	if room is Object and "map_room_id" in room:
		return str(room.map_room_id)
	return ""


func _room_contains_point(room: Variant, pos: Vector2, margin: float) -> bool:
	if room == null:
		return false
	if room is Object and room.has_method("contains_local_point"):
		return bool(room.call("contains_local_point", pos, margin))
	return false


func _dedupe_points(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var out: PackedVector2Array = [points[0]]
	for i in range(1, points.size()):
		if points[i].distance_to(out[out.size() - 1]) > 4.0:
			out.append(points[i])
	return out
