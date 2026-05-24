class_name EvolutionNode
extends Node2D

signal node_activated(node: EvolutionNode)

var home_room: Room = null
var node_id: String = ""
var consumed: bool = false
var _body: Polygon2D
var _tactical_map: Node = null


func _ready() -> void:
	add_to_group("evolution_nodes")
	_build_visual()


func setup(room: Room, id: String, map_node: Node) -> void:
	home_room = room
	node_id = id
	_tactical_map = map_node
	if home_room:
		position = home_room.position + Vector2(home_room.room_size.x * 0.2, -home_room.room_size.y * 0.1)
		home_room.set_meta("evolution_node", self)


func _build_visual() -> void:
	_body = Polygon2D.new()
	_body.color = Color(0.35, 0.75, 1.0, 0.75)
	_body.polygon = PackedVector2Array([
		Vector2(-10, -8), Vector2(10, -8), Vector2(12, 4), Vector2(0, 12), Vector2(-12, 4),
	])
	add_child(_body)


func deactivate() -> void:
	consumed = true
	if _body:
		_body.color = Color(0.25, 0.35, 0.45, 0.45)


func try_activate(squad_id: String) -> bool:
	if consumed:
		return false
	consumed = true
	if _body:
		_body.color = Color(0.25, 0.35, 0.45, 0.45)
	node_activated.emit(self)
	if _tactical_map and _tactical_map.has_method("on_evolution_node_activated"):
		_tactical_map.on_evolution_node_activated(self, squad_id)
	return true
