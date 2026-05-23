class_name MissionEntityIndex
extends RefCounted

## Room-indexed entity lists to avoid O(n) tree scans for fog/combat.

var soldiers_by_room: Dictionary = {}
var enemies_by_room: Dictionary = {}
var revealed_rooms: Array[Room] = []
var frontier_rooms: Array[Room] = []


func reset() -> void:
	soldiers_by_room.clear()
	enemies_by_room.clear()
	revealed_rooms.clear()
	frontier_rooms.clear()


func register_soldier(unit: SoldierUnit, room: Room) -> void:
	if not unit or not room:
		return
	var list: Array = soldiers_by_room.get(room, [])
	if unit not in list:
		list.append(unit)
	soldiers_by_room[room] = list


func unregister_soldier(unit: SoldierUnit, room: Room) -> void:
	if not room or not soldiers_by_room.has(room):
		return
	var list: Array = soldiers_by_room[room]
	list.erase(unit)
	if list.is_empty():
		soldiers_by_room.erase(room)
	else:
		soldiers_by_room[room] = list


func register_enemy(enemy: EnemyUnit, room: Room) -> void:
	if not enemy or not room:
		return
	var list: Array = enemies_by_room.get(room, [])
	if enemy not in list:
		list.append(enemy)
	enemies_by_room[room] = list


func unregister_enemy(enemy: EnemyUnit, room: Room) -> void:
	if not room or not enemies_by_room.has(room):
		return
	var list: Array = enemies_by_room[room]
	list.erase(enemy)
	if list.is_empty():
		enemies_by_room.erase(room)
	else:
		enemies_by_room[room] = list


func get_all_living_soldiers() -> Array[SoldierUnit]:
	var result: Array[SoldierUnit] = []
	for room in soldiers_by_room.keys():
		for unit in soldiers_by_room[room]:
			if unit is SoldierUnit and unit.is_alive and not unit.is_extracted:
				result.append(unit)
	return result


func get_all_living_enemies() -> Array[EnemyUnit]:
	var result: Array[EnemyUnit] = []
	for room in enemies_by_room.keys():
		for enemy in enemies_by_room[room]:
			if enemy is EnemyUnit and enemy.is_alive:
				result.append(enemy)
	return result


func living_enemy_count() -> int:
	return get_all_living_enemies().size()


func mark_revealed(room: Room) -> void:
	if room and room not in revealed_rooms:
		revealed_rooms.append(room)


func rooms_for_fog_update(all_rooms: Array) -> Array[Room]:
	if frontier_rooms.is_empty():
		return all_rooms
	return frontier_rooms
