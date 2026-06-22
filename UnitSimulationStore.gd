class_name UnitSimulationStore
extends RefCounted
## Packed unit data for 500–10k scale. No Node references in hot arrays.

enum Side { FRIENDLY = 0, HOSTILE = 1 }
enum Tier { DORMANT = 0, SIM_ONLY = 1, LITE = 2, FULL = 3 }

const FLAG_ALIVE := 1
const FLAG_EXTRACTED := 2
const FLAG_MOVING := 4
const FLAG_SIM_DRIVEN := 8

const MAX_UNITS := 12000
const SIM_BUCKETS := 8

var count: int = 0
var ids: PackedInt32Array = PackedInt32Array()
var positions: PackedVector2Array = PackedVector2Array()
var health: PackedFloat32Array = PackedFloat32Array()
var max_health: PackedFloat32Array = PackedFloat32Array()
var room_index: PackedInt32Array = PackedInt32Array()
var squad_id: PackedInt32Array = PackedInt32Array()
var side: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()
var tier: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var sim_bucket: PackedInt32Array = PackedInt32Array()
var archetype: PackedInt32Array = PackedInt32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var node_handle: PackedInt32Array = PackedInt32Array()
var target_room_index: PackedInt32Array = PackedInt32Array()
var grid_x: PackedInt32Array = PackedInt32Array()
var grid_y: PackedInt32Array = PackedInt32Array()
var morale: PackedInt32Array = PackedInt32Array()
var fatigue: PackedFloat32Array = PackedFloat32Array()
var protection: PackedInt32Array = PackedInt32Array()
var size: PackedInt32Array = PackedInt32Array()
var commander_index: PackedInt32Array = PackedInt32Array()
var squad_index: PackedInt32Array = PackedInt32Array()
var script_state: PackedInt32Array = PackedInt32Array()
var routed: PackedInt32Array = PackedInt32Array()
var unit_attack: PackedInt32Array = PackedInt32Array()
var unit_defense: PackedInt32Array = PackedInt32Array()
var unit_strength: PackedInt32Array = PackedInt32Array()
var precision: PackedInt32Array = PackedInt32Array()
var combat_speed: PackedInt32Array = PackedInt32Array()
var encumbrance: PackedInt32Array = PackedInt32Array()
var mr: PackedInt32Array = PackedInt32Array()
var ranged: PackedInt32Array = PackedInt32Array()
var range_cells: PackedInt32Array = PackedInt32Array()
var target_grid_x: PackedInt32Array = PackedInt32Array()
var target_grid_y: PackedInt32Array = PackedInt32Array()
var is_commander_unit: PackedInt32Array = PackedInt32Array()
var kills: PackedInt32Array = PackedInt32Array()
var death_round: PackedInt32Array = PackedInt32Array()

var room_ids: Array[String] = []
var room_positions: PackedVector2Array = PackedVector2Array()
var friendly_count_by_room: PackedInt32Array = PackedInt32Array()
var hostile_count_by_room: PackedInt32Array = PackedInt32Array()
var pending_damage_by_room: PackedFloat32Array = PackedFloat32Array()

var _next_id: int = 1
var _living_friendly: int = 0
var _living_hostile: int = 0
var on_unit_killed: Callable = Callable()
var _dirty_transform: PackedByteArray = PackedByteArray()


func reset() -> void:
	count = 0
	ids = PackedInt32Array()
	positions = PackedVector2Array()
	health = PackedFloat32Array()
	max_health = PackedFloat32Array()
	room_index = PackedInt32Array()
	squad_id = PackedInt32Array()
	side = PackedInt32Array()
	order = PackedInt32Array()
	tier = PackedInt32Array()
	flags = PackedInt32Array()
	sim_bucket = PackedInt32Array()
	archetype = PackedInt32Array()
	speed = PackedFloat32Array()
	node_handle = PackedInt32Array()
	target_room_index = PackedInt32Array()
	grid_x = PackedInt32Array()
	grid_y = PackedInt32Array()
	morale = PackedInt32Array()
	fatigue = PackedFloat32Array()
	protection = PackedInt32Array()
	size = PackedInt32Array()
	commander_index = PackedInt32Array()
	squad_index = PackedInt32Array()
	script_state = PackedInt32Array()
	routed = PackedInt32Array()
	unit_attack = PackedInt32Array()
	unit_defense = PackedInt32Array()
	unit_strength = PackedInt32Array()
	precision = PackedInt32Array()
	combat_speed = PackedInt32Array()
	encumbrance = PackedInt32Array()
	mr = PackedInt32Array()
	ranged = PackedInt32Array()
	range_cells = PackedInt32Array()
	target_grid_x = PackedInt32Array()
	target_grid_y = PackedInt32Array()
	is_commander_unit = PackedInt32Array()
	kills = PackedInt32Array()
	death_round = PackedInt32Array()
	room_ids.clear()
	room_positions = PackedVector2Array()
	friendly_count_by_room = PackedInt32Array()
	hostile_count_by_room = PackedInt32Array()
	pending_damage_by_room = PackedFloat32Array()
	_next_id = 1
	_living_friendly = 0
	_living_hostile = 0


func bind_rooms(rooms: Array) -> void:
	room_ids.clear()
	room_positions = PackedVector2Array()
	for room in rooms:
		if room == null:
			continue
		var map_id: String = ""
		var pos: Vector2 = Vector2.ZERO
		if room is Dictionary:
			map_id = str(room.get("map_room_id", ""))
			pos = room.get("position", Vector2.ZERO)
		elif room is Object:
			if "map_room_id" in room:
				map_id = str(room.map_room_id)
			if "position" in room:
				pos = room.position
		if map_id.is_empty():
			continue
		room_ids.append(map_id)
		room_positions.append(pos)
	var n := room_ids.size()
	friendly_count_by_room = PackedInt32Array()
	friendly_count_by_room.resize(n)
	hostile_count_by_room = PackedInt32Array()
	hostile_count_by_room.resize(n)
	pending_damage_by_room = PackedFloat32Array()
	pending_damage_by_room.resize(n)
	for i in range(n):
		friendly_count_by_room[i] = 0
		hostile_count_by_room[i] = 0
		pending_damage_by_room[i] = 0.0


func room_index_for_id(map_room_id: String) -> int:
	return room_ids.find(map_room_id)


func spawn_unit(
	unit_side: int,
	pos: Vector2,
	hp: float,
	hp_max: float,
	room_idx: int,
	squad: int = 0,
	unit_tier: int = Tier.LITE,
	unit_speed: float = 120.0,
	unit_archetype: int = 0,
) -> int:
	if count >= MAX_UNITS:
		return -1
	var idx := count
	count += 1
	ids.append(_next_id)
	_next_id += 1
	positions.append(pos)
	health.append(hp)
	max_health.append(hp_max)
	room_index.append(room_idx)
	squad_id.append(squad)
	side.append(unit_side)
	order.append(0)
	tier.append(unit_tier)
	flags.append(FLAG_ALIVE)
	sim_bucket.append(idx % SIM_BUCKETS)
	archetype.append(unit_archetype)
	speed.append(unit_speed)
	node_handle.append(-1)
	target_room_index.append(room_idx)
	grid_x.append(0)
	grid_y.append(0)
	morale.append(15)
	fatigue.append(0.0)
	protection.append(10)
	size.append(1)
	commander_index.append(-1)
	squad_index.append(squad)
	script_state.append(0)
	routed.append(0)
	unit_attack.append(10)
	unit_defense.append(10)
	unit_strength.append(10)
	precision.append(10)
	combat_speed.append(10)
	encumbrance.append(0)
	mr.append(10)
	ranged.append(0)
	range_cells.append(0)
	target_grid_x.append(0)
	target_grid_y.append(0)
	is_commander_unit.append(0)
	kills.append(0)
	death_round.append(-1)
	_adjust_room_count(room_idx, unit_side, 1)
	if unit_side == Side.FRIENDLY:
		_living_friendly += 1
	else:
		_living_hostile += 1
	return idx


func is_alive(idx: int) -> bool:
	if idx < 0 or idx >= count:
		return false
	return (flags[idx] & FLAG_ALIVE) != 0 and (flags[idx] & FLAG_EXTRACTED) == 0


func is_routed(idx: int) -> bool:
	if idx < 0 or idx >= count:
		return false
	return routed[idx] != 0


func set_routed(idx: int, on: bool = true) -> void:
	if idx >= 0 and idx < count:
		routed[idx] = 1 if on else 0


func spawn_from_definition(
	unit_side: int,
	gx: int,
	gy: int,
	battle_data,
	def,
	squad: int = 0,
	unit_tier: int = Tier.LITE,
) -> int:
	if def == null:
		return -1
	var idx := spawn_unit_on_grid(
		unit_side,
		gx,
		gy,
		battle_data,
		def.hp,
		def.hp,
		squad,
		unit_tier,
		float(def.combat_speed) * 12.0,
		def.archetype_index,
	)
	if idx >= 0:
		apply_definition_stats(idx, def)
	return idx


func apply_definition_stats(idx: int, def) -> void:
	if idx < 0 or idx >= count or def == null:
		return
	max_health[idx] = def.hp
	health[idx] = def.hp
	unit_attack[idx] = int(def.attack)
	unit_defense[idx] = int(def.defense)
	unit_strength[idx] = def.strength
	protection[idx] = def.protection
	precision[idx] = def.precision
	morale[idx] = def.morale
	combat_speed[idx] = def.combat_speed
	encumbrance[idx] = def.encumbrance
	mr[idx] = def.mr
	size[idx] = clampi(def.size, 1, 10)
	ranged[idx] = 1 if def.ranged else 0
	range_cells[idx] = def.range_cells if def.ranged else 0
	is_commander_unit[idx] = 1 if def.is_commander else 0
	speed[idx] = float(def.combat_speed) * 12.0
	archetype[idx] = def.archetype_index


func set_tier(idx: int, new_tier: int) -> void:
	if idx >= 0 and idx < count:
		tier[idx] = new_tier


func set_position(idx: int, pos: Vector2) -> void:
	if idx >= 0 and idx < count:
		positions[idx] = pos


func sync_grid_from_position(idx: int, battle_data) -> void:
	if idx < 0 or idx >= count or battle_data == null:
		return
	var g: Vector2i = battle_data.world_to_grid(positions[idx])
	g.x = clampi(g.x, 0, battle_data.grid_width - 1)
	g.y = clampi(g.y, 0, battle_data.grid_height - 1)
	grid_x[idx] = g.x
	grid_y[idx] = g.y


func set_grid_cell(idx: int, gx: int, gy: int, battle_data, cell_grid = null) -> void:
	if idx < 0 or idx >= count or battle_data == null:
		return
	gx = clampi(gx, 0, battle_data.grid_width - 1)
	gy = clampi(gy, 0, battle_data.grid_height - 1)
	if not battle_data.is_land_cell(gx, gy):
		return
	if cell_grid != null and not cell_grid.can_enter(gx, gy, size[idx], side[idx]):
		return
	var old_gx: int = grid_x[idx]
	var old_gy: int = grid_y[idx]
	if cell_grid != null and (old_gx != gx or old_gy != gy):
		cell_grid.move_unit(idx, old_gx, old_gy, gx, gy, size[idx], side[idx])
		mark_dirty_transform(idx)
	grid_x[idx] = gx
	grid_y[idx] = gy
	positions[idx] = battle_data.cell_center(gx, gy)
	var room_idx: int = battle_data.region_index_for_grid(gx, gy)
	if room_idx != room_index[idx]:
		set_room(idx, room_idx)


func spawn_unit_on_grid(
	unit_side: int,
	gx: int,
	gy: int,
	battle_data,
	hp: float,
	hp_max: float,
	squad: int = 0,
	unit_tier: int = Tier.LITE,
	unit_speed: float = 120.0,
	unit_archetype: int = 0,
) -> int:
	if battle_data == null:
		return -1
	if not battle_data.is_passable(gx, gy):
		var snapped: Vector2 = battle_data.snap_world_to_cell_center(battle_data.cell_center(gx, gy))
		var g: Vector2i = battle_data.world_to_grid(snapped)
		gx = g.x
		gy = g.y
	var room_idx: int = battle_data.region_index_for_grid(gx, gy)
	var idx := spawn_unit(
		unit_side,
		battle_data.cell_center(gx, gy),
		hp,
		hp_max,
		room_idx,
		squad,
		unit_tier,
		unit_speed,
		unit_archetype,
	)
	if idx >= 0:
		grid_x[idx] = gx
		grid_y[idx] = gy
	return idx


func try_step_toward(idx: int, target_gx: int, target_gy: int, battle_data, cell_grid = null) -> bool:
	if idx < 0 or idx >= count or battle_data == null:
		return false
	if not is_alive(idx):
		return false
	var cx: int = grid_x[idx]
	var cy: int = grid_y[idx]
	var contact_col: int = battle_data.contact_column
	var dist_contact: int = absi(cx - contact_col)
	# On the rally tile — keep pushing into the enemy side instead of idling.
	if cx == target_gx and cy == target_gy:
		if side[idx] == Side.FRIENDLY:
			target_gx = mini(battle_data.grid_width - 1, cx + 1)
		else:
			target_gx = maxi(0, cx - 1)
	var candidates: Array = []
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var nx: int = cx + dx
				var ny: int = cy + dy
				if not battle_data.is_land_cell(nx, ny):
					continue
				if cell_grid != null and not cell_grid.can_enter(nx, ny, size[idx], side[idx]):
					continue
				var dist: int = absi(nx - target_gx) + absi(ny - target_gy)
				var lane_bias: int = absi(ny - target_gy) if dist_contact <= 10 else 0
				var advance_bias: int = 0
				if dist_contact > 8:
					if side[idx] == Side.FRIENDLY and nx <= cx:
						advance_bias += 12
					elif side[idx] == Side.HOSTILE and nx >= cx:
						advance_bias += 12
				var enemy_bias: int = 0
				if cell_grid != null:
					var enemy_side: int = (
						Side.HOSTILE if side[idx] == Side.FRIENDLY else Side.FRIENDLY
					)
					if enemy_side == Side.FRIENDLY:
						enemy_bias = -mini(4, cell_grid.friendly_count_at_cell(nx, ny))
					else:
						enemy_bias = -mini(4, cell_grid.hostile_count_at_cell(nx, ny))
				candidates.append({
					"g": Vector2i(nx, ny),
					"score": dist * 4 + lane_bias + advance_bias + enemy_bias,
				})
		if not candidates.is_empty():
			break
	if candidates.is_empty():
		# Fallback: inch toward contact / enemy when local ring is blocked (e.g. lakes).
		for attempt in range(6):
			var toward_contact: int = 1 if side[idx] == Side.FRIENDLY else -1
			var fx: int = cx + toward_contact * (attempt + 1)
			if battle_data.is_land_cell(fx, cy) and (
				cell_grid == null or cell_grid.can_enter(fx, cy, size[idx], side[idx])
			):
				set_grid_cell(idx, fx, cy, battle_data, cell_grid)
				return true
			for lateral in [-1, 1]:
				var fy: int = cy + lateral * (attempt + 1)
				if battle_data.is_land_cell(cx, fy) and (
					cell_grid == null or cell_grid.can_enter(cx, fy, size[idx], side[idx])
				):
					set_grid_cell(idx, cx, fy, battle_data, cell_grid)
					return true
		return false
	candidates.sort_custom(func(a, b): return int(a["score"]) < int(b["score"]))
	var pick: Vector2i = candidates[0]["g"]
	set_grid_cell(idx, pick.x, pick.y, battle_data, cell_grid)
	return true


func set_room(idx: int, room_idx: int) -> void:
	if idx < 0 or idx >= count:
		return
	var old := room_index[idx]
	if old == room_idx:
		return
	_adjust_room_count(old, side[idx], -1)
	room_index[idx] = room_idx
	_adjust_room_count(room_idx, side[idx], 1)


func apply_damage(idx: int, amount: float, killer_idx: int = -1) -> void:
	if not is_alive(idx):
		return
	health[idx] = maxf(0.0, health[idx] - amount)
	if health[idx] <= 0.0:
		kill_unit(idx, killer_idx)


func add_fatigue(idx: int, amount: float) -> void:
	if idx < 0 or idx >= count:
		return
	fatigue[idx] += amount
	if fatigue[idx] >= 200.0:
		apply_damage(idx, 50.0)
	elif fatigue[idx] >= 100.0 and combat_speed[idx] > 2:
		combat_speed[idx] = maxi(2, combat_speed[idx] / 2)


func kill_unit(idx: int, killer_idx: int = -1) -> void:
	if idx < 0 or idx >= count:
		return
	if not is_alive(idx):
		return
	if killer_idx >= 0 and killer_idx < count and killer_idx != idx:
		kills[killer_idx] = kills[killer_idx] + 1
	flags[idx] &= ~FLAG_ALIVE
	_adjust_room_count(room_index[idx], side[idx], -1)
	if side[idx] == Side.FRIENDLY:
		_living_friendly = maxi(0, _living_friendly - 1)
	else:
		_living_hostile = maxi(0, _living_hostile - 1)
	if on_unit_killed.is_valid():
		on_unit_killed.call(idx)


func mark_dirty_transform(idx: int) -> void:
	if idx < 0 or idx >= count:
		return
	if _dirty_transform.size() != count:
		_dirty_transform.resize(count)
		_dirty_transform.fill(0)
	if idx < _dirty_transform.size():
		_dirty_transform[idx] = 1


func clear_dirty_transforms() -> void:
	if _dirty_transform.size() == count:
		_dirty_transform.fill(0)


func collect_dirty_transform_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _dirty_transform.size() != count:
		return out
	for i in range(count):
		if _dirty_transform[i] != 0 and is_alive(i):
			out.append(i)
	return out


func living_friendly_count() -> int:
	var n: int = 0
	for i in range(count):
		if side[i] == Side.FRIENDLY and is_alive(i):
			n += 1
	return n


func living_hostile_count() -> int:
	var n: int = 0
	for i in range(count):
		if side[i] == Side.HOSTILE and is_alive(i):
			n += 1
	return n


func sync_living_counts_from_flags() -> void:
	_living_friendly = living_friendly_count()
	_living_hostile = living_hostile_count()


func living_count_for_side(unit_side: int) -> int:
	if unit_side == Side.FRIENDLY:
		return _living_friendly
	return _living_hostile


func indices_in_room(room_idx: int, unit_side: int = -1) -> Array[int]:
	var result: Array[int] = []
	if room_idx < 0:
		return result
	for i in range(count):
		if not is_alive(i):
			continue
		if room_index[i] != room_idx:
			continue
		if unit_side >= 0 and side[i] != unit_side:
			continue
		result.append(i)
	return result


func tick_movement_stub(bucket: int, dt: float, battle_data = null) -> void:
	for i in range(count):
		if sim_bucket[i] != bucket:
			continue
		if not is_alive(i):
			continue
		if tier[i] == Tier.DORMANT:
			continue
		var target_idx := target_room_index[i]
		if target_idx < 0 or target_idx >= room_positions.size():
			continue
		if battle_data != null and grid_x.size() > i:
			var target_pos: Vector2 = room_positions[target_idx]
			var target_g: Vector2i = battle_data.world_to_grid(target_pos)
			var moved := try_step_toward(i, target_g.x, target_g.y, battle_data)
			if not moved and positions[i].distance_squared_to(target_pos) > 64.0:
				sync_grid_from_position(i, battle_data)
			continue
		var target_pos := room_positions[target_idx]
		var to_target := target_pos - positions[i]
		if to_target.length_squared() < 64.0:
			continue
		positions[i] += to_target.normalized() * speed[i] * dt


func _adjust_room_count(room_idx: int, unit_side: int, delta: int) -> void:
	if room_idx < 0 or room_idx >= friendly_count_by_room.size():
		return
	if unit_side == Side.FRIENDLY:
		friendly_count_by_room[room_idx] = maxi(0, friendly_count_by_room[room_idx] + delta)
	else:
		hostile_count_by_room[room_idx] = maxi(0, hostile_count_by_room[room_idx] + delta)
