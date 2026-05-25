extends Control

const TurnResolverLib := preload("res://TurnResolver.gd")
const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")
const GalaxyThreatAnalyzerLib := preload("res://GalaxyThreatAnalyzer.gd")
const BuildingDefinitionLib := preload("res://BuildingDefinition.gd")

@onready var graph_panel: Control = $MainHBox/GraphFrame/GraphPanel
@onready var graph_frame: PanelContainer = $MainHBox/GraphFrame
@onready var alloc_panel: PanelContainer = $MainHBox/AllocPanel
@onready var colony_panel: PanelContainer = $MainHBox/ColonyPanel
@onready var info_label: Label = $FooterPanel/InfoLabel
@onready var threat_strip: Button = $FooterPanel/ThreatStrip
@onready var stats_label: Label = $TopBar/StatsVBox/StatsLabel
@onready var seed_label: Label = $TopBar/StatsVBox/SeedLabel
@onready var alloc_value_label: Label = $MainHBox/AllocPanel/AllocVBox/AllocValueLabel
@onready var power_label: Label = $MainHBox/AllocPanel/AllocVBox/PowerLabel
@onready var alloc_slider: HSlider = $MainHBox/AllocPanel/AllocVBox/AllocSlider
@onready var minus_button: Button = $MainHBox/AllocPanel/AllocVBox/AllocRow/MinusButton
@onready var plus_button: Button = $MainHBox/AllocPanel/AllocVBox/AllocRow/PlusButton
@onready var colony_header: Label = $MainHBox/ColonyPanel/ColonyVBox/ColonyHeader
@onready var colony_status: Label = $MainHBox/ColonyPanel/ColonyVBox/ColonyStatus
@onready var existing_buildings_list: VBoxContainer = $MainHBox/ColonyPanel/ColonyVBox/ExistingBuildings
@onready var build_catalog_list: VBoxContainer = $MainHBox/ColonyPanel/ColonyVBox/BuildScroll/BuildCatalog
@onready var colony_feedback: Label = $MainHBox/ColonyPanel/ColonyVBox/ColonyFeedback
@onready var end_turn_button: Button = $FooterPanel/ActionRow/EndTurnButton
@onready var engage_button: Button = $FooterPanel/ActionRow/EngageButton
@onready var abort_button: Button = $FooterPanel/ActionRow/AbortButton

var _allocatable: Array[Dictionary] = []
var _focus_index: int = 0
var _graph_offset := Vector2.ZERO
var _graph_scale: float = 1.0
var _end_overlay: Label = null
var _pulse: float = 0.0
var _urgent_cycle: int = 0


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	graph_frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.04, 0.05, 0.08, 0.95)))
	alloc_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	colony_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	if not RunState.is_commander_run_active() or RunState.galaxy_state == null or RunState.army_pool == null:
		if RunState.load_commander_run():
			pass
		else:
			get_tree().change_scene_to_file("res://MainMenu.tscn")
			return
	$TopBar/BackButton.pressed.connect(_on_back_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	engage_button.pressed.connect(_on_engage_pressed)
	threat_strip.pressed.connect(_on_threat_strip_pressed)
	abort_button.pressed.connect(_on_abort_pressed)
	minus_button.pressed.connect(_on_minus_pressed)
	plus_button.pressed.connect(_on_plus_pressed)
	alloc_slider.value_changed.connect(_on_slider_changed)
	graph_panel.resized.connect(_recompute_graph_transform)
	_refresh_allocatable()
	_recompute_graph_transform()
	_refresh_ui()
	graph_panel.draw.connect(_draw_galaxy)
	graph_panel.gui_input.connect(_on_graph_input)
	graph_panel.queue_redraw()
	RunLog.info("Galaxy map — turn %d" % RunState.galaxy_state.turn_index)


func _process(delta: float) -> void:
	_pulse += delta
	if int(_pulse * 3.0) % 2 == 0:
		graph_panel.queue_redraw()


func _recompute_graph_transform() -> void:
	var galaxy = RunState.galaxy_state
	if galaxy == null or galaxy.nodes.is_empty():
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for node in galaxy.nodes:
		var p := _node_pos_raw(node)
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var span := max_p - min_p
	if span.x < 1.0:
		span.x = 1.0
	if span.y < 1.0:
		span.y = 1.0
	var panel_size := graph_panel.size
	if panel_size.x < 10.0 or panel_size.y < 10.0:
		return
	var margin := 48.0
	var scale_x := (panel_size.x - margin * 2.0) / span.x
	var scale_y := (panel_size.y - margin * 2.0) / span.y
	_graph_scale = minf(scale_x, scale_y) * 0.85
	var center := (min_p + max_p) * 0.5
	_graph_offset = panel_size * 0.5 - center * _graph_scale


func _refresh_allocatable() -> void:
	_allocatable = RunState.galaxy_state.get_allocatable_nodes()
	_focus_index = clampi(_focus_index, 0, maxi(0, _allocatable.size() - 1))


func _focused_node() -> Dictionary:
	if _allocatable.is_empty():
		return {}
	return _allocatable[_focus_index]


func _node_pos_raw(node: Dictionary) -> Vector2:
	var layer: int = int(node.get("layer", 0))
	var col: int = int(node.get("column", 0))
	return Vector2(layer * 150.0, col * 100.0)


func _node_pos(node: Dictionary) -> Vector2:
	return _node_pos_raw(node) * _graph_scale + _graph_offset


func _find_allocatable_index_for_id(node_id: String) -> int:
	for i in range(_allocatable.size()):
		if str(_allocatable[i].get("id", "")) == node_id:
			return i
	return -1


func _focus_node_id(node_id: String) -> void:
	var idx := _find_allocatable_index_for_id(node_id)
	if idx >= 0:
		_focus_index = idx
		_refresh_ui()
		graph_panel.queue_redraw()


func _refresh_ui() -> void:
	stats_label.text = (
		"Army %d / %d avail %d  |  MP %d  Bio %d  Alloy %d  |  Turn %d"
		% [
			RunState.army_pool.total_soldiers,
			RunState.army_pool.total_soldiers,
			RunState.army_pool.available_soldiers,
			RunState.commander_resources.manpower if RunState.commander_resources else 0,
			RunState.commander_resources.biomass if RunState.commander_resources else 0,
			RunState.commander_resources.alloys if RunState.commander_resources else 0,
			RunState.galaxy_state.turn_index,
		]
	)
	seed_label.text = "Seed %d  |  %s" % [RunState.run_seed, RunState.commander_id]
	threat_strip.text = GalaxyThreatAnalyzerLib.get_threat_strip_summary(
		RunState.galaxy_state, RunState.army_pool
	)
	var node := _focused_node()
	if node.is_empty():
		info_label.text = "No nodes available."
		power_label.text = ""
		end_turn_button.disabled = true
		engage_button.disabled = true
		_refresh_colony_panel({})
		return
	var node_id := str(node.get("id", ""))
	var owner := str(node.get("owner", ""))
	var terrain := str(node.get("terrain_tag", "open_field"))
	var enemy: int = int(node.get("enemy_strength", 0))
	var alloc: int = RunState.army_pool.get_allocation(node_id)
	var reinforce := GalaxyThreatAnalyzerLib.next_reinforce_preview(node)
	var power_text := GalaxyThreatAnalyzerLib.power_summary(alloc, enemy, terrain)
	var ratio := GalaxyThreatAnalyzerLib.estimate_power_ratio(alloc, enemy, terrain)
	power_label.text = "You %d  vs  Enemy %d  —  %s" % [alloc, enemy, power_text]
	if ratio >= 1.15:
		power_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
	elif ratio >= 0.85:
		power_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
	else:
		power_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	var status := GalaxyThreatAnalyzerLib.get_node_status(RunState.galaxy_state, RunState.army_pool, node_id)
	var status_name := _status_label(status)
	info_label.text = (
		"%s  |  %s  |  Terrain: %s  |  Enemy garrison: %d"
		% [node.get("display_name", node_id), status_name, terrain, enemy]
	)
	if reinforce > 0 and owner != GalaxyMapStateLib.OWNER_PLAYER:
		info_label.text += "  |  +%d enemy next turn" % reinforce
	elif reinforce > 0:
		info_label.text += "  |  neutral +%d pressure" % reinforce
	if not RunState.last_turn_summary.is_empty():
		info_label.text += "\n%s" % RunState.last_turn_summary
	var max_alloc: int = RunState.army_pool.available_soldiers + alloc
	alloc_slider.min_value = 0
	alloc_slider.max_value = maxi(max_alloc, alloc)
	alloc_slider.step = 25
	alloc_slider.value = alloc
	alloc_value_label.text = "Garrison: %d  (available %d)" % [alloc, RunState.army_pool.available_soldiers]
	var contested := _is_contested(node_id)
	engage_button.disabled = not contested or alloc <= 0
	end_turn_button.disabled = false
	if _end_overlay:
		_end_overlay.visible = false
	_refresh_colony_panel(node)


func _status_label(status: int) -> String:
	match status:
		GalaxyThreatAnalyzerLib.NodeStatus.END_TURN_BATTLE:
			return "BATTLE QUEUED"
		GalaxyThreatAnalyzerLib.NodeStatus.UNDER_DEFENDED:
			return "UNDER-DEFENDED"
		GalaxyThreatAnalyzerLib.NodeStatus.CRITICAL:
			return "CRITICAL THREAT"
		GalaxyThreatAnalyzerLib.NodeStatus.FRONTIER:
			return "FRONTIER"
		_:
			return "Stable"


func _refresh_colony_panel(node: Dictionary) -> void:
	for child in existing_buildings_list.get_children():
		child.queue_free()
	for child in build_catalog_list.get_children():
		child.queue_free()
	if node.is_empty():
		colony_header.text = "Colonies"
		colony_status.text = "Select a world on the map."
		colony_feedback.text = ""
		return
	var node_id := str(node.get("id", ""))
	var owner := str(node.get("owner", ""))
	if owner != GalaxyMapStateLib.OWNER_PLAYER:
		colony_header.text = "Colonies"
		colony_status.text = "Capture this world to construct buildings."
		colony_feedback.text = ""
		return
	var buildings: Array = node.get("buildings", [])
	var slots: int = int(node.get("building_slots", 0))
	colony_header.text = str(node.get("display_name", node_id))
	colony_status.text = "Buildings %d / %d  |  Bio %d  Alloy %d" % [
		buildings.size(),
		slots,
		RunState.commander_resources.biomass if RunState.commander_resources else 0,
		RunState.commander_resources.alloys if RunState.commander_resources else 0,
	]
	if buildings.is_empty():
		var empty_l := Label.new()
		empty_l.text = "(none built)"
		existing_buildings_list.add_child(empty_l)
	else:
		for building_id in buildings:
			var def: Dictionary = BuildingDefinitionLib.lookup(str(building_id))
			var bl := Label.new()
			bl.text = "• %s" % def.get("name", building_id)
			existing_buildings_list.add_child(bl)
	for building_id in BuildingDefinitionLib.all_buildable_ids():
		var def: Dictionary = BuildingDefinitionLib.lookup(building_id)
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (%d bio, %d alloy)" % [
			def.get("name", building_id),
			def.get("cost_biomass", 0),
			def.get("cost_alloys", 0),
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		var btn := Button.new()
		var reason := RunState.get_build_block_reason(node_id, building_id)
		btn.text = "Build" if reason.is_empty() else reason
		btn.disabled = not reason.is_empty()
		btn.pressed.connect(_on_build_pressed.bind(node_id, building_id))
		row.add_child(lbl)
		row.add_child(btn)
		build_catalog_list.add_child(row)


func _on_build_pressed(node_id: String, building_id: String) -> void:
	if RunState.try_commander_build(node_id, building_id):
		colony_feedback.text = "Built %s." % BuildingDefinitionLib.lookup(building_id).get("name", building_id)
		colony_feedback.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	else:
		colony_feedback.text = RunState.get_build_block_reason(node_id, building_id)
		colony_feedback.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_refresh_ui()
	graph_panel.queue_redraw()


func _is_contested(node_id: String) -> bool:
	for battle_node in RunState.galaxy_state.get_contested_battle_nodes(RunState.army_pool.allocated_by_node):
		if str(battle_node.get("id", "")) == node_id:
			return true
	return false


func _set_allocation(count: int) -> void:
	var node := _focused_node()
	if node.is_empty():
		return
	var node_id := str(node.get("id", ""))
	RunState.army_pool.set_allocation(node_id, count)
	RunState.save_commander_run()
	_refresh_ui()
	graph_panel.queue_redraw()


func _on_slider_changed(value: float) -> void:
	_set_allocation(int(value))


func _on_minus_pressed() -> void:
	var node := _focused_node()
	if node.is_empty():
		return
	var node_id := str(node.get("id", ""))
	var cur: int = RunState.army_pool.get_allocation(node_id)
	_set_allocation(maxi(0, cur - 50))


func _on_plus_pressed() -> void:
	var node := _focused_node()
	if node.is_empty():
		return
	var node_id := str(node.get("id", ""))
	var cur: int = RunState.army_pool.get_allocation(node_id)
	_set_allocation(cur + 50)


func _on_end_turn_pressed() -> void:
	var result: Dictionary = TurnResolverLib.resolve_turn(
		RunState.galaxy_state,
		RunState.army_pool,
		RunState.commander_resources,
		RunState.get_commander_profile(),
		false,
	)
	RunState.apply_commander_building_recruit()
	RunState.last_turn_summary = str(result.get("message", ""))
	RunState.run_credits = RunState.commander_resources.biomass
	RunState.save_commander_run()
	_refresh_allocatable()
	_recompute_graph_transform()
	_refresh_ui()
	graph_panel.queue_redraw()
	if bool(result.get("victory", false)) or bool(result.get("game_over", false)):
		_show_run_end(bool(result.get("victory", false)), str(result.get("message", "")))


func _on_engage_pressed() -> void:
	var node := _focused_node()
	if node.is_empty():
		return
	var node_id := str(node.get("id", ""))
	if RunState.army_pool.get_allocation(node_id) <= 0:
		return
	RunState.pending_battle_node_id = node_id
	RunState.pending_live_battle = true
	RunState.save_commander_run()
	get_tree().change_scene_to_file("res://BattleViewer.tscn")


func _on_threat_strip_pressed() -> void:
	var urgent := GalaxyThreatAnalyzerLib.get_urgent_node_ids(RunState.galaxy_state, RunState.army_pool)
	if urgent.is_empty():
		return
	_urgent_cycle = (_urgent_cycle + 1) % urgent.size()
	_focus_node_id(urgent[_urgent_cycle])


func _on_abort_pressed() -> void:
	RunState.end_commander_run()
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_back_pressed() -> void:
	RunState.save_commander_run()
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _show_run_end(victory: bool, message: String) -> void:
	if _end_overlay == null:
		_end_overlay = Label.new()
		_end_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_end_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_end_overlay.add_theme_font_size_override("font_size", 22)
		add_child(_end_overlay)
	_end_overlay.text = "%s\n\n%s\n\nPress Menu to exit." % ["VICTORY" if victory else "DEFEAT", message]
	_end_overlay.visible = true
	end_turn_button.disabled = true
	engage_button.disabled = true


func _on_graph_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos: Vector2 = graph_panel.get_local_mouse_position()
		var best_idx := -1
		var best_dist := 99999.0
		for i in range(_allocatable.size()):
			var pos: Vector2 = _node_pos(_allocatable[i])
			var dist: float = pos.distance_to(local_pos)
			var hit_radius: float = maxf(22.0, 28.0) * _graph_scale
			if dist < hit_radius and dist < best_dist:
				best_dist = dist
				best_idx = i
		if best_idx >= 0:
			_focus_index = best_idx
			_refresh_ui()
			graph_panel.queue_redraw()
		else:
			_try_focus_any_node_at(local_pos)


func _try_focus_any_node_at(local_pos: Vector2) -> void:
	var galaxy = RunState.galaxy_state
	if galaxy == null:
		return
	var best_id := ""
	var best_dist := 99999.0
	for node in galaxy.nodes:
		var node_id := str(node.get("id", ""))
		var pos: Vector2 = _node_pos(node)
		var dist: float = pos.distance_to(local_pos)
		var hit_radius: float = maxf(22.0, 28.0) * _graph_scale
		if dist < hit_radius and dist < best_dist:
			best_dist = dist
			best_id = node_id
	if not best_id.is_empty():
		var idx := _find_allocatable_index_for_id(best_id)
		if idx >= 0:
			_focus_index = idx
		else:
			for i in range(_allocatable.size()):
				if str(_allocatable[i].get("id", "")) == best_id:
					_focus_index = i
					break
		_refresh_ui()
		graph_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W:
				if _allocatable.size() > 0:
					_focus_index = (_focus_index - 1 + _allocatable.size()) % _allocatable.size()
					_refresh_ui()
					graph_panel.queue_redraw()
			KEY_S:
				if _allocatable.size() > 0:
					_focus_index = (_focus_index + 1) % _allocatable.size()
					_refresh_ui()
					graph_panel.queue_redraw()


func _draw_galaxy() -> void:
	var galaxy = RunState.galaxy_state
	if galaxy == null:
		return
	var focused_id := ""
	var focused := _focused_node()
	if not focused.is_empty():
		focused_id = str(focused.get("id", ""))
	var pulse_alpha: float = 0.35 + 0.25 * sin(_pulse * 4.0)
	for edge in galaxy.edges:
		var from_node: Dictionary = galaxy.get_node(str(edge.get("from_id", "")))
		var to_node: Dictionary = galaxy.get_node(str(edge.get("to_id", "")))
		if from_node.is_empty() or to_node.is_empty():
			continue
		var from_pos: Vector2 = _node_pos(from_node)
		var to_pos: Vector2 = _node_pos(to_node)
		graph_panel.draw_line(from_pos, to_pos, Color(0.4, 0.5, 0.65, 0.7), 2.0)
	for node in galaxy.nodes:
		var node_id := str(node.get("id", ""))
		var pos: Vector2 = _node_pos(node)
		var owner := str(node.get("owner", GalaxyMapStateLib.OWNER_NEUTRAL))
		var fill := Color(0.35, 0.38, 0.45, 0.95)
		match owner:
			GalaxyMapStateLib.OWNER_PLAYER:
				fill = Color(0.15, 0.45, 0.32, 0.95)
			GalaxyMapStateLib.OWNER_ENEMY:
				fill = Color(0.55, 0.18, 0.2, 0.95)
		var node_type := str(node.get("type", ""))
		var radius: float = maxf(18.0, 22.0 * _graph_scale)
		if node_type == "boss":
			radius = maxf(22.0, 28.0 * _graph_scale)
			fill = Color(0.48, 0.12, 0.62, 0.98)
		elif node_type == "hq":
			fill = Color(0.2, 0.5, 0.75, 0.98)
		var alloc: int = RunState.army_pool.get_allocation(node_id)
		if alloc > 0:
			fill = fill.lightened(0.15)
		var status := GalaxyThreatAnalyzerLib.get_node_status(RunState.galaxy_state, RunState.army_pool, node_id)
		var ring_color := Color.TRANSPARENT
		match status:
			GalaxyThreatAnalyzerLib.NodeStatus.CRITICAL:
				ring_color = Color(1.0, 0.15, 0.1, pulse_alpha)
			GalaxyThreatAnalyzerLib.NodeStatus.UNDER_DEFENDED:
				ring_color = Color(1.0, 0.45, 0.1, pulse_alpha)
			GalaxyThreatAnalyzerLib.NodeStatus.FRONTIER:
				ring_color = Color(1.0, 0.7, 0.2, pulse_alpha * 0.85)
			GalaxyThreatAnalyzerLib.NodeStatus.END_TURN_BATTLE:
				ring_color = Color(1.0, 0.92, 0.25, 0.9)
		if not ring_color.is_equal_approx(Color.TRANSPARENT):
			graph_panel.draw_arc(pos, radius + 10.0, 0.0, TAU, 28, ring_color, 3.5)
		if node.get("buildings", []).size() > 0:
			graph_panel.draw_circle(pos + Vector2(radius * 0.55, -radius * 0.55), 4.0, Color(0.55, 0.85, 1.0, 0.95))
		if node_id == focused_id:
			graph_panel.draw_circle(pos, radius + 6.0, Color(1.0, 0.92, 0.25, 0.35))
		graph_panel.draw_circle(pos, radius, fill)
		graph_panel.draw_arc(pos, radius, 0.0, TAU, 20, Color(0.9, 0.95, 1.0, 0.9), 2.0)
		var enemy: int = int(node.get("enemy_strength", 0))
		if enemy > 0 or owner != GalaxyMapStateLib.OWNER_PLAYER:
			var badge := "E%d" % enemy if enemy > 0 else "!"
			graph_panel.draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-18, radius + 12),
				badge,
				HORIZONTAL_ALIGNMENT_CENTER,
				40,
				10,
				Color(1.0, 0.55, 0.45, 0.95),
			)
		if alloc > 0:
			graph_panel.draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-20, 4),
				str(alloc),
				HORIZONTAL_ALIGNMENT_CENTER,
				40,
				11,
				Color(1.0, 1.0, 0.85, 1.0),
			)
		if node_id == focused_id:
			var label := str(node.get("display_name", ""))
			graph_panel.draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-70, -radius - 8),
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				140,
				12,
				Color(0.92, 0.95, 1.0, 0.95),
			)
