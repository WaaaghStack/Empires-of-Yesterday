class_name BattleTerritorySim
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryGpuFieldLib := preload("res://BattleTerritoryGpuField.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const BattlePerfProfilerLib := preload("res://BattlePerfProfiler.gd")
const BuildingDefinitionLib := preload("res://BuildingDefinition.gd")
const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")

const MAX_ROUNDS_DEFAULT := 4800
const DOMINANCE_FRAC := 0.92
const DOMINANCE_ROUNDS := 10
const STALL_ROUNDS := 20
const STALL_ROUNDS_VIEWER := 200
const STALL_TILE_DELTA := 2
## End early when a much larger army holds a clear map share (avoids 3000-round grinds).
const DECISIVE_TILE_FRAC := 0.64
const DECISIVE_FORCE_RATIO := 2.4
const DECISIVE_HOLD_ROUNDS := 12

const BACKEND_CPU := 0
const BACKEND_GPU := 1
const BACKEND_RUST := 2

var battle_data = null
var tile_control: BattleTileControlLib
var gpu_field: BattleTerritoryGpuFieldLib
var rust_field: BattleTerritoryRustBackendLib
var backend: int = BACKEND_CPU
var gpu_live_ready: bool = false
var rust_live_ready: bool = false
var round_index: int = 0
var sim_time: float = 0.0
var step_dt: float = BattlePacingLib.SIM_ROUND_SECONDS
var _dt_accum: float = 0.0
var finished: bool = false
var player_won: bool = false
var player_force: int = 0
var enemy_force: int = 0
var claimable_tiles: int = 0
var building_mods: Dictionary = {}
var max_rounds_limit: int = MAX_ROUNDS_DEFAULT
var end_reason: String = ""

var use_simple_water_model: bool = true
var _resolve_context: String = "full"

var _dominance_streak: int = 0
var _dominance_leader: int = 0  # 1 player, 2 enemy
var _stall_rounds: int = 0
var _stall_rounds_limit: int = STALL_ROUNDS
var _decisive_streak: int = 0
var _decisive_leader: int = 0  # 1 player, 2 enemy
var _prev_friendly: int = 0
var _prev_hostile: int = 0
var _dominance_hold_sec: float = 0.0
var _stall_sec: float = 0.0
var _decisive_hold_sec: float = 0.0
var _profiler: BattlePerfProfilerLib


func setup(
	map_data,
	player_count: int,
	enemy_count: int,
	galaxy = null,
	_commander_profile: Dictionary = {},
	world_conquest: bool = false,
) -> void:
	battle_data = map_data
	player_force = maxi(1, player_count)
	enemy_force = maxi(1, enemy_count)
	building_mods = _pressure_mods_from_galaxy(galaxy)
	tile_control = BattleTileControlLib.new()
	tile_control.setup(map_data)
	tile_control.apply_building_modifiers(building_mods)

	if use_simple_water_model:
		if world_conquest:
			tile_control.enable_world_conquest_model(player_count, enemy_count)
		else:
			tile_control.enable_simple_water_model(
				player_count,
				enemy_count,
				float(building_mods.get("friendly_pressure", 0.0)),
				maxf(0.0, float(building_mods.get("hostile_pressure", 0.04)) - 0.04),
			)
		tile_control.seed_territory_battle(map_data)
	else:
		tile_control.seed_territory_battle(map_data)
	claimable_tiles = tile_control.claimable_tile_count if tile_control != null else 0
	if claimable_tiles <= 0:
		claimable_tiles = _count_claimable()
	round_index = 0
	sim_time = 0.0
	_dt_accum = 0.0
	finished = false
	player_won = false
	end_reason = ""
	_dominance_streak = 0
	_dominance_leader = 0
	_stall_rounds = 0
	_decisive_streak = 0
	_decisive_leader = 0
	_dominance_hold_sec = 0.0
	_stall_sec = 0.0
	_decisive_hold_sec = 0.0
	_prev_friendly = _tiles_owned_by_player()
	_prev_hostile = _tiles_owned_by_enemy()
	_apply_max_rounds_for_context()


func use_gpu_for_live() -> bool:
	return backend == BACKEND_GPU


func use_rust_for_live() -> bool:
	return backend == BACKEND_RUST


func set_live_backend(use_gpu: bool) -> void:
	if use_gpu:
		backend = BACKEND_GPU
	elif rust_live_ready:
		backend = BACKEND_RUST
	else:
		backend = BACKEND_CPU


func enable_gpu_live() -> bool:
	if battle_data == null or tile_control == null:
		return false
	if not BattleTerritoryGpuFieldLib.default_live_backend_enabled():
		backend = BACKEND_CPU
		gpu_live_ready = false
		return false
	gpu_field = BattleTerritoryGpuFieldLib.new()
	gpu_live_ready = gpu_field.setup_from_tile_control(battle_data, tile_control)
	if gpu_live_ready:
		backend = BACKEND_GPU
		tile_control.friendly_tiles = gpu_field.friendly_tiles
		tile_control.hostile_tiles = gpu_field.hostile_tiles
	else:
		backend = BACKEND_CPU
		gpu_field = null
		push_warning(
			"BattleTerritoryGpuField: GPU live init failed; using CPU territory sim."
		)
	return gpu_live_ready


func enable_rust_live() -> bool:
	if battle_data == null or tile_control == null:
		return false
	if not BattleTerritoryRustBackendLib.extension_available():
		backend = BACKEND_CPU
		rust_live_ready = false
		return false
	rust_field = BattleTerritoryRustBackendLib.new()
	rust_live_ready = rust_field.setup_from_tile_control(battle_data, tile_control, true)
	if rust_live_ready:
		backend = BACKEND_RUST
		gpu_live_ready = false
		gpu_field = null
	else:
		backend = BACKEND_CPU
		rust_field = null
		push_warning(
			"BattleTerritoryRustBackend: Rust init failed; using CPU territory sim."
		)
	return rust_live_ready


func _ensure_rust_resolve_backend() -> bool:
	if battle_data == null or tile_control == null:
		return false
	if rust_field != null and rust_field.ready:
		backend = BACKEND_RUST
		return true
	if not BattleTerritoryRustBackendLib.default_resolve_backend_enabled():
		return false
	rust_field = BattleTerritoryRustBackendLib.new()
	rust_live_ready = rust_field.setup_from_tile_control(battle_data, tile_control)
	if rust_live_ready:
		backend = BACKEND_RUST
	return rust_live_ready


func set_resolve_context(context: String) -> void:
	_resolve_context = context
	if battle_data != null:
		_apply_max_rounds_for_context()


func _apply_max_rounds_for_context() -> void:
	match _resolve_context:
		"world_conquest":
			step_dt = WorldConquestConfigLib.SIM_DT
			max_rounds_limit = int(WorldConquestConfigLib.MAX_SIM_TIME_SEC / step_dt)
			_stall_rounds_limit = int(WorldConquestConfigLib.STALL_SEC / step_dt)
		"world":
			max_rounds_limit = MAX_ROUNDS_DEFAULT * 4
			_stall_rounds_limit = STALL_ROUNDS_VIEWER
		"queue":
			apply_queue_resolve_cap()
		"viewer":
			apply_viewer_resolve_cap()
		_:
			max_rounds_limit = _estimate_max_rounds()


func apply_queue_resolve_cap() -> void:
	max_rounds_limit = mini(_estimate_max_rounds(), BattlePacingLib.RESOLVE_MAX_ROUNDS_CAP)
	_stall_rounds_limit = STALL_ROUNDS


func apply_viewer_resolve_cap() -> void:
	max_rounds_limit = mini(_estimate_max_rounds(), BattlePacingLib.VIEWER_MAX_ROUNDS_CAP)
	_stall_rounds_limit = STALL_ROUNDS_VIEWER


func advance_dt(delta: float, max_steps: int = 12) -> Dictionary:
	if finished or battle_data == null or tile_control == null:
		return {"steps": 0, "finished": finished, "sim_time": sim_time}
	_dt_accum += delta
	var steps_to_run: int = 0
	while _dt_accum >= step_dt and steps_to_run < max_steps:
		_dt_accum -= step_dt
		steps_to_run += 1
	if steps_to_run <= 0:
		return {"steps": 0, "finished": finished, "sim_time": sim_time}
	var steps_done: int = 0
	if backend == BACKEND_RUST and rust_field != null and rust_field.ready:
		steps_done = _advance_rust_rounds(steps_to_run)
		sim_time += step_dt * float(steps_done)
	else:
		for _i in range(steps_to_run):
			if finished:
				break
			advance_round()
			sim_time += step_dt
			steps_done += 1
	return {"steps": steps_done, "finished": finished, "sim_time": sim_time}


func _advance_rust_rounds(count: int) -> int:
	if count <= 0 or finished or tile_control == null or rust_field == null:
		return 0
	rust_field.step_rounds(tile_control, count)
	round_index += count
	for _i in range(count):
		_check_conquest()
		if finished:
			break
	return count


func advance_round() -> void:
	if finished or battle_data == null or tile_control == null:
		return
	round_index += 1
	if backend == BACKEND_GPU and gpu_field != null and gpu_field.ready:
		gpu_field.step_round(tile_control)
		if gpu_field.readback_owners():
			gpu_field.copy_owners_to_cpu_buffer(tile_control.owners)
			tile_control.friendly_tiles = gpu_field.friendly_tiles
			tile_control.hostile_tiles = gpu_field.hostile_tiles
	elif backend == BACKEND_RUST and rust_field != null and rust_field.ready:
		rust_field.step_round(tile_control)
	else:
		tile_control.propagate_round_territory(battle_data)
	_check_conquest()


func run_to_completion(max_rounds: int = -1) -> Dictionary:
	var cap: int = max_rounds if max_rounds > 0 else max_rounds_limit
	while not finished and round_index < cap:
		advance_round()
	return get_result()


func build_replay_tape(max_rounds: int = -1, record_stride: int = 1) -> BattleTerritoryTapeLib:
	var tape := BattleTerritoryTapeLib.new()
	tape.record_stride = maxi(1, record_stride)
	if tile_control == null:
		return tape
	var saved_backend: int = backend
	var saved_rust_field = rust_field
	var saved_rust_ready: bool = rust_live_ready
	if not _ensure_rust_resolve_backend():
		backend = BACKEND_CPU
	_profiler = BattlePerfProfilerLib.new()
	if tile_control != null:
		tile_control.perf = _profiler

	var t0: int = Time.get_ticks_usec()
	var pressure_stride: int = tape.record_stride * BattlePacingLib.PRESSURE_KEYFRAME_STRIDE_MULT
	_record_tape_frame(tape, pressure_stride, true)
	var cap: int = max_rounds if max_rounds > 0 else max_rounds_limit
	while not finished and round_index < cap:
		advance_round()
		if finished or round_index % tape.record_stride == 0:
			_record_tape_frame(tape, pressure_stride, false)
	if tape.frame_count() > 0:
		var last: Dictionary = tape.get_frame(tape.frame_count() - 1)
		if int(last.get("round", -1)) != round_index:
			_record_tape_frame(tape, pressure_stride, true)
	tape.result = get_result()
	tape.resolve_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	tape.battle_data = battle_data
	tape.rebuild_segment_timing()
	if _profiler != null and _profiler.enabled:
		_profiler.log_resolve_summary(tape.resolve_ms, round_index, tape.frame_count())
	backend = saved_backend
	rust_field = saved_rust_field
	rust_live_ready = saved_rust_ready
	return tape


func allocation_losses(allocation: int, side_is_player: bool) -> int:
	if allocation <= 0 or claimable_tiles <= 0 or tile_control == null:
		return 0
	var owned: int = _tiles_owned_by_player() if side_is_player else _tiles_owned_by_enemy()
	var held_frac: float = clampf(float(owned) / float(claimable_tiles), 0.0, 1.0)
	if player_won and side_is_player:
		return int(float(allocation) * (1.0 - held_frac) * 0.12)
	if not player_won and side_is_player:
		return int(float(allocation) * (1.0 - held_frac) * 0.55)
	if player_won and not side_is_player:
		return int(float(allocation) * (1.0 - held_frac))
	return int(float(allocation) * (1.0 - held_frac) * 0.35)


func get_result() -> Dictionary:
	return {
		"player_won": player_won,
		"finished": finished,
		"turns": round_index,
		"sim_time": sim_time,
		"friendly_tiles": _tiles_owned_by_player(),
		"hostile_tiles": _tiles_owned_by_enemy(),
		"claimable_tiles": claimable_tiles,
		"resolve_mode": "territory",
		"territory_conquest": true,
		"end_reason": end_reason,
		"max_rounds_limit": max_rounds_limit,
	}


func get_seconds_per_cell() -> float:
	return BattlePacingLib.seconds_per_cell(battle_data)


static func _pressure_mods_from_galaxy(galaxy) -> Dictionary:
	var friendly_bonus: float = 0.0
	if galaxy == null:
		return {"friendly_pressure": 0.0, "hostile_pressure": 0.04}
	for node in galaxy.nodes:
		if str(node.get("owner", "")) != GalaxyMapStateLib.OWNER_PLAYER:
			continue
		for building_id in node.get("buildings", []):
			var def: Dictionary = BuildingDefinitionLib.lookup(str(building_id))
			friendly_bonus += float(def.get("pressure_bonus", 0.0))
			friendly_bonus += float(def.get("damage_bonus", 0.0)) * 1.5
	return {
		"friendly_pressure": clampf(friendly_bonus, 0.0, 0.85),
		"hostile_pressure": 0.04 + clampf(friendly_bonus * 0.08, 0.0, 0.12),
	}


func _check_conquest() -> void:
	if _resolve_context == "world_conquest":
		_check_conquest_world()
		return
	var friendly: int = _tiles_owned_by_player()
	var hostile: int = _tiles_owned_by_enemy()
	if claimable_tiles <= 0:
		finished = true
		player_won = friendly >= hostile
		end_reason = "cap"
		return
	if friendly >= claimable_tiles:
		finished = true
		player_won = true
		end_reason = "conquest"
		return
	if hostile >= claimable_tiles:
		finished = true
		player_won = false
		end_reason = "conquest"
		return

	var dom_frac: float = DOMINANCE_FRAC
	var leader: int = 0
	if float(friendly) >= float(claimable_tiles) * dom_frac:
		leader = 1
	elif float(hostile) >= float(claimable_tiles) * dom_frac:
		leader = 2
	if leader != 0 and leader == _dominance_leader:
		_dominance_streak += 1
	else:
		_dominance_leader = leader
		_dominance_streak = 1 if leader != 0 else 0
	if _dominance_streak >= DOMINANCE_ROUNDS:
		finished = true
		player_won = _dominance_leader == 1
		end_reason = "dominance"
		return

	var tile_delta: int = absi(friendly - _prev_friendly) + absi(hostile - _prev_hostile)
	if tile_delta <= STALL_TILE_DELTA:
		_stall_rounds += 1
	else:
		_stall_rounds = 0
	_prev_friendly = friendly
	_prev_hostile = hostile
	if _stall_rounds >= _stall_rounds_limit:
		finished = true
		player_won = friendly > hostile
		end_reason = "stall"
		return

	_check_decisive_lead(friendly, hostile)
	if finished:
		return

	if round_index >= max_rounds_limit:
		finished = true
		player_won = friendly > hostile
		end_reason = "cap"


func _record_tape_frame(tape: BattleTerritoryTapeLib, pressure_stride: int, force_pressure: bool) -> void:
	if tile_control == null:
		return
	var t0: int = _profiler.begin_phase("record_frame") if _profiler != null and _profiler.enabled else 0
	var record_pressure: bool = force_pressure or round_index % pressure_stride == 0
	var pf: PackedFloat32Array = PackedFloat32Array()
	var ph: PackedFloat32Array = PackedFloat32Array()
	if record_pressure:
		pf = tile_control.pressure_friendly
		ph = tile_control.pressure_hostile
	tape.record_frame(
		round_index,
		tile_control.owners,
		pf,
		ph,
		tile_control.friendly_tiles,
		tile_control.hostile_tiles,
	)
	if _profiler != null and _profiler.enabled and t0 > 0:
		_profiler.end_phase("record_frame", t0)


func _count_claimable() -> int:
	if tile_control == null:
		return 0
	var n: int = 0
	for idx in range(tile_control.owners.size()):
		if tile_control._is_claimable_index(idx):
			n += 1
	return n


func _tiles_owned_by_player() -> int:
	if tile_control != null:
		return tile_control.friendly_tiles
	return 0


func _tiles_owned_by_enemy() -> int:
	if tile_control != null:
		return tile_control.hostile_tiles
	return 0


func _estimate_max_rounds() -> int:
	if battle_data == null:
		return MAX_ROUNDS_DEFAULT
	var span: int = maxi(48, battle_data.grid_width + battle_data.grid_height)
	return mini(MAX_ROUNDS_DEFAULT, span * 50 + 640)


func _check_conquest_world() -> void:
	var friendly: int = _tiles_owned_by_player()
	var hostile: int = _tiles_owned_by_enemy()
	if claimable_tiles <= 0:
		finished = true
		player_won = friendly >= hostile
		end_reason = "cap"
		return
	if friendly >= claimable_tiles:
		finished = true
		player_won = true
		end_reason = "conquest"
		return
	if hostile >= claimable_tiles:
		finished = true
		player_won = false
		end_reason = "conquest"
		return
	if battle_data != null and tile_control != null:
		var pc: Vector2i = battle_data.player_capital_grid
		var ec: Vector2i = battle_data.enemy_capital_grid
		if pc.x >= 0 and _owner_at(pc.x, pc.y) == BattleTileControlLib.OWNER_HOSTILE:
			finished = true
			player_won = false
			end_reason = "capital"
			return
		if ec.x >= 0 and _owner_at(ec.x, ec.y) == BattleTileControlLib.OWNER_FRIENDLY:
			finished = true
			player_won = true
			end_reason = "capital"
			return
	var dom_frac: float = WorldConquestConfigLib.CONQUEST_LAND_FRAC
	var leader: int = 0
	if float(friendly) >= float(claimable_tiles) * dom_frac:
		leader = 1
	elif float(hostile) >= float(claimable_tiles) * dom_frac:
		leader = 2
	if leader != 0 and leader == _dominance_leader:
		_dominance_hold_sec += step_dt
	else:
		_dominance_leader = leader
		_dominance_hold_sec = step_dt if leader != 0 else 0.0
	if _dominance_hold_sec >= WorldConquestConfigLib.DOMINANCE_HOLD_SEC:
		finished = true
		player_won = _dominance_leader == 1
		end_reason = "dominance"
		return
	var tile_delta: int = absi(friendly - _prev_friendly) + absi(hostile - _prev_hostile)
	if tile_delta <= STALL_TILE_DELTA:
		_stall_sec += step_dt
	else:
		_stall_sec = 0.0
	_prev_friendly = friendly
	_prev_hostile = hostile
	if _stall_sec >= WorldConquestConfigLib.STALL_SEC:
		finished = true
		player_won = friendly > hostile
		end_reason = "stall"
		return
	_check_decisive_lead_world(friendly, hostile)
	if finished:
		return
	if sim_time >= WorldConquestConfigLib.MAX_SIM_TIME_SEC:
		finished = true
		player_won = friendly > hostile
		end_reason = "cap"


func _owner_at(gx: int, gy: int) -> int:
	if tile_control == null or battle_data == null:
		return BattleTileControlLib.OWNER_NEUTRAL
	if gx < 0 or gy < 0 or gx >= battle_data.grid_width or gy >= battle_data.grid_height:
		return BattleTileControlLib.OWNER_NEUTRAL
	return int(tile_control.owners[battle_data.cell_index(gx, gy)])


func _check_decisive_lead_world(friendly: int, hostile: int) -> void:
	if claimable_tiles <= 0 or player_force <= 0 or enemy_force <= 0:
		return
	var force_ratio: float = float(player_force) / float(maxi(1, enemy_force))
	var inv_ratio: float = float(enemy_force) / float(maxi(1, player_force))
	var leader: int = 0
	if (
		float(friendly) >= float(claimable_tiles) * DECISIVE_TILE_FRAC
		and force_ratio >= DECISIVE_FORCE_RATIO
	):
		leader = 1
	elif (
		float(hostile) >= float(claimable_tiles) * DECISIVE_TILE_FRAC
		and inv_ratio >= DECISIVE_FORCE_RATIO
	):
		leader = 2
	if leader != 0 and leader == _decisive_leader:
		_decisive_hold_sec += step_dt
	else:
		_decisive_leader = leader
		_decisive_hold_sec = step_dt if leader != 0 else 0.0
	if _decisive_hold_sec >= WorldConquestConfigLib.DECISIVE_HOLD_SEC:
		finished = true
		player_won = _decisive_leader == 1
		end_reason = "decisive"


func _check_decisive_lead(friendly: int, hostile: int) -> void:
	if claimable_tiles <= 0 or player_force <= 0 or enemy_force <= 0:
		return
	var force_ratio: float = float(player_force) / float(maxi(1, enemy_force))
	var inv_ratio: float = float(enemy_force) / float(maxi(1, player_force))
	var leader: int = 0
	if (
		float(friendly) >= float(claimable_tiles) * DECISIVE_TILE_FRAC
		and force_ratio >= DECISIVE_FORCE_RATIO
	):
		leader = 1
	elif (
		float(hostile) >= float(claimable_tiles) * DECISIVE_TILE_FRAC
		and inv_ratio >= DECISIVE_FORCE_RATIO
	):
		leader = 2
	if leader != 0 and leader == _decisive_leader:
		_decisive_streak += 1
	else:
		_decisive_leader = leader
		_decisive_streak = 1 if leader != 0 else 0
	if _decisive_streak >= DECISIVE_HOLD_ROUNDS:
		finished = true
		player_won = _decisive_leader == 1
		end_reason = "decisive"
