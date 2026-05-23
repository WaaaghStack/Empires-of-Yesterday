class_name SquadsManager
extends RefCounted

const OrderTypeLib := preload("res://OrderType.gd")
const MissionStateLib := preload("res://MissionState.gd")

const SQUAD_IDS: Array[String] = ["alpha", "bravo", "charlie"]
const SQUAD_LABELS: Array[String] = ["Alpha", "Bravo", "Charlie"]

var members_by_squad: Dictionary = {}
var doctrines: Dictionary = {}
var deploy_rooms: Dictionary = {}
var active_squad_id: String = "alpha"


func reset() -> void:
	members_by_squad.clear()
	doctrines.clear()
	deploy_rooms.clear()
	active_squad_id = "alpha"
	for squad_id in SQUAD_IDS:
		members_by_squad[squad_id] = []
		doctrines[squad_id] = OrderTypeLib.Type.CLEAR


func register_unit(unit: SoldierUnit, squad_id: String) -> void:
	if squad_id.is_empty():
		squad_id = "alpha"
	if not members_by_squad.has(squad_id):
		members_by_squad[squad_id] = []
	var list: Array = members_by_squad[squad_id]
	if unit not in list:
		list.append(unit)
	unit.squad_id = squad_id


func get_squad_units(squad_id: String) -> Array[SoldierUnit]:
	var units: Array[SoldierUnit] = []
	if not members_by_squad.has(squad_id):
		return units
	for unit in members_by_squad[squad_id]:
		if unit is SoldierUnit and unit.is_alive:
			units.append(unit)
	return units


func get_living_count(squad_id: String) -> int:
	return get_squad_units(squad_id).size()


func get_total_count(squad_id: String) -> int:
	if not members_by_squad.has(squad_id):
		return 0
	return members_by_squad[squad_id].size()


func get_squad_center(squad_id: String) -> Vector2:
	var units := get_squad_units(squad_id)
	if units.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for unit in units:
		total += unit.position
	return total / float(units.size())


func aggregate_hp_percent(squad_id: String) -> float:
	var units := get_squad_units(squad_id)
	if units.is_empty():
		return 0.0
	var current := 0
	var maximum := 0
	for unit in units:
		current += unit.current_health
		maximum += unit.max_health
	if maximum <= 0:
		return 0.0
	return float(current) / float(maximum)


func set_doctrine(squad_id: String, doctrine: OrderTypeLib.Type) -> void:
	doctrines[squad_id] = doctrine


func get_doctrine(squad_id: String) -> OrderTypeLib.Type:
	return doctrines.get(squad_id, OrderTypeLib.Type.CLEAR) as OrderTypeLib.Type


func set_deploy_room(squad_id: String, room: Room) -> void:
	deploy_rooms[squad_id] = room


func get_deploy_room(squad_id: String) -> Room:
	return deploy_rooms.get(squad_id, null) as Room


func squad_label(squad_id: String) -> String:
	var idx: int = SQUAD_IDS.find(squad_id)
	if idx >= 0:
		return SQUAD_LABELS[idx]
	return squad_id.capitalize()


func squad_status(squad_id: String) -> String:
	var units := get_squad_units(squad_id)
	if units.is_empty():
		return "WIPED"
	var engaged := units.any(func(u): return MissionStateLib.is_attackable_target(u.current_target))
	if engaged:
		return "ENGAGED"
	var moving := units.any(func(u): return u.is_moving)
	if moving:
		return "MOVING"
	var extracting := units.any(func(u): return u.is_extracting or u.is_extracted)
	if extracting:
		return "EXTRACTING"
	return "READY"


static func doctrine_for_objective(objective_template: String) -> OrderTypeLib.Type:
	match objective_template:
		"silent_extract", "scavenge":
			return OrderTypeLib.Type.EXPLORE
		"hold_purge":
			return OrderTypeLib.Type.DEFEND
		"hive_purge":
			return OrderTypeLib.Type.SEARCH_DESTROY
		_:
			return OrderTypeLib.Type.SEARCH_DESTROY
