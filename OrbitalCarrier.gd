# OrbitalCarrier.gd — pre-mission loadout, traits, drop zones, and squad stances.
extends Control

const SoldierCardScene := preload("res://SoldierCard.tscn")
const LoadoutPresetLib := preload("res://LoadoutPreset.gd")

const TRAIT_IDS: Array[String] = ["Steady", "Reckless", "Hive-Hater", "Veteran", "Ghost"]
const STANCE_IDS: Array[String] = ["Aggressive", "Balanced", "Cautious"]
const DROP_SECTORS: Array[String] = ["north", "south", "east", "west"]

var _squads: Array = [[], [], []]
var _squad_presets: Array[String] = ["assault_std", "support_std", "marksman_std"]
var _squad_stances: Array[String] = ["Balanced", "Balanced", "Balanced"]
var _squad_drop_sectors: Array[String] = ["north", "south", "east"]
var _operator_traits: Array = [[], [], [], [], [], [], [], [], [], [], [], []]
var _mutators_enabled: Dictionary = {
	"quiet_deck": false,
	"accelerated_swarm": false,
}
var _use_daily_seed := false

@onready var squad_scroll: ScrollContainer = $MainPanel/VBox/SquadScroll
@onready var squad_container: VBoxContainer = $MainPanel/VBox/SquadScroll/SquadContainer
@onready var deploy_button: Button = $MainPanel/VBox/DeployButton
@onready var subtitle_label: Label = $MainPanel/VBox/Header/Subtitle
@onready var tokens_label: Label = $MainPanel/VBox/Header/TokensLabel
@onready var seed_input: LineEdit = $MainPanel/VBox/SeedRow/SeedInput
@onready var reroll_all_button: Button = $MainPanel/VBox/RerollRow/RerollAllButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.configure_scroll(squad_scroll, 380.0)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	_use_daily_seed = get_tree().has_meta("daily_seed_run")
	if _use_daily_seed:
		get_tree().remove_meta("daily_seed_run")
	_generate_all_squads()
	_refresh_ui()
	deploy_button.pressed.connect(_on_deploy_pressed)
	reroll_all_button.pressed.connect(_on_reroll_all_pressed)
	$BackButton.pressed.connect(_on_back_pressed)
	$QuitButton.pressed.connect(_on_quit_pressed)
	tokens_label.text = "Carrier Biomass: %d  |  Tokens: %d" % [
		SaveManager.carrier_biomass,
		SaveManager.command_tokens,
	]
	if _use_daily_seed:
		var daily_seed: int = RunState.get_daily_seed()
		subtitle_label.text = "Daily planet reclamation — seed %d" % daily_seed
		subtitle_label.modulate = GameTheme.ACCENT
		seed_input.text = str(daily_seed)
		seed_input.editable = false
	else:
		subtitle_label.text = "Orbital Carrier — assign presets, pilot traits, drop sectors, and squad stances."
		subtitle_label.modulate = GameTheme.ACCENT_SUCCESS


func _generate_all_squads() -> void:
	var used_names: Dictionary = {}
	for squad_idx in range(RunState.SQUAD_COUNT):
		var squad_id: String = RunState.SQUAD_IDS[squad_idx]
		_squads[squad_idx] = RunState.generate_squad(squad_id, used_names)
		_init_squad_traits(squad_idx)


func _init_squad_traits(squad_idx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for slot in range(RunState.OPERATORS_PER_SQUAD):
		var global_idx: int = squad_idx * RunState.OPERATORS_PER_SQUAD + slot
		_operator_traits[global_idx] = TRAIT_IDS[rng.randi() % TRAIT_IDS.size()]


func _collect_names_excluding_squad(exclude_idx: int) -> Dictionary:
	var used: Dictionary = {}
	for squad_idx in range(_squads.size()):
		if squad_idx == exclude_idx:
			continue
		for op in _squads[squad_idx]:
			used[op.soldier_name] = true
	return used


func _reroll_squad(squad_idx: int) -> void:
	var used_names: Dictionary = _collect_names_excluding_squad(squad_idx)
	var squad_id: String = RunState.SQUAD_IDS[squad_idx]
	_squads[squad_idx] = RunState.generate_squad(squad_id, used_names)
	_init_squad_traits(squad_idx)
	_refresh_ui()


func _refresh_ui() -> void:
	for child in squad_container.get_children():
		child.queue_free()
	_build_mutator_row()
	for squad_idx in range(RunState.SQUAD_COUNT):
		_build_squad_section(squad_idx)


func _build_mutator_row() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	squad_container.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Run mutators (optional)"
	title.add_theme_color_override("font_color", GameTheme.TEXT_MUTED)
	vbox.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	for mutator_id in RunState.MUTATOR_IDS:
		var check := CheckBox.new()
		check.text = mutator_id.replace("_", " ").capitalize()
		check.button_pressed = bool(_mutators_enabled.get(mutator_id, false))
		check.toggled.connect(_on_mutator_toggled.bind(mutator_id))
		row.add_child(check)


func _on_mutator_toggled(mutator_id: String, enabled: bool) -> void:
	_mutators_enabled[mutator_id] = enabled


func _build_squad_section(squad_idx: int) -> void:
	var squad_id: String = RunState.SQUAD_IDS[squad_idx]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	squad_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "SQUAD %s" % GameTheme.squad_label(squad_id).to_upper()
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", GameTheme.squad_color(squad_id))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var reroll_btn := Button.new()
	reroll_btn.text = "Reroll"
	reroll_btn.pressed.connect(_on_reroll_squad_pressed.bind(squad_idx))
	header.add_child(reroll_btn)

	var config_row := HBoxContainer.new()
	config_row.add_theme_constant_override("separation", 10)
	vbox.add_child(config_row)

	var preset_box := _make_option_row("Loadout", _preset_labels_for_squad(squad_idx), _squad_presets[squad_idx])
	preset_box.item_selected.connect(_on_preset_selected.bind(squad_idx))
	config_row.add_child(preset_box)

	var stance_box := _make_option_row("Stance", STANCE_IDS, _squad_stances[squad_idx])
	stance_box.item_selected.connect(_on_stance_selected.bind(squad_idx))
	config_row.add_child(stance_box)

	var drop_box := _make_option_row("Drop Zone", DROP_SECTORS.map(func(s): return s.capitalize()), _squad_drop_sectors[squad_idx].capitalize())
	drop_box.item_selected.connect(_on_drop_selected.bind(squad_idx))
	config_row.add_child(drop_box)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	for slot in range(_squads[squad_idx].size()):
		var op = _squads[squad_idx][slot]
		var global_idx: int = squad_idx * RunState.OPERATORS_PER_SQUAD + slot
		var trait_box := OptionButton.new()
		trait_box.add_item("Trait: %s" % _operator_traits[global_idx])
		for trait_id in TRAIT_IDS:
			trait_box.add_item(trait_id)
		trait_box.select(TRAIT_IDS.find(_operator_traits[global_idx]) + 1)
		trait_box.item_selected.connect(_on_trait_selected.bind(global_idx))
		var card_wrap := VBoxContainer.new()
		card_wrap.add_child(trait_box)
		var card: SoldierCard = SoldierCardScene.instantiate()
		card_wrap.add_child(card)
		card.setup_display_only(op, true)
		grid.add_child(card_wrap)


func _make_option_row(label_text: String, options: Array, current: String) -> OptionButton:
	var box := OptionButton.new()
	box.text = label_text
	for opt in options:
		box.add_item(str(opt))
	var idx := options.find(current)
	if idx < 0:
		idx = 0
	box.select(idx)
	return box


func _preset_labels_for_squad(squad_idx: int) -> Array[String]:
	var role := "assault"
	var current := LoadoutPresetLib.get_by_id(_squad_presets[squad_idx])
	if current:
		role = current.archetype
	var labels: Array[String] = []
	for preset in LoadoutPresetLib.presets_for_archetype(role):
		labels.append(preset.display_name)
	return labels


func _on_preset_selected(squad_idx: int, index: int) -> void:
	var labels := _preset_labels_for_squad(squad_idx)
	if index < 0 or index >= labels.size():
		return
	var label: String = labels[index]
	var role := "assault"
	var current := LoadoutPresetLib.get_by_id(_squad_presets[squad_idx])
	if current:
		role = current.archetype
	for preset in LoadoutPresetLib.presets_for_archetype(role):
		if preset.display_name == label:
			_squad_presets[squad_idx] = preset.id
			break


func _on_stance_selected(squad_idx: int, index: int) -> void:
	if index >= 0 and index < STANCE_IDS.size():
		_squad_stances[squad_idx] = STANCE_IDS[index]


func _on_drop_selected(squad_idx: int, index: int) -> void:
	if index >= 0 and index < DROP_SECTORS.size():
		_squad_drop_sectors[squad_idx] = DROP_SECTORS[index]


func _on_trait_selected(global_idx: int, index: int) -> void:
	if index <= 0:
		return
	var trait_idx: int = index - 1
	if trait_idx >= 0 and trait_idx < TRAIT_IDS.size():
		_operator_traits[global_idx] = TRAIT_IDS[trait_idx]


func _on_reroll_squad_pressed(squad_idx: int) -> void:
	_reroll_squad(squad_idx)


func _on_reroll_all_pressed() -> void:
	_generate_all_squads()
	_refresh_ui()


func _on_deploy_pressed() -> void:
	var run_squad: Array[SoldierResource] = []
	for squad_idx in range(_squads.size()):
		var preset := LoadoutPresetLib.get_by_id(_squad_presets[squad_idx])
		for slot in range(_squads[squad_idx].size()):
			var op: SoldierResource = _squads[squad_idx][slot].duplicate_for_deploy()
			if preset:
				LoadoutPresetLib.apply_to_resource(op, preset)
			var global_idx: int = squad_idx * RunState.OPERATORS_PER_SQUAD + slot
			op.trait_id = str(_operator_traits[global_idx])
			SoldierResource.apply_trait_passive(op)
			run_squad.append(op)
	if run_squad.size() < RunState.ROSTER_SIZE:
		return
	RunState.start_planet_run(run_squad, _read_seed_override(), _use_daily_seed)
	for mutator_id in RunState.MUTATOR_IDS:
		RunState.set_mutator(mutator_id, bool(_mutators_enabled.get(mutator_id, false)))
	for squad_idx in range(RunState.SQUAD_COUNT):
		var squad_id: String = RunState.SQUAD_IDS[squad_idx]
		RunState.set_squad_stance(squad_id, _squad_stances[squad_idx].to_lower())
		RunState.set_squad_loadout_preset(squad_id, _squad_presets[squad_idx])
		RunState.deploy_assignments[squad_id] = _squad_drop_sectors[squad_idx]
	RunLog.note_run_seed(RunState.run_seed)
	RunLog.info(
		"Planet run started — squads=%d daily=%s seed=%d"
		% [RunState.SQUAD_COUNT, str(_use_daily_seed), RunState.run_seed]
	)
	get_tree().change_scene_to_file("res://PlanetMission.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _read_seed_override() -> int:
	if not seed_input or seed_input.text.strip_edges().is_empty():
		return -1
	var text := seed_input.text.strip_edges()
	if text.is_valid_int():
		return text.to_int()
	return hash(text) & 0x7FFFFFFF
