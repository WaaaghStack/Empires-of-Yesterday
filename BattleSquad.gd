class_name BattleSquad
extends RefCounted

var id: int = 0
var side: int = 0
var unit_indices: Array[int] = []
var order: int = 0
var hold_rounds: int = 0
var morale: float = 15.0
var routed: bool = false
var target_gx: int = -1
var target_gy: int = -1


func _init(squad_id: int = 0, squad_side: int = 0) -> void:
	id = squad_id
	side = squad_side


func living_count(store) -> int:
	var n: int = 0
	for idx in unit_indices:
		if store.is_alive(idx) and not store.is_routed(idx):
			n += 1
	return n
