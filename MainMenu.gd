extends Control

@onready var continue_button: Button = $MainPanel/VBox/ContinueButton
@onready var tokens_label: Label = $MainPanel/VBox/TokensLabel
@onready var daily_label: Label = $MainPanel/VBox/DailyLabel
@onready var more_button: Button = $MainPanel/VBox/MoreButton

var _classic_ops_menu: PopupMenu


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	_classic_ops_menu = PopupMenu.new()
	_classic_ops_menu.add_item("Legacy 4-op run", 0)
	_classic_ops_menu.add_item("Legacy planet run", 1)
	add_child(_classic_ops_menu)
	$MainPanel/VBox/NewRunButton.pressed.connect(_on_new_run_pressed)
	more_button.pressed.connect(_on_more_pressed)
	_classic_ops_menu.id_pressed.connect(_on_classic_ops_selected)
	continue_button.pressed.connect(_on_continue_pressed)
	$MainPanel/VBox/DailyRunButton.pressed.connect(_on_daily_run_pressed)
	$MainPanel/VBox/CodexButton.pressed.connect(_on_codex_pressed)
	$MainPanel/VBox/QuitButton.pressed.connect(_on_quit_pressed)
	continue_button.visible = RunState.run_active
	tokens_label.text = "Tokens: %d  |  Carrier Biomass: %d" % [
		SaveManager.command_tokens,
		SaveManager.carrier_biomass,
	]
	var daily_seed: int = RunState.get_daily_seed()
	daily_label.text = (
		"Daily seed: %d  |  %s\nShare: %s"
		% [daily_seed, SaveManager.format_daily_best_line(), SaveManager.get_daily_share_code(daily_seed)]
	)
	RunLog.info("MainMenu opened (continue=%s)" % str(RunState.run_active))


func _on_more_pressed() -> void:
	_classic_ops_menu.position = more_button.global_position + Vector2(0, more_button.size.y)
	_classic_ops_menu.popup()


func _on_classic_ops_selected(id: int) -> void:
	if id == 0:
		get_tree().set_meta("legacy_ops_mode", true)
		get_tree().change_scene_to_file("res://SquadSelection.tscn")
	elif id == 1:
		get_tree().set_meta("legacy_planet_run", true)
		get_tree().change_scene_to_file("res://OrbitalCarrier.tscn")


func _on_new_run_pressed() -> void:
	get_tree().change_scene_to_file("res://OrbitalCarrier.tscn")


func _on_continue_pressed() -> void:
	if RunState.run_active:
		if RunState.campaign_mode:
			get_tree().change_scene_to_file("res://CampaignNavigation.tscn")
		elif RunState.planet_mode:
			get_tree().change_scene_to_file("res://PlanetMission.tscn")
		else:
			get_tree().change_scene_to_file("res://BetweenMissionHub.tscn")


func _on_daily_run_pressed() -> void:
	get_tree().set_meta("daily_seed_run", true)
	get_tree().change_scene_to_file("res://OrbitalCarrier.tscn")


func _on_codex_pressed() -> void:
	get_tree().change_scene_to_file("res://Codex.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
