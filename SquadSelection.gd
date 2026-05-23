# SquadSelection.gd
extends Control

@export var soldier_resources: Array[SoldierResource] = []

var selected_soldiers: Array[SoldierResource] = []

@onready var soldier_container: GridContainer = $SoldierContainer
@onready var deploy_button: Button = $DeployButton

func _ready():
    load_soldiers()
    populate_soldier_cards()
    deploy_button.pressed.connect(_on_deploy_pressed)
    deploy_button.disabled = true

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
            # Connect without .bind() - SoldierCard already passes the soldier
            card.selected.connect(_on_soldier_selected)
            card.deselected.connect(_on_soldier_deselected)
            soldier_container.add_child(card)

func _on_soldier_selected(soldier: SoldierResource):
    if soldier not in selected_soldiers and selected_soldiers.size() < 4:
        selected_soldiers.append(soldier)
        update_deploy_button()

func _on_soldier_deselected(soldier: SoldierResource):
    selected_soldiers.erase(soldier)
    update_deploy_button()

func update_deploy_button():
    deploy_button.disabled = selected_soldiers.is_empty()

func _on_deploy_pressed():
    if not selected_soldiers.is_empty():
        get_tree().set_meta("selected_soldiers", selected_soldiers)
        get_tree().change_scene_to_file("res://TacticalMap.tscn")