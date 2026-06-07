class_name BattlePacing
extends RefCounted

## Full map width crossed in this many seconds (one tile step at a time).
const MAP_CROSS_SECONDS := 140.0
const SIM_ROUND_SECONDS := 0.42
## Viewer replay: sim already ran; playback should feel like a real battle.
const REPLAY_MIN_TOTAL_SECONDS := 45.0
## Upper bound for normalized watch time at 1× (raise with long sim caps).
const REPLAY_MAX_TOTAL_SECONDS := 4800.0
const REPLAY_MIN_SEGMENT_SECONDS := 0.42
const REPLAY_MAX_SEGMENT_SECONDS := 1.15
## Headless turn-end resolve: cap rounds and thin tape frames (10× baseline for long conquest).
const RESOLVE_MAX_ROUNDS_CAP := 960
## Viewer on-demand resolve may run longer than queue pre-resolve.
const VIEWER_MAX_ROUNDS_CAP := 3200
## Fight until one army is destroyed (no rout / early time-stop).
const ANNIHILATION_MAX_ROUNDS_CAP := 6400
const RESOLVE_TAPE_RECORD_STRIDE := 4
## Pressure keyframes on tape every (record_stride × this) sim rounds.
const PRESSURE_KEYFRAME_STRIDE_MULT := 2
## Territory replay segment pacing (watch time only — not sim).
const TERRITORY_PACING_CELL_CAP := 40
const TERRITORY_PACING_PER_CELL_MULT := 0.10
const TERRITORY_MAX_SEGMENT_SECONDS := 1.25
const TERRITORY_REPLAY_SECONDS_PER_ROUND := 0.12
const MIN_BATTLE_SECONDS := 30.0
const MAX_BATTLE_SECONDS := 6000.0


static func replay_segment_seconds(frame_count: int, record_stride: int = 1) -> float:
	## Legacy average segment length (metadata / fallback when per-gap timing unavailable).
	var gaps: int = maxi(1, frame_count - 1)
	var sim_rounds: int = gaps * maxi(1, record_stride)
	var target_total: float = clampf(
		float(sim_rounds) * SIM_ROUND_SECONDS * 0.9,
		REPLAY_MIN_TOTAL_SECONDS,
		REPLAY_MAX_TOTAL_SECONDS,
	)
	return clampf(
		target_total / float(gaps),
		REPLAY_MIN_SEGMENT_SECONDS,
		REPLAY_MAX_SEGMENT_SECONDS,
	)


## How long one replay gap should last from actual tile steps in that sim round.
static func segment_duration_for_frames(frame_a: Dictionary, frame_b: Dictionary, battle_data) -> float:
	var cells_moved: int = max_cell_delta_between_frames(frame_a, frame_b)
	if cells_moved <= 0:
		return REPLAY_MIN_SEGMENT_SECONDS
	if cells_moved == 1:
		return seconds_per_cell(battle_data)
	return clampf(
		float(cells_moved) * seconds_per_cell(battle_data),
		REPLAY_MIN_SEGMENT_SECONDS,
		REPLAY_MAX_SEGMENT_SECONDS * 4.0,
	)


static func territory_ownership_delta(frame_a: Dictionary, frame_b: Dictionary) -> int:
	if frame_b.has("owner_delta"):
		return int(frame_b["owner_delta"].size()) / 2
	var owners_a: PackedByteArray = _owners_from_territory_frame(frame_a)
	var owners_b: PackedByteArray = _owners_from_territory_frame(frame_b)
	if owners_a.is_empty() or owners_b.is_empty():
		return 0
	var n: int = mini(owners_a.size(), owners_b.size())
	var changed: int = 0
	for i in range(n):
		if owners_a[i] != owners_b[i]:
			changed += 1
	return changed


static func territory_segment_duration_for_frames(
	frame_a: Dictionary,
	frame_b: Dictionary,
	battle_data,
) -> float:
	var cells_changed: int = mini(
		territory_ownership_delta(frame_a, frame_b),
		TERRITORY_PACING_CELL_CAP,
	)
	if cells_changed <= 0:
		return REPLAY_MIN_SEGMENT_SECONDS
	var per_cell: float = seconds_per_cell(battle_data) * TERRITORY_PACING_PER_CELL_MULT
	return clampf(
		float(maxi(1, cells_changed)) * per_cell,
		REPLAY_MIN_SEGMENT_SECONDS,
		TERRITORY_MAX_SEGMENT_SECONDS,
	)


static func territory_replay_target_seconds(sim_rounds: int) -> float:
	## Watch time tracks sim length (~0.42s per sim round at 1×), not a fixed ~90s window.
	return clampf(
		float(maxi(1, sim_rounds)) * SIM_ROUND_SECONDS,
		REPLAY_MIN_TOTAL_SECONDS,
		REPLAY_MAX_TOTAL_SECONDS,
	)


static func _owners_from_territory_frame(frame: Dictionary) -> PackedByteArray:
	const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
	return BattleReplayTapeLib.owners_from_frame(frame)


static func max_cell_delta_between_frames(frame_a: Dictionary, frame_b: Dictionary) -> int:
	var max_delta: int = 0
	var gx_a = frame_a.get("grid_x", PackedInt32Array())
	var gy_a = frame_a.get("grid_y", PackedInt32Array())
	var gx_b = frame_b.get("grid_x", PackedInt32Array())
	var gy_b = frame_b.get("grid_y", PackedInt32Array())
	var n: int = mini(mini(gx_a.size(), gy_a.size()), mini(gx_b.size(), gy_b.size()))
	for i in range(n):
		var delta: int = absi(int(gx_b[i]) - int(gx_a[i])) + absi(int(gy_b[i]) - int(gy_a[i]))
		if delta > max_delta:
			max_delta = delta
	return max_delta


static func resolve_max_rounds(est_turns: int) -> int:
	var est_cap: int = maxi(est_turns + 12, 24)
	var hard_cap: int = int(ceil(MAX_BATTLE_SECONDS / SIM_ROUND_SECONDS))
	return mini(mini(est_cap, hard_cap), RESOLVE_MAX_ROUNDS_CAP)


static func annihilation_max_rounds(battle_data) -> int:
	if battle_data == null:
		return ANNIHILATION_MAX_ROUNDS_CAP
	var span: int = maxi(32, battle_data.grid_width + battle_data.grid_height)
	return mini(ANNIHILATION_MAX_ROUNDS_CAP, span * 60 + 960)


static func seconds_per_cell(battle_data) -> float:
	if battle_data == null:
		return 0.625
	var span: int = maxi(1, battle_data.grid_width)
	return MAP_CROSS_SECONDS / float(span)


static func compute(
	battle_data,
	player_alloc: int,
	enemy_alloc: int,
	cp_count: int,
	avg_spawn_to_cp_cells: float,
) -> Dictionary:
	var sec_per_cell: float = seconds_per_cell(battle_data)
	var dist: float = maxf(8.0, avg_spawn_to_cp_cells)
	var est_turns: int = maxi(
		int(ceil(dist * 2.0 + float(cp_count) * 8.0)),
		12,
	)
	var target_seconds: float = clampf(
		float(est_turns) * sec_per_cell,
		MIN_BATTLE_SECONDS,
		MAX_BATTLE_SECONDS,
	)
	var sim_round_seconds: float = SIM_ROUND_SECONDS
	var max_turns: int = resolve_max_rounds(est_turns)
	return {
		"target_seconds": target_seconds,
		"turn_seconds": sim_round_seconds,
		"sim_round_seconds": sim_round_seconds,
		"seconds_per_cell": sec_per_cell,
		"substep_seconds": sec_per_cell,
		"max_turns": max_turns,
		"est_turns": est_turns,
		"cells_per_turn_avg": 1.0,
	}


static func estimate_avg_spawn_to_cp_distance(battle_data) -> float:
	return estimate_avg_spawn_to_contact(battle_data)


static func estimate_avg_spawn_to_contact(battle_data) -> float:
	if battle_data == null:
		return 24.0
	var spawn_center: Vector2 = battle_data.player_spawn_zone.get_center()
	var g0: Vector2i = battle_data.world_to_grid(spawn_center)
	var contact_x: int = battle_data.contact_column
	return float(absi(contact_x - g0.x))


static func estimate_avg_spawn_to_cp_distance_legacy(battle_data) -> float:
	if battle_data == null or battle_data.capture_points.is_empty():
		return 24.0
	var spawn_center: Vector2 = battle_data.player_spawn_zone.get_center()
	var total := 0.0
	for cp in battle_data.capture_points:
		var cp_pos: Vector2 = cp.get("world_pos", Vector2.ZERO)
		var g0: Vector2i = battle_data.world_to_grid(spawn_center)
		var g1: Vector2i = battle_data.world_to_grid(cp_pos)
		total += float(absi(g1.x - g0.x) + absi(g1.y - g0.y))
	return total / float(battle_data.capture_points.size())
