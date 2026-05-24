class_name SquadsManager
extends RefCounted

const OrderTypeLib := preload("res://OrderType.gd")
const MissionStateLib := preload("res://MissionState.gd")

const SQUAD_IDS: Array[String] = ["alpha", "bravo", "charlie"]
const SQUAD_LABELS: Array[String] = ["Alpha", "Bravo", "Charlie"]
const SECTOR_TAGS: Array[String] = ["north", "south", "east", "west", "central"]

enum SectorDoctrine {
	NONE,
	ASSAULT_SECTOR,
	HOLD_CHOKE,
	SCOUT_SECTOR,
	ASSAULT_HIVE,
}

var members_by_squad: Dictionary = {}
var doctrines: Dictionary = {}
var sector_doctrines: Dictionary = {}
var sector_assignments: Dictionary = {}
var squad_stances: Dictionary = {}
var deploy_rooms: Dictionary = {}
var active_squad_id: String = "alpha"


func reset() -> void:
	members_by_squad.clear()
	doctrines.clear()
	sector_doctrines.clear()
	sector_assignments.clear()
	squad_stances.clear()
	deploy_rooms.clear()
	active_squad_id = "alpha"
	for squad_id in SQUAD_IDS:
		members_by_squad[squad_id] = []
		doctrines[squad_id] = OrderTypeLib.Type.CLEAR
		sector_doctrines[squad_id] = SectorDoctrine.NONE
		sector_assignments[squad_id] = ""
		squad_stances[squad_id] = "balanced"


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


func set_sector_doctrine(squad_id: String, doctrine: SectorDoctrine) -> void:
	sector_doctrines[squad_id] = doctrine


func get_sector_doctrine(squad_id: String) -> SectorDoctrine:
	return sector_doctrines.get(squad_id, SectorDoctrine.NONE) as SectorDoctrine


func set_sector_assignment(squad_id: String, sector: String) -> void:
	sector_assignments[squad_id] = sector


func get_sector_assignment(squad_id: String) -> String:
	return str(sector_assignments.get(squad_id, ""))


func set_squad_stance(squad_id: String, stance: String) -> void:
	squad_stances[squad_id] = stance.to_lower()


func get_squad_stance(squad_id: String) -> String:
	return str(squad_stances.get(squad_id, "balanced"))


static func sector_doctrine_label(doctrine: SectorDoctrine) -> String:
	match doctrine:
		SectorDoctrine.ASSAULT_SECTOR:
			return "Assault Sector"
		SectorDoctrine.HOLD_CHOKE:
			return "Hold Choke"
		SectorDoctrine.SCOUT_SECTOR:
			return "Scout Sector"
		SectorDoctrine.ASSAULT_HIVE:
			return "Assault Hive"
		_:
			return "None"


static func order_for_sector_doctrine(doctrine: SectorDoctrine) -> OrderTypeLib.Type:
	match doctrine:
		SectorDoctrine.ASSAULT_SECTOR, SectorDoctrine.ASSAULT_HIVE:
			return OrderTypeLib.Type.SEARCH_DESTROY
		SectorDoctrine.HOLD_CHOKE:
			return OrderTypeLib.Type.DEFEND
		SectorDoctrine.SCOUT_SECTOR:
			return OrderTypeLib.Type.EXPLORE
		_:
			return OrderTypeLib.Type.CLEAR


func rooms_for_sector(rooms: Array, sector: String) -> Array:
	if sector.is_empty():
		return rooms
	var result: Array = []
	for room in rooms:
		if room is Room and str(room.sector_tag) == sector:
			result.append(room)
	return result


func pick_target_room(squad_id: String, rooms: Array, hives: Array = []) -> Room:
	var sector: String = get_sector_assignment(squad_id)
	var doctrine: SectorDoctrine = get_sector_doctrine(squad_id)
	var pool: Array = rooms_for_sector(rooms, sector) if not sector.is_empty() else rooms.duplicate()
	if pool.is_empty():
		pool = rooms.duplicate()
	match doctrine:
		SectorDoctrine.ASSAULT_HIVE:
			for hive in hives:
				if hive and hive.home_room and hive.home_room in pool and hive.is_attackable():
					return hive.home_room
		SectorDoctrine.HOLD_CHOKE:
			for room in pool:
				if room is Room and str(room.get_meta("room_shape", "")) == "choke":
					return room
		SectorDoctrine.SCOUT_SECTOR:
			for room in pool:
				if room is Room and not room.is_revealed:
					return room
		SectorDoctrine.ASSAULT_SECTOR, _:
			for room in pool:
				if room is Room and room.requires_clear and not room.is_cleared:
					return room
	if not pool.is_empty():
		return pool[0]
	return null


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


func squad_status_display(squad_id: String) -> String:
	match squad_status(squad_id):
		"ENGAGED":
			return "IN CONTACT"
		"MOVING":
			return "MOVING"
		"EXTRACTING":
			return "EXTRACTING"
		"WIPED":
			return "WIPED"
		_:
			return "HOLDING"


static func doctrine_for_objective(objective_template: String) -> OrderTypeLib.Type:
	match objective_template:
		"planet_reclamation":
			return OrderTypeLib.Type.SEARCH_DESTROY
		"silent_extract", "scavenge":
			return OrderTypeLib.Type.EXPLORE
		"hold_purge":
			return OrderTypeLib.Type.DEFEND
		"hive_purge":
			return OrderTypeLib.Type.SEARCH_DESTROY
		_:
			return OrderTypeLib.Type.SEARCH_DESTROY
