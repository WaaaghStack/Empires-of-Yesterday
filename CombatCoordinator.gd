class_name CombatCoordinator
extends RefCounted

const LineOfSightLib := preload("res://LineOfSight.gd")
const MissionStateLib := preload("res://MissionState.gd")
const OrderTypeLib := preload("res://OrderType.gd")

const TICK_INTERVAL := 0.1

var _timer: float = 0.0


func reset() -> void:
	_timer = 0.0


func tick(
	delta: float,
	soldiers: Array,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	active_hives: Array
) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer = 0.0
	LineOfSightLib.begin_frame_cache()
	_assign_targets(soldiers, entity_index, rooms, door_nodes, active_hives)


func clear_soldier(soldier: SoldierUnit) -> void:
	if soldier:
		soldier.coordinator_assigned_target = null


func _assign_targets(
	soldiers: Array,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	active_hives: Array
) -> void:
	var attackable_hives: Array = []
	for hive in active_hives:
		if hive == null or not is_instance_valid(hive):
			continue
		if hive.has_method("is_attackable") and hive.is_attackable():
			attackable_hives.append(hive)
	var room_enemies_cache: Dictionary = {}
	var room_hive_cache: Dictionary = {}
	for soldier in soldiers:
		if not soldier is SoldierUnit or not soldier.is_alive or soldier.is_extracted:
			continue
		var assigned: Node2D = _pick_target_for_soldier(
			soldier,
			entity_index,
			rooms,
			door_nodes,
			attackable_hives,
			room_enemies_cache,
			room_hive_cache
		)
		soldier.apply_coordinator_target(assigned)


func _pick_target_for_soldier(
	soldier: SoldierUnit,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	attackable_hives: Array,
	room_enemies_cache: Dictionary,
	room_hive_cache: Dictionary
) -> Node2D:
	var marked: Node2D = _squad_marked_target(soldier, rooms, door_nodes)
	if marked:
		return marked
	var existing: Node2D = soldier.coordinator_assigned_target
	if existing and MissionStateLib.is_attackable_target(existing):
		if _can_see_target(soldier, existing, rooms, door_nodes):
			return existing
	match soldier.current_order:
		OrderTypeLib.Type.SEARCH_DESTROY:
			var enemy := _nearest_visible_enemy(soldier, entity_index, rooms, door_nodes)
			if enemy:
				return enemy
			return _nearest_visible_hive(soldier, attackable_hives, rooms, door_nodes)
		OrderTypeLib.Type.CLEAR:
			if soldier.order_room and soldier.has_searched_room:
				return _priority_target_in_room(
					soldier,
					soldier.order_room,
					entity_index,
					rooms,
					door_nodes,
					room_enemies_cache,
					room_hive_cache
				)
		OrderTypeLib.Type.DEFEND:
			if soldier.order_room and soldier.awaiting_at_destination:
				return _defend_target_in_room(
					soldier,
					soldier.order_room,
					entity_index,
					rooms,
					door_nodes,
					room_enemies_cache,
					room_hive_cache
				)
		OrderTypeLib.Type.EXPLORE, OrderTypeLib.Type.EXTRACT:
			if soldier.order_room and soldier.has_searched_room:
				return _priority_target_in_room(
					soldier,
					soldier.order_room,
					entity_index,
					rooms,
					door_nodes,
					room_enemies_cache,
					room_hive_cache
				)
	return null


func _squad_marked_target(soldier: SoldierUnit, rooms: Array, door_nodes: Array) -> Node2D:
	var marked: Node2D = MissionStateLib.squad_marked_target
	if not marked or not MissionStateLib.is_attackable_target(marked):
		return null
	if _can_see_target(soldier, marked, rooms, door_nodes):
		return marked
	return null


func _can_see_target(soldier: SoldierUnit, target: Node2D, rooms: Array, door_nodes: Array) -> bool:
	if not target or not MissionStateLib.is_attackable_target(target):
		return false
	return LineOfSightLib.has_line_of_sight(soldier.position, target.position, rooms, door_nodes)


func _nearest_visible_enemy(
	soldier: SoldierUnit,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array
) -> EnemyUnit:
	var nearest: EnemyUnit = null
	var nearest_dist_sq: float = INF
	const CANDIDATE_RADIUS := 520.0
	var soldier_room: Room = entity_index.get_soldier_room(soldier)
	var candidates: Array = []
	if soldier_room:
		candidates = entity_index.get_enemies_in_room(soldier_room)
	if candidates.size() < 4:
		for enemy in entity_index.get_enemies_near_position(soldier.position, CANDIDATE_RADIUS):
			if enemy not in candidates:
				candidates.append(enemy)
	for enemy in candidates:
		if not enemy is EnemyUnit or not enemy.is_alive:
			continue
		var dist_sq: float = soldier.position.distance_squared_to(enemy.position)
		if dist_sq >= nearest_dist_sq:
			continue
		if not _can_see_target(soldier, enemy, rooms, door_nodes):
			continue
		nearest_dist_sq = dist_sq
		nearest = enemy
	return nearest


func _nearest_visible_hive(soldier: SoldierUnit, hives: Array, rooms: Array, door_nodes: Array) -> Hive:
	var nearest: Hive = null
	var nearest_dist: float = INF
	for hive in hives:
		if not hive is Hive or not hive.is_attackable():
			continue
		if not _can_see_target(soldier, hive, rooms, door_nodes):
			continue
		var dist: float = soldier.position.distance_to(hive.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = hive
	return nearest


func _enemies_in_room(entity_index: MissionEntityIndex, room: Room, cache: Dictionary) -> Array:
	if cache.has(room):
		return cache[room]
	var list: Array = entity_index.get_enemies_in_room(room)
	cache[room] = list
	return list


func _hive_in_room(entity_index: MissionEntityIndex, room: Room, cache: Dictionary) -> Hive:
	if cache.has(room):
		return cache[room]
	var hive: Hive = entity_index.get_hive_in_room(room)
	cache[room] = hive
	return hive


func _visible_enemies_in_room(
	soldier: SoldierUnit,
	room: Room,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	room_enemies_cache: Dictionary
) -> Array:
	var visible: Array = []
	for enemy in _enemies_in_room(entity_index, room, room_enemies_cache):
		if _can_see_target(soldier, enemy, rooms, door_nodes):
			visible.append(enemy)
	return visible


func _visible_hive_in_room(
	soldier: SoldierUnit,
	room: Room,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	room_hive_cache: Dictionary
) -> Hive:
	var hive := _hive_in_room(entity_index, room, room_hive_cache)
	if hive and _can_see_target(soldier, hive, rooms, door_nodes):
		return hive
	return null


func _priority_target_in_room(
	soldier: SoldierUnit,
	room: Room,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	room_enemies_cache: Dictionary,
	room_hive_cache: Dictionary
) -> Node2D:
	var marked: Node2D = MissionStateLib.squad_marked_target
	if marked and MissionStateLib.is_attackable_target(marked):
		if marked is EnemyUnit and marked.home_room == room and _can_see_target(soldier, marked, rooms, door_nodes):
			return marked
		if marked is Hive and marked.home_room == room and _can_see_target(soldier, marked, rooms, door_nodes):
			return marked
	var hive := _visible_hive_in_room(soldier, room, entity_index, rooms, door_nodes, room_hive_cache)
	if hive:
		return hive
	var enemies: Array = _visible_enemies_in_room(soldier, room, entity_index, rooms, door_nodes, room_enemies_cache)
	var nearest: EnemyUnit = null
	var nearest_dist: float = INF
	for enemy in enemies:
		var dist: float = soldier.position.distance_to(enemy.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


func _defend_target_in_room(
	soldier: SoldierUnit,
	room: Room,
	entity_index: MissionEntityIndex,
	rooms: Array,
	door_nodes: Array,
	room_enemies_cache: Dictionary,
	room_hive_cache: Dictionary
) -> Node2D:
	var marked: Node2D = MissionStateLib.squad_marked_target
	if marked and MissionStateLib.is_attackable_target(marked):
		if marked.home_room == room and soldier.position.distance_to(marked.position) <= soldier.attack_range:
			if _can_see_target(soldier, marked, rooms, door_nodes):
				return marked
	var hive := _visible_hive_in_room(soldier, room, entity_index, rooms, door_nodes, room_hive_cache)
	if hive and soldier.position.distance_to(hive.position) <= soldier.attack_range:
		return hive
	var enemies: Array = _visible_enemies_in_room(soldier, room, entity_index, rooms, door_nodes, room_enemies_cache)
	var nearest: EnemyUnit = null
	var nearest_dist: float = soldier.attack_range
	for enemy in enemies:
		var dist: float = soldier.position.distance_to(enemy.position)
		if dist <= soldier.attack_range and dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest
