class_name BattleMapSnapshot
extends RefCounted

const BattleMapDataLib := preload("res://BattleMapData.gd")


static func to_dict(map_data) -> Dictionary:
	if map_data == null:
		return {}
	var terrain_arr: Array = []
	for i in range(map_data.terrain_cells.size()):
		terrain_arr.append(int(map_data.terrain_cells[i]))
	var blocked_arr: Array = []
	for i in range(map_data.blocked_cells.size()):
		blocked_arr.append(int(map_data.blocked_cells[i]))
	var cover_arr: Array = []
	for i in range(map_data.cover_cells.size()):
		cover_arr.append(int(map_data.cover_cells[i]))
	var move_arr: Array = []
	for i in range(map_data.terrain_move_cost.size()):
		move_arr.append(float(map_data.terrain_move_cost[i]))
	var def_arr: Array = []
	for i in range(map_data.terrain_defense.size()):
		def_arr.append(float(map_data.terrain_defense[i]))
	var height_arr: Array = []
	for i in range(map_data.tile_height.size()):
		height_arr.append(float(map_data.tile_height[i]))
	return {
		"map_seed": map_data.map_seed,
		"terrain_tag": map_data.terrain_tag,
		"terrain_mix": map_data.terrain_mix,
		"grid_width": map_data.grid_width,
		"grid_height": map_data.grid_height,
		"cell_size": map_data.cell_size,
		"map_size": [map_data.map_size.x, map_data.map_size.y],
		"contact_column": map_data.contact_column,
		"node_id": map_data.node_id,
		"node_type": map_data.node_type,
		"player_allocation": map_data.player_allocation,
		"enemy_allocation": map_data.enemy_allocation,
		"player_spawn_cells": _spawn_cells_to_array(map_data.player_spawn_cells),
		"enemy_spawn_cells": _spawn_cells_to_array(map_data.enemy_spawn_cells),
		"player_home_grid": [map_data.player_home_grid.x, map_data.player_home_grid.y],
		"enemy_home_grid": [map_data.enemy_home_grid.x, map_data.enemy_home_grid.y],
		"player_spawn_zone": _rect_to_array(map_data.player_spawn_zone),
		"enemy_spawn_zone": _rect_to_array(map_data.enemy_spawn_zone),
		"terrain_cells": terrain_arr,
		"blocked_cells": blocked_arr,
		"cover_cells": cover_arr,
		"terrain_move_cost": move_arr,
		"terrain_defense": def_arr,
		"tile_height": height_arr,
	}


static func from_dict(data: Dictionary):
	if data.is_empty():
		return null
	var map_data = BattleMapDataLib.new()
	map_data.map_seed = int(data.get("map_seed", 0))
	map_data.terrain_tag = str(data.get("terrain_tag", "open_field"))
	map_data.terrain_mix = data.get("terrain_mix", {})
	map_data.grid_width = int(data.get("grid_width", 96))
	map_data.grid_height = int(data.get("grid_height", 72))
	map_data.cell_size = float(data.get("cell_size", 32.0))
	var ms = data.get("map_size", [3072, 2304])
	if typeof(ms) == TYPE_ARRAY and ms.size() >= 2:
		map_data.map_size = Vector2(float(ms[0]), float(ms[1]))
	map_data.contact_column = int(data.get("contact_column", map_data.grid_width / 2))
	map_data.node_id = str(data.get("node_id", ""))
	map_data.node_type = str(data.get("node_type", "battle"))
	map_data.player_allocation = int(data.get("player_allocation", 500))
	map_data.enemy_allocation = int(data.get("enemy_allocation", 500))
	map_data.player_spawn_cells = _spawn_cells_from_array(data.get("player_spawn_cells", []))
	map_data.enemy_spawn_cells = _spawn_cells_from_array(data.get("enemy_spawn_cells", []))
	map_data.player_home_grid = _grid_from_array(data.get("player_home_grid", []))
	map_data.enemy_home_grid = _grid_from_array(data.get("enemy_home_grid", []))
	if map_data.player_home_grid.x < 0 and not map_data.player_spawn_cells.is_empty():
		var p0 = map_data.player_spawn_cells[0]
		map_data.player_home_grid = p0 if p0 is Vector2i else Vector2i(int(p0.x), int(p0.y))
	if map_data.enemy_home_grid.x < 0 and not map_data.enemy_spawn_cells.is_empty():
		var e0 = map_data.enemy_spawn_cells[0]
		map_data.enemy_home_grid = e0 if e0 is Vector2i else Vector2i(int(e0.x), int(e0.y))
	map_data.player_spawn_zone = _rect_from_array(data.get("player_spawn_zone", []))
	map_data.enemy_spawn_zone = _rect_from_array(data.get("enemy_spawn_zone", []))
	_fill_packed_byte(map_data.terrain_cells, data.get("terrain_cells", []), map_data.grid_width * map_data.grid_height)
	_fill_packed_byte(map_data.blocked_cells, data.get("blocked_cells", []), map_data.grid_width * map_data.grid_height)
	_fill_packed_byte(map_data.cover_cells, data.get("cover_cells", []), map_data.grid_width * map_data.grid_height)
	_fill_packed_float(map_data.terrain_move_cost, data.get("terrain_move_cost", []), map_data.grid_width * map_data.grid_height)
	_fill_packed_float(map_data.terrain_defense, data.get("terrain_defense", []), map_data.grid_width * map_data.grid_height)
	var height_size: int = map_data.grid_width * map_data.grid_height
	_fill_packed_float(map_data.tile_height, data.get("tile_height", []), height_size)
	if map_data.tile_height.is_empty() or map_data.tile_height.size() != height_size:
		map_data.tile_height.resize(height_size)
		map_data.tile_height.fill(0.5)
	if map_data.terrain_move_cost.is_empty() or map_data.terrain_defense.is_empty():
		map_data.rebuild_terrain_arrays()
	return map_data


static func _fill_packed_byte(target: PackedByteArray, src: Variant, size: int) -> void:
	target.resize(size)
	if typeof(src) != TYPE_ARRAY:
		return
	for i in range(mini(size, src.size())):
		target[i] = int(src[i]) & 0xFF


static func _fill_packed_float(target: PackedFloat32Array, src: Variant, size: int) -> void:
	target.resize(size)
	if typeof(src) != TYPE_ARRAY:
		return
	for i in range(mini(size, src.size())):
		target[i] = float(src[i])


static func _grid_from_array(src: Variant) -> Vector2i:
	if typeof(src) != TYPE_ARRAY or src.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(src[0]), int(src[1]))


static func _spawn_cells_to_array(cells: Array) -> Array:
	var out: Array = []
	for cell in cells:
		if cell is Vector2i:
			out.append([cell.x, cell.y])
		elif typeof(cell) == TYPE_ARRAY and cell.size() >= 2:
			out.append([int(cell[0]), int(cell[1])])
		elif typeof(cell) == TYPE_DICTIONARY:
			out.append([int(cell.get("x", cell.get("gx", 0))), int(cell.get("y", cell.get("gy", 0)))])
	return out


static func _rect_to_array(zone: Rect2) -> Array:
	if zone.size.x <= 0.0 and zone.size.y <= 0.0:
		return []
	return [zone.position.x, zone.position.y, zone.size.x, zone.size.y]


static func _rect_from_array(src: Variant) -> Rect2:
	if typeof(src) != TYPE_ARRAY or src.size() < 4:
		return Rect2()
	return Rect2(float(src[0]), float(src[1]), float(src[2]), float(src[3]))


static func _spawn_cells_from_array(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for cell in src:
		if cell is Vector2i:
			out.append(cell)
		elif typeof(cell) == TYPE_ARRAY and cell.size() >= 2:
			out.append(Vector2i(int(cell[0]), int(cell[1])))
		elif typeof(cell) == TYPE_DICTIONARY:
			out.append(Vector2i(int(cell.get("x", cell.get("gx", 0))), int(cell.get("y", cell.get("gy", 0)))))
	return out
