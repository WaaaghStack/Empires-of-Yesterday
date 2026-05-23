# SaveManager.gd — autoload for permanent meta progression.
extends Node

const SAVE_PATH := "user://profile.save"

const DEFAULT_UNLOCKED_CLASSES: Array[int] = [0, 1]

const CLASS_UNLOCK_COSTS: Dictionary = {
	2: 3,
	3: 5,
}

var command_tokens: int = 0
var total_runs: int = 0
var total_ops_cleared: int = 0
var best_run_depth: int = 0
var unlocked_classes: Array[int] = []
var unlocked_portraits: Array[String] = []
var discovered_modifiers: Array[String] = []
var discovered_enemies: Array[String] = []
var discovered_objectives: Array[String] = []
var daily_best_date: String = ""
var daily_best_ops: int = 0
var daily_best_kia: int = 999
var daily_best_time: float = 999999.0


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	unlocked_classes = DEFAULT_UNLOCKED_CLASSES.duplicate()
	unlocked_portraits.clear()
	discovered_modifiers.clear()
	discovered_enemies.clear()
	discovered_objectives.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		_seed_default_portraits()
		save_profile()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		_seed_default_portraits()
		return
	var json_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_seed_default_portraits()
		return
	var data: Dictionary = parsed
	command_tokens = int(data.get("command_tokens", 0))
	total_runs = int(data.get("total_runs", 0))
	total_ops_cleared = int(data.get("total_ops_cleared", 0))
	best_run_depth = int(data.get("best_run_depth", 0))
	unlocked_classes = _array_to_classes(data.get("unlocked_classes", []))
	unlocked_portraits = _to_string_array(data.get("unlocked_portraits", []))
	discovered_modifiers = _to_string_array(data.get("discovered_modifiers", []))
	discovered_enemies = _to_string_array(data.get("discovered_enemies", []))
	discovered_objectives = _to_string_array(data.get("discovered_objectives", []))
	daily_best_date = str(data.get("daily_best_date", ""))
	daily_best_ops = int(data.get("daily_best_ops", 0))
	daily_best_kia = int(data.get("daily_best_kia", 999))
	daily_best_time = float(data.get("daily_best_time", 999999.0))
	if unlocked_portraits.is_empty():
		_seed_default_portraits()
	_reset_daily_if_stale()


func save_profile() -> void:
	var data := {
		"command_tokens": command_tokens,
		"total_runs": total_runs,
		"total_ops_cleared": total_ops_cleared,
		"best_run_depth": best_run_depth,
		"unlocked_classes": unlocked_classes,
		"unlocked_portraits": unlocked_portraits,
		"discovered_modifiers": discovered_modifiers,
		"discovered_enemies": discovered_enemies,
		"discovered_objectives": discovered_objectives,
		"daily_best_date": daily_best_date,
		"daily_best_ops": daily_best_ops,
		"daily_best_kia": daily_best_kia,
		"daily_best_time": daily_best_time,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _portrait_pool() -> Node:
	return get_node("/root/PortraitPool")


func _run_state() -> Node:
	return get_node("/root/RunState")


func _seed_default_portraits() -> void:
	unlocked_portraits.clear()
	var portraits: Array[Texture2D] = _portrait_pool().get_all_portraits()
	for i in range(mini(4, portraits.size())):
		var path: String = _portrait_pool().get_portrait_path_at(i)
		if not path.is_empty() and path not in unlocked_portraits:
			unlocked_portraits.append(path)


func _today_key() -> String:
	var today := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [today.year, today.month, today.day]


func _reset_daily_if_stale() -> void:
	var today := _today_key()
	if daily_best_date != today:
		daily_best_date = today
		daily_best_ops = 0
		daily_best_kia = 999
		daily_best_time = 999999.0


func get_daily_share_code(seed_value: int = -1) -> String:
	var seed_val: int = seed_value if seed_value >= 0 else _run_state().get_daily_seed()
	return "EOY-%s-%d" % [_today_key(), seed_val]


func format_daily_best_line() -> String:
	_reset_daily_if_stale()
	if daily_best_ops <= 0:
		return "Daily best: no run recorded yet today."
	return "Daily best: %d ops | %d KIA | %.0fs" % [daily_best_ops, daily_best_kia, daily_best_time]


func record_daily_run_end(ops_cleared: int, total_kia: int, elapsed_seconds: float) -> Dictionary:
	_reset_daily_if_stale()
	var improved := false
	if _is_better_daily_score(ops_cleared, total_kia, elapsed_seconds):
		daily_best_ops = ops_cleared
		daily_best_kia = total_kia
		daily_best_time = elapsed_seconds
		improved = true
		save_profile()
	return {
		"improved": improved,
		"ops": daily_best_ops,
		"kia": daily_best_kia,
		"time": daily_best_time,
		"share_code": get_daily_share_code(),
	}


func _is_better_daily_score(ops_cleared: int, total_kia: int, elapsed_seconds: float) -> bool:
	if ops_cleared <= 0:
		return false
	if daily_best_ops <= 0:
		return true
	if ops_cleared > daily_best_ops:
		return true
	if ops_cleared < daily_best_ops:
		return false
	if total_kia < daily_best_kia:
		return true
	if total_kia > daily_best_kia:
		return false
	return elapsed_seconds < daily_best_time


func record_run_end(ops_cleared: int, run_won: bool) -> Dictionary:
	total_runs += 1
	total_ops_cleared += ops_cleared
	best_run_depth = maxi(best_run_depth, ops_cleared)
	var tokens_earned := maxi(1, ops_cleared) + (2 if run_won else 0)
	command_tokens += tokens_earned
	save_profile()
	return {
		"tokens_earned": tokens_earned,
		"new_best": ops_cleared >= best_run_depth,
		"ops_cleared": ops_cleared,
	}


func is_class_unlocked(marine_class: SoldierResource.MarineClass) -> bool:
	return marine_class in unlocked_classes


func get_class_unlock_cost(marine_class: SoldierResource.MarineClass) -> int:
	return int(CLASS_UNLOCK_COSTS.get(marine_class, 0))


func try_unlock_class(marine_class: SoldierResource.MarineClass) -> bool:
	if is_class_unlocked(marine_class):
		return true
	var cost: int = get_class_unlock_cost(marine_class)
	if command_tokens < cost:
		return false
	command_tokens -= cost
	unlocked_classes.append(marine_class)
	save_profile()
	return true


func is_portrait_unlocked(path: String) -> bool:
	return path.is_empty() or path in unlocked_portraits


func get_portrait_unlock_cost(portrait_index: int) -> int:
	if portrait_index < 4:
		return 0
	if portrait_index < 10:
		return 1
	return 2


func try_unlock_portrait(path: String) -> bool:
	if path.is_empty() or is_portrait_unlocked(path):
		return is_portrait_unlocked(path)
	var portrait_index: int = _portrait_pool().get_portrait_index_for_path(path)
	if portrait_index < 0:
		return false
	var cost: int = get_portrait_unlock_cost(portrait_index)
	if cost > 0 and command_tokens < cost:
		return false
	if cost > 0:
		command_tokens -= cost
	unlocked_portraits.append(path)
	save_profile()
	return true


func discover_modifier(id: String) -> void:
	if id not in discovered_modifiers:
		discovered_modifiers.append(id)
		save_profile()


func discover_enemy(id: String) -> void:
	if id not in discovered_enemies:
		discovered_enemies.append(id)
		save_profile()


func discover_objective(id: String) -> void:
	if id not in discovered_objectives:
		discovered_objectives.append(id)
		save_profile()


func _array_to_classes(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw is Array:
		for v in raw:
			result.append(int(v))
	if result.is_empty():
		return DEFAULT_UNLOCKED_CLASSES.duplicate()
	return result


func _to_string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for v in raw:
			result.append(str(v))
	return result
