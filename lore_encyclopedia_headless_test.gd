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
	var roster_units := 0
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
			if cname == "Hearthkin roster":
				var sprite := String(e.get("sprite", "")).strip_edges()
				if sprite == "":
					continue
				roster_units += 1
				if not FileAccess.file_exists(sprite):
					push_error("FAIL roster sprite missing for %s (%s)" % [String(e.get("name", "?")), sprite])
					quit()
					return
				var tex: Texture2D = load(sprite) as Texture2D
				if tex == null:
					push_error("FAIL roster sprite failed to load as texture for %s (%s)" % [String(e.get("name", "?")), sprite])
					quit()
					return
				for key in ["name", "role", "vibe", "fight", "win", "body"]:
					if String(e.get(key, "")).strip_edges() == "":
						push_error("FAIL roster unit missing field %s on %s" % [key, String(e.get("name", "?"))])
						quit()
						return
				var u = e.get("unit", {})
				if typeof(u) != TYPE_DICTIONARY:
					push_error("FAIL roster unit missing unit card on %s" % String(e.get("name", "?")))
					quit()
					return
				var arms := ["infantry", "assault", "recon", "pioneer", "artillery", "armor", "support", "anti_air", "air", "naval"]
				var ranks := ["screen", "line", "overwatch", "battery", "train", "air", "sea"]
				var sizes := ["person", "gun", "wagon", "aircraft", "vessel"]
				var groups := ["infantry_melee", "infantry_hybrid", "infantry_range", "infantry_skirmish", "infantry_engineer", "anti_air", "artillery", "support", "air"]
				var arm := String(u.get("arm", ""))
				var rank := String(u.get("rank", ""))
				var domain := String(u.get("domain", ""))
				var size_class := String(u.get("size_class", ""))
				var source := String(u.get("stats_source", ""))
				var group := String(u.get("group", ""))
				if arm not in arms or rank not in ranks or size_class not in sizes:
					push_error("FAIL roster unit closed-vocab on %s (arm=%s rank=%s size=%s)" % [String(e.get("name", "?")), arm, rank, size_class])
					quit()
					return
				if group not in groups:
					push_error("FAIL roster unit group on %s (%s)" % [String(e.get("name", "?")), group])
					quit()
					return
				if domain not in ["land", "air", "naval"]:
					push_error("FAIL roster unit domain on %s" % String(e.get("name", "?")))
					quit()
					return
				if source not in ["live", "proposed"]:
					push_error("FAIL roster unit stats_source on %s" % String(e.get("name", "?")))
					quit()
					return
				var stats = u.get("stats", {})
				if typeof(stats) != TYPE_DICTIONARY:
					push_error("FAIL roster unit stats missing on %s" % String(e.get("name", "?")))
					quit()
					return
				for sk in ["hp", "attack", "attack_interval", "reach", "perception", "speed", "cohesion", "vs_air", "blast", "cruise_z"]:
					if not stats.has(sk):
						push_error("FAIL roster unit stat %s missing on %s" % [sk, String(e.get("name", "?"))])
						quit()
						return
				if String(e.get("id", "")) == "hearthline":
					if arm != "infantry" or rank != "line" or group != "infantry_hybrid" or source != "live":
						push_error("FAIL Hearthline groups/source")
						quit()
						return
					if int(stats.get("hp", 0)) != 100 or int(stats.get("reach", 0)) != 70 or int(u.get("regiment_size", 0)) != 100:
						push_error("FAIL Hearthline live stats drifted from KindProfile")
						quit()
						return
					if int(stats.get("attack_interval", 0)) != 3:
						push_error("FAIL Hearthline attack_interval drifted from KindProfile")
						quit()
						return
				if String(e.get("id", "")) == "debt_wings":
					if arm != "air" or rank != "air" or group != "air" or source != "live":
						push_error("FAIL Debt Wings groups/source")
						quit()
						return
					if int(stats.get("hp", 0)) != 540 or int(stats.get("blast", 0)) != 12:
						push_error("FAIL Debt Wings live stats drifted from KindProfile")
						quit()
						return
					if int(stats.get("attack_interval", 0)) != 32:
						push_error("FAIL Debt Wings attack_interval drifted from KindProfile")
						quit()
						return
				if String(e.get("id", "")) == "stovebreakers":
					if arm != "assault" or rank != "line" or group != "infantry_melee" or source != "live":
						push_error("FAIL Stovebreakers groups/source")
						quit()
						return
					if int(stats.get("hp", 0)) != 140 or int(u.get("regiment_size", 0)) != 80:
						push_error("FAIL Stovebreakers live stats drifted from KindProfile")
						quit()
						return
					if int(stats.get("attack_interval", 0)) != 2:
						push_error("FAIL Stovebreakers attack_interval drifted from KindProfile")
						quit()
						return
				if String(e.get("id", "")) == "ledger_pieces":
					if arm != "artillery" or rank != "battery" or group != "artillery" or source != "live":
						push_error("FAIL Ledger Pieces groups/source")
						quit()
						return
					if int(stats.get("perception", 0)) != 160 or int(stats.get("blast", 0)) != 16:
						push_error("FAIL Ledger Pieces live stats drifted from KindProfile")
						quit()
						return
					if int(stats.get("attack_interval", 0)) != 8:
						push_error("FAIL Ledger Pieces attack_interval drifted from KindProfile")
						quit()
						return
				if String(e.get("id", "")) == "rolling_hearths" and (arm != "support" or group != "support"):
					push_error("FAIL Rolling Hearths must be support, not armor")
					quit()
					return
	print("catalogs=", catalogs.size(), " entries=", entries, " species=", species, " end_states=", end_states, " roster_units=", roster_units)

	if roster_units != 8:
		push_error("FAIL expected 8 Hearthkin roster units with sprites, got %d" % roster_units)
		quit()
		return

	var menu_src := FileAccess.get_file_as_string("res://MainMenu.gd")
	if not menu_src.contains("_on_lore_pressed") or not menu_src.contains("LoreButton"):
		push_error("FAIL MainMenu.gd missing Lore button hook")
		quit()
		return

	var lore_src := FileAccess.get_file_as_string("res://Lore.gd")
	if not lore_src.contains("_add_sprite") or not lore_src.contains("Job on the field") or not lore_src.contains("_add_unit_card"):
		push_error("FAIL Lore.gd missing roster sprite/role/unit-card render")
		quit()
		return
	if not lore_src.contains("attack_interval") or not lore_src.contains("infantry_hybrid"):
		push_error("FAIL Lore.gd missing attack_interval / group labels")
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
	var rendered := false
	for row in node._entries_flat:
		var e: Dictionary = row["entry"]
		if String(e.get("id", "")) == "hearthline":
			node._render_detail(row["catalog"], e)
			var saw_grid := false
			for child in node._detail_box.get_children():
				if child is GridContainer:
					saw_grid = true
					break
			if not saw_grid:
				push_error("FAIL Lore screen did not render Hearthline stat grid")
				quit()
				return
			rendered = true
			break
	if not rendered:
		push_error("FAIL could not render Hearthline unit card")
		quit()
		return

	if catalogs.size() >= 5 and species >= 6 and end_states >= 6 and entries >= 24 and flat == entries and wins_nonempty >= 12 and roster_units == 8:
		print("PASS lore encyclopedia headless")
	else:
		push_error("FAIL lore encyclopedia content/screen check")
	quit()
