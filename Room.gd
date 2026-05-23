class_name Room
extends Area2D

signal cleared(room: Room)
signal soldier_entered(room: Room, soldier: SoldierUnit)
signal soldier_exited(room: Room, soldier: SoldierUnit)
signal order_requested(room: Room)

@export var room_name: String = "Room"
@export var room_color: Color = Color(0.12, 0.14, 0.2, 0.18)
@export var is_spawn_room: bool = false
@export var is_extraction_room: bool = false
@export var requires_clear: bool = true

var is_spawn_eligible: bool = false
var map_room_id: String = ""
var planned_enemy_count: int = 0
var deploy_selection_mode: bool = false
var soldiers_inside: Array[SoldierUnit] = []
var enemies_inside: Array[EnemyUnit] = []
var enemies_present: Array[EnemyUnit] = []
var is_cleared: bool = false
var is_revealed: bool = false
var is_searched: bool = false
var room_size: Vector2 = Vector2(180, 130)
var _status_text: String = "CLEAR"

@onready var fill_poly: Polygon2D = $FillPoly
@onready var border_line: Line2D = $BorderLine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("rooms")
	input_pickable = true
	if not requires_clear:
		is_cleared = true
	_apply_size(room_size)
	_update_visuals()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	input_event.connect(_on_room_input_event)

func set_spawn_selection_highlight(active: bool, eligible: bool = false, selected: bool = false) -> void:
	if not border_line:
		return
	if not active:
		_refresh_status()
		queue_redraw()
		return
	if selected:
		border_line.default_color = GameTheme.ACCENT_SUCCESS
	elif eligible:
		border_line.default_color = Color(0.35, 0.9, 0.55, 0.95)
	else:
		border_line.default_color = Color(0.75, 0.25, 0.25, 0.85)
	queue_redraw()

func configure(size: Vector2, color: Color) -> void:
	room_size = size
	room_color = color
	if is_node_ready():
		_apply_size(size)
		_update_visuals()

func _apply_size(size: Vector2) -> void:
	var half := size * 0.5
	if collision_shape.shape is RectangleShape2D:
		(collision_shape.shape as RectangleShape2D).size = size
	if fill_poly:
		fill_poly.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
	if border_line:
		border_line.points = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
			Vector2(-half.x, -half.y),
		])

func get_room_center() -> Vector2:
	return position

func _draw() -> void:
	var half := room_size * 0.5
	var title_pos := Vector2(-half.x + 8.0, -half.y + 8.0)
	var status_pos := Vector2(-half.x + 8.0, half.y - 22.0)
	if deploy_selection_mode:
		if is_spawn_eligible:
			draw_string(ThemeDB.fallback_font, title_pos, room_name, HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.85, 0.98, 0.9, 1.0))
			draw_string(ThemeDB.fallback_font, status_pos, "SECURE DEPLOY", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, GameTheme.ACCENT_SUCCESS)
		else:
			draw_string(ThemeDB.fallback_font, title_pos, "RESTRICTED", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.55, 0.58, 0.65, 0.9))
			draw_string(ThemeDB.fallback_font, status_pos, "NO DEPLOY", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, Color(0.75, 0.25, 0.25, 0.85))
		return
	if not is_revealed:
		draw_string(ThemeDB.fallback_font, title_pos, "???", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.45, 0.48, 0.55, 0.9))
		draw_string(ThemeDB.fallback_font, status_pos, "UNKNOWN", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, Color(0.35, 0.38, 0.45, 0.9))
		return
	draw_string(ThemeDB.fallback_font, title_pos, room_name, HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.95, 0.97, 1.0, 1.0))
	var status_color := _status_color()
	draw_string(ThemeDB.fallback_font, status_pos, _status_text, HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, status_color)

func _status_color() -> Color:
	if not is_revealed:
		return Color(0.35, 0.38, 0.45, 0.9)
	if is_extraction_room:
		return GameTheme.ACCENT_SUCCESS
	if is_cleared:
		return GameTheme.ACCENT_SUCCESS
	if _has_spotted_enemies():
		return GameTheme.ACCENT_DANGER
	if is_searched and not _has_spotted_enemies():
		return GameTheme.ACCENT_SUCCESS
	if requires_clear:
		return GameTheme.ACCENT_WARN
	return GameTheme.TEXT_MUTED

func _has_spotted_enemies() -> bool:
	return enemies_present.any(func(e): return e.is_alive and e.is_visible_to_player)

func reveal() -> void:
	if is_revealed:
		return
	is_revealed = true
	_update_visuals()

func mark_searched() -> void:
	is_searched = true
	_refresh_status()

func _on_room_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			order_requested.emit(self)
			if _viewport:
				_viewport.set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and deploy_selection_mode:
			order_requested.emit(self)
			if _viewport:
				_viewport.set_input_as_handled()

func register_enemy(enemy: EnemyUnit) -> void:
	if enemy not in enemies_inside:
		enemies_inside.append(enemy)
	if enemy not in enemies_present and contains_local_point(enemy.position, 0.0):
		enemies_present.append(enemy)
	_refresh_status()

func unregister_enemy(enemy: EnemyUnit) -> void:
	enemies_inside.erase(enemy)
	enemies_present.erase(enemy)
	check_cleared_status()

func _on_area_entered(area: Area2D) -> void:
	var unit := area.get_parent()
	if unit is SoldierUnit and unit.is_alive:
		if unit not in soldiers_inside:
			soldiers_inside.append(unit)
		soldier_entered.emit(self, unit)
	elif unit is EnemyUnit and unit.is_alive:
		if unit not in enemies_present:
			enemies_present.append(unit)
		_refresh_status()

func _on_area_exited(area: Area2D) -> void:
	var unit := area.get_parent()
	if unit is SoldierUnit:
		soldiers_inside.erase(unit)
		soldier_exited.emit(self, unit)
	elif unit is EnemyUnit:
		enemies_present.erase(unit)
		_refresh_status()

func check_cleared_status() -> void:
	if is_cleared or not requires_clear:
		return
	if not has_registered_enemies():
		is_cleared = true
		_refresh_status()
		cleared.emit(self)

func mark_contested() -> void:
	is_cleared = false
	_refresh_status()

func _refresh_status() -> void:
	if not is_revealed:
		_status_text = "UNKNOWN"
	elif is_extraction_room:
		_status_text = "EXTRACT"
	elif is_cleared:
		_status_text = "SECURED"
	elif _has_spotted_enemies():
		_status_text = "CONTACT"
	elif is_searched:
		_status_text = "CLEAR"
	elif requires_clear:
		_status_text = "OBJECTIVE"
	else:
		_status_text = "UNSCANNED"
	if border_line:
		if not is_revealed:
			border_line.default_color = Color(0.25, 0.28, 0.34, 0.45)
		elif is_extraction_room or is_cleared or (is_searched and not _has_spotted_enemies()):
			border_line.default_color = GameTheme.ACCENT_SUCCESS
		elif _has_spotted_enemies():
			border_line.default_color = GameTheme.ACCENT_DANGER
		elif requires_clear:
			border_line.default_color = GameTheme.ACCENT_WARN
		else:
			border_line.default_color = Color(0.5, 0.75, 1.0, 0.75)
	queue_redraw()

func _update_visuals() -> void:
	if fill_poly:
		if not is_revealed:
			fill_poly.color = Color(0.03, 0.04, 0.06, 0.72)
		else:
			fill_poly.color = Color(room_color.r, room_color.g, room_color.b, 0.08)
	_refresh_status()

func refresh_intel() -> void:
	_refresh_status()

func has_living_enemies() -> bool:
	return enemies_present.any(func(e): return e.is_alive)

func has_registered_enemies() -> bool:
	return enemies_inside.any(func(e): return e.is_alive)

func get_spawn_position(index: int, total: int) -> Vector2:
	var spread: float = minf(room_size.x * 0.55, 48.0 * float(total))
	var step: float = spread / maxf(float(total - 1), 1.0)
	var offset_x: float = (float(index) - (float(total - 1) * 0.5)) * step
	return position + Vector2(offset_x, room_size.y * 0.18)

func contains_local_point(local_point: Vector2, padding: float = 16.0) -> bool:
	var half := room_size * 0.5 + Vector2(padding, padding)
	var offset := local_point - position
	return abs(offset.x) <= half.x and abs(offset.y) <= half.y
