class_name EarthGlobeMesh
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")


static func build_globe(map_data) -> ArrayMesh:
	return _build_globe_mesh(
		map_data,
		false,
		WorldConquestConfigLib.GLOBE_MESH_W,
		WorldConquestConfigLib.GLOBE_MESH_H,
	)


static func build_fluid_globe(map_data) -> ArrayMesh:
	return _build_globe_mesh(
		map_data,
		true,
		WorldConquestConfigLib.FLUID_MESH_W,
		WorldConquestConfigLib.FLUID_MESH_H,
	)


static func _build_globe_mesh(map_data, fluid: bool, mw: int, mh: int) -> ArrayMesh:
	if map_data == null:
		return ArrayMesh.new()
	var gw: int = map_data.grid_width
	var gh: int = map_data.grid_height
	var r: float = WorldConquestConfigLib.GLOBE_RADIUS
	var hs: float = WorldConquestConfigLib.HEIGHT_SCALE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for my in range(mh):
		for mx in range(mw):
			if fluid and not _quad_has_land(map_data, mx, my, mw, mh, gw, gh):
				continue
			_add_meridian_quad(st, map_data, mx, my, mw, mh, gw, gh, r, hs, fluid)
	st.generate_normals()
	return st.commit()


static func _mx_to_lon(mx: int, mw: int) -> float:
	return float(mx) / float(mw) * TAU - PI


static func _my_to_lat(my: int, mh: int) -> float:
	return PI * 0.5 - float(my) / float(mh) * PI


static func _grid_from_lon_lat(lon: float, lat: float, w: int, h: int) -> Vector2i:
	var gx: int = int(floor((lon + PI) / TAU * float(w)))
	gx = ((gx % w) + w) % w
	var gy: int = int(floor((PI * 0.5 - lat) / PI * float(h)))
	gy = clampi(gy, 0, h - 1)
	return Vector2i(gx, gy)


static func grid_to_sphere(gx: int, gy: int, w: int, h: int, radius: float, elev: float) -> Vector3:
	var lon: float = float(gx) / float(w) * TAU - PI
	var lat: float = PI * 0.5 - float(gy) / float(h) * PI
	return _pos_from_lon_lat(lon, lat, radius, elev)


static func _pos_from_lon_lat(lon: float, lat: float, radius: float, elev: float) -> Vector3:
	var cl: float = cos(lat)
	var base: Vector3 = Vector3(cl * cos(lon), sin(lat), cl * sin(lon)) * radius
	if elev <= 0.0001:
		return base
	return base + base.normalized() * elev


static func sphere_to_grid(pos: Vector3, w: int, h: int) -> Vector2i:
	var n: Vector3 = pos.normalized()
	var lat: float = asin(clampf(n.y, -1.0, 1.0))
	var lon: float = atan2(n.z, n.x)
	return _grid_from_lon_lat(lon, lat, w, h)


static func _quad_has_land(map_data, mx: int, my: int, mw: int, mh: int, gw: int, gh: int) -> bool:
	for corner in range(4):
		var lon: float = _mx_to_lon(mx + corner % 2, mw)
		var lat: float = _my_to_lat(my + corner / 2, mh)
		var g: Vector2i = _grid_from_lon_lat(lon, lat, gw, gh)
		if map_data.is_land_cell(g.x, g.y):
			return true
	return false


static func _sample_elevation(map_data, gx: int, gy: int, hs: float, fluid: bool) -> float:
	var elev: float = map_data.get_tile_height(gx, gy) * hs
	if fluid and map_data.is_land_cell(gx, gy):
		elev += WorldConquestConfigLib.FLUID_SURFACE_LIFT
	return elev


static func _add_meridian_quad(
	st: SurfaceTool,
	map_data,
	mx: int,
	my: int,
	mw: int,
	mh: int,
	gw: int,
	gh: int,
	radius: float,
	hs: float,
	fluid: bool,
) -> void:
	var lons: Array[float] = [_mx_to_lon(mx, mw), _mx_to_lon(mx + 1, mw)]
	var lats: Array[float] = [_my_to_lat(my, mh), _my_to_lat(my + 1, mh)]
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for j in range(2):
		for i in range(2):
			var lon: float = lons[i]
			var lat: float = lats[j]
			var g: Vector2i = _grid_from_lon_lat(lon, lat, gw, gh)
			var elev: float = _sample_elevation(map_data, g.x, g.y, hs, fluid)
			verts.append(_pos_from_lon_lat(lon, lat, radius, elev))
			var u: float = (lon + PI) / TAU
			var v: float = float(g.y) / float(gh)
			uvs.append(Vector2(u, v))
	var sample_g: Vector2i = _grid_from_lon_lat(
		(lons[0] + lons[1]) * 0.5, (lats[0] + lats[1]) * 0.5, gw, gh
	)
	var col: Color = (
		Color(1, 1, 1, 0.5)
		if fluid
		else _cell_color(map_data, sample_g.x, sample_g.y)
	)
	for idx in [0, 2, 1, 1, 2, 3]:
		st.set_color(col)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])


static func _cell_color(map_data, gx: int, gy: int) -> Color:
	if not map_data.is_land_cell(gx, gy):
		return Color(0.08, 0.22, 0.42)
	var t: int = map_data.get_cell_terrain(gx, gy)
	match t:
		BattleMapDataLib.Terrain.WATER:
			return Color(0.08, 0.22, 0.42)
		BattleMapDataLib.Terrain.MOUNTAIN:
			return Color(0.45, 0.42, 0.38)
		BattleMapDataLib.Terrain.SAND:
			return Color(0.72, 0.65, 0.42)
		BattleMapDataLib.Terrain.MUD:
			return Color(0.35, 0.48, 0.28)
		_:
			return Color(0.28, 0.52, 0.22)
