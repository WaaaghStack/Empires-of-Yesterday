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


func invalidate_cache_for_door(_door_node_id: String = "") -> void:
	_path_cache.clear()


func find_path(from_pos: Vector2, to_pos: Vector2, blocked_nodes: Array[String] = [], from_room: Room = null, to_room: Room = null) -> PackedVector2Array:
	if from_room and to_room and from_room.map_room_id != "" and to_room.map_room_id != "":
		var cache_key := "%s|%s|%s" % [from_room.map_room_id, to_room.map_room_id, str(blocked_nodes)]
		if _path_cache.has(cache_key):
			_cache_hits += 1
			var cached: PackedVector2Array = _path_cache[cache_key]
			if not cached.is_empty():
				return cached
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
	if from_room and to_room and from_room.map_room_id != "" and to_room.map_room_id != "":
		var cache_key := "%s|%s|%s" % [from_room.map_room_id, to_room.map_room_id, str(blocked_nodes)]
		_path_cache[cache_key] = result
	return result

func find_room_route(from_room_id: String, to_room_id: String, blocked_nodes: Array[String] = []) -> Array[String]:
	if from_room_id.is_empty() or to_room_id.is_empty() or from_room_id == to_room_id:
		return [from_room_id] if not from_room_id.is_empty() else []
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
		door_list.append({
			"id": "%s_%s" % [room_node, spine_node],
			"position": (nodes[room_node] + nodes[spine_node]) * 0.5,
			"room_node": room_node,
			"spine_node": spine_node,
		})
	return door_list

func room_to_node(room_name: String) -> String:
	return room_name_to_node.get(room_name, "")

func _fallback_path(from_pos: Vector2, to_pos: Vector2, from_room: Room, to_room: Room) -> PackedVector2Array:
	if not from_room or not to_room or from_room == to_room:
		return PackedVector2Array()
	var ids: Array[String] = find_room_route(from_room.map_room_id, to_room.map_room_id)
	if ids.is_empty():
		return PackedVector2Array()
	return _build_corridor_points(from_pos, ids, to_pos)

func _path_inside_same_node(from_pos: Vector2, to_pos: Vector2, from_room: Room, to_room: Room) -> PackedVector2Array:
	if from_pos.distance_to(to_pos) <= 8.0:
		return PackedVector2Array()
	if from_room and to_room and from_room == to_room:
		if from_room.contains_local_point(from_pos, 8.0) and from_room.contains_local_point(to_pos, 8.0):
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
		if cursor.distance_to(node_pos) <= 4.0:
			continue
		points.append(node_pos)
		cursor = node_pos
	if cursor.distance_to(to_pos) > 4.0:
		points.append(to_pos)
	return points

func _nearest_node(pos: Vector2, room_hint: Room = null) -> String:
	if room_hint and room_hint.map_room_id != "" and room_hint.contains_local_point(pos, 12.0):
		if nodes.has(room_hint.map_room_id):
			return room_hint.map_room_id
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
	return []

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

func _dedupe_points(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var out: PackedVector2Array = [points[0]]
	for i in range(1, points.size()):
		if points[i].distance_to(out[out.size() - 1]) > 4.0:
			out.append(points[i])
	return out
