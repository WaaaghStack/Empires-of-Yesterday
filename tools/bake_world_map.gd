extends SceneTree

const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
const WorldMapBakeLib := preload("res://WorldMapBakeLib.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")


func _init() -> void:
	var map_id: String = WorldMapCatalogLib.MAP_EARTH
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--map="):
			map_id = arg.substr(6)
	if map_id != WorldMapCatalogLib.MAP_EARTH:
		push_error("bake_world_map: only earth is implemented (%s)" % map_id)
		quit(1)
		return
	var w: int = WorldConquestConfigLib.GRID_W
	var h: int = WorldConquestConfigLib.GRID_H
	var land: PackedByteArray = WorldMapBakeLib.generate_earth_land_bits(w, h)
	var elev: PackedFloat32Array = WorldMapBakeLib.generate_earth_elevation_norm(w, h, land)
	var land_path: String = "res://data/maps/earth/land_360x180.bin"
	var elev_path: String = "res://data/maps/earth/elev_360x180.bin"
	if not WorldMapBakeLib.write_land_bin(land_path, land, w, h):
		push_error("failed to write %s" % land_path)
		quit(1)
		return
	if not WorldMapBakeLib.write_elev_bin(elev_path, elev, w, h):
		push_error("failed to write %s" % elev_path)
		quit(1)
		return
	var land_n: int = 0
	for b in land:
		if b > 0:
			land_n += 1
	print(
		"baked %s land=%d/%d (%.1f%%) -> %s"
		% [map_id, land_n, land.size(), 100.0 * float(land_n) / float(land.size()), land_path]
	)
	quit()
