# ActivityTrace.gd — autoload twin-file activity + FPS timeline (no class_name).
# Cross-reference txn volume vs FPS by shared t_ms (Time.get_ticks_msec).
#
# Files (under res://logs/ → project logs/):
#   activity_txn_latest.txt   — every command / SCD1 pull (append-only)
#   activity_fps_latest.txt   — FPS / frame_ms samples (append-only)
#   activity_txn_<stamp>.txt / activity_fps_<stamp>.txt — session archives
#
# Disable: EOY_ACTIVITY_TRACE=0
# FPS sample Hz: EOY_ACTIVITY_FPS_HZ (default 4)
extends Node

const LOG_DIR_NAME := "logs"
const TXN_LATEST := "activity_txn_latest.txt"
const FPS_LATEST := "activity_fps_latest.txt"
const MAX_TXN_LINES := 200000
const MAX_FPS_LINES := 50000
const DEFAULT_FPS_HZ := 4.0

var _enabled: bool = true
var _txn_file: FileAccess = null
var _fps_file: FileAccess = null
var _txn_archive: FileAccess = null
var _fps_archive: FileAccess = null
var _txn_lines: int = 0
var _fps_lines: int = 0
var _fps_accum_sec: float = 0.0
var _fps_interval_sec: float = 1.0 / DEFAULT_FPS_HZ
var _match_label: String = ""
var _session_stamp: String = ""


func _ready() -> void:
	_enabled = OS.get_environment("EOY_ACTIVITY_TRACE") != "0"
	var hz_env: String = OS.get_environment("EOY_ACTIVITY_FPS_HZ").strip_edges()
	if not hz_env.is_empty():
		_fps_interval_sec = 1.0 / maxf(0.5, float(hz_env))
	else:
		_fps_interval_sec = 1.0 / DEFAULT_FPS_HZ
	if _enabled:
		_open_session("boot")
		RunLog.info(
			"ActivityTrace on — txn=%s fps=%s (set EOY_ACTIVITY_TRACE=0 to disable)"
			% [txn_path(), fps_path()]
		)


func is_enabled() -> bool:
	return _enabled


func txn_path() -> String:
	return _log_dir().path_join(TXN_LATEST)


func fps_path() -> String:
	return _log_dir().path_join(FPS_LATEST)


## Call when a World Conquest match actually starts (after bootstrap).
func begin_match(label: String = "") -> void:
	if not _enabled:
		return
	_match_label = label if not label.is_empty() else "match"
	_open_session(_match_label)
	txn("match_begin", {"label": _match_label})


func end_match() -> void:
	if not _enabled:
		return
	txn("match_end", {"label": _match_label})
	flush()


## Append one activity/txn line. kind examples: scd1_pull, place, destroy, sim, full_resync.
func txn(kind: String, fields: Dictionary = {}) -> void:
	if not _enabled:
		return
	_write_txn(_format_line("TXN", kind, fields))


## Periodic FPS sample — call from screen _process with delta.
func tick_fps(delta: float, frame_ms: float, extra: Dictionary = {}) -> void:
	if not _enabled:
		return
	_fps_accum_sec += delta
	if _fps_accum_sec < _fps_interval_sec:
		return
	_fps_accum_sec = 0.0
	var fps: float = Engine.get_frames_per_second()
	var fields: Dictionary = {
		"fps": snappedf(fps, 0.1),
		"frame_ms": snappedf(frame_ms, 0.01),
	}
	for k in extra.keys():
		fields[k] = extra[k]
	_write_fps(_format_line("FPS", "sample", fields))


func flush() -> void:
	if _txn_file:
		_txn_file.flush()
	if _fps_file:
		_fps_file.flush()
	if _txn_archive:
		_txn_archive.flush()
	if _fps_archive:
		_fps_archive.flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func _exit_tree() -> void:
	flush()
	_close_files()


func _log_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join(LOG_DIR_NAME)


func _open_session(label: String) -> void:
	_close_files()
	_txn_lines = 0
	_fps_lines = 0
	_fps_accum_sec = 0.0
	var dir: String = _log_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_session_stamp = _stamp()
	_txn_file = FileAccess.open(dir.path_join(TXN_LATEST), FileAccess.WRITE)
	_fps_file = FileAccess.open(dir.path_join(FPS_LATEST), FileAccess.WRITE)
	_txn_archive = FileAccess.open(
		dir.path_join("activity_txn_%s.txt" % _session_stamp), FileAccess.WRITE
	)
	_fps_archive = FileAccess.open(
		dir.path_join("activity_fps_%s.txt" % _session_stamp), FileAccess.WRITE
	)
	var header := (
		"# ActivityTrace session=%s label=%s t_ms=Time.get_ticks_msec cross-ref FPS file by t_ms"
		% [_session_stamp, label]
	)
	_write_txn(header)
	_write_fps(header)
	_write_txn("# format: t_ms=N wall=ISO TXN kind=... key=value...")
	_write_fps("# format: t_ms=N wall=ISO FPS kind=sample fps=.. frame_ms=..")


func _format_line(channel: String, kind: String, fields: Dictionary) -> String:
	var t_ms: int = Time.get_ticks_msec()
	var wall: String = Time.get_datetime_string_from_system(true)
	var parts: PackedStringArray = PackedStringArray([
		"t_ms=%d" % t_ms,
		"wall=%s" % wall,
		channel,
		"kind=%s" % kind,
	])
	for k in fields.keys():
		var v: Variant = fields[k]
		var s: String = str(v)
		# Keep single-line; replace spaces in values lightly.
		if s.contains(" "):
			s = s.replace(" ", "_")
		parts.append("%s=%s" % [str(k), s])
	return " ".join(parts)


func _write_txn(line: String) -> void:
	if _txn_lines >= MAX_TXN_LINES:
		return
	if _txn_file:
		_txn_file.store_line(line)
	if _txn_archive:
		_txn_archive.store_line(line)
	_txn_lines += 1
	if _txn_lines % 64 == 0:
		flush()


func _write_fps(line: String) -> void:
	if _fps_lines >= MAX_FPS_LINES:
		return
	if _fps_file:
		_fps_file.store_line(line)
	if _fps_archive:
		_fps_archive.store_line(line)
	_fps_lines += 1
	if _fps_lines % 16 == 0:
		flush()


func _close_files() -> void:
	if _txn_file:
		_txn_file.close()
		_txn_file = null
	if _fps_file:
		_fps_file.close()
		_fps_file = null
	if _txn_archive:
		_txn_archive.close()
		_txn_archive = null
	if _fps_archive:
		_fps_archive.close()
		_fps_archive = null


func _stamp() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [
		dt.get("year", 1970),
		dt.get("month", 1),
		dt.get("day", 1),
		dt.get("hour", 0),
		dt.get("minute", 0),
		dt.get("second", 0),
	]


## Helper: summarize an SCD1 batch for txn logging (row/cell pressure).
static func scd1_batch_stats(domain: String, batch: Dictionary) -> Dictionary:
	var rows: int = 0
	if batch.has("rows") and batch.get("rows") is Array:
		rows = (batch.get("rows") as Array).size()
	elif batch.has("indices") and batch.get("indices") is PackedInt32Array:
		rows = (batch.get("indices") as PackedInt32Array).size()
	elif batch.has("display_indices") and batch.get("display_indices") is PackedInt32Array:
		rows = (batch.get("display_indices") as PackedInt32Array).size()
	var removed: int = 0
	if batch.has("removed_ids") and batch.get("removed_ids") is PackedInt32Array:
		removed = (batch.get("removed_ids") as PackedInt32Array).size()
	return {
		"domain": domain,
		"mode": "full" if bool(batch.get("full", false)) else "incr",
		"empty": 1 if bool(batch.get("empty", false)) else 0,
		"rows": rows,
		"removed": removed,
		"high_water": int(batch.get("high_water", 0)),
		"denied_cd": 1 if bool(batch.get("full_denied_cooldown", false)) else 0,
	}
