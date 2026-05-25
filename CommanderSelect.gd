extends Control

const CommanderProfileLib := preload("res://CommanderProfile.gd")

@onready var list_box: VBoxContainer = $MainPanel/VBox/ListScroll/ListBox
@onready var detail_label: Label = $MainPanel/VBox/DetailLabel
@onready var start_button: Button = $MainPanel/VBox/StartButton

var _selected_id: String = "logistician"


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	$MainPanel/VBox/BackButton.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	_build_list()
	_refresh_detail()
	RunLog.info("CommanderSelect opened")


func _build_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	for profile in CommanderProfileLib.PROFILES:
		var btn := Button.new()
		btn.text = str(profile.get("name", "Commander"))
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 40)
		var cid := str(profile.get("id", ""))
		btn.set_meta("commander_id", cid)
		btn.button_pressed = cid == _selected_id
		btn.pressed.connect(_on_commander_pressed.bind(cid))
		list_box.add_child(btn)


func _on_commander_pressed(commander_id: String) -> void:
	_selected_id = commander_id
	for child in list_box.get_children():
		if child is Button:
			child.button_pressed = str(child.get_meta("commander_id", "")) == commander_id
	_refresh_detail()


func _refresh_detail() -> void:
	var profile: Dictionary = CommanderProfileLib.get_by_id(_selected_id)
	detail_label.text = (
		"%s\n\n%s\n\nStarting army: %d\nManpower: %d  |  Biomass: %d  |  Alloys: %d\nAbility: %s"
		% [
			profile.get("name", ""),
			profile.get("description", ""),
			profile.get("starting_soldiers", 0),
			profile.get("starting_manpower", 0),
			profile.get("starting_biomass", 0),
			profile.get("starting_alloys", 0),
			profile.get("ability_name", ""),
		]
	)


func _on_start_pressed() -> void:
	var daily: bool = get_tree().get_meta("daily_seed_run", false)
	RunState.start_commander_run(_selected_id, -1, daily)
	get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
