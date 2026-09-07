extends Control

## Two Worlds — turn-based MVP screen.
##
## Drives the `TwoWorldsEngine` GDExtension (eon_engine authority): start a campaign, End Turn to
## resolve one WEGO turn, watch auto-resolved battles play back as baked-frame replays, and reach a
## victory. Presentation-only: all sim truth comes from the engine's wide-row report.

const FRAME_DT := 0.06  # seconds per recorded battle frame during playback

var _engine: Object = null
var _seed: int = 12345

var _provinces: Array = []
var _factions: Array = []
var _armies: Array = []
var _turn: int = 0
var _outcome: String = "Ongoing"
var _done: bool = false

# Battle review state.
var _state: String = "map"  # "map" | "battle"
var _turn_battles: Array = []
var _review_ptr: int = 0
var _battle: Dictionary = {}
var _battle_frames: Array = []
var _frame_idx: int = 0
var _frame_time: float = 0.0
var _playing: bool = false

var _font: Font = ThemeDB.fallback_font
var _end_btn: Button
var _menu_btn: Button
var _status_label: Label


func _ready() -> void:
	set_process(true)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_engine = _make_engine()
	if _engine == null:
		var err := Label.new()
		err.text = "TwoWorldsEngine not available — rebuild the Rust GDExtension (setup_rust.ps1 / .cursor/install.sh)."
		err.position = Vector2(40, 40)
		add_child(err)
		return

	var rs: Object = get_tree().root.get_node_or_null("RunState") if get_tree() else null
	if rs != null and "run_seed" in rs and int(rs.run_seed) != 0:
		_seed = int(rs.run_seed)
	_engine.new_campaign(_seed)

	_menu_btn = Button.new()
	_menu_btn.text = "\u2190 Menu"
	_menu_btn.position = Vector2(24, 20)
	_menu_btn.size = Vector2(120, 40)
	_menu_btn.pressed.connect(_on_menu)
	add_child(_menu_btn)

	_end_btn = Button.new()
	_end_btn.text = "End Turn"
	_end_btn.size = Vector2(220, 56)
	_end_btn.pressed.connect(_on_end_or_continue)
	add_child(_end_btn)

	_status_label = Label.new()
	_status_label.position = Vector2(24, 74)
	_status_label.add_theme_font_size_override("font_size", 15)
	add_child(_status_label)

	_refresh()
	_reposition()
	queue_redraw()


func _make_engine() -> Object:
	if ClassDB.class_exists("TwoWorldsEngine"):
		return ClassDB.instantiate("TwoWorldsEngine")
	return null


func _reposition() -> void:
	if _end_btn:
		_end_btn.position = Vector2(size.x * 0.5 - 110.0, size.y - 76.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition()
		queue_redraw()


func _refresh() -> void:
	_provinces = _engine.get_provinces()
	_factions = _engine.get_factions()
	_armies = _engine.get_armies()
	_turn = int(_engine.current_turn())
	_outcome = String(_engine.outcome())
	_update_status_text()


func _update_status_text() -> void:
	if _status_label == null:
		return
	var lines: Array = []
	for f in _factions:
		var gems: PackedFloat32Array = f.get("gems", PackedFloat32Array())
		var gem_str := ""
		if gems.size() >= 3:
			gem_str = "Au%d Ve%d Em%d" % [int(gems[0]), int(gems[1]), int(gems[2])]
		lines.append(
			"%s  Dom %d  Land %d  Units %d  Thrones %d  %s" % [
				String(f.get("name", "F")),
				int(f.get("dominion", 0.0)),
				int(f.get("land", 0)),
				int(f.get("units", 0)),
				int(f.get("thrones", 0)),
				gem_str,
			]
		)
	_status_label.text = "\n".join(lines)


func _process(delta: float) -> void:
	if _state != "battle" or not _playing:
		return
	_frame_time += delta
	while _frame_time >= FRAME_DT and _frame_idx < _battle_frames.size() - 1:
		_frame_idx += 1
		_frame_time -= FRAME_DT
	if _frame_idx >= _battle_frames.size() - 1:
		_playing = false
		_end_btn.text = "Continue"
	queue_redraw()


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_end_or_continue() -> void:
	if _state == "battle":
		_advance_review()
		return
	if _done:
		# Restart with a fresh seed for another match.
		_seed += 1
		_engine.new_campaign(_seed)
		_done = false
		_refresh()
		queue_redraw()
		return
	var res: Dictionary = _engine.end_turn()
	_turn = int(res.get("turn", _turn))
	_outcome = String(res.get("outcome", _outcome))
	_done = bool(res.get("done", false))
	_turn_battles = res.get("battles", [])
	_refresh()
	if _turn_battles.size() > 0:
		_review_ptr = 0
		_start_review(0)
	else:
		if _done:
			_end_btn.text = "Play Again"
		queue_redraw()


func _start_review(i: int) -> void:
	_battle = _engine.get_last_battle_frames(i)
	_battle_frames = _battle.get("frames", [])
	_frame_idx = 0
	_frame_time = 0.0
	_playing = _battle_frames.size() > 1
	_state = "battle"
	_end_btn.text = "Playing\u2026" if _playing else "Continue"
	queue_redraw()


func _advance_review() -> void:
	_review_ptr += 1
	if _review_ptr < _turn_battles.size():
		_start_review(_review_ptr)
	else:
		_state = "map"
		_end_btn.text = "Play Again" if _done else "End Turn"
		_refresh()
		queue_redraw()


func _fac_color(f: int) -> Color:
	match f:
		0:
			return Color(0.35, 0.6, 1.0)
		1:
			return Color(1.0, 0.4, 0.4)
		2:
			return Color(0.5, 0.85, 0.5)
		3:
			return Color(0.9, 0.8, 0.4)
		_:
			return Color(0.6, 0.6, 0.65)


func _province_pos(i: int, n: int, center: Vector2, radius: float) -> Vector2:
	var a := TAU * float(i) / float(max(n, 1)) - PI * 0.5
	return center + Vector2(cos(a), sin(a)) * radius


func _draw() -> void:
	# Header.
	draw_string(_font, Vector2(160, 46), "Two Worlds — Turn-Based (MVP)", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.92, 1.0))
	draw_string(_font, Vector2(size.x - 360, 46), "Turn %d   Outcome: %s" % [_turn, _outcome], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.88, 0.95))
	if _state == "map":
		_draw_map()
	else:
		_draw_battle()
	if _done and _state == "map":
		var msg := "VICTORY  —  %s" % _outcome
		draw_string(_font, Vector2(size.x * 0.5 - 220, size.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 0.95, 0.6))


func _draw_map() -> void:
	var n := _provinces.size()
	if n == 0:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.5 + 20.0)
	var radius: float = min(size.x, size.y) * 0.33
	var prov_r := 34.0

	# Edges.
	for i in range(n):
		var p: Dictionary = _provinces[i]
		var pa := _province_pos(i, n, center, radius)
		var neighbors: PackedInt32Array = p.get("neighbors", PackedInt32Array())
		for nb in neighbors:
			if nb > i:
				var pb := _province_pos(nb, n, center, radius)
				draw_line(pa, pb, Color(0.3, 0.34, 0.42, 0.7), 2.0)

	# Provinces.
	for i in range(n):
		var p: Dictionary = _provinces[i]
		var pos := _province_pos(i, n, center, radius)
		var owner := int(p.get("owner", -1))
		var col := _fac_color(owner) if owner >= 0 else Color(0.3, 0.32, 0.38)
		draw_circle(pos, prov_r, col.darkened(0.25))
		draw_arc(pos, prov_r, 0, TAU, 32, Color(0.85, 0.9, 1.0, 0.5), 2.0)
		# Capital ring.
		if int(p.get("capital_of", -1)) >= 0:
			draw_arc(pos, prov_r + 5.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 3.0)
		# Throne marker.
		if bool(p.get("has_throne", false)):
			draw_string(_font, pos + Vector2(-6, -prov_r - 8), "\u2605", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.9, 0.4))
		# Deposit dot.
		var dep := int(p.get("deposit", -1))
		if dep >= 0:
			var dep_cols: Array = [Color(0.95, 0.8, 0.3), Color(0.5, 0.85, 0.5), Color(0.95, 0.5, 0.3)]
			var dep_col: Color = dep_cols[clampi(dep, 0, 2)]
			draw_circle(pos + Vector2(prov_r - 6, -prov_r + 6), 6.0, dep_col)
		# Labels: province id + dominant dominion.
		var dom: PackedFloat32Array = p.get("dom", PackedFloat32Array())
		var best := 0.0
		for d in dom:
			best = max(best, d)
		draw_string(_font, pos + Vector2(-prov_r + 6, 4), "P%d" % int(p.get("id", i)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.97, 1.0))
		draw_string(_font, pos + Vector2(-prov_r + 6, 20), "D%d" % int(best), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 1.0, 0.9))
		var unrest := float(p.get("unrest", 0.0))
		if unrest > 1.0:
			draw_string(_font, pos + Vector2(4, -6), "!%d" % int(unrest), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.6, 0.5))

	# Army markers.
	for a in _armies:
		var prov := int(a.get("province", 0))
		var fac := int(a.get("faction", 0))
		var units := int(a.get("units", 0))
		var pos := _province_pos(prov, n, center, radius)
		var off := Vector2(0, prov_r + 16 + 16 * fac)
		var mk := pos + off
		_draw_triangle(mk, 9.0, _fac_color(fac))
		draw_string(_font, mk + Vector2(10, 5), "x%d" % units, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _fac_color(fac))

	# Hint.
	draw_string(_font, Vector2(size.x * 0.5 - 300, size.y - 92), "Click End Turn to resolve a WEGO turn (dominion tide, agents, auto-resolved battles).", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.85))


func _draw_triangle(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(-r, r), c + Vector2(r, r)])
	draw_colored_polygon(pts, col)


func _draw_battle() -> void:
	var w := float(_battle.get("width", 120.0))
	var h := float(_battle.get("height", 80.0))
	# Battlefield rect.
	var pad := 80.0
	var rect := Rect2(pad, 120.0, size.x - pad * 2.0, size.y - 260.0)
	draw_rect(rect, Color(0.09, 0.12, 0.1, 1.0))
	draw_rect(rect, Color(0.4, 0.5, 0.4, 0.6), false, 2.0)

	var summary: Dictionary = _turn_battles[_review_ptr] if _review_ptr < _turn_battles.size() else {}
	var winner := int(summary.get("winner", -1))
	var header := "Battle at Province %d — F%d vs F%d — winner: %s" % [
		int(summary.get("province", -1)),
		int(summary.get("attacker", 0)),
		int(summary.get("defender", 1)),
		("F%d" % winner) if winner >= 0 else "draw",
	]
	draw_string(_font, Vector2(pad, 104), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.95, 0.8))
	draw_string(_font, Vector2(pad, size.y - 120), "Frame %d / %d   (battle %d of %d)" % [_frame_idx + 1, _battle_frames.size(), _review_ptr + 1, _turn_battles.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))

	if _battle_frames.is_empty():
		return
	var frame: Dictionary = _battle_frames[_frame_idx]
	var fac: PackedByteArray = frame.get("fac", PackedByteArray())
	var kind: PackedByteArray = frame.get("kind", PackedByteArray())
	var xs: PackedFloat32Array = frame.get("x", PackedFloat32Array())
	var ys: PackedFloat32Array = frame.get("y", PackedFloat32Array())
	var alive: PackedByteArray = frame.get("alive", PackedByteArray())
	var count := xs.size()
	for i in range(count):
		if alive[i] == 0:
			continue
		var sx := rect.position.x + (xs[i] / w) * rect.size.x
		var sy := rect.position.y + (ys[i] / h) * rect.size.y
		var c := _fac_color(int(fac[i]))
		if kind[i] == 1:
			# Bomber — a diamond, slightly larger.
			var d := 5.0
			draw_colored_polygon(
				PackedVector2Array([Vector2(sx, sy - d), Vector2(sx + d, sy), Vector2(sx, sy + d), Vector2(sx - d, sy)]),
				c
			)
		else:
			draw_circle(Vector2(sx, sy), 3.0, c)
