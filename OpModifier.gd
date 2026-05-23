class_name OpModifier
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var credit_bonus: float = 0.0
@export var enemy_speed_mult: float = 1.0
@export var enemy_damage_bonus: int = 0
@export var ability_cooldown_reduction: float = 0.0
@export var fog_reveal_mult: float = 1.0
@export var marine_speed_mult: float = 1.0
@export var scavenge_credit_mult: float = 1.0
@export var hold_duration_mult: float = 1.0
@export var evac_search_reduction: int = 0
@export var synergy_objective: String = ""
@export var synergy_credit_bonus: float = 0.0


static func tight_timers() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "tight_timers"
	mod.display_name = "Tight Timers"
	mod.description = "+20% enemy speed, +30% run credits earned."
	mod.credit_bonus = 0.3
	mod.enemy_speed_mult = 1.2
	return mod


static func blackout() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "blackout"
	mod.display_name = "Blackout"
	mod.description = "Fog reveals slower, +bonus intel on debrief."
	mod.fog_reveal_mult = 0.65
	mod.credit_bonus = 0.15
	return mod


static func overcharged() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "overcharged"
	mod.display_name = "Overcharged"
	mod.description = "Abilities -4s cooldown, enemies deal +1 damage."
	mod.ability_cooldown_reduction = 4.0
	mod.enemy_damage_bonus = 1
	return mod


static func silent_running() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "silent_running"
	mod.display_name = "Silent Running"
	mod.description = "-30% marine speed. Silent Extract pays +35% credits."
	mod.marine_speed_mult = 0.7
	mod.synergy_objective = "silent_extract"
	mod.synergy_credit_bonus = 0.35
	return mod


static func deep_sweep() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "deep_sweep"
	mod.display_name = "Deep Sweep"
	mod.description = "Scavenge caches pay double. Enemies move +10% faster."
	mod.scavenge_credit_mult = 2.0
	mod.enemy_speed_mult = 1.1
	mod.synergy_objective = "scavenge"
	return mod


static func fortified_hold() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "fortified_hold"
	mod.display_name = "Fortified Hold"
	mod.description = "Hold & Purge timer -15%. Hostiles +15% speed."
	mod.hold_duration_mult = 0.85
	mod.enemy_speed_mult = 1.15
	mod.synergy_objective = "hold_purge"
	return mod


static func ghost_protocol() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "ghost_protocol"
	mod.display_name = "Ghost Protocol"
	mod.description = "Silent Extract needs 1 fewer search. Fog -20%."
	mod.evac_search_reduction = 1
	mod.fog_reveal_mult = 0.8
	mod.synergy_objective = "silent_extract"
	return mod


static func asset_recovery() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "asset_recovery"
	mod.display_name = "Asset Recovery"
	mod.description = "Standard ops pay +25% credits. Marines -10% speed."
	mod.synergy_objective = "standard"
	mod.synergy_credit_bonus = 0.25
	mod.marine_speed_mult = 0.9
	return mod


static func hot_insert() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "hot_insert"
	mod.display_name = "Hot Insert"
	mod.description = "+25% run credits. Hostiles deal +1 damage."
	mod.credit_bonus = 0.25
	mod.enemy_damage_bonus = 1
	return mod


static func scorched_earth() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "scorched_earth"
	mod.display_name = "Scorched Earth"
	mod.description = "Hold & Purge pays +30% credits. Hold timer +10%."
	mod.synergy_objective = "hold_purge"
	mod.synergy_credit_bonus = 0.3
	mod.hold_duration_mult = 1.1
	return mod


static func data_purge() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "data_purge"
	mod.display_name = "Data Purge"
	mod.description = "Black Site pays +30% credits. Hostiles +10% speed."
	mod.synergy_objective = "black_site"
	mod.synergy_credit_bonus = 0.3
	mod.enemy_speed_mult = 1.1
	return mod


static func extraction_team() -> OpModifier:
	var mod := OpModifier.new()
	mod.id = "extraction_team"
	mod.display_name = "Extraction Team"
	mod.description = "VIP Recovery pays +25% credits. Marines -5% speed."
	mod.synergy_objective = "vip_recovery"
	mod.synergy_credit_bonus = 0.25
	mod.marine_speed_mult = 0.95
	return mod


static func all_modifiers() -> Array[OpModifier]:
	return [
		tight_timers(),
		blackout(),
		overcharged(),
		silent_running(),
		deep_sweep(),
		fortified_hold(),
		ghost_protocol(),
		asset_recovery(),
		hot_insert(),
		scorched_earth(),
		data_purge(),
		extraction_team(),
	]


static func pick_random_three(_rng: RandomNumberGenerator) -> Array[OpModifier]:
	var pool: Array[OpModifier] = all_modifiers()
	pool.shuffle()
	var result: Array[OpModifier] = []
	for i in range(mini(3, pool.size())):
		result.append(pool[i])
	return result


func get_credit_multiplier_for_objective(objective_template: String) -> float:
	var mult := 1.0 + credit_bonus
	if not synergy_objective.is_empty() and synergy_objective == objective_template:
		mult += synergy_credit_bonus
	return mult
