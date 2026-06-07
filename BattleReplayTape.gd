class_name BattleReplayTape
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")

var round_duration: float = 0.42
var record_stride: int = 1
var segment_durations: Array = []
var battle_data = null
var unit_count: int = 0
var frames: Array = []
var result: Dictionary = {}
var resolve_ms: float = 0.0


func record_frame(
	store: UnitSimulationStoreLib,
	sim_round: int = -1,
	tile_owners: PackedByteArray = PackedByteArray(),
) -> void:
	if store == null:
		return
	unit_count = store.count
	var frame: Dictionary = _capture(store, tile_owners)
	if sim_round >= 0:
		frame["round"] = sim_round
	frames.append(frame)


func frame_count() -> int:
	return frames.size()


func to_dictionary() -> Dictionary:
	return {
		"round_duration": round_duration,
		"record_stride": record_stride,
		"segment_durations": segment_durations.duplicate(),
		"resolve_ms": resolve_ms,
		"result": result,
		"frames": frames.duplicate(true),
		"frame_count": frame_count(),
	}


## Restore tape from SQLite / JSON payload.
func load_from_dictionary(data: Dictionary) -> void:
	round_duration = float(data.get("round_duration", 0.42))
	record_stride = int(data.get("record_stride", 1))
	resolve_ms = float(data.get("resolve_ms", 0.0))
	result = data.get("result", {})
	frames = data.get("frames", []).duplicate(true)
	segment_durations = data.get("segment_durations", []).duplicate()
	unit_count = 0
	if not frames.is_empty():
		var f0: Dictionary = frames[0]
		var pos = f0.get("positions", PackedVector2Array())
		if pos is PackedVector2Array:
			unit_count = pos.size()
	if segment_durations.is_empty() and battle_data != null:
		rebuild_segment_timing()


## Per-gap playback times from MAP_CROSS_SECONDS (one cell step ≈ seconds_per_cell).
func rebuild_segment_timing() -> void:
	segment_durations.clear()
	if frames.size() < 2:
		return
	for gap in range(frames.size() - 1):
		var dur: float = BattlePacingLib.segment_duration_for_frames(
			frames[gap], frames[gap + 1], battle_data
		)
		segment_durations.append(dur)
	if not segment_durations.is_empty():
		var total: float = 0.0
		for d in segment_durations:
			total += float(d)
		round_duration = total / float(segment_durations.size())


func segment_at_playback_time(time_sec: float) -> Dictionary:
	if frames.size() < 2:
		return {"from_i": 0, "to_i": 0, "blend": 0.0, "round": 0}
	if segment_durations.is_empty():
		var seg: float = maxf(0.001, round_duration)
		var seg_idx: float = time_sec / seg
		var from_i: int = clampi(int(floor(seg_idx)), 0, frames.size() - 1)
		return {
			"from_i": from_i,
			"to_i": mini(from_i + 1, frames.size() - 1),
			"blend": clampf(seg_idx - float(from_i), 0.0, 1.0),
			"round": from_i,
		}
	var acc: float = 0.0
	for gap in range(segment_durations.size()):
		var dur: float = float(segment_durations[gap])
		if time_sec < acc + dur:
			var blend: float = clampf((time_sec - acc) / maxf(0.001, dur), 0.0, 1.0)
			return {"from_i": gap, "to_i": gap + 1, "blend": blend, "round": gap}
		acc += dur
	var last: int = frames.size() - 2
	return {"from_i": last, "to_i": last + 1, "blend": 1.0, "round": last}


func get_frame(index: int) -> Dictionary:
	if index < 0 or index >= frames.size():
		return {}
	return frames[index]


func apply_to_store(store: UnitSimulationStoreLib, frame_index: int) -> void:
	if store == null or frame_index < 0 or frame_index >= frames.size():
		return
	var frame: Dictionary = frames[frame_index]
	_apply_frame(store, frame, battle_data if battle_data != null else null)


func apply_interpolated(store: UnitSimulationStoreLib, from_idx: int, to_idx: int, blend: float) -> void:
	if store == null or frames.is_empty():
		return
	var a_idx: int = clampi(from_idx, 0, frames.size() - 1)
	var b_idx: int = clampi(to_idx, 0, frames.size() - 1)
	var a: Dictionary = frames[a_idx]
	var b: Dictionary = frames[b_idx]
	var t: float = clampf(blend, 0.0, 1.0)
	var use_b: bool = t >= 0.5
	var ax = a.get("grid_x", PackedInt32Array())
	var ay = a.get("grid_y", PackedInt32Array())
	var bx = b.get("grid_x", PackedInt32Array())
	var by = b.get("grid_y", PackedInt32Array())
	for i in range(store.count):
		if i >= ax.size() or i >= ay.size():
			continue
		if use_b and i < bx.size() and i < by.size():
			store.grid_x[i] = int(bx[i])
			store.grid_y[i] = int(by[i])
			store.health[i] = float(b["health"][i]) if i < b["health"].size() else store.health[i]
			store.flags[i] = int(b["flags"][i]) if i < b["flags"].size() else store.flags[i]
			store.routed[i] = int(b["routed"][i]) if i < b["routed"].size() else store.routed[i]
			store.tier[i] = int(b["tier"][i]) if i < b["tier"].size() else store.tier[i]
		else:
			store.grid_x[i] = int(ax[i])
			store.grid_y[i] = int(ay[i])
			store.health[i] = float(a["health"][i]) if i < a["health"].size() else store.health[i]
			store.flags[i] = int(a["flags"][i]) if i < a["flags"].size() else store.flags[i]
			store.routed[i] = int(a["routed"][i]) if i < a["routed"].size() else store.routed[i]
			store.tier[i] = int(a["tier"][i]) if i < a["tier"].size() else store.tier[i]
		if battle_data != null and i < bx.size() and i < by.size():
			var pos_a: Vector2 = battle_data.cell_center(int(ax[i]), int(ay[i]))
			var pos_b: Vector2 = battle_data.cell_center(int(bx[i]), int(by[i]))
			store.positions[i] = pos_a.lerp(pos_b, t)
		elif i < a["positions"].size() and i < b["positions"].size():
			store.positions[i] = a["positions"][i].lerp(b["positions"][i], t)
	store.sync_living_counts_from_flags()


func total_duration() -> float:
	if not segment_durations.is_empty():
		var total: float = 0.0
		for d in segment_durations:
			total += float(d)
		return total
	return maxf(0.0, float(maxi(0, frames.size() - 1)) * round_duration)


func _capture(store: UnitSimulationStoreLib, tile_owners: PackedByteArray = PackedByteArray()) -> Dictionary:
	var frame: Dictionary = {
		"positions": store.positions.duplicate(),
		"grid_x": store.grid_x.duplicate(),
		"grid_y": store.grid_y.duplicate(),
		"health": store.health.duplicate(),
		"flags": store.flags.duplicate(),
		"routed": store.routed.duplicate(),
		"tier": store.tier.duplicate(),
		"friendly_living": store.living_friendly_count(),
		"hostile_living": store.living_hostile_count(),
	}
	if not tile_owners.is_empty():
		frame["tile_owners"] = tile_owners.duplicate()
	return frame


func tile_owners_for_segment(from_i: int, to_i: int, blend: float) -> PackedByteArray:
	if frames.is_empty():
		return PackedByteArray()
	var use_i: int = from_i if blend < 0.5 else to_i
	use_i = clampi(use_i, 0, frames.size() - 1)
	return owners_from_frame(frames[use_i])


static func owners_from_frame(frame: Dictionary) -> PackedByteArray:
	var raw = frame.get("tile_owners", PackedByteArray())
	if raw is PackedByteArray:
		return raw
	if typeof(raw) == TYPE_ARRAY:
		var out := PackedByteArray()
		out.resize(raw.size())
		for i in range(raw.size()):
			out[i] = int(raw[i]) & 0xFF
		return out
	return PackedByteArray()


func _apply_frame(store: UnitSimulationStoreLib, frame: Dictionary, map_data = null) -> void:
	var n: int = mini(store.count, frame.get("positions", PackedVector2Array()).size())
	for i in range(n):
		store.positions[i] = frame["positions"][i]
		store.grid_x[i] = frame["grid_x"][i]
		store.grid_y[i] = frame["grid_y"][i]
		store.health[i] = frame["health"][i]
		store.flags[i] = frame["flags"][i]
		store.routed[i] = frame["routed"][i]
		store.tier[i] = frame["tier"][i]
		if map_data != null:
			store.positions[i] = map_data.cell_center(store.grid_x[i], store.grid_y[i])
	store.sync_living_counts_from_flags()
