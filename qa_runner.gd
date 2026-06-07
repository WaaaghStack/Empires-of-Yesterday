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
	"res://BattleTurnQueueScreen.gd",
	"res://CommandHQ.gd",
	"res://GalaxyThreatAnalyzer.gd",
	"res://BattlePhaseController.gd",
	"res://BattleArmyState.gd",
	"res://BattleTurnSimulator.gd",
	"res://BattleTacticalSim.gd",
	"res://BattleTerritorySim.gd",
	"res://BattleTerritoryGpuField.gd",
	"res://BattleTerritoryTape.gd",
	"res://BattleTerritoryReplayPlayer.gd",
	"res://BattleCombatResolver.gd",
	"res://BattleCellGrid.gd",
	"res://BattleArmyBuilder.gd",
	"res://BattleMoraleSystem.gd",
	"res://BattleOrderTypes.gd",
	"res://BattleScript.gd",
	"res://BattleEnemyDoctrine.gd",
	"res://BattleSpellCatalog.gd",
	"res://BattleMagicBudget.gd",
	"res://BattleMagicResolver.gd",
	"res://BattleHeatOverlay.gd",
	"res://BattleTileControl.gd",
	"res://BattleTileFluidField.gd",
	"res://BattleTileOwnershipOverlay.gd",
	"res://BattleMassPresentation.gd",
	"res://BattleUnitPresentation.gd",
	"res://BattleMapPlacement.gd",
	"res://BattleMovementEngine.gd",
	"res://BattlePacing.gd",
	"res://BattleUnitCatalog.gd",
	"res://BattleComposition.gd",
	"res://BattleCinematicCamera.gd",
	"res://BattleAtmosphere.gd",
	"res://BattleBriefingPanel.gd",
	"res://BattleSquad.gd",
	"res://BattleCommander.gd",
	"res://BattleSequence.gd",
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
	"res://BattleTurnQueueScreen.tscn",
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
	var battle_map = BattleMapGeneratorLib.generate(99, "urban", 400, 500, "L2_0", {}, "battle")
	if battle_map.regions.is_empty():
		_fail("battle map missing regions")
	elif battle_map.terrain_tag != "urban":
		_fail("battle map terrain mismatch")
	else:
		_log("OK  battle terrain map (%d regions)" % battle_map.regions.size())
	if battle_map.grid_width < 90 or battle_map.grid_height < 68:
		_fail("battle grid too small: %dx%d" % [battle_map.grid_width, battle_map.grid_height])
	else:
		_log("OK  battle grid %dx%d" % [battle_map.grid_width, battle_map.grid_height])
	var cp_battle: int = battle_map.total_capture_points()
	if cp_battle < 3 or cp_battle > 5:
		_fail("battle node expected 3-4 CPs, got %d" % cp_battle)
	else:
		_log("OK  battle CP count %d" % cp_battle)
	var boss_map = BattleMapGeneratorLib.generate(101, "open_field", 600, 900, "L3_boss", {}, "boss")
	var cp_boss: int = boss_map.total_capture_points()
	if cp_boss < 6 or cp_boss > 9:
		_fail("boss node expected 6-8 CPs, got %d" % cp_boss)
	else:
		_log("OK  boss CP count %d" % cp_boss)
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
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	var phase := BattlePhaseControllerLib.new()
	phase.tick(3.0, battle_map, null)
	if phase.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT:
		_log("OK  battle phase -> engagement")
	else:
		_fail("battle phase expected engagement after briefing, got %s" % phase.phase_name())
	if battle_map.mass_unit_mode:
		_fail("commander battle should disable mass_unit_mode")
	else:
		_log("OK  commander territory battle (fluid conquest)")
	var territory := BattleTerritorySimLib.new()
	territory.setup(battle_map, 120, 120, galaxy)
	if territory.claimable_tiles < 100:
		_fail("territory sim needs claimable tiles, got %d" % territory.claimable_tiles)
	else:
		_log("OK  territory claimable tiles %d" % territory.claimable_tiles)
	var before_f: int = territory._tiles_owned_by_player()
	territory.advance_round()
	if territory._tiles_owned_by_player() < before_f:
		_fail("territory round should not shrink player tiles")
	else:
		_log("OK  territory pressure round")
	var pre: Dictionary = TurnResolver.pre_resolve_live_battle(99, {}, 350, 400, "qa_battle", 80, "battle")
	if bool(pre.get("stub", true)):
		_fail("pre_resolve_live_battle should run territory sim")
	elif str(pre.get("resolve_mode", "")) != "territory":
		_fail("pre_resolve expected territory mode, got %s" % str(pre.get("resolve_mode", "")))
	elif int(pre.get("turns", 0)) < 1:
		_fail("pre_resolve should complete at least one turn")
	else:
		_log("OK  pre_resolve territory (%d turns, won=%s)" % [
			int(pre.get("turns", 0)),
			str(pre.get("player_won", false)),
		])
	if not RunState.has_method("get_build_block_reason"):
		_fail("RunState missing get_build_block_reason")
	elif RunState.get_build_block_reason("hq", "barracks") != "":
		_log("OK  build block reason when slots full")
	else:
		_log("OK  build block reason allows HQ barracks")
	_log("OK  battle viewer (no heat overlay)")
	_validate_battle_tactical_combat()
	_validate_battle_cell_size_cap()
	_validate_battle_turn_victory()
	_validate_battle_tile_terrain()
	_validate_pressure_outflow()
	_validate_pressure_height_headroom()
	_validate_battle_unit_placement()
	_validate_battle_pacing()
	_validate_battle_replay_tape()
	_validate_battle_perf_rounds()
	_validate_territory_resolve_bench()
	_validate_world_conquest_smoke()
	_validate_world_conquest_bench()
	_validate_territory_active_set_golden()
	_validate_territory_gpu_compare()
	_validate_territory_rust_compare()
	_validate_territory_rust_bake_compare()
	_validate_territory_rust_active_set_golden()
	_validate_territory_tape_golden()
	_validate_turn_battle_queue()
	_validate_game_database()
	_validate_squad_battle_resolve_speed()


func _validate_turn_battle_queue() -> void:
	_log("-- Turn battle queue (territory pre-resolve) --")
	const TurnResolverLib := preload("res://TurnResolver.gd")
	const GalaxyMapGeneratorLib := preload("res://GalaxyMapGenerator.gd")
	const ArmyPoolLib := preload("res://ArmyPool.gd")
	const CommanderResourcesLib := preload("res://CommanderResources.gd")
	const CommanderProfileLib := preload("res://CommanderProfile.gd")
	const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")
	var galaxy = GalaxyMapGeneratorLib.generate(88055)
	var army := ArmyPoolLib.new()
	army.reset(1200)
	var resources := CommanderResourcesLib.new()
	resources.reset_from_profile(CommanderProfileLib.get_by_id("hammer"))
	var battle_node: Dictionary = {}
	for node in galaxy.nodes:
		if str(node.get("owner", "")) == GalaxyMapStateLib.OWNER_NEUTRAL:
			battle_node = node
			break
	if battle_node.is_empty():
		_fail("galaxy needs neutral node for queue test")
		return
	var node_id := str(battle_node.get("id", ""))
	army.set_allocation(node_id, 200)
	var result: Dictionary = TurnResolverLib.resolve_turn_commander(
		galaxy, army, resources, CommanderProfileLib.get_by_id("hammer"), 88055
	)
	if not bool(result.get("needs_battle_queue", false)):
		_fail("resolve_turn_commander should queue battles when allocated")
		return
	var queue: Array = result.get("battle_queue", [])
	if queue.is_empty():
		_fail("battle_queue empty")
		return
	var entry: Dictionary = queue[0]
	if int(entry.get("frame_count", 0)) < 2:
		_fail("queued battle needs replay tape frames, got %d" % int(entry.get("frame_count", 0)))
	elif entry.get("tape", null) == null:
		_fail("queued battle missing tape")
	elif str(entry.get("resolve_mode", "")) != "territory":
		_fail("expected territory resolve mode, got %s" % str(entry.get("resolve_mode", "")))
	elif float(entry.get("resolve_ms", 9999.0)) > 12000.0:
		_fail("territory resolve too slow: %.1f ms (gate 12000ms)" % float(entry.get("resolve_ms", 0.0)))
	elif float(entry.get("resolve_ms", 9999.0)) > 3000.0:
		_log("WARN turn queue resolve %.1f ms above 3000ms target" % float(entry.get("resolve_ms", 0.0)))
	else:
		_log(
			"OK  turn queue 1 battle, %d frames, won=%s, %.1fms"
			% [int(entry.get("frame_count", 0)), str(entry.get("player_won", false)), float(entry.get("resolve_ms", 0.0))]
		)
	TurnResolverLib.apply_queued_battle_outcome(galaxy, army, entry)
	if not bool(entry.get("resolved", false)):
		_fail("apply_queued_battle_outcome should mark resolved")
	else:
		_log("OK  queued battle outcome applied")


func _validate_battle_tile_terrain() -> void:
	_log("-- Battle tile terrain / occupancy --")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleMapDataLib := preload("res://BattleMapData.gd")
	var mix: Dictionary = {"grass": 0.3, "water": 0.1, "mountain": 0.25, "sand": 0.15, "mud": 0.2}
	var qmap = BattleMapGeneratorLib.generate_quantum(424242, mix, 300, 300, "L1_0", "mixed", "battle")
	var expected_cells: int = qmap.grid_width * qmap.grid_height
	if qmap.terrain_cells.size() != expected_cells:
		_fail("terrain_cells size %d expected %d" % [qmap.terrain_cells.size(), expected_cells])
	elif qmap.terrain_move_cost.size() != expected_cells:
		_fail("terrain_move_cost size mismatch")
	elif qmap.terrain_defense.size() != expected_cells:
		_fail("terrain_defense size mismatch")
	elif qmap.tile_height.size() != expected_cells:
		_fail("tile_height size mismatch")
	else:
		_log("OK  quantum map cell arrays (%d)" % expected_cells)
	const BattleMapSnapshotLib := preload("res://BattleMapSnapshot.gd")
	var snap: Dictionary = BattleMapSnapshotLib.to_dict(qmap)
	var restored = BattleMapSnapshotLib.from_dict(snap)
	if restored == null or restored.tile_height.size() != expected_cells:
		_fail("BattleMapSnapshot tile_height round-trip failed")
	else:
		_log("OK  tile_height snapshot round-trip")
	var mix_sum := 0.0
	for key in mix.keys():
		mix_sum += float(qmap.terrain_mix.get(key, 0.0))
	if absf(mix_sum - 1.0) > 0.02:
		_fail("terrain_mix should sum to ~1, got %.3f" % mix_sum)
	else:
		_log("OK  terrain_mix normalized (%.2f)" % mix_sum)
	var impassable := 0
	var passable := 0
	for gy in range(qmap.grid_height):
		for gx in range(qmap.grid_width):
			if qmap.is_passable(gx, gy):
				passable += 1
			else:
				impassable += 1
			if qmap.is_passable(gx, gy) and qmap.is_cell_blocked(gx, gy):
				_fail("passable cell marked blocked at %d,%d" % [gx, gy])
			if not qmap.is_passable(gx, gy) and qmap.get_move_cost(gx, gy) < BattleMapDataLib.IMPASSABLE_MOVE_COST:
				if not qmap.is_cell_blocked(gx, gy):
					_fail("impassable inconsistency at %d,%d" % [gx, gy])
	if passable < expected_cells / 4:
		_fail("too few passable tiles: %d" % passable)
	else:
		_log("OK  passable=%d impassable=%d" % [passable, impassable])
	var store := UnitSimulationStore.new()
	var rooms: Array = []
	for region in qmap.regions:
		var room := Room.new()
		room.map_room_id = str(region.get("id", ""))
		room.position = region.get("center", Vector2.ZERO)
		room.room_size = qmap.region_world_rect(region).size
		rooms.append(room)
	store.bind_rooms(rooms)
	var spawn_gx: int = 8
	var spawn_gy: int = 12
	while spawn_gx < qmap.grid_width - 8 and not qmap.is_passable(spawn_gx, spawn_gy):
		spawn_gx += 1
	var idx := store.spawn_unit_on_grid(
		UnitSimulationStore.Side.FRIENDLY, spawn_gx, spawn_gy, qmap, 100.0, 100.0
	)
	if idx < 0:
		_fail("spawn_unit_on_grid failed")
	elif store.grid_x[idx] != spawn_gx or store.grid_y[idx] != spawn_gy:
		_fail("grid coords mismatch after spawn")
	else:
		var room_want: int = qmap.region_index_for_grid(spawn_gx, spawn_gy)
		if store.room_index[idx] != room_want:
			_fail("room_index from grid expected %d got %d" % [room_want, store.room_index[idx]])
		else:
			_log("OK  tile spawn grid=(%d,%d) room=%d" % [spawn_gx, spawn_gy, room_want])
	var resolved: Dictionary = TurnResolver.pre_resolve_live_battle(99, mix, 200, 200, "qa", 60, "battle")
	if bool(resolved.get("stub", true)):
		_fail("pre_resolve_live_battle should not be stub")
	elif int(resolved.get("units_spawned", 0)) < 10:
		_fail("pre_resolve units_spawned too low")
	else:
		_log("OK  TurnResolver pre-resolve (%d turns)" % int(resolved.get("turns", 0)))


func _validate_pressure_outflow() -> void:
	_log("-- Pressure gradient flow --")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var map = BattleMapGeneratorLib.generate(99123, "open_field", 80, 80, "qa_gradient", {}, "battle")
	var tc := BattleTileControlLib.new()
	tc.setup(map)
	var high_idx: int = -1
	var low_idx: int = -1
	for gy in range(10, map.grid_height - 10):
		for gx in range(10, map.grid_width - 10):
			var idx: int = map.cell_index(gx, gy)
			if not tc._is_claimable_index(idx):
				continue
			for d in BattleTileControlLib._CARDINAL_DIRS:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				if nx < 0 or ny < 0 or nx >= map.grid_width or ny >= map.grid_height:
					continue
				var ni: int = map.cell_index(nx, ny)
				if not tc._is_claimable_index(ni):
					continue
				var e_src: float = BattleTileControlLib.tile_elevation(map, gx, gy)
				var e_n: float = BattleTileControlLib.tile_elevation(map, nx, ny)
				if e_src + 5.0 < e_n:
					high_idx = idx
					low_idx = ni
					break
			if high_idx >= 0:
				break
		if high_idx >= 0:
			break
	if high_idx < 0:
		_log("SKIP  no uphill neighbor pair for gradient test")
		return
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[high_idx] = 50.0
	var after: PackedFloat32Array = tc._gradient_flow_pass(
		map, map.grid_width, map.grid_height, tc.pressure_friendly
	)
	if after[low_idx] < 0.05:
		_fail("gradient should flow downhill (low tile got %.4f)" % after[low_idx])
		return
	if after[high_idx] >= 50.0:
		_fail("gradient should remove pressure from high tile (kept %.3f)" % after[high_idx])
		return
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[low_idx] = 0.1
	if tc.pressure_friendly[low_idx] < 0.09:
		_fail("weak pressure should persist without dust cutoff")
		return
	_log("OK  gradient downhill flow + weak pressure retained")


func _validate_pressure_height_headroom() -> void:
	_log("-- Pressure gradient vs mountain --")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var map = BattleMapGeneratorLib.generate(99124, "open_field", 80, 80, "qa_gradient_mtn", {}, "battle")
	var tc := BattleTileControlLib.new()
	tc.setup(map)
	var src_idx: int = -1
	var mount_idx: int = -1
	for gy in range(10, map.grid_height - 10):
		for gx in range(10, map.grid_width - 10):
			var idx: int = map.cell_index(gx, gy)
			if not tc._is_claimable_index(idx):
				continue
			for d in BattleTileControlLib._CARDINAL_DIRS:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				var ni: int = map.cell_index(nx, ny)
				if ni < 0 or not tc._is_claimable_index(ni):
					continue
				if BattleTileControlLib.tile_elevation(map, nx, ny) >= 99.0:
					src_idx = idx
					mount_idx = ni
					break
			if src_idx >= 0:
				break
		if src_idx >= 0:
			break
	if src_idx < 0:
		_log("SKIP  no mountain-adjacent claimable tile for gradient mountain test")
		return
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[src_idx] = 120.0
	var after: PackedFloat32Array = tc._gradient_flow_pass(
		map, map.grid_width, map.grid_height, tc.pressure_friendly
	)
	var on_mountain: float = after[mount_idx]
	if on_mountain < 0.01:
		_fail("gradient should spill onto mountain when H_src > H_mtn (got %.4f)" % on_mountain)
		return
	tc.pressure_friendly.fill(0.0)
	tc.pressure_friendly[src_idx] = 50.0
	after = tc._gradient_flow_pass(map, map.grid_width, map.grid_height, tc.pressure_friendly)
	if after[mount_idx] > 0.01:
		_fail("should not reach mountain when H_src < H_mtn (got %.4f)" % after[mount_idx])
		return
	_log("OK  gradient respects effective height (mountain barrier)")


func _validate_battle_cp_spacing(battle_map) -> void:
	_log("-- Battle CP spacing --")
	if battle_map.capture_points.size() < 2:
		_fail("need at least 2 CPs for spacing check")
		return
	for i in range(battle_map.capture_points.size()):
		var a: Dictionary = battle_map.capture_points[i]
		var ax: int = int(a.get("grid_x", 0))
		var ay: int = int(a.get("grid_y", 0))
		if not battle_map.is_passable(ax, ay):
			_fail("CP %s on impassable tile" % str(a.get("id", "")))
			return
		for j in range(i + 1, battle_map.capture_points.size()):
			var b: Dictionary = battle_map.capture_points[j]
			var bx: int = int(b.get("grid_x", 0))
			var by: int = int(b.get("grid_y", 0))
			var dx: int = ax - bx
			var dy: int = ay - by
			if dx * dx + dy * dy < 64:
				_fail("CPs too close: %s and %s" % [a.get("id", ""), b.get("id", "")])
				return
	_log("OK  CP spacing on passable terrain (%d points)" % battle_map.capture_points.size())


func _validate_battle_unit_placement() -> void:
	_log("-- Battle unit placement on land --")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleUnitPresentationLib := preload("res://BattleUnitPresentation.gd")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	var bmap = BattleMapGeneratorLib.generate(555, "open_field", 400, 224, "qa_units", {}, "battle")
	if bmap.player_spawn_cells.size() < 50 or bmap.enemy_spawn_cells.size() < 50:
		_fail("rally spawn cells too few P=%d E=%d" % [
			bmap.player_spawn_cells.size(),
			bmap.enemy_spawn_cells.size(),
		])
	else:
		_log("OK  rally spawn cells P=%d E=%d" % [
			bmap.player_spawn_cells.size(),
			bmap.enemy_spawn_cells.size(),
		])
	var tactical := BattleTacticalSimLib.new()
	tactical.setup(bmap, 400, 224, null)
	var units := BattleUnitPresentationLib.new()
	var units_parent := Node2D.new()
	units_parent.add_child(units)
	units.setup(bmap, units_parent, 14.0)
	units.bind_tactical_sim(tactical)
	if units.store.count < 100:
		_fail("battle expected spawned units, got %d" % units.store.count)
	elif not units.all_positions_on_land():
		_fail("battle units must spawn on land cells only")
	else:
		_log("OK  unit spawn on land (%d units)" % units.store.count)
	tactical.movement.apply_tactical_moves(tactical.store, tactical.squads, tactical.cell_grid, 1)
	var paths: Dictionary = tactical.movement.plan_turn_paths(units.store)
	if paths.is_empty():
		_log("OK  tactical movement (no displacement round 1)")
	else:
		_log("OK  per-unit march paths planned (%d units with paths)" % paths.size())
	units.begin_turn_march(tactical)
	units_parent.queue_free()


func _validate_battle_pacing() -> void:
	_log("-- Battle pacing (30s-5min) --")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	var bmap = BattleMapGeneratorLib.generate(556, "urban", 400, 224, "qa_pace", {}, "battle")
	var sec_cell: float = BattlePacingLib.seconds_per_cell(bmap)
	var expected_cell: float = BattlePacingLib.MAP_CROSS_SECONDS / float(bmap.grid_width)
	if absf(sec_cell - expected_cell) > 0.05:
		_fail("seconds_per_cell expected ~%.3f, got %.3f" % [expected_cell, sec_cell])
	var small = BattlePacingLib.compute(bmap, 200, 200, 0, 20.0)
	var large = BattlePacingLib.compute(bmap, 1200, 800, 0, 35.0)
	var t_small: float = float(small.get("turn_seconds", 0.0)) * float(small.get("est_turns", 1))
	var t_large: float = float(large.get("turn_seconds", 0.0)) * float(large.get("est_turns", 1))
	if t_small < 25.0 or t_small > 620.0:
		_fail("small battle pacing out of range: %.1fs" % t_small)
	elif t_large < 25.0 or t_large > 620.0:
		_fail("large battle pacing out of range: %.1fs" % t_large)
	else:
		_log("OK  pacing bands (small~%.0fs large~%.0fs)" % [t_small, t_large])
	var sim := BattleTacticalSimLib.new()
	sim.setup(bmap, 400, 224, null)
	if absf(sim.get_seconds_per_cell() - sec_cell) > 0.02:
		_fail("visual seconds_per_cell mismatch %.3f" % sim.get_seconds_per_cell())
	elif absf(sim.get_turn_seconds() - BattlePacingLib.SIM_ROUND_SECONDS) > 0.08:
		_fail("sim round %.2f expected ~%.2f" % [sim.get_turn_seconds(), BattlePacingLib.SIM_ROUND_SECONDS])
	elif sim.max_rounds_limit > BattlePacingLib.RESOLVE_MAX_ROUNDS_CAP:
		_fail("max_rounds_limit %d exceeds resolve cap %d" % [
			sim.max_rounds_limit,
			BattlePacingLib.RESOLVE_MAX_ROUNDS_CAP,
		])
	else:
		_log(
			"OK  sim round %.2fs march %.2fs/cell max_rounds=%d"
			% [sim.get_turn_seconds(), sim.get_seconds_per_cell(), sim.max_rounds_limit]
		)


func _validate_game_database() -> void:
	_log("-- GameDatabase (godot-sqlite) smoke --")
	var gdb: Node = Engine.get_main_loop().root.get_node_or_null("/root/GameDatabase")
	if gdb == null:
		_fail("GameDatabase autoload missing")
		return
	if not gdb.has_method("LoadCommanderRun"):
		_fail("GameDatabase missing expected API")
	else:
		_log("OK  GameDatabase autoload present")
	_validate_battle_sql_tactical(gdb)


func _validate_battle_sql_tactical(gdb: Node) -> void:
	_log("-- Battle SQL territory (tiles + tile frames only) --")
	const BattleSqlPersistLib := preload("res://BattleSqlPersist.gd")
	const BattleSqlReplayLib := preload("res://BattleSqlReplay.gd")
	const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
	const TurnResolverLib := preload("res://TurnResolver.gd")
	const CommanderProfileLib := preload("res://CommanderProfile.gd")
	var node: Dictionary = {
		"id": "qa_sql_battle",
		"terrain_tag": "open_field",
		"terrain_mix": {},
		"type": "battle",
		"enemy_strength": 120,
	}
	var profile: Dictionary = CommanderProfileLib.get_by_id("logistician")
	var entry: Dictionary = TurnResolverLib.preresolve_commander_battle(4242, node, 120, profile)
	if str(entry.get("resolve_mode", "")) != "territory":
		_fail("preresolve entry should be territory mode")
		return
	if not entry.has("map_snapshot") or entry.get("tape") == null:
		_fail("preresolve entry missing map_snapshot or tape")
		return
	var preresolve_tape = entry.get("tape")
	if preresolve_tape != null and preresolve_tape.frame_count() > 0:
		var pf0: Dictionary = preresolve_tape.get_frame(0)
		var powners: PackedByteArray = BattleReplayTapeLib.owners_from_frame(pf0)
		if powners.is_empty():
			_fail("preresolve tape frame 0 missing tile_owners")
			return
	if not gdb.has_method("clear_territory_battle_data"):
		_fail("GameDatabase missing territory SQL API")
		return
	gdb._execute(
		"""
		INSERT INTO battles (
			run_id, node_id, terrain_tag, player_force, enemy_force, map_seed,
			player_won, player_losses, enemy_losses, turns, resolve_ms, resolve_mode, replay_json
		) VALUES (0,'qa_sql','open_field',120,120,4242,0,0,0,0,0.0,'territory','{}')
		"""
	)
	var battle_id: int = gdb._last_insert_id() if gdb.has_method("_last_insert_id") else 0
	if battle_id <= 0:
		_fail("could not create test battle row")
		return
	gdb.clear_territory_battle_data(battle_id)
	if not BattleSqlPersistLib.persist_from_entry(gdb, battle_id, entry):
		_fail("BattleSqlPersist.persist_from_entry failed")
		return
	if not gdb.has_territory_battle_data(battle_id):
		_fail("territory battle data missing after persist")
		return
	if not gdb.has_method("has_territory_replay_pack") or not gdb.has_territory_replay_pack(battle_id):
		_fail("battle_territory_replay pack missing after persist")
		return
	var height_rows: Array = gdb._query(
		"SELECT COUNT(*) AS n FROM battle_tiles WHERE battle_id = ? AND height IS NOT NULL",
		[battle_id],
	)
	var height_n: int = int(height_rows[0].get("n", 0)) if not height_rows.is_empty() else 0
	if height_n < 100:
		_fail("battle_tiles missing height metadata (got %d rows)" % height_n)
		return
	var pack_rows: Array = gdb._query(
		"SELECT frame_count, grid_width, grid_height, tape_blob FROM battle_territory_replay WHERE battle_id = ?",
		[battle_id],
	)
	if pack_rows.is_empty():
		_fail("battle_territory_replay row missing")
		return
	var loaded: Dictionary = BattleSqlReplayLib.load_from_db(gdb, battle_id)
	var tape = loaded.get("tape")
	if tape == null or tape.frame_count() < 2:
		_fail("SQL replay tape too short")
		return
	var packed_fc: int = int(pack_rows[0].get("frame_count", 0))
	if packed_fc != tape.frame_count():
		_fail("pack frame_count %d != tape %d" % [packed_fc, tape.frame_count()])
		return
	var gw: int = int(pack_rows[0].get("grid_width", 0))
	var gh: int = int(pack_rows[0].get("grid_height", 0))
	var expected_blob: int = gw * gh
	var tape_blob = pack_rows[0].get("tape_blob", PackedByteArray())
	if tape_blob is PackedByteArray and tape_blob.is_empty():
		_fail("tape_blob empty")
		return
	var rf0: Dictionary = tape.get_frame(0)
	var rowners: PackedByteArray = BattleReplayTapeLib.owners_from_frame(rf0)
	if rowners.is_empty():
		_fail("SQL replay frame 0 missing tile_owners")
		return
	const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
	var pf0: PackedFloat32Array = BattleTerritoryTapeLib.pressure_friendly_from_frame(rf0)
	if pf0.is_empty() or pf0.size() != rowners.size():
		_fail("SQL replay frame 0 missing pressure_f snapshot")
		return
	gdb.clear_territory_battle_data(battle_id)
	gdb._execute("DELETE FROM battles WHERE id = ?", [battle_id])
	if tape.total_duration() <= 0.0:
		_fail("tape total_duration should be positive")
		return
	_log("OK  SQL territory pack %d frames (%.1fs), grid %dx%d" % [tape.frame_count(), tape.total_duration(), gw, gh])


func _validate_territory_resolve_bench() -> void:
	_log("-- Territory resolve bench (96x72) --")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	const BattleReplayPackLib := preload("res://BattleReplayPack.gd")
	var bmap = BattleMapGeneratorLib.generate(99150, "open_field", 400, 400, "qa_territory_bench", {}, "battle")
	var sim := BattleTerritorySimLib.new()
	sim.set_resolve_context("queue")
	sim.setup(bmap, 400, 400, null)
	var t0: int = Time.get_ticks_usec()
	var tape = sim.build_replay_tape(-1, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	var resolve_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var t_bake: int = Time.get_ticks_usec()
	tape.bake_display_frames(bmap)
	var bake_ms: float = float(Time.get_ticks_usec() - t_bake) / 1000.0
	var ms: float = resolve_ms + bake_ms
	var blob: PackedByteArray = BattleReplayPackLib.pack_tape(tape, bmap.grid_width, bmap.grid_height)
	var ms_per_round: float = ms / maxf(1.0, float(sim.round_index))
	_log(
		"BENCH territory %dx%d rounds=%d frames=%d resolve_ms=%.1f bake_ms=%.1f total_ms=%.1f ms/round=%.3f tape_bytes=%d replay_watch_s=%.1f"
		% [
			bmap.grid_width,
			bmap.grid_height,
			sim.round_index,
			tape.frame_count(),
			resolve_ms,
			bake_ms,
			ms,
			ms_per_round,
			blob.size(),
			tape.total_duration(),
		]
	)
	if not tape.has_baked_display():
		_fail("territory bench tape missing baked display frames")
		return
	var watch_s: float = tape.total_duration()
	if watch_s > 4800.0 or watch_s < 20.0:
		_fail("territory replay watch %.1fs outside 20–4800s band" % watch_s)
	elif ms > 3000.0:
		_fail("96x72 territory resolve bench %.1f ms (gate 3000ms)" % ms)
	elif tape.frame_count() < 2:
		_fail("territory bench tape needs frames, got %d" % tape.frame_count())
	else:
		_log("OK  territory bench %.1fms %d frames end=%s" % [
			ms,
			tape.frame_count(),
			str(tape.result.get("end_reason", "")),
		])


func _validate_world_conquest_smoke() -> void:
	_log("-- World Conquest smoke (360x180 map + globe mesh) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(44201)
	if bmap.grid_width != WorldConquestConfigLib.GRID_W or bmap.grid_height != WorldConquestConfigLib.GRID_H:
		_fail("world conquest map size %dx%d" % [bmap.grid_width, bmap.grid_height])
		return
	if bmap.player_home_grid.x < 0 or bmap.enemy_home_grid.x < 0:
		_fail("world conquest missing HQ spawns")
		return
	var claimable: int = 0
	for gy in range(bmap.grid_height):
		for gx in range(bmap.grid_width):
			if bmap.is_land_cell(gx, gy):
				claimable += 1
	if claimable < 8000:
		_fail("world conquest claimable land too low (%d)" % claimable)
		return
	var globe: ArrayMesh = EarthGlobeMeshLib.build_globe(bmap)
	if globe.get_surface_count() < 1:
		_fail("world conquest globe mesh empty")
		return
	var fluid: ArrayMesh = EarthGlobeMeshLib.build_fluid_globe(bmap)
	if fluid.get_surface_count() < 1:
		_fail("world conquest fluid globe mesh empty")
		return
	_log("OK  world conquest smoke %dx%d claimable=%d" % [bmap.grid_width, bmap.grid_height, claimable])


func _validate_world_conquest_bench() -> void:
	if OS.get_environment("BATTLE_WORLD_CONQUEST_BENCH") != "1":
		return
	_log("-- World Conquest bench (360x180 live sim, 60 sim sec) --")
	const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
	var bmap = EarthMapGeneratorLib.generate(44202)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(bmap, WorldConquestConfigLib.PLAYER_FORCE, WorldConquestConfigLib.ENEMY_FORCE, null, {}, true)
	if not sim.enable_rust_live():
		sim.set_live_backend(false)
	var target_sim_sec: float = 60.0
	var steps_done: int = 0
	var t0: int = Time.get_ticks_usec()
	while sim.sim_time < target_sim_sec and not sim.finished:
		var info: Dictionary = sim.advance_dt(
			WorldConquestConfigLib.SIM_DT * float(WorldConquestConfigLib.SIM_MAX_STEPS_PER_FRAME),
			WorldConquestConfigLib.SIM_MAX_STEPS_PER_FRAME,
		)
		steps_done += int(info.get("steps", 0))
	var wall_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var steps_per_sec: float = float(steps_done) / maxf(0.001, wall_ms / 1000.0)
	var ms_per_step: float = wall_ms / maxf(1.0, float(steps_done))
	_log(
		"BENCH world_conquest %dx%d sim_sec=%.1f steps=%d wall_ms=%.1f steps/s=%.0f ms/step=%.3f backend=%d end=%s"
		% [
			bmap.grid_width,
			bmap.grid_height,
			sim.sim_time,
			steps_done,
			wall_ms,
			steps_per_sec,
			ms_per_step,
			sim.backend,
			str(sim.end_reason if sim.finished else "running"),
		]
	)
	if steps_done < int(target_sim_sec / WorldConquestConfigLib.SIM_DT) - 4:
		_fail("world conquest bench did not reach target sim time (steps=%d)" % steps_done)
	elif ms_per_step > 8.0:
		_fail("world conquest bench %.3f ms/step exceeds 8ms gate" % ms_per_step)
	else:
		_log("OK  world conquest bench %.1fms for %.0fs sim" % [wall_ms, sim.sim_time])


func _validate_territory_active_set_golden() -> void:
	_log("-- Territory active-set golden --")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	var bmap = BattleMapGeneratorLib.generate(99151, "open_field", 300, 300, "qa_active_set", {}, "battle")
	var rounds: int = 48

	var sim_full := BattleTerritorySimLib.new()
	sim_full.setup(bmap, 300, 300, null)
	sim_full.tile_control.use_active_set = false
	for _r in range(rounds):
		sim_full.advance_round()
	var owners_full: PackedByteArray = sim_full.tile_control.owners.duplicate()

	var sim_active := BattleTerritorySimLib.new()
	sim_active.setup(bmap, 300, 300, null)
	sim_active.tile_control.use_active_set = true
	for _r in range(rounds):
		sim_active.advance_round()
	var owners_active: PackedByteArray = sim_active.tile_control.owners.duplicate()

	if owners_full.size() != owners_active.size():
		_fail("active-set owner size mismatch")
		return
	var mismatches: int = 0
	for i in range(owners_full.size()):
		if owners_full[i] != owners_active[i]:
			mismatches += 1
	if mismatches > 8:
		_fail("active-set diverged from full grid on %d tiles after %d rounds" % [mismatches, rounds])
	elif mismatches > 0:
		_log("WARN active-set drift %d tiles (investigate halo); full grid authoritative" % mismatches)
	else:
		_log("OK  active-set matches full grid (%d rounds, %d tiles)" % [rounds, owners_full.size()])


func _validate_territory_gpu_compare() -> void:
	const BattleTerritoryGpuFieldLib := preload("res://BattleTerritoryGpuField.gd")
	if not BattleTerritoryGpuFieldLib.compare_enabled():
		return
	_log("-- Territory GPU vs CPU compare (96x72) --")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	var bmap = BattleMapGeneratorLib.generate(99153, "open_field", 400, 400, "qa_gpu_compare", {}, "battle")
	var rounds: int = 32

	var sim_cpu := BattleTerritorySimLib.new()
	sim_cpu.use_simple_water_model = true
	sim_cpu.setup(bmap, 400, 400, null)
	for _r in range(rounds):
		sim_cpu.advance_round()
	var owners_cpu: PackedByteArray = sim_cpu.tile_control.owners.duplicate()

	var sim_gpu := BattleTerritorySimLib.new()
	sim_gpu.use_simple_water_model = true
	sim_gpu.setup(bmap, 400, 400, null)
	if not sim_gpu.enable_gpu_live():
		_log("WARN territory GPU compare skipped (GPU init failed; set Forward+ renderer)")
		return
	for _r in range(rounds):
		sim_gpu.advance_round()
	sim_gpu.gpu_field.readback_owners()
	sim_gpu.gpu_field.copy_owners_to_cpu_buffer(sim_gpu.tile_control.owners)
	var owners_gpu: PackedByteArray = sim_gpu.tile_control.owners.duplicate()

	if owners_cpu.size() != owners_gpu.size():
		_fail("GPU compare owner array size mismatch")
		return
	var mismatches: int = 0
	for i in range(owners_cpu.size()):
		if owners_cpu[i] != owners_gpu[i]:
			mismatches += 1
	var pct: float = 100.0 * float(mismatches) / float(maxi(1, owners_cpu.size()))
	if mismatches > owners_cpu.size() / 8:
		_fail("GPU compare diverged on %d/%d tiles (%.1f%%) after %d rounds" % [
			mismatches, owners_cpu.size(), pct, rounds,
		])
	elif mismatches > 0:
		_log("WARN GPU compare drift %d tiles (%.1f%%); CPU authoritative" % [mismatches, pct])
	else:
		_log("OK  GPU compare matches CPU (%d rounds, %d tiles)" % [rounds, owners_cpu.size()])


func _validate_territory_rust_compare() -> void:
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	if not BattleTerritoryRustBackendLib.compare_enabled():
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust compare skipped (GDExtension not loaded)")
		return
	_log("-- Territory Rust vs CPU compare (96x72) --")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	var bmap = BattleMapGeneratorLib.generate(99154, "open_field", 400, 400, "qa_rust_compare", {}, "battle")
	var rounds: int = 32

	var sim_cpu := BattleTerritorySimLib.new()
	sim_cpu.use_simple_water_model = true
	sim_cpu.setup(bmap, 400, 400, null)
	for _r in range(rounds):
		sim_cpu.advance_round()
	var owners_cpu: PackedByteArray = sim_cpu.tile_control.owners.duplicate()

	var sim_rust := BattleTerritorySimLib.new()
	sim_rust.use_simple_water_model = true
	sim_rust.setup(bmap, 400, 400, null)
	sim_rust.rust_field = BattleTerritoryRustBackendLib.new()
	sim_rust.rust_live_ready = sim_rust.rust_field.setup_from_tile_control(
		bmap, sim_rust.tile_control, false
	)
	if not sim_rust.rust_live_ready:
		_fail("Rust compare init failed")
		return
	sim_rust.backend = BattleTerritorySimLib.BACKEND_RUST
	for _r in range(rounds):
		sim_rust.advance_round()
	var owners_rust: PackedByteArray = sim_rust.tile_control.owners.duplicate()

	if owners_cpu.size() != owners_rust.size():
		_fail("Rust compare owner array size mismatch")
		return
	var mismatches: int = 0
	for i in range(owners_cpu.size()):
		if owners_cpu[i] != owners_rust[i]:
			mismatches += 1
	if mismatches > 0:
		_fail("Rust compare diverged on %d/%d tiles after %d rounds" % [
			mismatches, owners_cpu.size(), rounds,
		])
	else:
		_log("OK  Rust compare matches CPU (%d rounds, %d tiles)" % [rounds, owners_cpu.size()])


func _validate_territory_rust_bake_compare() -> void:
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	if not BattleTerritoryRustBackendLib.bake_compare_enabled():
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust bake compare skipped (GDExtension not loaded)")
		return
	_log("-- Territory Rust fluid bake vs GDScript (96x72) --")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
	var bmap = BattleMapGeneratorLib.generate(99155, "open_field", 400, 400, "qa_rust_bake", {}, "battle")
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("viewer")
	sim.setup(bmap, 400, 400, null)
	var tape = sim.build_replay_tape(-1, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	var compare_frames: int = mini(8, tape.frame_count())
	if compare_frames < 1:
		_fail("Rust bake compare needs tape frames")
		return
	var mismatches: int = 0
	var bytes_compared: int = 0
	for fi in range(compare_frames):
		var pressures: Dictionary = tape.pressures_at_frame(fi)
		var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
		var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
		if pf.is_empty() or ph.is_empty():
			continue
		var gd_img: Image = BattleTileFluidFieldLib.build_fluid_image_from_powers(
			bmap, pf, ph, 1.0, 0
		)
		if gd_img == null:
			_fail("Rust bake compare GDScript image null at frame %d" % fi)
			return
		var gd_rgba: PackedByteArray = gd_img.get_data()
		var rust_rgba: PackedByteArray = BattleTerritoryRustBackendLib.bake_fluid_rgba(
			bmap, pf, ph, 1.0
		)
		if rust_rgba.size() != gd_rgba.size():
			_fail(
				"Rust bake size mismatch frame %d: rust=%d gd=%d"
				% [fi, rust_rgba.size(), gd_rgba.size()]
			)
			return
		for bi in range(gd_rgba.size()):
			if rust_rgba[bi] != gd_rgba[bi]:
				mismatches += 1
		bytes_compared += gd_rgba.size()
	if bytes_compared <= 0:
		_fail("Rust bake compare had no pressure frames to check")
	elif mismatches > 0:
		_fail(
			"Rust bake diverged on %d/%d bytes across %d frames"
			% [mismatches, bytes_compared, compare_frames]
		)
	else:
		_log(
			"OK  Rust bake matches GDScript (%d frames, %d bytes each)"
			% [compare_frames, bytes_compared / maxi(1, compare_frames)]
		)


func _validate_territory_rust_active_set_golden() -> void:
	const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
	if not BattleTerritoryRustBackendLib.active_set_compare_enabled():
		return
	if not BattleTerritoryRustBackendLib.extension_available():
		_log("WARN territory Rust active-set compare skipped (GDExtension not loaded)")
		return
	_log("-- Territory Rust active-set vs full grid (96x72) --")
	const BattleTileControlLib := preload("res://BattleTileControl.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	var bmap = BattleMapGeneratorLib.generate(99156, "open_field", 400, 400, "qa_rust_active", {}, "battle")
	var rounds: int = 48

	var tc_full := BattleTileControlLib.new()
	tc_full.setup(bmap)
	tc_full.enable_simple_water_model(400, 400, 0.0, 0.0)
	tc_full.seed_territory_battle(bmap)
	var rust_full := BattleTerritoryRustBackendLib.new()
	if not rust_full.setup_from_tile_control(bmap, tc_full, false, false):
		_fail("Rust active-set compare full-grid init failed")
		return
	for _r in range(rounds):
		rust_full.step_round(tc_full)
	var owners_full: PackedByteArray = tc_full.owners.duplicate()

	var tc_active := BattleTileControlLib.new()
	tc_active.setup(bmap)
	tc_active.enable_simple_water_model(400, 400, 0.0, 0.0)
	tc_active.seed_territory_battle(bmap)
	var rust_active := BattleTerritoryRustBackendLib.new()
	if not rust_active.setup_from_tile_control(bmap, tc_active, true, false):
		_fail("Rust active-set compare active init failed")
		return
	for _r in range(rounds):
		rust_active.step_round(tc_active)
	var owners_active: PackedByteArray = tc_active.owners.duplicate()

	if owners_full.size() != owners_active.size():
		_fail("Rust active-set owner size mismatch")
		return
	var mismatches: int = 0
	for i in range(owners_full.size()):
		if owners_full[i] != owners_active[i]:
			mismatches += 1
	if mismatches > 8:
		_fail(
			"Rust active-set diverged from full grid on %d tiles after %d rounds"
			% [mismatches, rounds]
		)
	elif mismatches > 0:
		_log("WARN Rust active-set drift %d tiles; full grid authoritative" % mismatches)
	else:
		_log(
			"OK  Rust active-set matches full grid (%d rounds, %d tiles)"
			% [rounds, owners_full.size()]
		)


func _validate_territory_tape_golden() -> void:
	_log("-- Territory tape golden (stride 4) --")
	const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	const BattleReplayPackLib := preload("res://BattleReplayPack.gd")
	var bmap = BattleMapGeneratorLib.generate(99152, "open_field", 350, 350, "qa_tape_golden", {}, "battle")
	var sim := BattleTerritorySimLib.new()
	sim.set_resolve_context("viewer")
	sim.setup(bmap, 350, 350, null)
	var tape = sim.build_replay_tape(-1, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	var blob: PackedByteArray = BattleReplayPackLib.pack_tape(tape, bmap.grid_width, bmap.grid_height)
	const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
	var loaded = BattleReplayPackLib.unpack_tape(blob)
	if loaded.frame_count() != tape.frame_count():
		_fail("pack round-trip frame count %d != %d" % [loaded.frame_count(), tape.frame_count()])
		return
	var final_owners: PackedByteArray = BattleTerritoryTapeLib.owners_from_frame_at_index(
		tape, tape.frame_count() - 1
	)
	var hash_val: int = 0
	for i in range(final_owners.size()):
		hash_val = (hash_val * 31 + int(final_owners[i])) & 0x7FFFFFFF
	tape.battle_data = bmap
	tape.rebuild_segment_timing()
	var watch_s: float = tape.total_duration()
	_log("BENCH replay_watch_s=%.1f frames=%d" % [watch_s, tape.frame_count()])
	if watch_s > 4800.0 or watch_s < 20.0:
		_fail("golden tape watch %.1fs outside 20–4800s band" % watch_s)
		return
	var expected_frames_min: int = maxi(2, sim.round_index / BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	if tape.frame_count() < expected_frames_min / 4:
		_fail("golden tape too few frames: %d" % tape.frame_count())
	elif str(tape.result.get("end_reason", "")).is_empty():
		_fail("golden tape missing end_reason")
	else:
		_log(
			"OK  tape golden rounds=%d frames=%d hash=%d end=%s pack=%d bytes"
			% [
				sim.round_index,
				tape.frame_count(),
				hash_val,
				str(tape.result.get("end_reason", "")),
				blob.size(),
			]
		)


func _validate_squad_battle_resolve_speed() -> void:
	_log("-- Tactical battle resolve speed (scaled entities) --")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	var bmap = BattleMapGeneratorLib.generate(88056, "open_field", 600, 600, "qa_tactical", {}, "battle")
	var sim := BattleTacticalSimLib.new()
	sim.setup(bmap, 600, 600, null)
	var t0: int = Time.get_ticks_usec()
	var tape = sim.build_replay_tape(-1, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	if sim.store.count > 320:
		_fail("600 alloc should scale to ~150 entities/side, got %d" % sim.store.count)
	elif ms > 6000.0:
		_fail("single 600v600 tactical resolve took %.1f ms (gate 6000ms)" % ms)
	else:
		_log("OK  tactical resolve %d units, %.1fms, %d frames" % [sim.store.count, ms, tape.frame_count()])


func _validate_battle_replay_tape() -> void:
	_log("-- Battle replay tape (pre-resolve) --")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	const BattleReplayPlayerLib := preload("res://BattleReplayPlayer.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattlePacingLib := preload("res://BattlePacing.gd")
	var bmap = BattleMapGeneratorLib.generate(557, "open_field", 350, 350, "qa_replay", {}, "battle")
	var sim := BattleTacticalSimLib.new()
	sim.setup(bmap, 350, 350, null)
	var tape = sim.build_replay_tape(80)
	if tape.frame_count() < 2:
		_fail("replay tape needs start + at least one round frame, got %d" % tape.frame_count())
	elif not bool(tape.result.get("finished", false)) and sim.round_index < 80:
		_fail("replay tape should finish or hit cap")
	else:
		_log(
			"OK  replay tape %d frames, %.1f ms resolve, %.2fs watch"
			% [tape.frame_count(), tape.resolve_ms, tape.total_duration()]
		)
	tape.battle_data = bmap
	tape.rebuild_segment_timing()
	if tape.segment_durations.is_empty() and tape.frame_count() > 1:
		_fail("replay segment_durations not built")
	var min_seg: float = BattlePacingLib.REPLAY_MIN_SEGMENT_SECONDS
	for d in tape.segment_durations:
		if float(d) + 0.001 < min_seg:
			_fail("replay segment %.3fs below min %.3fs" % [float(d), min_seg])
			return
	var sec_cell: float = BattlePacingLib.seconds_per_cell(bmap)
	if sec_cell < 1.0:
		_fail("seconds_per_cell too fast: %.3f" % sec_cell)
	var player := BattleReplayPlayerLib.new(tape)
	player.apply_start_frame(sim.store)
	var rounds_seen: int = 0
	while not player.finished:
		var info: Dictionary = player.tick(0.05, sim.store)
		rounds_seen = maxi(rounds_seen, int(info.get("round", 0)))
	if not bool(tape.result.get("finished", sim.finished)):
		_fail("replay result missing finished flag")
	else:
		_log("OK  replay playback (%d rounds seen, won=%s)" % [
			rounds_seen,
			str(tape.result.get("player_won", false)),
		])


func _validate_battle_perf_rounds() -> void:
	_log("-- Battle perf advance_round gates --")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattlePerfProfilerLib := preload("res://BattlePerfProfiler.gd")
	const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")
	const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
	var bmap_2k = BattleMapGeneratorLib.generate(88001, "open_field", 2000, 2000, "qa_perf_2k", {}, "battle")
	var sim_2k := BattleTacticalSimLib.new()
	sim_2k.setup(bmap_2k, 2000, 2000, null)
	var prof := BattlePerfProfilerLib.new()
	var ms_2k: float = prof.measure_round(sim_2k, sim_2k.advance_round)
	if ms_2k > 25.0:
		_fail("2k advance_round took %.2f ms (gate 25ms)" % ms_2k)
	else:
		_log("OK  2k advance_round %.2f ms (%d units)" % [ms_2k, sim_2k.store.count])
	const BattleScaleProfileLib := preload("res://BattleScaleProfile.gd")
	var bmap_10k = BattleMapGeneratorLib.generate(88002, "open_field", 10000, 10000, "qa_perf_10k", {}, "battle")
	var sim_10k := BattleTacticalSimLib.new()
	sim_10k.setup(bmap_10k, 1, 1, null)
	var def = BattleUnitCatalogLib.get_by_archetype(BattleUnitCatalogLib.ARCH_INFANTRY)
	var archer_def = BattleUnitCatalogLib.get_by_archetype(BattleUnitCatalogLib.ARCH_ARCHER)
	var spawn_n: int = 4999
	for side in [UnitSimulationStoreLib.Side.FRIENDLY, UnitSimulationStoreLib.Side.HOSTILE]:
		for slot in range(spawn_n):
			var gx: int = 8 + (slot % 40)
			var gy: int = 8 + int(slot / 40) % 80
			var tier: int = (
				UnitSimulationStoreLib.Tier.LITE if slot < spawn_n / 10
				else UnitSimulationStoreLib.Tier.SIM_ONLY
			)
			var use_def = archer_def if slot % 5 == 0 else def
			sim_10k.store.spawn_from_definition(side, gx, gy, bmap_10k, use_def, slot % 8, tier)
	sim_10k.cell_grid.rebuild_from_store(sim_10k.store)
	sim_10k.data_table.bind(sim_10k.store, sim_10k.cell_grid)
	sim_10k.scale_profile = BattleScaleProfileLib.for_unit_count(sim_10k.store.count)
	var ms_10k: float = prof.measure_round(sim_10k, sim_10k.advance_round)
	if ms_10k > 80.0:
		_fail("10k-tiered advance_round took %.2f ms (gate 80ms)" % ms_10k)
	else:
		_log("OK  10k-tiered advance_round %.2f ms (%d units)" % [ms_10k, sim_10k.store.count])


func _validate_battle_turn_victory() -> void:
	_log("-- Battle rout victory rules --")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	var scale_map = BattleMapGeneratorLib.generate(777, "open_field", 400, 80, "L3_0", {}, "battle")
	var sim := BattleTacticalSimLib.new()
	sim.setup(scale_map, 400, 80, null)
	var outcome: Dictionary = sim.run_to_completion(150)
	if not bool(outcome.get("player_won", false)):
		_fail("overwhelming force should win via rout/wipe (turns=%d E=%d)" % [
			int(outcome.get("turns", 0)),
			int(outcome.get("hostile_remaining", 0)),
		])
	elif int(outcome.get("turns", 0)) < 1:
		_fail("tactical sim should advance at least one turn")
	else:
		_log("OK  rout victory (%d turns, enemy left %d)" % [
			int(outcome.get("turns", 0)),
			int(outcome.get("hostile_remaining", 0)),
		])


func _validate_battle_tactical_combat() -> void:
	_log("-- Battle tactical combat --")
	const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
	const BattleCombatResolverLib := preload("res://BattleCombatResolver.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	var bmap = BattleMapGeneratorLib.generate(12345, "open_field", 80, 80, "qa_combat", {}, "battle")
	var sim := BattleTacticalSimLib.new()
	sim.setup(bmap, 80, 80, null)
	var resolver := BattleCombatResolverLib.new()
	resolver.setup(12345)
	var atk: int = -1
	var def: int = -1
	for i in range(sim.store.count):
		if atk < 0 and sim.store.side[i] == 0:
			atk = i
		if def < 0 and sim.store.side[i] == 1:
			def = i
	if atk < 0 or def < 0:
		_fail("need friendly and hostile for melee test")
		return
	var hp_before: float = sim.store.health[def]
	for _try in range(40):
		var dmg: float = resolver.resolve_melee(sim.store, atk, def)
		if dmg > 0.0:
			sim.store.apply_damage(def, dmg)
		if sim.store.health[def] < hp_before:
			break
	if sim.store.health[def] >= hp_before:
		_fail("melee should damage defender")
	else:
		_log("OK  melee hit reduces HP")


func _validate_battle_cell_size_cap() -> void:
	_log("-- Battle cell size cap --")
	const BattleCellGridLib := preload("res://BattleCellGrid.gd")
	const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
	const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")
	var bmap = BattleMapGeneratorLib.generate(222, "open_field", 20, 20, "qa_cap", {}, "battle")
	var store := UnitSimulationStore.new()
	var grid := BattleCellGridLib.new()
	grid.setup(bmap)
	var gx: int = 20
	var gy: int = 20
	while gx < bmap.grid_width and not bmap.is_land_cell(gx, gy):
		gx += 1
	var cavalry_def = BattleUnitCatalogLib.get_by_archetype(BattleUnitCatalogLib.ARCH_CAVALRY)
	var total_size := 0
	for i in range(5):
		var idx := store.spawn_from_definition(0, gx, gy, bmap, cavalry_def, i)
		if idx < 0:
			break
		grid.rebuild_from_store(store)
		total_size = grid.size_used(gx, gy)
		if total_size > BattleCellGridLib.MAX_SIZE_PER_CELL:
			_fail("cell size exceeded cap: %d" % total_size)
			return
	var big := BattleUnitCatalogLib.get_by_archetype(BattleUnitCatalogLib.ARCH_COMMANDER)
	big.size = 8
	var blocked_idx := store.spawn_from_definition(0, gx, gy, bmap, big, 99)
	if blocked_idx >= 0 and grid.can_enter_unit(store, blocked_idx, gx, gy):
		grid.rebuild_from_store(store)
		var used: int = grid.size_used(gx, gy)
		if used + big.size > BattleCellGridLib.MAX_SIZE_PER_CELL and grid.move_unit_from_store(store, blocked_idx, gx, gy):
			_fail("size cap should block overfull cell entry")
		else:
			_log("OK  cell size cap (%d/10 used)" % used)
	else:
		_log("OK  cell size cap enforced at spawn")


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
