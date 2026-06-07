extends Control

const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
const BattleDirectivesLib := preload("res://BattleDirectives.gd")
const BattlePhaseControllerLib := preload("res://BattlePhaseController.gd")
const TurnResolverLib := preload("res://TurnResolver.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleAtmosphereLib := preload("res://BattleAtmosphere.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattleTerritoryReplayPlayerLib := preload("res://BattleTerritoryReplayPlayer.gd")
const BattleBriefingPanelLib := preload("res://BattleBriefingPanel.gd")
const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")
const BattleMapSnapshotLib := preload("res://BattleMapSnapshot.gd")
const BattleSqlReplayLib := preload("res://BattleSqlReplay.gd")
const BattleDebriefPanelLib := preload("res://BattleDebriefPanel.gd")
const BattleTileOwnershipOverlayLib := preload("res://BattleTileOwnershipOverlay.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleMapPlacementLib := preload("res://BattleMapPlacement.gd")
const GameThemeLib := preload("res://GameTheme.gd")

@onready var world: Node2D = $PlayArea/SubViewportContainer/SubViewport/World
@onready var map_camera: Camera2D = $PlayArea/SubViewportContainer/SubViewport/World/MapCamera
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var status_label: Label = $HUD/HBox/StatusLabel
@onready var phase_label: Label = $HUD/PhaseLabel
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var summary_bar: PanelContainer = $SummaryBar
@onready var blue_count_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueCount
@onready var blue_sub_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueSub
@onready var red_count_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedCount
@onready var red_sub_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedSub
@onready var summary_round_label: Label = $SummaryBar/SummaryHBox/CenterPanel/RoundLabel
@onready var play_area: Control = $PlayArea
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var hud: VBoxContainer = $HUD
@onready var debrief_overlay: PanelContainer = $DebriefOverlay
@onready var debrief_panel: BattleDebriefPanelLib = $DebriefOverlay/DebriefPanel
@onready var briefing_panel: PanelContainer = $BriefingPanel
@onready var briefing_label: Label = $BriefingPanel/BriefingLabel
@onready var resolve_progress_bar: ProgressBar = $BriefingPanel/ResolveProgressBar
@onready var pause_button: Button = $HUD/HBox/PauseButton
@onready var speed_button: Button = $HUD/HBox/SpeedButton
@onready var retreat_button: Button = $HUD/HBox/DirectiveRow/RetreatButton
@onready var focus_button: Button = $HUD/HBox/DirectiveRow/FocusButton
@onready var hold_button: Button = $HUD/HBox/DirectiveRow/HoldButton
@onready var ability_button: Button = $HUD/HBox/DirectiveRow/AbilityButton
@onready var skip_button: Button = $HUD/HBox/SkipButton

var battle_data = null
var territory_sim: BattleTerritorySimLib
var directives: BattleDirectivesLib
var phase_ctrl: BattlePhaseControllerLib
var atmosphere: BattleAtmosphereLib
var _paused: bool = false
var _speed_mult: float = 1.0
var _elapsed: float = 0.0
var _battle_finished: bool = false
var _terrain_layer: Node2D
var _tile_overlay: BattleTileOwnershipOverlayLib
var _turn_clock: float = 0.0
var _claimable_tiles: int = 0
var _friendly_tiles: int = 0
var _hostile_tiles: int = 0
var _friendly_cumulative_power: float = 0.0
var _hostile_cumulative_power: float = 0.0
var _last_turn_index: int = 0
var _engagement_march_started: bool = false
var _visuals_ready: bool = false
var _battle_resolved: bool = false
var _replay_player: BattleTerritoryReplayPlayerLib
var _replay_tape = null
var _hud_clock: float = 0.0
var _replay_timer_label: Label = null  # dynamically created in the top SummaryBar center for replay progress
var _sql_replay: bool = false
var _pending_battle_id: int = 0
var _debrief_shown: bool = false
var _pending_player_won: bool = false
var _last_replay_frame_i: int = -1
var _saved_play_area_mouse: int = -1
var _saved_hud_mouse: int = -1
var _base_camera_zoom: float = 0.28

# Threaded resolve support (for long critical battles so we don't freeze the UI)
var _resolve_thread: Thread = null
var _resolve_result_tape = null
var _is_resolving_in_thread: bool = false
var _resolve_start_time: int = 0
var _resolve_stats: Dictionary = {}   # updated by worker thread, read by main thread for UI

const HUD_UPDATE_INTERVAL := 0.2
const CAMERA_PAN_SPEED := 420.0
const CAMERA_ZOOM_STEP := 1.12
const CAMERA_FIT_MARGIN := 0.94
const OVERLAY_MAX_UPDATES_PER_SEC := 12.0
const LIVE_SIM_ROUNDS_PER_SEC := 28.0
const LIVE_OVERLAY_MAX_UPDATES_PER_SEC := 15.0
const LIVE_MAX_ROUNDS_PER_FRAME := 48
const REPLAY_AUTO_SPEED_2X_DURATION := 120.0
const REPLAY_BLEND_CACHE_BUCKETS := 4

var _overlay_clock: float = 0.0
var _replay_log_enabled: bool = false
var _replay_log_clock: float = 0.0
var _replay_log_overlay_us: int = 0
var _replay_log_overlay_calls: int = 0
var _replay_log_owners_us: int = 0
var _replay_log_owners_calls: int = 0
var _replay_wall_last_usec: int = 0
var _is_baking_replay: bool = false
var _live_battle: bool = false
var _live_overlay_clock: float = 0.0
var _live_sim_accum: float = 0.0


func _ready() -> void:
	if not RunState.is_commander_run_active() or RunState.pending_battle_node_id.is_empty():
		get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")
		return
	add_to_group("battle_viewer")
	GameTheme.apply_to_control(self)
	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.pressed.connect(_on_speed_pressed)
	retreat_button.pressed.connect(_on_retreat_pressed)
	focus_button.pressed.connect(_on_focus_pressed)
	hold_button.pressed.connect(_on_hold_pressed)
	ability_button.pressed.connect(_on_ability_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	briefing_panel.gui_input.connect(_on_briefing_click)
	_load_battle_from_run_state()
	_setup_battle()
	_setup_summary_bar()
	# For the spectator / replay watching experience we want the player to have good playback control.
	retreat_button.visible = false
	skip_button.visible = false  # shown when replay tape is ready (_setup_replay_from_variant)
	speed_button.visible = true          # Always show speed control when watching battles
	pause_button.visible = true
	_speed_mult = 1.0
	_replay_log_enabled = OS.get_environment("BATTLE_REPLAY_LOG") == "1"
	_overlay_clock = 0.0
	play_area.resized.connect(_on_play_area_resized)
	sub_viewport_container.gui_input.connect(_on_play_area_gui_input)
	call_deferred("_layout_battle_play_area", true)
	RunLog.info(
		"BattleViewer — %s territory conquest P%d vs E%d"
		% [
			battle_data.terrain_tag if battle_data else "?",
			battle_data.player_allocation if battle_data else 0,
			battle_data.enemy_allocation if battle_data else 0,
		]
	)


func _load_battle_from_run_state() -> void:
	_pending_battle_id = RunState.pending_battle_id
	_sql_replay = false
	if _pending_battle_id > 0 and _game_db() != null:
		if _game_db().has_battle_replay_data(_pending_battle_id):
			var loaded: Dictionary = BattleSqlReplayLib.load_from_db(_game_db(), _pending_battle_id)
			if loaded.get("battle_data") != null and loaded.get("tape") != null:
				battle_data = loaded["battle_data"]
				_sql_replay = true
				RunState.pending_replay_tape = loaded["tape"]
				return
	var node_id := RunState.pending_battle_node_id
	var node: Dictionary = RunState.galaxy_state.get_node(node_id) if RunState.galaxy_state else {}
	var terrain := str(node.get("terrain_tag", "open_field"))
	var mix: Dictionary = node.get("terrain_mix", {})
	var node_type := str(node.get("type", "battle"))
	var player_count: int = RunState.army_pool.get_allocation(node_id) if RunState.army_pool else 500
	var enemy_count: int = int(node.get("enemy_strength", 500))
	var seed_val := (RunState.run_seed + hash(node_id)) & 0x7FFFFFFF
	battle_data = BattleMapGeneratorLib.generate(
		seed_val, terrain, player_count, enemy_count, node_id, mix, node_type
	)


func _setup_battle() -> void:
	if battle_data == null:
		return
	phase_ctrl = BattlePhaseControllerLib.new()
	directives = BattleDirectivesLib.new()
	territory_sim = BattleTerritorySimLib.new()
	territory_sim.use_simple_water_model = true
	territory_sim.set_resolve_context("viewer")
	territory_sim.setup(
		battle_data,
		battle_data.player_allocation,
		battle_data.enemy_allocation,
		RunState.galaxy_state,
	)
	_claimable_tiles = territory_sim.claimable_tiles
	_friendly_tiles = territory_sim._tiles_owned_by_player()
	_hostile_tiles = territory_sim._tiles_owned_by_enemy()
	atmosphere = BattleAtmosphereLib.new()
	atmosphere.name = "BattleAtmosphere"
	world.add_child(atmosphere)
	atmosphere.setup(battle_data, phase_ctrl, null)
	_reset_camera_to_landing()
	briefing_label.text = (
		_format_territory_briefing()
		+ "\n\n(Loading territory field…)"
	)
	briefing_panel.visible = true
	_visuals_ready = false
	_battle_resolved = false
	call_deferred("_build_field_visuals")
	_update_hud()


func _build_field_visuals() -> void:
	if battle_data == null or territory_sim == null:
		return
	_draw_terrain()
	_tile_overlay = BattleTileOwnershipOverlayLib.new()
	_tile_overlay.name = "TileOwnershipOverlay"
	_tile_overlay.z_index = 10  # Above fluid and terrain so home base dots are visible
	world.add_child(_tile_overlay)
	_tile_overlay.setup(battle_data)

	# Wire home base markers (black dot + team ring) for both sides using the fixed spawn zones.
	# These are the permanent "home bases" that emit the power/creeper in the fluid model.
	var home_bases_for_display: Array = []
	if battle_data != null:
		if battle_data.player_spawn_zone.size.x > 1.0 and battle_data.player_spawn_zone.size.y > 1.0:
			var pg: Vector2i = _home_grid_for_side(true)
			if pg.x >= 0:
				home_bases_for_display.append({"team": 1, "x": pg.x, "y": pg.y})
		if battle_data.enemy_spawn_zone.size.x > 1.0 and battle_data.enemy_spawn_zone.size.y > 1.0:
			var eg: Vector2i = _home_grid_for_side(false)
			if eg.x >= 0:
				home_bases_for_display.append({"team": 2, "x": eg.x, "y": eg.y})
	if home_bases_for_display.size() > 0:
		_tile_overlay.set_home_bases(home_bases_for_display)

	_live_battle = _should_use_live_battle()
	if _live_battle:
		var backend_env: String = OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower()
		if backend_env == "rust" and territory_sim.enable_rust_live():
			_tile_overlay.enable_gpu_pressure_mode()
		elif backend_env != "cpu" and territory_sim.enable_gpu_live():
			_tile_overlay.enable_gpu_sim_mode(territory_sim.gpu_field)
		else:
			_tile_overlay.enable_gpu_pressure_mode()
		if resolve_progress_bar:
			resolve_progress_bar.visible = false
		briefing_label.text = (
			_format_territory_briefing()
			+ "\n\nLive conquest — click when ready.\nFluid advances in real time (WASD pan, scroll zoom)."
		)
		_sync_live_counts_from_sim()
		_update_tile_overlay_live(true)
		_visuals_ready = true
		_battle_resolved = false
		_update_briefing_label_ready()
	elif RunState.pending_replay_tape != null:
		if not _sql_replay:
			briefing_label.text = "Loading queued battle replay…"
		else:
			briefing_label.text = "Loading battle from database…"
		_use_pending_replay_tape()
		if resolve_progress_bar:
			resolve_progress_bar.visible = false
		_sync_territory_counts_from_replay()
		_update_tile_overlay_from_replay(true)
		_visuals_ready = true
		_update_briefing_label_ready()
	elif _sql_replay:
		briefing_label.text = "Loading battle from database…"
		_use_pending_replay_tape()
		if resolve_progress_bar:
			resolve_progress_bar.visible = false
		_sync_territory_counts_from_replay()
		_update_tile_overlay_from_replay(true)
		_visuals_ready = true
		_battle_resolved = true
		_update_briefing_label_ready()
	else:
		briefing_label.text = "Resolving battle simulation...\n\nPlease wait."
		_start_threaded_resolve()

	if RunState.pending_queue_auto_watch and not _live_battle:
		RunState.pending_queue_auto_watch = false
		phase_ctrl.skip_briefing()
		briefing_panel.visible = false
		_prime_engagement_display()


func _prime_engagement_display() -> void:
	if territory_sim == null or battle_data == null:
		return
	_live_overlay_clock = 0.0
	_live_sim_accum = 0.0
	if _live_battle:
		_last_turn_index = territory_sim.round_index
		_update_tile_overlay_live(true)
		_update_replay_timer()
		skip_button.visible = true
		_engagement_march_started = true
		return
	if _replay_player != null:
		_replay_player.reset()
		_replay_player.speed_mult = _speed_mult
	_last_replay_frame_i = -1
	_overlay_clock = 0.0
	_replay_wall_last_usec = 0
	_update_tile_overlay_from_replay(true)
	if _tile_overlay != null and _tile_overlay.has_method("set_power_scale"):
		var s: float = clampf(float(_last_turn_index + 4) / 95.0, 0.02, 1.0)
		_tile_overlay.set_power_scale(s)
	_update_replay_timer()
	_engagement_march_started = true


func _draw_terrain() -> void:
	if _terrain_layer:
		_terrain_layer.queue_free()
	_terrain_layer = Node2D.new()
	_terrain_layer.name = "Terrain"
	_terrain_layer.z_index = -5
	world.add_child(_terrain_layer)
	var half: Vector2 = battle_data.map_size * 0.5
	var base := ColorRect.new()
	base.color = Color(0.08, 0.1, 0.12, 1.0)
	base.size = battle_data.map_size
	base.position = -half
	_terrain_layer.add_child(base)
	for gy in range(battle_data.grid_height):
		for gx in range(battle_data.grid_width):
			var tile := ColorRect.new()
			tile.size = Vector2(battle_data.cell_size, battle_data.cell_size)
			tile.position = battle_data.cell_center(gx, gy) - Vector2(
				battle_data.cell_size * 0.5, battle_data.cell_size * 0.5
			)
			var t: int = battle_data.get_cell_terrain(gx, gy)
			var h: float = battle_data.get_tile_height(gx, gy)
			var height_tint: float = clampf((h - 0.35) * 0.35, -0.12, 0.18)
			match t:
				BattleMapDataLib.Terrain.WATER:
					tile.color = Color(0.1, 0.32, 0.52, 0.95)
				BattleMapDataLib.Terrain.MOUNTAIN:
					tile.color = Color(0.38, 0.4, 0.44, 0.96) if battle_data.is_cell_blocked(gx, gy) else Color(0.3, 0.34, 0.38, 0.9)
				BattleMapDataLib.Terrain.SAND:
					tile.color = Color(0.52, 0.44, 0.28, 0.88)
				BattleMapDataLib.Terrain.MUD:
					tile.color = Color(0.18, 0.28, 0.14, 0.88)
				_:
					tile.color = Color(0.2, 0.38, 0.18, 0.82)
			tile.color = tile.color.lightened(height_tint)
			if battle_data.cover_cells.size() > battle_data.cell_index(gx, gy):
				if battle_data.cover_cells[battle_data.cell_index(gx, gy)] > 0:
					tile.color = tile.color.lerp(Color(0.1, 0.14, 0.12, 1.0), 0.35)
			_terrain_layer.add_child(tile)


func _process(delta: float) -> void:
	if _battle_finished or battle_data == null or territory_sim == null:
		return

	if _live_battle:
		if not briefing_panel.visible and not debrief_overlay.visible:
			_pan_camera(delta)
		if not _paused:
			var step := delta * _speed_mult
			_elapsed += step
			_tick_battle(delta, step)
		_check_end_conditions()
		_update_summary_bar()
		_hud_clock += delta
		if _hud_clock >= HUD_UPDATE_INTERVAL:
			_hud_clock = 0.0
			_update_hud()
			_update_replay_timer()
		return

	# Live progress while threaded resolve / bake runs on a worker thread.
	if _is_resolving_in_thread and resolve_progress_bar:
		var stats: Dictionary = _resolve_stats
		var est_max: int = (
			territory_sim.max_rounds_limit if territory_sim else BattlePacingLib.VIEWER_MAX_ROUNDS_CAP
		)
		if str(stats.get("phase", "sim")) == "bake":
			var bake_done: int = int(stats.get("bake_done", 0))
			var bake_total: int = maxi(1, int(stats.get("bake_total", 1)))
			resolve_progress_bar.value = 92.0 + 8.0 * float(bake_done) / float(bake_total)
			if briefing_label:
				briefing_label.text = (
					"Preparing replay visuals…\n"
					+ "Frame %d / %d (one-time bake after simulation)"
				) % [bake_done, bake_total]
		else:
			var current_round: int = int(stats.get("round", territory_sim.round_index if territory_sim else 0))
			var sim_frac: float = clampf(float(current_round) / maxf(1.0, float(est_max)), 0.0, 1.0)
			resolve_progress_bar.value = sim_frac * 92.0
			var f := int(stats.get("friendly_tiles", 0))
			var h := int(stats.get("hostile_tiles", 0))
			var claim := int(stats.get("claimable", 0))
			if claim > 0 and (f > 0 or h > 0) and briefing_label:
				var f_pct := _territory_percent_from(f, claim)
				var h_pct := _territory_percent_from(h, claim)
				var p_force: int = battle_data.player_allocation if battle_data else 0
				var e_force: int = battle_data.enemy_allocation if battle_data else 0
				briefing_label.text = (
					"Simulating territory battle…\n"
					+ "Round %d / %d  •  Blue %d%% (%d tiles)  Red %d%% (%d tiles)\n"
					+ "Committed: %d vs %d troops  •  home pump ×%.2f vs ×%.2f\n"
					+ "(Ends on map dominance, decisive army lead, stall, or round cap)"
				) % [
					current_round,
					est_max,
					f_pct,
					f,
					h_pct,
					h,
					p_force,
					e_force,
					_home_spawn_multiplier(p_force),
					_home_spawn_multiplier(e_force),
				]
			elif briefing_label:
				briefing_label.text = (
					"Resolving battle simulation…\nRound %d / %d"
					% [current_round, est_max]
				)

	if not briefing_panel.visible and not debrief_overlay.visible:
		_pan_camera(delta)
	if not _paused:
		var step := delta * _speed_mult
		_elapsed += step
		_tick_battle(delta, step)
	_check_end_conditions()
	_update_summary_bar()
	_hud_clock += delta
	if _hud_clock >= HUD_UPDATE_INTERVAL:
		_hud_clock = 0.0
		_update_hud()
		_update_replay_timer()  # keep top replay timer fresh even if summary bar update is skipped


func _tick_battle(delta: float, step: float) -> void:
	phase_ctrl.tick(step, battle_data, null)
	directives.tick(step)
	if briefing_panel.visible or not phase_ctrl.turns_active():
		return
	if _live_battle:
		_tick_live_battle(delta, step)
	else:
		_tick_replay_battle(delta, step)
	if atmosphere:
		atmosphere.tick(step)


func _tick_replay_battle(delta: float, step: float) -> void:
	if _replay_player == null:
		return
	_replay_player.speed_mult = _speed_mult
	var replay_delta: float = _wall_clock_replay_delta(delta)
	var play_info: Dictionary = _replay_player.tick(replay_delta)
	_last_turn_index = int(play_info.get("round", _last_turn_index))
	_friendly_tiles = int(play_info.get("friendly_tiles", _friendly_tiles))
	_hostile_tiles = int(play_info.get("hostile_tiles", _hostile_tiles))
	_friendly_cumulative_power = float(play_info.get("friendly_power_total", _friendly_cumulative_power))
	_hostile_cumulative_power = float(play_info.get("hostile_power_total", _hostile_cumulative_power))
	if _replay_tape is BattleTerritoryTapeLib and (_replay_tape as BattleTerritoryTapeLib).has_baked_display():
		_update_tile_overlay_from_replay(false)
	else:
		_overlay_clock += replay_delta
		var overlay_interval: float = 1.0 / OVERLAY_MAX_UPDATES_PER_SEC
		if _overlay_clock >= overlay_interval:
			_overlay_clock = 0.0
			_update_tile_overlay_from_replay(true)
	_replay_log_tick(delta)


func _tick_live_battle(delta: float, step: float) -> void:
	if territory_sim == null or territory_sim.finished:
		if territory_sim != null and territory_sim.finished and not _battle_resolved:
			_battle_resolved = true
		return
	_live_sim_accum += step * LIVE_SIM_ROUNDS_PER_SEC
	var rounds_to_run: int = mini(LIVE_MAX_ROUNDS_PER_FRAME, int(_live_sim_accum))
	_live_sim_accum -= float(rounds_to_run)
	if rounds_to_run < 1:
		rounds_to_run = 1
	var cap: int = territory_sim.max_rounds_limit
	for _i in range(rounds_to_run):
		if territory_sim.finished or territory_sim.round_index >= cap:
			break
		territory_sim.advance_round()
	_sync_live_counts_from_sim()
	_live_overlay_clock += delta
	var overlay_interval: float = 1.0 / LIVE_OVERLAY_MAX_UPDATES_PER_SEC
	if _live_overlay_clock >= overlay_interval:
		_live_overlay_clock = 0.0
		_update_tile_overlay_live(false)
	if territory_sim.finished:
		_battle_resolved = true
		_update_tile_overlay_live(true)


func _should_use_live_battle() -> bool:
	if _sql_replay:
		return false
	if RunState.pending_replay_tape != null:
		return false
	return true


func _sync_live_counts_from_sim() -> void:
	if territory_sim == null:
		return
	_last_turn_index = territory_sim.round_index
	if territory_sim.tile_control != null:
		_friendly_tiles = territory_sim.tile_control.friendly_tiles
		_hostile_tiles = territory_sim.tile_control.hostile_tiles
		var pf: PackedFloat32Array = territory_sim.tile_control.pressure_friendly
		var ph: PackedFloat32Array = territory_sim.tile_control.pressure_hostile
		var totals: Vector2 = BattleTileFluidFieldLib.cumulative_power_totals(pf, ph)
		_friendly_cumulative_power = totals.x
		_hostile_cumulative_power = totals.y


func _update_tile_overlay_live(force: bool) -> void:
	if _tile_overlay == null or territory_sim == null or territory_sim.tile_control == null:
		return
	if not force and _last_replay_frame_i == _last_turn_index:
		return
	_last_replay_frame_i = _last_turn_index
	var tc := territory_sim.tile_control
	if territory_sim.use_gpu_for_live() and territory_sim.gpu_field != null:
		if not territory_sim.gpu_field.export_state_to_tile_control(tc):
			return
	_tile_overlay.apply_live_state(tc.owners, tc.pressure_friendly, tc.pressure_hostile)


func _check_end_conditions() -> void:
	if phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.FINISHED:
		return
	if briefing_panel.visible or not phase_ctrl.turns_active():
		return
	if _live_battle:
		if not _battle_resolved or territory_sim == null or not territory_sim.finished:
			return
		var live_won: bool = bool(territory_sim.get_result().get("player_won", false))
		if phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT:
			phase_ctrl.begin_resolution()
		_show_end_debrief(live_won)
		return
	if _battle_resolved:
		if not _is_replay_finished():
			return
		var replay_won: bool = _replay_result().get("player_won", false)
		if phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT:
			phase_ctrl.begin_resolution()
		_show_end_debrief(replay_won)
		return


func _show_end_debrief(player_won: bool) -> void:
	if _debrief_shown or _battle_finished:
		return
	_debrief_shown = true
	_pending_player_won = player_won
	_paused = true
	if summary_bar:
		summary_bar.visible = false
	var pct: int = _territory_percent(_friendly_tiles) if _claimable_tiles > 0 else 0
	var summary_text: String = (
		"%s — held %d%% of claimable territory (%d / %d tiles)."
		% [
			"Victory" if player_won else "Defeat",
			pct,
			_friendly_tiles,
			_claimable_tiles,
		]
	)
	briefing_panel.visible = false
	if play_area != null:
		_saved_play_area_mouse = play_area.mouse_filter
		play_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hud != null:
		_saved_hud_mouse = hud.mouse_filter
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.visible = false
	if debrief_overlay:
		debrief_overlay.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		debrief_overlay.z_index = 200
		move_child(debrief_overlay, get_child_count() - 1)
		debrief_overlay.visible = true
		debrief_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if debrief_panel:
		debrief_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		debrief_panel.show_report(
			player_won, {}, summary_text, Callable(self, "_on_debrief_continue")
		)
		var btn: Button = debrief_panel.get_node_or_null("Margin/VBox/ContinueButton") as Button
		if btn:
			btn.grab_focus()


func _on_debrief_continue() -> void:
	if play_area != null and _saved_play_area_mouse >= 0:
		play_area.mouse_filter = _saved_play_area_mouse
		_saved_play_area_mouse = -1
	if hud != null:
		if _saved_hud_mouse >= 0:
			hud.mouse_filter = _saved_hud_mouse
			_saved_hud_mouse = -1
		hud.visible = true
	if debrief_overlay:
		debrief_overlay.visible = false
	_finish_battle(_pending_player_won)


func _finish_battle(player_won: bool, retreat: bool = false) -> void:
	if _battle_finished:
		return
	_battle_finished = true
	phase_ctrl.current_phase = BattlePhaseControllerLib.Phase.FINISHED
	var node_id: String = battle_data.node_id
	var player_losses: int = 0
	var enemy_losses: int = 0
	if territory_sim != null:
		player_losses = territory_sim.allocation_losses(battle_data.player_allocation, true)
		enemy_losses = territory_sim.allocation_losses(battle_data.enemy_allocation, false)
	if retreat:
		player_losses += int(battle_data.player_allocation * 0.15)
		player_won = false
	var queue_entry: Dictionary = RunState.find_turn_battle_entry(node_id)
	if not queue_entry.is_empty():
		RunState.apply_turn_battle_entry(queue_entry)
	elif not RunState.return_to_battle_queue_after_view:
		TurnResolverLib.apply_battle_result(
			RunState.galaxy_state,
			RunState.army_pool,
			node_id,
			player_won,
			player_losses,
			enemy_losses,
		)
	RunState.apply_commander_building_recruit()
	RunState.pending_battle_node_id = ""
	RunState.pending_battle_id = 0
	RunState.pending_live_battle = false
	RunState.pending_replay_tape = null
	RunState.save_commander_run()
	RunState.last_turn_summary = (
		"%s — %d%% territory held at end."
		% ["Victory" if player_won else "Defeat", _territory_percent(_friendly_tiles)]
	)
	if RunState.return_to_battle_queue_after_view:
		RunState.return_to_battle_queue_after_view = false
		get_tree().change_scene_to_file("res://BattleTurnQueueScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")


func _setup_summary_bar() -> void:
	if summary_bar == null:
		return
	summary_bar.add_theme_stylebox_override("panel", GameThemeLib.make_panel_style())
	summary_bar.visible = false

	# Make the top summary titles shorter and clearer for territory conquest replays.
	var blue_title: Label = summary_bar.get_node_or_null("SummaryHBox/BluePanel/BlueTitle")
	if blue_title:
		blue_title.text = "BLUE — CUMULATIVE POWER"
	var red_title: Label = summary_bar.get_node_or_null("SummaryHBox/RedPanel/RedTitle")
	if red_title:
		red_title.text = "RED — CUMULATIVE POWER"

	_create_replay_timer_label()
	_update_summary_bar()


func _create_replay_timer_label() -> void:
	if _replay_timer_label != null or summary_bar == null:
		return
	var center: VBoxContainer = summary_bar.get_node_or_null("SummaryHBox/CenterPanel")
	if center == null:
		return
	_replay_timer_label = Label.new()
	_replay_timer_label.name = "ReplayTimerLabel"
	_replay_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_replay_timer_label.add_theme_font_size_override("font_size", 11)
	_replay_timer_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.80, 0.95))
	_replay_timer_label.text = "0:00 / 0:00"
	center.add_child(_replay_timer_label)


func _format_replay_time(secs: float) -> String:
	var s: int = maxi(0, int(secs))
	return "%d:%02d" % [s / 60, s % 60]


func _update_replay_timer() -> void:
	if _replay_timer_label == null:
		return
	if _live_battle:
		_replay_timer_label.visible = true
		var speed_tag: String = "x%.0f" % _speed_mult if _speed_mult >= 1.0 else "x%.1f" % _speed_mult
		_replay_timer_label.text = "Round %d  ·  live %s" % [_last_turn_index, speed_tag]
		return
	if _replay_player == null or _replay_tape == null:
		_replay_timer_label.visible = false
		return
	_replay_timer_label.visible = true
	var cur: float = _replay_player.playback_time
	var tot: float = _replay_tape.total_duration()
	var speed_tag: String = "x%.0f" % _speed_mult if _speed_mult >= 1.0 else "x%.1f" % _speed_mult
	_replay_timer_label.text = "%s / %s (%s)" % [
		_format_replay_time(cur),
		_format_replay_time(tot),
		speed_tag,
	]


func _update_summary_bar() -> void:
	if summary_bar == null:
		return
	var show_bar: bool = (
		_visuals_ready
		and not briefing_panel.visible
		and phase_ctrl != null
		and phase_ctrl.turns_active()
	)
	summary_bar.visible = show_bar
	if not show_bar:
		return
	blue_count_label.text = _format_cumulative_power(_friendly_cumulative_power)
	red_count_label.text = _format_cumulative_power(_hostile_cumulative_power)
	blue_sub_label.text = "%d%% map  ·  %d tiles" % [
		_territory_percent(_friendly_tiles),
		_friendly_tiles,
	]
	red_sub_label.text = "%d%% map  ·  %d tiles" % [
		_territory_percent(_hostile_tiles),
		_hostile_tiles,
	]
	summary_round_label.text = "Round %d" % _last_turn_index

	# Keep the replay timer (playback progress) in sync at the top center.
	_update_replay_timer()


func _update_hud() -> void:
	if battle_data == null:
		return
	var play_tag: String = ""
	if _live_battle:
		play_tag = " [live]"
	elif _battle_resolved:
		play_tag = " [replay]"
	phase_label.text = "Phase: %s | Round %d%s" % [phase_ctrl.phase_name(), _last_turn_index, play_tag]
	objective_label.text = "Conquer all reachable tiles"
	status_label.text = (
		"%s | Map: Blue %d%%  Red %d%%  |  %.0fs  |  %s"
		% [
			battle_data.terrain_tag.capitalize(),
			_territory_percent(_friendly_tiles),
			_territory_percent(_hostile_tiles),
			_elapsed,
			"PAUSED" if _paused else ("x%.1f" % _speed_mult if _speed_mult < 1.0 else "x%.0f" % _speed_mult),
		]
	)

	# Keep the speed button label in sync so the player always knows the current playback rate.
	if speed_button:
		speed_button.text = "▶ x%.1f" % _speed_mult if _speed_mult < 1.0 else "▶ x%.0f" % _speed_mult


func _fluid_image_has_visible_pixels(img: Image) -> bool:
	if img == null:
		return false
	var used: Rect2i = img.get_used_rect()
	return used.size.x > 0 and used.size.y > 0


func _format_cumulative_power(total: float) -> String:
	if total >= 1_000_000.0:
		return "%.2fM" % (total / 1_000_000.0)
	if total >= 10_000.0:
		return "%.0fK" % (total / 1_000.0)
	if total >= 1_000.0:
		return "%.1fK" % (total / 1_000.0)
	return "%.0f" % total


func _territory_percent(tiles: int) -> int:
	return _territory_percent_from(tiles, _claimable_tiles)


func _territory_percent_from(tiles: int, claimable: int) -> int:
	if claimable <= 0 or tiles <= 0:
		return 0
	var pct: int = int(round(float(tiles) * 100.0 / float(claimable)))
	# One home tile on a 6k+ map rounds to 0%; show at least 1% when a side holds ground.
	return maxi(1, pct)


func _home_spawn_multiplier(committed: int) -> float:
	return 1.0 + float(maxi(1, committed)) * BattleTileControlLib.SPAWN_MULTIPLIER_PER_UNIT


func _format_territory_briefing() -> String:
	return (
		"Territory conquest — %s\nForces: %d vs %d\nClaimable tiles: %d"
		% [
			battle_data.terrain_tag.capitalize() if battle_data else "?",
			battle_data.player_allocation if battle_data else 0,
			battle_data.enemy_allocation if battle_data else 0,
			_claimable_tiles,
		]
	)


func _on_briefing_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not _visuals_ready:
			return
		if not _live_battle and not _battle_resolved:
			return
		phase_ctrl.skip_briefing()
		briefing_panel.visible = false
		_prime_engagement_display()


func _on_pause_pressed() -> void:
	_paused = not _paused


func _on_speed_pressed() -> void:
	# Spectator-friendly speeds: allow slow-mo for appreciating the "water" flow,
	# then faster options for skimming long battles.
	if _speed_mult < 0.6:
		_speed_mult = 1.0
	elif _speed_mult < 1.5:
		_speed_mult = 2.0
	elif _speed_mult < 3.0:
		_speed_mult = 4.0
	elif _speed_mult < 6.0:
		_speed_mult = 8.0
	else:
		_speed_mult = 0.5  # back to slow-mo to study interesting fronts


func _on_retreat_pressed() -> void:
	pass


func _on_focus_pressed() -> void:
	directives.request_focus_cp("")


func _on_hold_pressed() -> void:
	directives.request_hold_line()


func _on_ability_pressed() -> void:
	directives.request_commander_ability(RunState.get_commander_profile())


func _on_skip_pressed() -> void:
	if _live_battle:
		if territory_sim == null:
			return
		var cap: int = territory_sim.max_rounds_limit
		var safety: int = 0
		while not territory_sim.finished and territory_sim.round_index < cap and safety < 4000:
			territory_sim.advance_round()
			safety += 1
		_battle_resolved = true
		_sync_live_counts_from_sim()
		_update_tile_overlay_live(true)
		_check_end_conditions()
		return
	if _replay_player == null or _replay_tape == null:
		return
	_replay_player.playback_time = _replay_tape.total_duration()
	_replay_player.finished = true
	_update_tile_overlay_from_replay(true)
	_check_end_conditions()


func _on_play_area_resized() -> void:
	_layout_battle_play_area(false)


func _layout_battle_play_area(fit_camera: bool) -> void:
	if play_area == null or sub_viewport == null or sub_viewport_container == null:
		return
	var top: float = 8.0
	if summary_bar:
		top = summary_bar.size.y + 12.0
	var bottom_h: float = 8.0
	if hud:
		bottom_h = hud.size.y + 12.0
	play_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_area.offset_left = 0.0
	play_area.offset_right = 0.0
	play_area.offset_top = top
	play_area.offset_bottom = -bottom_h
	var play_size: Vector2 = play_area.size
	if play_size.x < 8.0 or play_size.y < 8.0:
		return
	sub_viewport_container.stretch = false
	sub_viewport.size = Vector2i(maxi(int(play_size.x), 1), maxi(int(play_size.y), 1))
	world.position = play_size * 0.5
	if fit_camera:
		_fit_camera_to_map()


func _fit_camera_to_map() -> void:
	if map_camera == null or battle_data == null or sub_viewport == null:
		return
	var vp: Vector2 = Vector2(sub_viewport.size)
	if vp.x < 1.0 or vp.y < 1.0:
		return
	var scale_factor: float = (
		minf(vp.x / battle_data.map_size.x, vp.y / battle_data.map_size.y) * CAMERA_FIT_MARGIN
	)
	_base_camera_zoom = maxf(0.05, scale_factor)
	map_camera.position = Vector2.ZERO
	map_camera.offset = Vector2.ZERO
	map_camera.zoom = Vector2(_base_camera_zoom, _base_camera_zoom)
	map_camera.enabled = true
	map_camera.make_current()


func _camera_zoom_limits() -> Vector2:
	var lo: float = maxf(0.05, _base_camera_zoom * 0.2)
	var hi: float = maxf(lo + 0.01, _base_camera_zoom * 5.0)
	return Vector2(lo, hi)


func _apply_camera_zoom_step(zoom_in: bool) -> void:
	if map_camera == null:
		return
	var limits: Vector2 = _camera_zoom_limits()
	var z: Vector2 = map_camera.zoom
	if zoom_in:
		z *= CAMERA_ZOOM_STEP
	else:
		z /= CAMERA_ZOOM_STEP
	map_camera.zoom = Vector2(
		clampf(z.x, limits.x, limits.y),
		clampf(z.y, limits.x, limits.y),
	)


func _on_play_area_gui_input(event: InputEvent) -> void:
	if _battle_finished or map_camera == null:
		return
	if briefing_panel.visible or debrief_overlay.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_camera_zoom_step(true)
			play_area.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_camera_zoom_step(false)
			play_area.accept_event()


func _reset_camera_to_landing() -> void:
	_fit_camera_to_map()


func _pan_camera(step: float) -> void:
	if map_camera == null or briefing_panel.visible:
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		pan.x += 1.0
	if pan == Vector2.ZERO:
		return
	var zoom_scale: float = maxf(0.15, map_camera.zoom.x)
	map_camera.position += pan.normalized() * CAMERA_PAN_SPEED * step / zoom_scale


func _use_pending_replay_tape() -> void:
	var pending = RunState.pending_replay_tape
	RunState.pending_replay_tape = null
	if pending == null:
		return
	_setup_replay_from_variant(pending)
	_battle_resolved = true
	RunLog.info("Territory replay loaded — %d frames" % [_replay_frame_count()])
	_update_replay_timer()  # show the timer immediately on load


func _preresolve_battle_for_replay() -> void:
	if territory_sim == null or battle_data == null:
		return
	# Fixed reasonable stride for the viewer fallback.
	# Replay timing should reflect the actual simulation length.
	_setup_replay_from_variant(territory_sim.build_replay_tape(-1, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE))
	_battle_resolved = true
	RunLog.info(
		"Territory preresolved — %d frames, %.1f ms"
		% [_replay_frame_count(), float(_replay_tape.resolve_ms if _replay_tape else 0.0)]
	)


# === THREADED RESOLVE (non-blocking for long critical battles) ===

func _start_threaded_resolve() -> void:
	if _is_resolving_in_thread or _resolve_thread != null:
		return

	_is_resolving_in_thread = true
	_resolve_start_time = Time.get_ticks_msec()
	_resolve_result_tape = null

	# Show proper loading state
	briefing_label.text = "Resolving battle simulation (critical fights on mountain can take a while)..."
	if resolve_progress_bar:
		resolve_progress_bar.visible = true
		resolve_progress_bar.value = 0.0

	_resolve_thread = Thread.new()
	_resolve_thread.start(Callable(self, "_threaded_resolve_worker"))


func _threaded_resolve_worker() -> void:
	# This runs on a background thread. Do NOT touch any Nodes or the scene tree here.
	if territory_sim == null or battle_data == null:
		call_deferred("_on_resolve_thread_finished")
		return

	var sim = territory_sim
	var tape := BattleTerritoryTapeLib.new()
	# Fixed stride for the viewer fallback.
	# We want the replay length to reflect how many simulation steps the battle actually took.
	tape.record_stride = BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE
	tape.battle_data = battle_data

	var t0 := Time.get_ticks_usec()

	# Record initial state
	_record_territory_tape_frame(tape, sim)

	var cap: int = sim.max_rounds_limit
	var last_recorded: int = sim.round_index

	while not sim.finished and sim.round_index < cap:
		sim.advance_round()

		# Publish live stats for the UI (main thread reads this)
		if sim.round_index % 8 == 0 or sim.finished:
			var friendly := 0
			var hostile := 0
			var claim: int = sim.claimable_tiles if "claimable_tiles" in sim else 0

			# Try public-ish methods first, then fall back to tile_control
			if sim.tile_control != null:
				friendly = sim.tile_control.friendly_tiles
				hostile = sim.tile_control.hostile_tiles
			else:
				friendly = sim._tiles_owned_by_player()
				hostile = sim._tiles_owned_by_enemy()

			_resolve_stats = {
				"round": sim.round_index,
				"friendly_tiles": friendly,
				"hostile_tiles": hostile,
				"claimable": claim,
				"finished": sim.finished,
			}

		if sim.finished or (sim.round_index - last_recorded) >= tape.record_stride:
			_record_territory_tape_frame(tape, sim)
			last_recorded = sim.round_index

	# Final frame if needed
	if tape.frame_count() == 0 or (tape.get_frame(tape.frame_count()-1).get("round", -1) != sim.round_index):
		_record_territory_tape_frame(tape, sim)

	tape.result = sim.get_result() if sim.has_method("get_result") else {}
	tape.resolve_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	tape.rebuild_segment_timing()

	# Bake replay images on the worker so the main thread does not freeze at ~92% progress.
	_resolve_stats = {
		"phase": "bake",
		"bake_done": 0,
		"bake_total": tape.frame_count(),
		"finished": false,
	}
	tape.bake_display_frames(battle_data, _resolve_stats)

	_resolve_result_tape = tape
	_resolve_stats["finished"] = true

	call_deferred("_on_resolve_thread_finished")


func _on_resolve_thread_finished() -> void:
	if _resolve_thread:
		_resolve_thread.wait_to_finish()
		_resolve_thread = null

	_is_resolving_in_thread = false

	var elapsed := Time.get_ticks_msec() - _resolve_start_time
	RunLog.info("BattleViewer: Threaded on-demand resolve finished in %.1f seconds" % (elapsed / 1000.0))

	if _resolve_result_tape != null:
		var tape_result: Dictionary = _resolve_result_tape.result if _resolve_result_tape.result else {}
		RunLog.info(
			"Territory sim ended: reason=%s rounds=%d frames=%d replay_s=%.1f"
			% [
				str(tape_result.get("end_reason", "?")),
				int(tape_result.get("turns", 0)),
				_replay_frame_count(),
				_resolve_result_tape.total_duration() if _resolve_result_tape else 0.0,
			]
		)
		_setup_replay_from_variant(_resolve_result_tape)
		_battle_resolved = true

	# Hide progress UI
	if resolve_progress_bar:
		resolve_progress_bar.visible = false

	# Continue normal viewer setup that was waiting for the resolve
	_sync_territory_counts_from_replay()
	_update_tile_overlay_from_replay(true)
	_visuals_ready = true
	_update_briefing_label_ready()
	_update_replay_timer()

	if RunState.pending_queue_auto_watch:
		RunState.pending_queue_auto_watch = false
		phase_ctrl.skip_briefing()
		briefing_panel.visible = false
		_prime_engagement_display()

	_resolve_result_tape = null


func _record_territory_tape_frame(tape: BattleTerritoryTapeLib, sim: BattleTerritorySimLib) -> void:
	if tape == null or sim == null or sim.tile_control == null:
		return
	var stride: int = maxi(1, tape.record_stride)
	var include_pressure: bool = (
		sim.finished
		or sim.round_index % (stride * 2) == 0
	)
	var pf: PackedFloat32Array = PackedFloat32Array()
	var ph: PackedFloat32Array = PackedFloat32Array()
	if include_pressure:
		pf = sim.tile_control.pressure_friendly
		ph = sim.tile_control.pressure_hostile
	tape.record_frame(
		sim.round_index,
		sim.tile_control.owners,
		pf,
		ph,
		sim.tile_control.friendly_tiles,
		sim.tile_control.hostile_tiles,
	)


func _setup_replay_from_variant(tape_source) -> void:
	if tape_source is BattleTerritoryTapeLib:
		_replay_tape = tape_source
	elif typeof(tape_source) == TYPE_DICTIONARY:
		_replay_tape = BattleTerritoryTapeLib.new()
		_replay_tape.load_from_dictionary(tape_source)
	else:
		_replay_tape = tape_source
	_replay_tape.battle_data = battle_data
	_replay_tape.rebuild_segment_timing()
	_ensure_baked_display_frames()
	_last_replay_frame_i = -1
	_overlay_clock = 0.0
	_replay_wall_last_usec = 0
	_replay_player = BattleTerritoryReplayPlayerLib.new(_replay_tape)
	_apply_replay_default_speed()
	skip_button.visible = _battle_resolved


func _apply_replay_default_speed() -> void:
	if _replay_tape == null:
		return
	var tot: float = _replay_tape.total_duration()
	if tot > REPLAY_AUTO_SPEED_2X_DURATION:
		_speed_mult = 2.0
	else:
		_speed_mult = 1.0
	if speed_button:
		speed_button.text = "▶ x%.0f" % _speed_mult if _speed_mult >= 1.0 else "▶ x%.1f" % _speed_mult


func _wall_clock_replay_delta(fallback_delta: float) -> float:
	var now: int = Time.get_ticks_usec()
	var dt: float = fallback_delta
	if _replay_wall_last_usec > 0:
		dt = float(now - _replay_wall_last_usec) / 1000000.0
	_replay_wall_last_usec = now
	return clampf(dt, 0.0, 0.25)


func _ensure_baked_display_frames() -> void:
	if _replay_tape == null or battle_data == null:
		return
	if not _replay_tape is BattleTerritoryTapeLib:
		return
	var tape: BattleTerritoryTapeLib = _replay_tape
	if tape.has_baked_display():
		return
	_is_baking_replay = true
	_is_resolving_in_thread = true
	if briefing_label:
		briefing_label.text = "Preparing replay visuals…"
	if resolve_progress_bar:
		resolve_progress_bar.visible = true
		resolve_progress_bar.value = 92.0
	var bake_progress: Dictionary = {"phase": "bake", "bake_done": 0, "bake_total": tape.frame_count()}
	_resolve_stats = bake_progress
	tape.bake_display_frames(battle_data, bake_progress)
	_is_baking_replay = false
	_is_resolving_in_thread = false
	if resolve_progress_bar:
		resolve_progress_bar.visible = false
	RunLog.info(
		"Territory replay baked %d frames in %.1f ms"
		% [tape.frame_count(), tape.bake_ms]
	)


func _update_tile_overlay_from_replay(force: bool = false) -> void:
	if _tile_overlay == null or _replay_tape == null or _replay_player == null:
		return
	var seg: Dictionary = _replay_tape.segment_at_playback_time(_replay_player.playback_time)
	var fi: int = int(seg.get("from_i", 0))
	var ti: int = int(seg.get("to_i", fi))
	var blend: float = float(seg.get("blend", 0.0))
	var cache_key: int = (
		fi * 10000 + ti * 10 + int(blend * float(REPLAY_BLEND_CACHE_BUCKETS))
	)
	if not force and cache_key == _last_replay_frame_i:
		return
	var t0: int = Time.get_ticks_usec() if _replay_log_enabled else 0
	_last_replay_frame_i = cache_key
	if _replay_tape is BattleTerritoryTapeLib:
		var tape_baked: BattleTerritoryTapeLib = _replay_tape
		if tape_baked.has_baked_display():
			var baked_img: Image = tape_baked.get_baked_image_for_segment(fi, ti, blend)
			if baked_img != null and _fluid_image_has_visible_pixels(baked_img):
				_tile_overlay.apply_prebuilt_image(baked_img)
				if _replay_log_enabled:
					_replay_log_overlay_us += Time.get_ticks_usec() - t0
					_replay_log_overlay_calls += 1
				return
	if _replay_tape is BattleTerritoryTapeLib:
		var tape: BattleTerritoryTapeLib = _replay_tape
		var p0: Dictionary = tape.pressures_at_frame(fi)
		var pf_a: PackedFloat32Array = p0.get("f", PackedFloat32Array())
		var ph_a: PackedFloat32Array = p0.get("h", PackedFloat32Array())
		if not pf_a.is_empty() and not ph_a.is_empty():
			var pf: PackedFloat32Array = pf_a
			var ph: PackedFloat32Array = ph_a
			if ti != fi and blend > 0.001:
				var p1: Dictionary = tape.pressures_at_frame(ti)
				var pf_b: PackedFloat32Array = p1.get("f", PackedFloat32Array())
				var ph_b: PackedFloat32Array = p1.get("h", PackedFloat32Array())
				if not pf_b.is_empty() and not ph_b.is_empty():
					const CodecLib := preload("res://BattleTilePressureCodec.gd")
					pf = CodecLib.lerp_arrays(pf_a, pf_b, blend)
					ph = CodecLib.lerp_arrays(ph_a, ph_b, blend)
			_tile_overlay.apply_powers(pf, ph)
			if _replay_log_enabled:
				_replay_log_overlay_us += Time.get_ticks_usec() - t0
				_replay_log_overlay_calls += 1
			return
		var owners: PackedByteArray = BattleTerritoryTapeLib.owners_from_frame_at_index(tape, fi)
		if not owners.is_empty():
			_tile_overlay.apply_owners(
				BattleTileFluidFieldLib.soften_owners_for_display(battle_data, owners)
			)
		if _replay_log_enabled:
			_replay_log_overlay_us += Time.get_ticks_usec() - t0
			_replay_log_overlay_calls += 1
		return
	var frame: Dictionary = _replay_tape.get_frame(fi)
	if frame.is_empty():
		return
	var owners_legacy: PackedByteArray = _owners_from_tape_frame(frame)
	if not owners_legacy.is_empty():
		_tile_overlay.apply_owners(owners_legacy)
	if _replay_log_enabled:
		_replay_log_overlay_us += Time.get_ticks_usec() - t0
		_replay_log_overlay_calls += 1


func _replay_log_tick(delta: float) -> void:
	if not _replay_log_enabled or _replay_player == null:
		return
	_replay_log_clock += delta
	if _replay_log_clock < 1.0:
		return
	_replay_log_clock = 0.0
	var avg_overlay: float = 0.0
	if _replay_log_overlay_calls > 0:
		avg_overlay = float(_replay_log_overlay_us) / float(_replay_log_overlay_calls) / 1000.0
	var avg_owners: float = 0.0
	if _replay_log_owners_calls > 0:
		avg_owners = float(_replay_log_owners_us) / float(_replay_log_owners_calls) / 1000.0
	RunLog.info(
		"BattleReplay playback=%.1fs overlay_avg=%.2fms owners_avg=%.2fms calls=%d"
		% [
			_replay_player.playback_time,
			avg_overlay,
			avg_owners,
			_replay_log_overlay_calls,
		]
	)
	_replay_log_overlay_us = 0
	_replay_log_overlay_calls = 0
	_replay_log_owners_us = 0
	_replay_log_owners_calls = 0


func _owners_from_tape_frame(frame: Dictionary) -> PackedByteArray:
	if frame.is_empty():
		return PackedByteArray()
	if _replay_tape is BattleTerritoryTapeLib:
		return BattleTerritoryTapeLib.owners_from_frame(frame)
	return BattleReplayTapeLib.owners_from_frame(frame)


func _sync_territory_counts_from_replay() -> void:
	if _replay_tape == null:
		return
	var f0: Dictionary = _replay_tape.get_frame(0)
	if f0.is_empty():
		return
	_friendly_tiles = int(f0.get("friendly_tiles", _friendly_tiles))
	_hostile_tiles = int(f0.get("hostile_tiles", _hostile_tiles))
	_sync_cumulative_power_from_frame(0)
	if _claimable_tiles <= 0 and territory_sim != null:
		_claimable_tiles = territory_sim.claimable_tiles


func _sync_cumulative_power_from_frame(frame_index: int) -> void:
	if _replay_tape == null or not _replay_tape is BattleTerritoryTapeLib:
		return
	var tape: BattleTerritoryTapeLib = _replay_tape
	if frame_index < 0 or frame_index >= tape.frame_count():
		return
	var pressures: Dictionary = tape.pressures_at_frame(frame_index)
	var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
	var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
	var totals: Vector2 = BattleTileFluidFieldLib.cumulative_power_totals(pf, ph)
	_friendly_cumulative_power = totals.x
	_hostile_cumulative_power = totals.y


func _replay_frame_count() -> int:
	if _replay_tape != null:
		return _replay_tape.frame_count()
	return 0


func _is_replay_finished() -> bool:
	if _replay_player != null:
		return _replay_player.finished
	return true


func _replay_result() -> Dictionary:
	if _replay_tape != null:
		return _replay_tape.result
	return {}


func _update_briefing_label_ready() -> void:
	var extra: String = ""
	if _live_battle:
		extra = "\n\nClick to begin live conquest."
	elif _battle_resolved and _replay_tape != null:
		var src: String = "SQLite replay" if _sql_replay else "territory sim"
		extra = (
			"\n\nConquest resolved (%.0f ms, %s). Click to watch fluid spread."
			% [float(_replay_tape.resolve_ms if _replay_tape else 0.0), src]
		)
	elif not _battle_resolved:
		extra = "\n\n(Resolving conquest…)"
	briefing_label.text = _format_territory_briefing() + extra


func _home_grid_for_side(player: bool) -> Vector2i:
	if battle_data == null:
		return Vector2i(-1, -1)
	var cached: Vector2i = (
		battle_data.player_home_grid if player else battle_data.enemy_home_grid
	)
	if cached.x >= 0 and battle_data.is_land_cell(cached.x, cached.y):
		return cached
	var zone: Rect2 = (
		battle_data.player_spawn_zone if player else battle_data.enemy_spawn_zone
	)
	return BattleMapPlacementLib.resolve_home_base_cell(battle_data, zone, player)


func _game_db():
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root.get_node_or_null("GameDatabase")
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _battle_finished or map_camera == null:
		return
	if briefing_panel.visible or debrief_overlay.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_camera_zoom_step(true)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_camera_zoom_step(false)
