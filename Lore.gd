extends Control

## In-game Lore encyclopedia — same chrome family as the Data Dictionary.
## Left: searchable catalogs -> entries. Right: selected entry (who they are, fight,
## strengths, weaknesses, unique win, optional roster sprite). Data lives in
## res://data/lore_encyclopedia.json.

const DATA_PATH := "res://data/lore_encyclopedia.json"

var _data: Dictionary = {}
var _entries_flat: Array = []
var _tree: Tree
var _search: LineEdit
var _detail_box: VBoxContainer


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_data = _load_data()

	var bg := ColorRect.new()
	bg.color = GameTheme.BG_DARK
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = String(_data.get("title", "Lore"))
	title.position = Vector2(32, 22)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", GameTheme.TEXT_PRIMARY)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = String(_data.get("subtitle", ""))
	subtitle.position = Vector2(32, 58)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", GameTheme.TEXT_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.size = Vector2(900, 28)
	add_child(subtitle)

	var back := Button.new()
	back.text = "\u2190 Menu"
	back.size = Vector2(120, 40)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.position = Vector2(-150, 22)
	GameTheme.apply_ghost_button(back)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://MainMenu.tscn"))
	add_child(back)

	var content := HBoxContainer.new()
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 24
	content.offset_top = 92
	content.offset_right = -24
	content.offset_bottom = -24
	content.add_theme_constant_override("separation", 16)
	add_child(content)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 8)
	content.add_child(left)

	_search = LineEdit.new()
	_search.placeholder_text = "Search lore\u2026"
	_search.text_changed.connect(func(_t): _rebuild_tree())
	left.add_child(_search)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_entry_selected)
	left.add_child(_tree)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	content.add_child(right)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_detail_box)

	_rebuild_tree()
	_select_first()


func _load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		return {"title": "Lore", "subtitle": "(data file missing)", "catalogs": []}
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"title": "Lore", "subtitle": "(parse error)", "catalogs": []}


func _rebuild_tree() -> void:
	_tree.clear()
	_entries_flat.clear()
	var query := _search.text.strip_edges().to_lower()
	var root := _tree.create_item()
	for cat in _data.get("catalogs", []):
		var cat_item: TreeItem = null
		for entry in cat.get("entries", []):
			var unit: Dictionary = {}
			var raw_u = entry.get("unit", {})
			if typeof(raw_u) == TYPE_DICTIONARY:
				unit = raw_u
			var tags_s := ""
			if typeof(unit.get("tags", [])) == TYPE_ARRAY:
				tags_s = _join_list(unit.get("tags", []))
			var hay := (
				String(entry.get("name", ""))
				+ " "
				+ String(entry.get("vibe", ""))
				+ " "
				+ String(entry.get("role", ""))
				+ " "
				+ String(entry.get("fight", ""))
				+ " "
				+ String(entry.get("win", ""))
				+ " "
				+ String(entry.get("sprite", ""))
				+ " "
				+ String(entry.get("body", ""))
				+ " "
				+ String(unit.get("domain", ""))
				+ " "
				+ String(unit.get("arm", ""))
				+ " "
				+ String(unit.get("rank", ""))
				+ " "
				+ String(unit.get("group", ""))
				+ " "
				+ String(unit.get("weapon", ""))
				+ " "
				+ tags_s
			).to_lower()
			if query != "" and not hay.contains(query):
				continue
			if cat_item == null:
				cat_item = _tree.create_item(root)
				cat_item.set_text(0, String(cat.get("name", "Catalog")))
				cat_item.set_selectable(0, false)
				cat_item.set_custom_color(0, GameTheme.ACCENT)
			var it := _tree.create_item(cat_item)
			var playable := String(entry.get("playable", ""))
			var mark := "  "
			if playable == "now":
				mark = "* "
			it.set_text(0, mark + String(entry.get("name", "entry")))
			it.set_metadata(0, _entries_flat.size())
			_entries_flat.append({"catalog": cat, "entry": entry})


func _select_first() -> void:
	if _entries_flat.is_empty():
		return
	var root := _tree.get_root()
	if root == null:
		return
	var cat := root.get_first_child()
	while cat != null:
		var leaf := cat.get_first_child()
		if leaf != null:
			leaf.select(0)
			_on_entry_selected()
			return
		cat = cat.get_next()


func _on_entry_selected() -> void:
	var sel := _tree.get_selected()
	if sel == null:
		return
	var meta = sel.get_metadata(0)
	if meta == null:
		return
	var row: Dictionary = _entries_flat[int(meta)]
	_render_detail(row["catalog"], row["entry"])


func _clear_detail() -> void:
	for c in _detail_box.get_children():
		c.queue_free()


func _mk_label(text: String, sizev: int, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sizev)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _join_list(v: Variant) -> String:
	if typeof(v) == TYPE_ARRAY:
		var parts: PackedStringArray = PackedStringArray()
		for item in v:
			parts.append(String(item))
		return ", ".join(parts)
	return String(v)


func _playable_label(playable: String) -> String:
	match playable:
		"now":
			return "Playable now"
		"horizon":
			return "Lore horizon"
		_:
			return playable


func _playable_color(playable: String) -> Color:
	match playable:
		"now":
			return GameTheme.ACCENT_SUCCESS
		"horizon":
			return GameTheme.ACCENT_WARN
		_:
			return GameTheme.TEXT_MUTED


func _add_section(label: String, value: String, value_color: Color = GameTheme.TEXT_PRIMARY) -> void:
	if value.strip_edges() == "":
		return
	_detail_box.add_child(_mk_label(label, 13, GameTheme.ACCENT, false))
	_detail_box.add_child(_mk_label(value, 15, value_color))


func _label_token(s: String) -> String:
	match s:
		"anti_air":
			return "Anti-air"
		"poor_vs_air":
			return "Poor vs air"
		"good_vs_air":
			return "Good vs air"
		"shock_breach":
			return "Shock"
		"after_shells":
			return "After-shells"
		"supply_spine":
			return "Supply spine"
		"not_a_tank":
			return "Not a tank"
		"single_target":
			return "Single target"
		"vs_air":
			return "vs Air"
		"cruise_z":
			return "Altitude"
		"attack_interval":
			return "Attack interval"
		"infantry_melee":
			return "Infantry melee"
		"infantry_hybrid":
			return "Infantry hybrid"
		"infantry_range":
			return "Infantry range"
		"infantry_skirmish":
			return "Infantry skirmish"
		"infantry_engineer":
			return "Infantry engineer"
		"regiment_size":
			return "Bodies"
		"size_class":
			return "Size"
		_:
			return s.replace("_", " ").capitalize()


func _fmt_stat(v: Variant) -> String:
	var f := float(v)
	if abs(f - round(f)) < 0.001:
		return str(int(round(f)))
	return "%.2f" % f


func _mk_chip(text: String, color: Color = GameTheme.ACCENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.16, 0.22, 1)
	st.border_color = color
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	l.add_theme_stylebox_override("normal", st)
	return l


func _add_chips(items: PackedStringArray, color: Color = GameTheme.ACCENT) -> void:
	if items.is_empty():
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in items:
		if String(t).strip_edges() == "":
			continue
		row.add_child(_mk_chip(String(t), color))
	_detail_box.add_child(row)


func _add_stat_grid(pairs: Array) -> void:
	if pairs.is_empty():
		return
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in pairs:
		var name_s := String(pair[0])
		var val_s := String(pair[1])
		grid.add_child(_mk_label(name_s, 12, GameTheme.TEXT_MUTED, false))
		grid.add_child(_mk_label(val_s, 14, GameTheme.TEXT_PRIMARY, false))
	_detail_box.add_child(grid)


func _add_unit_card(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var u: Dictionary = raw
	var arm := String(u.get("arm", "")).strip_edges()
	if arm == "":
		return
	var source := String(u.get("stats_source", "proposed"))
	var live := source == "live"
	_detail_box.add_child(_mk_label("Unit card", 13, GameTheme.ACCENT, false))
	var chips: PackedStringArray = PackedStringArray()
	chips.append(_label_token(String(u.get("domain", ""))))
	chips.append(_label_token(arm))
	chips.append("Rank: " + _label_token(String(u.get("rank", ""))))
	var group := String(u.get("group", "")).strip_edges()
	if group != "":
		chips.append(_label_token(group))
	chips.append(_label_token(String(u.get("size_class", ""))))
	if live:
		chips.append("Live")
	else:
		chips.append("Proposed")
	_add_chips(chips, GameTheme.ACCENT if live else GameTheme.ACCENT_WARN)
	_add_section("Weapon", String(u.get("weapon", "")))
	var pairs: Array = []
	pairs.append(["Bodies", _fmt_stat(u.get("regiment_size", 0))])
	pairs.append(["Spacing", _fmt_stat(u.get("spacing", 0))])
	var stats: Dictionary = u.get("stats", {})
	if typeof(stats) == TYPE_DICTIONARY:
		for key in ["hp", "attack", "attack_interval", "reach", "perception", "speed", "cohesion", "vs_air", "blast", "cruise_z"]:
			if stats.has(key):
				pairs.append([_label_token(key), _fmt_stat(stats[key])])
	_add_stat_grid(pairs)
	var tag_chips: PackedStringArray = PackedStringArray()
	for t in u.get("tags", []):
		tag_chips.append(_label_token(String(t)))
	if not tag_chips.is_empty():
		_detail_box.add_child(_mk_label("Attributes", 13, GameTheme.ACCENT, false))
		_add_chips(tag_chips, GameTheme.TEXT_PRIMARY)
	if live:
		_detail_box.add_child(_mk_label("Live numbers match the battle KindProfile. Encyclopedia is not combat authority.", 13, GameTheme.TEXT_MUTED))
	else:
		_detail_box.add_child(_mk_label("Proposed horizon stats — not a Custom Battle kind yet.", 13, GameTheme.TEXT_MUTED))


func _add_sprite(path: String) -> void:
	var p := path.strip_edges()
	if p == "":
		return
	var tex: Texture2D = null
	if ResourceLoader.exists(p):
		tex = load(p) as Texture2D
	if tex == null and FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(280, 280)
	tr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_box.add_child(tr)


func _render_detail(cat: Dictionary, entry: Dictionary) -> void:
	_clear_detail()
	var playable := String(entry.get("playable", ""))
	_detail_box.add_child(_mk_label(String(entry.get("name", "")), 24, GameTheme.TEXT_PRIMARY, false))
	var cat_line := String(cat.get("name", ""))
	if playable != "":
		cat_line += "  ·  " + _playable_label(playable)
	_detail_box.add_child(_mk_label(cat_line, 13, _playable_color(playable)))
	_add_sprite(String(entry.get("sprite", "")))
	_add_unit_card(entry.get("unit", {}))
	_add_section("Job on the field", String(entry.get("role", "")))
	_add_section("Who they are", String(entry.get("vibe", "")))
	_add_section("Origin", String(entry.get("origin", "")))
	_add_section("Temperament", String(entry.get("temperament", "")))
	_add_section("How they fight", String(entry.get("fight", "")))
	_add_section("Strengths", _join_list(entry.get("strengths", [])))
	_add_section("Weaknesses", _join_list(entry.get("weaknesses", [])), Color(0.92, 0.78, 0.78))
	_add_section("How they win", String(entry.get("win", "")), GameTheme.ACCENT)
	_add_section("Lore", String(entry.get("body", "")))
	var notes := String(entry.get("notes", ""))
	if notes != "":
		_detail_box.add_child(_mk_label("Notes: " + notes, 13, GameTheme.TEXT_MUTED))
