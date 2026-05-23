class_name IntelTerminal
extends Node2D

signal destroyed(terminal: IntelTerminal)

var is_destroyed := false
var home_room: Room = null

@onready var body_poly: Polygon2D = $BodyPoly


func _ready() -> void:
	add_to_group("intel_terminals")
	_update_visual()


func setup(room: Room, local_offset: Vector2 = Vector2.ZERO) -> void:
	home_room = room
	position = room.position + local_offset


func destroy_terminal() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	visible = false
	destroyed.emit(self)
	queue_free()


func _update_visual() -> void:
	if not body_poly:
		return
	body_poly.color = Color(0.25, 0.75, 0.95, 0.9)
	body_poly.polygon = PackedVector2Array([
		Vector2(-8, -10), Vector2(8, -10), Vector2(10, 6), Vector2(-10, 6),
	])
