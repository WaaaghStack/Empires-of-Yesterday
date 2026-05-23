extends Control

@onready var codex_scroll: ScrollContainer = $MainPanel/VBox/CodexScroll
@onready var body_label: RichTextLabel = $MainPanel/VBox/CodexScroll/ScrollContent/BodyLabel
@onready var tokens_label: Label = $MainPanel/VBox/CodexScroll/ScrollContent/TokensLabel
@onready var portrait_grid: GridContainer = $MainPanel/VBox/CodexScroll/ScrollContent/PortraitGrid


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.configure_scroll(codex_scroll, 480.0)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	$MainPanel/VBox/BackButton.pressed.connect(_on_back_pressed)
	_populate()


func _populate() -> void:
	tokens_label.text = "Command Tokens: %d" % SaveManager.command_tokens
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Operators[/b]")
	for operator in SoldierResource.get_roster_operators():
		var role_name := GameTheme.class_name_text(operator.marine_class)
		lines.append("  • [b]%s[/b] — %s" % [operator.soldier_name, role_name])
		lines.append("    %s" % operator.get_bio_line())
	lines.append("")
	lines.append("[b]Classes[/b]")
	for cls in SoldierResource.MarineClass.values():
		var display_name := GameTheme.class_name_text(cls)
		if SaveManager.is_class_unlocked(cls):
			lines.append("  • %s — unlocked" % display_name)
		else:
			lines.append("  • %s — locked (%d tokens)" % [display_name, SaveManager.get_class_unlock_cost(cls)])
	lines.append("")
	lines.append("[b]Modifiers discovered[/b]")
	if SaveManager.discovered_modifiers.is_empty():
		lines.append("  • None yet")
	else:
		for id in SaveManager.discovered_modifiers:
			lines.append("  • %s" % id.replace("_", " ").capitalize())
	lines.append("")
	lines.append("[b]Enemies encountered[/b]")
	if SaveManager.discovered_enemies.is_empty():
		lines.append("  • None yet")
	else:
		for id in SaveManager.discovered_enemies:
			lines.append("  • %s" % id.capitalize())
	lines.append("")
	lines.append("[b]Objectives seen[/b]")
	if SaveManager.discovered_objectives.is_empty():
		lines.append("  • None yet")
	else:
		for id in SaveManager.discovered_objectives:
			lines.append("  • %s" % id.replace("_", " ").capitalize())
	body_label.text = "\n".join(lines)
	_build_portrait_grid()


func _build_portrait_grid() -> void:
	for child in portrait_grid.get_children():
		child.queue_free()
	var count := PortraitPool.get_portrait_count()
	for i in range(count):
		var path := PortraitPool.get_portrait_path_at(i)
		if path.is_empty():
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(56, 56)
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(path):
			tex_rect.texture = load(path)
		if SaveManager.is_portrait_unlocked(path):
			tex_rect.modulate = Color.WHITE
		else:
			tex_rect.modulate = Color(0.35, 0.35, 0.38, 1.0)
		cell.add_child(tex_rect)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 28)
		if SaveManager.is_portrait_unlocked(path):
			btn.text = "Unlocked"
			btn.disabled = true
		else:
			var cost := SaveManager.get_portrait_unlock_cost(i)
			btn.text = "Unlock (%d)" % cost if cost > 0 else "Unlock"
			btn.pressed.connect(_try_unlock_portrait.bind(path, btn, tex_rect))
		cell.add_child(btn)
		portrait_grid.add_child(cell)


func _try_unlock_portrait(path: String, btn: Button, tex_rect: TextureRect) -> void:
	if SaveManager.try_unlock_portrait(path):
		tokens_label.text = "Command Tokens: %d" % SaveManager.command_tokens
		btn.text = "Unlocked"
		btn.disabled = true
		tex_rect.modulate = Color.WHITE
	else:
		var index := PortraitPool.get_portrait_index_for_path(path)
		var cost := SaveManager.get_portrait_unlock_cost(index)
		btn.text = "Need %d tokens" % cost


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
