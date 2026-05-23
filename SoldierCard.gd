# SoldierCard.gd
class_name SoldierCard
extends PanelContainer

signal selected(soldier: SoldierResource)
signal deselected(soldier: SoldierResource)

var soldier_data: SoldierResource
var is_selected := false

var portrait: TextureRect
var name_label: Label
var stats_label: Label
var checkbox: CheckBox

func _ready():
    portrait = $MarginContainer/VBoxContainer/Portrait
    name_label = $MarginContainer/VBoxContainer/Name
    stats_label = $MarginContainer/VBoxContainer/Stats
    checkbox = $MarginContainer/VBoxContainer/CheckBox
    
    if checkbox:
        checkbox.toggled.connect(_on_checkbox_toggled)

func setup(soldier: SoldierResource):
    soldier_data = soldier
    if portrait and soldier.portrait:
        portrait.texture = soldier.portrait
    if name_label:
        name_label.text = soldier.soldier_name
    if stats_label:
        stats_label.text = "HP: %d  DMG: %d" % [soldier.health, soldier.damage]

func _on_checkbox_toggled(toggled_on: bool):
    is_selected = toggled_on
    if toggled_on:
        selected.emit(soldier_data)
    else:
        deselected.emit(soldier_data)