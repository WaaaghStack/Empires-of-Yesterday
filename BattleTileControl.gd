class_name BattleTileControl
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const WorldConquestOutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")

const OWNER_NEUTRAL := 0
const OWNER_FRIENDLY := 1
const OWNER_HOSTILE := 2
const OWNER_CONTESTED := 3
const OWNER_UNCLAIMABLE := 4

const _NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]

## Propagation tuning (true Creeper World style)
## Home bases constantly generate new power every step. Power flows, cancels, and claims ground.
const PRESSURE_UNIT_PUSH := 0.88
const PRESSURE_DECAY := 0.68
const FLIP_THRESHOLD := 0.26
const MAX_FLIPS_PER_ROUND := 512
## Unit-less territory propagation (Creeper-style fluid front)
const PRESSURE_SPAWN_BASE := 0.38
const PRESSURE_SPAWN_EDGE := 0.52
## Legacy tactical diffusion only (not used by simple water path).
const HEIGHT_UPHILL_BLOCK := 0.22
const HEIGHT_DOWNHILL_BOOST := 1.38
const HEIGHT_UPHILL_PENALTY := 0.42
## Terrain elevation 0..HEIGHT_MAX (mountains = 100). Not a cap on pressure stored on a tile.
const HEIGHT_MAX := 100.0
## Hydrostatic gradient: effective height H = pressure + elevation; flow ∝ positive dH.
const FLOW_CONDUCTIVITY := 0.32
const MIN_FLOW_DELTA := 0.1
const MAX_OUTFLOW_FRAC := 0.5
## Ignore tiny pressure for territory claims (visual fade handled in BattleTileFluidField).
const MIN_CLAIM_PRESSURE := 0.04
## Base home power; per-round and start pressure scale by committed force (see home_spawn_rate_for_force).
const HOME_START_POWER := 10000.0
## +1% spawn multiplier per committed unit (1 unit → HOME_START_POWER × 1.01).
const SPAWN_MULTIPLIER_PER_UNIT := 0.01


## Terrain height only (0–HEIGHT_MAX). Pressure is separate and uncapped.
static func tile_elevation(map_data, gx: int, gy: int) -> float:
	if map_data == null:
		return 0.0
	return clampf(map_data.get_tile_height(gx, gy), 0.0, 1.0) * HEIGHT_MAX


static func effective_height(pressure: float, elevation: float) -> float:
	return pressure + elevation


static func _flow_mult_for_tile(map_data, gx: int, gy: int, claimable: bool) -> float:
	if not claimable or map_data == null:
		return 0.0
	var move: float = map_data.get_move_cost(gx, gy)
	if move >= BattleMapDataLib.IMPASSABLE_MOVE_COST:
		return 0.0
	return clampf(1.0 / maxf(1.0, move), 0.42, 1.05)


static func _claim_mult_for_tile(map_data, gx: int, gy: int, claimable: bool) -> float:
	if not claimable or map_data == null:
		return 1.0
	var mult: float = 1.0 + (map_data.get_defense(gx, gy) - 1.0) * 0.35
	var idx: int = map_data.cell_index(gx, gy)
	if map_data.cover_cells.size() > idx and int(map_data.cover_cells[idx]) > 0:
		mult += 0.1
	return clampf(mult, 1.0, 1.45)


const _CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var owners: PackedByteArray = PackedByteArray()
var pressure_friendly: PackedFloat32Array = PackedFloat32Array()
var pressure_hostile: PackedFloat32Array = PackedFloat32Array()
var claimable_mask: PackedByteArray = PackedByteArray()
var friendly_tiles: int = 0
var hostile_tiles: int = 0
var claimable_tile_count: int = 0
## QA: compare against full-grid gradient when true.
var force_full_grid_gradient: bool = false
var use_active_set: bool = false

# Ping-pong buffers to avoid allocations during diffusion (helps viewer fallback perf)
var _pressure_friendly_next: PackedFloat32Array = PackedFloat32Array()
var _pressure_hostile_next: PackedFloat32Array = PackedFloat32Array()
var _elevation: PackedFloat32Array = PackedFloat32Array()
var _active_indices: PackedInt32Array = PackedInt32Array()
var _active_scratch: PackedInt32Array = PackedInt32Array()
var _active_seen: PackedByteArray = PackedByteArray()
var _frontier_changed: bool = true
var _rounds_since_active_rebuild: int = 0
var _active_dirty_mark: PackedByteArray = PackedByteArray()
var _active_dirty_list: Array[int] = []
const INCREMENTAL_ACTIVE_MAX_DIRTY := 4096
const ACTIVE_REBUILD_INTERVAL := 3

var _map_data = null
var _tile_count: int = 0
var _friendly_reachable: PackedByteArray = PackedByteArray()
var _hostile_reachable: PackedByteArray = PackedByteArray()
var _friendly_bridge_reachable: PackedByteArray = PackedByteArray()
var _hostile_bridge_reachable: PackedByteArray = PackedByteArray()
## Land cells on built bridge paths (separate from HQ BFS reachability).
var _friendly_corridor_land: PackedByteArray = PackedByteArray()
var _hostile_corridor_land: PackedByteArray = PackedByteArray()
## 1D bridge pipe links (path[i-1], path[i+1]) for corridor pressure flow.
var _bridge_pipe_prev: PackedInt32Array = PackedInt32Array()
var _bridge_pipe_next: PackedInt32Array = PackedInt32Array()
var _bridge_pipe_path_packs: Array = []
var _bridge_water_mask_cache: PackedByteArray = PackedByteArray()
var _corridor_land_mask_cache: PackedByteArray = PackedByteArray()
var _bridge_flow_masks_dirty: bool = true
var _claimable_dirty_indices: Array[int] = []
var _claimable_dirty_lookup: PackedByteArray = PackedByteArray()
var _friendly_spawn_rate: float = 1.0
var _hostile_spawn_rate: float = 1.0

var use_simple_water_model: bool = false
var use_longitude_wrap: bool = false
var bridge_live_suction_enabled: bool = true
var perf = null

const ACTIVE_PRESSURE_EPS := 0.05
const ADAPTIVE_FRONTIER_EPS := 16

var _prev_friendly_tiles: int = 0
var _prev_hostile_tiles: int = 0
var _grad_targets: PackedInt32Array = PackedInt32Array()
var _grad_amounts: PackedFloat32Array = PackedFloat32Array()
## {team: 1|2, gx, gy, kind}
var _placed_spawners: Array = []
## Per-tile flow multiplier from terrain_move_cost (mud slow, grass normal).
var _terrain_flow_mult: PackedFloat32Array = PackedFloat32Array()
## Per-tile flip difficulty from cover / terrain_defense.
var _claim_ratio_mult: PackedFloat32Array = PackedFloat32Array()


func setup(map_data) -> void:
	_map_data = map_data
	_tile_count = map_data.grid_width * map_data.grid_height if map_data else 0
	owners.resize(_tile_count)
	owners.fill(OWNER_NEUTRAL)
	_friendly_reachable = _bfs_reachable(map_data, _spawn_cells(map_data, true))
	_hostile_reachable = _bfs_reachable(map_data, _spawn_cells(map_data, false))
	_friendly_bridge_reachable.resize(_tile_count)
	_friendly_bridge_reachable.fill(0)
	_hostile_bridge_reachable.resize(_tile_count)
	_hostile_bridge_reachable.fill(0)
	_friendly_corridor_land.resize(_tile_count)
	_friendly_corridor_land.fill(0)
	_hostile_corridor_land.resize(_tile_count)
	_hostile_corridor_land.fill(0)
	_bridge_pipe_prev.resize(_tile_count)
	_bridge_pipe_prev.fill(-1)
	_bridge_pipe_next.resize(_tile_count)
	_bridge_pipe_next.fill(-1)
	claimable_mask.resize(_tile_count)
	_elevation.resize(_tile_count)
	_terrain_flow_mult.resize(_tile_count)
	_claim_ratio_mult.resize(_tile_count)
	_active_seen.resize(_tile_count)
	_active_dirty_mark.resize(_tile_count)
	_active_dirty_mark.fill(0)
	_active_dirty_list.clear()
	_grad_targets.resize(4)
	_grad_amounts.resize(4)
	for idx in range(_tile_count):
		var gx: int = idx % map_data.grid_width
		var gy: int = idx / map_data.grid_width
		var claimable: bool = _is_claimable_index(idx)
		claimable_mask[idx] = 1 if claimable else 0
		_elevation[idx] = tile_elevation(map_data, gx, gy) if claimable else 0.0
		_terrain_flow_mult[idx] = _flow_mult_for_tile(map_data, gx, gy, claimable)
		_claim_ratio_mult[idx] = _claim_mult_for_tile(map_data, gx, gy, claimable)
		if not claimable:
			owners[idx] = OWNER_UNCLAIMABLE
	claimable_tile_count = 0
	for idx2 in range(_tile_count):
		if claimable_mask[idx2] != 0:
			claimable_tile_count += 1
	reset_pressures()
	_pressure_friendly_next.resize(_tile_count)
	_pressure_hostile_next.resize(_tile_count)
	_pressure_friendly_next.fill(0.0)
	_pressure_hostile_next.fill(0.0)
	_recount_ownership()
	_load_placed_spawners_from_map(map_data)
	rebuild_bridge_pipe_topology(map_data)


func reset_for_battle(map_data, store, cell_grid = null) -> void:
	setup(map_data)
	reset_pressures()
	seed_initial_owners(map_data, store, cell_grid)


func apply_building_modifiers(mods: Dictionary) -> void:
	_friendly_spawn_rate = 1.0 + float(mods.get("friendly_pressure", 0.0))
	_hostile_spawn_rate = 1.0 + float(mods.get("hostile_pressure", 0.0))

func enable_world_conquest_model(player_force: int, enemy_force: int) -> void:
	enable_simple_water_model(player_force, enemy_force, 0.0, 0.0)
	use_longitude_wrap = true
	use_active_set = true
	_friendly_spawn_rate *= WorldConquestConfigLib.WORLD_CONQUEST_PRESSURE_SCALE
	_hostile_spawn_rate *= WorldConquestConfigLib.WORLD_CONQUEST_PRESSURE_SCALE


func enable_simple_water_model(
	player_force: int,
	enemy_force: int,
	bonus_friendly: float = 0.0,
	bonus_hostile: float = 0.0,
) -> void:
	use_simple_water_model = true
	# === True Creeper World Logic ===
	#
	# Home bases are continuous generators that spawn new power every simulation step.
	# This is the core of the Creeper World model the user wants:
	#   - Home bases pump fresh power every second/step.
	#   - Power flows outward and fills the map from both ends.
	#   - Opposing power cancels on contact.
	#   - One side eventually dominates through sustained production + better positioning.
	#
	# spawn_rate = HOME_START_POWER × (1 + units × 0.01 + galaxy_bonus)
	_friendly_spawn_rate = home_spawn_rate_for_force(player_force, bonus_friendly)
	_hostile_spawn_rate = home_spawn_rate_for_force(enemy_force, bonus_hostile)

	if _tile_count > 0:
		reset_pressures()
	_pressure_friendly_next.resize(_tile_count)
	_pressure_hostile_next.resize(_tile_count)
	_pressure_friendly_next.fill(0.0)
	_pressure_hostile_next.fill(0.0)


func seed_territory_battle(map_data) -> PackedByteArray:
	if map_data == null:
		return owners.duplicate()
	reset_pressures()
	for idx in range(_tile_count):
		if _is_claimable_index(idx):
			owners[idx] = OWNER_NEUTRAL
	# Only the home-base tile is owned at start — not the whole deployment half-map.
	_claim_home_base_tile(map_data, map_data.player_spawn_zone, OWNER_FRIENDLY)
	_claim_home_base_tile(map_data, map_data.enemy_spawn_zone, OWNER_HOSTILE)
	if use_simple_water_model:
		_seed_initial_pressure(map_data)
	_recount_ownership()
	if use_active_set:
		_maybe_rebuild_active_indices()
	return owners.duplicate()


func propagate_round_territory(map_data) -> void:
	if map_data == null or _tile_count <= 0:
		return

	if use_simple_water_model:
		_propagate_simple_water(map_data)
		return

	# Original expensive creeper-style model
	_inject_territory_spawn_pressure(map_data)
	for idx in range(_tile_count):
		if not _is_claimable_index(idx):
			pressure_friendly[idx] *= PRESSURE_DECAY * 0.5
			pressure_hostile[idx] *= PRESSURE_DECAY * 0.5
			continue
		pressure_friendly[idx] *= PRESSURE_DECAY
		pressure_hostile[idx] *= PRESSURE_DECAY
	for _d in range(2):
		_diffuse_pressure_height_biased(map_data)
	_resolve_ownership_from_pressure()


func reset_pressures() -> void:
	if _tile_count <= 0:
		pressure_friendly = PackedFloat32Array()
		pressure_hostile = PackedFloat32Array()
		return
	pressure_friendly.resize(_tile_count)
	pressure_hostile.resize(_tile_count)
	pressure_friendly.fill(0.0)
	pressure_hostile.fill(0.0)


func propagate_round(map_data, store, cell_grid = null) -> void:
	if map_data == null or _tile_count <= 0:
		return
	# 1. Build current unit counts
	var f_count: PackedInt32Array = PackedInt32Array()
	var h_count: PackedInt32Array = PackedInt32Array()
	f_count.resize(_tile_count)
	h_count.resize(_tile_count)
	f_count.fill(0)
	h_count.fill(0)
	if cell_grid != null:
		for i in range(_tile_count):
			f_count[i] = cell_grid.friendly_count_at_cell(i % map_data.grid_width, i / map_data.grid_width)
			h_count[i] = cell_grid.hostile_count_at_cell(i % map_data.grid_width, i / map_data.grid_width)
	elif store != null:
		for i in range(store.count):
			if not store.is_alive(i):
				continue
			var gx: int = store.grid_x[i]
			var gy: int = store.grid_y[i]
			if gx < 0 or gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
				continue
			var idx: int = map_data.cell_index(gx, gy)
			if store.side[i] == UnitSimulationStoreLib.Side.FRIENDLY:
				f_count[idx] += 1
			else:
				h_count[idx] += 1

	# 2. Apply unit push + decay existing pressure
	for idx in range(_tile_count):
		if not _is_claimable_index(idx):
			pressure_friendly[idx] = 0.0
			pressure_hostile[idx] = 0.0
			continue
		var f_push: float = float(f_count[idx]) * PRESSURE_UNIT_PUSH
		var h_push: float = float(h_count[idx]) * PRESSURE_UNIT_PUSH
		pressure_friendly[idx] = pressure_friendly[idx] * PRESSURE_DECAY + f_push
		pressure_hostile[idx] = pressure_hostile[idx] * PRESSURE_DECAY + h_push

	# 3. Diffuse pressure (two light passes for organic spread)
	for _d in range(2):
		_diffuse_pressure_height_biased(map_data)

	_resolve_ownership_from_pressure()


func _propagate_simple_water(map_data) -> void:
	_prev_friendly_tiles = friendly_tiles
	_prev_hostile_tiles = hostile_tiles

	var t_inj: int = 0
	if perf != null:
		t_inj = perf.begin_phase("inject")
	_inject_home_base_tile(map_data, map_data.player_spawn_zone, _friendly_spawn_rate, true)
	_inject_home_base_tile(map_data, map_data.enemy_spawn_zone, _hostile_spawn_rate, false)
	_inject_placed_spawners(map_data)
	_suction_feed_bridge_pipes_live()
	if perf != null:
		perf.end_phase("inject", t_inj)

	var t_grad: int = 0
	if perf != null:
		t_grad = perf.begin_phase("gradient")
	_run_gradient_cancel_sync_pass(map_data)
	_suction_feed_bridge_pipes_live()
	var frontier_delta: int = (
		absi(friendly_tiles - _prev_friendly_tiles) + absi(hostile_tiles - _prev_hostile_tiles)
	)
	if frontier_delta > ADAPTIVE_FRONTIER_EPS and not use_active_set:
		_run_gradient_cancel_sync_pass(map_data)
	if perf != null:
		perf.end_phase("gradient", t_grad)

	var t_conq: int = 0
	if perf != null:
		t_conq = perf.begin_phase("conquest")
	_preserve_home_base_ownership(map_data)
	if use_active_set:
		_maybe_rebuild_active_indices()
	if perf != null:
		perf.end_phase("conquest", t_conq)


func _run_gradient_cancel_sync_pass(map_data) -> void:
	_spread_pressure_gradient(map_data)
	var t_cancel: int = 0
	if perf != null:
		t_cancel = perf.begin_phase("cancel")
	_cancel_overlapping_pressure()
	if perf != null:
		perf.end_phase("cancel", t_cancel)
	var t_sync: int = 0
	if perf != null:
		t_sync = perf.begin_phase("sync")
	_sync_ownership_from_pressures()
	if perf != null:
		perf.end_phase("sync", t_sync)


func _cancel_overlapping_pressure() -> void:
	if use_active_set and not _active_indices.is_empty():
		for idx in _active_indices:
			if claimable_mask[idx] == 0:
				continue
			var pf: float = pressure_friendly[idx]
			var ph: float = pressure_hostile[idx]
			if pf > 0.0 and ph > 0.0:
				var cancel: float = minf(pf, ph)
				pressure_friendly[idx] -= cancel
				pressure_hostile[idx] -= cancel
		return
	for idx in range(_tile_count):
		if claimable_mask[idx] == 0:
			pressure_friendly[idx] = 0.0
			pressure_hostile[idx] = 0.0
			continue
		var pf: float = pressure_friendly[idx]
		var ph: float = pressure_hostile[idx]
		if pf > 0.0 and ph > 0.0:
			var cancel: float = minf(pf, ph)
			pressure_friendly[idx] -= cancel
			pressure_hostile[idx] -= cancel


func _spread_pressure_gradient(map_data) -> void:
	if _map_data == null or map_data == null or _tile_count <= 0:
		return
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	_gradient_flow_pass_into(map_data, w, h, pressure_friendly, _pressure_friendly_next)
	_bridge_pipe_suction_pass(_pressure_friendly_next)
	var tmp_f: PackedFloat32Array = pressure_friendly
	pressure_friendly = _pressure_friendly_next
	_pressure_friendly_next = tmp_f
	_gradient_flow_pass_into(map_data, w, h, pressure_hostile, _pressure_hostile_next)
	_bridge_pipe_suction_pass(_pressure_hostile_next)
	var tmp_h: PackedFloat32Array = pressure_hostile
	pressure_hostile = _pressure_hostile_next
	_pressure_hostile_next = tmp_h


func _gradient_flow_pass_into(
	map_data,
	w: int,
	h: int,
	src: PackedFloat32Array,
	dst: PackedFloat32Array,
) -> void:
	if dst.size() != src.size():
		dst.resize(src.size())
	for i in range(src.size()):
		dst[i] = src[i]
	if use_active_set and not force_full_grid_gradient and not _active_indices.is_empty():
		_gradient_flow_active(map_data, w, h, src, dst)
		return
	for idx in range(_tile_count):
		if claimable_mask[idx] == 0:
			continue
		_gradient_flow_tile(map_data, w, h, idx % w, idx / w, src, dst)


func _gradient_flow_active(map_data, w: int, h: int, src: PackedFloat32Array, dst: PackedFloat32Array) -> void:
	_active_scratch.clear()
	for idx in _active_indices:
		_active_seen[idx] = 1
	for idx in _active_indices:
		_gradient_flow_tile(
			map_data, w, h, idx % w, idx / w, src, dst, _active_scratch
		)
	for ni in _active_scratch:
		_gradient_flow_tile(map_data, w, h, ni % w, ni / w, src, dst)
		_active_seen[ni] = 0


func _gradient_flow_tile(
	map_data,
	w: int,
	h: int,
	gx: int,
	gy: int,
	src: PackedFloat32Array,
	dst: PackedFloat32Array,
	halo_out: PackedInt32Array = PackedInt32Array(),
) -> void:
	var idx: int = map_data.cell_index(gx, gy)
	if claimable_mask[idx] == 0:
		return
	var p: float = src[idx]
	if p <= 0.0:
		return
	var elev_s: float = _elevation[idx]
	var h_src: float = effective_height(p, elev_s)
	var n_count: int = 0
	var want_total: float = 0.0
	for ni: int in _gradient_flow_neighbor_indices(map_data, gx, gy, idx):
		if claimable_mask[ni] == 0:
			continue
		var p_n: float = src[ni]
		var h_n: float = effective_height(p_n, _elevation[ni])
		var dh: float = h_src - h_n
		if dh <= MIN_FLOW_DELTA:
			continue
		var edge_flow: float = sqrt(_terrain_flow_mult[idx] * _terrain_flow_mult[ni])
		var amount: float = dh * FLOW_CONDUCTIVITY * edge_flow
		_grad_targets[n_count] = ni
		_grad_amounts[n_count] = amount
		n_count += 1
		want_total += amount
		if not halo_out.is_empty() and _active_seen[ni] == 0:
			halo_out.append(ni)
			_active_seen[ni] = 1
	if want_total <= 0.0:
		return
	var cap: float = minf(p * MAX_OUTFLOW_FRAC, want_total)
	var scale: float = cap / want_total
	dst[idx] -= cap
	for i in range(n_count):
		dst[_grad_targets[i]] += _grad_amounts[i] * scale


## Kept for qa_runner; runs one hydrostatic gradient pass (full grid).
func _gradient_flow_pass(map_data, w: int, h: int, src: PackedFloat32Array) -> PackedFloat32Array:
	var dst: PackedFloat32Array = src.duplicate()
	_gradient_flow_pass_into(map_data, w, h, src, dst)
	return dst


## Kept for qa_runner; runs one hydrostatic gradient pass.
func _outflow_pass(map_data, w: int, h: int, src: PackedFloat32Array) -> PackedFloat32Array:
	return _gradient_flow_pass(map_data, w, h, src)


func _home_base_tile_index(map_data, zone: Rect2, is_player: bool = true) -> int:
	if map_data == null or zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return -1
	var hq: Vector2i = (
		map_data.player_home_grid if is_player else map_data.enemy_home_grid
	)
	if hq.x >= 0 and map_data.is_land_cell(hq.x, hq.y):
		return map_data.cell_index(hq.x, hq.y)
	var center_world: Vector2 = zone.position + zone.size * 0.5
	var center: Vector2i = map_data.world_to_grid(center_world)
	if center.x >= 0 and center.y >= 0 and map_data.is_land_cell(center.x, center.y):
		var idx: int = map_data.cell_index(center.x, center.y)
		if _is_claimable_index(idx):
			return idx
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var gx: int = center.x + dx
			var gy: int = center.y + dy
			if gx < 0 or gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
				continue
			var idx: int = map_data.cell_index(gx, gy)
			if _is_claimable_index(idx):
				return idx
	return -1


func _claim_home_base_tile(map_data, zone: Rect2, owner: int) -> void:
	var idx: int = _home_base_tile_index(map_data, zone, owner == OWNER_FRIENDLY)
	if idx < 0:
		var is_player: bool = owner == OWNER_FRIENDLY
		for cell in _spawn_cells(map_data, is_player):
			var v := _cell_to_vec2i(cell)
			if v.x < 0 or v.y < 0:
				continue
			idx = map_data.cell_index(v.x, v.y)
			if _is_claimable_index(idx):
				break
			idx = -1
	if idx < 0:
		return
	var gx: int = idx % map_data.grid_width
	var gy: int = idx / map_data.grid_width
	_claim_at(gx, gy, owner)


func _preserve_home_base_ownership(map_data) -> void:
	if map_data == null:
		return
	_claim_home_base_tile(map_data, map_data.player_spawn_zone, OWNER_FRIENDLY)
	_claim_home_base_tile(map_data, map_data.enemy_spawn_zone, OWNER_HOSTILE)
	for sp: Dictionary in _placed_spawners:
		var team: int = int(sp.get("team", OWNER_FRIENDLY))
		var gx: int = int(sp.get("gx", -1))
		var gy: int = int(sp.get("gy", -1))
		if gx >= 0 and gy >= 0:
			_claim_at(gx, gy, OWNER_FRIENDLY if team == OWNER_FRIENDLY else OWNER_HOSTILE)


func _inject_home_base_tile(
	map_data,
	zone: Rect2,
	amount: float,
	is_friendly: bool,
	set_absolute: bool = false,
) -> void:
	if map_data == null or amount <= 0.0:
		return
	var idx: int = _home_base_tile_index(map_data, zone, is_friendly)
	if idx < 0:
		return
	_inject_pressure_at_index(idx, amount, is_friendly, set_absolute)


func _inject_pressure_at_index(
	idx: int,
	amount: float,
	is_friendly: bool,
	set_absolute: bool = false,
) -> void:
	if idx < 0 or amount <= 0.0:
		return
	if is_friendly:
		if set_absolute:
			pressure_friendly[idx] = amount
		else:
			pressure_friendly[idx] += amount
	else:
		if set_absolute:
			pressure_hostile[idx] = amount
		else:
			pressure_hostile[idx] += amount


func _inject_at_grid(
	map_data,
	gx: int,
	gy: int,
	amount: float,
	is_friendly: bool,
	set_absolute: bool = false,
) -> void:
	if map_data == null:
		return
	if gx < 0 or gy < 0 or gx >= map_data.grid_width or gy >= map_data.grid_height:
		return
	var idx: int = map_data.cell_index(gx, gy)
	if not _is_claimable_index(idx):
		return
	_inject_pressure_at_index(idx, amount, is_friendly, set_absolute)


func _inject_placed_spawners(map_data) -> void:
	for sp: Dictionary in _placed_spawners:
		var team: int = int(sp.get("team", OWNER_FRIENDLY))
		var gx: int = int(sp.get("gx", -1))
		var gy: int = int(sp.get("gy", -1))
		var amount: float = (
			_friendly_spawn_rate if team == OWNER_FRIENDLY else _hostile_spawn_rate
		)
		_inject_at_grid(map_data, gx, gy, amount, team == OWNER_FRIENDLY)


func add_placed_spawner(team: int, gx: int, gy: int, kind: String = "spawner") -> void:
	_placed_spawners.append({"team": team, "gx": gx, "gy": gy, "kind": kind})


func claim_tile(gx: int, gy: int, owner: int) -> void:
	_claim_at(gx, gy, owner)


func _load_placed_spawners_from_map(map_data) -> void:
	_placed_spawners.clear()
	if map_data == null:
		return
	for st in map_data.placed_structures:
		if str(st.get("kind", "")) != "spawner":
			continue
		var state: String = str(st.get("state", "active"))
		if state != "" and state != "active":
			continue
		_placed_spawners.append({
			"team": int(st.get("team", OWNER_FRIENDLY)),
			"gx": int(st.get("gx", 0)),
			"gy": int(st.get("gy", 0)),
			"kind": "spawner",
		})


func sync_placed_spawners_from_map(map_data) -> void:
	_load_placed_spawners_from_map(map_data)
	_extend_reachability_from_spawners(map_data)


## Extend built bridge/corridor claimability. Returns true if claimable_mask changed.
## force_full: rebuild all corridor masks (e.g. after outpost destroyed).
func sync_bridge_corridors_from_map(map_data, force_full: bool = false) -> bool:
	if map_data == null:
		return false
	var touched: PackedInt32Array = PackedInt32Array()
	if force_full:
		_friendly_bridge_reachable.fill(0)
		_hostile_bridge_reachable.fill(0)
		_friendly_corridor_land.fill(0)
		_hostile_corridor_land.fill(0)
		_bridge_pipe_prev.fill(-1)
		_bridge_pipe_next.fill(-1)
		_bridge_flow_masks_dirty = true
		for st in map_data.placed_structures:
			if st is Dictionary:
				st.erase("corridor_synced_built")
		for corridor in map_data.bridge_corridors:
			if corridor is Dictionary:
				corridor.erase("corridor_synced_built")
	for st in map_data.placed_structures:
		if not st is Dictionary:
			continue
		var kind: String = str(st.get("kind", ""))
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(kind):
			continue
		if kind == WorldConquestOutpostBuildLib.KIND_SPAWNER or kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
			var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
			if (
				state != WorldConquestOutpostBuildLib.STATE_CONNECTING
				and state != WorldConquestOutpostBuildLib.STATE_BUILDING
				and state != WorldConquestOutpostBuildLib.STATE_ACTIVE
			):
				continue
		elif str(st.get("state", "")) != WorldConquestOutpostBuildLib.STATE_CONNECTING:
			continue
		_apply_corridor_path_sync(map_data, st, force_full, touched)
	for corridor in map_data.bridge_corridors:
		if corridor is Dictionary:
			_apply_persisted_corridor_sync(map_data, corridor, force_full, touched)
	var nav_reconciled: bool = _reconcile_corridor_land_nav_masks(map_data)
	if force_full:
		rebuild_bridge_pipe_topology(map_data)
	if touched.is_empty():
		return nav_reconciled
	var changed: bool = _apply_claimable_cells(map_data, touched)
	return changed or nav_reconciled


## Incremental corridor sync for specific structure ids (CONNECTING path growth).
func sync_bridge_corridors_for_sids(map_data, sids: Array, force_full: bool = false) -> bool:
	if map_data == null or sids.is_empty():
		return false
	var touched: PackedInt32Array = PackedInt32Array()
	var sid_set: Dictionary = {}
	for sid_v in sids:
		sid_set[int(sid_v)] = true
	for st in map_data.placed_structures:
		if not st is Dictionary:
			continue
		var sid: int = int(st.get("id", -1))
		if sid < 0 or not sid_set.has(sid):
			continue
		var kind: String = str(st.get("kind", ""))
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(kind):
			continue
		_apply_corridor_path_sync(map_data, st, force_full, touched)
	if touched.is_empty():
		return false
	return _apply_claimable_cells(map_data, touched)


## Rebuild 1D prev/next links for all active bridge and corridor paths.
func rebuild_bridge_pipe_topology(map_data) -> void:
	if _tile_count <= 0:
		return
	_bridge_pipe_prev.fill(-1)
	_bridge_pipe_next.fill(-1)
	_bridge_pipe_path_packs.clear()
	if map_data == null:
		return
	for corridor: Dictionary in map_data.bridge_corridors:
		var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		_register_bridge_pipe_path(packed, packed.size())
		if packed.size() >= 2:
			_bridge_pipe_path_packs.append(packed)
	for st: Dictionary in map_data.placed_structures:
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		var kind: String = str(st.get("kind", ""))
		var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
		if kind == WorldConquestOutpostBuildLib.KIND_SPAWNER or kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
			if (
				state != WorldConquestOutpostBuildLib.STATE_CONNECTING
				and state != WorldConquestOutpostBuildLib.STATE_BUILDING
				and state != WorldConquestOutpostBuildLib.STATE_ACTIVE
			):
				continue
		elif state != WorldConquestOutpostBuildLib.STATE_CONNECTING:
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		var built: int = _built_bridge_cells_from_structure(st)
		_register_bridge_pipe_path(packed, built)
		if built >= 2:
			_bridge_pipe_path_packs.append(packed.slice(0, built))
	_bridge_flow_masks_dirty = true


func bridge_pipe_path_packs() -> Array:
	return _bridge_pipe_path_packs


func _register_bridge_pipe_path(packed: PackedInt32Array, built_cells: int) -> void:
	var n: int = clampi(built_cells, 0, packed.size())
	if n < 2:
		return
	for i in range(n):
		var cell_key: int = packed[i]
		if cell_key < 0 or cell_key >= _tile_count:
			continue
		if i > 0:
			_bridge_pipe_prev[cell_key] = packed[i - 1]
		if i < n - 1:
			_bridge_pipe_next[cell_key] = packed[i + 1]


func _bridge_pipe_neighbor_indices(idx: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if idx < 0 or idx >= _tile_count:
		return out
	var prev_i: int = _bridge_pipe_prev[idx]
	if prev_i >= 0 and prev_i < _tile_count and claimable_mask[prev_i] != 0:
		out.append(prev_i)
	var next_i: int = _bridge_pipe_next[idx]
	if next_i >= 0 and next_i < _tile_count and claimable_mask[next_i] != 0:
		if out.is_empty() or out[out.size() - 1] != next_i:
			out.append(next_i)
	return out


func _is_corridor_land_index(idx: int) -> bool:
	if idx < 0:
		return false
	if idx < _friendly_corridor_land.size() and _friendly_corridor_land[idx] > 0:
		return true
	if idx < _hostile_corridor_land.size() and _hostile_corridor_land[idx] > 0:
		return true
	return false


func _is_bridge_pipe_cell_index(idx: int) -> bool:
	if idx < 0 or idx >= _tile_count:
		return false
	if _is_bridge_water_index(idx) or _is_corridor_land_index(idx):
		return true
	var prev_i: int = _bridge_pipe_prev[idx] if idx < _bridge_pipe_prev.size() else -1
	var next_i: int = _bridge_pipe_next[idx] if idx < _bridge_pipe_next.size() else -1
	return prev_i >= 0 or next_i >= 0


## Bridge/corridor tiles prefer pipe topology; land uses cardinal neighbors.
func _gradient_flow_neighbor_indices(map_data, gx: int, gy: int, idx: int) -> PackedInt32Array:
	if _is_bridge_pipe_cell_index(idx):
		var pipe: PackedInt32Array = _bridge_pipe_neighbor_indices(idx)
		if not pipe.is_empty():
			return pipe
	return _cardinal_neighbor_indices(map_data, gx, gy)


func _suction_feed_bridge_pipes_live() -> void:
	if not bridge_live_suction_enabled:
		return
	var rate: float = WorldConquestConfigLib.BRIDGE_PIPE_SUCTION_RATE * 1.5
	var passes: int = maxi(1, WorldConquestConfigLib.BRIDGE_PIPE_LIVE_SUCTION_PASSES)
	if rate <= 0.0 or _tile_count <= 0:
		return
	_suction_feed_bridge_paths_direct(pressure_friendly, rate, passes)
	_suction_feed_bridge_paths_direct(pressure_hostile, rate, passes)


func _suction_transfer_along_pipe(
	src: PackedFloat32Array, from_k: int, to_k: int, rate: float
) -> void:
	if (
		from_k < 0 or to_k < 0
		or from_k >= _tile_count or to_k >= _tile_count
		or claimable_mask[from_k] == 0 or claimable_mask[to_k] == 0
	):
		return
	if src[from_k] <= src[to_k]:
		return
	var pull: float = (src[from_k] - src[to_k]) * rate
	var cap: float = minf(pull, src[from_k] * 0.75)
	if cap <= 0.001:
		return
	src[from_k] -= cap
	src[to_k] += cap


func _suction_feed_bridge_paths_direct(
	src: PackedFloat32Array, rate: float, passes: int
) -> void:
	if _bridge_pipe_path_packs.is_empty():
		return
	for _pass in range(passes):
		for packed_v in _bridge_pipe_path_packs:
			if not packed_v is PackedInt32Array:
				continue
			var packed: PackedInt32Array = packed_v
			if packed.size() < 2:
				continue
			for i in range(1, packed.size()):
				_suction_transfer_along_pipe(src, packed[i - 1], packed[i], rate)
			for i in range(packed.size() - 2, -1, -1):
				_suction_transfer_along_pipe(src, packed[i], packed[i + 1], rate)


func _bridge_pipe_suction_pass(dst: PackedFloat32Array) -> void:
	var rate: float = WorldConquestConfigLib.BRIDGE_PIPE_SUCTION_RATE
	if rate <= 0.0 or _tile_count <= 0:
		return
	for idx in range(_tile_count):
		if claimable_mask[idx] == 0:
			continue
		if not _is_bridge_pipe_cell_index(idx):
			continue
		var prev_i: int = _bridge_pipe_prev[idx] if idx < _bridge_pipe_prev.size() else -1
		var next_i: int = _bridge_pipe_next[idx] if idx < _bridge_pipe_next.size() else -1
		if prev_i >= 0 and claimable_mask[prev_i] != 0 and dst[prev_i] > dst[idx]:
			var pull: float = (dst[prev_i] - dst[idx]) * rate
			var cap: float = minf(pull, dst[prev_i] * 0.18)
			if cap > 0.001:
				dst[prev_i] -= cap
				dst[idx] += cap
		if next_i >= 0 and claimable_mask[next_i] != 0 and dst[idx] > dst[next_i]:
			var push: float = (dst[idx] - dst[next_i]) * rate
			var cap_n: float = minf(push, dst[idx] * 0.18)
			if cap_n > 0.001:
				dst[idx] -= cap_n
				dst[next_i] += cap_n


## Kick-start pressure along a completed bridge path (home end strongest).
func _cardinal_neighbor_indices(map_data, gx: int, gy: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if map_data == null:
		return out
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for d: Vector2i in _CARDINAL_DIRS:
		var nx: int = gx + d.x
		var ny: int = gy + d.y
		if ny < 0 or ny >= h:
			continue
		if use_longitude_wrap:
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
		elif nx < 0 or nx >= w:
			continue
		out.append(map_data.cell_index(nx, ny))
	return out


func tile_probe(map_data, gx: int, gy: int) -> Dictionary:
	var empty: Dictionary = {"valid": false}
	if map_data == null or gx < 0 or gy < 0:
		return empty
	if gx >= map_data.grid_width or gy >= map_data.grid_height:
		return empty
	var idx: int = map_data.cell_index(gx, gy)
	if idx < 0 or idx >= _tile_count:
		return empty
	var owner: int = int(owners[idx])
	var owner_name: String = "unclaimable"
	match owner:
		OWNER_NEUTRAL:
			owner_name = "neutral"
		OWNER_FRIENDLY:
			owner_name = "friendly"
		OWNER_HOSTILE:
			owner_name = "hostile"
		OWNER_CONTESTED:
			owner_name = "contested"
	var terrain: String = "water"
	if map_data.is_land_cell(gx, gy):
		terrain = BattleMapDataLib.TERRAIN_NAMES[
			clampi(int(map_data.get_cell_terrain(gx, gy)), 0, BattleMapDataLib.TERRAIN_NAMES.size() - 1)
		]
	return {
		"valid": true,
		"gx": gx,
		"gy": gy,
		"terrain": terrain,
		"owner": owner_name,
		"pf": pressure_friendly[idx],
		"ph": pressure_hostile[idx],
		"claimable": claimable_mask[idx] != 0,
		"f_bridge": _friendly_bridge_reachable[idx] != 0,
		"h_bridge": _hostile_bridge_reachable[idx] != 0,
		"f_corridor": _friendly_corridor_land[idx] != 0,
		"h_corridor": _hostile_corridor_land[idx] != 0,
		"f_reach": _friendly_reachable[idx] != 0,
		"h_reach": _hostile_reachable[idx] != 0,
		"flow_mult": _terrain_flow_mult[idx],
	}


func count_claimable_bridge_cells(map_data) -> Dictionary:
	var water_claimable: int = 0
	var water_total: int = 0
	var landings: int = 0
	if map_data == null:
		return {"water_claimable": 0, "water_total": 0, "landings": 0}
	for corridor in map_data.bridge_corridors:
		if not corridor is Dictionary:
			continue
		landings += 1
		var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		for key in packed:
			var idx: int = int(key)
			if idx < 0 or idx >= _tile_count:
				continue
			var gx: int = idx % map_data.grid_width
			var gy: int = idx / map_data.grid_width
			if not WorldConquestOutpostBuildLib.is_water_cell(map_data, gx, gy):
				continue
			water_total += 1
			if claimable_mask[idx] != 0:
				water_claimable += 1
	return {
		"water_claimable": water_claimable,
		"water_total": water_total,
		"landings": landings,
	}


func inject_corridor_pressure_pulse(
	path_keys: PackedInt32Array, team: int, amount_scale: float = 6.0
) -> void:
	if path_keys.is_empty() or _tile_count <= 0:
		return
	var base: float = (
		_friendly_spawn_rate if team == OWNER_FRIENDLY else _hostile_spawn_rate
	)
	var pulse: float = maxf(base * amount_scale, 12.0)
	var last_i: int = path_keys.size() - 1
	for i in range(path_keys.size()):
		var idx: int = int(path_keys[i])
		if idx < 0 or idx >= _tile_count or claimable_mask[idx] == 0:
			continue
		# Home end feeds the bridge; foreign landing gets a strong pulse so invasion is visible.
		var from_home: float = pulse * pow(0.96, float(i))
		var from_landing: float = pulse * pow(0.96, float(last_i - i))
		var amt: float = maxf(from_home, from_landing)
		if team == OWNER_FRIENDLY:
			pressure_friendly[idx] += amt
		else:
			pressure_hostile[idx] += amt
	_frontier_changed = true
	if use_active_set:
		_maybe_rebuild_active_indices(true)


func extend_beachhead_from_landing(map_data, gx: int, gy: int, team: int) -> bool:
	if map_data == null or gx < 0 or gy < 0:
		return false
	var mask: PackedByteArray = (
		_friendly_reachable if team == OWNER_FRIENDLY else _hostile_reachable
	)
	var touched: PackedInt32Array = PackedInt32Array()
	if not _flood_passable_into_mask(map_data, gx, gy, mask, touched):
		return false
	return _apply_claimable_cells(map_data, touched)


func _apply_corridor_path_sync(
	map_data,
	st: Dictionary,
	force_full: bool,
	touched: PackedInt32Array,
) -> void:
	var team: int = int(st.get("team", OWNER_FRIENDLY))
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if packed.is_empty():
		return
	var built_cells: int = clampi(_built_bridge_cells_from_structure(st), 1, packed.size())
	var synced_cells: int = 1 if force_full else int(st.get("corridor_synced_built", 1))
	synced_cells = clampi(synced_cells, 1, built_cells)
	_sync_corridor_path_cells(map_data, team, packed, built_cells, synced_cells, touched)
	st["corridor_synced_built"] = built_cells


func _apply_persisted_corridor_sync(
	map_data,
	corridor: Dictionary,
	force_full: bool,
	touched: PackedInt32Array,
) -> void:
	var team: int = int(corridor.get("team", OWNER_FRIENDLY))
	var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
	if packed.is_empty():
		return
	var built_cells: int = packed.size()
	var synced_cells: int = 1 if force_full else int(corridor.get("corridor_synced_built", 1))
	synced_cells = clampi(synced_cells, 1, built_cells)
	_sync_corridor_path_cells(map_data, team, packed, built_cells, synced_cells, touched)
	corridor["corridor_synced_built"] = built_cells


func _sync_corridor_path_cells(
	map_data,
	team: int,
	packed: PackedInt32Array,
	built_cells: int,
	synced_cells: int,
	touched: PackedInt32Array,
) -> void:
	var land_reach: PackedByteArray = (
		_friendly_reachable if team == OWNER_FRIENDLY else _hostile_reachable
	)
	var bridge_mask: PackedByteArray = (
		_friendly_bridge_reachable if team == OWNER_FRIENDLY else _hostile_bridge_reachable
	)
	var corridor_land: PackedByteArray = (
		_friendly_corridor_land if team == OWNER_FRIENDLY else _hostile_corridor_land
	)
	var src_idx: int = packed[0]
	if src_idx < 0 or src_idx >= land_reach.size() or land_reach[src_idx] == 0:
		return
	# Path source must use pipe gradient neighbors (sync loop starts at index 1).
	if synced_cells <= 1 and src_idx < corridor_land.size():
		var src_gx: int = src_idx % map_data.grid_width
		var src_gy: int = src_idx / map_data.grid_width
		if map_data.is_land_cell(src_gx, src_gy) and corridor_land[src_idx] == 0:
			corridor_land[src_idx] = 1
			_touch_bridge_flow_mask_cell(src_idx)
	if synced_cells >= built_cells:
		return
	var chain_ok: bool = true
	for i in range(1, synced_cells):
		var prev_key: int = packed[i]
		if prev_key < 0 or prev_key >= bridge_mask.size():
			chain_ok = false
			break
		if (
			bridge_mask[prev_key] == 0
			and corridor_land[prev_key] == 0
			and land_reach[prev_key] == 0
		):
			chain_ok = false
			break
	for i in range(synced_cells, built_cells):
		var cell_key: int = packed[i]
		if cell_key < 0 or cell_key >= bridge_mask.size():
			chain_ok = false
			continue
		if not chain_ok:
			continue
		var gx: int = cell_key % map_data.grid_width
		var gy: int = cell_key / map_data.grid_width
		if i > 0:
			var prev_key: int = packed[i - 1]
			if prev_key >= 0 and prev_key < _tile_count:
				_bridge_pipe_prev[cell_key] = prev_key
				_bridge_pipe_next[prev_key] = cell_key
		if WorldConquestOutpostBuildLib.is_water_cell(map_data, gx, gy):
			if bridge_mask[cell_key] == 0:
				bridge_mask[cell_key] = 1
				touched.append(cell_key)
				_touch_bridge_flow_mask_cell(cell_key)
		elif corridor_land[cell_key] == 0:
			corridor_land[cell_key] = 1
			if land_reach[cell_key] == 0:
				touched.append(cell_key)
			_touch_bridge_flow_mask_cell(cell_key)


## Ensure every built land-road cell is flagged for soldier nav (same-landmass roads
## sit on already-reachable tiles and were skipped by the old land_reach gate).
func _reconcile_corridor_land_nav_masks(map_data) -> bool:
	if map_data == null:
		return false
	var any: bool = false
	for st in map_data.placed_structures:
		if not st is Dictionary:
			continue
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		var built: int = _built_bridge_cells_from_structure(st)
		if _reconcile_packed_corridor_land(
			map_data,
			int(st.get("team", OWNER_FRIENDLY)),
			st.get("path_keys", PackedInt32Array()),
			built,
		):
			any = true
	for corridor in map_data.bridge_corridors:
		if not corridor is Dictionary:
			continue
		var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		if _reconcile_packed_corridor_land(
			map_data,
			int(corridor.get("team", OWNER_FRIENDLY)),
			packed,
			packed.size(),
		):
			any = true
	return any


func _reconcile_packed_corridor_land(
	map_data,
	team: int,
	packed: PackedInt32Array,
	built_cells: int,
) -> bool:
	if packed.is_empty() or built_cells <= 0:
		return false
	var corridor_land: PackedByteArray = (
		_friendly_corridor_land if team == OWNER_FRIENDLY else _hostile_corridor_land
	)
	var w: int = map_data.grid_width
	var any: bool = false
	var n: int = mini(built_cells, packed.size())
	for i in range(n):
		var cell_key: int = int(packed[i])
		if cell_key < 0 or cell_key >= corridor_land.size():
			continue
		var gx: int = cell_key % w
		var gy: int = cell_key / w
		if WorldConquestOutpostBuildLib.is_water_cell(map_data, gx, gy):
			continue
		if corridor_land[cell_key] != 0:
			continue
		corridor_land[cell_key] = 1
		_touch_bridge_flow_mask_cell(cell_key)
		any = true
	return any


func _built_bridge_cells_from_structure(st: Dictionary) -> int:
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if packed.is_empty():
		return 0
	var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
	if state == WorldConquestOutpostBuildLib.STATE_CONNECTING:
		return int(floor(float(st.get("path_built", 1.0))))
	return packed.size()


## Active outposts on separate landmasses (bridge-linked islands) must become claimable.
func _extend_reachability_from_spawners(map_data) -> void:
	if map_data == null or _placed_spawners.is_empty():
		return
	var changed: bool = false
	for sp: Dictionary in _placed_spawners:
		var team: int = int(sp.get("team", OWNER_FRIENDLY))
		var gx: int = int(sp.get("gx", -1))
		var gy: int = int(sp.get("gy", -1))
		if gx < 0 or gy < 0:
			continue
		var mask: PackedByteArray = (
			_friendly_reachable if team == OWNER_FRIENDLY else _hostile_reachable
		)
		if _flood_passable_into_mask(map_data, gx, gy, mask):
			changed = true
	if changed:
		_apply_reachability_to_claimable(map_data)


func _flood_passable_into_mask(
	map_data,
	start_gx: int,
	start_gy: int,
	mask: PackedByteArray,
	touched: PackedInt32Array = PackedInt32Array(),
) -> bool:
	if not map_data.is_passable(start_gx, start_gy):
		return false
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var start_idx: int = map_data.cell_index(start_gx, start_gy)
	if start_idx < 0 or start_idx >= mask.size():
		return false
	var any_new: bool = false
	if mask[start_idx] == 0:
		mask[start_idx] = 1
		any_new = true
		touched.append(start_idx)
	var queue: Array[Vector2i] = [Vector2i(start_gx, start_gy)]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d: Vector2i in _DIRS_CARDINAL:
			var nx: int = cur.x + d.x
			var ny: int = cur.y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if not map_data.is_passable(nx, ny):
				continue
			var nidx: int = map_data.cell_index(nx, ny)
			if mask[nidx] != 0:
				continue
			mask[nidx] = 1
			any_new = true
			touched.append(nidx)
			queue.append(Vector2i(nx, ny))
	return any_new


func _apply_claimable_cells(map_data, cell_indices: PackedInt32Array) -> bool:
	if map_data == null or cell_indices.is_empty():
		return false
	var w: int = map_data.grid_width
	var any_changed: bool = false
	for cell_key in cell_indices:
		var idx: int = int(cell_key)
		if idx < 0 or idx >= _tile_count:
			continue
		var gx: int = idx % w
		var gy: int = idx / w
		var was: int = claimable_mask[idx]
		var now: bool = _is_claimable_index(idx)
		if now == (was != 0):
			continue
		any_changed = true
		claimable_mask[idx] = 1 if now else 0
		_mark_claimable_dirty(idx)
		if now:
			claimable_tile_count += 1
			_elevation[idx] = tile_elevation(map_data, gx, gy)
			_terrain_flow_mult[idx] = _flow_mult_for_bridge_or_land(map_data, gx, gy, idx)
			_claim_ratio_mult[idx] = _claim_mult_for_tile(map_data, gx, gy, true)
			if owners[idx] == OWNER_UNCLAIMABLE:
				owners[idx] = OWNER_NEUTRAL
		else:
			claimable_tile_count = maxi(claimable_tile_count - 1, 0)
			owners[idx] = OWNER_UNCLAIMABLE
			pressure_friendly[idx] = 0.0
			pressure_hostile[idx] = 0.0
	if any_changed:
		_frontier_changed = true
	return any_changed


func _apply_reachability_to_claimable(map_data) -> void:
	if map_data == null:
		return
	var w: int = map_data.grid_width
	for idx in range(_tile_count):
		var gx: int = idx % w
		var gy: int = idx / w
		var was: int = claimable_mask[idx]
		var now: bool = _is_claimable_index(idx)
		claimable_mask[idx] = 1 if now else 0
		if now and was == 0:
			_elevation[idx] = tile_elevation(map_data, gx, gy)
			_terrain_flow_mult[idx] = _flow_mult_for_bridge_or_land(map_data, gx, gy, idx)
			_claim_ratio_mult[idx] = _claim_mult_for_tile(map_data, gx, gy, true)
			if owners[idx] == OWNER_UNCLAIMABLE:
				owners[idx] = OWNER_NEUTRAL
		elif not now and was != 0:
			owners[idx] = OWNER_UNCLAIMABLE
			pressure_friendly[idx] = 0.0
			pressure_hostile[idx] = 0.0
	claimable_tile_count = 0
	for idx2 in range(_tile_count):
		if claimable_mask[idx2] != 0:
			claimable_tile_count += 1
	_recount_ownership()
	_frontier_changed = true


const _DIRS_CARDINAL: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


func _inject_territory_spawn_pressure(map_data) -> void:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			if not _is_claimable_index(idx):
				continue
			var owner: int = owners[idx]
			if owner != OWNER_FRIENDLY and owner != OWNER_HOSTILE:
				continue
			var at_edge: bool = false
			for d in dirs:
				var ni: int = map_data.cell_index(gx + d.x, gy + d.y)
				if not _is_claimable_index(ni):
					continue
				if owners[ni] != owner:
					at_edge = true
					break
			var base: float = PRESSURE_SPAWN_EDGE if at_edge else PRESSURE_SPAWN_BASE
			if owner == OWNER_FRIENDLY:
				pressure_friendly[idx] += base * _friendly_spawn_rate
			else:
				pressure_hostile[idx] += base * _hostile_spawn_rate


## Match BattleTileFluidField._pressures_to_owners — sim territory should track visible fluid.
func _sync_ownership_from_pressures() -> void:
	const CLAIM_DOMINANCE_RATIO := 1.15
	var work_full: bool = not use_active_set or _active_indices.is_empty()
	if work_full:
		for idx in range(_tile_count):
			_sync_ownership_tile(idx, CLAIM_DOMINANCE_RATIO)
		return
	for idx in _active_indices:
		_sync_ownership_tile(idx, CLAIM_DOMINANCE_RATIO)


func _sync_ownership_tile(idx: int, dominance_ratio: float) -> void:
	if claimable_mask[idx] == 0:
		owners[idx] = OWNER_UNCLAIMABLE
		return
	var pf: float = pressure_friendly[idx]
	var ph: float = pressure_hostile[idx]
	var new_owner: int = owners[idx]
	var tile_ratio: float = dominance_ratio * _claim_ratio_mult[idx]
	if pf < MIN_CLAIM_PRESSURE and ph < MIN_CLAIM_PRESSURE:
		if owners[idx] != OWNER_FRIENDLY and owners[idx] != OWNER_HOSTILE:
			new_owner = OWNER_NEUTRAL
	elif pf > ph * tile_ratio:
		new_owner = OWNER_FRIENDLY
	elif ph > pf * tile_ratio:
		new_owner = OWNER_HOSTILE
	else:
		new_owner = OWNER_CONTESTED
	if new_owner != owners[idx]:
		_adjust_owner_count(owners[idx], -1)
		_adjust_owner_count(new_owner, 1)
		owners[idx] = new_owner
		_frontier_changed = true
		_mark_active_dirty(idx)


func _mark_active_dirty(idx: int) -> void:
	if not use_active_set or idx < 0 or idx >= _tile_count:
		return
	if _active_dirty_mark[idx] != 0:
		return
	_active_dirty_mark[idx] = 1
	_active_dirty_list.append(idx)
	if _map_data == null:
		return
	var w: int = _map_data.grid_width
	var gx: int = idx % w
	var gy: int = idx / w
	for d in _CARDINAL_DIRS:
		var ni: int = _map_data.cell_index(gx + d.x, gy + d.y)
		if ni < 0 or ni >= _tile_count or _active_dirty_mark[ni] != 0:
			continue
		_active_dirty_mark[ni] = 1
		_active_dirty_list.append(ni)


func _is_tile_active(idx: int) -> bool:
	if idx < 0 or idx >= _tile_count or claimable_mask[idx] == 0:
		return false
	if pressure_friendly[idx] > ACTIVE_PRESSURE_EPS or pressure_hostile[idx] > ACTIVE_PRESSURE_EPS:
		return true
	var w: int = _map_data.grid_width
	var gx: int = idx % w
	var gy: int = idx / w
	for d in _CARDINAL_DIRS:
		var ni: int = _map_data.cell_index(gx + d.x, gy + d.y)
		if claimable_mask[ni] == 0:
			continue
		if owners[ni] == OWNER_CONTESTED or owners[idx] != owners[ni]:
			return true
	return false


func _patch_active_indices() -> void:
	for idx: int in _active_dirty_list:
		if idx < 0 or idx >= _tile_count:
			continue
		_active_dirty_mark[idx] = 0
		var should: bool = _is_tile_active(idx)
		var was: bool = _active_seen[idx] != 0
		if should and not was:
			_active_indices.append(idx)
			_active_seen[idx] = 1
		elif not should and was:
			_active_seen[idx] = 0
			var pos: int = _active_indices.find(idx)
			if pos >= 0:
				_active_indices.remove_at(pos)
	_active_dirty_list.clear()


func _recount_ownership() -> void:
	friendly_tiles = 0
	hostile_tiles = 0
	for idx in range(_tile_count):
		if claimable_mask[idx] == 0:
			continue
		if owners[idx] == OWNER_FRIENDLY:
			friendly_tiles += 1
		elif owners[idx] == OWNER_HOSTILE:
			hostile_tiles += 1


func _maybe_rebuild_active_indices(force: bool = false) -> void:
	if not use_active_set:
		return
	_rounds_since_active_rebuild += 1
	var periodic: bool = _rounds_since_active_rebuild >= ACTIVE_REBUILD_INTERVAL
	if force or periodic:
		_rebuild_active_indices()
		_frontier_changed = false
		_rounds_since_active_rebuild = 0
		_active_dirty_list.clear()
		if _active_dirty_mark.size() == _tile_count:
			_active_dirty_mark.fill(0)
		return
	if _frontier_changed and not _active_dirty_list.is_empty():
		if _active_dirty_list.size() <= INCREMENTAL_ACTIVE_MAX_DIRTY:
			_patch_active_indices()
		else:
			_rebuild_active_indices()
		_frontier_changed = false
		_active_dirty_list.clear()
		if _active_dirty_mark.size() == _tile_count:
			_active_dirty_mark.fill(0)


func _rebuild_active_indices() -> void:
	_active_indices.clear()
	if _tile_count <= 0:
		return
	_active_seen.fill(0)
	for idx in range(_tile_count):
		if claimable_mask[idx] == 0:
			continue
		var active: bool = (
			pressure_friendly[idx] > ACTIVE_PRESSURE_EPS
			or pressure_hostile[idx] > ACTIVE_PRESSURE_EPS
		)
		if not active:
			var w: int = _map_data.grid_width
			var gx: int = idx % w
			var gy: int = idx / w
			for d in _CARDINAL_DIRS:
				var ni: int = _map_data.cell_index(gx + d.x, gy + d.y)
				if claimable_mask[ni] == 0:
					continue
				if (
					owners[ni] == OWNER_CONTESTED
					or owners[idx] != owners[ni]
				):
					active = true
					break
		if active:
			_active_indices.append(idx)
			_active_seen[idx] = 1


func _resolve_ownership_from_pressure() -> void:
	var flips: int = 0
	for idx in range(_tile_count):
		if not _is_claimable_index(idx):
			owners[idx] = OWNER_UNCLAIMABLE
			continue
		var pf: float = pressure_friendly[idx]
		var ph: float = pressure_hostile[idx]
		if pf < 0.05 and ph < 0.05:
			if owners[idx] != OWNER_FRIENDLY and owners[idx] != OWNER_HOSTILE:
				owners[idx] = OWNER_NEUTRAL
			continue
		if pf > ph + FLIP_THRESHOLD and owners[idx] != OWNER_FRIENDLY:
			if flips < MAX_FLIPS_PER_ROUND or owners[idx] == OWNER_HOSTILE:
				owners[idx] = OWNER_FRIENDLY
				flips += 1
		elif ph > pf + FLIP_THRESHOLD and owners[idx] != OWNER_HOSTILE:
			if flips < MAX_FLIPS_PER_ROUND or owners[idx] == OWNER_FRIENDLY:
				owners[idx] = OWNER_HOSTILE
				flips += 1
		elif pf > 0.15 and ph > 0.15:
			owners[idx] = OWNER_CONTESTED
		elif pf > ph:
			owners[idx] = OWNER_FRIENDLY
		else:
			owners[idx] = OWNER_HOSTILE


func _diffuse_pressure_height_biased(map_data) -> void:
	if _map_data == null:
		_diffuse_pressure_once(map_data)
		return
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height

	# Use ping-pong buffers when available to avoid expensive .duplicate() allocations every pass
	var use_pingpong := _pressure_friendly_next.size() == pressure_friendly.size()
	var nf := _pressure_friendly_next if use_pingpong else pressure_friendly.duplicate()
	var nh := _pressure_hostile_next if use_pingpong else pressure_hostile.duplicate()

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			if not _is_claimable_index(idx):
				continue
			var h_here: float = _map_data.get_tile_height(gx, gy)
			var sum_f: float = pressure_friendly[idx]
			var sum_h: float = pressure_hostile[idx]
			var w_f: float = 1.0
			var w_h: float = 1.0
			for d in dirs:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni: int = map_data.cell_index(nx, ny)
				if not _is_claimable_index(ni):
					continue
				var h_n: float = _map_data.get_tile_height(nx, ny)
				var delta: float = h_here - h_n
				if delta > HEIGHT_UPHILL_BLOCK:
					continue
				var flow_w: float = 0.6
				if delta > 0.02:
					flow_w *= HEIGHT_DOWNHILL_BOOST
				elif delta < -0.02:
					flow_w *= HEIGHT_UPHILL_PENALTY
				sum_f += pressure_friendly[ni] * flow_w
				sum_h += pressure_hostile[ni] * flow_w
				w_f += flow_w
				w_h += flow_w
			nf[idx] = sum_f / w_f
			nh[idx] = sum_h / w_h

	pressure_friendly = nf
	pressure_hostile = nh

	# Swap ping-pong buffers for next use
	if use_pingpong:
		_pressure_friendly_next = pressure_friendly
		_pressure_hostile_next = pressure_hostile
		# The old arrays are now the "current" ones after assignment above; swap references back
		# Actually the assignment already did the swap — we just need to prepare the "next" for next time.
		# Simpler: re-alias for next diffusion pass
		_pressure_friendly_next = nf if nf == _pressure_friendly_next else pressure_friendly  # no-op in practice after first use
		_pressure_hostile_next = nh if nh == _pressure_hostile_next else pressure_hostile


func _diffuse_pressure_once(map_data) -> void:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var nf := pressure_friendly.duplicate()
	var nh := pressure_hostile.duplicate()
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			if not _is_claimable_index(idx):
				continue
			var sum_f: float = pressure_friendly[idx]
			var sum_h: float = pressure_hostile[idx]
			var cnt: int = 1
			for d in dirs:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni: int = map_data.cell_index(nx, ny)
				if not _is_claimable_index(ni):
					continue
				sum_f += pressure_friendly[ni] * 0.6
				sum_h += pressure_hostile[ni] * 0.6
				cnt += 1
			nf[idx] = sum_f / float(cnt)
			nh[idx] = sum_h / float(cnt)
	pressure_friendly = nf
	pressure_hostile = nh


func seed_initial_owners(map_data, store, cell_grid = null) -> PackedByteArray:
	if map_data == null:
		return owners.duplicate()
	_fill_spawn_zone(map_data, map_data.player_spawn_zone, OWNER_FRIENDLY)
	_fill_spawn_zone(map_data, map_data.enemy_spawn_zone, OWNER_HOSTILE)
	for cell in _spawn_cells(map_data, true):
		_claim_at(cell.x, cell.y, OWNER_FRIENDLY)
	for cell in _spawn_cells(map_data, false):
		_claim_at(cell.x, cell.y, OWNER_HOSTILE)
	# Give seeded zones an initial pressure head-start so the front begins expanding immediately
	_seed_initial_pressure(map_data)
	return compute_frame(map_data, store, cell_grid)


static func home_spawn_rate_for_force(committed: int, galaxy_bonus: float = 0.0) -> float:
	var units: int = maxi(1, committed)
	return HOME_START_POWER * (1.0 + float(units) * SPAWN_MULTIPLIER_PER_UNIT + galaxy_bonus)


func _seed_initial_pressure(map_data) -> void:
	if map_data == null:
		return
	_inject_home_base_tile(map_data, map_data.player_spawn_zone, _friendly_spawn_rate, true, true)
	_inject_home_base_tile(map_data, map_data.enemy_spawn_zone, _hostile_spawn_rate, false, true)


func compute_frame(map_data, store, cell_grid = null) -> PackedByteArray:
	if map_data == null or _tile_count <= 0:
		return owners.duplicate()
	propagate_round(map_data, store, cell_grid)
	return owners.duplicate()


func owners_copy() -> PackedByteArray:
	return owners.duplicate()


static func owner_color(owner: int) -> Color:
	match owner:
		OWNER_FRIENDLY:
			return Color(0.35, 0.75, 1.0, 0.30)
		OWNER_HOSTILE:
			return Color(0.95, 0.35, 0.30, 0.30)
		OWNER_CONTESTED:
			return Color(0.95, 0.55, 0.15, 0.35)
		_:
			return Color(0, 0, 0, 0)


static func _spawn_cells(map_data, player: bool) -> Array:
	if map_data == null:
		return []
	var raw: Array = map_data.player_spawn_cells if player else map_data.enemy_spawn_cells
	var out: Array = []
	for cell in raw:
		var v := _cell_to_vec2i(cell)
		if v.x >= 0 and v.y >= 0:
			out.append(v)
	if out.is_empty() and map_data != null:
		var zone: Rect2 = map_data.player_spawn_zone if player else map_data.enemy_spawn_zone
		if zone.size.x > 0.0 and zone.size.y > 0.0:
			var gx: int = int(zone.position.x / map_data.cell_size)
			var gy: int = int(zone.position.y / map_data.cell_size)
			out.append(Vector2i(gx, gy))
	return out


static func _cell_to_vec2i(cell) -> Vector2i:
	if cell is Vector2i:
		return cell
	if typeof(cell) == TYPE_DICTIONARY:
		return Vector2i(int(cell.get("x", cell.get("gx", -1))), int(cell.get("y", cell.get("gy", -1))))
	if typeof(cell) == TYPE_ARRAY and cell.size() >= 2:
		return Vector2i(int(cell[0]), int(cell[1]))
	return Vector2i(-1, -1)


func _emit_from_zone(map_data, zone: Rect2, amount: float, is_friendly: bool) -> void:
	if map_data == null or zone.size.x <= 1.0 or zone.size.y <= 1.0 or amount <= 0.0:
		return

	var g0: Vector2i = map_data.world_to_grid(zone.position)
	var g1: Vector2i = map_data.world_to_grid(zone.position + zone.size)

	for gy in range(max(0, g0.y), min(map_data.grid_height, g1.y)):
		for gx in range(max(0, g0.x), min(map_data.grid_width, g1.x)):
			var idx: int = map_data.cell_index(gx, gy)
			if not _is_claimable_index(idx):
				continue

			if is_friendly:
				pressure_friendly[idx] += amount
			else:
				pressure_hostile[idx] += amount


# Strong direct pulse at the exact center of a home zone.
# This makes power visibly "erupt" from the home base marker every step
# and then flow outward — exactly the Creeper World feel the user wants.
func _inject_strong_home_pulse(map_data, zone: Rect2, amount: float, is_friendly: bool) -> void:
	if map_data == null or zone.size.x <= 1.0 or zone.size.y <= 1.0 or amount <= 0.0:
		return

	var center_world: Vector2 = zone.position + zone.size * 0.5
	var center: Vector2i = map_data.world_to_grid(center_world)

	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var gx: int = center.x + dx
			var gy: int = center.y + dy
			if gx < 0 or gx >= map_data.grid_width or gy < 0 or gy >= map_data.grid_height:
				continue
			var idx: int = map_data.cell_index(gx, gy)
			if not _is_claimable_index(idx):
				continue

			var strength: float = amount
			if dx != 0 or dy != 0:
				strength *= 0.55   # slightly weaker on the 8 surrounding cells

			if is_friendly:
				pressure_friendly[idx] += strength
			else:
				pressure_hostile[idx] += strength


func _fill_spawn_zone(map_data, zone: Rect2, owner: int) -> void:
	if map_data == null or zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return
	var g0: Vector2i = map_data.world_to_grid(zone.position)
	var g1: Vector2i = map_data.world_to_grid(zone.position + zone.size)
	var x0: int = clampi(mini(g0.x, g1.x), 0, map_data.grid_width - 1)
	var x1: int = clampi(maxi(g0.x, g1.x), 0, map_data.grid_width - 1)
	var y0: int = clampi(mini(g0.y, g1.y), 0, map_data.grid_height - 1)
	var y1: int = clampi(maxi(g0.y, g1.y), 0, map_data.grid_height - 1)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			_claim_at(gx, gy, owner)


func _apply_territory_creep(map_data) -> void:
	if map_data == null:
		return
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for _pass in range(2):
		var next: PackedByteArray = owners.duplicate()
		for gy in range(map_data.grid_height):
			for gx in range(map_data.grid_width):
				var idx: int = map_data.cell_index(gx, gy)
				if owners[idx] == OWNER_UNCLAIMABLE or not _is_claimable_index(idx):
					continue
				if owners[idx] != OWNER_NEUTRAL:
					continue
				var f_adj: bool = false
				var h_adj: bool = false
				for d in dirs:
					var ni: int = map_data.cell_index(gx + d.x, gy + d.y)
					if owners[ni] == OWNER_FRIENDLY:
						f_adj = true
					elif owners[ni] == OWNER_HOSTILE:
						h_adj = true
				if f_adj and not h_adj:
					next[idx] = OWNER_FRIENDLY
				elif h_adj and not f_adj:
					next[idx] = OWNER_HOSTILE
		owners = next


func _adjust_owner_count(owner: int, delta: int) -> void:
	if delta == 0:
		return
	match owner:
		OWNER_FRIENDLY:
			friendly_tiles = maxi(0, friendly_tiles + delta)
		OWNER_HOSTILE:
			hostile_tiles = maxi(0, hostile_tiles + delta)


func _claim_at(gx: int, gy: int, owner: int) -> void:
	if _map_data == null:
		return
	if gx < 0 or gy < 0 or gx >= _map_data.grid_width or gy >= _map_data.grid_height:
		return
	var idx: int = _map_data.cell_index(gx, gy)
	if claimable_mask[idx] == 0:
		return
	if owners[idx] != owner:
		_adjust_owner_count(owners[idx], -1)
		_adjust_owner_count(owner, 1)
		owners[idx] = owner
		_frontier_changed = true


func _touch_bridge_flow_mask_cell(idx: int) -> void:
	if idx < 0 or idx >= _tile_count:
		return
	if _bridge_water_mask_cache.size() != _tile_count:
		_bridge_flow_masks_dirty = true
		return
	_bridge_water_mask_cache[idx] = 1 if _is_bridge_water_index(idx) else 0
	_corridor_land_mask_cache[idx] = 1 if _is_corridor_land_index(idx) else 0


func _ensure_bridge_flow_masks() -> void:
	if not _bridge_flow_masks_dirty:
		return
	if _bridge_water_mask_cache.size() != _tile_count:
		_bridge_water_mask_cache.resize(_tile_count)
		_corridor_land_mask_cache.resize(_tile_count)
	for idx in range(_tile_count):
		_bridge_water_mask_cache[idx] = 1 if _is_bridge_water_index(idx) else 0
		_corridor_land_mask_cache[idx] = 1 if _is_corridor_land_index(idx) else 0
	_bridge_flow_masks_dirty = false


func bridge_water_mask_packed() -> PackedByteArray:
	_ensure_bridge_flow_masks()
	return _bridge_water_mask_cache


func corridor_land_mask_packed() -> PackedByteArray:
	_ensure_bridge_flow_masks()
	return _corridor_land_mask_cache


func friendly_corridor_land_packed() -> PackedByteArray:
	return _friendly_corridor_land


func hostile_corridor_land_packed() -> PackedByteArray:
	return _hostile_corridor_land


func friendly_bridge_reachable_packed() -> PackedByteArray:
	return _friendly_bridge_reachable


func hostile_bridge_reachable_packed() -> PackedByteArray:
	return _hostile_bridge_reachable


func _is_bridge_water_index(idx: int) -> bool:
	if _map_data == null or idx < 0 or idx >= _tile_count:
		return false
	var gx: int = idx % _map_data.grid_width
	var gy: int = idx / _map_data.grid_width
	if _map_data.is_land_cell(gx, gy):
		return false
	if idx >= _friendly_bridge_reachable.size():
		return false
	return _friendly_bridge_reachable[idx] > 0 or _hostile_bridge_reachable[idx] > 0


func _flow_mult_for_bridge_or_land(map_data, gx: int, gy: int, idx: int) -> float:
	if _is_bridge_water_index(idx):
		return WorldConquestConfigLib.BRIDGE_PRESSURE_FLOW_MULT
	return _flow_mult_for_tile(map_data, gx, gy, true)


func _is_claimable_index(idx: int) -> bool:
	if _map_data == null or idx < 0 or idx >= _tile_count:
		return false
	var gx: int = idx % _map_data.grid_width
	var gy: int = idx / _map_data.grid_width
	if idx >= _friendly_reachable.size() or idx >= _hostile_reachable.size():
		return false
	if _map_data.is_land_cell(gx, gy):
		return (
			_friendly_reachable[idx] > 0
			or _hostile_reachable[idx] > 0
			or _friendly_corridor_land[idx] > 0
			or _hostile_corridor_land[idx] > 0
		)
	if idx >= _friendly_bridge_reachable.size():
		return false
	return _friendly_bridge_reachable[idx] > 0 or _hostile_bridge_reachable[idx] > 0


func _bfs_reachable(map_data, seeds: Array) -> PackedByteArray:
	var total: int = map_data.grid_width * map_data.grid_height if map_data else 0
	var mask := PackedByteArray()
	mask.resize(total)
	mask.fill(0)
	if map_data == null or total <= 0:
		return mask
	var queue: Array = []
	for cell in seeds:
		var v := _cell_to_vec2i(cell)
		if v.x < 0 or v.y < 0 or v.x >= map_data.grid_width or v.y >= map_data.grid_height:
			continue
		if not map_data.is_passable(v.x, v.y):
			continue
		var idx: int = map_data.cell_index(v.x, v.y)
		if mask[idx] != 0:
			continue
		mask[idx] = 1
		queue.append(v)
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nx: int = cur.x + d.x
			var ny: int = cur.y + d.y
			if nx < 0 or ny < 0 or nx >= map_data.grid_width or ny >= map_data.grid_height:
				continue
			if not map_data.is_passable(nx, ny):
				continue
			var nidx: int = map_data.cell_index(nx, ny)
			if mask[nidx] != 0:
				continue
			mask[nidx] = 1
			queue.append(Vector2i(nx, ny))
	return mask


func _mark_claimable_dirty(idx: int) -> void:
	if idx < 0 or idx >= _tile_count:
		return
	if _claimable_dirty_lookup.size() != _tile_count:
		_claimable_dirty_lookup.resize(_tile_count)
		_claimable_dirty_lookup.fill(0)
	if _claimable_dirty_lookup[idx] != 0:
		return
	_claimable_dirty_lookup[idx] = 1
	_claimable_dirty_indices.append(idx)


func take_claimable_dirty_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _claimable_dirty_indices.is_empty():
		return out
	for idx: int in _claimable_dirty_indices:
		out.append(idx)
	_claimable_dirty_indices.clear()
	if _claimable_dirty_lookup.size() == _tile_count:
		for idx in out:
			if idx >= 0 and idx < _claimable_dirty_lookup.size():
				_claimable_dirty_lookup[idx] = 0
	return out
