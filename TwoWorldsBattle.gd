extends Control

## Standalone Custom Battle harness (Total War style "quick battle"). Reads battle params from
## RunState metadata (set by the main menu's Custom Battle setup), resolves one battle via the
## tested TwoWorldsEngine, and plays it back in the HD-2D BattleView. Returns to the main menu when
## the viewer is dismissed. Additive/opt-in — does not touch the live World Conquest path.

const BattleViewScript := preload("res://BattleView.gd")
const UiTheme := preload("res://GameTheme.gd")

var _engine: Object
var _view: Control
var _wait: Dictionary = {}
var _params: Dictionary = {}


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_params = _read_params()
	_engine = _make_engine()
	if _engine == null:
		var err := Label.new()
		err.text = "TwoWorldsEngine not available — rebuild the Rust GDExtension (bash ./.cursor/install.sh)."
		err.position = Vector2(40, 40)
		add_child(err)
		return
	_wait = UiTheme.attach_resolve_wait(self, _body_count(_params))
	# Paint the bar before the blocking Rust resolve, or Fight still looks dead.
	await get_tree().process_frame
	await get_tree().process_frame
	_resolve_and_play()


func _set_wait(text: String, value: float, spin: bool) -> void:
	var label: Label = _wait.get("label", null)
	var bar: ProgressBar = _wait.get("bar", null)
	if label:
		label.text = text
	if bar:
		bar.indeterminate = spin
		if not spin:
			bar.value = clampf(value, 0.0, 1.0)


func _hide_wait() -> void:
	var root: Control = _wait.get("root", null)
	if root:
		root.queue_free()
	_wait = {}


func _resolve_and_play() -> void:
	var n := _body_count(_params)
	_set_wait("Resolving %d bodies…" % n, 0.18, true)
	var t0 := Time.get_ticks_msec()
	if _params.has("roster"):
		_resolve_plan(_params)
	else:
		_engine.resolve_custom_battle(
			int(_params.get("seed", 1)),
			int(_params.get("f0_soldiers", 400)),
			int(_params.get("f0_bombers", 10)),
			int(_params.get("f1_soldiers", 400)),
			int(_params.get("f1_bombers", 10)),
		)
	print("Custom Battle resolve %dms bodies=%d" % [
		Time.get_ticks_msec() - t0,
		n,
	])
	_set_wait("Opening replay…", 0.78, false)
	await get_tree().process_frame
	_view = Control.new()
	_view.set_script(BattleViewScript)
	_view.anchor_right = 1.0
	_view.anchor_bottom = 1.0
	add_child(_view)
	_view.finished.connect(_on_finished)
	# Empty summary → BattleView pulls province/attacker/defender/winner from the battle meta.
	_view.play_engine_battle(_engine, 0, {})
	_hide_wait()


func _body_count(params: Dictionary) -> int:
	var roster: Array = params.get("roster", [])
	if roster.is_empty():
		return int(params.get("f0_soldiers", 400)) + int(params.get("f0_bombers", 10)) + int(params.get("f1_soldiers", 400)) + int(params.get("f1_bombers", 10))
	var n := 0
	for row in roster:
		if row is Dictionary:
			n += int((row as Dictionary).get("count", 0))
	return n


func _make_engine() -> Object:
	if ClassDB.class_exists("TwoWorldsEngine"):
		return ClassDB.instantiate("TwoWorldsEngine")
	return null


func _read_params() -> Dictionary:
	var rs: Object = get_tree().root.get_node_or_null("RunState") if get_tree() else null
	if rs != null and rs.has_meta("custom_battle"):
		var m: Variant = rs.get_meta("custom_battle")
		if m is Dictionary and not (m as Dictionary).is_empty():
			return m
	return {"seed": 1, "f0_soldiers": 400, "f0_bombers": 10, "f1_soldiers": 400, "f1_bombers": 10}


func _resolve_plan(params: Dictionary) -> void:
	var roster: Array = params.get("roster", [])
	var fac := PackedByteArray()
	var kind := PackedByteArray()
	var count := PackedInt32Array()
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var facing := PackedFloat32Array()
	var formation := PackedByteArray()
	var orders := PackedByteArray()
	for row in roster:
		if not (row is Dictionary):
			continue
		var d: Dictionary = row
		fac.append(int(d.get("faction", 0)))
		kind.append(int(d.get("kind", 0)))
		count.append(int(d.get("count", 100)))
		xs.append(float(d.get("x", 40.0)))
		ys.append(float(d.get("y", 60.0)))
		facing.append(float(d.get("facing", 0.0)))
		formation.append(int(d.get("formation", 0)))
		orders.append(int(d.get("order", 0)))
	_engine.resolve_custom_battle_plan(
		int(params.get("seed", 1)),
		int(params.get("order0", 0)),
		int(params.get("order1", 0)),
		fac,
		kind,
		count,
		xs,
		ys,
		facing,
		formation,
		orders,
	)


func _on_finished() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
