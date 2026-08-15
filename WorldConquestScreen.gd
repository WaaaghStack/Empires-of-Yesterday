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

const WorldPackLibScript := preload("res://WorldPackLib.gd")

@onready var globe_map: EarthGlobeMapLib = $PlayArea/SubViewportContainer/SubViewport/GlobeMap
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var play_area: Control = $PlayArea
@onready var summary_bar: PanelContainer = $MatchRibbon
@onready var you_caption: Label = $MatchRibbon/RibbonHBox/TugWrap/YouCaption
@onready var enemy_caption: Label = $MatchRibbon/RibbonHBox/TugWrap/EnemyCaption
@onready var au_label: Label = $MatchRibbon/RibbonHBox/MineralsRow/AuLabel
@onready var ve_label: Label = $MatchRibbon/RibbonHBox/MineralsRow/VeLabel
@onready var em_label: Label = $MatchRibbon/RibbonHBox/MineralsRow/EmLabel
@onready var time_label: Label = $MatchRibbon/RibbonHBox/TimeLabel
@onready var supply_label: Label = $MatchRibbon/RibbonHBox/SupplyLabel
@onready var status_label: Label = $BuildCluster/VBox/StatusLabel
@onready var hover_label: Label = $BuildCluster/VBox/HoverLabel
@onready var pause_button: Button = $SimCluster/HBox/PauseButton
@onready var speed_button: Button = $SimCluster/HBox/SpeedButton
@onready var spawner_button: Button = $BuildCluster/VBox/HBox/SpawnerButton
@onready var barracks_button: Button = $BuildCluster/VBox/HBox/BarracksButton
@onready var hangar_button: Button = $BuildCluster/VBox/HBox/HangarButton
@onready var inspect_button: Button = $BuildCluster/VBox/HBox/InspectButton
@onready var paint_button: Button = $BuildCluster/VBox/HBox/PaintButton
@onready var mode_button: Button = $OutpostPinCard/VBox/ModeButton
@onready var surge_button: Button = $OutpostPinCard/VBox/SurgeButton
@onready var tile_probe_label: Label = $InspectCard/InspectVBox/InspectLabel
@onready var inspect_claim_label: Label = $InspectCard/InspectVBox/ClaimLabel
@onready var inspect_pressure_blue: ColorRect = $InspectCard/InspectVBox/PressureMeters/BlueFill
@onready var inspect_pressure_red: ColorRect = $InspectCard/InspectVBox/PressureMeters/RedFill
@onready var inspect_pressure_caption: Label = $InspectCard/InspectVBox/PressureCaption
@onready var inspect_elev_bar: ProgressBar = $InspectCard/InspectVBox/ElevBar
@onready var inspect_elev_caption: Label = $InspectCard/InspectVBox/ElevCaption
@onready var inspect_card: PanelContainer = $InspectCard
@onready var back_button: Button = $MatchRibbon/RibbonHBox/BackButton
@onready var build_hint_label: Label = $BuildCluster/VBox/BuildHintLabel
@onready var cancel_paint_button: Button = $BuildCluster/VBox/HBox/CancelPaintButton
@onready var land_tug_blue: ColorRect = $MatchRibbon/RibbonHBox/TugWrap/LandTug/BlueFill
@onready var land_tug_neutral: ColorRect = $MatchRibbon/RibbonHBox/TugWrap/LandTug/NeutralFill
@onready var land_tug_red: ColorRect = $MatchRibbon/RibbonHBox/TugWrap/LandTug/RedFill
@onready var deploy_timer_bar: ProgressBar = $LoadingOverlay/DeployBanner/DeployRow/DeployCommit/DeployTimer
@onready var outpost_pin_card: PanelContainer = $OutpostPinCard
@onready var build_cluster: PanelContainer = $BuildCluster
@onready var sim_cluster: PanelContainer = $SimCluster
@onready var loading_status_line: Label = $LoadingOverlay/StatusLine
@onready var deploy_title_label: Label = $LoadingOverlay/DeployTitle
@onready var end_details_button: Button = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/DetailsButton
@onready var end_kpi_strip: HBoxContainer = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip
@onready var end_compare_row: HBoxContainer = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow
@onready var perf_hud_label: Label = $PerfHudLabel
@onready var end_overlay: Control = $EndOverlay
@onready var end_dim: ColorRect = $EndOverlay/Dim
@onready var end_scroll: ScrollContainer = $EndOverlay/ScrollCenter/Scroll
@onready var end_dash_panel: PanelContainer = $EndOverlay/ScrollCenter/Scroll/EndDashPanel
@onready var end_headline_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/Headline
@onready var end_reason_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/Reason
@onready var end_kpi_land_held: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip/KpiLandHeld/VBox/Value
@onready var end_kpi_peak_land: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip/KpiPeakLand/VBox/Value
@onready var end_kpi_sim_time: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip/KpiSimTime/VBox/Value
@onready var end_kpi_structures: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip/KpiStructures/VBox/Value
@onready var end_kpi_soldiers: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip/KpiSoldiers/VBox/Value
@onready var end_kpi_bombers: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/KPIStrip/KpiBombers/VBox/Value
@onready var end_you_land_bar: ProgressBar = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareYou/YouLandBar
@onready var end_you_tiles_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareYou/YouTiles
@onready var end_you_pressure_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareYou/YouPressure
@onready var end_you_supply_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareYou/YouSupply
@onready var end_you_minerals_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareYou/YouMinerals
@onready var end_enemy_land_bar: ProgressBar = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareEnemy/EnemyLandBar
@onready var end_enemy_tiles_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareEnemy/EnemyTiles
@onready var end_enemy_pressure_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareEnemy/EnemyPressure
@onready var end_enemy_supply_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareEnemy/EnemySupply
@onready var end_enemy_minerals_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/CompareRow/CompareEnemy/EnemyMinerals
@onready var end_forces_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/ForcesRow
@onready var end_meta_label: Label = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/MetaRow
@onready var end_play_again_button: Button = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/EndButtons/PlayAgainButton
@onready var end_same_map_button: Button = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/EndButtons/SameMapButton
@onready var end_menu_button: Button = $EndOverlay/ScrollCenter/Scroll/EndDashPanel/EndVBox/EndButtons/MenuButton
@onready var clarity_banner: PanelContainer = $ClarityBanner
@onready var clarity_label: Label = $ClarityBanner/ClarityLabel
@onready var loading_overlay: Control = $LoadingOverlay
@onready var loading_dim: ColorRect = $LoadingOverlay/Dim
@onready var loading_center: CenterContainer = $LoadingOverlay/Center
@onready var loading_status_label: Label = $LoadingOverlay/Center/LoadPanel/VBox/StatusLabel
@onready var loading_progress: ProgressBar = $LoadingOverlay/Center/LoadPanel/VBox/ProgressBar
@onready var deploy_banner: PanelContainer = $LoadingOverlay/DeployBanner
@onready var deploy_countdown_label: Label = $LoadingOverlay/DeployBanner/DeployRow/DeployCountdown
@onready var deploy_button: Button = $LoadingOverlay/DeployBanner/DeployRow/DeployCommit/DeployButton
@onready var deploy_hint_label: Label = $LoadingOverlay/DeployHint

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
var _enemy_ai_place_cooldown: float = 0.0
## Friendly-side mirror of enemy AI (AI vs AI test mode only).
var _player_ai_clock: float = 0.0
var _player_ai_action_queue: Array[Dictionary] = []
var _player_ai_place_cooldown: float = 0.0
## Throttle for empty AI plan soak diagnostics (AI vs AI); msec of last log.
var _ai_empty_plan_log_msec: int = 0
## Throttle for AI placement precheck reject diagnostics (AI vs AI).
var _ai_place_reject_log_msec: int = 0
## A1/E8: set when live WorldDataset entry fails (missing DLL / assert).
var _world_dataset_entry_failed: bool = false
## SCD1 versioned domain pulls (live paint — replaces PresentationTxn).
var _scd1_pull: Scd1DomainPullLib = Scd1DomainPullLib.new()
var _sim_time: float = 0.0
var _paused: bool = false
var _speed_mult: float = 1.0
var _overlay_clock: float = 0.0
var _depth_overlay_clock: float = 0.0
var _battle_finished: bool = false
var _build_mode: String = ""
var _paint_armed: bool = false
var _paint_stroke_active: bool = false
var _paint_last_cell: Vector2i = Vector2i(-99999, -99999)
var _selected_sid: int = -1
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
var _last_resource_shockwaves: Array = []
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
## Parallel to _network_road_pending: road class byte per queued cell (paint hierarchy).
var _network_road_pending_class: PackedByteArray = PackedByteArray()
## Intended final class per cell (spur/arterial/bridge); planned paint upgrades to this when built.
var _road_class_by_cell: Dictionary = {}
## Center cell id → PackedInt32Array of two shoulder cell ids (black | white | black).
var _road_shoulders_by_center: Dictionary = {}
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
var _deploy_phase: bool = false
var _deploy_pick_remaining: float = 0.0
var _deploy_locked_grid: Vector2i = Vector2i(-1, -1)
var _deploy_hover_grid: Vector2i = Vector2i(-1, -1)
var _deploy_commit_grid: Vector2i = Vector2i(-1, -1)
var _deploy_resolved: bool = false
var _deploy_auto_picked: bool = false
var _deploy_skip_reveal: bool = false
var _deploy_run_seed: int = 0
var _map_id: String = ""
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
## End-game FPS: after skipping sim once under FRAME_MS_SKIP_SIM, force resume next frame.
var _sim_skip_resume_next: bool = false
## Applied soft-cap (avoids redundant FFI); -1 = unknown / not yet set.
var _applied_soft_cap: int = -1
## Consecutive frames with prior_ms ≤ FRAME_BUDGET_MS while soft-cap is sticky-lowered.
var _soft_cap_healthy_streak: int = 0
## Last soft_cap RunLog time (Time.get_ticks_msec); rate-limits spam.
var _soft_cap_log_at_msec: int = 0
## Defer AI one frame when prior frame was heavy and this frame runs a sim step.
var _ai_deferred_dt: float = 0.0
var _cached_structure_hud_labels: Dictionary = {}
const PERF_RECENT_ACTION_MAX := 64
const CLARITY_BEAT_COUNT := 5
const CLARITY_BEAT_DISMISS_SEC := 8.0
const CLARITY_BEAT_TEXTS: Array[String] = [
	"Blue pressure spreads from your capital like a fluid.",
	"Build an Outpost on land you hold — 400 Supply — to pump the front forward.",
	"Au · Ve · Em fund soldiers and bombers. Own deposits to refill faster.",
	"Soldiers ferry open water when the land front runs out. Land to open a new shore.",
	"Hangars launch bombers that can open islands you cannot ferry to.",
]
var _clarity_beat_index: int = 0
var _clarity_beat_showing: bool = false
var _clarity_timer: float = 0.0
var _clarity_pressure_dismissed: bool = false
var _clarity_outpost_dismissed: bool = false
var _clarity_minerals_dismissed_at: float = -1.0
var _clarity_first_outpost_placed: bool = false
var _clarity_click_dismiss: bool = false
var _clarity_poll_clock: float = 0.0
var _coast_check_cache: bool = false
var _coast_check_known: bool = false
var _coast_check_clock: float = 0.0
var _run_structures_placed: int = 0
var _run_soldiers_spawned: int = 0
var _run_bombers_spawned: int = 0
var _run_peak_land_pct: int = 0
var _run_peak_enemy_land_pct: int = 0
var _run_outposts_placed: int = 0
var _run_barracks_placed: int = 0
var _run_hangars_placed: int = 0
var _run_enemy_structures_placed: int = 0
var _run_player_structures_placed: int = 0
var _run_supply_spent: float = 0.0
var _run_peak_soldiers: int = 0
var _run_peak_bombers: int = 0
var _run_first_outpost_sec: float = -1.0
var _conquest_nudge_shown: bool = false
var _orbit_seen: bool = false
var _end_details_open: bool = false
var _load_pack_warm: bool = false
var _clarity_pulse_tween: Tween
var _last_agent_teams: PackedByteArray = PackedByteArray()
var _last_agent_gx: PackedInt32Array = PackedInt32Array()
var _last_agent_gy: PackedInt32Array = PackedInt32Array()
var _last_bomber_teams: PackedByteArray = PackedByteArray()
var _last_bomber_gx: PackedInt32Array = PackedInt32Array()
var _last_bomber_gy: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	Engine.max_fps = 60
	_frame_profiler = FrameBudgetProfilerLib.new()
	_outpost_construction_queue = OutpostConstructionQueueLib.new()
	GameTheme.apply_to_control(self)
	_style_summary_hud()
	_setup_clarity_banner()
	_style_loading_overlay()
	_style_end_overlay()
	loading_overlay.visible = true
	_set_load_progress(0.0, "Baking terrain…")
	_load_started_msec = Time.get_ticks_msec()
	back_button.pressed.connect(_on_back_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.pressed.connect(_on_speed_pressed)
	spawner_button.toggled.connect(_on_spawner_toggled)
	if barracks_button:
		barracks_button.toggled.connect(_on_barracks_toggled)
	if hangar_button:
		hangar_button.toggled.connect(_on_hangar_toggled)
	inspect_button.toggled.connect(_on_inspect_toggled)
	if paint_button:
		paint_button.toggled.connect(_on_paint_toggled)
		paint_button.tooltip_text = "Paint a region: click-drag on the globe. Soldiers and bombers go there until you own it."
	if mode_button:
		mode_button.pressed.connect(_on_mode_pressed)
		mode_button.tooltip_text = "Cycle selected outpost: Pump / Drain / Battery."
	if surge_button:
		surge_button.pressed.connect(_on_surge_pressed)
		surge_button.tooltip_text = "Dump a Battery outpost's stored pressure as one wave."
	if cancel_paint_button:
		cancel_paint_button.pressed.connect(_on_cancel_paint_pressed)
		cancel_paint_button.tooltip_text = "Clear the painted region (Esc)."
	if inspect_card:
		inspect_card.add_theme_stylebox_override(
			"panel", GameThemeLib.make_panel_style(Color(0.09, 0.11, 0.16, 0.78), GameThemeLib.BORDER, 6)
		)
		inspect_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_button.tooltip_text = "Pause / resume (Space)"
	speed_button.tooltip_text = "Cycle sim speed x1 / x2 / x4"
	end_overlay.visible = false
	if end_play_again_button:
		end_play_again_button.pressed.connect(_on_play_again_pressed)
	if end_same_map_button:
		end_same_map_button.pressed.connect(_on_same_map_pressed)
		end_same_map_button.tooltip_text = "Replay this map — pick a new capital."
	if end_menu_button:
		end_menu_button.pressed.connect(_on_end_menu_pressed)
	if end_details_button:
		end_details_button.pressed.connect(_on_end_details_pressed)
	if spawner_button:
		spawner_button.tooltip_text = "Outpost · 400"
		_bind_tool_hover(spawner_button, "Outpost · 400")
	if barracks_button:
		barracks_button.tooltip_text = "Barracks · 400"
		_bind_tool_hover(barracks_button, "Barracks · 400")
	if hangar_button:
		hangar_button.tooltip_text = "Hangar · 400"
		_bind_tool_hover(hangar_button, "Hangar · 400")
	if paint_button:
		_bind_tool_hover(paint_button, "Paint")
	if inspect_button:
		_bind_tool_hover(inspect_button, "Inspect")
	if cancel_paint_button:
		_bind_tool_hover(cancel_paint_button, "Clear paint")
	if deploy_button:
		deploy_button.pressed.connect(_on_deploy_button_pressed)
	_setup_tool_icons()
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
		summary_bar.z_index = 41
	if build_cluster:
		build_cluster.z_index = 40
	if sim_cluster:
		sim_cluster.z_index = 40
	if perf_hud_label:
		perf_hud_label.visible = false
		perf_hud_label.z_index = 42
	call_deferred("_bootstrap_async")


func _bootstrap_async() -> void:
	_set_load_progress(0.08, "Baking terrain…")
	await get_tree().process_frame
	EconomyLib.ensure_loaded(RunState.economy_pack_id)
	_refresh_cached_structure_hud_labels()
	var seed_val: int = RunState.run_seed if RunState.run_seed != 0 else randi() & 0x7FFFFFFF
	_deploy_run_seed = seed_val
	_map_id = WorldMapCatalogLib.resolve_map_id(RunState.world_map_id)
	if RunState.ai_difficulty >= 0:
		set_enemy_ai_difficulty(RunState.ai_difficulty)
	# Probe cache before generate — generate writes the pack, so a post-bake check is always warm.
	_load_pack_warm = _is_world_pack_warm(_map_id, seed_val)
	battle_data = WorldConquestMapGeneratorLib.generate(
		_map_id, seed_val, false, RunState.map_gen_criteria()
	)
	_set_load_progress(0.35, "Lighting atmosphere…")
	await get_tree().process_frame
	_setup_globe_terrain_early(_map_id)
	if sub_viewport:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	if loading_center:
		loading_center.visible = false
	if loading_progress:
		loading_progress.visible = false
	if loading_status_line:
		loading_status_line.visible = true
	if loading_dim:
		loading_dim.color = Color(loading_dim.color.r, loading_dim.color.g, loading_dim.color.b, 0.35)
	_set_load_progress(0.55, "Seeding minerals…")
	await _await_min_load_time()
	_enter_deploy_phase()
	if _should_skip_deploy_pick():
		_skip_deploy_pick_fast()
	while not _deploy_resolved:
		await get_tree().process_frame
	await _apply_deploy_spawns()
	_set_load_progress(0.72, "Opening the front…")
	await get_tree().process_frame
	territory_sim = BattleTerritorySimLib.new()
	territory_sim.use_simple_water_model = true
	territory_sim.set_resolve_context("world_conquest")
	territory_sim.setup(battle_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	_claimable_tiles = territory_sim.claimable_tiles
	_player_home = battle_data.player_home_grid
	_enemy_home = battle_data.enemy_home_grid
	_sync_counts()
	_set_load_progress(0.82, "Waking the war room…")
	await get_tree().process_frame
	_setup_sim_after_spawns(_map_id)
	_set_load_progress(0.88, "Charting routes…")
	await get_tree().process_frame
	_warm_route_planner_at_load()
	_set_load_progress(0.94, "Warming the globe…")
	await get_tree().process_frame
	_update_tile_overlay(true)
	_update_hud()
	_set_load_progress(1.0, "Ready")
	await get_tree().process_frame
	_exit_deploy_overlay()
	loading_overlay.visible = false
	_loading = false
	_reset_run_metrics()
	_apply_ai_vs_ai_mode()
	if paint_button:
		paint_button.visible = not RunState.is_ai_vs_ai()
		paint_button.disabled = false
	_clarity_on_match_live()
	if globe_map != null and globe_map.has_method("frame_both_capitals"):
		globe_map.frame_both_capitals(_player_home, _enemy_home)
	if globe_map != null and globe_map.has_method("set_hemisphere_dim"):
		globe_map.set_hemisphere_dim(0)
	if _frame_profiler != null:
		_frame_profiler.reset_samples()
	RunLog.info(
		"World Conquest — %s  %dx%d" % [
			CFG.theater_display_name(RunState.theater_id),
			battle_data.grid_width,
			battle_data.grid_height,
		]
	)


func _await_min_load_time() -> void:
	if _load_pack_warm:
		return
	var elapsed_sec: float = float(Time.get_ticks_msec() - _load_started_msec) / 1000.0
	var wait_sec: float = CFG.WORLD_CONQUEST_MIN_LOAD_SEC - elapsed_sec
	if wait_sec > 0.0:
		await get_tree().create_timer(wait_sec).timeout


func _is_world_pack_warm(map_id: String, seed_val: int) -> bool:
	var visual_tag: String = ""
	if RunState.custom_world or CFG.normalize_theater_id(RunState.theater_id) != CFG.THEATER_EARTH:
		visual_tag = "p_lb%d_mb%d" % [
			int(round(RunState.land_bias * 100.0)),
			int(round(RunState.mountain_bias * 100.0)),
		]
	var albedo: Image = WorldPackLibScript.try_load_albedo(
		map_id, CFG.SPHERE_GRID_FREQUENCY, seed_val, visual_tag
	)
	if albedo == null or albedo.is_empty():
		return false
	if visual_tag != "":
		return true
	var cells: Dictionary = WorldPackLibScript.try_load_world_cells(map_id, CFG.SPHERE_GRID_FREQUENCY)
	if cells.is_empty():
		return false
	var land_var: Variant = cells.get("cell_land", PackedByteArray())
	return land_var is PackedByteArray and (land_var as PackedByteArray).size() > 0


func _enter_deploy_phase() -> void:
	_deploy_phase = true
	_deploy_skip_reveal = false
	_deploy_pick_remaining = CFG.DEPLOY_PICK_SEC
	_deploy_resolved = false
	_deploy_auto_picked = false
	_deploy_locked_grid = Vector2i(-1, -1)
	_deploy_hover_grid = Vector2i(-1, -1)
	_deploy_commit_grid = Vector2i(-1, -1)
	if loading_center:
		loading_center.visible = false
	if loading_progress:
		loading_progress.visible = false
	if loading_status_line:
		loading_status_line.visible = false
	if loading_dim:
		# Light vignette only — keep the globe readable for picking.
		loading_dim.color = Color(0.02, 0.03, 0.05, 0.28)
	if loading_overlay:
		loading_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if deploy_title_label:
		deploy_title_label.visible = true
	if deploy_banner:
		deploy_banner.visible = true
		deploy_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deploy_banner.add_theme_stylebox_override("panel", GameThemeLib.make_cluster_style())
	if deploy_button:
		deploy_button.mouse_filter = Control.MOUSE_FILTER_STOP
		deploy_button.disabled = true
		GameThemeLib.apply_ghost_button(deploy_button)
	if deploy_hint_label:
		deploy_hint_label.visible = true
		var region_hint: String = ""
		match RunState.start_region:
			"west":
				region_hint = "West hemisphere preferred. "
			"east":
				region_hint = "East hemisphere preferred. "
			_:
				region_hint = ""
		deploy_hint_label.text = (
			"%sRight-drag rotate · Scroll zoom · Enemy deploys furthest from you"
			% region_hint
		)
	if summary_bar:
		summary_bar.visible = false
	if build_cluster:
		build_cluster.visible = false
	if sim_cluster:
		sim_cluster.visible = false
	if globe_map != null and globe_map.has_method("set_hemisphere_dim"):
		var hmode: int = 0
		match RunState.start_region:
			"west":
				hmode = 1
			"east":
				hmode = 2
		globe_map.set_hemisphere_dim(hmode)
	_update_deploy_countdown_label()


func _exit_deploy_overlay() -> void:
	_deploy_phase = false
	if deploy_banner:
		deploy_banner.visible = false
	if deploy_title_label:
		deploy_title_label.visible = false
	if deploy_hint_label:
		deploy_hint_label.visible = false
	if loading_status_line:
		loading_status_line.visible = false
	if loading_dim:
		loading_dim.color = Color(0.02, 0.03, 0.05, 0.92)
	if summary_bar:
		summary_bar.visible = true
	if build_cluster:
		build_cluster.visible = true
	if sim_cluster:
		sim_cluster.visible = true
	_clear_placement_preview()


func _apply_deploy_spawns() -> void:
	_deploy_phase = false
	var grid: Vector2i = _deploy_commit_grid
	WorldConquestMapGeneratorLib.apply_player_spawn(battle_data, grid)
	WorldConquestMapGeneratorLib.apply_enemy_furthest_from_player(battle_data)
	_player_home = battle_data.player_home_grid
	_enemy_home = battle_data.enemy_home_grid
	if _deploy_auto_picked:
		_show_deploy_status("Capital auto-deployed")
	_refresh_markers()
	if deploy_banner:
		deploy_banner.visible = false
	if deploy_title_label:
		deploy_title_label.visible = false
	if deploy_hint_label:
		deploy_hint_label.visible = false
	if loading_center:
		loading_center.visible = false
	if loading_progress:
		loading_progress.visible = false
	if loading_status_line:
		loading_status_line.visible = true
	if loading_dim:
		loading_dim.color = Color(0.02, 0.03, 0.05, 0.28)
	_set_load_progress(0.62, "Enemy deploying…")
	await get_tree().process_frame
	var reveal_sec: float = 0.0 if _deploy_skip_reveal else CFG.DEPLOY_ENEMY_REVEAL_SEC
	if reveal_sec > 0.0:
		if globe_map != null and globe_map.has_method("ease_look_at_grid"):
			globe_map.ease_look_at_grid(_enemy_home, reveal_sec)
		elif globe_map != null and globe_map.has_method("look_at_grid"):
			globe_map.look_at_grid(_enemy_home)
		await get_tree().create_timer(reveal_sec).timeout


func _should_skip_deploy_pick() -> bool:
	return (
		RunState.skip_deploy_pick
		or RunState.is_ai_vs_ai()
		or OS.has_feature("eoy_qa")
	)


func _skip_deploy_pick_fast() -> void:
	var grid: Vector2i = WorldConquestMapGeneratorLib.pick_random_land_spawn(
		battle_data, _deploy_run_seed, RunState.start_region
	)
	if grid.x < 0:
		push_error("WorldConquestScreen: skip_deploy_pick but map has no land cells")
		return
	_deploy_commit_grid = grid
	_deploy_resolved = true
	_deploy_phase = false
	_deploy_auto_picked = false
	_deploy_skip_reveal = true
	_deploy_pick_remaining = 0.0


func _request_deploy_commit(from_timeout: bool = false) -> void:
	if _deploy_resolved or not _deploy_phase:
		return
	var grid: Vector2i
	if _deploy_locked_grid.x >= 0:
		grid = _deploy_locked_grid
	elif from_timeout:
		grid = _deploy_pick_timeout_grid()
		if grid.x < 0:
			grid = WorldConquestMapGeneratorLib.pick_random_land_spawn(
				battle_data, _deploy_run_seed, RunState.start_region
			)
		_deploy_auto_picked = true
	else:
		_show_deploy_status("Click land to lock a capital first.")
		return
	if grid.x < 0:
		push_error("WorldConquestScreen: deploy commit failed — no valid land")
		return
	_deploy_commit_grid = grid
	_deploy_resolved = true
	_deploy_phase = false


func _deploy_pick_timeout_grid() -> Vector2i:
	if _is_valid_deploy_land(_deploy_hover_grid):
		return _deploy_hover_grid
	return Vector2i(-1, -1)


func _is_valid_deploy_land(grid: Vector2i) -> bool:
	if not _is_on_map_grid(grid.x, grid.y):
		return false
	if battle_data.sphere_mode:
		return battle_data.is_land_cell_id(grid.x)
	return battle_data.is_land_cell(grid.x, grid.y)


func _update_deploy_countdown_label() -> void:
	if deploy_countdown_label == null:
		return
	var sec_left: int = int(ceil(_deploy_pick_remaining))
	var mins: int = sec_left / 60
	var secs: int = sec_left % 60
	deploy_countdown_label.text = "%d:%02d" % [mins, secs]
	if deploy_timer_bar:
		var max_sec: float = maxf(0.001, CFG.DEPLOY_PICK_SEC)
		deploy_timer_bar.value = clampf(_deploy_pick_remaining / max_sec, 0.0, 1.0) * 100.0
	if deploy_button:
		deploy_button.disabled = _deploy_locked_grid.x < 0
		GameThemeLib.apply_ghost_button(deploy_button)
		if not deploy_button.disabled:
			deploy_button.add_theme_color_override("font_color", GameThemeLib.ACCENT)
			deploy_button.add_theme_color_override("font_hover_color", GameThemeLib.TEXT_PRIMARY)


func _show_deploy_status(msg: String) -> void:
	if deploy_hint_label:
		deploy_hint_label.text = msg


func _show_deploy_preview(grid: Vector2i) -> void:
	if globe_map == null or battle_data == null or grid.x < 0:
		_clear_placement_preview()
		return
	var landing_idx: int = battle_data.cell_index(grid.x, grid.y)
	if landing_idx < 0:
		_clear_placement_preview()
		return
	globe_map.set_placement_preview(PackedInt32Array([landing_idx]), grid, grid, true, false)


func _update_deploy_hover() -> void:
	if not _deploy_phase or _deploy_resolved:
		return
	var grid: Vector2i = _mouse_to_grid()
	if grid == _deploy_hover_grid:
		return
	_deploy_hover_grid = grid
	if _deploy_locked_grid.x >= 0:
		_show_deploy_preview(_deploy_locked_grid)
	elif _is_valid_deploy_land(grid):
		_show_deploy_preview(grid)
	else:
		_clear_placement_preview()


func _try_deploy_pick_click() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_valid_deploy_land(grid):
		_show_deploy_status("Ocean — not claimable. Click land to plant your capital.")
		return
	_deploy_locked_grid = grid
	_show_deploy_preview(grid)
	_show_deploy_status("Capital locked — press Deploy, or wait for the timer.")
	if globe_map != null and globe_map.has_method("pulse_lock_marker"):
		globe_map.pulse_lock_marker(grid)
	if deploy_button:
		deploy_button.disabled = false
		GameThemeLib.apply_ghost_button(deploy_button)
		deploy_button.add_theme_color_override("font_color", GameThemeLib.ACCENT)
		deploy_button.add_theme_color_override("font_hover_color", GameThemeLib.TEXT_PRIMARY)


func _on_deploy_gui_input(event: InputEvent) -> void:
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
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_deploy_pick_click()
			sub_viewport_container.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbit_drag and globe_map != null:
			globe_map.orbit_camera(0.0, mm.relative * CFG.DEPLOY_ORBIT_MULT)
			sub_viewport_container.accept_event()
		else:
			_update_deploy_hover()


func _process_deploy_phase(delta: float) -> void:
	if not _deploy_resolved:
		_deploy_pick_remaining = maxf(0.0, _deploy_pick_remaining - delta)
		_update_deploy_countdown_label()
		_update_deploy_hover()
		if _deploy_pick_remaining <= 0.0:
			_request_deploy_commit(true)


func _on_deploy_button_pressed() -> void:
	_request_deploy_commit(false)


func _set_load_progress(ratio: float, status: String) -> void:
	if loading_status_label != null:
		loading_status_label.text = status
	if loading_status_line != null:
		loading_status_line.text = status
	if loading_progress != null:
		loading_progress.value = clampf(ratio, 0.0, 1.0) * 100.0


func _style_loading_overlay() -> void:
	if loading_overlay == null:
		return
	var panel: PanelContainer = loading_overlay.get_node_or_null("Center/LoadPanel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", GameThemeLib.make_panel_style())
	var pal: Dictionary = WorldConquestMapGeneratorLib.globe_colors_for_map(
		WorldMapCatalogLib.resolve_map_id(RunState.world_map_id)
	)
	var ocean: Color = pal.get("ocean", Color(0.05, 0.18, 0.42))
	if loading_dim:
		loading_dim.color = Color(ocean.r * 0.35, ocean.g * 0.35, ocean.b * 0.4, 0.72)
	if deploy_timer_bar:
		deploy_timer_bar.add_theme_stylebox_override(
			"fill", _make_bar_fill_style(Color(GameThemeLib.ACCENT.r, GameThemeLib.ACCENT.g, GameThemeLib.ACCENT.b, 0.55))
		)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.09, 0.11, 0.16, 0.35)
		bg.set_corner_radius_all(6)
		deploy_timer_bar.add_theme_stylebox_override("background", bg)


func _style_end_overlay() -> void:
	if end_overlay:
		end_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sheet: PanelContainer = $EndOverlay/ScrollCenter as PanelContainer
	if sheet != null:
		var sheet_style := GameThemeLib.make_panel_style(Color(0.09, 0.11, 0.16, 0.86), GameThemeLib.BORDER, 8)
		sheet_style.corner_radius_bottom_left = 0
		sheet_style.corner_radius_bottom_right = 0
		sheet.add_theme_stylebox_override("panel", sheet_style)
		sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	if end_dash_panel != null:
		end_dash_panel.add_theme_stylebox_override("panel", GameThemeLib.make_panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		var kpi_strip: HBoxContainer = end_dash_panel.get_node_or_null("EndVBox/KPIStrip") as HBoxContainer
		if kpi_strip != null:
			var kpi_panel_style := GameThemeLib.make_panel_style(
				GameThemeLib.BG_PANEL.darkened(0.08), GameThemeLib.BORDER, 6
			)
			for child in kpi_strip.get_children():
				if child is PanelContainer:
					child.add_theme_stylebox_override("panel", kpi_panel_style)
		var vbox: VBoxContainer = end_dash_panel.get_node_or_null("EndVBox") as VBoxContainer
		var buttons: HBoxContainer = end_dash_panel.get_node_or_null("EndVBox/EndButtons") as HBoxContainer
		if vbox != null and buttons != null:
			vbox.move_child(buttons, 2)
			if end_details_button:
				vbox.move_child(end_details_button, 3)
	if end_scroll != null:
		GameThemeLib.configure_scroll(end_scroll)
	GameThemeLib.apply_primary_button(end_play_again_button)
	GameThemeLib.apply_ghost_button(end_same_map_button)
	GameThemeLib.apply_ghost_button(end_menu_button)
	GameThemeLib.apply_ghost_button(end_details_button)
	_end_style_land_bars()


func _end_style_land_bars() -> void:
	if end_you_land_bar != null:
		end_you_land_bar.add_theme_stylebox_override(
			"fill", _make_bar_fill_style(GameThemeLib.ACCENT)
		)
	if end_enemy_land_bar != null:
		end_enemy_land_bar.add_theme_stylebox_override(
			"fill", _make_bar_fill_style(GameThemeLib.ACCENT_DANGER)
		)


func _make_bar_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style


func _reset_run_metrics() -> void:
	_run_structures_placed = 0
	_run_soldiers_spawned = 0
	_run_bombers_spawned = 0
	_run_peak_land_pct = 0
	_run_peak_enemy_land_pct = 0
	_run_outposts_placed = 0
	_run_barracks_placed = 0
	_run_hangars_placed = 0
	_run_enemy_structures_placed = 0
	_run_player_structures_placed = 0
	_run_supply_spent = 0.0
	_run_peak_soldiers = 0
	_run_peak_bombers = 0
	_run_first_outpost_sec = -1.0
	_conquest_nudge_shown = false


func _track_player_structure_metrics(kind: String) -> void:
	if kind == OutpostBuildLib.KIND_SPAWNER:
		_run_outposts_placed += 1
		if _run_first_outpost_sec < 0.0:
			_run_first_outpost_sec = _sim_time
	elif kind == OutpostBuildLib.KIND_BARRACKS:
		_run_barracks_placed += 1
	elif kind == OutpostBuildLib.KIND_HANGAR:
		_run_hangars_placed += 1


func _setup_globe_terrain_early(map_id: String) -> void:
	if globe_map != null:
		globe_map.setup(battle_data, map_id)
		var light := DirectionalLight3D.new()
		light.name = "Sun"
		light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
		light.light_energy = 1.45
		light.light_color = Color(1.0, 0.97, 0.92)
		light.shadow_enabled = false
		globe_map.add_child(light)
		var fill := DirectionalLight3D.new()
		fill.name = "Fill"
		fill.rotation_degrees = Vector3(25.0, 140.0, 0.0)
		fill.light_energy = 0.35
		fill.light_color = Color(0.55, 0.65, 0.9)
		fill.shadow_enabled = false
		globe_map.add_child(fill)
		var env_node := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.015, 0.02, 0.05)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.28, 0.34, 0.48)
		e.ambient_light_energy = 0.55
		env_node.environment = e
		globe_map.add_child(env_node)
	_refresh_resource_deposits()
	_on_play_area_resized(true)


func _setup_sim_after_spawns(map_id: String) -> void:
	OutpostBuildLib.prepare_land_components(battle_data)
	_setup_territory_backend()
	if territory_sim != null:
		_sync_bridge_corridors_to_sim(true, true)
	_refresh_markers()
	_resource_links_dirty = true
	_init_builder_agents()
	_assert_world_dataset_after_setup()
	_on_play_area_resized(true)


func _setup_world_visuals(map_id: String) -> void:
	_setup_globe_terrain_early(map_id)
	_setup_sim_after_spawns(map_id)


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
	if _paint_stroke_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_commit_paint_stroke()
	if _deploy_phase:
		_process_deploy_phase(delta)
		return
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
	var prior_ms: float = 0.0
	if _frame_profiler != null:
		prior_ms = _frame_profiler.prior_frame_ms()
	var sim_steps: int = 0
	var sim_max_steps: int = CFG.SIM_MAX_STEPS_PER_FRAME
	# End-game FPS ladder: catch-up → sticky soft-cap → skip-sim (alternate) → defer AI.
	# Soft-cap BEFORE advance_dt under load so Rust gradient binds the runtime cap this frame.
	# Sticky hysteresis: once lowered, do not raise until N consecutive healthy frames —
	# otherwise a post-skip "healthy" prior_ms snaps to DEFAULT and catch-up (4 steps) collapses FPS.
	var soft_cap_target: int = _soft_cap_target_for_prior_ms(prior_ms)
	_apply_active_set_soft_cap(soft_cap_target)
	var soft_cap_sticky: bool = (
		_applied_soft_cap > 0 and _applied_soft_cap < CFG.SOFT_CAP_DEFAULT
	)
	if prior_ms > CFG.FRAME_BUDGET_MS or soft_cap_sticky:
		sim_max_steps = 1
	if prior_ms > CFG.FRAME_MS_SKIP_SIM:
		if _sim_skip_resume_next:
			# Last frame skipped — force one advance so the game does not freeze.
			_sim_skip_resume_next = false
			sim_max_steps = 1
		else:
			_sim_skip_resume_next = true
			sim_max_steps = 0
	else:
		_sim_skip_resume_next = false

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

	var skip_heavy: bool = sim_max_steps == 0
	if not _paused and not territory_sim.finished:
		_supply += float(_friendly_tiles) * CFG.INCOME_PER_TILE_PER_SEC * delta
		_enemy_supply += float(_hostile_tiles) * CFG.INCOME_PER_TILE_PER_SEC * delta
		# Always feed advance_dt so _dt_accum keeps wall-clock time (max_steps=0 when skipping).
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
		# R1: one-shot leftover corridor clear (no live bridge maintain).
		if not _bridges_repaired:
			_maintain_bridge_corridors()
		var res_t: int = 0
		if _frame_profiler != null:
			res_t = _frame_profiler.begin_phase("resources")
		_tick_resources(delta * _speed_mult)
		if _frame_profiler != null:
			_frame_profiler.end_phase("resources", res_t)
		# Defer AI when prior frame was heavy and this frame ran a sim step, or when skipping sim.
		var defer_ai: bool = skip_heavy or (prior_ms > CFG.FRAME_MS_DEFER_AI and sim_steps > 0)
		var ai_dt: float = delta * _speed_mult
		if defer_ai:
			_ai_deferred_dt += ai_dt
		else:
			ai_dt += _ai_deferred_dt
			_ai_deferred_dt = 0.0
			var enemy_ai_t: int = 0
			if _frame_profiler != null:
				enemy_ai_t = _frame_profiler.begin_phase("enemy_ai")
			_tick_enemy_strategy(ai_dt)
			if RunState.is_ai_vs_ai():
				_tick_player_strategy(ai_dt)
			if _frame_profiler != null:
				_frame_profiler.end_phase("enemy_ai", enemy_ai_t)
	# Construction / world session continue while pressure sim is paused (build queues still advance).
	# Under skip-sim overload, only keep essential income/HUD — defer construction drain + presentation.
	if not skip_heavy and not territory_sim.finished:
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

	# F2: do not dirty unit visuals every sim step — keep 4 Hz refresh + spawn/death dirty flags.

	# After a fat sim or skip-sim frame, do not stack markers/gpu/overlay drain.
	var fat_sim_frame: bool = skip_heavy or (sim_steps > 0 and prior_ms > CFG.FRAME_MS_DEFER_AI)
	var bridge_flush_t: int = 0
	if _frame_profiler != null:
		bridge_flush_t = _frame_profiler.begin_phase("bridge_flush")
	if not fat_sim_frame:
		_drain_outpost_construction_queue()
	if _frame_profiler != null:
		_frame_profiler.end_phase("bridge_flush", bridge_flush_t)
	if not fat_sim_frame and prior_ms <= CFG.FRAME_MS_TIGHTEN_SOFT_CAP:
		_tick_overlay_owner_reconcile(delta)

	if not skip_heavy and not _paused and territory_sim != null and not territory_sim.finished:
		if not fat_sim_frame and prior_ms <= CFG.FRAME_MS_TIGHTEN_SOFT_CAP:
			if CFG.OVERLAY_DEPTH_TINT and _live_rust_presentation():
				_depth_overlay_clock += delta
				if _depth_overlay_clock >= 1.0 / CFG.OVERLAY_DEPTH_UPDATES_PER_SEC:
					_depth_overlay_clock = 0.0
					_update_tile_overlay(false)
			elif not CFG.OVERLAY_OWNERS_ONLY:
				_overlay_clock += delta
				if _overlay_clock >= 1.0 / CFG.OVERLAY_UPDATES_PER_SEC:
					_overlay_clock = 0.0
					_update_tile_overlay(false)
	# R1: logistics / builder road growth removed — do not tick builder_step or road paint.
	if not skip_heavy:
		_update_outpost_visuals(delta)
		_update_resource_visuals(delta)
		# Single live presentation pull: owners + optional structures/units (after sim).
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
	if not skip_heavy and _is_build_mode_active():
		_build_hint_clock += delta
		_route_hover_clock += delta
		if _build_hint_clock >= 0.12:
			_build_hint_clock = 0.0
			_update_build_hover_hint()
	_hud_clock += delta
	if _hud_clock >= 0.12:
		_hud_clock = 0.0
		_update_hud()
	if outpost_pin_card != null and outpost_pin_card.visible:
		_position_outpost_pin_card()
	if not skip_heavy:
		_tick_clarity_beats(delta)
		if _tile_inspect_active:
			_tile_probe_clock += delta
			if _tile_probe_clock >= 0.1:
				_tile_probe_clock = 0.0
				_update_tile_probe()
		_poll_route_planner()
		_maybe_refresh_route_backend(delta)
	_end_process_profiler_frame()


## Sticky soft-cap ladder from prior-frame cost. May tighten immediately; raises only after
## SOFT_CAP_HEALTHY_FRAMES_TO_RAISE consecutive frames with prior_ms ≤ FRAME_BUDGET_MS.
func _soft_cap_target_for_prior_ms(prior_ms: float) -> int:
	var pressure_cap: int = CFG.SOFT_CAP_DEFAULT
	if prior_ms > CFG.FRAME_MS_SKIP_SIM:
		pressure_cap = CFG.SOFT_CAP_CRITICAL
	elif (
		prior_ms > CFG.FRAME_MS_TIGHTEN_SOFT_CAP
		or prior_ms > CFG.FRAME_MS_SOFT_CAP_PREEMPT
	):
		pressure_cap = CFG.SOFT_CAP_STRESS

	if pressure_cap < CFG.SOFT_CAP_DEFAULT:
		_soft_cap_healthy_streak = 0
		# Tighten further under more pressure; never raise from CRITICAL→STRESS without health.
		if _applied_soft_cap < 0 or _applied_soft_cap >= CFG.SOFT_CAP_DEFAULT:
			return pressure_cap
		return mini(_applied_soft_cap, pressure_cap)

	# Healthy frame (prior_ms at or under tighten band — raise only after budget-healthy streak).
	if prior_ms > CFG.FRAME_BUDGET_MS:
		# Mild overload: keep sticky if lowered; do not count toward raise streak.
		_soft_cap_healthy_streak = 0
		if _applied_soft_cap > 0 and _applied_soft_cap < CFG.SOFT_CAP_DEFAULT:
			return _applied_soft_cap
		return CFG.SOFT_CAP_DEFAULT

	if _applied_soft_cap > 0 and _applied_soft_cap < CFG.SOFT_CAP_DEFAULT:
		_soft_cap_healthy_streak += 1
		if _soft_cap_healthy_streak >= CFG.SOFT_CAP_HEALTHY_FRAMES_TO_RAISE:
			_soft_cap_healthy_streak = 0
			return CFG.SOFT_CAP_DEFAULT
		return _applied_soft_cap

	_soft_cap_healthy_streak = 0
	return CFG.SOFT_CAP_DEFAULT


func _apply_active_set_soft_cap(cap: int) -> void:
	if territory_sim == null or not territory_sim.use_rust_for_live():
		return
	if _applied_soft_cap == cap:
		return
	territory_sim.set_active_set_soft_cap(cap)
	# Confirm Rust accepted the cap (ready path); retry next frame if not applied yet.
	var applied: int = territory_sim.get_active_set_soft_cap()
	if applied != cap:
		return
	var prev: int = _applied_soft_cap
	_applied_soft_cap = cap
	# Log sticky applied-cap changes only (hysteresis stops 5k↔24k thrash spam).
	if prev == cap:
		return
	var now_msec: int = Time.get_ticks_msec()
	# Safety rate-limit: if somehow thrashing, keep at most one line per interval.
	if prev > 0 and (now_msec - _soft_cap_log_at_msec) < CFG.SOFT_CAP_LOG_INTERVAL_MS:
		return
	_soft_cap_log_at_msec = now_msec
	RunLog.info("active_set_soft_cap=%d (prior overload ladder)" % cap)


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
	if _deploy_phase:
		_on_deploy_gui_input(event)
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
			if mb.pressed and _tile_inspect_active:
				_on_inspect_toggled(false)
				if inspect_button:
					inspect_button.set_block_signals(true)
					inspect_button.button_pressed = false
					inspect_button.set_block_signals(false)
			_orbit_drag = mb.pressed
			if mb.pressed:
				_orbit_seen = true
				_refresh_idle_hint()
			sub_viewport_container.accept_event()
		elif (
			mb.button_index == MOUSE_BUTTON_LEFT
			and not RunState.is_ai_vs_ai()
		):
			if _paint_stroke_active and not mb.pressed:
				_commit_paint_stroke()
			elif mb.pressed and _paint_armed:
				_try_begin_paint_stroke()
			elif mb.pressed and _is_build_mode_active():
				_try_place_structure()
			elif mb.pressed:
				_try_select_structure_at_cursor()
			sub_viewport_container.accept_event()
	elif event is InputEventMouseMotion:
		if _paint_stroke_active and globe_map != null:
			_stamp_paint_at_cursor()
			sub_viewport_container.accept_event()
		elif _orbit_drag and globe_map != null:
			var mm := event as InputEventMouseMotion
			globe_map.orbit_camera(0.0, mm.relative)
			_orbit_seen = true
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
	_run_supply_spent += cost.x
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


## Design lock R1: land bridges removed. Single choke-point so player + debug + AI all reject.
func _corridor_kind_removed(kind: String) -> bool:
	return kind == OutpostBuildLib.KIND_CORRIDOR_LINK


func _build_mode_noun() -> String:
	if _build_mode == OutpostBuildLib.KIND_BARRACKS:
		return "barracks"
	if _build_mode == OutpostBuildLib.KIND_HANGAR:
		return "hangar"
	return "outpost"


func _try_place_structure() -> void:
	if _corridor_kind_removed(_build_mode):
		_set_build_hint("Land bridges removed.")
		_apply_build_mode("")
		return
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		_set_build_hint("Click land on the globe to place a %s." % _build_mode_noun())
		return
	if not EconomyLib.can_afford_build(_supply, _friendly_resources, _build_mode):
		_set_build_hint(_placement_cost_hint(_build_mode))
		return
	var reject: String = _placement_hover_reject(grid.x, grid.y)
	if reject != "":
		_set_build_hint(reject)
		return
	# R1: structures land instantly on the clicked cell — no supply route, no road, no planner.
	call_deferred("_finish_place_structure", grid)


func _finish_place_structure(grid: Vector2i) -> void:
	if battle_data == null or _build_mode == "":
		return
	if _corridor_kind_removed(_build_mode):
		_set_build_hint("Land bridges removed.")
		_apply_build_mode("")
		return
	var placement: Dictionary = _resolve_placement(grid, true, _build_mode)
	var reject: String = str(placement.get("reject", ""))
	if reject != "":
		_set_build_hint(reject)
		return
	if placement.get("path_packed", PackedInt32Array()).is_empty():
		_set_build_hint("Could not place outpost here.")
		return
	if not EconomyLib.can_afford_build(_supply, _friendly_resources, _build_mode):
		_set_build_hint(_placement_cost_hint(_build_mode))
		return
	if not _pay_placement_cost(_build_mode):
		_set_build_hint(_placement_cost_hint(_build_mode))
		return
	var placed_sid: int = _commit_placed_structure(
		placement, BattleTileControlLib.OWNER_FRIENDLY, _build_mode, grid
	)
	if placed_sid < 0:
		_set_build_hint("Could not place outpost here.")
		return
	_run_structures_placed += 1
	_track_player_structure_metrics(_build_mode)
	if _build_mode == OutpostBuildLib.KIND_SPAWNER:
		_clarity_first_outpost_placed = true
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
	if _corridor_kind_removed(kind):
		# R1: land bridges removed — debug/AI callers must not resurrect them.
		return -1
	var placement: Dictionary = _resolve_placement_for_team(
		grid, allow_astar, kind, team, allow_standalone
	)
	if str(placement.get("reject", "")) != "":
		return -1
	if placement.get("path_packed", PackedInt32Array()).is_empty():
		return -1
	return _commit_placed_structure(placement, team, kind, grid)


## R1 instant placement: structures activate on their landing cell. No road path is planned,
## painted, or grown — `path_keys` is just the landing cell so downstream length math stays sane.
func _commit_placed_structure(
	placement: Dictionary, team: int, kind: String, click_grid: Vector2i
) -> int:
	if battle_data == null:
		return -1
	if _corridor_kind_removed(kind):
		return -1
	var landing: Vector2i = placement.get("landing", Vector2i(-1, -1))
	if landing.x < 0:
		return -1
	var landing_idx: int = battle_data.cell_index(landing.x, landing.y)
	if landing_idx < 0:
		return -1
	var path_packed := PackedInt32Array([landing_idx])
	var st: Dictionary = {
		"id": _next_structure_id,
		"team": team,
		"gx": landing.x,
		"gy": landing.y,
		"kind": kind,
		"state": OutpostBuildLib.STATE_ACTIVE,
		"source_gx": landing.x,
		"source_gy": landing.y,
		"path_keys": path_packed,
		"path_len": 1,
		"path_built": 1.0,
		"road_class": OutpostBuildLib.classify_road_class(kind, 1),
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
	# Every kind bumps the version: R1 haul hubs are "HQ + any ACTIVE structure", so the resource
	# link cache must see barracks/hangar placements too.
	_structure_sources_version += 1
	if kind == OutpostBuildLib.KIND_SPAWNER:
		# Instantly ACTIVE: let next frame's deferred sync light up the spawner aura.
		_spawners_pending_sync = true
	if team == BattleTileControlLib.OWNER_FRIENDLY and kind == OutpostBuildLib.KIND_SPAWNER:
		_clarity_first_outpost_placed = true
	_road_network_version += 1
	_invalidate_hover_path_cache()
	_clear_placement_preview()
	_outpost_marker_dirty = true
	_resource_links_dirty = true
	# Bridge list is always empty under R1; this call still refreshes claimable + owner visual.
	_sync_bridge_corridors_to_sim(false, true, true)
	_refresh_outpost_visuals(false, true, [], [placed_sid])
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


## R1: no supply routing. A successful precheck is the whole gate — the "path" is the landing cell.
## `allow_astar` / `allow_standalone` are kept for call-site compatibility and are now unused.
func _resolve_placement_for_team(
	click: Vector2i,
	_allow_astar: bool,
	build_kind: String,
	team: int,
	_allow_standalone: bool = true,
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
	if _corridor_kind_removed(build_kind):
		empty["reject"] = "Land bridges removed."
		return empty
	var precheck: Dictionary = _placement_precheck_for_team(click, build_kind, team)
	var pre_reject: String = str(precheck.get("reject", ""))
	if pre_reject != "":
		empty["reject"] = pre_reject
		return empty
	var landing: Vector2i = precheck.get("landing", Vector2i(-1, -1))
	if landing.x < 0:
		empty["reject"] = "Invalid landing tile."
		return empty
	var landing_idx: int = battle_data.cell_index(landing.x, landing.y)
	if landing_idx < 0:
		empty["reject"] = "Invalid landing tile."
		return empty
	empty["landing"] = landing
	empty["path_packed"] = PackedInt32Array([landing_idx])
	empty["source"] = landing
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
	if _corridor_kind_removed(build_kind):
		result["reject"] = "Land bridges removed."
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
	# R1: every remaining kind lands exactly on the clicked cell (no coastal snap).
	var landing: Vector2i = click
	result["landing"] = landing
	for st: Dictionary in structures:
		var min_d: int = _placement_min_spacing_cells(build_kind)
		if _structure_too_close(landing, int(st.get("gx", 0)), int(st.get("gy", 0)), min_d):
			result["reject"] = "Too close to another structure."
			return result
	return result


func _placement_territory_reject(gx: int, gy: int, build_kind: String = "") -> String:
	return _placement_territory_reject_for_team(
		gx, gy, BattleTileControlLib.OWNER_FRIENDLY, build_kind
	)


func _placement_territory_reject_for_team(
	gx: int, gy: int, team: int, _build_kind: String = ""
) -> String:
	if battle_data == null or territory_sim == null:
		return ""
	var idx: int = battle_data.cell_index(gx, gy)
	if idx < 0 or idx >= territory_sim.grid_cell_count():
		return ""
	# R1: structures only land on claimable tiles. Ocean landmasses open via ferry beachhead,
	# not by planting an outpost on unclaimable dirt (and not via land bridges).
	if not territory_sim.claimable_at_index(idx):
		return "Need claimable land (ferry beachhead for islands)."
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
		# Live SCD1 already paints ownership every frame — do not full-refresh owners
		# here (that rebuilds the border mask and tanks FPS). Depth tint only.
		var live_pres: bool = _live_rust_presentation()
		if force or not live_pres:
			var owners: PackedByteArray = _ownership_overlay_source()
			if not owners.is_empty():
				if (
					territory_sim.rust_live_ready
					and territory_sim.rust_field != null
					and territory_sim.rust_field.has_method("get_owner_display_r8")
				):
					var bytes: PackedByteArray = territory_sim.rust_field.get_owner_display_r8()
					if bytes.size() > 0:
						globe_map.apply_ownership_display_bytes(bytes)
					else:
						_warn_slow_owner_overlay_path("update_tile_overlay")
						globe_map.apply_ownership_overlay(owners)
				else:
					_warn_slow_owner_overlay_path("update_tile_overlay_cpu")
					globe_map.apply_ownership_overlay(owners)
		if CFG.OVERLAY_DEPTH_TINT and territory_sim.rust_live_ready and territory_sim.rust_field != null:
			if territory_sim.rust_field.has_method("get_pressure_depth_r8"):
				var depth_bytes: PackedByteArray = territory_sim.rust_field.get_pressure_depth_r8(
					CFG.PRESSURE_VIS_REF
				)
				if depth_bytes.size() > 0:
					globe_map.apply_ownership_depth_bytes(depth_bytes)
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
	var total: int = battle_data.gameplay_tile_count()
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
	# Skip reconcile entirely when prior frame was in soft-cap stress range.
	if _frame_profiler != null and _frame_profiler.prior_frame_ms() > CFG.FRAME_MS_TIGHTEN_SOFT_CAP:
		return
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
		var cached: int = (
			globe_map.get_owner_cache_byte_for_cell(idx)
			if battle_data.sphere_mode
			else globe_map.get_owner_cache_byte(idx)
		)
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
	# R1: roads domain retired from live paint (empty stub in Rust; do not pull).
	_apply_scd1_wallet(_scd1_pull.pull_domain(sim, "wallet", ""))
	_soldier_visual_clock += delta
	_bomber_visual_clock += delta
	# Under frame pressure, halve agent/bomber pull rates to cut SCD1 thrash.
	var prior_ms: float = 0.0
	if _frame_profiler != null:
		prior_ms = _frame_profiler.prior_frame_ms()
	var soldier_hz: float = CFG.SOLDIER_VISUAL_UPDATES_PER_SEC
	var bomber_hz: float = CFG.BOMBER_VISUAL_UPDATES_PER_SEC
	if prior_ms > CFG.FRAME_MS_SOFT_CAP_PREEMPT:
		soldier_hz *= 0.5
		bomber_hz *= 0.5
	var soldier_due: bool = (
		territory_sim.agents_ready()
		and (
			_soldier_visual_dirty
			or _soldier_visual_clock >= 1.0 / soldier_hz
		)
	)
	var bomber_due: bool = (
		territory_sim.bombers_ready()
		and (
			_bomber_visual_dirty
			or _bomber_visual_clock >= 1.0 / bomber_hz
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
	var display_idxs: PackedInt32Array = batch.get("display_indices", PackedInt32Array())
	var display_r8: PackedByteArray = batch.get("display_r8", PackedByteArray())
	var has_display_r8: bool = (
		not display_idxs.is_empty()
		and display_r8.size() == display_idxs.size()
	)
	# O1: full seed / huge batches — one-shot R8 apply (avoid 48/frame drip on ~64k cells).
	var one_shot: bool = (
		bool(batch.get("full", false))
		or idxs.size() >= CFG.OVERLAY_FULL_SEED_QUEUE_THRESHOLD
	)
	if one_shot and globe_map != null and territory_sim != null and territory_sim.rust_field != null:
		if _outpost_construction_queue != null:
			_outpost_construction_queue.clear_overlay_queue()
		var display_bytes: PackedByteArray = territory_sim.rust_field.get_owner_display_r8()
		if not display_bytes.is_empty():
			globe_map.apply_ownership_display_bytes(display_bytes)
			if _outpost_construction_queue != null:
				_outpost_construction_queue.request_gpu_upload()
			if globe_map.flush_pending_owner_gpu_upload(true):
				if _outpost_construction_queue != null:
					_outpost_construction_queue.mark_gpu_upload_committed()
			_maybe_log_perf_action("gpu_upload", {"cells": idxs.size(), "one_shot": 1}, 2.0)
		elif _outpost_construction_queue != null:
			if has_display_r8:
				_outpost_construction_queue.enqueue_overlay_display_delta(display_idxs, display_r8)
			else:
				_outpost_construction_queue.enqueue_overlay_delta(idxs, owners)
			_outpost_construction_queue.request_gpu_upload()
			_maybe_log_perf_action("gpu_upload", {"cells": idxs.size()}, 2.0)
	elif _outpost_construction_queue != null:
		if has_display_r8:
			_outpost_construction_queue.enqueue_overlay_display_delta(display_idxs, display_r8)
		else:
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
		# Full seed also replaces corridor ribbons from domain pack when present (B4).
		if batch.has("bridge_corridors") and battle_data != null:
			var corridors: Array = batch.get("bridge_corridors", [])
			if corridors is Array:
				battle_data.bridge_corridors.clear()
				for c in corridors:
					if c is Dictionary:
						battle_data.bridge_corridors.append((c as Dictionary).duplicate())
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
		# Tombstones: drop deleted sids from render cache (B1).
		var removed: PackedInt32Array = batch.get("removed_ids", PackedInt32Array())
		if removed.size() > 0:
			var drop: Dictionary = {}
			for i in range(removed.size()):
				drop[int(removed[i])] = true
				dirty_sids.append(int(removed[i]))
			var kept: Array = []
			for st in battle_data.placed_structures:
				if st is Dictionary and not drop.has(int(st.get("id", -1))):
					kept.append(st)
			battle_data.placed_structures = kept
	# Budget: only refresh markers for changed sids (full empty list rebuild only on full seed).
	if globe_map != null and dirty_sids.size() > 0:
		if bool(batch.get("full", false)):
			_refresh_markers([])
		else:
			_refresh_markers(dirty_sids)


## R1: SCD1 roads domain is no longer pulled. Kept as a no-op so any stale caller is harmless.
func _apply_scd1_roads(_batch: Dictionary) -> void:
	return


func _stamp_planned_road_paint(path: PackedInt32Array, road_class: int) -> void:
	if not CFG.ROAD_CELL_PAINT or path.is_empty() or battle_data == null:
		return
	var bridge_path: bool = road_class == OutpostBuildLib.ROAD_CLASS_BRIDGE
	var path_set: Dictionary = {}
	for pk in path:
		path_set[int(pk)] = true
	# Cosmetic 3-wide: every path cell is white; exactly two side cells are black.
	for i in range(path.size()):
		var key: int = int(path[i])
		if key < 0:
			continue
		var prev: int = int(_road_class_by_cell.get(key, OutpostBuildLib.ROAD_CLASS_NONE))
		var keep: int = _prefer_road_class(prev, road_class)
		_road_class_by_cell[key] = keep
		var shoulders: PackedInt32Array = OutpostBuildLib.road_shoulder_cells(
			battle_data, path, i, bridge_path
		)
		_road_shoulders_by_center[key] = shoulders
		var center_paint: int = keep if i == 0 else OutpostBuildLib.ROAD_CLASS_PLANNED
		_enqueue_network_road_paint(key, center_paint)
		var shoulder_paint: int = (
			OutpostBuildLib.ROAD_CLASS_SHOULDER
			if i == 0
			else OutpostBuildLib.ROAD_CLASS_PLANNED_SHOULDER
		)
		for s in shoulders:
			var sk: int = int(s)
			if sk < 0 or path_set.has(sk):
				continue
			var existing: int = int(_road_class_by_cell.get(sk, OutpostBuildLib.ROAD_CLASS_NONE))
			if _road_class_rank(existing) >= _road_class_rank(OutpostBuildLib.ROAD_CLASS_SPUR):
				continue
			_road_class_by_cell[sk] = OutpostBuildLib.ROAD_CLASS_SHOULDER
			_enqueue_network_road_paint(sk, shoulder_paint)


func _paint_road_center_and_shoulders(center: int, center_class: int) -> void:
	_enqueue_network_road_paint(center, center_class)
	var shoulders: Variant = _road_shoulders_by_center.get(center, PackedInt32Array())
	if shoulders is PackedInt32Array:
		for s in shoulders:
			var sk: int = int(s)
			if sk < 0:
				continue
			var existing: int = int(_road_class_by_cell.get(sk, OutpostBuildLib.ROAD_CLASS_NONE))
			if _road_class_rank(existing) >= _road_class_rank(OutpostBuildLib.ROAD_CLASS_SPUR):
				continue
			_road_class_by_cell[sk] = OutpostBuildLib.ROAD_CLASS_SHOULDER
			_enqueue_network_road_paint(sk, OutpostBuildLib.ROAD_CLASS_SHOULDER)


func _prefer_road_class(a: int, b: int) -> int:
	# bridge > arterial > spur > shoulder > planned > planned_shoulder > none
	return a if _road_class_rank(a) >= _road_class_rank(b) else b


func _road_class_rank(cls: int) -> int:
	match cls:
		OutpostBuildLib.ROAD_CLASS_BRIDGE:
			return 6
		OutpostBuildLib.ROAD_CLASS_ARTERIAL:
			return 5
		OutpostBuildLib.ROAD_CLASS_SPUR:
			return 4
		OutpostBuildLib.ROAD_CLASS_SHOULDER:
			return 3
		OutpostBuildLib.ROAD_CLASS_PLANNED:
			return 2
		OutpostBuildLib.ROAD_CLASS_PLANNED_SHOULDER:
			return 1
		_:
			return 0


func _enqueue_network_road_paint(cell: int, road_class: int) -> void:
	if cell < 0:
		return
	_network_road_pending.append(cell)
	_network_road_pending_class.append(road_class)


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
	_last_agent_teams = teams
	_last_agent_gx = gx
	_last_agent_gy = gy
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
	_last_bomber_teams = teams
	_last_bomber_gx = gx
	_last_bomber_gy = gy
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
	# Flat team baseline (Au/Ve/Em) so ferry units are possible without local deposits.
	var base: float = CFG.TEAM_BASELINE_MINERAL_PER_SEC * maxf(dt, 0.0)
	var friendly_delta: Array = [0.0, 0.0, 0.0]
	var hostile_delta: Array = [0.0, 0.0, 0.0]
	for i in CFG.RESOURCE_TYPE_COUNT:
		friendly_delta[i] = float(info.friendly[i]) + base
		hostile_delta[i] = float(info.hostile[i]) + base
	if _resource_wallet_active() and territory_sim != null:
		territory_sim.apply_resource_tick_delta(friendly_delta, hostile_delta)
		_pull_resource_wallet_from_rust()
	else:
		for i in CFG.RESOURCE_TYPE_COUNT:
			_friendly_resources[i] += float(friendly_delta[i])
			_hostile_resources[i] += float(hostile_delta[i])
	if bool(info.get("sites_dirty", info.get("links_dirty", false))):
		_resource_links_dirty = true
	_last_resource_shockwaves = info.get("shockwaves", info.get("pulses", []))
	var pulse_n: int = _last_resource_shockwaves.size()
	_maybe_log_perf_action(
		"resources",
		{"shockwaves": pulse_n, "sites_dirty": int(_resource_links_dirty)},
		2.0,
	)


func _update_resource_visuals(delta: float) -> void:
	if globe_map == null:
		return
	# Always sync miners so ownership changes and orbit visibility stay correct.
	globe_map.sync_resource_miners(ResourceLib.site_states())
	_resource_links_dirty = false
	globe_map.update_resource_shockwaves(_last_resource_shockwaves, delta)
	_last_resource_shockwaves.clear()



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
	# Under load, refresh connecting markers at half rate.
	var marker_period: float = 0.5
	if _frame_profiler != null and _frame_profiler.prior_frame_ms() > CFG.FRAME_MS_SOFT_CAP_PREEMPT:
		marker_period = 1.0
	if _outpost_marker_clock >= marker_period:
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
	# Option B: built ∪ planned so simultaneous connects can spur onto reserved corridors.
	var network_route: PackedByteArray = PackedByteArray()
	if _builder_authority_active() and territory_sim != null:
		network_route = territory_sim.get_network_route_mask(team)
	route_planner.update_infra_for_team(
		battle_data, _placement_structures(), team, network_route
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


## R1: async route placement is retired — placement no longer waits on a supply route.
## Kept as a safety net in case a stale planner request lands while a build mode is active.
func _finish_place_from_route(
	_res: Dictionary, grid: Vector2i, _landing: Vector2i
) -> void:
	if battle_data == null or _build_mode == "":
		return
	_finish_place_structure(grid)


## R1: no roads to preview — hover draws the landing marker directly (_show_landing_preview).
func _apply_hover_route_preview(_res: Dictionary) -> void:
	pass


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


func _gameplay_grid_w() -> int:
	if battle_data != null and battle_data.sphere_mode:
		return battle_data.cell_count
	return battle_data.grid_width if battle_data else 0


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
		_run_bombers_spawned += result.get("spawned_hangar_sids", PackedInt32Array()).size()
		_bump_run_force_peaks()
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
	var under_budget: bool = (
		_frame_profiler == null
		or (
			FrameBudgetProfilerLib.budget_allows_catchup(
				_frame_profiler.prior_frame_ms(), CFG.FRAME_BUDGET_MS
			)
			and _frame_profiler.prior_frame_ms() <= CFG.FRAME_MS_DEFER_AI
		)
	)
	# After a heavy prior frame, skip overlay apply too — keep queue pending.
	var skip_overlay_drain: bool = (
		_frame_profiler != null
		and _frame_profiler.prior_frame_ms() > CFG.FRAME_MS_TIGHTEN_SOFT_CAP
	)
	var marker_sids: Array = plan.get("marker_sids", [])
	if not marker_sids.is_empty() and globe_map != null:
		if under_budget:
			_refresh_markers(marker_sids)
			_maybe_log_perf_action("markers", {"structures": battle_data.placed_structures.size()}, 3.0)
		else:
			# Prior frame blew budget — re-queue markers instead of stacking draw work.
			for sid_var in marker_sids:
				_outpost_construction_queue.enqueue_marker(int(sid_var))
	var overlay_idxs: PackedInt32Array = plan.get("overlay_indices", PackedInt32Array())
	var overlay_vals: PackedByteArray = plan.get("overlay_values", PackedByteArray())
	var overlay_is_r8: bool = bool(plan.get("overlay_is_r8", false))
	if overlay_idxs.size() > 0 and globe_map != null:
		if skip_overlay_drain:
			if overlay_is_r8:
				_outpost_construction_queue.enqueue_overlay_display_delta(overlay_idxs, overlay_vals)
			else:
				_outpost_construction_queue.enqueue_overlay_delta(overlay_idxs, overlay_vals)
		else:
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
		if not under_budget:
			# Keep pending; drain will retry next frame.
			_outpost_construction_queue.request_gpu_upload()
		else:
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
		var team: int = int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY))
		var is_hostile: bool = team == BattleTileControlLib.OWNER_HOSTILE
		var wallet: Array = _hostile_resources if is_hostile else _friendly_resources
		if wallet[au_idx] < spawn_cost:
			continue
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		territory_sim.sync_agent_nav()
		if territory_sim.try_spawn_soldier(bid, team, gx, gy):
			if _resource_wallet_active():
				var deltas: Array = [0.0, 0.0, 0.0]
				deltas[au_idx] = -spawn_cost
				if is_hostile:
					territory_sim.apply_resource_tick_delta([0.0, 0.0, 0.0], deltas)
				else:
					territory_sim.apply_resource_tick_delta(deltas, [0.0, 0.0, 0.0])
				_pull_resource_wallet_from_rust()
			else:
				if is_hostile:
					_hostile_resources[au_idx] -= spawn_cost
				else:
					_friendly_resources[au_idx] -= spawn_cost
			st["spawn_timer"] = timer - CFG.BARRACKS_SPAWN_INTERVAL_SEC
			_soldier_visual_dirty = true
			if team == BattleTileControlLib.OWNER_FRIENDLY:
				_run_soldiers_spawned += 1
				_bump_run_force_peaks()


func _apply_ai_vs_ai_mode() -> void:
	if not RunState.is_ai_vs_ai():
		return
	# Stagger friendly plans so both AIs don't fire on the same frame.
	_player_ai_clock = CFG.ENEMY_AI_PLAN_INTERVAL_SEC * 0.5
	_apply_build_mode("")
	if spawner_button:
		spawner_button.disabled = true
	if barracks_button:
		barracks_button.disabled = true
	if hangar_button:
		hangar_button.disabled = true
	if paint_button:
		paint_button.disabled = true
		paint_button.button_pressed = false
	if mode_button:
		mode_button.disabled = true
		mode_button.visible = false
	if surge_button:
		surge_button.disabled = true
		surge_button.visible = false
	_set_build_hint("AI vs AI — orbit/zoom to watch (build input muted)")
	RunLog.info("AI vs AI mode enabled — both sides use multi-structure planner")


func _tick_enemy_strategy(dt: float) -> void:
	if not CFG.ENEMY_AI_ENABLED or battle_data == null or territory_sim == null or dt <= 0.0:
		return
	if _enemy_ai_place_cooldown > 0.0:
		_enemy_ai_place_cooldown = maxf(0.0, _enemy_ai_place_cooldown - dt)
	if _enemy_ai_place_cooldown <= 0.0:
		_drain_enemy_ai_queue()
	_enemy_ai_clock += dt
	if _enemy_ai_place_cooldown > 0.0:
		return
	if _enemy_ai_clock < CFG.ENEMY_AI_PLAN_INTERVAL_SEC:
		return
	_enemy_ai_clock = 0.0
	# R1: CONNECTING-count concurrent gate removed — structures go ACTIVE instantly.
	if _enemy_ai_action_queue.size() >= CFG.ENEMY_AI_MAX_ACTIONS_PER_PLAN:
		return
	var snapshot: Dictionary = _build_enemy_ai_snapshot()
	var planned: Array[Dictionary] = EnemyStrategyLib.plan_actions(snapshot)
	if planned.is_empty():
		_maybe_log_empty_ai_plan("enemy", snapshot)
	for action: Dictionary in planned:
		_enemy_ai_action_queue.append(action)


func _tick_player_strategy(dt: float) -> void:
	if not CFG.ENEMY_AI_ENABLED or battle_data == null or territory_sim == null or dt <= 0.0:
		return
	if _player_ai_place_cooldown > 0.0:
		_player_ai_place_cooldown = maxf(0.0, _player_ai_place_cooldown - dt)
	if _player_ai_place_cooldown <= 0.0:
		_drain_player_ai_queue()
	_player_ai_clock += dt
	if _player_ai_place_cooldown > 0.0:
		return
	if _player_ai_clock < CFG.ENEMY_AI_PLAN_INTERVAL_SEC:
		return
	_player_ai_clock = 0.0
	# R1: CONNECTING-count concurrent gate removed — structures go ACTIVE instantly.
	if _player_ai_action_queue.size() >= CFG.ENEMY_AI_MAX_ACTIONS_PER_PLAN:
		return
	var snapshot: Dictionary = _build_player_ai_snapshot()
	var planned: Array[Dictionary] = EnemyStrategyLib.plan_actions(snapshot)
	if planned.is_empty():
		_maybe_log_empty_ai_plan("player", snapshot)
	for action: Dictionary in planned:
		_player_ai_action_queue.append(action)


func _maybe_log_empty_ai_plan(side: String, snapshot: Dictionary) -> void:
	if not RunState.is_ai_vs_ai():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _ai_empty_plan_log_msec < 5000:
		return
	_ai_empty_plan_log_msec = now_msec
	var diag: Dictionary = EnemyStrategyLib.empty_plan_diag(snapshot)
	RunLog.info(
		(
			"AI plan empty (%s): reason=%s supply=%.0f own_spawners=%d connecting=%d own_barracks=%d own_hangars=%d au=%.1f em=%.1f"
			% [
				side,
				str(diag.get("reason", "")),
				float(diag.get("supply", 0.0)),
				int(diag.get("own_spawners", 0)),
				int(diag.get("connecting", 0)),
				int(diag.get("own_barracks", 0)),
				int(diag.get("own_hangars", 0)),
				float(diag.get("self_au", 0.0)),
				float(diag.get("self_em", 0.0)),
			]
		)
	)


func _maybe_log_ai_place_reject(side: String, kind: String, target: Vector2i, reject: String) -> void:
	if not RunState.is_ai_vs_ai():
		return
	if reject == "":
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _ai_place_reject_log_msec < 5000:
		return
	_ai_place_reject_log_msec = now_msec
	RunLog.info(
		(
			"AI place reject (%s): kind=%s target=(%d,%d) reason=%s"
			% [side, kind, target.x, target.y, reject]
		)
	)


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
		# R1: no CONNECTING concurrent-build gate — rely on planner caps / affordability.
		_ensure_route_portals_for_team(BattleTileControlLib.OWNER_HOSTILE, _enemy_home)
		# B1: budgeted pathfind first; full A* only if EnemyStrategy rate-limits allow.
		# Last resort: allow_standalone=true so AI keeps expanding like a human land click (R1).
		var full_n: int = int(action.get("full_astar_attempts", 0))
		var age: float = float(action.get("plan_age_sec", 0.0))
		var team: int = BattleTileControlLib.OWNER_HOSTILE
		var sid: int = debug_place_outpost_at(target, kind, team, false, false)
		if sid < 0 and EnemyStrategyLib.route_allow_full_astar(age, full_n):
			sid = debug_place_outpost_at(target, kind, team, true, false)
			action["full_astar_attempts"] = full_n + 1
		if sid < 0:
			sid = debug_place_outpost_at(target, kind, team, false, true)
		if sid >= 0:
			_pay_enemy_placement_cost(kind)
			_run_enemy_structures_placed += 1
			_enemy_ai_place_cooldown = CFG.ENEMY_AI_BUILD_COOLDOWN_SEC
			_enemy_ai_action_queue.clear()
			_maybe_log_perf_action(
				"enemy_ai",
				{"kind": kind, "gx": target.x, "gy": target.y, "sid": sid},
				1.5,
			)
			return
		else:
			# Drop failed intent — planner will re-evaluate on next interval.
			var fail: Dictionary = _resolve_placement_for_team(target, false, kind, team, true)
			_maybe_log_ai_place_reject("enemy", kind, target, str(fail.get("reject", "unknown")))


func _drain_player_ai_queue() -> void:
	var budget: int = CFG.ENEMY_AI_ACTIONS_PER_FRAME
	while budget > 0 and not _player_ai_action_queue.is_empty():
		budget -= 1
		var action: Dictionary = _player_ai_action_queue.pop_front()
		var kind: String = str(action.get("kind", OutpostBuildLib.KIND_SPAWNER))
		var target: Vector2i = action.get("target", Vector2i(-1, -1))
		if target.x < 0:
			continue
		if not EconomyLib.can_afford_build(_supply, _friendly_resources, kind):
			continue
		# R1: no CONNECTING concurrent-build gate — rely on planner caps / affordability.
		_ensure_route_portals_for_team(BattleTileControlLib.OWNER_FRIENDLY, _player_home)
		var full_n: int = int(action.get("full_astar_attempts", 0))
		var age: float = float(action.get("plan_age_sec", 0.0))
		var team: int = BattleTileControlLib.OWNER_FRIENDLY
		var sid: int = debug_place_outpost_at(target, kind, team, false, false)
		if sid < 0 and EnemyStrategyLib.route_allow_full_astar(age, full_n):
			sid = debug_place_outpost_at(target, kind, team, true, false)
			action["full_astar_attempts"] = full_n + 1
		if sid < 0:
			sid = debug_place_outpost_at(target, kind, team, false, true)
		if sid >= 0:
			_pay_placement_cost(kind)
			_run_player_structures_placed += 1
			_track_player_structure_metrics(kind)
			_player_ai_place_cooldown = CFG.ENEMY_AI_BUILD_COOLDOWN_SEC
			_player_ai_action_queue.clear()
			_maybe_log_perf_action(
				"player_ai",
				{"kind": kind, "gx": target.x, "gy": target.y, "sid": sid},
				1.5,
			)
			return
		else:
			var fail: Dictionary = _resolve_placement_for_team(target, false, kind, team, true)
			_maybe_log_ai_place_reject("player", kind, target, str(fail.get("reject", "unknown")))


func _build_enemy_ai_snapshot() -> Dictionary:
	var tc = territory_sim.tile_control if territory_sim != null else null
	var owners: PackedByteArray = (
		territory_sim.owners_for_ai() if territory_sim != null else PackedByteArray()
	)
	var claimable: PackedByteArray = (
		territory_sim.claimable_mask_for_ai() if territory_sim != null else PackedByteArray()
	)
	if owners.is_empty() and tc != null:
		owners = tc.owners
	if claimable.is_empty() and tc != null:
		claimable = tc.claimable_mask
	return {
		"map_data": battle_data,
		"structures": battle_data.placed_structures if battle_data != null else [],
		"owners": owners,
		"claimable": claimable,
		"self_owner": BattleTileControlLib.OWNER_HOSTILE,
		"opponent_owner": BattleTileControlLib.OWNER_FRIENDLY,
		"self_home": _enemy_home,
		"opponent_home": _player_home,
		"self_supply": _enemy_supply,
		"self_resources": _hostile_resources.duplicate(),
		"connecting_self": _count_connecting_for_team(BattleTileControlLib.OWNER_HOSTILE),
		# Legacy keys (hostile AI / older callers).
		"enemy_home": _enemy_home,
		"player_home": _player_home,
		"friendly_tiles": _friendly_tiles,
		"hostile_tiles": _hostile_tiles,
		"self_tiles": _hostile_tiles,
		"claimable_tiles": _claimable_tiles,
		"enemy_supply": _enemy_supply,
		"difficulty": _enemy_ai_difficulty,
		"connecting_hostile": _count_connecting_for_team(BattleTileControlLib.OWNER_HOSTILE),
	}


func _build_player_ai_snapshot() -> Dictionary:
	var tc = territory_sim.tile_control if territory_sim != null else null
	var owners: PackedByteArray = (
		territory_sim.owners_for_ai() if territory_sim != null else PackedByteArray()
	)
	var claimable: PackedByteArray = (
		territory_sim.claimable_mask_for_ai() if territory_sim != null else PackedByteArray()
	)
	if owners.is_empty() and tc != null:
		owners = tc.owners
	if claimable.is_empty() and tc != null:
		claimable = tc.claimable_mask
	return {
		"map_data": battle_data,
		"structures": battle_data.placed_structures if battle_data != null else [],
		"owners": owners,
		"claimable": claimable,
		"self_owner": BattleTileControlLib.OWNER_FRIENDLY,
		"opponent_owner": BattleTileControlLib.OWNER_HOSTILE,
		"self_home": _player_home,
		"opponent_home": _enemy_home,
		"self_supply": _supply,
		"self_resources": _friendly_resources.duplicate(),
		"connecting_self": _count_connecting_for_team(BattleTileControlLib.OWNER_FRIENDLY),
		"friendly_tiles": _friendly_tiles,
		"hostile_tiles": _hostile_tiles,
		"self_tiles": _friendly_tiles,
		"claimable_tiles": _claimable_tiles,
		"difficulty": _enemy_ai_difficulty,
	}


func _count_hostile_connecting() -> int:
	return _count_connecting_for_team(BattleTileControlLib.OWNER_HOSTILE)


func _count_connecting_for_team(team: int) -> int:
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
			return territory_sim.rust_field.structure_connecting_count(team)
	var n: int = 0
	for st: Dictionary in battle_data.placed_structures:
		if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != team:
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
	_network_road_pending_class = PackedByteArray()
	_road_class_by_cell.clear()
	_road_shoulders_by_center.clear()
	if territory_sim != null and territory_sim.rust_live_ready:
		territory_sim.configure_builders(_player_home, _enemy_home)
		_seed_network_road_visuals()
	_builder_visual_dirty = true


func _seed_network_road_visuals() -> void:
	if territory_sim == null:
		return
	if globe_map != null and globe_map.has_method("register_network_road_path"):
		for st: Dictionary in _placement_structures():
			var pk: PackedInt32Array = st.get("path_keys", PackedInt32Array())
			globe_map.register_network_road_path(pk)
		if battle_data != null:
			for corridor: Dictionary in battle_data.bridge_corridors:
				var cpk: PackedInt32Array = corridor.get("path_keys", PackedInt32Array())
				globe_map.register_network_road_path(cpk)
	for team in [BattleTileControlLib.OWNER_FRIENDLY, BattleTileControlLib.OWNER_HOSTILE]:
		var mask: PackedByteArray = territory_sim.get_network_built_mask(team)
		for idx in range(mask.size()):
			if mask[idx] != 0:
				var cls: int = int(_road_class_by_cell.get(idx, OutpostBuildLib.ROAD_CLASS_ARTERIAL))
				_enqueue_network_road_paint(idx, cls)


## R1: network road MultiMesh paint retired — drop any pending queue without drawing.
func _drain_network_road_visuals() -> void:
	_network_road_pending = PackedInt32Array()
	_network_road_pending_class = PackedByteArray()


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
		battle_data,
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
	BuilderAgentLib.begin_builder_return(bot, battle_data.placed_structures, battle_data)
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


## R1: road growth / builder bots removed. configure_builders may still run once for
## WorldDatasetAssert (builder authority flag), but nothing ticks growth or road paint.
func _update_builder_agents(_dt: float) -> void:
	return


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
		bot, battle_data.placed_structures, battle_data
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
	var sphere: bool = battle_data != null and battle_data.sphere_mode
	for i in range(_builder_agents.size()):
		var bot: Dictionary = _builder_agents[i]
		if sphere:
			positions.append(
				BuilderAgentLib.work_sphere_world_pos(
					bot,
					battle_data.placed_structures,
					battle_data,
					globe_map,
					CFG.BUILDER_SURFACE_LIFT,
				)
			)
		else:
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
	# R1: land bridges removed — drop any leftover corridor rows and clear claimable stamps.
	if battle_data == null:
		return
	if battle_data.bridge_corridors is Array and not battle_data.bridge_corridors.is_empty():
		battle_data.bridge_corridors.clear()
		_sync_bridge_corridors_to_sim(true, true)
	_bridges_repaired = true


func _repair_bridge_corridor_paths() -> void:
	# R1 no-op — corridors are not repaired or beachheaded.
	_maintain_bridge_corridors()


func _update_tile_probe() -> void:
	if tile_probe_label == null or battle_data == null or territory_sim == null:
		return
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		tile_probe_label.text = "Move cursor over the globe."
		if inspect_claim_label:
			inspect_claim_label.text = ""
		_clear_inspect_meters()
		return
	var probe: Dictionary = territory_sim.query_tile(grid.x, grid.y)
	if not bool(probe.get("valid", false)):
		tile_probe_label.text = "Invalid tile."
		_clear_inspect_meters()
		return
	var claimable: bool = bool(probe.get("claimable", false))
	var terrain: String = str(probe.get("terrain", "?"))
	var owner_s: String = str(probe.get("owner", "?"))
	var claim_line: String = "Claimable land"
	if not claimable:
		if terrain == "water":
			claim_line = "Ocean — ferry or bomb to open a shore"
		else:
			claim_line = "Unopened land — bomb or ferry to claim"
	var elev: float = float(probe.get("elev", 0.0))
	var pf: float = float(probe.get("pf", 0.0))
	var ph: float = float(probe.get("ph", 0.0))
	var h_val: float = float(probe.get("h_friendly", pf + elev))
	tile_probe_label.text = "%s · %s" % [
		terrain.capitalize() if terrain.length() > 0 else "Tile",
		owner_s,
	]
	if inspect_claim_label:
		inspect_claim_label.text = claim_line
	var total_p: float = maxf(0.001, pf + ph)
	var meter_w: float = 244.0
	if inspect_pressure_blue != null and inspect_pressure_blue.get_parent() is Control:
		meter_w = maxf(8.0, (inspect_pressure_blue.get_parent() as Control).size.x)
	if inspect_pressure_blue:
		inspect_pressure_blue.offset_right = (pf / total_p) * meter_w
	if inspect_pressure_red:
		inspect_pressure_red.offset_left = -((ph / total_p) * meter_w)
	if inspect_pressure_caption:
		inspect_pressure_caption.text = "Blue %.2f   Red %.2f" % [pf, ph]
	if inspect_elev_bar:
		inspect_elev_bar.value = clampf(elev, 0.0, 100.0)
	if inspect_elev_caption:
		inspect_elev_caption.text = "Elev %.0f / 100   H %.1f" % [elev, h_val]


func _clear_inspect_meters() -> void:
	if inspect_pressure_blue:
		inspect_pressure_blue.offset_right = 0.0
	if inspect_pressure_red:
		inspect_pressure_red.offset_left = 0.0
	if inspect_elev_bar:
		inspect_elev_bar.value = 0.0


func _on_inspect_toggled(on: bool) -> void:
	_tile_inspect_active = on
	if inspect_card:
		inspect_card.visible = on
	if tile_probe_label:
		tile_probe_label.visible = on
	if globe_map != null and globe_map.has_method("set_inspect_boost"):
		globe_map.set_inspect_boost(on)
	_style_tool_buttons()
	if on:
		_update_tile_probe()
	elif tile_probe_label:
		tile_probe_label.text = ""


func _rust_commands():
	if territory_sim == null:
		return null
	return territory_sim.rust_field


func _set_paint_armed(on: bool) -> void:
	if not on and _paint_stroke_active:
		_commit_paint_stroke()
		return
	_paint_armed = on and not RunState.is_ai_vs_ai()
	if paint_button:
		paint_button.set_block_signals(true)
		paint_button.button_pressed = _paint_armed
		paint_button.set_block_signals(false)
	if _paint_armed:
		_apply_build_mode("")
	_update_build_ui()


func _on_paint_toggled(on: bool) -> void:
	if RunState.is_ai_vs_ai():
		_set_paint_armed(false)
		return
	if on:
		_apply_build_mode("")
		_paint_armed = true
	else:
		if _paint_stroke_active:
			_commit_paint_stroke()
			return
		_paint_armed = false
	_update_build_ui()


func _try_begin_paint_stroke() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		_set_build_hint("Click-drag the globe to paint a region.")
		return
	var rust = _rust_commands()
	if rust == null or not rust.has_method("begin_team_paint_stroke"):
		_set_build_hint("Paint needs the live Rust sim.")
		return
	if not rust.begin_team_paint_stroke(BattleTileControlLib.OWNER_FRIENDLY):
		_set_build_hint("Could not start a paint stroke.")
		return
	_paint_stroke_active = true
	_paint_last_cell = Vector2i(-99999, -99999)
	if not _stamp_paint_at_cursor():
		rust.clear_team_paint(BattleTileControlLib.OWNER_FRIENDLY)
		_paint_stroke_active = false
		_set_build_hint("Need land — water snaps to the nearest coast.")
		return
	_set_build_hint("Drag to paint. Release to send units. Esc cancels.")


func _stamp_paint_at_cursor() -> bool:
	if not _paint_stroke_active:
		return false
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		return false
	if grid == _paint_last_cell:
		return true
	var rust = _rust_commands()
	if rust == null or not rust.has_method("stamp_team_paint"):
		return false
	if not rust.stamp_team_paint(BattleTileControlLib.OWNER_FRIENDLY, grid.x, grid.y):
		return false
	_paint_last_cell = grid
	_refresh_paint_pin()
	var pin: Dictionary = rust.get_team_paint(BattleTileControlLib.OWNER_FRIENDLY)
	var n: int = int(pin.get("count", 0))
	if n >= CFG.PAINT_CELL_CAP:
		_set_build_hint("Region full (%d). %s  Release to send units, or Clear paint." % [n, _paint_inbound_hint()])
	else:
		_set_build_hint(
			"Painting %d / %d. %s  Release to commit."
			% [n, CFG.PAINT_CELL_CAP, _paint_inbound_hint()]
		)
	return true


func _commit_paint_stroke() -> void:
	if not _paint_stroke_active:
		return
	_paint_stroke_active = false
	_paint_armed = false
	if paint_button:
		paint_button.set_block_signals(true)
		paint_button.button_pressed = false
		paint_button.set_block_signals(false)
	var rust = _rust_commands()
	if rust != null and rust.has_method("commit_team_paint_stroke"):
		rust.commit_team_paint_stroke(BattleTileControlLib.OWNER_FRIENDLY)
	_refresh_paint_pin()
	_update_build_ui()
	if rust == null:
		return
	var pin: Dictionary = rust.get_team_paint(BattleTileControlLib.OWNER_FRIENDLY)
	var n: int = int(pin.get("count", 0))
	if n <= 0 or int(pin.get("kind", 0)) == CFG.PAINT_NONE:
		_set_build_hint("Paint cleared.")
		return
	_set_build_hint(
		"Painted %d tiles. %s  Soldiers ferry until you own ~80%% of it."
		% [n, _paint_inbound_hint()]
	)


func _abort_paint_stroke() -> void:
	if not _paint_stroke_active:
		return
	_paint_stroke_active = false
	var rust = _rust_commands()
	if rust != null and rust.has_method("clear_team_paint"):
		rust.clear_team_paint(BattleTileControlLib.OWNER_FRIENDLY)
	_refresh_paint_pin()
	_set_build_hint("Paint cancelled.")


func _on_cancel_paint_pressed() -> void:
	if _paint_stroke_active:
		_abort_paint_stroke()
	else:
		var rust = _rust_commands()
		if rust != null and rust.has_method("clear_team_paint"):
			rust.clear_team_paint(BattleTileControlLib.OWNER_FRIENDLY)
		_refresh_paint_pin()
		_set_build_hint("Paint cleared.")
	_set_paint_armed(false)
	_refresh_command_hud()


func _refresh_paint_pin() -> void:
	if globe_map == null:
		return
	var rust = _rust_commands()
	if rust == null or not rust.has_method("get_team_paint"):
		globe_map.clear_command_pin()
		if globe_map.has_method("clear_paint_overlay"):
			globe_map.clear_paint_overlay()
		return
	var pin: Dictionary = rust.get_team_paint(BattleTileControlLib.OWNER_FRIENDLY)
	var kind: int = int(pin.get("kind", 0))
	if kind == CFG.PAINT_NONE:
		globe_map.clear_command_pin()
		if globe_map.has_method("clear_paint_overlay"):
			globe_map.clear_paint_overlay()
		return
	globe_map.set_command_pin(Vector2i(int(pin.get("gx", -1)), int(pin.get("gy", -1))), kind)
	if globe_map.has_method("set_paint_overlay") and rust.has_method("get_team_paint_cells"):
		globe_map.set_paint_overlay(
			rust.get_team_paint_cells(BattleTileControlLib.OWNER_FRIENDLY),
			BattleTileControlLib.OWNER_FRIENDLY,
			_ownership_overlay_source(),
		)


func _try_select_structure_at_cursor() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y) or battle_data == null:
		return
	var hit_sid: int = -1
	for st_var in battle_data.placed_structures:
		if not (st_var is Dictionary):
			continue
		var st: Dictionary = st_var
		if str(st.get("kind", "")) != OutpostBuildLib.KIND_SPAWNER:
			continue
		if int(st.get("team", 0)) != BattleTileControlLib.OWNER_FRIENDLY:
			continue
		if int(st.get("gx", -999)) == grid.x and int(st.get("gy", -999)) == grid.y:
			hit_sid = int(st.get("id", -1))
			break
	if hit_sid < 0:
		_clear_structure_selection()
		return
	_selected_sid = hit_sid
	_refresh_command_hud()
	_update_build_ui()


func _clear_structure_selection() -> void:
	_selected_sid = -1
	_refresh_command_hud()


func _refresh_command_hud() -> void:
	var rust = _rust_commands()
	var mode: int = CFG.SPAWNER_MODE_PUMP
	var tank: float = 0.0
	var has_outpost: bool = _selected_sid >= 0
	if has_outpost and rust != null and rust.has_method("query_spawner"):
		var q: Dictionary = rust.query_spawner(_selected_sid)
		if not q.is_empty():
			mode = int(q.get("spawner_mode", 0))
			tank = float(q.get("battery_tank", 0.0))
	if mode_button:
		mode_button.disabled = not has_outpost
		mode_button.text = CFG.spawner_mode_label(mode)
	if surge_button:
		surge_button.disabled = not has_outpost or mode != CFG.SPAWNER_MODE_BATTERY or tank <= 0.01
		surge_button.text = "Surge" if tank <= 0.01 else "Surge %.0f" % tank
		if not surge_button.disabled:
			GameThemeLib.apply_primary_button(surge_button)
		else:
			GameThemeLib.apply_ghost_button(surge_button)
	if outpost_pin_card:
		var show_card: bool = has_outpost and not RunState.is_ai_vs_ai()
		outpost_pin_card.visible = show_card
		if show_card:
			_position_outpost_pin_card()
	if cancel_paint_button:
		var painted: bool = _paint_armed or _paint_stroke_active
		cancel_paint_button.visible = painted and not RunState.is_ai_vs_ai()
	if globe_map != null and globe_map.has_method("set_selected_structure_grid"):
		var sel_grid := Vector2i(-1, -1)
		if has_outpost and battle_data != null:
			for st_var in battle_data.placed_structures:
				if not (st_var is Dictionary):
					continue
				var st: Dictionary = st_var
				if int(st.get("id", -1)) == _selected_sid:
					sel_grid = Vector2i(int(st.get("gx", -1)), int(st.get("gy", -1)))
					break
		globe_map.set_selected_structure_grid(sel_grid)
	_refresh_paint_pin()


func _on_mode_pressed() -> void:
	if _selected_sid < 0 or RunState.is_ai_vs_ai():
		return
	var rust = _rust_commands()
	if rust == null or not rust.has_method("set_spawner_mode"):
		return
	var q: Dictionary = rust.query_spawner(_selected_sid)
	var cur: int = int(q.get("spawner_mode", 0))
	var nxt: int = (cur + 1) % 3
	rust.set_spawner_mode(_selected_sid, nxt)
	_refresh_command_hud()
	_set_build_hint("Outpost is now %s." % CFG.spawner_mode_label(nxt))


func _on_surge_pressed() -> void:
	if _selected_sid < 0 or RunState.is_ai_vs_ai():
		return
	var rust = _rust_commands()
	if rust == null or not rust.has_method("surge_spawner"):
		return
	var dumped: float = float(rust.surge_spawner(_selected_sid))
	_refresh_command_hud()
	if dumped <= 0.01:
		_set_build_hint("Battery is empty — wait, then Surge.")
	else:
		_set_build_hint("Surged %.0f pressure from the outpost." % dumped)
		if globe_map != null and globe_map.has_method("flash_structure"):
			globe_map.flash_structure(_selected_sid)


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
	# Beachheads expand claimable in Rust — refresh denominator every sync or % exceeds 100.
	var live_claimable: int = territory_sim.claimable_tile_count_live()
	if live_claimable > 0:
		territory_sim.claimable_tiles = live_claimable
		_claimable_tiles = live_claimable
	if territory_sim.grid_authority_active() and territory_sim.rust_field != null:
		_friendly_tiles = territory_sim.rust_field.friendly_tiles
		_hostile_tiles = territory_sim.rust_field.hostile_tiles
		_run_peak_land_pct = maxi(_run_peak_land_pct, _pct(_friendly_tiles))
		_run_peak_enemy_land_pct = maxi(_run_peak_enemy_land_pct, _pct(_hostile_tiles))
		return
	if territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	_friendly_tiles = tc.friendly_tiles
	_hostile_tiles = tc.hostile_tiles
	_run_peak_land_pct = maxi(_run_peak_land_pct, _pct(_friendly_tiles))
	_run_peak_enemy_land_pct = maxi(_run_peak_enemy_land_pct, _pct(_hostile_tiles))


func _bump_run_force_peaks() -> void:
	if territory_sim == null:
		return
	_run_peak_soldiers = maxi(_run_peak_soldiers, territory_sim.agent_living_count())
	_run_peak_bombers = maxi(_run_peak_bombers, territory_sim.bomber_living_count())


func _pct(tiles: int) -> int:
	if _claimable_tiles <= 0:
		return 0
	return clampi(int(round(float(tiles) * 100.0 / float(_claimable_tiles))), 0, 100)


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
	play_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_area.offset_top = 0.0
	play_area.offset_bottom = 0.0
	play_area.offset_left = 0.0
	play_area.offset_right = 0.0
	var play_size: Vector2 = play_area.size
	if play_size.x < 8.0 or play_size.y < 8.0:
		return
	sub_viewport_container.stretch = true
	var scale: float = CFG.GLOBE_RENDER_SCALE
	sub_viewport.size = Vector2i(
		maxi(int(play_size.x * scale), 1),
		maxi(int(play_size.y * scale), 1),
	)
	if end_scroll != null:
		end_scroll.custom_minimum_size.y = 0.0


func _update_hud() -> void:
	if you_caption:
		you_caption.text = "You %d%%" % _pct(_friendly_tiles)
	if enemy_caption:
		enemy_caption.text = "Enemy %d%%" % _pct(_hostile_tiles)
	if au_label:
		au_label.text = "Au %d" % int(floor(_friendly_resources[0] if _friendly_resources.size() > 0 else 0.0))
	if ve_label:
		ve_label.text = "Ve %d" % int(floor(_friendly_resources[1] if _friendly_resources.size() > 1 else 0.0))
	if em_label:
		em_label.text = "Em %d" % int(floor(_friendly_resources[2] if _friendly_resources.size() > 2 else 0.0))
	_update_land_tug()
	_pulse_upkeep_warning()
	time_label.text = _format_sim_time(_sim_time)
	var supply_income: int = int(round(float(_friendly_tiles) * CFG.INCOME_PER_TILE_PER_SEC))
	supply_label.text = "Supply %s" % _format_supply(_supply)
	if supply_income != 0:
		supply_label.text = "Supply %s · +%d/s" % [_format_supply(_supply), supply_income]
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
		status_label.visible = true
		status_label.text = "WorldDataset FAIL CLOSED — fix Rust DLL / live flags"
		return
	if status_label:
		status_label.visible = false
	_maybe_show_conquest_nudge()
	speed_button.text = "x%.0f" % _speed_mult
	_bump_run_force_peaks()
	_refresh_command_hud()
	_refresh_build_affordances()
	_style_tool_buttons()
	if build_hint_label:
		build_hint_label.visible = build_hint_label.text != ""


func _style_summary_hud() -> void:
	if supply_label:
		supply_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		supply_label.add_theme_font_size_override("font_size", 13)
	if summary_bar:
		summary_bar.add_theme_stylebox_override("panel", GameThemeLib.make_ribbon_style())
		summary_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if back_button:
			back_button.mouse_filter = Control.MOUSE_FILTER_STOP
			GameThemeLib.apply_ghost_button(back_button)
	if build_cluster:
		build_cluster.add_theme_stylebox_override("panel", GameThemeLib.make_cluster_style())
	if sim_cluster:
		sim_cluster.add_theme_stylebox_override("panel", GameThemeLib.make_cluster_style())
	if outpost_pin_card:
		outpost_pin_card.add_theme_stylebox_override(
			"panel", GameThemeLib.make_panel_style(Color(0.09, 0.11, 0.16, 0.78), GameThemeLib.BORDER, 6)
		)
		outpost_pin_card.mouse_filter = Control.MOUSE_FILTER_STOP
	GameThemeLib.apply_ghost_button(pause_button)
	GameThemeLib.apply_ghost_button(speed_button)
	GameThemeLib.apply_ghost_button(mode_button)
	GameThemeLib.apply_ghost_button(surge_button)


func _update_land_tug() -> void:
	if land_tug_blue == null or land_tug_red == null or land_tug_neutral == null:
		return
	var claimable: float = maxf(1.0, float(_claimable_tiles))
	var blue_r: float = maxf(0.02, float(_friendly_tiles) / claimable)
	var red_r: float = maxf(0.02, float(_hostile_tiles) / claimable)
	var rest: float = maxf(0.02, 1.0 - blue_r - red_r + 0.04)
	land_tug_blue.size_flags_stretch_ratio = blue_r
	land_tug_red.size_flags_stretch_ratio = red_r
	land_tug_neutral.size_flags_stretch_ratio = rest


func _pulse_upkeep_warning() -> void:
	if au_label == null:
		return
	var deficit: bool = (
		territory_sim != null and territory_sim.agent_deficit_dps.x > 0.02
	)
	if deficit:
		var pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
		au_label.add_theme_color_override(
			"font_color", Color(1.0, 0.45 + pulse * 0.2, 0.22, 1.0)
		)
	else:
		au_label.add_theme_color_override("font_color", CFG.RESOURCE_COLORS[0])


func _refresh_build_affordances() -> void:
	if RunState.is_ai_vs_ai():
		return
	var outpost_ok: bool = EconomyLib.can_afford_build(
		_supply, _friendly_resources, OutpostBuildLib.KIND_SPAWNER
	)
	var barracks_ok: bool = EconomyLib.can_afford_build(
		_supply, _friendly_resources, OutpostBuildLib.KIND_BARRACKS
	)
	var hangar_ok: bool = EconomyLib.can_afford_build(
		_supply, _friendly_resources, OutpostBuildLib.KIND_HANGAR
	)
	if spawner_button:
		spawner_button.disabled = not outpost_ok and _build_mode != OutpostBuildLib.KIND_SPAWNER
	if barracks_button:
		barracks_button.disabled = not barracks_ok and _build_mode != OutpostBuildLib.KIND_BARRACKS
	if hangar_button:
		hangar_button.disabled = not hangar_ok and _build_mode != OutpostBuildLib.KIND_HANGAR


func _setup_hud_micro_labels() -> void:
	pass


func _insert_hud_micro_label(panel: VBoxContainer, text: String, align: int, child_index: int) -> void:
	if panel == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", GameThemeLib.TEXT_MUTED)
	panel.add_child(lbl)
	panel.move_child(lbl, child_index)


func _update_build_ui() -> void:
	spawner_button.set_block_signals(true)
	spawner_button.button_pressed = _build_mode == OutpostBuildLib.KIND_SPAWNER
	spawner_button.set_block_signals(false)
	if barracks_button:
		barracks_button.set_block_signals(true)
		barracks_button.button_pressed = _build_mode == OutpostBuildLib.KIND_BARRACKS
		barracks_button.set_block_signals(false)
	if hangar_button:
		hangar_button.set_block_signals(true)
		hangar_button.button_pressed = _build_mode == OutpostBuildLib.KIND_HANGAR
		hangar_button.set_block_signals(false)
	if _build_mode == OutpostBuildLib.KIND_SPAWNER:
		_set_build_hint(
			"Left-click any land you do not already hold (%s). Builds instantly. Esc cancel."
			% _format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER))
		)
	elif _build_mode == OutpostBuildLib.KIND_BARRACKS:
		_set_build_hint(
			"Left-click land (%s). Builds instantly. Soldiers cost Au+Ve. Esc cancel."
			% _format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_BARRACKS))
		)
	elif _build_mode == OutpostBuildLib.KIND_HANGAR:
		_set_build_hint(
			"Left-click land (%s). Builds instantly. Bombers cost Au+Em. Esc cancel."
			% _format_supply(EconomyLib.supply_cost(OutpostBuildLib.KIND_HANGAR))
		)
	else:
		if hover_label != null and (
			hover_label.text.begins_with("(") or hover_label.text.begins_with("Move cursor")
		):
			hover_label.text = ""
			hover_label.visible = false
		if _paint_armed:
			_set_build_hint("Click-drag land to paint a target region. %s  Esc cancel." % _paint_inbound_hint())
		elif _selected_sid >= 0:
			_set_build_hint("Outpost selected — Mode cycles Pump/Drain/Battery. Surge fires a Battery wave.")
		else:
			_refresh_idle_hint()
	_refresh_command_hud()


func _update_build_hover_hint() -> void:
	if not _is_build_mode_active():
		_clear_placement_preview()
		return
	var grid: Vector2i = _mouse_to_grid()
	if grid == _hover_hint_grid:
		return
	_hover_hint_grid = grid
	if hover_label == null:
		if _is_on_map_grid(grid.x, grid.y) and _placement_hover_reject(grid.x, grid.y) == "":
			_show_landing_preview(grid)
		else:
			_clear_placement_preview()
		return
	if not _is_on_map_grid(grid.x, grid.y):
		hover_label.text = "Move cursor over the globe."
		hover_label.visible = true
		_clear_placement_preview()
		return
	var reject: String = _placement_hover_reject(grid.x, grid.y)
	if reject != "":
		hover_label.text = "(%d,%d) — %s" % [grid.x, grid.y, reject]
		hover_label.visible = true
		_clear_placement_preview()
		return
	hover_label.text = "(%d,%d) Click to place" % [grid.x, grid.y]
	hover_label.visible = true
	_show_landing_preview(grid)


## R1: placement is instant and lands on the clicked cell, so the hover affordance is a single
## landing marker — no route planner, no ribbon. Callers must have cleared the reject first.
func _show_landing_preview(grid: Vector2i) -> void:
	if not CFG.ROUTE_HOVER_PREVIEW or globe_map == null or battle_data == null:
		return
	if _build_mode == "":
		return
	var landing_idx: int = battle_data.cell_index(grid.x, grid.y)
	if landing_idx < 0:
		_clear_placement_preview()
		return
	_hover_landing_grid = grid
	_route_pending_landing = grid
	globe_map.set_placement_preview(PackedInt32Array([landing_idx]), grid, grid, true, false)


func _apply_build_mode(mode: String) -> void:
	if RunState.is_ai_vs_ai() and mode != "":
		mode = ""
	if mode != "":
		if _paint_stroke_active:
			_commit_paint_stroke()
		_paint_armed = false
		if paint_button:
			paint_button.set_block_signals(true)
			paint_button.button_pressed = false
			paint_button.set_block_signals(false)
	if _corridor_kind_removed(mode):
		# R1: land bridges removed — never enter corridor build mode.
		_set_build_hint("Land bridges removed.")
		mode = ""
	_build_mode = mode
	_route_hover_clock = 0.0
	if mode == OutpostBuildLib.KIND_SPAWNER and _clarity_beat_showing and _clarity_beat_index == 1:
		_dismiss_current_clarity_beat()
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
	elif mode == OutpostBuildLib.KIND_BARRACKS:
		spawner_button.set_block_signals(true)
		spawner_button.button_pressed = false
		spawner_button.set_block_signals(false)
		if hangar_button:
			hangar_button.set_block_signals(true)
			hangar_button.button_pressed = false
			hangar_button.set_block_signals(false)
	elif mode == OutpostBuildLib.KIND_HANGAR:
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
	if RunState.is_ai_vs_ai():
		if spawner_button:
			spawner_button.set_block_signals(true)
			spawner_button.button_pressed = false
			spawner_button.set_block_signals(false)
		return
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_SPAWNER)
	elif _build_mode == OutpostBuildLib.KIND_SPAWNER:
		_apply_build_mode("")


func _on_barracks_toggled(on: bool) -> void:
	if RunState.is_ai_vs_ai():
		if barracks_button:
			barracks_button.set_block_signals(true)
			barracks_button.button_pressed = false
			barracks_button.set_block_signals(false)
		return
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_BARRACKS)
	elif _build_mode == OutpostBuildLib.KIND_BARRACKS:
		_apply_build_mode("")


func _on_hangar_toggled(on: bool) -> void:
	if RunState.is_ai_vs_ai():
		if hangar_button:
			hangar_button.set_block_signals(true)
			hangar_button.button_pressed = false
			hangar_button.set_block_signals(false)
		return
	if on:
		_apply_build_mode(OutpostBuildLib.KIND_HANGAR)
	elif _build_mode == OutpostBuildLib.KIND_HANGAR:
		_apply_build_mode("")


func _on_pause_pressed() -> void:
	_toggle_pause()


func _toggle_pause() -> void:
	if _loading or _deploy_phase or _battle_finished:
		return
	_paused = not _paused
	_update_pause_button_text()


func _update_pause_button_text() -> void:
	if pause_button:
		pause_button.text = "Resume" if _paused else "Pause"


func _on_speed_pressed() -> void:
	if _speed_mult < 1.5:
		_speed_mult = 2.0
	elif _speed_mult < 3.0:
		_speed_mult = 4.0
	else:
		_speed_mult = 1.0


func _setup_clarity_banner() -> void:
	if clarity_banner == null:
		return
	clarity_banner.visible = false
	clarity_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clarity_banner.add_theme_stylebox_override("panel", GameThemeLib.make_panel_style())
	if clarity_label:
		clarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clarity_label.add_theme_color_override("font_color", GameThemeLib.TEXT_PRIMARY)


func _clarity_beats_active() -> bool:
	return RunState.first_run_clarity and not _should_skip_deploy_pick()


func _clarity_beats_blocked() -> bool:
	return _loading or _deploy_phase or _battle_finished or end_overlay.visible


func _clarity_on_match_live() -> void:
	_coast_check_known = false
	_coast_check_cache = false
	_coast_check_clock = 0.0
	_clarity_poll_clock = 0.0
	if not _clarity_beats_active() or _clarity_beats_blocked():
		return
	_try_start_clarity_beat()


func _try_start_clarity_beat() -> void:
	if not _clarity_beats_active() or _clarity_beats_blocked():
		return
	if _clarity_beat_showing or _clarity_beat_index >= CLARITY_BEAT_COUNT:
		return
	while _clarity_beat_index < CLARITY_BEAT_COUNT and _clarity_beat_already_done(_clarity_beat_index):
		_clarity_beat_index += 1
	if _clarity_beat_index >= CLARITY_BEAT_COUNT:
		_finish_clarity_beats()
		return
	if not _clarity_beat_trigger_met(_clarity_beat_index):
		return
	_show_clarity_beat(_clarity_beat_index)


func _show_clarity_beat(idx: int) -> void:
	if clarity_banner == null or clarity_label == null:
		return
	if idx < 0 or idx >= CLARITY_BEAT_TEXTS.size():
		return
	_clarity_beat_showing = true
	_clarity_timer = 0.0
	_clarity_click_dismiss = false
	clarity_label.text = CLARITY_BEAT_TEXTS[idx]
	clarity_banner.visible = true
	_pulse_clarity_target(idx)


func _hide_clarity_banner() -> void:
	_clarity_beat_showing = false
	_clarity_timer = 0.0
	_clarity_click_dismiss = false
	if clarity_banner:
		clarity_banner.visible = false
	_stop_clarity_pulse()


func _dismiss_current_clarity_beat() -> void:
	if not _clarity_beat_showing:
		return
	match _clarity_beat_index:
		0:
			_clarity_pressure_dismissed = true
		1:
			_clarity_outpost_dismissed = true
		2:
			_clarity_minerals_dismissed_at = _sim_time
	_hide_clarity_banner()
	_clarity_beat_index += 1
	if _clarity_beat_index >= CLARITY_BEAT_COUNT:
		_finish_clarity_beats()
	else:
		_try_start_clarity_beat()


func _finish_clarity_beats() -> void:
	_hide_clarity_banner()
	_clarity_beat_index = CLARITY_BEAT_COUNT
	RunState.first_run_clarity = false


func _clarity_beat_trigger_met(idx: int) -> bool:
	match idx:
		0:
			return true
		1:
			return _clarity_pressure_dismissed and _supply >= float(EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER))
		2:
			return (
				_clarity_first_outpost_placed
				or (
					_clarity_outpost_dismissed
					and _supply >= float(EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER))
				)
			)
		3:
			# Ferry beat only after minerals; coast ownership or 90s fallback.
			if _clarity_minerals_dismissed_at < 0.0:
				return false
			if _player_owns_coast():
				return true
			return _sim_time - _clarity_minerals_dismissed_at >= 90.0
		4:
			return _clarity_barracks_or_hangar_available() or _sim_time >= 120.0
		_:
			return false


func _clarity_beat_should_dismiss(idx: int) -> bool:
	if _clarity_timer >= CLARITY_BEAT_DISMISS_SEC:
		return true
	match idx:
		0:
			return _clarity_click_dismiss
		1:
			return (
				_build_mode == OutpostBuildLib.KIND_SPAWNER
				or _clarity_first_outpost_placed
			)
		_:
			return false


func _tick_clarity_beats(delta: float) -> void:
	if not _clarity_beats_active():
		return
	if _clarity_beats_blocked():
		if _clarity_beat_showing:
			_hide_clarity_banner()
		return
	if _clarity_beat_showing:
		_clarity_timer += delta
		if _clarity_beat_should_dismiss(_clarity_beat_index):
			_dismiss_current_clarity_beat()
		return
	# Poll triggers a few times/sec — never every frame (coast scan is expensive).
	_clarity_poll_clock += delta
	if _clarity_poll_clock < 0.25:
		return
	_clarity_poll_clock = 0.0
	_try_start_clarity_beat()


func _player_owns_coast() -> bool:
	# Once true for this match, stay true. While false, recheck at most 1 Hz.
	if _coast_check_known and _coast_check_cache:
		return true
	var now_msec: int = Time.get_ticks_msec()
	if _coast_check_known and float(now_msec) - _coast_check_clock < 1000.0:
		return _coast_check_cache
	_coast_check_clock = float(now_msec)
	_coast_check_cache = _scan_player_owns_coast()
	_coast_check_known = true
	return _coast_check_cache


func _scan_player_owns_coast() -> bool:
	if battle_data == null or territory_sim == null or territory_sim.tile_control == null:
		return false
	var owners: PackedByteArray = territory_sim.tile_control.owners
	if battle_data.sphere_mode:
		var n: int = battle_data.cell_count
		for cid in range(n):
			if cid >= owners.size() or owners[cid] != BattleTileControlLib.OWNER_FRIENDLY:
				continue
			if OutpostBuildLib.is_coastal_cell(battle_data, cid, 0):
				return true
		return false
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	for gy in range(h):
		for gx in range(w):
			var idx: int = battle_data.cell_index(gx, gy)
			if idx < 0 or idx >= owners.size() or owners[idx] != BattleTileControlLib.OWNER_FRIENDLY:
				continue
			if OutpostBuildLib.is_coastal_cell(battle_data, gx, gy):
				return true
	return false


func _clarity_barracks_or_hangar_available() -> bool:
	return (
		EconomyLib.can_afford_build(_supply, _friendly_resources, OutpostBuildLib.KIND_BARRACKS)
		or EconomyLib.can_afford_build(_supply, _friendly_resources, OutpostBuildLib.KIND_HANGAR)
	)


func _maybe_show_conquest_nudge() -> void:
	if _conquest_nudge_shown or _claimable_tiles <= 0 or _is_build_mode_active():
		return
	if float(_friendly_tiles) / float(_claimable_tiles) < 0.75:
		return
	_conquest_nudge_shown = true
	if _clarity_beat_showing:
		return
	_set_build_hint("Conquest in reach.")


func _on_battle_finished() -> void:
	_finish_clarity_beats()
	# Skip full 65k border rebuild when live SCD1 kept the overlay cache warm.
	var cache_warm: bool = (
		globe_map != null
		and globe_map.owner_overlay_cache_populated()
		and _outpost_construction_queue != null
		and not _outpost_construction_queue.has_pending()
	)
	if cache_warm:
		_outpost_construction_queue.request_gpu_upload()
	elif globe_map != null:
		_apply_owner_visual_from_backends()
	if globe_map != null:
		globe_map.flush_pending_owner_gpu_upload(true)
	var res: Dictionary = territory_sim.get_result()
	_battle_finished = true
	_populate_end_dashboard(res)
	end_overlay.visible = true
	end_overlay.z_index = 60
	if end_dim:
		end_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if build_cluster:
		build_cluster.visible = false
	if sim_cluster:
		sim_cluster.visible = false
	if outpost_pin_card:
		outpost_pin_card.visible = false
	if inspect_card:
		inspect_card.visible = false
	if clarity_banner:
		clarity_banner.visible = false


func _populate_end_dashboard(res: Dictionary) -> void:
	var won: bool = bool(res.get("player_won", false))
	var reason: String = str(res.get("end_reason", ""))
	var headline: String = "You hold Earth"
	if won and reason == "enemy_zero_power":
		headline = "The red tide collapsed"
	elif won:
		headline = "You hold Earth"
	elif reason == "time_cap":
		headline = "Time expired"
	elif reason == "total_conquest":
		headline = "The red tide won"
	else:
		headline = "Defeat"
	var human_reason: String = _humanize_end_reason(reason)
	if end_headline_label:
		end_headline_label.text = headline
	if end_reason_label:
		end_reason_label.text = human_reason
	var land_pct: int = _pct(_friendly_tiles)
	var enemy_land_pct: int = _pct(_hostile_tiles)
	if end_kpi_land_held:
		end_kpi_land_held.text = "%d%%" % land_pct
	if end_kpi_peak_land:
		end_kpi_peak_land.text = "%d%%" % _run_peak_land_pct
	if end_kpi_sim_time:
		end_kpi_sim_time.text = _format_sim_time(_sim_time)
	if end_kpi_structures:
		end_kpi_structures.text = str(_run_structures_placed)
	if end_kpi_soldiers:
		end_kpi_soldiers.text = str(_run_peak_soldiers)
	if end_kpi_bombers:
		end_kpi_bombers.text = str(_run_peak_bombers)
	var fp: float = 0.0
	var ep: float = 0.0
	if territory_sim != null:
		var totals: Vector2 = territory_sim.power_totals()
		fp = totals.x
		ep = totals.y
	if end_you_land_bar:
		end_you_land_bar.value = float(land_pct)
	if end_enemy_land_bar:
		end_enemy_land_bar.value = float(enemy_land_pct)
	if end_you_tiles_label:
		end_you_tiles_label.text = "Tiles %d (%d%%)" % [_friendly_tiles, land_pct]
	if end_enemy_tiles_label:
		end_enemy_tiles_label.text = "Tiles %d (%d%%)" % [_hostile_tiles, enemy_land_pct]
	if end_you_pressure_label:
		end_you_pressure_label.text = "Pressure %s" % _format_supply(fp)
	if end_enemy_pressure_label:
		end_enemy_pressure_label.text = "Pressure %s" % _format_supply(ep)
	if end_you_supply_label:
		end_you_supply_label.text = "Supply %s (spent %s)" % [
			_format_supply(_supply), _format_supply(_run_supply_spent),
		]
	if end_enemy_supply_label:
		end_enemy_supply_label.text = "Supply %s" % _format_supply(_enemy_supply)
	if end_you_minerals_label:
		end_you_minerals_label.text = "Minerals %s" % _format_resources_line(_friendly_resources)
	if end_enemy_minerals_label:
		end_enemy_minerals_label.text = "Minerals %s" % _format_resources_line(_hostile_resources)
	if end_forces_label:
		end_forces_label.text = (
			(
				"Outposts %d · Barracks %d · Hangars %d placed  |  Enemy structures %d  |  "
				+ "Spawned soldiers %d · bombers %d"
			)
			% [
				_run_outposts_placed,
				_run_barracks_placed,
				_run_hangars_placed,
				_run_enemy_structures_placed,
				_run_soldiers_spawned,
				_run_bombers_spawned,
			]
		)
	var seed_val: int = _deploy_run_seed if _deploy_run_seed != 0 else RunState.run_seed
	var map_def: Dictionary = WorldMapCatalogLib.get_definition(_map_id)
	var map_name: String = str(map_def.get("display_name", _map_id))
	if end_meta_label:
		end_meta_label.text = "Seed %d  ·  Win path %s  ·  Map %s" % [seed_val, reason, map_name]
	_style_end_dashboard_result(won)


func _style_end_dashboard_result(won: bool) -> void:
	var accent: Color = GameThemeLib.ACCENT if won else GameThemeLib.ACCENT_DANGER
	var sheet: PanelContainer = $EndOverlay/ScrollCenter as PanelContainer
	if sheet != null:
		var sheet_style := GameThemeLib.make_panel_style(Color(0.09, 0.11, 0.16, 0.86), accent, 8)
		sheet_style.corner_radius_bottom_left = 0
		sheet_style.corner_radius_bottom_right = 0
		sheet.add_theme_stylebox_override("panel", sheet_style)
	if end_dim != null:
		end_dim.color = Color(0.02, 0.03, 0.05, 0.32) if won else Color(0.08, 0.02, 0.04, 0.38)
	if end_headline_label:
		end_headline_label.add_theme_color_override("font_color", accent)


func _humanize_end_reason(reason: String) -> String:
	match reason:
		"total_conquest":
			return "Every reachable land tile was claimed."
		"enemy_zero_power":
			return "Enemy pressure collapsed to zero."
		"time_cap":
			return "The match reached the two-hour sim time limit."
		"conquest", "dominance", "decisive":
			return "One side achieved decisive control."
		"cap", "stall":
			return "The battle ended without a clear victor."
		_:
			return reason if reason != "" else "Battle concluded."


func _on_play_again_pressed() -> void:
	# Keep Custom World criteria; roll a fresh seed. Vanilla Play stays criteria-default.
	RunState.run_seed = randi() & 0x7FFFFFFF
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_same_map_pressed() -> void:
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_end_menu_pressed() -> void:
	_go_main_menu()


func _go_main_menu() -> void:
	# Leaving a match clears Custom World so the next Play is vanilla unless re-opened.
	RunState.reset_custom_world_defaults()
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _confirm_leave(prompt: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = prompt
	dlg.ok_button_text = "Leave"
	dlg.cancel_button_text = "Stay"
	dlg.confirmed.connect(_go_main_menu)
	add_child(dlg)
	dlg.popup_centered()


func _on_back_pressed() -> void:
	if _deploy_phase:
		_confirm_leave("Abort deployment and return to menu?")
		return
	if _loading:
		_go_main_menu()
		return
	if not _battle_finished:
		_confirm_leave("Leave match and return to menu?")
		return
	_go_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if _clarity_beats_active() and _clarity_beat_showing and _clarity_beat_index == 0:
		if event is InputEventMouseButton and event.pressed:
			_clarity_click_dismiss = true
		elif event is InputEventScreenTouch and event.pressed:
			_clarity_click_dismiss = true
	if event.is_action_pressed("pause") and not event.is_echo():
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_show_perf_hud = not _show_perf_hud
			if perf_hud_label:
				perf_hud_label.visible = _show_perf_hud
				if _show_perf_hud:
					perf_hud_label.text = perf_build_hud_text(gather_perf_and_action_context())
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _deploy_phase:
				_deploy_locked_grid = Vector2i(-1, -1)
				_clear_placement_preview()
				_show_deploy_status("Click land · Drag to rotate · Scroll to zoom")
				get_viewport().set_input_as_handled()
			else:
				if _tile_inspect_active:
					_on_inspect_toggled(false)
					if inspect_button:
						inspect_button.set_block_signals(true)
						inspect_button.button_pressed = false
						inspect_button.set_block_signals(false)
				if _paint_stroke_active:
					_abort_paint_stroke()
				_apply_build_mode("")
				_set_paint_armed(false)
				_clear_structure_selection()
				get_viewport().set_input_as_handled()


func _is_on_map_grid(gx: int, gy: int) -> bool:
	if battle_data == null:
		return false
	if battle_data.sphere_mode:
		return gy == 0 and gx >= 0 and gx < battle_data.cell_count
	return gx >= 0 and gy >= 0 and gx < battle_data.grid_width and gy < battle_data.grid_height


func _placement_min_spacing_cells(place_kind: String) -> int:
	# Mirror EnemyStrategy: outposts keep wide spacing; barracks/hangar use soft military min
	# so AI (and humans) can plant military on small claimable beachheads next to outposts.
	if (
		place_kind == OutpostBuildLib.KIND_BARRACKS
		or place_kind == OutpostBuildLib.KIND_HANGAR
	):
		return maxi(2, int(CFG.ENEMY_AI_MILITARY_SPACING_CELLS))
	return CFG.MIN_SPAWNER_SPACING_CELLS


func _structure_too_close(a: Vector2i, bx: int, by: int, min_d: int = -1) -> bool:
	if min_d < 0:
		min_d = CFG.MIN_SPAWNER_SPACING_CELLS
	if battle_data != null and battle_data.sphere_mode:
		# Angular spacing via unit-sphere positions (cell_id Euclidean is meaningless).
		if (
			a.x < 0
			or bx < 0
			or a.x >= battle_data.cell_positions.size()
			or bx >= battle_data.cell_positions.size()
		):
			return false
		var pa: Vector3 = battle_data.cell_positions[a.x].normalized()
		var pb: Vector3 = battle_data.cell_positions[bx].normalized()
		var ang: float = acos(clampf(pa.dot(pb), -1.0, 1.0))
		# Rough cell arc length ≈ sqrt(4π / N); require min_d hops of that scale.
		var cell_ang: float = sqrt(TAU * 2.0 / maxf(1.0, float(battle_data.cell_count)))
		return ang < cell_ang * float(min_d)
	var dx: int = a.x - bx
	var dy: int = a.y - by
	return dx * dx + dy * dy < min_d * min_d


func _format_supply(v: float) -> String:
	return "%d" % int(round(v))


func _set_build_hint(msg: String) -> void:
	if build_hint_label == null:
		return
	build_hint_label.text = msg
	build_hint_label.visible = msg != ""


func _refresh_idle_hint() -> void:
	if _is_build_mode_active() or _paint_armed or _selected_sid >= 0:
		return
	const IDLE := "Right-drag to orbit · scroll to zoom"
	if _orbit_seen:
		if build_hint_label != null and build_hint_label.text == IDLE:
			_set_build_hint("")
	else:
		_set_build_hint(IDLE)


func _bind_tool_hover(btn: Button, label: String) -> void:
	if btn == null:
		return
	btn.mouse_entered.connect(func() -> void:
		if hover_label:
			hover_label.text = label
			hover_label.visible = label != ""
	)
	btn.mouse_exited.connect(func() -> void:
		if hover_label:
			hover_label.text = ""
			hover_label.visible = false
	)


func _setup_tool_icons() -> void:
	if spawner_button:
		spawner_button.icon = GameThemeLib.make_tool_icon("outpost")
		spawner_button.expand_icon = false
	if barracks_button:
		barracks_button.icon = GameThemeLib.make_tool_icon("barracks")
		barracks_button.expand_icon = false
	if hangar_button:
		hangar_button.icon = GameThemeLib.make_tool_icon("hangar")
		hangar_button.expand_icon = false
	if paint_button:
		paint_button.icon = GameThemeLib.make_tool_icon("paint")
		paint_button.expand_icon = false
	if inspect_button:
		inspect_button.icon = GameThemeLib.make_tool_icon("inspect")
		inspect_button.expand_icon = false
	if cancel_paint_button:
		cancel_paint_button.icon = GameThemeLib.make_tool_icon("clear")
		cancel_paint_button.expand_icon = false


func _style_tool_buttons() -> void:
	_style_one_tool(spawner_button, _build_mode == OutpostBuildLib.KIND_SPAWNER)
	_style_one_tool(barracks_button, _build_mode == OutpostBuildLib.KIND_BARRACKS)
	_style_one_tool(hangar_button, _build_mode == OutpostBuildLib.KIND_HANGAR)
	_style_one_tool(paint_button, _paint_armed)
	_style_one_tool(inspect_button, _tile_inspect_active)
	if pause_button:
		if _paused:
			GameThemeLib.apply_latched_button(pause_button)
		else:
			GameThemeLib.apply_ghost_button(pause_button)
			pause_button.modulate = Color.WHITE


func _style_one_tool(btn: Button, latched: bool) -> void:
	if btn == null:
		return
	if latched:
		GameThemeLib.apply_latched_button(btn)
	else:
		GameThemeLib.apply_ghost_button(btn)


func _paint_inbound_hint() -> String:
	var counts: Vector2i = _count_paint_occupancy()
	return "%d soldiers · %d bomber" % [counts.x, counts.y] if counts.y == 1 else "%d soldiers · %d bombers" % [counts.x, counts.y]


func _count_paint_occupancy() -> Vector2i:
	var rust = _rust_commands()
	if rust == null or not rust.has_method("get_team_paint_cells") or battle_data == null:
		return Vector2i.ZERO
	var cells: PackedInt32Array = rust.get_team_paint_cells(BattleTileControlLib.OWNER_FRIENDLY)
	if cells.is_empty():
		return Vector2i.ZERO
	var painted: Dictionary = {}
	for cell in cells:
		painted[int(cell)] = true
	var soldiers: int = 0
	var n_s: int = mini(_last_agent_teams.size(), mini(_last_agent_gx.size(), _last_agent_gy.size()))
	for i in range(n_s):
		if int(_last_agent_teams[i]) != BattleTileControlLib.OWNER_FRIENDLY:
			continue
		var cid: int = battle_data.cell_index(_last_agent_gx[i], _last_agent_gy[i])
		if painted.has(cid):
			soldiers += 1
	var bombers: int = 0
	var n_b: int = mini(_last_bomber_teams.size(), mini(_last_bomber_gx.size(), _last_bomber_gy.size()))
	for i in range(n_b):
		if int(_last_bomber_teams[i]) != BattleTileControlLib.OWNER_FRIENDLY:
			continue
		var cid: int = battle_data.cell_index(_last_bomber_gx[i], _last_bomber_gy[i])
		if painted.has(cid):
			bombers += 1
	return Vector2i(soldiers, bombers)


func _position_outpost_pin_card() -> void:
	if outpost_pin_card == null or globe_map == null or globe_map.camera == null:
		return
	var sel_grid := Vector2i(-1, -1)
	if _selected_sid >= 0 and battle_data != null:
		for st_var in battle_data.placed_structures:
			if not (st_var is Dictionary):
				continue
			var st: Dictionary = st_var
			if int(st.get("id", -1)) == _selected_sid:
				sel_grid = Vector2i(int(st.get("gx", -1)), int(st.get("gy", -1)))
				break
	if sel_grid.x < 0 or not globe_map.has_method("grid_world_pos"):
		return
	var world: Vector3 = globe_map.grid_world_pos(sel_grid)
	var cam: Camera3D = globe_map.camera
	if cam.is_position_behind(world):
		outpost_pin_card.visible = false
		return
	var vp: Vector2 = cam.unproject_position(world)
	if sub_viewport != null and play_area != null and sub_viewport.size.x > 0 and sub_viewport.size.y > 0:
		vp.x *= play_area.size.x / float(sub_viewport.size.x)
		vp.y *= play_area.size.y / float(sub_viewport.size.y)
	vp += Vector2(14, -40)
	var view: Vector2 = get_viewport_rect().size
	vp.x = clampf(vp.x, 12.0, maxf(12.0, view.x - 188.0))
	vp.y = clampf(vp.y, 56.0, maxf(56.0, view.y - 88.0))
	outpost_pin_card.position = vp


func _on_end_details_pressed() -> void:
	_end_details_open = not _end_details_open
	if end_kpi_strip:
		end_kpi_strip.visible = _end_details_open
	if end_compare_row:
		end_compare_row.visible = _end_details_open
	if end_forces_label:
		end_forces_label.visible = _end_details_open
	if end_meta_label:
		end_meta_label.visible = _end_details_open
	if end_details_button:
		end_details_button.text = "Hide details" if _end_details_open else "Details"
	var sheet: PanelContainer = $EndOverlay/ScrollCenter as PanelContainer
	if sheet:
		sheet.offset_top = -436.0 if _end_details_open else -196.0


func _clarity_beat_already_done(idx: int) -> bool:
	match idx:
		1:
			return _run_outposts_placed > 0 or _clarity_first_outpost_placed
		4:
			return _run_hangars_placed > 0
		_:
			return false


func _pulse_clarity_target(idx: int) -> void:
	_stop_clarity_pulse()
	var target: Control = null
	var scale_ok: bool = true
	match idx:
		1:
			target = spawner_button
		2:
			target = au_label
			scale_ok = false
		4:
			target = hangar_button
		_:
			target = null
	if target == null:
		return
	target.pivot_offset = target.size * 0.5
	_clarity_pulse_tween = create_tween()
	_clarity_pulse_tween.set_loops()
	if scale_ok:
		_clarity_pulse_tween.tween_property(target, "scale", Vector2(1.07, 1.07), 0.425)
		_clarity_pulse_tween.tween_property(target, "scale", Vector2.ONE, 0.425)
	else:
		_clarity_pulse_tween.tween_property(target, "modulate", Color(1.0, 0.92, 0.55, 1.0), 0.425)
		_clarity_pulse_tween.tween_property(target, "modulate", Color.WHITE, 0.425)


func _stop_clarity_pulse() -> void:
	if _clarity_pulse_tween != null:
		_clarity_pulse_tween.kill()
		_clarity_pulse_tween = null
	for btn in [spawner_button, hangar_button]:
		if btn:
			btn.modulate = Color.WHITE
			btn.scale = Vector2.ONE
	if au_label:
		au_label.modulate = Color.WHITE
	if ve_label:
		ve_label.modulate = Color.WHITE
	if em_label:
		em_label.modulate = Color.WHITE


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
