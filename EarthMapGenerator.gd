class_name EarthMapGenerator
extends RefCounted

const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")


## Back-compat wrapper — prefer WorldConquestMapGenerator.generate(map_id, seed).
static func generate(run_seed: int):
	return WorldConquestMapGeneratorLib.generate(WorldMapCatalogLib.DEFAULT_MAP_ID, run_seed)
