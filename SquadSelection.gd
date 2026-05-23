# SquadSelection.gd
extends Control

@export var soldier_resources: Array[SoldierResource] = []

@onready var soldier_container: GridContainer = $SoldierContainer
@onready var deploy_button: Button = $DeployButton

func _ready():
    print("DEBUG: _ready() called")
    print("DEBUG: Node name: ", name)
    print("DEBUG: SoldierContainer exists: ", has_node("SoldierContainer"))
    print("DEBUG: DeployButton exists: ", has_node("DeployButton"))
    
    print("DEBUG: About to call load_soldiers()")
    load_soldiers()
    print("DEBUG: Finished load_soldiers(), have ", soldier_resources.size(), " soldiers")
    
    print("DEBUG: About to call populate_soldier_cards()")
    populate_soldier_cards()
    print("DEBUG: Finished populate_soldier_cards()")
    
    deploy_button.pressed.connect(_on_deploy_pressed)
    deploy_button.disabled = true

func load_soldiers():
    print("DEBUG: load_soldiers() started")
    soldier_resources.clear()
    soldier_resources.append(preload("res://Soldier_Marine1.tres"))
    soldier_resources.append(preload("res://Soldier_Marine2.tres"))
    soldier_resources.append(preload("res://Soldier_Marine3.tres"))
    soldier_resources.append(preload("res://Soldier_Marine4.tres"))
    soldier_resources.append(preload("res://Soldier_Marine5.tres"))
    print("DEBUG: load_soldiers() finished")

func populate_soldier_cards():
    print("DEBUG: populate_soldier_cards() started")
    for child in soldier_container.get_children():
        child.queue_free()
    
    print("DEBUG: Cleared existing children, now creating cards...")
    for i in range(soldier_resources.size()):
        var soldier = soldier_resources[i]
        print("DEBUG: Processing soldier ", i, ": ", soldier.soldier_name)
        var card_scene = preload("res://SoldierCard.tscn")
        if card_scene:
            print("DEBUG: SoldierCard.tscn preloaded successfully")
            var card = card_scene.instantiate()
            print("DEBUG: Card instantiated")
            card.setup(soldier)
            print("DEBUG: Card setup complete")
            soldier_container.add_child(card)
            print("DEBUG: Card added to container")
        else:
            print("DEBUG: ERROR - Could not preload SoldierCard.tscn")
    print("DEBUG: populate_soldier_cards() finished")