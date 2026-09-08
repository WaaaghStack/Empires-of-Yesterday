extends Control

## Standalone Custom Battle harness (Total War style "quick battle"). Reads battle params from
## RunState metadata (set by the main menu's Custom Battle setup), resolves one battle via the
## tested TwoWorldsEngine, and plays it back in the HD-2D BattleView. Returns to the main menu when
## the viewer is dismissed. Additive/opt-in — does not touch the live World Conquest path.

const BattleViewScript := preload("res://BattleView.gd")

var _engine: Object
var _view: Control


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var params := _read_params()
	_engine = _make_engine()
	if _engine == null:
		var err := Label.new()
		err.text = "TwoWorldsEngine not available — rebuild the Rust GDExtension (bash ./.cursor/install.sh)."
		err.position = Vector2(40, 40)
		add_child(err)
		return

	_engine.resolve_custom_battle(
		int(params.get("seed", 1)),
		int(params.get("f0_soldiers", 400)),
		int(params.get("f0_bombers", 10)),
		int(params.get("f1_soldiers", 400)),
		int(params.get("f1_bombers", 10)),
	)

	_view = Control.new()
	_view.set_script(BattleViewScript)
	_view.anchor_right = 1.0
	_view.anchor_bottom = 1.0
	add_child(_view)
	_view.finished.connect(_on_finished)
	# Empty summary → BattleView pulls province/attacker/defender/winner from the battle meta.
	_view.play_engine_battle(_engine, 0, {})


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


func _on_finished() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
