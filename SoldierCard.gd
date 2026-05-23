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
        portrait.color = Color(0.3 + (soldier.damage / 100.0), 0.1, 0.1, 1)
    if name_label:
        name_label.text = soldier.soldier_name
    if health_bar:
        health_bar.max_value = soldier.health
        health_bar.value = soldier.health
    if stats_label:
        stats_label.text = "DMG: %d" % soldier.damage

func _on_checkbox_toggled(toggled_on: bool):
    is_selected = toggled_on
    if toggled_on:
        selected.emit(soldier_data)
    else:
        deselected.emit(soldier_data)