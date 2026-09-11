extends SceneTree

## Headless integration test for the Two Worlds MVP screen: instantiate the scene (runs _ready →
## new_campaign + UI build), then drive the End Turn loop to completion, fast-forwarding battle
## reviews. Verifies the turn-based campaign plays to a decisive outcome with no runtime errors.
## godot --headless --path . -s res://two_worlds_screen_headless_test.gd

func _init() -> void:
	print("=== Two Worlds Screen Headless ===")
	var scene: PackedScene = load("res://TwoWorldsScreen.tscn")
	if scene == null:
		push_error("FAIL could not load TwoWorldsScreen.tscn")
		quit()
		return
	var node: Control = scene.instantiate()
	get_root().add_child(node)
	# In a SceneTree script the node lifecycle has not ticked yet, so run _ready explicitly.
	if node._engine == null:
		node._ready()

	if not node._engine:
		push_error("FAIL engine not created (TwoWorldsEngine missing)")
		quit()
		return

	var turns_played := 0
	var battles_seen := 0
	var guard := 0
	while not node._done and guard < 300:
		guard += 1
		node._on_end_or_continue()  # from map: ends a turn
		turns_played += 1
		# Fast-forward any battle reviews triggered this turn.
		while node._state == "battle":
			battles_seen += 1
			node._playing = false
			node._frame_idx = max(node._battle_frames.size() - 1, 0)
			node._on_end_or_continue()  # "Continue" → next battle or back to map

	print("turns_played=", turns_played, " battles_seen=", battles_seen)
	print("final turn=", node._turn, " outcome=", node._outcome, " done=", node._done)
	# Sanity: provinces + factions populated from the engine.
	print("provinces=", node._provinces.size(), " factions=", node._factions.size())
	if node._done and node._provinces.size() > 0 and node._factions.size() >= 2:
		print("PASS two_worlds screen headless")
	else:
		push_error("FAIL screen did not reach a decisive outcome")
	quit()
