extends SceneTree

## Headless: R1 ocean claim via soldier ferry beachhead (replaces retired land-bridge invasion).
## godot --headless --path . -s res://bridge_invasion_smoke_test.gd

const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")


func _init() -> void:
	print("=== Ferry Beachhead Smoke Test (R1; was bridge invasion) ===")
	_run()
	quit()


func _run() -> void:
	var lines: PackedStringArray = PackedStringArray()
	if not BattleTerritoryRustBackendLib.extension_available():
		_log(lines, "WARN Rust GDExtension not loaded — skip ferry beachhead assert")
		_log(lines, "PASS ferry beachhead (skipped; no Rust)")
		_write(lines)
		return

	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var home: Vector2i = map_data.player_home_grid
	var island: Vector2i = _find_inland_foreign(map_data, home)
	if island.x < 0:
		_log(lines, "FAIL no foreign landmass tile")
		_write(lines)
		return

	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, 200, 200, null, {}, true)
	if not sim.enable_rust_live():
		_log(lines, "WARN rust live unavailable — skip beachhead assert")
		_log(lines, "PASS ferry beachhead (skipped; no rust live)")
		_write(lines)
		return

	var idx: int = map_data.cell_index(island.x, island.y)
	var result: Dictionary = {}
	if sim.rust_field != null:
		result = sim.rust_field.extend_beachhead_from_landing(
			island.x, island.y, BattleTileControlLib.OWNER_FRIENDLY
		)
	var claimable := false
	if sim.rust_field != null and sim.rust_field.has_method("claimable_at_index"):
		claimable = bool(sim.rust_field.claimable_at_index(idx))
	elif sim.tile_control != null and idx >= 0 and idx < sim.tile_control.claimable_mask.size():
		claimable = int(sim.tile_control.claimable_mask[idx]) != 0

	if not claimable and not bool(result.get("changed", false)):
		_log(lines, "FAIL ferry beachhead did not claim island %s" % island)
		_write(lines)
		return

	_log(lines, "OK ferry beachhead claimable island=%s idx=%d" % [island, idx])
	_log(lines, "PASS ferry beachhead smoke")
	_write(lines)


func _find_inland_foreign(map_data, home: Vector2i) -> Vector2i:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var sources: Array[Vector2i] = [home]
	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			if OutpostBuildLib.needs_bridge_route(map_data, Vector2i(gx, gy), sources):
				return Vector2i(gx, gy)
	return Vector2i(-1, -1)


func _log(lines: PackedStringArray, msg: String) -> void:
	print(msg)
	lines.append(msg)


func _write(lines: PackedStringArray) -> void:
	var f := FileAccess.open("res://bridge_invasion_smoke_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_line(line)
		f.close()
