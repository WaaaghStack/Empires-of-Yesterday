# PortraitPool.gd — autoload singleton (no class_name; registered in project.godot).
extends Node

const PORTRAIT_DIR := "res://assets/portraits"

const PORTRAIT_FILES: Array[String] = [
	"marine_portrait_01_black_male_buzzcut.png",
	"marine_portrait_02_white_female_ponytail.png",
	"marine_portrait_03_eastasian_male_clean.png",
	"marine_portrait_04_latina_female_wavy.png",
	"marine_portrait_05_southasian_male_beard.png",
	"marine_portrait_06_white_male_redhair.png",
	"marine_portrait_07_black_female_afro.png",
	"marine_portrait_08_middleeastern_male_stubble.png",
	"marine_portrait_09_black_male_curly.png",
	"marine_portrait_10_eastasian_female_bun.png",
	"marine_portrait_11_latino_male_fade.png",
	"marine_portrait_12_white_female_undercut.png",
	"marine_portrait_13_middleeastern_female_hijab.png",
	"marine_portrait_14_southasian_female_braid.png",
	"marine_portrait_15_black_male_dreads.png",
	"marine_portrait_16_white_male_shaved.png",
	"marine_portrait_17_latina_female_pixie.png",
	"marine_portrait_18_eastasian_male_spiked.png",
]

var _loaded_portraits: Array[Texture2D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_all_portraits()


func _portrait_path(file_name: String) -> String:
	return "%s/%s" % [PORTRAIT_DIR.rstrip("/"), file_name]


func _load_all_portraits() -> void:
	_loaded_portraits.clear()
	for file_name in _discover_portrait_files():
		var path := _portrait_path(file_name)
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex:
			_loaded_portraits.append(tex)
	if _loaded_portraits.is_empty():
		push_warning(
			"PortraitPool: no portraits in %s — add marine_portrait_*.png files there." % PORTRAIT_DIR
		)


func _discover_portrait_files() -> Array[String]:
	var files: Array[String] = []
	var seen: Dictionary = {}
	for file_name in PORTRAIT_FILES:
		if not seen.has(file_name):
			seen[file_name] = true
			files.append(file_name)
	var dir := DirAccess.open(PORTRAIT_DIR)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.to_lower().ends_with(".png") and entry.begins_with("marine_portrait"):
				if not seen.has(entry):
					seen[entry] = true
					files.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	files.sort()
	return files


func get_random_portraits(count: int) -> Array[Texture2D]:
	if _loaded_portraits.is_empty():
		_load_all_portraits()
	if count <= 0:
		return []
	var available := _loaded_portraits.duplicate()
	available.shuffle()
	var result: Array[Texture2D] = []
	for i in range(mini(count, available.size())):
		result.append(available[i])
	return result


func get_all_portraits() -> Array[Texture2D]:
	if _loaded_portraits.is_empty():
		_load_all_portraits()
	return _loaded_portraits.duplicate()


func get_portrait_count() -> int:
	return get_all_portraits().size()


func get_portrait_path_at(index: int) -> String:
	var files := _discover_portrait_files()
	if index < 0 or index >= files.size():
		return ""
	return _portrait_path(files[index])


func get_portrait_index_for_path(path: String) -> int:
	var files := _discover_portrait_files()
	for i in range(files.size()):
		if _portrait_path(files[i]) == path:
			return i
	return -1


func _save_manager() -> Node:
	return get_node("/root/SaveManager")


func get_unlocked_portraits() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for i in range(get_portrait_count()):
		var path := get_portrait_path_at(i)
		if _save_manager().is_portrait_unlocked(path):
			var tex: Texture2D = load(path)
			if tex:
				result.append(tex)
	return result


func get_random_unlocked_portraits(count: int) -> Array[Texture2D]:
	var available := get_unlocked_portraits()
	available.shuffle()
	var result: Array[Texture2D] = []
	for i in range(mini(count, available.size())):
		result.append(available[i])
	return result
