class_name BattleSimTierPolicy
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")

const SIDE_FRIENDLY := UnitSimulationStoreLib.Side.FRIENDLY
const SIDE_HOSTILE := UnitSimulationStoreLib.Side.HOSTILE


static func apply_round_tiers(
	store: UnitSimulationStoreLib,
	cell_grid: BattleCellGridLib,
	commanders: Array,
	contact_radius: int,
	visible_cap_per_side: int,
	contact_column: int = -1,
) -> bool:
	if store == null or cell_grid == null:
		return false
	var changed_visibility := false
	var contact_cells: Array = cell_grid.get_contested_cells()
	var front_friendly := 0
	var front_hostile := 0
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if store.is_commander_unit[i] != 0:
			if store.tier[i] != UnitSimulationStoreLib.Tier.FULL:
				store.set_tier(i, UnitSimulationStoreLib.Tier.FULL)
				changed_visibility = true
			continue
		var near: bool = _is_near_contact(store, i, contact_cells, contact_radius, contact_column)
		var desired: int
		if near:
			desired = UnitSimulationStoreLib.Tier.LITE
			if store.side[i] == SIDE_FRIENDLY:
				front_friendly += 1
			else:
				front_hostile += 1
		else:
			desired = UnitSimulationStoreLib.Tier.SIM_ONLY
		if store.tier[i] != desired:
			store.set_tier(i, desired)
			changed_visibility = true
	_enforce_visible_cap(store, SIDE_FRIENDLY, visible_cap_per_side, contact_cells, contact_radius)
	_enforce_visible_cap(store, SIDE_HOSTILE, visible_cap_per_side, contact_cells, contact_radius)
	return changed_visibility


static func spawn_tier_for_slot(slot: int, total: int, contact_column: int, spawn_gx: int) -> int:
	var front_band: int = maxi(8, total / 10)
	if slot < front_band:
		return UnitSimulationStoreLib.Tier.LITE
	var dist_from_spawn: int = absi(spawn_gx - contact_column)
	if dist_from_spawn <= 12:
		return UnitSimulationStoreLib.Tier.LITE
	return UnitSimulationStoreLib.Tier.SIM_ONLY


static func can_participate_in_combat(store, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= store.count:
		return false
	if not store.is_alive(unit_idx):
		return false
	return store.tier[unit_idx] != UnitSimulationStoreLib.Tier.SIM_ONLY


static func _is_near_contact(store, unit_idx: int, contact_cells: Array, radius: int, contact_column: int = -1) -> bool:
	if contact_cells.is_empty() and contact_column >= 0:
		return absi(store.grid_x[unit_idx] - contact_column) <= radius + 8
	if contact_cells.is_empty():
		return false
	var ux: int = store.grid_x[unit_idx]
	var uy: int = store.grid_y[unit_idx]
	for cell in contact_cells:
		var cx: int = cell.x
		var cy: int = cell.y
		if absi(ux - cx) + absi(uy - cy) <= radius:
			return true
	return false


static func _enforce_visible_cap(
	store,
	side: int,
	cap: int,
	contact_cells: Array,
	contact_radius: int,
) -> void:
	var lite_indices: Array = []
	for i in range(store.count):
		if not store.is_alive(i) or store.side[i] != side:
			continue
		if store.tier[i] == UnitSimulationStoreLib.Tier.LITE:
			lite_indices.append(i)
	if lite_indices.size() <= cap:
		return
	lite_indices.sort_custom(func(a, b):
		var da: int = _dist_to_nearest_contact(store, int(a), contact_cells)
		var db: int = _dist_to_nearest_contact(store, int(b), contact_cells)
		return da < db
	)
	for j in range(cap, lite_indices.size()):
		store.set_tier(int(lite_indices[j]), UnitSimulationStoreLib.Tier.SIM_ONLY)


static func _dist_to_nearest_contact(store, unit_idx: int, contact_cells: Array) -> int:
	if contact_cells.is_empty():
		return 9999
	var best: int = 9999
	var ux: int = store.grid_x[unit_idx]
	var uy: int = store.grid_y[unit_idx]
	for cell in contact_cells:
		best = mini(best, absi(ux - cell.x) + absi(uy - cell.y))
	return best
