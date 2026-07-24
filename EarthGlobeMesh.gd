class_name EarthGlobeMesh
extends RefCounted

const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")


static func build_globe(map_data, map_id: String = WorldMapCatalogLib.DEFAULT_MAP_ID) -> ArrayMesh:
	return _build_globe_mesh(
		map_data,
		false,
		WorldConquestConfigLib.GLOBE_MESH_W,
		WorldConquestConfigLib.GLOBE_MESH_H,
		map_id,
	)


static func build_fluid_globe(map_data, map_id: String = WorldMapCatalogLib.DEFAULT_MAP_ID) -> ArrayMesh:
	return _build_globe_mesh(
		map_data,
		true,
		WorldConquestConfigLib.FLUID_MESH_W,
		WorldConquestConfigLib.FLUID_MESH_H,
		map_id,
	)


static func build_sphere_grid_mesh(map_data, fluid: bool = false) -> ArrayMesh:
	if map_data == null or not map_data.sphere_mode:
		return ArrayMesh.new()
	var faces: PackedInt32Array = map_data.sphere_faces
	var positions: PackedVector3Array = map_data.cell_positions
	if faces.is_empty() or positions.is_empty():
		return ArrayMesh.new()
	var r: float = WorldConquestConfigLib.GLOBE_RADIUS
	var hs: float = WorldConquestConfigLib.HEIGHT_SCALE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_count: int = faces.size() / 3
	for t in range(tri_count):
		var verts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for corner in range(3):
			var cid: int = faces[t * 3 + corner]
			if cid < 0 or cid >= positions.size():
				continue
			var p: Vector3 = positions[cid].normalized()
			var elev: float = map_data.get_tile_height(cid, 0) * hs
			if fluid and map_data.is_land_cell(cid, 0):
				elev += WorldConquestConfigLib.FLUID_SURFACE_LIFT
			verts.append(p * (r + elev))
			var lon: float = atan2(p.z, p.x)
			var lat: float = asin(clampf(p.y, -1.0, 1.0))
			var u: float = (lon + PI) / TAU
			var v: float = (PI * 0.5 - lat) / PI
			uvs.append(Vector2(u, v))
		if verts.size() < 3:
			continue
		var col: Color = Color(1, 1, 1, 1.0 if not fluid else 0.0)
		for idx in [0, 2, 1]:
			st.set_color(col)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
	st.generate_normals()
	return st.commit()


static func _build_globe_mesh(
	map_data, fluid: bool, mw: int, mh: int, map_id: String
) -> ArrayMesh:
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
	var sphere: bool = bool(map_data.sphere_mode)
	for corner in range(4):
		var lon: float = _mx_to_lon(mx + corner % 2, mw)
		var lat: float = _my_to_lat(my + corner / 2, mh)
		var g: Vector2i = _grid_from_lon_lat(lon, lat, gw, gh)
		var is_land: bool = (
			map_data.is_land_equirect_pixel(g.x, g.y)
			if sphere
			else map_data.is_land_cell(g.x, g.y)
		)
		if is_land:
			return true
	return false


static func _sample_elevation(map_data, gx: int, gy: int, hs: float, fluid: bool) -> float:
	var sphere: bool = bool(map_data.sphere_mode)
	var elev: float = (
		map_data.get_tile_height_equirect_pixel(gx, gy)
		if sphere
		else map_data.get_tile_height(gx, gy)
	) * hs
	var is_land: bool = (
		map_data.is_land_equirect_pixel(gx, gy) if sphere else map_data.is_land_cell(gx, gy)
	)
	if fluid and is_land:
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
	# Terrain color from PlanetVisualBake albedo; white verts so shader albedo shows.
	var col: Color = Color(1, 1, 1, 1.0 if not fluid else 0.0)
	for idx in [0, 2, 1, 1, 2, 3]:
		st.set_color(col)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])
