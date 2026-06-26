class_name WorldMapCatalog
extends RefCounted

## Registry of World Conquest planet / custom maps. Add entries here or via mod JSON later.

const DEFAULT_MAP_ID := "earth"

const MAP_EARTH := "earth"
const MAP_MARS := "mars"
const MAP_VENUS := "venus"

const _BUILTIN: Dictionary = {
	MAP_EARTH: {
		"id": MAP_EARTH,
		"display_name": "Earth",
		"grid_w": 360,
		"grid_h": 180,
		"land_mask_path": "res://data/maps/earth/land_360x180.bin",
		"elevation_path": "res://data/maps/earth/elev_360x180.bin",
		"terrain_tag": "earth",
		"spawn_mode": "west_east",
		"canonical_land": true,
		"globe_ocean": Color(0.05, 0.18, 0.42),
		"globe_land": Color(0.34, 0.52, 0.28),
		"globe_mountain": Color(0.48, 0.44, 0.38),
		"globe_sand": Color(0.72, 0.64, 0.38),
	},
	MAP_MARS: {
		"id": MAP_MARS,
		"display_name": "Mars",
		"grid_w": 360,
		"grid_h": 180,
		"land_mask_path": "",
		"elevation_path": "",
		"terrain_tag": "mars",
		"spawn_mode": "west_east",
		"canonical_land": false,
		"globe_ocean": Color(0.12, 0.06, 0.05),
		"globe_land": Color(0.62, 0.28, 0.18),
		"globe_mountain": Color(0.45, 0.22, 0.15),
		"globe_sand": Color(0.78, 0.42, 0.22),
	},
	MAP_VENUS: {
		"id": MAP_VENUS,
		"display_name": "Venus",
		"grid_w": 360,
		"grid_h": 180,
		"land_mask_path": "",
		"elevation_path": "",
		"terrain_tag": "venus",
		"spawn_mode": "west_east",
		"canonical_land": false,
		"globe_ocean": Color(0.22, 0.16, 0.08),
		"globe_land": Color(0.78, 0.62, 0.28),
		"globe_mountain": Color(0.55, 0.42, 0.22),
		"globe_sand": Color(0.85, 0.72, 0.35),
	},
}


static func resolve_map_id(map_id: String) -> String:
	if map_id == "":
		return DEFAULT_MAP_ID
	if has_map(map_id):
		return map_id
	push_warning("WorldMapCatalog: unknown map '%s', using earth" % map_id)
	return DEFAULT_MAP_ID


static func has_map(map_id: String) -> bool:
	return _BUILTIN.has(map_id) or _mod_entry(map_id) != null


static func get_definition(map_id: String) -> Dictionary:
	var id: String = resolve_map_id(map_id)
	if _BUILTIN.has(id):
		return (_BUILTIN[id] as Dictionary).duplicate(true)
	var mod_def: Variant = _mod_entry(id)
	if mod_def is Dictionary:
		return (mod_def as Dictionary).duplicate(true)
	return (_BUILTIN[DEFAULT_MAP_ID] as Dictionary).duplicate(true)


static func list_map_ids() -> Array[String]:
	var out: Array[String] = []
	for key in _BUILTIN.keys():
		out.append(str(key))
	for key in _scan_mod_ids():
		if not out.has(key):
			out.append(key)
	return out


static func _mod_entry(map_id: String) -> Variant:
	var path: String = "res://mods/maps/%s.json" % map_id
	if not ResourceLoader.exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return null


static func _scan_mod_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://mods/maps")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			out.append(name.trim_suffix(".json"))
		name = dir.get_next()
	dir.list_dir_end()
	return out
