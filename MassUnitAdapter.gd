class_name MassUnitAdapter
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const UnitSimulationManagerLib := preload("res://UnitSimulationManager.gd")


static func living_soldier_nodes_from_store(
	store: UnitSimulationStoreLib,
	node_by_handle: Dictionary,
) -> Array[SoldierUnit]:
	var result: Array[SoldierUnit] = []
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if store.side[i] != UnitSimulationStoreLib.Side.FRIENDLY:
			continue
		var handle: int = store.node_handle[i]
		if handle >= 0 and node_by_handle.has(handle):
			var unit = node_by_handle[handle]
			if unit is SoldierUnit and unit.is_alive:
				result.append(unit)
	return result


static func living_soldiers_for_coordinator(
	store: UnitSimulationStoreLib,
	active_units: Array[SoldierUnit],
	mass_mode: bool,
) -> Array:
	if not mass_mode:
		return active_units
	var result: Array = []
	for unit in active_units:
		if unit is SoldierUnit and unit.is_alive and not unit.is_extracted:
			result.append(unit)
	return result


static func fog_anchor_positions(store: UnitSimulationStoreLib, active_units: Array[SoldierUnit], mass_mode: bool) -> Array[Vector2]:
	var anchors: Array[Vector2] = []
	if mass_mode and store != null:
		var seen_rooms: Dictionary = {}
		for i in range(store.count):
			if not store.is_alive(i):
				continue
			if store.side[i] != UnitSimulationStoreLib.Side.FRIENDLY:
				continue
			var ri: int = store.room_index[i]
			if seen_rooms.has(ri):
				continue
			seen_rooms[ri] = true
			if ri >= 0 and ri < store.room_positions.size():
				anchors.append(store.room_positions[ri])
		return anchors
	for unit in active_units:
		if unit is SoldierUnit and unit.is_alive and not unit.is_extracted:
			anchors.append(unit.position)
	return anchors


static func sync_run_state_from_store(store: UnitSimulationStoreLib) -> void:
	if store == null:
		return
	RunLog.perf(
		"mass_units friendly=%d hostile=%d total=%d"
		% [store.living_friendly_count(), store.living_hostile_count(), store.count]
	)
