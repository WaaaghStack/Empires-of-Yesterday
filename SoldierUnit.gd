class_name SoldierUnit
extends Node2D

const CombatFxLib := preload("res://CombatFx.gd")
const CombatAudioLib := preload("res://CombatAudio.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const MissionStateLib := preload("res://MissionState.gd")
const DynamicPathGraphLib := preload("res://DynamicPathGraph.gd")
const OrderTypeLib := preload("res://OrderType.gd")
const MissionTaskBoardLib := preload("res://MissionTaskBoard.gd")

signal clicked(unit: SoldierUnit)
signal order_changed(unit: SoldierUnit, order: OrderTypeLib.Type)
signal died(unit: SoldierUnit)
signal combat_hit(attacker_name: String, target_name: String, damage: int, killed: bool)
signal health_changed(unit: SoldierUnit)
signal extracted(unit: SoldierUnit)

@export var soldier_name: String = "Marine"
@export var max_health: int = 100
@export var current_health: int = 100
@export var damage: int = 25
@export var speed: float = 120.0
@export var attack_range: float = 140.0
@export var fire_rate: float = 1.0
@export var defense: int = 6
@export var portrait: Texture2D

var marine_class: SoldierResource.MarineClass = SoldierResource.MarineClass.ASSAULT
var ability_name: String = "Adrenaline"
var ability_cooldown_max: float = 12.0
var ability_timer: float = 0.0

var is_selected := false
var is_alive := true
var current_order: OrderTypeLib.Type = OrderTypeLib.Type.NONE
var preferred_order: OrderTypeLib.Type = OrderTypeLib.Type.CLEAR
var order_room: Room = null
var order_target: Vector2 = Vector2.ZERO
var is_moving := false
var awaiting_at_destination := false
var current_target: Node2D = null
var defend_anchor: Vector2 = Vector2.ZERO
var path_queue: Array[Vector2] = []
var path_index: int = 0
var is_searching := false
var search_timer: float = 0.0
var has_searched_room := false
var waiting_at_door: Node2D = null
var is_extracting := false
var is_extracted := false
var extract_timer: float = 0.0
var _extract_tick_second: int = -1
var snd_rooms: Array = []
var snd_index: int = 0
var explore_rooms: Array = []
var explore_index: int = 0
var _pathing_to_room: Room = null
const SEARCH_DURATION := 1.4
const WAYPOINT_RADIUS := 10.0
const EXTRACT_DURATION := 5.0
const EXTRACT_SPOT_RADIUS := 28.0

var base_damage: int = 25
var base_fire_rate: float = 1.0
var base_ability_cooldown: float = 12.0
var adrenaline_timer: float = 0.0
var repair_aura_timer: float = 0.0
var repair_aura_room: Room = null
var last_ability_detail: String = ""
var fire_cooldown: float = 0.0
var source_resource: SoldierResource
var squad_id: String = "alpha"
var formation_slot: int = 0
var task_board: MissionTaskBoardLib = null
var all_rooms: Array = []

const MIN_UNIT_SEPARATION := 28.0

const ADRENALINE_DURATION := 6.0
const REPAIR_AURA_DURATION := 8.0
const REPAIR_AURA_HEAL_PER_SEC := 0.025
const FOCUS_MARK_DURATION := 10.0

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
	current_health = resource.get_deploy_hp()
	if current_health <= 0 and not resource.is_kia:
		current_health = resource.health
	damage = resource.damage
	base_damage = resource.damage
	speed = resource.get_effective_speed()
	base_fire_rate = resource.fire_rate
	fire_rate = resource.get_effective_fire_rate()
	attack_range = resource.attack_range
	defense = resource.defense
	ability_name = resource.ability_name
	base_ability_cooldown = resource.ability_cooldown
	ability_cooldown_max = resource.get_effective_ability_cooldown()
	preferred_order = resource.default_order
	portrait = resource.portrait
	squad_id = resource.squad_id if resource.squad_id != "" else "alpha"
	update_visuals()

func update_visuals() -> void:
	if name_label:
		name_label.text = soldier_name
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if body_poly:
		var tint := GameTheme.class_color(marine_class)
		if squad_id != "":
			tint = tint.lerp(GameTheme.squad_color(squad_id), 0.35)
		body_poly.color = tint
	if order_label:
		order_label.text = OrderTypeLib.get_label(current_order)
	_update_health_color()

func set_selected(now_selected: bool) -> void:
	is_selected = now_selected
	if selection_ring:
		selection_ring.visible = now_selected

func issue_order(order: OrderTypeLib.Type, target_pos: Vector2, room: Room = null) -> void:
	current_order = order
	order_room = room
	order_target = target_pos
	defend_anchor = target_pos
	current_target = null
	awaiting_at_destination = false
	is_searching = false
	search_timer = 0.0
	has_searched_room = false
	is_extracting = false
	extract_timer = 0.0
	_extract_tick_second = -1
	waiting_at_door = null
	snd_rooms.clear()
	snd_index = 0
	explore_rooms.clear()
	explore_index = 0
	_pathing_to_room = null
	is_moving = true
	if order == OrderTypeLib.Type.SEARCH_DESTROY:
		_build_search_destroy_queue(room)
		if snd_rooms.is_empty():
			cancel_order()
			return
		_assign_search_destroy_room(snd_rooms[0])
		_update_snd_label()
	elif order == OrderTypeLib.Type.OBJECTIVE:
		_apply_objective_doctrine(room)
		if current_order == OrderTypeLib.Type.NONE:
			return
	elif order == OrderTypeLib.Type.EXPLORE:
		_build_explore_queue()
		explore_index = 0
		if explore_rooms.is_empty():
			cancel_order()
			return
		_advance_explore()
		_update_explore_label()
	else:
		_rebuild_corridor_path()
	if order_label:
		if order == OrderTypeLib.Type.SEARCH_DESTROY:
			_update_snd_label()
		elif order == OrderTypeLib.Type.EXPLORE:
			_update_explore_label()
		else:
			order_label.text = OrderTypeLib.get_label(order)
	_update_path_line(true)
	order_changed.emit(self, order)

func cancel_order() -> void:
	current_order = OrderTypeLib.Type.NONE
	order_room = null
	current_target = null
	awaiting_at_destination = false
	is_moving = false
	is_searching = false
	has_searched_room = false
	is_extracting = false
	extract_timer = 0.0
	_extract_tick_second = -1
	waiting_at_door = null
	snd_rooms.clear()
	snd_index = 0
	explore_rooms.clear()
	explore_index = 0
	path_queue.clear()
	path_index = 0
	_pathing_to_room = null
	if path_line:
		path_line.visible = false
	if order_label:
		order_label.text = "Idle"

func _mission_paused() -> bool:
	return MissionStateLib.is_unit_actions_frozen(self)

func _process(delta: float) -> void:
	if not is_alive or is_extracted or _mission_paused():
		return
	fire_cooldown = max(0.0, fire_cooldown - delta)
	ability_timer = max(0.0, ability_timer - delta)
	MissionStateLib.tick_squad_mark(delta)
	if adrenaline_timer > 0.0:
		adrenaline_timer = max(0.0, adrenaline_timer - delta)
		damage = int(base_damage * 1.2)
	else:
		damage = base_damage
	if repair_aura_timer > 0.0:
		repair_aura_timer = max(0.0, repair_aura_timer - delta)
		_tick_repair_aura(delta)
		if repair_aura_timer <= 0.0:
			repair_aura_room = null
	elif repair_aura_room:
		repair_aura_room = null
	if adrenaline_timer > 0.0 and source_resource:
		speed = source_resource.get_effective_speed() * 1.35
	elif source_resource:
		speed = source_resource.get_effective_speed()
	_refresh_combat_target()
	_process_search(delta)
	_process_movement(delta)
	_process_combat()
	_process_extract(delta)
	_process_order_behavior()
	_apply_unit_separation(delta)
	_update_snd_label()
	_update_explore_label()
	_update_path_line(false)

func _refresh_combat_target() -> void:
	if current_order == OrderTypeLib.Type.SEARCH_DESTROY:
		if current_target and _target_is_alive(current_target) and _can_see_combat_target(current_target):
			return
		current_target = _find_nearest_visible_enemy()
		if not current_target:
			current_target = _find_nearest_attackable_hive()
		if current_target is EnemyUnit and current_target.home_room:
			order_room = current_target.home_room
		elif current_target is Hive and current_target.home_room:
			order_room = current_target.home_room
	elif current_order == OrderTypeLib.Type.CLEAR and order_room and has_searched_room:
		current_target = _find_priority_combat_target_in_room()
	elif current_order == OrderTypeLib.Type.DEFEND and order_room and awaiting_at_destination:
		current_target = _find_defend_combat_target()
	elif current_target and not _target_is_alive(current_target):
		current_target = null

func _get_movement_target() -> Vector2:
	if current_order == OrderTypeLib.Type.DEFEND and awaiting_at_destination:
		return defend_anchor
	if _should_chase_in_room() and current_target and _target_is_alive(current_target):
		return current_target.position
	return order_target

func _should_chase_in_room() -> bool:
	if not current_target or not _target_is_alive(current_target):
		return false
	var target_room := _room_containing(current_target.position)
	if adrenaline_timer > 0.0 and order_room:
		if target_room == order_room and _can_see_combat_target(current_target):
			return true
	var my_room := _room_containing(position)
	if my_room and target_room:
		return my_room == target_room
	if current_order == OrderTypeLib.Type.CLEAR and has_searched_room and order_room:
		return order_room.contains_local_point(current_target.position, 0.0)
	return false

func _is_in_corridor() -> bool:
	return _is_in_corridor_at(position)

func _is_in_corridor_at(pos: Vector2) -> bool:
	var graph: RefCounted = _get_path_graph()
	if graph and graph.has_method("is_in_corridor"):
		return graph.is_in_corridor(pos)
	return false

func _is_walkable(pos: Vector2) -> bool:
	if _is_in_corridor_at(pos):
		return true
	if _room_containing(pos) != null:
		return true
	return _near_path_node(pos, 18.0)

func _near_path_node(pos: Vector2, radius: float) -> bool:
	var graph: RefCounted = _get_path_graph()
	if not graph or not graph.nodes:
		return false
	for node_pos in graph.nodes.values():
		if pos.distance_to(node_pos) <= radius:
			return true
	return false

func _needs_corridor_path() -> bool:
	if not order_room:
		return false
	if _should_chase_in_room():
		return false
	var my_room := _room_containing(position)
	return my_room != order_room

func _move_along_path(delta: float, waypoint: Vector2) -> void:
	var to_waypoint: Vector2 = waypoint - position
	if to_waypoint.length() <= 0.001:
		return
	var before: Vector2 = position
	var step: float = speed * delta
	if _is_in_corridor_at(position) or _is_in_corridor_at(waypoint):
		if absf(to_waypoint.x) >= absf(to_waypoint.y):
			position.x += signf(to_waypoint.x) * minf(absf(to_waypoint.x), step)
		else:
			position.y += signf(to_waypoint.y) * minf(absf(to_waypoint.y), step)
	elif _room_containing(position):
		position += to_waypoint.normalized() * minf(to_waypoint.length(), step)
	else:
		if absf(to_waypoint.x) >= absf(to_waypoint.y):
			position.x += signf(to_waypoint.x) * minf(absf(to_waypoint.x), step)
		else:
			position.y += signf(to_waypoint.y) * minf(absf(to_waypoint.y), step)
	if not _is_walkable(position):
		position = before
		return
	_update_facing(to_waypoint)

func _rebuild_path_to_room(room: Room) -> void:
	if not room:
		return
	if room == _pathing_to_room and not path_queue.is_empty():
		return
	order_room = room
	order_target = room.position
	_pathing_to_room = room
	_rebuild_corridor_path()

func _get_stop_distance() -> float:
	if current_order == OrderTypeLib.Type.DEFEND:
		return 10.0
	if _should_chase_in_room() and current_target:
		return attack_range * 0.72
	return 8.0

func _apply_objective_doctrine(start_room: Room = null) -> void:
	var template := "standard"
	for node in get_tree().get_nodes_in_group("tactical_map"):
		if node.has_method("get_objective_template"):
			template = node.get_objective_template()
			break
	match template:
		"silent_extract", "scavenge":
			current_order = OrderTypeLib.Type.EXPLORE
			_build_explore_queue()
			explore_index = 0
			if explore_rooms.is_empty():
				cancel_order()
				return
			_advance_explore()
			_update_explore_label()
		"hold_purge":
			current_order = OrderTypeLib.Type.DEFEND
			var hold: Room = _find_hold_room()
			if hold:
				order_room = hold
				order_target = hold.get_formation_position(formation_slot, 4, 0)
				defend_anchor = order_target
				_rebuild_corridor_path()
			else:
				current_order = OrderTypeLib.Type.SEARCH_DESTROY
				_build_search_destroy_queue(start_room)
				if snd_rooms.is_empty():
					cancel_order()
					return
				_assign_search_destroy_room(snd_rooms[0])
		"hive_purge":
			current_order = OrderTypeLib.Type.SEARCH_DESTROY
			_build_search_destroy_queue(start_room)
			if snd_rooms.is_empty():
				cancel_order()
				return
			_assign_search_destroy_room(snd_rooms[0])
		_:
			current_order = OrderTypeLib.Type.SEARCH_DESTROY
			_build_search_destroy_queue(start_room)
			if snd_rooms.is_empty():
				cancel_order()
				return
			_assign_search_destroy_room(snd_rooms[0])


func _find_hold_room() -> Room:
	for node in _rooms_source():
		if node is Room and node.get_meta("hold_room", false):
			return node
	return null


func _rooms_source() -> Array:
	if not all_rooms.is_empty():
		return all_rooms
	return get_tree().get_nodes_in_group("rooms")


func _apply_unit_separation(_delta: float) -> void:
	var my_room := _room_containing(position)
	if not my_room:
		return
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node == self or not node is SoldierUnit:
			continue
		var other: SoldierUnit = node as SoldierUnit
		if not other.is_alive or other.is_extracted:
			continue
		if other.squad_id != squad_id:
			continue
		var dist: float = position.distance_to(other.position)
		if dist < MIN_UNIT_SEPARATION and dist > 0.01:
			var push: Vector2 = (position - other.position).normalized() * (MIN_UNIT_SEPARATION - dist) * 0.5
			var candidate: Vector2 = position + push
			if my_room.contains_local_point(candidate, 0.0):
				position = candidate


func _build_search_destroy_queue(start_room: Room = null) -> void:
	snd_rooms.clear()
	if task_board:
		var squad_units: Array = []
		for node in get_tree().get_nodes_in_group("soldiers"):
			if node is SoldierUnit and (node as SoldierUnit).squad_id == squad_id and node.is_alive:
				squad_units.append(node)
		var shared: Array = task_board.build_snd_queue(squad_units, _rooms_source(), start_room, squad_id)
		for room in shared:
			if room is Room:
				snd_rooms.append(room)
		if formation_slot < snd_rooms.size():
			var my_room: Room = snd_rooms[formation_slot % snd_rooms.size()]
			snd_rooms = [my_room]
			for i in range(shared.size()):
				var r = shared[i]
				if r != my_room and not task_board.is_room_claimed(r, self):
					snd_rooms.append(r)
		snd_index = 0
		return
	var hostile: Array = []
	for node in _rooms_source():
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
	if not order_label or current_order != OrderTypeLib.Type.SEARCH_DESTROY:
		return
	var remaining: int = _count_living_enemies()
	if remaining > 0:
		order_label.text = "S&D — %d hostile(s)" % remaining
	else:
		order_label.text = "Area Clear"

func _build_explore_queue() -> void:
	explore_rooms.clear()
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and not node.is_spawn_room and not node.is_searched:
			explore_rooms.append(node)
	explore_rooms.sort_custom(func(a, b): return position.distance_to(a.position) < position.distance_to(b.position))

func _count_unexplored_rooms() -> int:
	var count: int = 0
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and not node.is_spawn_room and not node.is_searched:
			count += 1
	return count

func _update_explore_label() -> void:
	if not order_label or current_order != OrderTypeLib.Type.EXPLORE:
		return
	var remaining: int = _count_unexplored_rooms()
	if remaining > 0:
		order_label.text = "Explore — %d sector(s)" % remaining
	else:
		order_label.text = "Sweep Complete"

func _assign_explore_room(room: Room) -> void:
	order_room = room
	order_target = room.position
	has_searched_room = false
	is_searching = false
	search_timer = 0.0
	current_target = null
	awaiting_at_destination = false
	is_moving = true
	_pathing_to_room = null
	_rebuild_corridor_path()

func _advance_explore() -> void:
	while explore_index < explore_rooms.size():
		var candidate: Room = explore_rooms[explore_index]
		explore_index += 1
		if candidate.is_searched:
			continue
		_assign_explore_room(candidate)
		_update_explore_label()
		return
	_complete_explore()

func _complete_explore() -> void:
	is_moving = false
	is_searching = false
	awaiting_at_destination = true
	current_target = null
	explore_rooms.clear()
	explore_index = 0
	if path_line:
		path_line.visible = false
	if order_label:
		order_label.text = "Sweep Complete"

func _assign_search_destroy_room(room: Room) -> void:
	if task_board:
		task_board.claim_room(room, self, "snd")
	order_room = room
	order_target = room.get_formation_position(formation_slot, 4, 0)
	has_searched_room = false
	is_searching = false
	search_timer = 0.0
	current_target = null
	awaiting_at_destination = false
	is_moving = true
	_pathing_to_room = null
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
	if task_board:
		var fallback: Room = task_board.next_unclaimed_hostile(position, self, _rooms_source())
		if fallback:
			_assign_search_destroy_room(fallback)
			_update_snd_label()
			return
	_build_search_destroy_queue(null)
	snd_index = 0
	if snd_rooms.is_empty():
		_complete_search_destroy()
		return
	_assign_search_destroy_room(snd_rooms[0])
	_update_snd_label()

func _get_visible_rooms() -> Array[Room]:
	var room_list: Array[Room] = []
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room:
			room_list.append(node)
	return room_list

func _can_see_enemy(enemy: EnemyUnit) -> bool:
	if not enemy or not enemy.is_alive:
		return false
	var door_nodes: Array = get_tree().get_nodes_in_group("doors")
	return LineOfSightLib.has_line_of_sight(position, enemy.position, _get_visible_rooms(), door_nodes)

func _target_is_alive(target: Node2D) -> bool:
	return MissionStateLib.is_attackable_target(target)

func _can_see_combat_target(target: Node2D) -> bool:
	if not _target_is_alive(target):
		return false
	if target is EnemyUnit:
		return _can_see_enemy(target as EnemyUnit)
	if target is Hive:
		var door_nodes: Array = get_tree().get_nodes_in_group("doors")
		return LineOfSightLib.has_line_of_sight(position, target.position, _get_visible_rooms(), door_nodes)
	return false

func _combat_target_name(target: Node2D) -> String:
	if target is EnemyUnit:
		return (target as EnemyUnit).enemy_name
	if target is Hive:
		return (target as Hive).hive_name
	return "Target"

func _hive_in_room(room: Room) -> Hive:
	if not room:
		return null
	var hive = room.get_meta("hive", null)
	if hive is Hive and hive.is_attackable():
		return hive
	return null

func _find_attackable_hive_in_room(room: Room) -> Hive:
	var hive := _hive_in_room(room)
	if hive and _can_see_combat_target(hive):
		return hive
	return null

func _find_nearest_attackable_hive() -> Hive:
	var nearest: Hive = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("hives"):
		if node is Hive and node.is_attackable() and _can_see_combat_target(node):
			var dist: float = position.distance_to(node.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = node
	return nearest

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
	_pathing_to_room = null
	var graph: RefCounted = _get_path_graph()
	if graph:
		var from_room := _room_containing(position)
		var target_room: Room = order_room if order_room else from_room
		var blocked: Array[String] = []
		for point in graph.find_path(position, end_pos, blocked, from_room, target_room):
			path_queue.append(point)
	_pathing_to_room = order_room
	while path_index < path_queue.size() - 1 and position.distance_to(path_queue[path_index]) < WAYPOINT_RADIUS:
		path_index += 1
	_prime_doors_on_route()

func _prime_doors_on_route() -> void:
	if path_queue.is_empty():
		return
	var focus: Vector2 = path_queue[path_index] if path_index < path_queue.size() else order_target
	for node in get_tree().get_nodes_in_group("doors"):
		if not node.has_method("request_open"):
			continue
		var door_pos: Vector2 = (node as Node2D).position
		if door_pos.distance_to(focus) > 80.0 and door_pos.distance_to(position) > 88.0:
			continue
		node.request_open()

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
		if node is Room and node.contains_local_point(pos, 10.0):
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
		body_poly.rotation = sin((SEARCH_DURATION - search_timer) * 5.0) * 0.45
	var spotted := _find_visible_enemy_in_room()
	if spotted:
		is_searching = false
		has_searched_room = true
		current_target = spotted
		is_moving = true
		awaiting_at_destination = false
		if order_label:
			order_label.text = OrderTypeLib.get_label(current_order)
		return
	if search_timer > 0.0:
		return
	is_searching = false
	has_searched_room = true
	awaiting_at_destination = false
	if order_label:
		order_label.text = OrderTypeLib.get_label(current_order)
	if order_room:
		order_room.mark_searched()
	if _has_spotted_enemies_in_room() or _find_attackable_hive_in_room(order_room):
		is_moving = true
		current_target = _find_priority_combat_target_in_room()
	elif current_order == OrderTypeLib.Type.SEARCH_DESTROY and order_room and order_room.has_living_enemies():
		is_searching = true
		search_timer = SEARCH_DURATION * 0.65
		if order_label:
			order_label.text = "Searching"
	elif current_order == OrderTypeLib.Type.SEARCH_DESTROY:
		if not _any_living_enemies():
			_complete_search_destroy()
		else:
			_advance_search_destroy()
	elif current_order == OrderTypeLib.Type.EXPLORE:
		if order_room and (order_room.has_living_enemies() or _hive_in_room(order_room)):
			is_moving = true
			current_target = _find_priority_combat_target_in_room()
		else:
			_advance_explore()
	elif order_room and (order_room.has_living_enemies() or _hive_in_room(order_room)):
		is_moving = true
		current_target = _find_priority_combat_target_in_room()
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
	if current_order == OrderTypeLib.Type.DEFEND and awaiting_at_destination:
		return
	if _needs_corridor_path() and path_queue.is_empty():
		_rebuild_corridor_path()
		if path_queue.is_empty():
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

	_move_along_path(delta, waypoint)

func _current_waypoint() -> Vector2:
	if path_index >= path_queue.size():
		return Vector2.ZERO
	return path_queue[path_index]

func _move_direct_to_target(delta: float) -> void:
	if not _should_chase_in_room():
		return
	var target: Vector2 = _get_movement_target()
	var to_target: Vector2 = target - position
	var stop_distance: float = _get_stop_distance()
	if to_target.length() <= stop_distance:
		if current_target and _target_is_alive(current_target):
			return
		awaiting_at_destination = true
		is_moving = false
		return
	var before: Vector2 = position
	var direction: Vector2 = to_target.normalized()
	position += direction * speed * delta
	if not _is_walkable(position):
		position = before
		return
	_update_facing(direction)

func _on_reached_destination() -> void:
	if current_order in [OrderTypeLib.Type.CLEAR, OrderTypeLib.Type.SEARCH_DESTROY, OrderTypeLib.Type.EXPLORE] and order_room and not has_searched_room:
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
	if current_order == OrderTypeLib.Type.NONE and not awaiting_at_destination:
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
		else:
			var target_room := _room_containing(target.position)
			if target_room:
				_rebuild_path_to_room(target_room)
				is_moving = true
				awaiting_at_destination = false
		return
	_face_target(target)
	_attack_target(target)

func _pick_combat_target() -> Node2D:
	if current_target and _target_is_alive(current_target):
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
		OrderTypeLib.Type.CLEAR,
		OrderTypeLib.Type.SEARCH_DESTROY,
		OrderTypeLib.Type.DEFEND,
		OrderTypeLib.Type.EXTRACT,
		OrderTypeLib.Type.EXPLORE,
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

func _find_priority_combat_target_in_room() -> Node2D:
	var marked := _find_squad_marked_target()
	if marked and order_room:
		if marked is EnemyUnit and marked.home_room == order_room:
			return marked
		if marked is Hive and marked.home_room == order_room:
			return marked
	if not order_room:
		return null
	var hive := _find_attackable_hive_in_room(order_room)
	if hive:
		return hive
	return _find_priority_enemy_in_room()

func _find_defend_combat_target() -> Node2D:
	if not order_room:
		return null
	var marked := _find_squad_marked_target()
	if marked:
		if marked is EnemyUnit and marked.home_room == order_room and position.distance_to(marked.position) <= attack_range:
			return marked
		if marked is Hive and marked.home_room == order_room and position.distance_to(marked.position) <= attack_range:
			return marked
	var hive := _find_attackable_hive_in_room(order_room)
	if hive and position.distance_to(hive.position) <= attack_range:
		return hive
	return _find_enemy_in_defend_room()

func _find_priority_enemy_in_room() -> EnemyUnit:
	var marked := _find_squad_marked_target()
	if marked is EnemyUnit and order_room and marked.home_room == order_room:
		return marked
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
	var marked := _find_squad_marked_target()
	if marked is EnemyUnit and marked.home_room == order_room:
		if position.distance_to(marked.position) <= attack_range:
			return marked
	var nearest: EnemyUnit = null
	var nearest_dist: float = attack_range
	for enemy in order_room.enemies_present:
		if enemy is EnemyUnit and enemy.is_alive and _can_see_enemy(enemy):
			var dist: float = position.distance_to(enemy.position)
			if dist <= attack_range and dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy
	return nearest

func _find_combat_target() -> Node2D:
	var marked := _find_squad_marked_target()
	if marked:
		return marked
	if current_order == OrderTypeLib.Type.SEARCH_DESTROY:
		var global_target := _find_nearest_visible_enemy()
		if global_target:
			return global_target
		var global_hive := _find_nearest_attackable_hive()
		if global_hive:
			return global_hive
	if order_room and current_order in [OrderTypeLib.Type.CLEAR, OrderTypeLib.Type.SEARCH_DESTROY, OrderTypeLib.Type.DEFEND]:
		var room_target := _find_priority_combat_target_in_room() if current_order != OrderTypeLib.Type.DEFEND else _find_defend_combat_target()
		if room_target:
			return room_target
	var nearest: Node2D = null
	var nearest_dist: float = attack_range
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyUnit and node.is_alive and _can_see_enemy(node):
			var dist: float = position.distance_to(node.position)
			if dist > attack_range or dist >= nearest_dist:
				continue
			nearest_dist = dist
			nearest = node
	for node in get_tree().get_nodes_in_group("hives"):
		if node is Hive and node.is_attackable() and _can_see_combat_target(node):
			var dist: float = position.distance_to(node.position)
			if dist > attack_range or dist >= nearest_dist:
				continue
			nearest_dist = dist
			nearest = node
	return nearest

func _attack_target(target: Node2D) -> void:
	if fire_cooldown > 0.0 or not _target_is_alive(target):
		return
	var final_damage := damage
	if marine_class == SoldierResource.MarineClass.MARKSMAN and target.position.distance_to(position) > attack_range * 0.65:
		final_damage = int(damage * 1.35)
	var room_has_hostiles := order_room and (order_room.has_living_enemies() or _hive_in_room(order_room) != null)
	if marine_class == SoldierResource.MarineClass.BREACHER and room_has_hostiles:
		final_damage = int(damage * 1.2)
	var was_alive := _target_is_alive(target)
	if target is EnemyUnit:
		(target as EnemyUnit).take_damage(final_damage, self)
	elif target is Hive:
		(target as Hive).take_damage(final_damage, self)
	else:
		return
	fire_cooldown = 1.0 / fire_rate
	CombatFxLib.spawn_shot(self, target.global_position, Color(0.45, 0.85, 1.0, 0.95), 2.5)
	CombatFxLib.spawn_impact(target, Color(1.0, 0.35, 0.25, 0.85))
	_flash_attack()
	combat_hit.emit(
		soldier_name,
		_combat_target_name(target),
		final_damage,
		was_alive and not _target_is_alive(target)
	)

func _process_order_behavior() -> void:
	if current_order == OrderTypeLib.Type.SEARCH_DESTROY:
		if not _any_living_enemies():
			_complete_search_destroy()
			return
		if current_target and _target_is_alive(current_target) and _can_see_combat_target(current_target):
			if _should_chase_in_room():
				awaiting_at_destination = false
				is_moving = true
			else:
				var target_room := _room_containing(current_target.position)
				if target_room:
					_rebuild_path_to_room(target_room)
				is_moving = true
				awaiting_at_destination = false
			return
		if order_room and has_searched_room and _has_spotted_enemies_in_room():
			awaiting_at_destination = false
			if not is_moving:
				is_moving = true
		elif order_room and has_searched_room and not order_room.has_living_enemies() and not is_searching:
			_advance_search_destroy()
		elif order_room and not has_searched_room and not is_searching:
			awaiting_at_destination = false
			is_moving = true
			if path_queue.is_empty():
				_pathing_to_room = null
				_rebuild_corridor_path()
		elif order_room and has_searched_room and order_room.has_living_enemies() and not is_searching and not _has_spotted_enemies_in_room():
			is_searching = true
			search_timer = SEARCH_DURATION * 0.65
			if order_label:
				order_label.text = "Searching"
		return
	if not order_room:
		return
	match current_order:
		OrderTypeLib.Type.CLEAR:
			var room_has_hive := _hive_in_room(order_room) != null
			if (order_room.has_living_enemies() or room_has_hive) and has_searched_room and _has_spotted_enemies_in_room():
				awaiting_at_destination = false
				if not is_moving and _find_priority_combat_target_in_room():
					is_moving = true
			elif (order_room.has_living_enemies() or room_has_hive) and has_searched_room and not is_searching and not _has_spotted_enemies_in_room():
				var hunt_target := _find_nearest_visible_enemy()
				if hunt_target:
					current_target = hunt_target
					is_moving = true
					awaiting_at_destination = false
				else:
					var hive_target := _find_attackable_hive_in_room(order_room)
					if hive_target:
						current_target = hive_target
						is_moving = true
						awaiting_at_destination = false
					else:
						is_searching = true
						search_timer = SEARCH_DURATION * 0.65
						if order_label:
							order_label.text = "Searching"
			elif not order_room.has_living_enemies() and not room_has_hive:
				awaiting_at_destination = true
				current_target = null
		OrderTypeLib.Type.DEFEND:
			if position.distance_to(defend_anchor) <= 12.0:
				awaiting_at_destination = true
				is_moving = false
			if _find_defend_combat_target():
				current_target = _find_defend_combat_target()
		OrderTypeLib.Type.EXPLORE:
			if order_room.is_searched and has_searched_room and not is_searching:
				_advance_explore()
			elif order_room.has_living_enemies() and has_searched_room and _has_spotted_enemies_in_room():
				awaiting_at_destination = false
				if not is_moving and _find_priority_combat_target_in_room():
					is_moving = true
			elif order_room.has_living_enemies() and has_searched_room and not is_searching and not _has_spotted_enemies_in_room():
				is_searching = true
				search_timer = SEARCH_DURATION * 0.65
				if order_label:
					order_label.text = "Searching"
			elif not order_room.has_living_enemies() and has_searched_room and not is_searching:
				_advance_explore()
		OrderTypeLib.Type.EXTRACT:
			if is_extracted:
				return
			if order_room and order_room.is_extraction_room and not order_room.contains_local_point(position, EXTRACT_SPOT_RADIUS):
				is_extracting = false
				extract_timer = 0.0
				awaiting_at_destination = false
				is_moving = true

func _process_extract(delta: float) -> void:
	if current_order != OrderTypeLib.Type.EXTRACT or is_extracted:
		return
	if not order_room or not order_room.is_extraction_room:
		is_extracting = false
		extract_timer = 0.0
		return
	if not order_room.contains_local_point(position, EXTRACT_SPOT_RADIUS):
		is_extracting = false
		extract_timer = EXTRACT_DURATION
		if order_label and not is_moving:
			order_label.text = OrderTypeLib.get_label(current_order)
		return
	if not awaiting_at_destination and is_moving:
		return
	awaiting_at_destination = true
	is_moving = false
	if not is_extracting:
		is_extracting = true
		extract_timer = EXTRACT_DURATION
		_extract_tick_second = -1
		CombatAudioLib.play_extract_channel(self)
	extract_timer = max(0.0, extract_timer - delta)
	var tick_second: int = int(ceil(extract_timer))
	if tick_second != _extract_tick_second and tick_second > 0:
		_extract_tick_second = tick_second
		CombatAudioLib.play_extract_countdown_tick(self)
	if order_label:
		order_label.text = "Extracting %.1fs" % extract_timer
	if extract_timer > 0.0:
		return
	_complete_extraction()

func _complete_extraction() -> void:
	is_extracted = true
	is_extracting = false
	CombatAudioLib.play_extract_complete(self)
	is_moving = false
	awaiting_at_destination = true
	current_order = OrderTypeLib.Type.NONE
	current_target = null
	if path_line:
		path_line.visible = false
	if body_poly:
		body_poly.visible = false
	if selection_ring:
		selection_ring.visible = false
	if health_bar:
		health_bar.visible = false
	if order_label:
		order_label.text = "Extracted"
	extracted.emit(self)
	order_changed.emit(self, OrderTypeLib.Type.NONE)

func _find_squad_marked_target() -> Node2D:
	var marked: Node2D = MissionStateLib.squad_marked_target
	if not marked or not _target_is_alive(marked) or not _can_see_combat_target(marked):
		return null
	return marked

func _tick_repair_aura(delta: float) -> void:
	if not repair_aura_room:
		return
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			if repair_aura_room.contains_local_point(node.position, 12.0):
				node.heal(maxi(1, int(node.max_health * REPAIR_AURA_HEAL_PER_SEC * delta)))

func use_ability(_allies: Array[SoldierUnit]) -> bool:
	if ability_timer > 0.0 or not is_alive:
		return false
	last_ability_detail = ""
	var used := false
	match marine_class:
		SoldierResource.MarineClass.ASSAULT:
			adrenaline_timer = ADRENALINE_DURATION
			fire_cooldown = 0.0
			if order_room:
				is_moving = true
				awaiting_at_destination = false
				current_target = _find_visible_enemy_in_room()
				if not current_target:
					current_target = _find_nearest_visible_enemy()
			last_ability_detail = "aggressive sector push (%.0fs)" % ADRENALINE_DURATION
			used = true
		SoldierResource.MarineClass.SUPPORT:
			if current_order != OrderTypeLib.Type.DEFEND or not order_room or not awaiting_at_destination:
				last_ability_detail = "requires Defend order in sector"
				return false
			repair_aura_timer = REPAIR_AURA_DURATION
			repair_aura_room = order_room
			last_ability_detail = "repair aura in %s (%.0fs)" % [order_room.room_name, REPAIR_AURA_DURATION]
			used = true
		SoldierResource.MarineClass.MARKSMAN:
			var target := _find_combat_target()
			if not target:
				target = _find_nearest_visible_enemy()
			if not target:
				target = _find_nearest_attackable_hive()
			if not target and order_room:
				target = _find_attackable_hive_in_room(order_room)
			if target:
				MissionStateLib.set_squad_mark(target, FOCUS_MARK_DURATION)
				current_target = target
				last_ability_detail = "squad mark on %s (%.0fs)" % [_combat_target_name(target), FOCUS_MARK_DURATION]
				used = true
		SoldierResource.MarineClass.BREACHER:
			var door_count := _breach_nearby_doors(attack_range + 24.0)
			var blast_targets: Array[Node2D] = []
			var strike_room := order_room if order_room else _room_containing(position)
			if strike_room:
				for enemy in strike_room.enemies_present:
					if enemy is EnemyUnit and enemy.is_alive and enemy.is_visible_to_player and _can_see_enemy(enemy):
						blast_targets.append(enemy)
				var hive := _find_attackable_hive_in_room(strike_room)
				if hive:
					blast_targets.append(hive)
			for blast_target in blast_targets:
				var was_alive := _target_is_alive(blast_target)
				var charge_damage := int(base_damage * 0.85)
				if blast_target is EnemyUnit:
					(blast_target as EnemyUnit).take_damage(charge_damage, self)
				elif blast_target is Hive:
					(blast_target as Hive).take_damage(charge_damage, self)
				combat_hit.emit(
					soldier_name,
					_combat_target_name(blast_target),
					charge_damage,
					was_alive and not _target_is_alive(blast_target)
				)
			if door_count > 0:
				last_ability_detail = "%d bulkhead(s) breached" % door_count
			if blast_targets.size() > 0:
				var blast_note := "%d hostile(s) caught in blast" % blast_targets.size()
				last_ability_detail = blast_note if last_ability_detail.is_empty() else "%s, %s" % [last_ability_detail, blast_note]
			used = door_count > 0 or not blast_targets.is_empty()
	if not used:
		return false
	ability_timer = ability_cooldown_max
	return true

func _breach_nearby_doors(radius: float) -> int:
	var breached := 0
	for node in get_tree().get_nodes_in_group("doors"):
		if not node.has_method("force_open") or not node.has_method("blocks_travel"):
			continue
		if not node.blocks_travel():
			continue
		var door_pos: Vector2 = (node as Node2D).position
		if position.distance_to(door_pos) > radius:
			continue
		node.force_open()
		breached += 1
	if breached > 0:
		waiting_at_door = null
		if not path_queue.is_empty():
			_rebuild_corridor_path()
	return breached

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
	var final_amount: int = maxi(1, amount - defense)
	current_health = max(0, current_health - final_amount)
	CombatFxLib.spawn_damage_number(self, final_amount, Color(1.0, 0.3, 0.25, 1.0))
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
	CombatFxLib.spawn_death(self)
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
