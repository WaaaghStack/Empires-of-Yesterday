# TacticalMap.gd
extends Control

var selected_soldiers: Array[SoldierResource] = []
var deployed_soldiers: Dictionary = {}  # slot_index -> soldier
var enemies: Array = []

@onready var map_grid: GridContainer = $MapGrid
@onready var start_button: Button = $StartButton
@onready var back_button: Button = $BackButton

func _ready():
    start_button.pressed.connect(_on_start_pressed)
    back_button.pressed.connect(_on_back_pressed)
    
    if get_tree().has_meta("selected_soldiers"):
        selected_soldiers = get_tree().get_meta("selected_soldiers")
        print("TacticalMap: Received ", selected_soldiers.size(), " soldiers")
        spawn_deployment_slots()

func spawn_deployment_slots():
    for child in map_grid.get_children():
        child.queue_free()
    
    for i in range(12):
        var slot = Button.new()
        slot.custom_minimum_size = Vector2(80, 80)
        slot.text = "Empty"
        slot.pressed.connect(_on_slot_pressed.bind(i, slot))
        map_grid.add_child(slot)

func _on_slot_pressed(slot_index: int, slot_button: Button):
    if selected_soldiers.size() > 0 and not deployed_soldiers.has(slot_index):
        var soldier = selected_soldiers.pop_front()
        deployed_soldiers[slot_index] = soldier
        slot_button.text = soldier.soldier_name
        slot_button.disabled = true
        print("Deployed ", soldier.soldier_name, " to slot ", slot_index)

func _on_start_pressed():
    print("Mission started with ", deployed_soldiers.size(), " soldiers!")
    # TODO: Spawn enemies and start combat
    spawn_enemies()

func spawn_enemies():
    print("Spawning enemies...")
    # Simple enemy spawning - in a real game this would be more sophisticated
    for i in range(3):
        print("Enemy ", i, " spawned!")

func _on_back_pressed():
    get_tree().change_scene_to_file("res://SquadSelection.tscn")