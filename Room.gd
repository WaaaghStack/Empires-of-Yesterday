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
var sector_tag: String = "central"
var planned_enemy_count: int = 0
var deploy_selection_mode: bool = false
var soldiers_inside: Array[SoldierUnit] = []
var enemies_inside: Array[EnemyUnit] = []
var enemies_present: Array[EnemyUnit] = []
var is_cleared: bool = false
var is_revealed: bool = false
var is_searched: bool = false
var last_hostile_contact: bool = false
var order_target_highlight: bool = false
var intel_scan_label: String = ""
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


func get_rect() -> Rect2:
	var half := room_size * 0.5
	return Rect2(position - half, room_size)


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
		if last_hostile_contact:
			draw_string(ThemeDB.fallback_font, title_pos, "???", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.55, 0.48, 0.42, 0.95))
			draw_string(ThemeDB.fallback_font, status_pos, "AUDIO CONTACT", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, GameTheme.ACCENT_WARN)
			_draw_last_contact_marker(half)
		else:
			draw_string(ThemeDB.fallback_font, title_pos, "???", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.45, 0.48, 0.55, 0.9))
			draw_string(ThemeDB.fallback_font, status_pos, "UNKNOWN", HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, Color(0.35, 0.38, 0.45, 0.9))
		return
	draw_string(ThemeDB.fallback_font, title_pos, room_name, HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 14, Color(0.95, 0.97, 1.0, 1.0))
	var status_color := _status_color()
	draw_string(ThemeDB.fallback_font, status_pos, _status_text, HORIZONTAL_ALIGNMENT_LEFT, int(room_size.x - 16.0), 11, status_color)
	if last_hostile_contact and not _has_spotted_enemies():
		_draw_last_contact_marker(half)

func _draw_last_contact_marker(half: Vector2) -> void:
	var marker_pos := Vector2(half.x - 18.0, -half.y + 18.0)
	var size := 7.0
	var points := PackedVector2Array([
		marker_pos + Vector2(0.0, -size),
		marker_pos + Vector2(size, size),
		marker_pos + Vector2(-size, size),
	])
	draw_colored_polygon(points, Color(0.95, 0.42, 0.28, 0.92))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(1.0, 0.72, 0.45, 0.95), 1.5)

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


func set_intel_scan(label: String) -> void:
	intel_scan_label = label
	_refresh_status()

func _on_room_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not deploy_selection_mode and not is_revealed:
		return
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
		if not _has_spotted_enemies():
			clear_hostile_contact()
		_refresh_status()
		cleared.emit(self)

func mark_contested() -> void:
	is_cleared = false
	_refresh_status()

func _refresh_status() -> void:
	if not is_revealed:
		_status_text = "UNKNOWN"
	elif not intel_scan_label.is_empty():
		_status_text = intel_scan_label
	elif is_extraction_room:
		_status_text = "EXTRACT"
	elif is_cleared:
		_status_text = "SECURED"
	elif _has_spotted_enemies():
		_status_text = "CONTACT"
	elif last_hostile_contact:
		_status_text = "LAST CONTACT"
	elif is_searched:
		_status_text = "CLEAR"
	elif get_meta("loot_branch", false):
		_status_text = "LOOT WING"
	elif get_meta("vip_room", false) and not is_cleared:
		_status_text = "VIP"
	elif requires_clear and get_meta("intel_terminal", false) and int(get_meta("terminals_remaining", 0)) > 0:
		_status_text = "INTEL TERM"
	elif requires_clear:
		_status_text = "OBJECTIVE"
	else:
		_status_text = "UNSCANNED"
	if border_line:
		if order_target_highlight and is_revealed:
			border_line.default_color = Color(0.35, 0.88, 1.0, 1.0)
			border_line.width = 3.0
		elif not is_revealed:
			border_line.default_color = Color(0.25, 0.28, 0.34, 0.45)
			border_line.width = 2.0
		elif is_extraction_room or is_cleared or (is_searched and not _has_spotted_enemies()):
			border_line.default_color = GameTheme.ACCENT_SUCCESS
			border_line.width = 2.0
		elif _has_spotted_enemies():
			border_line.default_color = GameTheme.ACCENT_DANGER
			border_line.width = 2.0
		elif last_hostile_contact:
			border_line.default_color = Color(0.95, 0.45, 0.32, 0.95)
			border_line.width = 2.0
		elif requires_clear:
			border_line.default_color = GameTheme.ACCENT_WARN
			border_line.width = 2.0
		else:
			border_line.default_color = Color(0.5, 0.75, 1.0, 0.75)
			border_line.width = 2.0
	queue_redraw()

func _update_visuals() -> void:
	if fill_poly:
		if not is_revealed:
			fill_poly.color = Color(0.03, 0.04, 0.06, 0.72)
		elif order_target_highlight:
			fill_poly.color = Color(0.35, 0.82, 1.0, 0.14)
		else:
			fill_poly.color = Color(room_color.r, room_color.g, room_color.b, 0.08)
	_refresh_status()

func mark_hostile_contact(contact_label: String = "") -> void:
	last_hostile_contact = true
	if contact_label != "":
		set_meta("last_contact_label", contact_label)
	_refresh_status()
	queue_redraw()

func clear_hostile_contact() -> void:
	if not last_hostile_contact:
		return
	last_hostile_contact = false
	if has_meta("last_contact_label"):
		remove_meta("last_contact_label")
	_refresh_status()
	queue_redraw()

func set_order_target_highlight(active: bool) -> void:
	if order_target_highlight == active:
		return
	order_target_highlight = active
	_update_visuals()

func get_last_contact_label() -> String:
	return str(get_meta("last_contact_label", ""))

func refresh_intel() -> void:
	if last_hostile_contact and is_cleared and not has_registered_enemies():
		clear_hostile_contact()
	else:
		_refresh_status()

func has_living_enemies() -> bool:
	return enemies_present.any(func(e): return e.is_alive)

func has_registered_enemies() -> bool:
	return enemies_inside.any(func(e): return e.is_alive)

func get_spawn_position(index: int, total: int) -> Vector2:
	return get_formation_position(index, total, 0)


func get_formation_position(index: int, total: int, squad_slot: int = 0) -> Vector2:
	var member_count: int = maxi(total, 1)
	var margin: float = 14.0
	var usable := room_size - Vector2(margin * 2.0, margin * 2.0)
	var min_spacing: float = 18.0
	var cols: int = mini(4, member_count)
	if member_count >= 4 and (usable.x < 102.0 or usable.y < 82.0):
		cols = 2
	while cols > 1 and float(cols - 1) * min_spacing > usable.x:
		cols -= 1
	var row: int = int(float(index) / float(cols))
	var col: int = index % cols
	var rows: int = int(ceil(float(member_count) / float(cols)))
	var spacing_x: float = 28.0
	var spacing_y: float = 28.0
	if cols > 1:
		spacing_x = minf(28.0, usable.x / float(cols - 1))
	if rows > 1:
		spacing_y = minf(28.0, usable.y / float(rows - 1))
	var grid_w: float = float(cols - 1) * spacing_x
	var grid_h: float = float(rows - 1) * spacing_y
	var start_x: float = -grid_w * 0.5
	var start_y: float = -grid_h * 0.5 + room_size.y * 0.08
	var offset := Vector2(start_x + float(col) * spacing_x, start_y + float(row) * spacing_y)
	var squad_shift: float = clampf(float(squad_slot) * spacing_x * 0.15, -spacing_x * 0.35, spacing_x * 0.35)
	offset.x += squad_shift
	return _clamp_point_to_room(position + offset, margin)


func _clamp_point_to_room(world_pos: Vector2, margin: float) -> Vector2:
	var inset: float = 4.0
	var half := room_size * 0.5 - Vector2(margin, margin) - Vector2(inset, inset)
	var local := world_pos - position
	local.x = clampf(local.x, -half.x, half.x)
	local.y = clampf(local.y, -half.y, half.y)
	return position + local


func formation_fits(member_count: int, margin: float = 14.0) -> bool:
	var inset: float = 4.0
	var half := (room_size - Vector2(margin + inset, margin + inset) * 2.0) * 0.5
	for i in range(member_count):
		var pos := get_formation_position(i, member_count, 0)
		var local := pos - position
		if absf(local.x) > half.x + 0.5 or absf(local.y) > half.y + 0.5:
			return false
	return true

func contains_local_point(local_point: Vector2, padding: float = 16.0) -> bool:
	var half := room_size * 0.5 + Vector2(padding, padding)
	var offset := local_point - position
	return abs(offset.x) <= half.x and abs(offset.y) <= half.y
