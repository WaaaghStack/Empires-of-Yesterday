class_name TurnResolver
extends RefCounted

const GalaxyMapStateLib := preload("res://GalaxyMapState.gd")
const ArmyPoolLib := preload("res://ArmyPool.gd")
const CommanderProfileLib := preload("res://CommanderProfile.gd")
const BuildingDefinitionLib := preload("res://BuildingDefinition.gd")

## End-turn pipeline for commander mode.


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
