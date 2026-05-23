# SoldierCard.gd
class_name SoldierCard
extends PanelContainer

signal selected(soldier: SoldierResource)
signal deselected(soldier: SoldierResource)

var soldier_data: SoldierResource
var is_selected := false

var portrait: ColorRect
var name_label: Label
var class_label: Label
var health_bar: ProgressBar
var stats_label: Label
var desc_label: Label
var select_button: Button

func _ready() -> void:
	portrait = $VBoxContainer/Portrait
	name_label = $VBoxContainer/Name
	class_label = $VBoxContainer/Class
	health_bar = $VBoxContainer/HealthBar
	stats_label = $VBoxContainer/Stats
	desc_label = $VBoxContainer/Description
	select_button = $VBoxContainer/SelectButton
	select_button.pressed.connect(_on_select_pressed)

func setup(soldier: SoldierResource) -> void:
	soldier_data = soldier
	if portrait:
		portrait.color = GameTheme.class_color(soldier.marine_class).darkened(0.35)
	if name_label:
		name_label.text = soldier.soldier_name
	if class_label:
		class_label.text = GameTheme.class_name_text(soldier.marine_class).to_upper()
		class_label.modulate = GameTheme.class_color(soldier.marine_class)
	if health_bar:
		health_bar.max_value = soldier.health
		health_bar.value = soldier.health
		health_bar.modulate = GameTheme.ACCENT_SUCCESS
	if stats_label:
		stats_label.text = "HP %d  ·  DMG %d  ·  RNG %.0f" % [soldier.health, soldier.damage, soldier.attack_range]
	if desc_label:
		desc_label.text = soldier.description
	_update_button()

func set_selected_state(now_selected: bool) -> void:
	is_selected = now_selected
	_update_button()

func _on_select_pressed() -> void:
	if is_selected:
		is_selected = false
		deselected.emit(soldier_data)
	else:
		selected.emit(soldier_data)

func _update_button() -> void:
	if not select_button:
		return
	select_button.text = "Selected" if is_selected else "Add to Squad"
	select_button.button_pressed = is_selected

func update_health(new_health: int) -> void:
	if health_bar:
		health_bar.value = new_health
		var health_percent := float(new_health) / health_bar.max_value
		if health_percent > 0.6:
			health_bar.modulate = GameTheme.ACCENT_SUCCESS
		elif health_percent > 0.3:
			health_bar.modulate = GameTheme.ACCENT_WARN
		else:
			health_bar.modulate = GameTheme.ACCENT_DANGER
