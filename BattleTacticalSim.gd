class_name BattleTacticalSim
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")
const BattleArmyBuilderLib := preload("res://BattleArmyBuilder.gd")
const BattleMovementEngineLib := preload("res://BattleMovementEngine.gd")
const BattleCombatResolverLib := preload("res://BattleCombatResolver.gd")
const BattleMoraleSystemLib := preload("res://BattleMoraleSystem.gd")
const BattleMagicResolverLib := preload("res://BattleMagicResolver.gd")
const BattleScriptLib := preload("res://BattleScript.gd")
const BattleDirectivesLib := preload("res://BattleDirectives.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")
const BattleEnemyDoctrineLib := preload("res://BattleEnemyDoctrine.gd")
const BattleMagicBudgetLib := preload("res://BattleMagicBudget.gd")
const BattleDataTableLib := preload("res://BattleDataTable.gd")
const BattlePerfProfilerLib := preload("res://BattlePerfProfiler.gd")
const BattleSimTierPolicyLib := preload("res://BattleSimTierPolicy.gd")
const BattleScaleProfileLib := preload("res://BattleScaleProfile.gd")
const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleUnitAnalysisLib := preload("res://BattleUnitAnalysis.gd")
const BattleArmyScaleLib := preload("res://BattleArmyScale.gd")

const TURN_SECONDS_DEFAULT := 2.4
const MAX_ROUNDS_DEFAULT := 120

var battle_data = null
var store: UnitSimulationStoreLib
var cell_grid: BattleCellGridLib
var data_table: BattleDataTableLib
var movement: BattleMovementEngineLib
var combat: BattleCombatResolverLib
var morale_sys: BattleMoraleSystemLib
var magic: BattleMagicResolverLib
var scripts: BattleScriptLib
var directives: BattleDirectivesLib
var profiler: BattlePerfProfilerLib
var squads: Array = []
var commanders: Array = []
var round_index: int = 0
var finished: bool = false
var player_won: bool = false
var player_start: int = 0
var enemy_start: int = 0
var player_spawned: int = 0
var enemy_spawned: int = 0
var pacing: Dictionary = {}
var scale_profile: Dictionary = {}
var turn_seconds: float = TURN_SECONDS_DEFAULT
var max_rounds_limit: int = MAX_ROUNDS_DEFAULT
var tier_visibility_dirty: bool = false
## Dominions-style: only melee when units meet on adjacent tiles (no ranged/magic volleys).
var contact_only_combat: bool = false
## Record every spawned unit on the tape/SQL (no SIM_ONLY hiding during resolve).
var record_all_units_visible: bool = false
## Run until one side has zero living units (no rout victory, no round time-stop).
var fight_to_annihilation: bool = true
var _rng := RandomNumberGenerator.new()
var _sim_only_move_counter: int = 0
var tile_control: BattleTileControlLib


func setup(
	map_data,
	player_count: int,
	enemy_count: int,
	battle_directives = null,
	commander_profile: Dictionary = {},
) -> void:
	battle_data = map_data
	player_start = maxi(1, player_count)
	enemy_start = maxi(1, enemy_count)
	store = UnitSimulationStoreLib.new()
	cell_grid = BattleCellGridLib.new()
	data_table = BattleDataTableLib.new()
	movement = BattleMovementEngineLib.new()
	combat = BattleCombatResolverLib.new()
	morale_sys = BattleMoraleSystemLib.new()
	magic = BattleMagicResolverLib.new()
	scripts = BattleScriptLib.new()
	profiler = BattlePerfProfilerLib.new()
	if battle_directives != null:
		directives = battle_directives
	else:
		directives = BattleDirectivesLib.new()
	var seed_val: int = map_data.map_seed if map_data else 1
	_rng.seed = seed_val
	combat.setup(seed_val)
	magic.setup(seed_val)
	movement.setup(map_data, seed_val)
	cell_grid.setup(map_data)
	var built: Dictionary = BattleArmyBuilderLib.build_army(
		store, map_data, player_count, enemy_count, _rng, cell_grid
	)
	squads = built.get("squads", [])
	commanders = built.get("commanders", [])
	player_spawned = int(built.get("player_spawned", player_count))
	enemy_spawned = int(built.get("enemy_spawned", enemy_count))
	cell_grid.rebuild_from_store(store)
	data_table.bind(store, cell_grid)
	scale_profile = data_table.scale
	BattleMagicBudgetLib.attach_to_commanders(commanders, commander_profile)
	BattleEnemyDoctrineLib.apply_default_scripts(scripts, squads, commanders)
	scripts.apply_to_squads(squads)
	scripts.apply_to_commanders(commanders)
	var avg_dist: float = BattlePacingLib.estimate_avg_spawn_to_contact(map_data)
	pacing = BattlePacingLib.compute(map_data, player_count, enemy_count, 0, avg_dist)
	turn_seconds = float(pacing.get("sim_round_seconds", pacing.get("turn_seconds", TURN_SECONDS_DEFAULT)))
	if fight_to_annihilation:
		max_rounds_limit = BattlePacingLib.annihilation_max_rounds(map_data)
	else:
		max_rounds_limit = int(pacing.get("max_turns", MAX_ROUNDS_DEFAULT))
	round_index = 0
	finished = false
	player_won = false
	_sim_only_move_counter = 0
	tier_visibility_dirty = true
	tile_control = BattleTileControlLib.new()
	if tile_control != null:
		tile_control.reset_for_battle(map_data, store, cell_grid)


func get_turn_seconds() -> float:
	return turn_seconds


func get_seconds_per_cell() -> float:
	return float(pacing.get("seconds_per_cell", turn_seconds))


func get_dead_this_round() -> Array:
	return data_table.dead_this_round if data_table else []


func advance_round() -> Dictionary:
	if finished or battle_data == null or store == null:
		return _make_snapshot()
	round_index += 1
	profiler.begin_round()
	data_table.begin_round()
	var t0: int = profiler.begin_phase("tiers")
	var contact_col: int = battle_data.contact_column if battle_data else -1
	if record_all_units_visible:
		for i in range(store.count):
			if store.is_alive(i) and store.tier[i] == UnitSimulationStoreLib.Tier.SIM_ONLY:
				store.set_tier(i, UnitSimulationStoreLib.Tier.LITE)
		tier_visibility_dirty = false
	else:
		tier_visibility_dirty = BattleSimTierPolicyLib.apply_round_tiers(
			store,
			cell_grid,
			commanders,
			int(scale_profile.get("tier_contact_radius", 6)),
			int(scale_profile.get("visible_lite_cap_per_side", 2200)),
			contact_col,
		)
	profiler.end_phase("tiers", t0)
	t0 = profiler.begin_phase("orders")
	var dir_mod: Dictionary = directives.get_turn_modifiers() if directives else {}
	var morale_buff: int = int(dir_mod.get("morale_buff", 0))
	if morale_buff > 0:
		for i in range(store.count):
			if store.is_alive(i) and store.side[i] == UnitSimulationStoreLib.Side.FRIENDLY:
				store.morale[i] = mini(30, store.morale[i] + morale_buff)
	scripts.resolve_squad_targets(store, squads, battle_data)
	profiler.end_phase("orders", t0)
	t0 = profiler.begin_phase("movement")
	var move_interval: int = (
		1 if record_all_units_visible else int(scale_profile.get("sim_only_move_interval", 1))
	)
	_sim_only_move_counter += 1
	var steps: int = movement.plan_tactical_steps(store, squads, cell_grid, dir_mod)
	movement.apply_tactical_moves(
		store, squads, cell_grid, steps, data_table, move_interval, _sim_only_move_counter
	)
	profiler.end_phase("movement", t0)
	t0 = profiler.begin_phase("melee")
	var pairs: Array = cell_grid.build_melee_adjacency_pairs()
	combat.run_melee_phase(
		store,
		cell_grid,
		pairs,
		data_table.max_melee_swings(),
		data_table.fighters_per_edge(),
	)
	profiler.end_phase("melee", t0)
	if not contact_only_combat:
		t0 = profiler.begin_phase("ranged")
		if data_table.needs_archer_rebuild():
			data_table.rebuild_archer_index()
		combat.run_ranged_phase(
			store,
			cell_grid,
			data_table.archer_indices_friendly,
			data_table.archer_indices_hostile,
			data_table.max_ranged_shots(),
		)
		profiler.end_phase("ranged", t0)
		t0 = profiler.begin_phase("magic")
		magic.resolve_commander_round(store, cell_grid, commanders, squads)
		profiler.end_phase("magic", t0)
	t0 = profiler.begin_phase("morale")
	morale_sys.apply_casualty_morale(store, squads, data_table.dead_this_round)
	morale_sys.tick_squad_morale(store, squads, battle_data)
	profiler.end_phase("morale", t0)
	t0 = profiler.begin_phase("cleanup")
	data_table.remove_dead_from_grid()
	profiler.end_phase("cleanup", t0)
	profiler.log_round(round_index)
	_check_victory()
	return _make_snapshot()


func run_to_completion(max_rounds: int = -1) -> Dictionary:
	var cap: int = max_rounds if max_rounds > 0 else max_rounds_limit
	while not finished and round_index < cap:
		advance_round()
	return get_result()


## Resolve entire battle upfront for replay playback (Dominions-style: sim once, watch many times).
func build_replay_tape(max_rounds: int = -1, record_stride: int = 1) -> BattleReplayTapeLib:
	var tape := BattleReplayTapeLib.new()
	tape.round_duration = turn_seconds
	tape.record_stride = maxi(1, record_stride)
	if store == null:
		return tape
	var t0: int = Time.get_ticks_usec()
	tape.record_frame(store, round_index, _record_tile_owners())
	var cap: int = max_rounds if max_rounds > 0 else max_rounds_limit
	while not finished and round_index < cap:
		advance_round()
		if finished or fight_to_annihilation or round_index % tape.record_stride == 0:
			tape.record_frame(store, round_index, _record_tile_owners())
	if tape.frame_count() > 0:
		var last_frame: Dictionary = tape.get_frame(tape.frame_count() - 1)
		if int(last_frame.get("round", -1)) != round_index:
			tape.record_frame(store, round_index, _record_tile_owners())
	tape.result = get_result()
	tape.resolve_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	tape.battle_data = battle_data
	tape.rebuild_segment_timing()
	return tape


func allocation_losses(allocation: int, side: int) -> int:
	if store == null or allocation <= 0:
		return 0
	var spawned: int = player_spawned if side == UnitSimulationStoreLib.Side.FRIENDLY else enemy_spawned
	spawned = maxi(1, spawned)
	var living: int = (
		store.living_friendly_count()
		if side == UnitSimulationStoreLib.Side.FRIENDLY
		else store.living_hostile_count()
	)
	return BattleArmyScaleLib.allocation_losses(allocation, float(living) / float(spawned))


func get_result() -> Dictionary:
	var enemy_rout_frac: float = (
		morale_sys.army_rout_fraction(store, UnitSimulationStoreLib.Side.HOSTILE, enemy_start)
		if morale_sys and store
		else 0.0
	)
	return {
		"player_won": player_won,
		"finished": finished,
		"turns": round_index,
		"friendly_remaining": store.living_friendly_count() if store else 0,
		"hostile_remaining": store.living_hostile_count() if store else 0,
		"resolve_mode": "tactical",
		"enemy_rout": enemy_rout_frac >= BattleMoraleSystemLib.ROUT_CASUALTY_FRAC,
		"player_rout_frac": morale_sys.army_rout_fraction(store, UnitSimulationStoreLib.Side.FRIENDLY, player_start) if morale_sys and store else 0.0,
		"enemy_rout_frac": enemy_rout_frac,
	}


func get_contact_focus() -> Vector2:
	var best: Vector2i = cell_grid.get_contact_focus_cell()
	if best.x >= 0:
		return battle_data.cell_center(best.x, best.y)
	return battle_data.map_size * 0.5


func _check_victory() -> void:
	if store.living_hostile_count() <= 0:
		finished = true
		player_won = true
		return
	if store.living_friendly_count() <= 0:
		finished = true
		player_won = false
		return
	if fight_to_annihilation:
		if round_index >= max_rounds_limit:
			finished = true
			player_won = store.living_friendly_count() >= store.living_hostile_count()
		return
	if morale_sys.is_army_routed(store, commanders, UnitSimulationStoreLib.Side.HOSTILE, enemy_start):
		finished = true
		player_won = true
		return
	if morale_sys.is_army_routed(store, commanders, UnitSimulationStoreLib.Side.FRIENDLY, player_start):
		finished = true
		player_won = false
		return
	if round_index >= max_rounds_limit:
		finished = true
		player_won = store.living_friendly_count() > store.living_hostile_count()


func _make_snapshot() -> Dictionary:
	return {
		"turn": round_index,
		"friendly_living": store.living_friendly_count() if store else 0,
		"hostile_living": store.living_hostile_count() if store else 0,
		"dead_units": data_table.dead_this_round.duplicate() if data_table else [],
		"finished": finished,
		"player_won": player_won,
		"enemy_rout": morale_sys.army_rout_fraction(store, UnitSimulationStoreLib.Side.HOSTILE, enemy_start) if morale_sys else 0.0,
		"player_rout": morale_sys.army_rout_fraction(store, UnitSimulationStoreLib.Side.FRIENDLY, player_start) if morale_sys else 0.0,
		"tier_visibility_dirty": tier_visibility_dirty,
	}


func _record_tile_owners() -> PackedByteArray:
	if tile_control == null or battle_data == null:
		return PackedByteArray()
	var raw: PackedByteArray = tile_control.compute_frame(battle_data, store, cell_grid)
	return BattleTileFluidFieldLib.soften_owners_for_display(battle_data, raw)
