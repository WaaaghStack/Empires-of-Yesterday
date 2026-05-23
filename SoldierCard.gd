# SoldierCard.gd
class_name SoldierCard
extends PanelContainer

signal selected(soldier: SoldierResource)
signal deselected(soldier: SoldierResource)

var soldier_data: SoldierResource
var is_selected := false

@onready var portrait = $MarginContainer/VBoxContainer/Portrait
@onready var name_label = $MarginContainer/VBoxContainer/Name
@onready var stats_label = $MarginContainer/VBoxContainer/Stats
@onready var checkbox = $MarginContainer/VBoxContainer/CheckBox

func setup(soldier: SoldierResource):
    soldier_data = soldier
    if soldier.portrait:
        portrait.texture = soldier.portrait
    name_label.text = soldier.soldier_name
    stats_label.text = "HP: %d  DMG: %d" % [soldier.health, soldier.damage]

func _ready():
    checkbox.toggled.connect(_on_checkbox_toggled)

func _on_checkbox_toggled(toggled_on: bool):
    is_selected = toggled_on
    if toggled_on:
        selected.emit(soldier_data)
    else:
        deselected.emit(soldier_data)