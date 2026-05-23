class_name EnemyUnit
extends Node2D

const CombatFxLib := preload("res://CombatFx.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const MissionStateLib := preload("res://MissionState.gd")

signal died(enemy: EnemyUnit)
signal combat_hit(attacker_name: String, target_name: String, damage: int, killed: bool)

@export var enemy_name: String = "Hostile"
@export var max_health: int = 50
@export var damage: int = 12
@export var speed: float = 80.0
@export var attack_range: float = 110.0
@export var fire_rate: float = 0.7
@export var aggro_range: float = 420.0
@export var leash_range: float = 260.0

var current_health: int = 50
var is_alive := true
var is_visible_to_player := false
var home_room: Room = null
var fire_cooldown: float = 0.0

@onready var body_poly: Polygon2D = $BodyPoly
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	_update_visuals()
	_apply_visibility()

func _mission_paused() -> bool:
	return MissionStateLib.is_unit_actions_frozen(self)

func setup_from_resource(resource: Enemy, room: Room = null) -> void:
	if resource:
		enemy_name = resource.enemy_name
		max_health = resource.health
		current_health = resource.health
		damage = resource.damage
		speed = resource.speed
	home_room = room
	_update_visuals()

func _physics_process(delta: float) -> void:
	if not is_alive or _mission_paused():
		return
	fire_cooldown = max(0.0, fire_cooldown - delta)
	var target := _find_nearest_soldier()
	if not target:
		return
	var dist: float = position.distance_to(target.position)
	if home_room and position.distance_to(home_room.position) > leash_range and dist > attack_range:
		var home_dir := (home_room.position - position).normalized()
		position += home_dir * speed * 0.6 * delta
		return
	if dist > attack_range * 0.8 and dist <= aggro_range:
		var direction := (target.position - position).normalized()
		position += direction * speed * delta
		if body_poly:
			body_poly.rotation = direction.angle()
	elif dist <= attack_range:
		if not is_visible_to_player:
			return
		_face_target(target)
		_try_attack_target(target)

func _face_target(target: Node2D) -> void:
	if not target or not body_poly:
		return
	var direction := target.position - position
	if direction.length() > 0.01:
		body_poly.rotation = direction.angle()

func _find_nearest_soldier() -> SoldierUnit:
	var nearest: SoldierUnit = null
	var nearest_dist: float = aggro_range
	var rooms: Array = _get_rooms()
	var door_nodes: Array = get_tree().get_nodes_in_group("doors")
	for node in get_tree().get_nodes_in_group("soldiers"):
		if node is SoldierUnit and node.is_alive:
			var dist: float = position.distance_to(node.position)
			if dist >= nearest_dist:
				continue
			if not LineOfSightLib.has_line_of_sight(position, node.position, rooms, door_nodes):
				continue
			nearest_dist = dist
			nearest = node
	return nearest

func set_visible_to_player(now_visible: bool) -> void:
	if is_visible_to_player == now_visible:
		return
	is_visible_to_player = now_visible
	_apply_visibility()

func _apply_visibility() -> void:
	visible = is_visible_to_player
	if health_bar:
		health_bar.visible = is_visible_to_player

func _get_rooms() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("rooms"):
		result.append(node)
	return result

func _try_attack_target(target: SoldierUnit) -> void:
	if fire_cooldown > 0.0 or not target or not target.is_alive:
		return
	var was_alive := target.is_alive
	target.take_damage(damage, self)
	fire_cooldown = 1.0 / fire_rate
	CombatFxLib.spawn_shot(self, target.global_position, Color(1.0, 0.35, 0.55, 0.95), 2.0)
	CombatFxLib.spawn_impact(target, Color(1.0, 0.15, 0.35, 0.85))
	_flash_attack()
	combat_hit.emit(enemy_name, target.soldier_name, damage, was_alive and not target.is_alive)

func take_damage(amount: int, _from: Node2D = null) -> void:
	if not is_alive:
		return
	current_health = max(0, current_health - amount)
	if health_bar:
		health_bar.value = current_health
	if body_poly:
		body_poly.modulate = Color(1.2, 0.5, 0.5)
		var tween := create_tween()
		tween.tween_property(body_poly, "modulate", Color.WHITE, 0.12)
	if current_health <= 0:
		_die()

func _die() -> void:
	is_alive = false
	if body_poly:
		body_poly.modulate = Color(0.25, 0.25, 0.25, 0.5)
	if home_room:
		home_room.unregister_enemy(self)
	died.emit(self)

func _flash_attack() -> void:
	if body_poly:
		var tween := create_tween()
		tween.tween_property(body_poly, "modulate", Color(1.4, 0.4, 0.6), 0.05)
		tween.tween_property(body_poly, "modulate", Color.WHITE, 0.08)

func _update_visuals() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
