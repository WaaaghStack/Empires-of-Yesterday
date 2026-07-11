extends Control

const CFG := preload("res://WorldConquestConfig.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
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
const EnemyStrategyLib := preload("res://EnemyStrategy.gd")
const EconomyLib := preload("res://EconomyLib.gd")
const WorldDatasetAssertLib := preload("res://WorldDatasetAssert.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const PresentationApplyLib := preload("res://WorldConquestPresentationApply.gd")
const Scd1DomainPullLib := preload("res://Scd1DomainPull.gd")

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
@onready var hangar_button: Button = $HUD/HBox/HangarButton
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
var _enemy_supply: float = 0.0
var _enemy_ai_clock: float = 0.0
var _enemy_ai_difficulty: int = CFG.ENEMY_AI_DEFAULT_DIFFICULTY
var _enemy_ai_action_queue: Array[Dictionary] = []
## A1/E8: set when live WorldDataset entry fails (missing DLL / assert).
var _world_dataset_entry_failed: bool = false
## SCD1 versioned domain pulls (live paint — replaces PresentationTxn).
var _scd1_pull: Scd1DomainPullLib = Scd1DomainPullLib.new()
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
var _network_road_pending: PackedInt32Array = PackedInt32Array()
var _soldier_visual_dirty: bool = true
var _soldier_visual_clock: float = 0.0
var _bomber_visual_dirty: bool = true
var _bomber_visual_clock: float = 0.0
## Structure render cache apply deferred into pull_presentation_delta (live Rust only).
var _presentation_structures_dirty: bool = false
var _presentation_structure_merge: Dictionary = {}
## Counts full structure snapshots requested via presentation pull (perf / QA instrumentation).
var _structure_snapshot_pull_count: int = 0
var route_planner: RoutePlannerLib
var _route_request_id: int = -1
var _route_place_pending: bool = false
var _route_pending_grid: Vector2i = Vector2i(-1, -1)
var _route_pending_landing: Vector2i = Vector2i(-1, -1)
var _route_pending_mode: String = ""
var _route_hover_clock: float = 0.0
var _route_hover_request_id: int = -1
var _route_place_started_msec: int = 0
var _route_sources_synced: int = -1
var _route_road_synced: int = -1
var _route_road_debounce: float = 0.0
## team -> {sources: int, roads: int} last portal rebuild versions (event-driven freshness).
var _route_team_portal_sync: Dictionary = {}
## Single Rust planner holds one team graph; track which team is loaded.
var _route_planner_active_team: int = -1
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
var _slow_overlay_warned: bool = false
var _overlay_reconcile_cursor: int = 0
var _cached_structure_hud_labels: Dictionary = {}
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
	if hangar_button:
		hangar_button.toggled.connect(_on_hangar_toggled)
	corridor_link_button.toggled.connect(_on_corridor_link_toggled)
	inspect_button.toggled.connect(_on_inspect_toggled)
	if tile_probe_label:
		tile_probe_label.visible = false
	end_overlay.visible = false
	_supply = float(CFG.STARTING_SUPPLY)
	_enemy_supply = float(CFG.STARTING_SUPPLY)
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
	EconomyLib.ensure_loaded(RunState.economy_pack_id)
	_refresh_cached_structure_hud_labels()
	var seed_val: int = RunState.run_seed if RunState.run_seed != 0 else randi() & 0x7FFFFFFF
	var map_id: String = WorldMapCatalogLib.resolve_map_id(RunState.world_map_id)
	battle_data = WorldConquestMapGeneratorLib.generate(map_id, seed_val)
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
	_setup_world_visuals(map_id)
	_set_load_progress(0.62, "Preparing route planner…")
	await get_tree().process_frame
	_warm_route_planner_at_load()
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


func _setup_world_visuals(map_id: String) -> void:
	OutpostBuildLib.prepare_land_components(battle_data)
	_setup_territory_backend()
	if territory_sim != null:
		_sync_bridge_corridors_to_sim(true, true)
	if globe_map != null:
		globe_map.setup(battle_data, map_id)
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
	# E8: full live contract after logistics/wallet homes are configured (not at enable_rust_live).
	_assert_world_dataset_after_setup()
	_on_play_area_resized(true)


## E8: run WorldDatasetAssert once builders + mirror mode are ready for play.
func _assert_world_dataset_after_setup() -> void:
	if territory_sim == null or not CFG.world_dataset_require_live():
		return
	if not territory_sim.use_rust_for_live():
		_world_dataset_entry_failed = true
		push_error("WorldDataset FAIL CLOSED: Rust live not active after setup")
		return
	if not WorldDatasetAssertLib.validate_or_fail(territory_sim, battle_data):
		_world_dataset_entry_failed = true
		push_error("WorldDatasetAssert.validate_or_fail failed after full setup")


func _warm_route_planner_at_load() -> void:
	if not CFG.ROUTE_PRELOAD_AT_LOAD or battle_data == null:
		return
	if route_planner == null:
		route_planner = RoutePlannerLib.new()
	if not route_planner.setup_map(battle_data, _placement_structures()):
		push_warning("World Conquest: route planner preload failed")
		return
	_route_sources_synced = _structure_sources_version
	_route_road_synced = _road_network_version
	_route_road_debounce = 0.0
	_route_team_portal_sync.clear()
	_route_planner_active_team = -1
	_ensure_route_portals_for_team(BattleTileControlLib.OWNER_FRIENDLY, _player_home, true)
	if not CFG.ROUTE_WARMUP_PROBE or _player_home.x < 0:
		return
	if battle_data.is_land_cell(_player_home.x, _player_home.y):
		route_planner.find_route_sync(_player_home, OutpostBuildLib.KIND_SPAWNER, false)


func _process(delta: float) -> void:
	# Perf: skip FrameBudgetProfiler during bootstrap loading (reset_samples after _loading=false).
	if _loading:
		return
	# A1: do not advance dual-sim / play loop when live entry failed closed.
	if _world_dataset_entry_failed:
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
		_enemy_supply += float(_hostile_tiles) * CFG.INCOME_PER_TILE_PER_SEC * delta
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
		var enemy_ai_t: int = 0
		if _frame_profiler != null:
			enemy_ai_t = _frame_profiler.begin_phase("enemy_ai")
		_tick_enemy_strategy(delta * _speed_mult)
		if _frame_profiler != null:
			_frame_profiler.end_phase("enemy_ai", enemy_ai_t)
	# Construction / world session continue while pressure sim is paused (build queues still advance).
	if not territory_sim.finished:
		if _has_active_construction() and not _world_session_active() and not _paused:
			var outpost_t: int = 0
			if _frame_profiler != null:
				outpost_t = _frame_profiler.begin_phase("outpost")
			_advance_outpost_construction(delta * _speed_mult)
			if _frame_profiler != null:
				_frame_profiler.end_phase("outpost", outpost_t)
		if _world_session_active():
			_tick_world_session(delta * _speed_mult)
		elif not _paused:
			_tick_soldier_economy(delta * _speed_mult)
			_tick_barracks_spawns(delta * _speed_mult)

	if sim_steps > 0:
		_soldier_visual_dirty = true
		_bomber_visual_dirty = true

	var bridge_flush_t: int = 0
	if _frame_profiler != null:
		bridge_flush_t = _frame_profiler.begin_phase("bridge_flush")
	_drain_outpost_construction_queue()
	if _frame_profiler != null:
		_frame_profiler.end_phase("bridge_flush", bridge_flush_t)
	_tick_overlay_owner_reconcile(delta)

	if not _paused and territory_sim != null and not territory_sim.finished:
		if not CFG.OVERLAY_OWNERS_ONLY:
			_overlay_clock += delta
			if _overlay_clock >= 1.0 / CFG.OVERLAY_UPDATES_PER_SEC:
				_overlay_clock = 0.0
				_update_tile_overlay(false)
	if territory_sim != null and not territory_sim.finished:
		_update_builder_agents(delta * _speed_mult)
	_update_outpost_visuals(delta)
	_update_resource_visuals(delta)
	_drain_network_road_visuals()
	# Single live presentation pull: owners + optional structures/units (after sim + builders).
	var pres_t: int = 0
	if _frame_profiler != null:
		pres_t = _frame_profiler.begin_phase("presentation")
	if _live_rust_presentation():
		_flush_live_presentation_delta(delta)
	else:
		if sim_steps > 0 and CFG.OVERLAY_OWNERS_ONLY:
			_enqueue_ownership_overlay_delta()
		_update_soldier_visuals(delta)
		_update_bomber_visuals(delta)
	if _frame_profiler != null:
		_frame_profiler.end_phase("presentation", pres_t)
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
	# G4/A9: reject GPU env for World Conquest.
	BattleTerritoryRustBackendLib.reject_gpu_env_for_world_conquest()
	var backend_env: String = OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower()
	if backend_env == "cpu":
		# Explicit CPU only for QA/debug; live require_live forbids dual-sim without opt-in.
		if (
			CFG.world_dataset_require_live()
			and OS.get_environment("BATTLE_ALLOW_CPU_UNDER_LIVE") != "1"
		):
			push_error(
				"WorldDataset FAIL CLOSED: BATTLE_TERRITORY_BACKEND=cpu while world_dataset_require_live() — set BATTLE_ALLOW_CPU_UNDER_LIVE=1 only for intentional QA."
			)
			_world_dataset_entry_failed = true
		territory_sim.set_live_backend(false)
		territory_sim.refresh_world_dataset_mirror_mode()
		RunLog.info("World Conquest using CPU territory backend (BATTLE_TERRITORY_BACKEND=cpu)")
		return
	if backend_env == "gpu":
		push_error(
			"World Conquest ignores BATTLE_TERRITORY_BACKEND=gpu — use Rust or cpu."
		)
	if territory_sim.enable_rust_live():
		territory_sim.refresh_world_dataset_mirror_mode()
		# Full WorldDatasetAssert runs after configure_builders (see _assert_world_dataset_after_setup).
		# Early entry only fails closed when enable_rust_live itself failed.
		if territory_sim.world_dataset_failed():
			_world_dataset_entry_failed = true
			push_error(
				"WorldDataset FAIL CLOSED after enable_rust_live: %s"
				% str(territory_sim.world_dataset_error)
			)
			return
		if _scd1_pull != null:
			_scd1_pull.reset_for_new_match()
		RunLog.info("World Conquest using Rust territory backend (WorldDataset live + SCD1 pulls)")
		return
	# A1/G3: fail closed when live requires Rust but DLL missing — no silent CPU dual-sim.
	if CFG.world_dataset_require_live() or territory_sim.world_dataset_failed():
		_world_dataset_entry_failed = true
		var err: String = str(territory_sim.world_dataset_error)
		push_error(
			"WorldDataset FAIL CLOSED: Rust TerritorySim required for live play. %s" % err
		)
		RunLog.info("World Conquest FAILED: Rust extension not loaded (live contract)")
		if status_label:
			status_label.text = "WorldDataset FAIL CLOSED — Rust DLL required"
		return
	territory_sim.set_live_backend(false)
	territory_sim.refresh_world_dataset_mirror_mode()
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
	return EconomyLib.supply_cost(_build_mode)


func _placement_cost_affordable() -> bool:
	return EconomyLib.can_afford_build(_supply, _friendly_resources, _build_mode)


func _refresh_cached_structure_hud_labels() -> void:
	_cached_structure_hud_labels = {
		OutpostBuildLib.KIND_SPAWNER: EconomyLib.hud_label_for_kind(OutpostBuildLib.KIND_SPAWNER),
		OutpostBuildLib.KIND_BARRACKS: EconomyLib.hud_label_for_kind(OutpostBuildLib.KIND_BARRACKS),
		OutpostBuildLib.KIND_HANGAR: EconomyLib.hud_label_for_kind(OutpostBuildLib.KIND_HANGAR),
		OutpostBuildLib.KIND_CORRIDOR_LINK: EconomyLib.hud_label_for_kind(
			OutpostBuildLib.KIND_CORRIDOR_LINK
		),
	}


func _placement_cost_hint(kind: String) -> String:
	var cost: Vector4 = EconomyLib.placement_cost(kind)
	return "Need %s supply (have %s)." % [_format_supply(cost.x), _format_supply(_supply)]


func _pay_placement_cost(kind: String) -> bool:
	if not EconomyLib.can_afford_build(_supply, _friendly_resources, kind):
		return false
	var cost: Vector4 = EconomyLib.placement_cost(kind)
	_supply -= cost.x
	# SCD1 wallet: spend via Rust delta only (do not Godot-author absolute balances).
	if _resource_wallet_active() and territory_sim != null:
		territory_sim.apply_resource_tick_delta(
			[-cost.y, -cost.z, -cost.w],
			[0.0, 0.0, 0.0],
		)
		_pull_resource_wallet_from_rust()
	else:
		var paid: Dictionary = EconomyLib.pay_build(_supply + cost.x, _friendly_resources, kind)
		_supply = float(paid.get("supply", _supply))
		var res: Array = paid.get("resources", _friendly_resources)
		for i in range(mini(CFG.RESOURCE_TYPE_COUNT, res.size())):
			_friendly_resources[i] = float(res[i])
	return true


func _pay_enemy_placement_cost(kind: String) -> bool:
	if not EconomyLib.can_afford_build(_enemy_supply, _hostile_resources, kind):
		return false
	var cost: Vector4 = EconomyLib.placement_cost(kind)
	_enemy_supply -= cost.x
	if _resource_wallet_active() and territory_sim != null:
		territory_sim.apply_resource_tick_delta(
			[0.0, 0.0, 0.0],
			[-cost.y, -cost.z, -cost.w],
		)
		_pull_resource_wallet_from_rust()
	else:
		var paid: Dictionary = EconomyLib.pay_build(_enemy_supply + cost.x, _hostile_resources, kind)
		_enemy_supply = float(paid.get("supply", _enemy_supply))
		var res: Array = paid.get("resources", _hostile_resources)
		for i in range(mini(CFG.RESOURCE_TYPE_COUNT, res.size())):
			_hostile_resources[i] = float(res[i])
	return true


func _build_mode_noun() -> String:
	if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return "land bridge"
	if _build_mode == OutpostBuildLib.KIND_BARRACKS:
		return "barracks"
	if _build_mode == OutpostBuildLib.KIND_HANGAR:
		return "hangar"
	return "outpost"


func _try_place_structure() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Click land on the globe to place a %s." % _build_mode_noun()
		return
	if not EconomyLib.can_afford_build(_supply, _friendly_resources, _build_mode):
		build_hint_label.text = _placement_cost_hint(_build_mode)
		return
	var reject: String = _placement_hover_reject(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = reject
		return
	if route_planner == null or not route_planner.ready:
		_ensure_route_planner()
	if route_planner == null or not route_planner.ready:
		build_hint_label.text = "Route planner not ready."
		return
	# Event-driven: rebuild only when structure/road versions advanced since last portal build.
	_ensure_route_portals_for_team(BattleTileControlLib.OWNER_FRIENDLY, _player_home)
	build_hint_label.text = "Planning route…"
	if CFG.ROUTE_ASYNC_PLACEMENT:
		var precheck: Dictionary = _placement_precheck(grid, _build_mode)
		if str(precheck.get("reject", "")) != "":
			build_hint_label.text = str(precheck.get("reject", ""))
			return
		var landing: Vector2i = precheck.get("landing", Vector2i(-1, -1))
		if landing.x < 0:
			build_hint_label.text = "Could not place %s here." % _build_mode_noun()
			return
		_cancel_place_route_request()
		_route_pending_grid = grid
		_route_pending_landing = landing
		_route_pending_mode = _build_mode
		_route_place_pending = true
		_route_place_started_msec = Time.get_ticks_msec()
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
	var reject: String = str(placement.get("reject", ""))
	if reject != "":
		build_hint_label.text = reject
		return
	if placement.get("path_packed", PackedInt32Array()).is_empty():
		if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
			build_hint_label.text = "No route found for this land bridge."
		else:
			build_hint_label.text = "Could not place outpost here."
		return
	if not EconomyLib.can_afford_build(_supply, _friendly_resources, _build_mode):
		build_hint_label.text = _placement_cost_hint(_build_mode)
		return
	if not _pay_placement_cost(_build_mode):
		build_hint_label.text = _placement_cost_hint(_build_mode)
		return
	var placed_sid: int = _commit_placed_structure(
		placement, BattleTileControlLib.OWNER_FRIENDLY, _build_mode, grid
	)
	if placed_sid < 0:
		build_hint_label.text = "Could not place outpost here."
		return
	_apply_build_mode("")


func debug_place_outpost_at(
	grid: Vector2i,
	kind: String,
	team: int,
	allow_astar: bool = true,
	allow_standalone: bool = true,
) -> int:
	if battle_data == null or kind == "":
		return -1
	var placement: Dictionary = _resolve_placement_for_team(
		grid, allow_astar, kind, team, allow_standalone
	)
	if str(placement.get("reject", "")) != "":
		return -1
	if placement.get("path_packed", PackedInt32Array()).is_empty():
		return -1
	return _commit_placed_structure(placement, team, kind, grid)


func _commit_placed_structure(
	placement: Dictionary, team: int, kind: String, click_grid: Vector2i
) -> int:
	if battle_data == null:
		return -1
	var path_packed: PackedInt32Array = placement.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		return -1
	if kind != OutpostBuildLib.KIND_CORRIDOR_LINK:
		path_packed = OutpostBuildLib.densify_path_cardinal(battle_data, path_packed)
	var landing: Vector2i = placement.get("landing", Vector2i(-1, -1))
	if landing.x < 0:
		return -1
	var src: Vector2i = placement.get("source", Vector2i(-1, -1))
	var st: Dictionary = {
		"id": _next_structure_id,
		"team": team,
		"gx": landing.x,
		"gy": landing.y,
		"kind": kind,
		"state": OutpostBuildLib.STATE_CONNECTING,
		"source_gx": src.x,
		"source_gy": src.y,
		"path_keys": path_packed,
		"path_len": path_packed.size(),
		"path_built": 1.0,
	}
	if kind == OutpostBuildLib.KIND_SPAWNER or kind == OutpostBuildLib.KIND_BARRACKS or kind == OutpostBuildLib.KIND_HANGAR:
		st["health"] = CFG.OUTPOST_MAX_HEALTH
	if landing != click_grid:
		st["click_gx"] = click_grid.x
		st["click_gy"] = click_grid.y
	var placed_sid: int = int(st.get("id", -1))
	_next_structure_id += 1
	if territory_sim != null and territory_sim.rust_field != null:
		territory_sim.rust_field.structure_store_upsert(st)
	if _structure_authority_active():
		_pull_structure_render_cache({placed_sid: st})
	else:
		battle_data.placed_structures.append(st)
	if kind == OutpostBuildLib.KIND_SPAWNER:
		_structure_sources_version += 1
	_road_network_version += 1
	_invalidate_hover_path_cache()
	_clear_placement_preview()
	_outpost_road_dirty = true
	_outpost_marker_dirty = true
	_resource_links_dirty = true
	_enqueue_builder_job(placed_sid, team)
	if kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
		if _outpost_construction_queue != null:
			_outpost_construction_queue.enqueue_corridor(placed_sid)
			_outpost_construction_queue.enqueue_road(placed_sid)
			_outpost_construction_queue.enqueue_marker(placed_sid)
		else:
			_sync_bridge_corridors_to_sim(false, false, false)
			_refresh_outpost_visuals(true, true, [placed_sid], [placed_sid])
	else:
		_sync_bridge_corridors_to_sim(false, true, true)
		_refresh_outpost_visuals(true, true, [placed_sid], [placed_sid])
	return placed_sid


func _find_placement_route(
	landing: Vector2i,
	build_kind: String,
	_sources: Array[Vector2i],
	allow_astar: bool,
	_team: int = BattleTileControlLib.OWNER_FRIENDLY,
	route_home: Vector2i = Vector2i(-1, -1),
) -> Dictionary:
	var empty: Dictionary = {
		"path_packed": PackedInt32Array(),
		"source": Vector2i(-1, -1),
	}
	if battle_data == null or landing.x < 0:
		return empty
	if route_planner == null or not route_planner.ready:
		_ensure_route_planner()
	if route_planner == null or not route_planner.ready:
		return empty
	_ensure_route_portals_for_team(_team, route_home)
	var rust_route: Dictionary = route_planner.find_route_sync(
		landing, build_kind, allow_astar
	)
	return rust_route


func _resolve_placement(
	click: Vector2i, allow_astar: bool = false, build_kind: String = OutpostBuildLib.KIND_SPAWNER
) -> Dictionary:
	return _resolve_placement_for_team(
		click, allow_astar, build_kind, BattleTileControlLib.OWNER_FRIENDLY, true
	)


func _resolve_placement_for_team(
	click: Vector2i,
	allow_astar: bool,
	build_kind: String,
	team: int,
	allow_standalone: bool = true,
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
	var precheck: Dictionary = _placement_precheck_for_team(click, build_kind, team)
	var pre_reject: String = str(precheck.get("reject", ""))
	if pre_reject != "":
		empty["reject"] = pre_reject
		return empty
	var landing: Vector2i = precheck.get("landing", Vector2i(-1, -1))
	var sources: Array[Vector2i] = precheck.get("sources", [])
	var route_home: Vector2i = (
		_player_home if team == BattleTileControlLib.OWNER_FRIENDLY else _enemy_home
	)
	var route: Dictionary = _find_placement_route(
		landing, build_kind, sources, allow_astar, team, route_home
	)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
			var reject_code: int = int(route.get("reject", 0))
			var expand_n: int = int(route.get("expand_count", 0))
			RunLog.warn(
				"Land bridge route failed reject=%d expand=%d landing=(%d,%d)"
				% [reject_code, expand_n, landing.x, landing.y]
			)
			empty["reject"] = "No route found for this land bridge."
			return empty
		# Standalone (no supply path) is a last-resort player affordance only.
		if not allow_standalone:
			empty["reject"] = "No supply route to this tile."
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
	empty["landing"] = landing
	empty["path_packed"] = path_packed
	empty["source"] = route.get("source", Vector2i(-1, -1))
	return empty


func _placement_structures() -> Array:
	# Never force a full structure FFI pull here — called from route portal rebuilds.
	# Use the render cache already maintained by presentation/event pulls.
	if battle_data == null:
		return []
	return battle_data.placed_structures


func _placement_precheck(click: Vector2i, build_kind: String) -> Dictionary:
	return _placement_precheck_for_team(click, build_kind, BattleTileControlLib.OWNER_FRIENDLY)


func _placement_precheck_for_team(click: Vector2i, build_kind: String, team: int) -> Dictionary:
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
	var territory_reject: String = _placement_territory_reject_for_team(
		click.x, click.y, team, build_kind
	)
	if territory_reject != "":
		result["reject"] = territory_reject
		return result
	var route_home: Vector2i = _player_home if team == BattleTileControlLib.OWNER_FRIENDLY else _enemy_home
	var structures: Array = _placement_structures()
	var sources: Array[Vector2i] = OutpostBuildLib.operational_sources(
		structures, route_home, battle_data, team
	)
	result["sources"] = sources
	var landing: Vector2i
	if (
		build_kind == OutpostBuildLib.KIND_SPAWNER
		or build_kind == OutpostBuildLib.KIND_BARRACKS
		or build_kind == OutpostBuildLib.KIND_HANGAR
	):
		landing = click
	else:
		var snap_inland: bool = build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK
		landing = OutpostBuildLib.resolve_invasion_target(
			battle_data, click, sources, snap_inland, team
		)
		if landing.x < 0:
			result["reject"] = "No coastal landing on this landmass."
			return result
	result["landing"] = landing
	for st: Dictionary in structures:
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
	return _placement_territory_reject_for_team(
		gx, gy, BattleTileControlLib.OWNER_FRIENDLY, build_kind
	)


func _placement_territory_reject_for_team(
	gx: int, gy: int, team: int, build_kind: String = ""
) -> String:
	if build_kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
		return ""
	if battle_data == null or territory_sim == null:
		return ""
	var idx: int = battle_data.cell_index(gx, gy)
	if idx < 0 or idx >= territory_sim.grid_cell_count():
		return ""
	var owner: int = territory_sim.owner_at_index(idx)
	if team == BattleTileControlLib.OWNER_FRIENDLY and owner == BattleTileControlLib.OWNER_HOSTILE:
		return "Cannot build on enemy-held territory."
	if team == BattleTileControlLib.OWNER_HOSTILE and owner == BattleTileControlLib.OWNER_FRIENDLY:
		return "Cannot build on friendly-held territory."
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


func _warn_slow_owner_overlay_path(context: String) -> void:
	if not CFG.WORLD_DATASET_WARN_SLOW_OVERLAY or _slow_overlay_warned:
		return
	if (
		territory_sim == null
		or not territory_sim.rust_live_ready
		or territory_sim.rust_field == null
	):
		return
	_slow_overlay_warned = true
	RunLog.warn("WorldDataset: slow owner overlay path (%s) during Rust live play" % context)


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
		_warn_slow_owner_overlay_path("apply_owner_visual_from_backends")
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
					_warn_slow_owner_overlay_path("update_tile_overlay")
					globe_map.apply_ownership_overlay(owners)
			else:
				_warn_slow_owner_overlay_path("update_tile_overlay_cpu")
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


func _tick_overlay_owner_reconcile(_delta: float) -> void:
	if (
		not CFG.OVERLAY_OWNERS_ONLY
		or _battle_finished
		or globe_map == null
		or battle_data == null
		or territory_sim == null
		or not territory_sim.use_rust_for_live()
		or territory_sim.rust_field == null
	):
		return
	var total: int = battle_data.grid_width * battle_data.grid_height
	if total <= 0:
		return
	var budget: int = CFG.OVERLAY_RECONCILE_CELLS_PER_FRAME
	if (
		_frame_profiler != null
		and not FrameBudgetProfilerLib.budget_allows_catchup(
			_frame_profiler.prior_frame_ms(), CFG.FRAME_BUDGET_MS
		)
	):
		budget = budget / 2
	if budget <= 0:
		return
	budget = mini(budget, total)
	var rf := territory_sim.rust_field
	var fix_idxs := PackedInt32Array()
	var fix_vals := PackedByteArray()
	for _scan in range(budget):
		var idx: int = _overlay_reconcile_cursor
		_overlay_reconcile_cursor = (_overlay_reconcile_cursor + 1) % total
		var owner: int = rf.owner_at_index(idx)
		var expected: int = EarthGlobeMapLib.owner_display_byte_for(owner)
		var cached: int = globe_map.get_owner_cache_byte(idx)
		if expected == cached:
			continue
		fix_idxs.append(idx)
		fix_vals.append(expected)
	if fix_idxs.is_empty():
		return
	globe_map.apply_ownership_display_delta(fix_idxs, fix_vals)
	if _outpost_construction_queue != null:
		_outpost_construction_queue.request_gpu_upload()


func _live_rust_presentation() -> bool:
	return (
		CFG.world_dataset_live()
		and territory_sim != null
		and territory_sim.use_rust_for_live()
		and territory_sim.rust_live_ready
		and territory_sim.rust_field != null
	)


func _enqueue_ownership_overlay_delta() -> void:
	if globe_map == null or territory_sim == null or _outpost_construction_queue == null:
		return
	if not CFG.OVERLAY_OWNERS_ONLY:
		return
	if territory_sim.use_rust_for_live() and territory_sim.rust_field != null and territory_sim.rust_field.ready:
		if territory_sim.rust_field.has_method("consume_owner_overlay_delta"):
			var d: Dictionary = territory_sim.rust_field.consume_owner_overlay_delta()
			_enqueue_owner_delta_dict(d)
			return
	var owners: PackedByteArray = _ownership_overlay_source()
	if not owners.is_empty():
		_warn_slow_owner_overlay_path("enqueue_full_overlay")
		globe_map.apply_ownership_overlay(owners)
		_outpost_construction_queue.request_gpu_upload()


func _enqueue_owner_delta_dict(d: Dictionary) -> void:
	if _outpost_construction_queue == null or d.is_empty():
		return
	var display_idxs: PackedInt32Array = d.get("indices", PackedInt32Array())
	var display_vals: PackedByteArray = d.get("values", PackedByteArray())
	if display_idxs.is_empty():
		var owner_idxs: PackedInt32Array = d.get("owner_indices", PackedInt32Array())
		var owner_vals: PackedByteArray = d.get("owner_values", PackedByteArray())
		if owner_idxs.is_empty():
			return
		_outpost_construction_queue.enqueue_overlay_delta(owner_idxs, owner_vals)
		_last_overlay_delta_count = owner_idxs.size()
		return
	_outpost_construction_queue.enqueue_overlay_display_delta(display_idxs, display_vals)
	_last_overlay_delta_count = display_idxs.size()


## SCD1 live paint: per-domain versioned pulls (replaces PresentationTxn dual-feed).
func _flush_live_presentation_delta(delta: float) -> void:
	if not _live_rust_presentation() or territory_sim.finished:
		return
	if _scd1_pull == null:
		_scd1_pull = Scd1DomainPullLib.new()
	var sim = territory_sim
	# Non-unit domains every frame. Agents/bombers only when the visual rate is due —
	# otherwise last_version advances on unused pulls and intermediate moves are dropped.
	_apply_scd1_territory(_scd1_pull.pull_domain(sim, "territory", ""))
	_apply_scd1_structures(_scd1_pull.pull_domain(sim, "structures", ""))
	_apply_scd1_roads(_scd1_pull.pull_domain(sim, "roads", ""))
	_apply_scd1_wallet(_scd1_pull.pull_domain(sim, "wallet", ""))
	_soldier_visual_clock += delta
	_bomber_visual_clock += delta
	var soldier_due: bool = (
		territory_sim.agents_ready()
		and (
			_soldier_visual_dirty
			or _soldier_visual_clock >= 1.0 / CFG.SOLDIER_VISUAL_UPDATES_PER_SEC
		)
	)
	var bomber_due: bool = (
		territory_sim.bombers_ready()
		and (
			_bomber_visual_dirty
			or _bomber_visual_clock >= 1.0 / CFG.BOMBER_VISUAL_UPDATES_PER_SEC
		)
	)
	if soldier_due:
		_soldier_visual_clock = 0.0
		_soldier_visual_dirty = false
		_apply_scd1_agents(_scd1_pull.pull_domain(sim, "agents", ""))
	if bomber_due:
		_bomber_visual_clock = 0.0
		_bomber_visual_dirty = false
		_apply_scd1_bombers(_scd1_pull.pull_domain(sim, "bombers", ""))
	_presentation_structures_dirty = false
	_presentation_structure_merge.clear()


func _apply_scd1_territory(batch: Dictionary) -> void:
	if batch.is_empty() or bool(batch.get("empty", true)):
		return
	if bool(batch.get("full_denied_cooldown", false)):
		return
	var idxs: PackedInt32Array = batch.get("indices", PackedInt32Array())
	var owners: PackedByteArray = batch.get("owners", PackedByteArray())
	if idxs.is_empty():
		return
	if _outpost_construction_queue != null:
		_outpost_construction_queue.enqueue_overlay_delta(idxs, owners)
		_outpost_construction_queue.request_gpu_upload()
	_maybe_log_perf_action("gpu_upload", {"cells": idxs.size()}, 2.0)
	if territory_sim != null and territory_sim.rust_field != null:
		territory_sim.rust_field.friendly_tiles = int(
			batch.get("friendly_tiles", territory_sim.rust_field.friendly_tiles)
		)
		territory_sim.rust_field.hostile_tiles = int(
			batch.get("hostile_tiles", territory_sim.rust_field.hostile_tiles)
		)


func _apply_scd1_structures(batch: Dictionary) -> void:
	if batch.is_empty() or bool(batch.get("full_denied_cooldown", false)):
		return
	if bool(batch.get("empty", true)) and not bool(batch.get("full", false)):
		return
	var rows: Array = batch.get("rows", [])
	if battle_data == null:
		return
	var dirty_sids: Array = []
	if bool(batch.get("full", false)):
		_structure_snapshot_pull_count += 1
		battle_data.placed_structures.clear()
		for row in rows:
			if row is Dictionary:
				battle_data.placed_structures.append((row as Dictionary).duplicate())
				dirty_sids.append(int(row.get("id", -1)))
	else:
		var by_id: Dictionary = {}
		for st in battle_data.placed_structures:
			if st is Dictionary:
				by_id[int(st.get("id", -1))] = st
		for row in rows:
			if not row is Dictionary:
				continue
			var r: Dictionary = row
			var sid: int = int(r.get("id", -1))
			if sid < 0:
				continue
			if by_id.has(sid):
				var dst: Dictionary = by_id[sid]
				for k in r.keys():
					dst[k] = r[k]
			else:
				battle_data.placed_structures.append(r.duplicate())
			dirty_sids.append(sid)
	# Budget: only refresh markers for changed sids (full empty list rebuild only on full seed).
	if globe_map != null and dirty_sids.size() > 0:
		if bool(batch.get("full", false)):
			_refresh_markers([])
		else:
			_refresh_markers(dirty_sids)


func _apply_scd1_roads(batch: Dictionary) -> void:
	if batch.is_empty() or bool(batch.get("empty", true)):
		return
	if bool(batch.get("full_denied_cooldown", false)):
		return
	var idxs: PackedInt32Array = batch.get("indices", PackedInt32Array())
	for i in range(idxs.size()):
		_network_road_pending.append(int(idxs[i]))
	_drain_network_road_visuals()


func _apply_scd1_agents(batch: Dictionary) -> void:
	if globe_map == null:
		return
	# empty=true → no domain advance; keep prior living-set visuals.
	if batch.is_empty() or bool(batch.get("empty", true)):
		if not territory_sim.agents_ready():
			globe_map.sync_soldiers(PackedByteArray(), PackedInt32Array(), PackedInt32Array())
		return
	# Non-empty batch is the full living set (Rust living-set domain contract).
	var rows: Array = batch.get("rows", [])
	var teams := PackedByteArray()
	var gx := PackedInt32Array()
	var gy := PackedInt32Array()
	teams.resize(rows.size())
	gx.resize(rows.size())
	gy.resize(rows.size())
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		teams[i] = int(r.get("team", 1))
		gx[i] = int(r.get("gx", 0))
		gy[i] = int(r.get("gy", 0))
	globe_map.sync_soldiers(teams, gx, gy)


func _apply_scd1_bombers(batch: Dictionary) -> void:
	if globe_map == null:
		return
	if batch.is_empty() or bool(batch.get("empty", true)):
		if not territory_sim.bombers_ready():
			globe_map.sync_bombers(PackedByteArray(), PackedInt32Array(), PackedInt32Array())
		return
	# Non-empty batch is the full living set (+ optional one-shot bomb FX).
	var rows: Array = batch.get("rows", [])
	var teams := PackedByteArray()
	var gx := PackedInt32Array()
	var gy := PackedInt32Array()
	var scope := PackedInt32Array()
	teams.resize(rows.size())
	gx.resize(rows.size())
	gy.resize(rows.size())
	scope.resize(rows.size())
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		teams[i] = int(r.get("team", 1))
		gx[i] = int(r.get("gx", 0))
		gy[i] = int(r.get("gy", 0))
		scope[i] = int(r.get("search_scope", 0))
	globe_map.sync_bombers(teams, gx, gy, scope)
	var bomb_teams: PackedByteArray = batch.get("bomb_teams", PackedByteArray())
	var bomb_gx: PackedInt32Array = batch.get("bomb_gx", PackedInt32Array())
	var bomb_gy: PackedInt32Array = batch.get("bomb_gy", PackedInt32Array())
	if not bomb_teams.is_empty():
		globe_map.play_bomb_drops(bomb_teams, bomb_gx, bomb_gy)


func _apply_scd1_wallet(batch: Dictionary) -> void:
	if batch.is_empty() or bool(batch.get("full_denied_cooldown", false)):
		return
	# empty=true means no version advance — keep prior mirror (do not clear).
	if bool(batch.get("empty", true)) and not bool(batch.get("full", false)):
		return
	if bool(batch.get("error", false)):
		return
	var friendly: PackedFloat32Array = batch.get("friendly", PackedFloat32Array())
	var hostile: PackedFloat32Array = batch.get("hostile", PackedFloat32Array())
	if friendly.is_empty() and hostile.is_empty():
		return
	for i in range(mini(3, friendly.size())):
		_friendly_resources[i] = friendly[i]
	for i in range(mini(3, hostile.size())):
		_hostile_resources[i] = hostile[i]


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
	if battle_data == null or territory_sim == null:
		return
	var info: Dictionary = ResourceLib.tick(
		battle_data,
		territory_sim,
		battle_data.placed_structures,
		_player_home,
		_enemy_home,
		dt,
		_structure_sources_version,
		_road_network_version,
	)
	if _resource_wallet_active() and territory_sim != null:
		territory_sim.apply_resource_tick_delta(info.friendly, info.hostile)
		_pull_resource_wallet_from_rust()
	else:
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
	globe_map.sync_roads(
		battle_data.placed_structures, changed_sids, _builder_authority_active()
	)
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


func _has_connecting_outposts() -> bool:
	## Road still incomplete — only these should blink.
	if battle_data == null:
		return false
	for st: Dictionary in battle_data.placed_structures:
		if not OutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		if str(st.get("state", "")) == OutpostBuildLib.STATE_CONNECTING:
			return true
	return false


func _update_outpost_visuals(delta: float) -> void:
	if not _has_connecting_outposts():
		return
	_outpost_marker_clock += delta
	if globe_map != null:
		globe_map.set_marker_pulse(_outpost_marker_clock)
	# Pulse at 2 Hz — CONNECTING only (road not finished in structure table).
	if _outpost_marker_clock >= 0.5:
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
	_cancel_hover_route_request()
	_clear_placement_preview()


func _cancel_hover_route_request() -> void:
	if route_planner != null and route_planner.ready and _route_hover_request_id >= 0:
		route_planner.cancel_route(_route_hover_request_id)
	_route_hover_request_id = -1


func _cancel_place_route_request() -> void:
	if route_planner != null and route_planner.ready and _route_request_id >= 0:
		route_planner.cancel_route(_route_request_id)
	_route_request_id = -1
	_route_place_pending = false
	_route_place_started_msec = 0


func _cancel_route_requests() -> void:
	_cancel_hover_route_request()
	_cancel_place_route_request()


func _rebuild_route_portals() -> void:
	_ensure_route_portals_for_team(BattleTileControlLib.OWNER_FRIENDLY, _player_home, true)


func _rebuild_route_portals_for_team(team: int, route_home: Vector2i) -> void:
	if route_planner == null or not route_planner.ready or battle_data == null:
		return
	if route_home.x < 0:
		route_home = _player_home if team == BattleTileControlLib.OWNER_FRIENDLY else _enemy_home
	var network_built: PackedByteArray = PackedByteArray()
	if _builder_authority_active() and territory_sim != null:
		network_built = territory_sim.get_network_built_mask(team)
	route_planner.update_infra_for_team(
		battle_data, _placement_structures(), team, network_built
	)
	route_planner.rebuild_portals(battle_data, _placement_structures(), route_home, team)


## Rebuild portals for `team` when versions advanced, team graph not loaded, or force.
## Avoids spam rebuilds for repeated queries on the same team with unchanged infra.
func _ensure_route_portals_for_team(
	team: int, route_home: Vector2i = Vector2i(-1, -1), force: bool = false
) -> void:
	if route_planner == null or not route_planner.ready or battle_data == null:
		return
	var team_loaded: bool = _route_planner_active_team == team
	if not force and team_loaded and _route_team_portals_fresh(team):
		return
	_rebuild_route_portals_for_team(team, route_home)
	_route_planner_active_team = team
	_mark_route_team_portals_synced(team)


func _route_team_portals_fresh(team: int) -> bool:
	if not _route_team_portal_sync.has(team):
		return false
	var entry: Dictionary = _route_team_portal_sync[team]
	return (
		int(entry.get("sources", -1)) == _structure_sources_version
		and int(entry.get("roads", -1)) == _road_network_version
	)


func _mark_route_team_portals_synced(team: int) -> void:
	_route_team_portal_sync[team] = {
		"sources": _structure_sources_version,
		"roads": _road_network_version,
	}
	# Keep legacy debounce counters in sync for friendly (hover refresh path).
	if team == BattleTileControlLib.OWNER_FRIENDLY:
		_route_sources_synced = _structure_sources_version
		_route_road_synced = _road_network_version
		_route_road_debounce = 0.0


func _ensure_route_planner() -> void:
	if route_planner != null and route_planner.ready:
		return
	if route_planner == null:
		route_planner = RoutePlannerLib.new()
	if route_planner.setup_map(battle_data, _placement_structures()):
		_route_team_portal_sync.clear()
		_route_planner_active_team = -1
		_ensure_route_portals_for_team(BattleTileControlLib.OWNER_FRIENDLY, _player_home, true)


func _refresh_route_infra_and_portals() -> void:
	if battle_data == null:
		return
	_ensure_route_planner()
	if route_planner == null or not route_planner.ready:
		return
	# Infra changed: invalidate freshness; load friendly graph (active build UX).
	# Hostile reloads on next enemy pathfind via ensure + active-team switch.
	_route_team_portal_sync.clear()
	_route_planner_active_team = -1
	_ensure_route_portals_for_team(BattleTileControlLib.OWNER_FRIENDLY, _player_home, true)


func _maybe_refresh_route_backend(delta: float) -> void:
	if not _is_build_mode_active() and not _route_place_pending:
		return
	if _route_place_pending:
		return
	if battle_data == null:
		return
	if route_planner == null or not route_planner.ready:
		_ensure_route_planner()
		if route_planner == null or not route_planner.ready:
			return
	var stale_sources: bool = _structure_sources_version != _route_sources_synced
	var stale_roads: bool = _road_network_version != _route_road_synced
	if not stale_sources and not stale_roads:
		_route_road_debounce = 0.0
		return
	_route_road_debounce += delta
	var debounce_sec: float = (
		CFG.ROUTE_SOURCE_DEBOUNCE_SEC if stale_sources else CFG.ROUTE_ROAD_INFRA_DEBOUNCE_SEC
	)
	if _route_road_debounce < debounce_sec:
		return
	_route_road_debounce = 0.0
	_refresh_route_infra_and_portals()


func _poll_route_planner() -> void:
	if route_planner == null or not route_planner.ready:
		return
	if _route_hover_request_id < 0 and not _route_place_pending:
		return
	var res: Dictionary = route_planner.poll_route()
	if not bool(res.get("ready", false)):
		return
	var req_id: int = int(res.get("request_id", -1))
	if req_id == _route_hover_request_id and _route_hover_request_id >= 0:
		_route_hover_request_id = -1
		_apply_hover_route_preview(res)
		return
	if _route_place_pending and req_id == _route_request_id and _route_request_id >= 0:
		_route_request_id = -1
		_route_place_pending = false
		_route_place_started_msec = 0
		_finish_place_from_route(res, _route_pending_grid, _route_pending_landing)


func _finish_place_from_route(
	res: Dictionary, grid: Vector2i, landing: Vector2i
) -> void:
	if battle_data == null or _build_mode == "":
		return
	var route: Dictionary = route_planner.decode_route_result(res)
	var path_packed: PackedInt32Array = route.get("path_packed", PackedInt32Array())
	if path_packed.is_empty():
		if _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
			build_hint_label.text = "No route found for this land bridge."
		else:
			build_hint_label.text = "Could not place outpost here."
		return
	elif _build_mode != OutpostBuildLib.KIND_CORRIDOR_LINK and not OutpostBuildLib.path_is_cardinal_dense(battle_data, path_packed):
		path_packed = OutpostBuildLib.densify_path_cardinal(battle_data, path_packed)
	if not EconomyLib.can_afford_build(_supply, _friendly_resources, _build_mode):
		build_hint_label.text = _placement_cost_hint(_build_mode)
		return
	if not _pay_placement_cost(_build_mode):
		build_hint_label.text = _placement_cost_hint(_build_mode)
		return
	var placement: Dictionary = {
		"landing": landing,
		"path_packed": path_packed,
		"source": route.get("source", Vector2i(-1, -1)),
	}
	var placed_sid: int = _commit_placed_structure(
		placement, BattleTileControlLib.OWNER_FRIENDLY, _build_mode, grid
	)
	if placed_sid < 0:
		build_hint_label.text = "Could not place outpost here."
		return
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


func _sync_claimable_to_backends(
	force_owner_visual: bool = true,
	sync_agents: bool = true,
	rust_already_authoritative: bool = false,
) -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	var live_claimable: int = territory_sim.claimable_tile_count_live()
	if live_claimable > 0:
		territory_sim.claimable_tiles = live_claimable
		_claimable_tiles = live_claimable
	if (
		not rust_already_authoritative
		and not territory_sim.grid_authority_active()
		and territory_sim.rust_live_ready
		and territory_sim.rust_field != null
	):
		territory_sim.rust_field.sync_claimable_from(tc, battle_data, true)
	if sync_agents and territory_sim.agents_ready():
		territory_sim.sync_agent_nav()
	if (
		not territory_sim.world_dataset_live_active()
		and territory_sim.use_gpu_for_live()
		and territory_sim.gpu_field != null
	):
		territory_sim.gpu_field.refresh_claimable_from(battle_data, tc)
	if force_owner_visual:
		_apply_owner_visual_from_backends(true)


func _rust_world_edit_ready() -> bool:
	return (
		territory_sim != null
		and territory_sim.rust_live_ready
		and territory_sim.rust_field != null
		and territory_sim.rust_field.world_edit_capable()
	)


func _structure_authority_active() -> bool:
	return territory_sim != null and territory_sim.structure_authority_active()


func _world_session_active() -> bool:
	return territory_sim != null and territory_sim.world_session_active()


func _builder_authority_active() -> bool:
	return territory_sim != null and territory_sim.builder_authority_active()


func _resource_wallet_active() -> bool:
	return territory_sim != null and territory_sim.resource_wallet_active()


## SCD1: do not push Godot-authored absolute balances as wallet truth.
## Spends/income must use apply_resource_tick_delta on Rust; this is a read mirror only.
func _sync_resource_wallet_to_rust() -> void:
	# Intentionally no-op under SCD1 live wallet — Godot does not author balances.
	return


## Mirror wallet from SCD1 domain pull only under live (no parallel get_resource_balances paint path).
func _pull_resource_wallet_from_rust() -> void:
	if not _resource_wallet_active() or territory_sim == null:
		return
	if _live_rust_presentation() and _scd1_pull != null:
		var batch: Dictionary = _scd1_pull.pull_domain(territory_sim, "wallet", "")
		_apply_scd1_wallet(batch)
		return
	# Non-live / CPU: direct balance read from backend.
	var wallet: Dictionary = territory_sim.pull_resource_balances()
	if wallet.is_empty():
		return
	var friendly: PackedFloat32Array = wallet.get("friendly", PackedFloat32Array())
	var hostile: PackedFloat32Array = wallet.get("hostile", PackedFloat32Array())
	for i in range(mini(3, friendly.size())):
		_friendly_resources[i] = friendly[i]
	for i in range(mini(3, hostile.size())):
		_hostile_resources[i] = hostile[i]


func _on_rust_builder_cell_arrival(ev_var: Variant) -> void:
	var ev: Dictionary = ev_var
	var path_sid: int = int(ev.get("sid", -1))
	var kind: String = str(ev.get("kind", ""))
	var seg_from: int = int(ev.get("seg_from_idx", 0))
	# SCD1: under live builder authority, path_built comes only from domain pulls — do not invent.
	if _builder_authority_active() or _structure_authority_active():
		return
	var st: Dictionary = _find_structure_by_sid(path_sid)
	if not st.is_empty():
		st["path_built"] = BuilderAgentLib.path_built_after_seg(seg_from)
		if kind.is_empty():
			kind = str(st.get("kind", ""))
	if _outpost_construction_queue != null:
		_outpost_construction_queue.on_cell_advanced(path_sid)


func _on_rust_builder_path_completed(ev_var: Variant) -> void:
	var ev: Dictionary = ev_var
	var done_sid: int = int(ev.get("sid", -1))
	var gx: int = int(ev.get("gx", 0))
	var gy: int = int(ev.get("gy", 0))
	var team: int = int(ev.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	var is_corridor_link: bool = bool(ev.get("is_corridor_link", false))
	var kind: String = str(ev.get("kind", ""))
	_road_network_version += 1
	_outpost_marker_dirty = true
	_invalidate_hover_path_cache()
	if kind == OutpostBuildLib.KIND_SPAWNER:
		_resource_links_dirty = true
		_structure_sources_version += 1
	# SCD1 live: do not invent path_built/state on Godot cache — domain pull applies Rust truth.
	if _builder_authority_active() or _structure_authority_active():
		if _outpost_construction_queue != null:
			_outpost_construction_queue.on_path_completed(done_sid, gx, gy, team, is_corridor_link)
		return
	var st: Dictionary = _find_structure_by_sid(done_sid)
	if not st.is_empty():
		var plen: int = int(st.get("path_len", 0))
		if plen <= 0:
			var pk: PackedInt32Array = st.get("path_keys", PackedInt32Array())
			plen = pk.size()
		st["path_built"] = float(maxi(plen, 1))
		if is_corridor_link or kind == OutpostBuildLib.KIND_CORRIDOR_LINK:
			st["state"] = OutpostBuildLib.STATE_ACTIVE
		else:
			st["state"] = OutpostBuildLib.STATE_BUILDING
			if not st.has("build_remaining"):
				st["build_remaining"] = OutpostBuildLib.build_sec_for_kind(kind)
		if globe_map != null:
			globe_map.refresh_markers(
				battle_data.placed_structures, _player_home, _enemy_home, [done_sid]
			)
	if _outpost_construction_queue != null:
		_outpost_construction_queue.on_path_completed(done_sid, gx, gy, team, is_corridor_link)


func _pull_structure_render_cache(merge_by_sid: Dictionary = {}) -> void:
	## SCD1 live: never get_structure_snapshot dual-feed. All callers (place/destroy/world-edit/builder)
	## hit this choke-point and are redirected to versioned domain pull (REQUEST lock).
	if _live_rust_presentation() and _structure_authority_active():
		# Same-frame paint: merge any local placement rows, then SCD1 structures pull.
		for sid_k in merge_by_sid.keys():
			var row = merge_by_sid[sid_k]
			if row is Dictionary:
				_scd1_merge_structure_row(row as Dictionary)
		_presentation_structures_dirty = true
		for sid_k2 in merge_by_sid.keys():
			_presentation_structure_merge[sid_k2] = merge_by_sid[sid_k2]
		if _scd1_pull == null:
			_scd1_pull = Scd1DomainPullLib.new()
		if territory_sim != null:
			var batch: Dictionary = _scd1_pull.pull_domain(territory_sim, "structures", "")
			_apply_scd1_structures(batch)
		return
	# Non-live / CPU parity only.
	if territory_sim != null:
		territory_sim.pull_structure_render_cache(merge_by_sid)


## Upsert one structure dict into battle_data.placed_structures by id (SCD1 same-frame place).
func _scd1_merge_structure_row(row: Dictionary) -> void:
	if battle_data == null:
		return
	var sid: int = int(row.get("id", -1))
	if sid < 0:
		return
	for i in range(battle_data.placed_structures.size()):
		var st = battle_data.placed_structures[i]
		if st is Dictionary and int(st.get("id", -1)) == sid:
			for k in row.keys():
				st[k] = row[k]
			return
	battle_data.placed_structures.append(row.duplicate())


func _request_structure_presentation_refresh(merge_by_sid: Dictionary = {}) -> void:
	## Live SCD1: mark dirty + optional same-frame structures pull (via gated _pull helper).
	if _live_rust_presentation() and _structure_authority_active():
		_pull_structure_render_cache(merge_by_sid)
		return
	_pull_structure_render_cache(merge_by_sid)


## Apply structure field transactions from Rust change feed (no full table dump).
func _apply_structure_field_txn(pres: Dictionary) -> void:
	if battle_data == null or pres.is_empty():
		return
	var sids: PackedInt32Array = pres.get("path_built_sids", PackedInt32Array())
	var vals: PackedFloat32Array = pres.get("path_built_vals", PackedFloat32Array())
	var n: int = mini(sids.size(), vals.size())
	for i in range(n):
		var st: Dictionary = _find_structure_by_sid(int(sids[i]))
		if not st.is_empty():
			st["path_built"] = float(vals[i])
	var state_sids: PackedInt32Array = pres.get("state_sids", PackedInt32Array())
	var state_vals: PackedByteArray = pres.get("state_vals", PackedByteArray())
	var ns: int = mini(state_sids.size(), state_vals.size())
	var marker_sids: Array = []
	for j in range(ns):
		var st2: Dictionary = _find_structure_by_sid(int(state_sids[j]))
		if st2.is_empty():
			continue
		var code: int = int(state_vals[j])
		var prev: String = str(st2.get("state", ""))
		var next_state: String = prev
		match code:
			0:
				next_state = OutpostBuildLib.STATE_CONNECTING
			1:
				next_state = OutpostBuildLib.STATE_BUILDING
			2:
				next_state = OutpostBuildLib.STATE_ACTIVE
			_:
				pass
		# Never thrash finished structures back to CONNECTING (land-bridge pulse bug).
		# Once path is fully built / BUILDING / ACTIVE, reject CONNECTING regressions.
		if next_state == OutpostBuildLib.STATE_CONNECTING:
			var plen: int = OutpostBuildLib.path_len_from_structure(st2)
			var pbuilt: float = float(st2.get("path_built", 0.0))
			if (
				prev == OutpostBuildLib.STATE_BUILDING
				or prev == OutpostBuildLib.STATE_ACTIVE
				or (plen > 0 and pbuilt + 0.001 >= float(plen))
			):
				continue
		st2["state"] = next_state
		# Table says road finished / state changed — refresh that marker immediately
		# so we do not keep the CONNECTING blink after path is complete.
		marker_sids.append(int(state_sids[j]))
	if not marker_sids.is_empty() and globe_map != null:
		globe_map.refresh_markers(
			battle_data.placed_structures, _player_home, _enemy_home, marker_sids
		)


func _apply_structure_snapshot_dict(snap: Dictionary, merge_by_sid: Dictionary = {}) -> void:
	if battle_data == null or snap.is_empty():
		return
	var old_by_sid: Dictionary = {}
	for st_var in battle_data.placed_structures:
		if not st_var is Dictionary:
			continue
		var old_st: Dictionary = st_var
		var sid: int = int(old_st.get("id", -1))
		if sid >= 0:
			old_by_sid[sid] = old_st
	battle_data.placed_structures.clear()
	for st_var2 in snap.get("structures", []):
		if not st_var2 is Dictionary:
			continue
		var st: Dictionary = (st_var2 as Dictionary).duplicate()
		var sid2: int = int(st.get("id", -1))
		var merge_src: Dictionary = merge_by_sid.get(sid2, old_by_sid.get(sid2, {}))
		if merge_src is Dictionary:
			for key in ["health", "source_gx", "source_gy", "click_gx", "click_gy", "spawn_timer"]:
				if merge_src.has(key):
					st[key] = merge_src[key]
		battle_data.placed_structures.append(st)
	for entry_var in snap.get("corridor_synced", []):
		if not entry_var is Dictionary:
			continue
		var entry: Dictionary = entry_var
		var slot: int = int(entry.get("slot", -1))
		var built: int = int(entry.get("corridor_synced_built", 1))
		if slot >= 0 and slot < battle_data.bridge_corridors.size():
			var corridor = battle_data.bridge_corridors[slot]
			if corridor is Dictionary:
				corridor["corridor_synced_built"] = built


func _tick_world_session(dt: float) -> void:
	if battle_data == null or territory_sim == null or dt <= 0.0:
		return
	var au_idx: int = ResourceLib.TYPE_AURELIUM
	# SCD1: pass mirror of Rust wallet (read); session spends inside Rust when wallet active.
	if _resource_wallet_active():
		_pull_resource_wallet_from_rust()
	var result: Dictionary = territory_sim.tick_world_session(dt, _friendly_resources[au_idx])
	if result.is_empty():
		return
	if _resource_wallet_active():
		_pull_resource_wallet_from_rust()
	else:
		_friendly_resources[au_idx] = float(result.get("friendly_aurelium", _friendly_resources[au_idx]))
	if territory_sim != null:
		territory_sim.agent_deficit_dps = Vector2(
			float(result.get("friendly_deficit_dps", 0.0)),
			float(result.get("hostile_deficit_dps", 0.0)),
		)
	_apply_world_session_events(result)


func _apply_world_session_events(result: Dictionary) -> void:
	var need_structure_refresh: bool = false
	for sid_var in result.get("destroyed_sids", PackedInt32Array()):
		_destroy_outpost(int(sid_var), true)
		need_structure_refresh = true
	var timer_result: Dictionary = {
		"activated_sids": [],
		"activated_spawner_sids": [],
		"needs_sim_sync": bool(result.get("needs_sim_sync", false)),
	}
	for sid_v in result.get("activated_sids", PackedInt32Array()):
		timer_result.activated_sids.append(int(sid_v))
	for sid_v2 in result.get("activated_spawner_sids", PackedInt32Array()):
		timer_result.activated_spawner_sids.append(int(sid_v2))
	if (
		not timer_result.activated_sids.is_empty()
		or bool(timer_result.needs_sim_sync)
	):
		_apply_building_timer_result(timer_result)
		need_structure_refresh = true
	if not result.get("spawned_barracks_sids", PackedInt32Array()).is_empty():
		territory_sim.sync_agent_nav()
		_soldier_visual_dirty = true
		need_structure_refresh = true
	if not result.get("spawned_hangar_sids", PackedInt32Array()).is_empty():
		territory_sim.sync_agent_nav()
		_bomber_visual_dirty = true
		need_structure_refresh = true
	if bool(result.get("marker_dirty", false)):
		_outpost_marker_dirty = true
		need_structure_refresh = true
	# Never full-snapshot every world_session tick — only when structure set actually changed.
	if need_structure_refresh and _structure_authority_active():
		_request_structure_presentation_refresh()


func _finalize_rust_world_edit(
	result: Dictionary,
	force_owner_visual: bool,
	sync_agents: bool,
) -> bool:
	if result.is_empty() or territory_sim == null or territory_sim.rust_field == null:
		return false
	if not bool(result.get("changed", false)):
		return false
	territory_sim.rust_field.apply_world_edit_result(
		territory_sim.tile_control, result, battle_data
	)
	if _structure_authority_active():
		_pull_structure_render_cache()
	_sync_claimable_to_backends(force_owner_visual, sync_agents, true)
	return true


func _clear_corridor_sync_state_for_force_full() -> void:
	if battle_data == null:
		return
	for st in battle_data.placed_structures:
		if st is Dictionary:
			st.erase("corridor_synced_built")
	for corridor in battle_data.bridge_corridors:
		if corridor is Dictionary:
			corridor.erase("corridor_synced_built")


func _sync_bridge_corridors_to_sim(force_full: bool = false, sync_backends_now: bool = false, force_owner_visual: bool = true) -> void:
	if territory_sim == null or territory_sim.tile_control == null or battle_data == null:
		return
	var changed: bool = false
	if _rust_world_edit_ready():
		if force_full:
			_clear_corridor_sync_state_for_force_full()
		var result: Dictionary = territory_sim.rust_field.sync_bridge_corridors_rust(
			battle_data, force_full
		)
		changed = bool(result.get("changed", false))
		if sync_backends_now:
			_bridge_backend_sync_pending = false
			_bridge_backend_sync_accum = 0.0
			_finalize_rust_world_edit(result, force_owner_visual, true)
		elif changed:
			territory_sim.rust_field.apply_world_edit_result(
				territory_sim.tile_control, result, battle_data
			)
			_sync_claimable_to_backends(false, true, true)
		else:
			_bridge_backend_sync_pending = true
		return
	changed = territory_sim.tile_control.sync_bridge_corridors_from_map(
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
		if _rust_world_edit_ready():
			var corr_result: Dictionary = territory_sim.rust_field.sync_bridge_corridors_rust(
				battle_data, false, corridor_sids
			)
			if bool(plan.get("immediate_backend", false)):
				_finalize_rust_world_edit(corr_result, true, true)
			else:
				_finalize_rust_world_edit(corr_result, false, false)
		else:
			territory_sim.tile_control.sync_bridge_corridors_for_sids(
				battle_data, corridor_sids, false
			)
			if bool(plan.get("immediate_backend", false)):
				_sync_claimable_to_backends(true, true)
			else:
				_sync_claimable_to_backends(false, false)
	var beachhead: Dictionary = plan.get("beachhead", {})
	if not beachhead.is_empty() and territory_sim.tile_control != null:
		var gx: int = int(beachhead.get("gx", 0))
		var gy: int = int(beachhead.get("gy", 0))
		var team: int = int(beachhead.get("team", BattleTileControlLib.OWNER_FRIENDLY))
		var beach_changed: bool = false
		if _rust_world_edit_ready():
			var beach_result: Dictionary = territory_sim.rust_field.extend_beachhead_from_landing(
				gx, gy, team
			)
			beach_changed = bool(beach_result.get("changed", false))
			if beach_changed:
				if bool(beachhead.get("immediate", false)):
					_finalize_rust_world_edit(beach_result, true, true)
				else:
					_finalize_rust_world_edit(beach_result, false, false)
		elif territory_sim.tile_control.extend_beachhead_from_landing(battle_data, gx, gy, team):
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
	var overlay_is_r8: bool = bool(plan.get("overlay_is_r8", false))
	if overlay_idxs.size() > 0 and globe_map != null:
		var overlay_t: int = 0
		if _frame_profiler != null:
			overlay_t = _frame_profiler.begin_phase("overlay")
		if overlay_is_r8:
			globe_map.apply_ownership_display_delta(overlay_idxs, overlay_vals)
		else:
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
	var destroyed_ids: Array[int] = []
	for st: Dictionary in battle_data.placed_structures:
		var kind: String = str(st.get("kind", ""))
		if not OutpostBuildLib.is_corridor_path_kind(kind):
			continue
		var state: String = str(st.get("state", OutpostBuildLib.STATE_ACTIVE))
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		if OutpostBuildLib.has_build_phase(kind) and (
			state == OutpostBuildLib.STATE_BUILDING
			or state == OutpostBuildLib.STATE_ACTIVE
		):
			_tick_outpost_construction_damage(st, gx, gy, dt, destroyed_ids)
	for sid: int in destroyed_ids:
		_destroy_outpost(sid)


func _tick_soldier_economy(dt: float) -> void:
	if territory_sim == null or dt <= 0.0:
		return
	var living: int = territory_sim.agent_living_count()
	if not territory_sim.agents_ready() or living <= 0:
		territory_sim.agent_deficit_dps = Vector2.ZERO
		return
	var au_idx: int = ResourceLib.TYPE_AURELIUM
	var upkeep: float = float(living) * EconomyLib.soldier_upkeep_aurelium_per_sec() * dt
	if _resource_wallet_active():
		# SCD1: upkeep is a Rust wallet delta; mirror from pull after.
		var wallet: float = _friendly_resources[au_idx]
		var paid: float = minf(upkeep, wallet)
		var deltas: Array = [0.0, 0.0, 0.0]
		deltas[au_idx] = -paid
		territory_sim.apply_resource_tick_delta(deltas, [0.0, 0.0, 0.0])
		_pull_resource_wallet_from_rust()
		var deficit: float = upkeep - paid
		if deficit > 0.0 and upkeep > 0.0:
			territory_sim.agent_deficit_dps.x = CFG.SOLDIER_UPKEEP_DEFICIT_DPS * (deficit / upkeep)
		else:
			territory_sim.agent_deficit_dps.x = 0.0
		return
	var wallet2: float = _friendly_resources[au_idx]
	var paid2: float = minf(upkeep, wallet2)
	_friendly_resources[au_idx] = wallet2 - paid2
	var deficit2: float = upkeep - paid2
	if deficit2 > 0.0 and upkeep > 0.0:
		territory_sim.agent_deficit_dps.x = CFG.SOLDIER_UPKEEP_DEFICIT_DPS * (deficit2 / upkeep)
	else:
		territory_sim.agent_deficit_dps.x = 0.0


func _tick_barracks_spawns(dt: float) -> void:
	if battle_data == null or territory_sim == null or dt <= 0.0:
		return
	if not territory_sim.agents_ready():
		return
	var au_idx: int = ResourceLib.TYPE_AURELIUM
	var spawn_cost: float = EconomyLib.soldier_spawn_aurelium_cost()
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
			if _resource_wallet_active():
				var deltas: Array = [0.0, 0.0, 0.0]
				deltas[au_idx] = -spawn_cost
				territory_sim.apply_resource_tick_delta(deltas, [0.0, 0.0, 0.0])
				_pull_resource_wallet_from_rust()
			else:
				_friendly_resources[au_idx] -= spawn_cost
			st["spawn_timer"] = timer - CFG.BARRACKS_SPAWN_INTERVAL_SEC
			_soldier_visual_dirty = true


func _tick_enemy_strategy(dt: float) -> void:
	if not CFG.ENEMY_AI_ENABLED or battle_data == null or territory_sim == null or dt <= 0.0:
		return
	_drain_enemy_ai_queue()
	_enemy_ai_clock += dt
	if _enemy_ai_clock < CFG.ENEMY_AI_PLAN_INTERVAL_SEC:
		return
	_enemy_ai_clock = 0.0
	if _count_hostile_connecting() >= CFG.ENEMY_AI_MAX_CONCURRENT_BUILDS:
		return
	if _enemy_ai_action_queue.size() >= CFG.ENEMY_AI_MAX_ACTIONS_PER_PLAN:
		return
	var snapshot: Dictionary = _build_enemy_ai_snapshot()
	var planned: Array[Dictionary] = EnemyStrategyLib.plan_actions(snapshot)
	for action: Dictionary in planned:
		_enemy_ai_action_queue.append(action)


func _drain_enemy_ai_queue() -> void:
	var budget: int = CFG.ENEMY_AI_ACTIONS_PER_FRAME
	while budget > 0 and not _enemy_ai_action_queue.is_empty():
		budget -= 1
		var action: Dictionary = _enemy_ai_action_queue.pop_front()
		var kind: String = str(action.get("kind", OutpostBuildLib.KIND_SPAWNER))
		var target: Vector2i = action.get("target", Vector2i(-1, -1))
		if target.x < 0:
			continue
		if not EconomyLib.can_afford_build(_enemy_supply, _hostile_resources, kind):
			continue
		if _count_hostile_connecting() >= CFG.ENEMY_AI_MAX_CONCURRENT_BUILDS:
			_enemy_ai_action_queue.push_front(action)
			return
		_ensure_route_portals_for_team(BattleTileControlLib.OWNER_HOSTILE, _enemy_home)
		# B1: budgeted pathfind first; full A* only if EnemyStrategy rate-limits allow (no free unbounded fallback).
		# Never place AI standalone (no supply path).
		var full_n: int = int(action.get("full_astar_attempts", 0))
		var age: float = float(action.get("plan_age_sec", 0.0))
		var sid: int = debug_place_outpost_at(
			target, kind, BattleTileControlLib.OWNER_HOSTILE, false, false
		)
		if sid < 0 and EnemyStrategyLib.route_allow_full_astar(age, full_n):
			sid = debug_place_outpost_at(
				target, kind, BattleTileControlLib.OWNER_HOSTILE, true, false
			)
			action["full_astar_attempts"] = full_n + 1
		if sid >= 0:
			_pay_enemy_placement_cost(kind)
			_maybe_log_perf_action(
				"enemy_ai",
				{"kind": kind, "gx": target.x, "gy": target.y, "sid": sid},
				1.5,
			)
		else:
			# Drop failed intent — planner will re-evaluate on next interval.
			pass


func _build_enemy_ai_snapshot() -> Dictionary:
	var tc = territory_sim.tile_control if territory_sim != null else null
	return {
		"map_data": battle_data,
		"structures": battle_data.placed_structures if battle_data != null else [],
		"owners": tc.owners if tc != null else PackedByteArray(),
		"enemy_home": _enemy_home,
		"player_home": _player_home,
		"friendly_tiles": _friendly_tiles,
		"hostile_tiles": _hostile_tiles,
		"claimable_tiles": _claimable_tiles,
		"enemy_supply": _enemy_supply,
		"difficulty": _enemy_ai_difficulty,
		"connecting_hostile": _count_hostile_connecting(),
	}


func _count_hostile_connecting() -> int:
	if battle_data == null:
		return 0
	if territory_sim != null and territory_sim.rust_field != null:
		if (
			_structure_authority_active()
			or (
				territory_sim.rust_live_ready
				and territory_sim.rust_field.structure_store_capable()
			)
		):
			return territory_sim.rust_field.structure_connecting_count(
				BattleTileControlLib.OWNER_HOSTILE
			)
	var n: int = 0
	for st: Dictionary in battle_data.placed_structures:
		if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != BattleTileControlLib.OWNER_HOSTILE:
			continue
		if str(st.get("state", "")) == OutpostBuildLib.STATE_CONNECTING:
			n += 1
	return n


func _build_kind_cost(kind: String) -> float:
	return EconomyLib.supply_cost(kind)


func set_enemy_ai_difficulty(difficulty: int) -> void:
	_enemy_ai_difficulty = clampi(
		difficulty, EnemyStrategyLib.Difficulty.BEGINNER, EnemyStrategyLib.Difficulty.EXPERT
	)


func _init_builder_agents() -> void:
	_builder_agents.clear()
	_builder_job_queue_friendly.clear()
	_builder_job_queue_hostile.clear()
	_network_road_pending = PackedInt32Array()
	if territory_sim != null and territory_sim.rust_live_ready:
		territory_sim.configure_builders(_player_home, _enemy_home)
		_seed_network_road_visuals()
	_builder_visual_dirty = true


func _seed_network_road_visuals() -> void:
	if territory_sim == null:
		return
	for team in [BattleTileControlLib.OWNER_FRIENDLY, BattleTileControlLib.OWNER_HOSTILE]:
		var mask: PackedByteArray = territory_sim.get_network_built_mask(team)
		for idx in range(mask.size()):
			if mask[idx] != 0:
				_network_road_pending.append(idx)


func _drain_network_road_visuals() -> void:
	if globe_map == null or _network_road_pending.is_empty():
		return
	var cap: int = CFG.MAX_NETWORK_ROAD_CELLS_PER_FRAME
	var batch := PackedInt32Array()
	var n: int = mini(cap, _network_road_pending.size())
	if n > 0:
		batch = _network_road_pending.slice(0, n)
		_network_road_pending = _network_road_pending.slice(n, _network_road_pending.size())
	if not batch.is_empty():
		globe_map.apply_network_road_cells(batch)


func _builder_job_queue_for_team(team: int) -> Array[int]:
	if team == BattleTileControlLib.OWNER_HOSTILE:
		return _builder_job_queue_hostile
	return _builder_job_queue_friendly


func _enqueue_builder_job(sid: int, team: int) -> void:
	if sid < 0:
		return
	if territory_sim != null and territory_sim.rust_live_ready:
		if not territory_sim.builder_authority_active():
			territory_sim.configure_builders(_player_home, _enemy_home)
	if _builder_authority_active() and territory_sim != null:
		territory_sim.builder_enqueue_job(sid, team)
		_builder_visual_dirty = true
		return
	var q: Array[int] = _builder_job_queue_for_team(team)
	if not q.has(sid):
		q.append(sid)
	_assign_builder_jobs(team)


func _builder_queues_dict() -> Dictionary:
	return {
		"friendly": _builder_job_queue_friendly,
		"hostile": _builder_job_queue_hostile,
	}


func _assign_builder_jobs(team_filter: int = -1) -> void:
	if battle_data == null:
		return
	BuilderAgentLib.assign_builder_jobs(
		_builder_agents,
		_builder_queues_dict(),
		battle_data.placed_structures,
		battle_data.grid_width,
		team_filter,
	)
	_builder_visual_dirty = true


func _start_builder_job(bot: Dictionary, sid: int) -> void:
	if battle_data == null:
		return
	BuilderAgentLib.start_builder_job(bot, sid, battle_data.placed_structures)
	_builder_visual_dirty = true


func _begin_builder_return(bot: Dictionary) -> void:
	if battle_data == null:
		return
	BuilderAgentLib.begin_builder_return(bot, battle_data.placed_structures, battle_data.grid_width)
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
	if _builder_authority_active() and territory_sim != null:
		territory_sim.builder_cancel_job(sid)
		_builder_visual_dirty = true
		return
	_builder_job_queue_friendly.erase(sid)
	_builder_job_queue_hostile.erase(sid)
	for bot: Dictionary in _builder_agents:
		if int(bot.get("job_sid", -1)) == sid:
			_begin_builder_return(bot)


func _update_builder_agents(dt: float) -> void:
	if battle_data == null or dt <= 0.0:
		return
	if _builder_authority_active() and territory_sim != null:
		# Live authority: Rust logistics owns path_built / network growth / completions.
		# Godot only queues mesh cells and mirrors txn fields into the render cache.
		var frame: Dictionary = territory_sim.builder_step(dt)
		if frame.is_empty():
			return
		if bool(frame.get("visual_dirty", false)):
			_outpost_road_dirty = true
		for cell_key in frame.get("new_built_cells", PackedInt32Array()):
			_network_road_pending.append(int(cell_key))
		# Cell growth: path_built applied from PresentationTxn in _flush; local patch for same-frame cache.
		for ev_var in frame.get("cell_arrivals", []):
			_on_rust_builder_cell_arrival(ev_var)
		for ev_var2 in frame.get("path_completions", []):
			_on_rust_builder_path_completed(ev_var2)
		for sid_var in frame.get("completed_corridor_sids", PackedInt32Array()):
			_complete_corridor_link_by_id(int(sid_var))
		# Building timers live in world_session when active — never dual-step GDScript timers.
		_drain_network_road_visuals()
		return
	# Fallback only when builder authority is off (non-live / QA CPU path).
	if _builder_agents.is_empty():
		return
	var tctrl = territory_sim if territory_sim != null else null
	var frame: Dictionary = BuilderAgentLib.step_frame(
		dt,
		_builder_agents,
		battle_data.placed_structures,
		_builder_queues_dict(),
		battle_data.grid_width,
		battle_data,
		tctrl,
	)
	if bool(frame.get("visual_dirty", false)):
		_builder_visual_dirty = true
	for ev_var in frame.get("cell_arrivals", []):
		var ev: Dictionary = ev_var
		var st_arr: Dictionary = _find_structure_by_sid(int(ev.get("sid", -1)))
		if st_arr.is_empty():
			continue
		_emit_builder_cell_arrival(st_arr, int(ev.get("seg_from_idx", 0)))
	for ev_var2 in frame.get("path_completions", []):
		var ev2: Dictionary = ev_var2
		var st_path: Dictionary = _find_structure_by_sid(int(ev2.get("sid", -1)))
		if st_path.is_empty():
			continue
		_emit_builder_path_completed(st_path, bool(ev2.get("is_corridor_link", false)))
	for sid_var in frame.get("completed_corridor_sids", []):
		_complete_corridor_link_by_id(int(sid_var))
	if not _world_session_active():
		_apply_building_timer_result(frame.get("building_timer_result", {}))


func _apply_building_timer_result(result: Dictionary) -> void:
	var activated_sids: Array = result.get("activated_sids", [])
	var activated_spawner_sids: Array = result.get("activated_spawner_sids", [])
	if activated_sids.is_empty() and not bool(result.get("needs_sim_sync", false)):
		return
	if not activated_sids.is_empty() and territory_sim != null and territory_sim.rust_field != null and not _world_session_active():
		for sid_var in activated_sids:
			var sid: int = int(sid_var)
			var st: Dictionary = _find_structure_by_sid(sid)
			if st.is_empty():
				continue
			territory_sim.rust_field.structure_store_patch_state(
				sid,
				str(st.get("state", OutpostBuildLib.STATE_ACTIVE)),
				float(st.get("path_built", -1.0)),
			)
	if _structure_authority_active() and not _world_session_active():
		_pull_structure_render_cache()
	if not activated_spawner_sids.is_empty():
		_structure_sources_version += 1
		_spawners_pending_sync = true
	_road_network_version += 1
	_invalidate_hover_path_cache()
	if _outpost_construction_queue != null:
		for sid_var in activated_sids:
			_outpost_construction_queue.on_build_completed(int(sid_var))
	if bool(result.get("needs_sim_sync", false)):
		_sync_active_spawners_to_sim()


func _emit_builder_cell_arrival(st: Dictionary, seg_from_idx: int) -> void:
	st["path_built"] = BuilderAgentLib.path_built_after_seg(seg_from_idx)
	var kind: String = str(st.get("kind", ""))
	var path_sid: int = int(st.get("id", -1))
	if territory_sim != null and territory_sim.rust_field != null:
		territory_sim.rust_field.structure_store_patch_path_built(
			path_sid, float(st.get("path_built", 1.0))
		)
	if OutpostBuildLib.is_corridor_path_kind(kind) and kind != OutpostBuildLib.KIND_CORRIDOR_LINK:
		_road_network_version += 1
		if kind == OutpostBuildLib.KIND_SPAWNER:
			_resource_links_dirty = true
	if _outpost_construction_queue != null:
		_outpost_construction_queue.on_cell_advanced(path_sid)


func _emit_builder_path_completed(st: Dictionary, is_corridor_link: bool) -> void:
	var done_sid: int = int(st.get("id", -1))
	var gx: int = int(st.get("gx", 0))
	var gy: int = int(st.get("gy", 0))
	var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	if territory_sim != null and territory_sim.rust_field != null:
		territory_sim.rust_field.structure_store_patch_path_built(
			done_sid, float(st.get("path_built", -1.0))
		)
		if is_corridor_link:
			territory_sim.rust_field.structure_store_patch_state(
				done_sid,
				str(st.get("state", OutpostBuildLib.STATE_CONNECTING)),
				float(st.get("path_built", -1.0)),
			)
		else:
			var kind: String = str(st.get("kind", ""))
			territory_sim.rust_field.structure_store_enter_building(
				done_sid,
				OutpostBuildLib.build_sec_for_kind(kind),
				CFG.OUTPOST_MAX_HEALTH,
			)
	if _structure_authority_active():
		_pull_structure_render_cache()
	if _outpost_construction_queue != null:
		_outpost_construction_queue.on_path_completed(done_sid, gx, gy, team, is_corridor_link)


func _builder_home_grid(bot: Dictionary) -> Vector2i:
	return Vector2i(int(bot.get("home_gx", 0)), int(bot.get("home_gy", 0)))


func _builder_work_grid_pos(bot: Dictionary) -> Vector2:
	if battle_data == null:
		var home_fb: Vector2i = _builder_home_grid(bot)
		return BuilderAgentLib.orbit_grid(home_fb, float(bot.get("orbit_angle", 0.0)))
	return BuilderAgentLib.work_grid_pos(
		bot, battle_data.placed_structures, battle_data.grid_width
	)


func _update_builder_visuals(_delta: float) -> void:
	if _builder_authority_active() or globe_map == null:
		return
	if _builder_agents.is_empty():
		return
	_builder_visual_clock += _delta
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


func _update_bomber_visuals(delta: float) -> void:
	if globe_map == null or territory_sim == null:
		return
	if not territory_sim.bombers_ready():
		globe_map.sync_bombers(PackedByteArray(), PackedInt32Array(), PackedInt32Array())
		return
	_bomber_visual_clock += delta
	var bomber_refresh_sec: float = 1.0 / CFG.BOMBER_VISUAL_UPDATES_PER_SEC
	if not _bomber_visual_dirty and _bomber_visual_clock < bomber_refresh_sec:
		return
	_bomber_visual_clock = 0.0
	_bomber_visual_dirty = false
	var snap: Dictionary = territory_sim.get_bomber_snapshot()
	globe_map.sync_bombers(
		snap.get("teams", PackedByteArray()),
		snap.get("gx", PackedInt32Array()),
		snap.get("gy", PackedInt32Array()),
		snap.get("search_scope", PackedInt32Array()),
	)
	globe_map.play_bomb_drops(
		snap.get("bomb_teams", PackedByteArray()),
		snap.get("bomb_gx", PackedInt32Array()),
		snap.get("bomb_gy", PackedInt32Array()),
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
		# Already migrated to bridge_corridors (idempotent).
		return
	var gx: int = int(st.get("gx", 0))
	var gy: int = int(st.get("gy", 0))
	# Stop CONNECTING pulse immediately — land bridges have no BUILDING phase.
	var plen: int = OutpostBuildLib.path_len_from_structure(st)
	if plen <= 0:
		plen = int(st.get("path_len", 0))
	var path_keys: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if path_keys.is_empty() and globe_map != null and globe_map.has_method("_packed_path_keys"):
		# Keep ribbon continuity if path only lived in globe path cache.
		pass
	st["state"] = OutpostBuildLib.STATE_ACTIVE
	st["path_built"] = float(maxi(plen, 1))
	st["path_len"] = maxi(plen, path_keys.size())
	# Persist full ribbon under bridge_corridors (structure pin removed below; road + landing stay).
	var already_bridged: bool = false
	for bc in battle_data.bridge_corridors:
		if bc is Dictionary and int(bc.get("id", -1)) == sid:
			already_bridged = true
			# Refresh path if we have a fuller one now.
			if path_keys.size() > PackedInt32Array(bc.get("path_keys", PackedInt32Array())).size():
				bc["path_keys"] = path_keys
			break
	if not already_bridged:
		battle_data.bridge_corridors.append({
			"id": sid,
			"team": int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)),
			"gx": gx,
			"gy": gy,
			"path_keys": path_keys.duplicate(),
			"path_len": maxi(plen, path_keys.size()),
			"path_built": float(maxi(plen, path_keys.size())),
			"state": OutpostBuildLib.STATE_ACTIVE,
			"kind": OutpostBuildLib.KIND_CORRIDOR_LINK,
		})
	# Drop from placed_structures so CONNECTING pulse cannot stick; road cache keeps sid via bridge_corridors.
	battle_data.placed_structures.remove_at(idx)
	if territory_sim != null and territory_sim.rust_field != null:
		territory_sim.rust_field.structure_store_remove(sid)
		# Sync store from map (structures without this corridor + bridge_corridors list). Avoid full
		# pull_structure_render_cache — it rewrites placed_structures and is expensive mid-game.
		territory_sim.rust_field.sync_structure_store_from_map(battle_data)
	# Claimable / beachhead: force once for this corridor (not every sim tick).
	_sync_bridge_corridors_to_sim(false, true, true)
	_extend_beachhead_at_landing(st, gx, gy)
	_structure_sources_version += 1
	_road_network_version += 1
	_resource_links_dirty = true
	_invalidate_hover_path_cache()
	# Ensure full ribbon is painted for this sid and solid landing marker is shown.
	_outpost_road_dirty = true
	_outpost_marker_dirty = true
	_refresh_outpost_visuals(true, true, [sid], [])


func _tick_outpost_construction_damage(
	st: Dictionary, gx: int, gy: int, dt: float, destroyed_ids: Array[int]
) -> void:
	if territory_sim == null:
		return
	var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
	var dps: float = OutpostBuildLib.construction_dps_at(
		battle_data, territory_sim, gx, gy, team
	)
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


func _destroy_outpost(sid: int, skip_rust_remove: bool = false) -> void:
	if sid < 0 or battle_data == null:
		return
	var grid: Vector2i = Vector2i(-1, -1)
	var was_barracks: bool = false
	var was_hangar: bool = false
	for i in range(battle_data.placed_structures.size() - 1, -1, -1):
		var st: Dictionary = battle_data.placed_structures[i]
		if int(st.get("id", -1)) != sid:
			continue
		grid = Vector2i(int(st.get("gx", 0)), int(st.get("gy", 0)))
		was_barracks = str(st.get("kind", "")) == OutpostBuildLib.KIND_BARRACKS
		was_hangar = str(st.get("kind", "")) == OutpostBuildLib.KIND_HANGAR
		if not _structure_authority_active() and not skip_rust_remove:
			battle_data.placed_structures.remove_at(i)
		break
	if grid.x < 0:
		return
	if not skip_rust_remove and territory_sim != null and territory_sim.rust_field != null:
		territory_sim.rust_field.structure_store_remove(sid)
	# Always drop from render cache under SCD1; incremental pulls do not emit deletions.
	if _structure_authority_active() or skip_rust_remove:
		if battle_data != null:
			for j in range(battle_data.placed_structures.size() - 1, -1, -1):
				var st2 = battle_data.placed_structures[j]
				if st2 is Dictionary and int(st2.get("id", -1)) == sid:
					battle_data.placed_structures.remove_at(j)
					break
		_pull_structure_render_cache()
	_cancel_builder_job_for_sid(sid)
	if was_barracks and territory_sim != null:
		territory_sim.notify_barracks_destroyed(sid)
		_soldier_visual_dirty = true
	if was_hangar and territory_sim != null:
		territory_sim.notify_hangar_destroyed(sid)
		_bomber_visual_dirty = true
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
	if territory_sim == null:
		return ""
	var dps: float = OutpostBuildLib.construction_dps_at(
		battle_data, territory_sim, gx, gy
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
	if _rust_world_edit_ready():
		var result: Dictionary = territory_sim.rust_field.extend_beachhead_from_landing(gx, gy, team)
		if not bool(result.get("changed", false)):
			return
		if defer_backend_sync and _outpost_construction_queue != null:
			_outpost_construction_queue.enqueue_corridor(int(st.get("id", -1)))
		else:
			_finalize_rust_world_edit(result, true, true)
		return
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
	var grid: Vector2i = _mouse_to_grid()
	var bridge_stats: Dictionary = territory_sim.count_claimable_bridge_cells()
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
	var probe: Dictionary = territory_sim.query_tile(grid.x, grid.y)
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


func _sync_active_spawners_to_sim() -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	tc.sync_placed_spawners_from_map(battle_data)
	if not territory_sim.grid_authority_active():
		tc.sync_bridge_corridors_from_map(battle_data, true)
	var live_claimable: int = territory_sim.claimable_tile_count_live()
	if live_claimable > 0:
		territory_sim.claimable_tiles = live_claimable
		_claimable_tiles = live_claimable
	if territory_sim.rust_live_ready and territory_sim.rust_field != null:
		if not territory_sim.grid_authority_active():
			territory_sim.rust_field.sync_claimable_from(tc, battle_data, true)
		territory_sim.rust_field.sync_spawners_from(tc)
	if (
		not territory_sim.world_dataset_live_active()
		and territory_sim.use_gpu_for_live()
		and territory_sim.gpu_field != null
	):
		territory_sim.gpu_field.refresh_claimable_from(battle_data, tc)


func _sync_counts() -> void:
	if territory_sim == null:
		return
	_sim_time = territory_sim.sim_time
	if territory_sim.grid_authority_active() and territory_sim.rust_field != null:
		_friendly_tiles = territory_sim.rust_field.friendly_tiles
		_hostile_tiles = territory_sim.rust_field.hostile_tiles
		return
	if territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
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
	var snapshot: Dictionary = gather_perf_and_action_context()
	var cpu: Dictionary = snapshot.get("cpu", {})
	var cpu_p99: float = float(cpu.get("p99_ms", 0.0))
	var last_ms: float = float(cpu.get("last_ms", 0.0))
	if last_ms <= 0.0 and _frame_profiler != null:
		last_ms = _frame_profiler.prior_frame_ms()
	# CPU-bound if process time is high; otherwise treat as GPU/present path.
	var note: String = "likely_cpu" if cpu_p99 > 12.0 or last_ms > 12.0 else "likely_gpu"
	var extra: Dictionary = {"note": note}
	if _frame_profiler != null:
		var phases: String = _frame_profiler.phase_summary_line()
		if phases != "":
			extra["phases"] = phases
		extra["last_ms"] = "%.1f" % last_ms
	RunLog.warn(perf_format_log_line("fps_drop", snapshot, extra))


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
		var perf_txt: String = perf_build_hud_text(gather_perf_and_action_context())
		if _frame_profiler != null and _frame_profiler.has_method("hud_line"):
			perf_txt += "\n" + str(_frame_profiler.hud_line())
		perf_hud_label.text = perf_txt
	elif perf_hud_label:
		perf_hud_label.visible = false
	if _world_dataset_entry_failed:
		status_label.text = "WorldDataset FAIL CLOSED — fix Rust DLL / live flags"
		return
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
	spawner_button.text = str(
		_cached_structure_hud_labels.get(OutpostBuildLib.KIND_SPAWNER, "Outpost")
	)
	if barracks_button:
		barracks_button.text = str(
			_cached_structure_hud_labels.get(OutpostBuildLib.KIND_BARRACKS, "Barracks")
		)
	if hangar_button:
		hangar_button.text = str(
			_cached_structure_hud_labels.get(OutpostBuildLib.KIND_HANGAR, "Hangar")
		)
	if corridor_link_button:
		corridor_link_button.text = str(
			_cached_structure_hud_labels.get(OutpostBuildLib.KIND_CORRIDOR_LINK, "Land Bridge")
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
	if hangar_button:
		hangar_button.set_block_signals(true)
		hangar_button.button_pressed = _build_mode == OutpostBuildLib.KIND_HANGAR
		hangar_button.set_block_signals(false)
	if _build_mode == OutpostBuildLib.KIND_SPAWNER:
		build_hint_label.text = (
			(
				"Left-click connected land (%s). Use Land Bridge first for foreign coasts. "
				+ "~%.0fs build after any bridge segment. Esc cancel."
			)
			% [
				_format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER)),
				EconomyLib.build_sec_for_kind(OutpostBuildLib.KIND_SPAWNER),
			]
		)
	elif _build_mode == OutpostBuildLib.KIND_BARRACKS:
		build_hint_label.text = (
			(
				"Left-click connected land (%s). Road builds, then ~%.0fs barracks build. "
				+ "Spawns cost Au. Esc cancel."
			)
			% [
				_format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_BARRACKS)),
				EconomyLib.build_sec_for_kind(OutpostBuildLib.KIND_BARRACKS),
			]
		)
	elif _build_mode == OutpostBuildLib.KIND_HANGAR:
		build_hint_label.text = (
			(
				"Left-click connected land (%s). Road builds, then ~%.0fs hangar build. "
				+ "Bombers cost Au. Esc cancel."
			)
			% [
				_format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_HANGAR)),
				EconomyLib.build_sec_for_kind(OutpostBuildLib.KIND_HANGAR),
			]
		)
	elif _build_mode == OutpostBuildLib.KIND_CORRIDOR_LINK:
		build_hint_label.text = (
			(
				"Left-click enemy or neutral coast (%s). Inland clicks snap to shore. "
				+ "Route crosses water — short land leg from your territory, then bridge to landing. Esc cancel."
			)
			% _format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_CORRIDOR_LINK))
		)
	else:
		build_hint_label.text = (
			"Outpost (%s) · Barracks (%s) · Land Bridge (%s)"
			% [
				_format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER)),
				_format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_BARRACKS)),
				_format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_CORRIDOR_LINK)),
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
		_cancel_hover_route_request()
	var allow_astar: bool = CFG.OUTPOST_HOVER_ALLOW_ASTAR
	_route_hover_request_id = route_planner.start_route_async(landing, _build_mode, allow_astar)


func _apply_build_mode(mode: String) -> void:
	_build_mode = mode
	_route_hover_clock = 0.0
	if mode == "":
		_cancel_place_route_request()
	_invalidate_hover_path_cache()
	if mode == OutpostBuildLib.KIND_SPAWNER and barracks_button:
		barracks_button.set_block_signals(true)
		barracks_button.button_pressed = false
		barracks_button.set_block_signals(false)
		if hangar_button:
			hangar_button.set_block_signals(true)
			hangar_button.button_pressed = false
			hangar_button.set_block_signals(false)
		if corridor_link_button:
			corridor_link_button.set_block_signals(true)
			corridor_link_button.button_pressed = false
			corridor_link_button.set_block_signals(false)
	elif mode == OutpostBuildLib.KIND_BARRACKS:
		spawner_button.set_block_signals(true)
		spawner_button.button_pressed = false
		spawner_button.set_block_signals(false)
		if hangar_button:
			hangar_button.set_block_signals(true)
			hangar_button.button_pressed = false
			hangar_button.set_block_signals(false)
		if corridor_link_button:
			corridor_link_button.set_block_signals(true)
			corridor_link_button.button_pressed = false
			corridor_link_button.set_block_signals(false)
	elif mode == OutpostBuildLib.KIND_HANGAR:
		spawner_button.set_block_signals(true)
		spawner_button.button_pressed = false
		spawner_button.set_block_signals(false)
		if barracks_button:
			barracks_button.set_block_signals(true)
			barracks_button.button_pressed = false
			barracks_button.set_block_signals(false)
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
		if hangar_button:
			hangar_button.set_block_signals(true)
			hangar_button.button_pressed = false
			hangar_button.set_block_signals(false)
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


func _on_hangar_toggled(on: bool) -> void:
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_HANGAR)
	elif _build_mode == OutpostBuildLib.KIND_HANGAR:
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
	# One full Rust→globe sync so victory never leaves a stale painted map.
	_apply_owner_visual_from_backends()
	if globe_map != null:
		globe_map.flush_pending_owner_gpu_upload(true)
	var res: Dictionary = territory_sim.get_result()
	_battle_finished = true
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
