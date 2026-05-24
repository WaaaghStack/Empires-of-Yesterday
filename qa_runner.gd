extends Node

const MissionTaskBoardLib := preload("res://MissionTaskBoard.gd")
const MissionStateLib := preload("res://MissionState.gd")
const SquadsManagerLib := preload("res://SquadsManager.gd")

const REPORT_PATH := "res://qa_report.txt"

const SCRIPT_PATHS: Array[String] = [
	"res://BetweenMissionHub.gd",
	"res://Codex.gd",
	"res://CombatAudio.gd",
	"res://CombatFx.gd",
	"res://ControlsOverlay.gd",
	"res://Door.gd",
	"res://DynamicPathGraph.gd",
	"res://Enemy.gd",
	"res://EnemyUnit.gd",
	"res://EvolutionBoard.gd",
	"res://EvolutionNode.gd",
	"res://EvolutionUpgrade.gd",
	"res://GameTheme.gd",
	"res://LineOfSight.gd",
	"res://LoadoutPreset.gd",
	"res://MainMenu.gd",
	"res://MapVisuals.gd",
	"res://MissionDebrief.gd",
	"res://MissionMapData.gd",
	"res://PlanetMapData.gd",
	"res://OvermindHive.gd",
	"res://MissionState.gd",
	"res://MissionTaskBoard.gd",
	"res://MissionEntityIndex.gd",
	"res://CombatCoordinator.gd",
	"res://OrbitalCarrier.gd",
	"res://OpModifier.gd",
	"res://OperatorRosterCard.gd",
	"res://OrderType.gd",
	"res://PortraitPool.gd",
	"res://ProceduralMapGenerator.gd",
	"res://Room.gd",
	"res://RunState.gd",
	"res://RunLog.gd",
	"res://RunSummary.gd",
	"res://SaveManager.gd",
	"res://SoldierCard.gd",
	"res://SoldierResource.gd",
	"res://SoldierUnit.gd",
	"res://SquadsManager.gd",
	"res://SwarmDirector.gd",
	"res://Hive.gd",
	"res://HivePressure.gd",
	"res://CommsTemplates.gd",
	"res://HivePressure.gd",
	"res://CommsTemplates.gd",
	"res://SquadRosterPanel.gd",
	"res://SquadSelection.gd",
	"res://TacticalMap.gd",
	"res://TutorialState.gd",
]

const SCENE_PATHS: Array[String] = [
	"res://BetweenMissionHub.tscn",
	"res://Codex.tscn",
	"res://ControlsOverlay.tscn",
	"res://Door.tscn",
	"res://Hive.tscn",
	"res://OvermindHive.tscn",
	"res://EnemyUnit.tscn",
	"res://MainMenu.tscn",
	"res://MissionDebrief.tscn",
	"res://OrbitalCarrier.tscn",
	"res://OvermindHive.tscn",
	"res://EvolutionNode.tscn",
	"res://PlanetMission.tscn",
	"res://OperatorRosterCard.tscn",
	"res://Room.tscn",
	"res://RunSummary.tscn",
	"res://SoldierCard.tscn",
	"res://SoldierUnit.tscn",
	"res://SquadSelection.tscn",
	"res://TacticalMap.tscn",
	"res://PlanetMission.tscn",
]

const RESOURCE_PATHS: Array[String] = [
	"res://Soldier_Marine1.tres",
	"res://Soldier_Marine2.tres",
	"res://Soldier_Marine3.tres",
	"res://Soldier_Marine4.tres",
]

var _lines: PackedStringArray = PackedStringArray()
var _failures: Array[String] = []


func _ready() -> void:
	_log("=== QA VALIDATION START ===")
	_validate_scripts()
	_validate_scenes()
	_validate_resources()
	_validate_order_type()
	_validate_portrait_pool()
	_validate_map_generation()
	_validate_run_state()
	_validate_run_log()
	_validate_phase_features()
	_validate_objective_templates()
	_validate_multi_squad_and_hives()
	_validate_planet_run()
	_validate_v2_features()
	_print_summary()
	_write_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


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
	if OrderType.Type.EXPLORE != 6:
		_fail("OrderType.Type.EXPLORE expected 6, got %d" % OrderType.Type.EXPLORE)
	elif OrderType.Type.OBJECTIVE != 7:
		_fail("OrderType.Type.OBJECTIVE expected 7, got %d" % OrderType.Type.OBJECTIVE)
	else:
		_log("OK  EXPLORE + OBJECTIVE enum values")


func _validate_portrait_pool() -> void:
	_log("-- Portrait pool --")
	var count: int = PortraitPool.get_portrait_count()
	_log("Portrait textures loaded: %d" % count)
	if count == 0:
		_log("WARN no portrait PNGs found (UI uses class-color fallback)")
	else:
		var portraits: Array[Texture2D] = PortraitPool.get_random_portraits(4)
		if portraits.size() < mini(4, count):
			_fail("PortraitPool returned %d portraits for count=4" % portraits.size())
		else:
			_log("OK  random portrait assignment")


func _validate_map_generation() -> void:
	_log("-- Map generation --")
	var map_data = ProceduralMapGenerator.generate(12345, {"op_index": 2, "objective_template": "scavenge"})
	if map_data == null:
		_fail("ProceduralMapGenerator.generate returned null")
		return
	var rooms: Array = map_data.get_room_dicts()
	if rooms.is_empty():
		_fail("Generated map has no rooms")
	else:
		_log("OK  generated %d rooms (seed 12345, op 2 scavenge)" % rooms.size())
	if map_data.op_index != 2:
		_fail("Expected op_index 2 on map data")
	_validate_cross_room_pathfinding(map_data)


func _validate_cross_room_pathfinding(map_data) -> void:
	_log("-- Cross-room pathfinding --")
	var graph = map_data.path_graph
	if graph.corridor_rects.is_empty():
		_fail("Path graph corridor_rects is empty after map generation")
		return
	var rooms: Array = map_data.get_room_dicts()
	if rooms.size() < 2:
		_log("SKIP cross-room check (single room)")
		return
	var room_a: Dictionary = rooms[0]
	var room_b: Dictionary = rooms[1]
	var from_pos: Vector2 = room_a["pos"]
	var to_pos: Vector2 = room_b["pos"]
	var path: PackedVector2Array = graph.find_path(from_pos, to_pos)
	if path.is_empty():
		_fail("find_path returned empty route between first two rooms")
		return
	for rect in graph.corridor_rects:
		var mid: Vector2 = rect.get_center()
		if not graph.is_in_corridor(mid):
			_fail("Corridor midpoint not walkable: %s" % str(mid))
			return
	_log("OK  corridor walkability and cross-room path (%d waypoints)" % path.size())


func _validate_run_state() -> void:
	_log("-- RunState flow --")
	RunState.end_run()
	var squad: Array[SoldierResource] = []
	var marine: SoldierResource = load("res://Soldier_Marine1.tres")
	if marine:
		squad.append(marine.duplicate_for_deploy())
	RunState.start_run(squad, 999, false)
	if not RunState.run_active:
		_fail("RunState.start_run did not activate run")
	if RunState.run_seed != 999:
		_fail("RunState seed override failed")
	if RunState.next_op_seed() != 999 + 7919:
		_fail("RunState.next_op_seed mismatch")
	marine.current_hp = 40
	marine.is_injured = true
	RunState.advance_after_success()
	if RunState.op_index != 2:
		_fail("RunState.advance_after_success did not increment op_index")
	if not SaveManager.is_class_unlocked(SoldierResource.MarineClass.ASSAULT):
		_fail("Default Assault class should be unlocked")
	RunState.end_run()
	_log("OK  RunState transitions")


func _validate_run_log() -> void:
	_log("-- RunLog autoload --")
	if not RunLog.has_method("info"):
		_fail("RunLog missing info() API")
		return
	if RunLog.get_session_path().is_empty():
		_fail("RunLog session path is empty")
		return
	RunLog.info("QA RunLog smoke test")
	if not FileAccess.file_exists(RunLog.get_session_path()):
		_fail("RunLog workspace log missing: %s" % RunLog.get_session_path())
		return
	_log("OK  RunLog session=%s" % RunLog.get_session_path())


func _validate_phase_features() -> void:
	_log("-- Phase A-E / F smoke tests --")
	if "hold_purge" not in RunState.OBJECTIVE_TEMPLATES:
		_fail("hold_purge missing from OBJECTIVE_TEMPLATES")
	elif "black_site" not in RunState.OBJECTIVE_TEMPLATES:
		_fail("black_site missing from OBJECTIVE_TEMPLATES")
	elif "vip_recovery" not in RunState.OBJECTIVE_TEMPLATES:
		_fail("vip_recovery missing from OBJECTIVE_TEMPLATES")
	else:
		_log("OK  objective templates (%d)" % RunState.OBJECTIVE_TEMPLATES.size())
	var hold_map = ProceduralMapGenerator.generate(777, {"op_index": 2, "objective_template": "hold_purge"})
	if hold_map == null or hold_map.hold_room_id.is_empty():
		_fail("hold_purge map missing hold_room_id")
	else:
		_log("OK  hold_purge hold_room_id=%s" % hold_map.hold_room_id)
	var augment_script: Script = load("res://RunAugment.gd")
	if augment_script == null:
		_fail("RunAugment script failed to load")
	else:
		_log("OK  run augments script")
	var themed_map = ProceduralMapGenerator.generate(888, {"op_index": 1, "objective_template": "standard"})
	if themed_map == null or themed_map.facility_theme.is_empty():
		_fail("Generated map missing facility_theme")
	elif themed_map.facility_theme not in MapVisuals.FACILITY_THEMES:
		_fail("Unknown facility theme: %s" % themed_map.facility_theme)
	else:
		_log("OK  facility theme %s" % themed_map.facility_theme)
	var finale_map = ProceduralMapGenerator.generate(999, {"op_index": 4, "objective_template": "standard"})
	if finale_map == null or not finale_map.is_handcrafted:
		_fail("Op 4 should use handcrafted finale layout")
	elif finale_map.get_room_dicts().size() < 5:
		_fail("Finale map too small")
	else:
		_log("OK  handcrafted finale (%d rooms)" % finale_map.get_room_dicts().size())
	var share_code := SaveManager.get_daily_share_code(12345)
	if not share_code.begins_with("EOY-"):
		_fail("Daily share code format unexpected: %s" % share_code)
	else:
		_log("OK  daily share code %s" % share_code)


func _validate_objective_templates() -> void:
	_log("-- Objective template smoke tests --")
	const RoomScene := preload("res://Room.tscn")
	const TEMPLATE_SEEDS: Dictionary = {
		"standard": 4101,
		"silent_extract": 4102,
		"scavenge": 4103,
		"hold_purge": 4104,
		"black_site": 4105,
		"vip_recovery": 4106,
		"hive_purge": 4107,
	}
	for template in RunState.OBJECTIVE_TEMPLATES:
		var seed_value: int = int(TEMPLATE_SEEDS.get(template, 9000 + template.hash()))
		var map_data = ProceduralMapGenerator.generate(seed_value, {
			"op_index": 2,
			"objective_template": template,
			"map_tier": "medium",
		})
		if map_data == null:
			_fail("%s map generation returned null" % template)
			continue
		if map_data.objective_template != template:
			_fail("%s map objective_template mismatch" % template)
			continue
		match template:
			"silent_extract":
				if map_data.evac_reveal_after_searches < 1:
					_fail("silent_extract missing evac search gate")
			"scavenge":
				if map_data.bonus_credits_room_id.is_empty():
					_fail("scavenge missing bonus room id")
			"hold_purge":
				if map_data.hold_room_id.is_empty() or map_data.hold_duration_seconds <= 0.0:
					_fail("hold_purge missing hold room or duration")
			"black_site":
				if map_data.intel_terminal_room_ids.is_empty():
					_fail("black_site missing intel terminal rooms")
			"vip_recovery":
				if map_data.vip_room_id.is_empty():
					_fail("vip_recovery missing vip room")
			"hive_purge":
				if map_data.hive_room_ids.is_empty():
					_fail("hive_purge missing hive rooms")
		var rooms: Array = map_data.get_room_dicts()
		if rooms.is_empty():
			_fail("%s generated zero rooms" % template)
			continue
		var deploy_rooms: Array = []
		for room_data in rooms:
			if room_data.get("spawn_eligible", false):
				deploy_rooms.append(room_data)
		var test_rooms: Array = deploy_rooms if not deploy_rooms.is_empty() else rooms
		for room_data in test_rooms:
			var room: Node = RoomScene.instantiate()
			room.position = room_data["pos"]
			room.configure(room_data["size"], Color.WHITE)
			if not room.formation_fits(RunState.OPERATORS_PER_SQUAD):
				_fail("%s formation does not fit deploy room %s" % [template, str(room_data["size"])])
			room.free()
		_log("OK  %s rooms=%d deploy_rooms=%d" % [template, rooms.size(), test_rooms.size()])


func _validate_multi_squad_and_hives() -> void:
	_log("-- Multi-squad / hive smoke tests --")
	if RunState.ROSTER_SIZE != 12:
		_fail("RunState.ROSTER_SIZE expected 12, got %d" % RunState.ROSTER_SIZE)
	elif RunState.SQUAD_COUNT != 3:
		_fail("RunState.SQUAD_COUNT expected 3")
	else:
		_log("OK  roster constants 3x4=12")
	var roster: Array[SoldierResource] = RunState.generate_full_roster()
	if roster.size() != 12:
		_fail("generate_full_roster returned %d operators" % roster.size())
	else:
		_log("OK  generate_full_roster (12 operators)")
	var task_board: MissionTaskBoardLib = MissionTaskBoardLib.new()
	task_board.reset()
	if task_board == null:
		_fail("MissionTaskBoard failed to construct")
	else:
		_log("OK  MissionTaskBoard")
	var squads: SquadsManagerLib = SquadsManagerLib.new()
	squads.reset()
	if squads.get_doctrine("alpha") == OrderType.Type.CLEAR:
		_log("OK  SquadsManager defaults")
	else:
		_fail("SquadsManager doctrine default unexpected")
	var medium_map = ProceduralMapGenerator.generate(4242, {
		"op_index": 2,
		"objective_template": "standard",
		"map_tier": "medium",
	})
	if medium_map == null:
		_fail("medium map generation failed")
	else:
		var room_n: int = medium_map.get_room_dicts().size()
		if room_n < 14 or room_n > 19:
			_fail("medium map room count out of range: %d" % room_n)
		else:
			_log("OK  medium map %d rooms" % room_n)
	var large_map = ProceduralMapGenerator.generate(5252, {
		"op_index": 3,
		"objective_template": "hive_purge",
		"map_tier": "large",
	})
	if large_map == null:
		_fail("large hive_purge map failed")
	elif large_map.hive_room_ids.is_empty():
		_fail("hive_purge large map missing hive rooms")
	else:
		_log("OK  hive_purge large map hives=%d rooms=%d" % [
			large_map.hive_room_ids.size(),
			large_map.get_room_dicts().size(),
		])
	if "hive_purge" not in RunState.OBJECTIVE_TEMPLATES:
		_fail("hive_purge missing from OBJECTIVE_TEMPLATES")
	else:
		_log("OK  hive_purge objective template")
	var hive_scene: PackedScene = load("res://Hive.tscn")
	if hive_scene == null:
		_fail("Hive.tscn failed to load")
	else:
		var hive_node = hive_scene.instantiate()
		if hive_node == null:
			_fail("Hive scene failed to instantiate")
		elif not hive_node.has_method("take_damage"):
			_fail("Hive missing take_damage")
			hive_node.free()
		else:
			if not MissionStateLib.is_attackable_target(hive_node):
				_fail("Living hive should be an attackable target")
			hive_node.max_health = 120
			hive_node.current_health = 120
			hive_node.take_damage(120, null)
			if not hive_node.is_destroyed:
				_fail("Hive should be destroyed after lethal damage")
			elif MissionStateLib.is_attackable_target(hive_node):
				_fail("Destroyed hive should not be attackable")
			else:
				_log("OK  Hive combat destruction")
			hive_node.free()
		const SoldierScene := preload("res://SoldierUnit.tscn")
		var soldier = SoldierScene.instantiate()
		if soldier == null:
			_fail("SoldierUnit scene failed to instantiate for squad_status smoke test")
		else:
			add_child(soldier)
			var live_hive = hive_scene.instantiate()
			add_child(live_hive)
			soldier.current_target = live_hive
			var squads_for_status: SquadsManagerLib = SquadsManagerLib.new()
			squads_for_status.reset()
			squads_for_status.register_unit(soldier, "alpha")
			var status: String = squads_for_status.squad_status("alpha")
			if status != "ENGAGED":
				_fail("squad_status with hive target expected ENGAGED, got %s" % status)
			else:
				_log("OK  squad_status hive engagement")
			live_hive.free()
			soldier.free()
	var doctrine: OrderType.Type = SquadsManagerLib.doctrine_for_objective("silent_extract")
	if doctrine != OrderType.Type.EXPLORE:
		_fail("silent_extract doctrine should be EXPLORE")
	else:
		_log("OK  objective doctrine mapping")


func _validate_planet_run() -> void:
	_log("-- Planet run smoke tests --")
	const PlanetMapDataScript := preload("res://PlanetMapData.gd")
	var planet_map = ProceduralMapGenerator.generate_planet(13579, RunState.get_planet_config())
	if planet_map == null:
		_fail("generate_planet returned null")
		return
	if not planet_map is PlanetMapDataScript:
		_fail("generate_planet should return PlanetMapData")
	var room_count: int = planet_map.get_room_dicts().size()
	if room_count < 18 or room_count > 24:
		_fail("planet map room count out of range: %d" % room_count)
	elif planet_map.map_size.x < 1400.0 or planet_map.map_size.y < 1400.0:
		_fail("planet map size too small: %s" % str(planet_map.map_size))
	elif planet_map.overmind_room_id.is_empty():
		_fail("planet map missing overmind room")
	elif planet_map.regular_hive_room_ids.is_empty():
		_fail("planet map missing regular hive rooms")
	elif planet_map.regular_hive_room_ids.size() > 2:
		_fail("planet map hive count out of range: %d (expected 1-2)" % planet_map.regular_hive_room_ids.size())
	else:
		_log(
			"OK  planet map rooms=%d size=%s hives=%d overmind=%s"
			% [
				room_count,
				str(planet_map.map_size),
				planet_map.regular_hive_room_ids.size(),
				planet_map.overmind_room_id,
			]
		)
	var quiet_map = ProceduralMapGenerator.generate_planet(99999, {
		"planet_room_min": 12,
		"planet_room_max": 16,
		"mutators": ["quiet_deck"],
	})
	if quiet_map and quiet_map.regular_hive_room_ids.size() != 0:
		_fail("quiet_deck mutator should remove regular hives")
	elif quiet_map:
		_log("OK  quiet_deck mutator (0 regular hives)")
	_validate_mission_unpaused_start()
	var squad: Array[SoldierResource] = RunState.generate_full_roster()
	RunState.start_planet_run(squad, 24680, false)
	if not RunState.planet_mode:
		_fail("start_planet_run did not enable planet_mode")
	elif RunState.planet_phase != RunState.PlanetPhase.DEPLOY:
		_fail("start_planet_run should begin in DEPLOY phase")
	elif RunState.legacy_biomass != 0:
		_fail("legacy_biomass alias should start at 0")
	else:
		_log("OK  start_planet_run defaults")
	RunState.begin_planet_purge()
	if RunState.planet_phase != RunState.PlanetPhase.PURGE:
		_fail("begin_planet_purge failed")
	RunState.regular_hives_total = 4
	for i in range(4):
		RunState.on_regular_hive_destroyed()
	if RunState.planet_phase != RunState.PlanetPhase.QUEEN:
		_fail("planet phase should reach QUEEN after all hives destroyed")
	RunState.on_overmind_destroyed()
	if RunState.planet_phase != RunState.PlanetPhase.EXTRACT:
		_fail("planet phase should reach EXTRACT after overmind destroyed")
	elif not RunState.extract_window_open:
		_fail("evac should unlock after overmind destroyed")
	else:
		_log("OK  planet phase enum transitions")
	var phases: Array = RunState.PlanetPhase.keys()
	if phases.size() != 5:
		_fail("PlanetPhase enum expected 5 values, got %d" % phases.size())
	else:
		_log("OK  PlanetPhase enum (%s)" % ", ".join(phases))
	RunState.end_run()
	_log("OK  planet run smoke tests")


func _validate_v2_features() -> void:
	_log("-- V2 feature smoke tests --")
	var pressure := HivePressure.new()
	pressure.reset()
	pressure.configure("colony", [])
	var profile := pressure.profile
	if int(profile.get("spawn_cap", 0)) < 1:
		_fail("HivePressure colony baseline missing spawn_cap")
	else:
		_log("OK  HivePressure colony baseline")
	pressure.configure("colony", ["accelerated_swarm"])
	if float(pressure.profile.get("base_spawn_interval", 99.0)) >= float(profile.get("base_spawn_interval", 99.0)):
		_fail("accelerated_swarm should reduce hive interval")
	else:
		_log("OK  accelerated_swarm mutator pressure")
	if CommsTemplates.nests_halfway(1, 2).is_empty():
		_fail("CommsTemplates returned empty string")
	else:
		_log("OK  CommsTemplates military tone")
	var planet_map: RefCounted = ProceduralMapGenerator.generate_planet(99992, RunState.get_planet_config())
	var evo_count: int = planet_map.evolution_node_room_ids.size()
	if evo_count < 2 or evo_count > 3:
		_fail("expected 2-3 evolution nodes, got %d" % evo_count)
	else:
		_log("OK  evolution node count 2-3")
	MapVisuals._ensure_colony_tiles()
	if MapVisuals.get_colony_tile("floor") == null:
		_fail("colony placeholder floor tile missing")
	else:
		_log("OK  colony placeholder tiles")
	var stim := EvolutionUpgrade.get_by_id("stim_injector")
	var predator := EvolutionUpgrade.get_by_id("predator_instinct")
	if stim == null or predator == null:
		_fail("predator instinct synergy chain missing from EvolutionUpgrade catalog")
	elif predator.synergy_requires.is_empty():
		_fail("predator_instinct should require synergy tag")
	else:
		_log("OK  predator instinct synergy chain")
	_log("OK  V2 feature smoke tests")


func _validate_mission_unpaused_start() -> void:
	_log("-- Mission unpaused start --")
	var probe := Node.new()
	probe.add_to_group("tactical_map")
	add_child(probe)
	probe.set("game_active", true)
	probe.set("mission_complete", false)
	probe.set("spawn_selection_active", true)
	if not MissionStateLib.is_unit_actions_frozen(probe):
		_fail("deploy selection should freeze unit actions")
	probe.set("spawn_selection_active", false)
	if MissionStateLib.is_unit_actions_frozen(probe):
		_fail("active unpaused mission should not freeze unit actions")
	else:
		_log("OK  MissionState deploy-only freeze")
	probe.queue_free()


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
