class_name BattleTerritoryRustBackend
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")

var ready: bool = false
var friendly_tiles: int = 0
var hostile_tiles: int = 0

var _sim: RefCounted


static func extension_available() -> bool:
	return ClassDB.class_exists("TerritorySim")


static func backend_requested() -> bool:
	return OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower() == "rust"


static func default_resolve_backend_enabled() -> bool:
	if not extension_available():
		return false
	return OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower() != "cpu"


static func compare_enabled() -> bool:
	return OS.get_environment("BATTLE_RUST_COMPARE") == "1"


static func bake_compare_enabled() -> bool:
	return OS.get_environment("BATTLE_RUST_BAKE_COMPARE") == "1"


static func active_set_compare_enabled() -> bool:
	return OS.get_environment("BATTLE_RUST_ACTIVE_COMPARE") == "1"


static func _codec_sim() -> RefCounted:
	return ClassDB.instantiate("TerritorySim")


func setup_from_tile_control(
	map_data,
	tile_control: BattleTileControlLib,
	use_active_set: bool = false,
	use_adaptive_double_pass = null,
) -> bool:
	_free()
	if map_data == null or tile_control == null or not extension_available():
		return false
	_sim = ClassDB.instantiate("TerritorySim")
	if _sim == null:
		return false

	var player_home: int = tile_control._home_base_tile_index(
		map_data, map_data.player_spawn_zone, true
	)
	var enemy_home: int = tile_control._home_base_tile_index(
		map_data, map_data.enemy_spawn_zone, false
	)
	var spawner_data: Dictionary = _pack_spawners(tile_control._placed_spawners)
	var setup_dict: Dictionary = {
				"grid_w": map_data.grid_width,
				"grid_h": map_data.grid_height,
				"claimable": tile_control.claimable_mask,
				"elevation": tile_control._elevation,
				"flow_mult": tile_control._terrain_flow_mult,
				"claim_mult": tile_control._claim_ratio_mult,
				"owners": tile_control.owners,
				"pressure_friendly": tile_control.pressure_friendly,
				"pressure_hostile": tile_control.pressure_hostile,
				"friendly_spawn_rate": tile_control._friendly_spawn_rate,
				"hostile_spawn_rate": tile_control._hostile_spawn_rate,
				"player_home_idx": player_home,
				"enemy_home_idx": enemy_home,
				"spawner_teams": spawner_data.teams,
				"spawner_gx": spawner_data.gx,
				"spawner_gy": spawner_data.gy,
				"friendly_tiles": tile_control.friendly_tiles,
				"hostile_tiles": tile_control.hostile_tiles,
				"use_active_set": use_active_set,
	}
	if use_adaptive_double_pass != null:
		setup_dict["use_adaptive_double_pass"] = bool(use_adaptive_double_pass)

	ready = bool(_sim.call("setup_from_dict", setup_dict))
	if ready:
		friendly_tiles = tile_control.friendly_tiles
		hostile_tiles = tile_control.hostile_tiles
	return ready


func step_round(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	var spawner_data: Dictionary = _pack_spawners(tile_control._placed_spawners)
	_sim.call("update_spawners", spawner_data.teams, spawner_data.gx, spawner_data.gy)
	_sim.call("advance_round")
	_apply_state_to_tile_control(tile_control)


func step_rounds(tile_control: BattleTileControlLib, count: int) -> void:
	if not ready or _sim == null or tile_control == null or count <= 0:
		return
	var spawner_data: Dictionary = _pack_spawners(tile_control._placed_spawners)
	_sim.call("update_spawners", spawner_data.teams, spawner_data.gx, spawner_data.gy)
	_sim.call("advance_rounds", count)
	_apply_state_to_tile_control(tile_control)


func _apply_state_to_tile_control(tile_control: BattleTileControlLib) -> void:
	var synced: Dictionary = _sim.call("sync_into_tile_control")
	if synced.is_empty():
		return
	tile_control.owners = synced.get("owners", tile_control.owners)
	tile_control.pressure_friendly = synced.get(
		"pressure_friendly", tile_control.pressure_friendly
	)
	tile_control.pressure_hostile = synced.get("pressure_hostile", tile_control.pressure_hostile)
	tile_control.friendly_tiles = int(synced.get("friendly_tiles", tile_control.friendly_tiles))
	tile_control.hostile_tiles = int(synced.get("hostile_tiles", tile_control.hostile_tiles))
	friendly_tiles = tile_control.friendly_tiles
	hostile_tiles = tile_control.hostile_tiles


func sync_spawners_from(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	var spawner_data: Dictionary = _pack_spawners(tile_control._placed_spawners)
	_sim.call("update_spawners", spawner_data.teams, spawner_data.gx, spawner_data.gy)


static func encode_pressure_v2(pressure: PackedFloat32Array) -> PackedByteArray:
	if not extension_available():
		return PackedByteArray()
	var sim: RefCounted = _codec_sim()
	return sim.call("encode_pressure_v2", pressure)


static func decode_pressure_v2(blob: PackedByteArray) -> PackedFloat32Array:
	if not extension_available():
		return PackedFloat32Array()
	var sim: RefCounted = _codec_sim()
	return sim.call("decode_pressure_v2", blob)


static func bake_fluid_rgba(
	map_data,
	pressure_friendly: PackedFloat32Array,
	pressure_hostile: PackedFloat32Array,
	power_scale: float = 1.0,
	land_mask: PackedByteArray = PackedByteArray(),
) -> PackedByteArray:
	if map_data == null or not extension_available():
		return PackedByteArray()
	var mask: PackedByteArray = land_mask
	if mask.is_empty():
		mask = _claimable_mask_from_map(map_data)
	var sim: RefCounted = _codec_sim()
	return sim.call(
		"bake_fluid_rgba",
		map_data.grid_width,
		map_data.grid_height,
		mask,
		pressure_friendly,
		pressure_hostile,
		power_scale,
	)


static func land_mask_from_map(map_data) -> PackedByteArray:
	return _claimable_mask_from_map(map_data)


static func _claimable_mask_from_map(map_data) -> PackedByteArray:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var mask := PackedByteArray()
	mask.resize(w * h)
	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			mask[idx] = 1 if map_data.is_land_cell(gx, gy) else 0
	return mask


func _pack_spawners(spawners: Array) -> Dictionary:
	var teams := PackedByteArray()
	var gx := PackedInt32Array()
	var gy := PackedInt32Array()
	for sp in spawners:
		if not sp is Dictionary:
			continue
		teams.append(int(sp.get("team", BattleTileControlLib.OWNER_FRIENDLY)))
		gx.append(int(sp.get("gx", -1)))
		gy.append(int(sp.get("gy", -1)))
	return {"teams": teams, "gx": gx, "gy": gy}


func _free() -> void:
	ready = false
	_sim = null
	friendly_tiles = 0
	hostile_tiles = 0
