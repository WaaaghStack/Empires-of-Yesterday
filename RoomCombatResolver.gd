class_name RoomCombatResolver
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

const TICK_INTERVAL := 0.1
const FRIENDLY_DPS_PER_UNIT := 7.5
const HOSTILE_DPS_PER_UNIT := 6.8
const OVERFLOW_FRIENDLY_DPS := 0.9
const OVERFLOW_HOSTILE_DPS := 1.45

var _timer: float = 0.0


func reset() -> void:
	_timer = 0.0


func tick_combat(store: UnitSimulationStoreLib, rooms: Array, delta: float) -> void:
	if store == null or store.count == 0:
		return
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer = 0.0
	var room_count := store.friendly_count_by_room.size()
	for room_idx in range(room_count):
		var friendlies := store.friendly_count_by_room[room_idx]
		var hostiles := store.hostile_count_by_room[room_idx]
		if friendlies <= 0 or hostiles <= 0:
			continue
		if _room_has_full_tier_units(store, room_idx):
			continue
		var exchange: int = mini(friendlies, hostiles)
		var friendly_dps := float(exchange) * FRIENDLY_DPS_PER_UNIT * TICK_INTERVAL
		var hostile_dps := float(exchange) * HOSTILE_DPS_PER_UNIT * TICK_INTERVAL
		var overflow_h: int = maxi(0, hostiles - friendlies)
		var overflow_f: int = maxi(0, friendlies - hostiles)
		hostile_dps += float(overflow_h) * OVERFLOW_HOSTILE_DPS * TICK_INTERVAL
		friendly_dps += float(overflow_f) * OVERFLOW_FRIENDLY_DPS * TICK_INTERVAL
		store.pending_damage_by_room[room_idx] += hostile_dps
		_apply_room_casualties(store, room_idx, UnitSimulationStoreLib.Side.HOSTILE, friendly_dps)
		_apply_room_casualties(store, room_idx, UnitSimulationStoreLib.Side.FRIENDLY, hostile_dps)
		if store.hostile_count_by_room[room_idx] <= 0 and room_idx < rooms.size():
			var room: Room = rooms[room_idx]
			if room and room.requires_clear:
				room.check_cleared_status()


func _room_has_full_tier_units(store: UnitSimulationStoreLib, room_idx: int) -> bool:
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if store.room_index[i] != room_idx:
			continue
		if store.tier[i] == UnitSimulationStoreLib.Tier.FULL:
			return true
	return false


func _apply_room_casualties(store: UnitSimulationStoreLib, room_idx: int, unit_side: int, total_damage: float) -> void:
	if total_damage <= 0.0:
		return
	var victims: Array[int] = store.indices_in_room(room_idx, unit_side)
	if victims.is_empty():
		return
	var per_unit := total_damage / float(victims.size())
	for idx in victims:
		if store.tier[idx] == UnitSimulationStoreLib.Tier.FULL:
			continue
		store.apply_damage(idx, per_unit)
