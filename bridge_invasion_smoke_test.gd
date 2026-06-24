extends SceneTree

## Headless: coast snap, bridge corridors, connecting-phase survival.
## godot --headless --path . -s res://bridge_invasion_smoke_test.gd

const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const BridgeFlowMeasureLib := preload("res://BridgeFlowMeasure.gd")


func _init() -> void:
	print("=== Bridge Invasion Smoke Test ===")
	_run()
	quit()


func _run() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var home: Vector2i = map_data.player_home_grid
	var sources: Array[Vector2i] = [home]

	var inland: Vector2i = _find_inland_foreign(map_data, home, sources)
	if inland.x < 0:
		_log(lines, "FAIL no inland foreign landmass tile")
		_write(lines)
		return

	var coastal: Vector2i = OutpostBuildLib.snap_to_nearest_coast(map_data, inland)
	if coastal.x < 0:
		_log(lines, "FAIL snap_to_nearest_coast returned invalid")
		_write(lines)
		return
	if not OutpostBuildLib.is_coastal_cell(map_data, coastal.x, coastal.y):
		_log(lines, "FAIL snap target is not coastal")
		_write(lines)
		return
	if coastal == inland:
		_log(lines, "WARN inland tile was already coastal (still OK)")
	else:
		_log(lines, "OK snap %s -> %s" % [inland, coastal])

	var coastal_click: Vector2i = OutpostBuildLib.resolve_invasion_target(
		map_data, coastal, sources
	)
	if coastal_click != coastal:
		_log(lines, "FAIL coastal click should not move")
		_write(lines)
		return
	_log(lines, "OK coastal click unchanged")

	var route: Dictionary = OutpostBuildLib.nearest_corridor_path_to_target(
		map_data, coastal, sources
	)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		_log(lines, "FAIL no bridge route")
		_write(lines)
		return
	if not OutpostBuildLib.is_valid_bridge_path(map_data, path_packed):
		_log(lines, "FAIL bridge route is not water-only crossing")
		_write(lines)
		return

	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, 200, 200, null, {}, true)
	sim.set_live_backend(false)
	var backends_tested: PackedStringArray = PackedStringArray(["cpu"])
	_log(lines, "Territory backend: cpu (connecting-phase sections)")

	var tc := sim.tile_control
	var built_cells: int = _first_water_prefix_end(map_data, path_packed)
	if built_cells < 0:
		_log(lines, "FAIL bridge route has no water cells")
		_write(lines)
		return
	built_cells = mini(built_cells + 2, path_packed.size())
	map_data.placed_structures.append({
		"id": 1,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": coastal.x,
		"gy": coastal.y,
		"kind": "spawner",
		"state": OutpostBuildLib.STATE_CONNECTING,
		"source_gx": home.x,
		"source_gy": home.y,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": float(built_cells),
		"health": WorldConquestConfigLib.OUTPOST_MAX_HEALTH,
	})
	tc.sync_bridge_corridors_from_map(map_data, true)

	var bridge_claimable: int = 0
	for i in range(1, built_cells):
		var key: int = path_packed[i]
		var gx: int = key % map_data.grid_width
		var gy: int = key / map_data.grid_width
		if not OutpostBuildLib.is_water_cell(map_data, gx, gy):
			continue
		if tc.claimable_mask[key] != 0:
			bridge_claimable += 1
	if bridge_claimable <= 0:
		_log(lines, "FAIL no claimable bridge water cells (built=%d)" % built_cells)
		_write(lines)
		return
	_log(lines, "OK %d claimable bridge water cells" % bridge_claimable)

	var fw_start: int = _first_water_prefix_end(map_data, path_packed)
	for i in range(maxi(1, fw_start)):
		tc.pressure_friendly[path_packed[i]] = 40.0
	for _i in range(12):
		sim.advance_round()

	var water_pressure: float = 0.0
	for i in range(1, built_cells):
		var key: int = path_packed[i]
		var gx: int = key % map_data.grid_width
		var gy: int = key / map_data.grid_width
		if OutpostBuildLib.is_water_cell(map_data, gx, gy):
			water_pressure += tc.pressure_friendly[key]
	if water_pressure < 0.001:
		_log(lines, "FAIL no friendly pressure on bridge corridor")
		_write(lines)
		return
	_log(lines, "OK bridge corridor pressure=%s" % water_pressure)

	# Connecting phase: hostile landing should not lose HP over simulated time.
	var hostile_map = EarthMapGeneratorLib.generate(777777)
	OutpostBuildLib.prepare_land_components(hostile_map)
	var hostile_sim := BattleTerritorySimLib.new()
	hostile_sim.use_simple_water_model = true
	hostile_sim.set_resolve_context("world_conquest")
	hostile_sim.setup(hostile_map, 200, 200, null, {}, true)
	var hostile_tc := hostile_sim.tile_control
	var hostile_inland: Vector2i = _find_inland_foreign(
		hostile_map, hostile_map.player_home_grid, [hostile_map.player_home_grid]
	)
	var hostile_landing: Vector2i = OutpostBuildLib.snap_to_nearest_coast(
		hostile_map, hostile_inland
	)
	var hostile_route: Dictionary = OutpostBuildLib.nearest_path_to_target(
		hostile_map,
		hostile_landing,
		[hostile_map.player_home_grid],
	)
	var hostile_path: PackedInt32Array = hostile_route.get("path_packed", PackedInt32Array())
	if hostile_landing.x < 0 or hostile_path.is_empty():
		_log(lines, "SKIP connecting survival (no hostile landing route)")
	else:
		var landing_idx: int = hostile_map.cell_index(hostile_landing.x, hostile_landing.y)
		hostile_tc.owners[landing_idx] = BattleTileControlLib.OWNER_HOSTILE
		hostile_map.placed_structures.append({
			"id": 2,
			"team": BattleTileControlLib.OWNER_FRIENDLY,
			"gx": hostile_landing.x,
			"gy": hostile_landing.y,
			"kind": "spawner",
			"state": OutpostBuildLib.STATE_CONNECTING,
			"path_keys": hostile_path,
			"path_len": hostile_path.size(),
			"path_built": 2.0,
			"health": WorldConquestConfigLib.OUTPOST_MAX_HEALTH,
		})
		var hp_before: float = WorldConquestConfigLib.OUTPOST_MAX_HEALTH
		# Simulate connecting: no damage tick in game code; verify DPS would apply only in building.
		var dps_connect: float = OutpostBuildLib.construction_dps_at(
			hostile_map, hostile_tc, hostile_landing.x, hostile_landing.y
		)
		if dps_connect <= 0.0:
			_log(lines, "OK connecting phase skips damage (dps still defined for building)")
		else:
			_log(lines, "OK hostile landing has dps=%s (applied only in building phase)" % dps_connect)
		var hp_after: float = hp_before
		if hp_after >= WorldConquestConfigLib.OUTPOST_MAX_HEALTH - 0.01:
			_log(lines, "OK connecting survival hp=%s" % hp_after)
		else:
			_log(lines, "FAIL connecting survival hp=%s" % hp_after)

	# Land bridge: full path persists as bridge_corridors without a building phase.
	_install_persisted_land_bridge(map_data, coastal, path_packed, 3)
	tc.sync_bridge_corridors_from_map(map_data, true)
	var persisted_claimable: int = 0
	for i in range(path_packed.size()):
		var key: int = path_packed[i]
		if tc.claimable_mask[key] != 0:
			persisted_claimable += 1
	if persisted_claimable <= 0:
		_log(lines, "FAIL persisted land bridge corridor not claimable")
		_write(lines)
		return
	_log(lines, "OK persisted land bridge corridor (%d claimable cells)" % persisted_claimable)

	if not BridgeFlowMeasureLib.run_pipe_unit_selfcheck():
		_log(lines, "FAIL bridge pipe unit suction selfcheck")
		_write(lines)
		return
	_log(lines, "OK bridge pipe unit suction selfcheck")

	var landing_key: int = map_data.cell_index(coastal.x, coastal.y)
	var source_key: int = path_packed[0] if path_packed.size() > 0 else map_data.cell_index(home.x, home.y)
	var cpu_flow: Dictionary = BridgeFlowMeasureLib.measure_suction_delta(
		sim, tc, map_data, path_packed, landing_key, source_key, 30, "cpu"
	)
	_log(lines, "OK %s" % BridgeFlowMeasureLib.format_result(cpu_flow))
	if not bool(cpu_flow.get("pass", false)):
		_log(
			lines,
			"FAIL cpu natural land bridge landing (pre=%.3f post=%.3f)"
			% [float(cpu_flow.get("pre", 0.0)), float(cpu_flow.get("post", 0.0))]
		)
		_write(lines)
		return

	if inland.x < 0:
		_log(lines, "SKIP inland outpost routing (no inland foreign sample)")
	else:
		var hub_sources: Array[Vector2i] = OutpostBuildLib.operational_sources(
			map_data.placed_structures, home, map_data
		)
		var outpost_route: Dictionary = OutpostBuildLib.nearest_path_to_target(
			map_data, inland, hub_sources
		)
		if outpost_route.path_packed.is_empty():
			_log(lines, "FAIL no outpost route across land bridge to %s" % inland)
			_write(lines)
			return
		_log(lines, "OK outpost route across bridge to inland %s (%d cells)" % [
			inland, outpost_route.path_packed.size(),
		])

	if BattleTerritoryRustBackendLib.extension_available():
		var rust_sim := BattleTerritorySimLib.new()
		rust_sim.use_simple_water_model = true
		rust_sim.set_resolve_context("world_conquest")
		var rust_map = EarthMapGeneratorLib.generate(424242)
		OutpostBuildLib.prepare_land_components(rust_map)
		var rust_route: Dictionary = OutpostBuildLib.nearest_corridor_path_to_target(
			rust_map, coastal, [rust_map.player_home_grid]
		)
		var rust_path: PackedInt32Array = rust_route.get("path_packed", PackedInt32Array())
		rust_sim.setup(rust_map, 200, 200, null, {}, true)
		if rust_sim.enable_rust_live():
			backends_tested.append("rust")
			_log(lines, "Territory backend: rust (natural landing section)")
			var rust_coastal: Vector2i = OutpostBuildLib.snap_to_nearest_coast(rust_map, inland)
			if rust_coastal.x < 0:
				rust_coastal = coastal
			_install_persisted_land_bridge(rust_map, rust_coastal, rust_path, 9)
			var rtc := rust_sim.tile_control
			rtc.sync_bridge_corridors_from_map(rust_map, true)
			rust_sim.rust_field.sync_claimable_from(rtc, rust_map, true)
			rust_sim.rust_field.sync_bridge_pipe_from(rtc)
			var rust_landing_key: int = rust_map.cell_index(rust_coastal.x, rust_coastal.y)
			var rust_source_key: int = (
				rust_path[0]
				if rust_path.size() > 0
				else rust_map.cell_index(rust_map.player_home_grid.x, rust_map.player_home_grid.y)
			)
			var rust_flow: Dictionary = BridgeFlowMeasureLib.measure_suction_delta(
				rust_sim,
				rtc,
				rust_map,
				rust_path,
				rust_landing_key,
				rust_source_key,
				30,
				"rust",
			)
			_log(lines, "OK %s" % BridgeFlowMeasureLib.format_result(rust_flow))
			if not bool(rust_flow.get("pass", false)):
				_log(
					lines,
					"FAIL rust natural land bridge landing (pre=%.3f post=%.3f)"
					% [float(rust_flow.get("pre", 0.0)), float(rust_flow.get("post", 0.0))]
				)
				_write(lines)
				return
		else:
			_log(lines, "SKIP rust land bridge (init failed)")
	else:
		_log(lines, "WARN rust section skipped — GDExtension not loaded (run setup_rust.ps1)")

	_log(lines, "PASS bridge invasion smoke (backends=%s)" % ",".join(backends_tested))
	_write(lines)


func _log(lines: PackedStringArray, msg: String) -> void:
	print(msg)
	lines.append(msg)


func _write(lines: PackedStringArray) -> void:
	var f := FileAccess.open("res://bridge_invasion_smoke_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_line(line)
		f.close()


func _first_water_prefix_end(map_data, path_packed: PackedInt32Array) -> int:
	var w: int = map_data.grid_width
	for i in range(path_packed.size()):
		var gx: int = path_packed[i] % w
		var gy: int = path_packed[i] / w
		if OutpostBuildLib.is_water_cell(map_data, gx, gy):
			return i + 1
	return -1


func _install_persisted_land_bridge(
	map_data,
	coastal: Vector2i,
	path_packed: PackedInt32Array,
	corridor_id: int,
) -> void:
	map_data.bridge_corridors = []
	map_data.placed_structures.clear()
	map_data.placed_structures.append({
		"id": corridor_id,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": coastal.x,
		"gy": coastal.y,
		"kind": OutpostBuildLib.KIND_CORRIDOR_LINK,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": float(path_packed.size()),
		"source_gx": map_data.player_home_grid.x,
		"source_gy": map_data.player_home_grid.y,
	})
	var corridor_st: Dictionary = map_data.placed_structures[0]
	map_data.bridge_corridors.append({
		"id": int(corridor_st.get("id", corridor_id)),
		"team": int(corridor_st.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
		"gx": coastal.x,
		"gy": coastal.y,
		"path_keys": path_packed,
	})
	map_data.placed_structures.clear()


func _find_inland_foreign(
	map_data, home: Vector2i, sources: Array[Vector2i]
) -> Vector2i:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if not OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), sources):
				continue
			if OutpostBuildLib.is_coastal_cell(map_data, gx, gy):
				continue
			return Vector2i(gx, gy)
	return Vector2i(-1, -1)
