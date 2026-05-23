# TacticalMap.gd
extends Control

const ROOM_SCENE := preload("res://Room.tscn")
const SOLDIER_SCENE := preload("res://SoldierUnit.tscn")
const ENEMY_SCENE := preload("res://EnemyUnit.tscn")
const MapVisualsLib := preload("res://MapVisuals.gd")
const LineOfSightLib := preload("res://LineOfSight.gd")
const DOOR_SCENE := preload("res://Door.tscn")
const ProceduralMapGeneratorLib := preload("res://ProceduralMapGenerator.gd")

var map_data
var path_graph
var doors: Array[Node2D] = []
var selected_spawn_room: Room = null
var spawn_selection_active := false

var selected_soldiers: Array[SoldierResource] = []
var active_units: Array[SoldierUnit] = []
var rooms: Array[Room] = []
var active_enemies: Array[EnemyUnit] = []
var selected_unit_index: int = -1
var pending_order: OrderType.Type = OrderType.Type.CLEAR
var game_active := false
var is_paused := false
var mission_complete := false
var extraction_hint_shown := false
var _last_order_frame: int = -1
var _last_order_room: Room = null

@onready var start_button: Button = $HUD/VBox/StartButton
@onready var back_button: Button = $HUD/VBox/BackButton
@onready var combat_log: RichTextLabel = $LeftPanel/VBox/CombatLog
@onready var play_area: Control = $PlayArea
@onready var sub_viewport_container: SubViewportContainer = $PlayArea/SubViewportContainer
@onready var sub_viewport: SubViewport = $PlayArea/SubViewportContainer/SubViewport
@onready var world: Node2D = $PlayArea/SubViewportContainer/SubViewport/World
@onready var map_camera: Camera2D = $PlayArea/SubViewportContainer/SubViewport/World/MapCamera
@onready var pause_label: Label = $HUD/VBox/PauseLabel
@onready var mission_result_label: Label = $HUD/VBox/MissionResultLabel
@onready var unit_name_label: Label = $HUD/VBox/UnitPanel/UnitName
@onready var unit_class_label: Label = $HUD/VBox/UnitPanel/UnitClass
@onready var unit_health_label: Label = $HUD/VBox/UnitPanel/UnitHealth
@onready var unit_order_label: Label = $HUD/VBox/UnitPanel/UnitOrder
@onready var objective_label: Label = $HUD/VBox/ObjectiveLabel
@onready var order_move_btn: Button = $HUD/VBox/OrderPanel/MoveButton
@onready var order_clear_btn: Button = $HUD/VBox/OrderPanel/ClearButton
@onready var order_search_btn: Button = $HUD/VBox/OrderPanel/SearchDestroyButton
@onready var order_defend_btn: Button = $HUD/VBox/OrderPanel/DefendButton
@onready var order_extract_btn: Button = $HUD/VBox/OrderPanel/ExtractButton
@onready var ability_button: Button = $HUD/VBox/AbilityButton

func _ready() -> void:
	add_to_group("tactical_map")
	GameTheme.apply_to_control(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	$QuitButton.pressed.connect(_on_quit_pressed)
	order_move_btn.pressed.connect(_set_pending_order.bind(OrderType.Type.MOVE))
	order_clear_btn.pressed.connect(_set_pending_order.bind(OrderType.Type.CLEAR))
	order_search_btn.pressed.connect(_on_search_destroy_pressed)
	order_defend_btn.pressed.connect(_set_pending_order.bind(OrderType.Type.DEFEND))
	order_extract_btn.pressed.connect(_set_pending_order.bind(OrderType.Type.EXTRACT))
	ability_button.pressed.connect(_on_ability_pressed)
	var custom_seed := -1
	var env_seed := OS.get_environment("EOY_MAP_SEED")
	if env_seed.is_valid_int():
		custom_seed = env_seed.to_int()
	map_data = ProceduralMapGeneratorLib.generate(custom_seed)
	path_graph = map_data.path_graph
	_build_map_visuals()
	_build_doors()
	_build_rooms()
	_begin_spawn_selection()
	_set_pending_order(OrderType.Type.CLEAR)
	await _layout_play_area()
	_setup_map_input()
	_update_hud()
	var left_panel: PanelContainer = $LeftPanel
	var hud_panel: PanelContainer = $HUD
	left_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	hud_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	log_message("Procedural facility generated (seed %d)." % map_data.map_seed, "cyan")
	log_message("Select a secure deploy room, then press BEGIN MISSION.", GameTheme.ACCENT.to_html())
	_load_squad_from_meta()

func _layout_play_area() -> void:
	await get_tree().process_frame
	var left_rect: Rect2 = $LeftPanel.get_global_rect()
	var hud_rect: Rect2 = $HUD.get_global_rect()
	var play_pos := Vector2(left_rect.end.x, left_rect.position.y)
	var play_size := Vector2(
		hud_rect.position.x - left_rect.end.x,
		left_rect.end.y - left_rect.position.y
	)
	play_area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	play_area.global_position = play_pos
	play_area.size = play_size
	sub_viewport_container.stretch = false
	sub_viewport.size = Vector2i(maxi(int(play_size.x), 1), maxi(int(play_size.y), 1))
	world.position = play_size * 0.5
	var scale_factor: float = min(
		play_size.x / map_data.map_size.x,
		play_size.y / map_data.map_size.y
	) * 0.88
	map_camera.zoom = Vector2(scale_factor, scale_factor)
	map_camera.position = Vector2.ZERO
	map_camera.enabled = true
	map_camera.make_current()

func _build_map_visuals() -> void:
	var layer := Node2D.new()
	layer.name = "MapVisuals"
	layer.z_index = -10
	world.add_child(layer)
	world.move_child(layer, 0)

	var half: Vector2 = map_data.map_size * 0.5
	var deck_base: Polygon2D = MapVisualsLib.make_rect_polygon(
		Rect2(Vector2(-half.x, -half.y), map_data.map_size),
		Color(0.07, 0.08, 0.11, 1.0)
	)
	deck_base.name = "DeckBase"
	deck_base.z_index = -5
	layer.add_child(deck_base)

	var corridors := Node2D.new()
	corridors.name = "Corridors"
	corridors.z_index = -2
	layer.add_child(corridors)
	for rect: Rect2 in map_data.get_corridor_rects():
		_add_corridor_visual(corridors, rect)

	var hull_layer := Node2D.new()
	hull_layer.name = "HullLayer"
	hull_layer.z_index = 5
	world.add_child(hull_layer)

	var hull := Line2D.new()
	hull.name = "HullOutline"
	hull.points = map_data.get_hull_outline()
	hull.closed = true
	hull.width = 8.0
	hull.default_color = Color(0.65, 0.72, 0.85, 1.0)
	hull_layer.add_child(hull)

	var inner_hull := Line2D.new()
	inner_hull.name = "HullOutlineInner"
	inner_hull.points = map_data.get_hull_outline()
	inner_hull.closed = true
	inner_hull.width = 2.5
	inner_hull.default_color = Color(0.35, 0.75, 1.0, 0.95)
	hull_layer.add_child(inner_hull)

func _add_corridor_visual(parent: Node2D, rect: Rect2) -> void:
	var floor_poly: Polygon2D = MapVisualsLib.make_rect_polygon(rect, Color(0.11, 0.13, 0.17, 1.0))
	floor_poly.z_index = 0
	parent.add_child(floor_poly)

	var stripe_rect := rect
	if rect.size.x >= rect.size.y:
		stripe_rect = Rect2(
			rect.position + Vector2(4.0, rect.size.y * 0.38),
			Vector2(maxf(rect.size.x - 8.0, 8.0), maxf(rect.size.y * 0.24, 6.0))
		)
	else:
		stripe_rect = Rect2(
			rect.position + Vector2(rect.size.x * 0.38, 4.0),
			Vector2(maxf(rect.size.x * 0.24, 6.0), maxf(rect.size.y - 8.0, 8.0))
		)
	var stripe: Polygon2D = MapVisualsLib.make_rect_polygon(stripe_rect, Color(0.18, 0.42, 0.82, 0.85))
	stripe.z_index = 1
	parent.add_child(stripe)

	var outline: Line2D = MapVisualsLib.make_rect_outline(rect, Color(0.35, 0.42, 0.52, 0.85), 1.5)
	outline.z_index = 2
	parent.add_child(outline)

func _build_doors() -> void:
	for data: Dictionary in path_graph.get_door_positions():
		var door: Node2D = DOOR_SCENE.instantiate()
		var room_pos: Vector2 = path_graph.nodes[data.room_node]
		var spine_pos: Vector2 = path_graph.nodes[data.spine_node]
		data["rotation"] = (room_pos - spine_pos).angle()
		door.setup(data)
		door.spine_node_id = data.get("spine_node", "")
		door.add_to_group("doors")
		world.add_child(door)
		doors.append(door)

func _setup_map_input() -> void:
	sub_viewport_container.gui_input.connect(_on_play_area_gui_input)

func _on_play_area_gui_input(event: InputEvent) -> void:
	if mission_complete:
		return
	if not game_active and not spawn_selection_active:
		return
	if _is_pointer_over_ui(get_viewport().get_mouse_position()):
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	var world_pos := _container_mouse_to_world()
	if event.button_index == MOUSE_BUTTON_RIGHT:
		handle_map_right_click(world_pos)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		handle_map_left_click(world_pos)

func _container_mouse_to_world() -> Vector2:
	var local := sub_viewport_container.get_local_mouse_position()
	var sv_size := Vector2(sub_viewport.size)
	var cont_size := sub_viewport_container.size
	var sv_pos := Vector2(
		local.x * sv_size.x / maxf(cont_size.x, 1.0),
		local.y * sv_size.y / maxf(cont_size.y, 1.0)
	)
	var canvas_pos: Vector2 = map_camera.get_canvas_transform().affine_inverse() * sv_pos
	return world.to_local(canvas_pos)

func _load_squad_from_meta() -> void:
	if not get_tree().has_meta("selected_soldiers"):
		return
	var squad_meta = get_tree().get_meta("selected_soldiers")
	selected_soldiers.clear()
	if squad_meta is Array:
		for resource in squad_meta:
			if resource is SoldierResource:
				selected_soldiers.append(resource)
	if selected_soldiers.is_empty():
		return
	log_message("Squad loaded: %d marines ready." % selected_soldiers.size(), "white")

func handle_map_right_click(world_pos: Vector2) -> void:
	if spawn_selection_active:
		var spawn_room := _get_room_at_position(world_pos)
		if spawn_room and spawn_room.is_spawn_eligible:
			_select_spawn_room(spawn_room)
		elif spawn_room:
			log_message("%s is not secure for deployment." % spawn_room.room_name, GameTheme.ACCENT_WARN.to_html())
		return
	if not _selected_unit() and active_units.size() > 0:
		_select_unit(0)
	if not _selected_unit():
		log_message("Select an active marine first.", GameTheme.ACCENT_WARN.to_html())
		return
	var room := _get_room_at_position(world_pos)
	if room:
		_issue_order_to_selected(room)
	else:
		log_message("Click inside a room outline to issue orders.", GameTheme.TEXT_MUTED.to_html())

func handle_map_left_click(world_pos: Vector2) -> void:
	if spawn_selection_active:
		var spawn_room := _get_room_at_position(world_pos)
		if spawn_room and spawn_room.is_spawn_eligible:
			_select_spawn_room(spawn_room)
		elif spawn_room:
			log_message("%s is not secure for deployment." % spawn_room.room_name, GameTheme.ACCENT_WARN.to_html())
		else:
			log_message("Click a green-highlighted secure room to deploy.", GameTheme.TEXT_MUTED.to_html())
		return
	var closest_index := -1
	var closest_dist := 36.0
	for i in range(active_units.size()):
		var unit := active_units[i]
		if unit.is_alive:
			var dist := unit.position.distance_to(world_pos)
			if dist <= closest_dist:
				closest_dist = dist
				closest_index = i
	if closest_index >= 0:
		_select_unit(closest_index)

func _build_rooms() -> void:
	for data in map_data.get_room_dicts():
		var room: Room = ROOM_SCENE.instantiate()
		room.room_name = data.name
		room.position = data.pos
		room.map_room_id = data.id
		room.is_spawn_eligible = data.get("spawn_eligible", false)
		room.is_extraction_room = data.get("extract", false)
		room.requires_clear = data.get("clear", false)
		room.planned_enemy_count = data.get("enemies", 0)
		room.is_revealed = false
		room.deploy_selection_mode = false
		room.configure(data.size, data.color)
		room.cleared.connect(_on_room_cleared)
		room.order_requested.connect(_on_room_order_requested)
		world.add_child(room)
		rooms.append(room)

func _begin_spawn_selection() -> void:
	spawn_selection_active = true
	selected_spawn_room = null
	start_button.disabled = true
	start_button.text = "SELECT DEPLOY ROOM"
	for room in rooms:
		room.is_spawn_room = false
		room.deploy_selection_mode = true
		room.is_revealed = false
		room._update_visuals()
		room.set_spawn_selection_highlight(true, room.is_spawn_eligible, false)

func _select_spawn_room(room: Room) -> void:
	if not spawn_selection_active or not room.is_spawn_eligible:
		return
	selected_spawn_room = room
	for candidate in rooms:
		candidate.is_spawn_room = candidate == room
		candidate.set_spawn_selection_highlight(true, candidate.is_spawn_eligible, candidate == room)
	start_button.disabled = false
	start_button.text = "BEGIN MISSION"
	log_message("Deploy site: %s (secure, no hostiles)." % room.room_name, GameTheme.ACCENT_SUCCESS.to_html())

func _on_start_pressed() -> void:
	if game_active or mission_complete:
		return
	if selected_soldiers.is_empty():
		log_message("No squad deployed. Abort and re-select marines.", GameTheme.ACCENT_WARN.to_html())
		return
	if spawn_selection_active and not selected_spawn_room:
		log_message("Select a secure deploy room before beginning.", GameTheme.ACCENT_WARN.to_html())
		return
	spawn_selection_active = false
	game_active = true
	start_button.visible = false
	is_paused = true
	log_message("=== MISSION STARTED ===", "yellow")
	log_message("PAUSED — select marines, issue orders, then SPACE to execute.", "yellow")
	log_message("Fog of war active — hostiles must be spotted before engagement.", GameTheme.TEXT_MUTED.to_html())
	for room in rooms:
		room.deploy_selection_mode = false
		room.set_spawn_selection_highlight(false, false, false)
	_spawn_squad()
	_spawn_enemies()
	_init_fog_of_war()
	_update_objectives()
	_update_hud()

func _spawn_squad() -> void:
	var spawn_room := selected_spawn_room
	if not spawn_room:
		spawn_room = _get_spawn_room()
	if not spawn_room:
		return
	for i in range(selected_soldiers.size()):
		var resource := selected_soldiers[i]
		var unit: SoldierUnit = SOLDIER_SCENE.instantiate()
		unit.setup_from_resource(resource)
		unit.position = spawn_room.get_spawn_position(i, selected_soldiers.size())
		unit.clicked.connect(_on_unit_clicked)
		unit.died.connect(_on_unit_died)
		unit.order_changed.connect(_on_unit_order_changed)
		unit.combat_hit.connect(_on_combat_hit)
		unit.health_changed.connect(_on_unit_health_changed)
		world.add_child(unit)
		active_units.append(unit)
		log_message("Deployed: %s (%s)" % [resource.soldier_name, GameTheme.class_name_text(resource.marine_class)], "white")
	if active_units.size() > 0:
		_select_unit(0)

func _spawn_enemies() -> void:
	var enemy_id := 1
	for room in rooms:
		var count: int = room.planned_enemy_count
		if count <= 0:
			continue
		room.mark_contested()
		for i in range(count):
			var enemy_res := Enemy.new()
			enemy_res.enemy_name = "H-%d" % enemy_id
			enemy_res.health = 45 + enemy_id * 5
			enemy_res.damage = 10 + enemy_id
			enemy_res.alive = true
			var enemy: EnemyUnit = ENEMY_SCENE.instantiate()
			enemy.setup_from_resource(enemy_res, room)
			enemy.died.connect(_on_enemy_died)
			enemy.combat_hit.connect(_on_combat_hit)
			var offset := Vector2((i - (count - 1) * 0.5) * 36.0, room.room_size.y * 0.12)
			enemy.position = room.position + offset
			world.add_child(enemy)
			room.register_enemy(enemy)
			active_enemies.append(enemy)
			enemy_id += 1
	log_message("Hostile contacts detected in facility.", GameTheme.ACCENT_DANGER.to_html())
	log_message("Sensor feed limited — visual contact required.", GameTheme.TEXT_MUTED.to_html())

func _init_fog_of_war() -> void:
	for room in rooms:
		room.is_revealed = room == selected_spawn_room
		room.is_searched = false
		room._update_visuals()
	for enemy in active_enemies:
		enemy.set_visible_to_player(false)

func _process(_delta: float) -> void:
	if not game_active or mission_complete:
		return
	_update_fog_of_war()
	if not is_paused:
		_check_mission_status()

func _get_spawn_room() -> Room:
	for room in rooms:
		if room.is_spawn_room:
			return room
	return rooms[0] if rooms.size() > 0 else null

func _get_extraction_room() -> Room:
	for room in rooms:
		if room.is_extraction_room:
			return room
	return null

func _get_required_rooms() -> Array[Room]:
	return rooms.filter(func(r): return r.requires_clear)

func _on_room_order_requested(room: Room) -> void:
	if spawn_selection_active:
		if room.is_spawn_eligible:
			_select_spawn_room(room)
		else:
			log_message("%s is not secure for deployment." % room.room_name, GameTheme.ACCENT_WARN.to_html())
		return
	if not game_active or mission_complete:
		return
	if _is_pointer_over_ui(get_viewport().get_mouse_position()):
		return
	if not _selected_unit() and active_units.size() > 0:
		_select_unit(0)
	_issue_order_to_selected(room)

func _on_room_cleared(room: Room) -> void:
	log_message("%s secured." % room.room_name, GameTheme.ACCENT_SUCCESS.to_html())
	_update_objectives()
	if not is_paused:
		_check_mission_status()

func _on_combat_hit(attacker_name: String, target_name: String, damage: int, killed: bool) -> void:
	if killed:
		log_message("%s eliminated %s." % [attacker_name, target_name], GameTheme.ACCENT_SUCCESS.to_html())
	else:
		log_message("%s hits %s for %d." % [attacker_name, target_name, damage], "white")
	_update_hud()

func _on_unit_health_changed(_unit: SoldierUnit) -> void:
	_update_hud()

func _on_enemy_died(enemy: EnemyUnit) -> void:
	active_enemies.erase(enemy)
	if enemy.home_room:
		enemy.home_room.check_cleared_status()
	else:
		for room in rooms:
			room.check_cleared_status()
	_update_objectives()

func _on_unit_died(unit: SoldierUnit) -> void:
	log_message("%s is down." % unit.soldier_name, GameTheme.ACCENT_DANGER.to_html())
	var was_selected := unit == _selected_unit()
	var old_index := active_units.find(unit)
	active_units.erase(unit)
	if was_selected:
		if active_units.is_empty():
			selected_unit_index = -1
		else:
			_select_unit(clampi(old_index, 0, active_units.size() - 1))
	else:
		if selected_unit_index > old_index and selected_unit_index >= 0:
			selected_unit_index -= 1
		_update_hud()
	if _alive_units().is_empty() and game_active:
		_end_mission(false)

func _on_unit_order_changed(unit: SoldierUnit, _order: OrderType.Type) -> void:
	if unit == _selected_unit():
		_update_hud()

func _alive_units() -> Array[SoldierUnit]:
	return active_units.filter(func(u): return u.is_alive)

func _check_mission_status() -> void:
	if not game_active or mission_complete or is_paused:
		return
	var required := _get_required_rooms()
	var all_cleared := required.all(func(r): return r.is_cleared)
	var extraction := _get_extraction_room()
	if not all_cleared or not extraction:
		return
	for unit in _alive_units():
		if unit.order_room == extraction and unit.awaiting_at_destination:
			_end_mission(true)
			return
	if all_cleared and not extraction_hint_shown:
		extraction_hint_shown = true
		log_message("All objectives secured. Order squad to COMMAND BRIDGE.", GameTheme.ACCENT_SUCCESS.to_html())

func _end_mission(victory: bool) -> void:
	mission_complete = true
	game_active = false
	is_paused = false
	for unit in active_units:
		if unit.is_alive:
			unit.cancel_order()
	mission_result_label.visible = true
	if victory:
		mission_result_label.text = "MISSION COMPLETE"
		mission_result_label.modulate = GameTheme.ACCENT_SUCCESS
		log_message("=== MISSION COMPLETE ===", "gold")
		log_message("Squad extracted. Facility purged.", GameTheme.ACCENT_SUCCESS.to_html())
	else:
		mission_result_label.text = "MISSION FAILED"
		mission_result_label.modulate = GameTheme.ACCENT_DANGER
		log_message("=== MISSION FAILED ===", GameTheme.ACCENT_DANGER.to_html())
		log_message("Squad eliminated.", GameTheme.ACCENT_DANGER.to_html())
	_update_hud()

func log_message(message: String, color: String = "white") -> void:
	if combat_log:
		combat_log.append_text("[color=%s]%s[/color]\n" % [color, message])

func _set_pending_order(order: OrderType.Type) -> void:
	pending_order = order
	order_move_btn.button_pressed = order == OrderType.Type.MOVE
	order_clear_btn.button_pressed = order == OrderType.Type.CLEAR
	order_search_btn.button_pressed = order == OrderType.Type.SEARCH_DESTROY
	order_defend_btn.button_pressed = order == OrderType.Type.DEFEND
	order_extract_btn.button_pressed = order == OrderType.Type.EXTRACT
	log_message("Order mode: %s" % OrderType.get_label(order), GameTheme.ACCENT.to_html())

func _on_search_destroy_pressed() -> void:
	_set_pending_order(OrderType.Type.SEARCH_DESTROY)
	if not game_active or mission_complete:
		return
	var unit := _selected_unit()
	if not unit:
		log_message("Select a marine, then press S for autonomous Search & Destroy.", GameTheme.ACCENT_WARN.to_html())
		return
	_activate_search_destroy(unit, null)

func _activate_search_destroy(unit: SoldierUnit, start_room: Room = null) -> void:
	if not _any_living_enemies():
		log_message("No hostile contacts remain on deck.", GameTheme.TEXT_MUTED.to_html())
		return
	var start_pos: Vector2 = start_room.position if start_room else unit.position
	unit.issue_order(OrderType.Type.SEARCH_DESTROY, start_pos, start_room)
	if start_room:
		log_message("%s → Search & Destroy: autonomous purge from %s." % [unit.soldier_name, start_room.room_name], "white")
	else:
		log_message("%s → Search & Destroy: purging deck until all hostiles eliminated." % unit.soldier_name, "white")

func _any_living_enemies() -> bool:
	for enemy in active_enemies:
		if enemy.is_alive:
			return true
	return false

func _select_unit(index: int) -> void:
	if index < 0 or index >= active_units.size():
		selected_unit_index = -1
		for i in range(active_units.size()):
			active_units[i].set_selected(false)
		if game_active and index >= 0 and index < 4:
			log_message("No operator in slot %d." % (index + 1), GameTheme.TEXT_MUTED.to_html())
		_update_hud()
		return
	selected_unit_index = index
	for i in range(active_units.size()):
		active_units[i].set_selected(i == selected_unit_index)
	_update_hud()

func _selected_unit() -> SoldierUnit:
	if selected_unit_index >= 0 and selected_unit_index < active_units.size():
		var unit := active_units[selected_unit_index]
		if unit.is_alive:
			return unit
	return null

func _on_unit_clicked(unit: SoldierUnit) -> void:
	var index := active_units.find(unit)
	if index >= 0:
		_select_unit(index)

func _issue_order_to_selected(room: Room) -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_order_frame and _last_order_room == room:
		return
	_last_order_frame = frame
	_last_order_room = room
	var unit := _selected_unit()
	if not unit:
		log_message("Select an active marine first.", GameTheme.ACCENT_WARN.to_html())
		return
	if not game_active:
		log_message("Start the mission before issuing orders.", GameTheme.ACCENT_WARN.to_html())
		return
	var order := pending_order
	if room.is_extraction_room:
		order = OrderType.Type.EXTRACT
	elif order == OrderType.Type.EXTRACT and not room.is_extraction_room:
		log_message("Extract order only valid at the Command Bridge.", GameTheme.ACCENT_WARN.to_html())
		return
	if order == OrderType.Type.CLEAR and not room.requires_clear and not room.has_living_enemies():
		log_message("No hostiles reported in %s." % room.room_name, GameTheme.TEXT_MUTED.to_html())
		return
	if order == OrderType.Type.SEARCH_DESTROY:
		_activate_search_destroy(unit, room)
		_update_hud()
		return
	unit.issue_order(order, room.position, room)

func _on_ability_pressed() -> void:
	if not game_active or mission_complete:
		return
	var unit := _selected_unit()
	if not unit or not unit.is_alive:
		return
	if unit.use_ability(_alive_units()):
		log_message("%s used %s." % [unit.soldier_name, unit.ability_name], GameTheme.ACCENT.to_html())
		_update_hud()
	else:
		log_message("%s ability not ready or no valid target." % unit.soldier_name, GameTheme.TEXT_MUTED.to_html())

func _update_objectives() -> void:
	var required := _get_required_rooms()
	var cleared_count := required.filter(func(r): return r.is_cleared).size()
	objective_label.text = "Objectives: %d / %d cleared | Seed: %d" % [cleared_count, required.size(), map_data.map_seed]

func _update_hud() -> void:
	pause_label.visible = is_paused and game_active
	pause_label.text = "⏸ PAUSED — SPACE to resume"
	var unit := _selected_unit()
	if unit and unit.is_alive:
		unit_name_label.text = unit.soldier_name
		unit_class_label.text = GameTheme.class_name_text(unit.marine_class)
		unit_health_label.text = "HP %d / %d" % [unit.current_health, unit.max_health]
		unit_order_label.text = "Order: %s" % OrderType.get_label(unit.current_order)
		ability_button.text = "Ability: %s" % unit.ability_name
		ability_button.disabled = unit.ability_timer > 0.0 or not game_active
	else:
		unit_name_label.text = "No unit selected"
		unit_class_label.text = "—"
		unit_health_label.text = "—"
		unit_order_label.text = "—"
		ability_button.disabled = true

func _on_back_pressed() -> void:
	if get_tree().has_meta("selected_soldiers"):
		get_tree().remove_meta("selected_soldiers")
	get_tree().change_scene_to_file("res://SquadSelection.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if spawn_selection_active or not game_active or mission_complete:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_unit(0)
			KEY_2:
				_select_unit(1)
			KEY_3:
				_select_unit(2)
			KEY_4:
				_select_unit(3)
			KEY_M:
				_set_pending_order(OrderType.Type.MOVE)
			KEY_C:
				_set_pending_order(OrderType.Type.CLEAR)
			KEY_S:
				_on_search_destroy_pressed()
			KEY_D:
				_set_pending_order(OrderType.Type.DEFEND)
			KEY_E:
				_set_pending_order(OrderType.Type.EXTRACT)
			KEY_R:
				_on_ability_pressed()
		get_viewport().set_input_as_handled()

func _is_pointer_over_ui(screen_pos: Vector2) -> bool:
	return (
		$LeftPanel.get_global_rect().has_point(screen_pos)
		or $HUD.get_global_rect().has_point(screen_pos)
		or $QuitButton.get_global_rect().has_point(screen_pos)
		or $Title.get_global_rect().has_point(screen_pos)
	)

func toggle_pause() -> void:
	if not game_active or mission_complete:
		return
	is_paused = !is_paused
	if is_paused:
		log_message("=== PAUSED ===", "yellow")
	else:
		log_message("=== RESUMED — squad executing orders ===", GameTheme.ACCENT_SUCCESS.to_html())
		if not mission_complete:
			_check_mission_status()
	_update_hud()

func _get_room_at_position(local_pos: Vector2) -> Room:
	var best_room: Room = null
	var best_depth := -INF
	for room in rooms:
		if room.contains_local_point(local_pos):
			if room.z_index >= best_depth:
				best_depth = room.z_index
				best_room = room
	return best_room

func _update_fog_of_war() -> void:
	var door_nodes: Array = doors if not doors.is_empty() else get_tree().get_nodes_in_group("doors")
	for soldier in _alive_units():
		for room in rooms:
			if room.contains_local_point(soldier.position, 0.0):
				room.reveal()
			elif LineOfSightLib.can_reveal_room(soldier.position, room, rooms, door_nodes):
				room.reveal()
	for enemy in active_enemies:
		if not enemy.is_alive:
			continue
		var seen := false
		for soldier in _alive_units():
			if LineOfSightLib.has_line_of_sight(soldier.position, enemy.position, rooms, door_nodes):
				seen = true
				break
		enemy.set_visible_to_player(seen)
	for room in rooms:
		room.refresh_intel()
