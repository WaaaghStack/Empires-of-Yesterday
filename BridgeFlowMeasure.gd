class_name BridgeFlowMeasure
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

const SOURCE_PULSE_MULT := 8.0
const MIN_POST_PRESSURE := 0.5
const MIN_DELTA := 0.001


static func measure_suction_delta(
	sim,
	tc: BattleTileControlLib,
	map_data,
	path_keys: PackedInt32Array,
	landing_key: int,
	source_key: int,
	rounds: int,
	backend_label: String = "cpu",
) -> Dictionary:
	var coastal_gx: int = landing_key % map_data.grid_width
	var coastal_gy: int = landing_key / map_data.grid_width
	tc.extend_beachhead_from_landing(
		map_data, coastal_gx, coastal_gy, BattleTileControlLib.OWNER_FRIENDLY
	)
	if tc.bridge_pipe_path_packs().is_empty():
		tc.rebuild_bridge_pipe_topology(map_data)
	if sim.rust_field != null and sim.rust_field.ready:
		sim.rust_field.sync_claimable_from(tc, map_data, true)
		sim.rust_field.sync_bridge_pipe_from(tc)

	var saved_home_inject: bool = tc.home_inject_enabled
	var saved_suction: bool = tc.bridge_live_suction_enabled
	tc.home_inject_enabled = false

	_zero_pressures(sim, tc, path_keys)
	_inject_source_once(tc, sim, source_key, path_keys)
	tc.bridge_live_suction_enabled = false
	_sync_flags(sim, tc)
	for _pre in range(rounds):
		_advance_measure_round(sim, tc, map_data)
	var pre_p: float = _landing_pressure(sim, tc, landing_key)

	_zero_pressures(sim, tc, path_keys)
	_inject_source_once(tc, sim, source_key, path_keys)
	tc.bridge_live_suction_enabled = true
	_sync_flags(sim, tc)
	for _post in range(rounds):
		_advance_measure_round(sim, tc, map_data)
	var post_p: float = _landing_pressure(sim, tc, landing_key)
	var delta: float = post_p - pre_p
	tc.home_inject_enabled = saved_home_inject
	tc.bridge_live_suction_enabled = saved_suction
	_sync_flags(sim, tc)

	return {
		"pre": pre_p,
		"post": post_p,
		"delta": delta,
		"backend_label": backend_label,
		"pass": post_p >= MIN_POST_PRESSURE and delta > MIN_DELTA,
	}


static func format_result(result: Dictionary) -> String:
	return (
		"%s bridge natural landing pre_suction=%.3f post_suction=%.3f delta=%.3f"
		% [
			str(result.get("backend_label", "?")),
			float(result.get("pre", 0.0)),
			float(result.get("post", 0.0)),
			float(result.get("delta", 0.0)),
		]
	)


static func run_pipe_unit_selfcheck() -> bool:
	var pressures: PackedFloat32Array = PackedFloat32Array([8.0, 0.0, 0.0])
	var rate: float = WorldConquestConfigLib.BRIDGE_PIPE_SUCTION_RATE * 1.5
	var passes: int = maxi(1, WorldConquestConfigLib.BRIDGE_PIPE_LIVE_SUCTION_PASSES)
	for _pass in range(passes):
		_suction_transfer_along_pipe(pressures, 0, 1, rate)
		_suction_transfer_along_pipe(pressures, 1, 2, rate)
		_suction_transfer_along_pipe(pressures, 2, 1, rate)
		_suction_transfer_along_pipe(pressures, 1, 0, rate)
	return pressures[2] > 0.05


static func _suction_transfer_along_pipe(
	src: PackedFloat32Array, from_k: int, to_k: int, rate: float
) -> void:
	if from_k < 0 or to_k < 0 or from_k >= src.size() or to_k >= src.size():
		return
	if src[from_k] <= src[to_k]:
		return
	var pull: float = (src[from_k] - src[to_k]) * rate
	var cap: float = minf(pull, src[from_k] * 0.75)
	if cap <= 0.001:
		return
	src[from_k] -= cap
	src[to_k] += cap


static func _zero_pressures(
	sim, tc: BattleTileControlLib, path_keys: PackedInt32Array = PackedInt32Array()
) -> void:
	tc.pressure_friendly.fill(0.0)
	tc.pressure_hostile.fill(0.0)
	if sim.rust_field != null and sim.rust_field.ready:
		sim.rust_field.sync_pressures_from(tc)
	_prepare_active_set(tc, path_keys)


static func _inject_source_once(
	tc: BattleTileControlLib,
	sim,
	source_key: int,
	path_keys: PackedInt32Array,
) -> void:
	if source_key < 0 or source_key >= tc.pressure_friendly.size():
		return
	var source_only: PackedInt32Array = PackedInt32Array([source_key])
	tc.inject_corridor_pressure_pulse(
		source_only, BattleTileControlLib.OWNER_FRIENDLY, SOURCE_PULSE_MULT
	)
	_prepare_active_set(tc, path_keys)
	if sim.rust_field != null and sim.rust_field.ready:
		sim.rust_field.sync_pressures_from(tc)


static func _prepare_active_set(tc: BattleTileControlLib, path_keys: PackedInt32Array) -> void:
	if not tc.use_active_set:
		return
	for i in range(path_keys.size()):
		var key: int = int(path_keys[i])
		if key >= 0:
			tc._mark_active_dirty(key)
	tc._maybe_rebuild_active_indices(true)


static func _advance_measure_round(sim, tc: BattleTileControlLib, map_data) -> void:
	if sim.rust_field != null and sim.rust_field.ready and sim.backend == sim.BACKEND_RUST:
		_sync_flags(sim, tc)
		sim.rust_field.step_round(tc)
	else:
		tc.propagate_round_territory(map_data)


static func _sync_flags(sim, tc: BattleTileControlLib) -> void:
	if sim.rust_field == null or not sim.rust_field.ready:
		return
	var rf = sim.rust_field
	if rf._sim != null:
		if rf._sim.has_method("set_bridge_live_suction_enabled"):
			rf._sim.call(
				"set_bridge_live_suction_enabled", tc.bridge_live_suction_enabled
			)
		if rf._sim.has_method("set_home_inject_enabled"):
			rf._sim.call("set_home_inject_enabled", tc.home_inject_enabled)


static func _landing_pressure(sim, tc: BattleTileControlLib, landing_key: int) -> float:
	if sim.rust_field != null and sim.rust_field.ready:
		var rust_pf: PackedFloat32Array = sim.rust_field.get_pressure_friendly()
		if landing_key >= 0 and landing_key < rust_pf.size():
			return rust_pf[landing_key]
	if landing_key >= 0 and landing_key < tc.pressure_friendly.size():
		return tc.pressure_friendly[landing_key]
	return 0.0