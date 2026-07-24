class_name WorldConquestOutpostBuild
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const EconomyLib := preload("res://EconomyLib.gd")

const STATE_CONNECTING := "connecting"
const STATE_BUILDING := "building"
const STATE_ACTIVE := "active"

const KIND_SPAWNER := "spawner"
const KIND_BARRACKS := "barracks"
const KIND_HANGAR := "hangar"
const KIND_CORRIDOR_LINK := "corridor_link"

## Road paint hierarchy (R8 class bytes for globe overlay).
const ROAD_CLASS_NONE := 0
const ROAD_CLASS_SPUR := 1
const ROAD_CLASS_ARTERIAL := 2
const ROAD_CLASS_BRIDGE := 3
const ROAD_CLASS_PLANNED := 4
const ROAD_CLASS_SHOULDER := 5
const ROAD_CLASS_PLANNED_SHOULDER := 6


static func is_corridor_path_kind(kind: String) -> bool:
	return (
		kind == KIND_SPAWNER
		or kind == KIND_BARRACKS
		or kind == KIND_HANGAR
		or kind == KIND_CORRIDOR_LINK
	)


static func is_pressure_spawner_kind(kind: String) -> bool:
	return kind == KIND_SPAWNER


static func has_build_phase(kind: String) -> bool:
	return kind == KIND_SPAWNER or kind == KIND_BARRACKS or kind == KIND_HANGAR


static func build_sec_for_kind(kind: String) -> float:
	return EconomyLib.build_sec_for_kind(kind)

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
static var _snap_cache_seed: int = -1
static var _snap_cache_click_key: int = -1
static var _snap_cache_landing: Vector2i = Vector2i(-1, -1)


static func invalidate_snap_cache() -> void:
	_snap_cache_seed = -1
	_snap_cache_click_key = -1
	_snap_cache_landing = Vector2i(-1, -1)


## Pack static terrain + infrastructure masks for Rust route planner.
static func pack_route_snapshot(map_data, structures: Array) -> Dictionary:
	return pack_route_snapshot_for_team(
		map_data, structures, BattleTileControlLib.OWNER_FRIENDLY
	)


static func pack_route_snapshot_for_team(
	map_data, structures: Array, team: int
) -> Dictionary:
	if map_data == null:
		return {}
	if map_data.sphere_mode:
		return _pack_route_snapshot_sphere(map_data, structures, team)
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	if n <= 0:
		return {}
	prepare_land_components(map_data)
	var land_mask := PackedByteArray()
	var land_comp_out := PackedInt32Array()
	var infra_mask := PackedByteArray()
	land_mask.resize(n)
	land_comp_out.resize(n)
	infra_mask.resize(n)
	var road_cells: Dictionary = road_cells_for_team(map_data, structures, team)
	var bridge_mask: PackedByteArray = _bridge_mask_for_team(map_data, team, structures)
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			land_mask[idx] = 1 if map_data.is_land_cell(gx, gy) else 0
			land_comp_out[idx] = _land_comp[idx] if idx < _land_comp.size() else -1
			var infra: bool = road_cells.has(idx)
			if idx < bridge_mask.size() and bridge_mask[idx] != 0:
				infra = true
			infra_mask[idx] = 1 if infra else 0
	return {
		"grid_w": w,
		"grid_h": h,
		"wrap_longitude": true,
		"land_mask": land_mask,
		"bridge_mask": infra_mask,
		"land_comp": land_comp_out,
		"cell_positions": PackedFloat32Array(),
	}


static func _pack_route_snapshot_sphere(
	map_data, structures: Array, team: int
) -> Dictionary:
	var n: int = map_data.cell_count
	if n <= 0:
		return {}
	var land_mask := PackedByteArray()
	var land_comp_out := PackedInt32Array()
	var infra_mask := PackedByteArray()
	land_mask.resize(n)
	land_comp_out.resize(n)
	infra_mask.resize(n)
	land_comp_out.fill(-1)
	var road_cells: Dictionary = road_cells_for_team(map_data, structures, team)
	var bridge_mask: PackedByteArray = _bridge_mask_for_team(map_data, team, structures)
	for cid in range(n):
		land_mask[cid] = 1 if map_data.is_land_cell_id(cid) else 0
		var infra: bool = road_cells.has(cid)
		if cid < bridge_mask.size() and bridge_mask[cid] != 0:
			infra = true
		infra_mask[cid] = 1 if infra else 0
	var comp_id: int = 0
	for start in range(n):
		if land_comp_out[start] >= 0 or land_mask[start] == 0:
			continue
		var queue: Array[int] = [start]
		land_comp_out[start] = comp_id
		var qi: int = 0
		while qi < queue.size():
			var cur: int = queue[qi]
			qi += 1
			for nbr: int in map_data.get_neighbors(cur):
				if land_comp_out[nbr] >= 0 or land_mask[nbr] == 0:
					continue
				land_comp_out[nbr] = comp_id
				queue.append(nbr)
		comp_id += 1
	var cell_positions := PackedFloat32Array()
	if map_data.cell_positions.size() >= n:
		cell_positions.resize(n * 3)
		for cid in range(n):
			var p: Vector3 = map_data.cell_positions[cid]
			var base: int = cid * 3
			cell_positions[base] = p.x
			cell_positions[base + 1] = p.y
			cell_positions[base + 2] = p.z
	return {
		"grid_w": n,
		"grid_h": 1,
		"wrap_longitude": false,
		"land_mask": land_mask,
		"bridge_mask": infra_mask,
		"land_comp": land_comp_out,
		"graph_neighbors": map_data.neighbors,
		"graph_neighbor_count": map_data.neighbor_counts,
		"cell_positions": cell_positions,
	}


## Road/bridge infra only — avoids re-scanning the full land grid on every road cell.
static func pack_infra_mask_only(map_data, structures: Array) -> PackedByteArray:
	return pack_infra_mask_for_team(
		map_data, structures, BattleTileControlLib.OWNER_FRIENDLY
	)


static func pack_infra_mask_for_team(map_data, structures: Array, team: int) -> PackedByteArray:
	if map_data == null:
		return PackedByteArray()
	var n: int = map_data.gameplay_tile_count()
	if n <= 0:
		return PackedByteArray()
	var infra_mask := PackedByteArray()
	infra_mask.resize(n)
	infra_mask.fill(0)
	var road_cells: Dictionary = road_cells_for_team(map_data, structures, team)
	for key in road_cells:
		var idx: int = int(key)
		if idx >= 0 and idx < n:
			infra_mask[idx] = 1
	var bridge_mask: PackedByteArray = _bridge_mask_for_team(map_data, team, structures)
	for idx in range(n):
		if idx < bridge_mask.size() and bridge_mask[idx] != 0:
			infra_mask[idx] = 1
	return infra_mask


static func resource_supply_hubs(
	structures: Array,
	home: Vector2i,
	map_data = null,
	team: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var key: String = ""
	if home.x >= 0:
		out.append(home)
		seen["%d,%d" % [home.x, home.y]] = true
	for st: Dictionary in structures:
		if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
			continue
		if str(st.get("kind", "")) != "spawner":
			continue
		if str(st.get("state", STATE_ACTIVE)) != STATE_ACTIVE:
			continue
		var pt: Vector2i = Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0)))
		key = "%d,%d" % [pt.x, pt.y]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(pt)
	if map_data != null:
		for corridor: Dictionary in map_data.bridge_corridors:
			if int(corridor.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
				continue
			var bx: int = int(corridor.get("gx", -1))
			var by: int = int(corridor.get("gy", -1))
			if bx < 0:
				continue
			key = "%d,%d" % [bx, by]
			if seen.has(key):
				continue
			seen[key] = true
			out.append(Vector2i(bx, by))
	return out


static func operational_sources(
	structures: Array,
	home: Vector2i,
	map_data = null,
	team: int = BattleTileControlLib.OWNER_FRIENDLY,
	network_built: PackedByteArray = PackedByteArray(),
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var key: String = ""
	if home.x >= 0:
		out.append(home)
		seen["%d,%d" % [home.x, home.y]] = true
	for st: Dictionary in structures:
		if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
			continue
		if str(st.get("kind", "")) != "spawner":
			continue
		if str(st.get("state", STATE_ACTIVE)) != STATE_ACTIVE:
			continue
		var pt: Vector2i = Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0)))
		key = "%d,%d" % [pt.x, pt.y]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(pt)
	if map_data != null:
		for corridor: Dictionary in map_data.bridge_corridors:
			if int(corridor.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
				continue
			var bx: int = int(corridor.get("gx", -1))
			var by: int = int(corridor.get("gy", -1))
			if bx < 0:
				continue
			key = "%d,%d" % [bx, by]
			if seen.has(key):
				continue
			seen[key] = true
			out.append(Vector2i(bx, by))
	out.append_array(connecting_road_frontiers(map_data, structures, team, seen, network_built))
	return out


static func path_prefix_built_len(path: PackedInt32Array, built_mask: PackedByteArray) -> int:
	if path.is_empty():
		return 0
	var n: int = 0
	for key: int in path:
		if key < 0 or key >= built_mask.size() or built_mask[key] == 0:
			break
		n += 1
	return maxi(n, 1)


## Road tips of in-progress outposts — allows branching while earlier roads are still building.
static func connecting_road_frontiers(
	map_data,
	structures: Array,
	team: int,
	seen: Dictionary,
	network_built: PackedByteArray = PackedByteArray(),
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if map_data == null:
		return out
	var w: int = gameplay_grid_w(map_data)
	for st: Dictionary in structures:
		if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
			continue
		var kind: String = str(st.get("kind", ""))
		if not is_corridor_path_kind(kind) or kind == KIND_CORRIDOR_LINK:
			continue
		if str(st.get("state", STATE_CONNECTING)) != STATE_CONNECTING:
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		if packed.is_empty():
			continue
		var built: int = int(floor(float(st.get("path_built", 1.0))))
		built = clampi(built, 1, packed.size())
		var frontier_key: int = packed[built - 1]
		var pt: Vector2i = grid_from_packed_key(frontier_key, w, map_data)
		var dedupe: String = "%d,%d" % [pt.x, pt.y]
		if seen.has(dedupe):
			continue
		seen[dedupe] = true
		out.append(pt)
	return out


## Call once after Earth map generation (cheap; avoids per-click continent floods).
static func prepare_land_components(map_data) -> void:
	if map_data == null:
		return
	if map_data.sphere_mode:
		_prepare_land_components_sphere(map_data)
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


static func _prepare_land_components_sphere(map_data) -> void:
	var n: int = map_data.cell_count
	if _land_comp_seed == int(map_data.map_seed) and _land_comp.size() == n:
		return
	_ensure_bufs(n)
	_land_comp.fill(-1)
	_land_comp_seed = int(map_data.map_seed)
	var queue: PackedInt32Array = PackedInt32Array()
	var comp_id: int = 0
	for start in range(n):
		if not map_data.is_land_cell_id(start):
			continue
		if _land_comp[start] >= 0:
			continue
		queue.clear()
		queue.append(start)
		_land_comp[start] = comp_id
		var head: int = 0
		while head < queue.size():
			var cur: int = queue[head]
			head += 1
			for nbr: int in map_data.get_neighbors(cur):
				if nbr < 0 or nbr >= n:
					continue
				if not map_data.is_land_cell_id(nbr):
					continue
				if _land_comp[nbr] >= 0:
					continue
				_land_comp[nbr] = comp_id
				queue.append(nbr)
		comp_id += 1


## Infrastructure routing only — does not affect territory pressure (land-only sim).
static func nearest_path_to_target(
	map_data,
	target: Vector2i,
	sources: Array[Vector2i],
	_reach_version: int = 0,
	allow_astar: bool = true,
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
	var structures: Array = _structures_for_map(map_data)
	var infra_route: Dictionary = _bfs_infrastructure_route_packed(
		map_data,
		target,
		sources,
		_bridge_mask_for_team(map_data, BattleTileControlLib.OWNER_FRIENDLY, structures),
	)
	if not infra_route.path_packed.is_empty():
		return infra_route
	var bridge_land_route: Dictionary = _land_route_from_bridge_landing(
		map_data, target, BattleTileControlLib.OWNER_FRIENDLY
	)
	if not bridge_land_route.path_packed.is_empty():
		return bridge_land_route
	var bridge: Dictionary = _greedy_bridge_route_packed(map_data, target, sources)
	if not bridge.path_packed.is_empty():
		return bridge
	if allow_astar:
		return _astar_route_packed(map_data, target, sources, true)
	return empty


## Land Bridge routing: short land leg to a departure coast, water-only crossing, landing coast.
## Longitude wraps at the map seam (x=0 connects to x=width-1) like the globe mesh.
static func nearest_corridor_path_to_target(
	map_data,
	landing: Vector2i,
	sources: Array[Vector2i],
	_allow_astar: bool = true,
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if map_data == null or landing.x < 0 or not map_data.is_land_cell(landing.x, landing.y):
		return empty
	if not is_coastal_cell(map_data, landing.x, landing.y):
		return empty
	if map_data.sphere_mode:
		return _nearest_corridor_path_to_target_sphere(
			map_data, landing, sources, _allow_astar
		)
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var landing_key: int = _key(landing.x, landing.y, w)
	var landing_water: PackedInt32Array = _water_neighbor_keys(map_data, landing.x, landing.y)
	if landing_water.is_empty():
		return empty
	_ensure_bufs(w * h)
	_bump_search_gen()
	var water_gen: int = _search_gen
	if not _bfs_water_back_to_goals(map_data, landing_water, water_gen):
		return empty
	var best_coast: int = -1
	var best_dep: int = -1
	var best_source_key: int = -1
	var best_len: int = _G_INF
	_bump_search_gen()
	var land_gen: int = _search_gen
	_bfs_queue.clear()
	for src in sources:
		if src.x < 0 or not map_data.is_land_cell(src.x, src.y):
			continue
		var sk: int = _key(src.x, src.y, w)
		if _g_gen[sk] == land_gen:
			continue
		_g_gen[sk] = land_gen
		_g_score[sk] = 0
		_parent[sk] = -1
		_source_key[sk] = sk
		_bfs_queue.append(sk)
	if _bfs_queue.is_empty():
		return empty
	var head: int = 0
	while head < _bfs_queue.size():
		var cur_key: int = _bfs_queue[head]
		head += 1
		var cur_dist: int = _g_score[cur_key]
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		if cur_dist + 3 < best_len and _cell_has_water_neighbor(map_data, cx, cy):
			var dep_water: PackedInt32Array = _water_neighbor_keys(map_data, cx, cy)
			for wi in dep_water.size():
				var dep_key: int = dep_water[wi]
				if _g_gen[dep_key] != water_gen:
					continue
				var total: int = cur_dist + _g_score[dep_key] + 3
				if total < best_len:
					best_len = total
					best_coast = cur_key
					best_dep = dep_key
					best_source_key = _source_key[cur_key]
		for d: Vector2i in _DIRS:
			var nxy: Vector2i = _wrap_neighbor_xy(cx, cy, d.x, d.y, w, h)
			if nxy.x < 0:
				continue
			if not map_data.is_land_cell(nxy.x, nxy.y):
				continue
			var nk: int = _key(nxy.x, nxy.y, w)
			if _g_gen[nk] == land_gen:
				continue
			_g_gen[nk] = land_gen
			_g_score[nk] = cur_dist + 1
			_parent[nk] = cur_key
			_source_key[nk] = _source_key[cur_key]
			_bfs_queue.append(nk)
	if best_coast < 0:
		return empty
	var land_path: PackedInt32Array = _reconstruct_packed(best_coast)
	var water_path: PackedInt32Array = _packed_path_reversed(_reconstruct_packed(best_dep))
	var full: PackedInt32Array = _join_bridge_path(land_path, water_path, landing_key)
	if full.is_empty() or not is_valid_bridge_path(map_data, full):
		return empty
	return {
		"path_packed": full,
		"source": grid_from_packed_key(best_source_key, w, map_data),
	}


static func _nearest_corridor_path_to_target_sphere(
	map_data,
	landing: Vector2i,
	sources: Array[Vector2i],
	_allow_astar: bool = true,
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if map_data == null or landing.x < 0 or not map_data.is_land_cell_id(landing.x):
		return empty
	if not is_coastal_cell(map_data, landing.x, landing.y):
		return empty
	var n: int = map_data.cell_count
	var landing_key: int = landing.x
	var landing_water: PackedInt32Array = _water_neighbor_keys(map_data, landing.x, landing.y)
	if landing_water.is_empty():
		return empty
	_ensure_bufs(n)
	_bump_search_gen()
	var water_gen: int = _search_gen
	if not _bfs_water_back_to_goals(map_data, landing_water, water_gen):
		return empty
	var best_coast: int = -1
	var best_dep: int = -1
	var best_source_key: int = -1
	var best_len: int = _G_INF
	_bump_search_gen()
	var land_gen: int = _search_gen
	_bfs_queue.clear()
	for src in sources:
		if src.x < 0 or not map_data.is_land_cell_id(src.x):
			continue
		var sk: int = src.x
		if _g_gen[sk] == land_gen:
			continue
		_g_gen[sk] = land_gen
		_g_score[sk] = 0
		_parent[sk] = -1
		_source_key[sk] = sk
		_bfs_queue.append(sk)
	if _bfs_queue.is_empty():
		return empty
	var head: int = 0
	while head < _bfs_queue.size():
		var cur_key: int = _bfs_queue[head]
		head += 1
		var cur_dist: int = _g_score[cur_key]
		if cur_dist + 3 < best_len and _cell_has_water_neighbor(map_data, cur_key, 0):
			var dep_water: PackedInt32Array = _water_neighbor_keys(map_data, cur_key, 0)
			for wi in dep_water.size():
				var dep_key: int = dep_water[wi]
				if _g_gen[dep_key] != water_gen:
					continue
				var total: int = cur_dist + _g_score[dep_key] + 3
				if total < best_len:
					best_len = total
					best_coast = cur_key
					best_dep = dep_key
					best_source_key = _source_key[cur_key]
		for nbr: int in map_data.get_neighbors(cur_key):
			if nbr < 0 or nbr >= n:
				continue
			if not map_data.is_land_cell_id(nbr):
				continue
			if _g_gen[nbr] == land_gen:
				continue
			_g_gen[nbr] = land_gen
			_g_score[nbr] = cur_dist + 1
			_parent[nbr] = cur_key
			_source_key[nbr] = _source_key[cur_key]
			_bfs_queue.append(nbr)
	if best_coast < 0:
		return empty
	var land_path: PackedInt32Array = _reconstruct_packed(best_coast)
	var water_path: PackedInt32Array = _packed_path_reversed(_reconstruct_packed(best_dep))
	var full: PackedInt32Array = _join_bridge_path(land_path, water_path, landing_key)
	if full.is_empty() or not is_valid_bridge_path(map_data, full):
		return empty
	return {
		"path_packed": full,
		"source": Vector2i(best_source_key, 0),
	}


static func is_valid_bridge_path(map_data, packed: PackedInt32Array) -> bool:
	if packed.size() < 2 or map_data == null:
		return false
	if map_data.sphere_mode:
		var phase: int = 0
		var saw_water: bool = false
		for i in packed.size():
			var cid: int = packed[i]
			if cid < 0 or cid >= map_data.cell_count:
				return false
			var water: bool = is_water_cell(map_data, cid, 0)
			if phase == 0:
				if water:
					phase = 1
					saw_water = true
				elif not map_data.is_land_cell_id(cid):
					return false
			elif phase == 1:
				if water:
					pass
				elif map_data.is_land_cell_id(cid):
					if i != packed.size() - 1:
						return false
					phase = 2
				else:
					return false
			if i > 0 and not _sphere_graph_adjacent(map_data, packed[i - 1], packed[i]):
				return false
		return saw_water and phase == 2
	var w: int = map_data.grid_width
	var phase: int = 0
	var saw_water: bool = false
	for i in packed.size():
		var gx: int = packed[i] % w
		var gy: int = packed[i] / w
		var water: bool = is_water_cell(map_data, gx, gy)
		if phase == 0:
			if water:
				phase = 1
				saw_water = true
			elif not map_data.is_land_cell(gx, gy):
				return false
		elif phase == 1:
			if water:
				pass
			elif map_data.is_land_cell(gx, gy):
				if i != packed.size() - 1:
					return false
				phase = 2
			else:
				return false
		if i > 0 and not _cardinal_adjacent(
			grid_from_packed_key(packed[i - 1], w, map_data),
			grid_from_packed_key(packed[i], w, map_data),
			w,
		):
			return false
	return saw_water and phase == 2


static func needs_bridge_route(
	map_data,
	target: Vector2i,
	sources: Array[Vector2i],
	team: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> bool:
	if map_data == null or target.x < 0:
		return false
	if _land_comp_seed != int(map_data.map_seed) or _land_comp.is_empty():
		prepare_land_components(map_data)
	if _on_shared_landmass(map_data, target, sources):
		return false
	if _reachable_via_bridges(map_data, target, sources, team):
		return false
	return true


static func merge_infra_masks(base: PackedByteArray, extra: PackedByteArray) -> PackedByteArray:
	if base.is_empty():
		return extra
	if extra.is_empty():
		return base
	var n: int = mini(base.size(), extra.size())
	for i in range(n):
		if extra[i] != 0:
			base[i] = 1
	return base


## Trim a hub→landing path to the spur from the last built∪planned cell (option B).
## Does not pathfind — place-time only after a route is found. Land bridges skip this.
static func trim_path_to_network_spur(
	path: PackedInt32Array, route_mask: PackedByteArray
) -> PackedInt32Array:
	if path.is_empty() or route_mask.is_empty():
		return path
	var attach: int = -1
	for i in range(path.size()):
		var key: int = int(path[i])
		if key >= 0 and key < route_mask.size() and route_mask[key] != 0:
			attach = i
	if attach < 0:
		return path
	if attach == 0:
		return path
	return path.slice(attach)


static func classify_road_class(kind: String, path_len: int) -> int:
	if kind == KIND_CORRIDOR_LINK:
		return ROAD_CLASS_BRIDGE
	if path_len <= WorldConquestConfigLib.ROAD_SPUR_MAX_CELLS:
		return ROAD_CLASS_SPUR
	return ROAD_CLASS_ARTERIAL


## Cosmetic 3-wide band: path cell = white center; exactly one black cell on each
## side perpendicular to travel (left/right or "above/below" on the surface).
## Never picks path cells, water (land roads), or L-corner fill cells (those cause blobs).
static func road_shoulder_cells(
	map_data, path: PackedInt32Array, index: int, bridge_path: bool = false
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if bridge_path or map_data == null or path.is_empty() or index < 0 or index >= path.size():
		return out
	var curr: int = int(path[index])
	if curr < 0:
		return out
	var path_set: Dictionary = {}
	for k in path:
		path_set[int(k)] = true
	var prev: int = int(path[index - 1]) if index > 0 else -1
	var next: int = int(path[index + 1]) if index + 1 < path.size() else -1
	if prev < 0 and next >= 0:
		prev = next
	if next < 0 and prev >= 0:
		next = prev
	if not map_data.sphere_mode:
		return _road_shoulder_cells_rect(map_data, curr, prev, next, path_set)
	var pc: Vector3 = _road_cell_pos(map_data, curr)
	if pc.length_squared() < 0.0001:
		return out
	var tangent := Vector3.ZERO
	if prev >= 0 and next >= 0:
		tangent = _road_cell_pos(map_data, next) - _road_cell_pos(map_data, prev)
	elif prev >= 0:
		tangent = pc - _road_cell_pos(map_data, prev)
	elif next >= 0:
		tangent = _road_cell_pos(map_data, next) - pc
	if tangent.length_squared() < 0.0001:
		return out
	var normal: Vector3 = pc.normalized()
	var side: Vector3 = normal.cross(tangent)
	if side.length_squared() < 0.0001:
		return out
	side = side.normalized()
	var best_pos: int = -1
	var best_neg: int = -1
	var best_pos_score: float = 0.0
	var best_neg_score: float = 0.0
	for nbr in map_data.get_neighbors(curr):
		var n: int = int(nbr)
		if n < 0 or path_set.has(n):
			continue
		if not map_data.is_land_cell_id(n):
			continue
		# Skip the inside corner of an L-bend — that cell turns a 3-wide ribbon into a blob.
		if prev >= 0 and next >= 0 and prev != next:
			if _road_cells_adjacent(map_data, n, prev) and _road_cells_adjacent(map_data, n, next):
				continue
		var lateral: Vector3 = _road_cell_pos(map_data, n) - pc
		# Project off the radial so score is pure left/right along the surface.
		lateral = lateral - normal * lateral.dot(normal)
		if lateral.length_squared() < 0.0001:
			continue
		var score: float = lateral.normalized().dot(side)
		# Require a clear side vote — no weak "almost along the path" picks.
		if score > 0.25 and score > best_pos_score:
			best_pos_score = score
			best_pos = n
		elif score < -0.25 and score < best_neg_score:
			best_neg_score = score
			best_neg = n
	if best_pos >= 0:
		out.append(best_pos)
	if best_neg >= 0 and best_neg != best_pos:
		out.append(best_neg)
	return out


## Rect maps: if travel is mostly horizontal → black above/below; else black left/right.
static func _road_shoulder_cells_rect(
	map_data, curr: int, prev: int, next: int, path_set: Dictionary
) -> PackedInt32Array:
	var out := PackedInt32Array()
	var w: int = gameplay_grid_w(map_data)
	if w <= 0:
		return out
	var c: Vector2i = grid_from_packed_key(curr, w, map_data)
	var tangent := Vector2i.ZERO
	if prev >= 0 and next >= 0:
		var p: Vector2i = grid_from_packed_key(prev, w, map_data)
		var n: Vector2i = grid_from_packed_key(next, w, map_data)
		tangent = Vector2i(n.x - p.x, n.y - p.y)
	elif prev >= 0:
		var p2: Vector2i = grid_from_packed_key(prev, w, map_data)
		tangent = Vector2i(c.x - p2.x, c.y - p2.y)
	elif next >= 0:
		var n2: Vector2i = grid_from_packed_key(next, w, map_data)
		tangent = Vector2i(n2.x - c.x, n2.y - c.y)
	# Wrap dx on cylinder.
	if tangent.x > w / 2:
		tangent.x -= w
	elif tangent.x < -w / 2:
		tangent.x += w
	var side_a: Vector2i
	var side_b: Vector2i
	if absi(tangent.x) >= absi(tangent.y):
		# Moving horizontally (or tied) → shoulders north/south.
		side_a = Vector2i(0, -1)
		side_b = Vector2i(0, 1)
	else:
		# Moving vertically → shoulders west/east.
		side_a = Vector2i(-1, 0)
		side_b = Vector2i(1, 0)
	for side: Vector2i in [side_a, side_b]:
		var g := Vector2i(c.x + side.x, c.y + side.y)
		if map_data.sphere_mode:
			continue
		if g.y < 0 or g.y >= map_data.grid_height:
			continue
		g.x = posmod(g.x, w)
		if not map_data.is_land_cell(g.x, g.y):
			continue
		var key: int = _key(g.x, g.y, w)
		if path_set.has(key):
			continue
		if prev >= 0 and next >= 0 and prev != next:
			if _road_cells_adjacent(map_data, key, prev) and _road_cells_adjacent(map_data, key, next):
				continue
		out.append(key)
	return out


static func _road_cells_adjacent(map_data, a: int, b: int) -> bool:
	if map_data == null or a < 0 or b < 0 or a == b:
		return false
	for nbr in map_data.get_neighbors(a):
		if int(nbr) == b:
			return true
	return false


static func _road_cell_pos(map_data, cell_id: int) -> Vector3:
	if map_data == null or cell_id < 0:
		return Vector3.ZERO
	if map_data.sphere_mode and cell_id < map_data.cell_positions.size():
		return map_data.cell_positions[cell_id]
	var w: int = gameplay_grid_w(map_data)
	if w <= 0:
		return Vector3.ZERO
	var g: Vector2i = grid_from_packed_key(cell_id, w, map_data)
	return Vector3(float(g.x), 0.0, float(g.y))


## Road/outpost routing cells: built outpost paths plus completed land-bridge corridors.
static func road_cells_for_team(
	map_data,
	structures: Array,
	team: int,
	network_built: PackedByteArray = PackedByteArray(),
) -> Dictionary:
	var out: Dictionary = {}
	for st: Dictionary in structures:
		if int(st.get("team", 0)) != team:
			continue
		var kind: String = str(st.get("kind", ""))
		# All road-bearing structures: outposts, barracks, hangars.
		if kind != KIND_SPAWNER and kind != KIND_BARRACKS and kind != KIND_HANGAR:
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		if packed.is_empty():
			continue
		var state: String = str(st.get("state", STATE_ACTIVE))
		var built: int = packed.size()
		if state == STATE_CONNECTING:
			built = int(floor(float(st.get("path_built", 1.0))))
		built = clampi(built, 1, packed.size())
		for i in built:
			out[packed[i]] = true
	if map_data == null:
		return out
	var bridge_mask: PackedByteArray = _bridge_mask_for_team(map_data, team, structures)
	for i in range(bridge_mask.size()):
		if bridge_mask[i] != 0:
			out[i] = true
	return out


static func _reachable_via_bridges(
	map_data,
	target: Vector2i,
	sources: Array[Vector2i],
	team: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> bool:
	var route: Dictionary = _bfs_infrastructure_route_packed(
		map_data,
		target,
		sources,
		_bridge_mask_for_team(map_data, team, _structures_for_map(map_data)),
	)
	return not route.path_packed.is_empty()


static func _bridge_mask_for_team(map_data, team: int, structures: Array = []) -> PackedByteArray:
	var n: int = map_data.gameplay_tile_count() if map_data != null else 0
	var mask := PackedByteArray()
	mask.resize(n)
	mask.fill(0)
	if map_data == null or n <= 0:
		return mask
	for corridor: Dictionary in map_data.bridge_corridors:
		if int(corridor.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
			continue
		var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		for key: int in packed:
			if key >= 0 and key < n:
				mask[key] = 1
	for st: Dictionary in structures:
		if int(st.get("team", 0)) != team:
			continue
		if str(st.get("kind", "")) != KIND_CORRIDOR_LINK:
			continue
		var state: String = str(st.get("state", STATE_ACTIVE))
		if state != STATE_CONNECTING and state != STATE_BUILDING:
			continue
		var packed_st: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		if packed_st.is_empty():
			continue
		var built: int = int(floor(float(st.get("path_built", 1.0))))
		built = clampi(built, 1, packed_st.size())
		for i in range(built):
			var key: int = packed_st[i]
			if key >= 0 and key < n:
				mask[key] = 1
	return mask


static func _structures_for_map(map_data) -> Array:
	if map_data == null:
		return []
	return map_data.placed_structures


static func _nearest_bridge_landing_for_target(map_data, target: Vector2i, team: int) -> Vector2i:
	if map_data == null or target.x < 0:
		return Vector2i(-1, -1)
	if _land_comp_seed != int(map_data.map_seed) or _land_comp.is_empty():
		prepare_land_components(map_data)
	var sphere: bool = bool(map_data.sphere_mode)
	var w: int = map_data.grid_width
	var goal_comp: int = -1
	if sphere:
		if target.x < 0 or target.x >= _land_comp.size():
			return Vector2i(-1, -1)
		goal_comp = int(_land_comp[target.x])
	else:
		goal_comp = _land_comp[_key(target.x, target.y, w)]
	if goal_comp < 0:
		return Vector2i(-1, -1)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for corridor: Dictionary in map_data.bridge_corridors:
		if int(corridor.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
			continue
		var gx: int = int(corridor.get("gx", -1))
		var gy: int = int(corridor.get("gy", -1))
		if gx < 0:
			continue
		if sphere:
			if not map_data.is_land_cell_id(gx):
				continue
			if gx >= _land_comp.size() or int(_land_comp[gx]) != goal_comp:
				continue
			if (
				target.x < 0
				or gx < 0
				or target.x >= map_data.cell_positions.size()
				or gx >= map_data.cell_positions.size()
			):
				continue
			var pa: Vector3 = map_data.cell_positions[target.x].normalized()
			var pb: Vector3 = map_data.cell_positions[gx].normalized()
			var ang: float = acos(clampf(pa.dot(pb), -1.0, 1.0))
			if ang < best_d:
				best_d = ang
				best = Vector2i(gx, 0)
		else:
			if not map_data.is_land_cell(gx, gy):
				continue
			if _land_comp[_key(gx, gy, w)] != goal_comp:
				continue
			var dx: int = gx - target.x
			var dy: int = gy - target.y
			var d2: float = float(dx * dx + dy * dy)
			if d2 < best_d:
				best_d = d2
				best = Vector2i(gx, gy)
	return best


static func _land_route_from_bridge_landing(map_data, target: Vector2i, team: int) -> Dictionary:
	var landing: Vector2i = _nearest_bridge_landing_for_target(map_data, target, team)
	if landing.x < 0:
		return {"path_packed": PackedInt32Array(), "source": Vector2i(-1, -1)}
	return _bfs_route_packed(map_data, target, [landing], false)


static func _is_infrastructure_cell(
	map_data, gx: int, gy: int, bridge_mask: PackedByteArray
) -> bool:
	if map_data == null or gx < 0:
		return false
	if map_data.sphere_mode:
		if gx >= map_data.cell_count:
			return false
		if gx < bridge_mask.size() and bridge_mask[gx] != 0:
			return true
		return _is_route_cell(map_data, gx, 0, false)
	if gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
		return false
	var idx: int = map_data.cell_index(gx, gy)
	if idx >= 0 and idx < bridge_mask.size() and bridge_mask[idx] != 0:
		return true
	return _is_route_cell(map_data, gx, gy, false)


static func _bfs_infrastructure_route_packed(
	map_data,
	target: Vector2i,
	sources: Array[Vector2i],
	bridge_mask: PackedByteArray,
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if map_data == null or target.x < 0 or bridge_mask.is_empty():
		return empty
	if map_data.sphere_mode:
		return _bfs_infrastructure_route_packed_sphere(
			map_data, target, sources, bridge_mask
		)
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var goal_key: int = _key(target.x, target.y, w)
	_ensure_bufs(w * h)
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	for src in sources:
		if src.x < 0 or not _is_infrastructure_cell(map_data, src.x, src.y, bridge_mask):
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
				"source": grid_from_packed_key(_source_key[cur_key], w, map_data),
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
			if not _is_infrastructure_cell(map_data, nx, ny, bridge_mask):
				continue
			var nk: int = _key(nx, ny, w)
			if _g_gen[nk] == gen:
				continue
			_g_gen[nk] = gen
			_parent[nk] = cur_key
			_source_key[nk] = _source_key[cur_key]
			_bfs_queue.append(nk)
	return empty


static func _bfs_infrastructure_route_packed_sphere(
	map_data,
	target: Vector2i,
	sources: Array[Vector2i],
	bridge_mask: PackedByteArray,
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var n: int = map_data.cell_count
	var goal_key: int = target.x
	if goal_key < 0 or goal_key >= n:
		return empty
	_ensure_bufs(n)
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	for src in sources:
		if src.x < 0 or not _is_infrastructure_cell(map_data, src.x, 0, bridge_mask):
			continue
		var sk: int = src.x
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
				"source": Vector2i(_source_key[cur_key], 0),
			}
		expanded += 1
		for nbr: int in map_data.get_neighbors(cur_key):
			if nbr < 0 or nbr >= n:
				continue
			if not _is_infrastructure_cell(map_data, nbr, 0, bridge_mask):
				continue
			if _g_gen[nbr] == gen:
				continue
			_g_gen[nbr] = gen
			_parent[nbr] = cur_key
			_source_key[nbr] = _source_key[cur_key]
			_bfs_queue.append(nbr)
	return empty


## Land tile with water, pole edge, or wrapped seam water on a cardinal neighbor.
static func is_coastal_cell(map_data, gx: int, gy: int) -> bool:
	if map_data == null:
		return false
	if map_data.sphere_mode:
		if gx < 0 or gx >= map_data.cell_count or not map_data.is_land_cell_id(gx):
			return false
		for nbr: int in map_data.get_neighbors(gx):
			if is_water_cell(map_data, nbr, 0):
				return true
		return false
	if not map_data.is_land_cell(gx, gy):
		return false
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for d: Vector2i in _DIRS:
		var nxy: Vector2i = _wrap_neighbor_xy(gx, gy, d.x, d.y, w, h)
		if nxy.x < 0:
			return true
		if is_water_cell(map_data, nxy.x, nxy.y):
			return true
	return false


## Nearest coastal tile on the same land component as click (BFS on land).
static func snap_to_nearest_coast(
	map_data, click: Vector2i, allow_longitude_wrap: bool = true
) -> Vector2i:
	if map_data == null or click.x < 0:
		return Vector2i(-1, -1)
	if map_data.sphere_mode:
		if not map_data.is_land_cell_id(click.x):
			return Vector2i(-1, -1)
		if _land_comp_seed != int(map_data.map_seed) or _land_comp.is_empty():
			prepare_land_components(map_data)
		var click_key: int = click.x
		if (
			_snap_cache_seed == int(map_data.map_seed)
			and _snap_cache_click_key == click_key
			and _snap_cache_landing.x >= 0
		):
			return _snap_cache_landing
		if is_coastal_cell(map_data, click.x, click.y):
			_snap_cache_seed = int(map_data.map_seed)
			_snap_cache_click_key = click_key
			_snap_cache_landing = click
			return click
		var n: int = map_data.cell_count
		var goal_comp: int = _land_comp[click.x]
		if goal_comp < 0:
			return Vector2i(-1, -1)
		_ensure_bufs(n)
		_bump_search_gen()
		var gen: int = _search_gen
		_bfs_queue.clear()
		var start_key: int = click.x
		_g_gen[start_key] = gen
		_parent[start_key] = -1
		_bfs_queue.append(start_key)
		var head: int = 0
		while head < _bfs_queue.size():
			var cur_key: int = _bfs_queue[head]
			head += 1
			if is_coastal_cell(map_data, cur_key, 0):
				var found: Vector2i = Vector2i(cur_key, 0)
				_snap_cache_seed = int(map_data.map_seed)
				_snap_cache_click_key = click_key
				_snap_cache_landing = found
				return found
			for nbr: int in map_data.get_neighbors(cur_key):
				if nbr < 0 or nbr >= n:
					continue
				if not map_data.is_land_cell_id(nbr):
					continue
				if _land_comp[nbr] != goal_comp:
					continue
				if _g_gen[nbr] == gen:
					continue
				_g_gen[nbr] = gen
				_parent[nbr] = cur_key
				_bfs_queue.append(nbr)
		return Vector2i(-1, -1)
	if not map_data.is_land_cell(click.x, click.y):
		return Vector2i(-1, -1)
	if _land_comp_seed != int(map_data.map_seed) or _land_comp.is_empty():
		prepare_land_components(map_data)
	var click_key: int = _key(click.x, click.y, map_data.grid_width)
	if (
		_snap_cache_seed == int(map_data.map_seed)
		and _snap_cache_click_key == click_key
		and _snap_cache_landing.x >= 0
	):
		return _snap_cache_landing
	if is_coastal_cell(map_data, click.x, click.y):
		_snap_cache_seed = int(map_data.map_seed)
		_snap_cache_click_key = click_key
		_snap_cache_landing = click
		return click
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var goal_comp: int = _land_comp[_key(click.x, click.y, w)]
	if goal_comp < 0:
		return Vector2i(-1, -1)
	_ensure_bufs(w * h)
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	var start_key: int = _key(click.x, click.y, w)
	_g_gen[start_key] = gen
	_parent[start_key] = -1
	_bfs_queue.append(start_key)
	var head: int = 0
	while head < _bfs_queue.size():
		var cur_key: int = _bfs_queue[head]
		head += 1
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		if is_coastal_cell(map_data, cx, cy):
			var found: Vector2i = Vector2i(cx, cy)
			_snap_cache_seed = int(map_data.map_seed)
			_snap_cache_click_key = click_key
			_snap_cache_landing = found
			return found
		for d: Vector2i in _DIRS:
			var nxy: Vector2i
			if allow_longitude_wrap:
				nxy = _wrap_neighbor_xy(cx, cy, d.x, d.y, w, h)
			else:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if ny < 0 or ny >= h or nx < 0 or nx >= w:
					continue
				nxy = Vector2i(nx, ny)
			if nxy.x < 0:
				continue
			if not map_data.is_land_cell(nxy.x, nxy.y):
				continue
			if _land_comp[_key(nxy.x, nxy.y, w)] != goal_comp:
				continue
			var nk: int = _key(nxy.x, nxy.y, w)
			if _g_gen[nk] == gen:
				continue
			_g_gen[nk] = gen
			_parent[nk] = cur_key
			_bfs_queue.append(nk)
	return Vector2i(-1, -1)


static func subsample_path_for_preview(
	path_packed: PackedInt32Array, max_segments: int
) -> PackedInt32Array:
	if path_packed.size() <= 1 or max_segments < 1:
		return path_packed
	var max_pts: int = max_segments + 1
	if path_packed.size() <= max_pts:
		return path_packed
	var out := PackedInt32Array()
	out.resize(max_pts)
	for i in max_pts:
		var src_i: int = int(round(float(i) * float(path_packed.size() - 1) / float(max_pts - 1)))
		out[i] = path_packed[src_i]
	return out


## Foreign landmass clicks snap to nearest coast; same-landmass uses raw click unless snap_inland.
static func resolve_invasion_target(
	map_data,
	click: Vector2i,
	sources: Array[Vector2i],
	snap_inland_to_coast: bool = false,
	team: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> Vector2i:
	if map_data == null or click.x < 0:
		return Vector2i(-1, -1)
	if snap_inland_to_coast:
		if is_coastal_cell(map_data, click.x, click.y):
			return click
		return snap_to_nearest_coast(map_data, click, true)
	if not needs_bridge_route(map_data, click, sources, team):
		return click
	return snap_to_nearest_coast(map_data, click)


static func is_water_cell(map_data, gx: int, gy: int) -> bool:
	if map_data == null or gx < 0:
		return false
	if map_data.sphere_mode:
		if gy != 0 or gx >= map_data.cell_count:
			return false
		return not map_data.is_land_cell_id(gx)
	if gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
		return false
	return int(map_data.get_cell_terrain(gx, gy)) == BattleMapDataLib.Terrain.WATER


static func path_to_packed_keys(path: Array[Vector2i], grid_w: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(path.size())
	for i in path.size():
		out[i] = _key(path[i].x, path[i].y, grid_w)
	return out


static func gameplay_grid_w(map_data) -> int:
	return map_data.cell_count if map_data.sphere_mode else map_data.grid_width


static func grid_from_packed_key(cell_key: int, grid_w: int, map_data = null) -> Vector2i:
	if map_data != null and map_data.sphere_mode:
		return Vector2i(cell_key, 0)
	return Vector2i(cell_key % grid_w, cell_key / grid_w)


## Ensure each path step is one cardinal tile apart (longitude seam counts as adjacent).
static func path_is_cardinal_dense(map_data, packed: PackedInt32Array) -> bool:
	if packed.size() < 2 or map_data == null:
		return true
	if map_data.sphere_mode:
		for i in range(1, packed.size()):
			if not _sphere_graph_adjacent(map_data, packed[i - 1], packed[i]):
				return false
		return true
	var w: int = map_data.grid_width
	for i in range(1, packed.size()):
		var a: Vector2i = grid_from_packed_key(packed[i - 1], w, map_data)
		var b: Vector2i = grid_from_packed_key(packed[i], w, map_data)
		if not _cardinal_adjacent(a, b, w):
			return false
	return true


static func densify_path_cardinal(map_data, packed: PackedInt32Array) -> PackedInt32Array:
	if path_is_cardinal_dense(map_data, packed):
		return packed
	if packed.size() < 2 or map_data == null:
		return packed
	if map_data.sphere_mode:
		var out_sphere := PackedInt32Array()
		out_sphere.append(packed[0])
		for i in range(1, packed.size()):
			var prev_key: int = out_sphere[out_sphere.size() - 1]
			var goal_key: int = packed[i]
			if _sphere_graph_adjacent(map_data, prev_key, goal_key):
				out_sphere.append(goal_key)
				continue
			var connector_sphere: PackedInt32Array = _connector_path_sphere(
				map_data, prev_key, goal_key
			)
			for j in range(1, connector_sphere.size()):
				out_sphere.append(connector_sphere[j])
		return out_sphere
	var w: int = map_data.grid_width
	var out := PackedInt32Array()
	out.append(packed[0])
	for i in range(1, packed.size()):
		var prev: Vector2i = grid_from_packed_key(out[out.size() - 1], w, map_data)
		var goal: Vector2i = grid_from_packed_key(packed[i], w, map_data)
		if _cardinal_adjacent(prev, goal, w):
			out.append(packed[i])
			continue
		var connector: PackedInt32Array = _connector_path_cardinal(map_data, prev, goal, true)
		for j in range(1, connector.size()):
			out.append(connector[j])
	return out


static func _sphere_graph_adjacent(map_data, a_key: int, b_key: int) -> bool:
	for nbr: int in map_data.get_neighbors(a_key):
		if nbr == b_key:
			return true
	return false


static func _connector_path_sphere(map_data, from_key: int, to_key: int) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if map_data == null or from_key == to_key:
		empty.append(from_key)
		return empty
	var n: int = map_data.cell_count
	if from_key < 0 or to_key < 0 or from_key >= n or to_key >= n:
		return empty
	_ensure_bufs(n)
	_bump_search_gen()
	var gen: int = _search_gen
	_parent[from_key] = -1
	_g_gen[from_key] = gen
	_bfs_queue.clear()
	_bfs_queue.append(from_key)
	var head: int = 0
	var expanded: int = 0
	while head < _bfs_queue.size():
		expanded += 1
		if expanded >= WorldConquestConfigLib.OUTPOST_PATHFIND_MAX_EXPAND:
			return empty
		var cur_key: int = _bfs_queue[head]
		head += 1
		if cur_key == to_key:
			return _reconstruct_packed(to_key)
		for nbr: int in map_data.get_neighbors(cur_key):
			if nbr < 0 or nbr >= n:
				continue
			if not map_data.is_land_cell_id(nbr):
				continue
			if _g_gen[nbr] == gen:
				continue
			_g_gen[nbr] = gen
			_parent[nbr] = cur_key
			_bfs_queue.append(nbr)
	return empty


static func _cardinal_adjacent(a: Vector2i, b: Vector2i, grid_w: int) -> bool:
	var dx: int = absi(a.x - b.x)
	dx = mini(dx, grid_w - dx)
	var dy: int = absi(a.y - b.y)
	return dx + dy == 1


static func _connector_path_cardinal(
	map_data, from: Vector2i, to: Vector2i, allow_water: bool
) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if map_data == null or from == to:
		empty.append(_key(from.x, from.y, map_data.grid_width))
		return empty
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var goal_key: int = _key(to.x, to.y, w)
	var start_key: int = _key(from.x, from.y, w)
	_ensure_bufs(w * h)
	_bump_search_gen()
	var gen: int = _search_gen
	_parent[start_key] = -1
	_g_gen[start_key] = gen
	_bfs_queue.clear()
	_bfs_queue.append(start_key)
	var head: int = 0
	var expanded: int = 0
	while head < _bfs_queue.size():
		expanded += 1
		if expanded >= WorldConquestConfigLib.OUTPOST_PATHFIND_MAX_EXPAND:
			return empty
		var cur_key: int = _bfs_queue[head]
		head += 1
		if cur_key == goal_key:
			return _reconstruct_packed(goal_key)
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		for d: Vector2i in _DIRS:
			var nxy: Vector2i = _wrap_neighbor_xy(cx, cy, d.x, d.y, w, h)
			if nxy.x < 0:
				continue
			if not _is_route_cell(map_data, nxy.x, nxy.y, allow_water):
				continue
			var nk: int = _key(nxy.x, nxy.y, w)
			if _g_gen[nk] == gen:
				continue
			_g_gen[nk] = gen
			_parent[nk] = cur_key
			_bfs_queue.append(nk)
	return empty


static func path_len_from_structure(st: Dictionary) -> int:
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if not packed.is_empty():
		return packed.size()
	return int(st.get("path_len", 0))


static func path_from_structure(
	st: Dictionary, grid_w: int, map_data = null
) -> Array[Vector2i]:
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if not packed.is_empty():
		var out: Array[Vector2i] = []
		out.resize(packed.size())
		for i in packed.size():
			out[i] = grid_from_packed_key(packed[i], grid_w, map_data)
		return out
	var out_legacy: Array[Vector2i] = []
	for node in st.get("path", []):
		if node is Dictionary:
			out_legacy.append(Vector2i(int(node.get("gx", 0)), int(node.get("gy", 0))))
	return out_legacy


static func construction_dps_at(
	map_data, grid, gx: int, gy: int, team: int = BattleTileControlLib.OWNER_FRIENDLY
) -> float:
	if map_data == null or grid == null:
		return 0.0
	if gx < 0 or gy < 0:
		return 0.0
	var idx: int = map_data.cell_index(gx, gy)
	var owners_size: int = idx
	if grid.has_method("grid_cell_count"):
		owners_size = int(grid.grid_cell_count())
	elif "owners" in grid:
		owners_size = grid.owners.size()
	if idx < 0 or idx >= owners_size:
		return 0.0
	var owner: int = BattleTileControlLib.OWNER_NEUTRAL
	if grid.has_method("owner_at_index"):
		owner = int(grid.owner_at_index(idx))
	elif "owners" in grid:
		owner = int(grid.owners[idx])
	var own_p: float = 0.0
	var opp_p: float = 0.0
	if grid.has_method("pressure_friendly_at"):
		var pf: float = float(grid.pressure_friendly_at(idx))
		var ph: float = float(grid.pressure_hostile_at(idx))
		if team == BattleTileControlLib.OWNER_FRIENDLY:
			own_p = pf
			opp_p = ph
		else:
			own_p = ph
			opp_p = pf
	elif "pressure_friendly" in grid and "pressure_hostile" in grid:
		var pf2: float = grid.pressure_friendly[idx]
		var ph2: float = grid.pressure_hostile[idx]
		if team == BattleTileControlLib.OWNER_FRIENDLY:
			own_p = pf2
			opp_p = ph2
		else:
			own_p = ph2
			opp_p = pf2
	var ratio: float = 1.15
	if grid.has_method("claim_ratio_mult_at"):
		ratio *= float(grid.claim_ratio_mult_at(idx))
	elif "_claim_ratio_mult" in grid and idx < grid._claim_ratio_mult.size():
		ratio *= grid._claim_ratio_mult[idx]
	if opp_p >= BattleTileControlLib.MIN_CLAIM_PRESSURE and opp_p > own_p * ratio:
		return WorldConquestConfigLib.OUTPOST_ENEMY_DPS
	if owner == team:
		return 0.0
	if owner == BattleTileControlLib.OWNER_FRIENDLY or owner == BattleTileControlLib.OWNER_HOSTILE:
		return WorldConquestConfigLib.OUTPOST_ENEMY_DPS
	return 0.0


static func _on_shared_landmass(map_data, target: Vector2i, sources: Array[Vector2i]) -> bool:
	if map_data.sphere_mode:
		if target.x < 0 or target.x >= map_data.cell_count:
			return false
		var goal_comp: int = _land_comp[target.x] if target.x < _land_comp.size() else -1
		if goal_comp < 0:
			return false
		for src in sources:
			if src.x < 0 or src.x >= map_data.cell_count:
				continue
			if not map_data.is_land_cell_id(src.x):
				continue
			if src.x < _land_comp.size() and _land_comp[src.x] == goal_comp:
				return true
		return false
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
	if map_data.sphere_mode:
		return _bfs_route_packed_sphere(map_data, target, sources, allow_water)
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
				"source": grid_from_packed_key(_source_key[cur_key], w, map_data),
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


static func _bfs_route_packed_sphere(
	map_data, target: Vector2i, sources: Array[Vector2i], allow_water: bool
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var n: int = map_data.cell_count
	var goal_key: int = target.x
	if goal_key < 0 or goal_key >= n:
		return empty
	_ensure_bufs(n)
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	for src in sources:
		if src.x < 0 or src.x >= n:
			continue
		if not map_data.is_land_cell_id(src.x) and not (
			allow_water and src.x < map_data.terrain_cells.size()
		):
			if not _is_route_cell(map_data, src.x, 0, allow_water):
				continue
		elif not _is_route_cell(map_data, src.x, 0, allow_water):
			continue
		var sk: int = src.x
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
				"source": Vector2i(_source_key[cur_key], 0),
			}
		expanded += 1
		for nbr: int in map_data.get_neighbors(cur_key):
			if nbr < 0 or nbr >= n:
				continue
			if not _is_route_cell(map_data, nbr, 0, allow_water):
				continue
			if _g_gen[nbr] == gen:
				continue
			_g_gen[nbr] = gen
			_parent[nbr] = cur_key
			_source_key[nbr] = _source_key[cur_key]
			_bfs_queue.append(nbr)
	return empty


static func _astar_route_packed(
	map_data, target: Vector2i, sources: Array[Vector2i], allow_water: bool
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if map_data.sphere_mode:
		return _astar_route_packed_sphere(map_data, target, sources, allow_water)
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
				"source": grid_from_packed_key(_source_key[cur_key], w, map_data),
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


static func _astar_route_packed_sphere(
	map_data, target: Vector2i, sources: Array[Vector2i], allow_water: bool
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var n: int = map_data.cell_count
	var goal_key: int = target.x
	if goal_key < 0 or goal_key >= n:
		return empty
	_ensure_bufs(n)
	_bump_search_gen()
	var gen: int = _search_gen
	_heap_clear()
	for src in sources:
		if src.x < 0 or src.x >= n:
			continue
		if not map_data.is_land_cell_id(src.x) and not (
			allow_water and src.x < map_data.terrain_cells.size()
		):
			if not _is_route_cell(map_data, src.x, 0, allow_water):
				continue
		elif not _is_route_cell(map_data, src.x, 0, allow_water):
			continue
		var sk: int = src.x
		_g_score[sk] = 0
		_g_gen[sk] = gen
		_parent[sk] = -1
		_source_key[sk] = sk
		_heap_push(sk, _heuristic_key_sphere(map_data, sk, goal_key))
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
				"source": Vector2i(_source_key[cur_key], 0),
			}
		expanded += 1
		var cur_g: int = _g_score[cur_key]
		for nbr: int in map_data.get_neighbors(cur_key):
			if nbr < 0 or nbr >= n:
				continue
			if not _is_route_cell(map_data, nbr, 0, allow_water):
				continue
			var step: int = _sphere_edge_step_cost(map_data, cur_key, nbr, allow_water)
			var tentative: int = cur_g + step
			if _closed_gen[nbr] == gen:
				continue
			if _g_gen[nbr] != gen or tentative < _g_score[nbr]:
				_g_gen[nbr] = gen
				_g_score[nbr] = tentative
				_parent[nbr] = cur_key
				_source_key[nbr] = _source_key[cur_key]
				_heap_push(
					nbr, tentative + _heuristic_key_sphere(map_data, nbr, goal_key)
				)
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
	if map_data.sphere_mode:
		return _greedy_bridge_route_packed_sphere(map_data, target, sources)
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
				"source": grid_from_packed_key(start_key, w, map_data),
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


static func _greedy_bridge_route_packed_sphere(
	map_data, target: Vector2i, sources: Array[Vector2i]
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	var n: int = map_data.cell_count
	var goal_key: int = target.x
	if goal_key < 0 or goal_key >= n:
		return empty
	_ensure_bufs(n)
	_bump_search_gen()
	var gen: int = _search_gen
	var start_key: int = -1
	var start_h: int = _G_INF
	for src in sources:
		if src.x < 0 or src.x >= n or not map_data.is_land_cell_id(src.x):
			continue
		var sk: int = src.x
		var hh: int = _heuristic_key_sphere(map_data, sk, goal_key)
		if hh < start_h:
			start_h = hh
			start_key = sk
	if start_key < 0:
		return empty
	var path := PackedInt32Array()
	var cur_key: int = start_key
	path.append(cur_key)
	_visit_stamp[cur_key] = gen
	var max_steps: int = n + 128
	for _step in max_steps:
		if cur_key == goal_key:
			return {
				"path_packed": path,
				"source": Vector2i(start_key, 0),
			}
		var cur_h: int = _heuristic_key_sphere(map_data, cur_key, goal_key)
		var best_key: int = -1
		var best_h: int = _G_INF
		var equal_key: int = -1
		var uphill_key: int = -1
		for nbr: int in map_data.get_neighbors(cur_key):
			if nbr < 0 or nbr >= n:
				continue
			if not _is_route_cell(map_data, nbr, 0, true):
				continue
			if _visit_stamp[nbr] == gen:
				continue
			var nh: int = _heuristic_key_sphere(map_data, nbr, goal_key)
			if nh < best_h:
				best_h = nh
				best_key = nbr
			elif nh == cur_h and equal_key < 0:
				equal_key = nbr
			elif nh == cur_h + 1 and uphill_key < 0:
				uphill_key = nbr
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


static func _heuristic_key_sphere(map_data, cell_key: int, goal_key: int) -> int:
	if map_data == null or cell_key < 0 or goal_key < 0:
		return _G_INF
	var positions: PackedVector3Array = map_data.cell_positions
	if cell_key >= positions.size() or goal_key >= positions.size():
		return _G_INF
	# Chord distance — admissible for chord-sum edge costs (triangle inequality).
	return maxi(1, int(round(positions[cell_key].distance_to(positions[goal_key]) * 10000.0)))


static func _sphere_edge_step_cost(map_data, from_key: int, to_key: int, allow_water: bool) -> int:
	var terrain: int = 2 if is_water_cell(map_data, to_key, 0) else 1
	if not allow_water:
		terrain = 1
	var positions: PackedVector3Array = map_data.cell_positions
	if from_key < 0 or to_key < 0 or from_key >= positions.size() or to_key >= positions.size():
		return terrain
	var chord: int = maxi(1, int(round(positions[from_key].distance_to(positions[to_key]) * 10000.0)))
	return chord * terrain


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
	if map_data == null or gx < 0:
		return false
	if map_data.sphere_mode:
		if gy != 0 or gx >= map_data.cell_count:
			return false
		if map_data.is_land_cell_id(gx):
			return true
		if not allow_water:
			return false
		return int(map_data.get_cell_terrain(gx, 0)) == BattleMapDataLib.Terrain.WATER
	if gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
		return false
	if map_data.is_land_cell(gx, gy):
		return true
	if not allow_water:
		return false
	return int(map_data.get_cell_terrain(gx, gy)) == BattleMapDataLib.Terrain.WATER


static func _wrap_neighbor_xy(gx: int, gy: int, dx: int, dy: int, w: int, h: int) -> Vector2i:
	var nx: int = gx + dx
	var ny: int = gy + dy
	if ny < 0 or ny >= h:
		return Vector2i(-1, -1)
	if nx < 0:
		nx = w - 1
	elif nx >= w:
		nx = 0
	return Vector2i(nx, ny)


static func _cell_has_water_neighbor(map_data, gx: int, gy: int) -> bool:
	if map_data == null:
		return false
	if map_data.sphere_mode:
		if gx < 0 or gx >= map_data.cell_count:
			return false
		for nbr: int in map_data.get_neighbors(gx):
			if is_water_cell(map_data, nbr, 0):
				return true
		return false
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for d: Vector2i in _DIRS:
		var nxy: Vector2i = _wrap_neighbor_xy(gx, gy, d.x, d.y, w, h)
		if nxy.x < 0:
			return true
		if is_water_cell(map_data, nxy.x, nxy.y):
			return true
	return false


static func _water_neighbor_keys(map_data, gx: int, gy: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if map_data == null:
		return out
	if map_data.sphere_mode:
		if gx < 0 or gx >= map_data.cell_count:
			return out
		for nbr: int in map_data.get_neighbors(gx):
			if is_water_cell(map_data, nbr, 0):
				out.append(nbr)
		return out
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for d: Vector2i in _DIRS:
		var nxy: Vector2i = _wrap_neighbor_xy(gx, gy, d.x, d.y, w, h)
		if nxy.x < 0:
			continue
		if is_water_cell(map_data, nxy.x, nxy.y):
			out.append(_key(nxy.x, nxy.y, w))
	return out


static func _bfs_water_back_to_goals(
	map_data, goal_water_keys: PackedInt32Array, gen: int
) -> bool:
	if map_data != null and map_data.sphere_mode:
		var n: int = map_data.cell_count
		_bfs_queue.clear()
		for i in goal_water_keys.size():
			var gk: int = goal_water_keys[i]
			if gk < 0 or gk >= n:
				continue
			if _g_gen[gk] == gen:
				continue
			_g_gen[gk] = gen
			_g_score[gk] = 0
			_parent[gk] = -1
			_bfs_queue.append(gk)
		if _bfs_queue.is_empty():
			return false
		var head: int = 0
		var expanded: int = 0
		while head < _bfs_queue.size():
			var cur_key: int = _bfs_queue[head]
			head += 1
			expanded += 1
			if expanded >= WorldConquestConfigLib.OUTPOST_PATHFIND_MAX_EXPAND:
				return false
			var cur_dist: int = _g_score[cur_key]
			for nbr: int in map_data.get_neighbors(cur_key):
				if nbr < 0 or nbr >= n:
					continue
				if not is_water_cell(map_data, nbr, 0):
					continue
				if _g_gen[nbr] == gen:
					continue
				_g_gen[nbr] = gen
				_g_score[nbr] = cur_dist + 1
				_parent[nbr] = cur_key
				_bfs_queue.append(nbr)
		return true
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	_bfs_queue.clear()
	for i in goal_water_keys.size():
		var gk: int = goal_water_keys[i]
		if _g_gen[gk] == gen:
			continue
		_g_gen[gk] = gen
		_g_score[gk] = 0
		_parent[gk] = -1
		_bfs_queue.append(gk)
	if _bfs_queue.is_empty():
		return false
	var head: int = 0
	var expanded: int = 0
	while head < _bfs_queue.size():
		var cur_key: int = _bfs_queue[head]
		head += 1
		expanded += 1
		if expanded >= WorldConquestConfigLib.OUTPOST_PATHFIND_MAX_EXPAND:
			return false
		var cur_dist: int = _g_score[cur_key]
		var cx: int = cur_key % w
		var cy: int = cur_key / w
		for d: Vector2i in _DIRS:
			var nxy: Vector2i = _wrap_neighbor_xy(cx, cy, d.x, d.y, w, h)
			if nxy.x < 0:
				continue
			if not is_water_cell(map_data, nxy.x, nxy.y):
				continue
			var nk: int = _key(nxy.x, nxy.y, w)
			if _g_gen[nk] == gen:
				continue
			_g_gen[nk] = gen
			_g_score[nk] = cur_dist + 1
			_parent[nk] = cur_key
			_bfs_queue.append(nk)
	return true


static func _packed_path_reversed(packed: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(packed.size())
	for i in packed.size():
		out[i] = packed[packed.size() - 1 - i]
	return out


static func _join_bridge_path(
	land_path: PackedInt32Array, water_path: PackedInt32Array, landing_key: int
) -> PackedInt32Array:
	if land_path.is_empty() or water_path.is_empty():
		return PackedInt32Array()
	var out := PackedInt32Array()
	out.append_array(land_path)
	if out[out.size() - 1] != water_path[0]:
		out.append(water_path[0])
	for i in range(1, water_path.size()):
		if water_path[i] == out[out.size() - 1]:
			continue
		out.append(water_path[i])
	if out[out.size() - 1] != landing_key:
		out.append(landing_key)
	return out


static func _key(gx: int, gy: int, w: int) -> int:
	return gy * w + gx
