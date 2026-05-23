class_name OrderType
extends RefCounted

enum Type {
	NONE = 0,
	MOVE = 1,
	CLEAR = 2,
	SEARCH_DESTROY = 3,
	DEFEND = 4,
	EXTRACT = 5,
	EXPLORE = 6,
	OBJECTIVE = 7,
}

static func get_label(order: Type) -> String:
	match order:
		Type.MOVE:
			return "Move"
		Type.CLEAR:
			return "Clear Room"
		Type.SEARCH_DESTROY:
			return "Search & Destroy"
		Type.DEFEND:
			return "Defend"
		Type.EXTRACT:
			return "Extract"
		Type.EXPLORE:
			return "Explore"
		Type.OBJECTIVE:
			return "Objective"
	return "Idle"
