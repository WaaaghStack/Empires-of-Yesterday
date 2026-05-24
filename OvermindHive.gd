class_name OvermindHive
extends Hive

## Queen / Overmind multi-phase finale — must be destroyed to open evacuation.
var is_overmind: bool = true
var current_phase: int = 1
var max_phases: int = 3


func _ready() -> void:
	super._ready()
	hive_name = "Overmind Node"


func setup(room: Room, id: String, map_seed: int, enemy_stat_scale: float, op_index: int) -> void:
	super.setup(room, id, map_seed, enemy_stat_scale, op_index)
	hive_name = "Overmind Node"
	max_health = 420 + op_index * 80
	current_health = max_health
	current_phase = 1
	state = State.DORMANT
	spawn_cap = 5
	wave_size_base = 2
	if _health_bar:
		_health_bar.max_value = max_health
		_health_bar.value = current_health
	if _body:
		_body.color = Color(0.45, 0.12, 0.62, 0.92)
	if _ring:
		_ring.default_color = Color(0.85, 0.45, 1.0, 0.95)


func activate_overmind() -> void:
	if is_destroyed or state == State.ACTIVE:
		return
	state = State.ACTIVE
	current_phase = 1
	hive_activated.emit(self)
	_spawn_phase_wave(2)
	if _tactical_map and _tactical_map.has_method("log_message"):
		_tactical_map.log_message(
			"OVERMIND AWAKENED — destroy the queen node to open extraction.",
			GameTheme.ACCENT_DANGER.to_html(),
			"alert",
		)
	if _tactical_map and _tactical_map.has_method("trigger_cinematic"):
		_tactical_map.trigger_cinematic("queen", 2.0)


func _try_activate() -> void:
	pass


func take_damage(amount: int, from: Node2D = null) -> void:
	if not is_attackable():
		return
	var prev_pct := float(current_health) / float(maxi(max_health, 1))
	super.take_damage(amount, from)
	if is_destroyed:
		return
	var new_pct := float(current_health) / float(maxi(max_health, 1))
	var phase_threshold := 1.0 - float(current_phase) / float(max_phases)
	if new_pct <= phase_threshold and prev_pct > phase_threshold and current_phase < max_phases:
		current_phase += 1
		_spawn_phase_wave(1 + current_phase)
		if _tactical_map and _tactical_map.has_method("log_message"):
			_tactical_map.log_message(
				"OVERMIND PHASE %d — elite swarm surge." % current_phase,
				GameTheme.ACCENT_DANGER.to_html(),
				"alert",
			)
		RunState.award_echoes(1)


func _spawn_phase_wave(count: int) -> void:
	for i in range(count):
		_spawn_wave()


func destroy_hive(_killer: Node2D = null) -> void:
	if is_destroyed:
		return
	super.destroy_hive(_killer)
	if RunState.planet_mode:
		RunState.on_overmind_destroyed()
		RunState.award_echoes(2)
