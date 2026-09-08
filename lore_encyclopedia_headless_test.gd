extends SceneTree

## Headless check for the Lore encyclopedia: JSON parse + scene instantiate.
## Does not run live World Conquest qa_runner.
## godot --headless --path . -s res://lore_encyclopedia_headless_test.gd

func _init() -> void:
	print("=== Lore Encyclopedia Headless ===")
	var f := FileAccess.open("res://data/lore_encyclopedia.json", FileAccess.READ)
	if f == null:
		push_error("FAIL lore_encyclopedia.json missing")
		quit()
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("FAIL lore_encyclopedia.json did not parse to a Dictionary")
		quit()
		return
	var catalogs: Array = data.get("catalogs", [])
	var entries := 0
	var species := 0
	var end_states := 0
	var wins_nonempty := 0
	for c in catalogs:
		var cname := String(c.get("name", ""))
		for e in c.get("entries", []):
			entries += 1
			if String(e.get("win", "")).strip_edges() != "":
				wins_nonempty += 1
			if cname == "Species":
				species += 1
				for key in ["name", "vibe", "origin", "fight", "win", "body"]:
					if String(e.get(key, "")).strip_edges() == "":
						push_error("FAIL species missing field %s on %s" % [key, String(e.get("name", "?"))])
						quit()
						return
				if (e.get("strengths", []) as Array).is_empty() or (e.get("weaknesses", []) as Array).is_empty():
					push_error("FAIL species missing strengths/weaknesses on %s" % String(e.get("name", "?")))
					quit()
					return
			if cname == "End-states":
				end_states += 1
	print("catalogs=", catalogs.size(), " entries=", entries, " species=", species, " end_states=", end_states)

	var menu_src := FileAccess.get_file_as_string("res://MainMenu.gd")
	if not menu_src.contains("_on_lore_pressed") or not menu_src.contains("LoreButton"):
		push_error("FAIL MainMenu.gd missing Lore button hook")
		quit()
		return

	var scene: PackedScene = load("res://Lore.tscn")
	if scene == null:
		push_error("FAIL could not load Lore.tscn")
		quit()
		return
	var node: Control = scene.instantiate()
	get_root().add_child(node)
	if node._entries_flat.is_empty():
		node._ready()
	var flat: int = node._entries_flat.size()
	print("screen entries_flat=", flat)

	if catalogs.size() >= 4 and species >= 6 and end_states >= 6 and entries >= 16 and flat == entries and wins_nonempty >= 12:
		print("PASS lore encyclopedia headless")
	else:
		push_error("FAIL lore encyclopedia content/screen check")
	quit()
