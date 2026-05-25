class_name HivePressure
extends RefCounted

const MapVisualsLib := preload("res://MapVisuals.gd")

const COLONY_BASELINE := {
	"spawn_cap": 2,
	"wave_size_base": 1,
	"base_spawn_interval": 32.0,
	"min_spawn_interval": 18.0,
}

const JUNGLE_BASELINE := {
	"spawn_cap": 3,
	"wave_size_base": 1,
	"base_spawn_interval": 28.0,
	"min_spawn_interval": 15.0,
}

const CRASHED_SHIP_BASELINE := {
	"spawn_cap": 2,
	"wave_size_base": 2,
	"base_spawn_interval": 30.0,
	"min_spawn_interval": 16.0,
}

var profile: Dictionary = {}
var _escalation_timer: float = 0.0


func reset() -> void:
	profile.clear()
	_escalation_timer = 0.0


func configure(facility_theme: String, mutators: Array = []) -> void:
	profile = profile_for_run(facility_theme, mutators)


func tick(delta: float) -> void:
	if profile.is_empty():
		return
	_escalation_timer += delta
	if _escalation_timer >= 60.0:
		_escalation_timer = 0.0
		profile["min_spawn_interval"] = maxf(12.0, float(profile.get("min_spawn_interval", 18.0)) * 0.95)
		profile["base_spawn_interval"] = maxf(
			float(profile.get("min_spawn_interval", 18.0)),
			float(profile.get("base_spawn_interval", 32.0)) * 0.97,
		)


func apply_to_hive(hive: Hive) -> void:
	if hive == null or profile.is_empty():
		return
	apply_profile(hive, profile)


static func profile_for_run(facility_theme: String, mutators: Array = []) -> Dictionary:
	var theme := MapVisualsLib.normalize_theme(facility_theme)
	var result: Dictionary
	match theme:
		"jungle":
			result = JUNGLE_BASELINE.duplicate(true)
		"crashed_ship":
			result = CRASHED_SHIP_BASELINE.duplicate(true)
		_:
			result = COLONY_BASELINE.duplicate(true)
	for mutator_id in mutators:
		match str(mutator_id):
			"accelerated_swarm", "dense_spores":
				result["base_spawn_interval"] = float(result["base_spawn_interval"]) * 0.82
				result["min_spawn_interval"] = float(result["min_spawn_interval"]) * 0.85
				result["wave_size_base"] = int(result["wave_size_base"]) + 1
			"quiet_deck":
				result["spawn_cap"] = maxi(1, int(result["spawn_cap"]) - 1)
				result["base_spawn_interval"] = float(result["base_spawn_interval"]) * 1.15
			"reinforced":
				result["wave_size_base"] = int(result["wave_size_base"]) + 1
				result["spawn_cap"] = int(result["spawn_cap"]) + 1
	return result


static func apply_profile(hive: Hive, pressure_profile: Dictionary) -> void:
	if hive == null or pressure_profile.is_empty():
		return
	hive.spawn_cap = int(pressure_profile.get("spawn_cap", hive.spawn_cap))
	hive.wave_size_base = int(pressure_profile.get("wave_size_base", hive.wave_size_base))
	hive.base_spawn_interval = float(pressure_profile.get("base_spawn_interval", hive.base_spawn_interval))
	hive.min_spawn_interval = float(pressure_profile.get("min_spawn_interval", hive.min_spawn_interval))
	hive.current_interval = hive.base_spawn_interval
	hive.spawn_timer = hive.base_spawn_interval * 0.6
