class_name EnemyUnit
extends Node2D

const CombatFxLib := preload("res://CombatFx.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const MissionStateLib := preload("res://MissionState.gd")

signal died(enemy: EnemyUnit)
signal combat_hit(attacker_name: String, target_name: String, damage: int, killed: bool)
signal alarm_triggered(enemy: EnemyUnit)

@export var enemy_name: String = "Hostile"
@export var max_health: int = 50
@export var damage: int = 12
@export var speed: float = 80.0
@export var attack_range: float = 110.0
@export var fire_rate: float = 0.7
@export var aggro_range: float = 420.0
@export var leash_range: float = 260.0

var current_health: int = 50
var is_alive := true
var is_visible_to_player := false
var home_room: Room = null
var enemy_archetype: Enemy.Archetype = Enemy.Archetype.RIFLEMAN
var fire_cooldown: float = 0.0
var path_queue: Array[Vector2] = []
var path_index: int = 0
var hunt_room: Room = null
var waiting_at_door: Node2D = null
var _pathing_to_room: Room = null
var is_focus_marked := false
var focus_mark_timer: float = 0.0
var _alarm_called := false
var _ai_skip_frames: int = 0
var _ai_process_interval: int = 2
var _overwatch_anchor: Vector2 = Vector2.ZERO

const WAYPOINT_RADIUS := 10.0
const HUNT_SPEED_RATIO := 0.25
const SNIPER_CHASE_RANGE_MULT := 0.55
const HEAVY_DOOR_AGGRO_MULT := 1.65
const HEAVY_DOOR_PROXIMITY := 52.0

@onready var body_poly: Polygon2D = $BodyPoly
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	_update_visuals()
	_apply_visibility()

func _mission_paused() -> bool:
	return MissionStateLib.is_unit_actions_frozen(self)

func setup_from_resource(resource: Enemy, room: Room = null) -> void:
	if resource:
		enemy_name = resource.enemy_name
		max_health = resource.health
		current_health = resource.health
		damage = resource.damage
		speed = resource.speed
		if resource.attack_range > 0.0:
			attack_range = resource.attack_range
		if resource.fire_rate > 0.0:
			fire_rate = resource.fire_rate
		if resource.aggro_range > 0.0:
			aggro_range = resource.aggro_range
		if resource.leash_range > 0.0:
			leash_range = resource.leash_range
		enemy_archetype = resource.archetype
	home_room = room
	if home_room:
		_overwatch_anchor = home_room.position
	_update_visuals()

func _physics_process(delta: float) -> void:
	if not is_alive or _mission_paused():
		return
	if not is_visible_to_player:
		_ai_skip_frames += 1
		if _ai_skip_frames % _ai_process_interval != 0:
			return
	else:
		_ai_skip_frames = 0
	if focus_mark_timer > 0.0:
		focus_mark_timer = maxf(0.0, focus_mark_timer - delta)
		if focus_mark_timer <= 0.0:
			is_focus_marked = false
			_apply_mark_visual()
	fire_cooldown = max(0.0, fire_cooldown - delta)
	speed = _get_hunt_speed()
	var effective_aggro := _get_effective_aggro_range()
	var target := _find_nearest_soldier(effective_aggro)
	var is_aggro := target != null
	_apply_aggro_tint(is_aggro)
	if target:
		var dist: float = position.distance_to(target.position)
		if dist <= attack_range and is_visible_to_player:
			_face_target(target)
			_try_attack_target(target)
			return
		if dist <= effective_aggro:
			if _should_hold_overwatch(target):
				_hold_overwatch(delta, target)
				return
			_chase_soldier(delta, target)
			return
	_process_search_destroy(delta)

func _get_hunt_speed() -> float:
	return _average_soldier_speed() * HUNT_SPEED_RATIO

func _average_soldier_speed() -> float:
	if not is_inside_tree():
		return 56.0
	var total: float = 0.0
	var count: int = 0
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			total += node.speed
			count += 1
	if count > 0:
		return total / float(count)
	return 56.0

func _chase_soldier(delta: float, target: SoldierUnit) -> void:
	var move_speed := speed
	if enemy_archetype == Enemy.Archetype.HEAVY:
		move_speed *= 0.82
	var my_room := _room_containing(position)
	var target_room := _room_containing(target.position)
	if my_room and target_room and my_room == target_room:
		_move_direct(delta, target.position, move_speed)
		return
	if enemy_archetype == Enemy.Archetype.HEAVY and _is_near_choke_door() and my_room != target_room:
		_face_target(target)
		return
	if hunt_room != target_room or path_queue.is_empty():
		hunt_room = target_room
		_rebuild_path_to_position(target.position, target_room)
	_move_along_path(delta, move_speed)

func _process_search_destroy(delta: float) -> void:
	if home_room and not _any_soldiers_alive():
		if position.distance_to(home_room.position) > 16.0:
			_rebuild_path_to_position(home_room.position, home_room)
			_move_along_path(delta)
		return
	var target_room := _find_hunt_room()
	if not target_room:
		return
	if hunt_room != target_room or path_queue.is_empty():
		hunt_room = target_room
		_rebuild_path_to_position(target_room.position, target_room)
	_move_along_path(delta)

func _find_hunt_room() -> Room:
	var best_room: Room = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and _room_has_soldier(node):
			var dist: float = position.distance_to(node.position)
			if dist < best_dist:
				best_dist = dist
				best_room = node
	return best_room

func _room_has_soldier(room: Room) -> bool:
	for soldier in room.soldiers_inside:
		if soldier is SoldierUnit and soldier.is_alive:
			return true
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive and room.contains_local_point(node.position, 10.0):
			return true
	return false

func _any_soldiers_alive() -> bool:
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			return true
	return false

func _rebuild_path_to_position(end_pos: Vector2, target_room: Room) -> void:
	path_queue.clear()
	path_index = 0
	_pathing_to_room = null
	var graph := _get_path_graph()
	if not graph:
		path_queue.append(end_pos)
		return
	var from_room := _room_containing(position)
	var blocked: Array[String] = []
	for point in graph.find_path(position, end_pos, blocked, from_room, target_room):
		path_queue.append(point)
	if path_queue.is_empty():
		path_queue.append(end_pos)
	_pathing_to_room = target_room
	while path_index < path_queue.size() - 1 and position.distance_to(path_queue[path_index]) < WAYPOINT_RADIUS:
		path_index += 1

func _move_along_path(delta: float, move_speed: float = -1.0) -> void:
	var step_speed := move_speed if move_speed > 0.0 else speed
	if waiting_at_door:
		if waiting_at_door.blocks_travel():
			waiting_at_door.request_open()
			return
		waiting_at_door = null
		_rebuild_path_to_position(path_queue[path_queue.size() - 1], hunt_room)
	if path_index >= path_queue.size():
		return
	var waypoint: Vector2 = path_queue[path_index]
	if position.distance_to(waypoint) <= WAYPOINT_RADIUS:
		path_index += 1
		return
	var blocking_door := _find_blocking_door_ahead(waypoint)
	if blocking_door:
		blocking_door.request_open()
		waiting_at_door = blocking_door
		return
	_move_toward_waypoint(delta, waypoint, step_speed)

func _move_toward_waypoint(delta: float, waypoint: Vector2, move_speed: float) -> void:
	var to_waypoint: Vector2 = waypoint - position
	if to_waypoint.length() <= 0.001:
		return
	var before: Vector2 = position
	if _is_in_corridor_at(position) or _is_in_corridor_at(waypoint):
		var step: float = move_speed * delta
		if absf(to_waypoint.x) >= absf(to_waypoint.y):
			position.x += signf(to_waypoint.x) * minf(absf(to_waypoint.x), step)
		else:
			position.y += signf(to_waypoint.y) * minf(absf(to_waypoint.y), step)
	elif _room_containing(position):
		position += to_waypoint.normalized() * minf(to_waypoint.length(), move_speed * delta)
	else:
		var step: float = move_speed * delta
		if absf(to_waypoint.x) >= absf(to_waypoint.y):
			position.x += signf(to_waypoint.x) * minf(absf(to_waypoint.x), step)
		else:
			position.y += signf(to_waypoint.y) * minf(absf(to_waypoint.y), step)
	if not _is_walkable(position):
		position = before
		return
	if body_poly:
		body_poly.rotation = to_waypoint.angle()

func _move_direct(delta: float, target_pos: Vector2, move_speed: float) -> void:
	var before: Vector2 = position
	var to_target: Vector2 = target_pos - position
	if to_target.length() <= 0.001:
		return
	position += to_target.normalized() * minf(to_target.length(), move_speed * delta)
	if not _is_walkable(position):
		position = before
		return
	if body_poly:
		body_poly.rotation = to_target.angle()

func _room_containing(pos: Vector2) -> Room:
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and node.contains_local_point(pos, 10.0):
			return node
	return null

func _is_in_corridor_at(pos: Vector2) -> bool:
	var graph := _get_path_graph()
	if graph and graph.has_method("is_in_corridor"):
		return graph.is_in_corridor(pos)
	return false

func _is_walkable(pos: Vector2) -> bool:
	if _is_in_corridor_at(pos):
		return true
	if _room_containing(pos):
		return true
	var graph := _get_path_graph()
	if graph and graph.nodes:
		for node_pos in graph.nodes.values():
			if pos.distance_to(node_pos) <= 18.0:
				return true
	return false

func _get_path_graph() -> RefCounted:
	for node in get_tree().get_nodes_in_group("tactical_map"):
		return node.path_graph as RefCounted
	return null

func _find_blocking_door_ahead(waypoint: Vector2) -> Node2D:
	var move_dir: Vector2 = waypoint - position
	if move_dir.length() < 0.001:
		return null
	for node in get_tree().get_nodes_in_group("doors"):
		if not node.has_method("blocks_travel"):
			continue
		if node.blocks_travel():
			var door_node: Node2D = node as Node2D
			var to_door: Vector2 = door_node.position - position
			if to_door.length() > 44.0:
				continue
			if to_door.normalized().dot(move_dir.normalized()) > 0.35:
				return door_node
	return null

func _face_target(target: Node2D) -> void:
	if not target or not body_poly:
		return
	var direction := target.position - position
	if direction.length() > 0.01:
		body_poly.rotation = direction.angle()

func _get_effective_aggro_range() -> float:
	var range_val := aggro_range
	if enemy_archetype == Enemy.Archetype.HEAVY and _is_near_choke_door():
		range_val *= HEAVY_DOOR_AGGRO_MULT
	return range_val


func _is_near_choke_door() -> bool:
	for node in get_tree().get_nodes_in_group("doors"):
		if node is Node2D and position.distance_to(node.position) <= HEAVY_DOOR_PROXIMITY:
			return true
	return false


func _should_hold_overwatch(target: SoldierUnit) -> bool:
	if enemy_archetype != Enemy.Archetype.SNIPER or not home_room:
		return false
	var my_room := _room_containing(position)
	var target_room := _room_containing(target.position)
	if my_room == target_room:
		return false
	if my_room == home_room:
		return true
	return position.distance_to(_overwatch_anchor) <= leash_range * SNIPER_CHASE_RANGE_MULT


func _hold_overwatch(delta: float, target: SoldierUnit) -> void:
	if not home_room:
		return
	var anchor := home_room.position
	if position.distance_to(anchor) > 18.0:
		_move_direct(delta, anchor, speed * 0.65)
	else:
		_face_target(target)


func _find_nearest_soldier(max_range: float = -1.0) -> SoldierUnit:
	var search_range := max_range if max_range > 0.0 else aggro_range
	var nearest: SoldierUnit = null
	var nearest_dist: float = search_range
	var rooms: Array[Room] = _get_rooms()
	var door_nodes: Array = get_tree().get_nodes_in_group("doors")
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			var dist: float = position.distance_to(node.position)
			if dist >= nearest_dist:
				continue
			if not LineOfSightLib.has_line_of_sight(position, node.position, rooms, door_nodes):
				continue
			nearest_dist = dist
			nearest = node
	return nearest

func set_focus_marked(marked: bool, duration: float = 10.0) -> void:
	is_focus_marked = marked
	focus_mark_timer = duration if marked else 0.0
	_apply_mark_visual()

func _apply_mark_visual() -> void:
	if not body_poly:
		return
	if is_focus_marked and is_visible_to_player:
		body_poly.modulate = Color(1.35, 0.95, 0.35)
	else:
		body_poly.modulate = Color.WHITE

func set_visible_to_player(now_visible: bool) -> void:
	if is_visible_to_player == now_visible:
		return
	is_visible_to_player = now_visible
	_apply_visibility()
	if is_focus_marked:
		_apply_mark_visual()

func _apply_visibility() -> void:
	visible = is_visible_to_player
	if health_bar:
		health_bar.visible = is_visible_to_player

func _get_rooms() -> Array[Room]:
	var result: Array[Room] = []
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room:
			result.append(node)
	return result

func _try_attack_target(target: SoldierUnit) -> void:
	if fire_cooldown > 0.0 or not target or not target.is_alive:
		return
	var was_alive := target.is_alive
	target.take_damage(damage, self)
	fire_cooldown = 1.0 / fire_rate
	CombatFxLib.spawn_shot(self, target.global_position, Color(1.0, 0.35, 0.55, 0.95), 2.0)
	CombatFxLib.spawn_impact(target, Color(1.0, 0.15, 0.35, 0.85))
	_flash_attack()
	combat_hit.emit(enemy_name, target.soldier_name, damage, was_alive and not target.is_alive)
	if enemy_archetype == Enemy.Archetype.RIFLEMAN and not _alarm_called:
		_alarm_called = true
		alarm_triggered.emit(self)

func take_damage(amount: int, _from: Node2D = null) -> void:
	if not is_alive:
		return
	current_health = max(0, current_health - amount)
	CombatFxLib.spawn_damage_number(self, amount, Color(1.0, 0.45, 0.35, 1.0))
	if health_bar:
		health_bar.value = current_health
	if body_poly:
		body_poly.modulate = Color(1.2, 0.5, 0.5)
		var tween := create_tween()
		tween.tween_property(body_poly, "modulate", Color.WHITE, 0.12)
	if current_health <= 0:
		_die()

func _die() -> void:
	is_alive = false
	CombatFxLib.spawn_death(self, Color(0.9, 0.15, 0.45, 0.9))
	if body_poly:
		body_poly.modulate = Color(0.25, 0.25, 0.25, 0.5)
	if home_room:
		home_room.unregister_enemy(self)
	died.emit(self)

func _flash_attack() -> void:
	if body_poly:
		var tween := create_tween()
		tween.tween_property(body_poly, "modulate", Color(1.4, 0.4, 0.6), 0.05)
		tween.tween_property(body_poly, "modulate", Color.WHITE, 0.08)

func _apply_aggro_tint(aggro: bool) -> void:
	if not body_poly:
		return
	if aggro:
		body_poly.modulate = Color(1.15, 0.55, 0.55)
	else:
		body_poly.modulate = Color.WHITE

func _update_visuals() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if body_poly:
		match enemy_archetype:
			Enemy.Archetype.SNIPER:
				body_poly.color = Color(0.55, 0.22, 0.82, 1.0)
			Enemy.Archetype.HEAVY:
				body_poly.color = Color(0.72, 0.28, 0.18, 1.0)
			_:
				body_poly.color = Color(0.82, 0.12, 0.48, 1.0)
