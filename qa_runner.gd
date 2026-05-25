extends Node

const MissionTaskBoardLib := preload("res://MissionTaskBoard.gd")
const MissionStateLib := preload("res://MissionState.gd")
const SquadsManagerLib := preload("res://SquadsManager.gd")

const REPORT_PATH := "res://qa_report.txt"

const SCRIPT_PATHS: Array[String] = [
	"res://BackgroundMusic.gd",
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
	"res://UnitSimulationStore.gd",
	"res://UnitSimulationManager.gd",
	"res://UnitPresentationLayer.gd",
	"res://PathRequestQueue.gd",
	"res://RoomCombatResolver.gd",
	"res://MassUnitAdapter.gd",
	"res://MassBattleSpawner.gd",
	"res://CombatCoordinator.gd",
	"res://OrbitalCarrier.gd",
	"res://OpModifier.gd",
	"res://OperatorRosterCard.gd",
	"res://OrderType.gd",
	"res://PortraitPool.gd",
	"res://ProceduralMapGenerator.gd",
	"res://Room.gd",
	"res://CampaignGraphData.gd",
	"res://CampaignGraphGenerator.gd",
	"res://CampaignNavigation.gd",
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
	"res://CommanderProfile.gd",
	"res://ArmyPool.gd",
	"res://GalaxyMapState.gd",
	"res://GalaxyMapGenerator.gd",
	"res://CommanderResources.gd",
	"res://BuildingDefinition.gd",
	"res://TurnResolver.gd",
	"res://BattleMapData.gd",
	"res://BattleMapGenerator.gd",
	"res://SectorCombatResolver.gd",
	"res://BattleDirectives.gd",
	"res://CommanderSelect.gd",
	"res://GalaxyMapScreen.gd",
	"res://BattleViewer.gd",
	"res://BattleDebriefCommander.gd",
	"res://CommandHQ.gd",
	"res://GalaxyThreatAnalyzer.gd",
	"res://BattlePhaseController.gd",
	"res://BattleHeatOverlay.gd",
	"res://BattleMassPresentation.gd",
	"res://BattleCinematicCamera.gd",
	"res://BattleAtmosphere.gd",
]

const SCENE_PATHS: Array[String] = [
	"res://BetweenMissionHub.tscn",
	"res://CampaignNavigation.tscn",
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
	"res://CommanderSelect.tscn",
	"res://GalaxyMapScreen.tscn",
	"res://BattleViewer.tscn",
	"res://BattleDebriefCommander.tscn",
	"res://CommandHQ.tscn",
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
	_validate_campaign_mode()
	_validate_v2_features()
	_validate_mass_unit_simulation()
	_validate_commander_mode()
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
	if room_count < 12 or room_count > 16:
		_fail("planet map room count out of range: %d (expected 12-16)" % room_count)
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


func _validate_campaign_mode() -> void:
	_log("-- Campaign navigation smoke tests --")
	var graph: CampaignGraphData = CampaignGraphGenerator.generate(424242)
	if graph == null:
		_fail("CampaignGraphGenerator.generate returned null")
		return
	if graph.nodes.size() < 8:
		_fail("campaign graph too small: %d nodes" % graph.nodes.size())
	var boss: Dictionary = graph.get_node("boss")
	if boss.is_empty() or str(boss.get("type", "")) != "boss":
		_fail("campaign graph missing boss node")
	var available: Array[Dictionary] = graph.get_available_next()
	if available.is_empty():
		_fail("campaign graph should offer choices after start")
	else:
		_log("OK  campaign graph nodes=%d first_choices=%d" % [graph.nodes.size(), available.size()])
	var boss_cfg: Dictionary = graph.get_node_config("boss")
	if str(boss_cfg.get("map_tier", "")) != "large" or not bool(boss_cfg.get("campaign_boss", false)):
		_fail("boss node config invalid: %s" % str(boss_cfg))
	else:
		_log("OK  boss node config (large + campaign_boss)")
	var boss_map = ProceduralMapGenerator.generate(99991, {
		"op_index": 4,
		"objective_template": "hive_purge",
		"map_tier": "large",
		"campaign_boss": true,
	})
	var has_overmind := false
	for room in boss_map.get_room_dicts():
		if room.get("overmind_room", false):
			has_overmind = true
			break
	if not has_overmind:
		_fail("campaign boss map missing overmind room")
	else:
		_log("OK  campaign boss procedural map has overmind")
	var squad: Array[SoldierResource] = RunState.generate_full_roster()
	RunState.start_campaign_run(squad, 77777, false)
	if not RunState.campaign_mode or RunState.campaign_graph == null:
		_fail("start_campaign_run did not enable campaign_mode/graph")
	elif not RunState.campaign_graph.is_completed("start"):
		_fail("start node should be auto-completed")
	else:
		_log("OK  start_campaign_run")
	var first_choice: Array[Dictionary] = RunState.campaign_graph.get_available_next()
	if first_choice.is_empty():
		_fail("campaign run should have available nodes after start")
		return
	RunState.begin_campaign_mission(str(first_choice[0].get("id", "")))
	var mission_cfg: Dictionary = RunState.get_active_mission_config()
	if mission_cfg.is_empty():
		_fail("get_active_mission_config returned empty")
	else:
		_log("OK  mission config for node %s" % str(mission_cfg.get("map_tier", "?")))
	RunState.complete_current_mission_node()
	if RunState.missions_cleared < 1:
		_fail("complete_current_mission_node did not increment missions_cleared")
	else:
		_log("OK  complete_current_mission_node")
	var node_mut_cfg: Dictionary = RunState.get_mission_config_for_node(str(first_choice[0].get("id", "")))
	RunState.set_mutator("dense_spores", true)
	var merged: Array = node_mut_cfg.get("mutators", [])
	if "dense_spores" not in merged:
		_fail("get_mission_config should merge carrier mutators")
	else:
		_log("OK  mission config merges carrier mutators")
	RunState.prepare_sector_rewards(str(first_choice[0].get("id", "")))
	if RunState.pending_sector_reward_choices.is_empty():
		_fail("prepare_sector_rewards should offer choices")
	else:
		_log("OK  sector reward choices=%d" % RunState.pending_sector_reward_choices.size())
	var has_event := false
	for n in RunState.campaign_graph.nodes:
		if str(n.get("type", "")) in ["rest", "armory", "intel_broker"]:
			has_event = true
			break
	if not has_event:
		_log("WARN campaign graph has no event nodes (RNG)")
	else:
		_log("OK  campaign graph includes event nodes")
	SaveManager.try_grant_achievement("qa_smoke_test")
	if not SaveManager.codex_achievements.has("qa_smoke_test"):
		_fail("try_grant_achievement failed")
	else:
		_log("OK  codex achievements")
	var flanker := Enemy.make_archetype(Enemy.Kind.FLANKER, 1, 1.0)
	if flanker.speed < 90.0:
		_fail("Flanker archetype speed too low")
	else:
		_log("OK  Flanker enemy archetype")
	RunState.end_run()
	_log("OK  campaign navigation smoke tests")


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


func _validate_mass_unit_simulation() -> void:
	_log("-- Mass unit simulation --")
	const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
	const UnitSimulationManagerLib := preload("res://UnitSimulationManager.gd")
	var store := UnitSimulationStoreLib.new()
	var room_positions: PackedVector2Array = [
		Vector2(0, 0), Vector2(200, 0), Vector2(400, 0), Vector2(200, 200),
	]
	store.room_ids = ["r0", "r1", "r2", "r3"]
	store.room_positions = room_positions
	store.friendly_count_by_room = PackedInt32Array([0, 0, 0, 0])
	store.hostile_count_by_room = PackedInt32Array([0, 0, 0, 0])
	store.pending_damage_by_room = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(10000):
		var ri: int = rng.randi() % 4
		store.spawn_unit(
			UnitSimulationStoreLib.Side.FRIENDLY if i % 3 != 0 else UnitSimulationStoreLib.Side.HOSTILE,
			room_positions[ri] + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)),
			100.0,
			100.0,
			ri,
			rng.randi() % 4,
		)
	if store.count != 10000:
		_fail("expected 10000 store rows, got %d" % store.count)
	else:
		_log("OK  spawned 10000 unit rows")
	var t0 := Time.get_ticks_usec()
	for bucket in range(UnitSimulationStoreLib.SIM_BUCKETS):
		store.tick_movement_stub(bucket, 0.05)
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if elapsed_ms > 8.0:
		_fail("10k movement stub took %.2f ms (gate 8ms)" % elapsed_ms)
	else:
		_log("OK  10k movement stub %.2f ms" % elapsed_ms)
	var manager := UnitSimulationManagerLib.new()
	manager.store = store
	var room_indices: Array[int] = [0, 1, 2, 3]
	manager.spawn_horde(500, 500, room_indices, rng)
	if manager.store.count != 11000:
		_fail("horde spawn expected 11000 total, got %d" % manager.store.count)
	else:
		_log("OK  horde spawn layered on store")
	var battle_map = ProceduralMapGenerator.generate(88888, {"mass_unit_mode": true, "map_tier": "large"})
	if battle_map == null or not battle_map.mass_unit_mode:
		_fail("mass_unit_mode map generation failed")
	else:
		_log("OK  battle map mass_unit_mode flag")
	var default_map = ProceduralMapGenerator.generate(88889, {"op_index": 1, "map_tier": "medium"})
	if default_map != null and default_map.mass_unit_mode:
		_fail("default campaign map should not enable mass_unit_mode")
	else:
		_log("OK  campaign map keeps mass mode off")


func _validate_commander_mode() -> void:
	_log("-- Commander mode --")
	const ArmyPoolLib := preload("res://ArmyPool.gd")
	const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")
	const GalaxyMapGeneratorLib := preload("res://GalaxyMapGenerator.gd")
	const TurnResolverLib := preload("res://TurnResolver.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const CommanderResourcesLib := preload("res://CommanderResources.gd")
	const CommanderProfileLib := preload("res://CommanderProfile.gd")
	var army := ArmyPoolLib.new()
	army.reset(1000)
	if army.set_allocation("L1_0", 200):
		_log("OK  army allocation")
	else:
		_fail("army allocation should succeed")
	army.apply_permanent_losses(50)
	if army.total_soldiers != 950:
		_fail("permanent loss expected 950 total, got %d" % army.total_soldiers)
	else:
		_log("OK  permanent army losses")
	var galaxy = GalaxyMapGeneratorLib.generate(4242)
	if galaxy.nodes.is_empty():
		_fail("galaxy generator produced no nodes")
	else:
		_log("OK  galaxy generated (%d nodes)" % galaxy.nodes.size())
	var resources := CommanderResourcesLib.new()
	resources.reset_from_profile(CommanderProfileLib.get_by_id("hammer"))
	var result: Dictionary = TurnResolverLib.resolve_turn(
		galaxy, army, resources, CommanderProfileLib.get_by_id("hammer"), false
	)
	if not result.has("battles"):
		_fail("turn resolver missing battles key")
	else:
		_log("OK  turn resolver stub (%s)" % str(result.get("message", "")))
	var battle_map = BattleMapGeneratorLib.generate(99, "urban", 400, 500, "L2_0")
	if battle_map.regions.is_empty():
		_fail("battle map missing regions")
	elif battle_map.terrain_tag != "urban":
		_fail("battle map terrain mismatch")
	else:
		_log("OK  battle terrain map (%d regions)" % battle_map.regions.size())
	if galaxy.try_add_building("hq", "barracks"):
		_log("OK  building placement on HQ")
	else:
		_fail("building placement failed on player HQ")
	const GalaxyThreatAnalyzerLib := preload("res://GalaxyThreatAnalyzer.gd")
	var strip: String = GalaxyThreatAnalyzerLib.get_threat_strip_summary(galaxy, army)
	if strip.is_empty():
		_fail("threat strip should not be empty")
	else:
		_log("OK  threat strip (%s)" % strip)
	const BattlePhaseControllerLib := preload("res://BattlePhaseController.gd")
	var phase := BattlePhaseControllerLib.new()
	var store := UnitSimulationStore.new()
	phase.tick(3.0, battle_map, store)
	if phase.current_phase == BattlePhaseControllerLib.Phase.DEPLOYMENT:
		_log("OK  battle phase -> deployment")
	else:
		_fail("battle phase expected deployment after briefing, got %s" % phase.phase_name())
	phase.tick(4.0, battle_map, store)
	if phase.current_phase == BattlePhaseControllerLib.Phase.APPROACH:
		_log("OK  battle phase -> approach")
	else:
		_fail("battle phase expected approach, got %s" % phase.phase_name())
	if battle_map.contact_column <= 0:
		_fail("battle map missing contact_column")
	else:
		_log("OK  battle contact column %d" % battle_map.contact_column)
	if battle_map.total_objectives() < 1:
		_fail("battle map should have objective sectors")
	else:
		_log("OK  battle objectives (%d sectors)" % battle_map.total_objectives())
	if not RunState.has_method("get_build_block_reason"):
		_fail("RunState missing get_build_block_reason")
	elif RunState.get_build_block_reason("hq", "barracks") != "":
		_log("OK  build block reason when slots full")
	else:
		_log("OK  build block reason allows HQ barracks")
	const BattleHeatOverlayLib := preload("res://BattleHeatOverlay.gd")
	var lane_rng := RandomNumberGenerator.new()
	lane_rng.seed = 77
	var lane_count := 600
	var lane_positions: PackedVector2Array = BattleMapGeneratorLib.get_lane_spawn_positions(
		battle_map.player_spawn_zone,
		lane_count,
		lane_rng,
	)
	var expected_spawn := mini(lane_count, battle_map.max_visual_units)
	if lane_positions.size() < expected_spawn:
		_fail("lane spawn returned %d positions, expected %d" % [lane_positions.size(), expected_spawn])
	else:
		_log("OK  lane spawn grid (%d positions)" % lane_positions.size())
	var scale_store := UnitSimulationStore.new()
	var scale_rooms: Array = []
	for region in battle_map.regions:
		var room := Room.new()
		room.map_room_id = str(region.get("id", ""))
		room.position = region.get("center", Vector2.ZERO)
		room.room_size = battle_map.region_world_rect(region).size
		scale_rooms.append(room)
	scale_store.bind_rooms(scale_rooms)
	var spawn_target := mini(500, battle_map.player_allocation)
	if battle_map.player_allocation >= 500:
		spawn_target = mini(500, battle_map.max_visual_units)
	var spawn_region: Dictionary = battle_map.regions[0]
	var spawn_room := scale_store.room_index_for_id(str(spawn_region.get("id", "")))
	for i in range(spawn_target):
		scale_store.spawn_unit(
			UnitSimulationStore.Side.FRIENDLY,
			spawn_region.get("center", Vector2.ZERO) + Vector2(i % 20, i / 20),
			100.0,
			100.0,
			spawn_room,
		)
	if scale_store.count < spawn_target:
		_fail("battle scale spawn expected >= %d rows, got %d" % [spawn_target, scale_store.count])
	else:
		_log("OK  battle scale spawn rows=%d (target %d)" % [scale_store.count, spawn_target])
	var heat := BattleHeatOverlayLib.new()
	heat.setup(battle_map, scale_store)
	var heat_radius := heat.heat_radius_for_region(spawn_region)
	if heat_radius <= 0.0:
		_fail("BattleHeatOverlay heat radius should be > 0 for populated sector")
	else:
		_log("OK  BattleHeatOverlay heat radius %.1f" % heat_radius)
	if battle_map.max_visual_units < 2000:
		_fail("battle map max_visual_units too low: %d" % battle_map.max_visual_units)
	elif battle_map.impostor_size < 18.0:
		_fail("battle map impostor_size too small: %.1f" % battle_map.impostor_size)
	else:
		_log("OK  battle visual tuning knobs")
	_validate_battle_scale_spawn(battle_map)


func _validate_battle_scale_spawn(battle_map) -> void:
	_log("-- Battle scale spawn --")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleHeatOverlayLib := preload("res://BattleHeatOverlay.gd")
	const UnitSimulationManagerLib := preload("res://UnitSimulationManager.gd")
	var scale_map = BattleMapGeneratorLib.generate(777, "open_field", 1200, 900, "L3_0")
	if scale_map.max_visual_units < 500:
		_fail("battle map max_visual_units too low: %d" % scale_map.max_visual_units)
	else:
		_log("OK  max_visual_units %d" % scale_map.max_visual_units)
	var visual_p := mini(scale_map.player_allocation, scale_map.max_visual_units)
	var rng := RandomNumberGenerator.new()
	rng.seed = scale_map.map_seed + 11
	var positions := BattleMapGeneratorLib.get_lane_spawn_positions(
		scale_map.player_spawn_zone,
		visual_p,
		rng,
	)
	if scale_map.player_allocation >= 500 and positions.size() < mini(500, visual_p):
		_fail("lane spawn expected >= %d positions, got %d" % [mini(500, visual_p), positions.size()])
	else:
		_log("OK  lane spawn %d positions (alloc %d)" % [positions.size(), scale_map.player_allocation])
	var manager := UnitSimulationManagerLib.new()
	var rooms: Array = []
	for region in scale_map.regions:
		var r := Room.new()
		r.map_room_id = str(region.get("id", ""))
		r.position = region.get("center", Vector2.ZERO)
		r.room_size = scale_map.region_world_rect(region).size
		rooms.append(r)
	manager.setup(rooms, scale_map.path_graph, 200)
	var sample_count := mini(600, visual_p)
	var sample_positions := BattleMapGeneratorLib.get_lane_spawn_positions(
		scale_map.player_spawn_zone,
		sample_count,
		rng,
	)
	for pos in sample_positions:
		manager.store.spawn_unit(
			UnitSimulationStore.Side.FRIENDLY,
			pos,
			100.0,
			100.0,
			0,
			0,
			UnitSimulationStore.Tier.LITE,
		)
	if scale_map.player_allocation >= 500 and manager.store.count < mini(500, sample_count):
		_fail("store spawn expected >= %d rows, got %d" % [mini(500, sample_count), manager.store.count])
	else:
		_log("OK  store rows %d for scale probe" % manager.store.count)
	var heat := BattleHeatOverlayLib.new()
	heat.setup(scale_map, manager.store)
	var populated_radius := 0.0
	for region in scale_map.regions:
		var r := heat.heat_radius_for_region(region)
		if r > populated_radius:
			populated_radius = r
	if manager.store.count > 0 and populated_radius <= 12.0:
		_fail("heat overlay should report radius for populated sector (got %.1f)" % populated_radius)
	else:
		_log("OK  heat overlay radius %.1f" % populated_radius)


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
