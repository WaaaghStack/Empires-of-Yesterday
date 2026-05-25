class_name GalaxyMapState
extends RefCounted

const OWNER_PLAYER := "player"
const OWNER_ENEMY := "enemy"
const OWNER_NEUTRAL := "neutral"

var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var hq_node_id: String = "hq"
var boss_node_id: String = "boss"
var turn_index: int = 0


func get_node(node_id: String) -> Dictionary:
	for node in nodes:
		if str(node.get("id", "")) == node_id:
			return node
	return {}


func set_owner(node_id: String, owner: String) -> void:
	for i in range(nodes.size()):
		if str(nodes[i].get("id", "")) == node_id:
			nodes[i]["owner"] = owner
			if owner == OWNER_PLAYER and int(nodes[i].get("building_slots", 0)) <= 0:
				nodes[i]["building_slots"] = 2
			return


func try_add_building(node_id: String, building_id: String) -> bool:
	for i in range(nodes.size()):
		if str(nodes[i].get("id", "")) != node_id:
			continue
		if str(nodes[i].get("owner", "")) != OWNER_PLAYER:
			return false
		var slots: int = int(nodes[i].get("building_slots", 0))
		var buildings: Array = nodes[i].get("buildings", [])
		if buildings.size() >= slots:
			return false
		if building_id.is_empty():
			return false
		buildings.append(building_id)
		nodes[i]["buildings"] = buildings
		return true
	return false


func get_player_owned_ids() -> Array[String]:
	var ids: Array[String] = []
	for node in nodes:
		if str(node.get("owner", "")) == OWNER_PLAYER:
			ids.append(str(node.get("id", "")))
	return ids


func get_allocatable_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var owned: Dictionary = {}
	for node in nodes:
		if str(node.get("owner", "")) == OWNER_PLAYER:
			owned[str(node.get("id", ""))] = true
	for node in nodes:
		var node_id := str(node.get("id", ""))
		if node_id == hq_node_id:
			result.append(node)
			continue
		if str(node.get("owner", "")) == OWNER_PLAYER:
			result.append(node)
			continue
		for edge in edges:
			var from_id := str(edge.get("from_id", ""))
			var to_id := str(edge.get("to_id", ""))
			var adjacent := false
			if to_id == node_id and owned.has(from_id):
				adjacent = true
			if from_id == node_id and owned.has(to_id):
				adjacent = true
			if adjacent:
				result.append(node)
				break
	return result


func get_contested_battle_nodes(allocated: Dictionary) -> Array[Dictionary]:
	var battles: Array[Dictionary] = []
	for node in nodes:
		var node_id := str(node.get("id", ""))
		var alloc: int = int(allocated.get(node_id, 0))
		if alloc <= 0:
			continue
		var owner := str(node.get("owner", OWNER_NEUTRAL))
		var enemy_strength: int = int(node.get("enemy_strength", 0))
		if owner == OWNER_PLAYER and enemy_strength <= 0:
			continue
		if owner == OWNER_PLAYER and node_id == hq_node_id:
			continue
		battles.append(node)
	return battles


func is_galaxy_won() -> bool:
	return get_node(boss_node_id).get("owner", "") == OWNER_PLAYER


func is_hq_lost() -> bool:
	return get_node(hq_node_id).get("owner", "") != OWNER_PLAYER


func player_ownership_ratio() -> float:
	if nodes.is_empty():
		return 0.0
	var player_count := 0
	var contestable := 0
	for node in nodes:
		var node_type := str(node.get("type", ""))
		if node_type in ["start", "hq"]:
			continue
		contestable += 1
		if str(node.get("owner", "")) == OWNER_PLAYER:
			player_count += 1
	return float(player_count) / float(maxi(1, contestable))


func to_dict() -> Dictionary:
	return {
		"nodes": nodes.duplicate(true),
		"edges": edges.duplicate(true),
		"hq_node_id": hq_node_id,
		"boss_node_id": boss_node_id,
		"turn_index": turn_index,
	}


func from_dict(data: Dictionary) -> void:
	nodes = []
	for raw in data.get("nodes", []):
		if raw is Dictionary:
			nodes.append(raw.duplicate(true))
	edges = []
	for raw_e in data.get("edges", []):
		if raw_e is Dictionary:
			edges.append(raw_e.duplicate(true))
	hq_node_id = str(data.get("hq_node_id", "hq"))
	boss_node_id = str(data.get("boss_node_id", "boss"))
	turn_index = int(data.get("turn_index", 0))
