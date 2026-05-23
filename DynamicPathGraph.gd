class_name DynamicPathGraph
extends RefCounted

var nodes: Dictionary = {}
var edges: Array[Array] = []
var door_connections: Array[Dictionary] = []
var room_name_to_node: Dictionary = {}
var corridor_rects: Array[Rect2] = []

func find_path(from_pos: Vector2, to_pos: Vector2, blocked_nodes: Array[String] = [], from_room: Room = null, to_room: Room = null) -> PackedVector2Array:
	var start_id: String = _nearest_node(from_pos, from_room)
	var end_id: String = _nearest_node(to_pos, to_room)
	if start_id.is_empty() or end_id.is_empty():
		return PackedVector2Array([from_pos, to_pos])
	if start_id == end_id:
		return PackedVector2Array([from_pos, to_pos])
	var ids: Array[String] = _a_star(start_id, end_id, blocked_nodes)
	if ids.is_empty():
		return PackedVector2Array([from_pos, to_pos])
	var points: PackedVector2Array = [from_pos]
	for id in ids:
		points.append(nodes[id])
	points.append(to_pos)
	return _dedupe_points(points)

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

func _nearest_node(pos: Vector2, room_hint: Room = null) -> String:
	if room_hint and room_hint.map_room_id != "" and room_hint.contains_local_point(pos, 0.0):
		if nodes.has(room_hint.map_room_id):
			return room_hint.map_room_id
	if _point_in_corridor(pos):
		var junction_id := _nearest_junction(pos)
		if not junction_id.is_empty():
			return junction_id
	var best_id := ""
	var best_dist: float = INF
	for id in nodes.keys():
		var node_pos: Vector2 = nodes[id]
		if str(id).ends_with("_junction"):
			continue
		if not _point_in_corridor(pos):
			var dist: float = pos.distance_to(node_pos)
			if dist < best_dist:
				best_dist = dist
				best_id = id
	if best_id.is_empty():
		return _nearest_junction(pos)
	return best_id

func _nearest_junction(pos: Vector2) -> String:
	var best_id := ""
	var best_dist: float = INF
	for id in nodes.keys():
		if not str(id).ends_with("_junction"):
			continue
		var dist: float = pos.distance_to(nodes[id])
		if dist < best_dist:
			best_dist = dist
			best_id = id
	return best_id

func _point_in_corridor(pos: Vector2) -> bool:
	for rect in corridor_rects:
		if rect.has_point(pos):
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
