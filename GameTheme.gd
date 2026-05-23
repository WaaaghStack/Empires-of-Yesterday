class_name GameTheme
extends RefCounted

const BG_DARK := Color(0.05, 0.06, 0.09, 1.0)
const BG_PANEL := Color(0.09, 0.11, 0.16, 0.95)
const ACCENT := Color(0.35, 0.75, 1.0, 1.0)
const ACCENT_WARN := Color(0.95, 0.55, 0.2, 1.0)
const ACCENT_DANGER := Color(0.92, 0.28, 0.32, 1.0)
const ACCENT_SUCCESS := Color(0.3, 0.85, 0.55, 1.0)
const TEXT_PRIMARY := Color(0.92, 0.94, 0.97, 1.0)
const TEXT_MUTED := Color(0.55, 0.6, 0.68, 1.0)
const BORDER := Color(0.22, 0.28, 0.38, 1.0)

static func make_panel_style(bg: Color = BG_PANEL, border: Color = BORDER, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style

static func make_button_style(normal: Color, _hover: Color, _pressed: Color) -> StyleBoxFlat:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = normal
	normal_style.border_color = BORDER
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(6)
	normal_style.content_margin_left = 14
	normal_style.content_margin_top = 8
	normal_style.content_margin_right = 14
	normal_style.content_margin_bottom = 8
	return normal_style

static func apply_to_control(node: Control) -> void:
	var theme := Theme.new()
	var panel := make_panel_style()
	var button_normal := make_button_style(Color(0.14, 0.17, 0.24), Color(0.18, 0.22, 0.32), Color(0.1, 0.12, 0.18))
	var button_hover := make_button_style(Color(0.18, 0.22, 0.32), Color(0.22, 0.28, 0.38), Color(0.14, 0.17, 0.24))
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("normal", "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_hover)
	theme.set_color("font_color", "Label", TEXT_PRIMARY)
	theme.set_color("font_color", "Button", TEXT_PRIMARY)
	theme.set_color("font_color", "RichTextLabel", TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", 15)
	theme.set_font_size("font_size", "Button", 15)
	node.theme = theme

static func class_color(marine_class: SoldierResource.MarineClass) -> Color:
	match marine_class:
		SoldierResource.MarineClass.ASSAULT:
			return Color(0.9, 0.35, 0.25)
		SoldierResource.MarineClass.SUPPORT:
			return Color(0.35, 0.8, 0.55)
		SoldierResource.MarineClass.MARKSMAN:
			return Color(0.45, 0.65, 0.95)
		SoldierResource.MarineClass.BREACHER:
			return Color(0.95, 0.75, 0.25)
	return Color(0.7, 0.7, 0.7)

static func class_name_text(marine_class: SoldierResource.MarineClass) -> String:
	match marine_class:
		SoldierResource.MarineClass.ASSAULT:
			return "Assault"
		SoldierResource.MarineClass.SUPPORT:
			return "Support"
		SoldierResource.MarineClass.MARKSMAN:
			return "Marksman"
		SoldierResource.MarineClass.BREACHER:
			return "Breacher"
	return "Marine"
