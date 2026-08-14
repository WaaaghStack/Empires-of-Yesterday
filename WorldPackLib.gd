class_name WorldPackLib
extends RefCounted

const SphereGridLibScript := preload("res://SphereGridLib.gd")

const _CACHE_ROOT := "user://world_cache/"
const _VER := 2  # bump: equirect/cell dual-address fix invalidates stale packs
const _MAX_NEIGHBORS := 6


static func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(_CACHE_ROOT.path_join("sphere"))
	DirAccess.make_dir_recursive_absolute(_CACHE_ROOT.path_join("worlds"))


static func load_or_build_sphere_grid(frequency: int) -> Dictionary:
	ensure_dirs()
	var path: String = _sphere_grid_path(frequency)
	if FileAccess.file_exists(path):
		var loaded: Dictionary = _read_grid(path)
		if not loaded.is_empty() and int(loaded.get("frequency", 0)) == frequency:
			return loaded
	var grid: Dictionary = SphereGridLibScript.generate(frequency)
	_write_grid(path, grid)
	return grid


static func load_or_build_equirect_lut(grid: Dictionary, ow: int, oh: int) -> PackedInt32Array:
	ensure_dirs()
	var frequency: int = int(grid.get("frequency", 0))
	var path: String = _equirect_lut_path(frequency, ow, oh)
	if FileAccess.file_exists(path):
		var lut: PackedInt32Array = _read_equirect_lut(path, frequency, ow, oh)
		if lut.size() == ow * oh:
			return lut
	var lut: PackedInt32Array = SphereGridLibScript.build_equirect_to_cell(grid, ow, oh)
	_write_equirect_lut(path, frequency, ow, oh, lut)
	return lut


static func try_load_world_cells(map_id: String, frequency: int) -> Dictionary:
	var land_path: String = _world_cell_land_path(map_id, frequency)
	var elev_path: String = _world_cell_elev_path(map_id, frequency)
	if not FileAccess.file_exists(land_path) or not FileAccess.file_exists(elev_path):
		return {}
	var cell_land: PackedByteArray = _read_cell_land(land_path)
	var cell_elev: PackedFloat32Array = _read_cell_elev(elev_path)
	if cell_land.is_empty() or cell_elev.is_empty():
		return {}
	if cell_land.size() != cell_elev.size():
		return {}
	return {"cell_land": cell_land, "cell_elev": cell_elev}


static func save_world_cells(
	map_id: String,
	frequency: int,
	cell_land: PackedByteArray,
	cell_elev: PackedFloat32Array,
) -> bool:
	if cell_land.size() != cell_elev.size() or cell_land.is_empty():
		return false
	ensure_dirs()
	DirAccess.make_dir_recursive_absolute(_world_freq_dir(map_id, frequency))
	var ok_land: bool = _write_cell_land(_world_cell_land_path(map_id, frequency), cell_land)
	var ok_elev: bool = _write_cell_elev(_world_cell_elev_path(map_id, frequency), cell_elev)
	return ok_land and ok_elev


static func try_load_albedo(
	map_id: String, frequency: int, run_seed: int = 0, visual_tag: String = ""
) -> Image:
	var path: String = _world_albedo_path(map_id, frequency, run_seed, visual_tag)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return img


static func save_albedo(
	map_id: String, frequency: int, img: Image, run_seed: int = 0, visual_tag: String = ""
) -> bool:
	if img == null or img.is_empty():
		return false
	ensure_dirs()
	DirAccess.make_dir_recursive_absolute(_world_freq_dir(map_id, frequency))
	return img.save_png(_world_albedo_path(map_id, frequency, run_seed, visual_tag)) == OK


static func try_load_height(
	map_id: String, frequency: int, run_seed: int = 0, visual_tag: String = ""
) -> Image:
	var path: String = _world_height_path(map_id, frequency, run_seed, visual_tag)
	if not FileAccess.file_exists(path):
		return null
	return _read_height_rfbin(path)


static func save_height(
	map_id: String, frequency: int, img: Image, run_seed: int = 0, visual_tag: String = ""
) -> bool:
	if img == null or img.is_empty():
		return false
	ensure_dirs()
	DirAccess.make_dir_recursive_absolute(_world_freq_dir(map_id, frequency))
	return _write_height_rfbin(_world_height_path(map_id, frequency, run_seed, visual_tag), img)


static func _sphere_dir(frequency: int) -> String:
	return _CACHE_ROOT.path_join("sphere").path_join("f%d" % frequency)


static func _sphere_grid_path(frequency: int) -> String:
	return _sphere_dir(frequency).path_join("grid.wgrd")


static func _equirect_lut_path(frequency: int, ow: int, oh: int) -> String:
	return _sphere_dir(frequency).path_join("equirect_%dx%d.wlut" % [ow, oh])


static func _world_freq_dir(map_id: String, frequency: int) -> String:
	return _CACHE_ROOT.path_join("worlds").path_join(map_id).path_join("f%d" % frequency)


static func _world_cell_land_path(map_id: String, frequency: int) -> String:
	return _world_freq_dir(map_id, frequency).path_join("cell_land.wbin")


static func _world_cell_elev_path(map_id: String, frequency: int) -> String:
	return _world_freq_dir(map_id, frequency).path_join("cell_elev.wbin")


static func _world_albedo_path(
	map_id: String, frequency: int, run_seed: int = 0, visual_tag: String = ""
) -> String:
	var name: String = "albedo_s%d.png" % run_seed
	if visual_tag != "":
		name = "albedo_s%d_%s.png" % [run_seed, visual_tag]
	return _world_freq_dir(map_id, frequency).path_join(name)


static func _world_height_path(
	map_id: String, frequency: int, run_seed: int = 0, visual_tag: String = ""
) -> String:
	var name: String = "height_s%d.rfbin" % run_seed
	if visual_tag != "":
		name = "height_s%d_%s.rfbin" % [run_seed, visual_tag]
	return _world_freq_dir(map_id, frequency).path_join(name)


static func _read_magic(f: FileAccess, expected: String) -> bool:
	var magic: String = f.get_buffer(4).get_string_from_ascii()
	return magic == expected


static func _write_header(f: FileAccess, magic: String) -> void:
	f.store_buffer(magic.to_ascii_buffer())
	f.store_16(_VER)
	f.store_16(0)


static func _write_grid(path: String, grid: Dictionary) -> bool:
	var cell_count: int = int(grid.cell_count)
	var positions: PackedVector3Array = grid.positions
	var lat: PackedFloat32Array = grid.lat
	var lon: PackedFloat32Array = grid.lon
	var neighbor_count: PackedByteArray = grid.neighbor_count
	var neighbors: PackedInt32Array = grid.neighbors
	var faces: PackedInt32Array = grid.faces
	if positions.size() != cell_count or lat.size() != cell_count or lon.size() != cell_count:
		return false
	if neighbor_count.size() != cell_count or neighbors.size() != cell_count * _MAX_NEIGHBORS:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	_write_header(f, "WGRD")
	f.store_32(int(grid.frequency))
	f.store_32(cell_count)
	for i in range(cell_count):
		var p: Vector3 = positions[i]
		f.store_float(p.x)
		f.store_float(p.y)
		f.store_float(p.z)
	for i in range(cell_count):
		f.store_float(lat[i])
	for i in range(cell_count):
		f.store_float(lon[i])
	f.store_buffer(neighbor_count)
	for i in range(cell_count * _MAX_NEIGHBORS):
		f.store_32(neighbors[i])
	var face_count: int = faces.size() / 3
	f.store_32(face_count)
	for i in range(faces.size()):
		f.store_32(faces[i])
	f.close()
	return true


static func _read_grid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if not _read_magic(f, "WGRD"):
		f.close()
		return {}
	if f.get_16() != _VER:
		f.close()
		return {}
	f.get_16()
	var frequency: int = f.get_32()
	var cell_count: int = f.get_32()
	if cell_count <= 0:
		f.close()
		return {}
	var positions := PackedVector3Array()
	positions.resize(cell_count)
	for i in range(cell_count):
		positions[i] = Vector3(f.get_float(), f.get_float(), f.get_float())
	var lat := PackedFloat32Array()
	lat.resize(cell_count)
	for i in range(cell_count):
		lat[i] = f.get_float()
	var lon := PackedFloat32Array()
	lon.resize(cell_count)
	for i in range(cell_count):
		lon[i] = f.get_float()
	var neighbor_count: PackedByteArray = f.get_buffer(cell_count)
	if neighbor_count.size() != cell_count:
		f.close()
		return {}
	var neighbors := PackedInt32Array()
	neighbors.resize(cell_count * _MAX_NEIGHBORS)
	for i in range(cell_count * _MAX_NEIGHBORS):
		neighbors[i] = f.get_32()
	var face_count: int = f.get_32()
	var faces := PackedInt32Array()
	faces.resize(face_count * 3)
	for i in range(face_count * 3):
		faces[i] = f.get_32()
	f.close()
	return {
		"frequency": frequency,
		"cell_count": cell_count,
		"positions": positions,
		"lat": lat,
		"lon": lon,
		"neighbors": neighbors,
		"neighbor_count": neighbor_count,
		"faces": faces,
	}


static func _write_equirect_lut(
	path: String, frequency: int, ow: int, oh: int, lut: PackedInt32Array
) -> bool:
	if lut.size() != ow * oh:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	_write_header(f, "WLUT")
	f.store_32(frequency)
	f.store_32(ow)
	f.store_32(oh)
	for i in lut.size():
		f.store_32(lut[i])
	f.close()
	return true


static func _read_equirect_lut(
	path: String, frequency: int, ow: int, oh: int
) -> PackedInt32Array:
	if not FileAccess.file_exists(path):
		return PackedInt32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedInt32Array()
	if not _read_magic(f, "WLUT"):
		f.close()
		return PackedInt32Array()
	if f.get_16() != _VER:
		f.close()
		return PackedInt32Array()
	f.get_16()
	if f.get_32() != frequency or f.get_32() != ow or f.get_32() != oh:
		f.close()
		return PackedInt32Array()
	var total: int = ow * oh
	var lut := PackedInt32Array()
	lut.resize(total)
	for i in total:
		lut[i] = f.get_32()
	f.close()
	return lut


static func _write_cell_land(path: String, cell_land: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	_write_header(f, "WLND")
	f.store_32(cell_land.size())
	f.store_buffer(cell_land)
	f.close()
	return true


static func _read_cell_land(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	if not _read_magic(f, "WLND"):
		f.close()
		return PackedByteArray()
	if f.get_16() != _VER:
		f.close()
		return PackedByteArray()
	f.get_16()
	var cell_count: int = f.get_32()
	var bits: PackedByteArray = f.get_buffer(cell_count)
	f.close()
	if bits.size() != cell_count:
		return PackedByteArray()
	return bits


static func _write_cell_elev(path: String, cell_elev: PackedFloat32Array) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	_write_header(f, "WELV")
	f.store_32(cell_elev.size())
	for i in cell_elev.size():
		f.store_float(cell_elev[i])
	f.close()
	return true


static func _read_cell_elev(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	if not _read_magic(f, "WELV"):
		f.close()
		return PackedFloat32Array()
	if f.get_16() != _VER:
		f.close()
		return PackedFloat32Array()
	f.get_16()
	var cell_count: int = f.get_32()
	var elev := PackedFloat32Array()
	elev.resize(cell_count)
	for i in cell_count:
		elev[i] = f.get_float()
	f.close()
	return elev


static func _write_height_rfbin(path: String, img: Image) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return false
	var rf: Image = img
	if img.get_format() != Image.FORMAT_RF:
		rf = img.duplicate()
		rf.convert(Image.FORMAT_RF)
	var bytes: PackedByteArray = rf.get_data()
	if bytes.size() != w * h * 4:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	_write_header(f, "WRFH")
	f.store_32(w)
	f.store_32(h)
	f.store_buffer(bytes)
	f.close()
	return true


static func _read_height_rfbin(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if not _read_magic(f, "WRFH"):
		f.close()
		return null
	if f.get_16() != _VER:
		f.close()
		return null
	f.get_16()
	var w: int = f.get_32()
	var h: int = f.get_32()
	var expected: int = w * h * 4
	var bytes: PackedByteArray = f.get_buffer(expected)
	f.close()
	if bytes.size() != expected or w <= 0 or h <= 0:
		return null
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, bytes)
	if img.is_empty():
		return null
	return img
