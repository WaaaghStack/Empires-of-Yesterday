extends PanelContainer

func _ready() -> void:
	visible = false
	_apply_mouse_filter()
	add_theme_stylebox_override("panel", GameTheme.make_panel_style(Color(0.06, 0.08, 0.12, 0.92), GameTheme.ACCENT, 8))


func toggle() -> void:
	visible = not visible
	_apply_mouse_filter()


func _apply_mouse_filter() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
