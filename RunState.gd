# RunState.gd — autoload singleton for hybrid roguelite runs.
extends Node

const OBJECTIVE_TEMPLATES: Array[String] = [
	"standard", "silent_extract", "scavenge", "hold_purge", "black_site", "vip_recovery", "hive_purge",
]

const SQUAD_COUNT := 3
const OPERATORS_PER_SQUAD := 4
const ROSTER_SIZE := SQUAD_COUNT * OPERATORS_PER_SQUAD
const SQUAD_IDS: Array[String] = ["alpha", "bravo", "charlie"]

const INTEL_COSTS: Dictionary = {
	"reveal_room": 25,
	"extraction_hint": 35,
	"enemy_scan": 30,
}
const RECRUIT_COST := 55

const ROOKIE_CALLSIGNS: Array[String] = [
	"Rook", "Holt", "Nash", "Cruz", "Reed", "Blake", "Sato", "Kim", "Ortiz", "Hayes",
]

var run_active: bool = false
var op_index: int = 1
var ops_per_run: int = 4
var run_seed: int = 0
var squad: Array[SoldierResource] = []
var squad_assignments: Dictionary = {}
var deploy_assignments: Dictionary = {}
var active_squad_id: String = "alpha"
var cleared_ops: int = 0
var run_credits: int = 0
const OpModifierLib := preload("res://OpModifier.gd")
const RunAugmentLib := preload("res://RunAugment.gd")

var active_modifier: OpModifierLib = null
var active_run_augment: RunAugmentLib = null
var pending_intel: Dictionary = {}
var objective_template: String = "standard"
var last_mission_stats: Dictionary = {}
var daily_seed_mode: bool = false
var run_total_elapsed: float = 0.0
var run_total_casualties: int = 0

var _rng := RandomNumberGenerator.new()


func start_run(squad_resources: Array[SoldierResource], seed_override: int = -1, use_daily_seed: bool = false) -> void:
	run_active = true
	op_index = 1
	cleared_ops = 0
	run_credits = 0
	squad.clear()
	for res in squad_resources:
		var copy: SoldierResource = res.duplicate_for_deploy()
		copy.reset_for_new_run()
		squad.append(copy)
	_init_squad_assignments()
	daily_seed_mode = use_daily_seed
	if seed_override >= 0:
		run_seed = seed_override
	elif use_daily_seed:
		run_seed = _daily_seed_value()
	else:
		_rng.randomize()
		run_seed = _rng.randi()
	active_modifier = null
	active_run_augment = null
	pending_intel.clear()
	objective_template = _pick_objective_template()
	deploy_assignments.clear()
	active_squad_id = "alpha"
	last_mission_stats = {}
	run_total_elapsed = 0.0
	run_total_casualties = 0


func sync_from_units(units: Array) -> void:
	for unit in units:
		if not unit is SoldierUnit:
			continue
		var soldier_unit: SoldierUnit = unit as SoldierUnit
		if not soldier_unit.source_resource:
			continue
		var roster: SoldierResource = _find_squad_member(soldier_unit.source_resource)
		if not roster:
			continue
		if soldier_unit.is_alive:
			roster.current_hp = soldier_unit.current_health
			roster.is_kia = false
			roster.is_injured = roster.current_hp < roster.health
		else:
			roster.is_kia = true
			roster.current_hp = 0
		roster.portrait = soldier_unit.portrait


func _find_squad_member(source: SoldierResource) -> SoldierResource:
	for member in squad:
		if member.soldier_name == source.soldier_name and member.marine_class == source.marine_class:
			return member
	return null


func next_op_seed() -> int:
	return run_seed + op_index * 7919


func advance_after_success() -> void:
	cleared_ops += 1
	op_index += 1
	objective_template = _pick_objective_template()


func end_run() -> void:
	run_active = false
	active_modifier = null
	active_run_augment = null
	pending_intel.clear()
	last_mission_stats = {}


func has_ops_remaining() -> bool:
	return op_index < ops_per_run


func living_squad_count() -> int:
	var count := 0
	for member in squad:
		if not member.is_kia:
			count += 1
	return count


func is_squad_wiped() -> bool:
	return living_squad_count() == 0


func kia_squad_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(squad.size()):
		if squad[i].is_kia:
			indices.append(i)
	return indices


func has_kia_members() -> bool:
	return not kia_squad_indices().is_empty()


func get_heal_efficiency_mult() -> float:
	var mult := 1.0
	if active_run_augment and active_run_augment.id == "docs_kit":
		mult += 0.1
	return mult


func heal_squad_member(index: int, percent: float) -> bool:
	if index < 0 or index >= squad.size():
		return false
	var member: SoldierResource = squad[index]
	if member.is_kia:
		return false
	var max_hp: int = member.health
	var heal_amount: int = int(max_hp * percent * get_heal_efficiency_mult())
	member.current_hp = mini(max_hp, member.get_deploy_hp() + heal_amount)
	member.is_injured = member.current_hp < max_hp
	return true


func heal_all_squad(percent: float, cost: int) -> bool:
	if run_credits < cost:
		return false
	run_credits -= cost
	for i in range(squad.size()):
		heal_squad_member(i, percent)
	return true


func can_pick_run_augment() -> bool:
	return op_index >= 2 and active_run_augment == null


func pick_run_augment(aug: RunAugmentLib) -> void:
	active_run_augment = aug


func has_run_augment(augment_id: String) -> bool:
	return active_run_augment != null and active_run_augment.id == augment_id


func get_intel_cost(intel_type: String) -> int:
	var base_cost: int = int(INTEL_COSTS.get(intel_type, 0))
	if base_cost <= 0:
		return 0
	if has_run_augment("field_intel"):
		base_cost = maxi(5, base_cost - 5)
	return base_cost


func has_pending_intel(intel_type: String) -> bool:
	return bool(pending_intel.get(intel_type, false))


func purchase_intel(intel_type: String) -> bool:
	if not INTEL_COSTS.has(intel_type):
		return false
	if has_pending_intel(intel_type):
		return false
	var cost := get_intel_cost(intel_type)
	if run_credits < cost:
		return false
	run_credits -= cost
	pending_intel[intel_type] = true
	return true


func consume_pending_intel(intel_type: String) -> bool:
	if not has_pending_intel(intel_type):
		return false
	pending_intel[intel_type] = false
	return true


func generate_kia_replacement_draft() -> Array[SoldierResource]:
	_rng.randomize()
	var classes: Array = SoldierResource.MarineClass.values()
	classes.shuffle()
	var picks: Array[SoldierResource] = []
	var used_names: Dictionary = {}
	for member in squad:
		used_names[member.soldier_name] = true
	for marine_class in classes:
		if picks.size() >= 2:
			break
		picks.append(_make_injured_rookie(marine_class, used_names))
	return picks


func replace_kia_member(slot_index: int, rookie: SoldierResource) -> bool:
	if slot_index < 0 or slot_index >= squad.size():
		return false
	if not squad[slot_index].is_kia:
		return false
	if run_credits < RECRUIT_COST:
		return false
	run_credits -= RECRUIT_COST
	squad[slot_index] = rookie.duplicate_for_deploy()
	return true


func award_post_mission_bonuses() -> int:
	if has_run_augment("spare_parts"):
		return 5
	return 0


func record_mission_stats(stats: Dictionary) -> void:
	last_mission_stats = stats.duplicate(true)
	run_total_elapsed += float(stats.get("time_seconds", stats.get("elapsed", 0.0)))
	run_total_casualties += int(stats.get("casualties", 0))


func get_difficulty_config() -> Dictionary:
	var map_tier := "medium"
	if op_index >= 3 and op_index < ops_per_run:
		map_tier = "large"
	elif op_index >= ops_per_run:
		map_tier = "finale"
	return {
		"op_index": op_index,
		"objective_template": objective_template,
		"difficulty_tier": op_index,
		"map_tier": map_tier,
		"squad_count": SQUAD_COUNT,
		"modifier": active_modifier,
	}


func get_squad_id_for_index(index: int) -> String:
	if squad_assignments.has(index):
		return str(squad_assignments[index])
	var squad_idx: int = int(float(index) / float(OPERATORS_PER_SQUAD))
	return SQUAD_IDS[clampi(squad_idx, 0, SQUAD_IDS.size() - 1)]


func assign_operator_to_squad(index: int, squad_id: String) -> void:
	if index < 0 or index >= squad.size():
		return
	if squad_id not in SQUAD_IDS:
		return
	squad_assignments[index] = squad_id
	if index < squad.size():
		squad[index].squad_id = squad_id


func operators_in_squad(squad_id: String) -> Array[SoldierResource]:
	var result: Array[SoldierResource] = []
	for i in range(squad.size()):
		if get_squad_id_for_index(i) == squad_id:
			result.append(squad[i])
	return result


func get_unlocked_marine_classes() -> Array:
	var pool: Array = []
	for marine_class in SoldierResource.MarineClass.values():
		if SaveManager.is_class_unlocked(marine_class):
			pool.append(marine_class)
	if pool.is_empty():
		pool.append(SoldierResource.MarineClass.ASSAULT)
		pool.append(SoldierResource.MarineClass.SUPPORT)
	return pool


func generate_squad(squad_id: String, used_names: Dictionary = {}) -> Array[SoldierResource]:
	_rng.randomize()
	var operators: Array[SoldierResource] = []
	var class_pool := get_unlocked_marine_classes()
	var templates := SoldierResource.get_roster_operators()
	for slot in range(OPERATORS_PER_SQUAD):
		var marine_class = class_pool[_rng.randi() % class_pool.size()]
		var op := SoldierResource.new()
		op.marine_class = marine_class
		SoldierResource.apply_class_defaults(op)
		op.squad_id = squad_id
		op.soldier_name = _pick_rookie_name(used_names)
		used_names[op.soldier_name] = true
		if not templates.is_empty():
			var template: SoldierResource = templates[slot % templates.size()]
			op.default_order = template.default_order
		operators.append(op)
	var portraits: Array[Texture2D] = get_node("/root/PortraitPool").get_random_unlocked_portraits(OPERATORS_PER_SQUAD)
	for i in range(operators.size()):
		if i < portraits.size():
			operators[i].portrait = portraits[i]
	return operators


func generate_full_roster() -> Array[SoldierResource]:
	var roster: Array[SoldierResource] = []
	var used_names: Dictionary = {}
	for squad_id in SQUAD_IDS:
		for op in generate_squad(squad_id, used_names):
			roster.append(op)
	return roster


func _init_squad_assignments() -> void:
	squad_assignments.clear()
	for i in range(squad.size()):
		var squad_id: String = SQUAD_IDS[int(float(i) / float(OPERATORS_PER_SQUAD))]
		squad_assignments[i] = squad_id
		squad[i].squad_id = squad_id


func _make_injured_rookie(marine_class: SoldierResource.MarineClass, used_names: Dictionary) -> SoldierResource:
	var rookie := SoldierResource.new()
	rookie.marine_class = marine_class
	SoldierResource.apply_class_defaults(rookie)
	rookie.health = maxi(50, int(rookie.health * 0.85))
	rookie.damage = maxi(8, int(rookie.damage * 0.85))
	rookie.defense = maxi(3, int(rookie.defense * 0.9))
	rookie.current_hp = maxi(1, int(rookie.health * 0.65))
	rookie.is_injured = true
	rookie.is_kia = false
	rookie.soldier_name = _pick_rookie_name(used_names)
	used_names[rookie.soldier_name] = true
	var portraits: Array[Texture2D] = get_node("/root/PortraitPool").get_random_unlocked_portraits(1)
	if not portraits.is_empty():
		rookie.portrait = portraits[0]
	return rookie


func _pick_rookie_name(used_names: Dictionary) -> String:
	var pool := ROOKIE_CALLSIGNS.duplicate()
	pool.shuffle()
	for callsign in pool:
		if not used_names.has(callsign):
			return callsign
	return "Rookie-%d" % (_rng.randi() % 900 + 100)


func _pick_objective_template() -> String:
	_rng.randomize()
	return OBJECTIVE_TEMPLATES[_rng.randi() % OBJECTIVE_TEMPLATES.size()]


func get_daily_seed() -> int:
	return _daily_seed_value()


func _daily_seed_value() -> int:
	var today := Time.get_date_dict_from_system()
	return hash("%04d-%02d-%02d" % [today.year, today.month, today.day]) & 0x7FFFFFFF
