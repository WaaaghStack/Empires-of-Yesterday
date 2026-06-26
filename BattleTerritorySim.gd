class_name BattleTerritorySim
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryGpuFieldLib := preload("res://BattleTerritoryGpuField.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattlePerfProfilerLib := preload("res://BattlePerfProfiler.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestOutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
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

## Full-map pressure sums are expensive in GDScript; refresh at most once per ~sim-second.
const POWER_TOTALS_REFRESH_ROUNDS := 14

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
var _power_totals: Vector2 = Vector2.ZERO
var _power_totals_round: int = -0x7FFFFFFF
## Aurelium upkeep deficit → soldier DPS (x=friendly, y=hostile), set by WorldConquestScreen.
var agent_deficit_dps: Vector2 = Vector2.ZERO


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
	_power_totals = Vector2.ZERO
	_power_totals_round = -0x7FFFFFFF
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
	if _resolve_context == "world_conquest":
		backend = BACKEND_CPU if not rust_live_ready else BACKEND_RUST
		gpu_live_ready = false
		gpu_field = null
		return false
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
		var live_claimable: int = claimable_tile_count_live()
		if live_claimable > 0:
			claimable_tiles = live_claimable
		if _resolve_context == "world_conquest":
			_configure_world_agents()
		refresh_world_dataset_mirror_mode()
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
			_stall_rounds_limit = max_rounds_limit
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
	rust_field.step_rounds(tile_control, count, agent_deficit_dps.x, agent_deficit_dps.y)
	round_index += count
	# Rust syncs state once per batch — re-checking per round would see identical arrays.
	_check_conquest()
	return count


func agents_ready() -> bool:
	return rust_field != null and rust_field.agents_active()


func grid_authority_active() -> bool:
	return (
		use_rust_for_live()
		and rust_field != null
		and rust_field.grid_authority_enabled()
	)


func structure_authority_active() -> bool:
	return (
		use_rust_for_live()
		and rust_field != null
		and rust_field.structure_authority_enabled()
	)


func pull_structure_render_cache(merge_by_sid: Dictionary = {}) -> bool:
	if battle_data == null or rust_field == null:
		return false
	return rust_field.pull_structure_cache_to_map(battle_data, merge_by_sid)


func owner_at_index(idx: int) -> int:
	if grid_authority_active():
		return rust_field.owner_at_index(idx)
	if tile_control != null and idx >= 0 and idx < tile_control.owners.size():
		return int(tile_control.owners[idx])
	return BattleTileControlLib.OWNER_NEUTRAL


func claimable_at_index(idx: int) -> bool:
	if grid_authority_active():
		return rust_field.claimable_at_index(idx)
	if tile_control != null and idx >= 0 and idx < tile_control.claimable_mask.size():
		return tile_control.claimable_mask[idx] != 0
	return false


func claimable_tile_count_live() -> int:
	if grid_authority_active():
		var rust_n: int = rust_field.get_claimable_tile_count()
		if rust_n > 0:
			return rust_n
		if tile_control != null and tile_control.claimable_tile_count > 0:
			return tile_control.claimable_tile_count
		if claimable_tiles > 0:
			return claimable_tiles
		return maxi(rust_n, 0)
	if tile_control != null:
		return tile_control.claimable_tile_count
	return claimable_tiles


func claim_ratio_mult_at(idx: int) -> float:
	if grid_authority_active():
		return rust_field.claim_ratio_mult_at(idx)
	if tile_control != null and idx >= 0 and idx < tile_control._claim_ratio_mult.size():
		return tile_control._claim_ratio_mult[idx]
	return 1.0


func pressure_friendly_at(idx: int) -> float:
	if use_rust_for_live() and rust_field != null and rust_field.ready:
		var layers: PackedFloat32Array = rust_field.get_pressure_friendly()
		if idx >= 0 and idx < layers.size():
			return layers[idx]
	if tile_control != null and idx >= 0 and idx < tile_control.pressure_friendly.size():
		return tile_control.pressure_friendly[idx]
	return 0.0


func pressure_hostile_at(idx: int) -> float:
	if use_rust_for_live() and rust_field != null and rust_field.ready:
		var layers: PackedFloat32Array = rust_field.get_pressure_hostile()
		if idx >= 0 and idx < layers.size():
			return layers[idx]
	if tile_control != null and idx >= 0 and idx < tile_control.pressure_hostile.size():
		return tile_control.pressure_hostile[idx]
	return 0.0


func grid_cell_count() -> int:
	if battle_data != null:
		return battle_data.grid_width * battle_data.grid_height
	if tile_control != null:
		return tile_control.owners.size()
	return 0


func claim_tile(gx: int, gy: int, team: int) -> bool:
	if grid_authority_active():
		return rust_field.claim_tile_at(gx, gy, team)
	if tile_control != null:
		tile_control.claim_tile(gx, gy, team)
		return true
	return false


func query_tile(gx: int, gy: int) -> Dictionary:
	if grid_authority_active() and battle_data != null:
		var probe: Dictionary = rust_field.query_tile(gx, gy)
		if not bool(probe.get("valid", false)):
			return {"valid": false}
		var owner: int = int(probe.get("owner", BattleTileControlLib.OWNER_NEUTRAL))
		var owner_name: String = "unclaimable"
		match owner:
			BattleTileControlLib.OWNER_NEUTRAL:
				owner_name = "neutral"
			BattleTileControlLib.OWNER_FRIENDLY:
				owner_name = "friendly"
			BattleTileControlLib.OWNER_HOSTILE:
				owner_name = "hostile"
			BattleTileControlLib.OWNER_CONTESTED:
				owner_name = "contested"
		var terrain: String = "water"
		if battle_data.is_land_cell(gx, gy):
			terrain = BattleMapDataLib.TERRAIN_NAMES[
				clampi(
					int(battle_data.get_cell_terrain(gx, gy)),
					0,
					BattleMapDataLib.TERRAIN_NAMES.size() - 1,
				)
			]
		probe["terrain"] = terrain
		probe["owner_name"] = owner_name
		probe["owner"] = owner_name
		return probe
	if tile_control != null and battle_data != null:
		return tile_control.tile_probe(battle_data, gx, gy)
	return {"valid": false}


func count_claimable_bridge_cells() -> Dictionary:
	var water_claimable: int = 0
	var water_total: int = 0
	var landings: int = 0
	if battle_data == null:
		return {"water_claimable": 0, "water_total": 0, "landings": 0}
	for corridor in battle_data.bridge_corridors:
		if not corridor is Dictionary:
			continue
		landings += 1
		var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		for key in packed:
			var idx: int = int(key)
			if idx < 0 or idx >= grid_cell_count():
				continue
			var gx: int = idx % battle_data.grid_width
			var gy: int = idx / battle_data.grid_width
			if not WorldConquestOutpostBuildLib.is_water_cell(battle_data, gx, gy):
				continue
			water_total += 1
			if claimable_at_index(idx):
				water_claimable += 1
	return {
		"water_claimable": water_claimable,
		"water_total": water_total,
		"landings": landings,
	}


func sync_agent_nav() -> void:
	if rust_field != null and tile_control != null:
		rust_field.sync_agent_nav_from(tile_control)


func try_spawn_soldier(barracks_id: int, team: int, bx: int, by: int) -> bool:
	if rust_field == null:
		return false
	return rust_field.try_spawn_agent(barracks_id, team, bx, by)


func notify_barracks_destroyed(barracks_id: int) -> void:
	if rust_field != null:
		rust_field.notify_barracks_destroyed(barracks_id)


func agent_living_count() -> int:
	if rust_field == null:
		return 0
	return rust_field.agent_living_count()


func agent_living_for_barracks(barracks_id: int) -> int:
	if rust_field == null:
		return 0
	return rust_field.agent_living_for_barracks(barracks_id)


func get_agent_snapshot() -> Dictionary:
	if rust_field == null:
		return {}
	return rust_field.get_agent_snapshot()


func _configure_world_agents() -> void:
	if rust_field == null:
		return
	var cfg := WorldConquestConfigLib
	rust_field.configure_agents({
		"global_cap": cfg.GLOBAL_SOLDIER_CAP,
		"per_barracks_cap": cfg.BARRACKS_MAX_ACTIVE_UNITS,
		"max_hp": cfg.SOLDIER_MAX_HP,
		"move_cells_per_sec": cfg.SOLDIER_MOVE_CELLS_PER_SEC,
		"infra_move_mult": cfg.SOLDIER_INFRA_MOVE_MULT,
		"aura_pressure": cfg.SOLDIER_AURA_PRESSURE,
		"shoot_erode_per_sec": cfg.SOLDIER_SHOOT_ERODE_PER_SEC,
		"orphan_dps": cfg.SOLDIER_ORPHAN_DPS,
		"step_dt": cfg.SIM_DT,
		"replans_per_tick": cfg.SOLDIER_REPLANS_PER_TICK,
		"replan_fallback_rounds": cfg.SOLDIER_REPLAN_FALLBACK_ROUNDS,
	})
	sync_agent_nav()
	_configure_world_session()
	_configure_builders_and_wallet()


func configure_builders(player_home: Vector2i, enemy_home: Vector2i) -> void:
	if rust_field == null:
		return
	var cfg := WorldConquestConfigLib
	rust_field.configure_builders(
		{
			"road_cells_per_sec": cfg.OUTPOST_ROAD_CELLS_PER_SEC,
			"bots_per_home": cfg.BUILDER_BOTS_PER_HOME,
			"orbit_radius_cells": cfg.BUILDER_ORBIT_RADIUS_CELLS,
			"orbit_speed": cfg.BUILDER_ORBIT_SPEED,
			"return_sec": cfg.BUILDER_RETURN_SEC,
			"outpost_build_sec": cfg.OUTPOST_BUILD_SEC,
			"barracks_build_sec": cfg.BARRACKS_BUILD_SEC,
			"outpost_max_health": cfg.OUTPOST_MAX_HEALTH,
			"player_home_gx": player_home.x,
			"player_home_gy": player_home.y,
			"enemy_home_gx": enemy_home.x,
			"enemy_home_gy": enemy_home.y,
		},
		cfg.WORLD_DATASET_BUILDER_AUTHORITY and cfg.WORLD_DATASET_STRUCTURE_AUTHORITY,
	)


func builder_authority_active() -> bool:
	if rust_field == null or not WorldConquestConfigLib.WORLD_DATASET_BUILDER_AUTHORITY:
		return false
	return rust_field.builder_authority_enabled()


func builder_step(dt: float) -> Dictionary:
	if rust_field == null:
		return {}
	return rust_field.builder_step(dt)


func builder_enqueue_job(sid: int, team: int) -> void:
	if rust_field == null:
		return
	rust_field.builder_enqueue_job(sid, team)


func builder_cancel_job(sid: int) -> void:
	if rust_field == null:
		return
	rust_field.builder_cancel_job(sid)


func get_builder_visual_snapshot() -> Dictionary:
	if rust_field == null:
		return {}
	return rust_field.get_builder_visual_snapshot()


func resource_wallet_active() -> bool:
	if rust_field == null or not WorldConquestConfigLib.WORLD_DATASET_RESOURCE_WALLET:
		return false
	return rust_field.resource_wallet_enabled()


func world_dataset_live_active() -> bool:
	if not WorldConquestConfigLib.world_dataset_live():
		return false
	return (
		use_rust_for_live()
		and rust_field != null
		and rust_field.ready
		and grid_authority_active()
		and structure_authority_active()
		and world_session_active()
		and builder_authority_active()
		and resource_wallet_active()
	)


func refresh_world_dataset_mirror_mode() -> void:
	if tile_control == null:
		return
	tile_control.grid_mirror_frozen = (
		_resolve_context == "world_conquest"
		and WorldConquestConfigLib.world_dataset_live()
		and grid_authority_active()
	)


func sync_resource_balances(friendly: Array, hostile: Array) -> void:
	if rust_field == null:
		return
	rust_field.sync_resource_balances(friendly, hostile)


func apply_resource_tick_delta(friendly_delta: Array, hostile_delta: Array) -> void:
	if rust_field == null:
		return
	rust_field.apply_resource_tick_delta(friendly_delta, hostile_delta)


func pull_resource_balances() -> Dictionary:
	if rust_field == null:
		return {}
	return rust_field.get_resource_balances()


func _configure_builders_and_wallet() -> void:
	if rust_field == null:
		return
	var cfg := WorldConquestConfigLib
	rust_field.configure_resource_wallet(
		cfg.WORLD_DATASET_RESOURCE_WALLET and cfg.WORLD_DATASET_STRUCTURE_AUTHORITY,
	)


func world_session_active() -> bool:
	if rust_field == null or not WorldConquestConfigLib.WORLD_DATASET_WORLD_SESSION_TICK:
		return false
	return rust_field.world_session_enabled()


func tick_world_session(dt: float, friendly_aurelium: float) -> Dictionary:
	if rust_field == null:
		return {}
	return rust_field.world_session_tick(dt, friendly_aurelium)


func _configure_world_session() -> void:
	if rust_field == null:
		return
	var cfg := WorldConquestConfigLib
	rust_field.configure_world_session(
		{
			"outpost_build_sec": cfg.OUTPOST_BUILD_SEC,
			"barracks_build_sec": cfg.BARRACKS_BUILD_SEC,
			"outpost_max_health": cfg.OUTPOST_MAX_HEALTH,
			"outpost_enemy_dps": cfg.OUTPOST_ENEMY_DPS,
			"barracks_spawn_interval": cfg.BARRACKS_SPAWN_INTERVAL_SEC,
			"barracks_max_active": cfg.BARRACKS_MAX_ACTIVE_UNITS,
			"global_soldier_cap": cfg.GLOBAL_SOLDIER_CAP,
			"soldier_spawn_cost": cfg.SOLDIER_SPAWN_AURELIUM_COST,
		},
		cfg.WORLD_DATASET_WORLD_SESSION_TICK and cfg.WORLD_DATASET_STRUCTURE_AUTHORITY,
	)


func advance_round() -> void:
	if finished or battle_data == null or tile_control == null:
		return
	round_index += 1
	if backend == BACKEND_GPU and gpu_field != null and gpu_field.ready:
		gpu_field.step_round(tile_control)
		if gpu_field.readback_owners_if_due(round_index):
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


static func _pressure_mods_from_galaxy(_galaxy) -> Dictionary:
	return {"friendly_pressure": 0.0, "hostile_pressure": 0.04}


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
	if grid_authority_active() and rust_field != null:
		return rust_field.friendly_tiles
	if tile_control != null:
		return tile_control.friendly_tiles
	return 0


func _tiles_owned_by_enemy() -> int:
	if grid_authority_active() and rust_field != null:
		return rust_field.hostile_tiles
	if tile_control != null:
		return tile_control.hostile_tiles
	return 0


## Cached cumulative pressure totals (x friendly, y hostile); refreshed at most
## once per POWER_TOTALS_REFRESH_ROUNDS. Used by the HUD and the zero-power win check.
func power_totals() -> Vector2:
	if tile_control == null:
		return Vector2.ZERO
	if round_index - _power_totals_round >= POWER_TOTALS_REFRESH_ROUNDS:
		var layers: Dictionary = _live_pressure_arrays()
		_power_totals = BattleTileFluidFieldLib.cumulative_power_totals(
			layers.get("friendly", PackedFloat32Array()),
			layers.get("hostile", PackedFloat32Array()),
		)
		_power_totals_round = round_index
	return _power_totals


func _live_pressure_arrays() -> Dictionary:
	if use_rust_for_live() and rust_field != null and rust_field.ready:
		return {
			"friendly": rust_field.get_pressure_friendly(),
			"hostile": rust_field.get_pressure_hostile(),
		}
	if tile_control != null:
		return {
			"friendly": tile_control.pressure_friendly,
			"hostile": tile_control.pressure_hostile,
		}
	return {"friendly": PackedFloat32Array(), "hostile": PackedFloat32Array()}


func _hostile_power_total() -> float:
	return power_totals().y


func _estimate_max_rounds() -> int:
	if battle_data == null:
		return MAX_ROUNDS_DEFAULT
	var span: int = maxi(48, battle_data.grid_width + battle_data.grid_height)
	return mini(MAX_ROUNDS_DEFAULT, span * 50 + 640)


func _check_conquest_world() -> void:
	var friendly: int = _tiles_owned_by_player()
	var hostile: int = _tiles_owned_by_enemy()
	var live_claimable: int = claimable_tile_count_live()
	if live_claimable > 0:
		claimable_tiles = live_claimable
	if claimable_tiles <= 0:
		return
	var need: int = int(ceil(float(claimable_tiles) * WorldConquestConfigLib.CONQUEST_LAND_FRAC))
	if friendly >= need:
		finished = true
		player_won = true
		end_reason = "total_conquest"
		return
	if hostile >= need:
		finished = true
		player_won = false
		end_reason = "total_conquest"
		return
	if _hostile_power_total() <= WorldConquestConfigLib.ZERO_POWER_VICTORY_EPS:
		finished = true
		player_won = true
		end_reason = "enemy_zero_power"
		return
	if sim_time >= WorldConquestConfigLib.MAX_SIM_TIME_SEC:
		finished = true
		player_won = friendly > hostile
		end_reason = "time_cap"


func _owner_at(gx: int, gy: int) -> int:
	if tile_control == null or battle_data == null:
		return BattleTileControlLib.OWNER_NEUTRAL
	if gx < 0 or gy < 0 or gx >= battle_data.grid_width or gy >= battle_data.grid_height:
		return BattleTileControlLib.OWNER_NEUTRAL
	return int(tile_control.owners[battle_data.cell_index(gx, gy)])


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
