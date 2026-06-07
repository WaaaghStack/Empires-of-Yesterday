class_name BattleAtmosphere
extends Node2D

const BattlePhaseControllerLib := preload("res://BattlePhaseController.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const CombatFxLib := preload("res://CombatFx.gd")
const SectorCombatResolverLib := preload("res://SectorCombatResolver.gd")

var _battle_data = null
var _phase_ctrl: BattlePhaseControllerLib = null
var _sector_combat: SectorCombatResolverLib = null
var _dust: CPUParticles2D
var _tracer_timer: float = 0.0
var _damage_timer: float = 0.0
var _flip_burst_timer: float = 0.0
var _tracer_lines: Array[Line2D] = []


func setup(battle_data, phase_ctrl: BattlePhaseControllerLib, sector_combat: SectorCombatResolverLib) -> void:
	_battle_data = battle_data
	_phase_ctrl = phase_ctrl
	_sector_combat = sector_combat
	z_index = 6
	_setup_dust()


func _setup_dust() -> void:
	_dust = CPUParticles2D.new()
	_dust.name = "ContactDust"
	_dust.emitting = false
	_dust.amount = 48
	_dust.lifetime = 1.2
	_dust.explosiveness = 0.15
	_dust.spread = 55.0
	_dust.gravity = Vector2(0, 8)
	_dust.initial_velocity_min = 12.0
	_dust.initial_velocity_max = 36.0
	_dust.scale_amount_min = 2.0
	_dust.scale_amount_max = 5.0
	_dust.color = Color(0.55, 0.5, 0.42, 0.45)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	add_child(_dust)


func notify_flip_burst(strength: float = 1.0) -> void:
	# strength 1.0 = normal flip, >1.0 = major breakthrough / big territory swing
	var dur := clampf(0.9 + strength * 0.6, 1.0, 2.2)
	_flip_burst_timer = dur
	if _dust:
		_dust.emitting = true
		_dust.restart()
		_dust.amount = int(lerpf(48, 110, clampf(strength - 1.0, 0.0, 1.0)))
		_dust.explosiveness = lerpf(0.35, 0.75, clampf(strength - 1.0, 0.0, 1.0))


func tick(step: float) -> void:
	if _battle_data == null or _phase_ctrl == null:
		return
	_flip_burst_timer = maxf(0.0, _flip_burst_timer - step)
	_update_dust()
	if _phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT:
		_tracer_timer += step
		var interval: float = 0.28 if _flip_burst_timer > 0.0 else 0.38
		if _tracer_timer >= interval:
			_tracer_timer = 0.0
			_fire_tracer_salvo(maxi(12, 20 if _flip_burst_timer > 0.0 else 16))
	_damage_timer += step
	if _damage_timer >= 0.5:
		_damage_timer = 0.0
		_flush_damage_numbers()


func _update_dust() -> void:
	var active := _phase_ctrl.current_phase in [
		BattlePhaseControllerLib.Phase.ENGAGEMENT,
	]
	_dust.emitting = active or _flip_burst_timer > 0.0
	if not _dust.emitting:
		return
	var half: Vector2 = _battle_data.map_size * 0.5
	var contact_x: float = (float(_battle_data.contact_column) + 0.5) * _battle_data.cell_size - half.x
	_dust.position = Vector2(contact_x, 0.0)
	var band_h: float = half.y * (0.42 if _phase_ctrl.current_phase == BattlePhaseControllerLib.Phase.ENGAGEMENT else 0.35)
	_dust.emission_rect_extents = Vector2(_battle_data.cell_size * 2.8, band_h)
	if _flip_burst_timer > 0.0:
		_dust.amount = 72
		_dust.explosiveness = 0.55
	else:
		_dust.amount = 48
		_dust.explosiveness = 0.15


func _fire_tracer_salvo(salvo_cap: int = 16) -> void:
	if _battle_data == null:
		return
	var hot: Array[Dictionary] = []
	if _battle_data.capture_points.size() > 0:
		for cp in _battle_data.capture_points:
			var f: float = float(cp.get("friendly_power", 0.0))
			var h: float = float(cp.get("hostile_power", 0.0))
			if f > 0.0 and h > 0.0:
				hot.append(cp)
	else:
		for region in _battle_data.regions:
			var p: float = float(region.get("pressure", 0.0))
			if p > 0.08 and p < 0.92:
				hot.append(region)
	var salvo: int = mini(salvo_cap, maxi(4, hot.size()))
	for i in range(salvo):
		if i >= hot.size():
			break
		var region: Dictionary = hot[i]
		var center: Vector2 = region.get("world_pos", region.get("center", Vector2.ZERO))
		var offset_y := randf_range(-40.0, 40.0)
		var from_pos := center + Vector2(-28.0, offset_y)
		var to_pos := center + Vector2(28.0, offset_y)
		var control := str(region.get("control", BattleMapDataLib.CONTROL_NEUTRAL))
		var col := Color(0.9, 0.85, 0.5, 0.75) if control == BattleMapDataLib.CONTROL_PLAYER else Color(1.0, 0.55, 0.35, 0.75)
		var line := Line2D.new()
		line.width = 1.5
		line.default_color = col
		line.points = PackedVector2Array([from_pos, to_pos])
		line.z_index = 12
		add_child(line)
		_tracer_lines.append(line)
		var tween := create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.18)
		tween.tween_callback(_free_tracer.bind(line))
	while _tracer_lines.size() > 32:
		var old: Line2D = _tracer_lines.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _free_tracer(line: Line2D) -> void:
	if is_instance_valid(line):
		line.queue_free()
	_tracer_lines.erase(line)


func _flush_damage_numbers() -> void:
	if _sector_combat == null:
		return
	var batches: Array = _sector_combat.consume_damage_batches()
	for batch in batches:
		if batch is not Dictionary:
			continue
		var amount: int = int(batch.get("total", 0))
		if amount <= 0:
			continue
		var marker := Node2D.new()
		marker.position = batch.get("center", Vector2.ZERO)
		add_child(marker)
		CombatFxLib.spawn_damage_number(marker, -amount, Color(1.0, 0.35, 0.3, 1.0))
		marker.queue_free()
