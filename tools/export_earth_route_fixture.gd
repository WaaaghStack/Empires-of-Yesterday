extends SceneTree

const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")

func _init() -> void:
	var map_data = EarthMapGeneratorLib.generate(424242)
	OutpostBuildLib.prepare_land_components(map_data)
	var packed: Dictionary = OutpostBuildLib.pack_route_snapshot(map_data, [])
	var out_path := "res://testdata/earth424242_route.bin"
	DirAccess.make_dir_recursive_absolute("res://testdata")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("could not open %s" % out_path)
		quit(1)
		return
	f.store_32(int(packed.grid_w))
	f.store_32(int(packed.grid_h))
	f.store_buffer(packed.land_mask)
	var comp: PackedInt32Array = packed.land_comp
	for i in comp.size():
		f.store_32(comp[i])
	f.close()
	print("wrote %s (%d bytes)" % [out_path, int(packed.grid_w) * int(packed.grid_h)])
	quit()
