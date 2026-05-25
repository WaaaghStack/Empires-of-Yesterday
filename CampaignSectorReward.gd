extends Control

@onready var title_label: Label = $MainPanel/VBox/Title
@onready var subtitle_label: Label = $MainPanel/VBox/Subtitle
@onready var choices_box: VBoxContainer = $MainPanel/VBox/Choices
@onready var continue_button: Button = $MainPanel/VBox/ContinueButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	continue_button.pressed.connect(_on_continue_pressed)
	if not RunState.is_campaign_run_active():
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	_build_choices()
	continue_button.visible = RunState.pending_sector_reward_choices.is_empty()


func _build_choices() -> void:
	for child in choices_box.get_children():
		child.queue_free()
	var node_name := ""
	if RunState.campaign_graph and not RunState.last_completed_node_id.is_empty():
		node_name = str(RunState.campaign_graph.get_node(RunState.last_completed_node_id).get("display_name", ""))
	title_label.text = "Sector Cleared"
	subtitle_label.text = (
		"%s secured — choose your reward." % node_name if not node_name.is_empty()
		else "Choose your reward."
	)
	if RunState.pending_sector_reward_choices.is_empty():
		subtitle_label.text = "Sector secured. Continue to navigation."
		return
	for choice in RunState.pending_sector_reward_choices:
		var btn := Button.new()
		btn.text = "%s\n%s" % [str(choice.get("label", "Reward")), str(choice.get("detail", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_reward_selected.bind(choice.duplicate()))
		choices_box.add_child(btn)


func _on_reward_selected(choice: Dictionary) -> void:
	RunState.apply_sector_reward(choice)
	for child in choices_box.get_children():
		child.queue_free()
	subtitle_label.text = "Reward applied. Continue when ready."
	continue_button.visible = true


func _on_continue_pressed() -> void:
	if RunState.is_campaign_complete():
		get_tree().change_scene_to_file("res://RunSummary.tscn")
	else:
		get_tree().change_scene_to_file("res://CampaignNavigation.tscn")
