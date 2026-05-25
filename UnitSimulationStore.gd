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

var room_ids: Array[String] = []
var room_positions: PackedVector2Array = PackedVector2Array()
var friendly_count_by_room: PackedInt32Array = PackedInt32Array()
var hostile_count_by_room: PackedInt32Array = PackedInt32Array()
var pending_damage_by_room: PackedFloat32Array = PackedFloat32Array()

var _next_id: int = 1
var _living_friendly: int = 0
var _living_hostile: int = 0


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
		if room is Room:
			room_ids.append(room.map_room_id)
			room_positions.append(room.position)
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


func set_tier(idx: int, new_tier: int) -> void:
	if idx >= 0 and idx < count:
		tier[idx] = new_tier


func set_position(idx: int, pos: Vector2) -> void:
	if idx >= 0 and idx < count:
		positions[idx] = pos


func set_room(idx: int, room_idx: int) -> void:
	if idx < 0 or idx >= count:
		return
	var old := room_index[idx]
	if old == room_idx:
		return
	_adjust_room_count(old, side[idx], -1)
	room_index[idx] = room_idx
	_adjust_room_count(room_idx, side[idx], 1)


func apply_damage(idx: int, amount: float) -> void:
	if not is_alive(idx):
		return
	health[idx] = maxf(0.0, health[idx] - amount)
	if health[idx] <= 0.0:
		kill_unit(idx)


func kill_unit(idx: int) -> void:
	if idx < 0 or idx >= count:
		return
	if not is_alive(idx):
		return
	flags[idx] &= ~FLAG_ALIVE
	_adjust_room_count(room_index[idx], side[idx], -1)
	if side[idx] == Side.FRIENDLY:
		_living_friendly = maxi(0, _living_friendly - 1)
	else:
		_living_hostile = maxi(0, _living_hostile - 1)


func living_friendly_count() -> int:
	return _living_friendly


func living_hostile_count() -> int:
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


func tick_movement_stub(bucket: int, dt: float) -> void:
	## Phase A benchmark / lite movement toward target room center.
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
