class_name BattleArmyScale
extends RefCounted

## Galaxy allocation vs tactical entities. Each spawned unit runs full Dom-style sim
## (move, DRN melee/ranged, morale, scripts); casualties scale back to allocation.

const MIN_SQUADS_PER_SIDE := 8
const MAX_SQUADS_PER_SIDE := 56
const MIN_VISUAL_UNITS_PER_SIDE := 28
const MAX_VISUAL_UNITS_PER_SIDE := 140
const SOLDIERS_PER_SIM_UNIT := 8


static func squad_count(allocation: int) -> int:
	var n: int = maxi(1, allocation)
	return clampi(int(sqrt(float(n)) * 2.2), MIN_SQUADS_PER_SIDE, MAX_SQUADS_PER_SIDE)


static func sim_entity_count(allocation: int) -> int:
	return clampi(allocation / SOLDIERS_PER_SIM_UNIT, MIN_VISUAL_UNITS_PER_SIDE, MAX_VISUAL_UNITS_PER_SIDE)


static func sim_units_for_battle(player_alloc: int, enemy_alloc: int) -> Dictionary:
	return {
		"player_sim": sim_entity_count(player_alloc),
		"enemy_sim": sim_entity_count(enemy_alloc),
	}


static func allocation_losses(allocation: int, remaining_fraction: float) -> int:
	return maxi(0, int(roundf(float(maxi(1, allocation)) * (1.0 - clampf(remaining_fraction, 0.0, 1.0)))))
