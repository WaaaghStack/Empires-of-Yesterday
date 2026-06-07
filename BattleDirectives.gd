class_name BattleDirectives
extends RefCounted

enum Type { NONE, RETREAT, FOCUS_CP, HOLD_LINE, COMMANDER_ABILITY }

var active_type: Type = Type.NONE
var active_cp_id: String = ""
var ability_cooldown: float = 0.0
var focus_timer: float = 0.0
var hold_timer: float = 0.0
var damage_mult: float = 1.0
var move_mult: float = 1.0
var morale_buff: float = 0.0


func reset() -> void:
	active_type = Type.NONE
	active_cp_id = ""
	ability_cooldown = 0.0
	focus_timer = 0.0
	hold_timer = 0.0
	damage_mult = 1.0
	move_mult = 1.0
	morale_buff = 0.0


func tick(delta: float) -> void:
	ability_cooldown = maxf(0.0, ability_cooldown - delta)
	if focus_timer > 0.0:
		focus_timer = maxf(0.0, focus_timer - delta)
	elif hold_timer > 0.0:
		hold_timer = maxf(0.0, hold_timer - delta)
	elif active_type != Type.RETREAT:
		damage_mult = 1.0
		move_mult = 1.0
		morale_buff = 0.0


func get_turn_modifiers() -> Dictionary:
	var hostile_damage_mult := 1.0
	var casualty_reduction := 0.0
	match active_type:
		Type.FOCUS_CP:
			damage_mult = 1.12
			morale_buff = 2.0
			move_mult = 1.1
		Type.HOLD_LINE:
			damage_mult = 0.9
			casualty_reduction = 0.1
			morale_buff = 3.0
		Type.COMMANDER_ABILITY:
			damage_mult = maxf(damage_mult, 1.18)
			morale_buff = 4.0
		Type.RETREAT:
			damage_mult = 0.8
			move_mult = 1.15
			casualty_reduction = 0.05
	return {
		"damage_mult": damage_mult,
		"hostile_damage_mult": hostile_damage_mult,
		"casualty_reduction": casualty_reduction,
		"morale_buff": morale_buff,
		"move_mult": move_mult,
	}


func request_retreat() -> void:
	active_type = Type.RETREAT
	move_mult = 1.15
	damage_mult = 0.8


func request_focus_cp(cp_id: String) -> void:
	active_type = Type.FOCUS_CP
	active_cp_id = cp_id
	focus_timer = 12.0
	damage_mult = 1.12
	morale_buff = 2.0


func request_hold_line() -> void:
	active_type = Type.HOLD_LINE
	hold_timer = 10.0
	damage_mult = 0.9
	morale_buff = 3.0


func request_commander_ability(profile: Dictionary) -> bool:
	if ability_cooldown > 0.0:
		return false
	ability_cooldown = 25.0
	active_type = Type.COMMANDER_ABILITY
	match str(profile.get("ability_id", "")):
		"orbital_strike":
			damage_mult = 1.35
			focus_timer = 6.0
		"fortify_line":
			request_hold_line()
		"supply_drop":
			damage_mult = 1.1
			morale_buff = 5.0
			focus_timer = 8.0
		_:
			damage_mult = 1.2
			morale_buff = 2.0
	return true
