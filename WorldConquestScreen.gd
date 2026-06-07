extends Control

const CFG := preload("res://WorldConquestConfig.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTileOwnershipOverlayLib := preload("res://BattleTileOwnershipOverlay.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const GameThemeLib := preload("res://GameTheme.gd")
const EarthGlobeMapLib := preload("res://EarthGlobeMap.gd")

@onready var globe_map: EarthGlobeMapLib = $PlayArea/SubViewportContainer/SubViewport/GlobeMap
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var play_area: Control = $PlayArea
@onready var summary_bar: PanelContainer = $SummaryBar
@onready var blue_count_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueCount
@onready var blue_sub_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueSub
@onready var red_count_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedCount
@onready var red_sub_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedSub
@onready var time_label: Label = $SummaryBar/SummaryHBox/CenterPanel/TimeLabel
@onready var supply_label: Label = $SummaryBar/SummaryHBox/CenterPanel/SupplyLabel
@onready var status_label: Label = $HUD/HBox/StatusLabel
@onready var pause_button: Button = $HUD/HBox/PauseButton
@onready var speed_button: Button = $HUD/HBox/SpeedButton
@onready var spawner_button: Button = $HUD/HBox/SpawnerButton
@onready var back_button: Button = $TopBar/BackButton
@onready var build_hint_label: Label = $HUD/BuildHintLabel
@onready var end_overlay: PanelContainer = $EndOverlay
@onready var end_label: Label = $EndOverlay/Center/EndLabel

var battle_data = null
var territory_sim: BattleTerritorySimLib
var _tile_overlay: BattleTileOwnershipOverlayLib
var _claimable_tiles: int = 0
var _friendly_tiles: int = 0
var _hostile_tiles: int = 0
var _supply: float = 0.0
var _sim_time: float = 0.0
var _paused: bool = false
var _speed_mult: float = 1.0
var _overlay_clock: float = 0.0
var _battle_finished: bool = false
var _build_spawner_active: bool = false
var _last_overlay_step: int = -1
var _next_structure_id: int = 1
var _build_hint_clock: float = 0.0
var _hud_clock: float = 0.0
var _player_home: Vector2i = Vector2i(-1, -1)
var _enemy_home: Vector2i = Vector2i(-1, -1)
var _orbit_drag: bool = false


func _ready() -> void:
	GameTheme.apply_to_control(self)
	_style_summary_hud()
	back_button.pressed.connect(_on_back_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.pressed.connect(_on_speed_pressed)
	spawner_button.toggled.connect(_on_spawner_toggled)
	end_overlay.visible = false
	_supply = float(CFG.STARTING_SUPPLY)
	var seed_val: int = RunState.run_seed if RunState.run_seed != 0 else randi() & 0x7FFFFFFF
	battle_data = EarthMapGeneratorLib.generate(seed_val)
	territory_sim = BattleTerritorySimLib.new()
	territory_sim.use_simple_water_model = true
	territory_sim.set_resolve_context("world_conquest")
	territory_sim.setup(battle_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	_claimable_tiles = territory_sim.claimable_tiles
	_player_home = battle_data.player_home_grid
	_enemy_home = battle_data.enemy_home_grid
	_sync_counts()
	play_area.resized.connect(_on_play_area_resized)
	sub_viewport_container.gui_input.connect(_on_play_area_gui_input)
	if summary_bar:
		summary_bar.z_index = 40
	if has_node("TopBar"):
		$TopBar.z_index = 41
	if has_node("HUD"):
		$HUD.z_index = 40
	call_deferred("_setup_world_visuals")
	RunLog.info(
		"World Conquest — %dx%d Earth globe" % [battle_data.grid_width, battle_data.grid_height]
	)


func _setup_world_visuals() -> void:
	_tile_overlay = BattleTileOwnershipOverlayLib.new()
	_tile_overlay.setup(battle_data)
	_setup_territory_backend()
	if globe_map != null:
		globe_map.setup(battle_data)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
		light.light_energy = 1.2
		light.shadow_enabled = true
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
	_on_play_area_resized(true)
	_update_tile_overlay(true)
	_update_hud()


func _process(delta: float) -> void:
	if _battle_finished or battle_data == null or territory_sim == null:
		return
	if _orbit_drag and globe_map != null:
		var md: Vector2 = sub_viewport_container.get_local_mouse_position()
		pass
	if not _paused and not _build_spawner_active and not territory_sim.finished:
		_supply += float(_friendly_tiles) * CFG.INCOME_PER_TILE_PER_SEC * delta
		var info: Dictionary = territory_sim.advance_dt(
			delta * _speed_mult, CFG.SIM_MAX_STEPS_PER_FRAME
		)
		_sync_counts()
		_overlay_clock += delta
		if _overlay_clock >= 1.0 / CFG.OVERLAY_UPDATES_PER_SEC:
			_overlay_clock = 0.0
			_update_tile_overlay(false)
	if territory_sim.finished and not _battle_finished:
		_on_battle_finished()
	if _build_spawner_active:
		_build_hint_clock += delta
		if _build_hint_clock >= 0.12:
			_build_hint_clock = 0.0
			_update_build_hover_hint()
	_hud_clock += delta
	if _hud_clock >= 0.12:
		_hud_clock = 0.0
		_update_hud()


func _setup_territory_backend() -> void:
	var backend_env: String = OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower()
	if backend_env == "cpu":
		territory_sim.set_live_backend(false)
		_tile_overlay.enable_gpu_pressure_mode()
		RunLog.info("World Conquest using CPU territory backend (BATTLE_TERRITORY_BACKEND=cpu)")
		return
	if backend_env == "gpu" and territory_sim.enable_gpu_live():
		_tile_overlay.enable_gpu_sim_mode(territory_sim.gpu_field)
		RunLog.info("World Conquest using GPU territory backend")
		return
	if territory_sim.enable_rust_live():
		_tile_overlay.enable_gpu_pressure_mode()
		RunLog.info("World Conquest using Rust territory backend")
		return
	territory_sim.set_live_backend(false)
	_tile_overlay.enable_gpu_pressure_mode()
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
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _build_spawner_active:
			_try_place_spawner()
			sub_viewport_container.accept_event()
	elif event is InputEventMouseMotion and _orbit_drag and globe_map != null:
		var mm := event as InputEventMouseMotion
		globe_map.orbit_camera(0.0, mm.relative)
		sub_viewport_container.accept_event()


func _try_place_spawner() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Click on the globe (your blue territory)."
		return
	if _supply < float(CFG.SPAWNER_COST_SUPPLY):
		build_hint_label.text = "Need %s supply (have %s)." % [
			_format_supply(float(CFG.SPAWNER_COST_SUPPLY)),
			_format_supply(_supply),
		]
		return
	var reject: String = _spawner_reject_reason(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = reject
		return
	_supply -= float(CFG.SPAWNER_COST_SUPPLY)
	battle_data.placed_structures.append({
		"id": _next_structure_id,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": grid.x,
		"gy": grid.y,
		"kind": "spawner",
	})
	_next_structure_id += 1
	if territory_sim.tile_control != null:
		territory_sim.tile_control.add_placed_spawner(
			BattleTileControlLib.OWNER_FRIENDLY, grid.x, grid.y
		)
		territory_sim.tile_control.claim_tile(
			grid.x, grid.y, BattleTileControlLib.OWNER_FRIENDLY
		)
	_refresh_markers()
	_update_tile_overlay(true)
	_build_spawner_active = false
	_update_build_ui()


func _spawner_reject_reason(gx: int, gy: int) -> String:
	if territory_sim == null or territory_sim.tile_control == null:
		return "Simulation not ready."
	if not _is_on_map_grid(gx, gy):
		return "Out of map bounds."
	if not battle_data.is_land_cell(gx, gy):
		return "Need land (not ocean)."
	if not _is_player_territory_at(gx, gy):
		return "Need your blue territory."
	for st: Dictionary in battle_data.placed_structures:
		var dx: int = gx - int(st.get("gx", 0))
		var dy: int = gy - int(st.get("gy", 0))
		if dx * dx + dy * dy < CFG.MIN_SPAWNER_SPACING_CELLS * CFG.MIN_SPAWNER_SPACING_CELLS:
			return "Too close to another spawner."
	return ""


func _is_player_territory_at(gx: int, gy: int) -> bool:
	var tc := territory_sim.tile_control
	var idx: int = battle_data.cell_index(gx, gy)
	var owner: int = int(tc.owners[idx])
	if owner == BattleTileControlLib.OWNER_FRIENDLY:
		return true
	if owner == BattleTileControlLib.OWNER_HOSTILE:
		return false
	var pf: float = tc.pressure_friendly[idx]
	var ph: float = tc.pressure_hostile[idx]
	if pf < BattleTileControlLib.MIN_CLAIM_PRESSURE:
		return false
	var ratio: float = 1.15
	if idx < tc._claim_ratio_mult.size():
		ratio *= tc._claim_ratio_mult[idx]
	return pf > ph * ratio


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


func _update_tile_overlay(force: bool) -> void:
	if _tile_overlay == null or territory_sim == null or territory_sim.tile_control == null:
		return
	var step: int = territory_sim.round_index
	if not force and _last_overlay_step == step:
		return
	_last_overlay_step = step
	var tc := territory_sim.tile_control
	if territory_sim.use_gpu_for_live() and territory_sim.gpu_field != null:
		if not territory_sim.gpu_field.export_state_to_tile_control(tc):
			return
	if globe_map != null:
		globe_map.apply_fluid_from_pressures(tc.pressure_friendly, tc.pressure_hostile)


func _refresh_markers() -> void:
	if globe_map != null:
		globe_map.refresh_markers(battle_data.placed_structures, _player_home, _enemy_home)


func _sync_counts() -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	_sim_time = territory_sim.sim_time
	_friendly_tiles = tc.friendly_tiles
	_hostile_tiles = tc.hostile_tiles


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
	sub_viewport_container.stretch = false
	sub_viewport.size = Vector2i(maxi(int(play_size.x), 1), maxi(int(play_size.y), 1))


func _update_hud() -> void:
	var fp: float = 0.0
	var ep: float = 0.0
	if territory_sim != null and territory_sim.tile_control != null:
		var totals: Vector2 = BattleTileFluidFieldLib.cumulative_power_totals(
			territory_sim.tile_control.pressure_friendly,
			territory_sim.tile_control.pressure_hostile,
		)
		fp = totals.x
		ep = totals.y
	blue_count_label.text = _format_supply(fp)
	red_count_label.text = _format_supply(ep)
	blue_sub_label.text = "%d%% · %d tiles" % [_pct(_friendly_tiles), _friendly_tiles]
	red_sub_label.text = "%d%% · %d tiles" % [_pct(_hostile_tiles), _hostile_tiles]
	time_label.text = _format_sim_time(_sim_time)
	supply_label.text = "Supply %s" % _format_supply(_supply)
	status_label.text = "World Conquest  |  %s  |  x%.0f  |  drag globe · scroll zoom" % [
		"PAUSED" if _paused else "LIVE",
		_speed_mult,
	]
	speed_button.text = "▶ x%.0f" % _speed_mult
	spawner_button.text = "Outpost (%s)" % _format_supply(float(CFG.SPAWNER_COST_SUPPLY))


func _style_summary_hud() -> void:
	if supply_label:
		supply_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		supply_label.add_theme_font_size_override("font_size", 18)


func _update_build_ui() -> void:
	spawner_button.set_block_signals(true)
	spawner_button.button_pressed = _build_spawner_active
	spawner_button.set_block_signals(false)
	if _build_spawner_active:
		build_hint_label.text = (
			"Build paused. Left-click your territory (%s). Esc cancel. Drag to rotate globe."
			% _format_supply(float(CFG.SPAWNER_COST_SUPPLY))
		)
		_update_build_hover_hint()
	else:
		build_hint_label.text = "Place outposts on blue territory. Drag globe to rotate."


func _update_build_hover_hint() -> void:
	if not _build_spawner_active:
		return
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Move cursor over the globe."
		return
	var reject: String = _spawner_reject_reason(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = "(%d,%d) — %s" % [grid.x, grid.y, reject]
	else:
		build_hint_label.text = "(%d,%d) OK — click to place." % [grid.x, grid.y]


func _on_spawner_toggled(on: bool) -> void:
	_build_spawner_active = on
	_update_build_ui()


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
	end_label.text = (
		"%s\n\nHeld %d%% of land after %s.\n(%s)\n\nPress Back to exit."
		% [
			"VICTORY" if won else "DEFEAT",
			_pct(_friendly_tiles),
			_format_sim_time(_sim_time),
			reason,
		]
	)
	end_overlay.visible = true


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_build_spawner_active = false
		_update_build_ui()


func _is_on_map_grid(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < battle_data.grid_width and gy < battle_data.grid_height


func _pct(tiles: int) -> int:
	if _claimable_tiles <= 0:
		return 0
	return int(round(float(tiles) * 100.0 / float(_claimable_tiles)))


func _format_supply(v: float) -> String:
	return "%d" % int(round(v))


func _format_sim_time(t: float) -> String:
	var day: int = int(t / 60.0) + 1
	var sec: int = int(t) % 60
	var min: int = int(t / 60.0) % 60
	return "Day %d  %02d:%02d" % [day, min, sec]
