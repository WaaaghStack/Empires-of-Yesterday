class_name BattleMovementEngine
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")
const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")
const BattleSimTierPolicyLib := preload("res://BattleSimTierPolicy.gd")
const BattleScriptLib := preload("res://BattleScript.gd")

var battle_data = null
var _rng := RandomNumberGenerator.new()
var _last_paths: Dictionary = {}


func setup(map_data, seed_value: int = 0) -> void:
	battle_data = map_data
	_rng.seed = seed_value if seed_value != 0 else 1
	_last_paths.clear()


func plan_tactical_steps(store: UnitSimulationStoreLib, squads: Array, cell_grid: BattleCellGridLib, directives: Dictionary = {}) -> int:
	if store == null or battle_data == null:
		return 1
	var move_mult: float = float(directives.get("move_mult", 1.0))
	var max_steps := 1
	for squad in squads:
		if squad.target_gx < 0 or squad.target_gy < 0:
			if squad.order == BattleOrderTypesLib.SquadOrder.ADVANCE_CONTACT:
				squad.target_gx = battle_data.contact_column
				squad.target_gy = int(battle_data.grid_height * 0.5)
			else:
				continue
		for idx in squad.unit_indices:
			if not store.is_alive(idx):
				continue
			var def = BattleUnitCatalogLib.get_by_archetype(store.archetype[idx])
			var steps: int = maxi(1, int(roundf(float(def.move_cells_per_turn) * move_mult)))
			max_steps = maxi(max_steps, steps)
	return max_steps


func apply_tactical_moves(
	store: UnitSimulationStoreLib,
	squads: Array,
	cell_grid: BattleCellGridLib,
	step_count: int,
	data_table = null,
	sim_only_interval: int = 1,
	round_counter: int = 1,
) -> void:
	_last_paths.clear()
	if store == null or battle_data == null or step_count <= 0:
		return
	var move_sim_only: bool = sim_only_interval <= 1 or (round_counter % sim_only_interval) == 0
	for squad in squads:
		if squad.target_gx < 0:
			continue
		for idx in squad.unit_indices:
			if not store.is_alive(idx):
				continue
			var is_sim: bool = store.tier[idx] == UnitSimulationStoreLib.Tier.SIM_ONLY
			if is_sim and not move_sim_only:
				continue
			var steps_to_run: int = 1 if is_sim else step_count
			var from_pos: Vector2 = store.positions[idx]
			var tgt: Vector2i = BattleScriptLib.nearest_enemy_for_unit(store, idx)
			if tgt.x < 0:
				tgt = Vector2i(squad.target_gx, squad.target_gy)
			for _s in range(steps_to_run):
				if not store.try_step_toward(idx, tgt.x, tgt.y, battle_data, cell_grid):
					break
				# Retarget as lines shift so flank units keep feeding the main fight.
				var refreshed: Vector2i = BattleScriptLib.nearest_enemy_for_unit(store, idx)
				if refreshed.x >= 0:
					tgt = refreshed
			if store.positions[idx].distance_squared_to(from_pos) > 4.0:
				_last_paths[idx] = [store.positions[idx]]
				if data_table != null:
					data_table.mark_moved(idx)


func plan_turn_paths(store: UnitSimulationStoreLib) -> Dictionary:
	return _last_paths.duplicate()


func apply_paths_to_grid(store: UnitSimulationStoreLib, paths: Dictionary) -> void:
	pass
