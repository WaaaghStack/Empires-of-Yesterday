class_name BattleCinematicCamera
extends RefCounted

const BattlePhaseControllerLib := preload("res://BattlePhaseController.gd")
const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")

var camera: Camera2D = null
var _battle_data = null
var _phase_ctrl: BattlePhaseControllerLib = null
var _tactical: BattleTacticalSimLib = null
var _target_pos := Vector2.ZERO
var _target_zoom: float = 0.22
var _zoom_blend_speed: float = 1.4
var _shake: float = 0.0
var _wheel_timer: float = 0.0
var _last_friendly_ratio: float = 1.0
var _player_start: int = 1


func setup(
	cam: Camera2D,
	battle_data,
	phase_ctrl: BattlePhaseControllerLib,
	tactical_sim: BattleTacticalSimLib,
	player_start_count: int,
) -> void:
	camera = cam
	_battle_data = battle_data
	_phase_ctrl = phase_ctrl
	_tactical = tactical_sim
	_player_start = maxi(1, player_start_count)
	if camera:
		camera.zoom = Vector2(_target_zoom, _target_zoom)
		_target_pos = Vector2.ZERO


func notify_wheel_zoom() -> void:
	_wheel_timer = 3.0


func notify_capture_pulse() -> void:
	_shake = maxf(_shake, 0.32)


func tick(step: float) -> void:
	if camera == null or _battle_data == null or _phase_ctrl == null:
		return
	_wheel_timer = maxf(0.0, _wheel_timer - step)
	if _tactical and _tactical.store:
		var ratio := float(_tactical.store.living_friendly_count()) / float(_player_start)
		if ratio < _last_friendly_ratio - 0.08:
			_shake = maxf(_shake, 0.22)
		_last_friendly_ratio = ratio
	_compute_targets()
	if _wheel_timer <= 0.0:
		camera.zoom = camera.zoom.lerp(Vector2(_target_zoom, _target_zoom), minf(1.0, step * _zoom_blend_speed))
	camera.position = camera.position.lerp(_target_pos, minf(1.0, step * 2.2))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - step * 2.0)
		camera.offset = Vector2(
			randf_range(-_shake, _shake) * 40.0,
			randf_range(-_shake, _shake) * 28.0,
		)
	else:
		camera.offset = Vector2.ZERO


func _compute_targets() -> void:
	match _phase_ctrl.current_phase:
		BattlePhaseControllerLib.Phase.BRIEFING:
			_target_zoom = 0.18
			_target_pos = Vector2.ZERO
		BattlePhaseControllerLib.Phase.ENGAGEMENT:
			_target_zoom = clampf(_battle_data.engagement_zoom, 0.32, 0.48)
			_target_pos = _engagement_focus()
		BattlePhaseControllerLib.Phase.RESOLUTION:
			_target_zoom = 0.44
			_target_pos = _engagement_focus()
		_:
			_target_zoom = 0.4
			_target_pos = Vector2.ZERO


func _engagement_focus() -> Vector2:
	if _tactical:
		var contact: Vector2 = _tactical.get_contact_focus()
		if contact != Vector2.ZERO:
			return contact
	var half: Vector2 = _battle_data.map_size * 0.5
	var contact_x: float = (float(_battle_data.contact_column) + 0.5) * _battle_data.cell_size - half.x
	return Vector2(contact_x, 0.0)


func get_target_zoom() -> float:
	return _target_zoom


func focus_contact(pos: Vector2) -> void:
	if pos != Vector2.ZERO:
		_target_pos = pos
