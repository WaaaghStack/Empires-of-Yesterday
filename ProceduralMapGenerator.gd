class_name ProceduralMapGenerator
extends RefCounted

const MissionMapDataScript := preload("res://MissionMapData.gd")

const ROOM_NAME_POOL: Array[String] = [
	"Barracks", "Medical Bay", "Storage", "Engineering", "Armory", "Research Lab",
	"Crew Quarters", "Comms", "Archive", "Reactor", "Hangar", "Observation Deck",
]
const ROOM_SIZE_POOL: Array[Vector2] = [
	Vector2(150, 118), Vector2(168, 128), Vector2(132, 104), Vector2(178, 138), Vector2(142, 112),
]
const ROOM_COLOR_POOL: Array[Color] = [
	Color(0.2, 0.45, 0.85, 0.22), Color(0.35, 0.35, 0.5, 0.18), Color(0.25, 0.3, 0.38, 0.16),
	Color(0.55, 0.25, 0.2, 0.18), Color(0.2, 0.4, 0.22, 0.2), Color(0.35, 0.3, 0.15, 0.2),
	Color(0.15, 0.35, 0.28, 0.24), Color(0.4, 0.22, 0.35, 0.18),
]
const GRID_STEP := Vector2(230.0, 190.0)
const CORRIDOR_WIDTH := 52.0

static func generate(custom_seed: int = -1):
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_value: int = custom_seed if custom_seed >= 0 else rng.randi()
	rng.seed = seed_value
	var data: RefCounted = MissionMapDataScript.new()
	data.map_seed = seed_value
	var room_count: int = rng.randi_range(8, 10)
	var names: Array[String] = _pick_room_names(room_count, rng)
	var layout: Array[Vector2] = _build_layout(room_count, rng)
	var links: Array = _build_mst(room_count, layout, rng)
	links = _add_loop_edges(room_count, layout, links, rng, 2)
	var roles: Array[Dictionary] = _assign_roles(room_count, rng)
	for i in range(room_count):
		var role: Dictionary = roles[i]
		var size: Vector2 = ROOM_SIZE_POOL[rng.randi() % ROOM_SIZE_POOL.size()]
		data.rooms.append({
			"id": "room_%d" % i,
			"name": names[i],
			"pos": layout[i],
			"size": size,
			"color": ROOM_COLOR_POOL[rng.randi() % ROOM_COLOR_POOL.size()],
			"extract": role.get("extract", false),
			"clear": role.get("clear", false),
			"enemies": role.get("enemies", 0),
			"spawn_eligible": role.get("spawn_eligible", false),
		})
	for link in links:
		var a: int = link[0]
		var b: int = link[1]
		for rect in _corridor_between(layout[a], layout[b]):
			data.corridors.append(rect)
	_build_path_graph(data, links)
	data.path_graph.corridor_rects = data.corridors.duplicate()
	data.hull_outline = _build_hull(data)
	data.map_size = _compute_map_size(data)
	return data

static func _pick_room_names(count: int, _rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array[String] = []
	for name in ROOM_NAME_POOL:
		pool.append(name)
	pool.shuffle()
	var names: Array[String] = []
	for i in range(count):
		names.append(pool[i])
	names[names.size() - 1] = "Command Bridge"
	return names

static func _build_layout(count: int, rng: RandomNumberGenerator) -> Array[Vector2]:
	var cols: int = mini(4, count)
	var positions: Array[Vector2] = []
	for i in range(count):
		var col: int = i % cols
		var row: int = int(float(i) / float(cols))
		var offset: Vector2 = Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-18.0, 18.0))
		positions.append(Vector2(col * GRID_STEP.x, row * GRID_STEP.y) + offset)
	return _center_layout(positions)

static func _center_layout(positions: Array[Vector2]) -> Array[Vector2]:
	if positions.is_empty():
		return positions
	var min_pos: Vector2 = positions[0]
	var max_pos: Vector2 = positions[0]
	for pos in positions:
		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)
	var center: Vector2 = (min_pos + max_pos) * 0.5
	var centered: Array[Vector2] = []
	for pos in positions:
		centered.append(pos - center)
	return centered

static func _build_mst(count: int, layout: Array[Vector2], _rng: RandomNumberGenerator) -> Array:
	var edges: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			edges.append([i, j, layout[i].distance_to(layout[j])])
	edges.sort_custom(func(a, b): return a[2] < b[2])
	var parent: Array[int] = []
	for i in range(count):
		parent.append(i)
	var result: Array = []
	for edge in edges:
		var a: int = edge[0]
		var b: int = edge[1]
		var root_a: int = _find_parent(parent, a)
		var root_b: int = _find_parent(parent, b)
		if root_a != root_b:
			parent[root_a] = root_b
			result.append([a, b])
	return result

static func _add_loop_edges(count: int, layout: Array[Vector2], links: Array, _rng: RandomNumberGenerator, extra: int) -> Array:
	var existing: Dictionary = {}
	for link in links:
		existing["%d_%d" % [mini(link[0], link[1]), maxi(link[0], link[1])]] = true
	var candidates: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			var key: String = "%d_%d" % [i, j]
			if key in existing:
				continue
			candidates.append([i, j, layout[i].distance_to(layout[j])])
	candidates.sort_custom(func(a, b): return a[2] < b[2])
	var out: Array = links.duplicate()
	for i in range(mini(extra, candidates.size())):
		out.append([candidates[i][0], candidates[i][1]])
	return out

static func _find_parent(parent: Array[int], node: int) -> int:
	if parent[node] != node:
		parent[node] = _find_parent(parent, parent[node])
	return parent[node]

static func _assign_roles(count: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var roles: Array[Dictionary] = []
	for _i in range(count):
		roles.append({"extract": false, "clear": false, "enemies": 0, "spawn_eligible": true})
	roles[count - 1]["extract"] = true
	roles[count - 1]["spawn_eligible"] = false
	var hostile_indices: Array[int] = []
	for i in range(count - 1):
		hostile_indices.append(i)
	hostile_indices.shuffle()
	var hostile_count: int = mini(3, hostile_indices.size())
	for i in range(hostile_count):
		var idx: int = hostile_indices[i]
		roles[idx]["clear"] = true
		roles[idx]["spawn_eligible"] = false
		roles[idx]["enemies"] = rng.randi_range(1, 2)
	return roles

static func _corridor_between(a: Vector2, b: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var elbow: Vector2 = Vector2(b.x, a.y)
	if absf(a.x - b.x) <= 8.0 and absf(a.y - b.y) <= 8.0:
		rects.append(_center_rect((a + b) * 0.5, Vector2(maxf(CORRIDOR_WIDTH, 12.0), maxf(CORRIDOR_WIDTH, 12.0))))
		return rects
	if absf(a.x - b.x) > 8.0:
		rects.append(_center_rect(elbow, Vector2(absf(b.x - a.x) + CORRIDOR_WIDTH, CORRIDOR_WIDTH)))
	if absf(a.y - b.y) > 8.0:
		rects.append(_center_rect(Vector2(b.x, elbow.y), Vector2(CORRIDOR_WIDTH, absf(b.y - a.y) + CORRIDOR_WIDTH)))
	if rects.is_empty():
		rects.append(_center_rect((a + b) * 0.5, Vector2(CORRIDOR_WIDTH + 12.0, CORRIDOR_WIDTH + 12.0)))
	return rects

static func _center_rect(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)

static func _build_path_graph(data: RefCounted, links: Array) -> void:
	var graph = data.path_graph
	for room_data: Dictionary in data.rooms:
		var room_node_id: String = room_data["id"]
		graph.nodes[room_node_id] = room_data["pos"]
		graph.room_name_to_node[room_data["name"]] = room_node_id
	for link in links:
		var a_id: String = data.rooms[link[0]]["id"]
		var b_id: String = data.rooms[link[1]]["id"]
		var junction_id: String = "%s_%s_junction" % [a_id, b_id]
		var pos_a: Vector2 = data.rooms[link[0]]["pos"]
		var pos_b: Vector2 = data.rooms[link[1]]["pos"]
		var junction_pos: Vector2 = Vector2(pos_b.x, pos_a.y)
		graph.nodes[junction_id] = junction_pos
		graph.edges.append([a_id, junction_id])
		graph.edges.append([junction_id, b_id])
		graph.door_connections.append({"room_node": a_id, "spine_node": junction_id})
		graph.door_connections.append({"room_node": b_id, "spine_node": junction_id})

static func _build_hull(data: RefCounted) -> PackedVector2Array:
	var min_pos: Vector2 = Vector2(INF, INF)
	var max_pos: Vector2 = Vector2(-INF, -INF)
	for room_data: Dictionary in data.rooms:
		var half: Vector2 = room_data["size"] * 0.5
		min_pos = min_pos.min(room_data["pos"] - half)
		max_pos = max_pos.max(room_data["pos"] + half)
	for rect in data.corridors:
		min_pos = min_pos.min(rect.position)
		max_pos = max_pos.max(rect.end)
	var pad: Vector2 = Vector2(80.0, 70.0)
	min_pos -= pad
	max_pos += pad
	return PackedVector2Array([
		Vector2(min_pos.x, min_pos.y),
		Vector2(max_pos.x, min_pos.y),
		Vector2(max_pos.x, max_pos.y),
		Vector2(min_pos.x, max_pos.y),
	])

static func _compute_map_size(data: RefCounted) -> Vector2:
	var outline: PackedVector2Array = data.hull_outline
	if outline.is_empty():
		return Vector2(1024, 640)
	var min_pos: Vector2 = outline[0]
	var max_pos: Vector2 = outline[2]
	return max_pos - min_pos
