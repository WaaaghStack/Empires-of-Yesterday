extends Control

const SoldierCardScene := preload("res://SoldierCard.tscn")
@onready var graph_panel: Control = $MainHBox/GraphFrame/GraphPanel
@onready var roster_list: VBoxContainer = $MainHBox/RosterPanel/RosterVBox/RosterScroll/RosterList
@onready var graph_frame: PanelContainer = $MainHBox/GraphFrame
@onready var roster_panel: PanelContainer = $MainHBox/RosterPanel
@onready var roster_scroll: ScrollContainer = $MainHBox/RosterPanel/RosterVBox/RosterScroll
@onready var info_label: Label = $FooterPanel/InfoLabel
@onready var credits_label: Label = $TopBar/StatsVBox/CreditsLabel
@onready var seed_label: Label = $TopBar/StatsVBox/SeedLabel
@onready var commit_button: Button = $FooterPanel/ActionRow/CommitButton
@onready var abort_button: Button = $FooterPanel/ActionRow/AbortButton
var _available: Array[Dictionary] = []
var _focus_index: int = 0
var _graph_offset := Vector2(80.0, 60.0)


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	roster_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	graph_frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.04, 0.05, 0.08, 0.95)))
	GameTheme.configure_scroll(roster_scroll, 420.0)
	commit_button.pressed.connect(_on_commit_pressed)
	abort_button.pressed.connect(_on_abort_pressed)
	$TopBar/BackButton.pressed.connect(_on_back_pressed)
	$FooterPanel/ActionRow/ServicesBox/HealButton.pressed.connect(_on_heal_service_pressed)
	$FooterPanel/ActionRow/ServicesBox/IntelButton.pressed.connect(_on_intel_service_pressed)
	$FooterPanel/ActionRow/ServicesBox/RecruitButton.pressed.connect(_on_recruit_service_pressed)
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


func _node_preview_text(node: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(node.get("description", "")))
	var node_id := str(node.get("id", ""))
	var muts: Array = node.get("node_mutators", [])
	if not muts.is_empty() or RunState.is_node_intel_revealed(node_id):
		var labels: PackedStringArray = PackedStringArray()
		for m in muts:
			labels.append(str(m).replace("_", " "))
		if labels.is_empty():
			parts.append("Mutators: none")
		else:
			parts.append("Mutators: %s" % ", ".join(labels))
	else:
		parts.append("Mutators: [classified]")
	var reward: String = str(node.get("sector_reward", ""))
	if not reward.is_empty():
		parts.append("Reward: %s" % reward)
	return "  |  ".join(parts)


func _refresh_labels() -> void:
	credits_label.text = "Biomass: %d  |  Missions: %d  |  %s" % [
		RunState.run_credits,
		RunState.missions_cleared,
		SaveManager.format_ascension_line(),
	]
	seed_label.text = "Seed %d" % RunState.run_seed
	$FooterPanel/ActionRow/ServicesBox/HealButton.text = "Heal (%d)" % RunState.NAV_HEAL_COST
	$FooterPanel/ActionRow/ServicesBox/IntelButton.text = "Intel (%d)" % RunState.NAV_INTEL_COST
	$FooterPanel/ActionRow/ServicesBox/RecruitButton.text = "Recruit (%d)" % RunState.NAV_RECRUIT_COST
	if _available.is_empty():
		if RunState.is_campaign_complete():
			info_label.text = "Campaign complete — returning to summary…"
		else:
			info_label.text = "No available routes (run may be stuck)."
		commit_button.disabled = true
		return
	var node: Dictionary = _available[_focus_index]
	var node_type: String = str(node.get("type", ""))
	var commit_label := "Commit: %s" % str(node.get("display_name", "Mission"))
	if node_type == "rest":
		commit_label = "Rest & Recover"
	elif node_type == "armory":
		commit_label = "Open Armory"
	elif node_type == "intel_broker":
		commit_label = "Intel Broker"
	info_label.text = "%s\n%s\nW/S move · Enter commit · Esc abort" % [
		str(node.get("display_name", "Mission")),
		_node_preview_text(node),
	]
	commit_button.disabled = false
	commit_button.text = commit_label


func _focused_node() -> Dictionary:
	if _available.is_empty():
		return {}
	return _available[_focus_index]


func _on_commit_pressed() -> void:
	var node := _focused_node()
	if node.is_empty():
		return
	var node_id := str(node.get("id", ""))
	var node_type := str(node.get("type", ""))
	if node_type == "rest":
		RunState.apply_rest_node(node_id)
		RunState.complete_event_node(node_id)
		_refresh_available()
		_refresh_roster()
		_refresh_labels()
		graph_panel.queue_redraw()
		return
	if node_type == "intel_broker":
		var reveal_ids: Array[String] = []
		for child_id in RunState.campaign_graph.get_children(node_id):
			reveal_ids.append(child_id)
		RunState.reveal_intel_for_nodes(reveal_ids)
		RunState.complete_event_node(node_id)
		RunState.run_credits += 5
		_refresh_available()
		_refresh_labels()
		graph_panel.queue_redraw()
		return
	if node_type == "armory":
		info_label.text = "Armory open — use Heal / Intel / Recruit services below, then pick your next sector."
		RunState.complete_event_node(node_id)
		_refresh_available()
		_refresh_labels()
		graph_panel.queue_redraw()
		return
	RunState.begin_campaign_mission(node_id)
	RunLog.info("Campaign commit -> %s (%s)" % [node_id, node_type])
	get_tree().change_scene_to_file("res://TacticalMap.tscn")


func _on_heal_service_pressed() -> void:
	if not RunState.spend_biomass(RunState.NAV_HEAL_COST):
		info_label.text = "Not enough biomass for field heal."
		return
	RunState.heal_squad_percent(0.3)
	_refresh_roster()
	info_label.text = "Squad healed for %d biomass." % RunState.NAV_HEAL_COST


func _on_intel_service_pressed() -> void:
	if _available.is_empty():
		return
	if not RunState.spend_biomass(RunState.NAV_INTEL_COST):
		info_label.text = "Not enough biomass for intel sweep."
		return
	var node: Dictionary = _available[_focus_index]
	RunState.reveal_intel_for_nodes([str(node.get("id", ""))])
	_refresh_labels()
	graph_panel.queue_redraw()


func _on_recruit_service_pressed() -> void:
	if not RunState.spend_biomass(RunState.NAV_RECRUIT_COST):
		info_label.text = "Not enough biomass to draft a recruit."
		return
	var rookie := RunState.draft_recruit()
	if rookie:
		_refresh_roster()
		info_label.text = "Drafted %s into the roster." % rookie.soldier_name
	else:
		info_label.text = "No recruits available."


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
				if not commit_button.disabled:
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
			"rest":
				fill = Color(0.15, 0.38, 0.55, 0.95)
			"armory":
				fill = Color(0.42, 0.32, 0.12, 0.95)
			"intel_broker":
				fill = Color(0.22, 0.45, 0.62, 0.95)
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
			if label.length() > 18:
				label = label.substr(0, 16) + "…"
			graph_panel.draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-70, radius + 16),
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				140,
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
		"rest":
			graph_panel.draw_line(pos + Vector2(-5, 0), pos + Vector2(5, 0), Color(0.6, 0.9, 1.0, 0.95), 2.0)
		"armory":
			graph_panel.draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.8, 0.35, 0.95))
		"intel_broker":
			graph_panel.draw_circle(pos, 4.0, Color(0.5, 1.0, 1.0, 0.95))
		_:
			graph_panel.draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), Color(0.4, 1.0, 0.55, 0.95))
