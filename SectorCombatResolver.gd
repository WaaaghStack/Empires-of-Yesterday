class_name SectorCombatResolver
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")
const CombatFxLib := preload("res://CombatFx.gd")

const TICK_INTERVAL := 0.1
const FRIENDLY_DPS := 7.5
const HOSTILE_DPS := 6.8
const OVERFLOW_FRIENDLY_DPS := 0.9
const OVERFLOW_HOSTILE_DPS := 1.45
const FLIP_THRESHOLD := 0.62
const MIN_DAMAGE_PER_UNIT := 0.12
const CONTACT_STRIP_CELLS := 2.85

var _timer: float = 0.0
var _fx_cooldown: float = 0.0
var last_flip_region_id: String = ""
var fx_world: Node2D = null
var _sector_damage_pending: Dictionary = {}


func reset() -> void:
	_timer = 0.0
	_fx_cooldown = 0.0
	last_flip_region_id = ""
	_sector_damage_pending.clear()


func consume_damage_batches() -> Array:
	var batches: Array = []
	for region_id in _sector_damage_pending.keys():
		var entry: Dictionary = _sector_damage_pending[region_id]
		var total: int = int(roundf(float(entry.get("friendly", 0.0)) + float(entry.get("hostile", 0.0))))
		if total <= 0:
			continue
		batches.append({
			"region_id": region_id,
			"center": entry.get("center", Vector2.ZERO),
			"friendly": int(entry.get("friendly", 0.0)),
			"hostile": int(entry.get("hostile", 0.0)),
			"total": total,
		})
	_sector_damage_pending.clear()
	return batches


func tick_combat(
	store: UnitSimulationStore,
	battle_data,
	delta: float,
	damage_mult: float = 1.0,
	hostile_damage_mult: float = 1.0,
) -> void:
	if store == null or battle_data == null or store.count == 0:
		return
	_timer += delta
	_fx_cooldown = maxf(0.0, _fx_cooldown - delta)
	if _timer < TICK_INTERVAL:
		return
	_timer = 0.0
	_tick_contact_row_combat(store, battle_data, damage_mult, hostile_damage_mult)
	for region in battle_data.regions:
		var col: int = int(region.get("col", -1))
		if col >= 3 and col <= 5:
			continue
		var region_id := str(region.get("id", ""))
		var counts: Dictionary = _count_units_in_region(store, battle_data, region)
		var friendlies: int = int(counts.get("friendly", 0))
		var hostiles: int = int(counts.get("hostile", 0))
		if friendlies <= 0 and hostiles <= 0:
			continue
		var total := friendlies + hostiles
		var pressure: float = float(friendlies) / float(maxi(1, total))
		region["pressure"] = pressure
		var control := str(region.get("control", BattleMapDataLib.CONTROL_NEUTRAL))
		var def_bonus: float = battle_data.defender_bonus
		var dps: Vector2 = _row_exchange_dps(friendlies, hostiles, control, def_bonus, damage_mult, hostile_damage_mult)
		var friendly_dps: float = dps.x
		var hostile_dps: float = dps.y
		if friendlies > 0 and hostiles > 0:
			_apply_casualties_to_indices(
				store, counts.get("hostile_indices", []), friendly_dps, region_id, region, UnitSimulationStore.Side.HOSTILE
			)
			_apply_casualties_to_indices(
				store, counts.get("friendly_indices", []), hostile_dps, region_id, region, UnitSimulationStore.Side.FRIENDLY
			)
			_try_flip_region(battle_data, region, pressure)
		elif friendlies > 0 and pressure >= FLIP_THRESHOLD:
			_set_region_control(battle_data, region_id, BattleMapDataLib.CONTROL_PLAYER, region)
		elif hostiles > 0 and pressure <= 1.0 - FLIP_THRESHOLD:
			_set_region_control(battle_data, region_id, BattleMapDataLib.CONTROL_ENEMY, region)


func _contact_x(battle_data) -> float:
	var half: Vector2 = battle_data.map_size * 0.5
	return (float(battle_data.contact_column) + 0.5) * battle_data.cell_size - half.x


func _row_exchange_dps(
	friendlies: int,
	hostiles: int,
	control: String,
	def_bonus: float,
	damage_mult: float,
	hostile_damage_mult: float,
) -> Vector2:
	if friendlies <= 0 or hostiles <= 0:
		return Vector2.ZERO
	var exchange: int = mini(friendlies, hostiles)
	var friendly_dps := float(exchange) * FRIENDLY_DPS * TICK_INTERVAL * damage_mult
	var hostile_dps := float(exchange) * HOSTILE_DPS * TICK_INTERVAL * hostile_damage_mult
	var overflow_h: int = maxi(0, hostiles - friendlies)
	var overflow_f: int = maxi(0, friendlies - hostiles)
	hostile_dps += float(overflow_h) * OVERFLOW_HOSTILE_DPS * TICK_INTERVAL * hostile_damage_mult
	friendly_dps += float(overflow_f) * OVERFLOW_FRIENDLY_DPS * TICK_INTERVAL * damage_mult
	if control == BattleMapDataLib.CONTROL_PLAYER:
		hostile_dps *= def_bonus
	elif control == BattleMapDataLib.CONTROL_ENEMY:
		friendly_dps /= def_bonus
	return Vector2(friendly_dps, hostile_dps)


func _tick_contact_row_combat(
	store: UnitSimulationStore,
	battle_data,
	damage_mult: float,
	hostile_damage_mult: float,
) -> void:
	var contact_x: float = _contact_x(battle_data)
	var strip_half: float = battle_data.cell_size * CONTACT_STRIP_CELLS
	var sector_rows: int = 6
	var sh: float = battle_data.map_size.y / float(sector_rows)
	var half_y: float = battle_data.map_size.y * 0.5
	for row in range(sector_rows):
		var y0: float = float(row) * sh - half_y
		var y1: float = y0 + sh
		var friendly_indices: Array[int] = []
		var hostile_indices: Array[int] = []
		for i in range(store.count):
			if not store.is_alive(i):
				continue
			var pos: Vector2 = store.positions[i]
			if pos.y < y0 or pos.y >= y1:
				continue
			if absf(pos.x - contact_x) > strip_half:
				continue
			if store.side[i] == UnitSimulationStore.Side.FRIENDLY:
				friendly_indices.append(i)
			else:
				hostile_indices.append(i)
		if friendly_indices.is_empty() or hostile_indices.is_empty():
			continue
		var region_id := "sec_%d_4" % row
		var region: Dictionary = battle_data.get_region(region_id)
		if region.is_empty():
			continue
		var friendlies: int = friendly_indices.size()
		var hostiles: int = hostile_indices.size()
		var total: int = friendlies + hostiles
		var pressure: float = float(friendlies) / float(maxi(1, total))
		region["pressure"] = pressure
		var control := str(region.get("control", BattleMapDataLib.CONTROL_NEUTRAL))
		var def_bonus: float = battle_data.defender_bonus
		var dps: Vector2 = _row_exchange_dps(
			friendlies, hostiles, control, def_bonus, damage_mult, hostile_damage_mult
		)
		_apply_casualties_to_indices(
			store, hostile_indices, dps.x, region_id, region, UnitSimulationStore.Side.HOSTILE
		)
		_apply_casualties_to_indices(
			store, friendly_indices, dps.y, region_id, region, UnitSimulationStore.Side.FRIENDLY
		)
		_try_flip_region(battle_data, region, pressure)


func _count_units_in_region(store: UnitSimulationStore, battle_data, region: Dictionary) -> Dictionary:
	var rect: Rect2 = battle_data.region_world_rect(region)
	var friendly_indices: Array[int] = []
	var hostile_indices: Array[int] = []
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if not rect.has_point(store.positions[i]):
			continue
		if store.side[i] == UnitSimulationStore.Side.FRIENDLY:
			friendly_indices.append(i)
		else:
			hostile_indices.append(i)
	return {
		"friendly": friendly_indices.size(),
		"hostile": hostile_indices.size(),
		"friendly_indices": friendly_indices,
		"hostile_indices": hostile_indices,
	}


func get_hottest_sector_id(battle_data) -> String:
	if battle_data == null:
		return ""
	var best_id := ""
	var best_score := -1.0
	for region in battle_data.regions:
		var p: float = float(region.get("pressure", 0.0))
		var region_id := str(region.get("id", ""))
		if p <= 0.01 and p >= 0.99:
			continue
		var score: float = absf(p - 0.5)
		if bool(region.get("is_objective", false)):
			score += 0.15
		if score > best_score:
			best_score = score
			best_id = region_id
	return best_id


func _try_flip_region(battle_data, region: Dictionary, pressure: float) -> void:
	var region_id := str(region.get("id", ""))
	var control := str(region.get("control", BattleMapDataLib.CONTROL_NEUTRAL))
	if pressure >= FLIP_THRESHOLD and control != BattleMapDataLib.CONTROL_PLAYER:
		_set_region_control(battle_data, region_id, BattleMapDataLib.CONTROL_PLAYER, region)
	elif pressure <= 1.0 - FLIP_THRESHOLD and control != BattleMapDataLib.CONTROL_ENEMY:
		_set_region_control(battle_data, region_id, BattleMapDataLib.CONTROL_ENEMY, region)


func _set_region_control(battle_data, region_id: String, new_control: String, region: Dictionary) -> void:
	var old := str(region.get("control", ""))
	if old == new_control:
		return
	battle_data.set_region_control(region_id, new_control)
	region["control"] = new_control
	last_flip_region_id = region_id
	_spawn_flip_fx(region.get("center", Vector2.ZERO), new_control)


func _spawn_flip_fx(center: Vector2, control: String) -> void:
	if fx_world == null or not is_instance_valid(fx_world) or _fx_cooldown > 0.0:
		return
	_fx_cooldown = 0.35
	var marker := Node2D.new()
	marker.position = center
	fx_world.add_child(marker)
	var color := Color(0.35, 0.75, 1.0, 0.9) if control == BattleMapDataLib.CONTROL_PLAYER else Color(0.95, 0.35, 0.3, 0.9)
	CombatFxLib.spawn_impact(marker, color)
	marker.queue_free()


func _apply_casualties_to_indices(
	store: UnitSimulationStore,
	victims: Array,
	damage: float,
	region_id: String,
	region: Dictionary,
	victim_side: int,
) -> void:
	if damage <= 0.0 or victims.is_empty():
		return
	var per_unit: float = damage / float(victims.size())
	if per_unit > 0.0 and per_unit < MIN_DAMAGE_PER_UNIT:
		per_unit = MIN_DAMAGE_PER_UNIT
	for idx in victims:
		if store.tier[idx] == UnitSimulationStore.Tier.FULL:
			continue
		store.apply_damage(idx, per_unit)
	if region_id.is_empty():
		return
	if not _sector_damage_pending.has(region_id):
		_sector_damage_pending[region_id] = {
			"friendly": 0.0,
			"hostile": 0.0,
			"center": region.get("center", Vector2.ZERO),
		}
	var entry: Dictionary = _sector_damage_pending[region_id]
	if victim_side == UnitSimulationStore.Side.FRIENDLY:
		entry["friendly"] = float(entry.get("friendly", 0.0)) + damage
	else:
		entry["hostile"] = float(entry.get("hostile", 0.0)) + damage
