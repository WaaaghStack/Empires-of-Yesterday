class_name OperatorRosterCard
extends PanelContainer

const OrderTypeLib := preload("res://OrderType.gd")

signal card_pressed(slot_index: int)

var slot_index: int = -1
var _unit: SoldierUnit = null
var _resource: SoldierResource = null

@onready var portrait_rect: ColorRect = $Margin/HBox/Portrait/PortraitRect
@onready var portrait_image: TextureRect = $Margin/HBox/Portrait/PortraitImage
@onready var initials_label: Label = $Margin/HBox/Portrait/Initials
@onready var name_label: Label = $Margin/HBox/Info/Name
@onready var class_label: Label = $Margin/HBox/Info/Class
@onready var stats_label: Label = $Margin/HBox/Info/Stats
@onready var health_bar: ProgressBar = $Margin/HBox/Info/HealthBar
@onready var order_label: Label = $Margin/HBox/Info/Order

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP

func bind_unit(unit: SoldierUnit, index: int) -> void:
	_unit = unit
	_resource = unit.source_resource if unit else null
	slot_index = index
	_queue_refresh()

func bind_resource(resource: SoldierResource, index: int) -> void:
	_unit = null
	_resource = resource
	slot_index = index
	_queue_refresh()

func _queue_refresh(selected: bool = false) -> void:
	if is_node_ready() and _ensure_nodes():
		refresh(selected)
	else:
		call_deferred("refresh", selected)

func _ensure_nodes() -> bool:
	if not is_inside_tree():
		return false
	if portrait_rect == null:
		portrait_rect = $Margin/HBox/Portrait/PortraitRect
		portrait_image = $Margin/HBox/Portrait/PortraitImage
		initials_label = $Margin/HBox/Portrait/Initials
		name_label = $Margin/HBox/Info/Name
		class_label = $Margin/HBox/Info/Class
		stats_label = $Margin/HBox/Info/Stats
		health_bar = $Margin/HBox/Info/HealthBar
		order_label = $Margin/HBox/Info/Order
	return portrait_rect != null and health_bar != null

func refresh(selected: bool = false) -> void:
	if not _ensure_nodes():
		return
	if not _resource and _unit and _unit.source_resource:
		_resource = _unit.source_resource
	if not _resource and not _unit:
		visible = false
		return
	visible = true
	var marine_class: SoldierResource.MarineClass = _resource.marine_class if _resource else _unit.marine_class
	var display_name: String = _resource.soldier_name if _resource else _unit.soldier_name
	_apply_portrait(marine_class, display_name)
	name_label.text = display_name
	class_label.text = GameTheme.class_name_text(marine_class).to_upper()
	if _unit and _unit.is_alive:
		health_bar.max_value = _unit.max_health
		health_bar.value = _unit.current_health
		stats_label.text = _resource.get_stats_line() if _resource else ""
		if _unit.is_extracted:
			order_label.text = "Extracted"
			modulate = Color(0.65, 0.9, 1.0, 0.9)
		else:
			order_label.text = _unit_order_text(_unit)
			modulate = Color.WHITE
	elif _resource:
		if _resource.is_kia:
			health_bar.max_value = _resource.health
			health_bar.value = 0
			stats_label.text = _resource.get_stats_line()
			order_label.text = "KIA"
			modulate = Color(0.45, 0.45, 0.45, 0.75)
		else:
			health_bar.max_value = _resource.health
			health_bar.value = _resource.get_deploy_hp()
			stats_label.text = _resource.get_stats_line()
			order_label.text = "Standby" if not _resource.is_injured else "Injured"
			modulate = Color.WHITE
	else:
		health_bar.max_value = 1
		health_bar.value = 0
		stats_label.text = ""
		order_label.text = "KIA"
		modulate = Color(0.45, 0.45, 0.45, 0.75)
	_update_health_color()
	_apply_selection_style(selected)

func _apply_portrait(marine_class: SoldierResource.MarineClass, display_name: String) -> void:
	var portrait_tex: Texture2D = null
	if _resource and _resource.portrait:
		portrait_tex = _resource.portrait
	elif _unit and _unit.portrait:
		portrait_tex = _unit.portrait
	if portrait_tex and portrait_image:
		portrait_image.texture = portrait_tex
		portrait_image.visible = true
		portrait_rect.visible = false
		initials_label.visible = false
		return
	if portrait_image:
		portrait_image.texture = null
		portrait_image.visible = false
	portrait_rect.visible = true
	initials_label.visible = true
	portrait_rect.color = GameTheme.class_color(marine_class).darkened(0.35)
	initials_label.text = _initials(display_name)

func _unit_order_text(unit: SoldierUnit) -> String:
	if unit.order_label and unit.order_label.text != "":
		return unit.order_label.text
	return OrderTypeLib.get_label(unit.current_order)

func _initials(full_name: String) -> String:
	var parts: PackedStringArray = full_name.split(" ", false)
	if parts.size() >= 2:
		return (parts[0].left(1) + parts[1].left(1)).to_upper()
	return full_name.left(2).to_upper()

func _update_health_color() -> void:
	if not health_bar or health_bar.max_value <= 0.0:
		return
	var percent := health_bar.value / health_bar.max_value
	if percent > 0.6:
		health_bar.modulate = GameTheme.ACCENT_SUCCESS
	elif percent > 0.3:
		health_bar.modulate = GameTheme.ACCENT_WARN
	else:
		health_bar.modulate = GameTheme.ACCENT_DANGER

func _apply_selection_style(selected: bool) -> void:
	if selected:
		add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.12, 0.18, 0.28, 0.98), GameTheme.ACCENT, 10))
	else:
		add_theme_stylebox_override("panel", GameTheme.make_panel_style())

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_pressed.emit(slot_index)
		accept_event()
