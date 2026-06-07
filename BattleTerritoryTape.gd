class_name BattleTerritoryTape
extends RefCounted

const BattleReplayPackLib := preload("res://BattleReplayPack.gd")
const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTilePressureCodecLib := preload("res://BattleTilePressureCodec.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")
const BattleTerritoryReplayBakeLib := preload("res://BattleTerritoryReplayBake.gd")
const BattleTerritoryBakeWorkerLib := preload("res://BattleTerritoryBakeWorker.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")

const FRAME_SECONDS := BattleReplayPackLib.FRAME_SECONDS

var round_duration: float = FRAME_SECONDS
var record_stride: int = 4
var segment_durations: Array = []
var battle_data = null
var frames: Array = []
var result: Dictionary = {}
var resolve_ms: float = 0.0
## Wall-clock ms to pre-bake display images (Option D — once after sim).
var bake_ms: float = 0.0
var baked_png_frames: Array = []
var _owners_cache: PackedByteArray = PackedByteArray()
var _owners_frame_cache: Dictionary = {}
var _pressure_frame_cache: Dictionary = {}
var _baked_image_cache: Dictionary = {}


func record_frame(
	round_index: int,
	owners: PackedByteArray,
	pressure_friendly: PackedFloat32Array = PackedFloat32Array(),
	pressure_hostile: PackedFloat32Array = PackedFloat32Array(),
	friendly_count: int = -1,
	hostile_count: int = -1,
) -> void:
	var frame: Dictionary = {"round": round_index}
	if frames.is_empty():
		frame["tile_owners"] = owners.duplicate()
	else:
		var delta := PackedInt32Array()
		var base: PackedByteArray = _owners_cache
		if base.is_empty():
			base = owners_at_frame(frames.size() - 1)
		for i in range(mini(owners.size(), base.size())):
			if owners[i] != base[i]:
				delta.append(i)
				delta.append(int(owners[i]))
		frame["owner_delta"] = delta
	if (
		not pressure_friendly.is_empty()
		and not pressure_hostile.is_empty()
		and pressure_friendly.size() == owners.size()
	):
		frame["pressure_f"] = BattleTilePressureCodecLib.encode_v2(pressure_friendly)
		frame["pressure_h"] = BattleTilePressureCodecLib.encode_v2(pressure_hostile)
		frame["pressure_codec"] = 2
	if friendly_count >= 0 and hostile_count >= 0:
		frame["friendly_tiles"] = friendly_count
		frame["hostile_tiles"] = hostile_count
		frame["neutral_tiles"] = maxi(0, owners.size() - friendly_count - hostile_count)
	elif frames.is_empty():
		frame["friendly_tiles"] = _count_side(owners, BattleTileControlLib.OWNER_FRIENDLY)
		frame["hostile_tiles"] = _count_side(owners, BattleTileControlLib.OWNER_HOSTILE)
		frame["neutral_tiles"] = _count_side(owners, BattleTileControlLib.OWNER_NEUTRAL)
	else:
		var prev: Dictionary = frames[frames.size() - 1]
		var pf: int = int(prev.get("friendly_tiles", 0))
		var ph: int = int(prev.get("hostile_tiles", 0))
		var base_owners: PackedByteArray = _owners_cache
		if base_owners.is_empty():
			base_owners = owners_at_frame(frames.size() - 1)
		for i in range(mini(owners.size(), base_owners.size())):
			if owners[i] == base_owners[i]:
				continue
			match int(owners[i]):
				BattleTileControlLib.OWNER_FRIENDLY:
					pf += 1
				BattleTileControlLib.OWNER_HOSTILE:
					ph += 1
			match int(base_owners[i]):
				BattleTileControlLib.OWNER_FRIENDLY:
					pf = maxi(0, pf - 1)
				BattleTileControlLib.OWNER_HOSTILE:
					ph = maxi(0, ph - 1)
		frame["friendly_tiles"] = pf
		frame["hostile_tiles"] = ph
		frame["neutral_tiles"] = maxi(0, owners.size() - pf - ph)
	frames.append(frame)
	_invalidate_frame_caches()
	_owners_cache = owners_at_frame(frames.size() - 1)


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
		"resolve_mode": "territory",
		"pack_version": BattleReplayPackLib.VERSION_V2,
	}


func load_from_dictionary(data: Dictionary) -> void:
	round_duration = float(data.get("round_duration", 0.42))
	record_stride = int(data.get("record_stride", 1))
	resolve_ms = float(data.get("resolve_ms", 0.0))
	result = data.get("result", {})
	frames = data.get("frames", []).duplicate(true)
	segment_durations = data.get("segment_durations", []).duplicate()
	_owners_cache = PackedByteArray()
	_invalidate_frame_caches()
	if not frames.is_empty():
		_owners_cache = owners_at_frame(frames.size() - 1)
	if segment_durations.is_empty() and battle_data != null:
		rebuild_segment_timing()


func rebuild_segment_timing() -> void:
	segment_durations.clear()
	if frames.size() < 2 or battle_data == null:
		for _i in range(maxi(0, frames.size() - 1)):
			segment_durations.append(FRAME_SECONDS)
		return
	for i in range(frames.size() - 1):
		var dur: float = BattlePacingLib.territory_segment_duration_for_frames(
			frames[i], frames[i + 1], battle_data
		)
		segment_durations.append(dur)
	_normalize_segment_durations_to_target()


func _normalize_segment_durations_to_target() -> void:
	if segment_durations.is_empty():
		return
	var raw_total: float = 0.0
	for d in segment_durations:
		raw_total += float(d)
	if raw_total <= 0.0:
		return
	var sim_rounds: int = _estimate_sim_rounds_span()
	var target: float = BattlePacingLib.territory_replay_target_seconds(sim_rounds)
	# Only rescale when far from target — avoids crushing every replay to ~90s.
	if absf(raw_total - target) / maxf(target, 1.0) < 0.12:
		return
	var scale: float = target / raw_total
	var min_seg: float = BattlePacingLib.REPLAY_MIN_SEGMENT_SECONDS
	for i in range(segment_durations.size()):
		segment_durations[i] = maxf(min_seg, float(segment_durations[i]) * scale)


func _estimate_sim_rounds_span() -> int:
	if frames.is_empty():
		return 0
	var r0: int = int(frames[0].get("round", 0))
	var r1: int = int(frames[frames.size() - 1].get("round", r0))
	var span: int = maxi(1, r1 - r0)
	if span <= 1 and frames.size() > 1:
		span = maxi(1, (frames.size() - 1) * maxi(1, record_stride))
	return span


func _invalidate_frame_caches() -> void:
	_owners_frame_cache.clear()
	_pressure_frame_cache.clear()
	clear_baked_display()


func has_baked_display() -> bool:
	return not baked_png_frames.is_empty() and baked_png_frames.size() == frames.size()


func clear_baked_display() -> void:
	baked_png_frames.clear()
	_baked_image_cache.clear()
	bake_ms = 0.0


func bake_display_frames(map_data, progress_out: Dictionary = {}) -> void:
	clear_baked_display()
	if map_data == null or frames.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	var total: int = frames.size()
	baked_png_frames.resize(total)
	_warm_frame_caches_for_bake(total)
	if not _bake_display_frames_rust_parallel(map_data, progress_out, total):
		var workers: int = _bake_worker_count(total)
		if workers <= 1:
			_bake_display_frames_sequential(map_data, progress_out, total)
		else:
			_bake_display_frames_parallel(map_data, progress_out, total, workers)
	_baked_image_cache.clear()
	bake_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	RunLog.info("Territory bake %d frames in %.1f ms" % [total, bake_ms])


func _warm_frame_caches_for_bake(total: int) -> void:
	for fi in range(total):
		pressures_at_frame(fi)
		owners_at_frame(fi)


static func _bake_worker_count(frame_count: int) -> int:
	if frame_count < 4:
		return 1
	var cores: int = OS.get_processor_count()
	return clampi(mini(cores - 1, 8), 2, frame_count)


func _bake_display_frames_rust_parallel(
	map_data,
	progress_out: Dictionary,
	total: int,
) -> bool:
	if not BattleTerritoryRustBackendLib.extension_available():
		return false
	var frames_f: Array = []
	var frames_h: Array = []
	for fi in range(total):
		var pressures: Dictionary = pressures_at_frame(fi)
		var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
		var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
		if pf.is_empty() or ph.is_empty():
			return false
		frames_f.append(pf)
		frames_h.append(ph)
	if not progress_out.is_empty():
		progress_out["phase"] = "bake"
		progress_out["bake_done"] = 0
		progress_out["bake_total"] = total
	var sim: RefCounted = ClassDB.instantiate("TerritorySim")
	var land_mask: PackedByteArray = BattleTerritoryRustBackendLib._claimable_mask_from_map(
		map_data
	)
	var results: Array = sim.call(
		"bake_fluid_frames_parallel",
		map_data.grid_width,
		map_data.grid_height,
		land_mask,
		frames_f,
		frames_h,
		1.0,
	)
	if results.size() != total:
		return false
	for fi in range(total):
		baked_png_frames[fi] = results[fi]
		_bake_report_progress(progress_out, fi + 1, total)
	return true


func _bake_display_frames_sequential(map_data, progress_out: Dictionary, total: int) -> void:
	for fi in range(total):
		baked_png_frames[fi] = BattleTerritoryReplayBakeLib.bake_frame_rgba(self, fi, map_data)
		_bake_report_progress(progress_out, fi + 1, total)


func _bake_display_frames_parallel(
	map_data,
	progress_out: Dictionary,
	total: int,
	workers: int,
) -> void:
	if not progress_out.is_empty():
		progress_out["phase"] = "bake"
		progress_out["bake_done"] = 0
		progress_out["bake_total"] = total
	var frame_mutex := Mutex.new()
	var progress_mutex := Mutex.new()
	var task_ids: Array = []
	var chunk: int = int(ceili(float(total) / float(workers)))
	var range_start: int = 0
	while range_start < total:
		var range_end: int = mini(total, range_start + chunk)
		var lo: int = range_start
		var hi: int = range_end
		task_ids.append(
			WorkerThreadPool.add_task(
				BattleTerritoryBakeWorkerLib.bake_frame_range.bind(
					self,
					map_data,
					lo,
					hi,
					baked_png_frames,
					frame_mutex,
					progress_mutex,
					progress_out,
				)
			)
		)
		range_start = range_end
	for tid in task_ids:
		WorkerThreadPool.wait_for_task_completion(tid)
	_rebake_missing_display_frames(map_data, total)


func _rebake_missing_display_frames(map_data, total: int) -> void:
	for fi in range(total):
		var raw: Variant = baked_png_frames[fi]
		if raw is PackedByteArray and not (raw as PackedByteArray).is_empty():
			continue
		baked_png_frames[fi] = BattleTerritoryReplayBakeLib.bake_frame_rgba(self, fi, map_data)


func _bake_report_progress(progress_out: Dictionary, done: int, total: int) -> void:
	if progress_out.is_empty():
		return
	progress_out["phase"] = "bake"
	progress_out["bake_done"] = done
	progress_out["bake_total"] = total


static func _buffer_is_png(buf: PackedByteArray) -> bool:
	return buf.size() >= 4 and buf[0] == 137 and buf[1] == 80 and buf[2] == 78 and buf[3] == 71


func get_baked_image(frame_index: int) -> Image:
	if frame_index < 0 or frame_index >= baked_png_frames.size():
		return null
	if _baked_image_cache.has(frame_index):
		return _baked_image_cache[frame_index] as Image
	var raw: PackedByteArray = baked_png_frames[frame_index]
	if raw.is_empty():
		return null
	var img := Image.new()
	if _buffer_is_png(raw):
		if img.load_png_from_buffer(raw) != OK:
			return null
	elif battle_data != null:
		var w: int = battle_data.grid_width
		var h: int = battle_data.grid_height
		if raw.size() != w * h * 4:
			return null
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.set_data(w, h, false, Image.FORMAT_RGBA8, raw)
	else:
		return null
	_baked_image_cache[frame_index] = img
	return img


func get_baked_image_for_segment(from_i: int, to_i: int, blend: float) -> Image:
	if not has_baked_display():
		return null
	if from_i < 0 or from_i >= baked_png_frames.size():
		return null
	if to_i < 0 or to_i >= baked_png_frames.size() or blend <= 0.001 or from_i == to_i:
		return get_baked_image(from_i)
	# Snap between keyframes at playback — pixel lerp was still blocking the main thread.
	if blend >= 0.5:
		return get_baked_image(to_i)
	return get_baked_image(from_i)


func segment_at_playback_time(time_sec: float) -> Dictionary:
	if frames.is_empty():
		return {"from_i": 0, "to_i": 0, "blend": 0.0, "round": 0}
	var elapsed: float = 0.0
	for i in range(frames.size() - 1):
		var seg: float = FRAME_SECONDS
		if i < segment_durations.size():
			seg = float(segment_durations[i])
		if time_sec < elapsed + seg:
			var blend: float = clampf((time_sec - elapsed) / maxf(seg, 0.001), 0.0, 1.0)
			return _segment_indices(i, i + 1, blend)
		elapsed += seg
	var last_i: int = frames.size() - 1
	return _segment_indices(last_i, last_i, 1.0)


func total_duration() -> float:
	if segment_durations.is_empty():
		return maxf(0.0, float(maxi(0, frames.size() - 1)) * FRAME_SECONDS)
	var total: float = 0.0
	for d in segment_durations:
		total += float(d)
	return total


func get_frame(index: int) -> Dictionary:
	if index < 0 or index >= frames.size():
		return {}
	return frames[index]


func owners_at_frame(index: int) -> PackedByteArray:
	if index < 0 or index >= frames.size():
		return PackedByteArray()
	if _owners_frame_cache.has(index):
		return (_owners_frame_cache[index] as PackedByteArray).duplicate()
	var out: PackedByteArray = PackedByteArray()
	var full_at: int = -1
	for fi in range(index + 1):
		var frame: Dictionary = frames[fi]
		if frame.has("tile_owners"):
			var raw = frame["tile_owners"]
			if raw is PackedByteArray and not raw.is_empty():
				out = raw.duplicate()
				full_at = fi
	if out.is_empty():
		return PackedByteArray()
	for fi in range(full_at + 1, index + 1):
		var frame: Dictionary = frames[fi]
		var delta = frame.get("owner_delta", PackedInt32Array())
		if delta is PackedInt32Array:
			for j in range(0, delta.size(), 2):
				if j + 1 < delta.size():
					out[delta[j]] = delta[j + 1] & 0xFF
	_owners_frame_cache[index] = out.duplicate()
	return out


static func frame_has_pressure_blob(frame: Dictionary) -> bool:
	if frame.is_empty():
		return false
	if frame.has("pressure_friendly") or frame.has("pressure_hostile"):
		return true
	var pf = frame.get("pressure_f", PackedByteArray())
	var ph = frame.get("pressure_h", PackedByteArray())
	return (
		pf is PackedByteArray
		and ph is PackedByteArray
		and not pf.is_empty()
		and not ph.is_empty()
	)


func _pressure_keyframe_index(index: int) -> int:
	if frames.is_empty():
		return 0
	var clamped: int = clampi(index, 0, frames.size() - 1)
	for i in range(clamped, -1, -1):
		if frame_has_pressure_blob(frames[i]):
			return i
	for i in range(frames.size()):
		if frame_has_pressure_blob(frames[i]):
			return i
	return 0


func pressures_at_frame(index: int) -> Dictionary:
	if index < 0 or index >= frames.size():
		return {"f": PackedFloat32Array(), "h": PackedFloat32Array()}
	if _pressure_frame_cache.has(index):
		var cached: Dictionary = _pressure_frame_cache[index]
		return {
			"f": (cached.get("f", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
			"h": (cached.get("h", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		}
	var key_i: int = _pressure_keyframe_index(index)
	var key_frame: Dictionary = frames[key_i]
	var pf: PackedFloat32Array = pressure_friendly_from_frame(key_frame)
	var ph: PackedFloat32Array = pressure_hostile_from_frame(key_frame)
	_pressure_frame_cache[index] = {"f": pf.duplicate(), "h": ph.duplicate()}
	return {"f": pf, "h": ph}


static func owners_from_frame(frame: Dictionary) -> PackedByteArray:
	var raw = frame.get("tile_owners", PackedByteArray())
	if raw is PackedByteArray and not raw.is_empty():
		return raw
	return PackedByteArray()


static func owners_from_frame_at_index(tape: BattleTerritoryTape, index: int) -> PackedByteArray:
	if tape == null:
		return PackedByteArray()
	return tape.owners_at_frame(index)


static func pressure_friendly_from_frame(frame: Dictionary) -> PackedFloat32Array:
	if frame.is_empty():
		return PackedFloat32Array()
	if frame.has("pressure_friendly") and frame["pressure_friendly"] is PackedFloat32Array:
		return frame["pressure_friendly"]
	var blob = frame.get("pressure_f", PackedByteArray())
	if blob is PackedByteArray and not blob.is_empty():
		var codec: int = int(frame.get("pressure_codec", 1))
		if codec >= 2:
			return BattleTilePressureCodecLib.decode_v2(blob)
		return BattleTilePressureCodecLib.decode(blob)
	return PackedFloat32Array()


static func pressure_hostile_from_frame(frame: Dictionary) -> PackedFloat32Array:
	if frame.is_empty():
		return PackedFloat32Array()
	if frame.has("pressure_hostile") and frame["pressure_hostile"] is PackedFloat32Array:
		return frame["pressure_hostile"]
	var blob = frame.get("pressure_h", PackedByteArray())
	if blob is PackedByteArray and not blob.is_empty():
		var codec: int = int(frame.get("pressure_codec", 1))
		if codec >= 2:
			return BattleTilePressureCodecLib.decode_v2(blob)
		return BattleTilePressureCodecLib.decode(blob)
	return PackedFloat32Array()


func _segment_indices(from_i: int, to_i: int, blend: float) -> Dictionary:
	var r0: int = int(frames[from_i].get("round", from_i)) if from_i < frames.size() else 0
	var r1: int = int(frames[to_i].get("round", r0)) if to_i < frames.size() else r0
	return {
		"from_i": from_i,
		"to_i": to_i,
		"blend": blend,
		"round": int(lerpf(float(r0), float(r1), blend)),
	}


static func _count_side(owners: PackedByteArray, owner_val: int) -> int:
	var n: int = 0
	for i in range(owners.size()):
		if owners[i] == owner_val:
			n += 1
	return n
