class_name CampaignGraphGenerator
extends RefCounted

const CampaignGraphDataScript := preload("res://CampaignGraphData.gd")

const LAYER_COUNT := 5
const ELITE_OBJECTIVES: Array[String] = ["hive_purge", "hold_purge"]


static func generate(run_seed: int) -> CampaignGraphData:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var graph: RefCounted = CampaignGraphDataScript.new()
	graph.nodes.clear()
	graph.edges.clear()
	graph.completed_ids.clear()
	graph.pending_mission_node_id = ""

	graph.nodes.append(_make_node("start", 0, 0, "start", "small", "standard", false, rng))
	var prev_ids: Array[String] = ["start"]
	for layer in range(1, LAYER_COUNT - 1):
		var count := rng.randi_range(2, 3)
		var layer_ids: Array[String] = []
		for col in range(count):
			var node_id := "L%d_%d" % [layer, col]
			var node_type := "elite" if layer >= 2 and rng.randf() < 0.38 else "battle"
			var map_tier := "medium" if node_type == "elite" else "small"
			var objective := "standard"
			if node_type == "elite":
				objective = ELITE_OBJECTIVES[rng.randi() % ELITE_OBJECTIVES.size()]
			graph.nodes.append(_make_node(node_id, layer, col, node_type, map_tier, objective, false, rng))
			layer_ids.append(node_id)
		_wire_layers(prev_ids, layer_ids, rng, graph)
		prev_ids = layer_ids

	graph.nodes.append(
		_make_node("boss", LAYER_COUNT - 1, 0, "boss", "large", "hive_purge", true, rng)
	)
	for parent_id in prev_ids:
		graph.edges.append({"from_id": parent_id, "to_id": "boss"})

	graph.current_node_id = "start"
	graph.completed_ids.append("start")
	return graph


static func _make_node(
	node_id: String,
	layer: int,
	column: int,
	node_type: String,
	map_tier: String,
	objective_template: String,
	campaign_boss: bool,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var display_name := "Deploy"
	var description := "Insertion point — advance to the first combat sector."
	match node_type:
		"battle":
			display_name = "Combat Sector"
			description = "Standard hostile sweep. Clear zones and extract."
		"elite":
			display_name = "Elite Nest"
			description = "Heavy resistance and hive signatures. Higher biomass reward."
		"boss":
			display_name = "Overmind Sanctum"
			description = "Finale: purge nest hives, destroy the Overmind, extract all operators."
		_:
			pass
	return {
		"id": node_id,
		"layer": layer,
		"column": column,
		"type": node_type,
		"map_tier": map_tier,
		"objective_template": objective_template,
		"campaign_boss": campaign_boss,
		"display_name": display_name,
		"description": description,
		"draw_pos": Vector2(float(layer) * 220.0, float(column) * 130.0),
	}


static func _wire_layers(from_ids: Array[String], to_ids: Array[String], rng: RandomNumberGenerator, graph: RefCounted) -> void:
	if from_ids.is_empty() or to_ids.is_empty():
		return
	var incoming: Dictionary = {}
	for to_id in to_ids:
		incoming[to_id] = 0
	for from_id in from_ids:
		var targets: Array[String] = []
		var pick_count := mini(2, to_ids.size())
		var pool := to_ids.duplicate()
		pool.shuffle()
		for i in range(pick_count):
			targets.append(pool[i])
		for to_id in targets:
			graph.edges.append({"from_id": from_id, "to_id": to_id})
			incoming[to_id] = int(incoming.get(to_id, 0)) + 1
	for to_id in to_ids:
		if int(incoming.get(to_id, 0)) == 0:
			var parent_id: String = from_ids[rng.randi() % from_ids.size()]
			graph.edges.append({"from_id": parent_id, "to_id": to_id})
