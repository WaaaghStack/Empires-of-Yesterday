extends Control

const BuildingDefinitionLib := preload("res://BuildingDefinition.gd")
const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")

@onready var node_list: ItemList = $MainHBox/NodePanel/NodeVBox/NodeList
@onready var build_list: VBoxContainer = $MainHBox/BuildPanel/BuildVBox/BuildScroll/BuildList
@onready var status_label: Label = $FooterPanel/StatusLabel


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	$MainHBox/NodePanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	$MainHBox/BuildPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	if not RunState.is_commander_run_active():
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")
	return
	$TopBar/BackButton.pressed.connect(_on_back_pressed)
	node_list.item_selected.connect(_on_node_selected)
	_populate_nodes()
	_build_catalog()
	_refresh_status()


func _populate_nodes() -> void:
	node_list.clear()
	for node in RunState.galaxy_state.nodes:
		if str(node.get("owner", "")) != GalaxyMapStateLib.OWNER_PLAYER:
			continue
		var label := "%s (%d/%d buildings)" % [
			node.get("display_name", ""),
			node.get("buildings", []).size(),
			node.get("building_slots", 0),
		]
		node_list.add_item(label)
		node_list.set_item_metadata(node_list.item_count - 1, str(node.get("id", "")))


func _selected_node_id() -> String:
	var idx := node_list.get_selected_items()
	if idx.is_empty():
		return ""
	return str(node_list.get_item_metadata(idx[0]))


func _build_catalog() -> void:
	for child in build_list.get_children():
		child.queue_free()
	for building_id in BuildingDefinitionLib.all_buildable_ids():
		var def: Dictionary = BuildingDefinitionLib.lookup(building_id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s — Bio %d, Alloy %d" % [
			def.get("name", building_id),
			def.get("cost_biomass", 0),
			def.get("cost_alloys", 0),
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.text = "Build"
		btn.pressed.connect(_on_build_pressed.bind(building_id))
		row.add_child(label)
		row.add_child(btn)
		build_list.add_child(row)


func _on_build_pressed(building_id: String) -> void:
	var node_id := _selected_node_id()
	if node_id.is_empty():
		status_label.text = "Select an owned planet first."
		return
	if RunState.try_commander_build(node_id, building_id):
		status_label.text = "Built %s on %s." % [building_id, node_id]
		_populate_nodes()
		_refresh_status()
	else:
		status_label.text = "Cannot build — check resources, slots, or ownership."


func _on_node_selected(_index: int) -> void:
	_refresh_status()


func _refresh_status() -> void:
	status_label.text = "Manpower %d  |  Biomass %d  |  Alloys %d" % [
		RunState.commander_resources.manpower if RunState.commander_resources else 0,
		RunState.commander_resources.biomass if RunState.commander_resources else 0,
		RunState.commander_resources.alloys if RunState.commander_resources else 0,
	]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://GalaxyMapScreen.tscn")
