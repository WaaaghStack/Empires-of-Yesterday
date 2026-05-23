extends Control

@onready var outcome_label: Label = $MainPanel/VBox/OutcomeLabel
@onready var stats_label: RichTextLabel = $MainPanel/VBox/StatsScroll/StatsLabel
@onready var credits_label: Label = $MainPanel/VBox/CreditsLabel
@onready var seed_label: Label = $MainPanel/VBox/SeedLabel
@onready var continue_button: Button = $MainPanel/VBox/Buttons/ContinueButton
@onready var end_run_button: Button = $MainPanel/VBox/Buttons/EndRunButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.configure_scroll($MainPanel/VBox/StatsScroll, 160.0)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	continue_button.pressed.connect(_on_continue_pressed)
	end_run_button.pressed.connect(_on_end_run_pressed)
	_populate()


func _populate() -> void:
	var stats: Dictionary = RunState.last_mission_stats
	var victory: bool = bool(stats.get("victory", false))
	var partial: bool = bool(stats.get("partial", false))
	if victory:
		outcome_label.text = "OPERATION SUCCESS"
		outcome_label.modulate = GameTheme.ACCENT_SUCCESS
	elif partial:
		outcome_label.text = "PARTIAL SUCCESS"
		outcome_label.modulate = GameTheme.ACCENT_WARN
	else:
		outcome_label.text = "OPERATION FAILED"
		outcome_label.modulate = GameTheme.ACCENT_DANGER
	stats_label.text = (
		"Kills: [color=#88ddaa]%d[/color]\n"
		% int(stats.get("kills", 0))
		+ "Rooms cleared: [color=#88ddaa]%d[/color]\n" % int(stats.get("rooms_cleared", 0))
		+ "Casualties: [color=#ff8888]%d[/color]\n" % int(stats.get("casualties", 0))
		+ "Time: [color=#88ccff]%.0fs[/color]\n" % float(stats.get("elapsed", stats.get("time_seconds", 0.0)))
		+ "Op: [color=#cccccc]%d / %d[/color]\n" % [int(stats.get("op_index", 1)), RunState.ops_per_run]
		+ "Objective: [color=#cccccc]%s[/color]" % str(stats.get("objective", "standard")).replace("_", " ")
	)
	credits_label.text = "Run credits earned: +%d (total: %d)" % [
		int(stats.get("credits_earned", 0)),
		RunState.run_credits,
	]
	seed_label.text = "Run seed: %d  |  Map seed: %d" % [RunState.run_seed, int(stats.get("map_seed", stats.get("seed", 0)))]
	var can_continue := (
		RunState.run_active
		and victory
		and RunState.has_ops_remaining()
		and RunState.living_squad_count() > 0
	)
	continue_button.visible = can_continue
	continue_button.disabled = not can_continue
	if can_continue:
		continue_button.text = "Continue to Hub (Op %d)" % (RunState.op_index + 1)
	end_run_button.text = "End Run" if RunState.run_active else "Return to Menu"
	RunLog.info(
		"Mission debrief — outcome=%s op=%d/%d"
		% [outcome_label.text, int(stats.get("op_index", 1)), RunState.ops_per_run]
	)


func _on_continue_pressed() -> void:
	CombatAudio.play_ui_click(self)
	RunLog.info("Debrief continue to hub after op %d" % RunState.op_index)
	RunState.advance_after_success()
	get_tree().change_scene_to_file("res://BetweenMissionHub.tscn")


func _on_end_run_pressed() -> void:
	CombatAudio.play_ui_click(self)
	RunLog.info("Debrief end run from op %d" % RunState.op_index)
	var stats: Dictionary = RunState.last_mission_stats
	var won: bool = bool(stats.get("victory", false))
	var ops_cleared: int = RunState.cleared_ops
	if won:
		ops_cleared += 1
	var run_won := won and RunState.op_index >= RunState.ops_per_run
	var rewards: Dictionary = SaveManager.record_run_end(ops_cleared, run_won)
	var summary_meta := {
		"ops_cleared": ops_cleared,
		"run_won": run_won,
		"tokens_earned": rewards.get("tokens_earned", 0),
	}
	if RunState.daily_seed_mode:
		var daily_stats: Dictionary = SaveManager.record_daily_run_end(
			ops_cleared,
			RunState.run_total_casualties,
			RunState.run_total_elapsed,
		)
		summary_meta["daily_run"] = true
		summary_meta["daily_stats"] = daily_stats
	RunState.end_run()
	get_tree().set_meta("run_summary", summary_meta)
	get_tree().change_scene_to_file("res://RunSummary.tscn")
