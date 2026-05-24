class_name MissionEntityIndex
extends RefCounted

## Room-indexed entity lists to avoid O(n) tree scans for fog/combat.

var soldiers_by_room: Dictionary = {}
var enemies_by_room: Dictionary = {}
var hives_by_room: Dictionary = {}
var soldier_room: Dictionary = {}
var revealed_rooms: Array[Room] = []
var frontier_rooms: Array[Room] = []
var living_enemy_count_cached: int = 0


func _valid_enemy(enemy) -> EnemyUnit:
	if enemy == null or not is_instance_valid(enemy):
		return null
	if not enemy is EnemyUnit:
		return null
	return enemy as EnemyUnit


func _valid_soldier(unit) -> SoldierUnit:
	if unit == null or not is_instance_valid(unit):
		return null
	if not unit is SoldierUnit:
		return null
	return unit as SoldierUnit


func prune_stale_entries() -> void:
	for room in enemies_by_room.keys():
		var list: Array = enemies_by_room[room]
		var kept: Array = []
		for enemy in list:
			var eu := _valid_enemy(enemy)
			if eu:
				kept.append(eu)
		if kept.is_empty():
			enemies_by_room.erase(room)
		else:
			enemies_by_room[room] = kept
	living_enemy_count_cached = get_all_living_enemies().size()
	for room in soldiers_by_room.keys():
		var list: Array = soldiers_by_room[room]
		var kept_s: Array = []
		for unit in list:
			var su := _valid_soldier(unit)
			if su:
				kept_s.append(su)
		if kept_s.is_empty():
			soldiers_by_room.erase(room)
		else:
			soldiers_by_room[room] = kept_s
	var dead_soldiers: Array = []
	for unit in soldier_room.keys():
		if not _valid_soldier(unit):
			dead_soldiers.append(unit)
	for unit in dead_soldiers:
		soldier_room.erase(unit)


func reset() -> void:
	soldiers_by_room.clear()
	enemies_by_room.clear()
	hives_by_room.clear()
	soldier_room.clear()
	revealed_rooms.clear()
	frontier_rooms.clear()
	living_enemy_count_cached = 0


func register_soldier(unit: SoldierUnit, room: Room) -> void:
	if not unit or not room:
		return
	var previous: Room = soldier_room.get(unit, null)
	if previous and previous != room:
		unregister_soldier(unit, previous)
	var list: Array = soldiers_by_room.get(room, [])
	if unit not in list:
		list.append(unit)
	soldiers_by_room[room] = list
	soldier_room[unit] = room


func unregister_soldier(unit: SoldierUnit, room: Room) -> void:
	if not room or not soldiers_by_room.has(room):
		return
	var list: Array = soldiers_by_room[room]
	list.erase(unit)
	if list.is_empty():
		soldiers_by_room.erase(room)
	else:
		soldiers_by_room[room] = list
	if soldier_room.get(unit) == room:
		soldier_room.erase(unit)


func register_enemy(enemy: EnemyUnit, room: Room) -> void:
	if not enemy or not room:
		return
	var list: Array = enemies_by_room.get(room, [])
	if enemy not in list:
		list.append(enemy)
		if enemy.is_alive:
			living_enemy_count_cached += 1
	enemies_by_room[room] = list


func unregister_enemy(enemy: EnemyUnit, room: Room) -> void:
	if not room or not enemies_by_room.has(room):
		return
	if not is_instance_valid(enemy):
		prune_stale_entries()
		return
	var list: Array = enemies_by_room[room]
	if enemy in list and enemy.is_alive:
		living_enemy_count_cached = maxi(0, living_enemy_count_cached - 1)
	list.erase(enemy)
	if list.is_empty():
		enemies_by_room.erase(room)
	else:
		enemies_by_room[room] = list


func register_hive(hive: Hive, room: Room) -> void:
	if not hive or not room:
		return
	hives_by_room[room] = hive


func unregister_hive(room: Room) -> void:
	if room:
		hives_by_room.erase(room)


func get_hive_in_room(room: Room) -> Hive:
	if not room:
		return null
	var hive = hives_by_room.get(room, null)
	if is_instance_valid(hive) and hive is Hive and hive.is_attackable():
		return hive
	if room.has_meta("hive"):
		var meta_hive = room.get_meta("hive")
		if is_instance_valid(meta_hive) and meta_hive is Hive and meta_hive.is_attackable():
			return meta_hive
	return null


func get_all_living_soldiers() -> Array[SoldierUnit]:
	var result: Array[SoldierUnit] = []
	for room in soldiers_by_room.keys():
		for unit in soldiers_by_room[room]:
			var su := _valid_soldier(unit)
			if su and su.is_alive and not su.is_extracted:
				result.append(su)
	return result


func get_all_living_enemies() -> Array[EnemyUnit]:
	var result: Array[EnemyUnit] = []
	for room in enemies_by_room.keys():
		for enemy in enemies_by_room[room]:
			var eu := _valid_enemy(enemy)
			if eu and eu.is_alive:
				result.append(eu)
	return result


func living_enemy_count() -> int:
	return living_enemy_count_cached


func mark_revealed(room: Room) -> void:
	if room and room not in revealed_rooms:
		revealed_rooms.append(room)


func rebuild_frontier(all_rooms: Array, adjacent_fn: Callable) -> void:
	frontier_rooms.clear()
	if revealed_rooms.is_empty():
		return
	for room in all_rooms:
		if room.is_revealed:
			continue
		for revealed in revealed_rooms:
			if adjacent_fn.call(revealed, room):
				frontier_rooms.append(room)
				break


func rooms_for_fog_update(all_rooms: Array) -> Array[Room]:
	if frontier_rooms.is_empty():
		return all_rooms
	return frontier_rooms


func get_enemies_in_room(room: Room) -> Array:
	if not room:
		return []
	var list: Array = enemies_by_room.get(room, [])
	var result: Array = []
	for enemy in list:
		var eu := _valid_enemy(enemy)
		if eu and eu.is_alive:
			result.append(eu)
	return result


func get_soldiers_in_room(room: Room) -> Array:
	if not room:
		return []
	var list: Array = soldiers_by_room.get(room, [])
	var result: Array = []
	for soldier in list:
		var su := _valid_soldier(soldier)
		if su and su.is_alive and not su.is_extracted:
			result.append(su)
	return result


func get_soldier_room(unit: SoldierUnit) -> Room:
	if not unit:
		return null
	return soldier_room.get(unit, null)


func get_enemies_near_position(origin: Vector2, max_radius: float) -> Array[EnemyUnit]:
	var radius_sq := max_radius * max_radius
	var result: Array[EnemyUnit] = []
	for room in enemies_by_room.keys():
		for enemy in enemies_by_room[room]:
			var eu := _valid_enemy(enemy)
			if not eu or not eu.is_alive:
				continue
			if origin.distance_squared_to(eu.position) <= radius_sq:
				result.append(eu)
	return result


func get_enemies_for_fog_check(soldiers: Array, los_range: float) -> Array[EnemyUnit]:
	var seen: Dictionary = {}
	var result: Array[EnemyUnit] = []
	for room in revealed_rooms:
		for enemy in get_enemies_in_room(room):
			if enemy not in seen:
				seen[enemy] = true
				result.append(enemy)
	for soldier in soldiers:
		if not soldier is SoldierUnit:
			continue
		for enemy in get_enemies_near_position(soldier.position, los_range):
			if enemy not in seen:
				seen[enemy] = true
				result.append(enemy)
	for room in enemies_by_room.keys():
		for enemy in enemies_by_room[room]:
			var eu := _valid_enemy(enemy)
			if not eu or not eu.is_alive or not eu.is_visible_to_player:
				continue
			if eu not in seen:
				seen[eu] = true
				result.append(eu)
	return result


## Single fog pass: iterate frontier rooms once, batch reveals, one frontier rebuild caller-side.
func fog_reveal_rooms(
	soldiers: Array,
	rooms_to_check: Array,
	_all_rooms: Array,
	_door_nodes: Array,
	fog_scale: float,
	skip_room_fn: Callable,
	reveal_occupied_fn: Callable,
	los_reveal_fn: Callable,
	on_extraction_discovered_fn: Callable
) -> bool:
	var frontier_dirty := false
	for room in rooms_to_check:
		if skip_room_fn.call(room):
			continue
		var occupied := false
		for soldier in soldiers:
			if room.contains_local_point(soldier.position, 0.0):
				if reveal_occupied_fn.call(room):
					frontier_dirty = true
				occupied = true
		if occupied:
			continue
		if fog_scale < 1.0 or room.is_revealed:
			continue
		for soldier in soldiers:
			if los_reveal_fn.call(soldier.position, room):
				room.reveal()
				mark_revealed(room)
				frontier_dirty = true
				if room.is_extraction_room:
					on_extraction_discovered_fn.call(room)
				break
	return frontier_dirty


func fog_update_enemy_visibility(
	soldiers: Array,
	enemies: Array,
	_all_rooms: Array,
	_door_nodes: Array,
	los_range: float,
	has_los_fn: Callable,
	on_spotted_fn: Callable,
	on_lost_fn: Callable
) -> void:
	for enemy in enemies:
		var enemy_unit := _valid_enemy(enemy)
		if not enemy_unit:
			continue
		if not enemy_unit.is_alive:
			continue
		if not enemy_unit.is_visible_to_player:
			var near_soldier := false
			for soldier in soldiers:
				if soldier.position.distance_to(enemy_unit.position) <= los_range:
					near_soldier = true
					break
			if not near_soldier:
				continue
		var was_visible: bool = enemy_unit.is_visible_to_player
		var seen := false
		for soldier in soldiers:
			if has_los_fn.call(soldier.position, enemy_unit.position):
				seen = true
				break
		enemy_unit.set_visible_to_player(seen)
		if seen and not was_visible:
			on_spotted_fn.call(enemy_unit)
		elif not seen and was_visible:
			on_lost_fn.call(enemy_unit)
