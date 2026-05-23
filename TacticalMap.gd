# TacticalMap.gd
extends Control

var selected_soldiers: Array[SoldierResource] = []
var deployed_soldiers: Dictionary = {}  # slot_index -> soldier
var enemies: Array = []

var game_active := false

@onready var map_grid: GridContainer = $MapGrid
@onready var start_button: Button = $StartButton
@onready var back_button: Button = $BackButton

func _ready():
    start_button.pressed.connect(_on_start_pressed)
    back_button.pressed.connect(_on_back_pressed)
    
    if get_tree().has_meta("selected_soldiers"):
        selected_soldiers = get_tree().get_meta("selected_soldiers")
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

func _on_start_pressed():
    if deployed_soldiers.size() == 0:
        print("Deploy at least one soldier first!")
        return
    
    game_active = true
    start_button.disabled = true
    print("Mission started!")
    spawn_initial_enemies()
    start_combat_loop()

func spawn_initial_enemies():
    print("Spawning enemies...")
    for i in range(3):
        var enemy = {
            "name": "Enemy " + str(i + 1),
            "health": 50,
            "damage": 15,
            "alive": true
        }
        enemies.append(enemy)
        print("Spawned: ", enemy.name)
    
    # Start enemy attack timer
    var timer = Timer.new()
    timer.wait_time = 2.0
    timer.one_shot = false
    timer.timeout.connect(_enemy_attack_phase)
    add_child(timer)
    timer.start()

func start_combat_loop():
    print("Combat loop started!")
    # Soldiers attack first
    _soldier_attack_phase()

func _soldier_attack_phase():
    if not game_active:
        return
    
    print("--- Soldier Attack Phase ---")
    var alive_enemies = enemies.filter(func(e): return e.alive)
    
    if alive_enemies.size() == 0:
        _victory()
        return
    
    for slot_index in deployed_soldiers:
        var soldier = deployed_soldiers[slot_index]
        if alive_enemies.size() > 0:
            var target = alive_enemies[0]
            target.health -= soldier.damage
            print(soldier.soldier_name, " attacks ", target.name, " for ", soldier.damage, " damage!")
            
            if target.health <= 0:
                target.alive = false
                print(target.name, " defeated!")
    
    # Check if all enemies dead
    alive_enemies = enemies.filter(func(e): return e.alive)
    if alive_enemies.size() == 0:
        _victory()

func _enemy_attack_phase():
    if not game_active:
        return
    
    print("--- Enemy Attack Phase ---")
    var alive_soldiers = []
    for slot_index in deployed_soldiers:
        alive_soldiers.append(deployed_soldiers[slot_index])
    
    if alive_soldiers.size() == 0:
        _defeat()
        return
    
    var alive_enemies = enemies.filter(func(e): return e.alive)
    for enemy in alive_enemies:
        if alive_soldiers.size() > 0:
            var target = alive_soldiers[0]
            # Find which slot this soldier is in
            for slot_index in deployed_soldiers:
                if deployed_soldiers[slot_index] == target:
                    # Soldier takes damage
                    print(enemy.name, " attacks ", target.soldier_name, " for ", enemy.damage, " damage!")
                    # Note: In a full implementation, we'd track soldier health
                    break
    
    # Continue combat
    _soldier_attack_phase()

func _victory():
    game_active = false
    print("VICTORY! All enemies defeated!")

func _defeat():
    game_active = false
    print("DEFEAT! All soldiers lost!")