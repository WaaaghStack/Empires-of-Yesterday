class_name WorldConquestPresentationApply
extends RefCounted
## C1 partial: pure helpers for live presentation apply (Screen remains compositor).
## Keeps PresentationTxn field names and structure-merge rules in one place.

const CFG := preload("res://WorldConquestConfig.gd")


## True when structures should be included in pull_presentation_delta this frame.
static func want_structures_snapshot(structures_dirty: bool, structure_authority: bool) -> bool:
	if not structure_authority:
		return false
	if CFG.PRESENTATION_STRUCTURES_ONLY_WHEN_DIRTY:
		return structures_dirty
	return true


## Merge path_built / state patches from a presentation txn dict into a structure dict by sid.
## Returns list of sids that received marker-relevant updates.
static func apply_path_state_patches(
	structures: Array,
	path_sids: PackedInt32Array,
	path_vals: PackedFloat32Array,
	state_sids: PackedInt32Array,
	state_vals: PackedStringArray,
) -> PackedInt32Array:
	var dirty: PackedInt32Array = PackedInt32Array()
	var by_sid: Dictionary = {}
	for st in structures:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		by_sid[int(st.get("id", -1))] = st
	var n_path: int = mini(path_sids.size(), path_vals.size())
	for i in range(n_path):
		var sid: int = int(path_sids[i])
		var st: Dictionary = by_sid.get(sid, {})
		if st.is_empty():
			continue
		st["path_built"] = float(path_vals[i])
		dirty.append(sid)
	var n_state: int = mini(state_sids.size(), state_vals.size())
	for j in range(n_state):
		var sid2: int = int(state_sids[j])
		var st2: Dictionary = by_sid.get(sid2, {})
		if st2.is_empty():
			continue
		st2["state"] = str(state_vals[j])
		dirty.append(sid2)
	return dirty


## I10: CONNECTING pulse is only valid while state string is CONNECTING.
static func should_pulse_connecting(state: String) -> bool:
	return state == "connecting" or state == "CONNECTING"
