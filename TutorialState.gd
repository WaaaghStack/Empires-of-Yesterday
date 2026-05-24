# TutorialState.gd — first-run hint flags persisted in user://save.cfg
extends RefCounted

const SAVE_PATH := "user://save.cfg"

const FLAG_DEPLOY := "hint_deploy"
const FLAG_SECTOR_OVERLAY := "hint_sector_overlay"
const FLAG_CLEAR := "hint_clear"
const FLAG_EXTRACT := "hint_extract"
const FLAG_EXPLORE := "hint_explore"

static func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg


static func _save_cfg(cfg: ConfigFile) -> void:
	cfg.save(SAVE_PATH)


static func has_seen(flag: String) -> bool:
	var cfg := _load_cfg()
	return cfg.get_value("tutorial", flag, false)


static func mark_seen(flag: String) -> void:
	var cfg := _load_cfg()
	cfg.set_value("tutorial", flag, true)
	_save_cfg(cfg)


static func reset_all() -> void:
	var cfg := ConfigFile.new()
	for flag in [FLAG_DEPLOY, FLAG_SECTOR_OVERLAY, FLAG_CLEAR, FLAG_EXTRACT, FLAG_EXPLORE]:
		cfg.set_value("tutorial", flag, false)
	_save_cfg(cfg)
