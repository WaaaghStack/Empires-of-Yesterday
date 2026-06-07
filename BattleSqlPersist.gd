class_name BattleSqlPersist
extends RefCounted

const BattleMapSnapshotLib := preload("res://BattleMapSnapshot.gd")
const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")


## Write map + replay frames into SQLite (territory or legacy tactical).
static func persist_from_entry(gdb: Node, battle_id: int, entry: Dictionary) -> bool:
	if gdb == null or battle_id <= 0:
		return false
	var mode: String = str(entry.get("resolve_mode", "territory"))
	if mode == "territory":
		return persist_territory_from_entry(gdb, battle_id, entry)
	return persist_tactical_from_entry(gdb, battle_id, entry)


static func persist_territory_from_entry(gdb: Node, battle_id: int, entry: Dictionary) -> bool:
	if gdb == null or battle_id <= 0:
		return false
	var map_snap: Dictionary = entry.get("map_snapshot", {})
	if map_snap.is_empty():
		return false
	var map_data = BattleMapSnapshotLib.from_dict(map_snap)
	if map_data == null:
		return false
	var tape: BattleTerritoryTapeLib = _territory_tape_from_entry(entry)
	if tape == null or tape.frame_count() == 0:
		return false
	gdb.clear_territory_battle_data(battle_id)
	if not gdb.insert_battle_map(battle_id, map_data, map_snap):
		return false
	if not gdb.insert_battle_tiles(battle_id, map_data):
		return false
	tape.rebuild_segment_timing()
	if not gdb.insert_territory_replay_pack(battle_id, map_data, tape):
		return false
	gdb.insert_battle_meta(
		battle_id,
		tape.frame_count(),
		tape.record_stride,
		tape.round_duration,
		tape.resolve_ms,
	)
	return true


static func persist_tactical_from_entry(gdb: Node, battle_id: int, entry: Dictionary) -> bool:
	if gdb == null or battle_id <= 0:
		return false
	var map_snap: Dictionary = entry.get("map_snapshot", {})
	if map_snap.is_empty():
		return false
	var map_data = BattleMapSnapshotLib.from_dict(map_snap)
	if map_data == null:
		return false
	var tape: BattleReplayTapeLib = _tactical_tape_from_entry(entry)
	if tape == null or tape.frame_count() == 0:
		return false
	gdb.clear_tactical_battle_data(battle_id)
	if not gdb.insert_battle_map(battle_id, map_data, map_snap):
		return false
	if not gdb.insert_battle_tiles(battle_id, map_data):
		return false
	var frame0: Dictionary = tape.get_frame(0)
	var unit_count: int = _unit_count_from_frame(frame0)
	if unit_count <= 0:
		return false
	if not gdb.insert_battle_units(battle_id, frame0, unit_count):
		return false
	var prev_tiles: PackedInt32Array = PackedInt32Array()
	prev_tiles.resize(unit_count)
	for fi in range(tape.frame_count()):
		var frame: Dictionary = tape.get_frame(fi)
		var round_idx: int = int(frame.get("round", fi))
		gdb.insert_battle_round(
			battle_id,
			fi,
			round_idx,
			int(frame.get("friendly_living", 0)),
			int(frame.get("hostile_living", 0)),
		)
		gdb.insert_battle_unit_states(battle_id, fi, map_data, frame, unit_count)
		var tile_owners: PackedByteArray = BattleReplayTapeLib.owners_from_frame(frame)
		if not tile_owners.is_empty():
			gdb.insert_battle_tile_frame(
				battle_id,
				fi,
				tile_owners,
				frame.get("pressure_f", PackedByteArray()),
				frame.get("pressure_h", PackedByteArray()),
			)
		_record_moves(gdb, battle_id, fi, round_idx, map_data, frame, prev_tiles, unit_count)
		_fill_prev_tiles(map_data, frame, prev_tiles, unit_count)
	gdb.insert_battle_meta(
		battle_id,
		tape.frame_count(),
		tape.record_stride,
		tape.round_duration,
		tape.resolve_ms,
	)
	return true


static func _territory_tape_from_entry(entry: Dictionary) -> BattleTerritoryTapeLib:
	var raw = entry.get("tape", null)
	if raw == null:
		return null
	if raw is BattleTerritoryTapeLib:
		raw.result = entry.get("tape_result", raw.result)
		raw.resolve_ms = float(entry.get("resolve_ms", raw.resolve_ms))
		return raw
	var tape := BattleTerritoryTapeLib.new()
	if typeof(raw) == TYPE_DICTIONARY:
		tape.load_from_dictionary(raw)
	else:
		return null
	tape.result = entry.get("tape_result", tape.result)
	if tape.result.is_empty():
		tape.result = {
			"player_won": entry.get("player_won", false),
			"turns": entry.get("turns", 0),
		}
	tape.resolve_ms = float(entry.get("resolve_ms", tape.resolve_ms))
	return tape


static func _tactical_tape_from_entry(entry: Dictionary) -> BattleReplayTapeLib:
	var raw = entry.get("tape", null)
	if raw == null:
		return null
	var tape := BattleReplayTapeLib.new()
	if typeof(raw) == TYPE_DICTIONARY:
		tape.load_from_dictionary(raw)
	elif raw is BattleReplayTapeLib:
		return raw
	else:
		return null
	tape.result = entry.get("tape_result", tape.result)
	if tape.result.is_empty():
		tape.result = {
			"player_won": entry.get("player_won", false),
			"turns": entry.get("turns", 0),
		}
	tape.resolve_ms = float(entry.get("resolve_ms", tape.resolve_ms))
	return tape


static func _unit_count_from_frame(frame: Dictionary) -> int:
	var gx_arr = frame.get("grid_x", PackedInt32Array())
	if gx_arr is PackedInt32Array:
		return gx_arr.size()
	return 0


static func _fill_prev_tiles(
	map_data,
	frame: Dictionary,
	prev: PackedInt32Array,
	unit_count: int,
) -> void:
	var gx_arr = frame.get("grid_x", PackedInt32Array())
	var gy_arr = frame.get("grid_y", PackedInt32Array())
	for i in range(unit_count):
		if i >= gx_arr.size() or i >= gy_arr.size():
			prev[i] = -1
			continue
		prev[i] = map_data.cell_index(int(gx_arr[i]), int(gy_arr[i]))


static func _record_moves(
	gdb: Node,
	battle_id: int,
	frame_index: int,
	round_index: int,
	map_data,
	frame: Dictionary,
	prev_tiles: PackedInt32Array,
	unit_count: int,
) -> void:
	if frame_index == 0:
		return
	var gx_arr = frame.get("grid_x", PackedInt32Array())
	var gy_arr = frame.get("grid_y", PackedInt32Array())
	var flags_arr = frame.get("flags", PackedInt32Array())
	for i in range(unit_count):
		if i >= gx_arr.size() or i >= gy_arr.size():
			continue
		if i < flags_arr.size() and (int(flags_arr[i]) & UnitSimulationStoreLib.FLAG_ALIVE) == 0:
			continue
		var to_tile: int = map_data.cell_index(int(gx_arr[i]), int(gy_arr[i]))
		var from_tile: int = prev_tiles[i] if i < prev_tiles.size() else -1
		if from_tile < 0 or from_tile == to_tile:
			continue
		gdb.insert_battle_unit_move(battle_id, frame_index, round_index, i, from_tile, to_tile)


static func persist_live_round(
	gdb: Node,
	battle_id: int,
	map_data,
	store: UnitSimulationStoreLib,
	frame_index: int,
	round_index: int,
	prev_tiles: PackedInt32Array,
) -> void:
	if gdb == null or battle_id <= 0 or store == null or map_data == null:
		return
	var frame: Dictionary = {
		"positions": store.positions.duplicate(),
		"grid_x": store.grid_x.duplicate(),
		"grid_y": store.grid_y.duplicate(),
		"health": store.health.duplicate(),
		"flags": store.flags.duplicate(),
		"routed": store.routed.duplicate(),
		"tier": store.tier.duplicate(),
		"friendly_living": store.living_friendly_count(),
		"hostile_living": store.living_hostile_count(),
		"round": round_index,
	}
	gdb.insert_battle_round(
		battle_id,
		frame_index,
		round_index,
		int(frame.get("friendly_living", 0)),
		int(frame.get("hostile_living", 0)),
	)
	gdb.insert_battle_unit_states(battle_id, frame_index, map_data, frame, store.count)
	_record_moves(gdb, battle_id, frame_index, round_index, map_data, frame, prev_tiles, store.count)
	_fill_prev_tiles(map_data, frame, prev_tiles, store.count)

