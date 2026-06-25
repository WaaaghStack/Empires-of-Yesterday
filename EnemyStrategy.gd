class_name EnemyStrategy
extends RefCounted

## Pure decision layer for hostile expansion. Returns prioritized placement intents;
## callers execute via existing placement + builder job queues.

const CFG := preload("res://WorldConquestConfig.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")

enum Difficulty { BEGINNER, MEDIUM, EXPERT }

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func plan_actions(snapshot: Dictionary) -> Array[Dictionary]:
	var map_data = snapshot.get("map_data")
	if map_data == null:
		return []
	var difficulty: int = int(snapshot.get("difficulty", Difficulty.MEDIUM))
	var enemy_home: Vector2i = snapshot.get("enemy_home", Vector2i(-1, -1))
	var player_home: Vector2i = snapshot.get("player_home", Vector2i(-1, -1))
	if enemy_home.x < 0 or player_home.x < 0:
		return []
	var structures: Array = snapshot.get("structures", [])
	var owners: PackedByteArray = snapshot.get("owners", PackedByteArray())
	if owners.is_empty():
		return []
	var enemy_supply: float = float(snapshot.get("enemy_supply", 0.0))
	if enemy_supply < float(CFG.SPAWNER_COST_SUPPLY):
		return []
	var connecting: int = int(snapshot.get("connecting_hostile", 0))
	if connecting >= CFG.ENEMY_AI_MAX_CONCURRENT_BUILDS:
		return []

	var team: int = BattleTileControlLib.OWNER_HOSTILE
	var sources: Array[Vector2i] = OutpostBuildLib.operational_sources(
		structures, enemy_home, map_data, team
	)
	if sources.is_empty():
		return []

	var vision: int = _vision_radius(difficulty)
	var stride: int = CFG.ENEMY_AI_FRONTIER_SAMPLE_STRIDE
	var max_candidates: int = CFG.ENEMY_AI_MAX_CANDIDATES
	var candidates: Array[Vector2i] = _collect_candidates(
		map_data,
		owners,
		sources,
		enemy_home,
		player_home,
		vision,
		stride,
		max_candidates,
		difficulty,
	)
	if candidates.is_empty():
		return []

	var scored: Array[Dictionary] = []
	var bridge_budget: int = _max_bridge_checks(difficulty)
	var bridge_checks: int = 0
	var bridge_chance: float = _bridge_chance(difficulty)

	for cand: Vector2i in candidates:
		var outpost_score: float = _score_outpost_cell(
			map_data, owners, cand, enemy_home, player_home, structures, difficulty
		)
		if outpost_score > 0.0:
			scored.append({
				"kind": OutpostBuildLib.KIND_SPAWNER,
				"target": cand,
				"score": outpost_score,
			})

		if bridge_checks >= bridge_budget:
			continue
		if not OutpostBuildLib.is_coastal_cell(map_data, cand.x, cand.y):
			continue
		if not OutpostBuildLib.needs_bridge_route(map_data, cand, sources, team):
			continue
		bridge_checks += 1
		var bridge_score: float = _score_bridge_cell(
			map_data, owners, cand, player_home, difficulty
		) * bridge_chance
		if bridge_score > 0.0:
			scored.append({
				"kind": OutpostBuildLib.KIND_CORRIDOR_LINK,
				"target": cand,
				"score": bridge_score,
			})

	if scored.is_empty():
		return []

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var max_actions: int = mini(CFG.ENEMY_AI_MAX_ACTIONS_PER_PLAN, scored.size())
	var out: Array[Dictionary] = []
	for i in range(max_actions):
		out.append(scored[i])
	return out


static func _collect_candidates(
	map_data,
	owners: PackedByteArray,
	sources: Array[Vector2i],
	enemy_home: Vector2i,
	player_home: Vector2i,
	vision: int,
	stride: int,
	max_count: int,
	difficulty: int,
) -> Array[Vector2i]:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	var toward: Vector2i = _norm_dir(player_home - enemy_home)

	for src: Vector2i in sources:
		if out.size() >= max_count:
			break
		var perp := Vector2i(-toward.y, toward.x)
		for dist in range(stride, vision + 1, stride):
			if out.size() >= max_count:
				break
			var base: Vector2i = src + toward * dist
			for lateral: int in [-2, 0, 2]:
				var cand: Vector2i = base + perp * lateral * stride
				if cand.x < 0 or cand.y < 0 or cand.x >= w or cand.y >= h:
					continue
				var key: String = "%d,%d" % [cand.x, cand.y]
				if seen.has(key):
					continue
				seen[key] = true
				if not map_data.is_land_cell(cand.x, cand.y):
					continue
				var idx: int = map_data.cell_index(cand.x, cand.y)
				if idx < 0 or idx >= owners.size():
					continue
				var owner: int = int(owners[idx])
				if owner == BattleTileControlLib.OWNER_FRIENDLY:
					continue
				out.append(cand)

	if out.is_empty() and difficulty == Difficulty.BEGINNER:
		# Beginner: small jitter around home when no frontier found yet.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(map_data.map_seed) ^ 0xEAEA
		for _i in range(8):
			var gx: int = clampi(
				enemy_home.x + rng.randi_range(-vision, vision), 0, w - 1
			)
			var gy: int = clampi(
				enemy_home.y + rng.randi_range(-vision / 2, vision / 2), 0, h - 1
			)
			if not map_data.is_land_cell(gx, gy):
				continue
			var idx2: int = map_data.cell_index(gx, gy)
			if idx2 < 0 or idx2 >= owners.size():
				continue
			if int(owners[idx2]) == BattleTileControlLib.OWNER_FRIENDLY:
				continue
			out.append(Vector2i(gx, gy))
			if out.size() >= mini(8, max_count):
				break
	return out


static func _score_outpost_cell(
	map_data,
	owners: PackedByteArray,
	cand: Vector2i,
	enemy_home: Vector2i,
	player_home: Vector2i,
	structures: Array,
	difficulty: int,
) -> float:
	var idx: int = map_data.cell_index(cand.x, cand.y)
	if idx < 0 or idx >= owners.size():
		return 0.0
	var owner: int = int(owners[idx])
	if owner == BattleTileControlLib.OWNER_FRIENDLY:
		return 0.0
	if not _spacing_ok(cand, structures):
		return 0.0

	var score: float = 0.0
	if owner == BattleTileControlLib.OWNER_NEUTRAL:
		score += 12.0
	elif owner == BattleTileControlLib.OWNER_HOSTILE:
		score += 4.0

	if _has_owner_neighbor(owners, map_data, cand, BattleTileControlLib.OWNER_HOSTILE):
		score += 14.0
	if _has_owner_neighbor(owners, map_data, cand, BattleTileControlLib.OWNER_FRIENDLY):
		score += 6.0 * _contest_weight(difficulty)

	var dist_player: float = float(cand.distance_to(player_home))
	var dist_enemy: float = float(cand.distance_to(enemy_home))
	score += _advance_weight(difficulty) * maxf(0.0, 48.0 - dist_player * 0.35)
	score -= dist_enemy * 0.08
	return score


static func _score_bridge_cell(
	map_data,
	owners: PackedByteArray,
	cand: Vector2i,
	player_home: Vector2i,
	difficulty: int,
) -> float:
	if not OutpostBuildLib.is_coastal_cell(map_data, cand.x, cand.y):
		return 0.0
	var idx: int = map_data.cell_index(cand.x, cand.y)
	if idx < 0 or idx >= owners.size():
		return 0.0
	if int(owners[idx]) == BattleTileControlLib.OWNER_FRIENDLY:
		return 0.0
	var score: float = 18.0 + _advance_weight(difficulty) * 6.0
	score += maxf(0.0, 40.0 - float(cand.distance_to(player_home)) * 0.25)
	return score


static func _spacing_ok(cand: Vector2i, structures: Array) -> bool:
	var min_d2: int = CFG.MIN_SPAWNER_SPACING_CELLS * CFG.MIN_SPAWNER_SPACING_CELLS
	for st: Dictionary in structures:
		var dx: int = cand.x - int(st.get("gx", 0))
		var dy: int = cand.y - int(st.get("gy", 0))
		if dx * dx + dy * dy < min_d2:
			return false
	return true


static func _has_owner_neighbor(
	owners: PackedByteArray, map_data, cell: Vector2i, want_owner: int
) -> bool:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	for d: Vector2i in _DIRS:
		var nx: int = cell.x + d.x
		var ny: int = cell.y + d.y
		if ny < 0 or ny >= h:
			continue
		if nx < 0:
			nx = w - 1
		elif nx >= w:
			nx = 0
		var idx: int = map_data.cell_index(nx, ny)
		if idx >= 0 and idx < owners.size() and int(owners[idx]) == want_owner:
			return true
	return false


static func _norm_dir(v: Vector2i) -> Vector2i:
	if v == Vector2i.ZERO:
		return Vector2i(1, 0)
	var ax: int = 0 if v.x == 0 else (1 if v.x > 0 else -1)
	var ay: int = 0 if v.y == 0 else (1 if v.y > 0 else -1)
	return Vector2i(ax, ay)


static func _vision_radius(difficulty: int) -> int:
	match difficulty:
		Difficulty.BEGINNER:
			return CFG.ENEMY_AI_VISION_BEGINNER
		Difficulty.EXPERT:
			return CFG.ENEMY_AI_VISION_EXPERT
	return CFG.ENEMY_AI_VISION_MEDIUM


static func _bridge_chance(difficulty: int) -> float:
	match difficulty:
		Difficulty.BEGINNER:
			return CFG.ENEMY_AI_BRIDGE_CHANCE_BEGINNER
		Difficulty.EXPERT:
			return CFG.ENEMY_AI_BRIDGE_CHANCE_EXPERT
	return CFG.ENEMY_AI_BRIDGE_CHANCE_MEDIUM


static func _advance_weight(difficulty: int) -> float:
	match difficulty:
		Difficulty.BEGINNER:
			return 0.35
		Difficulty.EXPERT:
			return 1.25
	return 0.75


static func _contest_weight(difficulty: int) -> float:
	match difficulty:
		Difficulty.BEGINNER:
			return 0.4
		Difficulty.EXPERT:
			return 1.4
	return 0.9


static func _max_bridge_checks(difficulty: int) -> int:
	match difficulty:
		Difficulty.BEGINNER:
			return 2
		Difficulty.EXPERT:
			return 8
	return 4


static func run_selfcheck() -> Dictionary:
	var map_data = EarthMapGeneratorLib.generate(90909)
	OutpostBuildLib.prepare_land_components(map_data)
	var sim := BattleTerritorySimLib.new()
	sim.use_simple_water_model = true
	sim.set_resolve_context("world_conquest")
	sim.setup(map_data, CFG.PLAYER_FORCE, CFG.ENEMY_FORCE, null, {}, true)
	var tc = sim.tile_control
	var snap: Dictionary = {
		"map_data": map_data,
		"structures": map_data.placed_structures,
		"owners": tc.owners if tc != null else PackedByteArray(),
		"enemy_home": map_data.enemy_home_grid,
		"player_home": map_data.player_home_grid,
		"friendly_tiles": tc.friendly_tiles if tc != null else 0,
		"hostile_tiles": tc.hostile_tiles if tc != null else 0,
		"claimable_tiles": sim.claimable_tiles,
		"enemy_supply": float(CFG.STARTING_SUPPLY),
		"difficulty": Difficulty.MEDIUM,
		"connecting_hostile": 0,
	}
	var actions: Array[Dictionary] = plan_actions(snap)
	if actions.is_empty():
		return {"ok": false, "detail": "plan_actions returned empty on medium snapshot"}
	for a: Dictionary in actions:
		if str(a.get("kind", "")) == "":
			return {"ok": false, "detail": "action missing kind"}
		var tgt: Vector2i = a.get("target", Vector2i(-1, -1))
		if tgt.x < 0:
			return {"ok": false, "detail": "action missing target"}
	return {"ok": true, "detail": "actions=%d" % actions.size()}
