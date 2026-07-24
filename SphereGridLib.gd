class_name SphereGridLib
extends RefCounted

## Pure GDScript equal-area sphere grid (subdivided icosahedron).
## Mirrors rust/empire_territory/src/sphere_grid.rs for gameplay parity.
## Thin backend: swap generate() internals for Rust FFI when available.

const _MAX_NEIGHBORS := 6


static func generate(frequency: int) -> Dictionary:
	if ClassDB.class_exists("TerritorySim"):
		var sim = ClassDB.instantiate("TerritorySim")
		if sim and sim.has_method("generate_sphere_grid"):
			var d = sim.generate_sphere_grid(frequency)
			if d is Dictionary and int(d.get("cell_count", 0)) > 0:
				return d
	assert(frequency >= 1, "frequency must be >= 1")
	var f: int = frequency

	var icosa: Dictionary = _icosahedron()
	var base_verts: Array = icosa.verts
	var base_faces: Array = icosa.faces

	var positions: Array = base_verts.duplicate()
	var edge_verts: Dictionary = {}
	var faces: Array = []

	for face in base_faces:
		var v0: int = face[0]
		var v1: int = face[1]
		var v2: int = face[2]
		var p0: Vector3 = base_verts[v0]
		var p1: Vector3 = base_verts[v1]
		var p2: Vector3 = base_verts[v2]

		var grid: Array = []
		grid.resize(f + 1)
		for i in range(f + 1):
			grid[i] = []
			grid[i].resize(f + 1)
			grid[i].fill(0)

		for i in range(f + 1):
			for j in range(f - i + 1):
				grid[i][j] = _face_vertex(
					positions, edge_verts, p0, p1, p2, v0, v1, v2, i, j, f
				)

		for i in range(f):
			for j in range(f - i):
				var a: int = grid[i][j]
				var b: int = grid[i + 1][j]
				var c: int = grid[i][j + 1]
				faces.append([a, b, c])
				if j < f - i - 1:
					var d: int = grid[i + 1][j + 1]
					faces.append([b, d, c])

	var neighbor_data: Dictionary = _build_neighbors(positions.size(), faces)
	var neighbors_flat: PackedInt32Array = neighbor_data.neighbors
	var neighbor_count: PackedByteArray = neighbor_data.neighbor_count

	_separate_coincident_vertices(positions)

	var cell_count: int = positions.size()
	var packed_positions := PackedVector3Array()
	packed_positions.resize(cell_count)
	var lat := PackedFloat32Array()
	lat.resize(cell_count)
	var lon := PackedFloat32Array()
	lon.resize(cell_count)

	for i in range(cell_count):
		var p: Vector3 = positions[i]
		packed_positions[i] = p
		lat[i] = asin(clampf(p.y, -1.0, 1.0))
		lon[i] = atan2(p.z, p.x)

	var packed_faces := PackedInt32Array()
	packed_faces.resize(faces.size() * 3)
	for fi in range(faces.size()):
		var tri: Array = faces[fi]
		packed_faces[fi * 3] = tri[0]
		packed_faces[fi * 3 + 1] = tri[1]
		packed_faces[fi * 3 + 2] = tri[2]

	return {
		"frequency": f,
		"cell_count": cell_count,
		"positions": packed_positions,
		"lat": lat,
		"lon": lon,
		"neighbors": neighbors_flat,
		"neighbor_count": neighbor_count,
		"faces": packed_faces,
	}


static func sample_land_bits(
	grid: Dictionary, land_bits: PackedByteArray, src_w: int, src_h: int
) -> PackedByteArray:
	var cell_count: int = int(grid.cell_count)
	var out := PackedByteArray()
	out.resize(cell_count)
	for i in range(cell_count):
		var idx: int = _equirect_index(grid, i, src_w, src_h)
		out[i] = 1 if idx < land_bits.size() and land_bits[idx] != 0 else 0
	return out


static func sample_elevation(
	grid: Dictionary, elev: PackedFloat32Array, src_w: int, src_h: int
) -> PackedFloat32Array:
	var cell_count: int = int(grid.cell_count)
	var out := PackedFloat32Array()
	out.resize(cell_count)
	for i in range(cell_count):
		var idx: int = _equirect_index(grid, i, src_w, src_h)
		out[i] = elev[idx] if idx < elev.size() else 0.0
	return out


static func nearest_cell(grid: Dictionary, dir: Vector3) -> int:
	var positions: PackedVector3Array = grid.positions
	for i in range(positions.size()):
		var p: Vector3 = positions[i]
		if p.is_equal_approx(dir):
			return i

	var d: Vector3 = _normalize(dir)
	var best_i: int = 0
	var best_dot: float = -INF
	for i in range(positions.size()):
		var pn: Vector3 = _normalize(positions[i])
		var dot: float = d.dot(pn)
		if dot > best_dot:
			best_dot = dot
			best_i = i
	return best_i


## Multi-source BFS Voronoi on equirect — O(ow*oh + cells), not brute-force nearest.
## Prefers Rust TerritorySim FFI; GDScript fallback uses a head-index queue (no pop_front).
static func build_equirect_to_cell(grid: Dictionary, ow: int, oh: int) -> PackedInt32Array:
	if ClassDB.class_exists("TerritorySim"):
		var sim = ClassDB.instantiate("TerritorySim")
		if sim and sim.has_method("build_equirect_to_cell"):
			var freq: int = int(grid.get("frequency", 0))
			if sim.has_method("generate_sphere_grid"):
				sim.generate_sphere_grid(freq)
			var lut: PackedInt32Array = sim.build_equirect_to_cell(freq, ow, oh)
			if lut.size() == ow * oh:
				return lut
	var total: int = ow * oh
	var result := PackedInt32Array()
	result.resize(total)
	result.fill(-1)

	var lons: PackedFloat32Array = grid.lon
	var lats: PackedFloat32Array = grid.lat
	var cell_count: int = int(grid.cell_count)
	var qx := PackedInt32Array()
	var qy := PackedInt32Array()
	qx.resize(total)
	qy.resize(total)
	var q_head: int = 0
	var q_tail: int = 0

	for i in range(cell_count):
		var gx: int = _wrap_floor(_lon_to_u(lons[i], ow), ow)
		var gy: int = _clamp_floor(_lat_to_v(lats[i], oh), oh)
		var pidx: int = gy * ow + gx
		if result[pidx] == -1:
			result[pidx] = i
			qx[q_tail] = gx
			qy[q_tail] = gy
			q_tail += 1

	while q_head < q_tail:
		var cx: int = qx[q_head]
		var cy: int = qy[q_head]
		q_head += 1
		var cur_cell: int = result[cy * ow + cx]
		for di in range(4):
			var nx: int = cx
			var ny: int = cy
			match di:
				0:
					nx += 1
				1:
					nx -= 1
				2:
					ny += 1
				3:
					ny -= 1
			if ny < 0 or ny >= oh:
				continue
			if nx < 0:
				nx = ow - 1
			elif nx >= ow:
				nx = 0
			var nidx: int = ny * ow + nx
			if result[nidx] == -1:
				result[nidx] = cur_cell
				qx[q_tail] = nx
				qy[q_tail] = ny
				q_tail += 1

	return result


static func _icosahedron() -> Dictionary:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var raw: Array = [
		Vector3(-1.0, t, 0.0),
		Vector3(1.0, t, 0.0),
		Vector3(-1.0, -t, 0.0),
		Vector3(1.0, -t, 0.0),
		Vector3(0.0, -1.0, t),
		Vector3(0.0, 1.0, t),
		Vector3(0.0, -1.0, -t),
		Vector3(0.0, 1.0, -t),
		Vector3(0.0, -t, 1.0),
		Vector3(0.0, t, 1.0),
		Vector3(0.0, -t, -1.0),
		Vector3(0.0, t, -1.0),
	]
	var verts: Array = []
	for v in raw:
		verts.append(_normalize(v))
	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	return {"verts": verts, "faces": faces}


static func _normalize(v: Vector3) -> Vector3:
	var len: float = v.length()
	if len <= 0.0:
		return Vector3(0.0, 1.0, 0.0)
	return v / len


static func _slerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var dot: float = clampf(a.dot(b), -1.0, 1.0)
	var theta: float = acos(dot)
	if theta < 1e-6:
		return _normalize(a.lerp(b, t))
	var sin_theta: float = sin(theta)
	var w1: float = sin((1.0 - t) * theta) / sin_theta
	var w2: float = sin(t * theta) / sin_theta
	return _normalize(a * w1 + b * w2)


static func _edge_key(lo: int, hi: int, step: int) -> String:
	return "%d,%d,%d" % [lo, hi, step]


static func _subdivide_edge(
	positions: Array, edge_verts: Dictionary, a: int, b: int, step: int, f: int
) -> int:
	if step == 0:
		return a
	if step == f:
		return b
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var step_from_lo: int = step if a == lo else f - step
	var key: String = _edge_key(lo, hi, step_from_lo)
	if edge_verts.has(key):
		return int(edge_verts[key])
	var va: Vector3 = positions[lo]
	var vb: Vector3 = positions[hi]
	var pos: Vector3 = _slerp(va, vb, float(step_from_lo) / float(f))
	var idx: int = positions.size()
	positions.append(pos)
	edge_verts[key] = idx
	return idx


static func _face_vertex(
	positions: Array,
	edge_verts: Dictionary,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	v0: int,
	v1: int,
	v2: int,
	i: int,
	j: int,
	f: int,
) -> int:
	if j == 0:
		return _subdivide_edge(positions, edge_verts, v0, v1, i, f)
	if i == 0:
		return _subdivide_edge(positions, edge_verts, v0, v2, j, f)
	if i + j == f:
		return _subdivide_edge(positions, edge_verts, v1, v2, f - i, f)

	var k: int = f - i - j
	var pos: Vector3 = _normalize(
		p0 * float(k) + p1 * float(i) + p2 * float(j)
	)
	var idx: int = positions.size()
	positions.append(pos)
	return idx


static func _separate_coincident_vertices(positions: Array) -> void:
	var seen: Dictionary = {}
	var quant_scale: float = 1e6
	for i in range(positions.size()):
		var p: Vector3 = positions[i]
		var key: String = "%d,%d,%d" % [
			int(round(p.x * quant_scale)),
			int(round(p.y * quant_scale)),
			int(round(p.z * quant_scale)),
		]
		if seen.has(key):
			var j: int = int(seen[key])
			var nudge: float = float(i - j) * 1e-7
			p.x += nudge
			positions[i] = _normalize(p)
		else:
			seen[key] = i


static func _build_neighbors(cell_count: int, faces: Array) -> Dictionary:
	var adj: Array = []
	adj.resize(cell_count)
	for i in range(cell_count):
		adj[i] = {}

	for tri in faces:
		var verts: Array = [tri[0], tri[1], tri[2]]
		for a in range(3):
			for b in range(a + 1, 3):
				var va: int = verts[a]
				var vb: int = verts[b]
				if va == vb:
					continue
				adj[va][vb] = true
				adj[vb][va] = true

	var neighbors_flat := PackedInt32Array()
	neighbors_flat.resize(cell_count * _MAX_NEIGHBORS)
	neighbors_flat.fill(-1)
	var neighbor_count := PackedByteArray()
	neighbor_count.resize(cell_count)

	for i in range(cell_count):
		var nbr_keys: Array = adj[i].keys()
		nbr_keys.sort()
		var count: int = mini(nbr_keys.size(), _MAX_NEIGHBORS)
		neighbor_count[i] = count
		for slot in range(count):
			neighbors_flat[i * _MAX_NEIGHBORS + slot] = int(nbr_keys[slot])

	return {"neighbors": neighbors_flat, "neighbor_count": neighbor_count}


static func _equirect_index(grid: Dictionary, cell: int, src_w: int, src_h: int) -> int:
	var lons: PackedFloat32Array = grid.lon
	var lats: PackedFloat32Array = grid.lat
	var gx: int = _wrap_floor(_lon_to_u(lons[cell], src_w), src_w)
	var gy: int = _clamp_floor(_lat_to_v(lats[cell], src_h), src_h)
	return gy * src_w + gx


static func _lon_to_u(lon: float, src_w: int) -> float:
	return (lon + PI) / TAU * float(src_w)


static func _lat_to_v(lat: float, src_h: int) -> float:
	return (PI / 2.0 - lat) / PI * float(src_h)


static func _wrap_floor(u: float, src_w: int) -> int:
	var gx: int = int(floor(u))
	if src_w > 0:
		gx = int(posmod(float(gx), float(src_w)))
	return gx


static func _clamp_floor(v: float, src_h: int) -> int:
	if src_h == 0:
		return 0
	return clampi(int(floor(v)), 0, src_h - 1)
