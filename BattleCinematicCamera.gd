class_name BattleCinematicCamera
extends RefCounted

const BattlePhaseControllerLib := preload("res://BattlePhaseController.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
var camera: Camera2D = null
var _battle_data = null
var _phase_ctrl: BattlePhaseControllerLib = null
var _store: UnitSimulationStoreLib = null
var _target_pos := Vector2.ZERO
var _target_zoom: float = 0.22
var _zoom_blend_speed: float = 1.4
var _shake: float = 0.0
var _wheel_timer: float = 0.0
var _last_friendly_ratio: float = 1.0
var _player_start: int = 1
var _engagement_scan_phase: float = 0.0
var _flip_zoom_punch: float = 0.0


func setup(
	cam: Camera2D,
	battle_data,
	phase_ctrl: BattlePhaseControllerLib,
	store: UnitSimulationStoreLib,
	player_start_count: int,
) -> void:
	camera = cam
	_battle_data = battle_data
	_phase_ctrl = phase_ctrl
	_store = store
	_player_start = maxi(1, player_start_count)
	if camera:
		camera.zoom = Vector2(_target_zoom, _target_zoom)
		_target_pos = Vector2.ZERO


func notify_wheel_zoom() -> void:
	_wheel_timer = 3.0


func notify_sector_flip() -> void:
	_shake = maxf(_shake, 0.38)
	_flip_zoom_punch = 0.05


func tick(step: float, sector_combat) -> void:
	if camera == null or _battle_data == null or _phase_ctrl == null:
		return
	_wheel_timer = maxf(0.0, _wheel_timer - step)
	_engagement_scan_phase += step * 0.35
	_flip_zoom_punch = maxf(0.0, _flip_zoom_punch - step * 1.8)
	if _store:
		var ratio := float(_store.living_friendly_count()) / float(_player_start)
		if ratio < _last_friendly_ratio - 0.1:
			_shake = maxf(_shake, 0.25)
		_last_friendly_ratio = ratio
	_compute_targets(sector_combat)
	if _wheel_timer <= 0.0:
		camera.zoom = camera.zoom.lerp(Vector2(_target_zoom, _target_zoom), minf(1.0, step * _zoom_blend_speed))
	camera.position = camera.position.lerp(_target_pos, minf(1.0, step * 2.2))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - step * 2.0)
		camera.offset = Vector2(
			randf_range(-_shake, _shake) * 48.0,
			randf_range(-_shake, _shake) * 32.0,
		)
	else:
		camera.offset = Vector2.ZERO


func _compute_targets(sector_combat = null) -> void:
	match _phase_ctrl.current_phase:
		BattlePhaseControllerLib.Phase.BRIEFING:
			_target_zoom = 0.22
			_target_pos = Vector2.ZERO
		BattlePhaseControllerLib.Phase.DEPLOYMENT:
			_target_zoom = 0.28
			_target_pos = _zone_center(_battle_data.player_spawn_zone)
		BattlePhaseControllerLib.Phase.APPROACH:
			_target_zoom = lerpf(0.32, 0.4, _approach_blend())
			_target_pos = _lead_friendly_front()
		BattlePhaseControllerLib.Phase.ENGAGEMENT:
			_target_zoom = clampf(_battle_data.engagement_zoom, 0.34, 0.5) + _flip_zoom_punch
			_target_pos = _engagement_camera_focus(sector_combat)
		BattlePhaseControllerLib.Phase.RESOLUTION:
			_target_zoom = 0.5
			_target_pos = _resolution_focus()
		_:
			_target_zoom = 0.45
			_target_pos = Vector2.ZERO


func _approach_blend() -> float:
	if _phase_ctrl == null:
		return 0.0
	return clampf(_phase_ctrl.phase_timer / 4.0, 0.0, 1.0)


func _zone_center(zone: Rect2) -> Vector2:
	return zone.position + zone.size * 0.5


func _contact_line_center() -> Vector2:
	var half: Vector2 = _battle_data.map_size * 0.5
	var contact_x: float = (float(_battle_data.contact_column) + 0.5) * _battle_data.cell_size - half.x
	return Vector2(contact_x, 0.0)


func _engagement_camera_focus(sector_combat) -> Vector2:
	var base: Vector2 = _contact_line_center()
	var scan_y: float = sin(_engagement_scan_phase) * _battle_data.map_size.y * 0.22
	if sector_combat != null and _battle_data != null:
		var hot_id: String = sector_combat.get_hottest_sector_id(_battle_data)
		if not hot_id.is_empty():
			var region: Dictionary = _battle_data.get_region(hot_id)
			if not region.is_empty():
				var hot_center: Vector2 = region.get("center", Vector2.ZERO)
				base.y = lerpf(base.y, hot_center.y, 0.72)
				base.x = lerpf(base.x, hot_center.x, 0.35)
				return base + Vector2(0.0, scan_y * 0.25)
	return base + Vector2(0.0, scan_y)


func _lead_friendly_front() -> Vector2:
	if _store == null or _store.count == 0:
		return _zone_center(_battle_data.player_spawn_zone)
	var best_x := -999999.0
	var sum_y := 0.0
	var n := 0
	for i in range(_store.count):
		if not _store.is_alive(i):
			continue
		if _store.side[i] != UnitSimulationStoreLib.Side.FRIENDLY:
			continue
		best_x = maxf(best_x, _store.positions[i].x)
		sum_y += _store.positions[i].y
		n += 1
	if n == 0:
		return _zone_center(_battle_data.player_spawn_zone)
	return Vector2(best_x, sum_y / float(n))


func _resolution_focus() -> Vector2:
	var held: int = _battle_data.count_objectives_held()
	if held >= _battle_data.objective_sectors_required:
		return _contact_line_center()
	return _lead_friendly_front()


func get_target_zoom() -> float:
	return _target_zoom
