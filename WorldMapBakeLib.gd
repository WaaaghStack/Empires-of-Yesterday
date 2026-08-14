class_name WorldMapBakeLib
extends RefCounted

## Procedural land-mask builders for one-shot bake tools (no runtime PNG imports).


static func generate_earth_land_bits(w: int, h: int) -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(w * h)
	bits.fill(0)
	for gy in range(h):
		for gx in range(w):
			if _earth_land_at(gx, gy, w, h):
				bits[gy * w + gx] = 1
	_sanitize_land_mask(bits, w, h)
	return bits


static func generate_earth_elevation_norm(w: int, h: int, land_bits: PackedByteArray) -> PackedFloat32Array:
	var elev := PackedFloat32Array()
	elev.resize(w * h)
	for gy in range(h):
		var lat: float = PI * 0.5 - float(gy) / float(h) * PI
		for gx in range(w):
			var idx: int = gy * w + gx
			if land_bits[idx] == 0:
				elev[idx] = 0.0
				continue
			var base: float = 0.28 + 0.42 * absf(sin(lat * 1.35))
			if _near_coast(land_bits, w, h, gx, gy):
				base *= 0.55
			if _in_ellipse(gx, gy, 95.0, 22.0, 18.0, 12.0):
				base = maxf(base, 0.78)
			if _in_ellipse(gx, gy, 205.0, 70.0, 22.0, 38.0):
				base = maxf(base, 0.62)
			if _in_ellipse(gx, gy, 268.0, 118.0, 16.0, 10.0):
				base = maxf(base, 0.35)
			elev[idx] = clampf(base, 0.08, 0.95)
	return elev


static func write_land_bin(path: String, bits: PackedByteArray, w: int, h: int) -> bool:
	if bits.size() != w * h:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(w)
	f.store_32(h)
	f.store_buffer(bits)
	f.close()
	return true


static func write_elev_bin(path: String, elev: PackedFloat32Array, w: int, h: int) -> bool:
	if elev.size() != w * h:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(w)
	f.store_32(h)
	for i in elev.size():
		f.store_float(elev[i])
	f.close()
	return true


static func read_land_bin(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var w: int = f.get_32()
	var h: int = f.get_32()
	var expected: int = w * h
	var bits: PackedByteArray = f.get_buffer(expected)
	f.close()
	if bits.size() != expected or w <= 0 or h <= 0:
		return {}
	return {"grid_w": w, "grid_h": h, "land_bits": bits}


static func read_elev_bin(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var w: int = f.get_32()
	var h: int = f.get_32()
	var n: int = w * h
	var elev := PackedFloat32Array()
	elev.resize(n)
	for i in n:
		elev[i] = f.get_float()
	f.close()
	return {"grid_w": w, "grid_h": h, "elevation": elev}


static func _earth_land_at(gx: int, gy: int, w: int, h: int) -> bool:
	if gy < 2 or gy >= h - 2:
		return false
	# North America + Greenland
	if _in_ellipse(gx, gy, 52.0, 48.0, 34.0, 22.0):
		return true
	if _in_ellipse(gx, gy, 108.0, 26.0, 14.0, 10.0):
		return true
	if _in_ellipse(gx, gy, 88.0, 78.0, 10.0, 8.0):
		return true
	# South America
	if _in_ellipse(gx, gy, 98.0, 112.0, 16.0, 32.0):
		return true
	# Europe
	if _in_ellipse(gx, gy, 188.0, 42.0, 18.0, 12.0):
		return true
	if _in_ellipse(gx, gy, 172.0, 42.0, 6.0, 5.0):
		return true
	# Africa
	if _in_ellipse(gx, gy, 198.0, 82.0, 20.0, 30.0):
		return true
	if _in_ellipse(gx, gy, 204.0, 102.0, 5.0, 9.0):
		return true
	# Middle East + India
	if _in_ellipse(gx, gy, 218.0, 68.0, 14.0, 12.0):
		return true
	if _in_ellipse(gx, gy, 232.0, 76.0, 8.0, 14.0):
		return true
	# East Asia
	if _in_ellipse(gx, gy, 262.0, 52.0, 28.0, 18.0):
		return true
	if _in_ellipse(gx, gy, 280.0, 52.0, 5.0, 6.0):
		return true
	# SE Asia + Indonesia
	if _in_ellipse(gx, gy, 278.0, 88.0, 18.0, 12.0):
		return true
	# Australia
	if _in_ellipse(gx, gy, 292.0, 120.0, 18.0, 12.0):
		return true
	# New Zealand
	if _in_ellipse(gx, gy, 310.0, 122.0, 4.0, 5.0):
		return true
	# Japan
	if _in_ellipse(gx, gy, 282.0, 52.0, 4.0, 5.0):
		return true
	# UK / Iceland
	if _in_ellipse(gx, gy, 170.0, 40.0, 4.0, 3.0):
		return true
	if _in_ellipse(gx, gy, 166.0, 32.0, 3.0, 2.0):
		return true
	# Antarctica fringe
	if gy >= h - 14 and absf(float(gx) - 180.0) > 40.0:
		return true
	return false


static func _in_ellipse(gx: int, gy: int, cx: float, cy: float, rx: float, ry: float) -> bool:
	var dx: float = _lon_delta(gx, cx)
	var dy: float = float(gy) - cy
	if rx <= 0.001 or ry <= 0.001:
		return false
	return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0


static func _lon_delta(gx: int, cx: float) -> float:
	var d: float = float(gx) - cx
	if d > 180.0:
		d -= 360.0
	elif d < -180.0:
		d += 360.0
	return d


static func _near_coast(bits: PackedByteArray, w: int, h: int, gx: int, gy: int) -> bool:
	if bits[gy * w + gx] == 0:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = gx + dx
			var ny: int = gy + dy
			if ny < 0 or ny >= h:
				return true
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
			if bits[ny * w + nx] == 0:
				return true
	return false


static func sanitize_land_mask(bits: PackedByteArray, w: int, h: int) -> void:
	_sanitize_land_mask(bits, w, h)


static func _sanitize_land_mask(bits: PackedByteArray, w: int, h: int) -> void:
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			if bits[idx] == 0:
				continue
			var land_n: int = 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = gx + dx
					var ny: int = gy + dy
					if ny < 0 or ny >= h:
						continue
					if nx < 0:
						nx = w - 1
					elif nx >= w:
						nx = 0
					if bits[ny * w + nx] > 0:
						land_n += 1
			if land_n <= 1:
				bits[idx] = 0
