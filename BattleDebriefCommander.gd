extends Control

@onready var summary_label: Label = $MainPanel/VBox/SummaryLabel
@onready var continue_button: Button = $MainPanel/VBox/ContinueButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	continue_button.pressed.connect(_on_continue_pressed)
	$MainPanel/VBox/MenuButton.pressed.connect(_on_menu_pressed)
	var msg := RunState.last_turn_summary
	if RunState.army_pool:
		summary_label.text = (
			"Battle resolved.\n\nArmy: %d total (%d available)\nLost this run: %d\n\n%s"
			% [
				RunState.army_pool.total_soldiers,
				RunState.army_pool.available_soldiers,
				RunState.army_pool.total_lost_this_run,
				msg,
			]
		)
	else:
		summary_label.text = "Battle resolved."
	if RunState.galaxy_state and (
		RunState.galaxy_state.is_galaxy_won()
		or RunState.army_pool.is_defeated()
		or RunState.galaxy_state.is_hq_lost()
	):
		continue_button.text = "Return to Menu"


func _on_continue_pressed() -> void:
	if not RunState.is_commander_run_active():
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	if RunState.galaxy_state and (
		RunState.galaxy_state.is_galaxy_won()
		or RunState.army_pool.is_defeated()
		or RunState.galaxy_state.is_hq_lost()
	):
		_on_menu_pressed()
		return
	get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")


func _on_menu_pressed() -> void:
	RunState.end_commander_run()
	get_tree().change_scene_to_file("res://MainMenu.tscn")
