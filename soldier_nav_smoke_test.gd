extends SceneTree

## Headless: soldier nav rules — march to unclaimed land, hostile team.
## R1: bridge-crossing case retired (ocean claim = ferry beachhead; see bridge_invasion_smoke_test.gd).
## godot --headless --path . -s res://soldier_nav_smoke_test.gd

const CFG := preload("res://WorldConquestConfig.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")


func _init() -> void:
	print("=== Soldier Nav Smoke Test ===")
	_run()
	quit()


func _run() -> void:
	var lines: PackedStringArray = PackedStringArray()
	if not BattleTerritoryRustBackendLib.extension_available():
		_fail(lines, "Rust GDExtension not loaded")
		return

	if not _friendly_moves(lines):
		_write(lines)
		return
	_log(lines, "OK friendly soldier moved toward frontier")

	if not _hostile_moves(lines):
		_write(lines)
		return
	_log(lines, "OK hostile soldier moved toward frontier")

	# R1: ocean boots use soldier ferry + beachhead (bridge_invasion_smoke_test.gd), not corridors.
	_log(lines, "OK skip corridor crossing (R1; ferry beachhead covers ocean claim)")

	_log(lines, "PASS soldier nav smoke")
	_write(lines)


func _friendly_moves(lines: PackedStringArray) -> bool:
	var map_data = EarthMapGeneratorLib.generate(4242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := _make_sim(map_data)
	var bid: int = 99
	var home: Vector2i = map_data.player_home_grid
	if not sim.try_spawn_soldier(bid, BattleTileControlLib.OWNER_FRIENDLY, home.x, home.y):
		_fail(lines, "friendly spawn failed")
		return false
	var snap0: Dictionary = sim.get_agent_snapshot()
	var gx0: PackedInt32Array = snap0.get("gx", PackedInt32Array())
	var gy0: PackedInt32Array = snap0.get("gy", PackedInt32Array())
	if gx0.is_empty():
		_fail(lines, "friendly soldier missing after spawn")
		return false
	var sx: int = gx0[0]
	var sy: int = gy0[0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		_fail(lines, "friendly soldier died")
		return false
	if snap["gx"][0] == sx and snap["gy"][0] == sy:
		_fail(lines, "friendly soldier did not move")
		return false
	return true


func _hostile_moves(lines: PackedStringArray) -> bool:
	var map_data = EarthMapGeneratorLib.generate(7777)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := _make_sim(map_data)
	var enemy_home: Vector2i = map_data.enemy_home_grid
	var bid: int = 100
	if not sim.try_spawn_soldier(bid, BattleTileControlLib.OWNER_HOSTILE, enemy_home.x, enemy_home.y):
		_fail(lines, "hostile spawn failed")
		return false
	var snap0: Dictionary = sim.get_agent_snapshot()
	var sx: int = snap0["gx"][0]
	var sy: int = snap0["gy"][0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		_fail(lines, "hostile soldier died")
		return false
	if snap["gx"][0] == sx and snap["gy"][0] == sy:
		_fail(lines, "hostile soldier did not move")
		return false
	return true


func _make_sim(map_data) -> BattleTerritorySimLib:
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		push_error("soldier_nav_smoke_test: rust live failed")
		return null
	if not sim.agents_ready():
		push_error("soldier_nav_smoke_test: agents not configured")
		return null
	sim.sync_agent_nav()
	return sim


func _log(lines: PackedStringArray, msg: String) -> void:
	print(msg)
	lines.append(msg)


func _fail(lines: PackedStringArray, msg: String) -> void:
	_log(lines, "FAIL %s" % msg)


func _write(lines: PackedStringArray) -> void:
	var f := FileAccess.open("res://soldier_nav_smoke_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_line(line)
		f.close()
