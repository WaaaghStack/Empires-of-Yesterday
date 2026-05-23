class_name Door
extends Node2D

signal opened(door: Node2D)
signal closed(door: Node2D)

@export var door_name: String = "Bulkhead"
var room_node_id: String = ""
var spine_node_id: String = ""
var is_open := false
var _open_progress: float = 0.0
var _idle_close_timer: float = 0.0

@onready var frame_line: Line2D = $FrameLine
@onready var door_panel: Polygon2D = $DoorPanel

func setup(data: Dictionary) -> void:
	door_name = data.get("id", "Bulkhead")
	room_node_id = data.get("room_node", "")
	spine_node_id = data.get("spine_node", "")
	position = data.get("position", Vector2.ZERO)
	rotation = data.get("rotation", 0.0)
	queue_redraw()

func _process(delta: float) -> void:
	if is_open and _open_progress < 1.0:
		_open_progress = minf(_open_progress + delta * 3.0, 1.0)
		_update_visual()
	elif not is_open and _open_progress > 0.0:
		_open_progress = maxf(_open_progress - delta * 2.0, 0.0)
		_update_visual()
	if is_open and _open_progress >= 0.85:
		_idle_close_timer -= delta
		if _idle_close_timer <= 0.0 and not _soldiers_nearby(56.0):
			request_close()

func request_open() -> void:
	if is_open:
		return
	is_open = true
	_idle_close_timer = 2.5
	opened.emit(self)

func request_breach() -> void:
	force_open()

func force_open() -> void:
	if is_open and _open_progress >= 1.0:
		return
	is_open = true
	_open_progress = 1.0
	_idle_close_timer = 4.0
	_update_visual()
	opened.emit(self)

func request_close() -> void:
	if not is_open:
		return
	is_open = false
	closed.emit(self)

func blocks_travel() -> bool:
	return _open_progress < 0.85

func blocks_sight() -> bool:
	return _open_progress < 0.85

func get_blocked_path_nodes() -> Array[String]:
	if not blocks_travel():
		return []
	var blocked: Array[String] = []
	if spine_node_id != "":
		blocked.append(spine_node_id)
	return blocked

func _soldiers_nearby(radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			if node.position.distance_to(position) <= radius:
				return true
	return false

func _update_visual() -> void:
	if not door_panel:
		return
	var slide := _open_progress * 18.0
	door_panel.position = Vector2(slide, 0)
	door_panel.modulate = Color(1, 1, 1, 0.35 + _open_progress * 0.65)

func _ready() -> void:
	add_to_group("doors")
	_update_visual()
