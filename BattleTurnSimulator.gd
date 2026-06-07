class_name BattleTurnSimulator
extends RefCounted
## Deprecated wrapper — delegates to BattleTacticalSim (rout/annihilation only).

const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")
const BattleArmyStateLib := preload("res://BattleArmyState.gd")
const BattleDirectivesLib := preload("res://BattleDirectives.gd")
const BattleMovementEngineLib := preload("res://BattleMovementEngine.gd")

var battle_data = null
var army: BattleArmyStateLib
var directives: BattleDirectivesLib
var movement: BattleMovementEngineLib
var tactical: BattleTacticalSimLib
var turn_index: int = 0
var snapshots: Array = []
var finished: bool = false
var player_won: bool = false
var last_casualties: Dictionary = {"friendly": 0.0, "hostile": 0.0}
var pacing: Dictionary = {}
var turn_seconds: float = 2.4
var substep_seconds: float = 0.8
var max_turns_limit: int = 120


func setup(map_data, player_count: int, enemy_count: int, battle_directives = null) -> void:
	battle_data = map_data
	tactical = BattleTacticalSimLib.new()
	tactical.setup(map_data, player_count, enemy_count, battle_directives)
	army = BattleArmyStateLib.new()
	army.reset_from_allocations(player_count, enemy_count)
	directives = tactical.directives
	movement = tactical.movement
	pacing = tactical.pacing
	turn_seconds = tactical.get_turn_seconds()
	substep_seconds = tactical.get_seconds_per_cell()
	max_turns_limit = tactical.max_rounds_limit
	turn_index = 0
	snapshots.clear()
	finished = false
	player_won = false
	last_casualties = {"friendly": 0.0, "hostile": 0.0}


func get_turn_seconds() -> float:
	return turn_seconds


func get_substep_seconds() -> float:
	return substep_seconds


func get_seconds_per_cell() -> float:
	return tactical.get_seconds_per_cell() if tactical else substep_seconds


func advance_one_turn() -> Dictionary:
	if tactical == null:
		return {}
	var before_f: int = tactical.store.living_friendly_count()
	var before_h: int = tactical.store.living_hostile_count()
	var snap: Dictionary = tactical.advance_round()
	turn_index = int(snap.get("turn", turn_index))
	finished = bool(snap.get("finished", false))
	player_won = bool(snap.get("player_won", false))
	army.sync_from_store(tactical.store)
	last_casualties["friendly"] = float(maxi(0, before_f - tactical.store.living_friendly_count()))
	last_casualties["hostile"] = float(maxi(0, before_h - tactical.store.living_hostile_count()))
	snapshots.append(snap)
	return snap


func run_to_completion(max_turns: int = -1) -> Dictionary:
	if tactical:
		var outcome: Dictionary = tactical.run_to_completion(max_turns)
		finished = bool(outcome.get("finished", false))
		player_won = bool(outcome.get("player_won", false))
		turn_index = int(outcome.get("turns", turn_index))
		army.sync_from_store(tactical.store)
	return get_result()


func get_result() -> Dictionary:
	return {
		"player_won": player_won,
		"finished": finished,
		"turns": turn_index,
		"snapshots": snapshots,
		"friendly_remaining": army.living_friendly() if army else 0,
		"hostile_remaining": army.living_hostile() if army else 0,
	}


func get_hottest_cp_id() -> String:
	return ""
