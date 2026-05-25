class_name SwarmDirector
extends RefCounted

const EnemyLib := preload("res://Enemy.gd")

var damage_tags: Dictionary = {}
var disturbance_sectors: Array[String] = []
var tactical_map: Node = null
var _tick_timer: float = 0.0
var _reinforcement_cooldown: float = 0.0
var _adapt_log_cooldown: float = 0.0


func reset(map_node: Node = null) -> void:
	damage_tags.clear()
	disturbance_sectors.clear()
	tactical_map = map_node
	_tick_timer = 0.0
	_reinforcement_cooldown = 0.0
	_adapt_log_cooldown = 0.0


func register_damage(tag: String, amount: int) -> void:
	if tag.is_empty():
		return
	damage_tags[tag] = int(damage_tags.get(tag, 0)) + maxi(1, amount)


func dominant_damage_tag() -> String:
	var best_tag := "kinetic"
	var best_val := 0
	for tag in damage_tags.keys():
		var val: int = int(damage_tags.get(tag, 0))
		if val > best_val:
			best_val = val
			best_tag = str(tag)
	return best_tag


func pick_counter_archetype() -> Enemy.Kind:
	match dominant_damage_tag():
		"energy":
			return Enemy.Kind.HEAVY
		"kinetic":
			return Enemy.Kind.FLANKER
		"fire":
			return Enemy.Kind.RIFLEMAN
		"bio":
			return Enemy.Kind.HEAVY
		_:
			return Enemy.Kind.FLANKER


func on_disturbance(sector: String) -> void:
	if sector.is_empty():
		return
	if sector not in disturbance_sectors:
		disturbance_sectors.append(sector)
	_schedule_adjacent_reinforcement(sector)


func tick(delta: float) -> void:
	_reinforcement_cooldown = maxf(0.0, _reinforcement_cooldown - delta)
	_adapt_log_cooldown = maxf(0.0, _adapt_log_cooldown - delta)
	_tick_timer += delta
	if _tick_timer < 8.0:
		return
	_tick_timer = 0.0
	if disturbance_sectors.is_empty():
		return
	if _reinforcement_cooldown > 0.0:
		return
	var sector: String = disturbance_sectors[disturbance_sectors.size() - 1]
	_spawn_counter_wave(sector)
	_reinforcement_cooldown = 18.0


func _schedule_adjacent_reinforcement(sector: String) -> void:
	if not tactical_map or not tactical_map.has_method("log_message"):
		return
	var adjacent := _adjacent_sectors(sector)
	if adjacent.is_empty():
		return
	if _adapt_log_cooldown > 0.0:
		return
	var target: String = adjacent[0]
	_adapt_log_cooldown = 12.0
	tactical_map.log_message(
		"SWARM ADAPT: pressure shifting toward %s sector." % target,
		GameTheme.ACCENT_WARN.to_html(),
		"alert",
	)


func _spawn_counter_wave(sector: String) -> void:
	if not tactical_map or not tactical_map.has_method("register_spawned_enemy"):
		return
	if not tactical_map.has_method("get_rooms_in_sector"):
		return
	var rooms: Array = tactical_map.get_rooms_in_sector(sector)
	if rooms.is_empty():
		return
	var room = rooms[0]
	if not tactical_map.has_method("spawn_swarm_counter_enemy"):
		return
	tactical_map.spawn_swarm_counter_enemy(room, pick_counter_archetype())


static func _adjacent_sectors(sector: String) -> Array[String]:
	match sector:
		"north":
			return ["central", "east", "west"]
		"south":
			return ["central", "east", "west"]
		"east":
			return ["central", "north", "south"]
		"west":
			return ["central", "north", "south"]
		_:
			return ["north", "south", "east", "west"]
