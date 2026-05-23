extends Control

const HEAL_COST := 40
const HEAL_PERCENT := 0.25

@onready var hub_scroll: ScrollContainer = $MainPanel/VBox/HubScroll
@onready var op_label: Label = $MainPanel/VBox/OpLabel
@onready var credits_label: Label = $MainPanel/VBox/CreditsLabel
@onready var squad_list: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/SquadScroll/SquadList
@onready var heal_button: Button = $MainPanel/VBox/HubScroll/HubContent/Actions/HealButton
@onready var augment_panel: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/AugmentPanel
@onready var augment_list: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/AugmentPanel/AugmentList
@onready var augment_status: Label = $MainPanel/VBox/HubScroll/HubContent/AugmentPanel/AugmentStatus
@onready var intel_panel: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/IntelPanel
@onready var reveal_room_button: Button = $MainPanel/VBox/HubScroll/HubContent/IntelPanel/IntelButtons/RevealRoomButton
@onready var extract_hint_button: Button = $MainPanel/VBox/HubScroll/HubContent/IntelPanel/IntelButtons/ExtractHintButton
@onready var enemy_scan_button: Button = $MainPanel/VBox/HubScroll/HubContent/IntelPanel/IntelButtons/EnemyScanButton
@onready var recruit_panel: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/RecruitPanel
@onready var recruit_list: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/RecruitPanel/RecruitList
@onready var modifier_list: VBoxContainer = $MainPanel/VBox/HubScroll/HubContent/ModifierPanel/ModifierList
@onready var launch_button: Button = $MainPanel/VBox/LaunchButton
@onready var abort_button: Button = $MainPanel/VBox/AbortButton

var _modifier_options: Array[OpModifier] = []
var _augment_options: Array[RunAugment] = []
var _recruit_options: Array[SoldierResource] = []
var _recruit_slot_index: int = -1
var _selected_modifier: OpModifier = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.configure_scroll(hub_scroll, 420.0)
	GameTheme.configure_scroll($MainPanel/VBox/HubScroll/HubContent/SquadScroll, 96.0)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	heal_button.pressed.connect(_on_heal_pressed)
	reveal_room_button.pressed.connect(_on_intel_pressed.bind("reveal_room"))
	extract_hint_button.pressed.connect(_on_intel_pressed.bind("extraction_hint"))
	enemy_scan_button.pressed.connect(_on_intel_pressed.bind("enemy_scan"))
	launch_button.pressed.connect(_on_launch_pressed)
	abort_button.pressed.connect(_on_abort_pressed)
	_rng.randomize()
	_modifier_options = OpModifier.pick_random_three(_rng)
	_build_modifier_buttons()
	_setup_augment_panel()
	_setup_recruit_panel()
	_refresh()
	RunLog.info(
		"Between-op hub — op %d/%d credits=%d"
		% [RunState.op_index, RunState.ops_per_run, RunState.run_credits]
	)


func _setup_augment_panel() -> void:
	for child in augment_list.get_children():
		child.queue_free()
	if RunState.can_pick_run_augment():
		_augment_options = RunAugment.pick_random_two(_rng)
		augment_panel.visible = true
		for aug in _augment_options:
			var btn := Button.new()
			btn.toggle_mode = true
			btn.text = "%s — %s" % [aug.display_name, aug.description]
			btn.pressed.connect(_on_augment_selected.bind(aug, btn))
			augment_list.add_child(btn)
		augment_status.visible = false
	elif RunState.active_run_augment:
		augment_panel.visible = true
		augment_status.text = "Active augment: %s" % RunState.active_run_augment.display_name
		augment_status.visible = true
	else:
		augment_panel.visible = false


func _setup_recruit_panel() -> void:
	for child in recruit_list.get_children():
		child.queue_free()
	_recruit_options.clear()
	_recruit_slot_index = -1
	var kia_indices := RunState.kia_squad_indices()
	if kia_indices.is_empty():
		recruit_panel.visible = false
		return
	_recruit_slot_index = kia_indices[0]
	_recruit_options = RunState.generate_kia_replacement_draft()
	recruit_panel.visible = true
	for rookie in _recruit_options:
		var btn := Button.new()
		btn.text = "%s (%s) — %s · %d credits" % [
			rookie.soldier_name,
			GameTheme.class_name_text(rookie.marine_class),
			rookie.get_stats_line(),
			RunState.RECRUIT_COST,
		]
		btn.pressed.connect(_on_recruit_selected.bind(rookie))
		recruit_list.add_child(btn)


func _refresh() -> void:
	op_label.text = "Next operation: %d / %d" % [RunState.op_index, RunState.ops_per_run]
	credits_label.text = "Run credits: %d" % RunState.run_credits
	var heal_line := "Heal squad +25%% HP (%d credits)" % HEAL_COST
	if RunState.has_run_augment("docs_kit"):
		heal_line += " · Doc's Kit active"
	heal_button.text = heal_line
	heal_button.disabled = RunState.run_credits < HEAL_COST or RunState.is_squad_wiped()
	for child in squad_list.get_children():
		child.queue_free()
	for member in RunState.squad:
		var row := Label.new()
		if member.is_kia:
			row.text = "%s — KIA" % member.soldier_name
			row.modulate = GameTheme.ACCENT_DANGER
		else:
			row.text = "%s — HP %d / %d" % [member.soldier_name, member.get_deploy_hp(), member.health]
			if member.is_injured:
				row.modulate = GameTheme.ACCENT_WARN
		squad_list.add_child(row)
	_refresh_intel_buttons()
	launch_button.disabled = RunState.is_squad_wiped()


func _refresh_intel_buttons() -> void:
	reveal_room_button.text = _intel_button_text("reveal_room", "Reveal sector")
	extract_hint_button.text = _intel_button_text("extraction_hint", "Evac hint")
	enemy_scan_button.text = _intel_button_text("enemy_scan", "Enemy scan")
	reveal_room_button.disabled = _intel_button_disabled("reveal_room")
	extract_hint_button.disabled = _intel_button_disabled("extraction_hint")
	enemy_scan_button.disabled = _intel_button_disabled("enemy_scan")


func _intel_button_text(intel_type: String, label: String) -> String:
	if RunState.has_pending_intel(intel_type):
		return "%s — PURCHASED" % label
	return "%s (%d cr)" % [label, RunState.get_intel_cost(intel_type)]


func _intel_button_disabled(intel_type: String) -> bool:
	if RunState.has_pending_intel(intel_type):
		return true
	return RunState.run_credits < RunState.get_intel_cost(intel_type)


func _build_modifier_buttons() -> void:
	for child in modifier_list.get_children():
		child.queue_free()
	for mod in _modifier_options:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s — %s" % [mod.display_name, mod.description]
		btn.pressed.connect(_on_modifier_selected.bind(mod, btn))
		modifier_list.add_child(btn)


func _on_augment_selected(aug: RunAugment, btn: Button) -> void:
	RunState.pick_run_augment(aug)
	RunLog.info("Hub augment selected: %s" % aug.display_name)
	for child in augment_list.get_children():
		if child is Button and child != btn:
			child.button_pressed = false
	btn.button_pressed = true
	_setup_augment_panel()
	_refresh_intel_buttons()


func _on_intel_pressed(intel_type: String) -> void:
	if RunState.purchase_intel(intel_type):
		RunLog.info("Hub intel purchased: %s" % intel_type)
		_refresh()


func _on_recruit_selected(rookie: SoldierResource) -> void:
	if _recruit_slot_index < 0:
		return
	if RunState.replace_kia_member(_recruit_slot_index, rookie):
		_setup_recruit_panel()
		_refresh()


func _on_modifier_selected(mod: OpModifier, btn: Button) -> void:
	_selected_modifier = mod
	RunState.active_modifier = mod
	SaveManager.discover_modifier(mod.id)
	for child in modifier_list.get_children():
		if child is Button and child != btn:
			child.button_pressed = false
	btn.button_pressed = true


func _on_heal_pressed() -> void:
	if RunState.heal_all_squad(HEAL_PERCENT, HEAL_COST):
		RunLog.info("Hub heal squad (-%d credits)" % HEAL_COST)
		_refresh()


func _on_launch_pressed() -> void:
	if _selected_modifier:
		RunState.active_modifier = _selected_modifier
		RunLog.info(
			"Hub launch op %d — modifier=%s"
			% [RunState.op_index, _selected_modifier.display_name if _selected_modifier else "none"]
		)
	get_tree().change_scene_to_file("res://TacticalMap.tscn")


func _on_abort_pressed() -> void:
	RunLog.info("Hub abort run — cleared_ops=%d" % RunState.cleared_ops)
	var summary: Dictionary = SaveManager.record_run_end(RunState.cleared_ops, false)
	if RunState.daily_seed_mode:
		var daily_stats: Dictionary = SaveManager.record_daily_run_end(
			RunState.cleared_ops,
			RunState.run_total_casualties,
			RunState.run_total_elapsed,
		)
		summary["daily_run"] = true
		summary["daily_stats"] = daily_stats
	RunState.end_run()
	get_tree().set_meta("run_summary", summary)
	get_tree().change_scene_to_file("res://RunSummary.tscn")
