# TacticalMap.gd
extends Control

var selected_soldiers: Array[SoldierResource] = []
var deployed_soldiers: Dictionary = {}
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
        slot_button.text = soldier.soldier_name + " (" + str(soldier.health) + ")"
        slot_button.disabled = true

func _on_start_pressed():
    if deployed_soldiers.size() == 0:
        print("Deploy at least one soldier first!")
        return
    
    game_active = true
    start_button.disabled = true
    print("=== MISSION STARTED ===")
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
    
    var timer = Timer.new()
    timer.wait_time = 2.5
    timer.one_shot = false
    timer.timeout.connect(_enemy_attack_phase)
    add_child(timer)
    timer.start()

func start_combat_loop():
    print("Combat started!")
    _soldier_attack_phase()

func _soldier_attack_phase():
    if not game_active:
        return
    
    print("\n--- SOLDIER ATTACK PHASE ---")
    var alive_enemies = enemies.filter(func(e): return e.alive)
    
    if alive_enemies.size() == 0:
        _victory()
        return
    
    # Target weakest enemy
    alive_enemies.sort_custom(func(a, b): return a.health < b.health)
    var target = alive_enemies[0]
    
    for slot_index in deployed_soldiers:
        var soldier = deployed_soldiers[slot_index]
        if target.alive:
            target.health -= soldier.damage
            print(soldier.soldier_name, " attacks ", target.name, " for ", soldier.damage, " damage! (Enemy HP: ", target.health, ")")
            
            if target.health <= 0:
                target.alive = false
                print(target.name, " DEFEATED!")
    
    alive_enemies = enemies.filter(func(e): return e.alive)
    if alive_enemies.size() == 0:
        _victory()
        return
    
    await get_tree().create_timer(1.0).timeout
    _enemy_attack_phase()

func _enemy_attack_phase():
    if not game_active:
        return
    
    print("\n--- ENEMY ATTACK PHASE ---")
    var alive_soldiers = []
    for slot_index in deployed_soldiers:
        if deployed_soldiers[slot_index].health > 0:
            alive_soldiers.append({"slot": slot_index, "soldier": deployed_soldiers[slot_index]})
    
    if alive_soldiers.size() == 0:
        _defeat()
        return
    
    var alive_enemies = enemies.filter(func(e): return e.alive)
    for enemy in alive_enemies:
        if alive_soldiers.size() > 0:
            var target_data = alive_soldiers[0]
            var target_slot = target_data.slot
            var target_soldier = target_data.soldier
            
            target_soldier.health -= enemy.damage
            var button = target_soldier.button if target_soldier.has_method("get") else null
            if button:
                button.text = target_soldier.soldier_name + " (" + str(target_soldier.health) + ")"
            
            print(enemy.name, " attacks ", target_soldier.soldier_name, " for ", enemy.damage, " damage! (Soldier HP: ", target_soldier.health, ")")
            
            if target_soldier.health <= 0:
                print(target_soldier.soldier_name, " DIED!")
    
    await get_tree().create_timer(1.5).timeout
    _soldier_attack_phase()

func _victory():
    game_active = false
    print("\n=== VICTORY! ===")
    print("All enemies defeated!")

func _defeat():
    game_active = false
    print("\n=== DEFEAT ===")
    print("All soldiers lost!")

func _on_back_pressed():
    get_tree().change_scene_to_file("res://SquadSelection.tscn")