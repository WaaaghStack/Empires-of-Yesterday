# SquadSelection.gd
extends Control

const SoldierCardScene := preload("res://SoldierCard.tscn")

var _squads: Array = [[], [], []]
var _use_daily_seed := false

@onready var squad_scroll: ScrollContainer = $MainPanel/VBox/SquadScroll
@onready var squad_container: VBoxContainer = $MainPanel/VBox/SquadScroll/SquadContainer
@onready var deploy_button: Button = $MainPanel/VBox/DeployButton
@onready var selection_counter: Label = $MainPanel/VBox/Header/SelectionCounter
@onready var subtitle_label: Label = $MainPanel/VBox/Header/Subtitle
@onready var tokens_label: Label = $MainPanel/VBox/Header/TokensLabel
@onready var seed_input: LineEdit = $MainPanel/VBox/SeedRow/SeedInput
@onready var reroll_all_button: Button = $MainPanel/VBox/RerollRow/RerollAllButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.configure_scroll(squad_scroll, 380.0)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	_use_daily_seed = get_tree().has_meta("daily_seed_run")
	if _use_daily_seed:
		get_tree().remove_meta("daily_seed_run")
	_generate_all_squads()
	_refresh_ui()
	deploy_button.pressed.connect(_on_deploy_pressed)
	reroll_all_button.pressed.connect(_on_reroll_all_pressed)
	$BackButton.pressed.connect(_on_back_pressed)
	$MainPanel/VBox/PortraitButton.pressed.connect(_on_portrait_button_pressed)
	$QuitButton.pressed.connect(_on_quit_pressed)
	deploy_button.disabled = false
	tokens_label.text = "Command Tokens: %d" % SaveManager.command_tokens
	if _use_daily_seed:
		var daily_seed: int = RunState.get_daily_seed()
		subtitle_label.text = (
			"Daily seed run — seed %d  |  Share: %s  |  %s"
			% [daily_seed, SaveManager.get_daily_share_code(daily_seed), SaveManager.format_daily_best_line()]
		)
		subtitle_label.modulate = GameTheme.ACCENT
		seed_input.text = str(daily_seed)
		seed_input.editable = false


func _generate_all_squads() -> void:
	var used_names: Dictionary = {}
	for squad_idx in range(RunState.SQUAD_COUNT):
		var squad_id: String = RunState.SQUAD_IDS[squad_idx]
		_squads[squad_idx] = RunState.generate_squad(squad_id, used_names)


func _collect_names_excluding_squad(exclude_idx: int) -> Dictionary:
	var used: Dictionary = {}
	for squad_idx in range(_squads.size()):
		if squad_idx == exclude_idx:
			continue
		for op in _squads[squad_idx]:
			used[op.soldier_name] = true
	return used


func _reroll_squad(squad_idx: int) -> void:
	var used_names: Dictionary = _collect_names_excluding_squad(squad_idx)
	var squad_id: String = RunState.SQUAD_IDS[squad_idx]
	_squads[squad_idx] = RunState.generate_squad(squad_id, used_names)
	_refresh_ui()


func _refresh_ui() -> void:
	for child in squad_container.get_children():
		child.queue_free()
	for squad_idx in range(RunState.SQUAD_COUNT):
		_build_squad_section(squad_idx)
	_update_header()


func _build_squad_section(squad_idx: int) -> void:
	var squad_id: String = RunState.SQUAD_IDS[squad_idx]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	squad_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "SQUAD %s" % GameTheme.squad_label(squad_id).to_upper()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GameTheme.squad_color(squad_id))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var class_summary := Label.new()
	class_summary.text = _squad_class_summary(_squads[squad_idx])
	class_summary.add_theme_color_override("font_color", GameTheme.TEXT_MUTED)
	class_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(class_summary)
	var reroll_btn := Button.new()
	reroll_btn.text = "Reroll Squad"
	reroll_btn.pressed.connect(_on_reroll_squad_pressed.bind(squad_idx))
	header.add_child(reroll_btn)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)
	for op in _squads[squad_idx]:
		var card: SoldierCard = SoldierCardScene.instantiate()
		grid.add_child(card)
		card.setup_display_only(op, true)


func _squad_class_summary(operators: Array) -> String:
	var counts: Dictionary = {}
	for op in operators:
		var cls: String = GameTheme.class_name_text(op.marine_class)
		counts[cls] = int(counts.get(cls, 0)) + 1
	var parts: PackedStringArray = []
	for cls in counts.keys():
		parts.append("%s x%d" % [cls, counts[cls]])
	return ", ".join(parts)


func _update_header() -> void:
	selection_counter.text = "%d / %d SQUADS READY" % [RunState.SQUAD_COUNT, RunState.SQUAD_COUNT]
	selection_counter.modulate = GameTheme.ACCENT
	if not _use_daily_seed:
		var pool_size: int = RunState.get_unlocked_marine_classes().size()
		subtitle_label.text = (
			"Alpha / Bravo / Charlie roll random operators from %d unlocked classes. Reroll squads you dislike."
			% pool_size
		)
		subtitle_label.modulate = GameTheme.ACCENT_SUCCESS
	tokens_label.text = "Command Tokens: %d" % SaveManager.command_tokens
	deploy_button.text = "Start Run — 3 Squads × 4 Operators"


func _on_reroll_squad_pressed(squad_idx: int) -> void:
	_reroll_squad(squad_idx)


func _on_reroll_all_pressed() -> void:
	_generate_all_squads()
	_refresh_ui()


func _on_deploy_pressed() -> void:
	var run_squad: Array[SoldierResource] = []
	for squad in _squads:
		for op in squad:
			run_squad.append(op.duplicate_for_deploy())
	if run_squad.size() < RunState.ROSTER_SIZE:
		return
	RunState.start_run(run_squad, _read_seed_override(), _use_daily_seed)
	RunLog.note_run_seed(RunState.run_seed)
	RunLog.info(
		"Run started — squad=%d squads=%d daily=%s seed=%d"
		% [run_squad.size(), RunState.SQUAD_COUNT, str(_use_daily_seed), RunState.run_seed]
	)
	get_tree().change_scene_to_file("res://TacticalMap.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_portrait_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Codex.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _read_seed_override() -> int:
	if not seed_input or seed_input.text.strip_edges().is_empty():
		return -1
	var text := seed_input.text.strip_edges()
	if text.is_valid_int():
		return text.to_int()
	return hash(text) & 0x7FFFFFFF
