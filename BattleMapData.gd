class_name BattleMapData
extends RefCounted

const PathGraphScript := preload("res://DynamicPathGraph.gd")

const CONTROL_NEUTRAL := "neutral"
const CONTROL_PLAYER := "player"
const CONTROL_ENEMY := "enemy"

var map_seed: int = 0
var terrain_tag: String = "open_field"
var map_size: Vector2 = Vector2(2048, 1536)
var grid_width: int = 64
var grid_height: int = 48
var cell_size: float = 32.0
var blocked_cells: PackedByteArray = PackedByteArray()
var cover_cells: PackedByteArray = PackedByteArray()
var player_spawn_zone: Rect2 = Rect2()
var enemy_spawn_zone: Rect2 = Rect2()
var extraction_zone: Rect2 = Rect2()
var regions: Array[Dictionary] = []
var path_graph = PathGraphScript.new()
var mass_unit_mode: bool = true
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


func is_cell_blocked(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
		return true
	var idx := gy * grid_width + gx
	if idx >= blocked_cells.size():
		return false
	return blocked_cells[idx] > 0


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
