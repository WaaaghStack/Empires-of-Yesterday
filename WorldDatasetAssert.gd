class_name WorldDatasetAssert
extends RefCounted

const CFG := preload("res://WorldConquestConfig.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")


## Validate World Conquest live invariants (Rust authoritative, no parallel grid truth).
## E8: strict — any missing authority or GPU backend is a hard failure.
static func validate_live(territory_sim, battle_data = null) -> Dictionary:
	var issues: PackedStringArray = PackedStringArray()
	if not CFG.world_dataset_live():
		return {"ok": true, "issues": issues, "skipped": true}
	if not CFG.assert_canonical_constants():
		issues.append("assert_canonical_constants failed (BRIDGE_PRESSURE_FLOW_MULT)")
	if territory_sim == null:
		issues.append("territory_sim is null")
		return {"ok": false, "issues": issues}
	if territory_sim.has_method("world_dataset_failed") and bool(territory_sim.world_dataset_failed()):
		var err: String = str(territory_sim.get("world_dataset_error"))
		issues.append("world_dataset_error: %s" % err)
	if not territory_sim.use_rust_for_live() or territory_sim.rust_field == null:
		issues.append("Rust live backend not active")
	if territory_sim.rust_field != null and not bool(territory_sim.rust_field.get("ready")):
		issues.append("rust_field not ready")
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
	# A2/A3: grid_mirror_frozen must be universal under grid authority live contract.
	var tc = territory_sim.tile_control
	if tc == null:
		issues.append("tile_control is null")
	elif not bool(tc.get("grid_mirror_frozen")):
		issues.append("tile_control.grid_mirror_frozen is false")
	if (
		CFG.WORLD_DATASET_GRID_AUTHORITY
		and CFG.world_dataset_live()
		and territory_sim.has_method("world_dataset_require_live")
		and bool(territory_sim.world_dataset_require_live())
		and tc != null
		and not bool(tc.get("grid_mirror_frozen"))
	):
		issues.append("grid_mirror_frozen required under WORLD_DATASET_GRID_AUTHORITY live")
	if battle_data != null and territory_sim.structure_authority_active():
		_check_structure_cache(territory_sim, battle_data, issues)
	return {"ok": issues.is_empty(), "issues": issues, "skipped": false}


## E8: validate_live wrapper for QA — push_error each issue, return ok bool.
## Skipped (flags off) counts as pass. Screen/QA call this for hard live asserts.
static func validate_or_fail(territory_sim, battle_data = null) -> bool:
	var result: Dictionary = validate_live(territory_sim, battle_data)
	if bool(result.get("skipped", false)):
		return true
	if bool(result.get("ok", false)):
		return true
	var issues: PackedStringArray = result.get("issues", PackedStringArray())
	for issue in issues:
		push_error("WorldDatasetAssert.validate_or_fail: %s" % str(issue))
	return false


## E8: same as validate_or_fail but returns the full result dict (for logging).
static func validate_or_fail_result(territory_sim, battle_data = null) -> Dictionary:
	var result: Dictionary = validate_live(territory_sim, battle_data)
	if bool(result.get("skipped", false)) or bool(result.get("ok", false)):
		return result
	var issues: PackedStringArray = result.get("issues", PackedStringArray())
	for issue in issues:
		push_error("WorldDatasetAssert: %s" % str(issue))
	return result


## Hard assert for debug builds / QA harnesses that prefer assert() over soft fail.
static func assert_live(territory_sim, battle_data = null) -> void:
	var result: Dictionary = validate_live(territory_sim, battle_data)
	if bool(result.get("skipped", false)):
		return
	assert(
		bool(result.get("ok", false)),
		"WorldDatasetAssert.assert_live failed: %s" % ", ".join(result.get("issues", PackedStringArray()))
	)


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
		var gd_state: String = str(gd_st.get("state", ""))
		var rust_state: String = str(rust_st.get("state", ""))
		if gd_state != "" and rust_state != "" and gd_state != rust_state:
			issues.append(
				"state mismatch sid=%d gd=%s rust=%s" % [sid, gd_state, rust_state]
			)
		var gd_kind: String = str(gd_st.get("kind", ""))
		var rust_kind: String = str(rust_st.get("kind", ""))
		if gd_kind != "" and rust_kind != "" and gd_kind != rust_kind:
			issues.append("kind mismatch sid=%d gd=%s rust=%s" % [sid, gd_kind, rust_kind])
