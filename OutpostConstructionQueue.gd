class_name OutpostConstructionQueue
extends RefCounted

## Frame-budgeted visual work queue: corridors → beachhead → roads → markers → overlay → gpu.
## Pure scheduling — WorldConquestScreen executes drain_plan() side effects.

const CFG := preload("res://WorldConquestConfig.gd")

var _road_sids: Array[int] = []
var _marker_sids: Array[int] = []
var _corridor_sids: Array[int] = []
var _beachheads: Array[Dictionary] = []
var _overlay_indices: PackedInt32Array = PackedInt32Array()
var _overlay_values: PackedByteArray = PackedByteArray()
var _gpu_upload_pending: bool = false
var _last_overlay_drain_frame: int = -1


static func _enqueue_unique(arr: Array[int], sid: int) -> void:
	if sid < 0 or arr.has(sid):
		return
	arr.append(sid)


func on_cell_advanced(sid: int) -> void:
	_enqueue_unique(_road_sids, sid)
	_enqueue_unique(_corridor_sids, sid)


func on_path_completed(sid: int, gx: int, gy: int, team: int, immediate_backend: bool = false) -> void:
	_enqueue_unique(_road_sids, sid)
	_enqueue_unique(_marker_sids, sid)
	_enqueue_unique(_corridor_sids, sid)
	_beachheads.append({
		"sid": sid,
		"gx": gx,
		"gy": gy,
		"team": team,
		"immediate": immediate_backend,
	})


func on_build_completed(sid: int) -> void:
	_enqueue_unique(_marker_sids, sid)
	_enqueue_unique(_corridor_sids, sid)


func enqueue_road(sid: int) -> void:
	_enqueue_unique(_road_sids, sid)


func enqueue_marker(sid: int) -> void:
	_enqueue_unique(_marker_sids, sid)


func enqueue_corridor(sid: int) -> void:
	_enqueue_unique(_corridor_sids, sid)


func enqueue_overlay_delta(indices: PackedInt32Array, values: PackedByteArray) -> void:
	var n: int = mini(indices.size(), values.size())
	if n <= 0:
		return
	for i in range(n):
		_overlay_indices.append(indices[i])
		_overlay_values.append(values[i])


func request_gpu_upload() -> void:
	_gpu_upload_pending = true


func overlay_pending_count() -> int:
	return _overlay_indices.size()


func gpu_upload_pending() -> bool:
	return _gpu_upload_pending


func last_overlay_drain_frame() -> int:
	return _last_overlay_drain_frame


func has_pending() -> bool:
	return (
		not _road_sids.is_empty()
		or not _marker_sids.is_empty()
		or not _corridor_sids.is_empty()
		or not _beachheads.is_empty()
		or not _overlay_indices.is_empty()
		or _gpu_upload_pending
	)


func pending_counts() -> Dictionary:
	return {
		"roads": _road_sids.size(),
		"markers": _marker_sids.size(),
		"corridors": _corridor_sids.size(),
		"beachheads": _beachheads.size(),
		"overlay_cells": _overlay_indices.size(),
		"gpu_upload": 1 if _gpu_upload_pending else 0,
	}


## Returns incremental work for one frame. Never sets full_map_sync.
## Drain order: corridors → beachhead → roads → markers → overlay (capped) → gpu (only if no visual work above).
func drain_plan(current_frame: int) -> Dictionary:
	var plan := {
		"road_sids": [] as Array[int],
		"marker_sids": [] as Array[int],
		"corridor_sids": [] as Array[int],
		"beachhead": {} as Dictionary,
		"immediate_backend": false,
		"full_map_sync": false,
		"overlay_indices": PackedInt32Array(),
		"overlay_values": PackedByteArray(),
		"gpu_upload": false,
	}

	var max_corridor: int = CFG.MAX_CORRIDOR_SIDS_PER_FRAME
	while plan.corridor_sids.size() < max_corridor and not _corridor_sids.is_empty():
		var sid: int = _corridor_sids.pop_front()
		if sid >= 0 and not plan.corridor_sids.has(sid):
			plan.corridor_sids.append(sid)

	for i in range(_beachheads.size()):
		var bh: Dictionary = _beachheads[i]
		if bool(bh.get("immediate", false)):
			plan.beachhead = bh
			plan.immediate_backend = true
			_beachheads.remove_at(i)
			var bh_sid: int = int(bh.get("sid", -1))
			if bh_sid >= 0 and not plan.corridor_sids.has(bh_sid):
				plan.corridor_sids.append(bh_sid)
			break

	var max_roads: int = CFG.MAX_ROAD_SIDS_PER_FRAME
	while plan.road_sids.size() < max_roads and not _road_sids.is_empty():
		plan.road_sids.append(_road_sids.pop_front())

	var max_markers: int = CFG.MAX_MARKER_SIDS_PER_FRAME
	while plan.marker_sids.size() < max_markers and not _marker_sids.is_empty():
		plan.marker_sids.append(_marker_sids.pop_front())

	if plan.beachhead.is_empty() and not _beachheads.is_empty():
		plan.beachhead = _beachheads.pop_front()

	var overlay_n: int = 0
	var cap: int = CFG.OVERLAY_DELTA_CELLS_PER_FRAME
	if not _overlay_indices.is_empty():
		overlay_n = mini(_overlay_indices.size(), cap)
		plan.overlay_indices = _overlay_indices.slice(0, overlay_n)
		plan.overlay_values = _overlay_values.slice(0, overlay_n)
		if _overlay_indices.size() > overlay_n:
			_overlay_indices = _overlay_indices.slice(overlay_n, _overlay_indices.size())
			_overlay_values = _overlay_values.slice(overlay_n, _overlay_values.size())
		else:
			_overlay_indices = PackedInt32Array()
			_overlay_values = PackedByteArray()
		_last_overlay_drain_frame = current_frame

	var visual_drained: bool = (
		not plan.corridor_sids.is_empty()
		or not plan.beachhead.is_empty()
		or not plan.road_sids.is_empty()
		or not plan.marker_sids.is_empty()
		or overlay_n > 0
	)
	if not visual_drained and _gpu_upload_pending:
		var overlay_cooldown_ok: bool = (
			_last_overlay_drain_frame < 0
			or current_frame > _last_overlay_drain_frame + 1
		)
		if overlay_cooldown_ok:
			plan.gpu_upload = true

	return plan


func mark_gpu_upload_committed() -> void:
	_gpu_upload_pending = false