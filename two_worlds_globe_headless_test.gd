extends SceneTree

## Headless integration test for the Two Worlds GLOBE screen: instantiate, carve provinces from the
## real Earth map, begin the campaign, then drive the End Turn loop to a decisive outcome
## (fast-forwarding battle reviews). Verifies province carving + engine wiring + turn loop.
## godot --headless --path . -s res://two_worlds_globe_headless_test.gd

func _init() -> void:
	print("=== Two Worlds Globe Headless ===")
	var scene: PackedScene = load("res://TwoWorldsGlobe.tscn")
	if scene == null:
		push_error("FAIL could not load TwoWorldsGlobe.tscn")
		quit()
		return
	var node: Control = scene.instantiate()
	get_root().add_child(node)
	if node._engine == null:
		node._ready()
	if not node._engine:
		push_error("FAIL engine not created")
		quit()
		return

	print("provinces carved=", node._prov_count, " neighbors=", node._neighbors.size())
	var caps := 0
	for c in node._capital_of:
		if c >= 0:
			caps += 1
	var thrones := 0
	for t in node._has_throne:
		thrones += int(t)
	print("capitals=", caps, " thrones=", thrones)

	var turns := 0
	var battles := 0
	var guard := 0
	while not node._done and guard < 400:
		guard += 1
		node._on_end_turn()
		turns += 1
		while node._state == "battle":
			battles += 1
			# Fast-forward the overlay review.
			node._advance_review()

	print("turns=", turns, " battles=", battles)
	print("final turn=", node._turn, " outcome=", node._outcome, " done=", node._done)
	if node._done and node._prov_count >= 8 and caps == 2 and node._provinces.size() == node._prov_count:
		print("PASS two_worlds globe headless")
	else:
		push_error("FAIL globe screen did not reach a valid decisive outcome")
	quit()
