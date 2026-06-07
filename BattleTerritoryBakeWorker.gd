class_name BattleTerritoryBakeWorker
extends RefCounted

const BattleTerritoryReplayBakeLib := preload("res://BattleTerritoryReplayBake.gd")


## WorkerThreadPool entry: bake [from_i, to_i) into out_frames[fi] (disjoint ranges).
static func bake_frame_range(
	tape,
	map_data,
	from_i: int,
	to_i: int,
	out_frames: Array,
	frame_mutex: Mutex,
	progress_mutex: Mutex,
	progress_out: Dictionary,
) -> void:
	for fi in range(from_i, to_i):
		var rgba: PackedByteArray = BattleTerritoryReplayBakeLib.bake_frame_rgba(tape, fi, map_data)
		if frame_mutex != null:
			frame_mutex.lock()
		out_frames[fi] = rgba
		if frame_mutex != null:
			frame_mutex.unlock()
	if progress_mutex == null or progress_out.is_empty():
		return
	progress_mutex.lock()
	progress_out["phase"] = "bake"
	progress_out["bake_done"] = int(progress_out.get("bake_done", 0)) + (to_i - from_i)
	progress_mutex.unlock()
