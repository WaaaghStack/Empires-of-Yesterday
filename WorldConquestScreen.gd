extends Control

const CFG := preload("res://WorldConquestConfig.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const GameThemeLib := preload("res://GameTheme.gd")
const EarthGlobeMapLib := preload("res://EarthGlobeMap.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const ResourceLib := preload("res://WorldConquestResources.gd")
const RoutePlannerLib := preload("res://RoutePlannerRustBackend.gd")
const FrameBudgetProfilerLib := preload("res://FrameBudgetProfiler.gd")
const OutpostConstructionQueueLib := preload("res://OutpostConstructionQueue.gd")
const BuilderAgentLib := preload("res://BuilderAgentLib.gd")

@onready var globe_map: EarthGlobeMapLib = $PlayArea/SubViewportContainer/SubViewport/GlobeMap
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var play_area: Control = $PlayArea
@onready var summary_bar: PanelContainer = $SummaryBar
@onready var blue_count_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueCount
@onready var blue_sub_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueSub
@onready var blue_resources_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueResources
@onready var red_count_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedCount
@onready var red_sub_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedSub
@onready var red_resources_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedResources
@onready var time_label: Label = $SummaryBar/SummaryHBox/CenterPanel/TimeLabel
@onready var supply_label: Label = $SummaryBar/SummaryHBox/CenterPanel/SupplyLabel
@onready var status_label: Label = $HUD/HBox/StatusLabel
@onready var pause_button: Button = $HUD/HBox/PauseButton
@onready var speed_button: Button = $HUD/HBox/SpeedButton
@onready var spawner_button: Button = $HUD/HBox/SpawnerButton
@onready var barracks_button: Button = $HUD/HBox/BarracksButton
@onready var corridor_link_button: Button = $HUD/HBox/CorridorLinkButton
@onready var inspect_button: Button = $HUD/HBox/InspectButton
@onready var tile_probe_label: Label = $HUD/TileProbeLabel
@onready var back_button: Button = $TopBar/BackButton
@onready var build_hint_label: Label = $HUD/BuildHintLabel
@onready var perf_hud_label: Label = $PerfHudLabel
@onready var end_overlay: PanelContainer = $EndOverlay
@onready var end_label: Label = $EndOverlay/Center/EndLabel
@onready var loading_overlay: PanelContainer = $LoadingOverlay
@onready var loading_status_label: Label = $LoadingOverlay/Center/LoadPanel/VBox/StatusLabel
@onready var loading_progress: ProgressBar = $LoadingOverlay/Center/LoadPanel/VBox/ProgressBar

var battle_data = null
var territory_sim: BattleTerritorySimLib
var _claimable_tiles: int = 0
var _friendly_tiles: int = 0
var _hostile_tiles: int = 0
var _supply: float = 0.0
var _sim_time: float = 0.0
var _paused: bool = false
var _speed_mult: float = 1.0
var _overlay_clock: float = 0.0
var _battle_finished: bool = false
var _build_mode: String = ""
var _last_overlay_step: int = -1
var _next_structure_id: int = 1
var _build_hint_clock: float = 0.0
var _hud_clock: float = 0.0
var _player_home: Vector2i = Vector2i(-1, -1)
var _enemy_home: Vector2i = Vector2i(-1, -1)
var _orbit_drag: bool = false
var _outpost_road_dirty: bool = false
var _outpost_marker_dirty: bool = false
var _outpost_road_dirty_sids: Array[int] = []
var _outpost_marker_dirty_sids: Array[int] = []
var _outpost_marker_clock: float = 0.0
var _spawners_pending_sync: bool = false
var _hover_check_grid: Vector2i = Vector2i(-99999, -99999)
var _hover_reject_cache: String = ""
var _hover_hint_grid: Vector2i = Vector2i(-99999, -99999)
var _hover_landing_grid: Vector2i = Vector2i(-99999, -99999)
var _hover_sources_version: int = 0
var _hover_build_mode_cache: String = ""
var _structure_sources_version: int = 0
var _road_network_version: int = 0
var _friendly_resources: Array[float] = [0.0, 0.0, 0.0]
var _hostile_resources: Array[float] = [0.0, 0.0, 0.0]
var _resource_links_dirty: bool = true
var _last_resource_pulses: Array = []
var _tile_inspect_active: bool = false
var _tile_probe_clock: float = 0.0
var _bridges_repaired: bool = false
var _bridge_backend_sync_pending: bool = false
var _bridge_backend_sync_accum: float = 0.0
var _outpost_construction_queue: OutpostConstructionQueueLib
var _builder_agents: Array[Dictionary] = []
var _builder_job_queue_friendly: Array[int] = []
var _builder_job_queue_hostile: Array[int] = []
var _builder_visual_dirty: bool = true
var _builder_visual_clock: float = 0.0
var _soldier_visual_dirty: bool = true
var _soldier_visual_clock: float = 0.0
var route_planner: RoutePlannerLib
var _route_request_id: int = -1
var _route_place_pending: bool = false
var _route_pending_grid: Vector2i = Vector2i(-1, -1)
var _route_pending_landing: Vector2i = Vector2i(-1, -1)
var _route_pending_mode: String = ""
var _route_hover_clock: float = 0.0
var _route_hover_request_id: int = -1
var _route_sources_synced: int = -1
var _route_road_synced: int = -1
var _route_road_debounce: float = 0.0
var _loading: bool = true
var _load_started_msec: int = 0
var _frame_profiler: FrameBudgetProfilerLib
var _fps_low_streak: int = 0
var _fps_log_cooldown: float = 0.0
var _show_perf_hud: bool = false
var _last_frame_sim_steps: int = 0
var _last_overlay_delta_count: int = 0
var _perf_log_frame: int = -1
var _last_overlay_action_frame: int = -1
var _perf_action_cooldowns: Dictionary = {}
var _recent_perf_action_lines: Array[String] = []
const PERF_RECENT_ACTION_MAX := 64


func _ready() -> void:
	Engine.max_fps = 60
	_frame_profiler = FrameBudgetProfilerLib.new()
	_outpost_construction_queue = OutpostConstructionQueueLib.new()
	GameTheme.apply_to_control(self)
	_style_summary_hud()
	_style_loading_overlay()
	loading_overlay.visible = true
	_set_load_progress(0.0, "Starting…")
	_load_started_msec = Time.get_ticks_msec()
	back_button.pressed.connect(_on_back_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.pressed.connect(_on_speed_pressed)
	spawner_button.toggled.connect(_on_spawner_toggled)
	if barracks_button:
		barracks_button.toggled.connect(_on_barracks_toggled)
	corridor_link_button.toggled.connect(_on_corridor_link_toggled)
	inspect_button.toggled.connect(_on_inspect_toggled)
	if tile_probe_label:
		tile_probe_label.visible = false
	end_overlay.visible = false
	_supply = float(CFG.STARTING_SUPPLY)
	ResourceLib.reset()
	_friendly_resources = [0.0, 0.0, 0.0]
	_hostile_resources = [0.0, 0.0, 0.0]
	play_area.resized.connect(_on_play_area_resized)
	sub_viewport_container.gui_input.connect(_on_play_area_gui_input)
	if sub_viewport:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if summary_bar:
		summary_bar.z_index = 40
	if has_node("TopBar"):
		$TopBar.z_index = 41
	if has_node("HUD"):
		$HUD.z_index = 40
	if perf_hud_label:
		perf_hud_label.visible = false
		perf_hud_label.z_index = 42
	call_deferred("_bootstrap_async")


func _bootstrap_async() -> void:
	_set_load_progress(0.08, "Generating Earth map…")
	await get_tree().process_frame
	var seed_val: int = RunState.run_seed if RunState.run_seed != 0 else randi() & 0x7FFFFFFF
	battle_data = EarthMapGeneratorLib.generate(seed_val)
	_set_load_progress(0.28, "Initializing territory simulation…")
	await get_tree().process_frame
	territory_sim = BattleTerritorySimLib.new()
	territory_sim.use_simple_water_model = true
	territory_sim.set_resolve_context("world_conquest")
	territory_sim.setup(battle_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	_claimable_tiles = territory_sim.claimable_tiles
	_player_home = battle_data.player_home_grid
	_enemy_home = battle_data.enemy_home_grid
	_sync_counts()
	_set_load_progress(0.48, "Preparing simulation backend…")
	await get_tree().process_frame
	_setup_world_visuals()
	_set_load_progress(0.82, "Warming up globe…")
	await get_tree().process_frame
	_update_tile_overlay(true)
	_update_hud()
	_set_load_progress(0.95, "Almost ready…")
	await _await_min_load_time()
	_set_load_progress(1.0, "Ready")
	await get_tree().process_frame
	if sub_viewport:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	loading_overlay.visible = false
	_loading = false
	if _frame_profiler != null:
		_frame_profiler.reset_samples()
	RunLog.info(
		"World Conquest — %dx%d Earth globe" % [battle_data.grid_width, battle_data.grid_height]
	)


func _await_min_load_time() -> void:
	var elapsed_sec: float = float(Time.get_ticks_msec() - _load_started_msec) / 1000.0
	var wait_sec: float = CFG.WORLD_CONQUEST_MIN_LOAD_SEC - elapsed_sec
	if wait_sec > 0.0:
		await get_tree().create_timer(wait_sec).timeout


func _set_load_progress(ratio: float, status: String) -> void:
	if loading_status_label != null:
		loading_status_label.text = status
	if loading_progress != null:
		loading_progress.value = clampf(ratio, 0.0, 1.0) * 100.0


func _style_loading_overlay() -> void:
	if loading_overlay == null:
		return
	var panel: PanelContainer = loading_overlay.get_node_or_null("Center/LoadPanel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", GameThemeLib.make_panel_style())


func _setup_world_visuals() -> void:
	OutpostBuildLib.prepare_land_components(battle_data)
	_setup_territory_backend()
	if territory_sim != null:
		_sync_bridge_corridors_to_sim(true, true)
	if globe_map != null:
		globe_map.setup(battle_data)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
		light.light_energy = 1.2
		light.shadow_enabled = false
		globe_map.add_child(light)
		var env_node := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.02, 0.03, 0.06)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.3, 0.35, 0.45)
		e.ambient_light_energy = 0.5
		env_node.environment = e
		globe_map.add_child(env_node)
	_refresh_markers()
	_refresh_resource_deposits()
	_resource_links_dirty = true
	_init_builder_agents()
	_on_play_area_resized(true)


func _process(delta: float) -> void:
	# Perf: skip FrameBudgetProfiler during bootstrap loading (reset_samples after _loading=false).
	if _loading:
		return
	if _battle_finished or battle_data == null or territory_sim == null:
		return
	if _frame_profiler != null:
		_frame_profiler.begin_frame()
	_perf_log_frame = Engine.get_process_frames()
	_decrement_perf_action_cooldowns(delta)
	var sim_steps: int = 0
	var sim_max_steps: int = CFG.SIM_MAX_STEPS_PER_FRAME
	if (
		_frame_profiler != null
		and not FrameBudgetProfilerLib.budget_allows_catchup(
			_frame_profiler.prior_frame_ms(), CFG.FRAME_BUDGET_MS
		)
	):
		sim_max_steps = 1

	# Process deferred spawner activations from previous frame's build completions.
	# This moves the sync work (placed_spawners + Rust update_spawners) off the completion frame itself,
	# so "make the building" (dict + marker visual) is cheap on the build frame,
	# and the new pump starts contributing "aura power" on the next tick's advance (as the user expects).
	if _spawners_pending_sync:
		var spawner_t: int = 0
		if _frame_profiler != null:
			spawner_t = _frame_profiler.begin_phase("spawner_sync")
		if territory_sim.tile_control != null:
			territory_sim.tile_control.sync_placed_spawners_from_map(battle_data)
			if territory_sim.rust_live_ready and territory_sim.rust_field != null:
				territory_sim.rust_field.sync_spawners_from(territory_sim.tile_control)
		_spawners_pending_sync = false
		if _frame_profiler != null:
			_frame_profiler.end_phase("spawner_sync", spawner_t)

	if not _paused and not territory_sim.finished:
		_supply += float(_friendly_tiles) * CFG.INCOME_PER_TILE_PER_SEC * delta
		var sim_t: int = 0
		if _frame_profiler != null:
			sim_t = _frame_profiler.begin_phase("sim")
		var info: Dictionary = territory_sim.advance_dt(delta * _speed_mult, sim_max_steps)
		sim_steps = int(info.get("steps", 0))
		_last_frame_sim_steps = sim_steps
		if _frame_profiler != null:
			_frame_profiler.end_phase("sim", sim_t)
		if sim_steps > 0:
			_sync_counts()
			_maybe_log_perf_action("sim", {"steps": sim_steps}, 2.0)
		if _has_active_construction():
			var outpost_t: int = 0
			if _frame_profiler != null:
				outpost_t = _frame_profiler.begin_phase("outpost")
			_advance_outpost_construction(delta * _speed_mult)
			if _frame_profiler != null:
				_frame_profiler.end_phase("outpost", outpost_t)
		_tick_soldier_economy(delta * _speed_mult)
		_tick_barracks_spawns(delta * _speed_mult)
		if not _bridges_repaired:
			var bridge_t: int = 0
			if _frame_profiler != null:
				bridge_t = _frame_profiler.begin_phase("bridge")
			_maintain_bridge_corridors()
			if _frame_profiler != null:
				_frame_profiler.end_phase("bridge", bridge_t)
		var res_t: int = 0
		if _frame_profiler != null:
			res_t = _frame_profiler.begin_phase("resources")
		_tick_resources(delta * _speed_mult)
		if _frame_profiler != null:
			_frame_profiler.end_phase("resources", res_t)

	if sim_steps > 0:
		_soldier_visual_dirty = true
		if CFG.OVERLAY_OWNERS_ONLY:
			_enqueue_ownership_overlay_delta()

	var bridge_flush_t: int = 0
	if _frame_profiler != null:
		bridge_flush_t = _frame_profiler.begin_phase("bridge_flush")
	_drain_outpost_construction_queue()
	if _frame_profiler != null:
		_frame_profiler.end_phase("bridge_flush", bridge_flush_t)

	if not _paused and territory_sim != null and not territory_sim.finished:
		if not CFG.OVERLAY_OWNERS_ONLY:
			_overlay_clock += delta
			if _overlay_clock >= 1.0 / CFG.OVERLAY_UPDATES_PER_SEC:
				_overlay_clock = 0.0
				_update_tile_overlay(false)
		_update_builder_agents(delta * _speed_mult)
	_update_outpost_visuals(delta)
	_update_resource_visuals(delta)
	_update_builder_visuals(delta)
	var soldier_t: int = 0
	if _frame_profiler != null:
		soldier_t = _frame_profiler.begin_phase("soldiers")
	_update_soldier_visuals(delta)
	if _frame_profiler != null:
		_frame_profiler.end_phase("soldiers", soldier_t)
	if territory_sim.finished and not _battle_finished:
		_on_battle_finished()
	if _is_build_mode_active():
		_build_hint_clock += delta
		_route_hover_clock += delta
		if _build_hint_clock >= 0.12:
			_build_hint_clock = 0.0
			_update_build_hover_hint()
	_hud_clock += delta
	if _hud_clock >= 0.12:
		_hud_clock = 0.0
		_update_hud()
	if _tile_inspect_active:
		_tile_probe_clock += delta
		if _tile_probe_clock >= 0.1:
			_tile_probe_clock = 0.0
			_update_tile_probe()
	_poll_route_planner()
	_maybe_refresh_route_backend(delta)
	_end_process_profiler_frame()


func _end_process_profiler_frame(record_sample: bool = true) -> void:
	if _frame_profiler != null:
		_frame_profiler.end_frame(record_sample)


func request_outpost_visual_refresh(roads: bool, markers: bool, sid: int = -1) -> void:
	if _outpost_construction_queue != null and sid >= 0:
		if roads:
			_outpost_construction_queue.enqueue_road(sid)
		if markers:
			_outpost_construction_queue.enqueue_marker(sid)
		return
	_refresh_outpost_visuals(roads, markers)


func _setup_territory_backend() -> void:
	var backend_env: String = OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower()
	if backend_env == "cpu":
		territory_sim.set_live_backend(false)
		RunLog.info("World Conquest using CPU territory backend (BATTLE_TERRITORY_BACKEND=cpu)")
		return
	if backend_env == "gpu" and territory_sim.enable_gpu_live():
		RunLog.info("World Conquest using GPU territory backend")
		return
	if territory_sim.enable_rust_live():
		RunLog.info("World Conquest using Rust territory backend")
		return
	territory_sim.set_live_backend(false)
	RunLog.info("World Conquest using CPU territory backend (Rust extension not loaded)")


func _on_play_area_gui_input(event: InputEvent) -> void:
	if _battle_finished or battle_data == null or end_overlay.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if globe_map:
				globe_map.zoom_camera(true)
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if globe_map:
				globe_map.zoom_camera(false)
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_drag = mb.pressed
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _is_build_mode_active():
			_try_place_structure()
			sub_viewport_container.accept_event()
	elif event is InputEventMouseMotion and _orbit_drag and globe_map != null:
		var mm := event as InputEventMouseMotion
		globe_map.orbit_camera(0.0, mm.relative)
		sub_viewport_container.accept_event()


func _is_build_mode_active() -> bool:
	return _build_mode != ""


func _build_mode_cost() -> float:
	if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return float(CFG.CORRIDOR_LINK_COST_SUPPLY)
	if _build_mode == OutpostBuildLib.KIND_BARRACKS:
		return float(CFG.BARRACKS_COST_SUPPLY)
	return float(CFG.SPAWNER_COST_SUPPLY)


func _build_mode_noun() -> String:
	if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return "land bridge"
	if _build_mode == OutpostBuildLib.KIND_BARRACKS:
		return "barracks"
	return "outpost"


func _try_place_structure() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Click land on the globe to place a %s." % _build_mode_noun()
		return
	var cost: float = _build_mode_cost()
	if _supply < cost:
		build_hint_label.text = "Need %s supply (have %s)." % [
			_format_supply(cost),
			_format_supply(_supply),
		]
		return
	var reject: String = _placement_hover_reject(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = reject
		return
	build_hint_label.text = "Planning route…"
	_ensure_route_planner()
	var use_async: bool = (
		CFG.ROUTE_ASYNC_PLACEMENT
		and route_planner != null
		and route_planner.ready
		and _build_mode != OutpostBuildLib.KIND_CORRIDOR_LINK
	)
	if use_async:
		var precheck: Dictionary = _placement_precheck(grid, _build_mode)
		if str(precheck.get("reject", "")) != "":
			build_hint_label.text = str(precheck.get("reject", ""))
			return
		var landing: Vector2i = precheck.get("landing", Vector2i(-1, -1))
		if landing.x < 0:
			build_hint_label.text = "Could not place outpost here."
			return
		_cancel_route_requests()
		_route_pending_grid = grid
		_route_pending_landing = landing
		_route_pending_mode = _build_mode
		_route_place_pending = true
		_route_request_id = route_planner.start_route_async(landing, _build_mode, true)
		if _route_request_id < 0:
			_route_place_pending = false
			call_deferred("_finish_place_structure", grid)
		return
	call_deferred("_finish_place_structure", grid)


func _finish_place_structure(grid: Vector2i) -> void:
	if battle_data == null or _build_mode == "":
		return
	var placement: Dictionary = _resolve_placement(grid, true, _build_mode)
	var landing: Vector2i = placement.get("landing", Vector2i(-1, -1))
	var reject: String = str(placement.get("reject", ""))
	if reject != "":
		build_hint_label.text = reject
		return
	var path_packed: PackedInt32Array = placement.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		build_hint_label.text = "Could not place outpost here."
		return
	path_packed = OutpostBuildLib.densify_path_cardinal(battle_data, path_packed)
	var cost: float = _build_mode_cost()
	if _supply < cost:
		build_hint_label.text = "Need %s supply (have %s)." % [
			_format_supply(cost),
			_format_supply(_supply),
		]
		return
	_supply -= cost
	var src: Vector2i = placement.get("source", Vector2i(-1, -1))
	var st: Dictionary = {
		"id": _next_structure_id,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": landing.x,
		"gy": landing.y,
		"kind": _build_mode,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"source_gx": src.x,
		"source_gy": src.y,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": 1.0,
	}
	if _build_mode == OutpostBuildLib.KIND_SPAWNER or _build_mode == OutpostBuildLib.KIND_BARRACKS:
		st["health"] = CFG.OUTPOST_MAX_HEALTH
	if landing != grid:
		st["click_gx"] = grid.x
		st["click_gy"] = grid.y
	battle_data.placed_structures.append(st)
	var placed_sid: int = int(st.get("id", -1))
	_next_structure_id += 1
	if _build_mode == OutpostBuildLib.KIND_SPAWNER:
		_structure_sources_version += 1
	_road_network_version += 1
	_invalidate_hover_path_cache()
	_clear_placement_preview()
	_outpost_road_dirty = true
	_outpost_marker_dirty = true
	_resource_links_dirty = true
	_enqueue_builder_job(placed_sid, BattleTileControlLib.OWNER_FRIENDLY)
	_sync_bridge_corridors_to_sim(false, true, true)  # placement; force visual now cheap via bytes
	_refresh_outpost_visuals(true, true)
	_apply_build_mode("")


func _find_placement_route(
	landing: Vector2i,
	build_kind: String,
	sources: Array[Vector2i],
	allow_astar: bool,
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if battle_data == null or landing.x < 0:
		return empty
	# Land bridges must reach detached landmasses; keep the proven GDScript pathfinder.
	if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return OutpostBuildLib.nearest_corridor_path_to_target(
			battle_data, landing, sources, allow_astar
		)
	if route_planner != null and route_planner.ready:
		var rust_res: Dictionary = route_planner.find_route_sync(
			landing, build_kind, allow_astar
		)
		var rust_route: Dictionary = route_planner.decode_route_result(rust_res)
		if not rust_route.get("path_packed", PackedInt32Array()).is_empty():
			return rust_route
	return OutpostBuildLib.nearest_path_to_target(
		battle_data, landing, sources, _structure_sources_version, allow_astar
	)


func _resolve_placement(
	click: Vector2i, allow_astar: bool = false, build_kind: String = OutpostBuildLib.KIND_SPAWNER
) -> Dictionary:
	var empty: Dictionary = {
		"landing": Vector2i(-1, -1),
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
		"reject": "",
	}
	if battle_data == null:
		empty["reject"] = "Map not ready."
		return empty
	var precheck: Dictionary = _placement_precheck(click, build_kind)
	var pre_reject: String = str(precheck.get("reject", ""))
	if pre_reject != "":
		empty["reject"] = pre_reject
		return empty
	var landing: Vector2i = precheck.get("landing", Vector2i(-1, -1))
	var sources: Array[Vector2i] = precheck.get("sources", [])
	var route: Dictionary = _find_placement_route(
		landing, build_kind, sources, allow_astar
	)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
			empty["reject"] = "No water crossing found for this land bridge."
			return empty
		var landing_idx: int = battle_data.cell_index(landing.x, landing.y)
		if landing_idx >= 0:
			RunLog.warn(
				"Outpost routing failed at (%d, %d); placing standalone (no supply path)."
				% [landing.x, landing.y]
			)
			path_packed = PackedInt32Array([landing_idx])
			empty["landing"] = landing
			empty["path_packed"] = path_packed
			empty["source"] = landing
			return empty
		empty["reject"] = "Invalid landing tile."
		return empty
	if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
		if not OutpostBuildLib.is_valid_bridge_path(battle_data, path_packed):
			empty["reject"] = "Land bridge must cross open water (not overland)."
			return empty
	empty["landing"] = landing
	empty["path_packed"] = path_packed
	empty["source"] = route.get("source", Vector2i(-1, -1))
	return empty


func _placement_precheck(click: Vector2i, build_kind: String) -> Dictionary:
	var result: Dictionary = {
		"landing": Vector2i(-1, -1),
		"reject": "",
		"sources": [],
	}
	if battle_data == null:
		result["reject"] = "Map not ready."
		return result
	if not _is_on_map_grid(click.x, click.y):
		result["reject"] = "Out of map bounds."
		return result
	if not battle_data.is_land_cell(click.x, click.y):
		result["reject"] = "Need land (not ocean)."
		return result
	var territory_reject: String = _placement_territory_reject(click.x, click.y, build_kind)
	if territory_reject != "":
		result["reject"] = territory_reject
		return result
	var sources: Array[Vector2i] = OutpostBuildLib.operational_sources(
		battle_data.placed_structures, _player_home, battle_data
	)
	result["sources"] = sources
	var landing: Vector2i
	if (
		build_kind == OutpostBuildLib.KIND_SPAWNER
		or build_kind == OutpostBuildLib.KIND_BARRACKS
	):
		landing = click
	else:
		var snap_inland: bool = build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK
		landing = OutpostBuildLib.resolve_invasion_target(
			battle_data, click, sources, snap_inland
		)
		if landing.x < 0:
			result["reject"] = "No coastal landing on this landmass."
			return result
	result["landing"] = landing
	for st: Dictionary in battle_data.placed_structures:
		var dx: int = landing.x - int(st.get("gx", 0))
		var dy: int = landing.y - int(st.get("gy", 0))
		if dx * dx + dy * dy < CFG.MIN_SPAWNER_SPACING_CELLS * CFG.MIN_SPAWNER_SPACING_CELLS:
			result["reject"] = "Too close to another structure."
			return result
	for corridor: Dictionary in battle_data.bridge_corridors:
		var cdx: int = landing.x - int(corridor.get("gx", 0))
		var cdy: int = landing.y - int(corridor.get("gy", 0))
		if cdx * cdx + cdy * cdy < CFG.MIN_SPAWNER_SPACING_CELLS * CFG.MIN_SPAWNER_SPACING_CELLS:
			result["reject"] = "Too close to an existing land bridge."
			return result
	var kind_reject: String = _placement_kind_reject(landing, sources, build_kind)
	if kind_reject != "":
		result["reject"] = kind_reject
	return result


func _placement_kind_reject(
	landing: Vector2i, _sources: Array[Vector2i], build_kind: String
) -> String:
	if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
		if not OutpostBuildLib.is_coastal_cell(battle_data, landing.x, landing.y):
			return "Land Bridge needs a coastal landing."
	return ""


func _placement_territory_reject(gx: int, gy: int, build_kind: String = "") -> String:
	if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return ""
	if battle_data == null or territory_sim == null or territory_sim.tile_control == null:
		return ""
	var idx: int = battle_data.cell_index(gx, gy)
	if idx < 0 or idx >= territory_sim.tile_control.owners.size():
		return ""
	if int(territory_sim.tile_control.owners[idx]) == BattleTileControlLib.OWNER_HOSTILE:
		return "Cannot build on enemy-held territory."
	return ""


func _placement_hover_reject(gx: int, gy: int) -> String:
	if territory_sim == null or territory_sim.tile_control == null:
		return "Simulation not ready."
	var mode_key: String = _build_mode if _build_mode != "" else OutpostBuildLib.KIND_SPAWNER
	if (
		Vector2i(gx, gy) == _hover_check_grid
		and _hover_sources_version == _structure_sources_version
		and mode_key == _hover_build_mode_cache
	):
		return _hover_reject_cache
	_hover_check_grid = Vector2i(gx, gy)
	_hover_sources_version = _structure_sources_version
	_hover_build_mode_cache = mode_key
	var precheck: Dictionary = _placement_precheck(Vector2i(gx, gy), mode_key)
	_hover_landing_grid = precheck.get("landing", Vector2i(-99999, -99999))
	_hover_reject_cache = str(precheck.get("reject", ""))
	return _hover_reject_cache


func _mouse_to_grid() -> Vector2i:
	if globe_map == null or sub_viewport == null:
		return Vector2i(-1, -1)
	var local := sub_viewport_container.get_local_mouse_position()
	var cont_size := sub_viewport_container.size
	var sv_size := Vector2(sub_viewport.size)
	var vp_pos := Vector2(
		local.x * sv_size.x / maxf(cont_size.x, 1.0),
		local.y * sv_size.y / maxf(cont_size.y, 1.0),
	)
	return globe_map.pick_grid_from_viewport(vp_pos)


func _ownership_overlay_source() -> PackedByteArray:
	if territory_sim == null:
		return PackedByteArray()
	if territory_sim.use_rust_for_live() and territory_sim.rust_field != null and territory_sim.rust_field.ready:
		var rust_owners: PackedByteArray = territory_sim.rust_field.get_owners()
		if not rust_owners.is_empty():
			return rust_owners
	if territory_sim.tile_control != null:
		return territory_sim.tile_control.owners
	return PackedByteArray()


func _apply_owner_visual_from_backends(defer_gpu: bool = false) -> void:
	if globe_map == null or not CFG.OVERLAY_OWNERS_ONLY:
		return
	if (
		territory_sim != null
		and territory_sim.rust_live_ready
		and territory_sim.rust_field != null
		and territory_sim.rust_field.has_method("get_owner_display_r8")
	):
		var bytes: PackedByteArray = territory_sim.rust_field.get_owner_display_r8()
		if bytes.size() > 0:
			globe_map.apply_ownership_display_bytes(bytes)
			if defer_gpu and _outpost_construction_queue != null:
				_outpost_construction_queue.request_gpu_upload()
			return
	var owners: PackedByteArray = _ownership_overlay_source()
	if not owners.is_empty():
		globe_map.apply_ownership_overlay(owners)
		if defer_gpu and _outpost_construction_queue != null:
			_outpost_construction_queue.request_gpu_upload()


func _update_tile_overlay(force: bool) -> void:
	if territory_sim == null or globe_map == null:
		return
	if CFG.OVERLAY_OWNERS_ONLY:
		var owners: PackedByteArray = _ownership_overlay_source()
		if not owners.is_empty():
			# Prefer the zero-script-loop fast path when Rust can give us pre-baked display bytes.
			if territory_sim.rust_live_ready and territory_sim.rust_field != null and territory_sim.rust_field.has_method("get_owner_display_r8"):
				var bytes: PackedByteArray = territory_sim.rust_field.get_owner_display_r8()
				if bytes.size() > 0:
					globe_map.apply_ownership_display_bytes(bytes)
				else:
					globe_map.apply_ownership_overlay(owners)
			else:
				globe_map.apply_ownership_overlay(owners)
		return
	if territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	var step: int = territory_sim.round_index
	if not force and _last_overlay_step == step:
		return
	_last_overlay_step = step
	if territory_sim.use_gpu_for_live() and territory_sim.gpu_field != null:
		if not territory_sim.gpu_field.export_state_to_tile_control(tc):
			return
	if globe_map == null:
		return
	var pf: PackedFloat32Array = tc.pressure_friendly
	var ph: PackedFloat32Array = tc.pressure_hostile
	if territory_sim.use_rust_for_live() and territory_sim.rust_field != null:
		pf = territory_sim.rust_field.get_pressure_friendly()
		ph = territory_sim.rust_field.get_pressure_hostile()
	var peak: float = 10000.0
	if territory_sim.use_rust_for_live() and territory_sim.rust_field != null:
		peak = territory_sim.rust_field.pressure_overlay_peak()
	globe_map.apply_fluid_from_pressures_gpu(pf, ph, tc.claimable_mask, Rect2i(), peak)


func _enqueue_ownership_overlay_delta() -> void:
	if globe_map == null or territory_sim == null or _outpost_construction_queue == null:
		return
	if not CFG.OVERLAY_OWNERS_ONLY:
		return
	if territory_sim.use_rust_for_live() and territory_sim.rust_field != null and territory_sim.rust_field.ready:
		if territory_sim.rust_field.has_method("consume_owner_overlay_delta"):
			var d: Dictionary = territory_sim.rust_field.consume_owner_overlay_delta()
			var new_idxs: PackedInt32Array = d.get("indices", PackedInt32Array())
			var new_vals: PackedByteArray = d.get("values", PackedByteArray())
			if new_idxs.is_empty():
				return
			_outpost_construction_queue.enqueue_overlay_delta(new_idxs, new_vals)
			return
	var owners: PackedByteArray = _ownership_overlay_source()
	if not owners.is_empty():
		globe_map.apply_ownership_overlay(owners)
		_outpost_construction_queue.request_gpu_upload()


func _refresh_markers(changed_sids: Array = []) -> void:
	if globe_map == null:
		return
	var markers_t: int = 0
	if _frame_profiler != null:
		markers_t = _frame_profiler.begin_phase("markers")
	globe_map.refresh_markers(battle_data.placed_structures, _player_home, _enemy_home, changed_sids)
	if _frame_profiler != null:
		_frame_profiler.end_phase("markers", markers_t)
	_maybe_log_perf_action("markers", {"structures": battle_data.placed_structures.size()}, 3.0)


func _refresh_resource_deposits() -> void:
	if globe_map != null and battle_data != null:
		globe_map.refresh_resource_deposits(battle_data.resource_deposits)


func _tick_resources(dt: float) -> void:
	if battle_data == null or territory_sim == null or territory_sim.tile_control == null:
		return
	var info: Dictionary = ResourceLib.tick(
		battle_data,
		territory_sim.tile_control,
		battle_data.placed_structures,
		_player_home,
		_enemy_home,
		dt,
		_structure_sources_version,
		_road_network_version,
	)
	for i in CFG.RESOURCE_TYPE_COUNT:
		_friendly_resources[i] += float(info.friendly[i])
		_hostile_resources[i] += float(info.hostile[i])
	if bool(info.get("links_dirty", false)):
		_resource_links_dirty = true
	_last_resource_pulses = info.get("pulses", [])
	var pulse_n: int = _last_resource_pulses.size()
	_maybe_log_perf_action(
		"resources",
		{"pulses": pulse_n, "links_dirty": int(info.get("links_dirty", false))},
		2.0,
	)


func _update_resource_visuals(_delta: float) -> void:
	if globe_map == null:
		return
	if _resource_links_dirty:
		globe_map.sync_resource_sites(ResourceLib.site_states())
		_resource_links_dirty = false
	if not _last_resource_pulses.is_empty():
		globe_map.update_resource_pulses(_last_resource_pulses)
		_last_resource_pulses.clear()



func _sync_roads(changed_sids: Array = []) -> void:
	if globe_map == null:
		return
	var roads_t: int = 0
	if _frame_profiler != null:
		roads_t = _frame_profiler.begin_phase("roads")
	globe_map.sync_roads(battle_data.placed_structures, changed_sids)
	if _frame_profiler != null:
		_frame_profiler.end_phase("roads", roads_t)
	_maybe_log_perf_action("roads", {"structures": battle_data.placed_structures.size()}, 3.0)


func _refresh_outpost_visuals(roads: bool, markers: bool, road_sids: Array = [], marker_sids: Array = []) -> void:
	if roads:
		_sync_roads(road_sids)
	if markers:
		_refresh_markers(marker_sids)


func _has_building_outposts() -> bool:
	for st: Dictionary in battle_data.placed_structures:
		if str(st.get("kind", "")) != "spawner":
			continue
		if str(st.get("state", "")) == OutpostBuildLib.STATE_BUILDING:
			return true
	return false


func _has_vulnerable_outposts() -> bool:
	for st: Dictionary in battle_data.placed_structures:
		if str(st.get("kind", "")) != "spawner":
			continue
		var state: String = str(st.get("state", ""))
		if (
			state == OutpostBuildLib.STATE_CONNECTING
			or state == OutpostBuildLib.STATE_BUILDING
		):
			return true
	return false


func _update_outpost_visuals(delta: float) -> void:
	if not _has_vulnerable_outposts():
		return
	_outpost_marker_clock += delta
	if globe_map != null:
		globe_map.set_marker_pulse(_outpost_marker_clock)
	if _outpost_marker_clock >= 0.25:
		_outpost_marker_clock = 0.0
		if globe_map != null:
			globe_map.refresh_connecting_markers(
				battle_data.placed_structures, _player_home, _enemy_home
			)


func _invalidate_hover_path_cache() -> void:
	_hover_check_grid = Vector2i(-99999, -99999)
	_hover_hint_grid = Vector2i(-99999, -99999)
	_hover_landing_grid = Vector2i(-99999, -99999)
	_hover_build_mode_cache = ""
	_hover_reject_cache = ""
	OutpostBuildLib.invalidate_snap_cache()
	_cancel_route_requests()
	_clear_placement_preview()


func _cancel_route_requests() -> void:
	if route_planner != null and route_planner.ready:
		if _route_request_id >= 0:
			route_planner.cancel_route(_route_request_id)
		if _route_hover_request_id >= 0:
			route_planner.cancel_route(_route_hover_request_id)
	_route_request_id = -1
	_route_hover_request_id = -1
	_route_place_pending = false


func _rebuild_route_portals() -> void:
	if route_planner == null or not route_planner.ready or battle_data == null:
		return
	route_planner.rebuild_portals(
		battle_data, battle_data.placed_structures, _player_home
	)


func _ensure_route_planner() -> void:
	if route_planner != null and route_planner.ready:
		return
	if route_planner == null:
		route_planner = RoutePlannerLib.new()
	if route_planner.setup_map(battle_data, battle_data.placed_structures):
		_route_sources_synced = _structure_sources_version
		_route_road_synced = _road_network_version
		_rebuild_route_portals()


func _refresh_route_snapshot_and_portals() -> void:
	if battle_data == null:
		return
	_ensure_route_planner()
	if route_planner == null or not route_planner.ready:
		return
	route_planner.setup_map(battle_data, battle_data.placed_structures)
	_rebuild_route_portals()


func _refresh_route_infra_and_portals() -> void:
	if battle_data == null:
		return
	_ensure_route_planner()
	if route_planner == null or not route_planner.ready:
		return
	route_planner.update_infra(battle_data, battle_data.placed_structures)
	_rebuild_route_portals()


func _maybe_refresh_route_backend(delta: float) -> void:
	if not _is_build_mode_active() and not _route_place_pending:
		return
	if route_planner == null or battle_data == null:
		return
	if not route_planner.ready:
		_ensure_route_planner()
	if not route_planner.ready:
		return
	if _structure_sources_version != _route_sources_synced:
		_route_sources_synced = _structure_sources_version
		_route_road_synced = _road_network_version
		_route_road_debounce = 0.0
		# Do NOT force immediate rebuild here (was causing FPS hitch on every new outpost activation/connect).
		# The planner will pick up the new source on the next debounced infra refresh after some road change.
		# A short lag in routing planner state for *subsequent* placements is acceptable for smoothness.
		return
	if _road_network_version == _route_road_synced:
		_route_road_debounce = 0.0
		return
	_route_road_debounce += delta
	if _route_road_debounce < CFG.ROUTE_ROAD_INFRA_DEBOUNCE_SEC:
		return
	_route_road_synced = _road_network_version
	_route_road_debounce = 0.0
	_refresh_route_infra_and_portals()


func _poll_route_planner() -> void:
	if route_planner == null or not route_planner.ready:
		return
	if not _route_place_pending and _route_hover_request_id < 0:
		return
	var drained: int = 0
	while drained < 4:
		drained += 1
		var res: Dictionary = route_planner.poll_route()
		if not bool(res.get("ready", false)):
			break
		var req_id: int = int(res.get("request_id", -1))
		if _route_place_pending and req_id == _route_request_id:
			_route_request_id = -1
			_route_place_pending = false
			_finish_place_from_route(res, _route_pending_grid, _route_pending_landing)
			break
		elif req_id == _route_hover_request_id and _route_hover_request_id >= 0:
			_route_hover_request_id = -1
			_apply_hover_route_preview(res)


func _finish_place_from_route(
	res: Dictionary, grid: Vector2i, landing: Vector2i
) -> void:
	if battle_data == null or _build_mode == "":
		return
	var route: Dictionary = route_planner.decode_route_result(res)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty() or not bool(res.get("found", false)):
		var precheck: Dictionary = _placement_precheck(grid, _build_mode)
		var sources: Array[Vector2i] = precheck.get("sources", [])
		route = _find_placement_route(landing, _build_mode, sources, true)
		path_packed = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
			build_hint_label.text = "No water crossing found for this land bridge."
		else:
			build_hint_label.text = "Could not place outpost here."
		return
	if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		if not OutpostBuildLib.is_valid_bridge_path(battle_data, path_packed):
			build_hint_label.text = "Land bridge must cross open water (not overland)."
			return
	path_packed = OutpostBuildLib.densify_path_cardinal(battle_data, path_packed)
	var cost: float = _build_mode_cost()
	if _supply < cost:
		build_hint_label.text = "Need %s supply (have %s)." % [
			_format_supply(cost),
			_format_supply(_supply),
		]
		return
	_supply -= cost
	var src: Vector2i = route.get("source", Vector2i(-1, -1))
	var st: Dictionary = {
		"id": _next_structure_id,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": landing.x,
		"gy": landing.y,
		"kind": _build_mode,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"source_gx": src.x,
		"source_gy": src.y,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": 1.0,
	}
	if _build_mode == OutpostBuildLib.KIND_SPAWNER or _build_mode == OutpostBuildLib.KIND_BARRACKS:
		st["health"] = CFG.OUTPOST_MAX_HEALTH
	if landing != grid:
		st["click_gx"] = grid.x
		st["click_gy"] = grid.y
	battle_data.placed_structures.append(st)
	var placed_sid: int = int(st.get("id", -1))
	_next_structure_id += 1
	if _build_mode == OutpostBuildLib.KIND_SPAWNER:
		_structure_sources_version += 1
	_road_network_version += 1
	_invalidate_hover_path_cache()
	_clear_placement_preview()
	_outpost_road_dirty = true
	_outpost_marker_dirty = true
	_resource_links_dirty = true
	_enqueue_builder_job(placed_sid, BattleTileControlLib.OWNER_FRIENDLY)
	_sync_bridge_corridors_to_sim(false, true, true)  # placement; force visual now cheap via bytes
	_refresh_outpost_visuals(true, true)
	_apply_build_mode("")


func _apply_hover_route_preview(res: Dictionary) -> void:
	if globe_map == null or battle_data == null:
		return
	var route: Dictionary = route_planner.decode_route_result(res)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		_clear_placement_preview()
		return
	var is_corridor: bool = _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK
	globe_map.set_placement_preview(
		path_packed, _route_pending_landing, _hover_hint_grid, true, is_corridor
	)


func _clear_placement_preview() -> void:
	if globe_map != null:
		globe_map.clear_placement_preview()


func _sync_claimable_to_backends(force_owner_visual: bool = true, sync_agents: bool = true) -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	territory_sim.claimable_tiles = tc.claimable_tile_count
	_claimable_tiles = territory_sim.claimable_tiles
	if territory_sim.rust_live_ready and territory_sim.rust_field != null:
		territory_sim.rust_field.sync_claimable_from(tc, battle_data, true)
	if sync_agents and territory_sim.agents_ready():
		territory_sim.sync_agent_nav()
	if territory_sim.use_gpu_for_live() and territory_sim.gpu_field != null:
		territory_sim.gpu_field.refresh_claimable_from(battle_data, tc)
	if force_owner_visual:
		_apply_owner_visual_from_backends(true)


func _sync_bridge_corridors_to_sim(force_full: bool = false, sync_backends_now: bool = false, force_owner_visual: bool = true) -> void:
	if territory_sim == null or territory_sim.tile_control == null or battle_data == null:
		return
	var changed: bool = territory_sim.tile_control.sync_bridge_corridors_from_map(
		battle_data, force_full
	)
	if sync_backends_now:
		_bridge_backend_sync_pending = false
		_bridge_backend_sync_accum = 0.0
		_sync_claimable_to_backends(force_owner_visual)
	elif changed and territory_sim.agents_ready():
		territory_sim.sync_agent_nav()
	else:
		_bridge_backend_sync_pending = true


func _drain_outpost_construction_queue() -> void:
	if _outpost_construction_queue == null or not _outpost_construction_queue.has_pending():
		return
	if battle_data == null or territory_sim == null:
		return
	var plan: Dictionary = _outpost_construction_queue.drain_plan(_perf_log_frame)
	if bool(plan.get("full_map_sync", false)):
		return
	var corridor_sids: Array = plan.get("corridor_sids", [])
	if not corridor_sids.is_empty() and territory_sim.tile_control != null:
		territory_sim.tile_control.sync_bridge_corridors_for_sids(battle_data, corridor_sids, false)
		if bool(plan.get("immediate_backend", false)):
			_sync_claimable_to_backends(true, true)
		else:
			_sync_claimable_to_backends(false, false)
	var beachhead: Dictionary = plan.get("beachhead", {})
	if not beachhead.is_empty() and territory_sim.tile_control != null:
		var gx: int = int(beachhead.get("gx", 0))
		var gy: int = int(beachhead.get("gy", 0))
		var team: int = int(beachhead.get("team", BattleTileControlLib.OWNER_FRIENDLY))
		if territory_sim.tile_control.extend_beachhead_from_landing(battle_data, gx, gy, team):
			if bool(beachhead.get("immediate", false)):
				_sync_claimable_to_backends(true, true)
			else:
				_sync_claimable_to_backends(false, false)
	var road_sids: Array = plan.get("road_sids", [])
	if not road_sids.is_empty() and globe_map != null:
		_sync_roads(road_sids)
		_maybe_log_perf_action("roads", {"structures": battle_data.placed_structures.size()}, 3.0)
	var marker_sids: Array = plan.get("marker_sids", [])
	if not marker_sids.is_empty() and globe_map != null:
		_refresh_markers(marker_sids)
		_maybe_log_perf_action("markers", {"structures": battle_data.placed_structures.size()}, 3.0)
	var overlay_idxs: PackedInt32Array = plan.get("overlay_indices", PackedInt32Array())
	var overlay_vals: PackedByteArray = plan.get("overlay_values", PackedByteArray())
	if overlay_idxs.size() > 0 and globe_map != null:
		var overlay_t: int = 0
		if _frame_profiler != null:
			overlay_t = _frame_profiler.begin_phase("overlay")
		globe_map.apply_ownership_overlay_delta(overlay_idxs, overlay_vals)
		_outpost_construction_queue.request_gpu_upload()
		_last_overlay_delta_count = overlay_idxs.size()
		_last_overlay_action_frame = _perf_log_frame
		_maybe_log_perf_action("overlay:delta", {"cells": overlay_idxs.size()}, 1.0)
		if _frame_profiler != null:
			_frame_profiler.end_phase("overlay", overlay_t)
	if bool(plan.get("gpu_upload", false)) and globe_map != null:
		var gpu_t: int = 0
		if _frame_profiler != null:
			gpu_t = _frame_profiler.begin_phase("gpu_upload")
		if globe_map.flush_pending_owner_gpu_upload(false):
			_outpost_construction_queue.mark_gpu_upload_committed()
			_maybe_log_perf_action("gpu_upload", {"committed": 1}, 1.0)
		if _frame_profiler != null:
			_frame_profiler.end_phase("gpu_upload", gpu_t)


func _advance_outpost_construction(dt: float) -> void:
	if battle_data == null or dt <= 0.0 or territory_sim == null:
		return
	var sim_dirty: bool = false
	var pending_claims: Array[Vector2i] = []
	var destroyed_ids: Array[int] = []
	var completed_corridor_ids: Array[int] = []
	for st: Dictionary in battle_data.placed_structures:
		var kind: String = str(st.get("kind", ""))
		if not OutpostBuildLib.is_corridor_path_kind(kind):
			continue
		var state: String = str(st.get("state", OutpostBuildLib.STATE_ACTIVE))
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		if OutpostBuildLib.has_build_phase(kind) and state == OutpostBuildLib.STATE_BUILDING:
			_tick_outpost_construction_damage(st, gx, gy, dt, destroyed_ids)
			if destroyed_ids.has(int(st.get("id", -1))):
				continue
		elif OutpostBuildLib.has_build_phase(kind) and state == OutpostBuildLib.STATE_BUILDING:
			var build_sec: float = OutpostBuildLib.build_sec_for_kind(kind)
			var rem: float = float(st.get("build_remaining", build_sec))
			rem -= dt
			st["build_remaining"] = rem
			if rem <= 0.0:
				st["state"] = OutpostBuildLib.STATE_ACTIVE
				st.erase("build_remaining")
				st.erase("health")
				st["spawn_timer"] = 0.0
				if kind == OutpostBuildLib.KIND_SPAWNER:
					_structure_sources_version += 1
					_spawners_pending_sync = true
				_road_network_version += 1
				_invalidate_hover_path_cache()
				if _outpost_construction_queue != null:
					_outpost_construction_queue.on_build_completed(int(st.get("id", -1)))
				if kind == OutpostBuildLib.KIND_SPAWNER:
					var team = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
					var w = battle_data.grid_width
					var idx = int(st.get("gy", 0)) * w + int(st.get("gx", 0))
					var tctrl = territory_sim.tile_control if territory_sim != null else null
					if tctrl != null and idx >= 0 and idx < tctrl.owners.size() and tctrl.owners[idx] != team:
						pending_claims.append(Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0))))
				if kind != OutpostBuildLib.KIND_SPAWNER or pending_claims.size() > 0:
					sim_dirty = true
	for sid: int in destroyed_ids:
		_destroy_outpost(sid)
	for sid: int in completed_corridor_ids:
		_complete_corridor_link_by_id(sid)
	if sim_dirty:
		_sync_active_spawners_to_sim(pending_claims)


func _tick_soldier_economy(dt: float) -> void:
	if territory_sim == null or dt <= 0.0:
		return
	var living: int = territory_sim.agent_living_count()
	if not territory_sim.agents_ready() or living <= 0:
		territory_sim.agent_deficit_dps = Vector2.ZERO
		return
	var au_idx: int = ResourceLib.TYPE_AURELIUM
	var upkeep: float = float(living) * CFG.SOLDIER_UPKEEP_AURELIUM_PER_SEC * dt
	var wallet: float = _friendly_resources[au_idx]
	var paid: float = minf(upkeep, wallet)
	_friendly_resources[au_idx] = wallet - paid
	var deficit: float = upkeep - paid
	if deficit > 0.0 and upkeep > 0.0:
		var frac: float = deficit / upkeep
		territory_sim.agent_deficit_dps.x = CFG.SOLDIER_UPKEEP_DEFICIT_DPS * frac
	else:
		territory_sim.agent_deficit_dps.x = 0.0


func _tick_barracks_spawns(dt: float) -> void:
	if battle_data == null or territory_sim == null or dt <= 0.0:
		return
	if not territory_sim.agents_ready():
		return
	var au_idx: int = ResourceLib.TYPE_AURELIUM
	var spawn_cost: float = float(CFG.SOLDIER_SPAWN_AURELIUM_COST)
	for st: Dictionary in battle_data.placed_structures:
		if str(st.get("kind", "")) != OutpostBuildLib.KIND_BARRACKS:
			continue
		if str(st.get("state", "")) != OutpostBuildLib.STATE_ACTIVE:
			continue
		var bid: int = int(st.get("id", -1))
		if bid < 0:
			continue
		var timer: float = float(st.get("spawn_timer", 0.0)) + dt
		st["spawn_timer"] = timer
		if timer < CFG.BARRACKS_SPAWN_INTERVAL_SEC:
			continue
		if territory_sim.agent_living_for_barracks(bid) >= CFG.BARRACKS_MAX_ACTIVE_UNITS:
			continue
		if territory_sim.agent_living_count() >= CFG.GLOBAL_SOLDIER_CAP:
			continue
		if _friendly_resources[au_idx] < spawn_cost:
			continue
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
		territory_sim.sync_agent_nav()
		if territory_sim.try_spawn_soldier(bid, team, gx, gy):
			_friendly_resources[au_idx] -= spawn_cost
			st["spawn_timer"] = timer - CFG.BARRACKS_SPAWN_INTERVAL_SEC
			_soldier_visual_dirty = true


func _init_builder_agents() -> void:
	_builder_agents.clear()
	_builder_job_queue_friendly.clear()
	_builder_job_queue_hostile.clear()
	if _player_home.x >= 0:
		for slot in range(CFG.BUILDER_BOTS_PER_HOME):
			_builder_agents.append(
				BuilderAgentLib.make_bot(BattleTileControlLib.OWNER_FRIENDLY, _player_home, slot)
			)
	if _enemy_home.x >= 0:
		for slot in range(CFG.BUILDER_BOTS_PER_HOME):
			_builder_agents.append(
				BuilderAgentLib.make_bot(BattleTileControlLib.OWNER_HOSTILE, _enemy_home, slot)
			)
	_builder_visual_dirty = true


func _builder_job_queue_for_team(team: int) -> Array[int]:
	if team == BattleTileControlLib.OWNER_HOSTILE:
		return _builder_job_queue_hostile
	return _builder_job_queue_friendly


func _enqueue_builder_job(sid: int, team: int) -> void:
	if sid < 0:
		return
	var q: Array[int] = _builder_job_queue_for_team(team)
	if not q.has(sid):
		q.append(sid)
	_assign_builder_jobs(team)


func _assign_builder_jobs(team_filter: int = -1) -> void:
	for bot: Dictionary in _builder_agents:
		if str(bot.get("state", "")) != BuilderAgentLib.STATE_IDLE:
			continue
		var team: int = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
		if team_filter >= 0 and team != team_filter:
			continue
		var q: Array[int] = _builder_job_queue_for_team(team)
		while not q.is_empty():
			var sid: int = q[0]
			var st: Dictionary = _find_structure_by_sid(sid)
			if st.is_empty() or str(st.get("state", "")) != OutpostBuildLib.STATE_CONNECTING:
				q.remove_at(0)
				continue
			q.remove_at(0)
			_start_builder_job(bot, sid)
			break


func _start_builder_job(bot: Dictionary, sid: int) -> void:
	var st: Dictionary = _find_structure_by_sid(sid)
	if st.is_empty():
		return
	bot["state"] = BuilderAgentLib.STATE_WORKING
	bot["job_sid"] = sid
	bot["seg_from_idx"] = BuilderAgentLib.next_seg_index(float(st.get("path_built", 1.0)))
	bot["seg_t"] = 0.0
	bot["return_t"] = 0.0
	_builder_visual_dirty = true


func _begin_builder_return(bot: Dictionary) -> void:
	var pos: Vector2 = _builder_work_grid_pos(bot)
	bot["return_gx_f"] = pos.x
	bot["return_gy_f"] = pos.y
	bot["state"] = BuilderAgentLib.STATE_RETURNING
	bot["job_sid"] = -1
	bot["seg_t"] = 0.0
	bot["return_t"] = 0.0
	_builder_visual_dirty = true


func _find_structure_by_sid(sid: int) -> Dictionary:
	if sid < 0 or battle_data == null:
		return {}
	for st: Dictionary in battle_data.placed_structures:
		if int(st.get("id", -1)) == sid:
			return st
	return {}


func _cancel_builder_job_for_sid(sid: int) -> void:
	if sid < 0:
		return
	_builder_job_queue_friendly.erase(sid)
	_builder_job_queue_hostile.erase(sid)
	for bot: Dictionary in _builder_agents:
		if int(bot.get("job_sid", -1)) == sid:
			_begin_builder_return(bot)


func _update_builder_agents(dt: float) -> void:
	if battle_data == null or dt <= 0.0 or _builder_agents.is_empty():
		return
	var travel_sec: float = BuilderAgentLib.cell_travel_sec()
	var completed_corridor_ids: Array[int] = []
	for bot: Dictionary in _builder_agents:
		var state: String = str(bot.get("state", ""))
		if state == BuilderAgentLib.STATE_IDLE:
			bot["orbit_angle"] = float(bot.get("orbit_angle", 0.0)) + CFG.BUILDER_ORBIT_SPEED * dt
			continue
		if state == BuilderAgentLib.STATE_RETURNING:
			var ret_t: float = float(bot.get("return_t", 0.0)) + dt / maxf(CFG.BUILDER_RETURN_SEC, 0.001)
			bot["return_t"] = ret_t
			if ret_t >= 1.0:
				bot["state"] = BuilderAgentLib.STATE_IDLE
				bot["return_t"] = 0.0
				_assign_builder_jobs(int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY)))
			_builder_visual_dirty = true
			continue
		if state != BuilderAgentLib.STATE_WORKING:
			continue
		var job_sid: int = int(bot.get("job_sid", -1))
		var st: Dictionary = _find_structure_by_sid(job_sid)
		if st.is_empty() or str(st.get("state", "")) != OutpostBuildLib.STATE_CONNECTING:
			_begin_builder_return(bot)
			_assign_builder_jobs(int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY)))
			continue
		var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
		var seg_idx: int = int(bot.get("seg_from_idx", 0))
		if packed.size() < 2 or seg_idx >= packed.size() - 1:
			_on_builder_path_completed(st, completed_corridor_ids)
			_begin_builder_return(bot)
			_assign_builder_jobs(int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY)))
			continue
		var seg_t: float = float(bot.get("seg_t", 0.0)) + dt / maxf(travel_sec, 0.001)
		var job_finished: bool = false
		while seg_t >= 1.0:
			seg_t -= 1.0
			_on_builder_cell_arrival(st, seg_idx)
			var path_len: int = OutpostBuildLib.path_len_from_structure(st)
			if path_len <= 0:
				path_len = int(st.get("path_len", 0))
			st["path_len"] = path_len
			var built: float = float(st.get("path_built", 1.0))
			if built >= float(path_len):
				_on_builder_path_completed(st, completed_corridor_ids)
				_begin_builder_return(bot)
				_assign_builder_jobs(int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY)))
				job_finished = true
				break
			seg_idx += 1
			if seg_idx >= packed.size() - 1:
				_on_builder_path_completed(st, completed_corridor_ids)
				_begin_builder_return(bot)
				_assign_builder_jobs(int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY)))
				job_finished = true
				break
		if job_finished:
			_builder_visual_dirty = true
			continue
		bot["seg_from_idx"] = seg_idx
		bot["seg_t"] = seg_t
		_builder_visual_dirty = true
	for sid: int in completed_corridor_ids:
		_complete_corridor_link_by_id(sid)


func _on_builder_cell_arrival(st: Dictionary, seg_from_idx: int) -> void:
	st["path_built"] = BuilderAgentLib.path_built_after_seg(seg_from_idx)
	var kind: String = str(st.get("kind", ""))
	var path_sid: int = int(st.get("id", -1))
	if OutpostBuildLib.is_corridor_path_kind(kind) and kind != OutpostBuildLib.KIND_CORRIDOR_LINK:
		_road_network_version += 1
		if kind == OutpostBuildLib.KIND_SPAWNER:
			_resource_links_dirty = true
	if _outpost_construction_queue != null:
		_outpost_construction_queue.on_cell_advanced(path_sid)


func _on_builder_path_completed(st: Dictionary, completed_corridor_ids: Array[int]) -> void:
	var path_len: int = OutpostBuildLib.path_len_from_structure(st)
	if path_len <= 0:
		path_len = int(st.get("path_len", 0))
	st["path_len"] = path_len
	st["path_built"] = float(path_len)
	var kind: String = str(st.get("kind", ""))
	var is_corridor_link: bool = kind == OutpostBuildLib.KIND_CORRIDOR_LINK
	var done_sid: int = int(st.get("id", -1))
	var gx: int = int(st.get("gx", 0))
	var gy: int = int(st.get("gy", 0))
	var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	if _outpost_construction_queue != null:
		_outpost_construction_queue.on_path_completed(done_sid, gx, gy, team, is_corridor_link)
	if is_corridor_link:
		completed_corridor_ids.append(done_sid)
	else:
		st["state"] = OutpostBuildLib.STATE_BUILDING
		st["build_remaining"] = OutpostBuildLib.build_sec_for_kind(kind)


func _builder_home_grid(bot: Dictionary) -> Vector2i:
	return Vector2i(int(bot.get("home_gx", 0)), int(bot.get("home_gy", 0)))


func _builder_work_grid_pos(bot: Dictionary) -> Vector2:
	var state: String = str(bot.get("state", ""))
	var home: Vector2i = _builder_home_grid(bot)
	if state == BuilderAgentLib.STATE_IDLE:
		return BuilderAgentLib.orbit_grid(home, float(bot.get("orbit_angle", 0.0)))
	if state == BuilderAgentLib.STATE_RETURNING:
		var ret_t: float = clampf(float(bot.get("return_t", 0.0)), 0.0, 1.0)
		var orbit: Vector2 = BuilderAgentLib.orbit_grid(home, float(bot.get("orbit_angle", 0.0)))
		var from_g: Vector2 = Vector2(
			float(bot.get("return_gx_f", orbit.x)),
			float(bot.get("return_gy_f", orbit.y)),
		)
		return from_g.lerp(orbit, ret_t)
	var st: Dictionary = _find_structure_by_sid(int(bot.get("job_sid", -1)))
	if st.is_empty() or battle_data == null:
		return BuilderAgentLib.orbit_grid(home, float(bot.get("orbit_angle", 0.0)))
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	var w: int = battle_data.grid_width
	var seg_idx: int = int(bot.get("seg_from_idx", 0))
	if packed.size() < 2 or seg_idx >= packed.size() - 1:
		var landing: Vector2i = Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0)))
		return Vector2(float(landing.x), float(landing.y))
	var from_cell: Vector2i = OutpostBuildLib.grid_from_packed_key(packed[seg_idx], w)
	var to_cell: Vector2i = OutpostBuildLib.grid_from_packed_key(packed[seg_idx + 1], w)
	var t: float = clampf(float(bot.get("seg_t", 0.0)), 0.0, 1.0)
	return Vector2(float(from_cell.x), float(from_cell.y)).lerp(
		Vector2(float(to_cell.x), float(to_cell.y)), t
	)


func _update_builder_visuals(delta: float) -> void:
	if globe_map == null or _builder_agents.is_empty():
		return
	_builder_visual_clock += delta
	var refresh_sec: float = 1.0 / CFG.SOLDIER_VISUAL_UPDATES_PER_SEC
	if not _builder_visual_dirty and _builder_visual_clock < refresh_sec:
		return
	_builder_visual_clock = 0.0
	_builder_visual_dirty = false
	var positions: Array = []
	var teams := PackedByteArray()
	teams.resize(_builder_agents.size())
	for i in range(_builder_agents.size()):
		var bot: Dictionary = _builder_agents[i]
		var grid_pos: Vector2 = _builder_work_grid_pos(bot)
		positions.append(
			globe_map.grid_float_surface_pos(grid_pos.x, grid_pos.y, CFG.BUILDER_SURFACE_LIFT)
		)
		teams[i] = int(bot.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	globe_map.sync_builders(positions, teams)


func _update_soldier_visuals(delta: float) -> void:
	if globe_map == null or territory_sim == null:
		return
	if not territory_sim.agents_ready():
		globe_map.sync_soldiers(PackedByteArray(), PackedInt32Array(), PackedInt32Array())
		return
	_soldier_visual_clock += delta
	var soldier_refresh_sec: float = 1.0 / CFG.SOLDIER_VISUAL_UPDATES_PER_SEC
	if not _soldier_visual_dirty and _soldier_visual_clock < soldier_refresh_sec:
		return
	_soldier_visual_clock = 0.0
	_soldier_visual_dirty = false
	var snap: Dictionary = territory_sim.get_agent_snapshot()
	globe_map.sync_soldiers(
		snap.get("teams", PackedByteArray()),
		snap.get("gx", PackedInt32Array()),
		snap.get("gy", PackedInt32Array()),
	)


func _complete_corridor_link_by_id(sid: int) -> void:
	if sid < 0 or battle_data == null:
		return
	var st: Dictionary = {}
	var idx: int = -1
	for i in range(battle_data.placed_structures.size() - 1, -1, -1):
		var candidate: Dictionary = battle_data.placed_structures[i]
		if int(candidate.get("id", -1)) == sid:
			st = candidate
			idx = i
			break
	if idx < 0:
		return
	var gx: int = int(st.get("gx", 0))
	var gy: int = int(st.get("gy", 0))
	battle_data.bridge_corridors.append({
		"id": sid,
		"team": int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
		"gx": gx,
		"gy": gy,
		"path_keys": st.get("path_keys", PackedInt32Array()),
	})
	battle_data.placed_structures.remove_at(idx)
	_sync_bridge_corridors_to_sim(true, true, true)  # corridor link: force owner visual for new land
	_extend_beachhead_at_landing(st, gx, gy)
	_structure_sources_version += 1
	_road_network_version += 1
	_resource_links_dirty = true
	_invalidate_hover_path_cache()
	_outpost_road_dirty = true
	_outpost_marker_dirty = true
	_refresh_outpost_visuals(true, true)


func _tick_outpost_construction_damage(
	st: Dictionary, gx: int, gy: int, dt: float, destroyed_ids: Array[int]
) -> void:
	var tc := territory_sim.tile_control
	if tc == null:
		return
	var dps: float = OutpostBuildLib.construction_dps_at(battle_data, tc, gx, gy)
	if dps <= 0.0:
		return
	var max_hp: float = CFG.OUTPOST_MAX_HEALTH
	var prev_hp_i: int = int(ceil(float(st.get("health", max_hp))))
	var hp: float = float(st.get("health", max_hp)) - dps * dt
	st["health"] = hp
	if hp <= 0.0:
		destroyed_ids.append(int(st.get("id", -1)))
	elif int(ceil(hp)) != prev_hp_i:
		_outpost_marker_dirty = true


func _destroy_outpost(sid: int) -> void:
	if sid < 0 or battle_data == null:
		return
	var grid: Vector2i = Vector2i(-1, -1)
	var was_barracks: bool = false
	for i in range(battle_data.placed_structures.size() - 1, -1, -1):
		var st: Dictionary = battle_data.placed_structures[i]
		if int(st.get("id", -1)) != sid:
			continue
		grid = Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0)))
		was_barracks = str(st.get("kind", "")) == OutpostBuildLib.KIND_BARRACKS
		battle_data.placed_structures.remove_at(i)
		break
	if grid.x < 0:
		return
	_cancel_builder_job_for_sid(sid)
	if was_barracks and territory_sim != null:
		territory_sim.notify_barracks_destroyed(sid)
		_soldier_visual_dirty = true
	if globe_map != null:
		globe_map.clear_road(sid)
		globe_map.spawn_outpost_destroy_fx(grid)
	_structure_sources_version += 1
	_road_network_version += 1
	_invalidate_hover_path_cache()
	_outpost_road_dirty = true
	_outpost_marker_dirty = true
	_sync_bridge_corridors_to_sim(true, true, false)  # destroy: no need to force full owner visual
	_refresh_outpost_visuals(true, true)


func _outpost_risk_hint(gx: int, gy: int) -> String:
	if territory_sim == null or territory_sim.tile_control == null:
		return ""
	var dps: float = OutpostBuildLib.construction_dps_at(
		battle_data, territory_sim.tile_control, gx, gy
	)
	if dps <= 0.0:
		return "No damage while building here."
	return "Enemy territory — %.0f DPS vs %d HP." % [dps, int(CFG.OUTPOST_MAX_HEALTH)]


func _placement_risk_hint(gx: int, gy: int) -> String:
	if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return "Opens beachhead when bridge connects — place outposts afterward."
	return _outpost_risk_hint(gx, gy)


func _extend_beachhead_at_landing(st: Dictionary, gx: int, gy: int, defer_backend_sync: bool = false) -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	if territory_sim.tile_control.extend_beachhead_from_landing(battle_data, gx, gy, team):
		if defer_backend_sync and _outpost_construction_queue != null:
			_outpost_construction_queue.enqueue_corridor(int(st.get("id", -1)))
		else:
			_sync_claimable_to_backends(true)


func _has_active_construction() -> bool:
	if battle_data == null:
		return false
	for st: Dictionary in battle_data.placed_structures:
		var state: String = str(st.get("state", OutpostBuildLib.STATE_ACTIVE))
		if state == OutpostBuildLib.STATE_CONNECTING:
			return true
		var kind: String = str(st.get("kind", ""))
		if OutpostBuildLib.has_build_phase(kind) and state == OutpostBuildLib.STATE_BUILDING:
			return true
	return false


func _maintain_bridge_corridors() -> void:
	if battle_data == null or territory_sim == null or territory_sim.tile_control == null:
		return
	if _bridges_repaired or battle_data.bridge_corridors.is_empty():
		return
	_repair_bridge_corridor_paths()
	_bridges_repaired = true


func _repair_bridge_corridor_paths() -> void:
	if battle_data == null or territory_sim == null:
		return
	var changed: bool = false
	for corridor: Dictionary in battle_data.bridge_corridors:
		var packed: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
		if packed.is_empty():
			continue
		var dense: PackedInt32Array = OutpostBuildLib.densify_path_cardinal(battle_data, packed)
		if dense.size() != packed.size():
			corridor["path_keys"] = dense
			changed = true
	_sync_bridge_corridors_to_sim(true, true)
	for corridor: Dictionary in battle_data.bridge_corridors:
		var gx: int = int(corridor.get("gx", -1))
		var gy: int = int(corridor.get("gy", -1))
		if gx < 0:
			continue
		_extend_beachhead_at_landing(corridor, gx, gy)
	if changed:
		_outpost_road_dirty = true
		_refresh_outpost_visuals(true, false)


func _update_tile_probe() -> void:
	if tile_probe_label == null or battle_data == null or territory_sim == null:
		return
	var tc := territory_sim.tile_control
	if tc == null:
		return
	var grid: Vector2i = _mouse_to_grid()
	var bridge_stats: Dictionary = tc.count_claimable_bridge_cells(battle_data)
	var bridge_line: String = (
		"Bridges %d · water %d/%d claimable"
		% [
			int(bridge_stats.get("landings", 0)),
			int(bridge_stats.get("water_claimable", 0)),
			int(bridge_stats.get("water_total", 0)),
		]
	)
	if not _is_on_map_grid(grid.x, grid.y):
		tile_probe_label.text = "%s\nMove cursor over the globe." % bridge_line
		return
	var probe: Dictionary = tc.tile_probe(battle_data, grid.x, grid.y)
	if not bool(probe.get("valid", false)):
		tile_probe_label.text = bridge_line
		return
	tile_probe_label.text = (
		(
			"%s\n(%s,%s) %s · %s · claim=%s flow=%.2f\n"
			+ "Blue %.2f · Red %.2f\n"
			+ "reach F%s H%s · bridge F%s H%s · corridor F%s"
		)
		% [
			bridge_line,
			probe.get("gx", 0),
			probe.get("gy", 0),
			probe.get("terrain", "?"),
			probe.get("owner", "?"),
			probe.get("claimable", false),
			float(probe.get("flow_mult", 0.0)),
			float(probe.get("pf", 0.0)),
			float(probe.get("ph", 0.0)),
			probe.get("f_reach", false),
			probe.get("h_reach", false),
			probe.get("f_bridge", false),
			probe.get("h_bridge", false),
			probe.get("f_corridor", false),
		]
	)


func _on_inspect_toggled(on: bool) -> void:
	_tile_inspect_active = on
	if tile_probe_label:
		tile_probe_label.visible = on
	if on:
		_update_tile_probe()
	elif tile_probe_label:
		tile_probe_label.text = ""


func _sync_active_spawners_to_sim(pending_claims: Array = []) -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	tc.sync_placed_spawners_from_map(battle_data)
	tc.sync_bridge_corridors_from_map(battle_data, true)
	territory_sim.claimable_tiles = tc.claimable_tile_count
	_claimable_tiles = territory_sim.claimable_tiles
	for cell in pending_claims:
		if cell is Vector2i:
			tc.claim_tile(cell.x, cell.y, BattleTileControlLib.OWNER_FRIENDLY)
	var had_new_claims = pending_claims.size() > 0
	if territory_sim.rust_live_ready and territory_sim.rust_field != null:
		if had_new_claims:
			territory_sim.rust_field.sync_claimable_from(tc, battle_data, true)
		territory_sim.rust_field.sync_spawners_from(tc)  # always needed for the new active pump
	if territory_sim.use_gpu_for_live() and territory_sim.gpu_field != null:
		if had_new_claims:
			territory_sim.gpu_field.refresh_claimable_from(battle_data, tc)
	# No forced owner visual here when no new claims (outpost in already controlled land).
	# The spawners list is synced so the new pressure source works. Marker visual will update the outpost color.


func _sync_counts() -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	_sim_time = territory_sim.sim_time
	_friendly_tiles = tc.friendly_tiles
	_hostile_tiles = tc.hostile_tiles


func _watch_fps_drops(fps: int) -> void:
	_fps_log_cooldown = maxf(0.0, _fps_log_cooldown - 0.12)
	if fps < 42:
		_fps_low_streak += 1
	else:
		_fps_low_streak = 0
		return
	if _fps_low_streak < 4 or _fps_log_cooldown > 0.0:
		return
	_fps_low_streak = 0
	_fps_log_cooldown = 8.0
	RunLog.warn(
		perf_format_log_line(
			"fps_drop",
			gather_perf_and_action_context(),
			{"note": "likely_gpu"}
		)
	)


func _on_play_area_resized(_fit: bool = false) -> void:
	if play_area == null or sub_viewport == null:
		return
	var top: float = summary_bar.size.y + 12.0 if summary_bar else 132.0
	var bottom_h: float = $HUD.size.y + 12.0 if has_node("HUD") else 88.0
	play_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_area.offset_top = top
	play_area.offset_bottom = -bottom_h
	var play_size: Vector2 = play_area.size
	if play_size.x < 8.0 or play_size.y < 8.0:
		return
	sub_viewport_container.stretch = true
	var scale: float = CFG.GLOBE_RENDER_SCALE
	sub_viewport.size = Vector2i(
		maxi(int(play_size.x * scale), 1),
		maxi(int(play_size.y * scale), 1),
	)


func _update_hud() -> void:
	var fp: float = 0.0
	var ep: float = 0.0
	if territory_sim != null:
		var totals: Vector2 = territory_sim.power_totals()
		fp = totals.x
		ep = totals.y
	blue_count_label.text = _format_supply(fp)
	red_count_label.text = _format_supply(ep)
	blue_sub_label.text = "%d%% · %d tiles" % [_pct(_friendly_tiles), _friendly_tiles]
	red_sub_label.text = "%d%% · %d tiles" % [_pct(_hostile_tiles), _hostile_tiles]
	if blue_resources_label:
		blue_resources_label.text = _format_resources_line(_friendly_resources)
	if red_resources_label:
		red_resources_label.text = _format_resources_line(_hostile_resources)
	time_label.text = _format_sim_time(_sim_time)
	supply_label.text = "Supply %s" % _format_supply(_supply)
	var fps := Engine.get_frames_per_second()
	_watch_fps_drops(int(fps))
	if _show_perf_hud and perf_hud_label:
		perf_hud_label.visible = true
		perf_hud_label.text = perf_build_hud_text(gather_perf_and_action_context())
	elif perf_hud_label:
		perf_hud_label.visible = false
	status_label.text = (
		"World Conquest  |  %s  |  x%.0f  |  soldiers %d/%d  |  FPS %d  |  drag globe · scroll zoom"
		% [
			"PAUSED" if _paused else "LIVE",
			_speed_mult,
			territory_sim.agent_living_count() if territory_sim != null else 0,
			CFG.GLOBAL_SOLDIER_CAP,
			int(fps),
		]
	)
	speed_button.text = "▶ x%.0f" % _speed_mult
	spawner_button.text = "Outpost (%s)" % _format_supply(float(CFG.SPAWNER_COST_SUPPLY))
	if barracks_button:
		barracks_button.text = "Barracks (%s)" % _format_supply(float(CFG.BARRACKS_COST_SUPPLY))
	if corridor_link_button:
		corridor_link_button.text = "Land Bridge (%s)" % _format_supply(
			float(CFG.CORRIDOR_LINK_COST_SUPPLY)
		)


func _style_summary_hud() -> void:
	if supply_label:
		supply_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		supply_label.add_theme_font_size_override("font_size", 18)


func _update_build_ui() -> void:
	spawner_button.set_block_signals(true)
	spawner_button.button_pressed = _build_mode == OutpostBuildLib.KIND_SPAWNER
	spawner_button.set_block_signals(false)
	if corridor_link_button:
		corridor_link_button.set_block_signals(true)
		corridor_link_button.button_pressed = _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK
		corridor_link_button.set_block_signals(false)
	if barracks_button:
		barracks_button.set_block_signals(true)
		barracks_button.button_pressed = _build_mode == OutpostBuildLib.KIND_BARRACKS
		barracks_button.set_block_signals(false)
	if _build_mode == OutpostBuildLib.KIND_SPAWNER:
		build_hint_label.text = (
			(
				"Left-click connected land (%s). Use Land Bridge first for foreign coasts. "
				+ "~%.0fs build after any bridge segment. Esc cancel."
			)
			% [_format_supply(float(CFG.SPAWNER_COST_SUPPLY)), CFG.OUTPOST_BUILD_SEC]
		)
		_update_build_hover_hint()
	elif _build_mode == OutpostBuildLib.KIND_BARRACKS:
		build_hint_label.text = (
			(
				"Left-click connected land (%s). Road builds, then ~%.0fs barracks build. "
				+ "Spawns cost Au. Esc cancel."
			)
			% [_format_supply(float(CFG.BARRACKS_COST_SUPPLY)), CFG.BARRACKS_BUILD_SEC]
		)
		_update_build_hover_hint()
	elif _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		build_hint_label.text = (
			(
				"Left-click enemy or neutral coast (%s). Inland clicks snap to shore. "
				+ "Route crosses water — short land leg from your territory, then bridge to landing. Esc cancel."
			)
			% _format_supply(float(CFG.CORRIDOR_LINK_COST_SUPPLY))
		)
		_update_build_hover_hint()
	else:
		build_hint_label.text = (
			"Outpost (%s) · Barracks (%s) · Land Bridge (%s)"
			% [
				_format_supply(float(CFG.SPAWNER_COST_SUPPLY)),
				_format_supply(float(CFG.BARRACKS_COST_SUPPLY)),
				_format_supply(float(CFG.CORRIDOR_LINK_COST_SUPPLY)),
			]
		)


func _update_build_hover_hint() -> void:
	if not _is_build_mode_active():
		_clear_placement_preview()
		return
	var grid: Vector2i = _mouse_to_grid()
	if grid == _hover_hint_grid:
		return
	_hover_hint_grid = grid
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Move cursor over the globe."
		return
	var reject: String = _placement_hover_reject(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = "(%d,%d) — %s" % [grid.x, grid.y, reject]
		_clear_placement_preview()
		return
	build_hint_label.text = "(%d,%d) Click to place — %s" % [
		grid.x, grid.y, _placement_risk_hint(grid.x, grid.y),
	]
	_request_hover_route_preview(grid)


func _request_hover_route_preview(grid: Vector2i) -> void:
	if not CFG.ROUTE_HOVER_PREVIEW:
		return
	if route_planner == null or not route_planner.ready or battle_data == null:
		return
	if _build_mode == "":
		return
	if _route_hover_clock < CFG.OUTPOST_HOVER_REPLAN_SEC:
		return
	_route_hover_clock = 0.0
	var precheck: Dictionary = _placement_precheck(grid, _build_mode)
	if str(precheck.get("reject", "")) != "":
		_clear_placement_preview()
		return
	var landing: Vector2i = precheck.get("landing", Vector2i(-1, -1))
	if landing.x < 0:
		_clear_placement_preview()
		return
	if landing == _hover_landing_grid and _route_hover_request_id >= 0:
		return
	_hover_landing_grid = landing
	_route_pending_landing = landing
	if _route_hover_request_id >= 0:
		route_planner.cancel_route(_route_hover_request_id)
	var allow_astar: bool = CFG.OUTPOST_HOVER_ALLOW_ASTAR
	_route_hover_request_id = route_planner.start_route_async(landing, _build_mode, allow_astar)


func _apply_build_mode(mode: String) -> void:
	_build_mode = mode
	_route_hover_clock = 0.0
	_invalidate_hover_path_cache()
	if mode != "":
		_ensure_route_planner()
		if (
			_structure_sources_version != _route_sources_synced
			or _road_network_version != _route_road_synced
		):
			_refresh_route_infra_and_portals()
			_route_sources_synced = _structure_sources_version
			_route_road_synced = _road_network_version
			_route_road_debounce = 0.0
	if mode == OutpostBuildLib.KIND_SPAWNER and barracks_button:
		barracks_button.set_block_signals(true)
		barracks_button.button_pressed = false
		barracks_button.set_block_signals(false)
		if corridor_link_button:
			corridor_link_button.set_block_signals(true)
			corridor_link_button.button_pressed = false
			corridor_link_button.set_block_signals(false)
	elif mode == OutpostBuildLib.KIND_BARRACKS:
		spawner_button.set_block_signals(true)
		spawner_button.button_pressed = false
		spawner_button.set_block_signals(false)
		if corridor_link_button:
			corridor_link_button.set_block_signals(true)
			corridor_link_button.button_pressed = false
			corridor_link_button.set_block_signals(false)
	elif mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		spawner_button.set_block_signals(true)
		spawner_button.button_pressed = false
		spawner_button.set_block_signals(false)
		if barracks_button:
			barracks_button.set_block_signals(true)
			barracks_button.button_pressed = false
			barracks_button.set_block_signals(false)
	if mode == "":
		_clear_placement_preview()
	_update_build_ui()


func _on_spawner_toggled(on: bool) -> void:
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_SPAWNER)
	elif _build_mode == OutpostBuildLib.KIND_SPAWNER:
		_apply_build_mode("")


func _on_corridor_link_toggled(on: bool) -> void:
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_CORRIDOR_LINK)
	elif _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		_apply_build_mode("")


func _on_barracks_toggled(on: bool) -> void:
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_BARRACKS)
	elif _build_mode == OutpostBuildLib.KIND_BARRACKS:
		_apply_build_mode("")


func _on_pause_pressed() -> void:
	_paused = not _paused


func _on_speed_pressed() -> void:
	if _speed_mult < 1.5:
		_speed_mult = 2.0
	elif _speed_mult < 3.0:
		_speed_mult = 4.0
	else:
		_speed_mult = 1.0


func _on_battle_finished() -> void:
	_battle_finished = true
	var res: Dictionary = territory_sim.get_result()
	var won: bool = bool(res.get("player_won", false))
	var reason: String = str(res.get("end_reason", ""))
	var headline: String = "TOTAL CONQUEST" if won and reason == "total_conquest" else (
		"ENEMY ROUTED" if won and reason == "enemy_zero_power" else (
			"DEFEAT — ENEMY CONQUEST" if not won and reason == "total_conquest" else (
				"VICTORY" if won else "DEFEAT"
			)
		)
	)
	end_label.text = (
		"%s\n\n%s%% of claimable land after %s.\n(%s)\n\nPress Back to exit."
		% [
			headline,
			_pct(_friendly_tiles),
			_format_sim_time(_sim_time),
			reason,
		]
	)
	end_overlay.visible = true


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_show_perf_hud = not _show_perf_hud
			if perf_hud_label:
				perf_hud_label.visible = _show_perf_hud
				if _show_perf_hud:
					perf_hud_label.text = perf_build_hud_text(gather_perf_and_action_context())
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_apply_build_mode("")


func _is_on_map_grid(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < battle_data.grid_width and gy < battle_data.grid_height


func _pct(tiles: int) -> int:
	if _claimable_tiles <= 0:
		return 0
	return int(round(float(tiles) * 100.0 / float(_claimable_tiles)))


func _format_supply(v: float) -> String:
	return "%d" % int(round(v))


func _format_resources_line(wallet: Array[float]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in CFG.RESOURCE_TYPE_COUNT:
		var short: String = CFG.RESOURCE_SHORT[i] if i < CFG.RESOURCE_SHORT.size() else "?"
		parts.append("%s %d" % [short, int(floor(wallet[i]))])
	return "  ".join(parts)


func _format_sim_time(t: float) -> String:
	var day: int = int(t / 60.0) + 1
	var sec: int = int(t) % 60
	var minute: int = int(t / 60.0) % 60
	return "Day %d  %02d:%02d" % [day, minute, sec]


static func perf_gather_gpu_counters() -> Dictionary:
	return {
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"video_mem_mb": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		"texture_mem_mb": float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
	}


static func perf_gather_action_context(fields: Dictionary) -> Dictionary:
	return {
		"sim_steps": int(fields.get("sim_steps", 0)),
		"overlay_delta": int(fields.get("overlay_delta", 0)),
		"gpu_pending": bool(fields.get("gpu_pending", false)),
	}


static func perf_format_action_tag(action: String, fields: Dictionary = {}) -> String:
	var parts: PackedStringArray = PackedStringArray(["action=%s" % action])
	for key in fields.keys():
		parts.append("%s=%s" % [str(key), str(fields[key])])
	return " ".join(parts)


static func perf_format_log_line(action: String, snapshot: Dictionary, extra: Dictionary = {}) -> String:
	var fields: Dictionary = extra.duplicate()
	fields["frame"] = int(snapshot.get("frame", -1))
	fields["fps"] = int(snapshot.get("fps", 0.0))
	var cpu: Dictionary = snapshot.get("cpu", {})
	var gpu: Dictionary = snapshot.get("gpu", {})
	fields["cpu_p99"] = "%.1fms" % float(cpu.get("p99_ms", 0.0))
	fields["draw"] = int(gpu.get("draw_calls", 0))
	fields["vid_mb"] = "%.1f" % float(gpu.get("video_mem_mb", 0.0))
	var action_ctx: Dictionary = snapshot.get("action", {})
	if not action_ctx.is_empty():
		fields["sim_steps"] = int(action_ctx.get("sim_steps", 0))
		fields["overlay_delta"] = int(action_ctx.get("overlay_delta", 0))
		fields["gpu_pending"] = int(action_ctx.get("gpu_pending", false))
	return perf_format_action_tag(action, fields)


static func perf_build_hud_text(snapshot: Dictionary) -> String:
	var fps := float(snapshot.get("fps", 0.0))
	var cpu: Dictionary = snapshot.get("cpu", {})
	var gpu: Dictionary = snapshot.get("gpu", {})
	var action: Dictionary = snapshot.get("action", {})
	var lines: PackedStringArray = PackedStringArray()
	lines.append("FPS %.0f" % fps)
	if not cpu.is_empty():
		lines.append(
			"CPU p50=%.1f p95=%.1f p99=%.1f ms (min_fps %.0f)"
			% [
				float(cpu.get("p50_ms", 0.0)),
				float(cpu.get("p95_ms", 0.0)),
				float(cpu.get("p99_ms", 0.0)),
				float(cpu.get("min_fps", 0.0)),
			]
		)
	else:
		lines.append("CPU (warming up)")
	lines.append(
		"GPU draw=%d objs=%d vid=%.0fMB tex=%.0fMB"
		% [
			int(gpu.get("draw_calls", 0)),
			int(gpu.get("objects", 0)),
			float(gpu.get("video_mem_mb", 0.0)),
			float(gpu.get("texture_mem_mb", 0.0)),
		]
	)
	lines.append(
		"ctx sim_steps=%d overlay_delta=%d gpu_pending=%s"
		% [
			int(action.get("sim_steps", 0)),
			int(action.get("overlay_delta", 0)),
			"yes" if bool(action.get("gpu_pending", false)) else "no",
		]
	)
	return "\n".join(lines)


func gather_perf_and_action_context(sim_steps: int = -1) -> Dictionary:
	if sim_steps < 0:
		sim_steps = _last_frame_sim_steps
	var cpu_summary: Dictionary = {}
	if _frame_profiler != null:
		cpu_summary = _frame_profiler.summary()
	var gpu_pending := false
	if globe_map != null and globe_map.has_method("owner_gpu_upload_pending"):
		gpu_pending = globe_map.owner_gpu_upload_pending()
	return {
		"frame": _perf_log_frame,
		"fps": float(Engine.get_frames_per_second()),
		"cpu": cpu_summary,
		"gpu": perf_gather_gpu_counters(),
		"action": perf_gather_action_context({
			"sim_steps": sim_steps,
			"overlay_delta": _last_overlay_delta_count,
			"gpu_pending": gpu_pending,
		}),
	}


func _decrement_perf_action_cooldowns(delta: float) -> void:
	for key in _perf_action_cooldowns.keys():
		_perf_action_cooldowns[key] = maxf(0.0, float(_perf_action_cooldowns[key]) - delta)


func get_recent_perf_action_lines() -> Array[String]:
	return _recent_perf_action_lines.duplicate()


func _maybe_log_perf_action(action: String, fields: Dictionary, cooldown_sec: float) -> void:
	if float(_perf_action_cooldowns.get(action, 0.0)) > 0.0:
		return
	_perf_action_cooldowns[action] = cooldown_sec
	var line: String = perf_format_log_line(action, gather_perf_and_action_context(), fields)
	_recent_perf_action_lines.append(line)
	if _recent_perf_action_lines.size() > PERF_RECENT_ACTION_MAX:
		_recent_perf_action_lines.pop_front()
	RunLog.info(line)


func reset_perf_action_telemetry() -> void:
	_recent_perf_action_lines.clear()
	_perf_action_cooldowns.clear()
	if _frame_profiler != null:
		_frame_profiler.reset_samples()
