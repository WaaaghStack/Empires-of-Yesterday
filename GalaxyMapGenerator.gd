class_name GalaxyMapGenerator
extends RefCounted

const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")

const LAYER_COUNT := 5
const TERRAIN_TAGS: Array[String] = ["open_field", "mountain", "urban", "mixed"]


static func generate(run_seed: int):
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var galaxy := GalaxyMapStateLib.new()
	galaxy.nodes.clear()
	galaxy.edges.clear()
	galaxy.turn_index = 0
	galaxy.hq_node_id = "hq"
	galaxy.boss_node_id = "boss"

	galaxy.nodes.append(_make_node("hq", 0, 0, "hq", GalaxyMapStateLib.OWNER_PLAYER, "open_field", 0, rng))
	var prev_ids: Array[String] = ["hq"]
	for layer in range(1, LAYER_COUNT - 1):
		var count := rng.randi_range(2, 3)
		var layer_ids: Array[String] = []
		for col in range(count):
			var node_id := "L%d_%d" % [layer, col]
			var owner := GalaxyMapStateLib.OWNER_NEUTRAL
			if layer == 1:
				owner = GalaxyMapStateLib.OWNER_PLAYER if col == 0 else GalaxyMapStateLib.OWNER_NEUTRAL
			var terrain: String = TERRAIN_TAGS[rng.randi() % TERRAIN_TAGS.size()]
			var enemy_strength: int = rng.randi_range(120, 280) + layer * 80
			var node := _make_node(node_id, layer, col, "battle", owner, terrain, enemy_strength, rng)
			if terrain == "mixed":
				node["terrain_mix"] = _random_terrain_mix(rng)
			galaxy.nodes.append(node)
			layer_ids.append(node_id)
		_wire_layers(prev_ids, layer_ids, rng, galaxy)
		prev_ids = layer_ids

	var boss := _make_node("boss", LAYER_COUNT - 1, 0, "boss", GalaxyMapStateLib.OWNER_ENEMY, "mixed", 900, rng)
	boss["terrain_mix"] = _random_terrain_mix(rng)
	galaxy.nodes.append(boss)
	for parent_id in prev_ids:
		galaxy.edges.append({"from_id": parent_id, "to_id": "boss"})
	return galaxy


static func _make_node(
	node_id: String,
	layer: int,
	column: int,
	node_type: String,
	owner: String,
	terrain_tag: String,
	enemy_strength: int,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var display := node_id.replace("_", " ")
	if node_type == "hq":
		display = "Command HQ"
	elif node_type == "boss":
		display = "Enemy Core"
	return {
		"id": node_id,
		"layer": layer,
		"column": column,
		"type": node_type,
		"display_name": display,
		"owner": owner,
		"terrain_tag": terrain_tag,
		"enemy_strength": enemy_strength,
		"building_slots": 2 if owner == GalaxyMapStateLib.OWNER_PLAYER else 0,
		"buildings": [],
	}


static func _random_terrain_mix(rng: RandomNumberGenerator) -> Dictionary:
	var keys: Array[String] = ["grass", "water", "mountain", "sand", "mud"]
	var weights: Array[float] = []
	var total := 0.0
	for _k in keys:
		var w: float = rng.randf_range(0.05, 1.0)
		weights.append(w)
		total += w
	var mix: Dictionary = {}
	for i in range(keys.size()):
		mix[keys[i]] = weights[i] / total
	return mix


static func _wire_layers(
	prev_ids: Array[String],
	layer_ids: Array[String],
	rng: RandomNumberGenerator,
	galaxy,
) -> void:
	for child_id in layer_ids:
		var parent_id: String = prev_ids[rng.randi() % prev_ids.size()]
		galaxy.edges.append({"from_id": parent_id, "to_id": child_id})
