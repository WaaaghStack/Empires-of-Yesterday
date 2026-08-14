class_name WorldConquestMapGenerator
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
const WorldMapBakeLib := preload("res://WorldMapBakeLib.gd")
const SphereGridLibScript := preload("res://SphereGridLib.gd")
const WorldPackLibScript := preload("res://WorldPackLib.gd")


## Optional criteria (Custom World): land_bias, resource_density, mountain_bias, start_region,
## procedural (true → continental noise land, not Earth mask).
static func generate(
	map_id: String, run_seed: int, place_spawns: bool = true, criteria: Dictionary = {}
):
	var crit: Dictionary = _normalize_criteria(criteria)
	if WorldConquestConfigLib.SPHERE_GRID_ENABLED:
		return _generate_sphere(map_id, run_seed, place_spawns, crit)
	return _generate_rect(map_id, run_seed, place_spawns, crit)


static func _normalize_criteria(criteria: Dictionary) -> Dictionary:
	return {
		"land_bias": clampf(float(criteria.get("land_bias", 0.0)), -1.0, 1.0),
		"resource_density": clampf(float(criteria.get("resource_density", 1.0)), 0.25, 2.0),
		"mountain_bias": clampf(float(criteria.get("mountain_bias", 0.0)), -1.0, 1.0),
		"start_region": _normalize_start_region(str(criteria.get("start_region", "any"))),
		"procedural": bool(criteria.get("procedural", false)),
	}


static func _normalize_start_region(region: String) -> String:
	match region:
		"west", "east":
			return region
		_:
			return "any"


static func _mountain_threshold(mountain_bias: float) -> float:
	# Default 0.72; +bias → more mountains (lower threshold), −bias → fewer.
	return clampf(0.72 - mountain_bias * 0.18, 0.48, 0.88)


static func _resource_blob_target(resource_density: float) -> int:
	return maxi(
		1,
		int(round(float(WorldConquestConfigLib.RESOURCE_BLOBS_PER_TYPE) * resource_density))
	)


static func apply_player_spawn_sphere(data, cell_id: int) -> void:
	if cell_id < 0 or not data.is_land_cell_id(cell_id):
		push_error("WorldConquestMapGenerator: apply_player_spawn_sphere requires land cell_id")
		return
	_set_player_home(data, Vector2i(cell_id, 0))


static func apply_player_spawn(data, grid: Vector2i) -> void:
	if data.sphere_mode:
		apply_player_spawn_sphere(data, grid.x)
	else:
		if not data.is_land_cell(grid.x, grid.y):
			push_error("WorldConquestMapGenerator: apply_player_spawn requires land cell")
			return
		_set_player_home(data, grid)


static func apply_enemy_furthest_from_player(data) -> void:
	if data.player_home_grid.x < 0:
		push_error("WorldConquestMapGenerator: player home unset before enemy deploy")
		return
	var enemy: Vector2i
	if data.sphere_mode:
		var land_cells: Array[int] = _collect_land_cell_ids_sphere(data)
		if land_cells.is_empty():
			enemy = data.player_home_grid
		else:
			var enemy_cid: int = _furthest_land_cell(
				data.cell_positions, land_cells, data.player_home_grid.x
			)
			enemy = Vector2i(enemy_cid, 0)
	else:
		var land_cells_rect: Array[Vector2i] = _collect_land_cells_rect(data)
		if land_cells_rect.is_empty():
			enemy = data.player_home_grid
		else:
			enemy = _furthest_land_cell_rect(data, land_cells_rect, data.player_home_grid)
	_set_enemy_home(data, enemy)


static func pick_random_land_spawn(
	data, seed_val: int, start_region: String = "any"
) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xCA917A1
	var region: String = _normalize_start_region(start_region)
	if data.sphere_mode:
		var land_cells: Array[int] = _filter_land_ids_by_region(
			_collect_land_cell_ids_sphere(data), data, region
		)
		if land_cells.is_empty():
			land_cells = _collect_land_cell_ids_sphere(data)
		if land_cells.is_empty():
			return Vector2i(-1, -1)
		return Vector2i(land_cells[rng.randi_range(0, land_cells.size() - 1)], 0)
	var land_cells_rect: Array[Vector2i] = _filter_land_rect_by_region(
		_collect_land_cells_rect(data), data, region
	)
	if land_cells_rect.is_empty():
		land_cells_rect = _collect_land_cells_rect(data)
	if land_cells_rect.is_empty():
		return Vector2i(-1, -1)
	return land_cells_rect[rng.randi_range(0, land_cells_rect.size() - 1)]


static func _filter_land_ids_by_region(
	land_cells: Array[int], data, region: String
) -> Array[int]:
	if region == "any" or land_cells.is_empty():
		return land_cells
	var out: Array[int] = []
	for cid in land_cells:
		var lon: float = float(data.cell_lon[cid])
		if region == "west" and lon < 0.0:
			out.append(cid)
		elif region == "east" and lon >= 0.0:
			out.append(cid)
	return out


static func _filter_land_rect_by_region(
	land_cells: Array[Vector2i], data, region: String
) -> Array[Vector2i]:
	if region == "any" or land_cells.is_empty():
		return land_cells
	var w: int = data.grid_width
	var out: Array[Vector2i] = []
	for cell in land_cells:
		if region == "west" and cell.x < w / 2:
			out.append(cell)
		elif region == "east" and cell.x >= w / 2:
			out.append(cell)
	return out


static func _generate_rect(
	map_id: String, run_seed: int, place_spawns: bool, criteria: Dictionary
):
	var def: Dictionary = WorldMapCatalogLib.get_definition(map_id)
	var w: int = int(def.get("grid_w", WorldConquestConfigLib.GRID_W))
	var h: int = int(def.get("grid_h", WorldConquestConfigLib.GRID_H))
	var land_bias: float = float(criteria.get("land_bias", 0.0))
	var mountain_bias: float = float(criteria.get("mountain_bias", 0.0))
	var resource_density: float = float(criteria.get("resource_density", 1.0))
	var procedural: bool = bool(criteria.get("procedural", false))
	var land_bits: PackedByteArray
	var elev_norm: PackedFloat32Array
	if procedural:
		land_bits = _procedural_continental_land(w, h, run_seed, land_bias)
		elev_norm = _procedural_elevation(w, h, run_seed, land_bits)
		elev_norm = _apply_mountain_elev_bias(elev_norm, land_bits, mountain_bias)
	else:
		land_bits = _load_land_bits(def, w, h, run_seed)
		land_bits = _apply_land_bias(land_bits, w, h, run_seed, land_bias)
		elev_norm = _load_elevation_norm(def, w, h, run_seed, land_bits)
		elev_norm = _apply_mountain_elev_bias(elev_norm, land_bits, mountain_bias)
	var coast_bits: PackedByteArray = _build_coast_bits(land_bits, w, h)
	var mt_thresh: float = _mountain_threshold(mountain_bias)
	var data = BattleMapDataLib.new()
	data.map_seed = run_seed
	data.terrain_tag = str(def.get("terrain_tag", map_id))
	if procedural:
		data.pack_visual_tag = _procedural_pack_visual_tag(land_bias, mountain_bias)
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
			elif elev > mt_thresh:
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
	if place_spawns:
		_place_spawns_and_capitals(data, land_bits, run_seed, str(def.get("spawn_mode", "west_east")))
	else:
		_init_unset_homes(data)
	_scatter_resource_blobs(data, run_seed, resource_density)
	return data


static func _generate_sphere(
	map_id: String, run_seed: int, place_spawns: bool, criteria: Dictionary
):
	var def: Dictionary = WorldMapCatalogLib.get_definition(map_id)
	var ow: int = int(def.get("grid_w", WorldConquestConfigLib.GRID_W))
	var oh: int = int(def.get("grid_h", WorldConquestConfigLib.GRID_H))
	var frequency: int = WorldConquestConfigLib.SPHERE_GRID_FREQUENCY
	var land_bias: float = float(criteria.get("land_bias", 0.0))
	var mountain_bias: float = float(criteria.get("mountain_bias", 0.0))
	var resource_density: float = float(criteria.get("resource_density", 1.0))
	var procedural: bool = bool(criteria.get("procedural", false))

	var grid: Dictionary = WorldPackLibScript.load_or_build_sphere_grid(frequency)
	var cell_count: int = int(grid.cell_count)

	var land_bits: PackedByteArray
	var elev_base: PackedFloat32Array
	if procedural:
		# True random continents — never Earth land.bin / generate_earth_land_bits.
		land_bits = _procedural_continental_land(ow, oh, run_seed, land_bias)
		elev_base = _procedural_elevation(ow, oh, run_seed, land_bits)
		elev_base = _apply_mountain_elev_bias(elev_base, land_bits, mountain_bias)
	else:
		land_bits = _load_land_bits(def, ow, oh, run_seed)
		land_bits = _apply_land_bias(land_bits, ow, oh, run_seed, land_bias)
		elev_base = _load_elevation_norm_base(def, ow, oh, run_seed, land_bits)
		elev_base = _apply_mountain_elev_bias(elev_base, land_bits, mountain_bias)
	# Canonical Earth pack is bias≈0 only; procedural / biased land must not use shared cache.
	var use_pack_cache: bool = (
		not procedural
		and absf(land_bias) < 0.001
		and absf(mountain_bias) < 0.001
	)
	var cached: Dictionary = {}
	if use_pack_cache:
		cached = WorldPackLibScript.try_load_world_cells(map_id, frequency)
	var cell_land: PackedByteArray
	var cell_elev: PackedFloat32Array
	if (
		cached.is_empty()
		or cached.cell_land.size() != cell_count
		or cached.cell_elev.size() != cell_count
	):
		cell_land = SphereGridLibScript.sample_land_bits(grid, land_bits, ow, oh)
		cell_elev = SphereGridLibScript.sample_elevation(grid, elev_base, ow, oh)
		if use_pack_cache:
			WorldPackLibScript.save_world_cells(map_id, frequency, cell_land, cell_elev)
	else:
		cell_land = cached.cell_land
		cell_elev = cached.cell_elev
	cell_elev = _apply_elev_seed_noise_cells(cell_elev, cell_land, run_seed)
	var cell_coast: PackedByteArray = _build_coast_bits_sphere(cell_land, grid)
	var mt_thresh: float = _mountain_threshold(mountain_bias)

	var data = BattleMapDataLib.new()
	data.sphere_mode = true
	data.sphere_frequency = frequency
	data.cell_count = cell_count
	data.overlay_width = ow
	data.overlay_height = oh
	data.grid_width = ow
	data.grid_height = oh
	data.cell_positions = grid.positions
	data.cell_lat = grid.lat
	data.cell_lon = grid.lon
	data.neighbors = grid.neighbors
	data.neighbor_counts = grid.neighbor_count
	data.sphere_faces = grid.faces
	data.equirect_to_cell = WorldPackLibScript.load_or_build_equirect_lut(grid, ow, oh)

	data.map_seed = run_seed
	data.terrain_tag = str(def.get("terrain_tag", map_id))
	if procedural:
		data.pack_visual_tag = _procedural_pack_visual_tag(land_bias, mountain_bias)
	data.terrain_mix = {"grass": 0.5, "water": 0.35, "mountain": 0.08, "sand": 0.05, "mud": 0.02}
	data.cell_size = WorldConquestConfigLib.CELL_SIZE
	data.map_size = Vector2(float(ow), float(oh))
	data.player_allocation = WorldConquestConfigLib.PLAYER_FORCE
	data.enemy_allocation = WorldConquestConfigLib.ENEMY_FORCE
	data.node_id = "world_conquest"
	data.node_type = "world_conquest"
	data.mass_unit_mode = false
	data.contact_column = ow / 2
	data.objective_sectors_required = 0
	data.placed_structures = []
	data.bridge_corridors = []
	data.resource_deposits = []

	data.terrain_cells = PackedByteArray()
	data.terrain_cells.resize(cell_count)
	data.cover_cells = PackedByteArray()
	data.cover_cells.resize(cell_count)
	data.blocked_cells = PackedByteArray()
	data.blocked_cells.resize(cell_count)
	data.tile_height = PackedFloat32Array()
	data.tile_height.resize(cell_count)

	for cid in range(cell_count):
		var land: bool = cell_land[cid] > 0
		var elev: float = cell_elev[cid]
		if not land:
			data.terrain_cells[cid] = BattleMapDataLib.Terrain.WATER
			data.tile_height[cid] = 0.0
		elif elev > mt_thresh:
			data.terrain_cells[cid] = BattleMapDataLib.Terrain.MOUNTAIN
			data.tile_height[cid] = elev
		elif elev < 0.22 and cell_coast[cid] > 0:
			data.terrain_cells[cid] = BattleMapDataLib.Terrain.SAND
			data.tile_height[cid] = elev * 0.5
		else:
			data.terrain_cells[cid] = BattleMapDataLib.Terrain.GRASS
			data.tile_height[cid] = elev * 0.65

	data.rebuild_terrain_arrays()
	data.sync_blocked_from_terrain()
	if place_spawns:
		_place_sphere_spawns(data, cell_land, grid, run_seed)
	else:
		_init_unset_homes(data)
	_scatter_resource_blobs_sphere(data, run_seed, resource_density)
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


static func _load_elevation_norm_base(
	def: Dictionary, w: int, h: int, _seed_val: int, land_bits: PackedByteArray
) -> PackedFloat32Array:
	var path: String = str(def.get("elevation_path", ""))
	if path != "":
		var loaded: Dictionary = WorldMapBakeLib.read_elev_bin(path)
		if not loaded.is_empty():
			var elev: PackedFloat32Array = loaded.get("elevation", PackedFloat32Array())
			if int(loaded.get("grid_w", 0)) == w and int(loaded.get("grid_h", 0)) == h:
				return elev
	var map_id: String = str(def.get("id", WorldMapCatalogLib.MAP_EARTH))
	if map_id == WorldMapCatalogLib.MAP_EARTH:
		return WorldMapBakeLib.generate_earth_elevation_norm(w, h, land_bits)
	return _procedural_elevation(w, h, _seed_val, land_bits)


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


## Grow/shrink coasts from the canonical (or procedural) mask. |bias|≈0 is a no-op.
static func _apply_land_bias(
	land_bits: PackedByteArray, w: int, h: int, seed_val: int, bias: float
) -> PackedByteArray:
	if absf(bias) < 0.001:
		return land_bits
	var bits: PackedByteArray = land_bits.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x14A1DB15
	var grow: bool = bias > 0.0
	var strength: float = absf(bias)
	var passes: int = clampi(int(ceil(strength * 3.0)), 1, 3)
	for _pass in range(passes):
		var next: PackedByteArray = bits.duplicate()
		for gy in range(h):
			for gx in range(w):
				var idx: int = gy * w + gx
				var is_land: bool = bits[idx] > 0
				if grow and is_land:
					continue
				if not grow and not is_land:
					continue
				var land_n: int = 0
				var water_n: int = 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx: int = gx + dx
						var ny: int = gy + dy
						if ny < 0 or ny >= h:
							water_n += 1
							continue
						if nx < 0:
							nx = w - 1
						elif nx >= w:
							nx = 0
						if bits[ny * w + nx] > 0:
							land_n += 1
						else:
							water_n += 1
				if grow:
					# Ocean cell adjacent to land → chance to become land.
					if land_n <= 0:
						continue
					var p_grow: float = strength * (0.18 + 0.12 * float(land_n) / 8.0)
					if rng.randf() < p_grow:
						next[idx] = 1
				else:
					# Land cell adjacent to water → chance to become ocean.
					if water_n <= 0:
						continue
					var p_shrink: float = strength * (0.18 + 0.12 * float(water_n) / 8.0)
					if rng.randf() < p_shrink:
						next[idx] = 0
		bits = next
	WorldMapBakeLib.sanitize_land_mask(bits, w, h)
	return bits


static func _apply_mountain_elev_bias(
	elev: PackedFloat32Array, land_bits: PackedByteArray, mountain_bias: float
) -> PackedFloat32Array:
	if absf(mountain_bias) < 0.001:
		return elev
	var out: PackedFloat32Array = elev.duplicate()
	var delta: float = mountain_bias * 0.12
	for i in out.size():
		if land_bits[i] == 0:
			out[i] = 0.0
			continue
		out[i] = clampf(out[i] + delta, 0.0, 1.0)
	return out


static func _apply_elev_seed_noise_cells(
	cell_elev: PackedFloat32Array, cell_land: PackedByteArray, seed_val: int
) -> PackedFloat32Array:
	var out: PackedFloat32Array = cell_elev.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x5A17E4
	for i in out.size():
		if cell_land[i] == 0:
			out[i] = 0.0
			continue
		out[i] = clampf(out[i] + rng.randf_range(-0.05, 0.07), 0.0, 1.0)
	return out


static func _procedural_elevation(
	w: int, h: int, seed_val: int, land_bits: PackedByteArray
) -> PackedFloat32Array:
	var elev := PackedFloat32Array()
	elev.resize(w * h)
	var ridge := FastNoiseLite.new()
	ridge.seed = seed_val ^ 0x5A17E4
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.frequency = 0.035
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	ridge.fractal_lacunarity = 2.0
	ridge.fractal_gain = 0.5
	var warp := FastNoiseLite.new()
	warp.seed = seed_val ^ 0xE17
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 0.02
	warp.fractal_octaves = 2
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		var cos_lat: float = cos(lat)
		var sin_lat: float = sin(lat)
		for gx in range(w):
			var idx: int = gy * w + gx
			if land_bits[idx] == 0:
				elev[idx] = 0.0
				continue
			var lon: float = float(gx) / float(w) * TAU - PI
			var px: float = cos_lat * cos(lon)
			var py: float = sin_lat
			var pz: float = cos_lat * sin(lon)
			var scale: float = 48.0
			var n: float = ridge.get_noise_3d(px * scale, py * scale, pz * scale)
			var wiggle: float = warp.get_noise_3d(px * 24.0, py * 24.0, pz * 24.0) * 0.12
			# Map ~[-1,1] → inland elevation; coasts stay lower via later sand rule.
			var base: float = 0.28 + 0.42 * clampf(0.5 + 0.5 * n + wiggle, 0.0, 1.0)
			elev[idx] = clampf(base, 0.0, 1.0)
	return elev


## Multi-octave continental noise on the unit sphere (seamless lon wrap). land_bias shifts
## the land threshold: +1 → more land, −1 → more ocean. Not Earth-shaped.
static func _procedural_continental_land(
	w: int, h: int, seed_val: int, land_bias: float = 0.0
) -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(w * h)
	bits.fill(0)
	var continents := FastNoiseLite.new()
	continents.seed = seed_val
	continents.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continents.frequency = 0.012
	continents.fractal_type = FastNoiseLite.FRACTAL_FBM
	continents.fractal_octaves = 5
	continents.fractal_lacunarity = 2.15
	continents.fractal_gain = 0.52
	var detail := FastNoiseLite.new()
	detail.seed = seed_val ^ 0xA5A5C0DE
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.045
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 3
	detail.fractal_lacunarity = 2.0
	detail.fractal_gain = 0.5
	# Bias≈0 targets ~28–35% land; ±1 swings several percentage points.
	var threshold: float = 0.08 - clampf(land_bias, -1.0, 1.0) * 0.20
	var scale: float = 72.0
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		var cos_lat: float = cos(lat)
		var sin_lat: float = sin(lat)
		# Mild polar ocean bias so ice-caps are not solid continents.
		var pole_push: float = pow(absf(sin_lat), 2.4) * 0.12
		for gx in range(w):
			var lon: float = float(gx) / float(w) * TAU - PI
			var px: float = cos_lat * cos(lon)
			var py: float = sin_lat
			var pz: float = cos_lat * sin(lon)
			var n: float = continents.get_noise_3d(px * scale, py * scale, pz * scale)
			var d: float = detail.get_noise_3d(px * scale * 2.4, py * scale * 2.4, pz * scale * 2.4)
			var v: float = n + d * 0.28 - pole_push
			if v > threshold:
				bits[gy * w + gx] = 1
	WorldMapBakeLib.sanitize_land_mask(bits, w, h)
	return bits


static func _procedural_pack_visual_tag(land_bias: float, mountain_bias: float) -> String:
	return "p_lb%d_mb%d" % [int(round(land_bias * 100.0)), int(round(mountain_bias * 100.0))]


static func _procedural_placeholder_land(w: int, h: int, seed_val: int) -> PackedByteArray:
	# Legacy non-Earth catalog fallback — route through continental generator.
	return _procedural_continental_land(w, h, seed_val, 0.0)


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


static func _build_coast_bits_sphere(
	cell_land: PackedByteArray, grid: Dictionary
) -> PackedByteArray:
	var cell_count: int = int(grid.cell_count)
	var coast := PackedByteArray()
	coast.resize(cell_count)
	var neighbors: PackedInt32Array = grid.neighbors
	var neighbor_counts: PackedByteArray = grid.neighbor_count

	for cid in range(cell_count):
		if cell_land[cid] == 0:
			coast[cid] = 0
			continue
		var is_coast: bool = false
		var ncount: int = int(neighbor_counts[cid])
		var base: int = cid * 6
		for slot in range(ncount):
			var nbr: int = neighbors[base + slot]
			if nbr < 0 or nbr >= cell_count:
				continue
			if cell_land[nbr] == 0:
				is_coast = true
				break
		coast[cid] = 1 if is_coast else 0
	return coast


static func _init_unset_homes(data) -> void:
	data.player_home_grid = Vector2i(-1, -1)
	data.enemy_home_grid = Vector2i(-1, -1)
	data.player_capital_grid = Vector2i(-1, -1)
	data.enemy_capital_grid = Vector2i(-1, -1)
	data.player_spawn_cells = []
	data.enemy_spawn_cells = []
	data.player_spawn_zone = Rect2()
	data.enemy_spawn_zone = Rect2()


static func _set_player_home(data, grid: Vector2i) -> void:
	data.player_home_grid = grid
	data.player_capital_grid = grid
	var psz: float = 8.0 if data.sphere_mode else float(data.grid_width) * 0.08
	data.player_spawn_zone = Rect2(
		float(grid.x) - psz, float(grid.y) - psz, psz * 2.0, psz * 2.0
	)
	data.player_spawn_cells = [grid]


static func _set_enemy_home(data, grid: Vector2i) -> void:
	data.enemy_home_grid = grid
	data.enemy_capital_grid = grid
	var esz: float = 8.0 if data.sphere_mode else float(data.grid_width) * 0.08
	data.enemy_spawn_zone = Rect2(
		float(grid.x) - esz, float(grid.y) - esz, esz * 2.0, esz * 2.0
	)
	data.enemy_spawn_cells = [grid]


static func _collect_land_cell_ids_sphere(data) -> Array[int]:
	var out: Array[int] = []
	for cid in range(data.cell_count):
		if data.is_land_cell_id(cid):
			out.append(cid)
	return out


static func _collect_land_cells_rect(data) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for gy in range(data.grid_height):
		for gx in range(data.grid_width):
			if data.is_land_cell(gx, gy):
				out.append(Vector2i(gx, gy))
	return out


static func _furthest_land_cell_rect(
	data, land_cells: Array[Vector2i], from: Vector2i
) -> Vector2i:
	var best: Vector2i = from
	var best_d2: int = 0
	var w: int = data.grid_width
	for cell in land_cells:
		var dx: int = absi(cell.x - from.x)
		dx = mini(dx, w - dx)
		var dy: int = absi(cell.y - from.y)
		var d2: int = dx * dx + dy * dy
		if d2 > best_d2:
			best_d2 = d2
			best = cell
	return best


static func _place_sphere_spawns(
	data, cell_land: PackedByteArray, grid: Dictionary, seed_val: int
) -> void:
	var positions: PackedVector3Array = grid.positions
	var cell_count: int = int(grid.cell_count)
	var land_cells: Array[int] = []
	for cid in range(cell_count):
		if cell_land[cid] > 0 and data.is_land_cell_id(cid):
			land_cells.append(cid)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xE471

	var player_cid: int = -1
	var enemy_cid: int = -1
	if land_cells.is_empty():
		player_cid = 0
		enemy_cid = 0
	else:
		player_cid = land_cells[rng.randi_range(0, land_cells.size() - 1)]
		enemy_cid = _furthest_land_cell(positions, land_cells, player_cid)
		player_cid = _furthest_land_cell(positions, land_cells, enemy_cid)

	var player := Vector2i(player_cid, 0)
	var enemy := Vector2i(enemy_cid, 0)
	_set_player_home(data, player)
	_set_enemy_home(data, enemy)


static func _furthest_land_cell(
	positions: PackedVector3Array, land_cells: Array[int], from_cid: int
) -> int:
	var from_pos: Vector3 = positions[from_cid]
	var best_cid: int = from_cid
	var min_dot: float = 2.0
	for cid in land_cells:
		var dot: float = from_pos.dot(positions[cid])
		if dot < min_dot:
			min_dot = dot
			best_cid = cid
	return best_cid


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
	_set_player_home(data, player)
	_set_enemy_home(data, enemy)


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


static func _scatter_resource_blobs(
	data, seed_val: int, resource_density: float = 1.0
) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var blob_target: int = _resource_blob_target(resource_density)
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
		while placed < blob_target and tries < 8000:
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


static func _scatter_resource_blobs_sphere(
	data, seed_val: int, resource_density: float = 1.0
) -> void:
	var blob_target: int = _resource_blob_target(resource_density)
	var rng := RandomNumberGenerator.new()
	var placed_centers: Array[int] = []
	var next_id: int = 1
	for type_i in range(WorldConquestConfigLib.RESOURCE_TYPE_COUNT):
		rng.seed = seed_val ^ (0xB10B0000 + type_i * 0x9E37)
		var terrain_want: int = _terrain_for_resource_type(type_i)
		var candidates: Array[int] = []
		for cid in range(data.cell_count):
			if not data.is_land_cell_id(cid):
				continue
			if int(data.get_cell_terrain(cid, 0)) != terrain_want:
				continue
			if _too_close_to_spawn_sphere(data, cid):
				continue
			candidates.append(cid)
		var tries: int = 0
		var placed: int = 0
		while placed < blob_target and tries < 8000:
			tries += 1
			if candidates.is_empty():
				break
			var center: int = candidates[rng.randi_range(0, candidates.size() - 1)]
			if _too_close_to_blob_sphere(data, center, placed_centers):
				continue
			var size_tier: int = rng.randi_range(1, 3)
			var blob: Dictionary = _grow_resource_blob_sphere(
				data, center, size_tier, type_i, next_id, rng
			)
			if blob.is_empty():
				continue
			data.resource_deposits.append(blob)
			placed_centers.append(center)
			next_id += 1
			placed += 1


static func _too_close_to_spawn_sphere(data, cell_id: int) -> bool:
	var spots: Array[Vector2i] = [data.player_home_grid, data.enemy_home_grid]
	var pos: Vector3 = data.cell_positions[cell_id]
	var min_cos: float = cos(deg_to_rad(float(WorldConquestConfigLib.RESOURCE_SPAWN_EXCLUSION)))
	for spot in spots:
		if spot.x < 0:
			continue
		var other: Vector3 = data.cell_positions[spot.x]
		if pos.dot(other) > min_cos:
			return true
	return false


static func _too_close_to_blob_sphere(
	data, center: int, placed: Array[int]
) -> bool:
	var pos: Vector3 = data.cell_positions[center]
	var min_cos: float = cos(deg_to_rad(float(WorldConquestConfigLib.RESOURCE_BLOB_MIN_SPACING)))
	for other in placed:
		var other_pos: Vector3 = data.cell_positions[other]
		if pos.dot(other_pos) > min_cos:
			return true
	return false


static func _grow_resource_blob_sphere(
	data,
	center: int,
	size_tier: int,
	type_i: int,
	dep_id: int,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var want: int = int(data.get_cell_terrain(center, 0))
	var target_n: int = WorldConquestConfigLib.RESOURCE_BLOB_CELL_COUNT[size_tier]
	var keys := PackedInt32Array()
	var queue: Array[int] = [center]
	var seen: Dictionary = {center: true}
	while not queue.is_empty() and keys.size() < target_n:
		var cur: int = queue.pop_front()
		if not data.is_land_cell_id(cur):
			continue
		if int(data.get_cell_terrain(cur, 0)) != want:
			continue
		keys.append(cur)
		var nbrs: Array[int] = data.get_neighbors(cur)
		nbrs.shuffle()
		for nbr in nbrs:
			if seen.has(nbr):
				continue
			if rng.randf() > 0.62:
				continue
			seen[nbr] = true
			queue.append(nbr)
	if keys.size() < 3:
		return {}
	return {
		"id": dep_id,
		"type": type_i,
		"gx": center,
		"gy": 0,
		"size": size_tier,
		"yield_per_sec": WorldConquestConfigLib.RESOURCE_YIELD_BY_SIZE[size_tier],
		"cell_keys": keys,
	}


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
