class_name BattleTileControl
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

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
const ACTIVE_REBUILD_INTERVAL := 3

var _map_data = null
var _tile_count: int = 0
var _friendly_reachable: PackedByteArray = PackedByteArray()
var _hostile_reachable: PackedByteArray = PackedByteArray()
var _friendly_spawn_rate: float = 1.0
var _hostile_spawn_rate: float = 1.0

var use_simple_water_model: bool = false
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
	claimable_mask.resize(_tile_count)
	_elevation.resize(_tile_count)
	_terrain_flow_mult.resize(_tile_count)
	_claim_ratio_mult.resize(_tile_count)
	_active_seen.resize(_tile_count)
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


func reset_for_battle(map_data, store, cell_grid = null) -> void:
	setup(map_data)
	reset_pressures()
	seed_initial_owners(map_data, store, cell_grid)


func apply_building_modifiers(mods: Dictionary) -> void:
	_friendly_spawn_rate = 1.0 + float(mods.get("friendly_pressure", 0.0))
	_hostile_spawn_rate = 1.0 + float(mods.get("hostile_pressure", 0.0))

func enable_world_conquest_model(player_force: int, enemy_force: int) -> void:
	enable_simple_water_model(player_force, enemy_force, 0.0, 0.0)
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
	if perf != null:
		perf.end_phase("inject", t_inj)

	var t_grad: int = 0
	if perf != null:
		t_grad = perf.begin_phase("gradient")
	_run_gradient_cancel_sync_pass(map_data)
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
	var tmp_f: PackedFloat32Array = pressure_friendly
	pressure_friendly = _pressure_friendly_next
	_pressure_friendly_next = tmp_f
	_gradient_flow_pass_into(map_data, w, h, pressure_hostile, _pressure_hostile_next)
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
	for d in _CARDINAL_DIRS:
		var nx: int = gx + d.x
		var ny: int = gy + d.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var ni: int = map_data.cell_index(nx, ny)
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
	map_data, start_gx: int, start_gy: int, mask: PackedByteArray
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
			queue.append(Vector2i(nx, ny))
	return any_new


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
			_terrain_flow_mult[idx] = _flow_mult_for_tile(map_data, gx, gy, true)
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
	if force or _frontier_changed or _rounds_since_active_rebuild >= ACTIVE_REBUILD_INTERVAL:
		_rebuild_active_indices()
		_frontier_changed = false
		_rounds_since_active_rebuild = 0


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


func _is_claimable_index(idx: int) -> bool:
	if _map_data == null or idx < 0 or idx >= _tile_count:
		return false
	var gx: int = idx % _map_data.grid_width
	var gy: int = idx / _map_data.grid_width
	if not _map_data.is_land_cell(gx, gy):
		return false
	if idx >= _friendly_reachable.size() or idx >= _hostile_reachable.size():
		return false
	return _friendly_reachable[idx] > 0 or _hostile_reachable[idx] > 0


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
