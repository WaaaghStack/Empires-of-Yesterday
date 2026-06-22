extends Control

@onready var seed_label: Label = $MainPanel/VBox/SeedLabel
@onready var play_button: Button = $MainPanel/VBox/PlayButton
@onready var quit_button: Button = $MainPanel/VBox/QuitButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_refresh_seed_label()
	RunLog.info("MainMenu opened (world conquest)")


func _refresh_seed_label() -> void:
	if RunState.run_seed == 0:
		seed_label.text = "Random Earth map each run"
	else:
		seed_label.text = "Map seed: %d" % RunState.run_seed


func _on_play_pressed() -> void:
	if RunState.run_seed == 0:
		RunState.run_seed = randi() & 0x7FFFFFFF
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
