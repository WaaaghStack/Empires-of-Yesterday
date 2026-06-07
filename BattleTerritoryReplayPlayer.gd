class_name BattleTerritoryReplayPlayer
extends RefCounted

const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")

var tape = null
var playback_time: float = 0.0
var speed_mult: float = 1.0
var finished: bool = false
var _last_round: int = 0
var _last_frame_i: int = 0


func _init(replay_tape) -> void:
	tape = replay_tape
	finished = tape == null or tape.frame_count() < 1


func reset() -> void:
	playback_time = 0.0
	finished = false
	_last_round = 0
	_last_frame_i = 0


func tick(delta: float) -> Dictionary:
	if finished or tape == null or tape.frame_count() < 1:
		finished = true
		return _status()
	playback_time += delta * speed_mult
	var total: float = tape.total_duration()
	if playback_time >= total:
		playback_time = total
		finished = true
	var seg_info: Dictionary = tape.segment_at_playback_time(playback_time)
	_last_frame_i = int(seg_info.get("from_i", 0))
	_last_round = int(seg_info.get("round", _last_frame_i))
	return _status()


func _status() -> Dictionary:
	var frame: Dictionary = {}
	var friendly_power_total: float = 0.0
	var hostile_power_total: float = 0.0
	if tape != null and _last_frame_i >= 0 and _last_frame_i < tape.frame_count():
		frame = tape.get_frame(_last_frame_i)
		if tape is BattleTerritoryTapeLib:
			var pressures: Dictionary = (tape as BattleTerritoryTapeLib).pressures_at_frame(_last_frame_i)
			var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
			var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
			var totals: Vector2 = BattleTileFluidFieldLib.cumulative_power_totals(pf, ph)
			friendly_power_total = totals.x
			hostile_power_total = totals.y
	return {
		"round": _last_round,
		"finished": finished,
		"playback_time": playback_time,
		"friendly_tiles": int(frame.get("friendly_tiles", 0)),
		"hostile_tiles": int(frame.get("hostile_tiles", 0)),
		"friendly_power_total": friendly_power_total,
		"hostile_power_total": hostile_power_total,
	}
