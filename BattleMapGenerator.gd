class_name BattleMapGenerator
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleMapPlacementLib := preload("res://BattleMapPlacement.gd")

const GRID_W := 96
const GRID_H := 72
const CELL := 32.0
const CP_MIN_SPACING_CELLS := 10
const CP_EDGE_MARGIN := 8
const CP_RADIUS_CELLS := 4

const DEFAULT_QUANTUM_MIX: Dictionary = {
	"grass": 0.38,
	"water": 0.12,
	"mountain": 0.18,
	"sand": 0.14,
	"mud": 0.18,
}


static func get_lane_spawn_positions(
	battle_data,
	zone: Rect2,
	count: int,
	rng: RandomNumberGenerator,
) -> PackedVector2Array:
	var positions: PackedVector2Array = PackedVector2Array()
	if count <= 0 or zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return positions
	for i in range(count):
		if battle_data != null:
			positions.append(BattleMapPlacementLib.spawn_in_zone(battle_data, zone, i, count, rng))
		else:
			var cols := maxi(1, int(sqrt(float(count)) * 1.4))
			var cell_w := zone.size.x / float(cols)
			var cell_h := zone.size.y / float(maxi(1, int(ceil(float(count) / float(cols)))))
			var col: int = i % cols
			var row: int = i / cols
			positions.append(
				zone.position + Vector2((col + 0.5) * cell_w, (row + 0.5) * cell_h)
			)
	return positions


static func generate(
	seed_value: int,
	terrain_tag: String,
	player_count: int,
	enemy_count: int,
	node_id: String = "",
	terrain_mix: Dictionary = {},
	node_type: String = "battle",
):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mix: Dictionary = terrain_mix.duplicate()
	if mix.is_empty():
		mix = _mix_for_tag(terrain_tag, rng)
	var data = generate_quantum(seed_value, mix, player_count, enemy_count, node_id, terrain_tag, node_type)
	data.terrain_tag = terrain_tag if terrain_tag != "mixed" else _dominant_mix_label(mix)
	return data


static func generate_quantum(
	seed_value: int,
	terrain_mix: Dictionary,
	player_count: int,
	enemy_count: int,
	node_id: String = "",
	terrain_tag: String = "mixed",
	node_type: String = "battle",
):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data = BattleMapDataLib.new()
	data.map_seed = seed_value
	data.terrain_tag = terrain_tag
	data.terrain_mix = _normalize_mix(terrain_mix)
	data.grid_width = GRID_W
	data.grid_height = GRID_H
	data.cell_size = CELL
	data.map_size = Vector2(GRID_W * CELL, GRID_H * CELL)
	data.player_allocation = player_count
	data.enemy_allocation = enemy_count
	data.node_id = node_id
	data.node_type = node_type
	data.mass_unit_mode = false
	data.contact_column = GRID_W / 2
	data.objective_sectors_required = 0
	data.max_visual_units = 2200
	data.active_lite_cap = 2200
	data.impostor_size = 14.0
	data.engagement_zoom = 0.38
	_apply_mix_modifiers(data)
	var total := GRID_W * GRID_H
	data.terrain_cells = PackedByteArray()
	data.terrain_cells.resize(total)
	data.cover_cells = PackedByteArray()
	data.cover_cells.resize(total)
	data.blocked_cells = PackedByteArray()
	data.blocked_cells.resize(total)
	data.tile_height = PackedFloat32Array()
	data.tile_height.resize(total)
	_paint_coherent_biomes(data, rng)
	data.rebuild_terrain_arrays()
	_paint_border_walls(data)
	data.sync_blocked_from_terrain()
	_apply_cover_noise(data, rng)
	_define_zones(data)
	_build_regions_and_graph(data, rng)
	_aggregate_sector_terrain(data)
	_place_capture_points(data, rng, node_type, enemy_count)
	return data


## Large single-map RTS world (~4× linear vs standard battle = ~16× tiles).
static func generate_sized(
	seed_value: int,
	grid_w: int,
	grid_h: int,
	cell_size: float,
	terrain_mix: Dictionary,
	player_count: int,
	enemy_count: int,
	node_id: String = "world",
	terrain_tag: String = "mixed",
	node_type: String = "world",
):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data = BattleMapDataLib.new()
	data.map_seed = seed_value
	data.terrain_tag = terrain_tag
	data.terrain_mix = _normalize_mix(terrain_mix)
	data.grid_width = grid_w
	data.grid_height = grid_h
	data.cell_size = cell_size
	data.map_size = Vector2(float(grid_w) * cell_size, float(grid_h) * cell_size)
	data.player_allocation = player_count
	data.enemy_allocation = enemy_count
	data.node_id = node_id
	data.node_type = node_type
	data.mass_unit_mode = false
	data.contact_column = grid_w / 2
	data.objective_sectors_required = 0
	data.placed_structures = []
	data.max_visual_units = 2200
	data.active_lite_cap = 2200
	data.impostor_size = 14.0
	data.engagement_zoom = 0.38
	_apply_mix_modifiers(data)
	var total := grid_w * grid_h
	data.terrain_cells = PackedByteArray()
	data.terrain_cells.resize(total)
	data.cover_cells = PackedByteArray()
	data.cover_cells.resize(total)
	data.blocked_cells = PackedByteArray()
	data.blocked_cells.resize(total)
	data.tile_height = PackedFloat32Array()
	data.tile_height.resize(total)
	_paint_coherent_biomes(data, rng)
	data.rebuild_terrain_arrays()
	_paint_border_walls(data)
	data.sync_blocked_from_terrain()
	_apply_cover_noise(data, rng)
	_define_zones(data)
	_build_regions_and_graph(data, rng)
	_aggregate_sector_terrain(data)
	_place_capture_points(data, rng, node_type, enemy_count)
	return data


static func _normalize_mix(raw: Dictionary) -> Dictionary:
	var mix: Dictionary = {}
	var total := 0.0
	for key in ["grass", "water", "mountain", "sand", "mud"]:
		var w: float = float(raw.get(key, 0.0))
		if w > 0.0:
			mix[key] = w
			total += w
	if total <= 0.0:
		return DEFAULT_QUANTUM_MIX.duplicate()
	for key in mix.keys():
		mix[key] = float(mix[key]) / total
	return mix


static func _mix_for_tag(terrain_tag: String, rng: RandomNumberGenerator) -> Dictionary:
	match terrain_tag:
		"mountain":
			return {"grass": 0.22, "water": 0.06, "mountain": 0.48, "sand": 0.12, "mud": 0.12}
		"urban":
			return {"grass": 0.12, "water": 0.05, "mountain": 0.08, "sand": 0.2, "mud": 0.55}
		"open_field":
			return {"grass": 0.62, "water": 0.05, "mountain": 0.08, "sand": 0.15, "mud": 0.1}
		"mixed":
			return _random_mix(rng)
		_:
			return DEFAULT_QUANTUM_MIX.duplicate()


static func _random_mix(rng: RandomNumberGenerator) -> Dictionary:
	var keys: Array[String] = ["grass", "water", "mountain", "sand", "mud"]
	var weights: Array[float] = []
	var total := 0.0
	for _k in keys:
		var w: float = rng.randf_range(0.05, 1.0)
		weights.append(w)
		total += w
	var mix: Dictionary = {}
	for i in range(keys.size()):
		mix[keys[i]] = weights[i] / total
	return mix


static func _dominant_mix_label(mix: Dictionary) -> String:
	var best_key := "grass"
	var best_val := -1.0
	for key in mix.keys():
		var v: float = float(mix[key])
		if v > best_val:
			best_val = v
			best_key = str(key)
	return best_key


static func _terrain_from_name(name: String) -> int:
	match name:
		"water":
			return BattleMapDataLib.Terrain.WATER
		"mountain":
			return BattleMapDataLib.Terrain.MOUNTAIN
		"sand":
			return BattleMapDataLib.Terrain.SAND
		"mud":
			return BattleMapDataLib.Terrain.MUD
		_:
			return BattleMapDataLib.Terrain.GRASS


static func _paint_coherent_biomes(data, rng: RandomNumberGenerator) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var total: int = w * h
	for i in range(total):
		data.terrain_cells[i] = BattleMapDataLib.Terrain.GRASS
	var low_w: int = maxi(12, w / 4)
	var low_h: int = maxi(9, h / 4)
	var elev: PackedFloat32Array = PackedFloat32Array()
	var moist: PackedFloat32Array = PackedFloat32Array()
	elev.resize(low_w * low_h)
	moist.resize(low_w * low_h)
	for ly in range(low_h):
		for lx in range(low_w):
			var li: int = ly * low_w + lx
			elev[li] = rng.randf()
			moist[li] = rng.randf()
	_smooth_lowres_field(elev, low_w, low_h, 3)
	_smooth_lowres_field(moist, low_w, low_h, 3)
	var water_share: float = float(data.terrain_mix.get("water", 0.12))
	var mountain_share: float = float(data.terrain_mix.get("mountain", 0.18))
	var sand_share: float = float(data.terrain_mix.get("sand", 0.14))
	var mud_share: float = float(data.terrain_mix.get("mud", 0.18))
	var water_level: float = lerpf(0.58, 0.42, clampf(water_share * 2.5, 0.0, 1.0))
	var mountain_level: float = lerpf(0.78, 0.62, clampf(mountain_share * 2.2, 0.0, 1.0))
	var mud_level: float = lerpf(0.68, 0.52, clampf(mud_share * 2.0, 0.0, 1.0))
	for gy in range(h):
		for gx in range(w):
			var e: float = _sample_lowres(elev, low_w, low_h, gx, gy, w, h)
			var m: float = _sample_lowres(moist, low_w, low_h, gx, gy, w, h)
			data.tile_height[gy * w + gx] = e  # normalized height for flow mechanics (downhill bias)
			var edge: float = minf(
				minf(float(gx), float(w - 1 - gx)) / float(w),
				minf(float(gy), float(h - 1 - gy)) / float(h),
			)
			if edge < 0.04 or (edge < 0.1 and m < 0.35):
				data.terrain_cells[gy * w + gx] = BattleMapDataLib.Terrain.WATER
			elif e >= mountain_level:
				data.terrain_cells[gy * w + gx] = BattleMapDataLib.Terrain.MOUNTAIN
			elif m <= water_level and e < 0.45:
				data.terrain_cells[gy * w + gx] = BattleMapDataLib.Terrain.WATER
			elif m <= water_level + 0.08 and e < 0.5:
				data.terrain_cells[gy * w + gx] = BattleMapDataLib.Terrain.SAND
			elif e < 0.38 and m >= mud_level:
				data.terrain_cells[gy * w + gx] = BattleMapDataLib.Terrain.MUD
			else:
				data.terrain_cells[gy * w + gx] = BattleMapDataLib.Terrain.GRASS
	_expand_sand_beaches(data)
	_place_mountain_ridges(data, rng, mountain_share)
	_smooth_terrain_cells(data, 4)
	_enforce_terrain_adjacency(data)
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			var chosen: int = int(data.terrain_cells[idx])
			if chosen == BattleMapDataLib.Terrain.MOUNTAIN:
				data.tile_height[idx] = 1.0
				if rng.randf() < 0.32:
					data.blocked_cells[idx] = 1
			elif chosen == BattleMapDataLib.Terrain.WATER:
				data.tile_height[idx] = 0.0
				data.blocked_cells[idx] = 1


static func _sample_lowres(
	field: PackedFloat32Array,
	low_w: int,
	low_h: int,
	gx: int,
	gy: int,
	w: int,
	h: int,
) -> float:
	var fx: float = float(gx) / maxf(1.0, float(w - 1)) * float(low_w - 1)
	var fy: float = float(gy) / maxf(1.0, float(h - 1)) * float(low_h - 1)
	var x0: int = clampi(int(floor(fx)), 0, low_w - 1)
	var y0: int = clampi(int(floor(fy)), 0, low_h - 1)
	var x1: int = mini(x0 + 1, low_w - 1)
	var y1: int = mini(y0 + 1, low_h - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var v00: float = field[y0 * low_w + x0]
	var v10: float = field[y0 * low_w + x1]
	var v01: float = field[y1 * low_w + x0]
	var v11: float = field[y1 * low_w + x1]
	var vx0: float = lerpf(v00, v10, tx)
	var vx1: float = lerpf(v01, v11, tx)
	return lerpf(vx0, vx1, ty)


static func _smooth_lowres_field(field: PackedFloat32Array, low_w: int, low_h: int, passes: int) -> void:
	var scratch: PackedFloat32Array = PackedFloat32Array()
	scratch.resize(field.size())
	for _pass in range(passes):
		for ly in range(low_h):
			for lx in range(low_w):
				var sum := 0.0
				var n := 0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var nx: int = clampi(lx + ox, 0, low_w - 1)
						var ny: int = clampi(ly + oy, 0, low_h - 1)
						sum += field[ny * low_w + nx]
						n += 1
				scratch[ly * low_w + lx] = sum / float(n)
		for i in range(field.size()):
			field[i] = scratch[i]


static func _expand_sand_beaches(data) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var sand_mask: PackedByteArray = PackedByteArray()
	sand_mask.resize(w * h)
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			if int(data.terrain_cells[idx]) != BattleMapDataLib.Terrain.WATER:
				continue
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					if absi(ox) + absi(oy) > 2:
						continue
					var nx: int = gx + ox
					var ny: int = gy + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni: int = ny * w + nx
					if int(data.terrain_cells[ni]) == BattleMapDataLib.Terrain.GRASS:
						sand_mask[ni] = 1
	for i in range(sand_mask.size()):
		if sand_mask[i] > 0:
			data.terrain_cells[i] = BattleMapDataLib.Terrain.SAND


static func _place_mountain_ridges(data, rng: RandomNumberGenerator, mountain_share: float) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var ridge_count: int = clampi(int(2.0 + mountain_share * 6.0), 2, 6)
	for _r in range(ridge_count):
		var cx: int = rng.randi_range(w / 5, w * 4 / 5)
		var cy: int = rng.randi_range(h / 5, h * 4 / 5)
		var radius: int = rng.randi_range(4, 10)
		for gy in range(maxi(0, cy - radius), mini(h, cy + radius + 1)):
			for gx in range(maxi(0, cx - radius), mini(w, cx + radius + 1)):
				if Vector2(gx - cx, gy - cy).length() > float(radius):
					continue
				var idx: int = gy * w + gx
				if int(data.terrain_cells[idx]) == BattleMapDataLib.Terrain.WATER:
					continue
				if rng.randf() < 0.72:
					data.terrain_cells[idx] = BattleMapDataLib.Terrain.MOUNTAIN


static func _smooth_terrain_cells(data, passes: int) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var scratch: PackedByteArray = PackedByteArray()
	scratch.resize(w * h)
	for _pass in range(passes):
		for gy in range(h):
			for gx in range(w):
				var counts: Dictionary = {}
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var nx: int = gx + ox
						var ny: int = gy + oy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						var t: int = int(data.terrain_cells[ny * w + nx])
						counts[t] = int(counts.get(t, 0)) + 1
				var best_t: int = BattleMapDataLib.Terrain.GRASS
				var best_n: int = -1
				for t_key in counts.keys():
					var n: int = int(counts[t_key])
					if n > best_n:
						best_n = n
						best_t = int(t_key)
				scratch[gy * w + gx] = best_t
		for i in range(scratch.size()):
			data.terrain_cells[i] = scratch[i]


static func _enforce_terrain_adjacency(data) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			var t: int = int(data.terrain_cells[idx])
			if t == BattleMapDataLib.Terrain.SAND and not _has_neighbor_terrain(data, gx, gy, BattleMapDataLib.Terrain.WATER):
				data.terrain_cells[idx] = BattleMapDataLib.Terrain.GRASS
			if t == BattleMapDataLib.Terrain.MUD and not _has_neighbor_terrain(data, gx, gy, BattleMapDataLib.Terrain.GRASS):
				if _has_neighbor_terrain(data, gx, gy, BattleMapDataLib.Terrain.WATER):
					data.terrain_cells[idx] = BattleMapDataLib.Terrain.SAND
				else:
					data.terrain_cells[idx] = BattleMapDataLib.Terrain.GRASS
			if t == BattleMapDataLib.Terrain.GRASS and _has_neighbor_terrain(data, gx, gy, BattleMapDataLib.Terrain.MOUNTAIN):
				if rng_free_chance(gx, gy) < 0.22:
					data.terrain_cells[idx] = BattleMapDataLib.Terrain.MUD


static func rng_free_chance(_gx: int, _gy: int) -> float:
	return float((_gx * 17 + _gy * 31) % 100) / 100.0


static func _has_neighbor_terrain(data, gx: int, gy: int, terrain_type: int) -> bool:
	var w: int = data.grid_width
	var h: int = data.grid_height
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx: int = gx + ox
			var ny: int = gy + oy
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if int(data.terrain_cells[ny * w + nx]) == terrain_type:
				return true
	return false


static func _paint_border_walls(data) -> void:
	for gy in range(data.grid_height):
		for gx in range(data.grid_width):
			if gx < 2 or gy < 2 or gx >= data.grid_width - 2 or gy >= data.grid_height - 2:
				var idx: int = gy * data.grid_width + gx
				data.terrain_cells[idx] = BattleMapDataLib.Terrain.WATER
				data.terrain_move_cost[idx] = BattleMapDataLib.IMPASSABLE_MOVE_COST
				data.blocked_cells[idx] = 1


static func _apply_cover_noise(data, rng: RandomNumberGenerator) -> void:
	for gy in range(data.grid_height):
		for gx in range(data.grid_width):
			var idx: int = gy * data.grid_width + gx
			if data.blocked_cells[idx] != 0:
				continue
			var t: int = int(data.terrain_cells[idx])
			var cover_chance: float = 0.06
			if t == BattleMapDataLib.Terrain.MOUNTAIN:
				cover_chance = 0.22
			elif t == BattleMapDataLib.Terrain.MUD:
				cover_chance = 0.14
			elif t == BattleMapDataLib.Terrain.SAND:
				cover_chance = 0.04
			if rng.randf() < cover_chance:
				data.cover_cells[idx] = 1


static func _apply_mix_modifiers(data) -> void:
	var mountain_share: float = float(data.terrain_mix.get("mountain", 0.0))
	var mud_share: float = float(data.terrain_mix.get("mud", 0.0))
	var grass_share: float = float(data.terrain_mix.get("grass", 0.0))
	data.approach_speed_mult = clampf(1.2 - mountain_share * 0.55 - mud_share * 0.35, 0.65, 1.2)
	data.defender_bonus = clampf(0.92 + mountain_share * 0.35 + mud_share * 0.12, 0.9, 1.25)
	if grass_share > 0.5:
		data.approach_speed_mult = maxf(data.approach_speed_mult, 1.05)
		data.defender_bonus = minf(data.defender_bonus, 1.0)


static func _aggregate_sector_terrain(data) -> void:
	var sector_cols := 8
	var sector_rows := 6
	var tile_w: int = maxi(1, data.grid_width / sector_cols)
	var tile_h: int = maxi(1, data.grid_height / sector_rows)
	for region in data.regions:
		var col: int = int(region.get("col", 0))
		var row: int = int(region.get("row", 0))
		var counts: Dictionary = {}
		var walkable := 0
		for gy in range(row * tile_h, mini((row + 1) * tile_h, data.grid_height)):
			for gx in range(col * tile_w, mini((col + 1) * tile_w, data.grid_width)):
				if data.is_passable(gx, gy):
					walkable += 1
				var t: int = data.get_cell_terrain(gx, gy)
				var name: String = BattleMapDataLib.TERRAIN_NAMES[t] if t < BattleMapDataLib.TERRAIN_NAMES.size() else "grass"
				counts[name] = int(counts.get(name, 0)) + 1
		region["walkable_score"] = walkable
		region["dominant_terrain"] = _dominant_from_counts(counts)


static func _dominant_from_counts(counts: Dictionary) -> String:
	var best := "grass"
	var best_n := -1
	for key in counts.keys():
		var n: int = int(counts[key])
		if n > best_n:
			best_n = n
			best = str(key)
	return best


static func _define_zones(data) -> void:
	var cell: float = data.cell_size
	var half: Vector2 = data.map_size * 0.5
	var contact_x: float = (float(data.contact_column) + 0.5) * cell - half.x
	data.player_spawn_zone = Rect2(
		Vector2(-half.x + cell * 2, -half.y + cell * 6),
		Vector2(contact_x + cell * 2 - (-half.x + cell * 2), data.map_size.y - cell * 12),
	)
	data.enemy_spawn_zone = Rect2(
		Vector2(contact_x + cell * 2, -half.y + cell * 6),
		Vector2(half.x - cell * 2 - (contact_x + cell * 2), data.map_size.y - cell * 12),
	)
	data.player_spawn_zone = BattleMapPlacementLib.tighten_spawn_zone_to_passable(
		data, data.player_spawn_zone, true
	)
	data.enemy_spawn_zone = BattleMapPlacementLib.tighten_spawn_zone_to_passable(
		data, data.enemy_spawn_zone, false
	)
	BattleMapPlacementLib.build_rally_spawn_cells(data)
	data.extraction_zone = Rect2(
		Vector2(-half.x + cell * 2, -half.y + cell * 2),
		Vector2(cell * 6, cell * 5),
	)


static func _build_regions_and_graph(data, rng: RandomNumberGenerator) -> void:
	var sector_cols := 8
	var sector_rows := 6
	var sw: float = data.map_size.x / float(sector_cols)
	var sh: float = data.map_size.y / float(sector_rows)
	var half: Vector2 = data.map_size * 0.5
	data.regions.clear()
	var graph = data.path_graph
	graph.nodes.clear()
	graph.edges.clear()
	graph.corridor_rects.clear()
	graph.corridor_segments.clear()
	var contact_col_sector: int = sector_cols / 2
	for row in range(sector_rows):
		for col in range(sector_cols):
			var region_id := "sec_%d_%d" % [row, col]
			var center := Vector2(
				(col + 0.5) * sw - half.x,
				(row + 0.5) * sh - half.y,
			)
			var walkable := 0
			var tile_w: int = maxi(1, data.grid_width / sector_cols)
			var tile_h: int = maxi(1, data.grid_height / sector_rows)
			for gy in range(row * tile_h, mini((row + 1) * tile_h, data.grid_height)):
				for gx in range(col * tile_w, mini((col + 1) * tile_w, data.grid_width)):
					if data.is_passable(gx, gy):
						walkable += 1
			var control := BattleMapDataLib.CONTROL_NEUTRAL
			if col < contact_col_sector - 1:
				control = BattleMapDataLib.CONTROL_PLAYER
			elif col > contact_col_sector:
				control = BattleMapDataLib.CONTROL_ENEMY
			var is_objective := false
			data.regions.append({
				"id": region_id,
				"center": center,
				"walkable_score": walkable,
				"control": control,
				"pressure": 0.0,
				"is_objective": is_objective,
				"col": col,
				"row": row,
			})
			graph.nodes[region_id] = center
	for row in range(sector_rows):
		for col in range(sector_cols):
			var id_a := "sec_%d_%d" % [row, col]
			if col + 1 < sector_cols:
				var id_b := "sec_%d_%d" % [row, col + 1]
				graph.edges.append([id_a, id_b])
				graph.edges.append([id_b, id_a])
			if row + 1 < sector_rows:
				var id_c := "sec_%d_%d" % [row + 1, col]
				graph.edges.append([id_a, id_c])
				graph.edges.append([id_c, id_a])


static func cp_count_for_node_type(node_type: String, enemy_strength: int = 500) -> int:
	var nt := node_type.to_lower()
	var base_min := 3
	var base_max := 4
	if nt in ["boss", "major", "elite"]:
		base_min = 6
		base_max = 8
	var bonus := 0
	if enemy_strength >= 800:
		bonus = 1
	return clampi(base_min + bonus, base_min, base_max)


static func _place_capture_points(data, rng: RandomNumberGenerator, node_type: String, enemy_strength: int) -> void:
	data.capture_points.clear()
	var want: int = cp_count_for_node_type(node_type, enemy_strength)
	var placed_positions: Array[Vector2i] = []
	var attempts := 0
	var max_attempts := want * 80
	var contact_gx: int = data.contact_column
	while data.capture_points.size() < want and attempts < max_attempts:
		attempts += 1
		var gx: int = rng.randi_range(CP_EDGE_MARGIN, data.grid_width - CP_EDGE_MARGIN - 1)
		var gy: int = rng.randi_range(CP_EDGE_MARGIN, data.grid_height - CP_EDGE_MARGIN - 1)
		if not data.is_passable(gx, gy):
			continue
		var too_close := false
		for prev in placed_positions:
			var dx: int = gx - prev.x
			var dy: int = gy - prev.y
			if dx * dx + dy * dy < CP_MIN_SPACING_CELLS * CP_MIN_SPACING_CELLS:
				too_close = true
				break
		if too_close:
			continue
		placed_positions.append(Vector2i(gx, gy))
		var owner := BattleMapDataLib.CONTROL_NEUTRAL
		if gx < contact_gx - 6:
			owner = BattleMapDataLib.CONTROL_PLAYER
		elif gx > contact_gx + 6:
			owner = BattleMapDataLib.CONTROL_ENEMY
		var progress: float = 50.0
		if owner == BattleMapDataLib.CONTROL_PLAYER:
			progress = 72.0
		elif owner == BattleMapDataLib.CONTROL_ENEMY:
			progress = 28.0
		var cp_id := "cp_%d" % data.capture_points.size()
		data.capture_points.append({
			"id": cp_id,
			"grid_x": gx,
			"grid_y": gy,
			"world_pos": data.cell_center(gx, gy),
			"radius_cells": CP_RADIUS_CELLS,
			"owner": owner,
			"capture_progress": progress,
			"friendly_power": 0.0,
			"hostile_power": 0.0,
		})
	if data.capture_points.size() < want:
		_fallback_capture_points(data, want, contact_gx)
	data.objective_sectors_required = data.capture_points.size()


static func _fallback_capture_points(data, want: int, contact_gx: int) -> void:
	var cols := [0.22, 0.38, 0.5, 0.62, 0.78]
	var rows := [0.25, 0.42, 0.58, 0.75]
	var cp_index: int = data.capture_points.size()
	for row_t in rows:
		for col_t in cols:
			if cp_index >= want:
				return
			var gx: int = int(col_t * float(data.grid_width - 1))
			var gy: int = int(row_t * float(data.grid_height - 1))
			if not data.is_passable(gx, gy):
				continue
			var owner := BattleMapDataLib.CONTROL_NEUTRAL
			if gx < contact_gx - 4:
				owner = BattleMapDataLib.CONTROL_PLAYER
			elif gx > contact_gx + 4:
				owner = BattleMapDataLib.CONTROL_ENEMY
			var progress: float = 50.0
			if owner == BattleMapDataLib.CONTROL_PLAYER:
				progress = 70.0
			elif owner == BattleMapDataLib.CONTROL_ENEMY:
				progress = 30.0
			data.capture_points.append({
				"id": "cp_%d" % cp_index,
				"grid_x": gx,
				"grid_y": gy,
				"world_pos": data.cell_center(gx, gy),
				"radius_cells": CP_RADIUS_CELLS,
				"owner": owner,
				"capture_progress": progress,
				"friendly_power": 0.0,
				"hostile_power": 0.0,
			})
			cp_index += 1
