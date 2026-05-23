class_name MissionMapData
extends RefCounted

const PathGraphScript := preload("res://DynamicPathGraph.gd")

var map_seed: int = 0
var map_size: Vector2 = Vector2(1024, 640)
var rooms: Array[Dictionary] = []
var corridors: Array[Rect2] = []
var hull_outline: PackedVector2Array = PackedVector2Array()
var path_graph = PathGraphScript.new()
func get_room_dicts() -> Array[Dictionary]:
	return rooms

func get_corridor_rects() -> Array[Rect2]:
	return corridors

func get_hull_outline() -> PackedVector2Array:
	return hull_outline
