extends Control

const CFG := preload("res://WorldRTS3DConfig.gd")
const WorldMapGeneratorLib := preload("res://WorldMapGenerator.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTileOwnershipOverlayLib := preload("res://BattleTileOwnershipOverlay.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const GameThemeLib := preload("res://GameTheme.gd")
const BattleMapPlacementLib := preload("res://BattleMapPlacement.gd")
const WorldRTS3DMapLib := preload("res://WorldRTS3DMap.gd")

@onready var map_3d: WorldRTS3DMapLib = $PlayArea/SubViewportContainer/SubViewport/Map3D
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var play_area: Control = $PlayArea
@onready var summary_bar: PanelContainer = $SummaryBar
@onready var blue_count_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueCount
@onready var blue_sub_label: Label = $SummaryBar/SummaryHBox/BluePanel/BlueSub
@onready var red_count_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedCount
@onready var red_sub_label: Label = $SummaryBar/SummaryHBox/RedPanel/RedSub
@onready var round_label: Label = $SummaryBar/SummaryHBox/CenterPanel/RoundLabel
@onready var wallet_label: Label = $SummaryBar/SummaryHBox/CenterPanel/WalletLabel
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
var _wallet_power: float = 0.0
var _paused: bool = false
var _speed_mult: float = 1.0
var _round_index: int = 0
var _overlay_clock: float = 0.0
var _sim_accum: float = 0.0
var _battle_finished: bool = false
var _build_spawner_active: bool = false
var _last_overlay_round: int = -1
var _next_structure_id: int = 1
var _build_hint_clock: float = 0.0
var _hud_clock: float = 0.0
var _player_home: Vector2i = Vector2i(-1, -1)
var _enemy_home: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	GameTheme.apply_to_control(self)
	_style_summary_hud()
	back_button.pressed.connect(_on_back_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.pressed.connect(_on_speed_pressed)
	spawner_button.toggled.connect(_on_spawner_toggled)
	end_overlay.visible = false
	_wallet_power = float(CFG.STARTING_WALLET_POWER)
	var seed_val: int = RunState.run_seed if RunState.run_seed != 0 else randi() & 0x7FFFFFFF
	battle_data = WorldMapGeneratorLib.generate_world_3d(seed_val)
	territory_sim = BattleTerritorySimLib.new()
	territory_sim.use_simple_water_model = true
	territory_sim.set_resolve_context("world")
	territory_sim.setup(battle_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null)
	if territory_sim.tile_control != null:
		territory_sim.tile_control.use_active_set = true
	_claimable_tiles = territory_sim.claimable_tiles
	_player_home = _home_grid_for_side(true)
	_enemy_home = _home_grid_for_side(false)
	_sync_counts()
	play_area.resized.connect(_on_play_area_resized)
	sub_viewport_container.gui_input.connect(_on_play_area_gui_input)
	if summary_bar:
		summary_bar.z_index = 40
	if has_node("TopBar"):
		$TopBar.z_index = 41
	if has_node("HUD"):
		$HUD.z_index = 40
	play_area.z_index = 0
	call_deferred("_setup_world_visuals")
	RunLog.info(
		"World RTS 3D — %dx%d map" % [battle_data.grid_width, battle_data.grid_height]
	)


func _setup_world_visuals() -> void:
	_tile_overlay = BattleTileOwnershipOverlayLib.new()
	_tile_overlay.setup(battle_data)
	_setup_territory_backend()
	if map_3d != null:
		map_3d.setup(battle_data)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
		light.light_energy = 1.15
		light.shadow_enabled = true
		map_3d.add_child(light)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.12, 0.16, 0.22)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.35, 0.4, 0.48)
		e.ambient_light_energy = 0.45
		env.environment = e
		map_3d.add_child(env)
	_refresh_markers()
	_on_play_area_resized(true)
	_update_tile_overlay(true)
	_update_hud()


func _process(delta: float) -> void:
	if _battle_finished or battle_data == null or territory_sim == null:
		return
	if not end_overlay.visible:
		_pan_camera(delta)
	if not _paused and not _build_spawner_active and not territory_sim.finished:
		_wallet_power += (
			float(_friendly_tiles) * CFG.INCOME_PER_OWNED_TILE_PER_SEC * delta
		)
		_sim_accum += delta * _speed_mult * CFG.SIM_ROUNDS_PER_SEC
		var max_rounds: int = _sim_rounds_budget_per_frame()
		var rounds: int = mini(max_rounds, maxi(1, int(_sim_accum)))
		_sim_accum -= float(rounds)
		for _i in range(rounds):
			if territory_sim.finished:
				break
			territory_sim.advance_round()
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
		RunLog.info("World RTS 3D using CPU territory backend (BATTLE_TERRITORY_BACKEND=cpu)")
		return
	if backend_env == "gpu" and territory_sim.enable_gpu_live():
		_tile_overlay.enable_gpu_sim_mode(territory_sim.gpu_field)
		if territory_sim.tile_control != null:
			territory_sim.tile_control.use_active_set = false
		RunLog.info("World RTS 3D using GPU territory backend (BATTLE_TERRITORY_BACKEND=gpu)")
		return
	if territory_sim.enable_rust_live():
		_tile_overlay.enable_gpu_pressure_mode()
		if territory_sim.tile_control != null:
			territory_sim.tile_control.use_active_set = false
		RunLog.info("World RTS 3D using Rust territory backend")
		return
	territory_sim.set_live_backend(false)
	_tile_overlay.enable_gpu_pressure_mode()
	RunLog.info("World RTS 3D using CPU territory backend (Rust extension not loaded)")


func _sim_rounds_budget_per_frame() -> int:
	var cap: int = CFG.SIM_MAX_ROUNDS_PER_FRAME
	if territory_sim == null or territory_sim.tile_control == null:
		return cap
	if territory_sim.use_rust_for_live():
		return cap
	var tc := territory_sim.tile_control
	if not tc.use_active_set or tc._active_indices.is_empty():
		return cap
	var active_n: int = tc._active_indices.size()
	if active_n <= CFG.SIM_ACTIVE_SOFT_CAP:
		return cap
	var over: int = active_n - CFG.SIM_ACTIVE_SOFT_CAP
	return maxi(4, cap - over / 800)


func _pan_camera(step: float) -> void:
	if map_3d == null:
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
	map_3d.pan_camera(step, pan)


func _on_play_area_gui_input(event: InputEvent) -> void:
	if _battle_finished or battle_data == null or end_overlay.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if map_3d:
				map_3d.zoom_camera(true)
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if map_3d:
				map_3d.zoom_camera(false)
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _build_spawner_active:
			_try_place_spawner()
			sub_viewport_container.accept_event()


func _try_place_spawner() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Click on the map (land inside the border)."
		return
	if _wallet_power < float(CFG.SPAWNER_COST_POWER):
		build_hint_label.text = "Need %s power (wallet %s)." % [
			_format_power(float(CFG.SPAWNER_COST_POWER)),
			_format_power(_wallet_power),
		]
		return
	var reject: String = _spawner_reject_reason(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = reject
		return
	_wallet_power -= float(CFG.SPAWNER_COST_POWER)
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
		return "Need passable land (not water or blocked)."
	if not _is_player_territory_at(gx, gy):
		var idx: int = battle_data.cell_index(gx, gy)
		var owner: int = int(territory_sim.tile_control.owners[idx])
		return "Need your blue territory (tile is %s)." % _owner_label(owner)
	for st: Dictionary in battle_data.placed_structures:
		var dx: int = gx - int(st.get("gx", 0))
		var dy: int = gy - int(st.get("gy", 0))
		if dx * dx + dy * dy < CFG.MIN_SPAWNER_SPACING_CELLS * CFG.MIN_SPAWNER_SPACING_CELLS:
			return "Too close to another spawner (%d+ cells)." % CFG.MIN_SPAWNER_SPACING_CELLS
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
	return battle_data.world_to_grid(_viewport_mouse_to_map())


func _viewport_mouse_to_map() -> Vector2:
	var local := sub_viewport_container.get_local_mouse_position()
	var sv_size := Vector2(sub_viewport.size)
	var cont_size := sub_viewport_container.size
	var vp_pos := Vector2(
		local.x * sv_size.x / maxf(cont_size.x, 1.0),
		local.y * sv_size.y / maxf(cont_size.y, 1.0),
	)
	if map_3d == null or map_3d.camera == null:
		return Vector2(-99999.0, -99999.0)
	var origin: Vector3 = map_3d.camera.project_ray_origin(vp_pos)
	var dir: Vector3 = map_3d.camera.project_ray_normal(vp_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return Vector2(-99999.0, -99999.0)
	return Vector2(hit.x, hit.z)


func _update_tile_overlay(force: bool) -> void:
	if _tile_overlay == null or territory_sim == null or territory_sim.tile_control == null:
		return
	if not force and _last_overlay_round == _round_index:
		return
	_last_overlay_round = _round_index
	var tc := territory_sim.tile_control
	if territory_sim.use_gpu_for_live() and territory_sim.gpu_field != null:
		if not territory_sim.gpu_field.export_state_to_tile_control(tc):
			return
	_tile_overlay.apply_live_state(tc.owners, tc.pressure_friendly, tc.pressure_hostile)
	if map_3d != null:
		map_3d.apply_fluid_from_pressures(tc.pressure_friendly, tc.pressure_hostile)


func _refresh_markers() -> void:
	if map_3d != null:
		map_3d.refresh_markers(battle_data.placed_structures, _player_home, _enemy_home)


func _sync_counts() -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	_round_index = territory_sim.round_index
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
	blue_count_label.text = _format_power(fp)
	red_count_label.text = _format_power(ep)
	blue_sub_label.text = "%d%% · %d tiles" % [_pct(_friendly_tiles), _friendly_tiles]
	red_sub_label.text = "%d%% · %d tiles" % [_pct(_hostile_tiles), _hostile_tiles]
	round_label.text = "Round %d" % _round_index
	var wallet_str: String = _format_power(_wallet_power)
	wallet_label.text = "Wallet %s" % wallet_str
	status_label.text = "RTS 3D  |  %s  |  x%.0f  |  WASD pan · scroll zoom" % [
		"PAUSED" if _paused else "LIVE",
		_speed_mult,
	]
	speed_button.text = "▶ x%.0f" % _speed_mult
	spawner_button.text = "Spawner (%s)" % _format_power(float(CFG.SPAWNER_COST_POWER))


func _style_summary_hud() -> void:
	if wallet_label:
		wallet_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		wallet_label.add_theme_font_size_override("font_size", 18)
		wallet_label.add_theme_constant_override("outline_size", 3)
		wallet_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 1.0))


func _update_build_ui() -> void:
	spawner_button.set_block_signals(true)
	spawner_button.button_pressed = _build_spawner_active
	spawner_button.set_block_signals(false)
	if _build_spawner_active:
		build_hint_label.text = (
			(
				"Build paused. Left-click blue territory (%s). Esc cancel. "
				+ "WASD pan · scroll zoom."
			)
			% _format_power(float(CFG.SPAWNER_COST_POWER))
		)
		_update_build_hover_hint()
	else:
		build_hint_label.text = "Spawner → click your blue tiles. 3D map — smaller & faster."


func _update_build_hover_hint() -> void:
	if not _build_spawner_active:
		return
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Move cursor over the map."
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
	elif _speed_mult < 6.0:
		_speed_mult = 1.0
	else:
		_speed_mult = 0.5


func _on_battle_finished() -> void:
	_battle_finished = true
	var won: bool = bool(territory_sim.get_result().get("player_won", false))
	end_label.text = (
		"%s\n\nHeld %d%% after %d rounds.\n\nPress Back to exit."
		% ["VICTORY" if won else "DEFEAT", _pct(_friendly_tiles), _round_index]
	)
	end_overlay.visible = true


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_build_spawner_active = false
		_update_build_ui()


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


func _is_on_map_grid(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < battle_data.grid_width and gy < battle_data.grid_height


func _owner_label(owner: int) -> String:
	match owner:
		BattleTileControlLib.OWNER_FRIENDLY:
			return "yours"
		BattleTileControlLib.OWNER_HOSTILE:
			return "enemy red"
		BattleTileControlLib.OWNER_CONTESTED:
			return "contested"
		_:
			return "neutral"


func _pct(tiles: int) -> int:
	if _claimable_tiles <= 0:
		return 0
	return int(round(float(tiles) * 100.0 / float(_claimable_tiles)))


func _format_power(v: float) -> String:
	if v >= 1_000_000.0:
		return "%.2fM" % (v / 1_000_000.0)
	if v >= 10_000.0:
		return "%.0fK" % (v / 1_000.0)
	if v >= 1_000.0:
		return "%.1fK" % (v / 1_000.0)
	return "%.0f" % v
