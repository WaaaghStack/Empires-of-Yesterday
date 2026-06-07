# SimpleFluidSimulator.gd
# Creeper World style simulator for the v5 "Power Conquest" battles.
# Home bases continuously spawn new power every step. Power flows outward,
# cancels on contact, and gradually fills the map from both ends until one side wins.
#
# Designed to work directly with the v5 schema (grid_cells + home_bases).

class_name SimpleFluidSimulator
extends RefCounted

var battle_zone_id: int = 0
var width: int = 0
var height: int = 0

# In-memory simulation state (fast)
var terrain: PackedByteArray
var elevation: PackedFloat32Array
var power_team1: PackedFloat32Array
var power_team2: PackedFloat32Array
var owner_team: PackedByteArray

# Home bases (emitters)
var home_bases: Array = []   # [{team_id, x, y, spawn_rate, committed_troops}]

var step_count: int = 0

const OWNER_NONE := 0
const OWNER_TEAM1 := 1
const OWNER_TEAM2 := 2


func load_from_state(state: Dictionary) -> void:
	battle_zone_id = state.get("battle_zone_id", 0)
	width = state.get("width", 0)
	height = state.get("height", 0)

	terrain.resize(width * height)
	elevation.resize(width * height)
	power_team1.resize(width * height)
	power_team2.resize(width * height)
	owner_team.resize(width * height)

	var cells: Array = state.get("grid_cells", [])
	for cell in cells:
		var x := int(cell.get("x", 0))
		var y := int(cell.get("y", 0))
		var idx := y * width + x

		terrain[idx] = int(cell.get("terrain_type", 0))
		elevation[idx] = float(cell.get("elevation", 0.0))
		power_team1[idx] = float(cell.get("power_team1", 0.0))
		power_team2[idx] = float(cell.get("power_team2", 0.0))
		owner_team[idx] = int(cell.get("owner_team_id", 0))

	home_bases = state.get("home_bases", [])
	step_count = 0


func save_to_state() -> Dictionary:
	var cells := []
	for y in range(height):
		for x in range(width):
			var idx := y * width + x
			cells.append({
				"x": x,
				"y": y,
				"terrain_type": terrain[idx],
				"elevation": elevation[idx],
				"power_team1": power_team1[idx],
				"power_team2": power_team2[idx],
				"owner_team_id": owner_team[idx]
			})

	return {
		"battle_zone_id": battle_zone_id,
		"width": width,
		"height": height,
		"grid_cells": cells,
		"home_bases": home_bases
	}


func step() -> Array:
	# === True Creeper World Logic ===
	#
	# Home bases spawn new power every single step (the fundamental generator rule).
	# Power radiates outward from the two home bases and fills the map from both ends.
	# When the two powers meet they cancel. Sustained advantage from one base eventually
	# claims territory until one side controls the entire playable area.
	for base in home_bases:
		var team := int(base.get("team_id", 0))
		var bx := int(base.get("pos_x", 0))
		var by := int(base.get("pos_y", 0))
		var base_rate := float(base.get("base_spawn_rate", 10.0))
		var troops := float(base.get("committed_troops", 0))

		# Core Creeper behavior: the home base itself produces fresh power every step.
		# Troops committed to the battle increase the production rate of their base.
		var direct_spawn := base_rate + troops * 0.18

		if bx >= 0 and bx < width and by >= 0 and by < height:
			var idx := by * width + bx
			if team == 1:
				power_team1[idx] += direct_spawn * 2.1   # Strong injection right at the base
			else:
				power_team2[idx] += direct_spawn * 2.1

		# Emit into the immediate area around the home base so power starts flowing outward
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var nx: int = bx + dx
				var ny: int = by + dy
				if nx < 0 or nx >= width or ny < 0 or ny >= height:
					continue
				var nidx: int = ny * width + nx
				var strength := direct_spawn * 0.55
				if team == 1:
					power_team1[nidx] += strength
				else:
					power_team2[nidx] += strength

	# Diffusion — power flows outward from the home bases and fills the map
	var new_p1 := power_team1.duplicate()
	var new_p2 := power_team2.duplicate()

	for y in range(height):
		for x in range(width):
			var idx := y * width + x
			if owner_team[idx] == 0:
				continue

			var p1: float = power_team1[idx]
			var p2: float = power_team2[idx]

			# 8-way diffusion with light downhill preference (power likes to flow to lower ground)
			var sum1: float = p1 * 1.55
			var sum2: float = p2 * 1.55
			var count: float = 1.55

			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or nx >= width or ny < 0 or ny >= height:
						continue
					var nidx: int = ny * width + nx
					if owner_team[nidx] == 0:
						continue

					var flow := 0.20
					if elevation.size() > 0:
						var h_here := elevation[idx]
						var h_neigh := elevation[nidx]
						if h_neigh < h_here - 0.07:
							flow = 0.30   # flows downhill more easily
						elif h_neigh > h_here + 0.14:
							flow = 0.11   # uphill is harder

					sum1 += power_team1[nidx] * flow
					sum2 += power_team2[nidx] * flow
					count += flow

			new_p1[idx] = sum1 / count
			new_p2[idx] = sum2 / count

	power_team1 = new_p1
	power_team2 = new_p2

	# Cancellation + ownership (classic Creeper annihilation)
	var events: Array = []

	for i in range(power_team1.size()):
		var p1: float = power_team1[i]
		var p2: float = power_team2[i]

		if p1 > 0.0 and p2 > 0.0:
			var cancel: float = minf(p1, p2)
			power_team1[i] -= cancel
			power_team2[i] -= cancel

		# Clear dominance flips ownership
		var old_owner: int = owner_team[i]
		if power_team1[i] > power_team2[i] * 1.28 and power_team1[i] > 0.7:
			owner_team[i] = OWNER_TEAM1
		elif power_team2[i] > power_team1[i] * 1.28 and power_team2[i] > 0.7:
			owner_team[i] = OWNER_TEAM2

		if owner_team[i] != old_owner and owner_team[i] != 0:
			events.append({
				"type": "capture",
				"x": i % width,
				"y": i / width,
				"new_owner": owner_team[i]
			})

	step_count += 1
	return events  # so the caller can record them to replay_events


func get_ownership_percentages() -> Dictionary:
	var t1: int = 0
	var t2: int = 0
	var total: int = 0

	for i in range(owner_team.size()):
		if owner_team[i] == OWNER_TEAM1:
			t1 += 1
		elif owner_team[i] == OWNER_TEAM2:
			t2 += 1
		total += 1

	if total == 0:
		return {"team1": 0.0, "team2": 0.0}

	return {
		"team1": float(t1) / float(total),
		"team2": float(t2) / float(total)
	}
