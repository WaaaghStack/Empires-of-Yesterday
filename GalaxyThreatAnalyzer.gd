class_name GalaxyThreatAnalyzer
extends RefCounted

const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")

enum NodeStatus {
	SAFE,
	FRONTIER,
	UNDER_DEFENDED,
	END_TURN_BATTLE,
	CRITICAL,
}

const ENEMY_REINFORCE_DELTA := 35


static func get_node_status(galaxy, army_pool, node_id: String) -> int:
	if galaxy == null or node_id.is_empty():
		return NodeStatus.SAFE
	var node: Dictionary = galaxy.get_node(node_id)
	if node.is_empty():
		return NodeStatus.SAFE
	var owner := str(node.get("owner", ""))
	var enemy: int = int(node.get("enemy_strength", 0))
	var alloc: int = army_pool.get_allocation(node_id) if army_pool else 0
	var allocated: Dictionary = army_pool.allocated_by_node if army_pool else {}
	for battle_node in galaxy.get_contested_battle_nodes(allocated):
		if str(battle_node.get("id", "")) == node_id and alloc > 0:
			return NodeStatus.END_TURN_BATTLE
	if node_id == galaxy.hq_node_id or str(node.get("type", "")) == "hq":
		if _adjacent_enemy_pressure(galaxy, node_id) >= 400:
			return NodeStatus.CRITICAL
	if owner == GalaxyMapStateLib.OWNER_PLAYER and enemy > 0:
		if alloc < int(float(enemy) * 0.6):
			return NodeStatus.UNDER_DEFENDED
	if owner == GalaxyMapStateLib.OWNER_PLAYER and enemy <= 0:
		return NodeStatus.SAFE
	if owner == GalaxyMapStateLib.OWNER_ENEMY or owner == GalaxyMapStateLib.OWNER_NEUTRAL:
		if _is_adjacent_to_player(galaxy, node_id):
			return NodeStatus.FRONTIER
	if owner == GalaxyMapStateLib.OWNER_PLAYER and _is_adjacent_to_enemy_or_neutral_frontier(galaxy, node_id):
		if enemy > 0 or _adjacent_enemy_pressure(galaxy, node_id) > 200:
			return NodeStatus.FRONTIER
	return NodeStatus.SAFE


static func estimate_power_ratio(player_alloc: int, enemy_force: int, terrain_tag: String) -> float:
	var terrain_mod := 1.0
	match terrain_tag:
		"mountain":
			terrain_mod = 0.88
		"urban":
			terrain_mod = 0.92
		"open_field":
			terrain_mod = 1.05
	return float(player_alloc) * terrain_mod / maxf(1.0, float(enemy_force))


static func power_summary(player_alloc: int, enemy_force: int, terrain_tag: String) -> String:
	var ratio := estimate_power_ratio(player_alloc, enemy_force, terrain_tag)
	if ratio >= 1.15:
		return "Favorable"
	if ratio >= 0.85:
		return "Even fight"
	if ratio >= 0.6:
		return "Risky"
	return "Dangerous"


static func get_end_turn_battle_preview(galaxy, army_pool) -> Array[Dictionary]:
	if galaxy == null or army_pool == null:
		return []
	return galaxy.get_contested_battle_nodes(army_pool.allocated_by_node)


static func get_threat_strip_summary(galaxy, army_pool) -> String:
	if galaxy == null or army_pool == null:
		return ""
	var battles := get_end_turn_battle_preview(galaxy, army_pool)
	var underdef := 0
	var critical := 0
	var frontier := 0
	for node in galaxy.nodes:
		var node_id := str(node.get("id", ""))
		var status := get_node_status(galaxy, army_pool, node_id)
		match status:
			NodeStatus.UNDER_DEFENDED:
				underdef += 1
			NodeStatus.CRITICAL:
				critical += 1
			NodeStatus.FRONTIER:
				frontier += 1
	var parts: PackedStringArray = PackedStringArray()
	if battles.size() > 0:
		parts.append("%d battle(s) queued" % battles.size())
	if underdef > 0:
		parts.append("%d underdefended" % underdef)
	if critical > 0:
		parts.append("%d critical" % critical)
	elif frontier > 0:
		parts.append("%d frontier" % frontier)
	if parts.is_empty():
		return "Front stable — allocate troops or end turn"
	return " · ".join(parts)


static func get_urgent_node_ids(galaxy, army_pool) -> Array[String]:
	var ids: Array[String] = []
	if galaxy == null or army_pool == null:
		return ids
	for node in galaxy.nodes:
		var node_id := str(node.get("id", ""))
		var status := get_node_status(galaxy, army_pool, node_id)
		if status in [NodeStatus.CRITICAL, NodeStatus.UNDER_DEFENDED, NodeStatus.END_TURN_BATTLE, NodeStatus.FRONTIER]:
			ids.append(node_id)
	return ids


static func next_reinforce_preview(node: Dictionary) -> int:
	var owner := str(node.get("owner", ""))
	if owner == GalaxyMapStateLib.OWNER_ENEMY:
		return ENEMY_REINFORCE_DELTA
	if owner == GalaxyMapStateLib.OWNER_NEUTRAL:
		return 15
	return 0


static func _is_adjacent_to_player(galaxy, node_id: String) -> bool:
	for edge in galaxy.edges:
		var from_id := str(edge.get("from_id", ""))
		var to_id := str(edge.get("to_id", ""))
		var other := ""
		if from_id == node_id:
			other = to_id
		elif to_id == node_id:
			other = from_id
		else:
			continue
		if str(galaxy.get_node(other).get("owner", "")) == GalaxyMapStateLib.OWNER_PLAYER:
			return true
	return false


static func _is_adjacent_to_enemy_or_neutral_frontier(galaxy, node_id: String) -> bool:
	for edge in galaxy.edges:
		var from_id := str(edge.get("from_id", ""))
		var to_id := str(edge.get("to_id", ""))
		var other := ""
		if from_id == node_id:
			other = to_id
		elif to_id == node_id:
			other = from_id
		else:
			continue
		var o := str(galaxy.get_node(other).get("owner", ""))
		if o == GalaxyMapStateLib.OWNER_ENEMY or o == GalaxyMapStateLib.OWNER_NEUTRAL:
			return true
	return false


static func _adjacent_enemy_pressure(galaxy, node_id: String) -> int:
	var pressure := 0
	for edge in galaxy.edges:
		var from_id := str(edge.get("from_id", ""))
		var to_id := str(edge.get("to_id", ""))
		var other := ""
		if from_id == node_id:
			other = to_id
		elif to_id == node_id:
			other = from_id
		else:
			continue
		var other_node: Dictionary = galaxy.get_node(other)
		var o := str(other_node.get("owner", ""))
		if o == GalaxyMapStateLib.OWNER_ENEMY or o == GalaxyMapStateLib.OWNER_NEUTRAL:
			pressure += int(other_node.get("enemy_strength", 0))
	return pressure
