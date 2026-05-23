class_name MissionTaskBoard
extends RefCounted

## Shared room assignment — prevents duplicate S&D / explore targets across squads.

var _room_claims: Dictionary = {}
var _snd_queues: Dictionary = {}


func reset() -> void:
	_room_claims.clear()
	_snd_queues.clear()


func claim_room(room: Room, unit: SoldierUnit, task_type: String = "snd") -> bool:
	if not room or not unit:
		return false
	var room_id: String = room.map_room_id
	if room_id.is_empty():
		return false
	var existing = _room_claims.get(room_id, null)
	if existing != null:
		var holder: SoldierUnit = existing.get("unit", null) as SoldierUnit
		if is_instance_valid(holder) and holder != unit and holder.is_alive:
			return false
	_room_claims[room_id] = {
		"unit": unit,
		"squad_id": unit.squad_id,
		"task_type": task_type,
	}
	return true


func release_room(room: Room, unit: SoldierUnit) -> void:
	if not room:
		return
	var room_id: String = room.map_room_id
	if not _room_claims.has(room_id):
		return
	var holder: SoldierUnit = _room_claims[room_id].get("unit", null) as SoldierUnit
	if holder == unit or not is_instance_valid(holder):
		_room_claims.erase(room_id)


func release_all_for_unit(unit: SoldierUnit) -> void:
	if not unit:
		return
	for room_id in _room_claims.keys():
		var holder: SoldierUnit = _room_claims[room_id].get("unit", null) as SoldierUnit
		if holder == unit:
			_room_claims.erase(room_id)


func is_room_claimed(room: Room, exclude_unit: SoldierUnit = null) -> bool:
	if not room:
		return false
	var entry = _room_claims.get(room.map_room_id, null)
	if entry == null:
		return false
	var holder: SoldierUnit = entry.get("unit", null) as SoldierUnit
	if not is_instance_valid(holder) or not holder.is_alive:
		_room_claims.erase(room.map_room_id)
		return false
	if exclude_unit and holder == exclude_unit:
		return false
	return true


func build_snd_queue(
	units: Array,
	all_rooms: Array,
	start_room: Room = null,
	squad_id: String = "",
) -> Array[Room]:
	var origin: Vector2 = Vector2.ZERO
	if not units.is_empty() and units[0] is SoldierUnit:
		origin = (units[0] as SoldierUnit).position
	var hostile: Array[Room] = []
	for node in all_rooms:
		if not node is Room:
			continue
		var room: Room = node as Room
		if room.is_spawn_room or not room.has_living_enemies():
			continue
		if is_room_claimed(room):
			continue
		hostile.append(room)
	hostile.sort_custom(func(a, b): return origin.distance_to(a.position) < origin.distance_to(b.position))
	if start_room and not start_room.is_spawn_room:
		if start_room in hostile:
			hostile.erase(start_room)
		hostile.insert(0, start_room)
	if not squad_id.is_empty():
		_snd_queues[squad_id] = hostile.duplicate()
	return hostile


func partition_rooms(rooms: Array, units: Array) -> Dictionary:
	var result: Dictionary = {}
	for unit in units:
		if unit is SoldierUnit:
			result[unit] = []
	if rooms.is_empty() or units.is_empty():
		return result
	var unit_list: Array = []
	for unit in units:
		if unit is SoldierUnit and (unit as SoldierUnit).is_alive:
			unit_list.append(unit)
	if unit_list.is_empty():
		return result
	for i in range(rooms.size()):
		var assignee = unit_list[i % unit_list.size()]
		result[assignee].append(rooms[i])
	return result


func next_unclaimed_hostile(origin: Vector2, unit: SoldierUnit, all_rooms: Array) -> Room:
	var best: Room = null
	var best_dist: float = INF
	for node in all_rooms:
		if not node is Room:
			continue
		var room: Room = node as Room
		if room.is_spawn_room or not room.has_living_enemies():
			continue
		if is_room_claimed(room, unit):
			continue
		var dist: float = origin.distance_to(room.position)
		if dist < best_dist:
			best_dist = dist
			best = room
	return best
