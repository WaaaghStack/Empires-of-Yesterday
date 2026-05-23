class_name SoldierUnit
extends Node2D

const CombatFxLib := preload("res://CombatFx.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const MissionStateLib := preload("res://MissionState.gd")
const DynamicPathGraphLib := preload("res://DynamicPathGraph.gd")

signal clicked(unit: SoldierUnit)
signal order_changed(unit: SoldierUnit, order: OrderType.Type)
signal died(unit: SoldierUnit)
signal combat_hit(attacker_name: String, target_name: String, damage: int, killed: bool)
signal health_changed(unit: SoldierUnit)

@export var soldier_name: String = "Marine"
@export var max_health: int = 100
@export var current_health: int = 100
@export var damage: int = 25
@export var speed: float = 120.0
@export var attack_range: float = 140.0
@export var fire_rate: float = 1.0

var marine_class: SoldierResource.MarineClass = SoldierResource.MarineClass.ASSAULT
var ability_name: String = "Adrenaline"
var ability_cooldown_max: float = 12.0
var ability_timer: float = 0.0

var is_selected := false
var is_alive := true
var current_order: OrderType.Type = OrderType.Type.NONE
var order_room: Room = null
var order_target: Vector2 = Vector2.ZERO
var is_moving := false
var awaiting_at_destination := false
var current_target: EnemyUnit = null
var defend_anchor: Vector2 = Vector2.ZERO
var path_queue: Array[Vector2] = []
var path_index: int = 0
var is_searching := false
var search_timer: float = 0.0
var has_searched_room := false
var waiting_at_door: Node2D = null
var snd_rooms: Array = []
var snd_index: int = 0
const SEARCH_DURATION := 1.4
const WAYPOINT_RADIUS := 10.0

var base_damage: int = 25
var adrenaline_timer: float = 0.0
var fire_cooldown: float = 0.0
var source_resource: SoldierResource

@onready var body_poly: Polygon2D = $BodyPoly
@onready var selection_ring: Line2D = $SelectionRing
@onready var health_bar: ProgressBar = $HealthBar
@onready var name_label: Label = $NameLabel
@onready var order_label: Label = $OrderLabel
@onready var path_line: Line2D = $PathLine

func _ready() -> void:
	add_to_group("soldiers")
	update_visuals()
	if selection_ring:
		selection_ring.visible = false
	if path_line:
		path_line.visible = false
	for label_node in [name_label, order_label, health_bar]:
		if label_node:
			label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup_from_resource(resource: SoldierResource) -> void:
	if not resource:
		return
	source_resource = resource
	soldier_name = resource.soldier_name
	marine_class = resource.marine_class
	max_health = resource.health
	current_health = resource.health
	damage = resource.damage
	base_damage = resource.damage
	speed = resource.speed
	attack_range = resource.attack_range
	fire_rate = resource.fire_rate
	ability_name = resource.ability_name
	ability_cooldown_max = resource.ability_cooldown
	update_visuals()

func update_visuals() -> void:
	if name_label:
		name_label.text = soldier_name
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if body_poly:
		body_poly.color = GameTheme.class_color(marine_class)
	if order_label:
		order_label.text = OrderType.get_label(current_order)
	_update_health_color()

func set_selected(now_selected: bool) -> void:
	is_selected = now_selected
	if selection_ring:
		selection_ring.visible = now_selected

func issue_order(order: OrderType.Type, target_pos: Vector2, room: Room = null) -> void:
	current_order = order
	order_room = room
	order_target = target_pos
	defend_anchor = target_pos
	current_target = null
	awaiting_at_destination = false
	is_searching = false
	search_timer = 0.0
	has_searched_room = false
	waiting_at_door = null
	snd_rooms.clear()
	snd_index = 0
	is_moving = true
	if order == OrderType.Type.SEARCH_DESTROY:
		_build_search_destroy_queue(room)
		if snd_rooms.is_empty():
			cancel_order()
			return
		_assign_search_destroy_room(snd_rooms[0])
		_update_snd_label()
	else:
		_rebuild_corridor_path()
	if order_label:
		if order == OrderType.Type.SEARCH_DESTROY:
			_update_snd_label()
		else:
			order_label.text = OrderType.get_label(order)
	_update_path_line(true)
	order_changed.emit(self, order)

func cancel_order() -> void:
	current_order = OrderType.Type.NONE
	order_room = null
	current_target = null
	awaiting_at_destination = false
	is_moving = false
	is_searching = false
	has_searched_room = false
	waiting_at_door = null
	snd_rooms.clear()
	snd_index = 0
	path_queue.clear()
	path_index = 0
	if path_line:
		path_line.visible = false
	if order_label:
		order_label.text = "Idle"

func _mission_paused() -> bool:
	return MissionStateLib.is_unit_actions_frozen(self)

func _process(delta: float) -> void:
	if not is_alive or _mission_paused():
		return
	fire_cooldown = max(0.0, fire_cooldown - delta)
	ability_timer = max(0.0, ability_timer - delta)
	if adrenaline_timer > 0.0:
		adrenaline_timer = max(0.0, adrenaline_timer - delta)
		damage = int(base_damage * 1.5)
	else:
		damage = base_damage
	_refresh_combat_target()
	_process_search(delta)
	_process_movement(delta)
	_process_combat()
	_process_order_behavior()
	_update_snd_label()
	_update_path_line(false)

func _refresh_combat_target() -> void:
	if current_order == OrderType.Type.SEARCH_DESTROY:
		if current_target and current_target.is_alive and _can_see_enemy(current_target):
			return
		current_target = _find_nearest_visible_enemy()
		if current_target and current_target.home_room:
			order_room = current_target.home_room
	elif current_order == OrderType.Type.CLEAR and order_room and has_searched_room:
		current_target = _find_priority_enemy_in_room()
	elif current_order == OrderType.Type.DEFEND and order_room and awaiting_at_destination:
		current_target = _find_enemy_in_defend_room()
	elif current_target and not current_target.is_alive:
		current_target = null

func _get_movement_target() -> Vector2:
	if current_order == OrderType.Type.DEFEND and awaiting_at_destination:
		return defend_anchor
	if _should_chase_in_room() and current_target and current_target.is_alive:
		return current_target.position
	return order_target

func _should_chase_in_room() -> bool:
	if current_order == OrderType.Type.SEARCH_DESTROY:
		return current_target != null and current_target.is_alive
	return current_order == OrderType.Type.CLEAR and has_searched_room and order_room != null

func _get_stop_distance() -> float:
	if current_order == OrderType.Type.DEFEND:
		return 10.0
	if _should_chase_in_room() and current_target:
		return attack_range * 0.72
	return 8.0

func _build_search_destroy_queue(start_room: Room = null) -> void:
	snd_rooms.clear()
	var hostile: Array = []
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and not node.is_spawn_room and node.has_living_enemies():
			hostile.append(node)
	hostile.sort_custom(func(a, b): return position.distance_to(a.position) < position.distance_to(b.position))
	for room in hostile:
		snd_rooms.append(room)
	if start_room and not start_room.is_spawn_room:
		if start_room in snd_rooms:
			snd_rooms.erase(start_room)
		snd_rooms.insert(0, start_room)
	snd_index = 0

func _count_living_enemies() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyUnit and node.is_alive:
			count += 1
	return count

func _any_living_enemies() -> bool:
	return _count_living_enemies() > 0

func _next_hostile_room() -> Room:
	var nearest: Room = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and not node.is_spawn_room and node.has_living_enemies():
			var dist: float = position.distance_to(node.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = node
	return nearest

func _complete_search_destroy() -> void:
	is_moving = false
	is_searching = false
	awaiting_at_destination = true
	current_target = null
	snd_rooms.clear()
	snd_index = 0
	if path_line:
		path_line.visible = false
	if order_label:
		order_label.text = "Area Clear"

func _update_snd_label() -> void:
	if not order_label or current_order != OrderType.Type.SEARCH_DESTROY:
		return
	var remaining: int = _count_living_enemies()
	if remaining > 0:
		order_label.text = "S&D — %d hostile(s)" % remaining
	else:
		order_label.text = "Area Clear"

func _assign_search_destroy_room(room: Room) -> void:
	order_room = room
	order_target = room.position
	has_searched_room = false
	is_searching = false
	search_timer = 0.0
	current_target = null
	awaiting_at_destination = false
	is_moving = true
	_rebuild_corridor_path()

func _advance_search_destroy() -> void:
	if not _any_living_enemies():
		_complete_search_destroy()
		return
	if order_room:
		order_room.mark_searched()
	snd_index += 1
	while snd_index < snd_rooms.size():
		var candidate: Room = snd_rooms[snd_index]
		if candidate.has_living_enemies() or not candidate.is_searched:
			_assign_search_destroy_room(candidate)
			_update_snd_label()
			return
		snd_index += 1
	var next_room := _next_hostile_room()
	if next_room:
		_assign_search_destroy_room(next_room)
		_update_snd_label()
		return
	_build_search_destroy_queue(null)
	snd_index = 0
	if snd_rooms.is_empty():
		_complete_search_destroy()
		return
	_assign_search_destroy_room(snd_rooms[0])
	_update_snd_label()

func _visibility_sets() -> Array:
	var room_list: Array[Room] = []
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room:
			room_list.append(node)
	return [room_list, get_tree().get_nodes_in_group("doors")]

func _can_see_enemy(enemy: EnemyUnit) -> bool:
	if not enemy or not enemy.is_alive:
		return false
	var sets := _visibility_sets()
	return LineOfSightLib.has_line_of_sight(position, enemy.position, sets[0], sets[1])

func _has_spotted_enemies_in_room() -> bool:
	if not order_room:
		return false
	for enemy in order_room.enemies_present:
		if enemy is EnemyUnit and enemy.is_alive and _can_see_enemy(enemy):
			return true
	return false

func _rebuild_corridor_path() -> void:
	var end_pos: Vector2 = order_target
	if order_room:
		end_pos = order_room.position
	path_queue.clear()
	path_index = 0
	var graph: RefCounted = _get_path_graph()
	if graph:
		var blocked := _collect_blocked_path_nodes()
		var from_room := _room_containing(position)
		for point in graph.find_path(position, end_pos, blocked, from_room, order_room):
			path_queue.append(point)
	else:
		path_queue.append(position)
		path_queue.append(end_pos)
	while path_index < path_queue.size() - 1 and position.distance_to(path_queue[path_index]) < WAYPOINT_RADIUS:
		path_index += 1

func _collect_blocked_path_nodes() -> Array[String]:
	var blocked: Array[String] = []
	for node in get_tree().get_nodes_in_group("doors"):
		if node.has_method("get_blocked_path_nodes"):
			for node_id in node.get_blocked_path_nodes():
				if node_id not in blocked:
					blocked.append(node_id)
	return blocked

func _room_containing(pos: Vector2) -> Room:
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and node.contains_local_point(pos, 0.0):
			return node
	return null

func _get_path_graph() -> RefCounted:
	for node in get_tree().get_nodes_in_group("tactical_map"):
		return node.path_graph as RefCounted
	return null

func _process_search(delta: float) -> void:
	if not is_searching:
		return
	search_timer = max(0.0, search_timer - delta)
	if body_poly:
		body_poly.rotation += delta * 2.4
	var spotted := _find_visible_enemy_in_room()
	if spotted:
		is_searching = false
		has_searched_room = true
		current_target = spotted
		is_moving = true
		awaiting_at_destination = false
		if order_label:
			order_label.text = OrderType.get_label(current_order)
		return
	if search_timer > 0.0:
		return
	is_searching = false
	has_searched_room = true
	awaiting_at_destination = false
	if order_label:
		order_label.text = OrderType.get_label(current_order)
	if order_room:
		order_room.mark_searched()
	if _has_spotted_enemies_in_room():
		is_moving = true
		current_target = _find_priority_enemy_in_room()
	elif current_order == OrderType.Type.SEARCH_DESTROY and order_room and order_room.has_living_enemies():
		is_searching = true
		search_timer = SEARCH_DURATION * 0.65
		if order_label:
			order_label.text = "Searching"
	elif current_order == OrderType.Type.SEARCH_DESTROY:
		if not _any_living_enemies():
			_complete_search_destroy()
		else:
			_advance_search_destroy()
	elif order_room and order_room.has_living_enemies():
		is_moving = true
		current_target = _find_priority_enemy_in_room()
	else:
		awaiting_at_destination = true
		is_moving = false

func _start_room_search() -> void:
	if has_searched_room or is_searching:
		return
	is_searching = true
	search_timer = SEARCH_DURATION
	is_moving = false
	awaiting_at_destination = false
	waiting_at_door = null
	if order_label:
		order_label.text = "Searching"

func _process_movement(delta: float) -> void:
	if not is_moving or is_searching:
		return
	if current_order == OrderType.Type.DEFEND and awaiting_at_destination:
		return
	if waiting_at_door:
		if waiting_at_door.blocks_travel():
			waiting_at_door.request_open()
			return
		waiting_at_door = null
		_rebuild_corridor_path()

	if _should_chase_in_room():
		_move_direct_to_target(delta)
		return

	var waypoint: Vector2 = _current_waypoint()
	if waypoint == Vector2.ZERO:
		_on_reached_destination()
		return

	var to_waypoint: Vector2 = waypoint - position
	if to_waypoint.length() <= WAYPOINT_RADIUS:
		path_index += 1
		if path_index >= path_queue.size():
			_on_reached_destination()
		return

	var blocking_door := _find_blocking_door_ahead(waypoint)
	if blocking_door:
		blocking_door.request_open()
		waiting_at_door = blocking_door
		return

	var direction: Vector2 = to_waypoint.normalized()
	position += direction * speed * delta
	_update_facing(direction)

func _current_waypoint() -> Vector2:
	if path_index >= path_queue.size():
		return Vector2.ZERO
	return path_queue[path_index]

func _move_direct_to_target(delta: float) -> void:
	var target: Vector2 = _get_movement_target()
	var to_target: Vector2 = target - position
	var stop_distance: float = _get_stop_distance()
	if to_target.length() <= stop_distance:
		if current_target and current_target.is_alive:
			return
		awaiting_at_destination = true
		is_moving = false
		return
	var direction: Vector2 = to_target.normalized()
	position += direction * speed * delta
	_update_facing(direction)

func _on_reached_destination() -> void:
	if current_order in [OrderType.Type.CLEAR, OrderType.Type.SEARCH_DESTROY] and order_room and not has_searched_room:
		_start_room_search()
		return
	is_moving = false
	awaiting_at_destination = true
	if path_line:
		path_line.visible = false

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

func _update_facing(direction: Vector2) -> void:
	if direction.length() > 0.01 and body_poly:
		body_poly.rotation = direction.angle()

func _update_path_line(force_visible: bool) -> void:
	if not path_line:
		return
	if not force_visible and not is_moving:
		path_line.visible = false
		return
	var points := PackedVector2Array([Vector2.ZERO])
	if _should_chase_in_room():
		points.append(_get_movement_target() - position)
	elif path_queue.size() > path_index:
		for i in range(path_index, path_queue.size()):
			points.append(path_queue[i] - position)
	else:
		points.append(_get_movement_target() - position)
	path_line.points = points
	path_line.visible = points.size() > 1

func _process_combat() -> void:
	if is_searching:
		return
	if current_order == OrderType.Type.NONE and not awaiting_at_destination:
		return
	if not _should_engage():
		return
	var target := _pick_combat_target()
	if not target:
		return
	if position.distance_to(target.position) > attack_range:
		if _should_chase_in_room():
			is_moving = true
			awaiting_at_destination = false
		return
	_face_target(target)
	_attack_target(target)

func _pick_combat_target() -> EnemyUnit:
	if current_target and current_target.is_alive:
		return current_target
	return _find_combat_target()

func _face_target(target: Node2D) -> void:
	if not target or not body_poly:
		return
	var direction := target.position - position
	if direction.length() > 0.01:
		body_poly.rotation = direction.angle()

func _should_engage() -> bool:
	return current_order in [
		OrderType.Type.CLEAR,
		OrderType.Type.SEARCH_DESTROY,
		OrderType.Type.DEFEND,
		OrderType.Type.EXTRACT,
	]

func _find_nearest_visible_enemy() -> EnemyUnit:
	var nearest: EnemyUnit = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyUnit and node.is_alive and _can_see_enemy(node):
			var dist: float = position.distance_to(node.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = node
	return nearest

func _find_visible_enemy_in_room() -> EnemyUnit:
	if not order_room:
		return null
	var nearest: EnemyUnit = null
	var nearest_dist: float = INF
	for enemy in order_room.enemies_present:
		if enemy is EnemyUnit and enemy.is_alive and _can_see_enemy(enemy):
			var dist: float = position.distance_to(enemy.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy
	return nearest

func _find_priority_enemy_in_room() -> EnemyUnit:
	if not order_room:
		return null
	var nearest: EnemyUnit = null
	var nearest_dist: float = INF
	for enemy in order_room.enemies_present:
		if enemy is EnemyUnit and enemy.is_alive and _can_see_enemy(enemy):
			var dist: float = position.distance_to(enemy.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy
	return nearest

func _find_enemy_in_defend_room() -> EnemyUnit:
	if not order_room:
		return null
	var nearest: EnemyUnit = null
	var nearest_dist: float = attack_range
	for enemy in order_room.enemies_present:
		if enemy is EnemyUnit and enemy.is_alive and _can_see_enemy(enemy):
			var dist: float = position.distance_to(enemy.position)
			if dist <= attack_range and dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy
	return nearest

func _find_combat_target() -> EnemyUnit:
	if current_order == OrderType.Type.SEARCH_DESTROY:
		var global_target := _find_nearest_visible_enemy()
		if global_target:
			return global_target
	if order_room and current_order in [OrderType.Type.CLEAR, OrderType.Type.SEARCH_DESTROY, OrderType.Type.DEFEND]:
		var room_target := _find_priority_enemy_in_room() if current_order != OrderType.Type.DEFEND else _find_enemy_in_defend_room()
		if room_target:
			return room_target
	var nearest: EnemyUnit = null
	var nearest_dist: float = attack_range
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyUnit and node.is_alive and _can_see_enemy(node):
			var dist: float = position.distance_to(node.position)
			if dist > attack_range or dist >= nearest_dist:
				continue
			nearest_dist = dist
			nearest = node
	return nearest

func _attack_target(target: EnemyUnit) -> void:
	if fire_cooldown > 0.0:
		return
	var final_damage := damage
	if marine_class == SoldierResource.MarineClass.MARKSMAN and target.position.distance_to(position) > attack_range * 0.65:
		final_damage = int(damage * 1.35)
	if marine_class == SoldierResource.MarineClass.BREACHER and order_room and order_room.has_living_enemies():
		final_damage = int(damage * 1.2)
	var was_alive := target.is_alive
	target.take_damage(final_damage, self)
	fire_cooldown = 1.0 / fire_rate
	CombatFxLib.spawn_shot(self, target.global_position, Color(0.45, 0.85, 1.0, 0.95), 2.5)
	CombatFxLib.spawn_impact(target, Color(1.0, 0.35, 0.25, 0.85))
	_flash_attack()
	combat_hit.emit(
		soldier_name,
		target.enemy_name,
		final_damage,
		was_alive and not target.is_alive
	)

func _process_order_behavior() -> void:
	if current_order == OrderType.Type.SEARCH_DESTROY:
		if not _any_living_enemies():
			_complete_search_destroy()
			return
		if current_target and current_target.is_alive and _can_see_enemy(current_target):
			awaiting_at_destination = false
			is_moving = true
			return
		if order_room and has_searched_room and _has_spotted_enemies_in_room():
			awaiting_at_destination = false
			if not is_moving:
				is_moving = true
		elif order_room and has_searched_room and not order_room.has_living_enemies() and not is_searching:
			_advance_search_destroy()
		elif order_room and has_searched_room and order_room.has_living_enemies() and not is_searching and not _has_spotted_enemies_in_room():
			is_searching = true
			search_timer = SEARCH_DURATION * 0.65
			if order_label:
				order_label.text = "Searching"
		return
	if not order_room:
		return
	match current_order:
		OrderType.Type.CLEAR:
			if order_room.has_living_enemies() and has_searched_room and _has_spotted_enemies_in_room():
				awaiting_at_destination = false
				if not is_moving and _find_priority_enemy_in_room():
					is_moving = true
			elif order_room.has_living_enemies() and has_searched_room and not is_searching and not _has_spotted_enemies_in_room():
				var hunt_target := _find_nearest_visible_enemy()
				if hunt_target:
					current_target = hunt_target
					is_moving = true
					awaiting_at_destination = false
				else:
					is_searching = true
					search_timer = SEARCH_DURATION * 0.65
					if order_label:
						order_label.text = "Searching"
			elif not order_room.has_living_enemies():
				awaiting_at_destination = true
				current_target = null
		OrderType.Type.DEFEND:
			if position.distance_to(defend_anchor) <= 12.0:
				awaiting_at_destination = true
				is_moving = false
			if _find_enemy_in_defend_room():
				current_target = _find_enemy_in_defend_room()

func use_ability(allies: Array[SoldierUnit]) -> bool:
	if ability_timer > 0.0 or not is_alive:
		return false
	var used := false
	match marine_class:
		SoldierResource.MarineClass.ASSAULT:
			adrenaline_timer = 5.0
			fire_cooldown = 0.0
			used = true
		SoldierResource.MarineClass.SUPPORT:
			for ally in allies:
				if ally.is_alive:
					ally.heal(int(ally.max_health * 0.2))
			used = true
		SoldierResource.MarineClass.MARKSMAN:
			var target := _find_combat_target()
			if target:
				var was_alive := target.is_alive
				target.take_damage(int(base_damage * 2.0), self)
				combat_hit.emit(soldier_name, target.enemy_name, int(base_damage * 2.0), was_alive and not target.is_alive)
				used = true
		SoldierResource.MarineClass.BREACHER:
			var victims: Array[EnemyUnit] = []
			if order_room:
				for enemy in order_room.enemies_present:
					if enemy.is_alive and enemy.is_visible_to_player and _can_see_enemy(enemy):
						victims.append(enemy)
			else:
				for node in get_tree().get_nodes_in_group("enemies"):
					if node is EnemyUnit and node.is_alive and node.is_visible_to_player and _can_see_enemy(node):
						if position.distance_to(node.position) <= attack_range:
							victims.append(node)
			if not victims.is_empty():
				for enemy in victims:
					var was_alive := enemy.is_alive
					enemy.take_damage(int(base_damage * 0.75), self)
					combat_hit.emit(soldier_name, enemy.enemy_name, int(base_damage * 0.75), was_alive and not enemy.is_alive)
				used = true
	if not used:
		return false
	ability_timer = ability_cooldown_max
	return true

func heal(amount: int) -> void:
	if not is_alive:
		return
	current_health = min(max_health, current_health + amount)
	if health_bar:
		health_bar.value = current_health
	_update_health_color()
	health_changed.emit(self)

func take_damage(amount: int, _from: Node2D = null) -> void:
	if not is_alive:
		return
	current_health = max(0, current_health - amount)
	if health_bar:
		health_bar.value = current_health
	_update_health_color()
	CombatFxLib.spawn_impact(self, Color(1.0, 0.2, 0.2, 0.7))
	health_changed.emit(self)
	if current_health <= 0:
		_on_death()

func _on_death() -> void:
	is_alive = false
	cancel_order()
	if body_poly:
		body_poly.modulate = Color(0.35, 0.35, 0.35, 0.6)
	if name_label:
		name_label.text = soldier_name + " (KIA)"
	died.emit(self)

func _update_health_color() -> void:
	if not health_bar:
		return
	var percent := float(current_health) / max_health
	if percent > 0.6:
		health_bar.modulate = GameTheme.ACCENT_SUCCESS
	elif percent > 0.3:
		health_bar.modulate = GameTheme.ACCENT_WARN
	else:
		health_bar.modulate = GameTheme.ACCENT_DANGER

func _flash_attack() -> void:
	if body_poly:
		var tween := create_tween()
		tween.tween_property(body_poly, "modulate", Color(1.3, 1.3, 1.3), 0.05)
		tween.tween_property(body_poly, "modulate", Color.WHITE, 0.08)

func _on_input_event(_viewport, event, _shape_idx) -> void:
	if not is_alive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
