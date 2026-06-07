class_name BattleDataTable
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")
const BattleScaleProfileLib := preload("res://BattleScaleProfile.gd")

var store: UnitSimulationStoreLib
var cell_grid: BattleCellGridLib
var scale: Dictionary = {}
var dead_this_round: Array = []
var dirty_transforms: Array = []
var archer_indices_friendly: PackedInt32Array = PackedInt32Array()
var archer_indices_hostile: PackedInt32Array = PackedInt32Array()
var tier_visibility_dirty: bool = false
var _round_serial: int = 0


func bind(store_ref: UnitSimulationStoreLib, grid_ref: BattleCellGridLib) -> void:
	store = store_ref
	cell_grid = grid_ref
	if store != null:
		store.on_unit_killed = _on_unit_killed
	scale = BattleScaleProfileLib.for_unit_count(store.count)


func begin_round() -> void:
	_round_serial += 1
	dead_this_round.clear()
	dirty_transforms.clear()
	if store != null:
		store.clear_dirty_transforms()


func needs_archer_rebuild() -> bool:
	if store == null:
		return true
	var interval: int = 1
	if store.count >= 2000:
		interval = 3
	elif store.count >= 800:
		interval = 2
	return _round_serial % interval == 0


func rebuild_archer_index() -> void:
	archer_indices_friendly = PackedInt32Array()
	archer_indices_hostile = PackedInt32Array()
	if store == null:
		return
	for i in range(store.count):
		if not store.is_alive(i) or store.ranged[i] == 0:
			continue
		if store.tier[i] == UnitSimulationStoreLib.Tier.SIM_ONLY:
			continue
		if store.side[i] == UnitSimulationStoreLib.Side.FRIENDLY:
			archer_indices_friendly.append(i)
		else:
			archer_indices_hostile.append(i)


func mark_moved(unit_idx: int) -> void:
	if store == null:
		return
	store.mark_dirty_transform(unit_idx)
	dirty_transforms.append(unit_idx)


func remove_dead_from_grid() -> void:
	# Grid removal happens in _on_unit_killed when units die.
	pass


func max_melee_swings() -> int:
	return int(scale.get("max_melee_swings", 256))


func max_ranged_shots() -> int:
	return int(scale.get("max_ranged_shots", 120))


func fighters_per_edge() -> int:
	return int(scale.get("fighters_per_edge", 4))


func _on_unit_killed(unit_idx: int) -> void:
	dead_this_round.append(unit_idx)
	if store != null and unit_idx >= 0 and unit_idx < store.count:
		if unit_idx < store.death_round.size():
			store.death_round[unit_idx] = _round_serial
	if cell_grid != null and store != null and unit_idx >= 0 and unit_idx < store.count:
		cell_grid.remove_unit(
			unit_idx,
			store.grid_x[unit_idx],
			store.grid_y[unit_idx],
			store.size[unit_idx],
			store.side[unit_idx],
		)
