extends RefCounted

const SIGHT_RANGE := 420.0

static var _room_cache: Dictionary = {}


static func begin_frame_cache() -> void:
	_room_cache.clear()


static func has_line_of_sight(from_pos: Vector2, to_pos: Vector2, rooms: Array[Room], doors: Array) -> bool:
	if from_pos.distance_to(to_pos) > SIGHT_RANGE:
		return false
	if _segment_blocked_by_doors(from_pos, to_pos, doors):
		return false
	var room_a = _room_containing(from_pos, rooms)
	var room_b = _room_containing(to_pos, rooms)
	if room_a and room_b:
		return room_a == room_b
	if room_a and not room_b:
		return _can_see_out_of_room(from_pos, to_pos, room_a, rooms, doors)
	if room_b and not room_a:
		return _can_see_out_of_room(to_pos, from_pos, room_b, rooms, doors)
	return not _segment_passes_through_room(from_pos, to_pos, rooms, null)

static func can_reveal_room(from_pos: Vector2, room: Room, rooms: Array[Room], doors: Array) -> bool:
	if room.contains_local_point(from_pos, 0.0):
		return true
	var anchor := _nearest_open_door_anchor(from_pos, room, doors)
	if anchor == Vector2.ZERO:
		return false
	if from_pos.distance_to(anchor) > SIGHT_RANGE:
		return false
	if _segment_blocked_by_doors(from_pos, anchor, doors):
		return false
	return not _segment_passes_through_room(from_pos, anchor, rooms, room)

static func _nearest_open_door_anchor(from_pos: Vector2, room: Room, doors: Array) -> Vector2:
	var best_anchor := Vector2.ZERO
	var best_dist: float = INF
	for node in doors:
		if not node.has_method("blocks_sight") or not node.has_method("room_node_id"):
			continue
		if node.room_node_id != room.map_room_id:
			continue
		if node.blocks_sight():
			continue
		var door_pos: Vector2 = (node as Node2D).position
		var dist: float = from_pos.distance_to(door_pos)
		if dist < best_dist:
			best_dist = dist
			best_anchor = door_pos
	return best_anchor

static func _can_see_out_of_room(from_pos: Vector2, to_pos: Vector2, from_room: Room, rooms: Array[Room], doors: Array) -> bool:
	if _room_containing(to_pos, rooms) != null:
		return false
	if not _has_open_door_to_room(from_pos, from_room, doors):
		return false
	return not _segment_passes_through_room(from_pos, to_pos, rooms, from_room)

static func _has_open_door_to_room(from_pos: Vector2, room: Room, doors: Array) -> bool:
	if room.map_room_id.is_empty():
		return false
	for node in doors:
		if not node.has_method("blocks_sight") or not node.has_method("room_node_id"):
			continue
		if node.room_node_id != room.map_room_id:
			continue
		if node.blocks_sight():
			continue
		var door_pos: Vector2 = (node as Node2D).position
		if from_pos.distance_to(door_pos) <= 96.0:
			return true
	return false

static func _room_containing(pos: Vector2, rooms: Array[Room]) -> Room:
	var key := Vector2i(roundi(pos.x / 32.0), roundi(pos.y / 32.0))
	if _room_cache.has(key):
		return _room_cache[key]
	for room in rooms:
		if room.contains_local_point(pos, 0.0):
			_room_cache[key] = room
			return room
	_room_cache[key] = null
	return null

static func _segment_blocked_by_doors(a: Vector2, b: Vector2, doors: Array) -> bool:
	for node in doors:
		if not node.has_method("blocks_sight") or not node.blocks_sight():
			continue
		var door_pos: Vector2 = (node as Node2D).position
		if _distance_point_to_segment(door_pos, a, b) <= 18.0:
			return true
	return false

static func _segment_passes_through_room(a: Vector2, b: Vector2, rooms: Array[Room], ignore_room: Room) -> bool:
	var room_at_a := _room_containing(a, rooms)
	var room_at_b := _room_containing(b, rooms)
	for room in rooms:
		if room == ignore_room or room == room_at_a or room == room_at_b:
			continue
		var rect: Rect2 = _room_rect(room)
		if _segment_intersects_rect(a, b, rect):
			return true
	return false

static func _room_rect(room: Room) -> Rect2:
	var half: Vector2 = room.room_size * 0.5
	return Rect2(room.position - half, room.room_size)

static func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var expanded := rect.grow(2.0)
	if not expanded.has_point(a) and not expanded.has_point(b):
		if a.x < expanded.position.x and b.x < expanded.position.x:
			return false
		if a.x > expanded.end.x and b.x > expanded.end.x:
			return false
		if a.y < expanded.position.y and b.y < expanded.position.y:
			return false
		if a.y > expanded.end.y and b.y > expanded.end.y:
			return false
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var edges: Array = [
		[corners[0], corners[1]], [corners[1], corners[2]],
		[corners[2], corners[3]], [corners[3], corners[0]],
	]
	for edge in edges:
		if _segments_intersect(a, b, edge[0], edge[1]):
			return true
	return expanded.has_point(a) or expanded.has_point(b)

static func _segments_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1: float = _cross(p3 - p1, p2 - p1)
	var d2: float = _cross(p4 - p1, p2 - p1)
	var d3: float = _cross(p1 - p3, p4 - p3)
	var d4: float = _cross(p2 - p3, p4 - p3)
	return ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0))

static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x

static func _distance_point_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq < 0.001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	var projection: Vector2 = a + ab * t
	return point.distance_to(projection)
