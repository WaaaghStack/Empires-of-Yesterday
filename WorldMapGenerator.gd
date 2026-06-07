class_name WorldMapGenerator
extends RefCounted

const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
const WorldRTSConfigLib := preload("res://WorldRTSConfig.gd")
const WorldRTS3DConfigLib := preload("res://WorldRTS3DConfig.gd")


static func generate_world(run_seed: int):
	var mix: Dictionary = BattleMapGeneratorLib.DEFAULT_QUANTUM_MIX.duplicate()
	return BattleMapGeneratorLib.generate_sized(
		run_seed,
		WorldRTSConfigLib.GRID_W,
		WorldRTSConfigLib.GRID_H,
		WorldRTSConfigLib.CELL_SIZE,
		mix,
		WorldRTSConfigLib.PLAYER_FORCE,
		WorldRTSConfigLib.ENEMY_FORCE,
		"world",
		"open_field",
		"world",
	)


static func generate_world_3d(run_seed: int):
	var mix: Dictionary = BattleMapGeneratorLib.DEFAULT_QUANTUM_MIX.duplicate()
	return BattleMapGeneratorLib.generate_sized(
		run_seed,
		WorldRTS3DConfigLib.GRID_W,
		WorldRTS3DConfigLib.GRID_H,
		WorldRTS3DConfigLib.CELL_SIZE,
		mix,
		WorldRTS3DConfigLib.PLAYER_FORCE,
		WorldRTS3DConfigLib.ENEMY_FORCE,
		"world",
		"open_field",
		"world_3d",
	)
