class_name BattleScript
extends RefCounted

const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

## Squads advance on separate vertical sectors so the army uses the full map width.
const CONTACT_SECTOR_COUNT := 7
const SECTOR_MARGIN_CELLS := 4

var squad_orders: Dictionary = {}
var commander_queues: Dictionary = {}


func set_squad_order(squad_id: int, order: int) -> void:
	squad_orders[squad_id] = order


func set_commander_queue(commander_id: int, steps: Array) -> void:
	var q: Array = []
	for i in range(mini(steps.size(), BattleOrderTypesLib.COMMANDER_QUEUE_LEN)):
		q.append(int(steps[i]))
	while q.size() < BattleOrderTypesLib.COMMANDER_QUEUE_LEN:
		q.append(BattleOrderTypesLib.CommanderStep.WAIT)
	commander_queues[commander_id] = q


func apply_to_squads(squads: Array) -> void:
	for squad in squads:
		if squad_orders.has(squad.id):
			squad.order = int(squad_orders[squad.id])


func apply_to_commanders(commanders: Array) -> void:
	for cmd in commanders:
		if commander_queues.has(cmd.id):
			cmd.order_queue = commander_queues[cmd.id].duplicate()


func resolve_squad_targets(store, squads: Array, battle_data) -> void:
	for squad in squads:
		if squad.hold_rounds > 0:
			squad.hold_rounds -= 1
			continue
		match squad.order:
			BattleOrderTypesLib.SquadOrder.HOLD_POSITION:
				squad.target_gx = -1
				squad.target_gy = -1
			BattleOrderTypesLib.SquadOrder.ATTACK_CLOSEST, BattleOrderTypesLib.SquadOrder.ADVANCE_CONTACT:
				_set_squad_objective(store, squad, battle_data)
			BattleOrderTypesLib.SquadOrder.HOLD_AND_ATTACK_REAR:
				squad.hold_rounds = 1
				_set_squad_objective(store, squad, battle_data)


func _set_squad_objective(store, squad, battle_data) -> void:
	# Everyone marches on the nearest living enemy — no sector leash (avoids flank armies idling).
	var global_enemy := _nearest_enemy_for_squad(store, squad)
	if global_enemy.x >= 0:
		squad.target_gx = global_enemy.x
		squad.target_gy = global_enemy.y
		return
	var band: int = squad.id % CONTACT_SECTOR_COUNT
	var rally := _contact_rally_cell(squad, battle_data, band)
	squad.target_gx = rally.x
	squad.target_gy = rally.y


## Nearest hostile cell to any living member of this squad (whole map).
static func nearest_enemy_for_unit(store, unit_idx: int) -> Vector2i:
	if store == null or unit_idx < 0 or unit_idx >= store.count or not store.is_alive(unit_idx):
		return Vector2i(-1, -1)
	var best_dist: int = 999999
	var best := Vector2i(-1, -1)
	var ux: int = store.grid_x[unit_idx]
	var uy: int = store.grid_y[unit_idx]
	for i in range(store.count):
		if not store.is_alive(i) or store.side[i] == store.side[unit_idx]:
			continue
		var dist: int = absi(store.grid_x[i] - ux) + absi(store.grid_y[i] - uy)
		if dist < best_dist:
			best_dist = dist
			best = Vector2i(store.grid_x[i], store.grid_y[i])
	return best


func _nearest_enemy_for_squad(store, squad) -> Vector2i:
	var best_dist: int = 999999
	var best := Vector2i(-1, -1)
	for idx in squad.unit_indices:
		if not store.is_alive(idx):
			continue
		var hit := nearest_enemy_for_unit(store, idx)
		if hit.x < 0:
			continue
		var dist: int = absi(hit.x - store.grid_x[idx]) + absi(hit.y - store.grid_y[idx])
		if dist < best_dist:
			best_dist = dist
			best = hit
	return best


func _sector_y_range(battle_data, band: int) -> Vector2i:
	if battle_data == null:
		return Vector2i(0, 0)
	var bands: int = CONTACT_SECTOR_COUNT
	var t0: float = float(band) / float(maxi(1, bands - 1))
	var t1: float = float(mini(band + 1, bands - 1)) / float(maxi(1, bands - 1))
	var y_min: int = int(
		lerpf(battle_data.grid_height * 0.1, battle_data.grid_height * 0.9, t0)
	)
	var y_max: int = int(
		lerpf(battle_data.grid_height * 0.1, battle_data.grid_height * 0.9, t1)
	)
	y_min = clampi(y_min - SECTOR_MARGIN_CELLS, 0, battle_data.grid_height - 1)
	y_max = clampi(y_max + SECTOR_MARGIN_CELLS, 0, battle_data.grid_height - 1)
	return Vector2i(y_min, y_max)


func _nearest_enemy_in_sector(store, squad, battle_data, band: int) -> Vector2i:
	var y_range: Vector2i = _sector_y_range(battle_data, band)
	var best_dist: int = 99999
	var best := Vector2i(-1, -1)
	var fallback_dist: int = 99999
	var fallback := Vector2i(-1, -1)
	for idx in squad.unit_indices:
		if not store.is_alive(idx):
			continue
		for i in range(store.count):
			if not store.is_alive(i) or store.side[i] == squad.side:
				continue
			var ey: int = store.grid_y[i]
			var dist: int = absi(store.grid_x[i] - store.grid_x[idx]) + absi(ey - store.grid_y[idx])
			if ey >= y_range.x and ey <= y_range.y:
				if dist < best_dist:
					best_dist = dist
					best = Vector2i(store.grid_x[i], ey)
			elif dist < fallback_dist:
				fallback_dist = dist
				fallback = Vector2i(store.grid_x[i], ey)
	if best.x >= 0 and best_dist <= 36:
		return best
	if fallback.x >= 0 and fallback_dist <= 24:
		return fallback
	return Vector2i(-1, -1)


func _contact_rally_cell(squad, battle_data, band: int) -> Vector2i:
	var y_range: Vector2i = _sector_y_range(battle_data, band)
	var gy: int = int((y_range.x + y_range.y) * 0.5)
	var gx: int = battle_data.contact_column
	if squad.side == UnitSimulationStoreLib.Side.FRIENDLY:
		gx = clampi(gx - 2, 0, battle_data.grid_width - 1)
	else:
		gx = clampi(gx + 2, 0, battle_data.grid_width - 1)
	return Vector2i(gx, gy)


func _set_nearest_enemy_cell(store, squad, battle_data) -> void:
	_set_squad_objective(store, squad, battle_data)
