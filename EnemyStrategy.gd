class_name EnemyStrategy
extends RefCounted

## Pure decision layer for hostile expansion. Returns prioritized placement intents;
## callers execute via existing placement + builder job queues.
##
## Design lock A13/F1 (intentional): enemy AI places **outposts + land bridges only**.
## No barracks / hangar AI — player-only multi-structure toolkit for now.
##
## B1 pathfind policy (Screen must honor via helpers below):
## - Always try budgeted/capped route first (`prefer_budgeted_route` / allow_astar=false).
## - Full A* only when `route_allow_full_astar` says so (rate-limited, hard expand budget).
## - Never enable hover A* from this module (B9 stays false in Config / Screen hover path).
## - W3: wire `_drain_enemy_ai_queue` to these APIs and REMOVE unbounded allow_astar=true fallback.

const CFG := preload("res://WorldConquestConfig.gd")
const EconomyLib := preload("res://EconomyLib.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")

enum Difficulty { BEGINNER, MEDIUM, EXPERT }

## B1 path quality tiers for AI placement route attempts.
## Screen: map BUDGETED → allow_astar=false; FULL_ASTAR → allow_astar=true (only if allowed).
enum PathTier { BUDGETED = 0, FULL_ASTAR = 1 }

## Local pathfind budgets (not Config — W3 may promote ENEMY_AI_ALLOW_ASTAR / expand knobs later).
## Prefer greedy/capped search; full A* is a rare, hard-budgeted escalation.
const ENEMY_AI_PATHFIND_MAX_EXPAND := 6000
## Full A* may run at most this many times per queued action (after budgeted fails).
const ENEMY_AI_FULL_ASTAR_MAX_ATTEMPTS := 1
## Min seconds an action should age before full A* is considered (0 = same drain cycle OK once).
const ENEMY_AI_FULL_ASTAR_MIN_PLAN_AGE_SEC := 0.0
## When false, Screen must never pass allow_astar=true for AI (budgeted-only mode).
const ENEMY_AI_ALLOW_FULL_ASTAR := true

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## --- B1 public pathfind policy API (Screen / W3) ---------------------------------

## Always prefer capped/greedy pathfind first. B9: does not affect hover (hover stays Config).
static func prefer_budgeted_route() -> bool:
	return true


## Hard expand ceiling for AI placement pathfind. Screen/Rust may pass this when supported;
## until then, allow_astar=false uses Rust CHEAP caps; full A* should not exceed this intent.
static func max_path_expand_for_ai() -> int:
	return ENEMY_AI_PATHFIND_MAX_EXPAND


## Whether a full A* attempt is allowed for this AI action.
## `full_astar_attempts` = how many full-A* tries this action has already made.
## `plan_age_sec` = time since the action was planned (optional throttle).
static func route_allow_full_astar(plan_age_sec: float = 0.0, full_astar_attempts: int = 0) -> bool:
	if not ENEMY_AI_ALLOW_FULL_ASTAR:
		return false
	if full_astar_attempts >= ENEMY_AI_FULL_ASTAR_MAX_ATTEMPTS:
		return false
	if plan_age_sec + 0.0001 < ENEMY_AI_FULL_ASTAR_MIN_PLAN_AGE_SEC:
		return false
	return true


## First attempt is always budgeted; full A* only after budgeted miss + policy allows.
## `path_attempts` = total place attempts for this action (0 = first try).
static func path_tier_for_attempt(
	path_attempts: int = 0, plan_age_sec: float = 0.0, full_astar_attempts: int = 0
) -> int:
	# prefer_budgeted_route: first try never escalates.
	if path_attempts <= 0:
		return PathTier.BUDGETED
	if route_allow_full_astar(plan_age_sec, full_astar_attempts):
		return PathTier.FULL_ASTAR
	# Full A* not allowed — stay budgeted (Screen should defer via should_defer_after_budgeted_miss).
	return PathTier.BUDGETED


## Convenience: allow_astar flag for `debug_place_outpost_at` / `_resolve_placement_for_team`.
static func placement_allow_astar(
	path_attempts: int = 0, plan_age_sec: float = 0.0, full_astar_attempts: int = 0
) -> bool:
	return (
		path_tier_for_attempt(path_attempts, plan_age_sec, full_astar_attempts)
		== PathTier.FULL_ASTAR
	)


## After a budgeted miss: if full A* is not allowed, Screen should defer/skip (not unbounded retry).
static func should_defer_after_budgeted_miss(
	plan_age_sec: float = 0.0, full_astar_attempts: int = 0
) -> bool:
	return not route_allow_full_astar(plan_age_sec, full_astar_attempts)


## Annotate a planned action with pathfind policy fields for the drain queue.
static func decorate_action_path_policy(action: Dictionary) -> Dictionary:
	var out: Dictionary = action.duplicate(true)
	out["prefer_budgeted"] = prefer_budgeted_route()
	out["path_tier"] = PathTier.BUDGETED
	out["path_attempts"] = int(out.get("path_attempts", 0))
	out["full_astar_attempts"] = int(out.get("full_astar_attempts", 0))
	out["max_path_expand"] = max_path_expand_for_ai()
	# A13/F1: never barracks/hangar from AI planner.
	var kind: String = str(out.get("kind", ""))
	if kind != OutpostBuildLib.KIND_SPAWNER and kind != OutpostBuildLib.KIND_CORRIDOR_LINK:
		out["kind"] = OutpostBuildLib.KIND_SPAWNER
	return out


## --- Planner ---------------------------------------------------------------------

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
	if enemy_supply < EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER):
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
			# A13/F1: outposts only (no barracks/hangar intents).
			scored.append(decorate_action_path_policy({
				"kind": OutpostBuildLib.KIND_SPAWNER,
				"target": cand,
				"score": outpost_score,
			}))

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
			# A13/F1: land bridges only as non-outpost structure kind.
			scored.append(decorate_action_path_policy({
				"kind": OutpostBuildLib.KIND_CORRIDOR_LINK,
				"target": cand,
				"score": bridge_score,
			}))

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
	# B1 policy unit checks (no map / pathfind required).
	if not prefer_budgeted_route():
		return {"ok": false, "detail": "prefer_budgeted_route must be true"}
	if max_path_expand_for_ai() <= 0:
		return {"ok": false, "detail": "max_path_expand_for_ai must be > 0"}
	if max_path_expand_for_ai() > CFG.OUTPOST_PATHFIND_MAX_EXPAND:
		return {"ok": false, "detail": "AI expand budget must not exceed OUTPOST_PATHFIND_MAX_EXPAND"}
	if path_tier_for_attempt(0) != PathTier.BUDGETED:
		return {"ok": false, "detail": "first path attempt must be BUDGETED"}
	if placement_allow_astar(0, 0.0, 0):
		return {"ok": false, "detail": "first attempt must not allow full A*"}
	if ENEMY_AI_ALLOW_FULL_ASTAR:
		if not route_allow_full_astar(0.0, 0):
			return {"ok": false, "detail": "full A* should be allowed once when enabled"}
		if route_allow_full_astar(0.0, ENEMY_AI_FULL_ASTAR_MAX_ATTEMPTS):
			return {"ok": false, "detail": "full A* must stop after ENEMY_AI_FULL_ASTAR_MAX_ATTEMPTS"}
		if path_tier_for_attempt(1, 0.0, 0) != PathTier.FULL_ASTAR:
			return {"ok": false, "detail": "second attempt should escalate to FULL_ASTAR when allowed"}
		if not should_defer_after_budgeted_miss(0.0, ENEMY_AI_FULL_ASTAR_MAX_ATTEMPTS):
			return {"ok": false, "detail": "should defer when full A* attempts exhausted"}
	# B9: this module must never imply hover A* (policy is placement-only).
	if CFG.OUTPOST_HOVER_ALLOW_ASTAR:
		# Config owns hover; we only assert we do not flip it here. Soft note in detail if true.
		pass

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
		var kind: String = str(a.get("kind", ""))
		if kind == "":
			return {"ok": false, "detail": "action missing kind"}
		# A13/F1: outposts + bridges only.
		if kind != OutpostBuildLib.KIND_SPAWNER and kind != OutpostBuildLib.KIND_CORRIDOR_LINK:
			return {"ok": false, "detail": "A13/F1 violated: kind=%s" % kind}
		var tgt: Vector2i = a.get("target", Vector2i(-1, -1))
		if tgt.x < 0:
			return {"ok": false, "detail": "action missing target"}
		if not bool(a.get("prefer_budgeted", false)):
			return {"ok": false, "detail": "action missing prefer_budgeted policy"}
		if int(a.get("path_tier", -1)) != PathTier.BUDGETED:
			return {"ok": false, "detail": "planned actions must start at BUDGETED path tier"}
		if int(a.get("max_path_expand", 0)) != max_path_expand_for_ai():
			return {"ok": false, "detail": "action max_path_expand mismatch"}
	return {
		"ok": true,
		"detail": "actions=%d expand_cap=%d" % [actions.size(), max_path_expand_for_ai()],
	}
