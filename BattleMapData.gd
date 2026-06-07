class_name BattleMapData
extends RefCounted

const PathGraphScript := preload("res://DynamicPathGraph.gd")

const CONTROL_NEUTRAL := "neutral"
const CONTROL_PLAYER := "player"
const CONTROL_ENEMY := "enemy"

enum Terrain {
	GRASS = 0,
	WATER = 1,
	MOUNTAIN = 2,
	SAND = 3,
	MUD = 4,
}

const TERRAIN_NAMES: Array[String] = ["grass", "water", "mountain", "sand", "mud"]

## Per-terrain move cost (1 = normal). Values >= IMPASSABLE_MOVE_COST block movement.
const TERRAIN_MOVE_COST: Array[float] = [1.0, 99.0, 2.2, 1.35, 1.65]
const TERRAIN_DEFENSE: Array[float] = [1.0, 1.0, 1.35, 0.92, 1.12]
const IMPASSABLE_MOVE_COST := 50.0

var map_seed: int = 0
var terrain_tag: String = "open_field"
var terrain_mix: Dictionary = {}
var map_size: Vector2 = Vector2(3072, 2304)
var grid_width: int = 96
var grid_height: int = 72
var cell_size: float = 32.0
## Dominions-style capture points (see BattleMapGenerator placement).
var capture_points: Array = []
var node_type: String = "battle"
var terrain_cells: PackedByteArray = PackedByteArray()
var terrain_move_cost: PackedFloat32Array = PackedFloat32Array()
var terrain_defense: PackedFloat32Array = PackedFloat32Array()
var tile_height: PackedFloat32Array = PackedFloat32Array()
var blocked_cells: PackedByteArray = PackedByteArray()
var cover_cells: PackedByteArray = PackedByteArray()
var player_spawn_zone: Rect2 = Rect2()
var enemy_spawn_zone: Rect2 = Rect2()
var extraction_zone: Rect2 = Rect2()
## Fixed land spawn slots per side (Vector2i grid cells), built at map generation.
var player_spawn_cells: Array = []
var enemy_spawn_cells: Array = []
## Resolved land tile for HQ / home-base injection (never water).
var player_home_grid: Vector2i = Vector2i(-1, -1)
var enemy_home_grid: Vector2i = Vector2i(-1, -1)
var regions: Array[Dictionary] = []
var path_graph = PathGraphScript.new()
var mass_unit_mode: bool = false
var player_allocation: int = 500
var enemy_allocation: int = 500
var node_id: String = ""
var contact_column: int = 32
var objective_sectors_required: int = 3
var approach_speed_mult: float = 1.0
## Scales engagement camera zoom; musou march tuning lives in BattleMusouFeel.gd.
var musou_feel_scale: float = 1.0
var defender_bonus: float = 1.0
var max_visual_units: int = 2500
var active_lite_cap: int = 2500
var impostor_size: float = 22.0
var impostor_scale: float = 0.9
var engagement_zoom: float = 0.42
## RTS world: {id, team, gx, gy, kind} — kind "spawner" injects like home each round.
var placed_structures: Array = []
## World conquest: capital tiles for objective win.
var player_capital_grid: Vector2i = Vector2i(-1, -1)
var enemy_capital_grid: Vector2i = Vector2i(-1, -1)


func cell_index(gx: int, gy: int) -> int:
	return gy * grid_width + gx


func get_cell_terrain(gx: int, gy: int) -> int:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return Terrain.WATER
	var idx := cell_index(gx, gy)
	if idx >= terrain_cells.size():
		return Terrain.GRASS
	return int(terrain_cells[idx])


func get_move_cost(gx: int, gy: int) -> float:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return IMPASSABLE_MOVE_COST
	var idx := cell_index(gx, gy)
	if idx < terrain_move_cost.size():
		return terrain_move_cost[idx]
	var t: int = get_cell_terrain(gx, gy)
	if t >= 0 and t < TERRAIN_MOVE_COST.size():
		return TERRAIN_MOVE_COST[t]
	return 1.0


func get_defense(gx: int, gy: int) -> float:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return 1.0
	var idx := cell_index(gx, gy)
	if idx < terrain_defense.size():
		return terrain_defense[idx]
	var t: int = get_cell_terrain(gx, gy)
	if t >= 0 and t < TERRAIN_DEFENSE.size():
		return TERRAIN_DEFENSE[t]
	return 1.0


## Height layer (0.0 lowlands to 1.0 peaks → 0–100 terrain in sim). Pressure is not capped by height.
## is_passable / is_land_cell will later incorporate height for fluid movement rules.
func get_tile_height(gx: int, gy: int) -> float:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return 0.0
	var idx := cell_index(gx, gy)
	if idx < tile_height.size():
		return tile_height[idx]
	return 0.5


func is_passable(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return false
	if is_cell_blocked(gx, gy):
		return false
	return get_move_cost(gx, gy) < IMPASSABLE_MOVE_COST


func is_land_cell(gx: int, gy: int) -> bool:
	if not is_passable(gx, gy):
		return false
	return get_cell_terrain(gx, gy) != Terrain.WATER


func is_cell_blocked(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return true
	var idx := cell_index(gx, gy)
	if idx >= blocked_cells.size():
		return false
	return blocked_cells[idx] > 0


func sync_blocked_from_terrain() -> void:
	var total := grid_width * grid_height
	if blocked_cells.size() != total:
		blocked_cells.resize(total)
	for gy in range(grid_height):
		for gx in range(grid_width):
			var idx := cell_index(gx, gy)
			var blocked: int = 1 if get_move_cost(gx, gy) >= IMPASSABLE_MOVE_COST else 0
			blocked_cells[idx] = blocked


func rebuild_terrain_arrays() -> void:
	var total := grid_width * grid_height
	terrain_move_cost.resize(total)
	terrain_defense.resize(total)
	for gy in range(grid_height):
		for gx in range(grid_width):
			var idx := cell_index(gx, gy)
			var t: int = get_cell_terrain(gx, gy)
			if t < 0 or t >= TERRAIN_MOVE_COST.size():
				t = Terrain.GRASS
			terrain_move_cost[idx] = TERRAIN_MOVE_COST[t]
			terrain_defense[idx] = TERRAIN_DEFENSE[t]
	sync_blocked_from_terrain()


func sector_col_row_for_grid(gx: int, gy: int) -> Vector2i:
	var sector_cols := 8
	var sector_rows := 6
	var col: int = clampi(int(float(gx) * float(sector_cols) / float(grid_width)), 0, sector_cols - 1)
	var row: int = clampi(int(float(gy) * float(sector_rows) / float(grid_height)), 0, sector_rows - 1)
	return Vector2i(col, row)


func region_id_for_grid(gx: int, gy: int) -> String:
	var cr := sector_col_row_for_grid(gx, gy)
	return "sec_%d_%d" % [cr.y, cr.x]


func region_index_for_grid(gx: int, gy: int) -> int:
	var want_id := region_id_for_grid(gx, gy)
	for i in range(regions.size()):
		if str(regions[i].get("id", "")) == want_id:
			return i
	return 0


func cell_center(gx: int, gy: int) -> Vector2:
	var half := map_size * 0.5
	return Vector2(
		(gx + 0.5) * cell_size - half.x,
		(gy + 0.5) * cell_size - half.y,
	)


func world_to_grid(pos: Vector2) -> Vector2i:
	var half := map_size * 0.5
	var gx := int(floor((pos.x + half.x) / cell_size))
	var gy := int(floor((pos.y + half.y) / cell_size))
	return Vector2i(gx, gy)


func snap_world_to_cell_center(pos: Vector2) -> Vector2:
	var g := world_to_grid(pos)
	g.x = clampi(g.x, 0, grid_width - 1)
	g.y = clampi(g.y, 0, grid_height - 1)
	if not is_land_cell(g.x, g.y):
		return _nearest_land_center(g.x, g.y)
	return cell_center(g.x, g.y)


func _nearest_land_center(gx: int, gy: int) -> Vector2:
	for radius in range(1, 12):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var nx: int = gx + dx
				var ny: int = gy + dy
				if is_land_cell(nx, ny):
					return cell_center(nx, ny)
	return cell_center(gx, gy)


func _nearest_passable_center(gx: int, gy: int) -> Vector2:
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var nx: int = gx + dx
				var ny: int = gy + dy
				if is_passable(nx, ny):
					return cell_center(nx, ny)
	return cell_center(gx, gy)


func get_region(region_id: String) -> Dictionary:
	for region in regions:
		if str(region.get("id", "")) == region_id:
			return region
	return {}


func get_region_control(region_id: String) -> String:
	var region := get_region(region_id)
	return str(region.get("control", CONTROL_NEUTRAL))


func set_region_control(region_id: String, control: String) -> void:
	for i in range(regions.size()):
		if str(regions[i].get("id", "")) == region_id:
			regions[i]["control"] = control
			return


func count_controlled(control: String) -> int:
	var n := 0
	for region in regions:
		if str(region.get("control", "")) == control:
			n += 1
	return n


func count_objectives_held() -> int:
	var n := 0
	for region in regions:
		if bool(region.get("is_objective", false)) and str(region.get("control", "")) == CONTROL_PLAYER:
			n += 1
	return n


func total_objectives() -> int:
	var n := 0
	for region in regions:
		if bool(region.get("is_objective", false)):
			n += 1
	return n


func get_capture_point(cp_id: String) -> Dictionary:
	for cp in capture_points:
		if str(cp.get("id", "")) == cp_id:
			return cp
	return {}


func get_cp_at_world(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for cp in capture_points:
		var center: Vector2 = cp.get("world_pos", Vector2.ZERO)
		var radius: float = float(cp.get("radius_cells", 4)) * cell_size
		var dist: float = center.distance_to(pos)
		if dist <= radius and dist < best_dist:
			best_dist = dist
			best = cp
	return best


func count_cps_held(side: String) -> int:
	var n := 0
	for cp in capture_points:
		if str(cp.get("owner", CONTROL_NEUTRAL)) == side:
			n += 1
	return n


func all_cps_held(side: String) -> bool:
	if capture_points.is_empty():
		return false
	return count_cps_held(side) >= capture_points.size()


func total_capture_points() -> int:
	return capture_points.size()


func cp_ids() -> Array:
	var ids: Array = []
	for cp in capture_points:
		ids.append(str(cp.get("id", "")))
	return ids


func avg_defense_in_cp_zone(cp: Dictionary) -> float:
	if cp.is_empty():
		return 1.0
	var gx: int = int(cp.get("grid_x", 0))
	var gy: int = int(cp.get("grid_y", 0))
	var radius: int = int(cp.get("radius_cells", 4))
	var total := 0.0
	var count := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var nx: int = gx + dx
			var ny: int = gy + dy
			if not is_passable(nx, ny):
				continue
			total += get_defense(nx, ny)
			count += 1
	if count <= 0:
		return 1.0
	return total / float(count)


func region_world_rect(region: Dictionary) -> Rect2:
	var sector_cols := 8
	var sector_rows := 6
	var sw: float = map_size.x / float(sector_cols)
	var sh: float = map_size.y / float(sector_rows)
	var parts: PackedStringArray = str(region.get("id", "")).split("_")
	if parts.size() < 3:
		return Rect2(region.get("center", Vector2.ZERO), Vector2(sw, sh))
	var row: int = int(parts[1])
	var col: int = int(parts[2])
	var half := map_size * 0.5
	var top_left := Vector2(
		float(col) * sw - half.x,
		float(row) * sh - half.y,
	)
	return Rect2(top_left, Vector2(sw, sh))
