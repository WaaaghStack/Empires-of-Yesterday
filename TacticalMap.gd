# TacticalMap.gd
extends Control

const ROOM_SCENE := preload("res://Room.tscn")
const SOLDIER_SCENE := preload("res://SoldierUnit.tscn")
const ENEMY_SCENE := preload("res://EnemyUnit.tscn")
const EnemyLib := preload("res://Enemy.gd")
const INTEL_TERMINAL_SCENE := preload("res://IntelTerminal.tscn")
const VIP_ESCORT_SCENE := preload("res://VipEscort.tscn")
const MapVisualsLib := preload("res://MapVisuals.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const DOOR_SCENE := preload("res://Door.tscn")
const ProceduralMapGeneratorLib := preload("res://ProceduralMapGenerator.gd")
const OrderTypeLib := preload("res://OrderType.gd")
const CombatAudioLib := preload("res://CombatAudio.gd")
const TutorialStateLib := preload("res://TutorialState.gd")
const MissionStateLib := preload("res://MissionState.gd")
const IntelTerminalScript := preload("res://IntelTerminal.gd")
const VipEscortScript := preload("res://VipEscort.gd")
const DynamicPathGraphLib := preload("res://DynamicPathGraph.gd")
const MissionTaskBoardLib := preload("res://MissionTaskBoard.gd")
const SquadsManagerLib := preload("res://SquadsManager.gd")
const MissionEntityIndexLib := preload("res://MissionEntityIndex.gd")
const CombatCoordinatorLib := preload("res://CombatCoordinator.gd")
const HiveScene := preload("res://Hive.tscn")
const OvermindHiveScene := preload("res://OvermindHive.tscn")
const SwarmDirectorLib := preload("res://SwarmDirector.gd")
const EvolutionNodeScene := preload("res://EvolutionNode.tscn")
const EvolutionUpgradeLib := preload("res://EvolutionUpgrade.gd")
const EvolutionNodeLib := preload("res://EvolutionNode.gd")
const CommsTemplatesLib := preload("res://CommsTemplates.gd")
const HivePressureLib := preload("res://HivePressure.gd")

const MAX_COMMS_LINES := 40
const CAMERA_PAN_SPEED := 420.0
const CAMERA_ZOOM_MIN := 0.2
const CAMERA_ZOOM_MAX := 1.6
const CAMERA_ZOOM_WHEEL_STEP := 1.1
const CAMERA_FOLLOW_LERP := 0.14
const CAMERA_BOUNDS_PADDING := 56.0

var map_data
var path_graph: DynamicPathGraphLib
var doors: Array[Node2D] = []
var selected_spawn_room: Room = null
var spawn_selection_active := false
var deploy_assignments: Dictionary = {}
var _deploy_squad_index: int = 0
var _selected_squad_id: String = "alpha"
var task_board: MissionTaskBoardLib
var squads_manager: SquadsManagerLib
var entity_index: MissionEntityIndexLib
var combat_coordinator: CombatCoordinatorLib
var active_hives: Array = []
var _hives_destroyed: int = 0
var _hives_total: int = 0
var planet_mode: bool = false
var _overmind_hive = null
var _regular_hives_destroyed: int = 0
var _regular_hives_total: int = 0
var swarm_director: SwarmDirectorLib
var evolution_nodes: Array = []
var sector_panel: PanelContainer
var orbital_bar: HBoxContainer
var orbital_charge_label: Label
var _cinematic_timer: float = 0.0
var _cinematic_duration: float = 0.0
var _cinematic_slowmo: bool = false
var _comms_filter: String = "priority"
var _comms_entries: Array[Dictionary] = []
var _comms_rendered_count: int = 0
var _comms_force_rebuild: bool = true
var _hud_refresh_timer: float = 0.0
var _minimap_timer: float = 0.0
var _minimap_dirty: bool = true
var _comms_refresh_timer: float = 0.0
var _comms_dirty: bool = false
var _fog_timer: float = 0.0
var _hive_tick_timer: float = 0.0
const HIVE_TICK_INTERVAL := 0.25
var _fog_dirty: bool = true
var _swarm_tick_accum: float = 0.0
var _unit_tier_timer: float = 0.0
var _orbital_bar_timer: float = 0.0
var _cached_orbital_bonus: float = 0.0
var _perf_log_timer: float = 0.0
var _last_fog_ms: float = 0.0
var _cached_alive_units: Array[SoldierUnit] = []
var _alive_units_cache_frame: int = -1
var _show_threat_overlay: bool = false

var selected_soldiers: Array[SoldierResource] = []
var active_units: Array[SoldierUnit] = []
var rooms: Array[Room] = []
var active_enemies: Array[EnemyUnit] = []
var selected_unit_index: int = -1
var pending_order: OrderTypeLib.Type = OrderTypeLib.Type.CLEAR
var game_active := false
var sector_overlay_open := false
var mission_complete := false
var extraction_hint_shown := false
var extraction_identified_shown := false
var _last_order_frame: int = -1
var _last_order_room: Room = null
var mission_elapsed: float = 0.0
var kill_count: int = 0
var rooms_searched_count: int = 0
var _base_camera_zoom: float = 1.0
var _camera_follow_squad_id: String = ""
var _camera_follow_buttons: Dictionary = {}
var camera_follow_row: HBoxContainer
var zoom_indicator_label: Label
var deploy_banner: PanelContainer
var deploy_banner_label: Label
var _enemy_spawn_rng := RandomNumberGenerator.new()
var _rooms_cleared_count: int = 0
var _kill_count: int = 0
var _mission_start_time: float = 0.0
var _searched_room_count: int = 0
var _evac_search_gate: int = 0
var _hold_room: Room = null
var _hold_duration: float = 0.0
var _hold_timer: float = 0.0
var _hold_active: bool = false
var _hold_complete: bool = false
var _hold_wave_timer: float = 0.0
var _next_spawn_enemy_id: int = 100
var _order_highlight_room: Room = null
var hive_pressure: HivePressureLib
var extract_banner: PanelContainer
var extract_banner_label: Label
var _objective_beats_fired: Dictionary = {}
var _hive_telegraph_rooms: Dictionary = {}
var _threat_pinged_rooms: Dictionary = {}
var _intel_terminals_total: int = 0
var _intel_terminals_destroyed: int = 0
var _intel_terminal_nodes: Array = []
var _vip_escort: VipEscort = null
var _facility_alarm_active: bool = false
var _vip_extract_warned: bool = false

const HOLD_WAVE_INTERVAL := 12.0
const HUD_REFRESH_INTERVAL := 0.1
const MINIMAP_REFRESH_INTERVAL := 0.5
const COMMS_REFRESH_INTERVAL := 0.1
const FOG_UPDATE_INTERVAL_SEC := 0.5
const UNIT_TIER_INTERVAL := 0.2
const UNIT_SLEEP_RADIUS := 960.0
const FOG_LOS_RANGE := 480.0
const ORBITAL_BAR_INTERVAL := 0.5
const PATHFIND_BUDGET_INTERVAL := 1.0
const MAP_ENEMY_CAP := 22
const HIVE_TELEGRAPH_SECONDS := 1.2

@onready var start_button: Button = $HUD/HudScroll/VBox/StartButton
@onready var back_button: Button = $HUD/HudScroll/VBox/BackButton
@onready var comms_log: RichTextLabel = $LeftPanel/VBox/CommsScroll/CommsLog
@onready var comms_scroll: ScrollContainer = $LeftPanel/VBox/CommsScroll
@onready var controls_overlay: PanelContainer = $ControlsOverlay
@onready var squad_roster = $LeftPanel/VBox/SquadRosterPanel
@onready var roster_scroll: ScrollContainer = $LeftPanel/VBox/SquadRosterPanel/Scroll
@onready var hud_scroll: ScrollContainer = $HUD/HudScroll
@onready var play_area: Control = $PlayArea
@onready var mission_banner: PanelContainer = $PlayArea/MissionBanner
@onready var primary_objective_label: Label = $PlayArea/MissionBanner/BannerVBox/PrimaryObjectiveLabel
@onready var extraction_status_label: Label = $PlayArea/MissionBanner/BannerVBox/ExtractionStatusLabel
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var world: Node2D = $PlayArea/SubViewportContainer/SubViewport/World
@onready var map_camera: Camera2D = $PlayArea/SubViewportContainer/SubViewport/World/MapCamera
@onready var pause_label: Label = $HUD/HudScroll/VBox/PauseLabel
@onready var mission_result_label: Label = $HUD/HudScroll/VBox/MissionResultLabel
@onready var unit_name_label: Label = $HUD/HudScroll/VBox/UnitPanel/UnitName
@onready var unit_class_label: Label = $HUD/HudScroll/VBox/UnitPanel/UnitClass
@onready var unit_health_label: Label = $HUD/HudScroll/VBox/UnitPanel/UnitHealth
@onready var unit_order_label: Label = $HUD/HudScroll/VBox/UnitPanel/UnitOrder
@onready var objective_label: Label = $HUD/HudScroll/VBox/ObjectiveLabel
@onready var order_move_btn: Button = $HUD/HudScroll/VBox/OrderPanel/MoveButton
@onready var order_clear_btn: Button = $HUD/HudScroll/VBox/OrderPanel/ClearButton
@onready var order_search_btn: Button = $HUD/HudScroll/VBox/OrderPanel/SearchDestroyButton
@onready var order_defend_btn: Button = $HUD/HudScroll/VBox/OrderPanel/DefendButton
@onready var order_explore_btn: Button = $HUD/HudScroll/VBox/OrderPanel/ExploreButton
@onready var order_extract_btn: Button = $HUD/HudScroll/VBox/OrderPanel/ExtractButton
@onready var order_objective_btn: Button = $HUD/HudScroll/VBox/OrderPanel/ObjectiveButton
@onready var select_all_btn: Button = $HUD/HudScroll/VBox/SelectAllButton
@onready var ability_button: Button = $HUD/HudScroll/VBox/AbilityButton
var minimap_panel: Control
var comms_filter_row: HBoxContainer
var _pathfind_budget_timer: float = 0.0
var _mission_hud_tabs: TabContainer

func _ready() -> void:
	RunLog.set_verbose(false)
	add_to_group("tactical_map")
	task_board = MissionTaskBoardLib.new()
	squads_manager = SquadsManagerLib.new()
	entity_index = MissionEntityIndexLib.new()
	combat_coordinator = CombatCoordinatorLib.new()
	hive_pressure = HivePressureLib.new()
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.ignore_mouse($Title)
	GameTheme.ignore_mouse(play_area)
	GameTheme.configure_scroll(comms_scroll, 100.0)
	GameTheme.configure_scroll(roster_scroll, 120.0)
	GameTheme.configure_scroll(hud_scroll)
	process_mode = Node.PROCESS_MODE_ALWAYS
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	$QuitButton.pressed.connect(_on_quit_pressed)
	order_move_btn.pressed.connect(_set_pending_order.bind(OrderTypeLib.Type.MOVE))
	order_clear_btn.pressed.connect(_set_pending_order.bind(OrderTypeLib.Type.CLEAR))
	order_search_btn.pressed.connect(_on_search_destroy_pressed)
	order_defend_btn.pressed.connect(_set_pending_order.bind(OrderTypeLib.Type.DEFEND))
	order_explore_btn.pressed.connect(_on_explore_pressed)
	order_extract_btn.pressed.connect(_on_extract_pressed)
	order_objective_btn.pressed.connect(_on_objective_pressed)
	select_all_btn.pressed.connect(_select_all_units)
	ability_button.pressed.connect(_on_ability_pressed)
	squad_roster.roster_card_pressed.connect(_select_unit)
	squad_roster.squad_header_pressed.connect(_on_squad_header_pressed)
	_consolidate_mission_hud()
	_setup_commander_ui()
	var map_seed := -1
	if RunState.run_active:
		map_seed = RunState.run_seed if _is_planet_mission() else RunState.next_op_seed()
	else:
		var env_seed := OS.get_environment("EOY_MAP_SEED")
		if env_seed.is_valid_int():
			map_seed = env_seed.to_int()
	if _is_planet_mission() and RunState.run_active:
		if RunState.planet_map_data:
			map_data = RunState.planet_map_data
		else:
			map_data = ProceduralMapGeneratorLib.generate_planet(map_seed, RunState.get_planet_config())
			RunState.store_planet_map(map_data)
	elif RunState.run_active or map_seed >= 0:
		var config: Dictionary = RunState.get_difficulty_config() if RunState.run_active else {}
		map_data = ProceduralMapGeneratorLib.generate(map_seed, config)
	else:
		map_data = ProceduralMapGeneratorLib.generate(map_seed, {})
	path_graph = map_data.path_graph
	_evac_search_gate = int(map_data.evac_reveal_after_searches) if map_data else 0
	if RunState.run_active and RunState.active_modifier and RunState.active_modifier.evac_search_reduction > 0:
		_evac_search_gate = maxi(0, _evac_search_gate - RunState.active_modifier.evac_search_reduction)
	if RunState.run_active:
		SaveManager.discover_objective(map_data.objective_template)
	_build_map_visuals()
	_build_doors()
	_build_rooms()
	_begin_spawn_selection()
	_set_pending_order(OrderTypeLib.Type.CLEAR)
	await _layout_play_area()
	_setup_map_input()
	_update_hud()
	var hud_panel: PanelContainer = $HUD
	hud_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	if mission_banner:
		mission_banner.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.06, 0.08, 0.12, 0.88), Color(0.22, 0.28, 0.38, 0.9), 8))
	log_message("Procedural facility generated (seed %d)." % map_data.map_seed, "cyan")
	if map_data and map_data.is_handcrafted:
		log_message("Story finale layout — command facility deck.", GameTheme.ACCENT.to_html())
	elif map_data and map_data.facility_theme:
		log_message("Facility theme: %s." % map_data.facility_theme.capitalize(), GameTheme.TEXT_MUTED.to_html())
	if RunState.run_active:
		if _is_planet_mission():
			log_message(
				"Planet reclamation — phase %s | seed %d"
				% [RunState.get_planet_phase_name(), map_data.map_seed if map_data else RunState.run_seed],
				GameTheme.ACCENT.to_html(),
			)
			if $Title:
				$Title.text = "PLANETARY RECLAMATION — SINGLE MAP"
		else:
			log_message("Operation %d / %d — %s" % [
				RunState.op_index,
				RunState.ops_per_run,
				map_data.objective_template.replace("_", " ").capitalize(),
			], GameTheme.ACCENT.to_html())
	log_message("Select a secure deploy room, then press BEGIN MISSION.", GameTheme.ACCENT.to_html())
	log_message(RunLog.get_startup_announcement(), GameTheme.TEXT_MUTED.to_html())
	_load_squad_from_run_state()
	_show_tutorial_hints()
	if controls_overlay:
		controls_overlay.visible = false
		controls_overlay.add_theme_stylebox_override("panel", GameTheme.make_panel_style())

func _layout_play_area() -> void:
	await get_tree().process_frame
	var hud_rect: Rect2 = $HUD.get_global_rect()
	var top_y: float = 60.0
	var play_pos := Vector2(24.0, top_y)
	var play_size := Vector2(
		maxf(320.0, hud_rect.position.x - 32.0),
		maxf(320.0, hud_rect.end.y - top_y)
	)
	play_area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	play_area.global_position = play_pos
	play_area.size = play_size
	sub_viewport_container.stretch = false
	sub_viewport.size = Vector2i(maxi(int(play_size.x), 1), maxi(int(play_size.y), 1))
	world.position = play_size * 0.5
	var scale_factor: float = min(
		play_size.x / map_data.map_size.x,
		play_size.y / map_data.map_size.y
	) * 0.88
	map_camera.zoom = Vector2(scale_factor, scale_factor)
	_base_camera_zoom = scale_factor
	map_camera.position = Vector2.ZERO
	map_camera.enabled = true
	map_camera.make_current()
	_clamp_camera_position()
	_update_zoom_indicator()

func _build_map_visuals() -> void:
	var facility_theme := "industrial"
	if map_data:
		facility_theme = map_data.facility_theme
	var palette: Dictionary = MapVisualsLib.get_facility_palette(facility_theme)
	var layer := Node2D.new()
	layer.name = "MapVisuals"
	layer.z_index = -10
	world.add_child(layer)
	world.move_child(layer, 0)

	var half: Vector2 = map_data.map_size * 0.5
	var deck_base: Polygon2D = MapVisualsLib.make_rect_polygon(
		Rect2(Vector2(-half.x, -half.y), map_data.map_size),
		palette.get("deck", Color(0.07, 0.08, 0.11, 1.0))
	)
	deck_base.name = "DeckBase"
	deck_base.z_index = -5
	layer.add_child(deck_base)

	var corridors := Node2D.new()
	corridors.name = "Corridors"
	corridors.z_index = -2
	layer.add_child(corridors)
	for rect: Rect2 in map_data.get_corridor_rects():
		_add_corridor_visual(corridors, rect, palette)

	var hull_layer := Node2D.new()
	hull_layer.name = "HullLayer"
	hull_layer.z_index = 5
	world.add_child(hull_layer)

	var hull := Line2D.new()
	hull.name = "HullOutline"
	hull.points = map_data.get_hull_outline()
	hull.closed = true
	hull.width = 8.0
	hull.default_color = palette.get("hull_outer", Color(0.65, 0.72, 0.85, 1.0))
	hull_layer.add_child(hull)

	var inner_hull := Line2D.new()
	inner_hull.name = "HullOutlineInner"
	inner_hull.points = map_data.get_hull_outline()
	inner_hull.closed = true
	inner_hull.width = 2.5
	inner_hull.default_color = palette.get("hull_inner", Color(0.35, 0.75, 1.0, 0.95))
	hull_layer.add_child(inner_hull)

func _add_corridor_visual(parent: Node2D, rect: Rect2, palette: Dictionary = {}) -> void:
	if map_data and MapVisualsLib.colony_theme_active(map_data.facility_theme):
		var tiled := MapVisualsLib.make_colony_tiled_rect(rect, "corridor_stripe.png")
		tiled.z_index = 0
		parent.add_child(tiled)
		var outline: Line2D = MapVisualsLib.make_rect_outline(rect, palette.get("corridor_outline", Color(0.35, 0.42, 0.52, 0.85)), 1.5)
		outline.z_index = 2
		parent.add_child(outline)
		return
	if palette.is_empty():
		palette = MapVisualsLib.get_facility_palette("industrial")
	var floor_poly: Polygon2D = MapVisualsLib.make_rect_polygon(rect, palette.get("corridor_floor", Color(0.11, 0.13, 0.17, 1.0)))
	floor_poly.z_index = 0
	parent.add_child(floor_poly)

	var stripe_rect := rect
	if rect.size.x >= rect.size.y:
		stripe_rect = Rect2(
			rect.position + Vector2(4.0, rect.size.y * 0.38),
			Vector2(maxf(rect.size.x - 8.0, 8.0), maxf(rect.size.y * 0.24, 6.0))
		)
	else:
		stripe_rect = Rect2(
			rect.position + Vector2(rect.size.x * 0.38, 4.0),
			Vector2(maxf(rect.size.x * 0.24, 6.0), maxf(rect.size.y - 8.0, 8.0))
		)
	var stripe: Polygon2D = MapVisualsLib.make_rect_polygon(stripe_rect, palette.get("corridor_stripe", Color(0.18, 0.42, 0.82, 0.85)))
	stripe.z_index = 1
	parent.add_child(stripe)

	var outline: Line2D = MapVisualsLib.make_rect_outline(rect, palette.get("corridor_outline", Color(0.35, 0.42, 0.52, 0.85)), 1.5)
	outline.z_index = 2
	parent.add_child(outline)

func _build_doors() -> void:
	for data: Dictionary in path_graph.get_door_positions():
		var door: Node2D = DOOR_SCENE.instantiate()
		var room_pos: Vector2 = path_graph.nodes[data.room_node]
		var spine_pos: Vector2 = path_graph.nodes[data.spine_node]
		data["rotation"] = (room_pos - spine_pos).angle()
		door.setup(data)
		door.spine_node_id = data.get("spine_node", "")
		door.add_to_group("doors")
		if door.has_signal("opened"):
			door.opened.connect(_on_door_state_changed)
		if door.has_signal("closed"):
			door.closed.connect(_on_door_state_changed)
		world.add_child(door)
		if door.has_method("bind_tactical_map"):
			door.bind_tactical_map(self)
		doors.append(door)


func _on_door_state_changed(_door: Node2D) -> void:
	if path_graph:
		path_graph.invalidate_cache_for_door()
	_mark_fog_dirty()

func _setup_map_input() -> void:
	sub_viewport_container.gui_input.connect(_on_play_area_gui_input)

func _on_play_area_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_camera_zoom(event.button_index == MOUSE_BUTTON_WHEEL_UP)
			return
	if mission_complete:
		return
	if not game_active and not spawn_selection_active:
		return
	if _is_pointer_over_ui(get_viewport().get_mouse_position()):
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	var world_pos := _container_mouse_to_world()
	if event.button_index == MOUSE_BUTTON_RIGHT:
		handle_map_right_click(world_pos)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		handle_map_left_click(world_pos)

func _container_mouse_to_world() -> Vector2:
	var local := sub_viewport_container.get_local_mouse_position()
	var sv_size := Vector2(sub_viewport.size)
	var cont_size := sub_viewport_container.size
	var sv_pos := Vector2(
		local.x * sv_size.x / maxf(cont_size.x, 1.0),
		local.y * sv_size.y / maxf(cont_size.y, 1.0)
	)
	var canvas_pos: Vector2 = map_camera.get_canvas_transform().affine_inverse() * sv_pos
	return world.to_local(canvas_pos)

func _load_squad_from_run_state() -> void:
	selected_soldiers.clear()
	if RunState.run_active and not RunState.squad.is_empty():
		for resource in RunState.squad:
			if resource is SoldierResource and not resource.is_kia:
				selected_soldiers.append(resource)
	elif get_tree().has_meta("selected_soldiers"):
		var squad_meta = get_tree().get_meta("selected_soldiers")
		if squad_meta is Array:
			for resource in squad_meta:
				if resource is SoldierResource:
					selected_soldiers.append(resource)
		get_tree().remove_meta("selected_soldiers")
	if selected_soldiers.is_empty():
		return
	squad_roster.show_resources(selected_soldiers)
	log_message("Squad loaded: %d marines ready." % selected_soldiers.size())

func handle_map_right_click(world_pos: Vector2) -> void:
	if spawn_selection_active:
		var spawn_room := _get_room_at_position(world_pos)
		if spawn_room and spawn_room.is_spawn_eligible:
			_select_spawn_room(spawn_room)
		elif spawn_room:
			log_message("%s is not secure for deployment." % spawn_room.room_name, GameTheme.ACCENT_WARN.to_html())
		return
	if not _selected_unit() and active_units.size() > 0:
		_select_unit(0)
	var units := _get_selected_units()
	if units.is_empty():
		log_message("Select an active marine first.", GameTheme.ACCENT_WARN.to_html())
		return
	var room := _get_room_at_position(world_pos)
	if room:
		if not room.is_revealed:
			log_message("Sector uncharted — advance to reveal.", GameTheme.TEXT_MUTED.to_html())
			return
		if _order_supports_target_highlight():
			_update_order_target_highlight(room)
		_issue_order_to_selected(room)
	else:
		log_message("Click inside a room outline to issue orders.", GameTheme.TEXT_MUTED.to_html())

func handle_map_left_click(world_pos: Vector2) -> void:
	if spawn_selection_active:
		var spawn_room := _get_room_at_position(world_pos)
		if spawn_room and spawn_room.is_spawn_eligible:
			_select_spawn_room(spawn_room)
		elif spawn_room:
			log_message("%s is not secure for deployment." % spawn_room.room_name, GameTheme.ACCENT_WARN.to_html())
		else:
			log_message("Click a green-highlighted secure room to deploy.", GameTheme.TEXT_MUTED.to_html())
		return
	var closest_index := -1
	var closest_dist := 36.0
	for i in range(active_units.size()):
		var unit := active_units[i]
		if unit.is_alive:
			var dist := unit.position.distance_to(world_pos)
			if dist <= closest_dist:
				closest_dist = dist
				closest_index = i
	if closest_index >= 0:
		_select_unit(closest_index)

func _build_rooms() -> void:
	for data in map_data.get_room_dicts():
		var room: Room = ROOM_SCENE.instantiate()
		room.room_name = data.name
		room.position = data.pos
		room.map_room_id = data.id
		room.is_spawn_eligible = data.get("spawn_eligible", false)
		room.is_extraction_room = data.get("extract", false)
		room.requires_clear = data.get("clear", false)
		room.planned_enemy_count = data.get("enemies", 0)
		room.set_meta("stat_scale", data.get("stat_scale", 1.0))
		room.set_meta("scavenge", data.get("scavenge_bonus", false))
		room.set_meta("elite_slot", data.get("elite_slot", false))
		room.set_meta("hold_room", data.get("hold_room", false))
		room.set_meta("intel_terminal", data.get("intel_terminal", false))
		room.set_meta("vip_room", data.get("vip_room", false))
		room.set_meta("loot_branch", data.get("loot_branch", false))
		room.set_meta("hive_room", data.get("hive_room", false))
		room.set_meta("overmind_room", data.get("overmind_room", false))
		room.set_meta("evolution_node", data.get("evolution_node", false))
		room.sector_tag = str(data.get("sector", "central"))
		room.set_meta("room_shape", data.get("shape", "standard"))
		if data.get("hold_room", false):
			_hold_room = room
		room.is_revealed = false
		room.deploy_selection_mode = false
		room.configure(data.size, data.color)
		if map_data and MapVisualsLib.colony_theme_active(map_data.facility_theme):
			room.apply_colony_floor()
		room.cleared.connect(_on_room_cleared)
		room.order_requested.connect(_on_room_order_requested)
		room.soldier_entered.connect(_on_soldier_entered_room)
		world.add_child(room)
		rooms.append(room)

func _begin_spawn_selection() -> void:
	spawn_selection_active = true
	selected_spawn_room = null
	deploy_assignments.clear()
	_deploy_squad_index = 0
	_selected_squad_id = SquadsManagerLib.SQUAD_IDS[0]
	if _is_planet_mission() and not RunState.deploy_assignments.is_empty():
		_apply_carrier_sector_deployments()
	start_button.disabled = deploy_assignments.size() < SquadsManagerLib.SQUAD_IDS.size()
	if deploy_assignments.size() >= SquadsManagerLib.SQUAD_IDS.size():
		selected_spawn_room = deploy_assignments.get("alpha", null) as Room
		start_button.text = "BEGIN MISSION"
	else:
		start_button.text = "ASSIGN %s DEPLOY" % GameTheme.squad_label(_selected_squad_id).to_upper()
	_update_deploy_banner()
	for room in rooms:
		room.is_spawn_room = false
		room.deploy_selection_mode = true
		room.is_revealed = false
		room._update_visuals()
		_update_deploy_room_highlights()


func _update_deploy_room_highlights() -> void:
	for room in rooms:
		var assigned_squad := _squad_assigned_to_room(room)
		var is_current_pick := assigned_squad == _selected_squad_id
		room.set_spawn_selection_highlight(true, room.is_spawn_eligible, is_current_pick)


func _squad_assigned_to_room(room: Room) -> String:
	for squad_id in deploy_assignments.keys():
		if deploy_assignments[squad_id] == room:
			return str(squad_id)
	return ""


func _select_spawn_room(room: Room) -> void:
	if not spawn_selection_active or not room.is_spawn_eligible:
		return
	deploy_assignments[_selected_squad_id] = room
	RunLog.info("Deploy assign %s -> %s" % [_selected_squad_id, room.room_name])
	log_message(
		"%s deploy: %s" % [GameTheme.squad_label(_selected_squad_id), room.room_name],
		GameTheme.ACCENT_SUCCESS.to_html(),
		"squad",
	)
	_advance_deploy_squad_selection()
	_update_deploy_room_highlights()
	_update_deploy_banner()


func _update_deploy_banner() -> void:
	if not deploy_banner or not deploy_banner_label:
		return
	if not spawn_selection_active:
		deploy_banner.visible = false
		return
	deploy_banner.visible = true
	var parts: PackedStringArray = PackedStringArray()
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		var assigned: Room = deploy_assignments.get(squad_id, null) as Room
		var label := GameTheme.squad_label(squad_id)
		if assigned:
			parts.append("%s: %s ✓" % [label, assigned.room_name])
		elif squad_id == _selected_squad_id:
			parts.append("%s: pick room…" % label)
		else:
			parts.append("%s: —" % label)
	deploy_banner_label.text = "Deploy zones — %s" % " · ".join(parts)


func _advance_deploy_squad_selection() -> void:
	_deploy_squad_index += 1
	if _deploy_squad_index >= SquadsManagerLib.SQUAD_IDS.size():
		selected_spawn_room = deploy_assignments.get("alpha", null) as Room
		start_button.disabled = false
		start_button.text = "BEGIN MISSION"
		log_message("All squads assigned deploy zones. Press BEGIN MISSION.", GameTheme.ACCENT.to_html(), "objective")
		_update_deploy_banner()
		return
	_selected_squad_id = SquadsManagerLib.SQUAD_IDS[_deploy_squad_index]
	start_button.text = "ASSIGN %s DEPLOY" % GameTheme.squad_label(_selected_squad_id).to_upper()
	start_button.disabled = true
	_update_deploy_banner()

func _on_start_pressed() -> void:
	if game_active or mission_complete:
		return
	if selected_soldiers.is_empty():
		log_message("No squad deployed. Abort and re-select marines.", GameTheme.ACCENT_WARN.to_html())
		return
	if spawn_selection_active and deploy_assignments.size() < SquadsManagerLib.SQUAD_IDS.size():
		log_message("Assign deploy rooms for all three squads before beginning.", GameTheme.ACCENT_WARN.to_html(), "alert")
		return
	spawn_selection_active = false
	game_active = true
	if deploy_banner:
		deploy_banner.visible = false
	MissionStateLib.reset_mission()
	task_board.reset()
	squads_manager.reset()
	entity_index.reset()
	combat_coordinator.reset()
	active_hives.clear()
	_hives_destroyed = 0
	start_button.visible = false
	sector_overlay_open = false
	_objective_beats_fired.clear()
	if hive_pressure:
		hive_pressure.reset()
	_mission_start_time = Time.get_ticks_msec() / 1000.0
	_rooms_cleared_count = 0
	_kill_count = 0
	_searched_room_count = 0
	log_message("=== MISSION STARTED ===", "yellow")
	if _is_planet_mission():
		RunState.begin_planet_purge()
		log_message(
			"Planet purge: destroy %d nest hives, then the Overmind, then extract all operators."
			% _regular_hives_total,
			GameTheme.ACCENT.to_html(),
			"objective",
		)
	RunLog.info(
		"Op %d started — objective=%s map_seed=%d"
		% [
			RunState.op_index if RunState.run_active else 0,
			map_data.objective_template if map_data else "unknown",
			map_data.map_seed if map_data else 0,
		]
	)
	log_message(CommsTemplatesLib.mission_start(), GameTheme.ACCENT.to_html(), "objective")
	log_message("Fog of war active — hostiles must be spotted before engagement.", GameTheme.TEXT_MUTED.to_html())
	for room in rooms:
		room.deploy_selection_mode = false
		room.set_spawn_selection_highlight(false, false, false)
	_spawn_squad()
	_spawn_enemies()
	_spawn_hives()
	_spawn_evolution_nodes()
	_spawn_intel_terminals()
	_spawn_vip_escort()
	if map_data and map_data.objective_template == "hold_purge":
		_hold_duration = float(map_data.hold_duration_seconds) if map_data.hold_duration_seconds > 0.0 else 35.0
		if RunState.active_modifier and RunState.active_modifier.hold_duration_mult != 1.0:
			_hold_duration *= RunState.active_modifier.hold_duration_mult
		if _hold_room:
			log_message(
				"Hold & Purge: secure %s, then hold for %.0fs while reinforcements arrive." % [
					_hold_room.room_name,
					_hold_duration,
				],
				GameTheme.ACCENT.to_html()
			)
	elif map_data and map_data.objective_template == "hive_purge":
		log_message(
			"Hive Purge: destroy all bio-hives, clear zones, then extract.",
			GameTheme.ACCENT.to_html(),
			"objective",
		)
	elif _is_planet_mission():
		swarm_director = SwarmDirectorLib.new()
		swarm_director.reset(self)
		for squad_id in SquadsManagerLib.SQUAD_IDS:
			squads_manager.set_squad_stance(squad_id, RunState.get_squad_stance(squad_id))
		log_message(
			"Planet reclamation: secure sectors, purge nests, kill the Overmind, extract.",
			GameTheme.ACCENT.to_html(),
			"objective",
		)
	elif map_data and map_data.objective_template == "black_site":
		log_message(
			"Black Site: destroy all intel terminals, then extract.",
			GameTheme.ACCENT.to_html()
		)
	elif map_data and map_data.objective_template == "vip_recovery":
		log_message(
			"VIP Recovery: escort the asset — VIP follows your slowest operator.",
			GameTheme.ACCENT.to_html()
		)
	_init_fog_of_war()
	_apply_hub_intel_bonuses()
	if _is_planet_mission():
		_auto_assign_sector_doctrines()
	else:
		_issue_initial_objective_doctrines()
	_update_objectives()
	_update_hud()

func _spawn_squad() -> void:
	squads_manager.reset()
	var slot_by_squad: Dictionary = {"alpha": 0, "bravo": 0, "charlie": 0}
	var squad_index := 0
	for i in range(selected_soldiers.size()):
		var resource := selected_soldiers[i]
		if resource.is_kia:
			continue
		var squad_id: String = RunState.get_squad_id_for_index(i)
		if resource.squad_id != "":
			squad_id = resource.squad_id
		var spawn_room: Room = deploy_assignments.get(squad_id, selected_spawn_room) as Room
		if not spawn_room:
			spawn_room = _get_spawn_room()
		if not spawn_room:
			continue
		spawn_room.is_spawn_room = true
		var slot: int = int(slot_by_squad.get(squad_id, 0))
		slot_by_squad[squad_id] = slot + 1
		var unit: SoldierUnit = SOLDIER_SCENE.instantiate()
		unit.setup_from_resource(resource)
		unit.squad_id = squad_id
		unit.formation_slot = slot
		unit.task_board = task_board
		unit.all_rooms = rooms
		unit.bind_tactical_map(self)
		if RunState.active_modifier:
			if RunState.active_modifier.ability_cooldown_reduction > 0.0:
				unit.ability_cooldown_max = maxf(
					4.0,
					unit.ability_cooldown_max - RunState.active_modifier.ability_cooldown_reduction
				)
			if RunState.active_modifier.marine_speed_mult != 1.0:
				unit.speed *= RunState.active_modifier.marine_speed_mult
		unit.position = spawn_room.get_formation_position(slot, RunState.OPERATORS_PER_SQUAD, squad_index)
		if not spawn_room.get_rect().grow(-12.0).has_point(unit.position):
			RunLog.info(
				"Deploy clamped %s slot %d in %s"
				% [resource.soldier_name, slot, spawn_room.room_name]
			)
		unit.clicked.connect(_on_unit_clicked)
		unit.died.connect(_on_unit_died)
		unit.order_changed.connect(_on_unit_order_changed)
		unit.combat_hit.connect(_on_combat_hit)
		unit.health_changed.connect(_on_unit_health_changed)
		unit.extracted.connect(_on_unit_extracted)
		unit.order_path_failed.connect(_on_unit_order_path_failed)
		world.add_child(unit)
		active_units.append(unit)
		squads_manager.register_unit(unit, squad_id)
		entity_index.register_soldier(unit, spawn_room)
		log_message(
			"Deployed: %s (%s / %s)" % [
				resource.soldier_name,
				GameTheme.class_name_text(resource.marine_class),
				GameTheme.squad_label(squad_id),
			],
			"white",
			"squad",
		)
		squad_index += 1
	if active_units.size() > 0:
		_select_squad("alpha")
	squad_roster.bind_units(active_units, squads_manager, rooms, active_hives)
	_update_pathfind_budget()

func _spawn_enemies() -> void:
	var enemy_id := 1
	_enemy_spawn_rng.seed = map_data.map_seed
	var op_depth: int = RunState.op_index if RunState.run_active else 1
	var default_scale: float = map_data.enemy_stat_scale if map_data else 1.0
	for room in rooms:
		var count: int = room.planned_enemy_count
		if count <= 0:
			continue
		room.mark_contested()
		var stat_scale: float = float(room.get_meta("stat_scale", default_scale))
		var is_elite: bool = room.get_meta("elite_slot", false)
		for i in range(count):
			var is_elite_slot: bool = is_elite and i == count - 1
			var arch: Enemy.Kind = Enemy.pick_archetype_for_op(op_depth, _enemy_spawn_rng, is_elite_slot)
			var enemy_res := Enemy.create_archetype(arch, stat_scale, enemy_id)
			if RunState.active_modifier:
				if RunState.active_modifier.enemy_damage_bonus > 0:
					enemy_res.damage += RunState.active_modifier.enemy_damage_bonus
				if RunState.active_modifier.enemy_speed_mult != 1.0:
					enemy_res.speed *= RunState.active_modifier.enemy_speed_mult
			var arch_label := Enemy.archetype_label(arch)
			var intel_counts: Dictionary = room.get_meta("enemy_intel", {})
			intel_counts[arch_label] = int(intel_counts.get(arch_label, 0)) + 1
			room.set_meta("enemy_intel", intel_counts)
			SaveManager.discover_enemy(arch_label.to_lower())
			var enemy: EnemyUnit = ENEMY_SCENE.instantiate()
			enemy.setup_from_resource(enemy_res, room)
			enemy.bind_tactical_map(self)
			enemy.died.connect(_on_enemy_died)
			enemy.combat_hit.connect(_on_combat_hit)
			enemy.alarm_triggered.connect(_on_enemy_alarm_triggered)
			var offset := Vector2((i - (count - 1) * 0.5) * 36.0, room.room_size.y * 0.12)
			enemy.position = room.position + offset
			world.add_child(enemy)
			room.register_enemy(enemy)
			active_enemies.append(enemy)
			entity_index.register_enemy(enemy, room)
			enemy_id += 1
	log_message("Hostile contacts detected in facility.", GameTheme.ACCENT_DANGER.to_html(), "alert")
	log_message("Sensor feed limited — visual contact required.", GameTheme.TEXT_MUTED.to_html(), "combat")


func _spawn_hives() -> void:
	if not map_data:
		return
	_hives_total = 0
	_regular_hives_total = 0
	_regular_hives_destroyed = 0
	_overmind_hive = null
	if hive_pressure and map_data:
		hive_pressure.configure(map_data.facility_theme, RunState.active_mutators)
	for room in rooms:
		if not room.get_meta("hive_room", false):
			continue
		var is_overmind: bool = room.get_meta("overmind_room", false)
		var hive
		if is_overmind:
			hive = OvermindHiveScene.instantiate()
			_overmind_hive = hive
		else:
			hive = HiveScene.instantiate()
			_regular_hives_total += 1
		var op_depth: int = 3 if _is_planet_mission() else (RunState.op_index if RunState.run_active else 1)
		hive.setup(room, room.map_room_id, map_data.map_seed, map_data.enemy_stat_scale, op_depth)
		hive.bind_tactical_map(self)
		if hive_pressure and not is_overmind:
			hive_pressure.apply_to_hive(hive)
		hive.hive_destroyed.connect(_on_hive_destroyed)
		if not is_overmind:
			hive.hive_activated.connect(_on_hive_activated)
			hive.wave_spawned.connect(_on_hive_wave_spawned)
		world.add_child(hive)
		active_hives.append(hive)
		entity_index.register_hive(hive, room)
		_hives_total += 1
	if _is_planet_mission():
		RunState.regular_hives_total = _regular_hives_total
		RunState.regular_hives_destroyed = 0
	if _hives_total > 0:
		var hive_msg := "BIO SCAN: %d hive signature(s) on deck. Destroy or endure escalating waves." % _hives_total
		if _is_planet_mission() and _overmind_hive:
			hive_msg = (
				"BIO SCAN: %d nest hive(s) + dormant Overmind node. Purge nests to awaken the queen."
				% _regular_hives_total
			)
		log_message(hive_msg, GameTheme.ACCENT_WARN.to_html(), "alert")


func register_spawned_enemy(enemy: EnemyUnit, room: Room) -> bool:
	if _living_enemy_count() >= MAP_ENEMY_CAP:
		if is_instance_valid(enemy):
			enemy.queue_free()
		return false
	enemy.bind_tactical_map(self)
	enemy.died.connect(_on_enemy_died)
	enemy.combat_hit.connect(_on_combat_hit)
	enemy.alarm_triggered.connect(_on_enemy_alarm_triggered)
	world.add_child(enemy)
	if room:
		room.register_enemy(enemy)
	entity_index.register_enemy(enemy, room)
	active_enemies.append(enemy)
	return true


func _living_enemy_count() -> int:
	var count := 0
	for enemy in active_enemies:
		if enemy and is_instance_valid(enemy) and enemy.is_alive:
			count += 1
	return count


func is_enemy_cap_reached() -> bool:
	return _living_enemy_count() >= MAP_ENEMY_CAP


func mark_minimap_dirty() -> void:
	_minimap_dirty = true


func _on_hive_destroyed(hive) -> void:
	active_hives.erase(hive)
	var is_overmind: bool = hive is OvermindHive
	if _is_planet_mission() and not is_overmind:
		_regular_hives_destroyed += 1
		RunState.on_regular_hive_destroyed()
		_fire_objective_beats()
		if RunState.planet_phase == RunState.PlanetPhase.QUEEN and _overmind_hive and _overmind_hive.has_method("activate_overmind"):
			_overmind_hive.activate_overmind()
			log_message(CommsTemplatesLib.overmind_awakens(), GameTheme.ACCENT_DANGER.to_html(), "alert")
	elif is_overmind:
		call_deferred("_announce_extract_window")
	_hives_destroyed += 1
	if hive and hive.home_room:
		entity_index.unregister_hive(hive.home_room)
		var tag := "Overmind" if is_overmind else "Hive"
		log_message("%s neutralized in %s." % [tag, hive.home_room.room_name], GameTheme.ACCENT_SUCCESS.to_html(), "objective")
	CombatAudioLib.play_room_secured(self)
	_update_hive_threat_overlay()
	_update_objectives()
	_check_mission_status()


func _on_hive_activated(_hive) -> void:
	SaveManager.discover_enemy("bio_hive")
	_show_threat_overlay = true
	_update_objectives()


func _update_hive_threat_overlay() -> void:
	_show_threat_overlay = false
	for hive in active_hives:
		if hive and hive.is_attackable() and hive.state == Hive.State.ACTIVE:
			_show_threat_overlay = true
			return


func _issue_initial_objective_doctrines() -> void:
	if not map_data:
		return
	var doctrine := SquadsManagerLib.doctrine_for_objective(map_data.objective_template)
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		squads_manager.set_doctrine(squad_id, doctrine)
	log_message(
		"Objective doctrine [%s] assigned — press O to re-issue to selected squad." % OrderTypeLib.get_label(doctrine),
		GameTheme.ACCENT.to_html(),
		"objective",
	)


func get_objective_template() -> String:
	return map_data.objective_template if map_data else "standard"


func _spawn_intel_terminals() -> void:
	if not map_data or map_data.objective_template != "black_site":
		return
	for room in rooms:
		if not room.get_meta("intel_terminal", false):
			continue
		var terminal: IntelTerminal = INTEL_TERMINAL_SCENE.instantiate()
		var offset := Vector2(room.room_size.x * 0.22, -room.room_size.y * 0.08)
		terminal.setup(room, offset)
		terminal.destroyed.connect(_on_intel_terminal_destroyed)
		world.add_child(terminal)
		_intel_terminal_nodes.append(terminal)
		_intel_terminals_total += 1
		room.set_meta("terminals_remaining", int(room.get_meta("terminals_remaining", 0)) + 1)
	if _intel_terminals_total > 0:
		log_message(
			"SIGINT: %d intel terminals flagged for destruction." % _intel_terminals_total,
			GameTheme.ACCENT_WARN.to_html()
		)


func _spawn_vip_escort() -> void:
	if not map_data or map_data.objective_template != "vip_recovery":
		return
	var vip_room: Room = null
	for room in rooms:
		if room.get_meta("vip_room", false):
			vip_room = room
			break
	if not vip_room:
		return
	var vip: VipEscort = VIP_ESCORT_SCENE.instantiate()
	vip.position = vip_room.position + Vector2(-20.0, vip_room.room_size.y * 0.1)
	vip.died.connect(_on_vip_died)
	vip.reached_extraction.connect(_on_vip_reached_extraction)
	world.add_child(vip)
	_vip_escort = vip
	vip_room.reveal()
	log_message("VIP located in %s — keep them with the squad." % vip_room.room_name, GameTheme.ACCENT.to_html())


func _on_intel_terminal_destroyed(terminal: IntelTerminal) -> void:
	_intel_terminals_destroyed += 1
	if terminal and terminal.home_room:
		var remaining := int(terminal.home_room.get_meta("terminals_remaining", 1)) - 1
		terminal.home_room.set_meta("terminals_remaining", maxi(0, remaining))
		terminal.home_room._refresh_status()
	_intel_terminal_nodes.erase(terminal)
	CombatAudioLib.play_room_secured(self)
	log_message(
		"Intel terminal destroyed (%d / %d)." % [_intel_terminals_destroyed, _intel_terminals_total],
		GameTheme.ACCENT_SUCCESS.to_html()
	)
	_update_objectives()
	_check_mission_status()


func _try_destroy_room_terminals(room: Room) -> void:
	if not room.get_meta("intel_terminal", false):
		return
	if not room.is_cleared:
		return
	if room.soldiers_inside.is_empty():
		return
	for node in _intel_terminal_nodes.duplicate():
		if not is_instance_valid(node):
			continue
		if node is IntelTerminal and not node.is_destroyed and node.home_room == room:
			node.destroy_terminal()


func _on_vip_died(_vip: VipEscort) -> void:
	_vip_escort = null
	log_message("VIP is down — mission failed.", GameTheme.ACCENT_DANGER.to_html())
	_end_mission(false)


func _on_vip_reached_extraction(_vip: VipEscort) -> void:
	log_message("VIP reached evacuation zone.", GameTheme.ACCENT_SUCCESS.to_html())
	_update_objectives()
	_check_mission_status()


func _on_enemy_alarm_triggered(enemy: EnemyUnit) -> void:
	if _facility_alarm_active:
		return
	_facility_alarm_active = true
	var combat_room := _enemy_room(enemy)
	log_message("FACILITY ALARM — rifleman triggered lockdown!", GameTheme.ACCENT_DANGER.to_html())
	if map_data and map_data.objective_template == "silent_extract":
		_evac_search_gate = mini(_evac_search_gate + 1, 4)
		log_message(
			"Silent op compromised — evac intel requires %d more sector searches." % _evac_search_gate,
			GameTheme.ACCENT_WARN.to_html()
		)
	for room in rooms:
		if room.is_revealed:
			continue
		if combat_room and _rooms_are_adjacent(combat_room, room):
			room.mark_hostile_contact("Alarm")
			var room_key := room.map_room_id
			if not room_key.is_empty() and not _threat_pinged_rooms.has(room_key):
				_threat_pinged_rooms[room_key] = true
				CombatAudioLib.play_threat_ping(self)
	_update_objectives()

func _init_fog_of_war() -> void:
	for room in rooms:
		room.is_revealed = room == selected_spawn_room
		room.is_searched = false
		room._update_visuals()
	if selected_spawn_room:
		_reveal_and_search(selected_spawn_room)
	for enemy in active_enemies:
		enemy.set_visible_to_player(false)


func _apply_hub_intel_bonuses() -> void:
	if not RunState.run_active:
		return
	_apply_purchased_reveal_room_intel()
	_apply_purchased_extraction_hint_intel()
	_apply_overwatch_drone_bonus()
	_apply_purchased_enemy_scan_intel()


func _apply_purchased_reveal_room_intel() -> void:
	if not RunState.consume_pending_intel("reveal_room"):
		return
	var unrevealed_rooms: Array[Room] = []
	for room in rooms:
		if not room.is_revealed:
			unrevealed_rooms.append(room)
	if unrevealed_rooms.is_empty():
		return
	unrevealed_rooms.shuffle()
	var target: Room = unrevealed_rooms[0]
	target.reveal()
	target._update_visuals()
	log_message(
		"Intel uplink: %s mapped before deploy." % target.room_name,
		GameTheme.ACCENT.to_html()
	)


func _apply_purchased_extraction_hint_intel() -> void:
	if not RunState.consume_pending_intel("extraction_hint"):
		return
	var extraction := _get_extraction_room()
	if not extraction:
		return
	extraction.reveal()
	extraction._update_visuals()
	log_message(
		"SIGINT: evacuation zone likely at %s." % extraction.room_name,
		GameTheme.ACCENT_SUCCESS.to_html()
	)


func _apply_overwatch_drone_bonus() -> void:
	if not RunState.has_run_augment("overwatch_drone") or not selected_spawn_room:
		return
	var candidates: Array[Room] = []
	for room in rooms:
		if room.is_revealed or room == selected_spawn_room:
			continue
		var route: Array[String] = path_graph.find_room_route(
			selected_spawn_room.map_room_id,
			room.map_room_id
		)
		if route.size() == 2:
			candidates.append(room)
	if candidates.is_empty():
		for room in rooms:
			if not room.is_revealed and room != selected_spawn_room:
				candidates.append(room)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var bonus_room: Room = candidates[0]
	bonus_room.reveal()
	bonus_room._update_visuals()
	log_message(
		"Overwatch Drone: %s flagged on deploy." % bonus_room.room_name,
		GameTheme.ACCENT.to_html()
	)


func _apply_purchased_enemy_scan_intel() -> void:
	if not RunState.consume_pending_intel("enemy_scan"):
		return
	var hostile_rooms: Array[Room] = []
	for room in rooms:
		if room.planned_enemy_count > 0:
			hostile_rooms.append(room)
	if hostile_rooms.is_empty():
		return
	hostile_rooms.shuffle()
	var target: Room = hostile_rooms[0]
	target.reveal()
	var intel_counts: Dictionary = target.get_meta("enemy_intel", {})
	var parts: PackedStringArray = []
	for label in intel_counts.keys():
		parts.append("%s x%d" % [label, int(intel_counts[label])])
	var scan_text := "SCAN: hostiles"
	if not parts.is_empty():
		scan_text = "SCAN: %s" % ", ".join(parts)
	target.set_intel_scan(scan_text)
	target._update_visuals()
	log_message(
		"Enemy scan: %s — %s." % [target.room_name, scan_text],
		GameTheme.ACCENT_WARN.to_html()
	)

func _process(delta: float) -> void:
	var step := delta * (0.35 if _cinematic_slowmo else 1.0)
	if _cinematic_timer > 0.0:
		_cinematic_timer = maxf(0.0, _cinematic_timer - delta)
		if _cinematic_timer <= 0.0:
			_cinematic_slowmo = false
			Engine.time_scale = 1.0
	_update_camera_follow(step)
	_update_camera_pan(step)
	_clamp_camera_position()
	_update_zoom_indicator()
	_minimap_timer += step
	if minimap_panel and (_minimap_dirty or _minimap_timer >= MINIMAP_REFRESH_INTERVAL):
		_minimap_timer = 0.0
		_minimap_dirty = false
		minimap_panel.queue_redraw()
	_comms_refresh_timer += delta
	if _comms_dirty and _comms_refresh_timer >= COMMS_REFRESH_INTERVAL:
		_comms_refresh_timer = 0.0
		_comms_dirty = false
		_refresh_comms_display()
	if not game_active or mission_complete:
		return
	_pathfind_budget_timer += delta
	if _pathfind_budget_timer >= PATHFIND_BUDGET_INTERVAL:
		_pathfind_budget_timer = 0.0
		_update_pathfind_budget()
	_fog_timer += delta
	if _fog_dirty or _fog_timer >= FOG_UPDATE_INTERVAL_SEC:
		_fog_timer = 0.0
		_fog_dirty = false
		_update_fog_of_war()
	MissionStateLib.tick_squad_mark(step)
	combat_coordinator.tick(delta, _alive_units(), entity_index, rooms, doors, active_hives)
	_hive_tick_timer += step
	if _hive_tick_timer >= HIVE_TICK_INTERVAL:
		_hive_tick_timer = 0.0
		_tick_hives(HIVE_TICK_INTERVAL)
	if hive_pressure and game_active:
		hive_pressure.tick(step)
	_tick_hive_telegraphs(step)
	_unit_tier_timer += delta
	if _unit_tier_timer >= UNIT_TIER_INTERVAL:
		_unit_tier_timer = 0.0
		_update_unit_process_tiers()
	_hud_refresh_timer += delta
	if _hud_refresh_timer >= HUD_REFRESH_INTERVAL:
		_hud_refresh_timer = 0.0
		if game_active:
			_refresh_roster()
	_check_mission_status()
	if _hold_active:
		_update_hold_purge(delta)
	if _is_planet_mission():
		if swarm_director:
			_swarm_tick_accum += delta
			if _swarm_tick_accum >= 1.0:
				swarm_director.tick(_swarm_tick_accum)
				_swarm_tick_accum = 0.0
		_orbital_bar_timer += delta
		if _orbital_bar_timer >= ORBITAL_BAR_INTERVAL:
			_orbital_bar_timer = 0.0
			_cached_orbital_bonus = _compute_orbital_bonus()
		RunState.regen_orbital_charge(delta, _cached_orbital_bonus)
		_update_orbital_bar()
	if _is_planet_mission() and RunState.extract_window_open:
		_update_objectives()
		_update_extract_banner()
	if _any_unit_extracting():
		_update_objectives()
	_perf_log_timer += delta
	if _perf_log_timer >= 5.0:
		_perf_log_timer = 0.0
		RunLog.perf(
			"fog=%.1fms rooms=%d enemies=%d soldiers=%d"
			% [_last_fog_ms, rooms.size(), active_enemies.size(), active_units.size()]
		)

func _get_spawn_room() -> Room:
	for room in rooms:
		if room.is_spawn_room:
			return room
	return rooms[0] if rooms.size() > 0 else null

func _get_extraction_room() -> Room:
	for room in rooms:
		if room.is_extraction_room:
			return room
	return null

func _get_required_rooms() -> Array[Room]:
	return rooms.filter(func(r): return r.requires_clear)

func _mark_fog_dirty() -> void:
	_fog_dirty = true
	_minimap_dirty = true


func _on_soldier_entered_room(room: Room, soldier: SoldierUnit) -> void:
	if soldier and room:
		entity_index.register_soldier(soldier, room)
		_mark_fog_dirty()
	_try_destroy_room_terminals(room)
	if _is_planet_mission() and room.get_meta("evolution_node", false):
		for node in evolution_nodes:
			if node.get_script() == EvolutionNodeLib and node.home_room == room and not node.consumed:
				node.try_activate(soldier.squad_id)
				break
	if _is_planet_mission() and swarm_director and room.sector_tag != "":
		swarm_director.on_disturbance(room.sector_tag)


func _on_room_order_requested(room: Room) -> void:
	if spawn_selection_active:
		if room.is_spawn_eligible:
			_select_spawn_room(room)
		else:
			log_message("%s is not secure for deployment." % room.room_name, GameTheme.ACCENT_WARN.to_html())
		return
	if not game_active or mission_complete:
		return
	if _is_pointer_over_ui(get_viewport().get_mouse_position()):
		return
	if not _selected_unit() and active_units.size() > 0:
		_select_unit(0)
	_issue_order_to_selected(room)

func _objectives_cleared() -> bool:
	var required := _get_required_rooms()
	if _is_planet_mission():
		if not required.all(func(r): return r.is_cleared):
			return false
		if _regular_hives_total > 0 and _regular_hives_destroyed < _regular_hives_total:
			return false
		if not RunState.overmind_destroyed:
			return false
		return true
	if not required.all(func(r): return r.is_cleared):
		return false
	if map_data and map_data.objective_template == "hive_purge":
		if _hives_total > 0 and _hives_destroyed < _hives_total:
			return false
	if map_data and map_data.objective_template == "black_site":
		if _intel_terminals_total <= 0:
			return true
		return _intel_terminals_destroyed >= _intel_terminals_total
	return true

func _on_unit_extracted(unit: SoldierUnit) -> void:
	log_message("%s extracted." % unit.soldier_name, GameTheme.ACCENT_SUCCESS.to_html())
	_refresh_roster()
	_update_objectives()
	_update_hud()
	_check_mission_status()

func _on_room_cleared(room: Room) -> void:
	for hive in active_hives:
		if hive and hive.has_method("on_room_cleared") and hive.home_room == room:
			hive.on_room_cleared()
	if room == _hold_room and not _hold_complete:
		room.is_cleared = false
		if not _hold_active:
			_start_hold_phase()
		_update_objectives()
		return
	_rooms_cleared_count += 1
	CombatAudioLib.play_room_secured(self)
	log_message("%s secured." % room.room_name, GameTheme.ACCENT_SUCCESS.to_html())
	_try_destroy_room_terminals(room)
	_update_objectives()
	_check_mission_status()

func _on_combat_hit(attacker_name: String, target_name: String, damage: int, killed: bool) -> void:
	if killed:
		log_message("%s eliminated %s." % [attacker_name, target_name], GameTheme.ACCENT_SUCCESS.to_html())
	else:
		log_message("%s hits %s for %d." % [attacker_name, target_name, damage], "white")
	_maybe_audio_threat_ping(attacker_name, target_name)
	_update_hud()

func _on_unit_health_changed(_unit: SoldierUnit) -> void:
	_refresh_roster()
	_update_hud()

func _on_enemy_died(enemy: EnemyUnit) -> void:
	active_enemies.erase(enemy)
	if enemy.home_room:
		entity_index.unregister_enemy(enemy, enemy.home_room)
	_kill_count += 1
	if _is_planet_mission() and RunState.run_active:
		RunState.award_biomass(2)
		if enemy.get_meta("elite", false):
			RunState.award_echoes(1)
	if enemy.home_room:
		enemy.home_room.check_cleared_status()
	else:
		for room in rooms:
			room.check_cleared_status()
	_update_objectives()

func _on_unit_died(unit: SoldierUnit) -> void:
	log_message("%s is down." % unit.soldier_name, GameTheme.ACCENT_DANGER.to_html())
	if entity_index and entity_index.soldier_room.has(unit):
		entity_index.unregister_soldier(unit, entity_index.soldier_room[unit])
	if combat_coordinator:
		combat_coordinator.clear_soldier(unit)
	_alive_units_cache_frame = -1
	_update_pathfind_budget()
	var was_selected := unit.is_selected
	var old_index := active_units.find(unit)
	active_units.erase(unit)
	if was_selected:
		if _get_selected_units().is_empty():
			selected_unit_index = -1
			if not active_units.is_empty():
				_select_unit(clampi(old_index, 0, active_units.size() - 1))
		else:
			selected_unit_index = active_units.find(_get_selected_units()[0])
	else:
		if selected_unit_index > old_index and selected_unit_index >= 0:
			selected_unit_index -= 1
	squad_roster.bind_units(active_units, squads_manager, rooms, active_hives)
	_update_hud()
	if _alive_units().is_empty() and game_active:
		_end_mission(false)

func _on_unit_order_changed(_unit: SoldierUnit, _order: OrderTypeLib.Type) -> void:
	_refresh_roster()
	_update_hud()

func _alive_units() -> Array[SoldierUnit]:
	var frame := Engine.get_process_frames()
	if _alive_units_cache_frame == frame:
		return _cached_alive_units
	_alive_units_cache_frame = frame
	_cached_alive_units.clear()
	for unit in active_units:
		if unit.is_alive and not unit.is_extracted:
			_cached_alive_units.append(unit)
	return _cached_alive_units


func get_living_soldiers_cached() -> Array:
	return _alive_units()


func get_squad_mates(squad_id: String, exclude: SoldierUnit = null) -> Array[SoldierUnit]:
	var result: Array[SoldierUnit] = []
	for unit in _alive_units():
		if unit.squad_id == squad_id and unit != exclude and unit.is_alive and not unit.is_extracted:
			result.append(unit)
	return result


func _update_pathfind_budget() -> void:
	if not path_graph:
		return
	var alive_count := _alive_units().size()
	var max_finds := 4
	if alive_count >= 8:
		max_finds = 2
	elif alive_count >= 4:
		max_finds = 3
	path_graph.set_max_finds_per_frame(max_finds)


func _compute_orbital_bonus() -> float:
	var orbital_bonus := 0.0
	for squad_id in RunState.SQUAD_IDS:
		var board: EvolutionBoard = RunState.get_evolution_board(squad_id)
		for upgrade_id in board.applied_ids:
			var up := EvolutionUpgradeLib.get_by_id(upgrade_id)
			if up:
				orbital_bonus += up.orbital_charge_bonus * 0.01
	return orbital_bonus


func _update_unit_process_tiers() -> void:
	if not game_active or not map_camera:
		return
	var center := map_camera.position
	var zoom := maxf(map_camera.zoom.x, 0.01)
	var sleep_r := UNIT_SLEEP_RADIUS / zoom
	for unit in active_units:
		if not unit.is_alive or unit.is_extracted:
			continue
		var dist := unit.position.distance_to(center)
		unit.set_process(dist <= sleep_r)
	for enemy in active_enemies:
		if not enemy.is_alive:
			continue
		var dist := enemy.position.distance_to(center)
		var active := dist <= sleep_r or enemy.is_visible_to_player
		enemy.set_physics_process(active)
	for i in range(active_hives.size() - 1, -1, -1):
		var hive = active_hives[i]
		if hive == null or not is_instance_valid(hive) or (hive.get("is_destroyed") and hive.is_destroyed):
			active_hives.remove_at(i)

func _any_unit_extracting() -> bool:
	for unit in _alive_units():
		if unit.is_extracting and not unit.is_extracted:
			return true
	return false

func _check_mission_status() -> void:
	if not game_active or mission_complete:
		return
	if not _objectives_cleared():
		return
	var extraction := _get_extraction_room()
	if not extraction:
		return
	var alive := _alive_units()
	if alive.is_empty():
		return
	if map_data and map_data.objective_template == "vip_recovery":
		if not _vip_escort or not _vip_escort.is_alive:
			_end_mission(false)
			return
		if alive.all(func(u): return u.is_extracted):
			if not _vip_escort.is_at_extraction:
				if not _vip_extract_warned:
					_vip_extract_warned = true
					log_message(
						"VIP not at evac — hold extraction until the asset arrives.",
						GameTheme.ACCENT_WARN.to_html()
					)
				return
			_end_mission(true)
			return
	if alive.all(func(u): return u.is_extracted):
		_end_mission(true)
		return
	if not extraction_hint_shown:
		extraction_hint_shown = true
		_show_extract_hint_if_needed()
		if extraction.is_revealed:
			log_message(
				"All objectives secured. Press Extract [E] to evacuate via %s." % extraction.room_name,
				GameTheme.ACCENT_SUCCESS.to_html()
			)
		else:
			log_message(
				"All objectives secured. Locate the evacuation zone, then use Extract [E].",
				GameTheme.ACCENT_SUCCESS.to_html()
			)
	_update_objectives()

func _end_mission(victory: bool) -> void:
	mission_complete = true
	game_active = false
	sector_overlay_open = false
	RunState.sync_from_units(active_units)
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - _mission_start_time
	var casualties := 0
	for member in RunState.squad:
		if member.is_kia:
			casualties += 1
	var credits_earned := 0
	if victory:
		credits_earned = 15 + _kill_count * 2 + _rooms_cleared_count * 3
		if RunState.active_modifier:
			var objective_id: String = map_data.objective_template if map_data else "standard"
			credits_earned = int(credits_earned * RunState.active_modifier.get_credit_multiplier_for_objective(objective_id))
		var augment_bonus := RunState.award_post_mission_bonuses()
		if augment_bonus > 0:
			credits_earned += augment_bonus
		RunState.run_credits += credits_earned
		RunState.cleared_ops = maxi(RunState.cleared_ops, RunState.op_index)
	RunState.record_mission_stats({
		"victory": victory,
		"partial": victory and casualties > 0,
		"op_index": RunState.op_index if RunState.run_active else 1,
		"rooms_cleared": _rooms_cleared_count,
		"kills": _kill_count,
		"casualties": casualties,
		"time_seconds": elapsed,
		"credits_earned": credits_earned,
		"seed": map_data.map_seed if map_data else 0,
		"objective": map_data.objective_template if map_data else "standard",
	})
	for unit in active_units:
		if unit.is_alive:
			unit.cancel_order()
	mission_result_label.visible = true
	if victory:
		mission_result_label.text = "MISSION COMPLETE"
		mission_result_label.modulate = GameTheme.ACCENT_SUCCESS
		log_message("=== MISSION COMPLETE ===", "gold")
		log_message("Squad extracted. Facility purged.", GameTheme.ACCENT_SUCCESS.to_html())
	else:
		mission_result_label.text = "MISSION FAILED"
		mission_result_label.modulate = GameTheme.ACCENT_DANGER
		log_message("=== MISSION FAILED ===", GameTheme.ACCENT_DANGER.to_html())
		log_message("Squad eliminated.", GameTheme.ACCENT_DANGER.to_html())
	RunLog.info(
		"Op %d ended — victory=%s kills=%d casualties=%d elapsed=%.0fs"
		% [
			RunState.op_index if RunState.run_active else 0,
			str(victory),
			_kill_count,
			casualties,
			elapsed,
		]
	)
	_update_hud()
	await get_tree().create_timer(1.8).timeout
	if _is_planet_mission() and RunState.run_active:
		var ops_cleared := 1 if victory else 0
		var run_won := victory
		var purge_pct := 0.0
		if _regular_hives_total > 0:
			purge_pct = float(_regular_hives_destroyed) / float(_regular_hives_total)
		var max_evo_tier := 0
		for squad_id in RunState.SQUAD_IDS:
			max_evo_tier = maxi(max_evo_tier, RunState.get_evolution_board(squad_id).get_tier_reached())
		var rank_data := SaveManager.compute_imperial_reclamation_rank({
			"purge_pct": purge_pct,
			"legacy_biomass": RunState.legacy_biomass,
			"yesterdays_echoes": RunState.yesterdays_echoes,
			"evolution_tier": max_evo_tier,
		})
		var rewards: Dictionary = SaveManager.record_run_end(ops_cleared, run_won, {
			"legacy_biomass": RunState.legacy_biomass,
			"token_bonus": int(float(rank_data.get("score", 0)) / 100.0),
		})
		var summary_meta := {
			"ops_cleared": ops_cleared,
			"run_won": run_won,
			"tokens_earned": rewards.get("tokens_earned", 0),
			"planet_run": true,
			"planet_phase": RunState.get_planet_phase_name(),
			"legacy_biomass": RunState.legacy_biomass,
			"yesterdays_echoes": RunState.yesterdays_echoes,
			"imperial_rank": rank_data.get("rank", "Initiate"),
			"imperial_score": rank_data.get("score", 0),
			"evolution_tier": max_evo_tier,
			"evolution_summary": _collect_evolution_summary(),
		}
		if RunState.daily_seed_mode:
			var daily_stats: Dictionary = SaveManager.record_daily_run_end(
				ops_cleared,
				RunState.run_total_casualties,
				RunState.run_total_elapsed,
			)
			summary_meta["daily_run"] = true
			summary_meta["daily_stats"] = daily_stats
		RunState.end_run()
		get_tree().set_meta("run_summary", summary_meta)
		get_tree().change_scene_to_file("res://RunSummary.tscn")
		return
	if RunState.run_active:
		get_tree().change_scene_to_file("res://MissionDebrief.tscn")
	else:
		get_tree().change_scene_to_file("res://SquadSelection.tscn")

func log_message(message: String, color: String = "white", category: String = "all") -> void:
	RunLog.comms(message)
	var line := "[color=#%s]%s[/color]" % [color, message]
	var trimmed := false
	_comms_entries.append({"line": line, "category": category})
	while _comms_entries.size() > MAX_COMMS_LINES:
		_comms_entries.pop_front()
		trimmed = true
	if trimmed:
		_comms_force_rebuild = true
	_comms_dirty = true


func log_order_message(message: String, color: String = "white") -> void:
	log_message(message, color, "order")
	_comms_dirty = false
	_refresh_comms_display()


func _refresh_comms_display() -> void:
	if not comms_log:
		return
	if _comms_force_rebuild:
		_comms_force_rebuild = false
		_comms_rendered_count = 0
		comms_log.clear()
	var lines: PackedStringArray = PackedStringArray()
	if _comms_rendered_count == 0:
		for entry in _comms_entries:
			var cat: String = str(entry.get("category", "all"))
			if _comms_entry_visible(cat):
				lines.append(str(entry.get("line", "")))
		comms_log.text = "\n".join(lines)
		_comms_rendered_count = _comms_entries.size()
	else:
		while _comms_rendered_count < _comms_entries.size():
			var entry: Dictionary = _comms_entries[_comms_rendered_count]
			var cat: String = str(entry.get("category", "all"))
			if _comms_entry_visible(cat):
				comms_log.append_text(str(entry.get("line", "")) + "\n")
			_comms_rendered_count += 1
	GameTheme.scroll_to_bottom(comms_scroll)

func _refresh_roster() -> void:
	if not squad_roster or not game_active:
		return
	squad_roster.ensure_roster(active_units, squads_manager, rooms, active_hives)
	squad_roster.refresh(_selected_indices())

func _selected_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(active_units.size()):
		if active_units[i].is_alive and active_units[i].is_selected:
			indices.append(i)
	return indices

func _set_pending_order(order: OrderTypeLib.Type, save_preference: bool = true) -> void:
	pending_order = order
	order_move_btn.button_pressed = order == OrderTypeLib.Type.MOVE
	order_clear_btn.button_pressed = order == OrderTypeLib.Type.CLEAR
	order_search_btn.button_pressed = order == OrderTypeLib.Type.SEARCH_DESTROY
	order_defend_btn.button_pressed = order == OrderTypeLib.Type.DEFEND
	order_explore_btn.button_pressed = order == OrderTypeLib.Type.EXPLORE
	order_extract_btn.button_pressed = order == OrderTypeLib.Type.EXTRACT
	order_objective_btn.button_pressed = order == OrderTypeLib.Type.OBJECTIVE
	if save_preference:
		for unit in _get_selected_units():
			unit.preferred_order = order
	log_message("Order mode: %s" % OrderTypeLib.get_label(order), GameTheme.ACCENT.to_html())

func _apply_order_mode_from_unit(unit: SoldierUnit) -> void:
	if not unit:
		return
	_set_pending_order(unit.preferred_order, false)

func _on_search_destroy_pressed() -> void:
	_set_pending_order(OrderTypeLib.Type.SEARCH_DESTROY)
	if not game_active or mission_complete:
		return
	var units := _get_selected_units()
	if units.is_empty():
		units = squads_manager.get_squad_units(_selected_squad_id)
	if units.is_empty():
		log_message("Select a squad (F1-F3), then press S for coordinated Search & Destroy.", GameTheme.ACCENT_WARN.to_html(), "alert")
		return
	_issue_squad_search_destroy(units, null)
	_update_hud()

func _get_unexplored_rooms() -> Array[Room]:
	return rooms.filter(func(r): return not r.is_spawn_room and not r.is_searched)

func _on_explore_pressed() -> void:
	_set_pending_order(OrderTypeLib.Type.EXPLORE)
	if not game_active or mission_complete:
		return
	var unexplored := _get_unexplored_rooms()
	if unexplored.is_empty():
		log_message("All sectors explored.", GameTheme.TEXT_MUTED.to_html())
		return
	var units := _get_selected_units()
	if units.is_empty():
		log_message("Select operators, then press Explore [X] to sweep uncharted sectors.", GameTheme.ACCENT_WARN.to_html())
		return
	for unit in units:
		if unit.is_extracted:
			continue
		_activate_explore(unit)
	_update_hud()

func _activate_explore(unit: SoldierUnit) -> void:
	var remaining := _get_unexplored_rooms().size()
	unit.issue_order(OrderTypeLib.Type.EXPLORE, unit.position, null)
	log_message(
		"%s → Explore: checking %d uncharted sector(s)." % [unit.soldier_name, remaining],
		"white"
	)

func _issue_squad_search_destroy(units: Array, start_room: Room = null) -> void:
	if not _any_living_enemies():
		log_message("No hostile contacts remain on deck.", GameTheme.TEXT_MUTED.to_html(), "objective")
		return
	var queue: Array = task_board.build_snd_queue(units, rooms, start_room, _selected_squad_id)
	var partitions: Dictionary = task_board.partition_rooms(queue, units)
	for unit in units:
		if not unit is SoldierUnit or unit.is_extracted:
			continue
		var assigned: Array = partitions.get(unit, [])
		if assigned.is_empty():
			_activate_search_destroy(unit, start_room)
			continue
		unit.issue_order(OrderTypeLib.Type.SEARCH_DESTROY, unit.position, assigned[0])
		log_message(
			"%s → S&D: %s" % [unit.soldier_name, assigned[0].room_name if assigned[0] is Room else "purge"],
			"white",
			"combat",
		)
	squads_manager.set_doctrine(_selected_squad_id, OrderTypeLib.Type.SEARCH_DESTROY)


func _issue_squad_objective(units: Array, start_room: Room = null) -> void:
	var doctrine := SquadsManagerLib.doctrine_for_objective(get_objective_template())
	squads_manager.set_doctrine(_selected_squad_id, OrderTypeLib.Type.OBJECTIVE)
	for unit in units:
		if not unit is SoldierUnit or unit.is_extracted:
			continue
		unit.issue_order(OrderTypeLib.Type.OBJECTIVE, unit.position, start_room)
	log_message(
		"%s → Objective [%s]: auto %s" % [
			GameTheme.squad_label(_selected_squad_id),
			get_objective_template(),
			OrderTypeLib.get_label(doctrine),
		],
		GameTheme.ACCENT.to_html(),
		"objective",
	)


func _on_objective_pressed() -> void:
	_set_pending_order(OrderTypeLib.Type.OBJECTIVE)
	if not game_active or mission_complete:
		return
	var units := squads_manager.get_squad_units(_selected_squad_id)
	if units.is_empty():
		units = _get_selected_units()
	if units.is_empty():
		log_message("Select a squad (F1-F3), then press O for Objective doctrine.", GameTheme.ACCENT_WARN.to_html(), "alert")
		return
	_issue_squad_objective(units, null)
	_update_hud()


func _activate_search_destroy(unit: SoldierUnit, start_room: Room = null) -> void:
	if not _any_living_enemies():
		log_message("No hostile contacts remain on deck.", GameTheme.TEXT_MUTED.to_html(), "objective")
		return
	var start_pos: Vector2 = start_room.position if start_room else unit.position
	unit.issue_order(OrderTypeLib.Type.SEARCH_DESTROY, start_pos, start_room)
	if start_room:
		log_message("%s → Search & Destroy: autonomous purge from %s." % [unit.soldier_name, start_room.room_name], "white", "combat")
	else:
		log_message("%s → Search & Destroy: purging deck until all hostiles eliminated." % unit.soldier_name, "white", "combat")


func _any_living_enemies() -> bool:
	for enemy in active_enemies:
		if enemy.is_alive:
			return true
	return false

func _select_squad(squad_id: String) -> void:
	_clear_order_target_highlight()
	_selected_squad_id = squad_id
	RunState.active_squad_id = squad_id
	var first_index := -1
	for unit in active_units:
		unit.set_navigation_path_visible(false)
	for i in range(active_units.size()):
		var unit := active_units[i]
		var selected := unit.is_alive and unit.squad_id == squad_id
		unit.set_selected(selected)
		if selected and first_index < 0:
			first_index = i
	selected_unit_index = first_index
	if first_index >= 0:
		_apply_order_mode_from_unit(active_units[first_index])
	log_message("Selected squad %s." % GameTheme.squad_label(squad_id), GameTheme.squad_color(squad_id).to_html(), "squad")
	_update_hud()
	_refresh_roster()
	if game_active and squads_manager.get_living_count(squad_id) > 0:
		_follow_squad(squad_id, false)


func _follow_squad(squad_id: String, allow_toggle: bool = true) -> void:
	if allow_toggle and _camera_follow_squad_id == squad_id:
		_clear_camera_follow()
		return
	if not squads_manager or squads_manager.get_living_count(squad_id) <= 0:
		if game_active:
			log_message("%s has no active operators to follow." % GameTheme.squad_label(squad_id), GameTheme.TEXT_MUTED.to_html())
		return
	_camera_follow_squad_id = squad_id
	_update_camera_follow_buttons()
	RunLog.debug("Camera follow %s" % squad_id)
	if allow_toggle:
		log_message("Camera following %s [F1-F3]." % GameTheme.squad_label(squad_id), GameTheme.squad_color(squad_id).to_html())


func _clear_camera_follow() -> void:
	if _camera_follow_squad_id.is_empty():
		return
	_camera_follow_squad_id = ""
	_update_camera_follow_buttons()
	RunLog.debug("Camera follow cleared (manual pan)")


func _update_camera_follow(delta: float) -> void:
	if _camera_follow_squad_id.is_empty() or not map_camera or not squads_manager:
		return
	if squads_manager.get_living_count(_camera_follow_squad_id) <= 0:
		_clear_camera_follow()
		return
	var target := squads_manager.get_squad_center(_camera_follow_squad_id)
	if target == Vector2.ZERO:
		return
	map_camera.position = map_camera.position.lerp(target, clampf(CAMERA_FOLLOW_LERP * delta * 60.0, 0.0, 1.0))


func _update_camera_follow_buttons() -> void:
	for squad_id in _camera_follow_buttons.keys():
		var btn: Button = _camera_follow_buttons[squad_id]
		if not btn:
			continue
		var following: bool = _camera_follow_squad_id == squad_id
		btn.button_pressed = following
		btn.modulate = Color(1.15, 1.15, 1.15) if following else Color.WHITE


func _on_squad_header_pressed(squad_id: String) -> void:
	_select_squad(squad_id)
	if squad_roster:
		squad_roster.bind_units(active_units, squads_manager, rooms, active_hives)


func _select_unit(index: int) -> void:
	_clear_order_target_highlight()
	if index < 0 or index >= active_units.size() or not active_units[index].is_alive:
		for unit in active_units:
			unit.set_selected(false)
		selected_unit_index = -1
		if game_active and index >= 0 and index < RunState.ROSTER_SIZE:
			log_message("No operator in slot %d." % (index + 1), GameTheme.TEXT_MUTED.to_html())
		_update_hud()
		return
	selected_unit_index = index
	_selected_squad_id = active_units[index].squad_id
	for i in range(active_units.size()):
		active_units[i].set_selected(i == selected_unit_index and active_units[i].is_alive)
	_apply_order_mode_from_unit(active_units[index])
	_update_hud()
	_refresh_roster()


func _select_all_units() -> void:
	if not game_active or mission_complete:
		return
	var selected_count := 0
	for unit in active_units:
		unit.set_navigation_path_visible(false)
		var now_selected := unit.is_alive
		unit.set_selected(now_selected)
		if now_selected:
			selected_count += 1
	if selected_count == 0:
		selected_unit_index = -1
		log_message("No active operators to select.", GameTheme.TEXT_MUTED.to_html())
		_update_hud()
		return
	selected_unit_index = active_units.find(_get_selected_units()[0])
	_apply_order_mode_from_unit(_get_selected_units()[0])
	log_message("Selected all operators (%d)." % selected_count)
	_update_hud()
	_refresh_roster()

func _get_selected_units() -> Array[SoldierUnit]:
	var units: Array[SoldierUnit] = []
	for unit in active_units:
		if unit.is_alive and unit.is_selected:
			units.append(unit)
	return units

func _selected_unit() -> SoldierUnit:
	var units := _get_selected_units()
	if not units.is_empty():
		return units[0]
	if selected_unit_index >= 0 and selected_unit_index < active_units.size():
		var unit := active_units[selected_unit_index]
		if unit.is_alive:
			return unit
	return null

func _on_unit_clicked(unit: SoldierUnit) -> void:
	var index := active_units.find(unit)
	if index >= 0:
		_select_unit(index)

func _issue_order_to_selected(room: Room) -> void:
	_clear_order_target_highlight()
	var frame := Engine.get_process_frames()
	if frame == _last_order_frame and _last_order_room == room:
		return
	_last_order_frame = frame
	_last_order_room = room
	var units := _get_selected_units()
	if units.is_empty():
		units = squads_manager.get_squad_units(_selected_squad_id)
	if units.is_empty():
		log_message("Select a squad (F1-F3) or operator first.", GameTheme.ACCENT_WARN.to_html(), "alert")
		return
	if not game_active:
		log_message("Start the mission before issuing orders.", GameTheme.ACCENT_WARN.to_html())
		return
	if not room.is_revealed:
		log_message("Sector uncharted — advance to reveal.", GameTheme.TEXT_MUTED.to_html())
		return
	var order := pending_order
	if room.is_extraction_room:
		if not _objectives_cleared():
			log_message("Secure all objectives before extraction.", GameTheme.ACCENT_WARN.to_html())
			return
		order = OrderTypeLib.Type.EXTRACT
	elif order == OrderTypeLib.Type.EXTRACT and not room.is_extraction_room:
		log_message("Extract order only valid at the evacuation zone.", GameTheme.ACCENT_WARN.to_html())
		return
	if order == OrderTypeLib.Type.CLEAR and not room.requires_clear and not room.has_living_enemies():
		log_message("No hostiles reported in %s." % room.room_name, GameTheme.TEXT_MUTED.to_html())
		return
	if order == OrderTypeLib.Type.SEARCH_DESTROY:
		_issue_squad_search_destroy(units, room)
		log_order_message(
			CommsTemplatesLib.order_accepted(
				GameTheme.squad_label(_selected_squad_id),
				OrderTypeLib.get_label(OrderTypeLib.Type.SEARCH_DESTROY),
				room.room_name,
			),
			GameTheme.ACCENT.to_html(),
		)
		_update_hud()
		return
	if order == OrderTypeLib.Type.OBJECTIVE:
		_issue_squad_objective(units, room)
		_update_hud()
		return
	if order == OrderTypeLib.Type.EXPLORE:
		for unit in units:
			if unit.is_extracted:
				continue
			_activate_explore(unit)
		_update_hud()
		return
	if order == OrderTypeLib.Type.CLEAR:
		_show_clear_hint_if_needed()
	var squad_label := GameTheme.squad_label(_selected_squad_id)
	var order_name := OrderTypeLib.get_label(order)
	for unit in units:
		if unit.is_extracted:
			continue
		unit.issue_order(order, room.position, room)
	log_order_message(
		CommsTemplatesLib.order_accepted(squad_label, order_name, room.room_name),
		GameTheme.ACCENT.to_html(),
	)
	CombatAudioLib.play_order_issued(self)
	_update_hud()


func _on_unit_order_path_failed(unit: SoldierUnit, room: Room) -> void:
	if not room:
		return
	log_order_message(
		CommsTemplatesLib.order_no_route(GameTheme.squad_label(unit.squad_id), room.room_name),
		GameTheme.ACCENT_WARN.to_html(),
	)

func _on_ability_pressed() -> void:
	if not game_active or mission_complete:
		return
	var unit := _selected_unit()
	if not unit or not unit.is_alive:
		return
	if unit.use_ability(_alive_units()):
		var detail := unit.last_ability_detail
		if detail.is_empty():
			log_message("%s used %s." % [unit.soldier_name, unit.ability_name], GameTheme.ACCENT.to_html())
		else:
			log_message("%s — %s: %s" % [unit.soldier_name, unit.ability_name, detail], GameTheme.ACCENT.to_html())
		_update_hud()
	else:
		var reason := unit.last_ability_detail
		if reason.is_empty():
			log_message("%s ability not ready or no valid target." % unit.soldier_name, GameTheme.TEXT_MUTED.to_html())
		else:
			log_message("%s — %s (%s)" % [unit.soldier_name, unit.ability_name, reason], GameTheme.TEXT_MUTED.to_html())

func _update_objectives() -> void:
	var required := _get_required_rooms()
	var cleared_count := required.filter(func(r): return r.is_cleared).size()
	var primary_text := ""
	if map_data and map_data.objective_template == "hold_purge" and _hold_room:
		if _hold_complete:
			primary_text = "Hold & Purge: %s secured — %d / %d zones clear" % [
				_hold_room.room_name,
				cleared_count,
				required.size(),
			]
		elif _hold_active:
			var hold_note := "operators present" if not _hold_room.soldiers_inside.is_empty() else "no operators in sector"
			primary_text = "Hold & Purge: %s — %.0fs remaining (%s)" % [
				_hold_room.room_name,
				_hold_timer,
				hold_note,
			]
		else:
			primary_text = "Hold & Purge: secure %s, then hold position — %d / %d" % [
				_hold_room.room_name,
				cleared_count,
				required.size(),
			]
	elif map_data and map_data.objective_template == "black_site":
		primary_text = "Black Site: terminals %d / %d  |  zones %d / %d" % [
			_intel_terminals_destroyed,
			maxi(_intel_terminals_total, 1),
			cleared_count,
			required.size(),
		]
	elif map_data and map_data.objective_template == "vip_recovery":
		var vip_status := "missing"
		if _vip_escort and _vip_escort.is_alive:
			vip_status = "at evac" if _vip_escort.is_at_extraction else "with squad"
		primary_text = "VIP Recovery: %s — zones %d / %d" % [vip_status, cleared_count, required.size()]
	elif map_data and map_data.objective_template == "hive_purge":
		primary_text = "Hive Purge: hives %d / %d  |  zones %d / %d" % [
			_hives_destroyed,
			maxi(_hives_total, 1),
			cleared_count,
			required.size(),
		]
	elif _is_planet_mission():
		var phase_name := RunState.get_planet_phase_name()
		primary_text = "[%s] Nests %d / %d  |  zones %d / %d" % [
			phase_name,
			_regular_hives_destroyed,
			maxi(_regular_hives_total, 1),
			cleared_count,
			required.size(),
		]
		if RunState.planet_phase == RunState.PlanetPhase.QUEEN and not RunState.overmind_destroyed:
			primary_text += "  |  OVERMIND ACTIVE"
		elif RunState.extract_window_open:
			primary_text += "  |  EVAC OPEN"
	else:
		primary_text = "Primary: Clear hostile zones — %d / %d" % [cleared_count, required.size()]
	var extraction_text := _get_extraction_status_text()
	if _objectives_cleared():
		primary_text += "  |  COMPLETE"
		if primary_objective_label:
			primary_objective_label.modulate = GameTheme.ACCENT_SUCCESS
	else:
		primary_text += "  |  IN PROGRESS"
		if primary_objective_label:
			primary_objective_label.modulate = Color.WHITE
	if primary_objective_label:
		primary_objective_label.text = primary_text
	if extraction_status_label:
		extraction_status_label.text = extraction_text
		var banner_alive := _alive_units()
		if _objectives_cleared():
			var banner_evac := _get_extraction_room()
			if banner_evac and banner_evac.is_revealed:
				var banner_extracted := banner_alive.filter(func(u): return u.is_extracted).size()
				if banner_alive.size() > 0 and banner_extracted >= banner_alive.size():
					extraction_status_label.modulate = GameTheme.ACCENT_SUCCESS
				else:
					extraction_status_label.modulate = GameTheme.ACCENT
			else:
				extraction_status_label.modulate = GameTheme.ACCENT_WARN
		else:
			extraction_status_label.modulate = GameTheme.TEXT_MUTED
	objective_label.text = "%s\n%s" % [primary_text, extraction_text]
	if mission_banner:
		mission_banner.visible = game_active and not mission_complete

func _get_extraction_status_text() -> String:
	if not game_active:
		return "Evac: Standby"
	var alive_ops := _alive_units()
	var evac_room := _get_extraction_room()
	if _is_planet_mission() and RunState.overmind_destroyed and RunState.extract_window_open:
		var base := "Evac: Open — reach %s" % [evac_room.room_name if evac_room else "extract zone"]
		if alive_ops.is_empty():
			return base
		var extracted_planet := alive_ops.filter(func(u): return u.is_extracted).size()
		return "%s (%d / %d extracted)" % [base, extracted_planet, alive_ops.size()]
	if not _objectives_cleared():
		return "Evac: Locked until objectives are complete"
	if not evac_room or not evac_room.is_revealed:
		return "Evac: Zone unknown — explore to locate"
	if alive_ops.is_empty():
		return "Evac: %s — no operators remaining" % evac_room.room_name
	var extracted_count := alive_ops.filter(func(u): return u.is_extracted).size()
	if extracted_count >= alive_ops.size():
		return "Evac: %s — all operators extracted" % evac_room.room_name
	var extracting_count := alive_ops.filter(func(u): return u.is_extracting).size()
	var status := "Evac: %s — %d / %d extracted" % [evac_room.room_name, extracted_count, alive_ops.size()]
	if extracting_count > 0:
		status += " (%d extracting)" % extracting_count
	return status

func _on_extract_pressed() -> void:
	_set_pending_order(OrderTypeLib.Type.EXTRACT)
	if not game_active or mission_complete:
		return
	if not _objectives_cleared():
		log_message("Secure all objectives before extraction.", GameTheme.ACCENT_WARN.to_html())
		return
	_show_extract_hint_if_needed()
	var extraction := _get_extraction_room()
	if not extraction:
		log_message("No evacuation zone on this deck.", GameTheme.ACCENT_WARN.to_html())
		return
	if not extraction.is_revealed:
		log_message("Evacuation zone not located. Explore the facility first.", GameTheme.ACCENT_WARN.to_html())
		return
	var units := _get_selected_units()
	if units.is_empty():
		log_message("Select operators, then press Extract [E] to evacuate.", GameTheme.ACCENT_WARN.to_html())
		return
	for unit in units:
		if unit.is_extracted:
			continue
		unit.issue_order(OrderTypeLib.Type.EXTRACT, extraction.position, extraction)
		log_message("%s → Extract: %s" % [unit.soldier_name, extraction.room_name], "white")
	CombatAudioLib.play_extract_channel(self)
	_update_hud()

func _update_hud() -> void:
	pause_label.visible = sector_overlay_open and game_active and _is_planet_mission()
	pause_label.text = "SECTOR OVERLAY — SPACE to close" if sector_overlay_open else "REAL-TIME — SPACE for sector overlay"
	select_all_btn.disabled = not game_active or mission_complete or spawn_selection_active or _alive_units().is_empty()
	var explore_locked := not game_active or mission_complete or spawn_selection_active or _get_unexplored_rooms().is_empty()
	order_explore_btn.disabled = explore_locked
	order_explore_btn.tooltip_text = "No uncharted sectors remain." if _get_unexplored_rooms().is_empty() else "Sweep uncharted sectors [X]"
	var extract_locked := not game_active or mission_complete or spawn_selection_active or not _objectives_cleared()
	var extraction := _get_extraction_room()
	if extraction and _evac_search_gate > 0 and _searched_room_count < _evac_search_gate:
		extract_locked = true
	if extraction and not extraction.is_revealed:
		extract_locked = true
	order_extract_btn.disabled = extract_locked
	order_objective_btn.disabled = not game_active or mission_complete or spawn_selection_active
	if not _objectives_cleared():
		order_extract_btn.tooltip_text = "Secure all objectives before extraction."
	elif extraction and not extraction.is_revealed:
		order_extract_btn.tooltip_text = "Locate the evacuation zone first."
	elif _evac_search_gate > 0 and _searched_room_count < _evac_search_gate:
		order_extract_btn.tooltip_text = "Silent op: search 2 sectors before evac unlocks."
	else:
		order_extract_btn.tooltip_text = "Order selected operators to evacuate [E]"
	var units := _get_selected_units()
	var unit := _selected_unit()
	var squad_units := squads_manager.get_squad_units(_selected_squad_id) if squads_manager else []
	var show_commander := squad_units.size() >= 2 and (units.size() >= 2 or units.is_empty())
	if show_commander:
		var hp_pct := squads_manager.aggregate_hp_percent(_selected_squad_id) * 100.0
		unit_name_label.text = "Squad %s" % GameTheme.squad_label(_selected_squad_id)
		unit_class_label.text = "%s — %s" % [
			squads_manager.squad_status(_selected_squad_id),
			OrderTypeLib.get_label(squads_manager.get_doctrine(_selected_squad_id)),
		]
		unit_health_label.text = "Aggregate HP %.0f%% · %d operators" % [hp_pct, squad_units.size()]
		unit_order_label.text = "Doctrine: %s · [O] Objective · F1-F3 select" % OrderTypeLib.get_label(pending_order)
		ability_button.text = "Squad command"
		ability_button.disabled = true
	elif units.size() > 1:
		unit_name_label.text = "%d operators selected" % units.size()
		unit_class_label.text = "Multi-select active"
		unit_health_label.text = "—"
		unit_order_label.text = "Pending: %s" % OrderTypeLib.get_label(pending_order)
		ability_button.text = "Ability: —"
		ability_button.disabled = true
	elif unit and unit.is_alive:
		unit_name_label.text = unit.soldier_name
		unit_class_label.text = GameTheme.class_name_text(unit.marine_class)
		unit_health_label.text = "HP %d / %d · DEF %d" % [unit.current_health, unit.max_health, unit.defense]
		unit_order_label.text = "Status: %s · Default: %s" % [
			unit.get_trust_status(),
			OrderTypeLib.get_label(unit.preferred_order),
		]
		ability_button.text = "Ability: %s" % unit.ability_name
		var ability_ready := unit.ability_timer <= 0.0 and game_active
		ability_button.disabled = not ability_ready
		if ability_ready:
			ability_button.text += " ✓ READY"
			ability_button.modulate = GameTheme.ACCENT_SUCCESS
		else:
			ability_button.modulate = Color.WHITE
			if unit.ability_timer > 0.0:
				ability_button.text += " (%.0fs)" % unit.ability_timer
		if unit.source_resource and unit.source_resource.is_injured:
			unit_health_label.text += " · INJURED"
	else:
		unit_name_label.text = "No unit selected"
		unit_class_label.text = "—"
		unit_health_label.text = "—"
		unit_order_label.text = "—"
		ability_button.disabled = true
	_apply_command_mode_ui()
	_update_navigation_path_preview(unit, units)
	squad_roster.refresh(_selected_indices())


func _update_navigation_path_preview(primary_unit: SoldierUnit, selected_units: Array) -> void:
	for active_unit in active_units:
		if not is_instance_valid(active_unit):
			continue
		active_unit.set_navigation_path_visible(false)
	# Only one operator selected (not whole squad / select-all).
	if primary_unit and selected_units.size() == 1 and primary_unit.is_alive:
		if primary_unit.current_order != OrderTypeLib.Type.NONE and primary_unit.is_moving:
			primary_unit.set_navigation_path_visible(true)

func _apply_command_mode_ui() -> void:
	var engaged := false
	if squads_manager:
		for squad_id in SquadsManagerLib.SQUAD_IDS:
			if squads_manager.squad_status(squad_id) == "ENGAGED":
				engaged = true
				break
	var assault := Color(1.15, 1.1, 0.85)
	var transit := Color(0.72, 0.75, 0.82)
	order_clear_btn.modulate = assault if engaged else Color.WHITE
	order_search_btn.modulate = assault if engaged else Color.WHITE
	order_defend_btn.modulate = assault if engaged else Color.WHITE
	order_move_btn.modulate = transit if engaged else Color.WHITE
	order_explore_btn.modulate = transit if engaged else Color.WHITE
	order_objective_btn.modulate = transit if engaged else Color.WHITE
	order_extract_btn.modulate = Color.WHITE

func _on_back_pressed() -> void:
	CombatAudioLib.play_ui_click(self)
	if RunState.run_active:
		if _is_planet_mission():
			get_tree().change_scene_to_file("res://MainMenu.tscn")
		else:
			get_tree().change_scene_to_file("res://BetweenMissionHub.tscn")
	else:
		get_tree().change_scene_to_file("res://MainMenu.tscn")


func _is_planet_mission() -> bool:
	return planet_mode or (RunState.run_active and RunState.planet_mode)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_sector_overlay()
		get_viewport().set_input_as_handled()
		return
	if spawn_selection_active or not game_active or mission_complete:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_unit(0)
			KEY_2:
				_select_unit(1)
			KEY_3:
				_select_unit(2)
			KEY_4:
				_select_unit(3)
			KEY_F1:
				_select_squad("alpha")
			KEY_F2:
				_select_squad("bravo")
			KEY_F3:
				_select_squad("charlie")
			KEY_M:
				_set_pending_order(OrderTypeLib.Type.MOVE)
			KEY_C:
				_set_pending_order(OrderTypeLib.Type.CLEAR)
			KEY_S:
				_on_search_destroy_pressed()
			KEY_O:
				_on_objective_pressed()
			KEY_X:
				_on_explore_pressed()
			KEY_D:
				_set_pending_order(OrderTypeLib.Type.DEFEND)
			KEY_E:
				_on_extract_pressed()
			KEY_A:
				_select_all_units()
			KEY_R:
				_on_ability_pressed()
			KEY_SLASH, KEY_QUESTION:
				if controls_overlay:
					controls_overlay.toggle()
		get_viewport().set_input_as_handled()

func _is_pointer_over_ui(screen_pos: Vector2) -> bool:
	if controls_overlay and controls_overlay.visible and controls_overlay.get_global_rect().has_point(screen_pos):
		return true
	return (
		$LeftPanel.get_global_rect().has_point(screen_pos)
		or $HUD.get_global_rect().has_point(screen_pos)
		or $QuitButton.get_global_rect().has_point(screen_pos)
		or $Title.get_global_rect().has_point(screen_pos)
	)

func toggle_sector_overlay() -> void:
	if not game_active or mission_complete:
		return
	sector_overlay_open = !sector_overlay_open
	if sector_panel:
		sector_panel.visible = sector_overlay_open and _is_planet_mission()
	if sector_overlay_open:
		log_message("Sector overlay open — assign sectors and doctrines.", GameTheme.ACCENT.to_html(), "objective")
	else:
		log_message("Sector overlay closed.", GameTheme.TEXT_MUTED.to_html())
	_update_hud()

func _get_room_at_position(local_pos: Vector2) -> Room:
	var best_room: Room = null
	var best_depth := -INF
	for room in rooms:
		if room.contains_local_point(local_pos):
			if room.z_index >= best_depth:
				best_depth = room.z_index
				best_room = room
	return best_room

func _tick_hives(delta: float) -> void:
	var living_hives: Array = []
	for hive in active_hives:
		if hive == null or not is_instance_valid(hive):
			continue
		if hive.get("is_destroyed") and hive.is_destroyed:
			continue
		living_hives.append(hive)
		if hive.has_method("tick_focus_mark"):
			hive.tick_focus_mark(delta)
		if hive.state == Hive.State.DORMANT and hive.has_method("tick_dormant_activation"):
			hive.tick_dormant_activation()
		elif hive.state == Hive.State.ACTIVE and hive.has_method("tick_active"):
			hive.tick_active(delta)
	active_hives = living_hives


func despawn_enemy(enemy: EnemyUnit) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	active_enemies.erase(enemy)
	if enemy.is_alive:
		enemy.take_damage(enemy.max_health)
	elif enemy.home_room and entity_index:
		entity_index.unregister_enemy(enemy, enemy.home_room)
	if is_instance_valid(enemy):
		enemy.queue_free()


func _update_fog_of_war() -> void:
	var fog_start := Time.get_ticks_usec()
	if entity_index:
		entity_index.prune_stale_entries()
	LineOfSightLib.begin_frame_cache()
	var door_nodes: Array[Node2D] = doors
	var fog_scale: float = 1.0
	if RunState.active_modifier and RunState.active_modifier.fog_reveal_mult != 1.0:
		fog_scale = RunState.active_modifier.fog_reveal_mult
	var soldiers := _alive_units()
	var rooms_to_check: Array = rooms
	if entity_index and not entity_index.revealed_rooms.is_empty():
		rooms_to_check = entity_index.rooms_for_fog_update(rooms)
	var frontier_dirty := entity_index.fog_reveal_rooms(
		soldiers,
		rooms_to_check,
		rooms,
		door_nodes,
		fog_scale,
		func(room: Room) -> bool:
			return room.is_extraction_room and _evac_search_gate > 0 and _searched_room_count < _evac_search_gate,
		func(room: Room) -> bool:
			return _reveal_and_search(room),
		func(soldier_pos: Vector2, room: Room) -> bool:
			return LineOfSightLib.can_reveal_room(soldier_pos, room, rooms, door_nodes),
		func(room: Room) -> void:
			_on_extraction_room_discovered(room)
	)
	if frontier_dirty:
		entity_index.rebuild_frontier(rooms, _rooms_are_adjacent)
		_minimap_dirty = true
	var fog_enemies: Array = entity_index.get_enemies_for_fog_check(soldiers, FOG_LOS_RANGE)
	entity_index.fog_update_enemy_visibility(
		soldiers,
		fog_enemies,
		rooms,
		door_nodes,
		FOG_LOS_RANGE,
		func(from_pos: Vector2, to_pos: Vector2) -> bool:
			return LineOfSightLib.has_line_of_sight(from_pos, to_pos, rooms, door_nodes),
		func(enemy: EnemyUnit) -> void:
			_report_enemy_contact(enemy),
		func(enemy: EnemyUnit) -> void:
			_note_enemy_lost(enemy)
	)
	_last_fog_ms = float(Time.get_ticks_usec() - fog_start) / 1000.0

func _on_extraction_room_discovered(room: Room) -> void:
	if not room.is_extraction_room:
		return
	if _evac_search_gate > 0 and _searched_room_count < _evac_search_gate:
		return
	if extraction_identified_shown:
		return
	extraction_identified_shown = true
	CombatAudioLib.play_extract_channel(self)
	log_message("Evac zone identified: %s." % room.room_name, GameTheme.ACCENT_SUCCESS.to_html())
	if _objectives_cleared():
		log_message("Press Extract [E] to order operators to the evac point.", GameTheme.ACCENT.to_html())
	_update_objectives()

func _track_room_searched(room: Room) -> void:
	if room.is_searched:
		return
	room.mark_searched()
	_searched_room_count += 1
	if room.get_meta("scavenge", false):
		var bonus := 10
		if RunState.active_modifier and RunState.active_modifier.scavenge_credit_mult != 1.0:
			bonus = int(bonus * RunState.active_modifier.scavenge_credit_mult)
		RunState.run_credits += bonus
		log_message("Scavenge cache recovered: +%d run credits." % bonus, "gold")
	if room.get_meta("loot_branch", false):
		var loot_bonus := 8
		if RunState.active_modifier and RunState.active_modifier.scavenge_credit_mult != 1.0:
			loot_bonus = int(loot_bonus * RunState.active_modifier.scavenge_credit_mult)
		RunState.run_credits += loot_bonus
		log_message("Dead-end cache recovered: +%d run credits." % loot_bonus, "gold")
	if _evac_search_gate > 0 and _searched_room_count >= _evac_search_gate:
		log_message("Intel uplink: evacuation zone coordinates unlocked.", GameTheme.ACCENT.to_html())

func _reveal_and_search(room: Room) -> bool:
	var newly_revealed := not room.is_revealed
	room.reveal()
	entity_index.mark_revealed(room)
	_track_room_searched(room)
	if room.is_extraction_room:
		_on_extraction_room_discovered(room)
	return newly_revealed

func _update_camera_pan(delta: float) -> void:
	if not map_camera or not sub_viewport_container:
		return
	if _is_pointer_over_ui(get_viewport().get_mouse_position()):
		return
	var mouse := sub_viewport_container.get_local_mouse_position()
	var container_size := sub_viewport_container.size
	if not sub_viewport_container.get_rect().has_point(mouse):
		return
	var pan := Vector2.ZERO
	if mouse.x < 24.0:
		pan.x -= 1.0
	elif mouse.x > container_size.x - 24.0:
		pan.x += 1.0
	if mouse.y < 24.0:
		pan.y -= 1.0
	elif mouse.y > container_size.y - 24.0:
		pan.y += 1.0
	if pan != Vector2.ZERO:
		_clear_camera_follow()
		map_camera.position += pan.normalized() * CAMERA_PAN_SPEED * delta / map_camera.zoom.x


func _get_camera_bounds() -> Rect2:
	if not map_data:
		return Rect2(Vector2(-512, -320), Vector2(1024, 640))
	var outline: PackedVector2Array = map_data.get_hull_outline()
	if outline.size() >= 4:
		var min_pos: Vector2 = outline[0]
		var max_pos: Vector2 = outline[2]
		return Rect2(min_pos, max_pos - min_pos)
	var half: Vector2 = map_data.map_size * 0.5
	return Rect2(-half, map_data.map_size)


func _clamp_camera_position() -> void:
	if not map_camera or not sub_viewport:
		return
	var bounds := _get_camera_bounds().grow(-CAMERA_BOUNDS_PADDING)
	if bounds.size.x <= 1.0 or bounds.size.y <= 1.0:
		return
	var zoom := map_camera.zoom.x
	var view_half := (Vector2(sub_viewport.size) / zoom) * 0.5
	var min_pos := bounds.position + view_half
	var max_pos := bounds.position + bounds.size - view_half
	if min_pos.x > max_pos.x:
		map_camera.position.x = bounds.get_center().x
	else:
		map_camera.position.x = clampf(map_camera.position.x, min_pos.x, max_pos.x)
	if min_pos.y > max_pos.y:
		map_camera.position.y = bounds.get_center().y
	else:
		map_camera.position.y = clampf(map_camera.position.y, min_pos.y, max_pos.y)


func _apply_camera_zoom(zoom_in: bool) -> void:
	if not map_camera:
		return
	if not sub_viewport_container.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	var factor := CAMERA_ZOOM_WHEEL_STEP if zoom_in else 1.0 / CAMERA_ZOOM_WHEEL_STEP
	var before := map_camera.zoom
	map_camera.zoom = (map_camera.zoom * factor).clamp(
		Vector2(CAMERA_ZOOM_MIN, CAMERA_ZOOM_MIN),
		Vector2(CAMERA_ZOOM_MAX, CAMERA_ZOOM_MAX)
	)
	if map_camera.zoom != before:
		RunLog.debug("Camera zoom %.0f%%" % (_get_zoom_percent()))
	_clamp_camera_position()
	_update_zoom_indicator()


func _get_zoom_percent() -> float:
	if _base_camera_zoom <= 0.0 or not map_camera:
		return 100.0
	return (map_camera.zoom.x / _base_camera_zoom) * 100.0


func _update_zoom_indicator() -> void:
	if not zoom_indicator_label:
		return
	zoom_indicator_label.text = "Zoom %d%%" % int(round(_get_zoom_percent()))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_camera_zoom(true)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_camera_zoom(false)


func _show_tutorial_hints() -> void:
	if not TutorialStateLib.has_seen(TutorialStateLib.FLAG_DEPLOY):
		log_message("Tip: Click a green secure room to pick your deploy site.", GameTheme.TEXT_MUTED.to_html())
		TutorialStateLib.mark_seen(TutorialStateLib.FLAG_DEPLOY)
	if not TutorialStateLib.has_seen(TutorialStateLib.FLAG_SECTOR_OVERLAY):
		log_message("Tip: SPACE opens sector overlay while combat continues.", GameTheme.TEXT_MUTED.to_html())
		TutorialStateLib.mark_seen(TutorialStateLib.FLAG_SECTOR_OVERLAY)
	if not TutorialStateLib.has_seen(TutorialStateLib.FLAG_EXPLORE):
		log_message("Tip: Explore [X] sends operators to sweep uncharted sectors.", GameTheme.TEXT_MUTED.to_html())
		TutorialStateLib.mark_seen(TutorialStateLib.FLAG_EXPLORE)


func _show_clear_hint_if_needed() -> void:
	if TutorialStateLib.has_seen(TutorialStateLib.FLAG_CLEAR):
		return
	log_message(
		"Tip: Clear [C] + click a room — operators move in and eliminate hostiles.",
		GameTheme.TEXT_MUTED.to_html()
	)
	TutorialStateLib.mark_seen(TutorialStateLib.FLAG_CLEAR)


func _show_extract_hint_if_needed() -> void:
	if TutorialStateLib.has_seen(TutorialStateLib.FLAG_EXTRACT):
		return
	log_message(
		"Tip: Extract [E] orders operators to the evacuation zone once objectives are complete.",
		GameTheme.TEXT_MUTED.to_html()
	)
	TutorialStateLib.mark_seen(TutorialStateLib.FLAG_EXTRACT)


func _start_hold_phase() -> void:
	if not _hold_room or _hold_complete:
		return
	_hold_active = true
	_hold_timer = _hold_duration
	_hold_wave_timer = HOLD_WAVE_INTERVAL * 0.5
	log_message(
		"Initial hostiles cleared — HOLD %s for %.0fs!" % [_hold_room.room_name, _hold_duration],
		GameTheme.ACCENT_WARN.to_html()
	)
	log_message("Reinforcement waves inbound. Keep operators in the sector.", GameTheme.ACCENT_DANGER.to_html())
	_spawn_hold_wave()
	_update_objectives()


func _update_hold_purge(delta: float) -> void:
	if not _hold_room or not _hold_active or _hold_complete:
		return
	if _hold_room.soldiers_inside.is_empty():
		_update_objectives()
		return
	_hold_timer = maxf(0.0, _hold_timer - delta)
	_hold_wave_timer -= delta
	if _hold_wave_timer <= 0.0:
		_spawn_hold_wave()
		_hold_wave_timer = HOLD_WAVE_INTERVAL
	if _hold_timer <= 0.0 and not _hold_room.has_living_enemies():
		_complete_hold_purge()
	_update_objectives()


func _complete_hold_purge() -> void:
	if _hold_complete:
		return
	_hold_active = false
	_hold_complete = true
	if _hold_room:
		_hold_room.is_cleared = true
		_hold_room._refresh_status()
		_rooms_cleared_count += 1
		CombatAudioLib.play_room_secured(self)
		log_message("%s purge complete — position held." % _hold_room.room_name, GameTheme.ACCENT_SUCCESS.to_html())
	_update_objectives()
	_check_mission_status()


func _spawn_hold_wave() -> void:
	if not _hold_room or not _hold_active:
		return
	var op_depth: int = RunState.op_index if RunState.run_active else 1
	var stat_scale: float = float(_hold_room.get_meta("stat_scale", map_data.enemy_stat_scale if map_data else 1.0))
	var wave_size: int = 1 if op_depth <= 2 else 2
	for i in range(wave_size):
		var arch: Enemy.Kind = Enemy.pick_archetype_for_op(op_depth, _enemy_spawn_rng, false)
		var enemy_res := Enemy.create_archetype(arch, stat_scale, _next_spawn_enemy_id)
		_next_spawn_enemy_id += 1
		SaveManager.discover_enemy(Enemy.archetype_label(arch).to_lower())
		var enemy: EnemyUnit = ENEMY_SCENE.instantiate()
		enemy.setup_from_resource(enemy_res, _hold_room)
		enemy.bind_tactical_map(self)
		enemy.died.connect(_on_enemy_died)
		enemy.combat_hit.connect(_on_combat_hit)
		enemy.alarm_triggered.connect(_on_enemy_alarm_triggered)
		var offset := Vector2((float(i) - (float(wave_size - 1) * 0.5)) * 36.0, _hold_room.room_size.y * 0.12)
		enemy.position = _hold_room.position + offset
		world.add_child(enemy)
		_hold_room.register_enemy(enemy)
		active_enemies.append(enemy)
		entity_index.register_enemy(enemy, _hold_room)
	log_message("Reinforcements entering %s!" % _hold_room.room_name, GameTheme.ACCENT_DANGER.to_html())


func _order_supports_target_highlight() -> bool:
	return pending_order != OrderTypeLib.Type.NONE


func _clear_order_target_highlight() -> void:
	if _order_highlight_room:
		_order_highlight_room.set_order_target_highlight(false)
		_order_highlight_room = null


func _update_order_target_highlight(target_room: Room) -> void:
	if _order_highlight_room == target_room:
		return
	if _order_highlight_room:
		_order_highlight_room.set_order_target_highlight(false)
	_order_highlight_room = target_room
	if target_room:
		target_room.set_order_target_highlight(true)


func _room_containing_unit(unit: SoldierUnit) -> Room:
	for room in rooms:
		if room.contains_local_point(unit.position, 10.0):
			return room
	return null


func _room_containing_point(pos: Vector2) -> Room:
	for room in rooms:
		if room.contains_local_point(pos, 0.0):
			return room
	return null


func _enemy_room(enemy: EnemyUnit) -> Room:
	if enemy.home_room:
		return enemy.home_room
	return _room_containing_point(enemy.position)


func _enemy_archetype_label(enemy: EnemyUnit) -> String:
	return Enemy.archetype_label(enemy.enemy_archetype)


func _report_enemy_contact(enemy: EnemyUnit) -> void:
	if enemy.get_meta("contact_reported", false):
		return
	enemy.set_meta("contact_reported", true)
	var room := _enemy_room(enemy)
	if not room:
		return
	var arch_label := _enemy_archetype_label(enemy)
	room.mark_hostile_contact(arch_label)
	SaveManager.discover_enemy(arch_label.to_lower())
	CombatAudioLib.play_contact_ping(self)
	log_message(
		"VISUAL CONTACT — %s hostile in %s." % [arch_label, room.room_name],
		GameTheme.ACCENT_DANGER.to_html()
	)


func _note_enemy_lost(enemy: EnemyUnit) -> void:
	if not enemy.get_meta("contact_reported", false):
		return
	var room := _room_containing_point(enemy.position)
	if room:
		room.mark_hostile_contact(_enemy_archetype_label(enemy))


func _get_combat_room(attacker_name: String, target_name: String) -> Room:
	for enemy in active_enemies:
		if not enemy.is_alive:
			continue
		if enemy.enemy_name == attacker_name or enemy.enemy_name == target_name:
			var room := _room_containing_point(enemy.position)
			if room:
				return room
	for unit in active_units:
		if not unit.is_alive:
			continue
		if unit.soldier_name == attacker_name or unit.soldier_name == target_name:
			var room := _room_containing_point(unit.position)
			if room:
				return room
	for hive in active_hives:
		if not hive or hive.is_destroyed:
			continue
		if hive.hive_name == target_name:
			return hive.home_room
	return null


func _rooms_are_adjacent(room_a: Room, room_b: Room) -> bool:
	if not room_a or not room_b or room_a == room_b:
		return false
	if path_graph:
		var route: Array[String] = path_graph.find_room_route(room_a.map_room_id, room_b.map_room_id)
		return route.size() == 2
	return room_a.position.distance_to(room_b.position) <= 280.0


func _is_adjacent_to_revealed(room: Room) -> bool:
	for other in rooms:
		if other.is_revealed and _rooms_are_adjacent(other, room):
			return true
	return false


func _maybe_audio_threat_ping(attacker_name: String, target_name: String) -> void:
	var combat_room := _get_combat_room(attacker_name, target_name)
	if not combat_room or combat_room.is_revealed:
		return
	if not _is_adjacent_to_revealed(combat_room):
		return
	var room_key := combat_room.map_room_id
	if room_key.is_empty() or _threat_pinged_rooms.has(room_key):
		return
	_threat_pinged_rooms[room_key] = true
	combat_room.mark_hostile_contact("Unknown")
	CombatAudioLib.play_threat_ping(self)
	log_message(
		"Audio contact — gunfire in adjacent sector (%s)." % combat_room.room_name,
		GameTheme.ACCENT_WARN.to_html(),
		"alert",
	)


func _consolidate_mission_hud() -> void:
	var left_panel: PanelContainer = $LeftPanel
	var left_vbox: VBoxContainer = $LeftPanel/VBox
	var hud_vbox: VBoxContainer = $HUD/HudScroll/VBox
	left_panel.visible = false
	left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mission_hud_tabs = TabContainer.new()
	_mission_hud_tabs.name = "MissionTabs"
	_mission_hud_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mission_hud_tabs.custom_minimum_size = Vector2(0, 300)

	var squad_tab := VBoxContainer.new()
	squad_tab.name = "Squad"
	squad_tab.add_theme_constant_override("separation", 10)
	_mission_hud_tabs.add_child(squad_tab)
	_mission_hud_tabs.set_tab_title(0, "Squad")

	var comms_tab := VBoxContainer.new()
	comms_tab.name = "Comms"
	comms_tab.add_theme_constant_override("separation", 8)
	_mission_hud_tabs.add_child(comms_tab)
	_mission_hud_tabs.set_tab_title(1, "Comms")

	var roster_title: Node = left_vbox.get_node_or_null("RosterTitle")
	if roster_title:
		roster_title.queue_free()
	var log_title: Node = left_vbox.get_node_or_null("LogTitle")
	if log_title:
		log_title.queue_free()

	squad_roster.reparent(squad_tab)
	squad_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	squad_roster.custom_minimum_size = Vector2(0, 140)

	objective_label.reparent(squad_tab)
	squad_tab.move_child(objective_label, 0)
	$HUD/HudScroll/VBox/UnitPanel.reparent(squad_tab)
	select_all_btn.reparent(squad_tab)
	$HUD/HudScroll/VBox/OrderPanel.reparent(squad_tab)
	$HUD/HudScroll/VBox/HotkeyHint.reparent(squad_tab)
	ability_button.reparent(squad_tab)

	comms_scroll.reparent(comms_tab)
	comms_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comms_scroll.custom_minimum_size = Vector2(0, 200)
	if comms_log:
		comms_log.fit_content = false
		comms_log.scroll_active = true
	for label_node in [unit_name_label, unit_class_label, unit_health_label, unit_order_label, objective_label]:
		if label_node:
			label_node.clip_text = true
			label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var insert_idx := hud_vbox.get_child_count()
	for i in range(hud_vbox.get_child_count()):
		if hud_vbox.get_child(i) == start_button:
			insert_idx = i
			break
	hud_vbox.add_child(_mission_hud_tabs)
	hud_vbox.move_child(_mission_hud_tabs, insert_idx)


func _setup_commander_ui() -> void:
	var comms_tab: VBoxContainer = _mission_hud_tabs.get_node("Comms") as VBoxContainer
	comms_filter_row = HBoxContainer.new()
	comms_filter_row.name = "CommsFilterRow"
	for filter_id in ["priority", "all", "alerts", "combat", "objective"]:
		var btn := Button.new()
		btn.text = filter_id.capitalize()
		btn.toggle_mode = true
		btn.button_pressed = filter_id == "priority"
		btn.pressed.connect(_set_comms_filter.bind(filter_id, btn))
		comms_filter_row.add_child(btn)
	comms_tab.add_child(comms_filter_row)
	comms_tab.move_child(comms_filter_row, 0)

	var hud_vbox: VBoxContainer = $HUD/HudScroll/VBox
	camera_follow_row = HBoxContainer.new()
	camera_follow_row.name = "CameraFollowRow"
	var camera_title := Label.new()
	camera_title.text = "Follow"
	camera_title.add_theme_font_size_override("font_size", 12)
	camera_title.add_theme_color_override("font_color", GameTheme.TEXT_MUTED)
	camera_follow_row.add_child(camera_title)
	_camera_follow_buttons.clear()
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		var follow_btn := Button.new()
		follow_btn.text = "%s [F%d]" % [GameTheme.squad_label(squad_id), SquadsManagerLib.SQUAD_IDS.find(squad_id) + 1]
		follow_btn.toggle_mode = true
		follow_btn.tooltip_text = "Pan camera to %s squad center" % GameTheme.squad_label(squad_id)
		follow_btn.pressed.connect(_follow_squad.bind(squad_id, true))
		camera_follow_row.add_child(follow_btn)
		_camera_follow_buttons[squad_id] = follow_btn
	var squad_tab: VBoxContainer = _mission_hud_tabs.get_node("Squad") as VBoxContainer
	squad_tab.add_child(camera_follow_row)
	squad_tab.move_child(camera_follow_row, squad_tab.get_child_count() - 1)

	deploy_banner = PanelContainer.new()
	deploy_banner.name = "DeployBanner"
	deploy_banner.visible = false
	deploy_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	deploy_banner.offset_left = 12.0
	deploy_banner.offset_top = 86.0
	deploy_banner.offset_right = -12.0
	deploy_banner.offset_bottom = 132.0
	deploy_banner.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.08, 0.1, 0.14, 0.92), GameTheme.ACCENT, 8))
	deploy_banner_label = Label.new()
	deploy_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deploy_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deploy_banner_label.add_theme_font_size_override("font_size", 13)
	deploy_banner.add_child(deploy_banner_label)
	play_area.add_child(deploy_banner)

	zoom_indicator_label = Label.new()
	zoom_indicator_label.name = "ZoomIndicator"
	zoom_indicator_label.text = "Zoom 100%"
	zoom_indicator_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	zoom_indicator_label.offset_left = -120.0
	zoom_indicator_label.offset_top = -28.0
	zoom_indicator_label.offset_right = -8.0
	zoom_indicator_label.offset_bottom = -8.0
	zoom_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_indicator_label.add_theme_font_size_override("font_size", 11)
	zoom_indicator_label.add_theme_color_override("font_color", GameTheme.TEXT_MUTED)
	zoom_indicator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_area.add_child(zoom_indicator_label)

	minimap_panel = Control.new()
	minimap_panel.name = "MinimapPanel"
	minimap_panel.custom_minimum_size = Vector2(160, 120)
	minimap_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap_panel.offset_left = 12.0
	minimap_panel.offset_bottom = -12.0
	minimap_panel.offset_top = -132.0
	minimap_panel.offset_right = 172.0
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_area.add_child(minimap_panel)
	minimap_panel.draw.connect(_draw_minimap)

	extract_banner = PanelContainer.new()
	extract_banner.name = "ExtractBanner"
	extract_banner.visible = false
	extract_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	extract_banner.offset_left = 180.0
	extract_banner.offset_top = 8.0
	extract_banner.offset_right = -180.0
	extract_banner.offset_bottom = 52.0
	extract_banner.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.12, 0.22, 0.14, 0.94), GameTheme.ACCENT_SUCCESS, 8))
	extract_banner_label = Label.new()
	extract_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extract_banner_label.add_theme_font_size_override("font_size", 16)
	extract_banner.add_child(extract_banner_label)
	play_area.add_child(extract_banner)

	_setup_sector_delegation_ui()
	_setup_orbital_bar()


func _apply_carrier_sector_deployments() -> void:
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		var sector := str(RunState.deploy_assignments.get(squad_id, ""))
		if sector.is_empty():
			continue
		var room := _pick_spawn_room_for_sector(sector)
		if room:
			deploy_assignments[squad_id] = room
			squads_manager.set_sector_assignment(squad_id, sector)
			log_message(
				"Carrier drop: %s → %s sector (%s)." % [GameTheme.squad_label(squad_id), sector, room.room_name],
				GameTheme.ACCENT.to_html(),
				"squad",
			)


func _pick_spawn_room_for_sector(sector: String) -> Room:
	for room in rooms:
		if room.is_spawn_eligible and room.sector_tag == sector:
			return room
	for room in rooms:
		if room.is_spawn_eligible:
			return room
	return null


func _spawn_evolution_nodes() -> void:
	if not _is_planet_mission():
		return
	evolution_nodes.clear()
	for room in rooms:
		if not room.get_meta("evolution_node", false):
			continue
		var node = EvolutionNodeScene.instantiate()
		node.setup(room, room.map_room_id, self)
		world.add_child(node)
		evolution_nodes.append(node)
	if not evolution_nodes.is_empty():
		log_message(
			"EVOLUTION: %d field upgrade nodes detected on-map." % evolution_nodes.size(),
			GameTheme.ACCENT.to_html(),
			"objective",
		)


func register_swarm_damage(tag: String, amount: int) -> void:
	if swarm_director:
		swarm_director.register_damage(tag, amount)


func get_rooms_in_sector(sector: String) -> Array:
	return squads_manager.rooms_for_sector(rooms, sector)


func spawn_swarm_counter_enemy(room: Room, arch: Enemy.Kind) -> void:
	if not room:
		return
	var enemy_res := EnemyLib.create_archetype(arch, map_data.enemy_stat_scale if map_data else 1.0, _next_spawn_enemy_id)
	_next_spawn_enemy_id += 1
	var enemy: EnemyUnit = ENEMY_SCENE.instantiate()
	enemy.setup_from_resource(enemy_res, room)
	enemy.position = room.position
	register_spawned_enemy(enemy, room)
	log_message("Swarm counter (%s) inbound in %s." % [EnemyLib.archetype_label(arch), room.room_name], GameTheme.ACCENT_WARN.to_html(), "alert")


func trigger_cinematic(_reason: String, duration: float = 2.0) -> void:
	_cinematic_timer = duration
	_cinematic_duration = duration
	_cinematic_slowmo = true
	Engine.time_scale = 0.45
	if map_camera and _overmind_hive:
		var tween := create_tween()
		tween.tween_property(map_camera, "position", _overmind_hive.position, duration * 0.5)


func _on_hive_wave_spawned(hive, _count: int) -> void:
	if hive and hive.home_room:
		_hive_telegraph_rooms[hive.home_room] = HIVE_TELEGRAPH_SECONDS
		log_message(
			CommsTemplatesLib.hive_wave_inbound(hive.home_room.room_name),
			GameTheme.ACCENT_DANGER.to_html(),
			"alert",
		)
		_minimap_dirty = true


func _tick_hive_telegraphs(delta: float) -> void:
	if _hive_telegraph_rooms.is_empty():
		return
	var expired: Array = []
	for room in _hive_telegraph_rooms.keys():
		_hive_telegraph_rooms[room] = float(_hive_telegraph_rooms[room]) - delta
		if float(_hive_telegraph_rooms[room]) <= 0.0:
			expired.append(room)
	for room in expired:
		_hive_telegraph_rooms.erase(room)
	if not expired.is_empty():
		_minimap_dirty = true


func _fire_objective_beats() -> void:
	if not _is_planet_mission() or _regular_hives_total <= 0:
		return
	var ratio := float(_regular_hives_destroyed) / float(_regular_hives_total)
	if ratio >= 0.5 and not _objective_beats_fired.get("half_nests", false):
		_objective_beats_fired["half_nests"] = true
		log_message(
			CommsTemplatesLib.nests_halfway(_regular_hives_destroyed, _regular_hives_total),
			GameTheme.ACCENT.to_html(),
			"objective",
		)
	if _regular_hives_destroyed >= _regular_hives_total and _regular_hives_total > 0 and not _objective_beats_fired.get("last_nest", false):
		_objective_beats_fired["last_nest"] = true
		log_message(CommsTemplatesLib.last_nest_cleared(), GameTheme.ACCENT.to_html(), "objective")


func _auto_assign_sector_doctrines() -> void:
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		var sector := squads_manager.get_sector_assignment(squad_id)
		if sector.is_empty():
			sector = str(RunState.deploy_assignments.get(squad_id, ""))
			if not sector.is_empty():
				squads_manager.set_sector_assignment(squad_id, sector)
		var doctrine := SquadsManagerLib.SectorDoctrine.ASSAULT_SECTOR
		if sector.is_empty():
			doctrine = SquadsManagerLib.SectorDoctrine.SCOUT_SECTOR
		elif _regular_hives_total > 0 and squad_id == "bravo":
			doctrine = SquadsManagerLib.SectorDoctrine.ASSAULT_HIVE
		squads_manager.set_sector_doctrine(squad_id, doctrine)
		squads_manager.set_doctrine(squad_id, OrderTypeLib.Type.OBJECTIVE)
		var units := squads_manager.get_squad_units(squad_id)
		if not units.is_empty():
			_issue_squad_objective(units, null)
		log_message(
			CommsTemplatesLib.squad_doctrine_assigned(
				GameTheme.squad_label(squad_id),
				SquadsManagerLib.sector_doctrine_label(doctrine),
			),
			GameTheme.ACCENT.to_html(),
			"objective",
		)


func _announce_extract_window() -> void:
	if not RunState.extract_window_open:
		return
	log_message(
		CommsTemplatesLib.extract_unlocked(),
		GameTheme.ACCENT_SUCCESS.to_html(),
		"objective",
	)
	_show_extract_banner(true)


func _show_extract_banner(visible: bool) -> void:
	if extract_banner:
		extract_banner.visible = visible
	_update_extract_banner()


func _update_extract_banner() -> void:
	if not extract_banner_label:
		return
	if RunState.extract_window_open:
		extract_banner_label.text = "EVAC OPEN — extract all operators"
		extract_banner_label.add_theme_color_override("font_color", GameTheme.ACCENT_SUCCESS)
		if extract_banner:
			extract_banner.modulate = Color.WHITE
	elif extract_banner:
		extract_banner.visible = false


func _comms_entry_visible(category: String) -> bool:
	if _comms_filter == "all":
		return true
	if _comms_filter == "priority":
		return category in ["alert", "alerts", "objective", "order"]
	if _comms_filter == "alerts":
		return category == "alert"
	return _comms_filter == category


func on_evolution_node_activated(node, squad_id: String) -> void:
	if not node or squad_id.is_empty():
		return
	var board: EvolutionBoard = RunState.get_evolution_board(squad_id)
	var choices := EvolutionUpgradeLib.roll_choices(board, 2)
	if choices.is_empty():
		log_message("Evolution node depleted.", GameTheme.TEXT_MUTED.to_html())
		return
	_show_evolution_pick_popup(squad_id, choices, node)


func _show_evolution_pick_popup(squad_id: String, choices: Array, node) -> void:
	var popup := AcceptDialog.new()
	popup.title = "Evolution — %s" % GameTheme.squad_label(squad_id)
	popup.dialog_text = "Select a field upgrade:"
	popup.min_size = Vector2(360, 180)
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)
	for upgrade in choices:
		var btn := Button.new()
		btn.text = "%s — %s" % [upgrade.display_name, upgrade.description]
		btn.pressed.connect(func():
			var units := squads_manager.get_squad_units(squad_id)
			RunState.apply_evolution_upgrade(squad_id, upgrade.id, units)
			log_message(
				"EVOLUTION: %s applied [%s]." % [GameTheme.squad_label(squad_id), upgrade.display_name],
				GameTheme.ACCENT_SUCCESS.to_html(),
				"objective",
			)
			popup.queue_free()
		)
		vbox.add_child(btn)
	add_child(popup)
	popup.popup_centered()


func _setup_sector_delegation_ui() -> void:
	if sector_panel:
		return
	sector_panel = PanelContainer.new()
	sector_panel.name = "SectorPanel"
	sector_panel.visible = false
	sector_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sector_panel.offset_left = 200.0
	sector_panel.offset_top = 140.0
	sector_panel.offset_right = -200.0
	sector_panel.offset_bottom = 210.0
	sector_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.06, 0.08, 0.12, 0.92), GameTheme.ACCENT, 6))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	sector_panel.add_child(vbox)
	var title := Label.new()
	title.text = "Sector Delegation (real-time overlay)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var sector_row := HBoxContainer.new()
	sector_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for sector in SquadsManagerLib.SECTOR_TAGS:
		if sector == "central":
			continue
		var btn := Button.new()
		btn.text = sector.capitalize()
		btn.pressed.connect(_assign_sector_to_selected.bind(sector))
		sector_row.add_child(btn)
	vbox.add_child(sector_row)
	var doctrine_row := HBoxContainer.new()
	doctrine_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for doctrine in [
		SquadsManagerLib.SectorDoctrine.ASSAULT_SECTOR,
		SquadsManagerLib.SectorDoctrine.HOLD_CHOKE,
		SquadsManagerLib.SectorDoctrine.SCOUT_SECTOR,
		SquadsManagerLib.SectorDoctrine.ASSAULT_HIVE,
	]:
		var btn := Button.new()
		btn.text = SquadsManagerLib.sector_doctrine_label(doctrine)
		btn.pressed.connect(_assign_sector_doctrine_to_selected.bind(doctrine))
		doctrine_row.add_child(btn)
	vbox.add_child(doctrine_row)
	play_area.add_child(sector_panel)


func _setup_orbital_bar() -> void:
	if orbital_bar:
		return
	orbital_bar = HBoxContainer.new()
	orbital_bar.name = "OrbitalBar"
	orbital_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	orbital_bar.offset_left = 190.0
	orbital_bar.offset_top = -148.0
	orbital_bar.offset_right = -12.0
	orbital_bar.offset_bottom = -118.0
	orbital_bar.add_theme_constant_override("separation", 8)
	orbital_charge_label = Label.new()
	orbital_charge_label.text = "Orbital: 100"
	orbital_bar.add_child(orbital_charge_label)
	for ability in ["Scan", "Strike", "Resupply", "EMP"]:
		var btn := Button.new()
		btn.text = ability
		btn.pressed.connect(_on_orbital_ability.bind(ability.to_lower()))
		orbital_bar.add_child(btn)
	play_area.add_child(orbital_bar)
	orbital_bar.visible = _is_planet_mission()


func _update_orbital_bar() -> void:
	if orbital_charge_label:
		orbital_charge_label.text = "Orbital: %.0f" % RunState.orbital_charges


func _on_orbital_ability(ability_id: String) -> void:
	if not _is_planet_mission():
		log_message("Orbital abilities are planet-run only.", GameTheme.ACCENT_WARN.to_html())
		return
	var cost := 25.0
	match ability_id:
		"scan":
			cost = 20.0
			if not RunState.spend_orbital_charge(cost):
				return
			for room in rooms:
				if not room.is_revealed:
					room.reveal()
					room._update_visuals()
			log_message("Orbital Scan — full sector sweep.", GameTheme.ACCENT.to_html(), "objective")
			if _overmind_hive and RunState.planet_phase == RunState.PlanetPhase.QUEEN:
				_overmind_hive.home_room.reveal()
		"strike":
			cost = 35.0
			if not RunState.spend_orbital_charge(cost):
				return
			trigger_cinematic("strike", 1.5)
			for enemy in active_enemies.duplicate():
				if enemy is EnemyUnit and enemy.is_alive:
					enemy.take_damage(40, null)
			log_message("Orbital Strike — area bombardment.", GameTheme.ACCENT_DANGER.to_html(), "alert")
		"resupply":
			cost = 30.0
			if not RunState.spend_orbital_charge(cost):
				return
			for unit in squads_manager.get_squad_units(_selected_squad_id):
				unit.heal(int(unit.max_health * 0.25))
				unit.add_stress(-0.2)
			log_message("Orbital Resupply — %s restored." % GameTheme.squad_label(_selected_squad_id), GameTheme.ACCENT_SUCCESS.to_html())
		"emp":
			cost = 28.0
			if not RunState.spend_orbital_charge(cost):
				return
			for hive in active_hives:
				if hive and hive.is_attackable():
					hive.spawn_timer = 30.0
					hive.state = Hive.State.DORMANT
			log_message("Orbital EMP — hives suppressed 30s.", GameTheme.ACCENT.to_html())
	_update_orbital_bar()


func _assign_sector_to_selected(sector: String) -> void:
	squads_manager.set_sector_assignment(_selected_squad_id, sector)
	log_message("%s assigned to %s sector." % [GameTheme.squad_label(_selected_squad_id), sector], GameTheme.ACCENT.to_html())
	_issue_sector_doctrine_orders(_selected_squad_id)


func _assign_sector_doctrine_to_selected(doctrine: SquadsManagerLib.SectorDoctrine) -> void:
	squads_manager.set_sector_doctrine(_selected_squad_id, doctrine)
	var order := SquadsManagerLib.order_for_sector_doctrine(doctrine)
	squads_manager.set_doctrine(_selected_squad_id, order)
	log_message(
		"%s doctrine: %s" % [GameTheme.squad_label(_selected_squad_id), SquadsManagerLib.sector_doctrine_label(doctrine)],
		GameTheme.ACCENT.to_html(),
	)
	_issue_sector_doctrine_orders(_selected_squad_id)


func _issue_sector_doctrine_orders(squad_id: String) -> void:
	var target := squads_manager.pick_target_room(squad_id, rooms, active_hives)
	if not target:
		return
	var order := squads_manager.get_doctrine(squad_id)
	for unit in squads_manager.get_squad_units(squad_id):
		unit.issue_order(order, target.position, target)


func _collect_evolution_summary() -> Array[String]:
	var lines: Array[String] = []
	for squad_id in RunState.SQUAD_IDS:
		for line in RunState.get_evolution_board(squad_id).get_summary_lines():
			if line not in lines:
				lines.append(line)
	return lines


func _set_comms_filter(filter_id: String, btn: Button) -> void:
	_comms_filter = filter_id
	if comms_filter_row:
		for child in comms_filter_row.get_children():
			if child is Button:
				(child as Button).button_pressed = child == btn
	_comms_force_rebuild = true
	_refresh_comms_display()


func _draw_minimap() -> void:
	if not minimap_panel or not map_data:
		return
	var panel_size := minimap_panel.size
	minimap_panel.draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.04, 0.05, 0.08, 0.88))
	minimap_panel.draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.25, 0.35, 0.5, 0.6), false, 1.0)
	if rooms.is_empty():
		return
	var min_pos := rooms[0].position
	var max_pos := rooms[0].position
	for room in rooms:
		min_pos = min_pos.min(room.position - room.room_size * 0.5)
		max_pos = max_pos.max(room.position + room.room_size * 0.5)
	var span := max_pos - min_pos
	if span.x < 1.0 or span.y < 1.0:
		return
	var pad := 6.0
	for room in rooms:
		var rel := (room.position - min_pos) / span
		var rs := room.room_size / span * (panel_size - Vector2(pad * 2, pad * 2))
		var pos := Vector2(pad, pad) + rel * (panel_size - Vector2(pad * 2, pad * 2)) - rs * 0.5
		var col := Color(0.15, 0.18, 0.24, 0.9)
		if room.is_revealed:
			col = Color(0.22, 0.32, 0.42, 0.95)
		if room.is_cleared:
			col = Color(0.18, 0.42, 0.32, 0.95)
		if room.get_meta("hive_room", false):
			col = Color(0.55, 0.15, 0.35, 0.95)
		if room.get_meta("overmind_room", false):
			col = Color(0.62, 0.18, 0.82, 0.98)
		minimap_panel.draw_rect(Rect2(pos, rs), col)
		var icon_center := pos + rs * 0.5
		if room.is_extraction_room:
			minimap_panel.draw_circle(icon_center, 4.0, GameTheme.ACCENT_SUCCESS)
		elif room.get_meta("evolution_node", false):
			minimap_panel.draw_circle(icon_center, 3.5, Color(0.35, 0.85, 1.0, 0.95))
		elif room.get_meta("hive_room", false) and not room.get_meta("overmind_room", false):
			minimap_panel.draw_circle(icon_center, 4.0, Color(0.95, 0.25, 0.55, 0.95))
		elif room.get_meta("elite_slot", false):
			minimap_panel.draw_circle(icon_center, 3.0, Color(1.0, 0.75, 0.25, 0.95))
		if _hive_telegraph_rooms.has(room):
			minimap_panel.draw_arc(icon_center, 7.0, 0.0, TAU, 12, Color(1.0, 0.35, 0.25, 0.9), 2.0)
	for unit in active_units:
		if not unit.is_alive:
			continue
		var rel_u := (unit.position - min_pos) / span
		var dot := Vector2(pad, pad) + rel_u * (panel_size - Vector2(pad * 2, pad * 2))
		minimap_panel.draw_circle(dot, 3.0, GameTheme.squad_color(unit.squad_id))
	if _show_threat_overlay:
		for room in rooms:
			if room.last_hostile_contact or room.has_living_enemies():
				var rel_t := (room.position - min_pos) / span
				var dot_t := Vector2(pad, pad) + rel_t * (panel_size - Vector2(pad * 2, pad * 2))
				minimap_panel.draw_circle(dot_t, 4.0, Color(0.95, 0.35, 0.25, 0.75))
