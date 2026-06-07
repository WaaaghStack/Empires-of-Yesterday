class_name UnitSimulationManager
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const PathRequestQueueLib := preload("res://PathRequestQueue.gd")
const RoomCombatResolverLib := preload("res://RoomCombatResolver.gd")
const OrderTypeLib := preload("res://OrderType.gd")

const MOVE_TICK_HZ := 20.0
const ORDER_TICK_HZ := 10.0
const TIER_TICK_HZ := 5.0
const FULL_TIER_CAP_DEFAULT := 300
const PROMOTE_RADIUS_BASE := 960.0

var store: UnitSimulationStore
var path_queue: PathRequestQueue
var room_combat: RoomCombatResolver

var _move_accum: float = 0.0
var _order_accum: float = 0.0
var _tier_accum: float = 0.0
var _move_bucket: int = 0
var _full_tier_cap: int = FULL_TIER_CAP_DEFAULT
var _rooms: Array = []
var _path_graph: DynamicPathGraph = null
var _squad_target_rooms: Dictionary = {}
var use_room_combat: bool = true


func _init() -> void:
	store = UnitSimulationStore.new()
	path_queue = PathRequestQueue.new()
	room_combat = RoomCombatResolver.new()


func reset() -> void:
	store.reset()
	path_queue.reset()
	room_combat.reset()
	_move_accum = 0.0
	_order_accum = 0.0
	_tier_accum = 0.0
	_move_bucket = 0
	_rooms.clear()
	_path_graph = null
	_squad_target_rooms.clear()


func setup(rooms: Array, graph: DynamicPathGraph, full_tier_cap: int = FULL_TIER_CAP_DEFAULT) -> void:
	_rooms = rooms
	_path_graph = graph
	_full_tier_cap = maxi(24, full_tier_cap)
	store.bind_rooms(rooms)


func sync_nodes_from_handles(node_map: Dictionary) -> void:
	for i in range(store.count):
		var handle: int = store.node_handle[i]
		if handle < 0 or not node_map.has(handle):
			continue
		var unit = node_map[handle]
		if unit is SoldierUnit:
			sync_store_from_node(unit, i)


func tick(delta: float, camera_pos: Vector2, zoom: float) -> void:
	if store.count == 0:
		return
	_move_accum += delta
	var move_step := 1.0 / MOVE_TICK_HZ
	while _move_accum >= move_step:
		_move_accum -= move_step
		store.tick_movement_stub(_move_bucket, move_step)
		_tick_lite_pathing(_move_bucket, move_step)
		_move_bucket = (_move_bucket + 1) % UnitSimulationStoreLib.SIM_BUCKETS
	_order_accum += delta
	if _order_accum >= 1.0 / ORDER_TICK_HZ:
		_order_accum = 0.0
		_tick_squad_orders()
	if use_room_combat:
		room_combat.tick_combat(store, _rooms, delta)
	_tier_accum += delta
	if _tier_accum >= 1.0 / TIER_TICK_HZ:
		_tier_accum = 0.0
		update_tiers(camera_pos, zoom)


func update_tiers(camera_pos: Vector2, zoom: float) -> void:
	var promote_r := PROMOTE_RADIUS_BASE / maxf(zoom, 0.15)
	var full_count := 0
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if store.tier[i] == UnitSimulationStoreLib.Tier.FULL:
			full_count += 1
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		var dist := store.positions[i].distance_to(camera_pos)
		var current_tier: int = store.tier[i]
		if store.node_handle[i] >= 0:
			store.tier[i] = UnitSimulationStoreLib.Tier.FULL
			continue
		if dist <= promote_r and full_count < _full_tier_cap:
			if current_tier < UnitSimulationStoreLib.Tier.LITE:
				store.tier[i] = UnitSimulationStoreLib.Tier.LITE
			if dist <= promote_r * 0.55 and full_count < _full_tier_cap:
				store.tier[i] = UnitSimulationStoreLib.Tier.LITE
		elif dist > promote_r * 1.35:
			if current_tier == UnitSimulationStoreLib.Tier.LITE:
				store.tier[i] = UnitSimulationStoreLib.Tier.SIM_ONLY
			elif dist > promote_r * 2.5:
				store.tier[i] = UnitSimulationStoreLib.Tier.DORMANT


func set_squad_target_room(squad_key: String, room_idx: int) -> void:
	_squad_target_rooms[squad_key] = room_idx
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if store.side[i] != UnitSimulationStoreLib.Side.FRIENDLY:
			continue
		if _squad_index_for_id(squad_key, store.squad_id[i]):
			store.target_room_index[i] = room_idx


func register_node_handle(store_index: int, handle: int) -> void:
	if store_index >= 0 and store_index < store.count:
		store.node_handle[store_index] = handle
		store.tier[store_index] = UnitSimulationStoreLib.Tier.FULL


func sync_node_from_store(store_index: int, unit: SoldierUnit) -> void:
	if store_index < 0 or store_index >= store.count or unit == null:
		return
	unit.position = store.positions[store_index]
	unit.current_health = int(store.health[store_index])
	unit.is_alive = store.is_alive(store_index)


func sync_store_from_node(unit: SoldierUnit, store_index: int) -> void:
	if store_index < 0 or store_index >= store.count or unit == null:
		return
	store.positions[store_index] = unit.position
	store.health[store_index] = float(unit.current_health)
	if not unit.is_alive:
		store.kill_unit(store_index)


func spawn_horde(
	friendly_count: int,
	hostile_count: int,
	room_indices: Array[int],
	rng: RandomNumberGenerator,
) -> void:
	if room_indices.is_empty():
		return
	for _f in range(friendly_count):
		var ri: int = room_indices[rng.randi() % room_indices.size()]
		var pos := _spawn_pos_in_room(ri)
		store.spawn_unit(
			UnitSimulationStoreLib.Side.FRIENDLY,
			pos,
			100.0,
			100.0,
			ri,
			rng.randi() % 4,
			UnitSimulationStoreLib.Tier.LITE,
		)
	for _h in range(hostile_count):
		var ri_h: int = room_indices[rng.randi() % room_indices.size()]
		var pos_h := _spawn_pos_in_room(ri_h)
		store.spawn_unit(
			UnitSimulationStoreLib.Side.HOSTILE,
			pos_h,
			50.0,
			50.0,
			ri_h,
			0,
			UnitSimulationStoreLib.Tier.LITE,
			80.0,
			1,
		)


func get_full_tier_soldier_nodes() -> Array[SoldierUnit]:
	var result: Array[SoldierUnit] = []
	return result


func _tick_squad_orders() -> void:
	for squad_key in _squad_target_rooms.keys():
		set_squad_target_room(str(squad_key), int(_squad_target_rooms[squad_key]))


func _tick_lite_pathing(bucket: int, _dt: float) -> void:
	if _path_graph == null:
		return
	for i in range(store.count):
		if store.sim_bucket[i] != bucket:
			continue
		if not store.is_alive(i):
			continue
		if store.tier[i] == UnitSimulationStoreLib.Tier.DORMANT:
			continue
		if store.tier[i] == UnitSimulationStoreLib.Tier.FULL:
			continue
		var room_idx := store.room_index[i]
		var target_idx := store.target_room_index[i]
		if room_idx == target_idx:
			continue
		if room_idx < 0 or target_idx < 0:
			continue
		if room_idx >= store.room_ids.size() or target_idx >= store.room_ids.size():
			continue
		var from_id := store.room_ids[room_idx]
		var to_id := store.room_ids[target_idx]
		var squad_key := "sq_%d" % store.squad_id[i]
		var route: Array[String] = path_queue.get_squad_room_route(_path_graph, squad_key, from_id, to_id)
		for j in range(1, route.size()):
			var node_id := route[j]
			if str(node_id).contains("_door_"):
				continue
			var next_idx := store.room_index_for_id(node_id)
			if next_idx >= 0 and next_idx != room_idx:
				store.target_room_index[i] = next_idx
				break


func _spawn_pos_in_room(room_idx: int) -> Vector2:
	if room_idx >= 0 and room_idx < store.room_positions.size():
		return store.room_positions[room_idx]
	return Vector2.ZERO


func _squad_index_for_id(squad_key: String, squad_index: int) -> bool:
	match squad_key:
		"alpha":
			return squad_index == 0
		"bravo":
			return squad_index == 1
		"charlie":
			return squad_index == 2
		"delta":
			return squad_index == 3
	return str(squad_index) == squad_key
