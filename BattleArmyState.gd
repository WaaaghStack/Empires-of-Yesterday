class_name BattleArmyState
extends RefCounted
## Legacy shim: army strength is living units in UnitSimulationStore (no power pools).

var friendly_spawned: int = 0
var hostile_spawned: int = 0


func reset_from_allocations(player_count: int, enemy_count: int) -> void:
	friendly_spawned = maxi(1, player_count)
	hostile_spawned = maxi(1, enemy_count)


func living_friendly() -> int:
	return friendly_spawned


func living_hostile() -> int:
	return hostile_spawned


func sync_from_store(store) -> void:
	if store == null:
		return
	friendly_spawned = store.living_friendly_count()
	hostile_spawned = store.living_hostile_count()
