class_name BattleMusouFeel
extends RefCounted
## Tunable Dynasty-Warriors-Empires style march / contact feel.

const BASE_MARCH_SPEED := 95.0
const CHARGE_BURST_MULT := 1.72
const GRIND_MULT := 0.24
const REAR_REFILL_MULT := 1.18
const WAVE_PERIOD := 2.75
const WAVE_CHARGE_DUTY := 0.44
const CONTACT_HOLD_BAND_CELLS := 0.35
const CONTACT_MEET_OVERLAP_CELLS := 0.65
const REAR_BAND_CELLS := 5.0
const CONTACT_GRIND_CELLS := 1.35
const LANE_JITTER := 52.0
const LATERAL_DRIFT_SPEED := 1.35
const FRONT_CHURN_AMP := 16.0
const FRONT_CHURN_FREQ := 4.2
const FLIP_SURGE_DURATION := 1.35
const FLIP_SURGE_MULT := 1.58
const CONTACT_SCALE_BOOST := 0.14
const SQUAD_SPEED_0 := 1.28
const SQUAD_SPEED_1 := 1.05
const SQUAD_SPEED_2 := 0.86
const SQUAD_SPEED_3 := 0.7


static func wave_charge_mult(elapsed: float) -> float:
	var phase: float = fmod(elapsed, WAVE_PERIOD) / WAVE_PERIOD
	if phase < WAVE_CHARGE_DUTY:
		var t: float = phase / WAVE_CHARGE_DUTY
		return lerpf(1.0, CHARGE_BURST_MULT, sin(t * PI) * sin(t * PI))
	return lerpf(CHARGE_BURST_MULT * 0.55, GRIND_MULT + 0.35, (phase - WAVE_CHARGE_DUTY) / (1.0 - WAVE_CHARGE_DUTY))


static func squad_speed_mult(squad: int) -> float:
	match absi(squad) % 4:
		0:
			return SQUAD_SPEED_0
		1:
			return SQUAD_SPEED_1
		2:
			return SQUAD_SPEED_2
		_:
			return SQUAD_SPEED_3


static func contact_dist_x(pos_x: float, contact_x: float, side: int) -> float:
	if side == 0:
		return contact_x - pos_x
	return pos_x - contact_x


static func zone_speed_mult(dist_to_contact: float, cell_size: float, flip_surge: float) -> float:
	var hold: float = cell_size * CONTACT_HOLD_BAND_CELLS
	var grind: float = cell_size * CONTACT_GRIND_CELLS
	var rear: float = cell_size * REAR_BAND_CELLS
	if dist_to_contact <= grind:
		return GRIND_MULT * flip_surge
	if dist_to_contact <= hold:
		return lerpf(GRIND_MULT, 0.55, (dist_to_contact - grind) / maxf(1.0, hold - grind)) * flip_surge
	if dist_to_contact >= rear:
		return REAR_REFILL_MULT * flip_surge
	return 1.0 * flip_surge


static func flip_surge_mult(surge_timer: float) -> float:
	if surge_timer <= 0.0:
		return 1.0
	var t: float = surge_timer / FLIP_SURGE_DURATION
	return lerpf(FLIP_SURGE_MULT, 1.0, 1.0 - t * t)


static func lane_offset_y(unit_id: int, elapsed: float) -> float:
	var seed: float = float(unit_id % 997) * 0.13
	return sin(elapsed * LATERAL_DRIFT_SPEED + seed) * LANE_JITTER * 0.35


static func front_churn_offset(unit_id: int, elapsed: float) -> Vector2:
	var a: float = float(unit_id % 511) * 0.07 + elapsed * FRONT_CHURN_FREQ
	return Vector2(
		sin(a) * FRONT_CHURN_AMP * 0.45,
		cos(a * 1.37) * FRONT_CHURN_AMP,
	)


static func contact_scale_boost(dist_to_contact: float, cell_size: float, elapsed: float, unit_id: int) -> float:
	var grind: float = cell_size * CONTACT_GRIND_CELLS
	if dist_to_contact > grind:
		return 0.0
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 6.5 + float(unit_id % 89))
	return CONTACT_SCALE_BOOST * pulse * (1.0 - dist_to_contact / maxf(1.0, grind))
