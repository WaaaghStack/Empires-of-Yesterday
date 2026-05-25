class_name MassBattleSpawner
extends RefCounted

const UnitSimulationManagerLib := preload("res://UnitSimulationManager.gd")

## Wave spawner for battle-map stress missions.


static func apply_mission_config(
	manager: UnitSimulationManagerLib,
	map_data,
	rooms: Array,
	rng: RandomNumberGenerator,
) -> void:
	if map_data == null or not map_data.mass_unit_mode:
		return
	var room_indices: Array[int] = []
	for i in range(rooms.size()):
		var room: Room = rooms[i]
		if room and room.is_spawn_eligible:
			room_indices.append(i)
	if room_indices.is_empty():
		for i in range(rooms.size()):
			room_indices.append(i)
	var friendlies: int = int(map_data.initial_friendlies)
	var hostiles: int = int(map_data.initial_hostiles)
	if friendlies <= 0 and hostiles <= 0 and map_data.battle_map_preset:
		friendlies = 4000
		hostiles = 6000
	var active_cap: int = int(map_data.active_lite_cap)
	friendlies = mini(friendlies, int(map_data.max_units))
	hostiles = mini(hostiles, int(map_data.max_units) - friendlies)
	if active_cap > 0:
		var total_spawn := friendlies + hostiles
		if total_spawn > active_cap:
			var ratio := float(active_cap) / float(total_spawn)
			friendlies = int(float(friendlies) * ratio)
			hostiles = active_cap - friendlies
	manager.spawn_horde(friendlies, hostiles, room_indices, rng)
	RunLog.info(
		"Mass battle spawn: %d friendly, %d hostile (cap %d)"
		% [friendlies, hostiles, map_data.max_units]
	)
