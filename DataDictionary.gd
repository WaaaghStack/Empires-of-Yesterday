extends Control

## In-game Data Dictionary — a Unity Catalog–style reference for the tables that populate the game.
## Left: searchable list of catalogs -> tables. Right: selected table's grain/source/description/notes
## plus a columns grid (Column | Type | Null | Key | Description). Data lives in
## res://data/data_dictionary.json so it can be curated without code changes.

const DATA_PATH := "res://data/data_dictionary.json"

var _data: Dictionary = {}
var _tables_flat: Array = []      # flat list of {catalog, table}
var _tree: Tree
var _search: LineEdit
var _detail_box: VBoxContainer
var _cols_tree: Tree
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_data = _load_data()

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = String(_data.get("title", "Data Dictionary"))
	title.position = Vector2(32, 22)
	title.add_theme_font_size_override("font_size", 26)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = String(_data.get("subtitle", ""))
	subtitle.position = Vector2(32, 58)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.76, 0.86))
	add_child(subtitle)

	var back := Button.new()
	back.text = "\u2190 Menu"
	back.size = Vector2(120, 40)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.position = Vector2(-150, 22)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://MainMenu.tscn"))
	add_child(back)

	# Two-pane layout below the header.
	var content := HBoxContainer.new()
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 24
	content.offset_top = 92
	content.offset_right = -24
	content.offset_bottom = -24
	content.add_theme_constant_override("separation", 16)
	add_child(content)

	# Left: search + tables tree.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 8)
	content.add_child(left)

	_search = LineEdit.new()
	_search.placeholder_text = "Search tables\u2026"
	_search.text_changed.connect(func(_t): _rebuild_tree())
	left.add_child(_search)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_table_selected)
	left.add_child(_tree)

	# Right: detail panel.
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
		return {"title": "Data Dictionary", "subtitle": "(data file missing)", "catalogs": []}
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"title": "Data Dictionary", "subtitle": "(parse error)", "catalogs": []}


func _rebuild_tree() -> void:
	_tree.clear()
	_tables_flat.clear()
	var query := _search.text.strip_edges().to_lower()
	var root := _tree.create_item()
	for cat in _data.get("catalogs", []):
		var cat_item: TreeItem = null
		for tbl in cat.get("tables", []):
			var hay := (String(tbl.get("name", "")) + " " + String(tbl.get("description", ""))).to_lower()
			if query != "" and not hay.contains(query):
				continue
			if cat_item == null:
				cat_item = _tree.create_item(root)
				cat_item.set_text(0, String(cat.get("name", "Catalog")))
				cat_item.set_selectable(0, false)
				cat_item.set_custom_color(0, Color(0.65, 0.78, 1.0))
			var it := _tree.create_item(cat_item)
			it.set_text(0, "  " + String(tbl.get("name", "table")))
			it.set_metadata(0, _tables_flat.size())
			_tables_flat.append({"catalog": cat, "table": tbl})


func _select_first() -> void:
	if _tables_flat.is_empty():
		return
	# Select the first table leaf.
	var root := _tree.get_root()
	if root == null:
		return
	var cat := root.get_first_child()
	while cat != null:
		var leaf := cat.get_first_child()
		if leaf != null:
			leaf.select(0)
			_on_table_selected()
			return
		cat = cat.get_next()


func _on_table_selected() -> void:
	var sel := _tree.get_selected()
	if sel == null:
		return
	var meta = sel.get_metadata(0)
	if meta == null:
		return
	var entry: Dictionary = _tables_flat[int(meta)]
	_render_detail(entry["catalog"], entry["table"])


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


func _render_detail(cat: Dictionary, tbl: Dictionary) -> void:
	_clear_detail()
	_detail_box.add_child(_mk_label(String(tbl.get("name", "")), 24, Color(0.95, 0.97, 1.0), false))
	_detail_box.add_child(_mk_label(String(cat.get("name", "")), 13, Color(0.6, 0.72, 0.95)))
	_detail_box.add_child(_mk_label("Grain: " + String(tbl.get("grain", "\u2014")), 14, Color(0.85, 0.88, 0.95)))
	_detail_box.add_child(_mk_label("Source: " + String(tbl.get("source", "\u2014")), 13, Color(0.75, 0.85, 0.7)))
	_detail_box.add_child(_mk_label(String(tbl.get("description", "")), 15, Color(0.88, 0.9, 0.95)))

	# Columns grid (Unity Catalog style).
	var cols_header := _mk_label("Columns", 17, Color(0.8, 0.86, 1.0), false)
	_detail_box.add_child(cols_header)

	_cols_tree = Tree.new()
	_cols_tree.columns = 5
	_cols_tree.hide_root = true
	_cols_tree.set_column_titles_visible(true)
	_cols_tree.set_column_title(0, "Column")
	_cols_tree.set_column_title(1, "Type")
	_cols_tree.set_column_title(2, "Null")
	_cols_tree.set_column_title(3, "Key")
	_cols_tree.set_column_title(4, "Description")
	_cols_tree.set_column_expand(0, false)
	_cols_tree.set_column_custom_minimum_width(0, 220)
	_cols_tree.set_column_expand(1, false)
	_cols_tree.set_column_custom_minimum_width(1, 200)
	_cols_tree.set_column_expand(2, false)
	_cols_tree.set_column_custom_minimum_width(2, 90)
	_cols_tree.set_column_expand(3, false)
	_cols_tree.set_column_custom_minimum_width(3, 130)
	_cols_tree.set_column_expand(4, true)
	_cols_tree.custom_minimum_size = Vector2(0, 320)
	_cols_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(_cols_tree)

	var croot := _cols_tree.create_item()
	for col in tbl.get("columns", []):
		var row := _cols_tree.create_item(croot)
		row.set_text(0, String(col.get("name", "")))
		row.set_text(1, String(col.get("type", "")))
		row.set_text(2, String(col.get("null", "")))
		row.set_text(3, String(col.get("key", "")))
		row.set_text(4, String(col.get("desc", "")))
		row.set_custom_color(0, Color(0.95, 0.95, 0.8))
		row.set_custom_color(1, Color(0.7, 0.85, 0.95))
		if String(col.get("key", "")) != "":
			row.set_custom_color(3, Color(0.95, 0.8, 0.5))

	var notes := String(tbl.get("notes", ""))
	if notes != "":
		_detail_box.add_child(_mk_label("Notes: " + notes, 13, Color(0.8, 0.82, 0.88)))
