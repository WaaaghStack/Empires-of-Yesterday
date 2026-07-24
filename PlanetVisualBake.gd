class_name PlanetVisualBake
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
const WorldPackLibScript := preload("res://WorldPackLib.gd")

const _COAST_RING_MAX := 8


static func build_albedo_image_cached(map_data, map_id: String) -> Image:
	var frequency: int = int(map_data.sphere_frequency) if map_data else 0
	var run_seed: int = int(map_data.map_seed) if map_data else 0
	if frequency > 0:
		var cached: Image = WorldPackLibScript.try_load_albedo(map_id, frequency, run_seed)
		if cached != null:
			return cached
	var img: Image = build_albedo_image(map_data, map_id)
	if img != null and frequency > 0:
		WorldPackLibScript.save_albedo(map_id, frequency, img, run_seed)
	return img


static func build_height_image_cached(map_data, map_id: String) -> Image:
	var frequency: int = int(map_data.sphere_frequency) if map_data else 0
	var run_seed: int = int(map_data.map_seed) if map_data else 0
	if frequency > 0:
		var cached: Image = WorldPackLibScript.try_load_height(map_id, frequency, run_seed)
		if cached != null:
			return cached
	var img: Image = build_height_image(map_data)
	if img != null and frequency > 0:
		WorldPackLibScript.save_height(map_id, frequency, img, run_seed)
	return img


static func build_albedo_image(map_data, map_id: String) -> Image:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var palette: Dictionary = WorldConquestMapGeneratorLib.globe_colors_for_map(map_id)
	var ocean_col: Color = palette.get("ocean", Color(0.05, 0.18, 0.42))
	var land_col: Color = palette.get("land", Color(0.34, 0.52, 0.28))
	var mountain_col: Color = palette.get("mountain", Color(0.48, 0.44, 0.38))
	var sand_col: Color = palette.get("sand", Color(0.72, 0.64, 0.38))
	var mud_col: Color = land_col.darkened(0.38).lerp(Color(0.28, 0.24, 0.14), 0.55)

	var coast: Dictionary = _build_coast_distance_fields(map_data)
	var land_dist: PackedByteArray = coast.land_dist
	var water_dist: PackedByteArray = coast.water_dist

	var sphere: bool = bool(map_data.sphere_mode)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		var pole_factor: float = 1.0 - pow(1.0 - absf(sin(lat)), 1.6) * 0.18
		for gx in range(w):
			var idx: int = gy * w + gx
			var col: Color
			var is_land: bool = (
				map_data.is_land_equirect_pixel(gx, gy)
				if sphere
				else map_data.is_land_cell(gx, gy)
			)
			if not is_land:
				col = _ocean_albedo(land_dist[idx], ocean_col, pole_factor)
			else:
				col = _land_albedo(
					map_data, gx, gy, water_dist[idx], land_col, mountain_col, sand_col, mud_col
				)
			col = _apply_micro_noise(col, gx, gy)
			img.set_pixel(gx, gy, col)
	return img


static func build_height_image(map_data) -> Image:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var sphere: bool = bool(map_data.sphere_mode)
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for gy in range(h):
		for gx in range(w):
			var ht: float = 0.0
			var is_land: bool = (
				map_data.is_land_equirect_pixel(gx, gy)
				if sphere
				else map_data.is_land_cell(gx, gy)
			)
			if is_land:
				ht = clampf(
					(
						map_data.get_tile_height_equirect_pixel(gx, gy)
						if sphere
						else map_data.get_tile_height(gx, gy)
					),
					0.0,
					1.0,
				)
			img.set_pixel(gx, gy, Color(ht, 0.0, 0.0, 1.0))
	return img


static func _build_coast_distance_fields(map_data) -> Dictionary:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var sphere: bool = bool(map_data.sphere_mode)
	var total: int = w * h
	var land_dist := PackedByteArray()
	var water_dist := PackedByteArray()
	land_dist.resize(total)
	water_dist.resize(total)
	var far: int = _COAST_RING_MAX + 1
	land_dist.fill(far)
	water_dist.fill(far)

	var queue := PackedInt32Array()
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			var is_land: bool = (
				map_data.is_land_equirect_pixel(gx, gy)
				if sphere
				else map_data.is_land_cell(gx, gy)
			)
			if is_land:
				land_dist[idx] = 0
				queue.append(idx)
			else:
				water_dist[idx] = 0

	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var gx: int = idx % w
		var gy: int = idx / w
		var cur: int = int(land_dist[idx])
		if cur >= _COAST_RING_MAX:
			continue
		for di in range(4):
			var nx: int = gx
			var ny: int = gy
			match di:
				0:
					nx += 1
				1:
					nx -= 1
				2:
					ny += 1
				3:
					ny -= 1
			if ny < 0 or ny >= h:
				continue
			nx = _wrap_gx(nx, w)
			var nidx: int = ny * w + nx
			var nd: int = cur + 1
			if nd < int(land_dist[nidx]):
				land_dist[nidx] = nd
				queue.append(nidx)

	queue.clear()
	head = 0
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			var is_land2: bool = (
				map_data.is_land_equirect_pixel(gx, gy)
				if sphere
				else map_data.is_land_cell(gx, gy)
			)
			if not is_land2:
				queue.append(idx)

	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var gx: int = idx % w
		var gy: int = idx / w
		var cur: int = int(water_dist[idx])
		if cur >= _COAST_RING_MAX:
			continue
		for di in range(4):
			var nx: int = gx
			var ny: int = gy
			match di:
				0:
					nx += 1
				1:
					nx -= 1
				2:
					ny += 1
				3:
					ny -= 1
			if ny < 0 or ny >= h:
				continue
			nx = _wrap_gx(nx, w)
			var nidx: int = ny * w + nx
			var nd: int = cur + 1
			if nd < int(water_dist[nidx]):
				water_dist[nidx] = nd
				queue.append(nidx)

	return {"land_dist": land_dist, "water_dist": water_dist}


static func _hash_cell(gx: int, gy: int) -> float:
	return fmod(sin(float(gx) * 12.9898 + float(gy) * 78.233) * 43758.5453, 1.0)


static func _apply_micro_noise(col: Color, gx: int, gy: int) -> Color:
	var n: float = _hash_cell(gx, gy)
	var amp: float = lerpf(0.02, 0.04, n)
	var delta: float = (n - 0.5) * 2.0 * amp
	return Color(
		clampf(col.r + delta, 0.0, 1.0),
		clampf(col.g + delta * 0.92, 0.0, 1.0),
		clampf(col.b + delta * 0.85, 0.0, 1.0),
		1.0
	)


static func _wrap_gx(gx: int, w: int) -> int:
	return ((gx % w) + w) % w


static func _ocean_albedo(land_dist: int, ocean_col: Color, pole_factor: float) -> Color:
	var coast_dist: int = mini(land_dist, _COAST_RING_MAX)
	var depth: float = float(coast_dist) / float(_COAST_RING_MAX)
	var deep: Color = ocean_col.darkened(0.22)
	var shallow: Color = ocean_col.lightened(0.12).lerp(Color(0.08, 0.42, 0.48), 0.38)
	var col: Color = deep.lerp(shallow, 1.0 - depth)
	return col * pole_factor


static func _land_albedo(
	map_data,
	gx: int,
	gy: int,
	water_dist: int,
	land_col: Color,
	mountain_col: Color,
	sand_col: Color,
	mud_col: Color,
) -> Color:
	var elev: float = clampf(
		(
			map_data.get_tile_height_equirect_pixel(gx, gy)
			if bool(map_data.sphere_mode)
			else map_data.get_tile_height(gx, gy)
		),
		0.0,
		1.0,
	)
	var terrain: int = (
		map_data.get_cell_terrain_equirect_pixel(gx, gy)
		if bool(map_data.sphere_mode)
		else map_data.get_cell_terrain(gx, gy)
	)
	var coast_t: float = 1.0 - clampf(
		float(mini(water_dist, _COAST_RING_MAX)) / float(_COAST_RING_MAX), 0.0, 1.0
	)

	var col: Color
	match terrain:
		BattleMapDataLib.Terrain.MOUNTAIN:
			col = mountain_col.lightened(elev * 0.22)
			col = col.lerp(Color(0.58, 0.52, 0.44), elev * 0.35)
		BattleMapDataLib.Terrain.SAND:
			col = sand_col.lerp(sand_col.darkened(0.16), coast_t * 0.65)
			col = col.lightened(elev * 0.08)
		BattleMapDataLib.Terrain.MUD:
			col = mud_col.darkened(0.06).lerp(mud_col.lightened(0.1), elev * 0.4)
		_:
			var shade: float = lerpf(0.84, 1.1, elev)
			var hue_var: float = (_hash_cell(gx, gy) - 0.5) * 0.06
			col = land_col * shade
			col.g = clampf(col.g + hue_var, 0.0, 1.0)
			col.r = clampf(col.r - hue_var * 0.35, 0.0, 1.0)

	if water_dist <= 1:
		col = col.darkened(0.08 + coast_t * 0.04)

	return col
