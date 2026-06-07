class_name TurnResolver
extends RefCounted

const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")
const ArmyPoolLib := preload("res://ArmyPool.gd")
const CommanderProfileLib := preload("res://CommanderProfile.gd")
const BuildingDefinitionLib := preload("res://BuildingDefinition.gd")
const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattlePacingLib := preload("res://BattlePacing.gd")
const BattleMapSnapshotLib := preload("res://BattleMapSnapshot.gd")

## End-turn pipeline for commander mode.
##
## Future headless pre-resolve: call `pre_resolve_live_battle(seed, mix, forces)` before the
## player opens BattleViewer, record tile/sector snapshots per 10Hz tick, then replay in-viewer.


static func resolve_turn(
	galaxy,
	army,
	resources,
	profile: Dictionary,
	use_live_battle: bool = false,
) -> Dictionary:
	var result := {
		"battles": [],
		"player_won_battles": 0,
		"income": {},
		"game_over": false,
		"victory": false,
		"message": "",
	}
	if army.total_allocated() > army.total_soldiers:
		result.message = "Over-allocated soldiers."
		return result
	var battles: Array = galaxy.get_contested_battle_nodes(army.allocated_by_node)
	var dmg_mult: float = float(profile.get("damage_mult", 1.0))
	var def_mult: float = float(profile.get("defense_mult", 1.0))
	var casualty_reduction := _building_casualty_reduction(galaxy)
	for node in battles:
		var node_id := str(node.get("id", ""))
		var player_force: int = army.get_allocation(node_id)
		var enemy_force: int = int(node.get("enemy_strength", 100))
		var terrain: String = str(node.get("terrain_tag", "open_field"))
		var battle_outcome: Dictionary
		if use_live_battle:
			battle_outcome = {"deferred": true, "node_id": node_id}
		else:
			battle_outcome = resolve_stub_battle(
				player_force, enemy_force, terrain, dmg_mult, def_mult, casualty_reduction
			)
		battle_outcome["node_id"] = node_id
		battle_outcome["terrain_tag"] = terrain
		battle_outcome["player_force"] = player_force
		result.battles.append(battle_outcome)
		if bool(battle_outcome.get("player_won", false)):
			result.player_won_battles += 1
			galaxy.set_owner(node_id, GalaxyMapStateLib.OWNER_PLAYER)
			node["enemy_strength"] = maxi(40, int(enemy_force * 0.35))
			var win_losses: int = int(battle_outcome.get("player_losses", 0))
			if win_losses > 0:
				army.apply_permanent_losses(win_losses)
		else:
			var lost: int = int(battle_outcome.get("player_losses", 0))
			army.apply_permanent_losses(lost)
	_apply_income(galaxy, resources, profile)
	_enemy_reinforce_turn(galaxy, army)
	galaxy.turn_index += 1
	army.clear_allocations()
	result.income = resources.to_dict()
	result.game_over = army.is_defeated() or galaxy.is_hq_lost()
	result.victory = galaxy.is_galaxy_won()
	if result.victory:
		result.message = "Galaxy secured — enemy core captured."
	elif result.game_over:
		result.message = "Command defeated — army or HQ lost."
	else:
		result.message = "Turn %d resolved — %d/%d battles won." % [
			galaxy.turn_index,
			result.player_won_battles,
			battles.size(),
		]
	return result


## Commander end-turn: tactical pre-resolve each battle; outcomes apply via battle queue UI.
static func resolve_turn_commander(
	galaxy,
	army,
	resources,
	profile: Dictionary,
	run_seed: int = 0,
) -> Dictionary:
	var result := {
		"battle_queue": [],
		"player_won_battles": 0,
		"income": {},
		"game_over": false,
		"victory": false,
		"message": "",
		"needs_battle_queue": false,
	}
	if army.total_allocated() > army.total_soldiers:
		result.message = "Over-allocated soldiers."
		return result
	var battles: Array = galaxy.get_contested_battle_nodes(army.allocated_by_node)
	var queue: Array = []
	for node in battles:
		var node_id := str(node.get("id", ""))
		var player_force: int = army.get_allocation(node_id)
		var entry: Dictionary = preresolve_commander_battle(run_seed, node, player_force, profile, galaxy)
		queue.append(entry)
		if bool(entry.get("player_won", false)):
			result.player_won_battles += 1
	result.battle_queue = queue
	result.needs_battle_queue = queue.size() > 0
	_apply_income(galaxy, resources, profile)
	_enemy_reinforce_turn(galaxy, army)
	galaxy.turn_index += 1
	army.clear_allocations()
	result.income = resources.to_dict()
	if result.needs_battle_queue:
		result.message = "Turn %d — review %d battle(s)." % [galaxy.turn_index, queue.size()]
	else:
		result.game_over = army.is_defeated() or galaxy.is_hq_lost()
		result.victory = galaxy.is_galaxy_won()
		if result.victory:
			result.message = "Galaxy secured — enemy core captured."
		elif result.game_over:
			result.message = "Command defeated — army or HQ lost."
		else:
			result.message = "Turn %d resolved — no battles." % galaxy.turn_index
	return result


static func preresolve_commander_battle(
	run_seed: int,
	node: Dictionary,
	player_force: int,
	profile: Dictionary,
	galaxy = null,
) -> Dictionary:
	var node_id := str(node.get("id", ""))
	var terrain := str(node.get("terrain_tag", "open_field"))
	var mix: Dictionary = node.get("terrain_mix", {})
	var node_type := str(node.get("type", "battle"))
	var enemy_force: int = int(node.get("enemy_strength", 100))
	var seed_val: int = (run_seed + hash(node_id)) & 0x7FFFFFFF
	var battle_map = BattleMapGeneratorLib.generate(
		seed_val, terrain, player_force, enemy_force, node_id, mix, node_type
	)
	return _preresolve_territory_battle_entry(
		battle_map, node_id, terrain, player_force, enemy_force, galaxy, seed_val
	)


static func _preresolve_territory_battle_entry(
	battle_map,
	node_id: String,
	terrain: String,
	player_force: int,
	enemy_force: int,
	galaxy = null,
	map_seed: int = 0,
) -> Dictionary:
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("queue")
	sim.setup(battle_map, player_force, enemy_force, galaxy)
	var tape: BattleTerritoryTapeLib = sim.build_replay_tape(
		BattlePacingLib.RESOLVE_MAX_ROUNDS_CAP,
		BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE,
	)
	tape.battle_data = battle_map
	tape.rebuild_segment_timing()
	var outcome: Dictionary = tape.result
	tape.result = outcome
	var tape_dict: Dictionary = tape.to_dictionary()
	return {
		"node_id": node_id,
		"label": battle_queue_label({"id": node_id}, player_force, enemy_force),
		"terrain_tag": terrain,
		"player_force": player_force,
		"enemy_force": enemy_force,
		"player_won": bool(outcome.get("player_won", false)),
		"player_losses": sim.allocation_losses(player_force, true),
		"enemy_losses": sim.allocation_losses(enemy_force, false),
		"tape": tape,
		"replay_json": JSON.stringify(tape_dict),
		"resolved": false,
		"turns": int(outcome.get("turns", 0)),
		"frame_count": tape.frame_count(),
		"resolve_ms": tape.resolve_ms,
		"resolve_mode": "territory",
		"map_seed": map_seed,
		"claimable_tiles": int(outcome.get("claimable_tiles", 0)),
		"map_snapshot": BattleMapSnapshotLib.to_dict(battle_map),
		"tape_result": outcome,
	}


static func battle_queue_label(node: Dictionary, player_force: int, enemy_force: int) -> String:
	return "%s — %d vs %d" % [str(node.get("id", "?")), player_force, enemy_force]


static func apply_queued_battle_outcome(galaxy, army, entry: Dictionary) -> void:
	if bool(entry.get("resolved", false)):
		return
	apply_battle_result(
		galaxy,
		army,
		str(entry.get("node_id", "")),
		bool(entry.get("player_won", false)),
		int(entry.get("player_losses", 0)),
		int(entry.get("enemy_losses", 0)),
	)
	entry["resolved"] = true


static func finalize_commander_turn_status(galaxy, army, battles_won: int, battles_total: int) -> Dictionary:
	var game_over: bool = army.is_defeated() or galaxy.is_hq_lost()
	var victory: bool = galaxy.is_galaxy_won()
	var message: String
	if victory:
		message = "Galaxy secured — enemy core captured."
	elif game_over:
		message = "Command defeated — army or HQ lost."
	else:
		message = "Turn %d resolved — %d/%d battles won." % [
			galaxy.turn_index,
			battles_won,
			battles_total,
		]
	return {"game_over": game_over, "victory": victory, "message": message}


static func pre_resolve_live_battle(
	seed_value: int,
	terrain_mix: Dictionary,
	player_force: int,
	enemy_force: int,
	node_id: String = "",
	max_turns: int = 120,
	node_type: String = "battle",
) -> Dictionary:
	var battle_map = BattleMapGeneratorLib.generate_quantum(
		seed_value, terrain_mix, player_force, enemy_force, node_id, "mixed", node_type
	)
	if battle_map == null:
		return {"stub": true, "error": "map_failed"}
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true   # TEST: cheap home-base water model
	sim.setup(battle_map, player_force, enemy_force, null)
	var turn_cap: int = max_turns if max_turns > 0 else sim.max_rounds_limit
	var tape: BattleTerritoryTapeLib = sim.build_replay_tape(turn_cap, BattlePacingLib.RESOLVE_TAPE_RECORD_STRIDE)
	var outcome: Dictionary = tape.result
	return {
		"stub": false,
		"seed": seed_value,
		"node_id": node_id,
		"node_type": node_type,
		"max_turns": max_turns,
		"turns": int(outcome.get("turns", 0)),
		"player_won": bool(outcome.get("player_won", false)),
		"player_losses": sim.allocation_losses(player_force, true),
		"enemy_losses": sim.allocation_losses(enemy_force, false),
		"snapshots": [],
		"claimable_tiles": int(outcome.get("claimable_tiles", 0)),
		"resolve_mode": "territory",
		"resolve_ms": tape.resolve_ms,
	}


static func resolve_stub_battle(
	player_force: int,
	enemy_force: int,
	terrain_tag: String,
	damage_mult: float = 1.0,
	defense_mult: float = 1.0,
	casualty_reduction: float = 0.0,
) -> Dictionary:
	var terrain_mod := 1.0
	match terrain_tag:
		"mountain":
			terrain_mod = 0.88
		"urban":
			terrain_mod = 0.92
		"open_field":
			terrain_mod = 1.05
	var effective_player := float(player_force) * damage_mult * terrain_mod
	var effective_enemy := float(enemy_force) * defense_mult
	var ratio := effective_player / maxf(1.0, effective_enemy)
	var player_won := ratio >= 1.0 or (ratio > 0.72 and randf() < ratio * 0.45)
	var player_losses := 0
	if player_won:
		player_losses = int(float(enemy_force) * 0.12 / maxf(defense_mult, 0.5))
		player_losses = int(float(player_losses) * (1.0 - casualty_reduction))
	else:
		player_losses = int(float(player_force) * clampf(0.25 + (1.0 - ratio) * 0.35, 0.2, 0.65))
	var enemy_losses := int(float(enemy_force) * 0.5) if player_won else int(float(enemy_force) * 0.08)
	return {
		"player_won": player_won,
		"player_losses": maxi(0, player_losses),
		"enemy_losses": maxi(0, enemy_losses),
		"ratio": ratio,
	}


static func apply_battle_result(
	galaxy,
	army,
	node_id: String,
	player_won: bool,
	player_losses: int,
	enemy_losses: int,
) -> void:
	if player_losses > 0:
		army.apply_permanent_losses(player_losses)
	var node: Dictionary = galaxy.get_node(node_id)
	if node.is_empty():
		return
	if player_won:
		galaxy.set_owner(node_id, GalaxyMapStateLib.OWNER_PLAYER)
		node["enemy_strength"] = maxi(0, int(node.get("enemy_strength", 0)) - enemy_losses)
	else:
		node["enemy_strength"] = maxi(40, int(node.get("enemy_strength", 0)) - int(enemy_losses * 0.5))


static func _apply_income(
	galaxy,
	resources,
	profile: Dictionary,
) -> void:
	var economy_mult: float = float(profile.get("economy_mult", 1.0))
	resources.manpower += int(8 * economy_mult)
	for node in galaxy.nodes:
		if str(node.get("owner", "")) != GalaxyMapStateLib.OWNER_PLAYER:
			continue
		for building_id in node.get("buildings", []):
			var def: Dictionary = BuildingDefinitionLib.lookup(str(building_id))
			resources.manpower += int(def.get("manpower_per_turn", 0))
			resources.biomass += int(def.get("biomass_per_turn", 0))
			resources.alloys += int(def.get("alloys_per_turn", 0))
			var recruit: int = int(def.get("recruit_per_turn", 0))
			if recruit > 0 and resources.manpower >= 10:
				resources.manpower -= 10
				# Recruit handled via RunState.apply_commander_recruit


static func _enemy_reinforce_turn(galaxy, _army) -> void:
	for node in galaxy.nodes:
		if str(node.get("owner", "")) == GalaxyMapStateLib.OWNER_ENEMY:
			node["enemy_strength"] = int(node.get("enemy_strength", 100)) + 35
		elif str(node.get("owner", "")) == GalaxyMapStateLib.OWNER_NEUTRAL:
			node["enemy_strength"] = int(node.get("enemy_strength", 80)) + 15


static func _building_casualty_reduction(galaxy) -> float:
	var reduction := 0.0
	for node in galaxy.nodes:
		if str(node.get("owner", "")) != GalaxyMapStateLib.OWNER_PLAYER:
			continue
		for building_id in node.get("buildings", []):
			var def: Dictionary = BuildingDefinitionLib.lookup(str(building_id))
			reduction += float(def.get("casualty_reduction", 0.0))
	return clampf(reduction, 0.0, 0.35)
