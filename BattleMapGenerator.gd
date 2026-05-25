class_name BattleMapGenerator
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")

const GRID_W := 64
const GRID_H := 48
const CELL := 32.0


static func get_lane_spawn_positions(zone: Rect2, count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var positions: PackedVector2Array = PackedVector2Array()
	if count <= 0 or zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return positions
	var cols := maxi(1, int(sqrt(float(count)) * 1.4))
	var rows := maxi(1, int(ceil(float(count) / float(cols))))
	var cell_w := zone.size.x / float(cols)
	var cell_h := zone.size.y / float(rows)
	var placed := 0
	for row in range(rows):
		for col in range(cols):
			if placed >= count:
				break
			var jitter := Vector2(
				rng.randf_range(-cell_w * 0.22, cell_w * 0.22),
				rng.randf_range(-cell_h * 0.22, cell_h * 0.22),
			)
			var pos := zone.position + Vector2(
				(col + 0.5) * cell_w,
				(row + 0.5) * cell_h,
			) + jitter
			positions.append(pos)
			placed += 1
	return positions


static func generate(
	seed_value: int,
	terrain_tag: String,
	player_count: int,
	enemy_count: int,
	node_id: String = "",
):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := BattleMapDataLib.new()
	data.map_seed = seed_value
	data.terrain_tag = terrain_tag
	data.grid_width = GRID_W
	data.grid_height = GRID_H
	data.cell_size = CELL
	data.map_size = Vector2(GRID_W * CELL, GRID_H * CELL)
	data.player_allocation = player_count
	data.enemy_allocation = enemy_count
	data.node_id = node_id
	data.mass_unit_mode = true
	data.contact_column = GRID_W / 2
	data.objective_sectors_required = 3
	data.max_visual_units = 2500
	data.active_lite_cap = 2500
	data.impostor_size = 22.0
	data.engagement_zoom = 0.42
	_apply_terrain_modifiers(data)
	data.blocked_cells = PackedByteArray()
	data.blocked_cells.resize(GRID_W * GRID_H)
	data.cover_cells = PackedByteArray()
	data.cover_cells.resize(GRID_W * GRID_H)
	_paint_terrain(data, terrain_tag, rng)
	_define_zones(data)
	_build_regions_and_graph(data, rng)
	return data


static func _apply_terrain_modifiers(data) -> void:
	match data.terrain_tag:
		"mountain":
			data.approach_speed_mult = 0.75
			data.defender_bonus = 1.15
		"urban":
			data.approach_speed_mult = 0.82
			data.defender_bonus = 1.1
		"open_field":
			data.approach_speed_mult = 1.15
			data.defender_bonus = 0.95
		_:
			data.approach_speed_mult = 1.0
			data.defender_bonus = 1.0


static func _paint_terrain(data, terrain_tag: String, rng: RandomNumberGenerator) -> void:
	match terrain_tag:
		"mountain":
			for gy in range(GRID_H):
				for gx in range(GRID_W):
					var ridge: float = absf(float(gx) - GRID_W * 0.5) / float(GRID_W)
					if ridge > 0.28 and rng.randf() < 0.55:
						data.blocked_cells[gy * GRID_W + gx] = 1
		"urban":
			for block_y in range(0, GRID_H, 6):
				for block_x in range(0, GRID_W, 5):
					if rng.randf() < 0.42:
						for dy in range(4):
							for dx in range(4):
								var gx := block_x + dx
								var gy := block_y + dy
								if gx < GRID_W and gy < GRID_H:
									data.blocked_cells[gy * GRID_W + gx] = 1
		"mixed":
			_paint_terrain(data, "mountain" if rng.randf() < 0.5 else "urban", rng)
		_:
			for gy in range(GRID_H):
				for gx in range(GRID_W):
					if gx < 2 or gy < 2 or gx >= GRID_W - 2 or gy >= GRID_H - 2:
						data.blocked_cells[gy * GRID_W + gx] = 1
	for gy in range(GRID_H):
		for gx in range(GRID_W):
			var idx := gy * GRID_W + gx
			if data.blocked_cells[idx] == 0 and rng.randf() < 0.08:
				data.cover_cells[idx] = 1


static func _define_zones(data) -> void:
	var half: Vector2 = data.map_size * 0.5
	var contact_x: float = (float(data.contact_column) + 0.5) * CELL - half.x
	data.player_spawn_zone = Rect2(
		Vector2(-half.x + CELL * 2, -half.y + CELL * 6),
		Vector2(contact_x + CELL * 2 - (-half.x + CELL * 2), data.map_size.y - CELL * 12),
	)
	data.enemy_spawn_zone = Rect2(
		Vector2(contact_x + CELL * 2, -half.y + CELL * 6),
		Vector2(half.x - CELL * 2 - (contact_x + CELL * 2), data.map_size.y - CELL * 12),
	)
	data.extraction_zone = Rect2(
		Vector2(-half.x + CELL * 2, -half.y + CELL * 2),
		Vector2(CELL * 6, CELL * 5),
	)


static func _build_regions_and_graph(data, rng: RandomNumberGenerator) -> void:
	var sector_cols := 8
	var sector_rows := 6
	var sw: float = data.map_size.x / float(sector_cols)
	var sh: float = data.map_size.y / float(sector_rows)
	var half: Vector2 = data.map_size * 0.5
	data.regions.clear()
	var graph = data.path_graph
	graph.nodes.clear()
	graph.edges.clear()
	graph.corridor_rects.clear()
	graph.corridor_segments.clear()
	var contact_col_sector: int = sector_cols / 2
	for row in range(sector_rows):
		for col in range(sector_cols):
			var region_id := "sec_%d_%d" % [row, col]
			var center := Vector2(
				(col + 0.5) * sw - half.x,
				(row + 0.5) * sh - half.y,
			)
			var walkable := 0
			for _i in range(12):
				var gx: int = rng.randi_range(1, data.grid_width - 2)
				var gy: int = rng.randi_range(1, data.grid_height - 2)
				if not data.is_cell_blocked(gx, gy):
					walkable += 1
			var control := BattleMapDataLib.CONTROL_NEUTRAL
			if col < contact_col_sector - 1:
				control = BattleMapDataLib.CONTROL_PLAYER
			elif col > contact_col_sector:
				control = BattleMapDataLib.CONTROL_ENEMY
			var is_objective := row >= 2 and row <= 3 and col >= contact_col_sector - 1 and col <= contact_col_sector
			data.regions.append({
				"id": region_id,
				"center": center,
				"walkable_score": walkable,
				"control": control,
				"pressure": 0.0,
				"is_objective": is_objective,
				"col": col,
				"row": row,
			})
			graph.nodes[region_id] = center
	for row in range(sector_rows):
		for col in range(sector_cols):
			var id_a := "sec_%d_%d" % [row, col]
			if col + 1 < sector_cols:
				var id_b := "sec_%d_%d" % [row, col + 1]
				graph.edges.append([id_a, id_b])
				graph.edges.append([id_b, id_a])
			if row + 1 < sector_rows:
				var id_c := "sec_%d_%d" % [row + 1, col]
				graph.edges.append([id_a, id_c])
				graph.edges.append([id_c, id_a])
