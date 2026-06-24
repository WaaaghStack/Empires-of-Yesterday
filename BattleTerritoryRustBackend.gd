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
	var wrap_longitude: bool = (
		map_data.node_type == "world_conquest" or tile_control.use_longitude_wrap
	)
	var setup_dict: Dictionary = {
				"grid_w": map_data.grid_width,
				"grid_h": map_data.grid_height,
				"wrap_longitude": wrap_longitude,
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
	_maybe_update_spawners(tile_control._placed_spawners)
	if _sim.has_method("set_bridge_live_suction_enabled"):
		_sim.call(
			"set_bridge_live_suction_enabled", tile_control.bridge_live_suction_enabled
		)
	if _sim.has_method("set_home_inject_enabled"):
		_sim.call("set_home_inject_enabled", tile_control.home_inject_enabled)
	_sim.call("advance_round")
	_apply_owners_delta_to_tile_control(tile_control)


var last_owner_delta_indices: PackedInt32Array = PackedInt32Array()
var last_owner_delta_values: PackedByteArray = PackedByteArray()
var _spawner_stamp: int = -1
var _cached_spawner_teams: PackedByteArray = PackedByteArray()
var _cached_spawner_gx: PackedInt32Array = PackedInt32Array()
var _cached_spawner_gy: PackedInt32Array = PackedInt32Array()


func step_rounds(tile_control: BattleTileControlLib, count: int) -> void:
	if not ready or _sim == null or tile_control == null or count <= 0:
		return
	_maybe_update_spawners(tile_control._placed_spawners)
	if _sim.has_method("set_bridge_live_suction_enabled"):
		_sim.call(
			"set_bridge_live_suction_enabled", tile_control.bridge_live_suction_enabled
		)
	if _sim.has_method("set_home_inject_enabled"):
		_sim.call("set_home_inject_enabled", tile_control.home_inject_enabled)
	_sim.call("advance_rounds", count)
	_apply_owners_delta_to_tile_control(tile_control)


func consume_owner_overlay_delta() -> Dictionary:
	var out := {
		"indices": last_owner_delta_indices,
		"values": last_owner_delta_values,
	}
	last_owner_delta_indices = PackedInt32Array()
	last_owner_delta_values = PackedByteArray()
	return out


func _apply_owners_delta_to_tile_control(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if not _sim.has_method("sync_owners_delta"):
		_apply_state_to_tile_control(tile_control)
		return
	var synced: Dictionary = _sim.call("sync_owners_delta")
	if synced.is_empty():
		last_owner_delta_indices = PackedInt32Array()
		last_owner_delta_values = PackedByteArray()
		return
	last_owner_delta_indices = synced.get("owner_indices", PackedInt32Array())
	last_owner_delta_values = synced.get("owner_values", PackedByteArray())
	var indices: PackedInt32Array = last_owner_delta_indices
	var values: PackedByteArray = last_owner_delta_values
	var n: int = mini(indices.size(), values.size())
	for i in range(n):
		var idx: int = indices[i]
		if idx >= 0 and idx < tile_control.owners.size():
			tile_control.owners[idx] = values[i]
	tile_control.friendly_tiles = int(synced.get("friendly_tiles", tile_control.friendly_tiles))
	tile_control.hostile_tiles = int(synced.get("hostile_tiles", tile_control.hostile_tiles))
	friendly_tiles = tile_control.friendly_tiles
	hostile_tiles = tile_control.hostile_tiles


func get_owners() -> PackedByteArray:
	if not ready or _sim == null:
		return PackedByteArray()
	if _sim.has_method("get_owners"):
		return _sim.call("get_owners")
	return PackedByteArray()

func get_owner_display_r8() -> PackedByteArray:
	if not ready or _sim == null:
		return PackedByteArray()
	if _sim.has_method("get_owner_display_r8"):
		return _sim.call("get_owner_display_r8")
	return PackedByteArray()


func get_pressure_friendly() -> PackedFloat32Array:
	if not ready or _sim == null:
		return PackedFloat32Array()
	if _sim.has_method("get_pressure_friendly"):
		return _sim.call("get_pressure_friendly")
	return PackedFloat32Array()


func get_pressure_hostile() -> PackedFloat32Array:
	if not ready or _sim == null:
		return PackedFloat32Array()
	if _sim.has_method("get_pressure_hostile"):
		return _sim.call("get_pressure_hostile")
	return PackedFloat32Array()


func pressure_overlay_peak() -> float:
	if not ready or _sim == null:
		return 10000.0
	if _sim.has_method("pressure_overlay_peak"):
		return float(_sim.call("pressure_overlay_peak"))
	return 10000.0


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
	_spawner_stamp = -1
	_maybe_update_spawners(tile_control._placed_spawners)


func sync_pressures_from(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if _sim.has_method("sync_pressures_from"):
		_sim.call(
			"sync_pressures_from",
			tile_control.pressure_friendly,
			tile_control.pressure_hostile,
		)


func inject_corridor_pressure_pulse(
	path_keys: PackedInt32Array,
	team: int,
	amount_scale: float = 6.0,
) -> void:
	if not ready or _sim == null or path_keys.is_empty():
		return
	if _sim.has_method("inject_corridor_pressure_pulse"):
		_sim.call("inject_corridor_pressure_pulse", path_keys, team, amount_scale)


func sync_bridge_pipe_from(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if not _sim.has_method("update_bridge_pipe"):
		return
	_sim.call(
		"update_bridge_pipe",
		tile_control._bridge_pipe_prev,
		tile_control._bridge_pipe_next,
		tile_control.bridge_water_mask_packed(),
		tile_control.corridor_land_mask_packed(),
	)
	if _sim.has_method("update_bridge_paths"):
		_sim.call("update_bridge_paths", tile_control.bridge_pipe_path_packs())


func sync_claimable_from(
	tile_control: BattleTileControlLib,
	map_data = null,
	use_active_set: bool = true,
) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if _sim.has_method("update_claimable_delta"):
		var delta: Dictionary = _pack_claimable_delta(tile_control)
		if delta.is_empty():
			return
		_sim.call(
			"update_claimable_delta",
			delta.indices,
			delta.claimable,
			delta.owners,
			delta.elevation,
			delta.flow_mult,
			delta.claim_mult,
		)
		sync_bridge_pipe_from(tile_control)
		return
	if _sim.has_method("update_claimable"):
		_sim.call(
			"update_claimable",
			tile_control.claimable_mask,
			tile_control._elevation,
			tile_control._terrain_flow_mult,
			tile_control._claim_ratio_mult,
			tile_control.owners,
		)
		sync_bridge_pipe_from(tile_control)
		return
	if map_data != null:
		push_warning(
			"TerritorySim missing update_claimable — reinitializing Rust sim from tile control."
		)
		setup_from_tile_control(map_data, tile_control, use_active_set)


func _pack_claimable_delta(tile_control: BattleTileControlLib) -> Dictionary:
	var indices: PackedInt32Array = tile_control.take_claimable_dirty_indices()
	if indices.is_empty():
		return {}
	var claimable := PackedByteArray()
	var owners := PackedByteArray()
	var elevation := PackedFloat32Array()
	var flow_mult := PackedFloat32Array()
	var claim_mult := PackedFloat32Array()
	claimable.resize(indices.size())
	owners.resize(indices.size())
	elevation.resize(indices.size())
	flow_mult.resize(indices.size())
	claim_mult.resize(indices.size())
	for i in range(indices.size()):
		var idx: int = indices[i]
		claimable[i] = tile_control.claimable_mask[idx]
		owners[i] = tile_control.owners[idx]
		elevation[i] = tile_control._elevation[idx]
		flow_mult[i] = tile_control._terrain_flow_mult[idx]
		claim_mult[i] = tile_control._claim_ratio_mult[idx]
	return {
		"indices": indices,
		"claimable": claimable,
		"owners": owners,
		"elevation": elevation,
		"flow_mult": flow_mult,
		"claim_mult": claim_mult,
	}


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


func _spawner_stamp_from(spawners: Array) -> int:
	var stamp: int = spawners.size() * 131
	for sp in spawners:
		if not sp is Dictionary:
			continue
		stamp = stamp * 31 + int(sp.get("team", 0))
		stamp = stamp * 31 + int(sp.get("gx", 0))
		stamp = stamp * 31 + int(sp.get("gy", 0))
	return stamp


func _maybe_update_spawners(spawners: Array) -> void:
	if not ready or _sim == null:
		return
	var stamp: int = _spawner_stamp_from(spawners)
	if stamp == _spawner_stamp:
		return
	var spawner_data: Dictionary = _pack_spawners(spawners)
	_cached_spawner_teams = spawner_data.teams
	_cached_spawner_gx = spawner_data.gx
	_cached_spawner_gy = spawner_data.gy
	_spawner_stamp = stamp
	_sim.call("update_spawners", _cached_spawner_teams, _cached_spawner_gx, _cached_spawner_gy)


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


func configure_agents(cfg: Dictionary) -> bool:
	if not ready or _sim == null or not _sim.has_method("configure_agents"):
		return false
	return bool(_sim.call("configure_agents", cfg))


func agents_active() -> bool:
	if not ready or _sim == null:
		return false
	if _sim.has_method("agents_active"):
		return bool(_sim.call("agents_active"))
	return false


func sync_agent_nav_from(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if not _sim.has_method("update_agent_nav_masks"):
		return
	_sim.call(
		"update_agent_nav_masks",
		tile_control.friendly_corridor_land_packed(),
		tile_control.hostile_corridor_land_packed(),
		tile_control.friendly_bridge_reachable_packed(),
		tile_control.hostile_bridge_reachable_packed(),
	)


func set_agent_deficit_dps(friendly_dps: float, hostile_dps: float) -> void:
	if not ready or _sim == null:
		return
	if _sim.has_method("set_agent_deficit_dps"):
		_sim.call("set_agent_deficit_dps", friendly_dps, hostile_dps)


func try_spawn_agent(barracks_id: int, team: int, bx: int, by: int) -> bool:
	if not ready or _sim == null:
		return false
	if _sim.has_method("try_spawn_agent"):
		return bool(_sim.call("try_spawn_agent", barracks_id, team, bx, by))
	return false


func notify_barracks_destroyed(barracks_id: int) -> void:
	if not ready or _sim == null:
		return
	if _sim.has_method("notify_barracks_destroyed"):
		_sim.call("notify_barracks_destroyed", barracks_id)


func agent_living_count() -> int:
	if not ready or _sim == null:
		return 0
	if _sim.has_method("agent_living_count"):
		return int(_sim.call("agent_living_count"))
	return 0


func agent_living_for_barracks(barracks_id: int) -> int:
	if not ready or _sim == null:
		return 0
	if _sim.has_method("agent_living_for_barracks"):
		return int(_sim.call("agent_living_for_barracks", barracks_id))
	return 0


func get_agent_snapshot() -> Dictionary:
	if not ready or _sim == null:
		return {}
	if _sim.has_method("get_agent_snapshot"):
		return _sim.call("get_agent_snapshot")
	return {}
