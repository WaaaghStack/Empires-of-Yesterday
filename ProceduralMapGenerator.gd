class_name ProceduralMapGenerator
extends RefCounted

const MissionMapDataScript := preload("res://MissionMapData.gd")
const PlanetMapDataScript := preload("res://PlanetMapData.gd")
const MapVisualsLib := preload("res://MapVisuals.gd")

const ROOM_NAME_POOL: Array[String] = [
	"Barracks", "Medical Bay", "Storage", "Engineering", "Armory", "Research Lab",
	"Crew Quarters", "Comms", "Archive", "Reactor", "Hangar", "Observation Deck",
]
const ROOM_SIZE_POOL: Array[Vector2] = [
	Vector2(150, 118), Vector2(168, 128), Vector2(132, 104), Vector2(178, 138), Vector2(142, 112),
]
const ROOM_SHAPE_WIDE_BAY := Vector2(210, 96)
const ROOM_SHAPE_CHOKE := Vector2(88, 168)
const ROOM_SHAPE_LOOT := Vector2(118, 96)
const SHAPE_WEIGHTS: Array[Dictionary] = [
	{"id": "standard", "weight": 50},
	{"id": "wide_bay", "weight": 25},
	{"id": "choke", "weight": 25},
]
const ROOM_COLOR_POOL: Array[Color] = [
	Color(0.2, 0.45, 0.85, 0.22), Color(0.35, 0.35, 0.5, 0.18), Color(0.25, 0.3, 0.38, 0.16),
	Color(0.55, 0.25, 0.2, 0.18), Color(0.2, 0.4, 0.22, 0.2), Color(0.35, 0.3, 0.15, 0.2),
	Color(0.15, 0.35, 0.28, 0.24), Color(0.4, 0.22, 0.35, 0.18),
]
const CORRIDOR_LENGTH := 56.0
const CORRIDOR_WIDTH := 48.0
const PIECE_MARGIN := 8.0
const PLANET_SPINE_MAX_WORLD_SPAN := 3600.0

static func generate(custom_seed: int = -1, config: Dictionary = {}):
	var op_index: int = int(config.get("op_index", 1))
	# Handcrafted 5-room finale is legacy op-run only; campaign nodes always use tier-based maps.
	if op_index >= 4 and config.get("handcrafted_finale", true) and str(config.get("node_type", "")).is_empty():
		return _generate_finale_map(custom_seed, config)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_value: int = custom_seed if custom_seed >= 0 else rng.randi()
	rng.seed = seed_value
	var objective_template: String = str(config.get("objective_template", "standard"))
	var map_tier: String = str(config.get("map_tier", "medium"))
	var data: RefCounted = MissionMapDataScript.new()
	data.map_seed = seed_value
	data.objective_template = objective_template
	data.op_index = op_index
	data.map_tier = map_tier
	data.map_scale = _map_scale_for_tier(map_tier)
	data.facility_theme = MapVisualsLib.pick_facility_theme(rng)
	data.enemy_stat_scale = _enemy_scale_for_op(op_index)
	data.evac_reveal_after_searches = 0
	data.bonus_credits_room_id = ""
	if objective_template == "silent_extract":
		data.evac_reveal_after_searches = 2
	elif objective_template == "scavenge":
		data.bonus_credits_room_id = "scavenge_bonus"
	elif objective_template == "hold_purge":
		data.hold_duration_seconds = float(rng.randi_range(30, 45))
	elif objective_template == "black_site":
		data.evac_reveal_after_searches = 0
	elif objective_template == "vip_recovery":
		data.evac_reveal_after_searches = 0
	elif objective_template == "hive_purge":
		data.evac_reveal_after_searches = 0
	var room_count: int = _room_count_for_tier(map_tier, rng)
	var add_loot_branch := rng.randf() < 0.42 and map_tier != "large"
	if add_loot_branch:
		room_count += 1
	var names: Array[String] = _pick_room_names(room_count, rng)
	var roles: Array[Dictionary] = _assign_roles(room_count, rng, op_index, objective_template, add_loot_branch, map_tier)
	if config.get("campaign_boss", false) and objective_template == "hive_purge":
		_apply_campaign_boss_roles(roles, room_count, rng, config)
	var layout := _build_lego_layout(room_count, rng, add_loot_branch, data.map_scale)
	_center_layout(layout)
	var theme_palette: Dictionary = MapVisualsLib.get_facility_palette(data.facility_theme)
	var theme_room_colors: Array = theme_palette.get("room_colors", ROOM_COLOR_POOL)
	for i in range(room_count):
		var piece: Dictionary = layout.rooms[i]
		var role: Dictionary = roles[i]
		data.rooms.append({
			"id": role.get("id_override", "room_%d" % i),
			"name": names[i],
			"pos": piece.pos,
			"size": piece.size,
			"shape": piece.get("shape", "standard"),
			"color": theme_room_colors[i % theme_room_colors.size()],
			"extract": role.get("extract", false),
			"clear": role.get("clear", false),
			"enemies": role.get("enemies", 0),
			"spawn_eligible": role.get("spawn_eligible", false),
			"scavenge_bonus": role.get("scavenge_bonus", false),
			"elite_slot": role.get("elite_slot", false),
			"hold_room": role.get("hold_room", false),
			"intel_terminal": role.get("intel_terminal", false),
			"vip_room": role.get("vip_room", false),
			"loot_branch": role.get("loot_branch", false),
			"hive_room": role.get("hive_room", false),
			"overmind_room": role.get("overmind_room", false),
			"evolution_node": role.get("evolution_node", false),
			"sector": data.sector_tags.get(role.get("id_override", "room_%d" % i), "central"),
			"stat_scale": data.enemy_stat_scale,
		})
		if role.get("hive_room", false) and not role.get("overmind_room", false):
			if not data.hive_room_ids.has(role.get("id_override", "room_%d" % i)):
				data.hive_room_ids.append(role.get("id_override", "room_%d" % i))
		if role.get("overmind_room", false):
			data.overmind_room_id = role.get("id_override", "room_%d" % i)
		if role.get("hold_room", false):
			data.hold_room_id = role.get("id_override", "room_%d" % i)
		if role.get("intel_terminal", false):
			data.intel_terminal_room_ids.append(role.get("id_override", "room_%d" % i))
		if role.get("vip_room", false):
			data.vip_room_id = role.get("id_override", "room_%d" % i)
		if role.get("loot_branch", false):
			data.loot_branch_room_id = role.get("id_override", "room_%d" % i)
		if role.get("hive_room", false):
			data.hive_room_ids.append(role.get("id_override", "room_%d" % i))
		data.sector_tags[role.get("id_override", "room_%d" % i)] = _sector_tag_for_pos(piece.pos)
	_finalize_links(data, layout.link_specs)
	data.hull_outline = _build_hull(data)
	data.map_size = _compute_map_size(data)
	return data


static func generate_planet(custom_seed: int = -1, config: Dictionary = {}):
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_value: int = custom_seed if custom_seed >= 0 else rng.randi()
	rng.seed = seed_value
	var op_index: int = int(config.get("op_index", 3))
	var data: RefCounted = PlanetMapDataScript.new()
	data.map_seed = seed_value
	data.objective_template = "planet_reclamation"
	data.op_index = op_index
	data.map_tier = "planet"
	data.map_scale = _map_scale_for_tier("planet")
	data.facility_theme = MapVisualsLib.pick_facility_theme(rng)
	data.enemy_stat_scale = _enemy_scale_for_op(op_index)
	data.evac_reveal_after_searches = 0
	var room_min: int = int(config.get("planet_room_min", 12))
	var room_max: int = int(config.get("planet_room_max", 16))
	var room_count: int = rng.randi_range(room_min, room_max)
	var names: Array[String] = _pick_room_names(room_count, rng)
	var roles: Array[Dictionary] = _assign_planet_roles(room_count, rng, op_index, config)
	var layout := _build_spine_layout(room_count, rng, data.map_scale)
	var shrink_attempts := 0
	while _layout_world_span(layout) > PLANET_SPINE_MAX_WORLD_SPAN and shrink_attempts < 4:
		shrink_attempts += 1
		data.map_scale *= 0.92
		layout = _build_spine_layout(room_count, rng, data.map_scale)
	_center_layout(layout)
	var theme_palette: Dictionary = MapVisualsLib.get_facility_palette(data.facility_theme)
	var theme_room_colors: Array = theme_palette.get("room_colors", ROOM_COLOR_POOL)
	for i in range(room_count):
		var piece: Dictionary = layout.rooms[i]
		var role: Dictionary = roles[i]
		var room_id: String = str(role.get("id_override", "room_%d" % i))
		data.rooms.append({
			"id": room_id,
			"name": names[i],
			"pos": piece.pos,
			"size": piece.size,
			"shape": piece.get("shape", "standard"),
			"color": theme_room_colors[i % theme_room_colors.size()],
			"extract": role.get("extract", false),
			"clear": role.get("clear", false),
			"enemies": role.get("enemies", 0),
			"spawn_eligible": role.get("spawn_eligible", false),
			"scavenge_bonus": false,
			"elite_slot": role.get("elite_slot", false),
			"hold_room": false,
			"intel_terminal": false,
			"vip_room": false,
			"loot_branch": false,
			"hive_room": role.get("hive_room", false),
			"overmind_room": role.get("overmind_room", false),
			"evolution_node": role.get("evolution_node", false),
			"sector": data.sector_tags.get(room_id, "central"),
			"stat_scale": data.enemy_stat_scale,
		})
		if role.get("hive_room", false) and not role.get("overmind_room", false):
			data.hive_room_ids.append(room_id)
			data.regular_hive_room_ids.append(room_id)
		if role.get("overmind_room", false):
			data.overmind_room_id = room_id
			data.hive_room_ids.append(room_id)
		if role.get("evolution_node", false):
			data.evolution_node_room_ids.append(room_id)
		data.sector_tags[room_id] = _sector_tag_for_pos(piece.pos)
	_finalize_links(data, layout.link_specs)
	data.hull_outline = _build_hull(data)
	data.map_size = _compute_map_size(data)
	data.planet_hive_target = data.regular_hive_room_ids.size()
	if _mutators_include(config, "reinforced"):
		data.enemy_stat_scale *= 1.12
		for room_data: Dictionary in data.rooms:
			if int(room_data.get("enemies", 0)) > 0:
				room_data["enemies"] = maxi(1, int(room_data["enemies"]) - 1)
	if MapVisualsLib.normalize_theme(data.facility_theme) == "colony":
		data.enemy_stat_scale *= 0.96
	for sector in ["north", "south", "east", "west", "central"]:
		var count := 0
		for room_data: Dictionary in data.rooms:
			if str(room_data.get("sector", "central")) == sector:
				count += 1
		if count > 0:
			data.sector_room_counts[sector] = count
	return data


static func _generate_finale_map(custom_seed: int, config: Dictionary) -> RefCounted:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_value: int = custom_seed if custom_seed >= 0 else rng.randi()
	rng.seed = seed_value
	var objective_template: String = str(config.get("objective_template", "standard"))
	var data: RefCounted = MissionMapDataScript.new()
	data.map_seed = seed_value
	data.objective_template = objective_template
	data.op_index = 4
	data.facility_theme = "command"
	data.is_handcrafted = true
	data.enemy_stat_scale = _enemy_scale_for_op(4)
	data.evac_reveal_after_searches = 0
	var palette: Dictionary = MapVisualsLib.get_facility_palette("command")
	var room_colors: Array = palette.get("room_colors", ROOM_COLOR_POOL)
	var room_specs: Array[Dictionary] = [
		{"id": "finale_deploy", "name": "Deploy Bay", "pos": Vector2(-320, 0), "size": Vector2(150, 118), "shape": "standard", "spawn": true},
		{"id": "finale_ops", "name": "Ops Center", "pos": Vector2(-80, 0), "size": Vector2(168, 128), "shape": "wide_bay", "clear": true, "enemies": 2},
		{"id": "finale_vault", "name": "Secure Vault", "pos": Vector2(180, 0), "size": Vector2(142, 112), "shape": "choke", "clear": true, "enemies": 2, "elite": true},
		{"id": "finale_core", "name": "Server Core", "pos": Vector2(180, -190), "size": Vector2(132, 104), "shape": "standard", "clear": true, "enemies": 2},
		{"id": "finale_bridge", "name": "Command Bridge", "pos": Vector2(420, 0), "size": Vector2(178, 138), "shape": "wide_bay", "extract": true},
	]
	var link_specs: Array[Dictionary] = [
		{"a": 0, "b": 1, "parent_dir": "E"},
		{"a": 1, "b": 2, "parent_dir": "E"},
		{"a": 2, "b": 4, "parent_dir": "E"},
		{"a": 2, "b": 3, "parent_dir": "N"},
	]
	for i in range(room_specs.size()):
		var spec: Dictionary = room_specs[i]
		data.rooms.append({
			"id": spec.get("id", "room_%d" % i),
			"name": spec.get("name", "Sector %d" % i),
			"pos": spec.get("pos", Vector2.ZERO),
			"size": spec.get("size", Vector2(150, 118)),
			"shape": spec.get("shape", "standard"),
			"color": room_colors[i % room_colors.size()],
			"extract": spec.get("extract", false),
			"clear": spec.get("clear", false),
			"enemies": spec.get("enemies", 0),
			"spawn_eligible": spec.get("spawn", false),
			"scavenge_bonus": false,
			"elite_slot": spec.get("elite", false),
			"hold_room": false,
			"intel_terminal": objective_template == "black_site" and i == 3,
			"vip_room": objective_template == "vip_recovery" and i == 1,
			"loot_branch": false,
			"stat_scale": data.enemy_stat_scale,
		})
		if spec.get("hold_room", false):
			data.hold_room_id = str(spec.get("id", ""))
		if objective_template == "black_site" and i == 3:
			data.intel_terminal_room_ids.append(str(spec.get("id", "")))
		if objective_template == "vip_recovery" and i == 1:
			data.vip_room_id = str(spec.get("id", ""))
	if objective_template == "hold_purge":
		data.hold_duration_seconds = 35.0
		data.hold_room_id = "finale_vault"
		for room_data: Dictionary in data.rooms:
			if room_data["id"] == "finale_vault":
				room_data["hold_room"] = true
				room_data["clear"] = true
	_finalize_links(data, link_specs)
	data.hull_outline = _build_hull(data)
	data.map_size = _compute_map_size(data)
	return data

static func _enemy_scale_for_op(op_index: int) -> float:
	match clampi(op_index, 1, 4):
		1:
			return 1.0
		2:
			return 1.15
		3:
			return 1.3
		_:
			return 1.5

static func _room_count_for_tier(map_tier: String, rng: RandomNumberGenerator) -> int:
	match map_tier:
		"planet":
			return rng.randi_range(40, 60)
		"large":
			return rng.randi_range(22, 30)
		"medium":
			return rng.randi_range(14, 18)
		"current", "small":
			return rng.randi_range(8, 10)
		_:
			return rng.randi_range(14, 18)


static func _map_scale_for_tier(map_tier: String) -> float:
	match map_tier:
		"planet":
			return 2.35
		"large":
			return 2.0
		"medium":
			return 1.7
		"current", "small":
			return 1.0
		_:
			return 1.7


static func _sector_tag_for_pos(pos: Vector2) -> String:
	if absf(pos.x) >= absf(pos.y):
		return "east" if pos.x >= 0.0 else "west"
	return "north" if pos.y < 0.0 else "south"


static func _hostile_room_count(op_index: int, objective_template: String, map_tier: String = "medium") -> int:
	var base := clampi(op_index + 1, 2, 4)
	match map_tier:
		"planet":
			base = clampi(op_index + 18, 24, 34)
		"large":
			base = clampi(op_index + 5, 8, 12)
		"medium":
			base = clampi(op_index + 3, 5, 8)
	if objective_template == "silent_extract":
		base = maxi(1, base - 1)
	return base


static func _hive_count_for_tier(map_tier: String, objective_template: String, rng: RandomNumberGenerator) -> int:
	if objective_template == "hive_purge":
		match map_tier:
			"large":
				return rng.randi_range(2, 3)
			"medium":
				return rng.randi_range(1, 2)
			_:
				return 1
	match map_tier:
		"large":
			return rng.randi_range(1, 2)
		"medium":
			return rng.randi_range(0, 1)
		_:
			return 0

static func _enemies_per_room(op_index: int, rng: RandomNumberGenerator) -> int:
	match clampi(op_index, 1, 4):
		1:
			return 1
		2:
			return rng.randi_range(1, 2)
		3:
			return 2
		_:
			return 2

static func _pick_room_names(count: int, _rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array[String] = []
	for room_name in ROOM_NAME_POOL:
		pool.append(room_name)
	pool.shuffle()
	var names: Array[String] = []
	for i in range(count):
		if i < pool.size():
			names.append(pool[i])
		else:
			names.append("Sector %d" % (i + 1))
	if names.size() > 0:
		names[names.size() - 1] = "Command Bridge"
	return names

static func _pick_room_shape(rng: RandomNumberGenerator, force_shape: String = "") -> String:
	if not force_shape.is_empty():
		return force_shape
	var roll := rng.randi_range(1, 100)
	var cumulative := 0
	for entry in SHAPE_WEIGHTS:
		cumulative += int(entry["weight"])
		if roll <= cumulative:
			return str(entry["id"])
	return "standard"


static func _size_for_shape(shape: String, rng: RandomNumberGenerator) -> Vector2:
	match shape:
		"wide_bay":
			return ROOM_SHAPE_WIDE_BAY
		"choke":
			return ROOM_SHAPE_CHOKE
		"loot":
			return ROOM_SHAPE_LOOT
		_:
			return ROOM_SIZE_POOL[rng.randi() % ROOM_SIZE_POOL.size()]


static func _build_spine_layout(count: int, rng: RandomNumberGenerator, map_scale: float = 1.0) -> Dictionary:
	var corridor_len: float = CORRIDOR_LENGTH * map_scale
	var rooms: Array[Dictionary] = []
	var link_specs: Array[Dictionary] = []
	var corridors: Array[Rect2] = []
	var branch_budget := mini(maxi(0, count - 5), maxi(0, int(round(float(count) * 0.35))))
	var spine_len := count - branch_budget
	var first_shape := _pick_room_shape(rng)
	rooms.append({
		"index": 0,
		"pos": Vector2.ZERO,
		"size": _size_for_shape(first_shape, rng),
		"shape": first_shape,
	})
	for i in range(1, spine_len):
		var shape := _pick_room_shape(rng)
		var child_size: Vector2 = _size_for_shape(shape, rng)
		var parent_idx: int = i - 1
		var parent: Dictionary = rooms[parent_idx]
		var dir := "E"
		var child_pos: Vector2 = _child_pos_from_attachment_scaled(parent.pos, parent.size, child_size, dir, corridor_len)
		var parent_port: Vector2 = _port_on_edge(parent.pos, parent.size, dir)
		var child_port: Vector2 = _port_on_edge(child_pos, child_size, _opposite_dir(dir))
		var corridor: Rect2 = _corridor_rect_between(parent_port, child_port)
		rooms.append({"index": i, "pos": child_pos, "size": child_size, "shape": shape})
		link_specs.append({"a": parent_idx, "b": i, "parent_dir": dir})
		corridors.append(corridor)
	var parent_candidates: Array[int] = []
	for i in range(1, spine_len - 1):
		parent_candidates.append(i)
	if parent_candidates.is_empty() and spine_len > 2:
		parent_candidates.append(int(spine_len / 2))
	for b in range(branch_budget):
		var room_idx: int = spine_len + b
		var shape := _pick_room_shape(rng)
		var child_size: Vector2 = _size_for_shape(shape, rng)
		var placed := false
		var attempts: Array = []
		for parent_idx in parent_candidates:
			for dir in ["N", "S"]:
				attempts.append([parent_idx, dir])
		attempts.shuffle()
		for attempt in attempts:
			var parent_idx: int = attempt[0]
			var dir: String = attempt[1]
			var parent: Dictionary = rooms[parent_idx]
			var child_pos: Vector2 = _child_pos_from_attachment_scaled(parent.pos, parent.size, child_size, dir, corridor_len)
			var parent_port: Vector2 = _port_on_edge(parent.pos, parent.size, dir)
			var child_port: Vector2 = _port_on_edge(child_pos, child_size, _opposite_dir(dir))
			var corridor: Rect2 = _corridor_rect_between(parent_port, child_port)
			if _layout_overlaps(child_pos, child_size, rooms, corridors, corridor, parent_idx):
				continue
			rooms.append({"index": room_idx, "pos": child_pos, "size": child_size, "shape": shape})
			link_specs.append({"a": parent_idx, "b": room_idx, "parent_dir": dir})
			corridors.append(corridor)
			placed = true
			break
		if not placed and not parent_candidates.is_empty():
			var parent_idx: int = parent_candidates[b % parent_candidates.size()]
			var dir := "N" if b % 2 == 0 else "S"
			var parent: Dictionary = rooms[parent_idx]
			var child_pos: Vector2 = _child_pos_from_attachment_scaled(parent.pos, parent.size, child_size, dir, corridor_len)
			var parent_port: Vector2 = _port_on_edge(parent.pos, parent.size, dir)
			var child_port: Vector2 = _port_on_edge(child_pos, child_size, _opposite_dir(dir))
			var corridor: Rect2 = _corridor_rect_between(parent_port, child_port)
			rooms.append({"index": room_idx, "pos": child_pos, "size": child_size, "shape": shape})
			link_specs.append({"a": parent_idx, "b": room_idx, "parent_dir": dir})
			corridors.append(corridor)
	return {"rooms": rooms, "link_specs": link_specs, "corridors": corridors}


static func _layout_world_span(layout: Dictionary) -> float:
	var room_list: Array = layout.get("rooms", [])
	if room_list.is_empty():
		return 0.0
	var min_pos: Vector2 = _room_aabb(room_list[0].pos, room_list[0].size, 0.0).position
	var max_pos: Vector2 = _room_aabb(room_list[0].pos, room_list[0].size, 0.0).end
	for room in room_list:
		var rect: Rect2 = _room_aabb(room.pos, room.size, 0.0)
		min_pos = min_pos.min(rect.position)
		max_pos = max_pos.max(rect.end)
	return maxf(max_pos.x - min_pos.x, max_pos.y - min_pos.y)


static func _build_lego_layout(count: int, rng: RandomNumberGenerator, add_loot_branch: bool = false, map_scale: float = 1.0) -> Dictionary:
	var rooms: Array[Dictionary] = []
	var link_specs: Array[Dictionary] = []
	var corridors: Array[Rect2] = []
	var corridor_len: float = CORRIDOR_LENGTH * map_scale
	var first_shape := _pick_room_shape(rng)
	rooms.append({
		"index": 0,
		"pos": Vector2.ZERO,
		"size": _size_for_shape(first_shape, rng),
		"shape": first_shape,
	})
	for i in range(1, count):
		var is_loot_leaf := add_loot_branch and i == count - 1
		var shape := "loot" if is_loot_leaf else _pick_room_shape(rng)
		var child_size: Vector2 = _size_for_shape(shape, rng)
		var placed := false
		var attempts: Array = []
		var preferred_parents: Array[int] = []
		if is_loot_leaf:
			preferred_parents = _leaf_room_indices(link_specs, rooms.size())
		for parent_idx in range(rooms.size()):
			if is_loot_leaf and not preferred_parents.is_empty() and parent_idx not in preferred_parents:
				continue
			for dir in ["E", "W", "N", "S"]:
				attempts.append([parent_idx, dir])
		if is_loot_leaf and attempts.is_empty():
			for parent_idx in range(rooms.size()):
				for dir in ["E", "W", "N", "S"]:
					attempts.append([parent_idx, dir])
		attempts.shuffle()
		for attempt in attempts:
			var parent_idx: int = attempt[0]
			var dir: String = attempt[1]
			var parent: Dictionary = rooms[parent_idx]
			var child_pos: Vector2 = _child_pos_from_attachment_scaled(parent.pos, parent.size, child_size, dir, corridor_len)
			var parent_port: Vector2 = _port_on_edge(parent.pos, parent.size, dir)
			var child_port: Vector2 = _port_on_edge(child_pos, child_size, _opposite_dir(dir))
			var corridor: Rect2 = _corridor_rect_between(parent_port, child_port)
			if _layout_overlaps(child_pos, child_size, rooms, corridors, corridor, parent_idx):
				continue
			rooms.append({"index": i, "pos": child_pos, "size": child_size, "shape": shape})
			link_specs.append({"a": parent_idx, "b": i, "parent_dir": dir})
			corridors.append(corridor)
			placed = true
			break
		if not placed:
			var parent_idx: int = i - 1
			var dir := "E"
			var parent: Dictionary = rooms[parent_idx]
			var child_pos: Vector2 = _child_pos_from_attachment_scaled(parent.pos, parent.size, child_size, dir, corridor_len)
			var parent_port: Vector2 = _port_on_edge(parent.pos, parent.size, dir)
			var child_port: Vector2 = _port_on_edge(child_pos, child_size, _opposite_dir(dir))
			var corridor: Rect2 = _corridor_rect_between(parent_port, child_port)
			rooms.append({"index": i, "pos": child_pos, "size": child_size, "shape": shape})
			link_specs.append({"a": parent_idx, "b": i, "parent_dir": dir})
			corridors.append(corridor)
	return {"rooms": rooms, "link_specs": link_specs, "corridors": corridors}


static func _leaf_room_indices(link_specs: Array[Dictionary], room_count: int) -> Array[int]:
	var degree: Dictionary = {}
	for i in range(room_count):
		degree[i] = 0
	for spec in link_specs:
		degree[spec["a"]] = int(degree.get(spec["a"], 0)) + 1
		degree[spec["b"]] = int(degree.get(spec["b"], 0)) + 1
	var leaves: Array[int] = []
	for i in range(room_count):
		if int(degree.get(i, 0)) <= 1 and i != room_count - 1:
			leaves.append(i)
	return leaves

static func _finalize_links(data: RefCounted, link_specs: Array[Dictionary]) -> void:
	data.corridors.clear()
	var resolved_links: Array[Dictionary] = []
	for spec in link_specs:
		var room_a: Dictionary = data.rooms[spec["a"]]
		var room_b: Dictionary = data.rooms[spec["b"]]
		var parent_dir: String = spec["parent_dir"]
		var a_port: Vector2 = _port_on_edge(room_a.pos, room_a.size, parent_dir)
		var b_port: Vector2 = _port_on_edge(room_b.pos, room_b.size, _opposite_dir(parent_dir))
		var corridor: Rect2 = _corridor_rect_between(a_port, b_port)
		data.corridors.append(corridor)
		resolved_links.append({
			"a": spec["a"],
			"b": spec["b"],
			"a_port": a_port,
			"b_port": b_port,
			"corridor": corridor,
		})
	_build_path_graph(data, resolved_links)

static func _center_layout(layout: Dictionary) -> void:
	var rooms: Array = layout.rooms
	var corridors: Array = layout.corridors
	if rooms.is_empty():
		return
	var min_pos: Vector2 = _room_aabb(rooms[0].pos, rooms[0].size, 0.0).position
	var max_pos: Vector2 = _room_aabb(rooms[0].pos, rooms[0].size, 0.0).end
	for room in rooms:
		var rect: Rect2 = _room_aabb(room.pos, room.size, 0.0)
		min_pos = min_pos.min(rect.position)
		max_pos = max_pos.max(rect.end)
	for rect in corridors:
		min_pos = min_pos.min(rect.position)
		max_pos = max_pos.max(rect.end)
	var center: Vector2 = (min_pos + max_pos) * 0.5
	for room in rooms:
		room.pos -= center
	for i in range(corridors.size()):
		var rect: Rect2 = corridors[i]
		corridors[i] = Rect2(rect.position - center, rect.size)

static func _assign_roles(
	count: int,
	rng: RandomNumberGenerator,
	op_index: int,
	objective_template: String,
	add_loot_branch: bool = false,
	map_tier: String = "medium",
) -> Array[Dictionary]:
	var roles: Array[Dictionary] = []
	for _i in range(count):
		roles.append({"extract": false, "clear": false, "enemies": 0, "spawn_eligible": true})
	roles[count - 1]["extract"] = true
	roles[count - 1]["spawn_eligible"] = false
	var loot_idx := count - 1 if add_loot_branch else -1
	if loot_idx >= 0:
		roles[loot_idx]["id_override"] = "loot_branch"
		roles[loot_idx]["loot_branch"] = true
		roles[loot_idx]["spawn_eligible"] = true
		roles[loot_idx]["clear"] = false
		roles[loot_idx]["enemies"] = 0
	var hostile_indices: Array[int] = []
	for i in range(count - 1):
		if i == loot_idx:
			continue
		hostile_indices.append(i)
	hostile_indices.shuffle()
	var hostile_count: int = mini(_hostile_room_count(op_index, objective_template, map_tier), hostile_indices.size())
	var per_room: int = _enemies_per_room(op_index, rng)
	var hold_room_idx: int = hostile_indices[0] if objective_template == "hold_purge" and hostile_count > 0 else -1
	var terminal_pool: Array[int] = []
	if objective_template == "black_site":
		for hi in range(hostile_count):
			terminal_pool.append(hostile_indices[hi])
		terminal_pool.shuffle()
	var terminal_count := mini(3, maxi(2, terminal_pool.size()))
	var terminal_indices: Dictionary = {}
	for t in range(terminal_count):
		if t >= terminal_pool.size():
			break
		terminal_indices[terminal_pool[t]] = true
	if objective_template == "vip_recovery":
		var hostile_set: Dictionary = {}
		for hi in range(mini(hostile_count, hostile_indices.size())):
			hostile_set[hostile_indices[hi]] = true
		var vip_candidates: Array[int] = []
		for idx in range(count - 1):
			if idx == loot_idx:
				continue
			if not hostile_set.has(idx):
				vip_candidates.append(idx)
		if vip_candidates.is_empty():
			for idx in range(count - 1):
				if idx != loot_idx:
					vip_candidates.append(idx)
		if not vip_candidates.is_empty():
			var vip_idx: int = vip_candidates[rng.randi() % vip_candidates.size()]
			roles[vip_idx]["vip_room"] = true
			roles[vip_idx]["spawn_eligible"] = true
	for i in range(hostile_count):
		var idx: int = hostile_indices[i]
		roles[idx]["clear"] = true
		roles[idx]["spawn_eligible"] = false
		if idx == hold_room_idx:
			roles[idx]["hold_room"] = true
		if terminal_indices.has(idx):
			roles[idx]["intel_terminal"] = true
		var enemy_count: int = per_room
		var is_elite_slot := false
		if op_index >= 3 and i == hostile_count - 1:
			is_elite_slot = true
		elif op_index >= 4 and hostile_count > 1 and i == hostile_count - 2:
			is_elite_slot = true
		if is_elite_slot:
			roles[idx]["elite_slot"] = true
			enemy_count += 1
		roles[idx]["enemies"] = enemy_count
	if objective_template == "scavenge" and hostile_indices.size() > hostile_count:
		var bonus_idx: int = hostile_indices[hostile_count]
		if bonus_idx != loot_idx:
			roles[bonus_idx]["scavenge_bonus"] = true
			roles[bonus_idx]["id_override"] = "scavenge_bonus"
			roles[bonus_idx]["spawn_eligible"] = true
			roles[bonus_idx]["clear"] = false
			roles[bonus_idx]["enemies"] = 0
	var hive_count := _hive_count_for_tier(map_tier, objective_template, rng)
	if hive_count > 0:
		var hive_pool: Array[int] = []
		for idx in hostile_indices:
			if idx == hold_room_idx or terminal_indices.has(idx):
				continue
			hive_pool.append(idx)
		hive_pool.shuffle()
		for h in range(mini(hive_count, hive_pool.size())):
			var hive_idx: int = hive_pool[h]
			roles[hive_idx]["hive_room"] = true
			roles[hive_idx]["enemies"] = maxi(int(roles[hive_idx]["enemies"]), 1)
			roles[hive_idx]["id_override"] = "hive_%d" % h
	return roles


static func _assign_planet_roles(count: int, rng: RandomNumberGenerator, op_index: int, config: Dictionary = {}) -> Array[Dictionary]:
	var roles: Array[Dictionary] = []
	for _i in range(count):
		roles.append({"extract": false, "clear": false, "enemies": 0, "spawn_eligible": true})
	roles[0]["spawn_eligible"] = true
	roles[0]["clear"] = false
	roles[0]["enemies"] = 0
	roles[0]["id_override"] = "planet_deploy"
	roles[count - 1]["extract"] = true
	roles[count - 1]["spawn_eligible"] = false
	roles[count - 1]["id_override"] = "planet_extract"
	var hostile_indices: Array[int] = []
	for i in range(1, count - 1):
		hostile_indices.append(i)
	hostile_indices.shuffle()
	var hostile_count: int = mini(_hostile_room_count(op_index, "planet_reclamation", "planet"), hostile_indices.size())
	var per_room: int = _enemies_per_room(op_index, rng)
	for i in range(hostile_count):
		var idx: int = hostile_indices[i]
		roles[idx]["clear"] = true
		roles[idx]["spawn_eligible"] = false
		roles[idx]["enemies"] = per_room + (1 if i >= hostile_count - 2 else 0)
		if _mutators_include(config, "quiet_deck"):
			roles[idx]["enemies"] = maxi(0, int(roles[idx]["enemies"]) - 1)
		if i >= hostile_count - 2:
			roles[idx]["elite_slot"] = true
	var hive_count := rng.randi_range(1, 2)
	if _mutators_include(config, "dense_spores"):
		hive_count += 1
	if hive_count > 0:
		hive_count = mini(hive_count, maxi(1, hostile_indices.size() - 1))
	var hive_pool: Array[int] = []
	for idx in hostile_indices:
		hive_pool.append(idx)
	hive_pool.shuffle()
	for h in range(mini(hive_count, hive_pool.size())):
		var hive_idx: int = hive_pool[h]
		roles[hive_idx]["hive_room"] = true
		roles[hive_idx]["enemies"] = maxi(int(roles[hive_idx]["enemies"]), 1)
		roles[hive_idx]["id_override"] = "hive_%d" % h
	var overmind_idx := _pick_overmind_room_index(count, hostile_indices)
	if overmind_idx >= 0:
		roles[overmind_idx]["hive_room"] = true
		roles[overmind_idx]["overmind_room"] = true
		roles[overmind_idx]["clear"] = true
		roles[overmind_idx]["enemies"] = maxi(int(roles[overmind_idx]["enemies"]), 2)
		roles[overmind_idx]["elite_slot"] = true
		roles[overmind_idx]["id_override"] = "overmind_core"
	var evo_pool: Array[int] = []
	for idx in hostile_indices:
		if idx != overmind_idx and not roles[idx].get("hive_room", false):
			evo_pool.append(idx)
	evo_pool.shuffle()
	var evo_count := mini(rng.randi_range(1, 2), evo_pool.size())
	for e in range(evo_count):
		var evo_idx: int = evo_pool[e]
		roles[evo_idx]["evolution_node"] = true
		if not roles[evo_idx].has("id_override"):
			roles[evo_idx]["id_override"] = "evo_%d" % e
	return roles


static func _apply_campaign_boss_roles(
	roles: Array[Dictionary],
	count: int,
	rng: RandomNumberGenerator,
	config: Dictionary,
) -> void:
	var hostile_indices: Array[int] = []
	for i in range(count - 1):
		if roles[i].get("clear", false) and not roles[i].get("loot_branch", false):
			hostile_indices.append(i)
	hostile_indices.shuffle()
	var hive_count := rng.randi_range(1, 2)
	if _mutators_include(config, "dense_spores"):
		hive_count += 1
	var hive_pool: Array[int] = []
	for idx in hostile_indices:
		if not roles[idx].get("overmind_room", false):
			hive_pool.append(idx)
	hive_pool.shuffle()
	for h in range(mini(hive_count, hive_pool.size())):
		var hive_idx: int = hive_pool[h]
		roles[hive_idx]["hive_room"] = true
		roles[hive_idx]["enemies"] = maxi(int(roles[hive_idx]["enemies"]), 1)
		roles[hive_idx]["id_override"] = "hive_%d" % h
	var overmind_idx := _pick_overmind_room_index(count, hostile_indices)
	if overmind_idx >= 0:
		roles[overmind_idx]["hive_room"] = true
		roles[overmind_idx]["overmind_room"] = true
		roles[overmind_idx]["clear"] = true
		roles[overmind_idx]["enemies"] = maxi(int(roles[overmind_idx]["enemies"]), 2)
		roles[overmind_idx]["elite_slot"] = true
		roles[overmind_idx]["id_override"] = "overmind_core"
	var evo_pool: Array[int] = []
	for idx in hostile_indices:
		if idx != overmind_idx and not roles[idx].get("hive_room", false):
			evo_pool.append(idx)
	evo_pool.shuffle()
	var evo_count := mini(rng.randi_range(1, 2), evo_pool.size())
	for e in range(evo_count):
		var evo_idx: int = evo_pool[e]
		roles[evo_idx]["evolution_node"] = true
		if not roles[evo_idx].has("id_override"):
			roles[evo_idx]["id_override"] = "evo_%d" % e


static func _pick_overmind_room_index(count: int, hostile_indices: Array[int]) -> int:
	if hostile_indices.is_empty():
		return count - 2 if count > 2 else -1
	var best_idx: int = hostile_indices[0]
	var best_dist := 0.0
	for idx in hostile_indices:
		if idx <= 0 or idx >= count - 1:
			continue
		var dist := absf(float(idx - (count / 2)))
		if dist > best_dist:
			best_dist = dist
			best_idx = idx
	return best_idx


static func _opposite_dir(dir: String) -> String:
	match dir:
		"E":
			return "W"
		"W":
			return "E"
		"N":
			return "S"
		"S":
			return "N"
	return "E"

static func _port_on_edge(room_pos: Vector2, room_size: Vector2, dir: String) -> Vector2:
	var half: Vector2 = room_size * 0.5
	match dir:
		"E":
			return room_pos + Vector2(half.x, 0.0)
		"W":
			return room_pos + Vector2(-half.x, 0.0)
		"N":
			return room_pos + Vector2(0.0, -half.y)
		"S":
			return room_pos + Vector2(0.0, half.y)
	return room_pos

static func _child_pos_from_attachment_scaled(parent_pos: Vector2, parent_size: Vector2, child_size: Vector2, dir: String, corridor_len: float) -> Vector2:
	var ph: Vector2 = parent_size * 0.5
	var ch: Vector2 = child_size * 0.5
	match dir:
		"E":
			return Vector2(parent_pos.x + ph.x + corridor_len + ch.x, parent_pos.y)
		"W":
			return Vector2(parent_pos.x - ph.x - corridor_len - ch.x, parent_pos.y)
		"S":
			return Vector2(parent_pos.x, parent_pos.y + ph.y + corridor_len + ch.y)
		"N":
			return Vector2(parent_pos.x, parent_pos.y - ph.y - corridor_len - ch.y)
	return parent_pos


static func _child_pos_from_attachment(parent_pos: Vector2, parent_size: Vector2, child_size: Vector2, dir: String) -> Vector2:
	return _child_pos_from_attachment_scaled(parent_pos, parent_size, child_size, dir, CORRIDOR_LENGTH)

static func _corridor_rect_between(port_a: Vector2, port_b: Vector2) -> Rect2:
	var inset := 6.0
	if absf(port_a.x - port_b.x) >= absf(port_a.y - port_b.y):
		var x0: float = minf(port_a.x, port_b.x) - inset
		var x1: float = maxf(port_a.x, port_b.x) + inset
		var y: float = (port_a.y + port_b.y) * 0.5
		return Rect2(Vector2(x0, y - CORRIDOR_WIDTH * 0.5), Vector2(maxf(x1 - x0, 8.0), CORRIDOR_WIDTH))
	var y0: float = minf(port_a.y, port_b.y) - inset
	var y1: float = maxf(port_a.y, port_b.y) + inset
	var x: float = (port_a.x + port_b.x) * 0.5
	return Rect2(Vector2(x - CORRIDOR_WIDTH * 0.5, y0), Vector2(CORRIDOR_WIDTH, maxf(y1 - y0, 8.0)))

static func _room_aabb(pos: Vector2, size: Vector2, margin: float) -> Rect2:
	var half: Vector2 = size * 0.5
	return Rect2(pos - half, size).grow(margin)

static func _layout_overlaps(
	child_pos: Vector2,
	child_size: Vector2,
	existing_rooms: Array,
	existing_corridors: Array,
	new_corridor: Rect2,
	parent_idx: int
) -> bool:
	var child_rect: Rect2 = _room_aabb(child_pos, child_size, PIECE_MARGIN)
	for i in range(existing_rooms.size()):
		if child_rect.intersects(_room_aabb(existing_rooms[i].pos, existing_rooms[i].size, PIECE_MARGIN)):
			return true
	for rect in existing_corridors:
		if child_rect.intersects(rect.grow(4.0)):
			return true
	for i in range(existing_rooms.size()):
		if i == parent_idx:
			continue
		if new_corridor.intersects(_room_aabb(existing_rooms[i].pos, existing_rooms[i].size, 2.0)):
			return true
	for rect in existing_corridors:
		if new_corridor.intersects(rect.grow(2.0)):
			return true
	return false

static func _build_path_graph(data: RefCounted, links: Array) -> void:
	var graph = data.path_graph
	for room_data: Dictionary in data.rooms:
		var room_node_id: String = room_data["id"]
		graph.nodes[room_node_id] = room_data["pos"]
		graph.room_name_to_node[room_data["name"]] = room_node_id
	for link in links:
		var room_a: Dictionary = data.rooms[link["a"]]
		var room_b: Dictionary = data.rooms[link["b"]]
		var a_id: String = room_a["id"]
		var b_id: String = room_b["id"]
		var door_a_id: String = "%s_%s_door_a" % [a_id, b_id]
		var door_b_id: String = "%s_%s_door_b" % [a_id, b_id]
		graph.nodes[door_a_id] = link["a_port"]
		graph.nodes[door_b_id] = link["b_port"]
		graph.edges.append([a_id, door_a_id])
		graph.edges.append([door_a_id, door_b_id])
		graph.edges.append([door_b_id, b_id])
		graph.door_connections.append({"room_node": a_id, "spine_node": door_a_id})
		graph.door_connections.append({"room_node": b_id, "spine_node": door_b_id})
		graph.corridor_segments.append({
			"rect": link["corridor"],
			"door_a": door_a_id,
			"door_b": door_b_id,
		})
	graph.corridor_rects = data.corridors.duplicate()

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


static func _mutators_include(config: Dictionary, mutator_id: String) -> bool:
	var raw = config.get("mutators", [])
	if raw is Array:
		return mutator_id in raw
	return false
