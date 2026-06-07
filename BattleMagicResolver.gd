class_name BattleMagicResolver
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")
const BattleSpellCatalogLib := preload("res://BattleSpellCatalog.gd")
const BattleCellGridLib := preload("res://BattleCellGrid.gd")

var _rng := RandomNumberGenerator.new()


func setup(seed_value: int = 1) -> void:
	_rng.seed = seed_value


func resolve_commander_round(
	store,
	cell_grid: BattleCellGridLib,
	commanders: Array,
	squads: Array,
) -> void:
	for cmd in commanders:
		if not cmd.alive or cmd.unit_index < 0 or not store.is_alive(cmd.unit_index):
			continue
		var step: int = cmd.current_step()
		if step == BattleOrderTypesLib.CommanderStep.WAIT:
			cmd.advance_queue()
			continue
		if step == BattleOrderTypesLib.CommanderStep.CAST_SPELL:
			_cast_default_spell(store, cell_grid, cmd, squads)
		elif step == BattleOrderTypesLib.CommanderStep.BLESS_SQUAD:
			_cast_spell(store, cmd, BattleSpellCatalogLib.SPELL_BLESS, squads)
		cmd.advance_queue()


func _cast_default_spell(store, cell_grid: BattleCellGridLib, cmd, squads: Array) -> void:
	var spell_id: String = BattleSpellCatalogLib.default_spell_for_step(cmd.queue_step)
	_cast_spell(store, cmd, spell_id, squads, cell_grid)


func _cast_spell(store, cmd, spell_id: String, squads: Array, cell_grid = null) -> void:
	var spec: Dictionary = BattleSpellCatalogLib.get_spell(spell_id)
	if spec.is_empty():
		return
	var cost: int = int(spec.get("gems", 1))
	if cmd.gems_remaining < cost:
		return
	cmd.gems_remaining -= cost
	match spell_id:
		BattleSpellCatalogLib.SPELL_FIREBALL:
			_fireball(store, cmd, cell_grid, spec)
		BattleSpellCatalogLib.SPELL_BLESS:
			_bless_squad(store, cmd, squads, spec)
		BattleSpellCatalogLib.SPELL_FEAR:
			_fear_near(store, cmd, spec)
		BattleSpellCatalogLib.SPELL_SLEEP:
			_sleep_near(store, cmd, spec)


func _fireball(store, cmd, cell_grid, spec: Dictionary) -> void:
	if cell_grid == null or cmd.unit_index < 0:
		return
	var gx: int = store.grid_x[cmd.unit_index]
	var gy: int = store.grid_y[cmd.unit_index]
	var dmg: float = float(spec.get("damage", 12))
	for idx in cell_grid.units_at(gx, gy):
		if store.side[int(idx)] == cmd.side:
			continue
		if store.is_alive(int(idx)):
			store.apply_damage(int(idx), dmg, cmd.unit_index)


func _bless_squad(store, cmd, squads: Array, spec: Dictionary) -> void:
	for squad in squads:
		if squad.side != cmd.side:
			continue
		for u in squad.unit_indices:
			if store.is_alive(u):
				store.morale[u] = mini(30, store.morale[u] + int(spec.get("morale_bonus", 2)))
				store.unit_strength[u] += int(spec.get("damage_bonus", 1))
		return


func _fear_near(store, cmd, spec: Dictionary) -> void:
	var pen: int = int(spec.get("morale_penalty", 3))
	for i in range(store.count):
		if not store.is_alive(i) or store.side[i] == cmd.side:
			continue
		var dist: int = absi(store.grid_x[i] - store.grid_x[cmd.unit_index]) + absi(
			store.grid_y[i] - store.grid_y[cmd.unit_index]
		)
		if dist <= 6:
			store.morale[i] = maxi(0, store.morale[i] - pen)


func _sleep_near(store, cmd, spec: Dictionary) -> void:
	var add: float = float(spec.get("fatigue_add", 30.0))
	for i in range(store.count):
		if not store.is_alive(i) or store.side[i] == cmd.side:
			continue
		var dist: int = absi(store.grid_x[i] - store.grid_x[cmd.unit_index]) + absi(
			store.grid_y[i] - store.grid_y[cmd.unit_index]
		)
		if dist <= 4:
			store.fatigue[i] = minf(180.0, store.fatigue[i] + add)
