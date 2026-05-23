# SquadSelection.gd
extends Control

signal squad_selected(soldiers: Array[SoldierResource])

@export var soldier_resources: Array[SoldierResource] = []

var selected_soldiers: Array[SoldierResource] = []

@onready var soldier_container = $SoldierContainer
@onready var deploy_button = $DeployButton

func _ready():
    load_soldiers()
    populate_soldier_cards()
    deploy_button.pressed.connect(_on_deploy_pressed)

func load_soldiers():
    soldier_resources = [
        preload("res://Soldier_Marine1.tres"),
        preload("res://Soldier_Marine2.tres"),
        preload("res://Soldier_Marine3.tres"),
        preload("res://Soldier_Marine4.tres"),
        preload("res://Soldier_Marine5.tres")
    ]

func populate_soldier_cards():
    for child in soldier_container.get_children():
        child.queue_free()
    
    for soldier in soldier_resources:
        var card_scene = preload("res://SoldierCard.tscn")
        if card_scene:
            var card = card_scene.instantiate()
            card.setup(soldier)
            card.selected.connect(_on_soldier_selected.bind(soldier))
            card.deselected.connect(_on_soldier_deselected.bind(soldier))
            soldier_container.add_child(card)

func _on_soldier_selected(soldier: SoldierResource):
    if selected_soldiers.size() < 4 and soldier not in selected_soldiers:
        selected_soldiers.append(soldier)
        update_deploy_button()

func _on_soldier_deselected(soldier: SoldierResource):
    selected_soldiers.erase(soldier)
    update_deploy_button()

func update_deploy_button():
    deploy_button.disabled = selected_soldiers.is_empty()

func _on_deploy_pressed():
    if not selected_soldiers.is_empty():
        squad_selected.emit(selected_soldiers)
        print("Squad deployed: ", selected_soldiers.map(func(s): return s.soldier_name))