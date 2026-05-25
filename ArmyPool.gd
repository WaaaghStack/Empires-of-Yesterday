class_name ArmyPool
extends RefCounted

const MIN_ARMY_TO_CONTINUE := 80

var total_soldiers: int = 0
var available_soldiers: int = 0
var allocated_by_node: Dictionary = {}
var reserve_soldiers: int = 0
var total_lost_this_run: int = 0


func reset(starting_total: int) -> void:
	total_soldiers = maxi(0, starting_total)
	available_soldiers = total_soldiers
	allocated_by_node.clear()
	reserve_soldiers = 0
	total_lost_this_run = 0


func total_allocated() -> int:
	var sum := 0
	for node_id in allocated_by_node.keys():
		sum += int(allocated_by_node[node_id])
	return sum


func get_allocation(node_id: String) -> int:
	return int(allocated_by_node.get(node_id, 0))


func set_allocation(node_id: String, count: int) -> bool:
	var clamped: int = maxi(0, count)
	var old: int = get_allocation(node_id)
	var delta: int = clamped - old
	if delta > available_soldiers:
		return false
	allocated_by_node[node_id] = clamped
	available_soldiers -= delta
	return true


func clear_allocations() -> void:
	for node_id in allocated_by_node.keys():
		available_soldiers += int(allocated_by_node[node_id])
	allocated_by_node.clear()


func apply_permanent_losses(losses: int) -> void:
	if losses <= 0:
		return
	var actual: int = mini(losses, total_soldiers)
	total_soldiers = maxi(0, total_soldiers - actual)
	available_soldiers = mini(available_soldiers, total_soldiers)
	total_lost_this_run += actual
	_trim_allocations_to_available()


func recruit(count: int) -> void:
	if count <= 0:
		return
	total_soldiers += count
	available_soldiers += count


func is_defeated() -> bool:
	return total_soldiers < MIN_ARMY_TO_CONTINUE


func to_dict() -> Dictionary:
	return {
		"total_soldiers": total_soldiers,
		"available_soldiers": available_soldiers,
		"allocated_by_node": allocated_by_node.duplicate(),
		"reserve_soldiers": reserve_soldiers,
		"total_lost_this_run": total_lost_this_run,
	}


func from_dict(data: Dictionary) -> void:
	total_soldiers = int(data.get("total_soldiers", 0))
	available_soldiers = int(data.get("available_soldiers", 0))
	allocated_by_node = data.get("allocated_by_node", {}).duplicate()
	reserve_soldiers = int(data.get("reserve_soldiers", 0))
	total_lost_this_run = int(data.get("total_lost_this_run", 0))


func _trim_allocations_to_available() -> void:
	while total_allocated() > available_soldiers:
		for node_id in allocated_by_node.keys():
			if allocated_by_node[node_id] > 0:
				allocated_by_node[node_id] = int(allocated_by_node[node_id]) - 1
				if total_allocated() <= available_soldiers:
					break
