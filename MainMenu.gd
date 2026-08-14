extends Control

const EnemyStrategyLib := preload("res://EnemyStrategy.gd")

@onready var main_panel: PanelContainer = $MainPanel
@onready var custom_panel: PanelContainer = $CustomWorldPanel
@onready var seed_label: Label = $MainPanel/VBox/SeedLabel
@onready var ai_vs_ai_check: CheckBox = $MainPanel/VBox/AiVsAiCheck
@onready var play_button: Button = $MainPanel/VBox/PlayButton
@onready var custom_world_button: Button = $MainPanel/VBox/CustomWorldButton
@onready var quit_button: Button = $MainPanel/VBox/QuitButton

@onready var custom_seed_label: Label = $CustomWorldPanel/VBox/SeedRow/CustomSeedLabel
@onready var reroll_seed_button: Button = $CustomWorldPanel/VBox/SeedRow/RerollSeedButton
@onready var land_bias_slider: HSlider = $CustomWorldPanel/VBox/LandBiasRow/LandBiasSlider
@onready var land_bias_value: Label = $CustomWorldPanel/VBox/LandBiasRow/LandBiasValue
@onready var resource_density_slider: HSlider = $CustomWorldPanel/VBox/ResourceRow/ResourceDensitySlider
@onready var resource_density_value: Label = $CustomWorldPanel/VBox/ResourceRow/ResourceDensityValue
@onready var mountain_bias_slider: HSlider = $CustomWorldPanel/VBox/MountainRow/MountainBiasSlider
@onready var mountain_bias_value: Label = $CustomWorldPanel/VBox/MountainRow/MountainBiasValue
@onready var start_region_option: OptionButton = $CustomWorldPanel/VBox/StartRegionRow/StartRegionOption
@onready var difficulty_option: OptionButton = $CustomWorldPanel/VBox/DifficultyRow/DifficultyOption
@onready var generate_play_button: Button = $CustomWorldPanel/VBox/GeneratePlayButton
@onready var custom_back_button: Button = $CustomWorldPanel/VBox/BackButton

var _custom_seed: int = 0


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	main_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	custom_panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	play_button.pressed.connect(_on_play_pressed)
	custom_world_button.pressed.connect(_on_custom_world_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	reroll_seed_button.pressed.connect(_on_reroll_seed_pressed)
	generate_play_button.pressed.connect(_on_generate_play_pressed)
	custom_back_button.pressed.connect(_on_custom_back_pressed)
	land_bias_slider.value_changed.connect(_on_land_bias_changed)
	resource_density_slider.value_changed.connect(_on_resource_density_changed)
	mountain_bias_slider.value_changed.connect(_on_mountain_bias_changed)
	if ai_vs_ai_check:
		ai_vs_ai_check.button_pressed = RunState.ai_vs_ai
		ai_vs_ai_check.tooltip_text = (
			"Both sides expand with the outpost AI. Deploy is skipped; you can orbit/zoom and watch."
		)
	_setup_custom_options()
	_show_main()
	_refresh_seed_label()
	RunLog.info("MainMenu opened (world conquest)")


func _setup_custom_options() -> void:
	start_region_option.clear()
	start_region_option.add_item("Any hemisphere", 0)
	start_region_option.add_item("West (lon < 0)", 1)
	start_region_option.add_item("East (lon ≥ 0)", 2)
	start_region_option.select(0)
	difficulty_option.clear()
	difficulty_option.add_item("Beginner", EnemyStrategyLib.Difficulty.BEGINNER)
	difficulty_option.add_item("Medium", EnemyStrategyLib.Difficulty.MEDIUM)
	difficulty_option.add_item("Expert", EnemyStrategyLib.Difficulty.EXPERT)
	difficulty_option.select(EnemyStrategyLib.Difficulty.MEDIUM)
	land_bias_slider.min_value = -1.0
	land_bias_slider.max_value = 1.0
	land_bias_slider.step = 0.05
	land_bias_slider.value = 0.0
	resource_density_slider.min_value = 0.25
	resource_density_slider.max_value = 2.0
	resource_density_slider.step = 0.05
	resource_density_slider.value = 1.0
	mountain_bias_slider.min_value = -1.0
	mountain_bias_slider.max_value = 1.0
	mountain_bias_slider.step = 0.05
	mountain_bias_slider.value = 0.0
	_on_land_bias_changed(0.0)
	_on_resource_density_changed(1.0)
	_on_mountain_bias_changed(0.0)
	_reroll_custom_seed()


func _show_main() -> void:
	main_panel.visible = true
	custom_panel.visible = false


func _show_custom() -> void:
	main_panel.visible = false
	custom_panel.visible = true
	_refresh_custom_seed_label()


func _refresh_seed_label() -> void:
	if RunState.run_seed == 0:
		seed_label.text = "Random Earth map each run"
	else:
		seed_label.text = "Map seed: %d" % RunState.run_seed


func _refresh_custom_seed_label() -> void:
	custom_seed_label.text = "Seed: %d" % _custom_seed


func _reroll_custom_seed() -> void:
	_custom_seed = randi() & 0x7FFFFFFF
	if _custom_seed == 0:
		_custom_seed = 1
	_refresh_custom_seed_label()


func _on_land_bias_changed(v: float) -> void:
	land_bias_value.text = "%+.2f" % v


func _on_resource_density_changed(v: float) -> void:
	resource_density_value.text = "%.2f×" % v


func _on_mountain_bias_changed(v: float) -> void:
	mountain_bias_value.text = "%+.2f" % v


func _on_play_pressed() -> void:
	if ai_vs_ai_check:
		RunState.ai_vs_ai = ai_vs_ai_check.button_pressed
	RunState.reset_custom_world_defaults()
	if RunState.run_seed == 0:
		RunState.run_seed = randi() & 0x7FFFFFFF
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_custom_world_pressed() -> void:
	_show_custom()


func _on_custom_back_pressed() -> void:
	_show_main()


func _on_reroll_seed_pressed() -> void:
	_reroll_custom_seed()


func _start_region_from_option() -> String:
	match start_region_option.get_selected_id():
		1:
			return "west"
		2:
			return "east"
		_:
			return "any"


func _on_generate_play_pressed() -> void:
	if ai_vs_ai_check:
		RunState.ai_vs_ai = ai_vs_ai_check.button_pressed
	RunState.custom_world = true
	RunState.world_map_id = "earth"
	RunState.run_seed = _custom_seed
	RunState.land_bias = float(land_bias_slider.value)
	RunState.resource_density = float(resource_density_slider.value)
	RunState.mountain_bias = float(mountain_bias_slider.value)
	RunState.start_region = _start_region_from_option()
	RunState.ai_difficulty = int(difficulty_option.get_selected_id())
	RunLog.info(
		(
			"Custom World: seed=%d land_bias=%.2f resource=%.2f mountain=%.2f region=%s difficulty=%d procedural=1"
			% [
				RunState.run_seed,
				RunState.land_bias,
				RunState.resource_density,
				RunState.mountain_bias,
				RunState.start_region,
				RunState.ai_difficulty,
			]
		)
	)
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
