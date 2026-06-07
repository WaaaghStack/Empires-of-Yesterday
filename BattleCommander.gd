class_name BattleCommander
extends RefCounted

const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")

var id: int = 0
var side: int = 0
var unit_index: int = -1
var alive: bool = true
var queue: Array = []
var queue_step: int = 0
var gems_remaining: int = 0


func _init(cmd_id: int = 0, cmd_side: int = 0, unit_idx: int = -1) -> void:
	id = cmd_id
	side = cmd_side
	unit_index = unit_idx
	queue.resize(BattleOrderTypesLib.COMMANDER_QUEUE_LEN)
	for i in range(queue.size()):
		queue[i] = BattleOrderTypesLib.CommanderStep.WAIT


func current_step() -> int:
	if queue_step >= 0 and queue_step < queue.size():
		return int(queue[queue_step])
	return BattleOrderTypesLib.CommanderStep.WAIT


func advance_queue() -> void:
	queue_step = (queue_step + 1) % maxi(1, queue.size())


var order_queue: Array:
	get:
		return queue
	set(value):
		queue = value
		queue_step = 0
