# SquadSelection.gd
extends Control

@export var soldier_resources: Array[SoldierResource] = []

var selected_soldiers: Array[SoldierResource] = []

@onready var soldier_container: GridContainer = $SoldierContainer
@onready var deploy_button: Button = $DeployButton
@onready var selection_counter: Label = $SelectionCounter

func _ready():
    load_soldiers()
    populate_soldier_cards()
    deploy_button.pressed.connect(_on_deploy_pressed)
    deploy_button.disabled = true
    update_selection_counter()

func load_soldiers():
    soldier_resources.clear()
    soldier_resources.append(preload("res://Soldier_Marine1.tres"))
    soldier_resources.append(preload("res://Soldier_Marine2.tres"))
    soldier_resources.append(preload("res://Soldier_Marine3.tres"))
    soldier_resources.append(preload("res://Soldier_Marine4.tres"))
    soldier_resources.append(preload("res://Soldier_Marine5.tres"))

func populate_soldier_cards():
    for child in soldier_container.get_children():
        child.queue_free()
    
    for soldier in soldier_resources:
        var card_scene = preload("res://SoldierCard.tscn")
        if card_scene:
            var card = card_scene.instantiate()
            card.setup(soldier)
            card.selected.connect(_on_soldier_selected)
            card.deselected.connect(_on_soldier_deselected)
            soldier_container.add_child(card)

func _on_soldier_selected(soldier: SoldierResource):
    if soldier not in selected_soldiers and selected_soldiers.size() < 4:
        selected_soldiers.append(soldier)
        update_deploy_button()
        update_selection_counter()

func _on_soldier_deselected(soldier: SoldierResource):
    selected_soldiers.erase(soldier)
    update_deploy_button()
    update_selection_counter()

func update_deploy_button():
    deploy_button.disabled = selected_soldiers.is_empty()

func update_selection_counter():
    selection_counter.text = "%d/4 SELECTED" % selected_soldiers.size()
    if selected_soldiers.size() == 4:
        selection_counter.modulate = Color(0.85, 0.15, 0.1, 1)
    else:
        selection_counter.modulate = Color(0.7, 0.7, 0.7, 1)

func _on_deploy_pressed():
    if not selected_soldiers.is_empty():
        get_tree().set_meta("selected_soldiers", selected_soldiers)
        get_tree().change_scene_to_file("res://TacticalMap.tscn")