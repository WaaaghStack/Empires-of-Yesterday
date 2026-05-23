extends SceneTree

const REPORT_PATH := "res://qa_report.txt"
const SCRIPT_PATHS: Array[String] = [
	"res://CombatAudio.gd",
	"res://CombatFx.gd",
	"res://Door.gd",
	"res://DynamicPathGraph.gd",
	"res://Enemy.gd",
	"res://EnemyUnit.gd",
	"res://GameTheme.gd",
	"res://LineOfSight.gd",
	"res://MapVisuals.gd",
	"res://MissionMapData.gd",
	"res://MissionState.gd",
	"res://OperatorRosterCard.gd",
	"res://OrderType.gd",
	"res://PortraitPool.gd",
	"res://ProceduralMapGenerator.gd",
	"res://Room.gd",
	"res://SoldierCard.gd",
	"res://SoldierResource.gd",
	"res://SoldierUnit.gd",
	"res://SquadRosterPanel.gd",
	"res://SquadSelection.gd",
	"res://TacticalMap.gd",
]

const SCENE_PATHS: Array[String] = [
	"res://Door.tscn",
	"res://EnemyUnit.tscn",
	"res://OperatorRosterCard.tscn",
	"res://Room.tscn",
	"res://SoldierCard.tscn",
	"res://SoldierUnit.tscn",
	"res://SquadSelection.tscn",
	"res://TacticalMap.tscn",
]

const RESOURCE_PATHS: Array[String] = [
	"res://Soldier_Marine1.tres",
	"res://Soldier_Marine2.tres",
	"res://Soldier_Marine3.tres",
	"res://Soldier_Marine4.tres",
]

var _lines: PackedStringArray = PackedStringArray()
var _failures: Array[String] = []


func _initialize() -> void:
	_log("=== QA VALIDATION START ===")
	_validate_scripts()
	_validate_scenes()
	_validate_resources()
	_validate_order_type()
	_validate_portrait_pool()
	_validate_map_generation()
	_validate_squad_selection_script()
	_print_summary()
	_write_report()
	quit(1 if not _failures.is_empty() else 0)


func _log(message: String) -> void:
	_lines.append(message)
	print(message)


func _fail(message: String) -> void:
	_failures.append(message)
	_log("FAIL: %s" % message)


func _validate_scripts() -> void:
	_log("-- Scripts --")
	for path in SCRIPT_PATHS:
		if load(path) == null:
			_fail("Script failed to load: %s" % path)
		else:
			_log("OK  %s" % path)


func _validate_scenes() -> void:
	_log("-- Scenes --")
	for path in SCENE_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			_fail("Scene failed to load: %s" % path)
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			_fail("Scene failed to instantiate: %s" % path)
		else:
			_log("OK  %s" % path)
			instance.free()


func _validate_resources() -> void:
	_log("-- Soldier resources --")
	for path in RESOURCE_PATHS:
		var resource: SoldierResource = load(path)
		if resource == null:
			_fail("Resource failed to load: %s" % path)
		else:
			_log("OK  %s (%s)" % [path, resource.soldier_name])


func _validate_order_type() -> void:
	_log("-- OrderType enum --")
	var order_script: GDScript = load("res://OrderType.gd")
	if order_script == null:
		_fail("OrderType.gd missing")
		return
	var explore_value: int = OrderType.Type.EXPLORE
	if explore_value != 6:
		_fail("OrderType.Type.EXPLORE expected 6, got %d" % explore_value)
	else:
		_log("OK  EXPLORE enum value")


func _validate_portrait_pool() -> void:
	_log("-- Portrait pool --")
	var count: int = PortraitPool.get_portrait_count()
	_log("Portrait textures loaded: %d" % count)
	if count == 0:
		_log("WARN no portrait PNGs found (game falls back to class colors)")
	else:
		var portraits: Array[Texture2D] = PortraitPool.get_random_portraits(4)
		if portraits.size() < mini(4, count):
			_fail("PortraitPool returned %d portraits for count=4" % portraits.size())
		else:
			_log("OK  random portrait assignment")


func _validate_map_generation() -> void:
	_log("-- Map generation --")
	var map_data = ProceduralMapGenerator.generate(12345)
	if map_data == null:
		_fail("ProceduralMapGenerator.generate returned null")
		return
	var rooms: Array = map_data.get_room_dicts()
	if rooms.is_empty():
		_fail("Generated map has no rooms")
	else:
		_log("OK  generated %d rooms (seed 12345)" % rooms.size())
	_validate_cross_room_pathfinding(map_data)


func _validate_cross_room_pathfinding(map_data) -> void:
	_log("-- Cross-room pathfinding --")
	var graph = map_data.path_graph
	if graph.corridor_rects.is_empty():
		_fail("Path graph corridor_rects is empty after map generation")
		return
	var rooms: Array = map_data.get_room_dicts()
	if rooms.size() < 2:
		return
	var path: PackedVector2Array = graph.find_path(rooms[0]["pos"], rooms[1]["pos"])
	if path.is_empty():
		_fail("find_path returned empty route between adjacent rooms")
		return
	for rect in graph.corridor_rects:
		if not graph.is_in_corridor(rect.get_center()):
			_fail("Corridor midpoint not registered as corridor")
			return
	_log("OK  corridor connectivity")


func _validate_squad_selection_script() -> void:
	_log("-- Squad selection script --")
	var script: GDScript = load("res://SquadSelection.gd")
	if script == null:
		_fail("SquadSelection.gd missing")
		return
	var card_script: GDScript = load("res://SoldierCard.gd")
	if card_script == null:
		_fail("SoldierCard.gd missing")
		return
	_log("OK  squad selection scripts")


func _print_summary() -> void:
	_log("=== QA VALIDATION END ===")
	if _failures.is_empty():
		_log("RESULT: PASS")
	else:
		_log("RESULT: FAIL (%d issue(s))" % _failures.size())


func _write_report() -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		for line in _lines:
			file.store_line(line)
		file.close()
		_log("Report written to %s" % REPORT_PATH)
