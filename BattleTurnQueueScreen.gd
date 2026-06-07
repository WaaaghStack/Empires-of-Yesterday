extends Control

const GameThemeLib := preload("res://GameTheme.gd")

@onready var title_label: Label = $MainPanel/VBox/TitleLabel
@onready var hint_label: Label = $MainPanel/VBox/HintLabel
@onready var battle_list: VBoxContainer = $MainPanel/VBox/BattleScroll/BattleList
@onready var skip_all_button: Button = $MainPanel/VBox/SkipAllButton
@onready var continue_button: Button = $MainPanel/VBox/ContinueButton


func _ready() -> void:
	GameThemeLib.apply_to_control(self)
	GameThemeLib.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameThemeLib.make_panel_style())
	skip_all_button.pressed.connect(_on_skip_all_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	if not RunState.is_commander_run_active() or not RunState.has_turn_battle_queue():
		get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")
		return
	_refresh_list()


func _refresh_list() -> void:
	for child in battle_list.get_children():
		child.queue_free()
	var pending := RunState.count_unresolved_turn_battles()
	title_label.text = "Battles this turn"
	hint_label.text = (
		"%d battle(s) resolved in simulation. Watch replays or skip to apply results."
		% pending
	)
	continue_button.visible = pending == 0
	skip_all_button.visible = pending > 0
	for entry in RunState.turn_battle_queue:
		if bool(entry.get("resolved", false)):
			continue
		_add_battle_row(entry)


func _add_battle_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var won_txt := "WIN" if bool(entry.get("player_won", false)) else "LOSS"
	var ms: float = float(entry.get("resolve_ms", 0.0))
	label.text = "%s  [%s, %d rounds, %.0fms sim]" % [
		str(entry.get("label", "?")),
		won_txt,
		int(entry.get("turns", 0)),
		ms,
	]
	row.add_child(label)
	var watch_btn := Button.new()
	watch_btn.text = "Watch"
	watch_btn.custom_minimum_size = Vector2(90, 36)
	watch_btn.pressed.connect(_on_watch_pressed.bind(entry))
	row.add_child(watch_btn)
	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(90, 36)
	skip_btn.pressed.connect(_on_skip_pressed.bind(entry))
	row.add_child(skip_btn)
	battle_list.add_child(row)


func _on_watch_pressed(entry: Dictionary) -> void:
	var node_id := str(entry.get("node_id", ""))
	if node_id.is_empty():
		return
	RunState.pending_battle_node_id = node_id
	RunState.pending_battle_id = int(entry.get("battle_id", 0))
	RunState.pending_live_battle = false
	var tape = entry.get("tape", null)
	if typeof(tape) == TYPE_DICTIONARY:
		RunState.pending_replay_tape = tape
	else:
		RunState.pending_replay_tape = tape
	RunState.pending_queue_auto_watch = true
	RunState.return_to_battle_queue_after_view = true
	RunState.save_commander_run()
	get_tree().change_scene_to_file("res://BattleViewer.tscn")


func _on_skip_pressed(entry: Dictionary) -> void:
	RunState.apply_turn_battle_entry(entry)
	RunState.save_commander_run()
	_refresh_list()


func _on_skip_all_pressed() -> void:
	for entry in RunState.turn_battle_queue:
		if not bool(entry.get("resolved", false)):
			RunState.apply_turn_battle_entry(entry)
	RunState.save_commander_run()
	_refresh_list()


func _on_continue_pressed() -> void:
	if RunState.has_turn_battle_queue():
		return
	var status: Dictionary = RunState.complete_turn_battle_queue()
	RunState.save_commander_run()
	if bool(status.get("victory", false)) or bool(status.get("game_over", false)):
		RunState.end_commander_run()
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")
