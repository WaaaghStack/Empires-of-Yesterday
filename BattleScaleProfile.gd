class_name BattleScaleProfile
extends RefCounted

const MELEE_SWINGS_SMALL := 256
const MELEE_SWINGS_LARGE := 512
const RANGED_SHOTS_BASE := 40
const RANGED_SHOTS_CAP := 160
const FIGHTERS_PER_SIDE_PER_EDGE := 4
const TIER_CONTACT_RADIUS_SMALL := 6
const TIER_CONTACT_RADIUS_LARGE := 10
const LARGE_ARMY_THRESHOLD := 3500


static func for_unit_count(unit_count: int) -> Dictionary:
	var n: int = maxi(1, unit_count)
	var large: bool = n >= LARGE_ARMY_THRESHOLD
	var sqrt_n: int = int(sqrt(float(n)))
	return {
		"max_melee_swings": MELEE_SWINGS_LARGE if large else MELEE_SWINGS_SMALL,
		"max_ranged_shots": mini(RANGED_SHOTS_CAP, RANGED_SHOTS_BASE + sqrt_n),
		"fighters_per_edge": FIGHTERS_PER_SIDE_PER_EDGE,
		"tier_contact_radius": TIER_CONTACT_RADIUS_LARGE if large else TIER_CONTACT_RADIUS_SMALL,
		"sim_only_move_interval": 3 if large else 1,
		"visible_lite_cap_per_side": 1500 if large else 2200,
	}
