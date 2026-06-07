class_name EarthMapGenerator
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

const LAND_MASK_PATH := "res://data/earth/land_mask_360x180.png"
const ELEVATION_PATH := "res://data/earth/elevation_360x180.png"


static func generate(run_seed: int):
	var w: int = WorldConquestConfigLib.GRID_W
	var h: int = WorldConquestConfigLib.GRID_H
	var land_bits: PackedByteArray = _load_or_build_land_bits(w, h, run_seed)
	var elev_norm: PackedFloat32Array = _load_or_build_elevation_norm(w, h, run_seed, land_bits)
	var coast_bits: PackedByteArray = _build_coast_bits(land_bits, w, h)
	var data = BattleMapDataLib.new()
	data.map_seed = run_seed
	data.terrain_tag = "earth"
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
	_place_spawns_and_capitals(data, land_bits, run_seed)
	return data


static func _load_or_build_land_bits(w: int, h: int, seed_val: int) -> PackedByteArray:
	var total: int = w * h
	var bits := PackedByteArray()
	bits.resize(total)
	if ResourceLoader.exists(LAND_MASK_PATH):
		var tex: Texture2D = load(LAND_MASK_PATH)
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and img.get_width() == w and img.get_height() == h:
				for gy in range(h):
					for gx in range(w):
						bits[gy * w + gx] = 1 if img.get_pixel(gx, gy).r > 0.5 else 0
				return bits
	var proc: Image = _procedural_earth_land(w, h, seed_val)
	for i in range(total):
		bits[i] = 1 if proc.get_pixel(i % w, i / w).r > 0.5 else 0
	return bits


static func _load_or_build_elevation_norm(
	w: int, h: int, seed_val: int, land_bits: PackedByteArray
) -> PackedFloat32Array:
	var total: int = w * h
	var elev := PackedFloat32Array()
	elev.resize(total)
	if ResourceLoader.exists(ELEVATION_PATH):
		var tex: Texture2D = load(ELEVATION_PATH)
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and img.get_width() == w and img.get_height() == h:
				for gy in range(h):
					for gx in range(w):
						elev[gy * w + gx] = img.get_pixel(gx, gy).r
				return elev
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
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						is_coast = true
						break
					if land_bits[ny * w + nx] == 0:
						is_coast = true
						break
				if is_coast:
					break
			coast[idx] = 1 if is_coast else 0
	return coast


static func _procedural_earth_land(w: int, h: int, seed_val: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		for gx in range(w):
			var lon: float = float(gx) / float(w) * TAU - PI
			var land: bool = false
			if absf(lat) < 1.35:
				var amer: float = _blob(lon + 1.9, lat + 0.15, 0.85, 0.55)
				var eurasia: float = _blob(lon - 0.35, lat - 0.05, 1.1, 0.65)
				var africa: float = _blob(lon - 0.15, lat + 0.55, 0.45, 0.45)
				var aus: float = _blob(lon - 2.35, lat + 1.05, 0.35, 0.28)
				var n: float = rng.randf_range(-0.12, 0.12)
				land = amer + eurasia + africa + aus + n > 0.42
			img.set_pixel(gx, gy, Color(1.0, 0, 0) if land else Color(0, 0, 0))
	return img


static func _blob(lon: float, lat: float, rx: float, ry: float) -> float:
	var dx: float = lon / rx
	var dy: float = lat / ry
	return exp(-(dx * dx + dy * dy))


static func _place_spawns_and_capitals(data, land_bits: PackedByteArray, seed_val: int) -> void:
	var w: int = data.grid_width
	var h: int = data.grid_height
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0xE471
	var west_cells: Array[Vector2i] = []
	var east_cells: Array[Vector2i] = []
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			if land_bits[idx] == 0:
				continue
			if not data.is_land_cell(gx, gy):
				continue
			if gx < w / 3:
				west_cells.append(Vector2i(gx, gy))
			elif gx > w * 2 / 3:
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
