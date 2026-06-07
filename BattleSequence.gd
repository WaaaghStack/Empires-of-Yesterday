class_name BattleSequence
extends RefCounted

enum Phase {
	ORDERS,
	MOVEMENT,
	MELEE,
	MISSILE,
	MAGIC,
	MORALE,
	CLEANUP,
}

static func phase_name(phase: int) -> String:
	match phase:
		Phase.ORDERS:
			return "orders"
		Phase.MOVEMENT:
			return "movement"
		Phase.MELEE:
			return "melee"
		Phase.MISSILE:
			return "missile"
		Phase.MAGIC:
			return "magic"
		Phase.MORALE:
			return "morale"
		Phase.CLEANUP:
			return "cleanup"
		_:
			return "unknown"
