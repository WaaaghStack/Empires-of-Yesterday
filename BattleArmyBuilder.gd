class_name BattleArmyBuilder
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")
const BattleMapPlacementLib := preload("res://BattleMapPlacement.gd")
const BattleFormationPlacementLib := preload("res://BattleFormationPlacement.gd")
const BattleCompositionLib := preload("res://BattleComposition.gd")
const BattleSquadLib := preload("res://BattleSquad.gd")
const BattleCommanderLib := preload("res://BattleCommander.gd")
const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")
const BattleSimTierPolicyLib := preload("res://BattleSimTierPolicy.gd")
const BattleArmyScaleLib := preload("res://BattleArmyScale.gd")

const SQUAD_TARGET_SIZE := 100
const MAX_SPAWN_PER_SIDE := 2200


static func build_army(
	store: UnitSimulationStoreLib,
	battle_data,
	player_count: int,
	enemy_count: int,
	rng: RandomNumberGenerator,
	cell_grid = null,
) -> Dictionary:
	var squads: Array = []
	var commanders: Array = []
	if store == null or battle_data == null:
		return {"squads": squads, "commanders": commanders}
	BattleMapPlacementLib.build_rally_spawn_cells(battle_data)
	var scale: Dictionary = BattleArmyScaleLib.sim_units_for_battle(player_count, enemy_count)
	var p_spawn: int = mini(maxi(1, int(scale.get("player_sim", player_count))), MAX_SPAWN_PER_SIDE)
	var e_spawn: int = mini(maxi(1, int(scale.get("enemy_sim", enemy_count))), MAX_SPAWN_PER_SIDE)
	var p_arch := BattleCompositionLib.build_archetype_list(p_spawn, rng)
	var e_arch := BattleCompositionLib.build_archetype_list(e_spawn, rng)
	var p_units: Array[int] = _spawn_side(
		store, battle_data, cell_grid, UnitSimulationStoreLib.Side.FRIENDLY, p_spawn, p_arch
	)
	var e_units: Array[int] = _spawn_side(
		store, battle_data, cell_grid, UnitSimulationStoreLib.Side.HOSTILE, e_spawn, e_arch
	)
	squads = _group_squads(p_units, UnitSimulationStoreLib.Side.FRIENDLY)
	squads.append_array(_group_squads(e_units, UnitSimulationStoreLib.Side.HOSTILE))
	commanders = _place_commanders(store, battle_data, p_units, e_units, rng)
	for s in squads:
		for idx in s.unit_indices:
			store.squad_index[idx] = s.id
	for cmd in commanders:
		if cmd.unit_index >= 0 and cmd.unit_index < store.count:
			store.commander_index[cmd.unit_index] = cmd.id
	return {"squads": squads, "commanders": commanders, "player_spawned": p_spawn, "enemy_spawned": e_spawn}


static func _spawn_side(
	store: UnitSimulationStoreLib,
	battle_data,
	cell_grid,
	side: int,
	target: int,
	archetypes: PackedInt32Array,
) -> Array[int]:
	var indices: Array[int] = []
	var occupied: Dictionary = {}
	for slot in range(target):
		var arch_idx: int = archetypes[slot % archetypes.size()] if archetypes.size() > 0 else 0
		var def = BattleUnitCatalogLib.get_by_archetype(arch_idx)
		var unit_size: int = maxi(1, def.size)
		var g: Vector2i = BattleFormationPlacementLib.spawn_cell_for_unit(
			battle_data, side, slot, target, occupied, cell_grid, unit_size
		)
		if g.x < 0:
			var zone: Rect2 = (
				battle_data.player_spawn_zone
				if side == UnitSimulationStoreLib.Side.FRIENDLY
				else battle_data.enemy_spawn_zone
			)
			g = BattleMapPlacementLib.find_open_cell_in_zone(
				battle_data, zone, side, slot, occupied, cell_grid, unit_size
			)
		if g.x < 0:
			continue
		var unit_tier: int = BattleSimTierPolicyLib.spawn_tier_for_slot(
			slot, target, battle_data.contact_column, g.x
		)
		var idx: int = store.spawn_from_definition(side, g.x, g.y, battle_data, def, slot % 8, unit_tier)
		if idx >= 0:
			indices.append(idx)
			if cell_grid != null:
				cell_grid.add_unit(idx, g.x, g.y, store.size[idx], side)
	return indices


static func _group_squads(unit_indices: Array[int], side: int) -> Array:
	var squads: Array = []
	if unit_indices.is_empty():
		return squads
	var squad_id := 0
	var bucket: Array[int] = []
	for idx in unit_indices:
		bucket.append(idx)
		if bucket.size() >= SQUAD_TARGET_SIZE:
			var sq := BattleSquadLib.new(squad_id, side)
			sq.unit_indices = bucket.duplicate()
			sq.order = BattleOrderTypesLib.SquadOrder.ADVANCE_CONTACT
			squads.append(sq)
			squad_id += 1
			bucket.clear()
	if not bucket.is_empty():
		var sq := BattleSquadLib.new(squad_id, side)
		sq.unit_indices = bucket
		sq.order = BattleOrderTypesLib.SquadOrder.ADVANCE_CONTACT
		squads.append(sq)
	return squads


static func _place_commanders(
	store: UnitSimulationStoreLib,
	battle_data,
	friendly_units: Array[int],
	hostile_units: Array[int],
	rng: RandomNumberGenerator,
) -> Array:
	var commanders: Array = []
	if not friendly_units.is_empty():
		var pick: int = friendly_units[rng.randi() % friendly_units.size()]
		var def = BattleUnitCatalogLib.get_by_archetype(BattleUnitCatalogLib.ARCH_COMMANDER)
		store.apply_definition_stats(pick, def)
		store.set_tier(pick, UnitSimulationStoreLib.Tier.FULL)
		var cmd := BattleCommanderLib.new(0, UnitSimulationStoreLib.Side.FRIENDLY, pick)
		cmd.order_queue = _default_commander_queue()
		cmd.gems_remaining = 12
		commanders.append(cmd)
	var enemy_cmd_count: int = clampi(1 + hostile_units.size() / 800, 1, 3)
	for i in range(enemy_cmd_count):
		if hostile_units.is_empty():
			break
		var pick_e: int = hostile_units[rng.randi() % hostile_units.size()]
		var def_e = BattleUnitCatalogLib.get_by_archetype(BattleUnitCatalogLib.ARCH_COMMANDER)
		store.apply_definition_stats(pick_e, def_e)
		store.set_tier(pick_e, UnitSimulationStoreLib.Tier.FULL)
		var ecmd := BattleCommanderLib.new(i + 1, UnitSimulationStoreLib.Side.HOSTILE, pick_e)
		ecmd.order_queue = _default_commander_queue()
		ecmd.gems_remaining = 8
		commanders.append(ecmd)
	return commanders


static func _default_commander_queue() -> Array:
	return [
		BattleOrderTypesLib.CommanderStep.ATTACK_CLOSEST,
		BattleOrderTypesLib.CommanderStep.CAST_SPELL,
		BattleOrderTypesLib.CommanderStep.WAIT,
		BattleOrderTypesLib.CommanderStep.BLESS_SQUAD,
		BattleOrderTypesLib.CommanderStep.WAIT,
	]
