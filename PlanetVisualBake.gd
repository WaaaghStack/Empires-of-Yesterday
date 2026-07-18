class_name PlanetVisualBake
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")

const _COAST_RING_MAX := 8


static func build_albedo_image(map_data, map_id: String) -> Image:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var palette: Dictionary = WorldConquestMapGeneratorLib.globe_colors_for_map(map_id)
	var ocean_col: Color = palette.get("ocean", Color(0.05, 0.18, 0.42))
	var land_col: Color = palette.get("land", Color(0.34, 0.52, 0.28))
	var mountain_col: Color = palette.get("mountain", Color(0.48, 0.44, 0.38))
	var sand_col: Color = palette.get("sand", Color(0.72, 0.64, 0.38))
	var mud_col: Color = land_col.darkened(0.38).lerp(Color(0.28, 0.24, 0.14), 0.55)

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		var pole_factor: float = 1.0 - pow(1.0 - absf(sin(lat)), 1.6) * 0.18
		for gx in range(w):
			var col: Color
			if not map_data.is_land_cell(gx, gy):
				col = _ocean_albedo(map_data, gx, gy, ocean_col, pole_factor)
			else:
				col = _land_albedo(
					map_data, gx, gy, land_col, mountain_col, sand_col, mud_col
				)
			col = _apply_micro_noise(col, gx, gy)
			img.set_pixel(gx, gy, col)
	return img


static func build_height_image(map_data) -> Image:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for gy in range(h):
		for gx in range(w):
			var ht: float = 0.0
			if map_data.is_land_cell(gx, gy):
				ht = clampf(map_data.get_tile_height(gx, gy), 0.0, 1.0)
			img.set_pixel(gx, gy, Color(ht, 0.0, 0.0, 1.0))
	return img


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


static func _ring_distance(
	map_data, gx: int, gy: int, want_land: bool, max_r: int
) -> int:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var nx: int = _wrap_gx(gx + dx, w)
				var ny: int = gy + dy
				if ny < 0 or ny >= h:
					continue
				var is_land: bool = map_data.is_land_cell(nx, ny)
				if want_land and is_land:
					return r
				if not want_land and not is_land:
					return r
	return max_r


static func _ocean_albedo(
	map_data, gx: int, gy: int, ocean_col: Color, pole_factor: float
) -> Color:
	var coast_dist: int = _ring_distance(map_data, gx, gy, true, _COAST_RING_MAX)
	var depth: float = float(coast_dist) / float(_COAST_RING_MAX)
	var deep: Color = ocean_col.darkened(0.22)
	var shallow: Color = ocean_col.lightened(0.12).lerp(Color(0.08, 0.42, 0.48), 0.38)
	var col: Color = deep.lerp(shallow, 1.0 - depth)
	return col * pole_factor


static func _land_albedo(
	map_data,
	gx: int,
	gy: int,
	land_col: Color,
	mountain_col: Color,
	sand_col: Color,
	mud_col: Color,
) -> Color:
	var elev: float = clampf(map_data.get_tile_height(gx, gy), 0.0, 1.0)
	var terrain: int = map_data.get_cell_terrain(gx, gy)
	var water_dist: int = _ring_distance(map_data, gx, gy, false, _COAST_RING_MAX)
	var coast_t: float = 1.0 - clampf(float(water_dist) / float(_COAST_RING_MAX), 0.0, 1.0)

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
