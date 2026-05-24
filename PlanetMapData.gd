class_name PlanetMapData
extends MissionMapData

## Single-planet hull persisted for the duration of a run.
var is_planet_map: bool = true
var planet_hive_target: int = 0
var regular_hive_room_ids: Array[String] = []
var sector_room_counts: Dictionary = {}
var evolution_node_room_ids: Array[String] = []


func is_overmind_room(room_id: String) -> bool:
	return not overmind_room_id.is_empty() and room_id == overmind_room_id


func is_regular_hive_room(room_id: String) -> bool:
	return room_id in regular_hive_room_ids
