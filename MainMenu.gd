extends Control

@onready var continue_button: Button = $MainPanel/VBox/ContinueButton
@onready var tokens_label: Label = $MainPanel/VBox/TokensLabel
@onready var daily_label: Label = $MainPanel/VBox/DailyLabel


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	$MainPanel/VBox/NewRunButton.pressed.connect(_on_new_run_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	$MainPanel/VBox/DailyRunButton.pressed.connect(_on_daily_run_pressed)
	$MainPanel/VBox/CodexButton.pressed.connect(_on_codex_pressed)
	$MainPanel/VBox/QuitButton.pressed.connect(_on_quit_pressed)
	continue_button.visible = RunState.run_active
	tokens_label.text = "Command Tokens: %d" % SaveManager.command_tokens
	var daily_seed: int = RunState.get_daily_seed()
	daily_label.text = (
		"Daily seed: %d  |  %s\nShare: %s"
		% [daily_seed, SaveManager.format_daily_best_line(), SaveManager.get_daily_share_code(daily_seed)]
	)
	RunLog.info("MainMenu opened (continue=%s)" % str(RunState.run_active))


func _on_new_run_pressed() -> void:
	get_tree().change_scene_to_file("res://SquadSelection.tscn")


func _on_continue_pressed() -> void:
	if RunState.run_active:
		get_tree().change_scene_to_file("res://BetweenMissionHub.tscn")


func _on_daily_run_pressed() -> void:
	get_tree().set_meta("daily_seed_run", true)
	get_tree().change_scene_to_file("res://SquadSelection.tscn")


func _on_codex_pressed() -> void:
	get_tree().change_scene_to_file("res://Codex.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
