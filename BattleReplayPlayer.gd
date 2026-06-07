class_name BattleReplayPlayer
extends RefCounted

const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

var tape: BattleReplayTapeLib
var playback_time: float = 0.0
var speed_mult: float = 1.0
var finished: bool = false
var _last_round: int = 0
var _last_tier_sig: int = 0


func _init(replay_tape: BattleReplayTapeLib) -> void:
	tape = replay_tape
	finished = tape == null or tape.frame_count() <= 1


func reset() -> void:
	playback_time = 0.0
	finished = false
	_last_round = 0
	_last_tier_sig = 0


func skip_to_end() -> void:
	if tape == null:
		finished = true
		return
	playback_time = tape.total_duration()


func tick(delta: float, store: UnitSimulationStoreLib) -> Dictionary:
	if finished or tape == null or store == null or tape.frame_count() < 2:
		finished = true
		return _status(store)
	playback_time += delta * speed_mult
	var total: float = tape.total_duration()
	if playback_time >= total:
		playback_time = total
		finished = true
	var seg_info: Dictionary = tape.segment_at_playback_time(playback_time)
	var from_i: int = int(seg_info.get("from_i", 0))
	var to_i: int = int(seg_info.get("to_i", from_i))
	var blend: float = float(seg_info.get("blend", 0.0))
	tape.apply_interpolated(store, from_i, to_i, blend)
	var tier_dirty: bool = _tier_signature(store) != _last_tier_sig
	_last_tier_sig = _tier_signature(store)
	_last_round = from_i
	return _status(store, tier_dirty)


func apply_start_frame(store: UnitSimulationStoreLib) -> void:
	if tape == null or store == null:
		return
	tape.apply_to_store(store, 0)
	_last_tier_sig = _tier_signature(store)
	_last_round = 0
	playback_time = 0.0
	finished = false


func _status(store: UnitSimulationStoreLib, tier_dirty: bool = false) -> Dictionary:
	return {
		"round": _last_round,
		"finished": finished,
		"playback_time": playback_time,
		"tier_visibility_dirty": tier_dirty,
		"friendly_living": store.living_friendly_count() if store else 0,
		"hostile_living": store.living_hostile_count() if store else 0,
	}


func _tier_signature(store: UnitSimulationStoreLib) -> int:
	var sig: int = store.count
	for i in range(mini(store.count, 64)):
		sig = (sig * 31 + store.tier[i]) & 0x7FFFFFFF
	return sig
