class_name BattleMapPlacement
extends RefCounted

## Passable-only spawn and formation positions for battle visuals.


static func spawn_in_zone(battle_data, zone: Rect2, index: int, total: int, rng: RandomNumberGenerator) -> Vector2:
	if battle_data == null:
		return Vector2.ZERO
	if zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return _random_land_in_rect(battle_data, zone, rng)
	var cols := maxi(1, int(sqrt(float(total)) * 1.35))
	var rows := maxi(1, int(ceil(float(total) / float(cols))))
	var slot: int = clampi(index, 0, cols * rows - 1)
	var col: int = slot % cols
	var row: int = slot / cols
	var cell_w := zone.size.x / float(cols)
	var cell_h := zone.size.y / float(rows)
	var base := zone.position + Vector2((col + 0.5) * cell_w, (row + 0.5) * cell_h)
	for attempt in range(24):
		var jitter := Vector2(
			rng.randf_range(-cell_w * 0.22, cell_w * 0.22),
			rng.randf_range(-cell_h * 0.22, cell_h * 0.22),
		)
		var snapped: Vector2 = battle_data.snap_world_to_cell_center(base + jitter)
		var g: Vector2i = battle_data.world_to_grid(snapped)
		if battle_data.is_land_cell(g.x, g.y):
			return snapped
	return _random_land_in_rect(battle_data, zone, rng)


static func formation_near_cp(battle_data, cp: Dictionary, side: int, slot: int, total: int, rng: RandomNumberGenerator) -> Vector2:
	if battle_data == null or cp.is_empty():
		return Vector2.ZERO
	var gx: int = int(cp.get("grid_x", 0))
	var gy: int = int(cp.get("grid_y", 0))
	var radius: int = int(cp.get("radius_cells", 4))
	var slots := maxi(1, total)
	var angle: float = float(slot) / float(slots) * TAU + rng.randf_range(-0.15, 0.15)
	var ring: float = rng.randf_range(0.35, 0.95)
	var dist_cells: int = maxi(1, int(float(radius) * ring))
	var ox: int = int(round(cos(angle) * float(dist_cells)))
	var oy: int = int(round(sin(angle) * float(dist_cells)))
	if side == 0:
		ox -= maxi(1, radius / 3)
	else:
		ox += maxi(1, radius / 3)
	for attempt in range(32):
		var tx: int = gx + ox + rng.randi_range(-1, 1)
		var ty: int = gy + oy + rng.randi_range(-1, 1)
		if battle_data.is_land_cell(tx, ty):
			return battle_data.cell_center(tx, ty)
	return battle_data.snap_world_to_cell_center(cp.get("world_pos", Vector2.ZERO))


static func build_rally_spawn_cells(battle_data) -> void:
	if battle_data == null:
		return
	battle_data.player_spawn_cells = _collect_spawn_cells_for_zone(
		battle_data, battle_data.player_spawn_zone, true
	)
	battle_data.enemy_spawn_cells = _collect_spawn_cells_for_zone(
		battle_data, battle_data.enemy_spawn_zone, false
	)
	battle_data.player_home_grid = _home_from_spawn_cells(
		battle_data, battle_data.player_spawn_cells, true
	)
	battle_data.enemy_home_grid = _home_from_spawn_cells(
		battle_data, battle_data.enemy_spawn_cells, false
	)


static func _home_from_spawn_cells(battle_data, cells: Array, is_player: bool) -> Vector2i:
	if not cells.is_empty():
		var first = cells[0]
		if first is Vector2i:
			return first
		return Vector2i(int(first.x), int(first.y))
	return _fallback_home_in_half(battle_data, is_player)


## Nearest passable land tile to the spawn zone center (HQ must not sit on water).
static func resolve_home_base_cell(battle_data, zone: Rect2, is_player: bool) -> Vector2i:
	if battle_data == null or zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return Vector2i(-1, -1)
	return _home_from_spawn_cells(
		battle_data,
		_collect_spawn_cells_for_zone(battle_data, zone, is_player),
		is_player,
	)


static func home_base_world_pos(battle_data, zone: Rect2, is_player: bool) -> Vector2:
	if battle_data == null:
		return Vector2.ZERO
	var g: Vector2i = resolve_home_base_cell(battle_data, zone, is_player)
	if g.x >= 0:
		return battle_data.cell_center(g.x, g.y)
	return battle_data.snap_world_to_cell_center(zone.get_center())


static func spawn_cell_key(gx: int, gy: int) -> int:
	return gx * 10000 + gy


static func spawn_cell_for_unit(
	battle_data,
	side: int,
	slot: int,
	occupied: Dictionary = {},
	cell_grid = null,
	unit_size: int = 1,
) -> Vector2i:
	if battle_data == null:
		return Vector2i(-1, -1)
	var cells: Array = (
		battle_data.player_spawn_cells
		if side == 0
		else battle_data.enemy_spawn_cells
	)
	if not cells.is_empty():
		var start: int = slot % cells.size()
		for attempt in range(cells.size()):
			var entry = cells[(start + attempt) % cells.size()]
			var g: Vector2i = entry if entry is Vector2i else Vector2i(int(entry.x), int(entry.y))
			var key: int = spawn_cell_key(g.x, g.y)
			if occupied.has(key):
				continue
			if cell_grid != null and not cell_grid.can_enter(g.x, g.y, unit_size):
				continue
			occupied[key] = true
			return g
	var zone: Rect2 = (
		battle_data.player_spawn_zone
		if side == 0
		else battle_data.enemy_spawn_zone
	)
	return find_open_cell_in_zone(battle_data, zone, side, slot, occupied, cell_grid, unit_size)


static func find_open_cell_in_zone(
	battle_data,
	zone: Rect2,
	side: int,
	slot: int,
	occupied: Dictionary,
	cell_grid = null,
	unit_size: int = 1,
) -> Vector2i:
	if battle_data == null:
		return Vector2i(-1, -1)
	var rng := RandomNumberGenerator.new()
	rng.seed = slot * 7919 + side * 104729
	var anchor: Vector2 = spawn_in_zone(battle_data, zone, slot, maxi(32, slot + 8), rng)
	var ag: Vector2i = battle_data.world_to_grid(anchor)
	for radius in range(0, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius and radius > 0:
					continue
				var gx: int = ag.x + dx
				var gy: int = ag.y + dy
				if not battle_data.is_land_cell(gx, gy):
					continue
				if side == 0 and gx >= battle_data.contact_column:
					continue
				if side != 0 and gx <= battle_data.contact_column:
					continue
				var key: int = spawn_cell_key(gx, gy)
				if occupied.has(key):
					continue
				if cell_grid != null and not cell_grid.can_enter(gx, gy, unit_size):
					continue
				occupied[key] = true
				return Vector2i(gx, gy)
	return Vector2i(-1, -1)


static func _collect_spawn_cells_for_zone(battle_data, zone: Rect2, is_player: bool) -> Array:
	var candidates: Array = []
	var g0: Vector2i = battle_data.world_to_grid(zone.position)
	var g1: Vector2i = battle_data.world_to_grid(zone.position + zone.size)
	var x0: int = clampi(mini(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var x1: int = clampi(maxi(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var y0: int = clampi(mini(g0.y, g1.y), 0, battle_data.grid_height - 1)
	var y1: int = clampi(maxi(g0.y, g1.y), 0, battle_data.grid_height - 1)
	var center: Vector2 = zone.get_center()
	var center_g: Vector2i = battle_data.world_to_grid(center)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if not battle_data.is_land_cell(gx, gy):
				continue
			if is_player and gx >= battle_data.contact_column:
				continue
			if not is_player and gx <= battle_data.contact_column:
				continue
			var dist: int = absi(gx - center_g.x) + absi(gy - center_g.y)
			candidates.append({"g": Vector2i(gx, gy), "d": dist})
	candidates.sort_custom(func(a, b): return int(a["d"]) < int(b["d"]))
	var out: Array = []
	for entry in candidates:
		out.append(entry["g"])
		if out.size() >= 2048:
			break
	return out


static func _random_land_in_rect(battle_data, zone: Rect2, rng: RandomNumberGenerator) -> Vector2:
	var g0: Vector2i = battle_data.world_to_grid(zone.position)
	var g1: Vector2i = battle_data.world_to_grid(zone.position + zone.size)
	var x0: int = clampi(mini(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var x1: int = clampi(maxi(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var y0: int = clampi(mini(g0.y, g1.y), 0, battle_data.grid_height - 1)
	var y1: int = clampi(maxi(g0.y, g1.y), 0, battle_data.grid_height - 1)
	for _attempt in range(64):
		var gx: int = rng.randi_range(x0, x1)
		var gy: int = rng.randi_range(y0, y1)
		if battle_data.is_land_cell(gx, gy):
			return battle_data.cell_center(gx, gy)
	return battle_data.snap_world_to_cell_center(zone.get_center())


static func tighten_spawn_zone_to_passable(
	battle_data,
	zone: Rect2,
	is_player: bool = true,
) -> Rect2:
	if battle_data == null:
		return zone
	var min_gx: int = battle_data.grid_width
	var min_gy: int = battle_data.grid_height
	var max_gx: int = 0
	var max_gy: int = 0
	var found := false
	var g0: Vector2i = battle_data.world_to_grid(zone.position)
	var g1: Vector2i = battle_data.world_to_grid(zone.position + zone.size)
	var x0: int = clampi(mini(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var x1: int = clampi(maxi(g0.x, g1.x), 0, battle_data.grid_width - 1)
	var y0: int = clampi(mini(g0.y, g1.y), 0, battle_data.grid_height - 1)
	var y1: int = clampi(maxi(g0.y, g1.y), 0, battle_data.grid_height - 1)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if not battle_data.is_land_cell(gx, gy):
				continue
			found = true
			min_gx = mini(min_gx, gx)
			min_gy = mini(min_gy, gy)
			max_gx = maxi(max_gx, gx)
			max_gy = maxi(max_gy, gy)
	if not found:
		var fallback: Vector2i = _fallback_home_in_half(battle_data, is_player)
		if fallback.x < 0:
			return zone
		min_gx = fallback.x
		min_gy = fallback.y
		max_gx = fallback.x
		max_gy = fallback.y
		found = true
	var half: Vector2 = battle_data.map_size * 0.5
	var pad: float = battle_data.cell_size * 0.5
	var pos := Vector2(
		float(min_gx) * battle_data.cell_size - half.x + pad,
		float(min_gy) * battle_data.cell_size - half.y + pad,
	)
	var size := Vector2(
		float(max_gx - min_gx + 1) * battle_data.cell_size - pad,
		float(max_gy - min_gy + 1) * battle_data.cell_size - pad,
	)
	var min_size := Vector2(battle_data.cell_size * 4.0, battle_data.cell_size * 4.0)
	size.x = maxf(size.x, min_size.x)
	size.y = maxf(size.y, min_size.y)
	return Rect2(pos, size)


static func _fallback_home_in_half(battle_data, is_player: bool) -> Vector2i:
	if battle_data == null:
		return Vector2i(-1, -1)
	var cx: int
	if is_player:
		cx = maxi(0, battle_data.contact_column / 3)
	else:
		var right_w: int = battle_data.grid_width - battle_data.contact_column
		cx = mini(
			battle_data.grid_width - 1,
			battle_data.contact_column + right_w * 2 / 3,
		)
	var cy: int = battle_data.grid_height / 2
	var max_r: int = maxi(battle_data.grid_width, battle_data.grid_height)
	for radius in range(0, max_r):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and absi(dx) != radius and absi(dy) != radius:
					continue
				var gx: int = cx + dx
				var gy: int = cy + dy
				if gx < 0 or gy < 0 or gx >= battle_data.grid_width or gy >= battle_data.grid_height:
					continue
				if is_player and gx >= battle_data.contact_column:
					continue
				if not is_player and gx <= battle_data.contact_column:
					continue
				if battle_data.is_land_cell(gx, gy):
					return Vector2i(gx, gy)
	return Vector2i(-1, -1)


