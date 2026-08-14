extends SceneTree

## Headless smoke: procedural Custom World continents + criteria effects.
## godot --headless --path . -s res://tools/custom_world_criteria_smoke.gd

const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")


func _init() -> void:
	var seed_a: int = 424242
	var seed_b: int = 777001
	var earth = WorldConquestMapGeneratorLib.generate(
		WorldMapCatalogLib.MAP_EARTH, seed_a, false, {}
	)
	var proc_a = WorldConquestMapGeneratorLib.generate(
		WorldMapCatalogLib.MAP_EARTH,
		seed_a,
		false,
		{"procedural": true, "land_bias": 0.0, "resource_density": 1.0, "mountain_bias": 0.0},
	)
	var proc_b = WorldConquestMapGeneratorLib.generate(
		WorldMapCatalogLib.MAP_EARTH,
		seed_b,
		false,
		{"procedural": true, "land_bias": 0.0, "resource_density": 1.0, "mountain_bias": 0.0},
	)
	var proc_wet = WorldConquestMapGeneratorLib.generate(
		WorldMapCatalogLib.MAP_EARTH,
		seed_a,
		false,
		{"procedural": true, "land_bias": 0.8, "resource_density": 1.75, "mountain_bias": 0.6},
	)
	var proc_dry = WorldConquestMapGeneratorLib.generate(
		WorldMapCatalogLib.MAP_EARTH,
		seed_a,
		false,
		{"procedural": true, "land_bias": -0.7, "resource_density": 0.35, "mountain_bias": -0.5},
	)

	var earth_land: int = _count_land(earth)
	var proc_a_land: int = _count_land(proc_a)
	var proc_b_land: int = _count_land(proc_b)
	var wet_land: int = _count_land(proc_wet)
	var dry_land: int = _count_land(proc_dry)
	var base_mtn: int = _count_terrain(proc_a, BattleMapDataLib.Terrain.MOUNTAIN)
	var wet_mtn: int = _count_terrain(proc_wet, BattleMapDataLib.Terrain.MOUNTAIN)
	var base_res: int = proc_a.resource_deposits.size()
	var dense_res: int = proc_wet.resource_deposits.size()
	var sparse_res: int = proc_dry.resource_deposits.size()

	var overlap_earth: Dictionary = _land_overlap(proc_a, earth)
	var jaccard_earth: float = float(overlap_earth.get("jaccard", 1.0))
	var differ_earth: int = int(overlap_earth.get("differ", 0))
	var overlap_seeds: Dictionary = _land_overlap(proc_a, proc_b)
	var jaccard_seeds: float = float(overlap_seeds.get("jaccard", 1.0))
	var differ_seeds: int = int(overlap_seeds.get("differ", 0))

	var west = WorldConquestMapGeneratorLib.pick_random_land_spawn(proc_a, seed_a, "west")
	var east = WorldConquestMapGeneratorLib.pick_random_land_spawn(proc_a, seed_a, "east")

	var ok: bool = true
	var detail: PackedStringArray = []

	if str(proc_a.pack_visual_tag) == "":
		ok = false
		detail.append("procedural maps must set pack_visual_tag")
	if wet_land <= proc_a_land:
		ok = false
		detail.append("land_bias+ should grow land (%d vs %d)" % [wet_land, proc_a_land])
	if dry_land >= proc_a_land:
		ok = false
		detail.append("land_bias- should shrink land (%d vs %d)" % [dry_land, proc_a_land])
	if dense_res <= base_res:
		ok = false
		detail.append("resource_density+ should add deposits (%d vs %d)" % [dense_res, base_res])
	if sparse_res >= base_res:
		ok = false
		detail.append("resource_density- should cut deposits (%d vs %d)" % [sparse_res, base_res])
	if wet_mtn <= base_mtn:
		ok = false
		detail.append("mountain_bias+ should add mountains (%d vs %d)" % [wet_mtn, base_mtn])
	# Must not be Earth silhouette: Jaccard vs Earth base should be clearly below identity.
	if jaccard_earth > 0.55 or differ_earth < 8000:
		ok = false
		detail.append(
			(
				"procedural must differ from Earth mask (jaccard=%.3f differ=%d earth_land=%d proc_land=%d)"
				% [jaccard_earth, differ_earth, earth_land, proc_a_land]
			)
		)
	# Two seeds must produce different topology.
	if jaccard_seeds > 0.70 or differ_seeds < 5000:
		ok = false
		detail.append(
			(
				"two procedural seeds must differ (jaccard=%.3f differ=%d)"
				% [jaccard_seeds, differ_seeds]
			)
		)
	if west.x < 0 or east.x < 0:
		ok = false
		detail.append("start_region spawn failed")
	elif proc_a.sphere_mode:
		if float(proc_a.cell_lon[west.x]) >= 0.0:
			ok = false
			detail.append("west spawn lon should be < 0 (got %f)" % float(proc_a.cell_lon[west.x]))
		if float(proc_a.cell_lon[east.x]) < 0.0:
			ok = false
			detail.append("east spawn lon should be >= 0 (got %f)" % float(proc_a.cell_lon[east.x]))

	var summary: String = (
		"CUSTOM_WORLD_SMOKE ok=%s land=%d/%d/%d mtn=%d/%d res=%d/%d/%d jacc_earth=%.3f jacc_seeds=%.3f west=%s east=%s"
		% [
			str(ok),
			dry_land,
			proc_a_land,
			wet_land,
			base_mtn,
			wet_mtn,
			sparse_res,
			base_res,
			dense_res,
			jaccard_earth,
			jaccard_seeds,
			str(west),
			str(east),
		]
	)
	print(summary)
	for line in detail:
		print("  FAIL: ", line)
	var f := FileAccess.open("res://tools/custom_world_smoke_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(summary + "\n")
		for line in detail:
			f.store_string("FAIL: %s\n" % line)
		f.close()
	quit(0 if ok else 1)


func _count_land(data) -> int:
	var n: int = 0
	if data.sphere_mode:
		for cid in range(data.cell_count):
			if data.is_land_cell_id(cid):
				n += 1
	else:
		for gy in range(data.grid_height):
			for gx in range(data.grid_width):
				if data.is_land_cell(gx, gy):
					n += 1
	return n


func _count_terrain(data, terrain: int) -> int:
	var n: int = 0
	if data.sphere_mode:
		for cid in range(data.cell_count):
			if int(data.get_cell_terrain(cid, 0)) == terrain:
				n += 1
	else:
		for gy in range(data.grid_height):
			for gx in range(data.grid_width):
				if int(data.get_cell_terrain(gx, gy)) == terrain:
					n += 1
	return n


## Jaccard / differ on land membership. Sphere: compare equirect land via is_land_equirect_pixel
## when available; else compare cell_id land for same topology length.
func _land_overlap(a, b) -> Dictionary:
	var both: int = 0
	var either: int = 0
	var differ: int = 0
	if a.sphere_mode and b.sphere_mode and a.cell_count == b.cell_count:
		for cid in range(a.cell_count):
			var la: bool = a.is_land_cell_id(cid)
			var lb: bool = b.is_land_cell_id(cid)
			if la or lb:
				either += 1
			if la and lb:
				both += 1
			if la != lb:
				differ += 1
	else:
		var w: int = mini(int(a.grid_width), int(b.grid_width))
		var h: int = mini(int(a.grid_height), int(b.grid_height))
		for gy in range(h):
			for gx in range(w):
				var la2: bool = (
					a.is_land_equirect_pixel(gx, gy)
					if a.sphere_mode
					else a.is_land_cell(gx, gy)
				)
				var lb2: bool = (
					b.is_land_equirect_pixel(gx, gy)
					if b.sphere_mode
					else b.is_land_cell(gx, gy)
				)
				if la2 or lb2:
					either += 1
				if la2 and lb2:
					both += 1
				if la2 != lb2:
					differ += 1
	var jaccard: float = 0.0 if either == 0 else float(both) / float(either)
	return {"jaccard": jaccard, "differ": differ, "both": both, "either": either}
