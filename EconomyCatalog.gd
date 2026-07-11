class_name EconomyCatalog
extends RefCounted

## Authoring registry for World Conquest structure/unit economy defs.
## Compiled at load by EconomyLib — not read per frame.

const PACK_DEFAULT := "default"

const KIND_SPAWNER := "spawner"
const KIND_BARRACKS := "barracks"
const KIND_CORRIDOR_LINK := "corridor_link"
const KIND_HANGAR := "hangar"

const UNIT_SOLDIER := "soldier"
const UNIT_BOMBER := "bomber"

## Matches rust/empire_territory/src/structures.rs KIND_* u8 values.
const KIND_U8: Dictionary = {
	KIND_SPAWNER: 0,
	KIND_BARRACKS: 1,
	KIND_CORRIDOR_LINK: 2,
	KIND_HANGAR: 3,
}

const UNIT_U8: Dictionary = {
	UNIT_SOLDIER: 0,
	UNIT_BOMBER: 1,
}

const MAX_KINDS := 4
const MAX_UNITS := 2
const RESOURCE_SLOTS := 3

const _CFG := preload("res://WorldConquestConfig.gd")
const _OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")

const _BUILTIN: Dictionary = {
	PACK_DEFAULT: {
		"pack_id": PACK_DEFAULT,
		"structures": {
			KIND_SPAWNER: {
				"id": KIND_SPAWNER,
				"display_name": "Outpost",
				"cost": {"supply": _CFG.SPAWNER_COST_SUPPLY, "resources": [0.0, 0.0, 0.0]},
				"build_sec": _CFG.OUTPOST_BUILD_SEC,
				"max_health": _CFG.OUTPOST_MAX_HEALTH,
				"logistics_drain": _CFG.LOGISTICS_DRAIN_SPAWNER,
			},
			KIND_BARRACKS: {
				"id": KIND_BARRACKS,
				"display_name": "Barracks",
				"cost": {"supply": _CFG.BARRACKS_COST_SUPPLY, "resources": [0.0, 0.0, 0.0]},
				"build_sec": _CFG.BARRACKS_BUILD_SEC,
				"max_health": _CFG.OUTPOST_MAX_HEALTH,
				"logistics_drain": _CFG.LOGISTICS_DRAIN_BARRACKS,
				"spawns": {
					"unit_id": UNIT_SOLDIER,
					"interval_sec": _CFG.BARRACKS_SPAWN_INTERVAL_SEC,
					"max_active": _CFG.BARRACKS_MAX_ACTIVE_UNITS,
					"spawn_cost": {
						"supply": 0.0,
						"resources": [_CFG.SOLDIER_SPAWN_AURELIUM_COST, 0.0, 0.0],
					},
				},
			},
			KIND_CORRIDOR_LINK: {
				"id": KIND_CORRIDOR_LINK,
				"display_name": "Land Bridge",
				"cost": {"supply": _CFG.CORRIDOR_LINK_COST_SUPPLY, "resources": [0.0, 0.0, 0.0]},
				"build_sec": 0.0,
				"max_health": _CFG.OUTPOST_MAX_HEALTH,
				"logistics_drain": _CFG.LOGISTICS_DRAIN_CORRIDOR,
			},
			KIND_HANGAR: {
				"id": KIND_HANGAR,
				"display_name": "Hangar",
				"cost": {"supply": _CFG.HANGAR_COST_SUPPLY, "resources": [0.0, 0.0, 0.0]},
				"build_sec": _CFG.HANGAR_BUILD_SEC,
				"max_health": _CFG.OUTPOST_MAX_HEALTH,
				"logistics_drain": _CFG.LOGISTICS_DRAIN_HANGAR,
				"spawns": {
					"unit_id": UNIT_BOMBER,
					"interval_sec": _CFG.HANGAR_SPAWN_INTERVAL_SEC,
					"max_active": _CFG.HANGAR_MAX_ACTIVE_UNITS,
					"spawn_cost": {
						"supply": 0.0,
						"resources": [_CFG.BOMBER_SPAWN_AURELIUM_COST, 0.0, 0.0],
					},
				},
			},
		},
		"units": {
			UNIT_SOLDIER: {
				"id": UNIT_SOLDIER,
				"display_name": "Soldier",
				"global_cap": _CFG.GLOBAL_SOLDIER_CAP,
				"upkeep_per_sec": {
					"supply": 0.0,
					"resources": [_CFG.SOLDIER_UPKEEP_AURELIUM_PER_SEC, 0.0, 0.0],
				},
			},
			UNIT_BOMBER: {
				"id": UNIT_BOMBER,
				"display_name": "Bomber",
				"global_cap": _CFG.GLOBAL_BOMBER_CAP,
				"upkeep_per_sec": {"supply": 0.0, "resources": [0.0, 0.0, 0.0]},
			},
		},
	},
}


static func resolve_pack_id(pack_id: String) -> String:
	if pack_id == "":
		return PACK_DEFAULT
	if has_pack(pack_id):
		return pack_id
	push_warning("EconomyCatalog: unknown pack '%s', using default" % pack_id)
	return PACK_DEFAULT


static func has_pack(pack_id: String) -> bool:
	return _BUILTIN.has(pack_id) or _mod_pack(pack_id) != null


static func get_pack(pack_id: String) -> Dictionary:
	var id: String = resolve_pack_id(pack_id)
	if _BUILTIN.has(id):
		return (_BUILTIN[id] as Dictionary).duplicate(true)
	var mod_def: Variant = _mod_pack(id)
	if mod_def is Dictionary:
		return (mod_def as Dictionary).duplicate(true)
	return (_BUILTIN[PACK_DEFAULT] as Dictionary).duplicate(true)


static func structure_kind_ids() -> Array[String]:
	return [
		KIND_SPAWNER,
		KIND_BARRACKS,
		KIND_CORRIDOR_LINK,
		KIND_HANGAR,
	]


static func unit_ids() -> Array[String]:
	return [UNIT_SOLDIER, UNIT_BOMBER]


static func kind_u8(kind: String) -> int:
	return int(KIND_U8.get(kind, -1))


static func unit_u8(unit_id: String) -> int:
	return int(UNIT_U8.get(unit_id, -1))


static func _mod_pack(pack_id: String) -> Variant:
	var path: String = "res://mods/economy/%s.json" % pack_id
	if not ResourceLoader.exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return null
