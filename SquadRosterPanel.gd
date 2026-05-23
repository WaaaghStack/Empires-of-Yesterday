class_name SquadRosterPanel
extends VBoxContainer

signal roster_card_pressed(slot_index: int)
signal squad_header_pressed(squad_id: String)

const OrderTypeLib := preload("res://OrderType.gd")
const SquadsManagerLib := preload("res://SquadsManager.gd")

@onready var roster_list: VBoxContainer = $Scroll/RosterList

var _squad_headers: Dictionary = {}


func _ready() -> void:
	var scroll := get_node_or_null("Scroll") as ScrollContainer
	if scroll:
		GameTheme.configure_scroll(scroll, 120.0)
	clear_roster()

func clear_roster() -> void:
	if not roster_list:
		return
	for child in roster_list.get_children():
		child.queue_free()
	_squad_headers.clear()

func show_resources(resources: Array[SoldierResource]) -> void:
	if not roster_list:
		return
	clear_roster()
	var by_squad: Dictionary = {}
	for i in range(resources.size()):
		var res: SoldierResource = resources[i]
		var sid: String = res.squad_id if res.squad_id != "" else RunState.get_squad_id_for_index(i)
		if not by_squad.has(sid):
			by_squad[sid] = []
		by_squad[sid].append(res)
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		_add_squad_header(squad_id, by_squad.get(squad_id, []), true)

func bind_units(units: Array[SoldierUnit]) -> void:
	if not roster_list:
		return
	clear_roster()
	var by_squad: Dictionary = {}
	for i in range(units.size()):
		var unit: SoldierUnit = units[i]
		var sid: String = unit.squad_id if unit.squad_id != "" else "alpha"
		if not by_squad.has(sid):
			by_squad[sid] = []
		by_squad[sid].append({"unit": unit, "index": i})
	for squad_id in SquadsManagerLib.SQUAD_IDS:
		_add_squad_header(squad_id, by_squad.get(squad_id, []), false)

func _add_squad_header(squad_id: String, entries: Array, resources_mode: bool) -> void:
	var living := 0
	var total := entries.size()
	var hp_sum := 0
	var hp_max := 0
	var doctrine := OrderTypeLib.get_label(OrderTypeLib.Type.CLEAR)
	for entry in entries:
		if resources_mode:
			var res: SoldierResource = entry
			if res and not res.is_kia:
				living += 1
				hp_sum += res.get_deploy_hp()
				hp_max += res.health
		else:
			var unit: SoldierUnit = entry.get("unit")
			if unit and unit.is_alive:
				living += 1
				hp_sum += unit.current_health
				hp_max += unit.max_health
				if unit.current_order != OrderTypeLib.Type.NONE:
					doctrine = OrderTypeLib.get_label(unit.current_order)
	var header := Button.new()
	header.text = "%s  %d/%d  HP %d%%  |  %s" % [
		GameTheme.squad_label(squad_id),
		living,
		maxi(total, 4),
		int((float(hp_sum) / float(maxi(hp_max, 1))) * 100.0),
		doctrine,
	]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_color_override("font_color", GameTheme.squad_color(squad_id))
	header.pressed.connect(_on_squad_header.bind(squad_id))
	roster_list.add_child(header)
	_squad_headers[squad_id] = header

func refresh(selected_indices: Array[int] = []) -> void:
	var selected_squads: Dictionary = {}
	for idx in selected_indices:
		if idx >= 0 and idx < RunState.ROSTER_SIZE:
			selected_squads[RunState.get_squad_id_for_index(idx)] = true
	for squad_id in _squad_headers.keys():
		var header: Button = _squad_headers[squad_id]
		if not is_instance_valid(header):
			continue
		header.modulate = Color(1.2, 1.2, 1.2, 1.0) if selected_squads.has(squad_id) else Color.WHITE

func _on_squad_header(squad_id: String) -> void:
	squad_header_pressed.emit(squad_id)

func _on_card_pressed(slot_index: int) -> void:
	roster_card_pressed.emit(slot_index)
