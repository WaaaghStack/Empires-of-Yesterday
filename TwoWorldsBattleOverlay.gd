extends Control

## Battle replay overlay for the Two Worlds globe mode. Draws the baked BattleReport frames
## (soldier dots / bomber diamonds) on top of the globe, with a Continue button. Emits
## `closed` when the user dismisses the current battle.

signal closed

const FRAME_DT := 0.06

var _frames: Array = []
var _summary: Dictionary = {}
var _bw: float = 120.0
var _bh: float = 80.0
var _idx: int = 0
var _time: float = 0.0
var _playing: bool = false
var _font: Font = ThemeDB.fallback_font
var _btn: Button


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	visible = false
	_btn = Button.new()
	_btn.text = "Continue"
	_btn.size = Vector2(200, 52)
	_btn.pressed.connect(_on_continue)
	add_child(_btn)


func show_battle(frames: Array, summary: Dictionary, bw: float, bh: float) -> void:
	_frames = frames
	_summary = summary
	_bw = max(bw, 1.0)
	_bh = max(bh, 1.0)
	_idx = 0
	_time = 0.0
	_playing = _frames.size() > 1
	visible = true
	_btn.text = "Playing\u2026" if _playing else "Continue"
	_reposition()
	queue_redraw()


func _reposition() -> void:
	if _btn:
		_btn.position = Vector2(size.x * 0.5 - 100.0, size.y - 72.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition()


func _process(delta: float) -> void:
	if not visible or not _playing:
		return
	_time += delta
	while _time >= FRAME_DT and _idx < _frames.size() - 1:
		_idx += 1
		_time -= FRAME_DT
	if _idx >= _frames.size() - 1:
		_playing = false
		_btn.text = "Continue"
	queue_redraw()


func _on_continue() -> void:
	visible = false
	closed.emit()


func _fac_color(f: int) -> Color:
	match f:
		0:
			return Color(0.35, 0.6, 1.0)
		1:
			return Color(1.0, 0.4, 0.4)
		_:
			return Color(0.7, 0.7, 0.75)


func _draw() -> void:
	# Dim the globe behind, then draw the battlefield.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.06, 0.93))
	var pad := 90.0
	var rect := Rect2(pad, 130.0, size.x - pad * 2.0, size.y - 250.0)
	draw_rect(rect, Color(0.09, 0.13, 0.1, 1.0))
	draw_rect(rect, Color(0.4, 0.5, 0.4, 0.7), false, 2.0)

	var winner := int(_summary.get("winner", -1))
	var header := "Battle at Province %d  —  F%d vs F%d  —  winner: %s" % [
		int(_summary.get("province", -1)),
		int(_summary.get("attacker", 0)),
		int(_summary.get("defender", 1)),
		("F%d" % winner) if winner >= 0 else "draw",
	]
	draw_string(_font, Vector2(pad, 96), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.95, 0.8))
	if _frames.is_empty():
		draw_string(_font, rect.position + Vector2(20, 30), "(no frames)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))
		return
	draw_string(_font, Vector2(pad, size.y - 96), "Frame %d / %d" % [_idx + 1, _frames.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))

	var frame: Dictionary = _frames[_idx]
	var fac: PackedByteArray = frame.get("fac", PackedByteArray())
	var kind: PackedByteArray = frame.get("kind", PackedByteArray())
	var xs: PackedFloat32Array = frame.get("x", PackedFloat32Array())
	var ys: PackedFloat32Array = frame.get("y", PackedFloat32Array())
	var alive: PackedByteArray = frame.get("alive", PackedByteArray())
	for i in range(xs.size()):
		if alive[i] == 0:
			continue
		var sx := rect.position.x + (xs[i] / _bw) * rect.size.x
		var sy := rect.position.y + (ys[i] / _bh) * rect.size.y
		var c := _fac_color(int(fac[i]))
		if kind[i] == 1:
			var d := 5.0
			draw_colored_polygon(PackedVector2Array([Vector2(sx, sy - d), Vector2(sx + d, sy), Vector2(sx, sy + d), Vector2(sx - d, sy)]), c)
		else:
			draw_circle(Vector2(sx, sy), 3.0, c)
