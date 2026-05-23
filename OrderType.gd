class_name OrderType
extends RefCounted

enum Type { NONE, MOVE, CLEAR, SEARCH_DESTROY, DEFEND, EXTRACT }

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
	return "Idle"
