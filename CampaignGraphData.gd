class_name CampaignGraphData
extends RefCounted

## Branching campaign map state for mission-to-mission runs.

var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var current_node_id: String = ""
var completed_ids: Array[String] = []
var pending_mission_node_id: String = ""


func get_node(node_id: String) -> Dictionary:
	for node in nodes:
		if str(node.get("id", "")) == node_id:
			return node
	return {}


func get_node_ids_at_layer(layer: int) -> Array[String]:
	var ids: Array[String] = []
	for node in nodes:
		if int(node.get("layer", -1)) == layer:
			ids.append(str(node.get("id", "")))
	return ids


func is_completed(node_id: String) -> bool:
	return node_id in completed_ids


func get_available_next() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	if current_node_id.is_empty():
		return available
	for edge in edges:
		if str(edge.get("from_id", "")) != current_node_id:
			continue
		var to_id := str(edge.get("to_id", ""))
		if to_id.is_empty() or is_completed(to_id):
			continue
		var node := get_node(to_id)
		if not node.is_empty() and str(node.get("type", "")) != "start":
			available.append(node)
	return available


func get_children(node_id: String) -> Array[String]:
	var child_ids: Array[String] = []
	for edge in edges:
		if str(edge.get("from_id", "")) == node_id:
			child_ids.append(str(edge.get("to_id", "")))
	return child_ids


func is_run_complete() -> bool:
	var boss := get_node("boss")
	if boss.is_empty():
		return false
	return is_completed("boss")


func get_node_config(node_id: String) -> Dictionary:
	var node := get_node(node_id)
	if node.is_empty():
		return {}
	return {
		"node_id": node_id,
		"node_type": str(node.get("type", "battle")),
		"map_tier": str(node.get("map_tier", "small")),
		"objective_template": str(node.get("objective_template", "standard")),
		"campaign_boss": bool(node.get("campaign_boss", false)),
		"display_name": str(node.get("display_name", "Mission")),
		"description": str(node.get("description", "")),
		"node_mutators": node.get("node_mutators", []),
		"sector_reward": str(node.get("sector_reward", "")),
		"heal_percent": float(node.get("heal_percent", 0.0)),
		"biomass_bonus": int(node.get("biomass_bonus", 0)),
	}


func is_combat_node_type(node_type: String) -> bool:
	return node_type in ["battle", "elite", "boss"]


func is_event_node_type(node_type: String) -> bool:
	return node_type in ["rest", "armory", "intel_broker"]


func missions_cleared_count() -> int:
	var count := 0
	for node_id in completed_ids:
		var node := get_node(node_id)
		if node.is_empty():
			continue
		var node_type := str(node.get("type", ""))
		if node_type in ["battle", "elite", "boss"]:
			count += 1
	return count
