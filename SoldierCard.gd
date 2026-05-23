# SoldierCard.gd
class_name SoldierCard
extends PanelContainer

signal selected(soldier: SoldierResource)
signal deselected(soldier: SoldierResource)

const OrderTypeLib := preload("res://OrderType.gd")

var soldier_data: SoldierResource
var is_selected := false

var portrait: TextureRect
var portrait_fallback: ColorRect
var name_label: Label
var class_label: Label
var health_bar: ProgressBar
var stats_label: Label
var desc_label: Label
var default_order_option: OptionButton
var select_button: Button

const DEPLOY_ORDERS: Array[OrderTypeLib.Type] = [
	OrderTypeLib.Type.CLEAR,
	OrderTypeLib.Type.SEARCH_DESTROY,
	OrderTypeLib.Type.DEFEND,
	OrderTypeLib.Type.EXPLORE,
]

func _ready() -> void:
	_ensure_nodes()
	select_button.pressed.connect(_on_select_pressed)
	if default_order_option:
		default_order_option.item_selected.connect(_on_default_order_selected)

func _ensure_nodes() -> void:
	if name_label:
		return
	portrait = $VBoxContainer/PortraitFrame/Portrait
	portrait_fallback = $VBoxContainer/PortraitFrame/PortraitFallback
	name_label = $VBoxContainer/Name
	class_label = $VBoxContainer/Class
	health_bar = $VBoxContainer/HealthBar
	stats_label = $VBoxContainer/Stats
	desc_label = $VBoxContainer/Description
	default_order_option = $VBoxContainer/DefaultOrderOption
	select_button = $VBoxContainer/SelectButton

func setup(soldier: SoldierResource) -> void:
	soldier_data = soldier
	_ensure_nodes()
	_apply_portrait(soldier)
	if name_label:
		name_label.text = soldier.soldier_name
	if class_label:
		class_label.text = GameTheme.class_name_text(soldier.marine_class).to_upper()
		class_label.modulate = GameTheme.class_color(soldier.marine_class)
	if health_bar:
		health_bar.max_value = soldier.health
		health_bar.value = soldier.health
		health_bar.modulate = GameTheme.ACCENT_SUCCESS
	if desc_label:
		desc_label.text = soldier.description
		desc_label.visible = true
	if stats_label:
		stats_label.text = "%s · %s" % [
			GameTheme.class_name_text(soldier.marine_class),
			soldier.get_stats_line(),
		]
	_sync_default_order_option(soldier.default_order)
	_update_button()


func setup_display_only(soldier: SoldierResource, compact: bool = false) -> void:
	setup(soldier)
	if select_button:
		select_button.visible = false
	var order_label := get_node_or_null("VBoxContainer/DefaultOrderLabel")
	if order_label:
		order_label.visible = false
	if default_order_option:
		default_order_option.visible = false
	if compact:
		if desc_label:
			desc_label.visible = false
		custom_minimum_size = Vector2(200, 210)

func _sync_default_order_option(order: OrderTypeLib.Type) -> void:
	if not default_order_option:
		return
	for i in range(DEPLOY_ORDERS.size()):
		if DEPLOY_ORDERS[i] == order:
			default_order_option.select(i)
			return
	default_order_option.select(0)

func _on_default_order_selected(index: int) -> void:
	if not soldier_data or index < 0 or index >= DEPLOY_ORDERS.size():
		return
	soldier_data.default_order = DEPLOY_ORDERS[index]

func _apply_portrait(soldier: SoldierResource) -> void:
	if not portrait or not portrait_fallback:
		return
	if soldier.portrait:
		portrait.texture = soldier.portrait
		portrait.visible = true
		portrait_fallback.visible = false
	else:
		portrait.texture = null
		portrait.visible = false
		portrait_fallback.visible = true
		portrait_fallback.color = GameTheme.class_color(soldier.marine_class).darkened(0.35)

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
	if is_selected:
		select_button.text = "Selected"
	else:
		select_button.text = "Add to Squad"
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
