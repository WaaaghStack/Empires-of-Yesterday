class_name WorldDatasetAssert
extends RefCounted

const CFG := preload("res://WorldConquestConfig.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")


## Validate World Conquest live invariants (Rust authoritative, no parallel grid truth).
static func validate_live(territory_sim, battle_data = null) -> Dictionary:
	var issues: PackedStringArray = PackedStringArray()
	if not CFG.world_dataset_live():
		return {"ok": true, "issues": issues, "skipped": true}
	if territory_sim == null:
		issues.append("territory_sim is null")
		return {"ok": false, "issues": issues}
	if not territory_sim.use_rust_for_live() or territory_sim.rust_field == null:
		issues.append("Rust live backend not active")
	if not territory_sim.grid_authority_active():
		issues.append("grid authority inactive")
	if not territory_sim.structure_authority_active():
		issues.append("structure authority inactive")
	if not territory_sim.world_session_active():
		issues.append("world session tick inactive")
	if not territory_sim.builder_authority_active():
		issues.append("builder authority inactive")
	if not territory_sim.resource_wallet_active():
		issues.append("resource wallet inactive")
	if territory_sim.use_gpu_for_live():
		issues.append("GPU territory backend active during WC live")
	var tc = territory_sim.tile_control
	if tc != null and not bool(tc.get("grid_mirror_frozen")):
		issues.append("tile_control.grid_mirror_frozen is false")
	if battle_data != null and territory_sim.structure_authority_active():
		_check_structure_cache(territory_sim, battle_data, issues)
	return {"ok": issues.is_empty(), "issues": issues}


static func _check_structure_cache(territory_sim, battle_data, issues: PackedStringArray) -> void:
	var snap: Dictionary = territory_sim.rust_field.get_structure_snapshot()
	var rust_list: Array = snap.get("structures", [])
	var by_id: Dictionary = {}
	for st_var in rust_list:
		if st_var is Dictionary:
			by_id[int(st_var.get("id", -1))] = st_var
	for gd_st in battle_data.placed_structures:
		if not gd_st is Dictionary:
			continue
		var sid: int = int(gd_st.get("id", -1))
		if sid < 0:
			continue
		if not by_id.has(sid):
			issues.append("render cache sid=%d missing from Rust snapshot" % sid)
			continue
		var rust_st: Dictionary = by_id[sid]
		var gd_pb: float = float(gd_st.get("path_built", -1.0))
		var rust_pb: float = float(rust_st.get("path_built", -1.0))
		if absf(gd_pb - rust_pb) > 0.01:
			issues.append("path_built mismatch sid=%d gd=%.2f rust=%.2f" % [sid, gd_pb, rust_pb])
