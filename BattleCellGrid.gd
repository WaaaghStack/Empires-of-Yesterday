class_name BattleCellGrid
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

## Dominions-style stacking: many units per tile; only enemy presence blocks entry.
const MAX_SIZE_PER_CELL := 64
const MASK_FRIENDLY := 1
const MASK_HOSTILE := 2
const MASK_BOTH := 3

var battle_data = null
var width: int = 0
var height: int = 0
var _cell_units: Array = []
var _cell_size_used: PackedInt32Array = PackedInt32Array()
var _cell_side_mask: PackedInt32Array = PackedInt32Array()
var _contested_cells: Array = []
var _contested_lookup: Dictionary = {}
var _friendly_count_by_cell: PackedInt32Array = PackedInt32Array()
var _hostile_count_by_cell: PackedInt32Array = PackedInt32Array()


func setup(map_data) -> void:
	battle_data = map_data
	width = map_data.grid_width if map_data else 0
	height = map_data.grid_height if map_data else 0
	var n: int = width * height
	_cell_units.clear()
	_cell_units.resize(n)
	for i in range(n):
		_cell_units[i] = PackedInt32Array()
	_cell_size_used = PackedInt32Array()
	_cell_size_used.resize(n)
	_cell_side_mask = PackedInt32Array()
	_cell_side_mask.resize(n)
	_friendly_count_by_cell = PackedInt32Array()
	_friendly_count_by_cell.resize(n)
	_hostile_count_by_cell = PackedInt32Array()
	_hostile_count_by_cell.resize(n)
	for i in range(n):
		_cell_size_used[i] = 0
		_cell_side_mask[i] = 0
		_friendly_count_by_cell[i] = 0
		_hostile_count_by_cell[i] = 0
	_contested_cells.clear()
	_contested_lookup.clear()


func cell_index(gx: int, gy: int) -> int:
	return gy * width + gx


func can_enter(gx: int, gy: int, unit_size: int, unit_side: int = -1) -> bool:
	if battle_data == null or gx < 0 or gy < 0 or gx >= width or gy >= height:
		return false
	if not battle_data.is_land_cell(gx, gy):
		return false
	var idx: int = cell_index(gx, gy)
	if unit_side >= 0:
		var enemy_used: int = (
			_hostile_count_by_cell[idx]
			if unit_side == UnitSimulationStoreLib.Side.FRIENDLY
			else _friendly_count_by_cell[idx]
		)
		return enemy_used + unit_size <= MAX_SIZE_PER_CELL
	return _cell_size_used[idx] + unit_size <= MAX_SIZE_PER_CELL


func size_used(gx: int, gy: int) -> int:
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _cell_size_used.size():
		return 0
	return _cell_size_used[idx]


func units_at(gx: int, gy: int) -> PackedInt32Array:
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _cell_units.size():
		return PackedInt32Array()
	return _cell_units[idx]


func units_at_array(gx: int, gy: int) -> Array:
	var packed: PackedInt32Array = units_at(gx, gy)
	var out: Array = []
	for u in packed:
		out.append(u)
	return out


func get_contested_cells() -> Array:
	return _contested_cells


func friendly_count_at_cell(gx: int, gy: int) -> int:
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _friendly_count_by_cell.size():
		return 0
	return _friendly_count_by_cell[idx]


func hostile_count_at_cell(gx: int, gy: int) -> int:
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _hostile_count_by_cell.size():
		return 0
	return _hostile_count_by_cell[idx]


func rebuild_from_store(store) -> void:
	if store == null:
		return
	setup(battle_data)
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		add_unit(i, store.grid_x[i], store.grid_y[i], store.size[i], store.side[i])


func can_enter_unit(store, unit_idx: int, gx: int, gy: int) -> bool:
	if unit_idx < 0 or unit_idx >= store.count:
		return false
	return can_enter(gx, gy, store.size[unit_idx])


func move_unit_from_store(store, unit_idx: int, to_gx: int, to_gy: int) -> bool:
	if unit_idx < 0 or unit_idx >= store.count:
		return false
	return move_unit(
		unit_idx,
		store.grid_x[unit_idx],
		store.grid_y[unit_idx],
		to_gx,
		to_gy,
		store.size[unit_idx],
		store.side[unit_idx],
	)


func add_unit(unit_idx: int, gx: int, gy: int, unit_size: int, unit_side: int) -> void:
	if gx < 0 or gy < 0 or gx >= width or gy >= height:
		return
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _cell_units.size():
		return
	var list: PackedInt32Array = _cell_units[idx]
	for j in range(list.size()):
		if list[j] == unit_idx:
			return
	list.append(unit_idx)
	_cell_units[idx] = list
	_cell_size_used[idx] += unit_size
	_apply_side_count(idx, unit_side, 1)
	_refresh_contested(idx)


func remove_unit(unit_idx: int, gx: int, gy: int, unit_size: int, unit_side: int) -> void:
	if gx < 0 or gy < 0 or gx >= width or gy >= height:
		return
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _cell_units.size():
		return
	var list: PackedInt32Array = _cell_units[idx]
	var new_list := PackedInt32Array()
	for j in range(list.size()):
		if list[j] != unit_idx:
			new_list.append(list[j])
	_cell_units[idx] = new_list
	_cell_size_used[idx] = maxi(0, _cell_size_used[idx] - unit_size)
	_apply_side_count(idx, unit_side, -1)
	_refresh_contested(idx)


func move_unit(unit_idx: int, from_gx: int, from_gy: int, to_gx: int, to_gy: int, unit_size: int, unit_side: int) -> bool:
	if not can_enter(to_gx, to_gy, unit_size, unit_side):
		return false
	remove_unit(unit_idx, from_gx, from_gy, unit_size, unit_side)
	add_unit(unit_idx, to_gx, to_gy, unit_size, unit_side)
	return true


func has_both_sides_at(gx: int, gy: int, _store = null) -> bool:
	var idx: int = cell_index(gx, gy)
	if idx < 0 or idx >= _cell_side_mask.size():
		return false
	return (_cell_side_mask[idx] & MASK_BOTH) == MASK_BOTH


func get_contact_focus_cell() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := 0
	for cell in _contested_cells:
		var n: int = units_at(cell.x, cell.y).size()
		if n > best_n:
			best_n = n
			best = cell
	return best


func build_melee_adjacency_pairs() -> Array:
	var pairs: Array = []
	var seen: Dictionary = {}
	for cell in _contested_cells:
		var gx: int = cell.x
		var gy: int = cell.y
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx: int = gx + dx
				var ny: int = gy + dy
				if battle_data != null and not battle_data.is_land_cell(nx, ny):
					continue
				if not has_both_sides_at(nx, ny):
					var key: String = "%d,%d|%d,%d" % [mini(gx, nx), mini(gy, ny), maxi(gx, nx), maxi(gy, ny)]
					if seen.has(key):
						continue
					seen[key] = true
					pairs.append({"gx": gx, "gy": gy, "nx": nx, "ny": ny})
	return pairs


func _apply_side_count(cell_idx: int, unit_side: int, delta: int) -> void:
	var mask_bit: int = MASK_FRIENDLY if unit_side == 0 else MASK_HOSTILE
	if unit_side == 0:
		_friendly_count_by_cell[cell_idx] = maxi(0, _friendly_count_by_cell[cell_idx] + delta)
	else:
		_hostile_count_by_cell[cell_idx] = maxi(0, _hostile_count_by_cell[cell_idx] + delta)
	if delta > 0:
		_cell_side_mask[cell_idx] |= mask_bit
	elif delta < 0:
		if unit_side == 0 and _friendly_count_by_cell[cell_idx] <= 0:
			_cell_side_mask[cell_idx] &= ~MASK_FRIENDLY
		elif unit_side != 0 and _hostile_count_by_cell[cell_idx] <= 0:
			_cell_side_mask[cell_idx] &= ~MASK_HOSTILE


func _refresh_contested(cell_idx: int) -> void:
	var contested: bool = (_cell_side_mask[cell_idx] & MASK_BOTH) == MASK_BOTH
	var had: bool = _contested_lookup.has(cell_idx)
	if contested and not had:
		var gx: int = cell_idx % width
		var gy: int = cell_idx / width
		_contested_cells.append(Vector2i(gx, gy))
		_contested_lookup[cell_idx] = true
	elif not contested and had:
		_contested_lookup.erase(cell_idx)
		var gx_r: int = cell_idx % width
		var gy_r: int = cell_idx / width
		for i in range(_contested_cells.size() - 1, -1, -1):
			var c: Vector2i = _contested_cells[i]
			if c.x == gx_r and c.y == gy_r:
				_contested_cells.remove_at(i)
				break
