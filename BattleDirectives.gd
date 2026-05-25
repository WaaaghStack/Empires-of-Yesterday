class_name BattleDirectives
extends RefCounted

enum Type { NONE, RETREAT, FOCUS_SECTOR, HOLD_LINE, COMMANDER_ABILITY }

var active_type: Type = Type.NONE
var active_sector_id: String = ""
var ability_cooldown: float = 0.0
var focus_timer: float = 0.0
var hold_timer: float = 0.0
var damage_mult: float = 1.0
var move_mult: float = 1.0


func reset() -> void:
	active_type = Type.NONE
	active_sector_id = ""
	ability_cooldown = 0.0
	focus_timer = 0.0
	hold_timer = 0.0
	damage_mult = 1.0
	move_mult = 1.0


func tick(delta: float) -> void:
	ability_cooldown = maxf(0.0, ability_cooldown - delta)
	if focus_timer > 0.0:
		focus_timer = maxf(0.0, focus_timer - delta)
		damage_mult = 1.15
		move_mult = 1.2
	elif hold_timer > 0.0:
		hold_timer = maxf(0.0, hold_timer - delta)
		damage_mult = 0.85
		move_mult = 0.7
	else:
		if active_type != Type.RETREAT:
			damage_mult = 1.0
			move_mult = 1.0


func request_retreat() -> void:
	active_type = Type.RETREAT
	move_mult = 1.35
	damage_mult = 0.75


func request_focus_sector(sector_id: String) -> void:
	active_type = Type.FOCUS_SECTOR
	active_sector_id = sector_id
	focus_timer = 12.0


func request_hold_line() -> void:
	active_type = Type.HOLD_LINE
	hold_timer = 10.0


func request_commander_ability(profile: Dictionary) -> bool:
	if ability_cooldown > 0.0:
		return false
	ability_cooldown = 25.0
	active_type = Type.COMMANDER_ABILITY
	match str(profile.get("ability_id", "")):
		"orbital_strike":
			damage_mult = 1.4
			focus_timer = 6.0
		"fortify_line":
			request_hold_line()
		"supply_drop":
			move_mult = 1.25
			focus_timer = 8.0
		_:
			damage_mult = 1.2
	return true


func apply_to_manager(manager: UnitSimulationManager) -> void:
	if manager == null or manager.store == null:
		return
	for i in range(manager.store.count):
		if not manager.store.is_alive(i):
			continue
		if manager.store.side[i] != UnitSimulationStore.Side.FRIENDLY:
			continue
		if active_type == Type.FOCUS_SECTOR and not active_sector_id.is_empty():
			var target_idx := manager.store.room_index_for_id(active_sector_id)
			if target_idx >= 0:
				manager.store.target_room_index[i] = target_idx
		elif active_type == Type.RETREAT:
			manager.store.target_room_index[i] = 0
