class_name WorldRTS3DTerrainMesh
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldRTS3DConfigLib := preload("res://WorldRTS3DConfig.gd")


static func build(map_data) -> ArrayMesh:
	if map_data == null:
		return ArrayMesh.new()
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var cs: float = map_data.cell_size
	var hs: float = WorldRTS3DConfigLib.HEIGHT_SCALE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gy in range(h):
		for gx in range(w):
			_add_cell(st, map_data, gx, gy, cs, hs)
	st.generate_normals()
	return st.commit()


static func _add_cell(st: SurfaceTool, map_data, gx: int, gy: int, cs: float, hs: float) -> void:
	var c00: Vector2 = map_data.cell_center(gx, gy) - Vector2(cs * 0.5, cs * 0.5)
	var c10: Vector2 = c00 + Vector2(cs, 0.0)
	var c01: Vector2 = c00 + Vector2(0.0, cs)
	var c11: Vector2 = c00 + Vector2(cs, cs)
	var y00: float = _elev_y(map_data, gx, gy, hs)
	var y10: float = _elev_y(map_data, gx + 1, gy, hs)
	var y01: float = _elev_y(map_data, gx, gy + 1, hs)
	var y11: float = _elev_y(map_data, gx + 1, gy + 1, hs)
	var col: Color = _cell_color(map_data, gx, gy)
	st.set_color(col)
	st.add_vertex(Vector3(c00.x, y00, c00.y))
	st.set_color(col)
	st.add_vertex(Vector3(c10.x, y10, c10.y))
	st.set_color(col)
	st.add_vertex(Vector3(c01.x, y01, c01.y))
	st.set_color(col)
	st.add_vertex(Vector3(c10.x, y10, c10.y))
	st.set_color(col)
	st.add_vertex(Vector3(c11.x, y11, c11.y))
	st.set_color(col)
	st.add_vertex(Vector3(c01.x, y01, c01.y))


static func _elev_y(map_data, gx: int, gy: int, hs: float) -> float:
	if gx < 0 or gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
		return 0.0
	return map_data.get_tile_height(gx, gy) * hs


static func _cell_color(map_data, gx: int, gy: int) -> Color:
	var t: int = map_data.get_cell_terrain(gx, gy)
	var c: Color
	match t:
		BattleMapDataLib.Terrain.WATER:
			c = Color(0.12, 0.38, 0.58)
		BattleMapDataLib.Terrain.MOUNTAIN:
			c = Color(0.42, 0.44, 0.48) if map_data.is_cell_blocked(gx, gy) else Color(0.34, 0.38, 0.42)
		BattleMapDataLib.Terrain.SAND:
			c = Color(0.55, 0.46, 0.3)
		BattleMapDataLib.Terrain.MUD:
			c = Color(0.22, 0.32, 0.18)
		_:
			c = Color(0.22, 0.42, 0.2)
	if not map_data.is_passable(gx, gy) and t == BattleMapDataLib.Terrain.GRASS:
		c = c.darkened(0.15)
	var tint: float = clampf((map_data.get_tile_height(gx, gy) - 0.35) * 0.25, -0.1, 0.15)
	return c.lightened(tint)


## Terrain-following fluid surface (flat plane was hidden under hills).
static func build_fluid_drape(map_data) -> ArrayMesh:
	if map_data == null:
		return ArrayMesh.new()
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var cs: float = map_data.cell_size
	var hs: float = WorldRTS3DConfigLib.HEIGHT_SCALE
	var lift: float = WorldRTS3DConfigLib.FLUID_SURFACE_LIFT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			_add_fluid_cell(st, map_data, gx, gy, w, h, cs, hs, lift)
	st.generate_normals()
	return st.commit()


static func _add_fluid_cell(
	st: SurfaceTool,
	map_data,
	gx: int,
	gy: int,
	grid_w: int,
	grid_h: int,
	cs: float,
	hs: float,
	lift: float,
) -> void:
	var c00: Vector2 = map_data.cell_center(gx, gy) - Vector2(cs * 0.5, cs * 0.5)
	var c10: Vector2 = c00 + Vector2(cs, 0.0)
	var c01: Vector2 = c00 + Vector2(0.0, cs)
	var c11: Vector2 = c00 + Vector2(cs, cs)
	var y00: float = _elev_y(map_data, gx, gy, hs) + lift
	var y10: float = _elev_y(map_data, gx + 1, gy, hs) + lift
	var y01: float = _elev_y(map_data, gx, gy + 1, hs) + lift
	var y11: float = _elev_y(map_data, gx + 1, gy + 1, hs) + lift
	var u0: float = float(gx) / float(grid_w)
	var u1: float = float(gx + 1) / float(grid_w)
	var v0: float = 1.0 - float(gy + 1) / float(grid_h)
	var v1: float = 1.0 - float(gy) / float(grid_h)
	st.set_uv(Vector2(u0, v0))
	st.add_vertex(Vector3(c00.x, y00, c00.y))
	st.set_uv(Vector2(u1, v0))
	st.add_vertex(Vector3(c10.x, y10, c10.y))
	st.set_uv(Vector2(u0, v1))
	st.add_vertex(Vector3(c01.x, y01, c01.y))
	st.set_uv(Vector2(u1, v0))
	st.add_vertex(Vector3(c10.x, y10, c10.y))
	st.set_uv(Vector2(u1, v1))
	st.add_vertex(Vector3(c11.x, y11, c11.y))
	st.set_uv(Vector2(u0, v1))
	st.add_vertex(Vector3(c01.x, y01, c01.y))
