class_name VipEscort
extends Node2D

const MissionStateLib := preload("res://MissionState.gd")

signal died(vip: VipEscort)
signal reached_extraction(vip: VipEscort)

const WAYPOINT_RADIUS := 10.0
const FOLLOW_SPEED_RATIO := 0.82
const EXTRACT_SPOT_RADIUS := 28.0

var is_alive := true
var is_at_extraction := false
var follow_offset := Vector2(28.0, 18.0)
var path_queue: Array[Vector2] = []
var path_index: int = 0
var waiting_at_door: Node2D = null
var _pathing_to: Vector2 = Vector2.ZERO

@onready var body_poly: Polygon2D = $BodyPoly
@onready var label: Label = $Label


func _ready() -> void:
	add_to_group("vip_escort")
	label.text = "VIP"
	_update_visual()


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	if MissionStateLib.is_unit_actions_frozen(self):
		return
	var anchor := _find_slowest_marine()
	if not anchor:
		return
	var target_pos := anchor.position + follow_offset
	var dist := position.distance_to(target_pos)
	if dist > 52.0:
		if path_queue.is_empty() or _pathing_to.distance_to(target_pos) > 36.0:
			_rebuild_path_to(target_pos)
		_move_along_path(delta)
	elif dist > 8.0:
		_move_direct(delta, target_pos, _follow_speed())
	_check_extraction_status()


func _follow_speed() -> float:
	return _find_slowest_marine_speed() * FOLLOW_SPEED_RATIO


func _find_slowest_marine_speed() -> float:
	var slowest := 120.0
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			slowest = minf(slowest, node.speed)
	return slowest


func _find_slowest_marine() -> SoldierUnit:
	var slowest: SoldierUnit = null
	var slowest_speed := INF
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			if node.speed < slowest_speed:
				slowest_speed = node.speed
				slowest = node
	return slowest


func _rebuild_path_to(end_pos: Vector2) -> void:
	path_queue.clear()
	path_index = 0
	_pathing_to = end_pos
	var graph := _get_path_graph()
	if not graph:
		path_queue.append(end_pos)
		return
	var from_room := _room_containing(position)
	var target_room := _room_containing(end_pos)
	var blocked: Array[String] = []
	for point in graph.find_path(position, end_pos, blocked, from_room, target_room):
		path_queue.append(point)
	if path_queue.is_empty():
		path_queue.append(end_pos)


func _move_along_path(delta: float) -> void:
	if waiting_at_door:
		if waiting_at_door.blocks_travel():
			waiting_at_door.request_open()
			return
		waiting_at_door = null
		_rebuild_path_to(_pathing_to)
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
	_move_direct(delta, waypoint, _follow_speed())


func _move_direct(delta: float, target_pos: Vector2, move_speed: float) -> void:
	var to_target: Vector2 = target_pos - position
	if to_target.length() <= 0.001:
		return
	var before := position
	position += to_target.normalized() * minf(to_target.length(), move_speed * delta)
	if not _is_walkable(position):
		position = before
		return
	if body_poly:
		body_poly.rotation = to_target.angle()


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


func _check_extraction_status() -> void:
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and node.is_extraction_room:
			if node.contains_local_point(position, EXTRACT_SPOT_RADIUS):
				if not is_at_extraction:
					is_at_extraction = true
					reached_extraction.emit(self)
				return
	is_at_extraction = false


func take_damage(_amount: int) -> void:
	if not is_alive:
		return
	is_alive = false
	died.emit(self)
	queue_free()


func _update_visual() -> void:
	if not body_poly:
		return
	body_poly.color = Color(0.95, 0.82, 0.25, 1.0)
	body_poly.polygon = PackedVector2Array([
		Vector2(-9, -11), Vector2(9, -11), Vector2(11, 8), Vector2(-11, 8),
	])
