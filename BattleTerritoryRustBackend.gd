class_name BattleTerritoryRustBackend
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

var ready: bool = false
var friendly_tiles: int = 0
var hostile_tiles: int = 0
var _grid_authority: bool = false
var _structure_authority: bool = false

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
	var terrain: Dictionary = _pack_terrain_setup(map_data)
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
				"pressure_inject_interval_rounds": WorldConquestConfigLib.PRESSURE_INJECT_INTERVAL_ROUNDS,
				"player_home_idx": player_home,
				"enemy_home_idx": enemy_home,
				"spawner_teams": spawner_data.teams,
				"spawner_gx": spawner_data.gx,
				"spawner_gy": spawner_data.gy,
				"friendly_tiles": tile_control.friendly_tiles,
				"hostile_tiles": tile_control.hostile_tiles,
				"use_active_set": use_active_set,
				"passable_mask": terrain.passable_mask,
				"land_mask": terrain.land_mask,
				"tile_height": terrain.tile_height,
				"move_cost": terrain.move_cost,
				"defense": terrain.defense,
				"cover_cells": terrain.cover_cells,
				"friendly_reachable": tile_control._friendly_reachable,
				"hostile_reachable": tile_control._hostile_reachable,
				"friendly_bridge_reachable": tile_control._friendly_bridge_reachable,
				"hostile_bridge_reachable": tile_control._hostile_bridge_reachable,
				"friendly_corridor_land": tile_control._friendly_corridor_land,
				"hostile_corridor_land": tile_control._hostile_corridor_land,
	}
	if use_adaptive_double_pass != null:
		setup_dict["use_adaptive_double_pass"] = bool(use_adaptive_double_pass)

	ready = bool(_sim.call("setup_from_dict", setup_dict))
	if ready:
		friendly_tiles = tile_control.friendly_tiles
		hostile_tiles = tile_control.hostile_tiles
		_grid_authority = use_active_set and WorldConquestConfigLib.WORLD_DATASET_GRID_AUTHORITY
		_structure_authority = (
			use_active_set and WorldConquestConfigLib.WORLD_DATASET_STRUCTURE_AUTHORITY
		)
		sync_structure_store_from_map(map_data)
		if _structure_authority and not structure_store_capable():
			_structure_authority = false
	return ready


func structure_authority_enabled() -> bool:
	return _structure_authority and structure_store_capable()


func set_structure_authority(enabled: bool) -> void:
	_structure_authority = enabled


func grid_authority_enabled() -> bool:
	return _grid_authority and ready and _sim != null


func set_grid_authority(enabled: bool) -> void:
	_grid_authority = enabled


func owner_at_index(idx: int) -> int:
	if not ready or _sim == null or not _sim.has_method("owner_at_index"):
		return BattleTileControlLib.OWNER_NEUTRAL
	return int(_sim.call("owner_at_index", idx))


func claimable_at_index(idx: int) -> bool:
	if not ready or _sim == null or not _sim.has_method("claimable_at_index"):
		return false
	return bool(_sim.call("claimable_at_index", idx))


func get_claimable_tile_count() -> int:
	if not ready or _sim == null:
		return -1
	if _sim.has_method("get_claimable_tile_count"):
		return int(_sim.call("get_claimable_tile_count"))
	if _sim.has_method("claimable_tile_count"):
		return int(_sim.call("claimable_tile_count"))
	return -1


func claim_ratio_mult_at(idx: int) -> float:
	if not ready or _sim == null or not _sim.has_method("claim_ratio_mult_at"):
		return 1.0
	return float(_sim.call("claim_ratio_mult_at", idx))


func query_tile(gx: int, gy: int) -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("query_tile"):
		return {"valid": false}
	return _sim.call("query_tile", gx, gy)


func claim_tile_at(gx: int, gy: int, team: int) -> bool:
	if not ready or _sim == null or not _sim.has_method("claim_tile_at"):
		return false
	return bool(_sim.call("claim_tile_at", gx, gy, team))


func step_round(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	_maybe_update_spawners(tile_control._placed_spawners)
	if _sim.has_method("set_home_inject_enabled"):
		_sim.call("set_home_inject_enabled", tile_control.home_inject_enabled)
	_sim.call("advance_round")
	_apply_owners_delta_to_tile_control(tile_control)


var last_owner_delta_indices: PackedInt32Array = PackedInt32Array()
var last_owner_delta_values: PackedByteArray = PackedByteArray()
var last_display_delta_indices: PackedInt32Array = PackedInt32Array()
var last_display_delta_values: PackedByteArray = PackedByteArray()
var _spawner_stamp: int = -1
var _cached_spawner_teams: PackedByteArray = PackedByteArray()
var _cached_spawner_gx: PackedInt32Array = PackedInt32Array()
var _cached_spawner_gy: PackedInt32Array = PackedInt32Array()


func step_rounds(
	tile_control: BattleTileControlLib,
	count: int,
	friendly_deficit_dps: float = 0.0,
	hostile_deficit_dps: float = 0.0,
) -> void:
	if not ready or _sim == null or tile_control == null or count <= 0:
		return
	_maybe_update_spawners(tile_control._placed_spawners)
	if _sim.has_method("set_home_inject_enabled"):
		_sim.call("set_home_inject_enabled", tile_control.home_inject_enabled)
	if _sim.has_method("world_conquest_advance_rounds"):
		var synced: Dictionary = _sim.call(
			"world_conquest_advance_rounds", count, friendly_deficit_dps, hostile_deficit_dps
		)
		_apply_owners_sync_dict(tile_control, synced)
		return
	_sim.call("advance_rounds", count)
	_apply_owners_delta_to_tile_control(tile_control)


func set_home_inject_enabled(enabled: bool) -> void:
	if not ready or _sim == null:
		return
	if _sim.has_method("set_home_inject_enabled"):
		_sim.call("set_home_inject_enabled", enabled)


func consume_owner_overlay_delta() -> Dictionary:
	var out := {
		"indices": last_display_delta_indices,
		"values": last_display_delta_values,
		"owner_indices": last_owner_delta_indices,
		"owner_values": last_owner_delta_values,
	}
	last_display_delta_indices = PackedInt32Array()
	last_display_delta_values = PackedByteArray()
	last_owner_delta_indices = PackedInt32Array()
	last_owner_delta_values = PackedByteArray()
	return out


## Single presentation pull for a live frame (consume-only; does not advance sim).
## Prefer Rust presentation transaction log (main tables stay in Rust; this is the change feed).
func pull_presentation_delta(opts: Dictionary = {}) -> Dictionary:
	# Defaults false: callers must opt in. Avoid accidental full structure/agent FFI every frame.
	var include_structures: bool = bool(opts.get("structures", false))
	var include_agents: bool = bool(opts.get("agents", false))
	var include_bombers: bool = bool(opts.get("bombers", false))
	var out := {
		"owners": {},
		"friendly_tiles": friendly_tiles,
		"hostile_tiles": hostile_tiles,
		"structures": {},
		"agents": {},
		"bombers": {},
		# Structure field transactions (path_built / state) — apply without full table dump.
		"path_built_sids": PackedInt32Array(),
		"path_built_vals": PackedFloat32Array(),
		"state_sids": PackedInt32Array(),
		"state_vals": PackedByteArray(),
		"new_road_cells": PackedInt32Array(),
		"completed_sids": PackedInt32Array(),
		"marker_dirty_sids": PackedInt32Array(),
		"structures_dirty": false,
	}
	if ready and _sim != null and _sim.has_method("pull_presentation_txn"):
		var txn: Dictionary = _sim.call("pull_presentation_txn", include_structures)
		out["owners"] = txn.get("owners", {})
		out["friendly_tiles"] = int(txn.get("friendly_tiles", friendly_tiles))
		out["hostile_tiles"] = int(txn.get("hostile_tiles", hostile_tiles))
		friendly_tiles = int(out["friendly_tiles"])
		hostile_tiles = int(out["hostile_tiles"])
		out["path_built_sids"] = txn.get("path_built_sids", PackedInt32Array())
		out["path_built_vals"] = txn.get("path_built_vals", PackedFloat32Array())
		out["state_sids"] = txn.get("state_sids", PackedInt32Array())
		out["state_vals"] = txn.get("state_vals", PackedByteArray())
		out["new_road_cells"] = txn.get("new_road_cells", PackedInt32Array())
		out["completed_sids"] = txn.get("completed_sids", PackedInt32Array())
		out["marker_dirty_sids"] = txn.get("marker_dirty_sids", PackedInt32Array())
		out["structures_dirty"] = bool(txn.get("structures_dirty", false))
		if include_structures:
			out["structures"] = txn.get("structures", {})
		# Clear legacy last_* buffers so dual consume cannot double-apply owners.
		last_display_delta_indices = PackedInt32Array()
		last_display_delta_values = PackedByteArray()
		last_owner_delta_indices = PackedInt32Array()
		last_owner_delta_values = PackedByteArray()
	else:
		out["owners"] = consume_owner_overlay_delta()
		if include_structures and structure_authority_enabled():
			out["structures"] = get_structure_snapshot()
	if include_agents and ready and _sim != null and _sim.has_method("get_agent_snapshot"):
		out["agents"] = _sim.call("get_agent_snapshot")
	if include_bombers and ready and _sim != null and _sim.has_method("get_bomber_snapshot"):
		out["bombers"] = _sim.call("get_bomber_snapshot")
	return out


func _apply_owners_delta_to_tile_control(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if not _sim.has_method("sync_owners_delta"):
		_apply_state_to_tile_control(tile_control)
		return
	_apply_owners_sync_dict(tile_control, _sim.call("sync_owners_delta"))


func _apply_owners_sync_dict(tile_control: BattleTileControlLib, synced: Dictionary) -> void:
	if tile_control == null or synced.is_empty():
		last_owner_delta_indices = PackedInt32Array()
		last_owner_delta_values = PackedByteArray()
		last_display_delta_indices = PackedInt32Array()
		last_display_delta_values = PackedByteArray()
		return
	last_owner_delta_indices = synced.get("owner_indices", PackedInt32Array())
	last_owner_delta_values = synced.get("owner_values", PackedByteArray())
	last_display_delta_indices = synced.get("display_indices", PackedInt32Array())
	last_display_delta_values = synced.get("display_r8", PackedByteArray())
	var indices: PackedInt32Array = last_owner_delta_indices
	var values: PackedByteArray = last_owner_delta_values
	if not grid_authority_enabled():
		var n: int = mini(indices.size(), values.size())
		for i in range(n):
			var idx: int = indices[i]
			if idx >= 0 and idx < tile_control.owners.size():
				tile_control.owners[idx] = values[i]
	friendly_tiles = int(synced.get("friendly_tiles", friendly_tiles))
	hostile_tiles = int(synced.get("hostile_tiles", hostile_tiles))
	if not grid_authority_enabled():
		tile_control.friendly_tiles = friendly_tiles
		tile_control.hostile_tiles = hostile_tiles


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
	if grid_authority_enabled():
		return
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


func world_edit_capable() -> bool:
	return (
		ready
		and _sim != null
		and _sim.has_method("world_edit_ready")
		and bool(_sim.call("world_edit_ready"))
	)


func structure_store_capable() -> bool:
	return (
		ready
		and _sim != null
		and _sim.has_method("structure_store_ready")
		and bool(_sim.call("structure_store_ready"))
	)


func sync_structure_store_from_map(map_data) -> void:
	if not ready or _sim == null or map_data == null:
		return
	if not _sim.has_method("sync_structure_store"):
		return
	_sim.call("sync_structure_store", map_data.placed_structures, map_data.bridge_corridors)


func get_structure_snapshot() -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("get_structure_snapshot"):
		return {}
	return _sim.call("get_structure_snapshot")


const _STRUCTURE_CACHE_MERGE_KEYS: Array[String] = [
	"health",
	"source_gx",
	"source_gy",
	"click_gx",
	"click_gy",
	"spawn_timer",
]


func pull_structure_cache_to_map(map_data, merge_by_sid: Dictionary = {}) -> bool:
	if map_data == null or not structure_authority_enabled():
		return false
	var snap: Dictionary = get_structure_snapshot()
	if snap.is_empty():
		return false
	var old_by_sid: Dictionary = {}
	for st_var in map_data.placed_structures:
		if not st_var is Dictionary:
			continue
		var old_st: Dictionary = st_var
		var sid: int = int(old_st.get("id", -1))
		if sid >= 0:
			old_by_sid[sid] = old_st
	map_data.placed_structures.clear()
	for st_var in snap.get("structures", []):
		if not st_var is Dictionary:
			continue
		var st: Dictionary = (st_var as Dictionary).duplicate()
		var sid: int = int(st.get("id", -1))
		var merge_src: Dictionary = merge_by_sid.get(sid, old_by_sid.get(sid, {}))
		if merge_src is Dictionary:
			for key in _STRUCTURE_CACHE_MERGE_KEYS:
				if merge_src.has(key):
					st[key] = merge_src[key]
		map_data.placed_structures.append(st)
	for entry_var in snap.get("corridor_synced", []):
		if not entry_var is Dictionary:
			continue
		var entry: Dictionary = entry_var
		var slot: int = int(entry.get("slot", -1))
		var built: int = int(entry.get("corridor_synced_built", 1))
		if slot >= 0 and slot < map_data.bridge_corridors.size():
			var corridor = map_data.bridge_corridors[slot]
			if corridor is Dictionary:
				corridor["corridor_synced_built"] = built
	return true


func structure_store_upsert(st: Dictionary) -> void:
	if not ready or _sim == null or st.is_empty():
		return
	if _sim.has_method("structure_store_upsert"):
		_sim.call("structure_store_upsert", st)


func structure_store_remove(sid: int) -> void:
	if not ready or _sim == null or sid < 0:
		return
	if _sim.has_method("structure_store_remove"):
		_sim.call("structure_store_remove", sid)


func structure_store_patch_path_built(sid: int, path_built: float) -> void:
	if not ready or _sim == null or sid < 0:
		return
	if _sim.has_method("structure_store_patch_path_built"):
		_sim.call("structure_store_patch_path_built", sid, path_built)


func structure_store_patch_state(sid: int, state: String, path_built: float = -1.0) -> void:
	if not ready or _sim == null or sid < 0:
		return
	if _sim.has_method("structure_store_patch_state"):
		_sim.call("structure_store_patch_state", sid, state, path_built)


func structure_connecting_count(team: int) -> int:
	if not structure_store_capable():
		return -1
	return int(_sim.call("structure_connecting_count", team))


func configure_world_session(cfg: Dictionary, enabled: bool) -> void:
	if not ready or _sim == null or not _sim.has_method("configure_world_session"):
		return
	_sim.call("configure_world_session", cfg, enabled)


func configure_content_tables(cfg: Dictionary) -> void:
	if not ready or _sim == null or not _sim.has_method("configure_content_tables"):
		return
	_sim.call("configure_content_tables", cfg)


func world_session_enabled() -> bool:
	if not ready or _sim == null or not _sim.has_method("world_session_enabled"):
		return false
	return bool(_sim.call("world_session_enabled"))


func world_session_tick(dt: float, friendly_aurelium: float) -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("world_session_tick"):
		return {}
	return _sim.call("world_session_tick", dt, friendly_aurelium)


func configure_builders(cfg: Dictionary, enabled: bool) -> void:
	if not ready or _sim == null or not _sim.has_method("configure_builders"):
		return
	_sim.call("configure_builders", cfg, enabled)


func builder_authority_enabled() -> bool:
	if not ready or _sim == null or not _sim.has_method("builder_authority_enabled"):
		return false
	return bool(_sim.call("builder_authority_enabled"))


func builder_enqueue_job(sid: int, team: int) -> void:
	if not ready or _sim == null or sid < 0:
		return
	if _sim.has_method("builder_enqueue_job"):
		_sim.call("builder_enqueue_job", sid, team)


func builder_cancel_job(sid: int) -> void:
	if not ready or _sim == null or sid < 0:
		return
	if _sim.has_method("builder_cancel_job"):
		_sim.call("builder_cancel_job", sid)


func builder_step(dt: float) -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("builder_step"):
		return {}
	return _sim.call("builder_step", dt)


func get_builder_visual_snapshot() -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("get_builder_visual_snapshot"):
		return {}
	return _sim.call("get_builder_visual_snapshot")


func get_network_built_mask(team: int) -> PackedByteArray:
	if not ready or _sim == null or not _sim.has_method("get_network_built_mask"):
		return PackedByteArray()
	return _sim.call("get_network_built_mask", team)


func get_logistics_strain() -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("get_logistics_strain"):
		return {}
	return _sim.call("get_logistics_strain")


func configure_resource_wallet(enabled: bool) -> void:
	if not ready or _sim == null or not _sim.has_method("configure_resource_wallet"):
		return
	_sim.call("configure_resource_wallet", enabled)


func resource_wallet_enabled() -> bool:
	if not ready or _sim == null or not _sim.has_method("resource_wallet_enabled"):
		return false
	return bool(_sim.call("resource_wallet_enabled"))


func sync_resource_balances(friendly: Array, hostile: Array) -> void:
	if not ready or _sim == null:
		return
	if _sim.has_method("sync_resource_balances"):
		_sim.call("sync_resource_balances", PackedFloat32Array(friendly), PackedFloat32Array(hostile))


func apply_resource_tick_delta(friendly_delta: Array, hostile_delta: Array) -> void:
	if not ready or _sim == null:
		return
	if _sim.has_method("apply_resource_tick_delta"):
		_sim.call(
			"apply_resource_tick_delta",
			PackedFloat32Array(friendly_delta),
			PackedFloat32Array(hostile_delta),
		)


func get_resource_balances() -> Dictionary:
	if not ready or _sim == null or not _sim.has_method("get_resource_balances"):
		return {}
	return _sim.call("get_resource_balances")


func structure_store_enter_building(sid: int, build_remaining: float, max_health: float) -> bool:
	if not ready or _sim == null or sid < 0:
		return false
	if _sim.has_method("structure_store_enter_building"):
		return bool(_sim.call("structure_store_enter_building", sid, build_remaining, max_health))
	return false


static func _pack_terrain_setup(map_data) -> Dictionary:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	var passable := PackedByteArray()
	var land := PackedByteArray()
	var height := PackedFloat32Array()
	var move := PackedFloat32Array()
	var defense := PackedFloat32Array()
	var cover := PackedByteArray()
	passable.resize(n)
	land.resize(n)
	height.resize(n)
	move.resize(n)
	defense.resize(n)
	cover.resize(n)
	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			passable[idx] = 1 if map_data.is_passable(gx, gy) else 0
			land[idx] = 1 if map_data.is_land_cell(gx, gy) else 0
			height[idx] = map_data.get_tile_height(gx, gy)
			move[idx] = map_data.get_move_cost(gx, gy)
			defense[idx] = map_data.get_defense(gx, gy)
			if map_data.cover_cells.size() > idx:
				cover[idx] = map_data.cover_cells[idx]
	return {
		"passable_mask": passable,
		"land_mask": land,
		"tile_height": height,
		"move_cost": move,
		"defense": defense,
		"cover_cells": cover,
	}


static func _built_bridge_cells(st: Dictionary) -> int:
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if packed.is_empty():
		return 0
	var state: String = str(st.get("state", OutpostBuildLib.STATE_ACTIVE))
	if state == OutpostBuildLib.STATE_CONNECTING:
		return int(floor(float(st.get("path_built", 1.0))))
	return packed.size()


static func _structure_qualifies_for_corridor_sync(st: Dictionary) -> bool:
	if not st is Dictionary:
		return false
	var kind: String = str(st.get("kind", ""))
	if not OutpostBuildLib.is_corridor_path_kind(kind):
		return false
	if kind == OutpostBuildLib.KIND_SPAWNER or kind == OutpostBuildLib.KIND_BARRACKS or kind == OutpostBuildLib.KIND_HANGAR:
		var state: String = str(st.get("state", OutpostBuildLib.STATE_ACTIVE))
		return (
			state == OutpostBuildLib.STATE_CONNECTING
			or state == OutpostBuildLib.STATE_BUILDING
			or state == OutpostBuildLib.STATE_ACTIVE
		)
	return str(st.get("state", "")) == OutpostBuildLib.STATE_CONNECTING


func pack_corridor_specs(map_data, sid_filter: Array = []) -> Array:
	var specs: Array = []
	if map_data == null:
		return specs
	var sid_set: Dictionary = {}
	for sid_v in sid_filter:
		sid_set[int(sid_v)] = true
	var filter_sids: bool = not sid_set.is_empty()
	for st in map_data.placed_structures:
		if not st is Dictionary:
			continue
		var sid: int = int(st.get("id", -1))
		if filter_sids and (sid < 0 or not sid_set.has(sid)):
			continue
		if not _structure_qualifies_for_corridor_sync(st):
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		specs.append({
			"sid": sid,
			"team": int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
			"path_keys": packed,
			"built_cells": _built_bridge_cells(st),
			"synced_cells": int(st.get("corridor_synced_built", 1)),
		})
	if filter_sids:
		return specs
	for i in range(map_data.bridge_corridors.size()):
		var corridor = map_data.bridge_corridors[i]
		if not corridor is Dictionary:
			continue
		var packed_c: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		specs.append({
			"sid": -(i + 1),
			"team": int(corridor.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
			"path_keys": packed_c,
			"built_cells": packed_c.size(),
			"synced_cells": int(corridor.get("corridor_synced_built", 1)),
		})
	return specs


func extend_beachhead_from_landing(gx: int, gy: int, team: int) -> Dictionary:
	if not world_edit_capable():
		return {}
	return _sim.call("extend_beachhead_from_landing", gx, gy, team)


func sync_bridge_corridors_rust(map_data, force_full: bool, sid_filter: Array = []) -> Dictionary:
	if not world_edit_capable() or map_data == null:
		return {}
	var filter_packed := PackedInt32Array()
	for sid_v in sid_filter:
		filter_packed.append(int(sid_v))
	var specs: Array = []
	if not structure_store_capable():
		specs = pack_corridor_specs(map_data, sid_filter)
	return _sim.call("sync_bridge_corridors_rust", specs, force_full, filter_packed)


func apply_world_edit_result(tile_control: BattleTileControlLib, result: Dictionary, map_data) -> void:
	if result.is_empty():
		return
	var delta: Dictionary = result.get("claimable_delta", {})
	var indices: PackedInt32Array = delta.get("indices", PackedInt32Array())
	var n: int = indices.size()
	if n > 0 and not grid_authority_enabled() and tile_control != null:
		var claimable: PackedByteArray = delta.get("claimable", PackedByteArray())
		var owners: PackedByteArray = delta.get("owners", PackedByteArray())
		var elevation: PackedFloat32Array = delta.get("elevation", PackedFloat32Array())
		var flow_mult: PackedFloat32Array = delta.get("flow_mult", PackedFloat32Array())
		var claim_mult: PackedFloat32Array = delta.get("claim_mult", PackedFloat32Array())
		for i in range(n):
			var idx: int = indices[i]
			if idx < 0 or idx >= tile_control.claimable_mask.size():
				continue
			if i < claimable.size():
				tile_control.claimable_mask[idx] = claimable[i]
			if i < owners.size():
				tile_control.owners[idx] = owners[i]
			if i < elevation.size():
				tile_control._elevation[idx] = elevation[i]
			if i < flow_mult.size():
				tile_control._terrain_flow_mult[idx] = flow_mult[i]
			if i < claim_mult.size():
				tile_control._claim_ratio_mult[idx] = claim_mult[i]
		tile_control.claimable_tile_count = 0
		for cidx in range(tile_control.claimable_mask.size()):
			if tile_control.claimable_mask[cidx] != 0:
				tile_control.claimable_tile_count += 1
	if map_data != null:
		for entry in result.get("synced_updates", []):
			if not entry is Dictionary:
				continue
			var sid: int = int(entry.get("sid", -1))
			var built: int = int(entry.get("corridor_synced_built", 1))
			if sid >= 0:
				for st in map_data.placed_structures:
					if st is Dictionary and int(st.get("id", -1)) == sid:
						st["corridor_synced_built"] = built
						break
			elif sid < -1:
				var corr_i: int = -(sid + 1)
				if corr_i >= 0 and corr_i < map_data.bridge_corridors.size():
					var corridor = map_data.bridge_corridors[corr_i]
					if corridor is Dictionary:
						corridor["corridor_synced_built"] = built
	if not grid_authority_enabled():
		pull_world_edit_mirror(tile_control)


func pull_world_edit_mirror(tile_control: BattleTileControlLib) -> void:
	if not ready or _sim == null or tile_control == null:
		return
	if not _sim.has_method("get_world_edit_mirror"):
		return
	var mirror: Dictionary = _sim.call("get_world_edit_mirror")
	if mirror.is_empty():
		return
	tile_control._friendly_reachable = mirror.get(
		"friendly_reachable", tile_control._friendly_reachable
	)
	tile_control._hostile_reachable = mirror.get(
		"hostile_reachable", tile_control._hostile_reachable
	)
	tile_control._friendly_bridge_reachable = mirror.get(
		"friendly_bridge_reachable", tile_control._friendly_bridge_reachable
	)
	tile_control._hostile_bridge_reachable = mirror.get(
		"hostile_bridge_reachable", tile_control._hostile_bridge_reachable
	)
	tile_control._friendly_corridor_land = mirror.get(
		"friendly_corridor_land", tile_control._friendly_corridor_land
	)
	tile_control._hostile_corridor_land = mirror.get(
		"hostile_corridor_land", tile_control._hostile_corridor_land
	)


func _free() -> void:
	ready = false
	_sim = null
	_grid_authority = false
	_structure_authority = false
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
	if not ready or _sim == null:
		return
	if not _sim.has_method("update_agent_nav_masks"):
		return
	if grid_authority_enabled() and _sim.has_method("get_world_edit_mirror"):
		var mirror: Dictionary = _sim.call("get_world_edit_mirror")
		if not mirror.is_empty():
			_sim.call(
				"update_agent_nav_masks",
				mirror.get("friendly_corridor_land", PackedByteArray()),
				mirror.get("hostile_corridor_land", PackedByteArray()),
				mirror.get("friendly_bridge_reachable", PackedByteArray()),
				mirror.get("hostile_bridge_reachable", PackedByteArray()),
			)
			return
	if tile_control == null:
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


func configure_bombers(cfg: Dictionary) -> bool:
	if not ready or _sim == null or not _sim.has_method("configure_bombers"):
		return false
	return bool(_sim.call("configure_bombers", cfg))


func bombers_active() -> bool:
	if not ready or _sim == null:
		return false
	if _sim.has_method("bombers_active"):
		return bool(_sim.call("bombers_active"))
	return false


func notify_hangar_destroyed(hangar_id: int) -> void:
	if not ready or _sim == null:
		return
	if _sim.has_method("notify_hangar_destroyed"):
		_sim.call("notify_hangar_destroyed", hangar_id)


func try_spawn_bomber(hangar_id: int, team: int, gx: int, gy: int) -> bool:
	if not ready or _sim == null:
		return false
	if _sim.has_method("try_spawn_bomber"):
		return bool(_sim.call("try_spawn_bomber", hangar_id, team, gx, gy))
	return false


func bomber_living_count() -> int:
	if not ready or _sim == null:
		return 0
	if _sim.has_method("bomber_living_count"):
		return int(_sim.call("bomber_living_count"))
	return 0


func bomber_living_for_hangar(hangar_id: int) -> int:
	if not ready or _sim == null:
		return 0
	if _sim.has_method("bomber_living_for_hangar"):
		return int(_sim.call("bomber_living_for_hangar", hangar_id))
	return 0


func get_bomber_snapshot() -> Dictionary:
	if not ready or _sim == null:
		return {}
	if _sim.has_method("get_bomber_snapshot"):
		return _sim.call("get_bomber_snapshot")
	return {}
