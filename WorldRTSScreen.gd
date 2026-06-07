extends Control

const WorldMapGeneratorLib := preload("res://WorldMapGenerator.gd")
const WorldRTSConfigLib := preload("res://WorldRTSConfig.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTileOwnershipOverlayLib := preload("res://BattleTileOwnershipOverlay.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const GameThemeLib := preload("res://GameTheme.gd")
const BattleMapPlacementLib := preload("res://BattleMapPlacement.gd")
const WorldRTSTerrainBakeLib := preload("res://WorldRTSTerrainBake.gd")

@onready var world: Node2D = $PlayArea/SubViewportContainer/SubViewport/World
@onready var map_camera: Camera2D = $PlayArea/SubViewportContainer/SubViewport/World/MapCamera
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
var _terrain_layer: Node2D
var _structure_layer: Node2D
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
var _base_camera_zoom: float = 0.2
var _last_overlay_round: int = -1
var _next_structure_id: int = 1
var _hq_layer: Node2D
var _build_hint_clock: float = 0.0
var _hud_clock: float = 0.0


func _ready() -> void:
	GameTheme.apply_to_control(self)
	_style_summary_hud()
	back_button.pressed.connect(_on_back_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	speed_button.pressed.connect(_on_speed_pressed)
	spawner_button.toggled.connect(_on_spawner_toggled)
	end_overlay.visible = false
	_wallet_power = float(WorldRTSConfigLib.STARTING_WALLET_POWER)
	var seed_val: int = RunState.run_seed if RunState.run_seed != 0 else randi() & 0x7FFFFFFF
	battle_data = WorldMapGeneratorLib.generate_world(seed_val)
	territory_sim = BattleTerritorySimLib.new()
	territory_sim.use_simple_water_model = true
	territory_sim.set_resolve_context("world")
	territory_sim.setup(
		battle_data,
		WorldRTSConfigLib.PLAYER_FORCE,
		WorldRTSConfigLib.ENEMY_FORCE,
		null,
	)
	if territory_sim.tile_control != null:
		territory_sim.tile_control.use_active_set = true
	_claimable_tiles = territory_sim.claimable_tiles
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
	RunLog.info("World RTS — %dx%d map" % [battle_data.grid_width, battle_data.grid_height])


func _setup_world_visuals() -> void:
	_draw_terrain()
	_tile_overlay = BattleTileOwnershipOverlayLib.new()
	_tile_overlay.name = "TileOverlay"
	_tile_overlay.z_index = 10
	world.add_child(_tile_overlay)
	_tile_overlay.setup(battle_data)
	_setup_territory_backend()
	_wire_home_base_markers()
	_structure_layer = Node2D.new()
	_structure_layer.name = "Structures"
	_structure_layer.z_index = 12
	world.add_child(_structure_layer)
	_hq_layer = Node2D.new()
	_hq_layer.name = "HQMarkers"
	_hq_layer.z_index = 14
	world.add_child(_hq_layer)
	_refresh_hq_markers()
	_refresh_structure_markers()
	_on_play_area_resized(true)
	_update_tile_overlay(true)
	_update_hud()


func _draw_terrain() -> void:
	if _terrain_layer:
		_terrain_layer.queue_free()
	_terrain_layer = Node2D.new()
	_terrain_layer.name = "Terrain"
	_terrain_layer.z_index = -5
	world.add_child(_terrain_layer)
	world.move_child(_terrain_layer, 0)
	var tex: ImageTexture = WorldRTSTerrainBakeLib.build_terrain_texture(battle_data)
	if tex == null:
		return
	var half: Vector2 = battle_data.map_size * 0.5
	var terrain_sprite := Sprite2D.new()
	terrain_sprite.name = "TerrainMap"
	terrain_sprite.texture = tex
	terrain_sprite.centered = false
	terrain_sprite.position = -half
	terrain_sprite.scale = Vector2(battle_data.cell_size, battle_data.cell_size)
	terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_terrain_layer.add_child(terrain_sprite)


func _process(delta: float) -> void:
	if _battle_finished or battle_data == null or territory_sim == null:
		return
	if not end_overlay.visible:
		_pan_camera(delta)
	if not _paused and not _build_spawner_active and not territory_sim.finished:
		_wallet_power += (
			float(_friendly_tiles)
			* WorldRTSConfigLib.INCOME_PER_OWNED_TILE_PER_SEC
			* delta
		)
		_sim_accum += delta * _speed_mult * WorldRTSConfigLib.SIM_ROUNDS_PER_SEC
		var max_rounds: int = _sim_rounds_budget_per_frame()
		var rounds: int = mini(max_rounds, maxi(1, int(_sim_accum)))
		_sim_accum -= float(rounds)
		for _i in range(rounds):
			if territory_sim.finished:
				break
			territory_sim.advance_round()
		_sync_counts()
		_overlay_clock += delta
		var overlay_interval: float = 1.0 / WorldRTSConfigLib.OVERLAY_UPDATES_PER_SEC
		if _overlay_clock >= overlay_interval:
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
		RunLog.info("World RTS using CPU territory backend (BATTLE_TERRITORY_BACKEND=cpu)")
		return
	if backend_env == "gpu" and territory_sim.enable_gpu_live():
		_tile_overlay.enable_gpu_sim_mode(territory_sim.gpu_field)
		if territory_sim.tile_control != null:
			territory_sim.tile_control.use_active_set = false
		RunLog.info("World RTS using GPU territory backend (BATTLE_TERRITORY_BACKEND=gpu)")
		return
	if territory_sim.enable_rust_live():
		_tile_overlay.enable_gpu_pressure_mode()
		if territory_sim.tile_control != null:
			territory_sim.tile_control.use_active_set = false
		RunLog.info("World RTS using Rust territory backend")
		return
	territory_sim.set_live_backend(false)
	_tile_overlay.enable_gpu_pressure_mode()
	RunLog.info("World RTS using CPU territory backend (Rust extension not loaded)")


func _sim_rounds_budget_per_frame() -> int:
	var cap: int = WorldRTSConfigLib.SIM_MAX_ROUNDS_PER_FRAME
	if territory_sim == null or territory_sim.tile_control == null:
		return cap
	if territory_sim.use_rust_for_live():
		return cap
	var tc := territory_sim.tile_control
	if not tc.use_active_set or tc._active_indices.is_empty():
		return cap
	var active_n: int = tc._active_indices.size()
	if active_n <= WorldRTSConfigLib.SIM_ACTIVE_SOFT_CAP:
		return cap
	var over: int = active_n - WorldRTSConfigLib.SIM_ACTIVE_SOFT_CAP
	return maxi(3, cap - over / 1500)


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


func _wire_home_base_markers() -> void:
	if _tile_overlay == null or battle_data == null:
		return
	var home_bases: Array = []
	if battle_data.player_spawn_zone.size.x > 1.0 and battle_data.player_spawn_zone.size.y > 1.0:
		var pg: Vector2i = _home_grid_for_side(true)
		if pg.x >= 0:
			home_bases.append({"team": 1, "x": pg.x, "y": pg.y})
	if battle_data.enemy_spawn_zone.size.x > 1.0 and battle_data.enemy_spawn_zone.size.y > 1.0:
		var eg: Vector2i = _home_grid_for_side(false)
		if eg.x >= 0:
			home_bases.append({"team": 2, "x": eg.x, "y": eg.y})
	if home_bases.size() > 0:
		_tile_overlay.set_home_bases(home_bases)


func _refresh_hq_markers() -> void:
	if _hq_layer == null or battle_data == null:
		return
	for c in _hq_layer.get_children():
		c.queue_free()
	var cs: float = battle_data.cell_size
	for zone: Rect2 in [battle_data.player_spawn_zone, battle_data.enemy_spawn_zone]:
		if zone.size.x <= 1.0 or zone.size.y <= 1.0:
			continue
		var is_player: bool = zone == battle_data.player_spawn_zone
		var hg: Vector2i = _home_grid_for_side(is_player)
		if hg.x < 0:
			continue
		var center: Vector2 = battle_data.cell_center(hg.x, hg.y)
		var ring := ColorRect.new()
		var ring_sz: float = cs * 3.2
		ring.size = Vector2(ring_sz, ring_sz)
		ring.position = center - ring.size * 0.5
		ring.color = Color(0.2, 0.55, 1.0, 0.35) if is_player else Color(1.0, 0.35, 0.25, 0.42)
		_hq_layer.add_child(ring)
		var core := ColorRect.new()
		var core_sz: float = cs * 1.4
		core.size = Vector2(core_sz, core_sz)
		core.position = center - core.size * 0.5
		core.color = Color(0.15, 0.45, 0.95, 0.95) if is_player else Color(0.95, 0.25, 0.18, 0.95)
		_hq_layer.add_child(core)


func _pan_camera(step: float) -> void:
	if map_camera == null:
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
	var zoom_scale: float = maxf(0.08, map_camera.zoom.x)
	map_camera.position += pan.normalized() * WorldRTSConfigLib.CAMERA_PAN_SPEED * step / zoom_scale


func _on_play_area_gui_input(event: InputEvent) -> void:
	if _battle_finished or battle_data == null or end_overlay.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_camera_zoom_step(true)
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_camera_zoom_step(false)
			sub_viewport_container.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _build_spawner_active:
			_try_place_spawner()
			sub_viewport_container.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _battle_finished or battle_data == null or end_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_build_spawner_active = false
			_update_build_ui()


func _try_place_spawner() -> void:
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Click on the map (land inside the border)."
		return
	if _wallet_power < float(WorldRTSConfigLib.SPAWNER_COST_POWER):
		build_hint_label.text = "Need %s power (wallet %s)." % [
			_format_power(float(WorldRTSConfigLib.SPAWNER_COST_POWER)),
			_format_power(_wallet_power),
		]
		return
	var reject: String = _spawner_reject_reason(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = reject
		return
	_wallet_power -= float(WorldRTSConfigLib.SPAWNER_COST_POWER)
	var st: Dictionary = {
		"id": _next_structure_id,
		"team": BattleTileControlLib.OWNER_FRIENDLY,
		"gx": grid.x,
		"gy": grid.y,
		"kind": "spawner",
	}
	_next_structure_id += 1
	battle_data.placed_structures.append(st)
	if territory_sim.tile_control != null:
		territory_sim.tile_control.add_placed_spawner(
			BattleTileControlLib.OWNER_FRIENDLY, grid.x, grid.y
		)
		territory_sim.tile_control.claim_tile(
			grid.x, grid.y, BattleTileControlLib.OWNER_FRIENDLY
		)
	_refresh_structure_markers()
	_update_tile_overlay(true)
	_build_spawner_active = false
	_update_build_ui()
	RunLog.info("Placed spawner at (%d,%d)" % [grid.x, grid.y])


func _can_place_spawner_at(gx: int, gy: int) -> bool:
	return _spawner_reject_reason(gx, gy) == ""


func _spawner_reject_reason(gx: int, gy: int) -> String:
	if territory_sim == null or territory_sim.tile_control == null:
		return "Simulation not ready."
	if not _is_on_map_grid(gx, gy):
		return "Out of map bounds."
	if not battle_data.is_land_cell(gx, gy):
		return "Need passable land (not water or blocked)."
	var tc := territory_sim.tile_control
	var idx: int = battle_data.cell_index(gx, gy)
	if idx < 0 or idx >= tc.owners.size():
		return "Invalid tile."
	if not _is_player_territory_at(gx, gy):
		var owner: int = int(tc.owners[idx])
		return "Need your blue territory (tile is %s)." % _owner_label(owner)
	for st: Dictionary in battle_data.placed_structures:
		var dx: int = gx - int(st.get("gx", 0))
		var dy: int = gy - int(st.get("gy", 0))
		if dx * dx + dy * dy < WorldRTSConfigLib.MIN_SPAWNER_SPACING_CELLS * WorldRTSConfigLib.MIN_SPAWNER_SPACING_CELLS:
			return "Too close to another spawner (%d+ cells)." % WorldRTSConfigLib.MIN_SPAWNER_SPACING_CELLS
	return ""


func _is_player_territory_at(gx: int, gy: int) -> bool:
	if territory_sim == null or territory_sim.tile_control == null or battle_data == null:
		return false
	var tc := territory_sim.tile_control
	var idx: int = battle_data.cell_index(gx, gy)
	if idx < 0 or idx >= tc.owners.size():
		return false
	var owner: int = int(tc.owners[idx])
	if owner == BattleTileControlLib.OWNER_FRIENDLY:
		return true
	if owner == BattleTileControlLib.OWNER_HOSTILE:
		return false
	var pf: float = tc.pressure_friendly[idx] if idx < tc.pressure_friendly.size() else 0.0
	var ph: float = tc.pressure_hostile[idx] if idx < tc.pressure_hostile.size() else 0.0
	if pf < BattleTileControlLib.MIN_CLAIM_PRESSURE:
		return false
	var ratio: float = 1.15
	if idx < tc._claim_ratio_mult.size():
		ratio *= tc._claim_ratio_mult[idx]
	return pf > ph * ratio


func _owner_label(owner: int) -> String:
	match owner:
		BattleTileControlLib.OWNER_FRIENDLY:
			return "yours"
		BattleTileControlLib.OWNER_HOSTILE:
			return "enemy red"
		BattleTileControlLib.OWNER_CONTESTED:
			return "contested"
		BattleTileControlLib.OWNER_UNCLAIMABLE:
			return "unclaimable"
		_:
			return "neutral"


func _is_on_map_grid(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < battle_data.grid_width and gy < battle_data.grid_height


func _mouse_to_grid() -> Vector2i:
	var map_pos: Vector2 = _viewport_mouse_to_map()
	return battle_data.world_to_grid(map_pos)


func _viewport_mouse_to_map() -> Vector2:
	var local := sub_viewport_container.get_local_mouse_position()
	var sv_size := Vector2(sub_viewport.size)
	var cont_size := sub_viewport_container.size
	var sv_pos := Vector2(
		local.x * sv_size.x / maxf(cont_size.x, 1.0),
		local.y * sv_size.y / maxf(cont_size.y, 1.0),
	)
	var canvas_pos: Vector2 = map_camera.get_canvas_transform().affine_inverse() * sv_pos
	return world.to_local(canvas_pos)


func _update_build_hover_hint() -> void:
	if not _build_spawner_active or battle_data == null:
		return
	var grid: Vector2i = _mouse_to_grid()
	if not _is_on_map_grid(grid.x, grid.y):
		build_hint_label.text = "Move cursor over the map. Blue = you, red = enemy."
		return
	var owner: int = BattleTileControlLib.OWNER_NEUTRAL
	if territory_sim != null and territory_sim.tile_control != null:
		var idx: int = battle_data.cell_index(grid.x, grid.y)
		if idx >= 0 and idx < territory_sim.tile_control.owners.size():
			owner = int(territory_sim.tile_control.owners[idx])
	var reject: String = _spawner_reject_reason(grid.x, grid.y)
	if reject != "":
		build_hint_label.text = "(%d,%d) %s — %s" % [grid.x, grid.y, _owner_label(owner), reject]
	else:
		build_hint_label.text = "(%d,%d) OK — click to place (%s)." % [
			grid.x,
			grid.y,
			_format_power(float(WorldRTSConfigLib.SPAWNER_COST_POWER)),
		]


func _refresh_structure_markers() -> void:
	if _structure_layer == null:
		return
	for c in _structure_layer.get_children():
		c.queue_free()
	var cs: float = battle_data.cell_size
	for st: Dictionary in battle_data.placed_structures:
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		var center: Vector2 = battle_data.cell_center(gx, gy)
		var marker := ColorRect.new()
		marker.size = Vector2(cs * 0.7, cs * 0.7)
		marker.position = center - marker.size * 0.5
		var team: int = int(st.get("team", 1))
		marker.color = Color(0.2, 0.55, 1.0, 0.95) if team == 1 else Color(1.0, 0.35, 0.25, 0.95)
		marker.z_index = 2
		_structure_layer.add_child(marker)


func _sync_counts() -> void:
	if territory_sim == null or territory_sim.tile_control == null:
		return
	var tc := territory_sim.tile_control
	_round_index = territory_sim.round_index
	_friendly_tiles = tc.friendly_tiles
	_hostile_tiles = tc.hostile_tiles


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


func _on_play_area_resized(fit_camera: bool = false) -> void:
	if play_area == null or sub_viewport == null:
		return
	var top: float = 8.0
	if summary_bar:
		top = summary_bar.size.y + 12.0
	var bottom_h: float = 72.0
	if has_node("HUD"):
		bottom_h = $HUD.size.y + 12.0
	play_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_area.offset_top = top
	play_area.offset_bottom = -bottom_h
	var play_size: Vector2 = play_area.size
	if play_size.x < 8.0 or play_size.y < 8.0:
		return
	sub_viewport_container.stretch = false
	sub_viewport.size = Vector2i(maxi(int(play_size.x), 1), maxi(int(play_size.y), 1))
	world.position = play_size * 0.5
	if fit_camera:
		_frame_start_view()


func _fit_camera_to_map() -> void:
	if map_camera == null or battle_data == null:
		return
	var vp: Vector2 = Vector2(sub_viewport.size)
	var scale_factor: float = (
		minf(vp.x / battle_data.map_size.x, vp.y / battle_data.map_size.y)
		* WorldRTSConfigLib.CAMERA_FIT_MARGIN
	)
	_base_camera_zoom = maxf(0.04, scale_factor)
	map_camera.position = Vector2.ZERO
	map_camera.zoom = Vector2(_base_camera_zoom, _base_camera_zoom)
	map_camera.make_current()


func _frame_start_view() -> void:
	_fit_camera_to_map()
	if map_camera == null or battle_data == null:
		return
	var half: Vector2 = battle_data.map_size * 0.5
	var contact_x: float = (float(battle_data.contact_column) + 0.5) * battle_data.cell_size - half.x
	map_camera.position = Vector2(contact_x, 0.0)
	var zoom_in: float = clampf(_base_camera_zoom * 2.2, _base_camera_zoom * 0.55, _base_camera_zoom * 6.0)
	map_camera.zoom = Vector2(zoom_in, zoom_in)


func _apply_camera_zoom_step(zoom_in: bool) -> void:
	if map_camera == null:
		return
	var lo: float = maxf(0.04, _base_camera_zoom * 0.15)
	var hi: float = maxf(lo + 0.02, _base_camera_zoom * 6.0)
	var z: Vector2 = map_camera.zoom
	z *= WorldRTSConfigLib.CAMERA_ZOOM_STEP if zoom_in else (1.0 / WorldRTSConfigLib.CAMERA_ZOOM_STEP)
	map_camera.zoom = Vector2(clampf(z.x, lo, hi), clampf(z.y, lo, hi))


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
	var wallet_str: String = _format_power(_wallet_power)
	round_label.text = "Round %d" % _round_index
	if wallet_label:
		wallet_label.text = "Wallet %s" % wallet_str
		wallet_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		wallet_label.add_theme_constant_override("outline_size", 3)
		wallet_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 1.0))
	status_label.text = (
		"RTS World  |  %s  |  x%.0f  |  %s"
		% [
			"PAUSED" if _paused else "LIVE",
			_speed_mult,
			"BUILD (paused)" if _build_spawner_active else "Pan WASD · scroll zoom",
		]
	)
	speed_button.text = "▶ x%.0f" % _speed_mult
	spawner_button.text = "Spawner (%s)" % _format_power(float(WorldRTSConfigLib.SPAWNER_COST_POWER))


func _style_summary_hud() -> void:
	if wallet_label:
		wallet_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		wallet_label.add_theme_font_size_override("font_size", 18)
		wallet_label.add_theme_constant_override("outline_size", 3)
		wallet_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 1.0))
	if round_label:
		round_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 1.0))
	if summary_bar:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.06, 0.08, 0.12, 0.92)
		panel.set_corner_radius_all(6)
		panel.content_margin_left = 12
		panel.content_margin_right = 12
		panel.content_margin_top = 8
		panel.content_margin_bottom = 8
		summary_bar.add_theme_stylebox_override("panel", panel)


func _update_build_ui() -> void:
	spawner_button.set_block_signals(true)
	spawner_button.button_pressed = _build_spawner_active
	spawner_button.set_block_signals(false)
	if _build_spawner_active:
		build_hint_label.text = (
			(
				"Build paused. Left-click blue territory on the map (%s). Esc cancel. "
				+ "Pan WASD · scroll zoom."
			)
			% _format_power(float(WorldRTSConfigLib.SPAWNER_COST_POWER))
		)
		_update_build_hover_hint()
	else:
		build_hint_label.text = (
			"Spawner → click your blue tiles. YOU / ENEMY markers show HQs. "
			+ "Pan WASD · scroll to the red front."
		)


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
		"%s\n\nHeld %d%% of claimable territory after %d rounds.\n\nPress Back to exit."
		% [
			"VICTORY" if won else "DEFEAT",
			_pct(_friendly_tiles),
			_round_index,
		]
	)
	end_overlay.visible = true


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


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
