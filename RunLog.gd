# RunLog.gd — autoload session log capture (no class_name).
extends Node

const LATEST_FILENAME := "latest_run.txt"
const FLUSH_INTERVAL_SEC := 0.25
const MAX_SESSION_LINES := 10000

var _log_dir := ""
var _latest_path := ""
var _timestamped_path := ""
var _file: FileAccess = null
var _copy_file: FileAccess = null
var _run_seed_note := "(not started)"
var _mutex := Mutex.new()
var _engine_logger: _RunEngineLogger = null
var _verbose := false
var _capture_prints := false
var _pending_lines: PackedStringArray = PackedStringArray()
var _flush_timer := 0.0
var _line_count := 0
var _truncated := false


class _RunEngineLogger extends Logger:
	var _owner: Node = null

	func _init(owner: Node) -> void:
		_owner = owner

	func _log_message(message: String, error: bool) -> void:
		if _owner == null:
			return
		if error:
			_owner._write_engine_line("ERROR", message)
		elif _owner._capture_prints:
			_owner._write_engine_line("PRINT", message)

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if _owner == null:
			return
		var level := "ERROR"
		if error_type == 1:
			level = "WARN"
		var detail := rationale if not rationale.is_empty() else code
		if detail.is_empty():
			detail = "(no message)"
		var location := "%s:%d" % [file.get_file(), line] if not file.is_empty() else function
		_owner._write_engine_line(level, "%s — %s" % [location, detail])


func _init() -> void:
	_engine_logger = _RunEngineLogger.new(self)
	OS.add_logger(_engine_logger)
	_begin_session()


func _ready() -> void:
	set_process(true)
	var announcement := get_startup_announcement()
	print(announcement)
	info("RunLog ready — %s" % announcement)


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL_SEC:
		_flush_timer = 0.0
		_flush_pending()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_pending()


func _exit_tree() -> void:
	_flush_pending()
	_close_files()


func set_verbose(enabled: bool) -> void:
	_verbose = enabled
	_capture_prints = enabled


func is_verbose() -> bool:
	return _verbose


func get_session_path() -> String:
	return _latest_path


func flush_now() -> void:
	_flush_pending(true)


func get_workspace_log_dir() -> String:
	return _log_dir


## Safe logging for scripts compiled before the RunLog autoload is registered (-s smoke tests).
static func emit_info(msg: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var rl: Node = tree.root.get_node_or_null("RunLog")
		if rl != null and rl.has_method("info"):
			rl.call("info", msg)
			return
	print(msg)


func get_disk_hint() -> String:
	return _latest_path


func debug(msg: String) -> void:
	if _verbose:
		_write_line("DEBUG", msg)


func info(msg: String) -> void:
	_write_line("INFO", msg)


func warn(msg: String) -> void:
	_write_line("WARN", msg)


func error(msg: String) -> void:
	_write_line("ERROR", msg)


func comms(msg: String) -> void:
	_write_line("COMMS", msg)


func perf(msg: String) -> void:
	if _verbose:
		_write_line("PERF", msg)


func note_run_seed(run_seed: int) -> void:
	_run_seed_note = str(run_seed)
	info("Run seed set: %d" % run_seed)


func push_error_msg(msg: String) -> void:
	error(msg)
	push_error(msg)


func get_startup_announcement() -> String:
	return "Session log: %s" % _latest_path


func _get_workspace_log_dir() -> String:
	var project_root := ProjectSettings.globalize_path("res://")
	return project_root.path_join("logs")


func _begin_session() -> void:
	_mutex.lock()
	_close_files()
	_pending_lines.clear()
	_line_count = 0
	_truncated = false
	_log_dir = _get_workspace_log_dir()
	if DirAccess.make_dir_recursive_absolute(_log_dir) != OK:
		push_error("RunLog: failed to create %s" % _log_dir)
		_mutex.unlock()
		return
	var stamp := _session_timestamp()
	_latest_path = _log_dir.path_join(LATEST_FILENAME)
	_timestamped_path = _log_dir.path_join("run_%s.txt" % stamp)
	_file = FileAccess.open(_latest_path, FileAccess.WRITE)
	_copy_file = FileAccess.open(_timestamped_path, FileAccess.WRITE)
	if _file == null:
		push_error("RunLog: failed to open %s" % _latest_path)
		_mutex.unlock()
		return
	_write_header()
	_flush_pending(true)
	_mutex.unlock()


func _write_header() -> void:
	var version := Engine.get_version_info()
	var version_text := "%d.%d.%d.%s" % [
		version.get("major", 0),
		version.get("minor", 0),
		version.get("patch", 0),
		version.get("status", "unknown"),
	]
	var started := Time.get_datetime_string_from_system(true)
	var header_lines: PackedStringArray = PackedStringArray([
		"=== Empires of Yesterday — Session Log ===",
		"Started: %s" % started,
		"Godot: %s" % version_text,
		"Run seed: %s" % _run_seed_note,
		"Workspace latest: %s" % _latest_path,
		"Workspace archive: %s" % _timestamped_path,
		"==========================================",
		"",
	])
	for line in header_lines:
		_enqueue_raw(line)


func _write_line(level: String, msg: String) -> void:
	var stamp := Time.get_datetime_string_from_system(true)
	_enqueue_raw("[%s] [%s] %s" % [stamp, level, msg])


func _write_engine_line(level: String, msg: String) -> void:
	var stamp := Time.get_datetime_string_from_system(true)
	_enqueue_raw("[%s] [ENGINE:%s] %s" % [stamp, level, msg])


func _enqueue_raw(line: String) -> void:
	if _truncated:
		return
	_mutex.lock()
	_pending_lines.append(line)
	_mutex.unlock()


func _flush_pending(_force: bool = false) -> void:
	_mutex.lock()
	if _pending_lines.is_empty():
		_mutex.unlock()
		return
	var batch := _pending_lines
	_pending_lines = PackedStringArray()
	_mutex.unlock()
	if _file == null and _copy_file == null:
		return
	_mutex.lock()
	for line in batch:
		if _line_count >= MAX_SESSION_LINES:
			if not _truncated:
				_truncated = true
				var note := "... [RunLog truncated — max %d lines per session] ..." % MAX_SESSION_LINES
				if _file:
					_file.store_line(note)
				if _copy_file:
					_copy_file.store_line(note)
				_line_count += 1
			break
		if _file:
			_file.store_line(line)
		if _copy_file:
			_copy_file.store_line(line)
		_line_count += 1
	if _file:
		_file.flush()
	if _copy_file:
		_copy_file.flush()
	_mutex.unlock()


func _close_files() -> void:
	if _file:
		_file.close()
		_file = null
	if _copy_file:
		_copy_file.close()
		_copy_file = null


func _session_timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [
		dt.get("year", 1970),
		dt.get("month", 1),
		dt.get("day", 1),
		dt.get("hour", 0),
		dt.get("minute", 0),
		dt.get("second", 0),
	]
