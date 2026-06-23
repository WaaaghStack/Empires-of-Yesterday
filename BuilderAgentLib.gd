class_name BuilderAgentLib
extends RefCounted

const CFG := preload("res://WorldConquestConfig.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")

const STATE_IDLE := "idle"
const STATE_WORKING := "working"
const STATE_RETURNING := "returning"


static func cell_travel_sec() -> float:
	if CFG.OUTPOST_ROAD_CELLS_PER_SEC <= 0.001:
		return 1.0
	return 1.0 / CFG.OUTPOST_ROAD_CELLS_PER_SEC


static func make_bot(team: int, home: Vector2i, slot: int) -> Dictionary:
	var per_home: int = maxi(CFG.BUILDER_BOTS_PER_HOME, 1)
	return {
		"id": slot,
		"team": team,
		"home_gx": home.x,
		"home_gy": home.y,
		"state": STATE_IDLE,
		"job_sid": -1,
		"seg_from_idx": 0,
		"seg_t": 0.0,
		"orbit_angle": float(slot) * TAU / float(per_home),
		"return_t": 0.0,
	}


static func team_home(team: int, player_home: Vector2i, enemy_home: Vector2i) -> Vector2i:
	if team == BattleTileControlLib.OWNER_HOSTILE:
		return enemy_home
	return player_home


static func orbit_grid(home: Vector2i, angle: float) -> Vector2:
	var r: float = CFG.BUILDER_ORBIT_RADIUS_CELLS
	return Vector2(
		float(home.x) + cos(angle) * r,
		float(home.y) + sin(angle) * r * 0.42
	)


static func next_seg_index(path_built: float) -> int:
	return maxi(0, int(floor(path_built)) - 1)


static func path_built_after_seg(seg_from_idx: int) -> float:
	return float(seg_from_idx + 2)