extends Control

const SoldierCardScene := preload("res://SoldierCard.tscn")

@onready var graph_panel: Control = $MainHBox/GraphFrame/GraphPanel
@onready var roster_list: VBoxContainer = $MainHBox/RosterPanel/RosterVBox/RosterScroll/RosterList
@onready var graph_frame: PanelContainer = $MainHBox/GraphFrame
@onready var roster_panel: PanelContainer = $MainHBox/RosterPanel
@onready var roster_scroll: ScrollContainer = $MainHBox/RosterPanel/RosterVBox/RosterScroll
@onready var info_label: Label = $BottomBar/InfoLabel
@onready var credits_label: Label = $Header/CreditsLabel
@onready var seed_label: Label = $Header/SeedLabel

var _available: Array[Dictionary] = []
var _focus_index: int = 0
var _graph_offset := Vector2(80.0, 60.0)


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	roster_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	graph_frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.04, 0.05, 0.08, 0.95)))
	GameTheme.configure_scroll(roster_scroll, 420.0)
	$CommitButton.pressed.connect(_on_commit_pressed)
	$AbortButton.pressed.connect(_on_abort_pressed)
	$BackButton.pressed.connect(_on_back_pressed)
	if not RunState.is_campaign_run_active() or RunState.campaign_graph == null:
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	_refresh_available()
	_refresh_roster()
	_refresh_labels()
	graph_panel.draw.connect(_draw_graph)
	graph_panel.queue_redraw()
	RunLog.info("Campaign navigation — seed %d missions=%d" % [RunState.run_seed, RunState.missions_cleared])


func _refresh_available() -> void:
	_available = RunState.campaign_graph.get_available_next()
	_focus_index = clampi(_focus_index, 0, maxi(0, _available.size() - 1))


func _refresh_roster() -> void:
	for child in roster_list.get_children():
		child.queue_free()
	for member in RunState.squad:
		var card: Control = SoldierCardScene.instantiate()
		roster_list.add_child(card)
		if card.has_method("setup_display_only"):
			card.setup_display_only(member, true)
		elif card.has_method("setup"):
			card.setup(member)
		if member.is_kia:
			card.modulate = Color(0.45, 0.45, 0.5, 0.85)


func _refresh_labels() -> void:
	credits_label.text = "Biomass: %d  |  Missions: %d" % [RunState.run_credits, RunState.missions_cleared]
	seed_label.text = "Campaign seed: %d" % RunState.run_seed
	if _available.is_empty():
		if RunState.is_campaign_complete():
			info_label.text = "Campaign complete — returning to summary…"
		else:
			info_label.text = "No available routes (run may be stuck)."
		$CommitButton.disabled = true
		return
	var node: Dictionary = _available[_focus_index]
	info_label.text = (
		"%s — %s  |  W/S: move  Enter: commit  Esc: abort run"
		% [str(node.get("display_name", "Mission")), str(node.get("description", ""))]
	)
	$CommitButton.disabled = false
	$CommitButton.text = "COMMIT — %s" % str(node.get("display_name", "Mission"))


func _focused_node() -> Dictionary:
	if _available.is_empty():
		return {}
	return _available[_focus_index]


func _on_commit_pressed() -> void:
	var node := _focused_node()
	if node.is_empty():
		return
	var node_id := str(node.get("id", ""))
	RunState.begin_campaign_mission(node_id)
	RunLog.info("Campaign commit -> %s (%s)" % [node_id, str(node.get("type", ""))])
	get_tree().change_scene_to_file("res://TacticalMap.tscn")


func _on_abort_pressed() -> void:
	RunState.end_run()
	get_tree().change_scene_to_file("res://RunSummary.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W:
				if _available.size() > 0:
					_focus_index = (_focus_index - 1 + _available.size()) % _available.size()
					_refresh_labels()
					graph_panel.queue_redraw()
					get_viewport().set_input_as_handled()
			KEY_S:
				if _available.size() > 0:
					_focus_index = (_focus_index + 1) % _available.size()
					_refresh_labels()
					graph_panel.queue_redraw()
					get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if not $CommitButton.disabled:
					_on_commit_pressed()
					get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_on_abort_pressed()
				get_viewport().set_input_as_handled()


func _draw_graph() -> void:
	if RunState.campaign_graph == null:
		return
	var graph = RunState.campaign_graph
	var focused_id := ""
	var focused := _focused_node()
	if not focused.is_empty():
		focused_id = str(focused.get("id", ""))
	for edge in graph.edges:
		var from_node: Dictionary = graph.get_node(str(edge.get("from_id", "")))
		var to_node: Dictionary = graph.get_node(str(edge.get("to_id", "")))
		if from_node.is_empty() or to_node.is_empty():
			continue
		var from_pos: Vector2 = from_node.get("draw_pos", Vector2.ZERO) + _graph_offset
		var to_pos: Vector2 = to_node.get("draw_pos", Vector2.ZERO) + _graph_offset
		graph_panel.draw_line(from_pos, to_pos, Color(0.55, 0.62, 0.72, 0.75), 2.0)
	for node in graph.nodes:
		var node_id := str(node.get("id", ""))
		var pos: Vector2 = node.get("draw_pos", Vector2.ZERO) + _graph_offset
		var node_type := str(node.get("type", ""))
		var radius := 22.0
		var fill := Color(0.2, 0.24, 0.32, 0.95)
		var outline := Color(0.45, 0.52, 0.62, 0.95)
		match node_type:
			"battle":
				fill = Color(0.55, 0.18, 0.2, 0.95)
			"elite":
				fill = Color(0.62, 0.38, 0.12, 0.95)
			"boss":
				fill = Color(0.48, 0.12, 0.62, 0.98)
				radius = 28.0
			"start":
				fill = Color(0.18, 0.42, 0.28, 0.95)
		if graph.is_completed(node_id):
			fill = fill.darkened(0.35)
			outline = Color(0.3, 0.35, 0.4, 0.8)
		var available := false
		for avail in _available:
			if str(avail.get("id", "")) == node_id:
				available = true
				break
		if available:
			outline = Color(0.35, 0.85, 1.0, 1.0)
		if node_id == focused_id:
			graph_panel.draw_circle(pos, radius + 6.0, Color(1.0, 0.92, 0.25, 0.35))
			outline = Color(1.0, 0.92, 0.25, 1.0)
		graph_panel.draw_circle(pos, radius, fill)
		graph_panel.draw_arc(pos, radius, 0.0, TAU, 24, outline, 2.5)
		_draw_node_glyph(pos, node_type)
		if node_id == focused_id or available:
			var label := str(node.get("display_name", ""))
			graph_panel.draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-48, radius + 18),
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				96,
				11,
				Color(0.92, 0.95, 1.0, 0.95),
			)


func _draw_node_glyph(pos: Vector2, node_type: String) -> void:
	match node_type:
		"battle":
			graph_panel.draw_line(pos + Vector2(-6, 4), pos + Vector2(6, -4), Color.WHITE, 2.0)
			graph_panel.draw_line(pos + Vector2(-6, -4), pos + Vector2(6, 4), Color.WHITE, 2.0)
		"elite":
			graph_panel.draw_circle(pos, 6.0, Color(1.0, 0.85, 0.35, 0.95))
		"boss":
			graph_panel.draw_arc(pos, 10.0, 0.0, TAU, 12, Color(0.95, 0.55, 1.0, 0.95), 2.0)
		_:
			graph_panel.draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), Color(0.4, 1.0, 0.55, 0.95))
