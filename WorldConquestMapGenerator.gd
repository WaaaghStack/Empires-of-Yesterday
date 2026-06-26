class_name WorldConquestMapGenerator
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
const WorldMapBakeLib := preload("res://WorldMapBakeLib.gd")


static func generate(map_id: String, run_seed: int):
	var def: Dictionary = WorldMapCatalogLib.get_definition(map_id)
	var w: int = int(def.get("grid_w", WorldConquestConfigLib.GRID_W))
	var h: int = int(def.get("grid_h", WorldConquestConfigLib.GRID_H))
	var land_bits: PackedByteArray = _load_land_bits(def, w, h, run_seed)
	var elev_norm: PackedFloat32Array = _load_elevation_norm(def, w, h, run_seed, land_bits)
	var coast_bits: PackedByteArray = _build_coast_bits(land_bits, w, h)
	var data = BattleMapDataLib.new()
	data.map_seed = run_seed
	data.terrain_tag = str(def.get("terrain_tag", map_id))
	data.terrain_mix = {"grass": 0.5, "water": 0.35, "mountain": 0.08, "sand": 0.05, "mud": 0.02}
	data.grid_width = w
	data.grid_height = h
	data.cell_size = WorldConquestConfigLib.CELL_SIZE
	data.map_size = Vector2(float(w), float(h))
	data.player_allocation = WorldConquestConfigLib.PLAYER_FORCE
	data.enemy_allocation = WorldConquestConfigLib.ENEMY_FORCE
	data.node_id = "world_conquest"
	data.node_type = "world_conquest"
	data.mass_unit_mode = false
	data.contact_column = w / 2
	data.objective_sectors_required = 0
	data.placed_structures = []
	data.bridge_corridors = []
	data.resource_deposits = []
	var total: int = w * h
	data.terrain_cells = PackedByteArray()
	data.terrain_cells.resize(total)
	data.cover_cells = PackedByteArray()
	data.cover_cells.resize(total)
	data.blocked_cells = PackedByteArray()
	data.blocked_cells.resize(total)
	data.tile_height = PackedFloat32Array()
	data.tile_height.resize(total)
	for gy in range(h):
		for gx in range(w):
			var idx: int = data.cell_index(gx, gy)
			var land: bool = land_bits[idx] > 0
			var elev: float = elev_norm[idx]
			if not land:
				data.terrain_cells[idx] = BattleMapDataLib.Terrain.WATER
				data.tile_height[idx] = 0.0
			elif elev > 0.72:
				data.terrain_cells[idx] = BattleMapDataLib.Terrain.MOUNTAIN
				data.tile_height[idx] = elev
			elif elev < 0.22 and coast_bits[idx] > 0:
				data.terrain_cells[idx] = BattleMapDataLib.Terrain.SAND
				data.tile_height[idx] = elev * 0.5
			else:
				data.terrain_cells[idx] = BattleMapDataLib.Terrain.GRASS
				data.tile_height[idx] = elev * 0.65
	data.rebuild_terrain_arrays()
	data.sync_blocked_from_terrain()
	_place_spawns_and_capitals(data, land_bits, run_seed, str(def.get("spawn_mode", "west_east")))
	_scatter_resource_blobs(data, run_seed)
	return data


static func globe_colors_for_map(map_id: String) -> Dictionary:
	var def: Dictionary = WorldMapCatalogLib.get_definition(map_id)
	return {
		"ocean": def.get("globe_ocean", Color(0.05, 0.18, 0.42)),
		"land": def.get("globe_land", Color(0.34, 0.52, 0.28)),
		"mountain": def.get("globe_mountain", Color(0.48, 0.44, 0.38)),
		"sand": def.get("globe_sand", Color(0.72, 0.64, 0.38)),
	}


static func _load_land_bits(def: Dictionary, w: int, h: int, seed_val: int) -> PackedByteArray:
	var path: String = str(def.get("land_mask_path", ""))
	if path != "":
		var loaded: Dictionary = WorldMapBakeLib.read_land_bin(path)
		if not loaded.is_empty():
			var bits: PackedByteArray = loaded.get("land_bits", PackedByteArray())
			if int(loaded.get("grid_w", 0)) == w and int(loaded.get("grid_h", 0)) == h:
				return bits
	var map_id: String = str(def.get("id", WorldMapCatalogLib.MAP_EARTH))
	if map_id == WorldMapCatalogLib.MAP_EARTH:
		return WorldMapBakeLib.generate_earth_land_bits(w, h)
	return _procedural_placeholder_land(w, h, seed_val)


static func _load_elevation_norm(
	def: Dictionary, w: int, h: int, seed_val: int, land_bits: PackedByteArray
) -> PackedFloat32Array:
	var path: String = str(def.get("elevation_path", ""))
	if path != "":
		var loaded: Dictionary = WorldMapBakeLib.read_elev_bin(path)
		if not loaded.is_empty():
			var elev: PackedFloat32Array = loaded.get("elevation", PackedFloat32Array())
			if int(loaded.get("grid_w", 0)) == w and int(loaded.get("grid_h", 0)) == h:
				return _apply_elev_seed_noise(elev, land_bits, seed_val)
	var map_id: String = str(def.get("id", WorldMapCatalogLib.MAP_EARTH))
	if map_id == WorldMapCatalogLib.MAP_EARTH:
		return _apply_elev_seed_noise(
			WorldMapBakeLib.generate_earth_elevation_norm(w, h, land_bits), land_bits, seed_val
		)
	return _procedural_elevation(w, h, seed_val, land_bits)


static func _apply_elev_seed_noise(
	elev: PackedFloat32Array, land_bits: PackedByteArray, seed_val: int
) -> PackedFloat32Array:
	var out: PackedFloat32Array = elev.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x5A17E4
	for i in out.size():
		if land_bits[i] == 0:
			out[i] = 0.0
			continue
		out[i] = clampf(out[i] + rng.randf_range(-0.05, 0.07), 0.0, 1.0)
	return out


static func _procedural_elevation(
	w: int, h: int, seed_val: int, land_bits: PackedByteArray
) -> PackedFloat32Array:
	var elev := PackedFloat32Array()
	elev.resize(w * h)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x5A17E4
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		for gx in range(w):
			var idx: int = gy * w + gx
			if land_bits[idx] == 0:
				elev[idx] = 0.0
				continue
			var base: float = 0.25 + 0.35 * absf(sin(lat * 2.0))
			base += rng.randf_range(-0.08, 0.12)
			elev[idx] = clampf(base, 0.0, 1.0)
	return elev


static func _procedural_placeholder_land(w: int, h: int, seed_val: int) -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(w * h)
	bits.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		for gx in range(w):
			var lon: float = float(gx) / float(w) * TAU - PI
			var n: float = rng.randf_range(-0.1, 0.1)
			var v: float = exp(-((lon / 0.9) ** 2 + (lat / 0.5) ** 2)) + n
			if v > 0.35:
				bits[gy * w + gx] = 1
	return bits


static func _build_coast_bits(land_bits: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var coast := PackedByteArray()
	coast.resize(w * h)
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			if land_bits[idx] == 0:
				coast[idx] = 0
				continue
			var is_coast: bool = false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = gx + dx
					var ny: int = gy + dy
					if ny < 0 or ny >= h:
						is_coast = true
						break
					if nx < 0:
						nx = w - 1
					elif nx >= w:
						nx = 0
					if land_bits[ny * w + nx] == 0:
						is_coast = true
						break
				if is_coast:
					break
			coast[idx] = 1 if is_coast else 0
	return coast


static func _place_spawns_and_capitals(
	data, land_bits: PackedByteArray, seed_val: int, spawn_mode: String
) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xE471
	var west_cells: Array[Vector2i] = []
	var east_cells: Array[Vector2i] = []
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			if land_bits[idx] == 0 or not data.is_land_cell(gx, gy):
				continue
			if spawn_mode == "west_east":
				if gx < w / 3:
					west_cells.append(Vector2i(gx, gy))
				elif gx > w * 2 / 3:
					east_cells.append(Vector2i(gx, gy))
			else:
				west_cells.append(Vector2i(gx, gy))
				east_cells.append(Vector2i(gx, gy))
	var player: Vector2i = _pick_cell(west_cells, rng)
	var enemy: Vector2i = _pick_cell(east_cells, rng)
	if player.x < 0:
		player = _pick_cell(_all_land(data, land_bits), rng)
	if enemy.x < 0:
		enemy = _pick_cell(_all_land(data, land_bits), rng)
	data.player_home_grid = player
	data.enemy_home_grid = enemy
	data.player_capital_grid = player
	data.enemy_capital_grid = enemy
	var psz: float = float(w) * 0.08
	var esz: float = float(w) * 0.08
	data.player_spawn_zone = Rect2(
		float(player.x) - psz, float(player.y) - psz, psz * 2.0, psz * 2.0
	)
	data.enemy_spawn_zone = Rect2(
		float(enemy.x) - esz, float(enemy.y) - esz, esz * 2.0, esz * 2.0
	)
	data.player_spawn_cells = [player]
	data.enemy_spawn_cells = [enemy]


static func _all_land(data, land_bits: PackedByteArray) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var w: int = data.grid_width
	for gy in range(data.grid_height):
		for gx in range(data.grid_width):
			if land_bits[gy * w + gx] > 0 and data.is_land_cell(gx, gy):
				out.append(Vector2i(gx, gy))
	return out


static func _pick_cell(cells: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	if cells.is_empty():
		return Vector2i(-1, -1)
	return cells[rng.randi_range(0, cells.size() - 1)]


static func _scatter_resource_blobs(data, seed_val: int) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var rng := RandomNumberGenerator.new()
	var placed_centers: Array[Vector2i] = []
	var next_id: int = 1
	for type_i in range(WorldConquestConfigLib.RESOURCE_TYPE_COUNT):
		rng.seed = seed_val ^ (0xB10B0000 + type_i * 0x9E37)
		var terrain_want: int = _terrain_for_resource_type(type_i)
		var candidates: Array[Vector2i] = []
		for gy in range(h):
			for gx in range(w):
				if not data.is_land_cell(gx, gy):
					continue
				if int(data.get_cell_terrain(gx, gy)) != terrain_want:
					continue
				if _too_close_to_spawn(data, gx, gy):
					continue
				candidates.append(Vector2i(gx, gy))
		var tries: int = 0
		var placed: int = 0
		while placed < WorldConquestConfigLib.RESOURCE_BLOBS_PER_TYPE and tries < 8000:
			tries += 1
			if candidates.is_empty():
				break
			var center: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
			if _too_close_to_blob(center, placed_centers):
				continue
			var size_tier: int = rng.randi_range(1, 3)
			var blob: Dictionary = _grow_resource_blob(
				data, center, size_tier, type_i, next_id, w, h, rng
			)
			if blob.is_empty():
				continue
			data.resource_deposits.append(blob)
			placed_centers.append(center)
			next_id += 1
			placed += 1


static func _terrain_for_resource_type(type_i: int) -> int:
	match type_i:
		1:
			return BattleMapDataLib.Terrain.MOUNTAIN
		2:
			return BattleMapDataLib.Terrain.SAND
		_:
			return BattleMapDataLib.Terrain.GRASS


static func _too_close_to_spawn(data, gx: int, gy: int) -> bool:
	var spots: Array[Vector2i] = [data.player_home_grid, data.enemy_home_grid]
	for spot in spots:
		if spot.x < 0:
			continue
		var dx: int = absi(gx - spot.x)
		dx = mini(dx, data.grid_width - dx)
		var dy: int = absi(gy - spot.y)
		if dx * dx + dy * dy < WorldConquestConfigLib.RESOURCE_SPAWN_EXCLUSION ** 2:
			return true
	return false


static func _too_close_to_blob(center: Vector2i, placed: Array[Vector2i]) -> bool:
	var min_d2: int = WorldConquestConfigLib.RESOURCE_BLOB_MIN_SPACING ** 2
	for other in placed:
		var dx: int = absi(center.x - other.x)
		var dy: int = absi(center.y - other.y)
		if dx * dx + dy * dy < min_d2:
			return true
	return false


static func _grow_resource_blob(
	data,
	center: Vector2i,
	size_tier: int,
	type_i: int,
	dep_id: int,
	w: int,
	h: int,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var want: int = int(data.get_cell_terrain(center.x, center.y))
	var target_n: int = WorldConquestConfigLib.RESOURCE_BLOB_CELL_COUNT[size_tier]
	var keys := PackedInt32Array()
	var queue: Array[Vector2i] = [center]
	var seen: Dictionary = {center: true}
	while not queue.is_empty() and keys.size() < target_n:
		var cur: Vector2i = queue.pop_front()
		if not data.is_land_cell(cur.x, cur.y):
			continue
		if int(data.get_cell_terrain(cur.x, cur.y)) != want:
			continue
		keys.append(cur.y * w + cur.x)
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		]
		dirs.shuffle()
		for d in dirs:
			var nx: int = cur.x + d.x
			var ny: int = cur.y + d.y
			if ny < 0 or ny >= h:
				continue
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
			var nxt := Vector2i(nx, ny)
			if seen.has(nxt):
				continue
			if rng.randf() > 0.62:
				continue
			seen[nxt] = true
			queue.append(nxt)
	if keys.size() < 3:
		return {}
	return {
		"id": dep_id,
		"type": type_i,
		"gx": center.x,
		"gy": center.y,
		"size": size_tier,
		"yield_per_sec": WorldConquestConfigLib.RESOURCE_YIELD_BY_SIZE[size_tier],
		"cell_keys": keys,
	}
