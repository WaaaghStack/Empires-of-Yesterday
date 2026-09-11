extends SceneTree

## Headless check for the Data Dictionary screen: loads the catalog JSON + scene, instantiates it,
## and verifies catalogs/tables/columns populated with no parse errors.
## godot --headless --path . -s res://data_dictionary_headless_test.gd

func _init() -> void:
	print("=== Data Dictionary Headless ===")
	# 1. JSON parses and has content.
	var f := FileAccess.open("res://data/data_dictionary.json", FileAccess.READ)
	if f == null:
		push_error("FAIL data_dictionary.json missing")
		quit()
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("FAIL data_dictionary.json did not parse to a Dictionary")
		quit()
		return
	var catalogs: Array = data.get("catalogs", [])
	var tables := 0
	var columns := 0
	for c in catalogs:
		for t in c.get("tables", []):
			tables += 1
			columns += (t.get("columns", []) as Array).size()
	print("catalogs=", catalogs.size(), " tables=", tables, " columns=", columns)

	# 2. Scene + script load and instantiate without errors.
	var scene: PackedScene = load("res://DataDictionary.tscn")
	if scene == null:
		push_error("FAIL could not load DataDictionary.tscn")
		quit()
		return
	var node: Control = scene.instantiate()
	get_root().add_child(node)
	# In a SceneTree script the node lifecycle has not ticked, so run _ready explicitly.
	if node._tables_flat.is_empty():
		node._ready()
	var flat: int = node._tables_flat.size()
	print("screen tables_flat=", flat)

	if catalogs.size() >= 4 and tables >= 10 and columns >= 40 and flat == tables:
		print("PASS data dictionary headless")
	else:
		push_error("FAIL data dictionary content/screen check")
	quit()
