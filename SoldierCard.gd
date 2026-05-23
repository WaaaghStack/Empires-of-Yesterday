# SoldierCard.gd
class_name SoldierCard
extends PanelContainer

signal selected(soldier: SoldierResource)
signal deselected(soldier: SoldierResource)

var soldier_data: SoldierResource
var is_selected := false

var portrait: ColorRect
var name_label: Label
var health_bar: ProgressBar
var stats_label: Label
var checkbox: CheckBox

func _ready():
    portrait = $VBoxContainer/Portrait
    name_label = $VBoxContainer/Name
    health_bar = $VBoxContainer/HealthBar
    stats_label = $VBoxContainer/Stats
    checkbox = $VBoxContainer/CheckBox
    
    if checkbox:
        checkbox.toggled.connect(_on_checkbox_toggled)

func setup(soldier: SoldierResource):
    soldier_data = soldier
    if portrait:
        var intensity = clamp(soldier.damage / 50.0, 0.3, 0.8)
        portrait.color = Color(intensity, 0.05, 0.05, 1)
    if name_label:
        name_label.text = soldier.soldier_name
    if health_bar:
        health_bar.max_value = soldier.health
        health_bar.value = soldier.health
        health_bar.modulate = Color(0.2, 0.8, 0.2, 1)
    if stats_label:
        stats_label.text = "DMG: %d" % soldier.damage

func update_health(new_health: int):
    if health_bar:
        health_bar.value = new_health
        var health_percent = float(new_health) / health_bar.max_value
        if health_percent > 0.6:
            health_bar.modulate = Color(0.2, 0.8, 0.2, 1)
        elif health_percent > 0.3:
            health_bar.modulate = Color(0.8, 0.6, 0.1, 1)
        else:
            health_bar.modulate = Color(0.8, 0.2, 0.1, 1)

func _on_checkbox_toggled(toggled_on: bool):
    is_selected = toggled_on
    if toggled_on:
        selected.emit(soldier_data)
    else:
        deselected.emit(soldier_data)