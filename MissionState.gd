class_name MissionState
extends RefCounted

static func is_unit_actions_frozen(node: Node) -> bool:
	for tactical_map in node.get_tree().get_nodes_in_group("tactical_map"):
		if tactical_map.mission_complete or not tactical_map.game_active:
			return true
		return tactical_map.is_paused
	return false
