class_name BattleUnitPresentation
extends Node2D
## Renders individual battle units; casualties only from store HP.

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleMassPresentationLib := preload("res://BattleMassPresentation.gd")
const BattleMovementEngineLib := preload("res://BattleMovementEngine.gd")
const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")

var store: UnitSimulationStoreLib
var mass_render: BattleMassPresentationLib
var _battle_data = null
var _movement: BattleMovementEngineLib
var _musou_elapsed: float = 0.0
var _march_paths: Dictionary = {}
var _march_start_positions: Dictionary = {}
var _march_progress: Dictionary = {}
var _march_active: bool = false
var _seconds_per_cell: float = 0.625
var _engagement_spawned: bool = false
var _impostor_size: float = 14.0
var _tile_replay_mode: bool = false


func setup(battle_data, parent_world: Node2D, impostor_size: float = 14.0) -> void:
	_battle_data = battle_data
	_impostor_size = impostor_size
	store = UnitSimulationStoreLib.new()
	mass_render = BattleMassPresentationLib.new()
	mass_render.setup(store, self, impostor_size)
	z_index = 5
	if battle_data:
		var half: Vector2 = battle_data.map_size * 0.5
		var contact_x: float = (
			(float(battle_data.contact_column) + 0.5) * battle_data.cell_size - half.x
		)
		mass_render.set_contact_line(contact_x, battle_data.cell_size)
	_movement = BattleMovementEngineLib.new()
	_movement.setup(battle_data, battle_data.map_seed if battle_data else 0)


func set_starts(_player_count: int, _enemy_count: int) -> void:
	pass


func set_pacing(seconds_per_cell: float) -> void:
	_seconds_per_cell = maxf(0.15, seconds_per_cell)


func set_visible_on_field(on: bool) -> void:
	visible = on
	if mass_render:
		mass_render.visible = on


func bind_tactical_sim(tactical) -> void:
	if tactical == null:
		return
	bind_tactical_store(tactical.store, tactical.movement)


func bind_tactical_store(
	tactical_store: UnitSimulationStoreLib,
	movement_engine: BattleMovementEngineLib = null,
	rebuild_meshes: bool = false,
) -> void:
	if tactical_store != null:
		store = tactical_store
		if mass_render:
			mass_render.setup(store, self, _impostor_size)
	_engagement_spawned = store != null and store.count > 0
	if movement_engine != null:
		_movement = movement_engine
	if rebuild_meshes and mass_render:
		mass_render.refresh_instances()


func preload_field_visuals() -> void:
	if store == null or mass_render == null:
		return
	mass_render.refresh_instances()
	_engagement_spawned = true
	set_visible_on_field(true)


func set_replay_visual_mode(enabled: bool) -> void:
	if mass_render:
		mass_render.set_replay_visual_mode(enabled)


func set_tile_replay_mode(enabled: bool) -> void:
	_tile_replay_mode = enabled
	visible = not enabled
	set_mass_visible(not enabled)
	if enabled and mass_render:
		mass_render.reset()


func is_tile_replay_mode() -> bool:
	return _tile_replay_mode


func set_mass_visible(on: bool) -> void:
	if mass_render:
		mass_render.visible = on


func sync_from_army(_army = null, snap: Dictionary = {}, movement_engine: BattleMovementEngineLib = null) -> void:
	if movement_engine != null:
		_movement = movement_engine
	if store != null and store.count > 0:
		_engagement_spawned = true
	if mass_render == null:
		return
	if snap.get("tier_visibility_dirty", false):
		mass_render.refresh_instances()
	elif snap.has("dead_units"):
		mass_render.notify_deaths(snap.get("dead_units", []))
	else:
		mass_render.notify_dirty_from_store()


func sync_replay_deaths(prev_flags: PackedInt32Array) -> void:
	if store == null or mass_render == null:
		return
	var deaths: Array = []
	var n: int = mini(store.count, prev_flags.size())
	for i in range(n):
		var was_alive: bool = (prev_flags[i] & UnitSimulationStoreLib.FLAG_ALIVE) != 0
		if was_alive and not store.is_alive(i):
			deaths.append(i)
	if not deaths.is_empty():
		mass_render.notify_deaths(deaths)


func begin_turn_march(tactical_or_movement = null, movement_engine: BattleMovementEngineLib = null) -> void:
	if tactical_or_movement is BattleTacticalSimLib:
		movement_engine = tactical_or_movement.movement
	elif tactical_or_movement is BattleMovementEngineLib:
		movement_engine = tactical_or_movement
	if store == null or _battle_data == null:
		return
	if movement_engine != null:
		_movement = movement_engine
	if _movement == null:
		return
	_march_paths = _movement.plan_turn_paths(store)
	_march_start_positions.clear()
	_march_progress.clear()
	_march_active = false
	for idx in _march_paths.keys():
		var unit_idx: int = int(idx)
		if unit_idx < 0 or unit_idx >= store.count or not store.is_alive(unit_idx):
			continue
		var path: Array = _march_paths[unit_idx]
		if path.is_empty():
			continue
		_march_start_positions[unit_idx] = store.positions[unit_idx]
		_march_progress[unit_idx] = 0.0
		_march_active = true


func is_marching() -> bool:
	return _march_active


func tick_replay_visuals(delta: float, camera_pos: Vector2, camera_zoom: float) -> void:
	if _tile_replay_mode or store == null or store.count == 0:
		return
	_march_active = false
	_musou_elapsed += delta
	mass_render.set_musou_time(_musou_elapsed)
	mass_render.set_camera(camera_pos, camera_zoom)
	mass_render.update_all_visible_transforms()


func tick_motion(delta: float, camera_pos: Vector2, camera_zoom: float) -> void:
	if store == null or store.count == 0:
		return
	_musou_elapsed += delta
	mass_render.set_musou_time(_musou_elapsed)
	mass_render.set_camera(camera_pos, camera_zoom)
	if _march_active:
		tick_march(delta)
	var dirty: PackedInt32Array = store.collect_dirty_transform_indices() if store else PackedInt32Array()
	mass_render.update_transforms(delta, dirty)


func tick_march(delta: float) -> bool:
	if not _march_active or store == null:
		return false
	var duration: float = maxf(0.15, _seconds_per_cell)
	var any_active := false
	for idx in _march_paths.keys():
		var unit_idx: int = int(idx)
		if unit_idx < 0 or unit_idx >= store.count or not store.is_alive(unit_idx):
			continue
		if not _march_progress.has(unit_idx):
			continue
		var path: Array = _march_paths[unit_idx]
		if path.is_empty():
			continue
		var to_pos: Vector2 = path[0]
		var from_pos: Vector2 = _march_start_positions.get(unit_idx, store.positions[unit_idx])
		var prog: float = float(_march_progress[unit_idx]) + delta / duration
		_march_progress[unit_idx] = minf(1.0, prog)
		store.positions[unit_idx] = from_pos.lerp(to_pos, float(_march_progress[unit_idx]))
		if float(_march_progress[unit_idx]) < 1.0:
			any_active = true
	if not any_active:
		_march_active = false
	return _march_active


func all_positions_on_land() -> bool:
	if store == null or _battle_data == null:
		return true
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		var g: Vector2i = _battle_data.world_to_grid(store.positions[i])
		if not _battle_data.is_land_cell(g.x, g.y):
			return false
	return true
