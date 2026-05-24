class_name Hive
extends Node2D

const CombatFxLib := preload("res://CombatFx.gd")
const CommsTemplatesLib := preload("res://CommsTemplates.gd")

signal hive_destroyed(hive: Hive)
signal hive_activated(hive: Hive)
signal wave_spawned(hive: Hive, count: int)
signal wave_telegraph(hive: Hive)

const EnemyScene := preload("res://EnemyUnit.tscn")
const TELEGRAPH_SECONDS := 1.5

enum State { DORMANT, ACTIVE, DESTROYED }

@export var base_spawn_interval: float = 34.0
@export var min_spawn_interval: float = 16.0
@export var spawn_cap: int = 3
@export var wave_size_base: int = 1
@export var max_health: int = 180

var home_room: Room = null
var hive_id: String = ""
var hive_name: String = "Bio-Hive"
var state: State = State.DORMANT
var is_destroyed: bool = false
var current_health: int = 180
var spawn_timer: float = 0.0
var escalation_timer: float = 0.0
var current_interval: float = 22.0
var spawned_enemies: Array[EnemyUnit] = []
var stat_scale: float = 1.0
var op_depth: int = 1
var is_focus_marked := false
var _spawn_rng := RandomNumberGenerator.new()
var _next_enemy_id: int = 5000
var _tactical_map: Node = null
var _body: Polygon2D
var _ring: Line2D
var _health_bar: ProgressBar
var focus_mark_timer: float = 0.0
var _telegraph_timer: float = 0.0
var _telegraph_active := false
var _last_damage_comms_pct: float = 1.0


func _ready() -> void:
	add_to_group("hives")
	add_to_group("combat_targets")
	_build_visual()
	current_interval = base_spawn_interval
	spawn_timer = base_spawn_interval * 0.6
	current_health = max_health
	_sync_process_mode()


func _sync_process_mode() -> void:
	set_process(false)


func setup(room: Room, id: String, map_seed: int, enemy_stat_scale: float, op_index: int) -> void:
	home_room = room
	hive_id = id
	hive_name = "Bio-Hive"
	stat_scale = enemy_stat_scale
	op_depth = op_index
	max_health = 120 + op_index * 45
	current_health = max_health
	_spawn_rng.seed = map_seed + hash(id)
	if _health_bar:
		_health_bar.max_value = max_health
		_health_bar.value = current_health
	if home_room:
		position = home_room.position + Vector2(0.0, -home_room.room_size.y * 0.15)
		home_room.set_meta("hive", self)
		home_room.set_meta("is_hive_room", true)


func bind_tactical_map(map_node: Node) -> void:
	_tactical_map = map_node


func apply_pressure_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	spawn_cap = int(profile.get("spawn_cap", spawn_cap))
	wave_size_base = int(profile.get("wave_size_base", wave_size_base))
	base_spawn_interval = float(profile.get("base_spawn_interval", base_spawn_interval))
	min_spawn_interval = float(profile.get("min_spawn_interval", min_spawn_interval))
	current_interval = base_spawn_interval
	spawn_timer = base_spawn_interval * 0.6


func is_attackable() -> bool:
	return not is_destroyed and state != State.DESTROYED


func _build_visual() -> void:
	_body = Polygon2D.new()
	_body.color = Color(0.55, 0.15, 0.35, 0.85)
	_body.polygon = PackedVector2Array([
		Vector2(-14, -10), Vector2(14, -10), Vector2(18, 6), Vector2(0, 16), Vector2(-18, 6),
	])
	add_child(_body)
	_ring = Line2D.new()
	_ring.width = 2.0
	_ring.default_color = Color(0.95, 0.35, 0.55, 0.9)
	_ring.points = PackedVector2Array([
		Vector2(-16, -12), Vector2(16, -12), Vector2(20, 8), Vector2(0, 20), Vector2(-20, 8), Vector2(-16, -12),
	])
	add_child(_ring)
	_health_bar = ProgressBar.new()
	_health_bar.offset_left = -18.0
	_health_bar.offset_top = 16.0
	_health_bar.offset_right = 18.0
	_health_bar.offset_bottom = 21.0
	_health_bar.max_value = max_health
	_health_bar.value = current_health
	_health_bar.show_percentage = false
	add_child(_health_bar)


func tick_dormant_activation() -> void:
	if is_destroyed or state != State.DORMANT:
		return
	_try_activate()


func tick_focus_mark(delta: float) -> void:
	if focus_mark_timer <= 0.0:
		return
	focus_mark_timer = maxf(0.0, focus_mark_timer - delta)
	if focus_mark_timer <= 0.0:
		is_focus_marked = false
		_apply_mark_visual()


func tick_active(delta: float) -> void:
	if is_destroyed or state != State.ACTIVE:
		return
	_prune_spawned()
	if _telegraph_active:
		_telegraph_timer -= delta
		var t := 1.0 - (_telegraph_timer / TELEGRAPH_SECONDS)
		var pulse := 1.0 + 0.18 * sin(t * TAU * 3.0)
		scale = Vector2(pulse, pulse)
		if _ring:
			_ring.width = 2.0 + 3.5 * t
			_ring.default_color = Color(1.0, 0.45 + 0.25 * t, 0.2, 1.0)
		if _body:
			_body.modulate = Color(1.0, 0.7 + 0.3 * t, 0.45 + 0.35 * t, 1.0)
		if _telegraph_timer <= 0.0:
			_telegraph_active = false
			scale = Vector2.ONE
			if _body:
				_body.modulate = Color.WHITE
			_spawn_wave()
			spawn_timer = current_interval
		return
	scale = Vector2.ONE
	spawn_timer -= delta
	escalation_timer += delta
	if escalation_timer >= 60.0:
		escalation_timer = 0.0
		current_interval = maxf(min_spawn_interval, current_interval * 0.92)
	if spawn_timer <= 0.0:
		if _at_global_enemy_cap():
			spawn_timer = current_interval * 0.35
			return
		_begin_wave_telegraph()


func _begin_wave_telegraph() -> void:
	_telegraph_active = true
	_telegraph_timer = TELEGRAPH_SECONDS
	wave_telegraph.emit(self)
	if _ring:
		_ring.default_color = Color(1.0, 0.55, 0.25, 1.0)
	if _tactical_map and _tactical_map.has_method("log_message"):
		var room_name := home_room.room_name if home_room else "sector"
		_tactical_map.log_message(
			CommsTemplatesLib.hive_wave_inbound(room_name),
			GameTheme.ACCENT_DANGER.to_html(),
			"alert",
		)
	_minimap_dirty_ping()


func _minimap_dirty_ping() -> void:
	if _tactical_map and _tactical_map.has_method("mark_minimap_dirty"):
		_tactical_map.mark_minimap_dirty()


func _at_global_enemy_cap() -> bool:
	if _tactical_map and _tactical_map.has_method("is_enemy_cap_reached"):
		return _tactical_map.is_enemy_cap_reached()
	return false


func _try_activate() -> void:
	if not home_room:
		return
	if home_room.is_revealed:
		_activate()
		return
	var room_list: Array = _rooms_source()
	for node in room_list:
		if not node is Room:
			continue
		var room: Room = node as Room
		if not room.is_revealed:
			continue
		if _is_adjacent_to(room, home_room):
			_activate()
			return


func _rooms_source() -> Array:
	if _tactical_map and _tactical_map.get("rooms"):
		var cached: Array = _tactical_map.rooms
		if not cached.is_empty():
			return cached
	return get_tree().get_nodes_in_group("rooms")


func _is_adjacent_to(a: Room, b: Room) -> bool:
	if not a or not b:
		return false
	return a.position.distance_to(b.position) < (a.room_size.length() + b.room_size.length()) * 0.65


func _activate() -> void:
	if state != State.DORMANT:
		return
	state = State.ACTIVE
	_sync_process_mode()
	hive_activated.emit(self)
	if _tactical_map and _tactical_map.has_method("log_message"):
		_tactical_map.log_message(
			CommsTemplatesLib.hive_active(home_room.room_name if home_room else "sector"),
			GameTheme.ACCENT_DANGER.to_html(),
			"alert",
		)


func _spawn_wave() -> void:
	if not home_room or not _tactical_map:
		return
	_apply_mark_visual()
	_prune_spawned()
	var living := spawned_enemies.size()
	if living >= spawn_cap:
		return
	if _at_global_enemy_cap():
		spawn_timer = current_interval * 0.35
		return
	var wave_size: int = wave_size_base + maxi(0, int(op_depth / 3))
	wave_size = mini(wave_size, spawn_cap - living)
	for i in range(wave_size):
		if _at_global_enemy_cap():
			break
		var arch: Enemy.Kind = Enemy.pick_archetype_for_op(op_depth, _spawn_rng, false)
		var enemy_res := Enemy.create_archetype(arch, stat_scale, _next_enemy_id)
		_next_enemy_id += 1
		var enemy: EnemyUnit = EnemyScene.instantiate()
		enemy.setup_from_resource(enemy_res, home_room)
		var offset := Vector2((float(i) - float(wave_size - 1) * 0.5) * 32.0, home_room.room_size.y * 0.1)
		enemy.position = home_room.position + offset
		enemy.set_meta("hive_spawned", true)
		if _tactical_map.has_method("register_spawned_enemy"):
			if not _tactical_map.register_spawned_enemy(enemy, home_room):
				enemy.queue_free()
				continue
		spawned_enemies.append(enemy)
	wave_spawned.emit(self, wave_size)


func _prune_spawned() -> void:
	spawned_enemies = spawned_enemies.filter(func(e): return is_instance_valid(e) and e.is_alive)


func take_damage(amount: int, _from: Node2D = null) -> void:
	if not is_attackable():
		return
	var final_amount := maxi(1, amount)
	current_health = max(0, current_health - final_amount)
	var pct := float(current_health) / float(maxi(max_health, 1))
	CombatFxLib.spawn_damage_number(self, final_amount, Color(0.95, 0.35, 0.65, 1.0))
	if _health_bar:
		_health_bar.value = current_health
	if _body:
		_body.modulate = Color(1.25, 0.55, 0.75)
		var tween := create_tween()
		tween.tween_property(_body, "modulate", Color.WHITE, 0.12)
	CombatFxLib.spawn_impact(self, Color(0.95, 0.25, 0.55, 0.85))
	if _tactical_map and _tactical_map.has_method("log_message"):
		if pct <= 0.75 and _last_damage_comms_pct > 0.75:
			_last_damage_comms_pct = pct
			_tactical_map.log_message(
				CommsTemplatesLib.hive_damage(final_amount, pct),
				GameTheme.ACCENT_WARN.to_html(),
				"combat",
			)
		elif pct <= 0.35 and _last_damage_comms_pct > 0.35:
			_last_damage_comms_pct = pct
			_tactical_map.log_message(
				CommsTemplatesLib.hive_damage(final_amount, pct),
				GameTheme.ACCENT_DANGER.to_html(),
				"combat",
			)
	if current_health <= 0:
		destroy_hive()


func set_focus_marked(marked: bool, duration: float = 10.0) -> void:
	is_focus_marked = marked
	focus_mark_timer = duration if marked else 0.0
	_apply_mark_visual()
	_sync_process_mode()


func _apply_mark_visual() -> void:
	if not _ring:
		return
	if _telegraph_active:
		_ring.default_color = Color(1.0, 0.55, 0.25, 1.0)
		_ring.width = 3.0
	elif is_focus_marked:
		_ring.default_color = Color(1.0, 0.92, 0.35, 1.0)
		_ring.width = 3.0
	else:
		_ring.default_color = Color(0.95, 0.35, 0.55, 0.9)
		_ring.width = 2.0


func destroy_hive(_killer: Node2D = null) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	state = State.DESTROYED
	_sync_process_mode()
	var remaining: Array = spawned_enemies.duplicate()
	spawned_enemies.clear()
	for enemy in remaining:
		if _tactical_map and _tactical_map.has_method("despawn_enemy"):
			_tactical_map.despawn_enemy(enemy)
		elif is_instance_valid(enemy):
			if enemy.is_alive:
				enemy.take_damage(enemy.max_health)
			enemy.queue_free()
	CombatFxLib.spawn_death(self, Color(0.95, 0.2, 0.55, 0.9))
	if _body:
		_body.color = Color(0.25, 0.25, 0.28, 0.5)
		_body.modulate = Color(0.6, 0.6, 0.65, 0.7)
	if _ring:
		_ring.default_color = Color(0.35, 0.35, 0.38, 0.45)
	if _health_bar:
		_health_bar.visible = false
	if home_room:
		if home_room.has_meta("hive"):
			home_room.remove_meta("hive")
		if home_room.has_method("check_cleared_status"):
			home_room.check_cleared_status()
	hive_destroyed.emit(self)


func on_room_cleared() -> void:
	if home_room and home_room.is_cleared and not is_destroyed:
		destroy_hive()


func get_living_spawn_count() -> int:
	_prune_spawned()
	return spawned_enemies.size()
