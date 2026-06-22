class_name FrameBudgetProfiler
extends RefCounted

## Frame times are always sampled for the F3 HUD. Set BATTLE_FRAME_BUDGET_LOG=1 to log spikes above 16 ms.
const SPIKE_MS := 16.0
const MAX_SAMPLES := 300

var spike_log_enabled: bool = false
var _frame_start_usec: int = 0
var _phase_ms: Dictionary = {}
var _frame_times_ms: Array[float] = []


func _init() -> void:
	spike_log_enabled = OS.get_environment("BATTLE_FRAME_BUDGET_LOG") == "1"


func begin_frame() -> void:
	_frame_start_usec = Time.get_ticks_usec()
	_phase_ms.clear()


func begin_phase(phase_name: String) -> int:
	return Time.get_ticks_usec()


func end_phase(phase_name: String, start_usec: int) -> void:
	if start_usec <= 0:
		return
	_phase_ms[phase_name] = float(Time.get_ticks_usec() - start_usec) / 1000.0


func reset_samples() -> void:
	_frame_times_ms.clear()


func end_frame(record_sample: bool = true) -> void:
	if _frame_start_usec <= 0:
		return
	var total_ms: float = float(Time.get_ticks_usec() - _frame_start_usec) / 1000.0
	if record_sample:
		_frame_times_ms.append(total_ms)
		if _frame_times_ms.size() > MAX_SAMPLES:
			_frame_times_ms.pop_front()
	if spike_log_enabled and record_sample and total_ms > SPIKE_MS:
		var parts: PackedStringArray = PackedStringArray()
		for key in _phase_ms.keys():
			parts.append("%s=%.2fms" % [key, float(_phase_ms[key])])
		var msg := "FrameBudget SPIKE %.2fms | %s" % [total_ms, " ".join(parts)]
		if ClassDB.class_exists("RunLog"):
			RunLog.info(msg)
		else:
			print(msg)


func percentile(p: float) -> float:
	if _frame_times_ms.is_empty():
		return 0.0
	var sorted: Array = _frame_times_ms.duplicate()
	sorted.sort()
	var idx: int = clampi(int(floor(float(sorted.size() - 1) * p)), 0, sorted.size() - 1)
	return float(sorted[idx])


func min_fps() -> float:
	if _frame_times_ms.is_empty():
		return 0.0
	var max_ms: float = 0.0
	for ms in _frame_times_ms:
		if float(ms) > max_ms:
			max_ms = float(ms)
	if max_ms <= 0.001:
		return 0.0
	return 1000.0 / max_ms


func summary() -> Dictionary:
	if _frame_times_ms.is_empty():
		return {}
	return {
		"samples": _frame_times_ms.size(),
		"p50_ms": percentile(0.50),
		"p95_ms": percentile(0.95),
		"p99_ms": percentile(0.99),
		"min_fps": min_fps(),
	}