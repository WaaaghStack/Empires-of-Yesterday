class_name EnemyUnit
extends Node2D

const CombatFxLib := preload("res://CombatFx.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const MissionStateLib := preload("res://MissionState.gd")
const EnemySpriteFactoryLib := preload("res://EnemySpriteFactory.gd")

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
var enemy_archetype: Enemy.Kind = Enemy.Kind.RIFLEMAN
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
var all_rooms: Array = []
var _tactical_map: Node = null
var _soldier_scan_cache: Array = []
var _soldier_scan_frame: int = -1

const WAYPOINT_RADIUS := 10.0
const HUNT_SPEED_RATIO := 0.25
const SNIPER_CHASE_RANGE_MULT := 0.55
const HEAVY_DOOR_AGGRO_MULT := 1.65
const HEAVY_DOOR_PROXIMITY := 52.0

@onready var body_sprite: Sprite2D = $BodySprite
@onready var body_poly: Polygon2D = $BodyPoly
@onready var health_bar: ProgressBar = $HealthBar

var _facing_dir: String = "south"
var _sprite_archetype: String = "grunt"
var _base_tint: Color = Color.WHITE
var _aggro_active := false

func _ready() -> void:
	add_to_group("enemies")
	_load_enemy_sprites()
	current_health = max_health
	_update_visuals()
	_apply_visibility()
	if body_poly:
		body_poly.visible = false

func _mission_paused() -> bool:
	return MissionStateLib.is_unit_actions_frozen(self)

func _load_enemy_sprites() -> void:
	_sprite_archetype = _archetype_sprite_id()
	if body_sprite:
		_set_facing_from_direction(Vector2(0, 1))
		body_sprite.visible = is_visible_to_player


func _archetype_sprite_id() -> String:
	match enemy_archetype:
		Enemy.Kind.SNIPER:
			return "sniper"
		Enemy.Kind.HEAVY:
			return "heavy"
		_:
			return "grunt"


func _set_facing_from_direction(direction: Vector2) -> void:
	if direction.length_squared() < 0.0001:
		return
	var facing := "east" if direction.x >= 0.0 else "west"
	if absf(direction.y) > absf(direction.x):
		facing = "south" if direction.y >= 0.0 else "north"
	if facing == _facing_dir:
		return
	_facing_dir = facing
	if body_sprite:
		var tex: Texture2D = EnemySpriteFactoryLib.get_texture(_sprite_archetype, facing)
		if tex:
			body_sprite.texture = tex
			body_sprite.scale = EnemySpriteFactoryLib.get_scale_for_texture(tex)


func _body_canvas() -> CanvasItem:
	if body_sprite and body_sprite.visible:
		return body_sprite
	return body_poly


func _set_body_modulate(tint: Color) -> void:
	var node := _body_canvas()
	if node:
		node.modulate = tint


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
	_sprite_archetype = _archetype_sprite_id()
	home_room = room
	if home_room:
		_overwatch_anchor = home_room.position
	_load_enemy_sprites()
	_update_visuals()


func bind_tactical_map(map_node: Node) -> void:
	_tactical_map = map_node
	if map_node and map_node.get("rooms"):
		all_rooms = map_node.rooms


func _physics_process(delta: float) -> void:
	if not is_alive or _mission_paused():
		return
	if not _should_run_ai_this_frame():
		return
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

func _should_run_ai_this_frame() -> bool:
	if is_visible_to_player:
		_ai_skip_frames = 0
		return true
	var interval := _ai_process_interval
	var nearest_dist := _distance_to_nearest_soldier()
	if nearest_dist > 640.0:
		interval = 3
	_ai_skip_frames += 1
	return _ai_skip_frames % interval == 0


func _distance_to_nearest_soldier() -> float:
	var nearest := INF
	for soldier in _living_soldiers_source():
		if soldier is SoldierUnit and soldier.is_alive:
			nearest = minf(nearest, position.distance_to(soldier.position))
	return nearest


func _living_soldiers_source() -> Array:
	var frame := Engine.get_process_frames()
	if _tactical_map and _tactical_map.has_method("get_living_soldiers_cached"):
		return _tactical_map.get_living_soldiers_cached()
	if _tactical_map and _tactical_map.get("entity_index"):
		return _tactical_map.entity_index.get_all_living_soldiers()
	if _soldier_scan_frame == frame:
		return _soldier_scan_cache
	_soldier_scan_frame = frame
	_soldier_scan_cache.clear()
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			_soldier_scan_cache.append(node)
	return _soldier_scan_cache


func _rooms_source() -> Array:
	if not all_rooms.is_empty():
		return all_rooms
	return get_tree().get_nodes_in_group("rooms")


func _get_doors() -> Array:
	if _tactical_map and _tactical_map.get("doors"):
		var cached: Array = _tactical_map.doors
		if not cached.is_empty():
			return cached
	return get_tree().get_nodes_in_group("doors")


func _get_hunt_speed() -> float:
	return _average_soldier_speed() * HUNT_SPEED_RATIO

func _average_soldier_speed() -> float:
	if not is_inside_tree():
		return 56.0
	var total: float = 0.0
	var count: int = 0
	for node in _living_soldiers_source():
		if node is SoldierUnit and node.is_alive:
			total += node.speed
			count += 1
	if count > 0:
		return total / float(count)
	return 56.0

func _chase_soldier(delta: float, target: SoldierUnit) -> void:
	var move_speed := speed
	if enemy_archetype == Enemy.Kind.HEAVY:
		move_speed *= 0.82
	var my_room := _room_containing(position)
	var target_room := _room_containing(target.position)
	if my_room and target_room and my_room == target_room:
		_move_direct(delta, target.position, move_speed)
		return
	if enemy_archetype == Enemy.Kind.HEAVY and _is_near_choke_door() and my_room != target_room:
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
	for node in _rooms_source():
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
	for node in _living_soldiers_source():
		if node is SoldierUnit and node.is_alive and room.contains_local_point(node.position, 10.0):
			return true
	return false

func _any_soldiers_alive() -> bool:
	for node in _living_soldiers_source():
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
	var step: float = move_speed * delta
	position += to_waypoint.normalized() * minf(to_waypoint.length(), step)
	if not _is_walkable(position):
		position = before
		return
	_set_facing_from_direction(to_waypoint)

func _move_direct(delta: float, target_pos: Vector2, move_speed: float) -> void:
	var before: Vector2 = position
	var to_target: Vector2 = target_pos - position
	if to_target.length() <= 0.001:
		return
	position += to_target.normalized() * minf(to_target.length(), move_speed * delta)
	if not _is_walkable(position):
		position = before
		return
	_set_facing_from_direction(to_target)

func _room_containing(pos: Vector2) -> Room:
	for node in _rooms_source():
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
	if _tactical_map and _tactical_map.get("path_graph"):
		return _tactical_map.path_graph as RefCounted
	for node in get_tree().get_nodes_in_group("tactical_map"):
		return node.path_graph as RefCounted
	return null

func _find_blocking_door_ahead(waypoint: Vector2) -> Node2D:
	var move_dir: Vector2 = waypoint - position
	if move_dir.length() < 0.001:
		return null
	for node in _get_doors():
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
	if not target:
		return
	var direction := target.position - position
	if direction.length() > 0.01:
		_set_facing_from_direction(direction)

func _get_effective_aggro_range() -> float:
	var range_val := aggro_range
	if enemy_archetype == Enemy.Kind.HEAVY and _is_near_choke_door():
		range_val *= HEAVY_DOOR_AGGRO_MULT
	return range_val


func _is_near_choke_door() -> bool:
	for node in _get_doors():
		if node is Node2D and position.distance_to(node.position) <= HEAVY_DOOR_PROXIMITY:
			return true
	return false


func _should_hold_overwatch(target: SoldierUnit) -> bool:
	if enemy_archetype != Enemy.Kind.SNIPER or not home_room:
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
	var door_nodes: Array = _get_doors()
	for node in _living_soldiers_source():
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
	if is_focus_marked and is_visible_to_player:
		_set_body_modulate(Color(1.35, 0.95, 0.35))
	else:
		_apply_aggro_tint(_aggro_active)

func set_visible_to_player(now_visible: bool) -> void:
	if is_visible_to_player == now_visible:
		return
	is_visible_to_player = now_visible
	_apply_visibility()
	if is_focus_marked:
		_apply_mark_visual()

func _apply_visibility() -> void:
	visible = is_visible_to_player
	if body_sprite:
		body_sprite.visible = is_visible_to_player
	if health_bar:
		health_bar.visible = is_visible_to_player

func _get_rooms() -> Array[Room]:
	var result: Array[Room] = []
	for node in _rooms_source():
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
	if enemy_archetype == Enemy.Kind.RIFLEMAN and not _alarm_called:
		_alarm_called = true
		alarm_triggered.emit(self)

func take_damage(amount: int, _from: Node2D = null) -> void:
	if not is_alive:
		return
	current_health = max(0, current_health - amount)
	CombatFxLib.spawn_damage_number(self, amount, Color(1.0, 0.45, 0.35, 1.0))
	if health_bar:
		health_bar.value = current_health
	var flash_target := _body_canvas()
	if flash_target:
		_set_body_modulate(Color(1.2, 0.5, 0.5))
		var tween := create_tween()
		tween.tween_property(flash_target, "modulate", _base_tint, 0.12)
	if current_health <= 0:
		_die()

func _die() -> void:
	is_alive = false
	CombatFxLib.spawn_death(self, Color(0.9, 0.15, 0.45, 0.9))
	_set_body_modulate(Color(0.35, 0.35, 0.35, 0.55))
	if home_room:
		home_room.unregister_enemy(self)
	died.emit(self)

func _flash_attack() -> void:
	var flash_target := _body_canvas()
	if flash_target:
		var tween := create_tween()
		tween.tween_property(flash_target, "modulate", Color(1.4, 0.4, 0.6), 0.05)
		tween.tween_property(flash_target, "modulate", _base_tint, 0.08)

func _apply_aggro_tint(aggro: bool) -> void:
	_aggro_active = aggro
	if is_focus_marked and is_visible_to_player:
		return
	if aggro:
		_set_body_modulate(Color(1.15, 0.55, 0.55))
	else:
		_set_body_modulate(_base_tint)

func _update_visuals() -> void:
	_sprite_archetype = _archetype_sprite_id()
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	match enemy_archetype:
		Enemy.Kind.SNIPER:
			_base_tint = Color(0.85, 0.75, 1.0)
		Enemy.Kind.HEAVY:
			_base_tint = Color(1.0, 0.82, 0.72)
		_:
			_base_tint = Color.WHITE
	if body_sprite:
		_set_facing_from_direction(Vector2(0, 1))
		_apply_aggro_tint(_aggro_active)
	elif body_poly:
		match enemy_archetype:
			Enemy.Kind.SNIPER:
				body_poly.color = Color(0.55, 0.22, 0.82, 1.0)
			Enemy.Kind.HEAVY:
				body_poly.color = Color(0.72, 0.28, 0.18, 1.0)
			_:
				body_poly.color = Color(0.82, 0.12, 0.48, 1.0)
