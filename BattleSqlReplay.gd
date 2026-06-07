class_name BattleSqlReplay

extends RefCounted


const BattleMapSnapshotLib := preload("res://BattleMapSnapshot.gd")

const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")

const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")




## Load battle replay from SQLite (territory tile frames or legacy tactical units).

static func load_from_db(gdb: Node, battle_id: int) -> Dictionary:

	var out: Dictionary = {"battle_data": null, "tape": null, "battle_id": battle_id}

	if gdb == null or battle_id <= 0:

		return out

	if gdb.has_method("has_battle_replay_data") and not gdb.has_battle_replay_data(battle_id):

		return out

	var mode_rows: Array = gdb._query(

		"SELECT resolve_mode FROM battles WHERE id = ? LIMIT 1",

		[battle_id],

	) if gdb.has_method("_query") else []

	var resolve_mode: String = "territory"

	if not mode_rows.is_empty():

		resolve_mode = str(mode_rows[0].get("resolve_mode", "territory"))

	if resolve_mode == "territory" or gdb.count_battle_units(battle_id) <= 0:

		return _load_territory_from_db(gdb, battle_id)

	return _load_tactical_from_db(gdb, battle_id)




static func _load_territory_from_db(gdb: Node, battle_id: int) -> Dictionary:

	var out: Dictionary = {"battle_data": null, "tape": null, "battle_id": battle_id}

	if not gdb.has_territory_battle_data(battle_id):

		return out

	var map_snap: Dictionary = gdb.load_battle_map_snapshot(battle_id)

	var map_data = BattleMapSnapshotLib.from_dict(map_snap)

	if map_data == null:

		return out

	_apply_sql_tile_heights(gdb, battle_id, map_data)

	var tape = gdb.load_territory_replay_pack(battle_id) if gdb.has_method("load_territory_replay_pack") else null
	if tape == null:
		tape = _load_territory_tape_legacy(gdb, battle_id, map_data)
	if tape == null or tape.frame_count() < 1:
		return out
	tape.battle_data = map_data
	var meta: Dictionary = gdb.load_battle_meta(battle_id)
	if not meta.is_empty():
		tape.record_stride = int(meta.get("record_stride", tape.record_stride))
		tape.resolve_ms = float(meta.get("resolve_ms", tape.resolve_ms))
	tape.rebuild_segment_timing()

	var result_row: Dictionary = gdb.load_battle_result_row(battle_id)

	if not result_row.is_empty():

		tape.result = {

			"player_won": int(result_row.get("player_won", 0)) != 0,

			"turns": int(result_row.get("turns", 0)),

			"resolve_mode": "territory",

		}

	out["battle_data"] = map_data

	out["tape"] = tape

	return out


static func _load_territory_tape_legacy(gdb: Node, battle_id: int, map_data):
	var rounds: Array = gdb.load_battle_rounds(battle_id)
	if rounds.is_empty():
		return null
	var tape := BattleTerritoryTapeLib.new()
	tape.battle_data = map_data
	var meta: Dictionary = gdb.load_battle_meta(battle_id)
	tape.record_stride = int(meta.get("record_stride", 1))
	tape.round_duration = float(meta.get("round_duration", BattleTerritoryTapeLib.FRAME_SECONDS))
	tape.resolve_ms = float(meta.get("resolve_ms", 0.0))
	var tile_by_frame: Dictionary = gdb.load_battle_tile_frames_grouped(battle_id)
	for row in rounds:
		var fi: int = int(row.get("frame_index", 0))
		var frame: Dictionary = {
			"round": int(row.get("round_index", fi)),
			"friendly_tiles": int(row.get("friendly_living", 0)),
			"hostile_tiles": int(row.get("hostile_living", 0)),
		}
		if tile_by_frame.has(fi):
			_apply_tile_pack_to_frame(frame, tile_by_frame[fi])
		tape.frames.append(frame)
	return tape


static func _load_tactical_from_db(gdb: Node, battle_id: int) -> Dictionary:

	var out: Dictionary = {"battle_data": null, "tape": null, "battle_id": battle_id}

	if not gdb.has_tactical_battle_data(battle_id):

		return out

	var map_snap: Dictionary = gdb.load_battle_map_snapshot(battle_id)

	var map_data = BattleMapSnapshotLib.from_dict(map_snap)

	if map_data == null:

		return out

	_apply_sql_tile_heights(gdb, battle_id, map_data)

	var meta: Dictionary = gdb.load_battle_meta(battle_id)

	var unit_count: int = gdb.count_battle_units(battle_id)

	if unit_count <= 0:

		return _load_territory_from_db(gdb, battle_id)

	var rounds: Array = gdb.load_battle_rounds(battle_id)

	if rounds.is_empty():

		return out

	var tape := BattleReplayTapeLib.new()

	tape.battle_data = map_data

	tape.unit_count = unit_count

	tape.record_stride = int(meta.get("record_stride", 1))

	tape.round_duration = float(meta.get("round_duration", 0.42))

	tape.resolve_ms = float(meta.get("resolve_ms", 0.0))

	var states_by_frame: Dictionary = gdb.load_battle_unit_states_grouped(battle_id, unit_count)

	var tile_by_frame: Dictionary = gdb.load_battle_tile_frames_grouped(battle_id)

	for row in rounds:

		var fi: int = int(row.get("frame_index", 0))

		var frame: Dictionary = states_by_frame.get(fi, {})

		if frame.is_empty():

			continue

		if tile_by_frame.has(fi):
			_apply_tile_pack_to_frame(frame, tile_by_frame[fi])

		for ui in range(unit_count):

			frame["positions"][ui] = map_data.cell_center(

				int(frame["grid_x"][ui]), int(frame["grid_y"][ui])

			)

		frame["round"] = int(row.get("round_index", fi))

		frame["friendly_living"] = int(row.get("friendly_living", 0))

		frame["hostile_living"] = int(row.get("hostile_living", 0))

		tape.frames.append(frame)

	tape.rebuild_segment_timing()

	var result_row: Dictionary = gdb.load_battle_result_row(battle_id)

	if not result_row.is_empty():

		tape.result = {

			"player_won": int(result_row.get("player_won", 0)) != 0,

			"turns": int(result_row.get("turns", 0)),

		}

	out["battle_data"] = map_data

	out["tape"] = tape

	return out




static func _apply_sql_tile_heights(gdb: Node, battle_id: int, map_data) -> void:
	if gdb != null and gdb.has_method("apply_battle_tile_heights_to_map"):
		gdb.apply_battle_tile_heights_to_map(battle_id, map_data)


static func _apply_tile_pack_to_frame(frame: Dictionary, tile_pack) -> void:
	if tile_pack is Dictionary:
		frame["tile_owners"] = tile_pack.get("owners", PackedByteArray())
		if tile_pack.has("pressure_f"):
			frame["pressure_f"] = tile_pack["pressure_f"]
		if tile_pack.has("pressure_h"):
			frame["pressure_h"] = tile_pack["pressure_h"]
	elif tile_pack is PackedByteArray:
		frame["tile_owners"] = tile_pack


## Apply a single SQL frame to the live store (legacy tactical only).

static func apply_sql_frame(

	store: UnitSimulationStoreLib,

	map_data,

	frame: Dictionary,

) -> void:

	if store == null or frame.is_empty():

		return

	var n: int = mini(store.count, _frame_unit_count(frame))

	var gx_arr = frame.get("grid_x", PackedInt32Array())

	var gy_arr = frame.get("grid_y", PackedInt32Array())

	var hp_arr = frame.get("health", PackedFloat32Array())

	var flags_arr = frame.get("flags", PackedInt32Array())

	var routed_arr = frame.get("routed", PackedInt32Array())

	var tier_arr = frame.get("tier", PackedInt32Array())

	for i in range(n):

		if i < gx_arr.size():

			store.grid_x[i] = int(gx_arr[i])

		if i < gy_arr.size():

			store.grid_y[i] = int(gy_arr[i])

		if i < hp_arr.size():

			store.health[i] = float(hp_arr[i])

		if i < flags_arr.size():

			store.flags[i] = int(flags_arr[i])

		if i < routed_arr.size():

			store.routed[i] = int(routed_arr[i])

		if i < tier_arr.size():

			store.tier[i] = int(tier_arr[i])

		if map_data != null:

			store.positions[i] = map_data.cell_center(store.grid_x[i], store.grid_y[i])




static func _frame_unit_count(frame: Dictionary) -> int:

	var gx_arr = frame.get("grid_x", PackedInt32Array())

	if gx_arr is PackedInt32Array:

		return gx_arr.size()

	return 0
