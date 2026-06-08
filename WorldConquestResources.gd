class_name WorldConquestResources
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")

const TYPE_AURELIUM := 0
const TYPE_VERDANTITE := 1
const TYPE_EMBERSTONE := 2

const PHASE_IDLE := "idle"
const PHASE_LINKING := "linking"
const PHASE_HAULING := "hauling"

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

static var _site_states: Dictionary = {}
static var _roads_cache: Dictionary = {}
static var _roads_cache_version: int = -1
static var _bfs_parent: PackedInt32Array = PackedInt32Array()
static var _bfs_gen: PackedInt32Array = PackedInt32Array()
static var _bfs_queue: PackedInt32Array = PackedInt32Array()
static var _search_gen: int = 1


static func reset() -> void:
	_site_states.clear()
	_roads_cache.clear()
	_roads_cache_version = -1


static func tick(
	map_data,
	tile_control,
	structures: Array,
	player_home: Vector2i,
	enemy_home: Vector2i,
	delta: float,
	structure_version: int = 0,
	road_network_version: int = 0,
) -> Dictionary:
	var network_key: int = structure_version * 100000 + road_network_version
	var result := {
		"friendly": [0.0, 0.0, 0.0],
		"hostile": [0.0, 0.0, 0.0],
		"pulses": [],
		"links_dirty": false,
	}
	if map_data == null or tile_control == null or delta <= 0.0:
		return result
	var deposits: Array = map_data.resource_deposits
	if deposits.is_empty():
		return result
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	_ensure_bufs(n)
	var friendly_roads: Dictionary = _road_cells_for_team_cached(
		structures, BattleTileControlLib.OWNER_FRIENDLY, network_key
	)
	var hostile_roads: Dictionary = {}
	var friendly_hubs: Array[Vector2i] = OutpostBuildLib.operational_sources(structures, player_home)
	var hostile_hubs: Array[Vector2i] = []
	if enemy_home.x >= 0:
		hostile_hubs.append(enemy_home)
	var links_dirty: bool = false
	var pulse_cap: int = WorldConquestConfigLib.RESOURCE_MAX_VISUAL_PULSES
	for dep: Dictionary in deposits:
		var dep_id: int = int(dep.get("id", -1))
		if dep_id < 0:
			continue
		var gx: int = int(dep.get("gx", 0))
		var gy: int = int(dep.get("gy", 0))
		var idx: int = map_data.cell_index(gx, gy)
		if idx < 0 or idx >= tile_control.owners.size():
			continue
		var owner: int = int(tile_control.owners[idx])
		var team: int = 0
		if owner == BattleTileControlLib.OWNER_FRIENDLY:
			team = BattleTileControlLib.OWNER_FRIENDLY
		elif owner == BattleTileControlLib.OWNER_HOSTILE:
			team = BattleTileControlLib.OWNER_HOSTILE
		var state: Dictionary = _site_state(dep_id)
		if team == 0:
			if not state.is_empty():
				_reset_site(dep_id)
				links_dirty = true
			continue
		if int(state.get("team", 0)) != team:
			_reset_site(dep_id)
			state = _site_state(dep_id)
			links_dirty = true
		state["team"] = team
		state["type"] = int(dep.get("type", 0))
		state["gx"] = gx
		state["gy"] = gy
		state["yield_per_sec"] = float(dep.get("yield_per_sec", 1.0))
		var phase: String = str(state.get("phase", PHASE_IDLE))
		var roads: Dictionary = friendly_roads if team == BattleTileControlLib.OWNER_FRIENDLY else hostile_roads
		var hubs: Array[Vector2i] = friendly_hubs if team == BattleTileControlLib.OWNER_FRIENDLY else hostile_hubs
		if phase == PHASE_IDLE:
			var retry_v: int = int(state.get("link_retry_version", -1))
			if retry_v == network_key and bool(state.get("link_pending", false)):
				continue
			var link_path: PackedInt32Array = _plan_link_path(
				map_data, tile_control, gx, gy, team, roads, hubs, w, h
			)
			state["link_retry_version"] = network_key
			if link_path.is_empty():
				state["link_pending"] = true
				continue
			state["link_pending"] = false
			state["phase"] = PHASE_LINKING
			state["link_path"] = link_path
			state["link_built"] = 1.0
			state["haul_path"] = PackedInt32Array()
			state["pulses"] = []
			state["yield_acc"] = 0.0
			links_dirty = true
			phase = PHASE_LINKING
		if phase == PHASE_LINKING:
			var built: float = float(state.get("link_built", 1.0))
			var link_path_l: PackedInt32Array = state.get("link_path", PackedInt32Array())
			var prev_cells: int = int(floor(built))
			built += WorldConquestConfigLib.RESOURCE_LINK_CELLS_PER_SEC * delta
			state["link_built"] = built
			if int(floor(built)) != prev_cells:
				links_dirty = true
			if built >= float(link_path_l.size()):
				var haul: PackedInt32Array = _build_haul_path(
					map_data, link_path_l, roads, hubs, w, h
				)
				if haul.is_empty():
					state["phase"] = PHASE_IDLE
					state.erase("link_path")
					state["link_built"] = 0.0
				else:
					state["phase"] = PHASE_HAULING
					state["haul_path"] = haul
					state["pulses"] = []
					state["yield_acc"] = 0.0
					links_dirty = true
		if str(state.get("phase", "")) == PHASE_HAULING:
			var credited: Array = _tick_hauling(state, delta, w)
			var wallet: Array = result.friendly if team == BattleTileControlLib.OWNER_FRIENDLY else result.hostile
			wallet[int(state.get("type", 0))] += float(credited[0])
			if result.pulses.size() >= pulse_cap:
				continue
			var type_i: int = int(state.get("type", 0))
			for pulse_vis: Dictionary in credited[1]:
				if result.pulses.size() >= pulse_cap:
					break
				pulse_vis["type"] = type_i
				pulse_vis["team"] = team
				result.pulses.append(pulse_vis)
	result.links_dirty = links_dirty
	return result


static func site_states() -> Dictionary:
	return _site_states


static func _site_state(dep_id: int) -> Dictionary:
	var key: String = "dep_%d" % dep_id
	if not _site_states.has(key):
		_site_states[key] = {}
	return _site_states[key]


static func _reset_site(dep_id: int) -> void:
	_site_states.erase("dep_%d" % dep_id)


static func _tick_hauling(state: Dictionary, delta: float, grid_w: int) -> Array:
	var haul: PackedInt32Array = state.get("haul_path", PackedInt32Array())
	if haul.size() < 2:
		return [0.0, []]
	var yield_rate: float = float(state.get("yield_per_sec", 1.0))
	var acc: float = float(state.get("yield_acc", 0.0)) + yield_rate * delta
	var credited: float = 0.0
	var pulses: Array = state.get("pulses", [])
	while acc >= 1.0:
		pulses.append({"t": 0.0})
		acc -= 1.0
	state["yield_acc"] = acc
	var speed: float = WorldConquestConfigLib.RESOURCE_HAUL_CELLS_PER_SEC
	var seg_len: float = maxf(float(haul.size() - 1), 1.0)
	var step: float = speed * delta / seg_len
	var alive: Array = []
	for pulse: Dictionary in pulses:
		var t: float = float(pulse.get("t", 0.0)) + step
		if t >= 1.0:
			credited += 1.0
			continue
		pulse["t"] = t
		alive.append(pulse)
	state["pulses"] = alive
	var vis: Array = []
	for pulse: Dictionary in alive:
		var pos: Vector2i = _pos_along_path(haul, float(pulse.get("t", 0.0)), grid_w)
		vis.append({"gx": pos.x, "gy": pos.y, "t": float(pulse.get("t", 0.0))})
	return [credited, vis]


static func _pos_along_path(path: PackedInt32Array, t: float, grid_w: int) -> Vector2i:
	var max_i: int = path.size() - 1
	if max_i <= 0:
		return OutpostBuildLib.grid_from_packed_key(path[0], grid_w) if path.size() > 0 else Vector2i(-1, -1)
	var f: float = clampf(t, 0.0, 1.0) * float(max_i)
	var i0: int = int(floor(f))
	var i1: int = mini(i0 + 1, max_i)
	if i0 == i1:
		return OutpostBuildLib.grid_from_packed_key(path[i0], grid_w)
	var frac: float = f - float(i0)
	var a: Vector2i = OutpostBuildLib.grid_from_packed_key(path[i0], grid_w)
	var b: Vector2i = OutpostBuildLib.grid_from_packed_key(path[i1], grid_w)
	return Vector2i(
		int(round(lerpf(float(a.x), float(b.x), frac))),
		int(round(lerpf(float(a.y), float(b.y), frac))),
	)


static func _road_cells_for_team_cached(
	structures: Array, team: int, network_key: int
) -> Dictionary:
	if _roads_cache_version != network_key:
		_roads_cache.clear()
		_roads_cache_version = network_key
	var cache_key: String = "t%d" % team
	if _roads_cache.has(cache_key):
		return _roads_cache[cache_key]
	var built: Dictionary = _road_cells_for_team(structures, team)
	_roads_cache[cache_key] = built
	return built


static func _road_cells_for_team(structures: Array, team: int) -> Dictionary:
	var out: Dictionary = {}
	for st: Dictionary in structures:
		if int(st.get("team", 0)) != team:
			continue
		if str(st.get("kind", "")) != "spawner":
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		if packed.is_empty():
			continue
		var state: String = str(st.get("state", OutpostBuildLib.STATE_ACTIVE))
		var built: int = packed.size()
		if state == OutpostBuildLib.STATE_CONNECTING:
			built = int(floor(float(st.get("path_built", 1.0))))
		built = clampi(built, 1, packed.size())
		for i in built:
			out[packed[i]] = true
	return out


static func _plan_link_path(
	map_data,
	tile_control,
	gx: int,
	gy: int,
	team: int,
	roads: Dictionary,
	hubs: Array[Vector2i],
	w: int,
	h: int,
) -> PackedInt32Array:
	var start_key: int = _key(gx, gy, w)
	var targets: Dictionary = {}
	if roads.is_empty():
		for hub in hubs:
			if hub.x >= 0:
				targets[_key(hub.x, hub.y, w)] = true
	else:
		for rk in roads.keys():
			targets[rk] = true
		for hub in hubs:
			if hub.x < 0:
				continue
			var hk: int = _key(hub.x, hub.y, w)
			if roads.has(hk):
				targets[hk] = true
	if targets.is_empty():
		return PackedInt32Array()
	var goal_key: int = _bfs_to_targets(
		map_data, tile_control, start_key, team, roads, targets, w, h
	)
	if goal_key < 0:
		return PackedInt32Array()
	return _reconstruct_path(goal_key)


static func _build_haul_path(
	map_data,
	link_path: PackedInt32Array,
	roads: Dictionary,
	hubs: Array[Vector2i],
	w: int,
	h: int,
) -> PackedInt32Array:
	if link_path.is_empty():
		return PackedInt32Array()
	# Haul visuals + credit: deposit (path[0]) → join → hub/outpost (path[-1]).
	var join_key: int = link_path[link_path.size() - 1]
	var hub_key: int = _nearest_hub_key(join_key, hubs, w)
	var out := PackedInt32Array()
	out.append_array(link_path)
	if hub_key < 0 or join_key == hub_key:
		return out
	var road_targets: Dictionary = {}
	for hub in hubs:
		if hub.x >= 0:
			road_targets[_key(hub.x, hub.y, w)] = true
	var road_path: PackedInt32Array = _bfs_on_roads(join_key, road_targets, roads, w, h)
	if road_path.is_empty():
		return out
	for i in range(1, road_path.size()):
		out.append(road_path[i])
	return out


static func _nearest_hub_key(from_key: int, hubs: Array[Vector2i], w: int) -> int:
	var best: int = -1
	var best_d: int = 0x3FFFFFFF
	var fx: int = from_key % w
	var fy: int = from_key / w
	for hub in hubs:
		if hub.x < 0:
			continue
		var hk: int = _key(hub.x, hub.y, w)
		var dx: int = absi(hub.x - fx)
		dx = mini(dx, w - dx)
		var dy: int = absi(hub.y - fy)
		var d: int = dx + dy
		if d < best_d:
			best_d = d
			best = hk
	return best


static func _bfs_to_targets(
	map_data,
	tile_control,
	start_key: int,
	team: int,
	roads: Dictionary,
	targets: Dictionary,
	w: int,
	h: int,
) -> int:
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	_bfs_parent[start_key] = -1
	_bfs_gen[start_key] = gen
	_bfs_queue.append(start_key)
	var head: int = 0
	while head < _bfs_queue.size():
		var cur: int = _bfs_queue[head]
		head += 1
		if targets.has(cur):
			return cur
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
			var nk: int = _key(nx, ny, w)
			if _bfs_gen[nk] == gen:
				continue
			if not _can_traverse_link(map_data, tile_control, nx, ny, team, roads):
				continue
			_bfs_gen[nk] = gen
			_bfs_parent[nk] = cur
			_bfs_queue.append(nk)
	return -1


static func _bfs_on_roads(
	start_key: int,
	targets: Dictionary,
	roads: Dictionary,
	w: int,
	h: int,
) -> PackedInt32Array:
	_bump_search_gen()
	var gen: int = _search_gen
	_bfs_queue.clear()
	_bfs_parent[start_key] = -1
	_bfs_gen[start_key] = gen
	_bfs_queue.append(start_key)
	var head: int = 0
	while head < _bfs_queue.size():
		var cur: int = _bfs_queue[head]
		head += 1
		if targets.has(cur):
			return _reconstruct_path(cur)
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
			var nk: int = _key(nx, ny, w)
			if _bfs_gen[nk] == gen:
				continue
			if not roads.has(nk) and nk != start_key:
				continue
			_bfs_gen[nk] = gen
			_bfs_parent[nk] = cur
			_bfs_queue.append(nk)
	return PackedInt32Array()


static func _can_traverse_link(
	map_data,
	tile_control,
	gx: int,
	gy: int,
	team: int,
	roads: Dictionary,
) -> bool:
	var key: int = _key(gx, gy, map_data.grid_width)
	if roads.has(key):
		return true
	if not map_data.is_land_cell(gx, gy):
		return false
	var idx: int = map_data.cell_index(gx, gy)
	if idx < 0 or idx >= tile_control.owners.size():
		return false
	return int(tile_control.owners[idx]) == team


static func _reconstruct_path(goal_key: int) -> PackedInt32Array:
	var length: int = 0
	var cur: int = goal_key
	while cur >= 0:
		length += 1
		cur = _bfs_parent[cur]
	var out := PackedInt32Array()
	out.resize(length)
	cur = goal_key
	for i in range(length - 1, -1, -1):
		out[i] = cur
		cur = _bfs_parent[cur]
	return out


static func _key(gx: int, gy: int, w: int) -> int:
	return gy * w + gx


static func _bump_search_gen() -> void:
	_search_gen += 1
	if _search_gen >= 0x7FFFFFF0:
		_bfs_gen.fill(0)
		_search_gen = 1


static func _ensure_bufs(cell_count: int) -> void:
	if _bfs_parent.size() < cell_count:
		_bfs_parent.resize(cell_count)
		_bfs_gen.resize(cell_count)
