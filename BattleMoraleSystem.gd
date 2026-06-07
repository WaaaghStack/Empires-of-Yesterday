class_name BattleMoraleSystem
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

const ROUT_CASUALTY_FRAC := 0.45
const ROUT_MORALE_THRESHOLD := 4
const SQUAD_MORALE_PENALTY_PER_DEATH := 1


func apply_casualty_morale(store, squads: Array, dead_indices: Array) -> void:
	for idx in dead_indices:
		if idx < 0 or idx >= store.count:
			continue
		var sq_id: int = store.squad_index[idx]
		for squad in squads:
			if squad.id != sq_id:
				continue
			for u in squad.unit_indices:
				if store.is_alive(u) and not store.is_routed(u):
					store.morale[u] = maxi(0, store.morale[u] - SQUAD_MORALE_PENALTY_PER_DEATH)
			break


func check_unit_rout(_store, _idx: int, _battle_data) -> void:
	# Routing disabled — units fight until dead.
	pass


func tick_squad_morale(store, squads: Array, battle_data) -> void:
	for squad in squads:
		var living: int = squad.living_count(store)
		var total: int = maxi(1, squad.unit_indices.size())
		if float(total - living) / float(total) >= 0.35:
			for u in squad.unit_indices:
				check_unit_rout(store, u, battle_data)


func army_rout_fraction(store, side: int, start_count: int) -> float:
	if start_count <= 0:
		return 1.0
	var dead_or_routed: int = 0
	for i in range(store.count):
		if store.side[i] != side:
			continue
		if not store.is_alive(i) or store.is_routed(i):
			dead_or_routed += 1
	return float(dead_or_routed) / float(start_count)


func commanders_alive(commanders: Array, store, side: int) -> int:
	var n: int = 0
	for cmd in commanders:
		if cmd.side != side:
			continue
		if cmd.unit_index >= 0 and store.is_alive(cmd.unit_index) and not store.is_routed(cmd.unit_index):
			cmd.alive = true
			n += 1
		else:
			cmd.alive = false
	return n


func is_army_routed(store, commanders: Array, side: int, start_count: int) -> bool:
	if commanders_alive(commanders, store, side) <= 0:
		return true
	return army_rout_fraction(store, side, start_count) >= ROUT_CASUALTY_FRAC


func _flee_off_map(store, idx: int, battle_data) -> void:
	if battle_data == null:
		return
	var gx: int = store.grid_x[idx]
	var gy: int = store.grid_y[idx]
	if store.side[idx] == UnitSimulationStoreLib.Side.FRIENDLY:
		gx = maxi(0, gx - 2)
	else:
		gx = mini(battle_data.grid_width - 1, gx + 2)
	store.set_grid_cell(idx, gx, gy, battle_data)
