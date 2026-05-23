class_name MissionState
extends RefCounted

static var squad_marked_target: Node2D = null
static var squad_mark_timer: float = 0.0

static func is_unit_actions_frozen(node: Node) -> bool:
	for tactical_map in node.get_tree().get_nodes_in_group("tactical_map"):
		if tactical_map.mission_complete or not tactical_map.game_active:
			return true
		return tactical_map.is_paused
	return false

static func is_attackable_target(target: Node2D) -> bool:
	if not target or not is_instance_valid(target):
		return false
	if target is EnemyUnit:
		return target.is_alive
	if target is Hive:
		return target.is_attackable()
	return false

static func set_squad_mark(target: Node2D, duration: float = 10.0) -> void:
	clear_squad_mark()
	squad_marked_target = target
	squad_mark_timer = duration
	if target and target.has_method("set_focus_marked"):
		target.set_focus_marked(true, duration)

static func set_squad_mark_enemy(enemy: EnemyUnit, duration: float = 10.0) -> void:
	set_squad_mark(enemy, duration)

static func tick_squad_mark(delta: float) -> void:
	if squad_mark_timer <= 0.0:
		return
	squad_mark_timer = maxf(0.0, squad_mark_timer - delta)
	if squad_mark_timer <= 0.0 or not is_attackable_target(squad_marked_target):
		clear_squad_mark()

static func clear_squad_mark() -> void:
	if is_instance_valid(squad_marked_target) and squad_marked_target.has_method("set_focus_marked"):
		squad_marked_target.set_focus_marked(false)
	squad_marked_target = null
	squad_mark_timer = 0.0

static func reset_mission() -> void:
	clear_squad_mark()
