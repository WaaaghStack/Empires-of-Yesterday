class_name CommsTemplates
extends RefCounted

## Military-tone comms copy for tactical map logs.


static func mission_start() -> String:
	return "All squads on deck. Weapons hot — execute reclamation protocol."


static func hive_active(room_name: String) -> String:
	return "CONTACT — bio-signature active in %s. Nest is live." % room_name


static func hive_wave_inbound(room_name: String) -> String:
	return "INBOUND — swarm pulse detected at %s. Stand by." % room_name


static func hive_damage(amount: int, pct_remaining: float) -> String:
	return "STRUCTURAL HIT — hive taking %d damage. Integrity at %.0f%%." % [amount, pct_remaining * 100.0]


static func nests_halfway(destroyed: int, total: int) -> String:
	return "PHASE SHIFT — %d of %d nests down. Swarm pressure escalating." % [destroyed, total]


static func last_nest_cleared() -> String:
	return "FINAL NEST — all satellite hives neutralized. Overmind channel opening."


static func queen_awakens() -> String:
	return "QUEEN SIGNAL — Overmind node active. Kill the core or lose the deck."


static func overmind_awakens() -> String:
	return queen_awakens()


static func extract_unlocked() -> String:
	return "EVAC OPEN — Overmind down. Extract all operators when ready."


static func extract_window_open(seconds: float) -> String:
	return extract_unlocked()


static func extract_window_closing(_seconds: float) -> String:
	return extract_unlocked()


static func squad_doctrine_assigned(squad_label: String, doctrine: String) -> String:
	return "%s — doctrine [%s] issued at mission start." % [squad_label, doctrine]


static func order_accepted(squad_label: String, order_label: String, room_name: String) -> String:
	return "%s — %s, move to %s." % [squad_label, order_label, room_name]


static func order_no_route(squad_label: String, room_name: String) -> String:
	return "%s — NEGATIVE, no route to %s." % [squad_label, room_name]
