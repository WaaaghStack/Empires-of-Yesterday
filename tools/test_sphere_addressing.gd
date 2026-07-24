extends SceneTree
## Unit gates for sphere dual-address + sector radians (AUDIT A1–A4).
## Run: godot --headless --path . -s res://tools/test_sphere_addressing.gd

const BattleMapDataLib := preload("res://BattleMapData.gd")
const SphereGridLib := preload("res://SphereGridLib.gd")


func _initialize() -> void:
	var fails: PackedStringArray = PackedStringArray()
	var freq: int = 2
	var grid: Dictionary = SphereGridLib.generate(freq)
	var cell_count: int = int(grid.get("cell_count", 0))
	if cell_count <= 0:
		push_error("FAIL generate returned empty grid")
		quit(1)
		return
	var map = BattleMapDataLib.new()
	map.sphere_mode = true
	map.cell_count = cell_count
	map.sphere_frequency = freq
	map.grid_width = 32
	map.grid_height = 16
	map.overlay_width = 32
	map.overlay_height = 16
	map.cell_positions = grid.get("positions", PackedVector3Array())
	map.cell_lat = grid.get("lat", PackedFloat32Array())
	map.cell_lon = grid.get("lon", PackedFloat32Array())
	map.neighbors = grid.get("neighbors", PackedInt32Array())
	map.neighbor_counts = grid.get("neighbor_count", PackedByteArray())
	map.equirect_to_cell = SphereGridLib.build_equirect_to_cell(grid, map.grid_width, map.grid_height)
	map.terrain_cells.resize(cell_count)
	map.tile_height.resize(cell_count)
	for i in range(cell_count):
		map.terrain_cells[i] = 1 if i % 3 != 0 else 0  # WATER=0 assumed sparse
		map.tile_height[i] = float(i % 10) / 10.0

	# A1: gameplay cell_id (5,0) stays cell 5; equirect pixel (5,0) uses LUT (may differ).
	var gameplay_id: int = map.cell_index(5, 0)
	if gameplay_id != 5:
		fails.append("cell_index(5,0) gameplay expected 5 got %d" % gameplay_id)
	var eq0: int = map.equirect_pixel_to_cell(5, 0)
	if eq0 < 0 or eq0 >= cell_count:
		fails.append("equirect_pixel_to_cell(5,0) out of range %d" % eq0)
	# Mid-latitude equirect must be LUT-based, not dual shortcut.
	var eq_mid: int = map.equirect_pixel_to_cell(10, 8)
	var lut_mid: int = int(map.equirect_to_cell[8 * map.grid_width + 10])
	if eq_mid != lut_mid:
		fails.append("equirect mid pixel %d != lut %d" % [eq_mid, lut_mid])
	# cell_index with gy!=0 must match equirect path
	var via_cell_index: int = map.cell_index(10, 8)
	if via_cell_index != eq_mid:
		fails.append("cell_index(10,8)=%d != equirect %d" % [via_cell_index, eq_mid])

	# A2: sector bins spread across multiple columns when lon varies
	var bins := {}
	for cid in range(mini(cell_count, 42)):
		var cr: Vector2i = map.sector_col_row_for_grid(cid, 0)
		bins["%d_%d" % [cr.x, cr.y]] = true
	if bins.size() < 3:
		fails.append("sector bins too few (%d) — likely still using degrees on radians" % bins.size())

	# A3: equirect land helpers don't crash and differ from raw cell_id path for row0
	var land_eq: bool = map.is_land_equirect_pixel(0, 0)
	var land_id0: bool = map.is_land_cell_id(0)
	# May or may not differ; must be valid booleans and height in range
	var ht: float = map.get_tile_height_equirect_pixel(0, 0)
	if ht < 0.0 or ht > 1.0:
		fails.append("equirect height out of range %s" % str(ht))

	# A4: sphere cell_center is finite
	var c: Vector2 = map.cell_center(0, 0)
	if not is_finite(c.x) or not is_finite(c.y):
		fails.append("cell_center non-finite")

	if not fails.is_empty():
		for f in fails:
			push_error("FAIL %s" % f)
		quit(1)
		return
	print(
		"PASS sphere addressing cell_count=%d eq0=%d eq_mid=%d sectors=%d land_eq=%s land_id0=%s"
		% [cell_count, eq0, eq_mid, bins.size(), str(land_eq), str(land_id0)]
	)
	quit(0)
