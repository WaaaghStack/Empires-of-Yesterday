class_name BattleDebriefPanel
extends PanelContainer

const GameThemeLib := preload("res://GameTheme.gd")

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var summary_label: Label = $Margin/VBox/SummaryLabel
@onready var analysis_header: Label = $Margin/VBox/AnalysisHeader
@onready var unit_list: ItemList = $Margin/VBox/UnitScroll/UnitList
@onready var continue_button: Button = $Margin/VBox/ContinueButton

var _on_continue: Callable = Callable()


func _ready() -> void:
	add_theme_stylebox_override("panel", GameThemeLib.make_panel_style())
	continue_button.pressed.connect(_on_continue_pressed)


func show_report(
	player_won: bool,
	analysis: Dictionary,
	summary_text: String,
	on_continue: Callable = Callable(),
) -> void:
	_on_continue = on_continue
	title_label.text = "BATTLE WON" if player_won else "BATTLE LOST"
	title_label.add_theme_color_override(
		"font_color",
		GameThemeLib.ACCENT_SUCCESS if player_won else GameThemeLib.ACCENT_DANGER,
	)
	summary_label.text = summary_text
	analysis_header.text = "Unit analysis — kills and casualties"
	_fill_unit_list(analysis)


func _on_continue_pressed() -> void:
	if _on_continue.is_valid():
		_on_continue.call()


func _fill_unit_list(analysis: Dictionary) -> void:
	unit_list.clear()
	var units: Array = analysis.get("units", [])
	if units.is_empty():
		unit_list.add_item("No unit-level highlights (resolve a new turn for kill tracking).")
		return
	for row in units:
		var status := "Alive"
		if bool(row.get("died", false)):
			var dr: int = int(row.get("death_round", -1))
			status = "KIA round %d" % dr if dr >= 0 else "KIA"
		var side_col := Color(0.35, 0.75, 1.0) if int(row.get("side", 0)) == 0 else Color(0.95, 0.35, 0.3)
		var text := "%s  %s  —  %d kills  —  %s" % [
			str(row.get("side_name", "?")),
			str(row.get("type_name", "Unit")),
			int(row.get("kills", 0)),
			status,
		]
		var idx: int = unit_list.add_item(text)
		unit_list.set_item_custom_fg_color(idx, side_col)
