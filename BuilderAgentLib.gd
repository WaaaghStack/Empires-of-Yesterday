class_name BuilderAgentLib
extends RefCounted

const CFG := preload("res://WorldConquestConfig.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")

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


## BUILDING-phase timer: decrements build_remaining and transitions to ACTIVE.
static func step_building_timers(
	dt: float, structures: Array, map_data, tile_control
) -> Dictionary:
	var pending_claims: Array[Vector2i] = []
	var activated_spawner_sids: Array[int] = []
	var activated_sids: Array[int] = []
	var needs_sim_sync: bool = false
	if dt <= 0.0 or map_data == null:
		return {
			"pending_claims": pending_claims,
			"activated_spawner_sids": activated_spawner_sids,
			"activated_sids": activated_sids,
			"needs_sim_sync": false,
		}
	var w: int = map_data.grid_width
	for st: Dictionary in structures:
		var kind: String = str(st.get("kind", ""))
		if not OutpostBuildLib.has_build_phase(kind):
			continue
		if str(st.get("state", "")) != OutpostBuildLib.STATE_BUILDING:
			continue
		var build_sec: float = OutpostBuildLib.build_sec_for_kind(kind)
		var rem: float = float(st.get("build_remaining", build_sec)) - dt
		st["build_remaining"] = rem
		if rem > 0.0:
			continue
		st["state"] = OutpostBuildLib.STATE_ACTIVE
		st.erase("build_remaining")
		st.erase("health")
		st["spawn_timer"] = 0.0
		var sid: int = int(st.get("id", -1))
		if sid >= 0:
			activated_sids.append(sid)
		if kind == OutpostBuildLib.KIND_SPAWNER:
			if sid >= 0:
				activated_spawner_sids.append(sid)
			var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
			var idx: int = int(st.get("gy", 0)) * w + int(st.get("gx", 0))
			if (
				tile_control != null
				and idx >= 0
				and idx < tile_control.owners.size()
				and tile_control.owners[idx] != team
			):
				pending_claims.append(Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0))))
				needs_sim_sync = true
		else:
			needs_sim_sync = true
	return {
		"pending_claims": pending_claims,
		"activated_spawner_sids": activated_spawner_sids,
		"activated_sids": activated_sids,
		"needs_sim_sync": needs_sim_sync,
	}