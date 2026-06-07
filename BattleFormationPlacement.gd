class_name BattleFormationPlacement
extends RefCounted

const BattleMapPlacementLib := preload("res://BattleMapPlacement.gd")

## Spawn ~100-unit batches in recognizable military shapes (line, square, column).

const BATCH_SIZE := 100

enum Kind { LINE, SQUARE, COLUMN }


static func spawn_cell_for_unit(
	battle_data,
	side: int,
	slot: int,
	total_units: int,
	occupied: Dictionary,
	cell_grid = null,
	unit_size: int = 1,
) -> Vector2i:
	if battle_data == null or total_units <= 0:
		return Vector2i(-1, -1)
	var batch_index: int = slot / BATCH_SIZE
	var slot_in_batch: int = slot % BATCH_SIZE
	var batch_total: int = mini(BATCH_SIZE, total_units - batch_index * BATCH_SIZE)
	var kind: int = _formation_for_batch(batch_index)
	var anchor: Vector2i = _batch_anchor(battle_data, side, batch_index, total_units, occupied)
	var offset: Vector2i = _offset_in_formation(kind, slot_in_batch, batch_total)
	var target := Vector2i(anchor.x + offset.x, anchor.y + offset.y)
	return _resolve_passable_cell(
		battle_data, side, target, anchor, occupied, cell_grid, unit_size, slot
	)


static func _formation_for_batch(batch_index: int) -> int:
	match batch_index % 3:
		0:
			return Kind.LINE
		1:
			return Kind.SQUARE
		_:
			return Kind.COLUMN


static func _offset_in_formation(kind: int, slot_in_batch: int, batch_total: int) -> Vector2i:
	var n: int = maxi(1, batch_total)
	match kind:
		Kind.LINE:
			# Rank facing the enemy: wide front, shallow depth.
			var files: int = clampi(n, 1, 40)
			var ranks: int = int(ceil(float(n) / float(files)))
			var file: int = slot_in_batch % files
			var rank: int = slot_in_batch / files
			return Vector2i(-rank, file - ranks / 2)
		Kind.SQUARE:
			var side_len: int = maxi(1, int(ceil(sqrt(float(n)))))
			var col: int = slot_in_batch % side_len
			var row: int = slot_in_batch / side_len
			return Vector2i(-row, col - side_len / 2)
		Kind.COLUMN:
			var files: int = clampi(maxi(4, int(sqrt(float(n)))), 4, 12)
			var ranks: int = int(ceil(float(n) / float(files)))
			var file: int = slot_in_batch % files
			var rank: int = slot_in_batch / files
			return Vector2i(-rank, file - files / 2)
	return Vector2i.ZERO


static func _batch_anchor(
	battle_data,
	side: int,
	batch_index: int,
	total_units: int,
	occupied: Dictionary,
) -> Vector2i:
	var zone: Rect2 = (
		battle_data.player_spawn_zone
		if side == 0
		else battle_data.enemy_spawn_zone
	)
	var batches: int = maxi(1, int(ceil(float(total_units) / float(BATCH_SIZE))))
	var g0: Vector2i = battle_data.world_to_grid(zone.position)
	var g1: Vector2i = battle_data.world_to_grid(zone.position + zone.size)
	var x0: int = clampi(mini(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var x1: int = clampi(maxi(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var y0: int = clampi(mini(g0.y, g1.y), 0, battle_data.grid_height - 1)
	var y1: int = clampi(maxi(g0.y, g1.y), 0, battle_data.grid_height - 1)
	var front_x: int = x0
	if side == 0:
		for gx in range(x1, x0 - 1, -1):
			for gy in range(y0, y1 + 1):
				if battle_data.is_land_cell(gx, gy) and gx < battle_data.contact_column:
					front_x = gx
					break
			if front_x != x0:
				break
	else:
		front_x = x1
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				if battle_data.is_land_cell(gx, gy) and gx > battle_data.contact_column:
					front_x = gx
					break
			if front_x != x1:
				break
	var mid_y: int = (y0 + y1) / 2
	var band_step: int = maxi(8, (y1 - y0 + 1) / maxi(1, batches))
	var gy_anchor: int = clampi(mid_y + (batch_index - batches / 2) * band_step, y0, y1)
	var depth_step: int = 3
	var gx_anchor: int = front_x
	if side == 0:
		gx_anchor = clampi(front_x - batch_index * depth_step, x0, battle_data.contact_column - 1)
	else:
		gx_anchor = clampi(front_x + batch_index * depth_step, battle_data.contact_column + 1, x1)
	for attempt in range(48):
		var try_g := Vector2i(gx_anchor, gy_anchor + attempt - 24)
		if _cell_ok(battle_data, side, try_g, occupied, null, 1):
			return try_g
	return Vector2i(gx_anchor, gy_anchor)


static func _resolve_passable_cell(
	battle_data,
	side: int,
	target: Vector2i,
	anchor: Vector2i,
	occupied: Dictionary,
	cell_grid,
	unit_size: int,
	seed_slot: int,
) -> Vector2i:
	if _cell_ok(battle_data, side, target, occupied, cell_grid, unit_size):
		var key: int = BattleMapPlacementLib.spawn_cell_key(target.x, target.y)
		occupied[key] = true
		return target
	for radius in range(1, 10):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var g := Vector2i(target.x + dx, target.y + dy)
				if _cell_ok(battle_data, side, g, occupied, cell_grid, unit_size):
					occupied[BattleMapPlacementLib.spawn_cell_key(g.x, g.y)] = true
					return g
	return BattleMapPlacementLib.find_open_cell_in_zone(
		battle_data,
		battle_data.player_spawn_zone if side == 0 else battle_data.enemy_spawn_zone,
		side,
		seed_slot,
		occupied,
		cell_grid,
		unit_size,
	)


static func _cell_ok(
	battle_data,
	side: int,
	g: Vector2i,
	occupied: Dictionary,
	cell_grid,
	unit_size: int,
) -> bool:
	if g.x < 0 or g.y < 0:
		return false
	if not battle_data.is_land_cell(g.x, g.y):
		return false
	if side == 0 and g.x >= battle_data.contact_column:
		return false
	if side != 0 and g.x <= battle_data.contact_column:
		return false
	var key: int = BattleMapPlacementLib.spawn_cell_key(g.x, g.y)
	if occupied.has(key):
		return false
	if cell_grid != null and not cell_grid.can_enter(g.x, g.y, unit_size, side):
		return false
	return true
