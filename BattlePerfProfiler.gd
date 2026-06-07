class_name BattlePerfProfiler
extends RefCounted

## Set BATTLE_PERF_LOG=1 in environment to log resolve phase timings.
var enabled: bool = false
var _phase_us: Dictionary = {}
var _round_total_us: int = 0
var _resolve_phases: Dictionary = {}


func _init() -> void:
	enabled = OS.get_environment("BATTLE_PERF_LOG") == "1"


func begin_round() -> void:
	_phase_us.clear()
	_round_total_us = 0


func begin_phase(phase_name: String) -> int:
	if not enabled:
		return 0
	return Time.get_ticks_usec()


func end_phase(phase_name: String, start_usec: int) -> void:
	if not enabled or start_usec <= 0:
		return
	var elapsed: int = Time.get_ticks_usec() - start_usec
	_phase_us[phase_name] = int(_phase_us.get(phase_name, 0)) + elapsed
	_round_total_us += elapsed
	_resolve_phases[phase_name] = int(_resolve_phases.get(phase_name, 0)) + elapsed


func log_round(round_index: int) -> void:
	if not enabled or _phase_us.is_empty():
		return
	var parts: PackedStringArray = PackedStringArray()
	for key in _phase_us.keys():
		parts.append("%s=%.2fms" % [key, float(_phase_us[key]) / 1000.0])
	var msg := "BattlePerf round %d total=%.2fms | %s" % [
		round_index,
		float(_round_total_us) / 1000.0,
		" ".join(parts),
	]
	if Engine.has_singleton("RunLog") or ClassDB.class_exists("RunLog"):
		RunLog.info(msg)
	else:
		print(msg)


func log_resolve_summary(resolve_ms: float, round_count: int, frame_count: int) -> void:
	if not enabled:
		return
	var parts: PackedStringArray = PackedStringArray()
	for key in _resolve_phases.keys():
		parts.append("%s=%.1fms" % [key, float(_resolve_phases[key]) / 1000.0])
	var msg := (
		"BattlePerf resolve %.1fms %d rounds %d frames | %s"
		% [resolve_ms, round_count, frame_count, " ".join(parts)]
	)
	if Engine.has_singleton("RunLog") or ClassDB.class_exists("RunLog"):
		RunLog.info(msg)
	else:
		print(msg)


func measure_round(_sim, advance_fn: Callable) -> float:
	var t0: int = Time.get_ticks_usec()
	advance_fn.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0
