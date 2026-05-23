# SquadSelection.gd
extends Control

@export var soldier_resources: Array[SoldierResource] = []

var selected_soldiers: Array[SoldierResource] = []
var soldier_cards: Array[SoldierCard] = []

@onready var soldier_container: GridContainer = $MainPanel/VBox/SoldierContainer
@onready var deploy_button: Button = $MainPanel/VBox/DeployButton
@onready var selection_counter: Label = $MainPanel/VBox/Header/SelectionCounter
@onready var subtitle_label: Label = $MainPanel/VBox/Header/Subtitle

func _ready() -> void:
	GameTheme.apply_to_control(self)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	load_soldiers()
	populate_soldier_cards()
	deploy_button.pressed.connect(_on_deploy_pressed)
	$QuitButton.pressed.connect(_on_quit_pressed)
	deploy_button.disabled = true
	update_selection_counter()

func load_soldiers() -> void:
	soldier_resources.clear()
	var paths := [
		"res://Soldier_Marine1.tres",
		"res://Soldier_Marine2.tres",
		"res://Soldier_Marine3.tres",
		"res://Soldier_Marine4.tres",
		"res://Soldier_Marine5.tres",
	]
	for path in paths:
		var res: SoldierResource = load(path)
		SoldierResource.apply_class_defaults(res)
		soldier_resources.append(res)

func populate_soldier_cards() -> void:
	for child in soldier_container.get_children():
		child.queue_free()
	soldier_cards.clear()
	for soldier in soldier_resources:
		var card: SoldierCard = preload("res://SoldierCard.tscn").instantiate()
		card.setup(soldier)
		card.selected.connect(_on_soldier_selected)
		card.deselected.connect(_on_soldier_deselected)
		soldier_container.add_child(card)
		soldier_cards.append(card)

func _on_soldier_selected(soldier: SoldierResource) -> void:
	if soldier in selected_soldiers:
		return
	if selected_soldiers.size() >= 4:
		for card in soldier_cards:
			if card.soldier_data == soldier:
				card.set_selected_state(false)
		log_blocked_selection()
		return
	selected_soldiers.append(soldier)
	for card in soldier_cards:
		if card.soldier_data == soldier:
			card.set_selected_state(true)
	update_deploy_button()
	update_selection_counter()

func _on_soldier_deselected(soldier: SoldierResource) -> void:
	selected_soldiers.erase(soldier)
	for card in soldier_cards:
		if card.soldier_data == soldier:
			card.set_selected_state(false)
	update_deploy_button()
	update_selection_counter()

func log_blocked_selection() -> void:
	subtitle_label.text = "Squad cap reached — deselect a marine to swap."
	subtitle_label.modulate = GameTheme.ACCENT_WARN

func update_deploy_button() -> void:
	deploy_button.disabled = selected_soldiers.is_empty()
	if selected_soldiers.is_empty():
		deploy_button.text = "Select Marines to Deploy"
	else:
		deploy_button.text = "Deploy Squad (%d)" % selected_soldiers.size()

func update_selection_counter() -> void:
	selection_counter.text = "%d / 4 OPERATORS SELECTED" % selected_soldiers.size()
	if selected_soldiers.size() == 4:
		selection_counter.modulate = GameTheme.ACCENT
		subtitle_label.text = "Squad ready. Proceed to mission deployment."
		subtitle_label.modulate = GameTheme.ACCENT_SUCCESS
	else:
		selection_counter.modulate = GameTheme.TEXT_MUTED
		subtitle_label.text = "Choose up to four operators for the purge mission."
		subtitle_label.modulate = GameTheme.TEXT_MUTED

func _on_deploy_pressed() -> void:
	if selected_soldiers.is_empty():
		return
	var deploy_squad: Array[SoldierResource] = []
	for soldier in selected_soldiers:
		deploy_squad.append(soldier.duplicate_for_deploy())
	get_tree().set_meta("selected_soldiers", deploy_squad)
	get_tree().change_scene_to_file("res://TacticalMap.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
