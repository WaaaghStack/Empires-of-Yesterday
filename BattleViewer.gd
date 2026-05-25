extends Control

const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
const UnitSimulationManagerLib := preload("res://UnitSimulationManager.gd")
const BattleMassPresentationLib := preload("res://BattleMassPresentation.gd")
const SectorCombatResolverLib := preload("res://SectorCombatResolver.gd")
const BattleDirectivesLib := preload("res://BattleDirectives.gd")
const BattlePhaseControllerLib := preload("res://BattlePhaseController.gd")
const TurnResolverLib := preload("res://TurnResolver.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleHeatOverlayLib := preload("res://BattleHeatOverlay.gd")
const BattleCinematicCameraLib := preload("res://BattleCinematicCamera.gd")
const BattleAtmosphereLib := preload("res://BattleAtmosphere.gd")
const BattleMusouFeelLib := preload("res://BattleMusouFeel.gd")
const GameThemeLib := preload("res://GameTheme.gd")

const SPAWN_WAVE_INTERVAL := 0.4

@onready var world: Node2D = $PlayArea/SubViewportContainer/SubViewport/World
@onready var map_camera: Camera2D = $PlayArea/SubViewportContainer/SubViewport/World/MapCamera
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var status_label: Label = $HUD/HBox/StatusLabel
@onready var phase_label: Label = $HUD/PhaseLabel
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var briefing_panel: PanelContainer = $BriefingPanel
@onready var briefing_label: Label = $BriefingPanel/BriefingLabel
@onready var pause_button: Button = $HUD/HBox/PauseButton
@onready var speed_button: Button = $HUD/HBox/SpeedButton
@onready var retreat_button: Button = $HUD/HBox/DirectiveRow/RetreatButton
@onready var focus_button: Button = $HUD/HBox/DirectiveRow/FocusButton
@onready var hold_button: Button = $HUD/HBox/DirectiveRow/HoldButton
@onready var ability_button: Button = $HUD/HBox/DirectiveRow/AbilityButton
@onready var skip_button: Button = $HUD/HBox/SkipButton

var battle_data = null
var unit_sim: UnitSimulationManagerLib
var unit_render: BattleMassPresentationLib
var sector_combat: SectorCombatResolverLib
var directives: BattleDirectivesLib
var phase_ctrl: BattlePhaseControllerLib
var heat_overlay: BattleHeatOverlayLib
var cine_camera: BattleCinematicCameraLib
var atmosphere: BattleAtmosphereLib
var _paused: bool = false
var _speed_mult: float = 1.0
var _elapsed: float = 0.0
var _battle_finished: bool = false
var _terrain_layer: Node2D
var _wave_rng := RandomNumberGenerator.new()
var _wave_spawn_timer: float = 0.0
var _player_start_count: int = 0
var _enemy_start_count: int = 0
var _visual_player_cap: int = 0
var _visual_enemy_cap: int = 0
var _player_spawned: int = 0
var _enemy_spawned: int = 0
var _last_flip_seen: String = ""
var _focused_sector_id: String = ""
var _musou_elapsed: float = 0.0
var _flip_surge_timer: float = 0.0


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
	RunLog.info("BattleViewer — %s P%d vs E%d" % [
		battle_data.terrain_tag if battle_data else "?",
		battle_data.player_allocation if battle_data else 0,
		battle_data.enemy_allocation if battle_data else 0,
	])


func _load_battle_from_run_state() -> void:
	var node_id := RunState.pending_battle_node_id
	var node: Dictionary = RunState.galaxy_state.get_node(node_id) if RunState.galaxy_state else {}
	var terrain := str(node.get("terrain_tag", "open_field"))
	var player_count: int = RunState.army_pool.get_allocation(node_id) if RunState.army_pool else 500
	var enemy_count: int = int(node.get("enemy_strength", 500))
	var seed_val := (RunState.run_seed + hash(node_id)) & 0x7FFFFFFF
	battle_data = BattleMapGeneratorLib.generate(seed_val, terrain, player_count, enemy_count, node_id)


func _setup_battle() -> void:
	if battle_data == null:
		return
	phase_ctrl = BattlePhaseControllerLib.new()
	sector_combat = SectorCombatResolverLib.new()
	sector_combat.fx_world = world
	directives = BattleDirectivesLib.new()
	_wave_rng.seed = battle_data.map_seed + 11
	unit_sim = UnitSimulationManagerLib.new()
	var rooms: Array = []
	for region in battle_data.regions:
		var r := Room.new()
		r.map_room_id = str(region.get("id", ""))
		r.position = region.get("center", Vector2.ZERO)
		r.room_size = battle_data.region_world_rect(region).size
		rooms.append(r)
	unit_sim.setup(rooms, battle_data.path_graph, 300)
	unit_sim.path_queue.set_max_finds_per_frame(20)
	_draw_terrain()
	heat_overlay = BattleHeatOverlayLib.new()
	heat_overlay.name = "HeatOverlay"
	world.add_child(heat_overlay)
	heat_overlay.setup(battle_data, unit_sim.store)
	unit_render = BattleMassPresentationLib.new()
	unit_render.setup(unit_sim.store, world, battle_data.impostor_size)
	unit_render.set_contact_line(_contact_x(), battle_data.cell_size)
	atmosphere = BattleAtmosphereLib.new()
	atmosphere.name = "BattleAtmosphere"
	world.add_child(atmosphere)
	atmosphere.setup(battle_data, phase_ctrl, sector_combat)
	cine_camera = BattleCinematicCameraLib.new()
	cine_camera.setup(map_camera, battle_data, phase_ctrl, unit_sim.store, battle_data.player_allocation)
	map_camera.position = Vector2.ZERO
	map_camera.zoom = Vector2(0.22, 0.22)
	map_camera.make_current()
	_player_start_count = battle_data.player_allocation
	_enemy_start_count = battle_data.enemy_allocation
	_visual_player_cap = mini(battle_data.player_allocation, battle_data.max_visual_units)
	_visual_enemy_cap = mini(battle_data.enemy_allocation, battle_data.max_visual_units)
	briefing_label.text = (
		"%s Battle\n\n%d soldiers march on %d defenders.\n\nObjective: Hold %d key sectors\n\nClick to begin"
		% [
			battle_data.terrain_tag.capitalize().replace("_", " "),
			battle_data.player_allocation,
			battle_data.enemy_allocation,
			battle_data.objective_sectors_required,
		]
	)
	briefing_panel.visible = true
	_update_hud()


func _spawn_wave(wave_index: int) -> void:
	if battle_data == null or unit_sim == null:
		return
	var waves: int = phase_ctrl.max_waves
	var per_wave_p: int = int(ceil(float(_visual_player_cap) / float(waves)))
	var per_wave_e: int = int(ceil(float(_visual_enemy_cap) / float(waves)))
	if wave_index == waves - 1:
		per_wave_p = _visual_player_cap - _player_spawned
		per_wave_e = _visual_enemy_cap - _enemy_spawned
	per_wave_p = maxi(0, per_wave_p)
	per_wave_e = maxi(0, per_wave_e)
	if per_wave_p > 0:
		_spawn_side_lane(per_wave_p, UnitSimulationStore.Side.FRIENDLY, battle_data.player_spawn_zone)
		_player_spawned += per_wave_p
	if per_wave_e > 0:
		_spawn_side_lane(per_wave_e, UnitSimulationStore.Side.HOSTILE, battle_data.enemy_spawn_zone)
		_enemy_spawned += per_wave_e
	phase_ctrl.mark_wave_spawned()
	if unit_render:
		unit_render.refresh_instances()
	heat_overlay.refresh()


func _spawn_side_lane(count: int, side: int, zone: Rect2) -> void:
	var positions: PackedVector2Array = BattleMapGeneratorLib.get_lane_spawn_positions(zone, count, _wave_rng)
	var advance_targets: Array[int] = _contact_sector_room_indices(side)
	var lane_i := 0
	for pos in positions:
		var room_idx := _nearest_room_index(pos)
		var squad: int = lane_i % 4
		lane_i += 1
		var store_idx: int
		if side == UnitSimulationStore.Side.FRIENDLY:
			store_idx = unit_sim.store.spawn_unit(
				side, pos, 100.0, 100.0, room_idx, squad, UnitSimulationStore.Tier.LITE, 140.0
			)
		else:
			store_idx = unit_sim.store.spawn_unit(
				side, pos, 80.0, 80.0, room_idx, squad, UnitSimulationStore.Tier.LITE, 120.0, 1
			)
		if store_idx >= 0 and not advance_targets.is_empty():
			unit_sim.store.target_room_index[store_idx] = advance_targets[_wave_rng.randi() % advance_targets.size()]


func _nearest_room_index(pos: Vector2) -> int:
	var best := 0
	var best_dist := INF
	for i in range(unit_sim.store.room_positions.size()):
		var d: float = pos.distance_squared_to(unit_sim.store.room_positions[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _contact_sector_room_indices(side: int) -> Array[int]:
	var result: Array[int] = []
	if battle_data == null:
		return result
	var contact_col: int = 4
	for i in range(battle_data.regions.size()):
		var region: Dictionary = battle_data.regions[i]
		var col: int = int(region.get("col", 0))
		if side == UnitSimulationStore.Side.FRIENDLY:
			if col >= contact_col - 1 and col <= contact_col + 1:
				result.append(i)
		else:
			if col >= contact_col and col <= contact_col + 2:
				result.append(i)
	if result.is_empty():
		for i in range(battle_data.regions.size()):
			result.append(i)
	return result


func _pick_contact_target_room(side: int, pos: Vector2) -> int:
	var candidates: Array[int] = _contact_sector_room_indices(side)
	var best: int = candidates[0]
	var best_dist: float = INF
	for idx in candidates:
		var d: float = pos.distance_squared_to(unit_sim.store.room_positions[idx])
		if d < best_dist:
			best_dist = d
			best = idx
	return best


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
			if battle_data.is_cell_blocked(gx, gy):
				var block := ColorRect.new()
				block.color = Color(0.15, 0.16, 0.2, 0.95)
				block.size = Vector2(battle_data.cell_size - 1, battle_data.cell_size - 1)
				block.position = battle_data.cell_center(gx, gy) - Vector2(battle_data.cell_size * 0.5, battle_data.cell_size * 0.5)
				_terrain_layer.add_child(block)


func _process(delta: float) -> void:
	if _battle_finished or battle_data == null:
		return
	var step := delta * _speed_mult
	if not _paused:
		_elapsed += step
		_tick_battle(step)
	_check_end_conditions()
	_update_hud()


func _tick_battle(step: float) -> void:
	phase_ctrl.tick(step, battle_data, unit_sim.store)
	if phase_ctrl.waves_spawned < phase_ctrl.max_waves:
		if phase_ctrl.current_phase != BattlePhaseControllerLib.Phase.BRIEFING:
			_wave_spawn_timer += step
			if _wave_spawn_timer >= SPAWN_WAVE_INTERVAL:
				_wave_spawn_timer = 0.0
				_spawn_wave(phase_ctrl.waves_spawned)
	directives.tick(step)
	directives.apply_to_manager(unit_sim)
	if phase_ctrl.advance_active():
		_tick_battle_advance(step)
	if phase_ctrl.should_tick_sector_combat():
		var threat_mult: float = clampf(
			float(battle_data.enemy_allocation) / maxf(1.0, float(battle_data.player_allocation)),
			0.88,
			1.22,
		)
		sector_combat.tick_combat(
			unit_sim.store, battle_data, step, directives.damage_mult, threat_mult
		)
		if sector_combat.last_flip_region_id != _last_flip_seen:
			_last_flip_seen = sector_combat.last_flip_region_id
			_flip_surge_timer = BattleMusouFeelLib.FLIP_SURGE_DURATION
			heat_overlay.sync_flip(_last_flip_seen)
			cine_camera.notify_sector_flip()
			if atmosphere:
				atmosphere.notify_flip_burst()
		heat_overlay.refresh()
	unit_sim.tick(step, map_camera.position, map_camera.zoom.x)
	unit_sim.update_tiers(map_camera.position, map_camera.zoom.x)
	if unit_render:
		unit_render.set_camera(map_camera.position, map_camera.zoom.x)
		unit_render.set_musou_time(_musou_elapsed)
		unit_render.update_transforms(step)
	if heat_overlay:
		heat_overlay.tick(step)
	if atmosphere:
		atmosphere.tick(step)
	if cine_camera and _focused_sector_id.is_empty():
		cine_camera.tick(step, sector_combat)
	elif _focused_sector_id.is_empty() == false:
		_tick_focus_camera(step)


func _contact_x() -> float:
	return (float(battle_data.contact_column) + 0.5) * battle_data.cell_size - battle_data.map_size.x * 0.5


func _tick_battle_advance(step: float) -> void:
	_musou_elapsed += step
	_flip_surge_timer = maxf(0.0, _flip_surge_timer - step)
	var contact_x: float = _contact_x()
	var phase_mult: float = 1.0
	if phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT:
		phase_mult = 0.9
	elif phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.RESOLUTION:
		phase_mult = 0.55
	var wave_mult: float = BattleMusouFeelLib.wave_charge_mult(_musou_elapsed)
	var flip_mult: float = BattleMusouFeelLib.flip_surge_mult(_flip_surge_timer)
	var meet_overlap: float = battle_data.cell_size * BattleMusouFeelLib.CONTACT_MEET_OVERLAP_CELLS
	var rear_band: float = battle_data.cell_size * BattleMusouFeelLib.REAR_BAND_CELLS
	for i in range(unit_sim.store.count):
		if not unit_sim.store.is_alive(i):
			continue
		var unit_side: int = unit_sim.store.side[i]
		var pos: Vector2 = unit_sim.store.positions[i]
		var dist: float = BattleMusouFeelLib.contact_dist_x(pos.x, contact_x, unit_side)
		var zone_mult: float = BattleMusouFeelLib.zone_speed_mult(dist, battle_data.cell_size, flip_mult)
		var squad_mult: float = BattleMusouFeelLib.squad_speed_mult(unit_sim.store.squad_id[i])
		var march: float = (
			BattleMusouFeelLib.BASE_MARCH_SPEED
			* battle_data.approach_speed_mult
			* battle_data.musou_feel_scale
			* step
			* directives.move_mult
			* phase_mult
			* wave_mult
			* zone_mult
			* squad_mult
		)
		if unit_side == UnitSimulationStore.Side.FRIENDLY:
			if pos.x < contact_x - rear_band:
				unit_sim.store.target_room_index[i] = _pick_contact_target_room(unit_side, pos)
			if pos.x < contact_x:
				pos.x = minf(pos.x + march, contact_x + meet_overlap * 0.5)
			else:
				pos.x = maxf(pos.x - march * 0.35, contact_x - meet_overlap * 0.25)
		else:
			if pos.x > contact_x + rear_band:
				unit_sim.store.target_room_index[i] = _pick_contact_target_room(unit_side, pos)
			if pos.x > contact_x:
				pos.x = maxf(pos.x - march, contact_x - meet_overlap * 0.5)
			else:
				pos.x = minf(pos.x + march * 0.35, contact_x + meet_overlap * 0.25)
		if dist <= battle_data.cell_size * BattleMusouFeelLib.CONTACT_GRIND_CELLS:
			var churn: Vector2 = BattleMusouFeelLib.front_churn_offset(unit_sim.store.ids[i], _musou_elapsed)
			pos += churn * step * 3.5
		var target_pos: Vector2 = unit_sim.store.room_positions[unit_sim.store.target_room_index[i]]
		var lane_y: float = target_pos.y + BattleMusouFeelLib.lane_offset_y(unit_sim.store.ids[i], _musou_elapsed)
		pos.y = lerpf(pos.y, lane_y, minf(1.0, step * 2.8))
		unit_sim.store.positions[i] = pos
		var new_room: int = _nearest_room_index(pos)
		if new_room != unit_sim.store.room_index[i]:
			unit_sim.store.set_room(i, new_room)


func _tick_focus_camera(step: float) -> void:
	var region: Dictionary = battle_data.get_region(_focused_sector_id)
	if region.is_empty():
		return
	map_camera.position = map_camera.position.lerp(region.get("center", Vector2.ZERO), minf(1.0, step * 3.0))


func _check_end_conditions() -> void:
	if phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.FINISHED:
		return
	var friendly := unit_sim.store.living_friendly_count()
	var hostile := unit_sim.store.living_hostile_count()
	var friendly_ratio := float(friendly) / maxf(1.0, float(_player_start_count))
	var hostile_ratio := float(hostile) / maxf(1.0, float(_enemy_start_count))
	var objectives_held: int = battle_data.count_objectives_held()
	if phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT:
		if objectives_held >= battle_data.objective_sectors_required:
			_finish_battle(true)
			return
		if friendly_ratio < 0.15:
			_finish_battle(false)
			return
		if hostile_ratio < 0.15:
			phase_ctrl.begin_resolution()
		if directives.active_type == BattleDirectivesLib.Type.RETREAT and _elapsed > 10.0:
			_finish_battle(false, true)
	elif phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.RESOLUTION:
		if hostile_ratio < 0.08 or objectives_held >= battle_data.objective_sectors_required:
			_finish_battle(true)
		elif friendly_ratio < 0.1:
			_finish_battle(false)


func _finish_battle(player_won: bool, retreat: bool = false) -> void:
	if _battle_finished:
		return
	_battle_finished = true
	phase_ctrl.current_phase = BattlePhaseControllerLib.Phase.FINISHED
	var node_id: String = battle_data.node_id
	var player_losses: int = battle_data.player_allocation - unit_sim.store.living_friendly_count()
	var enemy_losses: int = battle_data.enemy_allocation - unit_sim.store.living_hostile_count()
	if retreat:
		player_losses += int(battle_data.player_allocation * 0.15)
		player_won = false
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
	RunState.pending_live_battle = false
	RunState.save_commander_run()
	get_tree().change_scene_to_file("res://BattleDebriefCommander.tscn")


func _update_hud() -> void:
	if not unit_sim or battle_data == null:
		return
	var objectives_held: int = battle_data.count_objectives_held()
	var total_obj: int = battle_data.total_objectives()
	phase_label.text = "Phase: %s" % phase_ctrl.phase_name()
	objective_label.text = "Key zones held: %d / %d required (%d of %d objectives)" % [
		objectives_held,
		battle_data.objective_sectors_required,
		objectives_held,
		total_obj,
	]
	status_label.text = (
		"%s | P %d / %d  E %d / %d  |  %.0fs  |  %s"
		% [
			battle_data.terrain_tag.capitalize(),
			unit_sim.store.living_friendly_count(),
			battle_data.player_allocation,
			unit_sim.store.living_hostile_count(),
			battle_data.enemy_allocation,
			_elapsed,
			"PAUSED" if _paused else ("x%.0f" % _speed_mult),
		]
	)


func _on_briefing_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		phase_ctrl.skip_briefing()
		briefing_panel.visible = false


func _on_pause_pressed() -> void:
	_paused = not _paused


func _on_speed_pressed() -> void:
	if _speed_mult < 2.0:
		_speed_mult = 2.0
	elif _speed_mult < 4.0:
		_speed_mult = 4.0
	else:
		_speed_mult = 1.0


func _on_retreat_pressed() -> void:
	directives.request_retreat()
	var rear_id := "sec_2_0"
	if unit_sim.store.room_index_for_id(rear_id) >= 0:
		directives.active_sector_id = rear_id


func _on_focus_pressed() -> void:
	if not _focused_sector_id.is_empty():
		directives.request_focus_sector(_focused_sector_id)
	elif battle_data.regions.size() > 0:
		var hot := sector_combat.get_hottest_sector_id(battle_data)
		if hot.is_empty():
			hot = str(battle_data.regions[battle_data.regions.size() / 2].get("id", ""))
		directives.request_focus_sector(hot)


func _on_hold_pressed() -> void:
	directives.request_hold_line()


func _on_ability_pressed() -> void:
	directives.request_commander_ability(RunState.get_commander_profile())


func _on_skip_pressed() -> void:
	var ratio := float(unit_sim.store.living_friendly_count()) / maxf(1.0, float(unit_sim.store.living_hostile_count()))
	_finish_battle(ratio >= 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _battle_finished or map_camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if briefing_panel.visible:
			return
		_pick_sector_at_screen(event.position)
	var pan := Vector2.ZERO
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_W:
				pan.y = -1
			KEY_S:
				pan.y = 1
			KEY_A:
				pan.x = -1
			KEY_D:
				pan.x = 1
	if pan != Vector2.ZERO:
		map_camera.position += pan * 48.0
		if cine_camera:
			cine_camera.notify_wheel_zoom()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_camera.zoom = (map_camera.zoom * 1.1).clamp(Vector2(0.2, 0.2), Vector2(1.2, 1.2))
			if cine_camera:
				cine_camera.notify_wheel_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_camera.zoom = (map_camera.zoom / 1.1).clamp(Vector2(0.2, 0.2), Vector2(1.2, 1.2))
			if cine_camera:
				cine_camera.notify_wheel_zoom()


func _pick_sector_at_screen(_screen_pos: Vector2) -> void:
	var container: SubViewportContainer = $PlayArea/SubViewportContainer
	if container == null or sub_viewport == null:
		return
	var local: Vector2 = container.get_local_mouse_position()
	var world_pos: Vector2 = map_camera.get_screen_center_position()
	var offset: Vector2 = (local - container.size * 0.5) / map_camera.zoom
	world_pos = map_camera.position + offset
	var best_id := ""
	var best_dist := 999999.0
	for region in battle_data.regions:
		var center: Vector2 = region.get("center", Vector2.ZERO)
		var dist: float = center.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best_id = str(region.get("id", ""))
	if not best_id.is_empty() and best_dist < 200.0:
		_focused_sector_id = best_id
		directives.request_focus_sector(best_id)
