class_name WorldRTSTerrainBake
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")


## One texture for the whole map (replaces thousands of per-tile ColorRects).
static func build_terrain_texture(map_data) -> ImageTexture:
	if map_data == null:
		return null
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var grass := Color(0.2, 0.38, 0.18, 0.82)
	for gy in range(h):
		for gx in range(w):
			img.set_pixel(gx, gy, _cell_color(map_data, gx, gy, grass))
	return ImageTexture.create_from_image(img)


static func _cell_color(map_data, gx: int, gy: int, grass: Color) -> Color:
	var t: int = map_data.get_cell_terrain(gx, gy)
	var c: Color = grass
	if t == BattleMapDataLib.Terrain.GRASS and map_data.is_passable(gx, gy):
		c = grass
	elif not map_data.is_passable(gx, gy) and t == BattleMapDataLib.Terrain.GRASS:
		c = grass
	else:
		match t:
			BattleMapDataLib.Terrain.WATER:
				c = Color(0.1, 0.32, 0.52, 0.95)
			BattleMapDataLib.Terrain.MOUNTAIN:
				c = (
					Color(0.38, 0.4, 0.44, 0.96)
					if map_data.is_cell_blocked(gx, gy)
					else Color(0.3, 0.34, 0.38, 0.9)
				)
			BattleMapDataLib.Terrain.SAND:
				c = Color(0.52, 0.44, 0.28, 0.88)
			BattleMapDataLib.Terrain.MUD:
				c = Color(0.18, 0.28, 0.14, 0.88)
			_:
				c = grass
	var height_tint: float = clampf((map_data.get_tile_height(gx, gy) - 0.35) * 0.35, -0.12, 0.18)
	return c.lightened(height_tint)
