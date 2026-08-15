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


static func make_ribbon_style() -> StyleBoxFlat:
	var style := make_panel_style(Color(0.09, 0.11, 0.16, 0.62), BORDER, 6)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 10
	style.content_margin_bottom = 4
	return style


static func make_cluster_style() -> StyleBoxFlat:
	var style := make_panel_style(Color(0.09, 0.11, 0.16, 0.62), BORDER, 8)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style


static func _button_style(bg: Color, border: Color, margin_h: int = 14, margin_v: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = margin_h
	style.content_margin_top = margin_v
	style.content_margin_right = margin_h
	style.content_margin_bottom = margin_v
	return style


static func apply_primary_button(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.22, 0.32), ACCENT))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.20, 0.28, 0.40), ACCENT))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.18, 0.26), ACCENT))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0.12, 0.14, 0.18, 0.55), BORDER))
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)


static func apply_ghost_button(btn: Button) -> void:
	if btn == null:
		return
	var border := Color(BORDER.r, BORDER.g, BORDER.b, 0.55)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0), border))
	btn.add_theme_stylebox_override("hover", _button_style(Color(1, 1, 1, 0.05), BORDER))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(1, 1, 1, 0.08), ACCENT))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0, 0, 0, 0), Color(BORDER.r, BORDER.g, BORDER.b, 0.28)))
	btn.add_theme_color_override("font_color", TEXT_MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_disabled_color", Color(TEXT_MUTED.r, TEXT_MUTED.g, TEXT_MUTED.b, 0.45))


static func apply_latched_button(btn: Button) -> void:
	if btn == null:
		return
	apply_ghost_button(btn)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.22, 0.32, 0.35), ACCENT, 8, 6))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.20, 0.28, 0.40, 0.45), ACCENT, 8, 6))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.22, 0.32, 0.55), ACCENT, 8, 6))
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)


static func make_tool_icon(kind: String, col: Color = TEXT_PRIMARY) -> ImageTexture:
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"outpost":
			_icon_fill_circle(img, 11, 11, 7, col)
			_icon_fill_circle(img, 11, 11, 3, Color(0, 0, 0, 0))
		"barracks":
			_icon_fill_rect(img, 3, 8, 16, 11, col)
			_icon_fill_rect(img, 7, 11, 8, 5, Color(0, 0, 0, 0))
		"hangar":
			_icon_fill_rect(img, 2, 14, 18, 5, col)
			_icon_fill_rect(img, 4, 7, 14, 4, col)
		"paint":
			_icon_dash_rect(img, 4, 4, 14, 14, col)
		"inspect":
			_icon_fill_circle(img, 9, 9, 6, col)
			_icon_fill_circle(img, 9, 9, 3, Color(0, 0, 0, 0))
			_icon_fill_rect(img, 14, 14, 5, 2, col)
		"clear":
			_icon_fill_rect(img, 4, 10, 14, 2, col)
			_icon_fill_rect(img, 10, 4, 2, 14, col)
		_:
			_icon_fill_rect(img, 6, 6, 10, 10, col)
	return ImageTexture.create_from_image(img)


static func _icon_fill_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for iy in range(maxi(0, y), mini(22, y + h)):
		for ix in range(maxi(0, x), mini(22, x + w)):
			img.set_pixel(ix, iy, col)


static func _icon_fill_circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	var r2: int = r * r
	for iy in range(22):
		for ix in range(22):
			var dx: int = ix - cx
			var dy: int = iy - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(ix, iy, col)


static func _icon_dash_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for i in range(w):
		if (i % 4) < 2:
			if y >= 0 and y < 22 and x + i >= 0 and x + i < 22:
				img.set_pixel(x + i, y, col)
			if y + h - 1 >= 0 and y + h - 1 < 22 and x + i >= 0 and x + i < 22:
				img.set_pixel(x + i, y + h - 1, col)
	for i in range(h):
		if (i % 4) < 2:
			if x >= 0 and x < 22 and y + i >= 0 and y + i < 22:
				img.set_pixel(x, y + i, col)
			if x + w - 1 >= 0 and x + w - 1 < 22 and y + i >= 0 and y + i < 22:
				img.set_pixel(x + w - 1, y + i, col)


static func ignore_mouse(node: Control) -> void:
	if node:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func configure_scroll(scroll: ScrollContainer, min_height: float = 0.0) -> void:
	if not scroll:
		return
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	if min_height > 0.0:
		scroll.custom_minimum_size.y = min_height


static func scroll_to_bottom(scroll: ScrollContainer) -> void:
	if not scroll:
		return
	var bar := scroll.get_v_scroll_bar()
	if bar:
		scroll.set_deferred("scroll_vertical", int(bar.max_value))


static func apply_to_control(node: Control) -> void:
	var game_theme := Theme.new()
	var panel := make_panel_style()
	var ghost := _button_style(Color(0, 0, 0, 0), Color(BORDER.r, BORDER.g, BORDER.b, 0.55))
	var ghost_hover := _button_style(Color(1, 1, 1, 0.05), BORDER)
	game_theme.set_stylebox("panel", "PanelContainer", panel)
	game_theme.set_stylebox("normal", "Button", ghost)
	game_theme.set_stylebox("hover", "Button", ghost_hover)
	game_theme.set_stylebox("pressed", "Button", ghost_hover)
	game_theme.set_color("font_color", "Label", TEXT_PRIMARY)
	game_theme.set_color("font_color", "Button", TEXT_MUTED)
	game_theme.set_color("font_hover_color", "Button", TEXT_PRIMARY)
	game_theme.set_color("font_pressed_color", "Button", TEXT_PRIMARY)
	game_theme.set_color("font_color", "RichTextLabel", TEXT_PRIMARY)
	game_theme.set_font_size("font_size", "Label", 15)
	game_theme.set_font_size("font_size", "Button", 15)
	node.theme = game_theme
