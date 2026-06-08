class_name WorldConquestOutpostBuild
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

const STATE_CONNECTING := "connecting"
const STATE_BUILDING := "building"
const STATE_ACTIVE := "active"

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const _G_INF: int = 0x3FFFFFFF

static var _parent: PackedInt32Array = PackedInt32Array()
static var _g_score: PackedInt32Array = PackedInt32Array()
static var _g_gen: PackedInt32Array = PackedInt32Array()
static var _closed_gen: PackedInt32Array = PackedInt32Array()
static var _open_stamp: PackedInt32Array = PackedInt32Array()
static var _visit_stamp: PackedInt32Array = PackedInt32Array()
static var _source_key: PackedInt32Array = PackedInt32Array()
static var _open: PackedInt32Array = PackedInt32Array()
static var _bfs_queue: PackedInt32Array = PackedInt32Array()
static var _heap_keys: PackedInt32Array = PackedInt32Array()
static var _heap_f: PackedInt32Array = PackedInt32Array()
static var _search_gen: int = 1
static var _land_comp: PackedInt32Array = PackedInt32Array()
static var _land_comp_seed: int = -1


static func operational_sources(structures: Array, home: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if home.x >= 0:
		out.append(home)
	for st: Dictionary in structures:
		if str(st.get("kind", "")) != "spawner":
			continue
		if str(st.get("state", STATE_ACTIVE)) != STATE_ACTIVE:
			continue
		out.append(Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0))))
	return out


## Call once after Earth map generation (cheap; avoids per-click continent floods).
static func prepare_land_components(map_data) -> void:
	if map_data == null:
		return
	if _land_comp_seed == int(map_data.map_seed) and _land_comp.size() == map_data.grid_width * map_data.grid_height:
		return
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	_ensure_bufs(n)
	_land_comp.fill(-1)
	_land_comp_seed = int(map_data.map_seed)
	var queue: PackedInt32Array = PackedInt32Array()
	var comp_id: int = 0
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			var start_key: int = _key(gx, gy, w)
			if _land_comp[start_key] >= 0:
				continue
			queue.clear()
			queue.append(start_key)
			_land_comp[start_key] = comp_id
			var head: int = 0
			while head < queue.size():
				var cur: int = queue[head]
				head += 1
				var cx: int = cur % w
				var cy: int = cur / w
				for d: Vector2i in _DIRS:
					var nx: int = cx + d.x
					var ny: int = cy + d.y
					if ny < 0 or ny >= h:
						continue
					if nx < 0:
						nx = w - 1
					elif nx >= w:
						nx = 0
					if not map_data.is_land_cell(nx, ny):
						continue
					var nk: int = _key(nx, ny, w)
					if _land_comp[nk] >= 0:
						continue
					_land_comp[nk] = comp_id
					queue.append(nk)
			comp_id += 1


## Infrastructure routing only — does not affect territory pressure (land-only sim).
static func nearest_path_to_target(
	map_data,
	target: Vector2i,
	sources: Array[Vector2i],
	_reach_version: int = 0,
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if map_data == null or target.x < 0:
		return empty
	if not map_data.is_land_cell(target.x, target.y):
		return empty
	if _land_comp_seed != int(map_data.map_seed) or _land_comp.is_empty():
		prepare_land_components(map_data)
	if _on_shared_landmass(map_data, target, sources):
		var land_route: Dictionary = _bfs_route_packed(map_data, target, sources, false)
		if not land_route.path_packed.is_empty():
			return land_route
	var bridge: Dictionary = _greedy_bridge_route_packed(map_data, target, sources)
	if not bridge.path_packed.is_empty():
		return bridge
	return _astar_route_packed(map_data, target, sources, true)


static func needs_bridge_route(map_data, target: Vector2i, sources: Array[Vector2i]) -> bool:
	if map_data == null or target.x < 0:
		return false
	if _land_comp_seed != int(map_data.map_seed) or _land_comp.is_empty():
		prepare_land_components(map_data)
	return not _on_shared_landmass(map_data, target, sources)


static func is_water_cell(map_data, gx: int, gy: int) -> bool:
	if map_data == null or gx < 0 or gy < 0:
		return false
	if gx >= map_data.grid_width or gy >= map_data.grid_height:
		return false
	return int(map_data.get_cell_terrain(gx, gy)) == BattleMapDataLib.Terrain.WATER


static func path_to_packed_keys(path: Array[Vector2i], grid_w: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(path.size())
	for i in path.size():
		out[i] = _key(path[i].x, path[i].y, grid_w)
	return out


static func grid_from_packed_key(cell_key: int, grid_w: int) -> Vector2i:
	return Vector2i(cell_key % grid_w, cell_key / grid_w)


static func path_len_from_structure(st: Dictionary) -> int:
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if not packed.is_empty():
		return packed.size()
	return int(st.get("path_len", 0))


static func path_from_structure(st: Dictionary, grid_w: int) -> Array[Vector2i]:
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if not packed.is_empty():
		var out: Array[Vector2i] = []
		out.resize(packed.size())
		for i in packed.size():
			out[i] = grid_from_packed_key(packed[i], grid_w)
		return out
	var out_legacy: Array[Vector2i] = []
	for node in st.get("path", []):
		if node is Dictionary:
			out_legacy.append(Vector2i(int(node.get("gx", 0)), int(node.get("gy", 0))))
	return out_legacy


static func construction_dps_at(map_data, tile_control, gx: int, gy: int) -> float:
	if map_data == null or tile_control == null:
		return 0.0
	if gx < 0 or gy < 0:
		return 0.0
	var idx: int = map_data.cell_index(gx, gy)
	if idx < 0 or idx >= tile_control.owners.size():
		return 0.0
	var owner: int = int(tile_control.owners[idx])
	if owner == BattleTileControlLib.OWNER_FRIENDLY:
		return 0.0
	if owner == BattleTileControlLib.OWNER_HOSTILE:
		return WorldConquestConfigLib.OUTPOST_ENEMY_DPS
	var pf: float = tile_control.pressure_friendly[idx]
	var ph: float = tile_control.pressure_hostile[idx]
	var ratio: float = 1.15
	if idx < tile_control._claim_ratio_mult.size():
		ratio *= tile_control._claim_ratio_mult[idx]
	if ph >= BattleTileControlLib.MIN_CLAIM_PRESSURE and ph > pf * ratio:
		return WorldConquestConfigLib.OUTPOST_ENEMY_DPS
	return 0.0


static func _on_shared_landmass(map_data, target: Vector2i, sources: Array[Vector2i]) -> bool:
	var w: int = map_data.grid_width
	var goal_comp: int = _land_comp[_key(target.x, target.y, w)]
	if goal_comp < 0:
		return false
	for src in sources:
		if src.x < 0 or not map_data.is_land_cell(src.x, src.y):
			continue
		if _land_comp[_key(src.x, src.y, w)] == goal_comp:
			return true
	return false


static func _bfs_route_packed(
	map_data, target: Vector2i, sources: Array[Vector2i], allow_water: bool
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var goal_key: int = _key(target.x, target.y, w)
	_ensure_bufs(w * h)
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	for src in sources:
		if src.x < 0 or not map_data.is_land_cell(src.x, src.y):
			continue
		var sk: int = _key(src.x, src.y, w)
		if _g_gen[sk] == gen:
			continue
		_g_gen[sk] = gen
		_parent[sk] = -1
		_source_key[sk] = sk
		_bfs_queue.append(sk)
	if _bfs_queue.is_empty():
		return empty
	var head: int = 0
	var expanded: int = 0
	while head < _bfs_queue.size():
		if expanded >= WorldConquestConfigLib.OUTPOST_PATHFIND_MAX_EXPAND:
			return empty
		var cur_key: int = _bfs_queue[head]
		head += 1
		if cur_key == goal_key:
			return {
				"path_packed": _reconstruct_packed(cur_key),
				"source": grid_from_packed_key(_source_key[cur_key], w),
			}
		expanded += 1
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		for d: Vector2i in _DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if ny < 0 or ny >= h:
				continue
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
			if not _is_route_cell(map_data, nx, ny, allow_water):
				continue
			var nk: int = _key(nx, ny, w)
			if _g_gen[nk] == gen:
				continue
			_g_gen[nk] = gen
			_parent[nk] = cur_key
			_source_key[nk] = _source_key[cur_key]
			_bfs_queue.append(nk)
	return empty


static func _astar_route_packed(
	map_data, target: Vector2i, sources: Array[Vector2i], allow_water: bool
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var goal_key: int = _key(target.x, target.y, w)
	_ensure_bufs(w * h)
	_bump_search_gen()
	var gen: int = _search_gen
	_heap_clear()
	for src in sources:
		if src.x < 0 or not map_data.is_land_cell(src.x, src.y):
			continue
		var sk: int = _key(src.x, src.y, w)
		_g_score[sk] = 0
		_g_gen[sk] = gen
		_parent[sk] = -1
		_source_key[sk] = sk
		_heap_push(sk, _heuristic_key(sk, goal_key, w))
	if _heap_keys.is_empty():
		return empty
	var expanded: int = 0
	while not _heap_keys.is_empty():
		if expanded >= WorldConquestConfigLib.OUTPOST_PATHFIND_MAX_EXPAND:
			return empty
		var cur_key: int = _heap_pop()
		if cur_key < 0:
			return empty
		if _closed_gen[cur_key] == gen:
			continue
		_closed_gen[cur_key] = gen
		if cur_key == goal_key:
			return {
				"path_packed": _reconstruct_packed(cur_key),
				"source": grid_from_packed_key(_source_key[cur_key], w),
			}
		expanded += 1
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		var cur_g: int = _g_score[cur_key]
		for d: Vector2i in _DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if ny < 0 or ny >= h:
				continue
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
			if not _is_route_cell(map_data, nx, ny, allow_water):
				continue
			var nk: int = _key(nx, ny, w)
			var step: int = 2 if is_water_cell(map_data, nx, ny) else 1
			var tentative: int = cur_g + step
			if _closed_gen[nk] == gen:
				continue
			if _g_gen[nk] != gen or tentative < _g_score[nk]:
				_g_gen[nk] = gen
				_g_score[nk] = tentative
				_parent[nk] = cur_key
				_source_key[nk] = _source_key[cur_key]
				_heap_push(nk, tentative + _heuristic_key(nk, goal_key, w))
	return empty


static func _heap_clear() -> void:
	_heap_keys.clear()
	_heap_f.clear()


static func _heap_swap(i: int, j: int) -> void:
	var tk: int = _heap_keys[i]
	_heap_keys[i] = _heap_keys[j]
	_heap_keys[j] = tk
	var tf: int = _heap_f[i]
	_heap_f[i] = _heap_f[j]
	_heap_f[j] = tf


static func _heap_push(key: int, f: int) -> void:
	_heap_keys.append(key)
	_heap_f.append(f)
	var i: int = _heap_keys.size() - 1
	while i > 0:
		var p: int = (i - 1) >> 1
		if _heap_f[p] <= _heap_f[i]:
			break
		_heap_swap(i, p)
		i = p


static func _heap_pop() -> int:
	var n: int = _heap_keys.size()
	if n == 0:
		return -1
	var out: int = _heap_keys[0]
	if n == 1:
		_heap_keys.resize(0)
		_heap_f.resize(0)
		return out
	_heap_keys[0] = _heap_keys[n - 1]
	_heap_f[0] = _heap_f[n - 1]
	_heap_keys.resize(n - 1)
	_heap_f.resize(n - 1)
	var i: int = 0
	while true:
		var l: int = i * 2 + 1
		var r: int = l + 1
		var smallest: int = i
		if l < _heap_keys.size() and _heap_f[l] < _heap_f[smallest]:
			smallest = l
		if r < _heap_keys.size() and _heap_f[r] < _heap_f[smallest]:
			smallest = r
		if smallest == i:
			break
		_heap_swap(i, smallest)
		i = smallest
	return out


static func _greedy_bridge_route_packed(
	map_data, target: Vector2i, sources: Array[Vector2i]
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var goal_key: int = _key(target.x, target.y, w)
	_ensure_bufs(w * h)
	_bump_search_gen()
	var gen: int = _search_gen
	var start_key: int = -1
	var start_h: int = _G_INF
	for src in sources:
		if src.x < 0 or not map_data.is_land_cell(src.x, src.y):
			continue
		var sk: int = _key(src.x, src.y, w)
		var hh: int = _heuristic_key(sk, goal_key, w)
		if hh < start_h:
			start_h = hh
			start_key = sk
	if start_key < 0:
		return empty
	var path := PackedInt32Array()
	var cur_key: int = start_key
	path.append(cur_key)
	_visit_stamp[cur_key] = gen
	var max_steps: int = w + h + 128
	for _step in max_steps:
		if cur_key == goal_key:
			return {
				"path_packed": path,
				"source": grid_from_packed_key(start_key, w),
			}
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		var cur_h: int = _heuristic_key(cur_key, goal_key, w)
		var best_key: int = -1
		var best_h: int = _G_INF
		var equal_key: int = -1
		var uphill_key: int = -1
		for d: Vector2i in _DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if ny < 0 or ny >= h:
				continue
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
			if not _is_route_cell(map_data, nx, ny, true):
				continue
			var nk: int = _key(nx, ny, w)
			if _visit_stamp[nk] == gen:
				continue
			var nh: int = _heuristic_key(nk, goal_key, w)
			if nh < best_h:
				best_h = nh
				best_key = nk
			elif nh == cur_h and equal_key < 0:
				equal_key = nk
			elif nh == cur_h + 1 and uphill_key < 0:
				uphill_key = nk
		if best_key < 0:
			best_key = equal_key
		if best_key < 0:
			best_key = uphill_key
		if best_key < 0:
			return empty
		_visit_stamp[best_key] = gen
		cur_key = best_key
		path.append(cur_key)
	return empty


static func _heuristic_key(cell_key: int, goal_key: int, w: int) -> int:
	var gx: int = cell_key % w
	var gy: int = cell_key / w
	var tx: int = goal_key % w
	var ty: int = goal_key / w
	var dx: int = absi(tx - gx)
	dx = mini(dx, w - dx)
	var dy: int = absi(ty - gy)
	return dx + dy


static func _reconstruct_packed(goal_key: int) -> PackedInt32Array:
	var length: int = 0
	var cur: int = goal_key
	while cur >= 0:
		length += 1
		cur = _parent[cur]
	var out := PackedInt32Array()
	out.resize(length)
	cur = goal_key
	for i in range(length - 1, -1, -1):
		out[i] = cur
		cur = _parent[cur]
	return out


static func _bump_search_gen() -> void:
	_search_gen += 1
	if _search_gen >= 0x7FFFFFF0:
		_g_gen.fill(0)
		_closed_gen.fill(0)
		_open_stamp.fill(0)
		_visit_stamp.fill(0)
		_search_gen = 1


static func _ensure_bufs(cell_count: int) -> void:
	if _parent.size() < cell_count:
		_parent.resize(cell_count)
		_g_score.resize(cell_count)
		_g_gen.resize(cell_count)
		_closed_gen.resize(cell_count)
		_open_stamp.resize(cell_count)
		_visit_stamp.resize(cell_count)
		_source_key.resize(cell_count)
		_land_comp.resize(cell_count)


static func _is_route_cell(map_data, gx: int, gy: int, allow_water: bool) -> bool:
	if map_data == null or gx < 0 or gy < 0:
		return false
	if gx >= map_data.grid_width or gy >= map_data.grid_height:
		return false
	if map_data.is_land_cell(gx, gy):
		return true
	if not allow_water:
		return false
	return int(map_data.get_cell_terrain(gx, gy)) == BattleMapDataLib.Terrain.WATER


static func _key(gx: int, gy: int, w: int) -> int:
	return gy * w + gx
