class_name BattleCombatResolver
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")
const BattleSimTierPolicyLib := preload("res://BattleSimTierPolicy.gd")

const FATIGUE_UNCONSCIOUS := 100.0
const FATIGUE_DEATH := 200.0

var _rng := RandomNumberGenerator.new()
var _melee_rr: int = 0


func setup(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	_melee_rr = 0


func drn(base: int) -> int:
	var b: int = maxi(0, base)
	return b + _rng.randi_range(0, b)


func resolve_melee(store, attacker_idx: int, defender_idx: int) -> float:
	if not BattleSimTierPolicyLib.can_participate_in_combat(store, attacker_idx):
		return 0.0
	if not BattleSimTierPolicyLib.can_participate_in_combat(store, defender_idx):
		return 0.0
	if not store.is_alive(attacker_idx) or not store.is_alive(defender_idx):
		return 0.0
	var atk_roll: int = drn(store.unit_attack[attacker_idx])
	var def_roll: int = drn(store.unit_defense[defender_idx])
	if atk_roll <= def_roll:
		store.fatigue[attacker_idx] = minf(
			FATIGUE_DEATH, store.fatigue[attacker_idx] + float(store.encumbrance[attacker_idx]) * 0.5
		)
		return 0.0
	var dmg_roll: int = drn(store.unit_strength[attacker_idx])
	var prot_roll: int = drn(store.protection[defender_idx])
	var damage: float = float(maxi(1, dmg_roll - prot_roll))
	store.fatigue[attacker_idx] = minf(
		FATIGUE_DEATH, store.fatigue[attacker_idx] + float(store.encumbrance[attacker_idx])
	)
	_apply_fatigue_effects(store, attacker_idx)
	_apply_fatigue_effects(store, defender_idx)
	return damage


func resolve_ranged_at_cell(store, cell_grid: BattleCellGridLib, shooter_idx: int, gx: int, gy: int) -> int:
	if not BattleSimTierPolicyLib.can_participate_in_combat(store, shooter_idx):
		return -1
	if not store.is_alive(shooter_idx) or store.ranged[shooter_idx] == 0:
		return -1
	var hit_roll: int = drn(store.precision[shooter_idx])
	var target_idx: int = _pick_target_in_cell(store, gx, gy, shooter_idx, hit_roll, cell_grid)
	if target_idx < 0:
		return -1
	var dmg_roll: int = drn(store.unit_strength[shooter_idx])
	var prot_roll: int = drn(store.protection[target_idx])
	var damage: float = float(maxi(1, dmg_roll - prot_roll))
	store.apply_damage(target_idx, damage, shooter_idx)
	return target_idx


func run_melee_phase(
	store,
	cell_grid: BattleCellGridLib,
	pairs: Array,
	max_swings: int,
	fighters_per_edge: int,
) -> void:
	var swings := 0
	var combatants: Array = []
	for pair in pairs:
		if swings >= max_swings:
			break
		_collect_adjacent_fighters_sampled(store, cell_grid, pair, combatants, fighters_per_edge)
	for entry in combatants:
		if swings >= max_swings:
			break
		var atk: int = int(entry["attacker"])
		var def: int = int(entry["defender"])
		if not store.is_alive(atk) or not store.is_alive(def):
			continue
		var dmg: float = resolve_melee(store, atk, def)
		if dmg > 0.0:
			store.apply_damage(def, dmg, atk)
		swings += 1


func run_ranged_phase(
	store,
	cell_grid: BattleCellGridLib,
	archers_friendly: PackedInt32Array,
	archers_hostile: PackedInt32Array,
	max_shots: int,
) -> void:
	var shots := 0
	var shooters: Array = []
	for i in archers_friendly.size():
		shooters.append(archers_friendly[i])
	for i in archers_hostile.size():
		shooters.append(archers_hostile[i])
	shooters.sort_custom(func(a, b): return store.combat_speed[int(a)] > store.combat_speed[int(b)])
	for shooter in shooters:
		if shots >= max_shots:
			break
		var sidx: int = int(shooter)
		if not BattleSimTierPolicyLib.can_participate_in_combat(store, sidx):
			continue
		var target: Vector2i = _ranged_target_cell_indexed(store, cell_grid, sidx)
		if target.x < 0:
			continue
		resolve_ranged_at_cell(store, cell_grid, sidx, target.x, target.y)
		shots += 1


func _collect_adjacent_fighters_sampled(
	store,
	cell_grid: BattleCellGridLib,
	pair: Dictionary,
	out: Array,
	per_side_cap: int,
) -> void:
	var gx: int = int(pair.get("gx", 0))
	var gy: int = int(pair.get("gy", 0))
	var nx: int = int(pair.get("nx", 0))
	var ny: int = int(pair.get("ny", 0))
	var a_units: PackedInt32Array = cell_grid.units_at(gx, gy)
	var b_units: PackedInt32Array = cell_grid.units_at(nx, ny)
	var a_f: Array = _top_fighters(store, a_units, per_side_cap)
	var b_f: Array = _top_fighters(store, b_units, per_side_cap)
	for ai in a_f:
		for bi in b_f:
			if store.side[int(ai)] == store.side[int(bi)]:
				continue
			var friendly_is_a: bool = store.side[int(ai)] == UnitSimulationStoreLib.Side.FRIENDLY
			var atk_f: int = int(ai) if friendly_is_a else int(bi)
			var def_f: int = int(bi) if friendly_is_a else int(ai)
			var slot: int = (_melee_rr + atk_f + def_f) % 999983
			_melee_rr = slot + 1
			out.append({"attacker": atk_f, "defender": def_f, "speed": store.combat_speed[atk_f], "slot": slot})


func _top_fighters(store, units: PackedInt32Array, cap: int) -> Array:
	var pool: Array = []
	for u in units:
		var idx: int = int(u)
		if not BattleSimTierPolicyLib.can_participate_in_combat(store, idx):
			continue
		pool.append({"idx": idx, "speed": store.combat_speed[idx]})
	if pool.is_empty():
		return []
	pool.sort_custom(func(a, b): return int(a["speed"]) > int(b["speed"]))
	var out: Array = []
	for i in range(mini(cap, pool.size())):
		out.append(pool[i]["idx"])
	return out


func _pick_target_in_cell(
	store,
	gx: int,
	gy: int,
	shooter_idx: int,
	hit_roll: int,
	cell_grid: BattleCellGridLib = null,
) -> int:
	var candidates: Array = []
	var units: PackedInt32Array = (
		cell_grid.units_at(gx, gy) if cell_grid != null else PackedInt32Array()
	)
	if units.is_empty():
		for i in range(store.count):
			if store.grid_x[i] == gx and store.grid_y[i] == gy:
				units.append(i)
	for u in units:
		var idx: int = int(u)
		if not store.is_alive(idx):
			continue
		if store.side[idx] == store.side[shooter_idx]:
			continue
		if not BattleSimTierPolicyLib.can_participate_in_combat(store, idx):
			continue
		candidates.append(idx)
	if candidates.is_empty():
		return -1
	var pick: int = candidates[_rng.randi() % candidates.size()]
	if hit_roll < drn(store.unit_defense[pick]):
		return -1
	return int(pick)


func _ranged_target_cell_indexed(store, cell_grid: BattleCellGridLib, shooter_idx: int) -> Vector2i:
	var sx: int = store.grid_x[shooter_idx]
	var sy: int = store.grid_y[shooter_idx]
	var rng: int = store.range_cells[shooter_idx]
	var enemy_side: int = (
		UnitSimulationStoreLib.Side.HOSTILE
		if store.side[shooter_idx] == UnitSimulationStoreLib.Side.FRIENDLY
		else UnitSimulationStoreLib.Side.FRIENDLY
	)
	var best := Vector2i(-1, -1)
	var best_dist: int = 99999
	for d in range(1, rng + 1):
		for gx in range(maxi(0, sx - d), mini(cell_grid.width, sx + d + 1)):
			for gy in range(maxi(0, sy - d), mini(cell_grid.height, sy + d + 1)):
				if absi(gx - sx) + absi(gy - sy) != d:
					continue
				var has_target := false
				if enemy_side == UnitSimulationStoreLib.Side.FRIENDLY:
					has_target = cell_grid.friendly_count_at_cell(gx, gy) > 0
				else:
					has_target = cell_grid.hostile_count_at_cell(gx, gy) > 0
				if not has_target:
					continue
				if d < best_dist:
					best_dist = d
					best = Vector2i(gx, gy)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _apply_fatigue_effects(store, idx: int) -> void:
	if store.fatigue[idx] >= FATIGUE_DEATH:
		store.apply_damage(idx, store.health[idx])
	elif store.fatigue[idx] >= FATIGUE_UNCONSCIOUS:
		store.combat_speed[idx] = maxi(2, store.combat_speed[idx] / 2)
