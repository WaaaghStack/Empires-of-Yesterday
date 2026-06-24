class_name BuilderAgentLib
extends RefCounted

const CFG := preload("res://WorldConquestConfig.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")

const STATE_IDLE := "idle"
const STATE_WORKING := "working"
const STATE_RETURNING := "returning"

const SELFCHECK_MAX_STEPS := 2400
const SELFCHECK_DT := 1.0 / 60.0


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


static func find_structure(structures: Array, sid: int) -> Dictionary:
	if sid < 0:
		return {}
	for st: Dictionary in structures:
		if int(st.get("id", -1)) == sid:
			return st
	return {}


static func job_queue_for_team(queues: Dictionary, team: int) -> Array:
	if team == BattleTileControlLib.OWNER_HOSTILE:
		return queues.get("hostile", [])
	return queues.get("friendly", [])


static func assign_builder_jobs(
	bots: Array, queues: Dictionary, structures: Array, team_filter: int = -1
) -> void:
	for bot: Dictionary in bots:
		if str(bot.get("state", "")) != STATE_IDLE:
			continue
		var team: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
		if team_filter >= 0 and team != team_filter:
			continue
		var q: Array = job_queue_for_team(queues, team)
		while not q.is_empty():
			var sid: int = int(q[0])
			var st: Dictionary = find_structure(structures, sid)
			if st.is_empty() or str(st.get("state", "")) != OutpostBuildLib.STATE_CONNECTING:
				q.remove_at(0)
				continue
			q.remove_at(0)
			start_builder_job(bot, sid, structures)
			break


static func start_builder_job(bot: Dictionary, sid: int, structures: Array) -> void:
	var st: Dictionary = find_structure(structures, sid)
	if st.is_empty():
		return
	bot["state"] = STATE_WORKING
	bot["job_sid"] = sid
	bot["seg_from_idx"] = next_seg_index(float(st.get("path_built", 1.0)))
	bot["seg_t"] = 0.0
	bot["return_t"] = 0.0


static func work_grid_pos(bot: Dictionary, structures: Array, grid_w: int) -> Vector2:
	var state: String = str(bot.get("state", ""))
	var home: Vector2i = Vector2i(int(bot.get("home_gx", 0)), int(bot.get("home_gy", 0)))
	if state == STATE_IDLE:
		return orbit_grid(home, float(bot.get("orbit_angle", 0.0)))
	if state == STATE_RETURNING:
		var ret_t: float = clampf(float(bot.get("return_t", 0.0)), 0.0, 1.0)
		var orbit: Vector2 = orbit_grid(home, float(bot.get("orbit_angle", 0.0)))
		var from_g: Vector2 = Vector2(
			float(bot.get("return_gx_f", orbit.x)),
			float(bot.get("return_gy_f", orbit.y)),
		)
		return from_g.lerp(orbit, ret_t)
	var st: Dictionary = find_structure(structures, int(bot.get("job_sid", -1)))
	if st.is_empty() or grid_w <= 0:
		return orbit_grid(home, float(bot.get("orbit_angle", 0.0)))
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	var seg_idx: int = int(bot.get("seg_from_idx", 0))
	if packed.size() < 2 or seg_idx >= packed.size() - 1:
		return Vector2(float(int(st.get("gx", 0))), float(int(st.get("gy", 0))))
	var from_cell: Vector2i = OutpostBuildLib.grid_from_packed_key(packed[seg_idx], grid_w)
	var to_cell: Vector2i = OutpostBuildLib.grid_from_packed_key(packed[seg_idx + 1], grid_w)
	var t: float = clampf(float(bot.get("seg_t", 0.0)), 0.0, 1.0)
	return Vector2(float(from_cell.x), float(from_cell.y)).lerp(
		Vector2(float(to_cell.x), float(to_cell.y)), t
	)


static func begin_builder_return(bot: Dictionary, structures: Array, grid_w: int) -> void:
	var pos: Vector2 = work_grid_pos(bot, structures, grid_w)
	bot["return_gx_f"] = pos.x
	bot["return_gy_f"] = pos.y
	bot["state"] = STATE_RETURNING
	bot["job_sid"] = -1
	bot["seg_t"] = 0.0
	bot["return_t"] = 0.0


## After a job ends: start the next queued CONNECTING job from the bot's current
## position, or begin the return-to-orbit lerp only when the team queue is empty.
static func try_assign_next_job(
	bot: Dictionary, queues: Dictionary, structures: Array, grid_w: int
) -> bool:
	var team: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	var q: Array = job_queue_for_team(queues, team)
	while not q.is_empty():
		var sid: int = int(q[0])
		var st: Dictionary = find_structure(structures, sid)
		if st.is_empty() or str(st.get("state", "")) != OutpostBuildLib.STATE_CONNECTING:
			q.remove_at(0)
			continue
		q.remove_at(0)
		start_builder_job(bot, sid, structures)
		return true
	begin_builder_return(bot, structures, grid_w)
	return false


static func on_cell_arrival(st: Dictionary, seg_from_idx: int) -> Dictionary:
	st["path_built"] = path_built_after_seg(seg_from_idx)
	return {
		"sid": int(st.get("id", -1)),
		"seg_from_idx": seg_from_idx,
		"kind": str(st.get("kind", "")),
	}


static func on_path_completed(st: Dictionary) -> Dictionary:
	var path_len: int = OutpostBuildLib.path_len_from_structure(st)
	if path_len <= 0:
		path_len = int(st.get("path_len", 0))
	st["path_len"] = path_len
	st["path_built"] = float(path_len)
	var kind: String = str(st.get("kind", ""))
	var is_corridor_link: bool = kind == OutpostBuildLib.KIND_CORRIDOR_LINK
	if not is_corridor_link:
		st["state"] = OutpostBuildLib.STATE_BUILDING
		st["build_remaining"] = OutpostBuildLib.build_sec_for_kind(kind)
	return {
		"sid": int(st.get("id", -1)),
		"gx": int(st.get("gx", 0)),
		"gy": int(st.get("gy", 0)),
		"team": int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
		"is_corridor_link": is_corridor_link,
		"kind": kind,
	}


## One simulation tick: bot travel, arrivals, path completion, building timers.
static func step_frame(
	dt: float,
	bots: Array,
	structures: Array,
	queues: Dictionary,
	grid_w: int,
	map_data = null,
	tile_control = null,
) -> Dictionary:
	var result := {
		"visual_dirty": false,
		"cell_arrivals": [],
		"path_completions": [],
		"completed_corridor_sids": [],
		"reassign_teams": [],
		"building_timer_result": {},
	}
	if dt <= 0.0 or bots.is_empty():
		return result
	var travel_sec: float = cell_travel_sec()
	for bot: Dictionary in bots:
		var state: String = str(bot.get("state", ""))
		if state == STATE_IDLE:
			bot["orbit_angle"] = float(bot.get("orbit_angle", 0.0)) + CFG.BUILDER_ORBIT_SPEED * dt
			continue
		if state == STATE_RETURNING:
			var ret_t: float = float(bot.get("return_t", 0.0)) + dt / maxf(CFG.BUILDER_RETURN_SEC, 0.001)
			bot["return_t"] = ret_t
			result["visual_dirty"] = true
			if ret_t >= 1.0:
				bot["state"] = STATE_IDLE
				bot["return_t"] = 0.0
				var team: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
				if not result["reassign_teams"].has(team):
					result["reassign_teams"].append(team)
			continue
		if state != STATE_WORKING:
			continue
		var job_sid: int = int(bot.get("job_sid", -1))
		var st: Dictionary = find_structure(structures, job_sid)
		if st.is_empty() or str(st.get("state", "")) != OutpostBuildLib.STATE_CONNECTING:
			var team_bad: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
			if not try_assign_next_job(bot, queues, structures, grid_w):
				if not result["reassign_teams"].has(team_bad):
					result["reassign_teams"].append(team_bad)
			result["visual_dirty"] = true
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		var seg_idx: int = int(bot.get("seg_from_idx", 0))
		if packed.size() < 2 or seg_idx >= packed.size() - 1:
			var done_early: Dictionary = on_path_completed(st)
			result["path_completions"].append(done_early)
			if bool(done_early.get("is_corridor_link", false)):
				result["completed_corridor_sids"].append(int(done_early.get("sid", -1)))
			var team_done: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
			if not try_assign_next_job(bot, queues, structures, grid_w):
				if not result["reassign_teams"].has(team_done):
					result["reassign_teams"].append(team_done)
			result["visual_dirty"] = true
			continue
		var seg_t: float = float(bot.get("seg_t", 0.0)) + dt / maxf(travel_sec, 0.001)
		var job_finished: bool = false
		while seg_t >= 1.0:
			seg_t -= 1.0
			result["cell_arrivals"].append(on_cell_arrival(st, seg_idx))
			var path_len: int = OutpostBuildLib.path_len_from_structure(st)
			if path_len <= 0:
				path_len = int(st.get("path_len", 0))
			st["path_len"] = path_len
			var built: float = float(st.get("path_built", 1.0))
			if built >= float(path_len):
				var done_full: Dictionary = on_path_completed(st)
				result["path_completions"].append(done_full)
				if bool(done_full.get("is_corridor_link", false)):
					result["completed_corridor_sids"].append(int(done_full.get("sid", -1)))
				var team_full: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
				if not try_assign_next_job(bot, queues, structures, grid_w):
					if not result["reassign_teams"].has(team_full):
						result["reassign_teams"].append(team_full)
				job_finished = true
				break
			seg_idx += 1
			if seg_idx >= packed.size() - 1:
				var done_seg: Dictionary = on_path_completed(st)
				result["path_completions"].append(done_seg)
				if bool(done_seg.get("is_corridor_link", false)):
					result["completed_corridor_sids"].append(int(done_seg.get("sid", -1)))
				var team_seg: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
				if not try_assign_next_job(bot, queues, structures, grid_w):
					if not result["reassign_teams"].has(team_seg):
						result["reassign_teams"].append(team_seg)
				job_finished = true
				break
		if job_finished:
			result["visual_dirty"] = true
			continue
		bot["seg_from_idx"] = seg_idx
		bot["seg_t"] = seg_t
		result["visual_dirty"] = true
	for team_var in result["reassign_teams"]:
		assign_builder_jobs(bots, queues, structures, int(team_var))
	if map_data != null:
		result["building_timer_result"] = step_building_timers(dt, structures, map_data, tile_control)
	return result


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


static func run_selfcheck() -> Dictionary:
	const GRID_W := 16
	var home := Vector2i(0, 0)
	var bots: Array = [
		make_bot(BattleTileControlLib.OWNER_FRIENDLY, home, 0),
		make_bot(BattleTileControlLib.OWNER_FRIENDLY, home, 1),
	]
	var path_keys := PackedInt32Array([0, 1, 2, 3])
	var st: Dictionary = {
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": 3,
		"gy": 0,
		"kind": OutpostBuildLib.KIND_SPAWNER,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_keys": path_keys,
		"path_len": 4,
		"path_built": 1.0,
	}
	var structures: Array = [st]
	var queues: Dictionary = {
		"friendly": [1],
		"hostile": [],
	}
	var fake_map = BattleMapDataLib.new()
	fake_map.grid_width = GRID_W
	assign_builder_jobs(bots, queues, structures)
	var cells: int = 0
	var steps: int = 0
	while steps < SELFCHECK_MAX_STEPS:
		steps += 1
		var frame: Dictionary = step_frame(
			SELFCHECK_DT, bots, structures, queues, GRID_W, fake_map, null
		)
		for ev: Dictionary in frame.get("cell_arrivals", []):
			cells += 1
		if str(st.get("state", "")) == OutpostBuildLib.STATE_ACTIVE:
			var ok_line: String = (
				"OK  builder selfcheck CONNECTING->BUILDING->ACTIVE cells=%d" % cells
			)
			print(ok_line)
			return {"ok": true, "detail": ok_line}
	var state: String = str(st.get("state", ""))
	var fail_line: String = (
		"FAIL builder selfcheck stuck state=%s cells=%d steps=%d" % [state, cells, steps]
	)
	print(fail_line)
	return {"ok": false, "detail": fail_line}


static func run_chain_selfcheck() -> Dictionary:
	const GRID_W := 16
	var home := Vector2i(0, 0)
	var bot: Dictionary = make_bot(BattleTileControlLib.OWNER_FRIENDLY, home, 0)
	var bots: Array = [bot]
	var st1: Dictionary = {
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": 2,
		"gy": 0,
		"kind": OutpostBuildLib.KIND_SPAWNER,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_keys": PackedInt32Array([0, 1, 2]),
		"path_len": 3,
		"path_built": 1.0,
	}
	var st2: Dictionary = {
		"id": 2,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": 5,
		"gy": 0,
		"kind": OutpostBuildLib.KIND_SPAWNER,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_keys": PackedInt32Array([0, 1, 2, 3, 4, 5]),
		"path_len": 6,
		"path_built": 1.0,
	}
	var structures: Array = [st1, st2]
	var queues: Dictionary = {"friendly": [1, 2], "hostile": []}
	var fake_map = BattleMapDataLib.new()
	fake_map.grid_width = GRID_W
	assign_builder_jobs(bots, queues, structures)
	var steps: int = 0
	var saw_returning: bool = false
	var jobs_done: int = 0
	while steps < SELFCHECK_MAX_STEPS:
		steps += 1
		var frame: Dictionary = step_frame(
			SELFCHECK_DT, bots, structures, queues, GRID_W, fake_map, null
		)
		if str(bot.get("state", "")) == STATE_RETURNING:
			var still_connecting: int = 0
			for st_chk: Dictionary in structures:
				if str(st_chk.get("state", "")) == OutpostBuildLib.STATE_CONNECTING:
					still_connecting += 1
			if still_connecting > 0:
				saw_returning = true
		for ev: Dictionary in frame.get("path_completions", []):
			var sid_done: int = int(ev.get("sid", -1))
			if sid_done == 1 or sid_done == 2:
				jobs_done += 1
		if (
			str(st1.get("state", "")) != OutpostBuildLib.STATE_CONNECTING
			and str(st2.get("state", "")) != OutpostBuildLib.STATE_CONNECTING
		):
			break
	if saw_returning:
		var fail_ret: String = "FAIL builder chain selfcheck bot returned home mid-queue"
		print(fail_ret)
		return {"ok": false, "detail": fail_ret}
	if jobs_done < 2:
		var fail_jobs: String = "FAIL builder chain selfcheck jobs_done=%d" % jobs_done
		print(fail_jobs)
		return {"ok": false, "detail": fail_jobs}
	var ok_line: String = "OK  builder chain selfcheck no-return jobs=%d steps=%d" % [jobs_done, steps]
	print(ok_line)
	return {"ok": true, "detail": ok_line}