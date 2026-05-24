extends Control

@onready var summary_label: RichTextLabel = $MainPanel/VBox/SummaryScroll/SummaryLabel
@onready var tokens_label: Label = $MainPanel/VBox/TokensLabel
@onready var new_run_button: Button = $MainPanel/VBox/Buttons/NewRunButton
@onready var menu_button: Button = $MainPanel/VBox/Buttons/MenuButton


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.configure_scroll($MainPanel/VBox/SummaryScroll, 120.0)
	$MainPanel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	new_run_button.pressed.connect(_on_new_run_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_populate()


func _populate() -> void:
	var summary: Dictionary = {}
	if get_tree().has_meta("run_summary"):
		summary = get_tree().get_meta("run_summary")
		get_tree().remove_meta("run_summary")
	var tokens: int = int(summary.get("tokens_earned", 0))
	var ops_cleared: int = int(summary.get("ops_cleared", 0))
	var daily_block := ""
	if summary.get("daily_run", false):
		var daily: Dictionary = summary.get("daily_stats", {})
		daily_block = (
			"\nDaily run: [color=#88ccff]%s[/color]\n"
			% str(daily.get("share_code", SaveManager.get_daily_share_code()))
		)
		if daily.get("improved", false):
			daily_block += "New daily best! "
		daily_block += SaveManager.format_daily_best_line()
	var planet_block := ""
	if summary.get("planet_run", false):
		planet_block = (
			"\nImperial Reclamation: [color=#ffd080]%s[/color] (score %d)\n"
			% [str(summary.get("imperial_rank", "Initiate")), int(summary.get("imperial_score", 0))]
			+ "Legacy Biomass: [color=#88ddaa]%d[/color]  |  Echoes: [color=#cc88ff]%d[/color]\n"
			% [int(summary.get("legacy_biomass", 0)), int(summary.get("yesterdays_echoes", 0))]
			+ "Evolution tier: [color=#88ccff]%d[/color]\n" % int(summary.get("evolution_tier", 0))
		)
		var evo_lines: Array = summary.get("evolution_summary", [])
		if not evo_lines.is_empty():
			planet_block += "Build: [color=#cccccc]%s[/color]\n" % ", ".join(evo_lines)
		planet_block += "Carrier Biomass (meta): [color=#88ddaa]%d[/color]\n" % SaveManager.carrier_biomass
	summary_label.text = (
		"Ops cleared: [color=#88ccff]%d[/color]\n" % ops_cleared
		+ "Best depth: [color=#88ddaa]%d[/color]\n" % SaveManager.best_run_depth
		+ "Total runs: [color=#cccccc]%d[/color]" % SaveManager.total_runs
		+ planet_block
		+ daily_block
	)
	tokens_label.text = "Command Tokens earned: +%d (balance: %d)" % [tokens, SaveManager.command_tokens]
	if summary.get("planet_run", false):
		new_run_button.text = "New Planet Run"


func _on_new_run_pressed() -> void:
	get_tree().change_scene_to_file("res://OrbitalCarrier.tscn")


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
