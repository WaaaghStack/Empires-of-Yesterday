# TacticalMap.gd
extends Control

var selected_soldiers: Array[SoldierResource] = []

@onready var map_grid: GridContainer = $MapGrid
@onready var back_button: Button = $BackButton

func _ready():
    back_button.pressed.connect(_on_back_pressed)
    
    # Get selected soldiers from the previous scene
    if get_tree().has_meta("selected_soldiers"):
        selected_soldiers = get_tree().get_meta("selected_soldiers")
        print("TacticalMap: Received ", selected_soldiers.size(), " soldiers")
        spawn_soldiers()

func spawn_soldiers():
    # Clear any existing children
    for child in map_grid.get_children():
        child.queue_free()
    
    # Create a simple grid of deployment slots
    for i in range(12):  # 6x2 grid = 12 slots
        var slot = Button.new()
        slot.custom_minimum_size = Vector2(80, 80)
        slot.text = "Empty"
        slot.pressed.connect(_on_slot_pressed.bind(i, slot))
        map_grid.add_child(slot)
    
    print("TacticalMap: Created 12 deployment slots")

func _on_slot_pressed(slot_index: int, slot_button: Button):
    if selected_soldiers.size() > 0:
        var soldier = selected_soldiers.pop_front()
        slot_button.text = soldier.soldier_name
        slot_button.disabled = true
        print("Deployed ", soldier.soldier_name, " to slot ", slot_index)

func _on_back_pressed():
    get_tree().change_scene_to_file("res://SquadSelection.tscn")