extends SceneTree

## Headless: barracks soldier spawn + orphan damage.
## godot --headless --path . -s res://barracks_smoke_test.gd

const CFG := preload("res://WorldConquestConfig.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")


func _init() -> void:
	print("=== Barracks Soldier Smoke Test ===")
	_run()
	quit()


func _run() -> void:
	if not BattleTerritoryRustBackendLib.extension_available():
		push_error("barracks_smoke_test: Rust GDExtension not loaded")
		return
	var map_data = EarthMapGeneratorLib.generate(4242)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		push_error("barracks_smoke_test: Rust live backend failed")
		return
	if not sim.agents_ready():
		push_error("barracks_smoke_test: agents not configured")
		return
	sim.sync_agent_nav()
	var bid: int = 99
	var bx: int = map_data.player_home_grid.x
	var by: int = map_data.player_home_grid.y
	if not sim.try_spawn_soldier(bid, BattleTileControlLib.OWNER_FRIENDLY, bx, by):
		push_error("barracks_smoke_test: spawn failed")
		return
	var snap0: Dictionary = sim.get_agent_snapshot()
	var gx0: PackedInt32Array = snap0.get("gx", PackedInt32Array())
	var gy0: PackedInt32Array = snap0.get("gy", PackedInt32Array())
	if gx0.is_empty():
		push_error("barracks_smoke_test: no spawn position")
		return
	var start_x: int = gx0[0]
	var start_y: int = gy0[0]
	for _i in range(28):
		sim.advance_round()
	var snap: Dictionary = sim.get_agent_snapshot()
	if int(snap.get("count", 0)) < 1:
		push_error("barracks_smoke_test: soldier died immediately")
		return
	var gx1: PackedInt32Array = snap.get("gx", PackedInt32Array())
	var gy1: PackedInt32Array = snap.get("gy", PackedInt32Array())
	if gx1[0] == start_x and gy1[0] == start_y:
		push_error("barracks_smoke_test: soldier did not move after 28 rounds")
		return
	sim.notify_barracks_destroyed(bid)
	for _j in range(20):
		sim.advance_round()
	print("barracks_smoke_test: PASS (agents=%d)" % sim.agent_living_count())
